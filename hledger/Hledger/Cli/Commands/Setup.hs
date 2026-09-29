{-|

Check and show the status of the hledger installation.

-}
{-
Old design notes:

## Goals
- Make getting started with hledger and PTA easier and quicker, to
  (a) make this practical for more people (non techies, busy techies..)
  (b) free up more time and energy for learning and doing PTA and finance

Subgoals:
- Reduce the special knowledge and docs needed after install, to get a standard setup working (especially on windows)
- Help with discovery and setup of advanced quality of life terminal features
- Assist with setting up a first or new journal file
- Deliver relevant install/setup/config expertise more efficiently, freeing up dev and support time

## Design
Why a built in command and not a shell script, haskell script, or docs ?
So it is available and runs reliably anywhere a hledger executable runs, and so it can detect more context-specific advice.
(Optionally use shell or haskell scripts for prototyping, if that's helpful)

## Setup checks
Somewhat ordered.
These deal with the complexities of terminals, the shell, GHC, hledger, and the user's machine, locale, and data.
Initially just informational hints.
Later, add automated or interactive diagnosis and repair attempts,
and semi-persistent state (invalidated at suitable times).
These checks are a necessary evil/stopgap; long term, automate/replace/remove them whenever possible.

-}

-- {-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
-- {-# LANGUAGE NamedFieldPuns #-}
-- {-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}

{-# OPTIONS_GHC -Wno-name-shadowing #-}
{-# OPTIONS_GHC -Wno-unused-top-binds #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE RecordWildCards #-}
-- {-# OPTIONS_GHC -Wno-unused-matches #-}

module Hledger.Cli.Commands.Setup (
  setupmode
 ,setup
)
where

import Control.Concurrent (rtsSupportsBoundThreads)
import Control.Exception
import Control.Monad
-- import Data.ByteString qualified as B
import Data.Char
import Data.Default (def)
import Data.List
import Data.Map qualified as M
import Data.Maybe
import Data.Text qualified as T
import Data.Text.Encoding qualified as T
import Data.Version qualified (showVersion)
import Network.HTTP.Client
import Network.HTTP.Types (statusCode, hLocation)
import Network.HTTP.Req as R
import Safe
import System.Directory
import System.Environment (getEnvironment, lookupEnv)
import System.Exit
import System.FilePath
import System.Info
import System.Process
import Text.Printf (printf)

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Conf
import Hledger.Cli.Version
import System.Console.ANSI (hSupportsANSIColor)
import System.IO (localeEncoding, stdout, hFlush, hIsTerminalDevice)


setupmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Setup.txt")
  []
  [generalflagsgroup3]
  []
  ([], Nothing)


{- | Test and print the status of various aspects of the hledger installation.
May also show extra info and hints on how to fix problems.
The goal is to detect and show as much useful information as possible,
and to complete this task reliably regardless of what we find,
without premature termination or misformatting.

The tests are grouped into setup* routines, so named because they might do more
than just test in future.

This is the second version of setup. If it finds that the currently
running hledger is not the one installed in PATH (by comparing --version output),
it refuses to proceed further until that has been done.
This means it can rely on all the latest features and use the hledger API
within this process, simplifying things greatly.
-}
setup :: CliOpts -> Journal -> IO ()
setup _opts@CliOpts{rawopts_=_rawopts, reportspec_=_rspec} _ignoredj = do
  -- This command is not given a journal and should not use _ignoredj;
  -- instead read it ourselves when we are ready.
  putStrLn "Checking your setup (and contacting hledger.org to find out the current release):"
  -- color <- useColorOnStdout
  -- when color $ 
  --   putStrLn $ "Legend: " <> intercalate ", " [
  --      good    "good"
  --     ,neutral "neutral"
  --     ,warning "unknown"
  --     ,bad     "warning"
  --     ]
  elatestversionnumstr <- getLatestHledgerVersion
  meconf <- setupHledger elatestversionnumstr
  setupTerminal meconf
  setupJournal meconf
  -- putStr "\n"

------------------------------------------------------------------------------

-- Returns Nothing if no config file was found,
-- or Just the read error or config if it was found.
setupHledger :: Either String String -> IO (Maybe (Either String Conf))
setupHledger elatestversionnumstr = do
  pgroup "hledger"

  let
    os'
      | os=="darwin" = "macos"
      | os=="mingw32" = "windows"
      | otherwise = os
  mosversion <- getOSVersion
  let osdesc = os' <> maybe "" (" "<>) mosversion
  pdesc "is running on"
  putStrLn $ "      " <> osdesc <> " on " <> arch

  pdesc "is built with a supported compiler/RTS"
  p (if rtsSupportsBoundThreads then Y else N) $ 
    compilerName <> " " <> Data.Version.showVersion fullCompilerVersion
      <> if rtsSupportsBoundThreads then ", using threaded RTS" else ", RTS does not have threads enabled"

  pdesc "is a native binary for this machine ?"
  case hbinArch binaryinfo of
    Nothing -> p U $ "couldn't detect this binary's architecture"
    Just a | a /= arch -> p N $ "binary is for " <> a <> ", system is " <> arch <> ", may run slowly"
    Just a -> p Y a

  pdesc "is a released version ?"
  if isReleaseVersion $ hbinPackageVersion binaryinfo
  then p Y prognameandversion
  else i N prognameandversion

  pdesc "is up to date ? checking latest..." >> hFlush stdout
  case elatestversionnumstr of
    Left e -> p U ("couldn't read " <> latestHledgerVersionUrlStr <> " " <> e)
    Right latestversionnumstr ->
      case toVersion latestversionnumstr of
        Nothing -> p U "couldn't parse latest version number"
        Just latestversion -> p
          (if hbinPackageVersion binaryinfo >= latestversion then Y else N)
          ("latest is " <> latestversionnumstr <> ", " <> showVersion (hbinPackageVersion binaryinfo) <> " is installed")

  pdesc "is installed in PATH (this version) ?"
  pathexes  <- findExecutables progname
  let
    (failaction, failmsg) =
      -- (exitFailure , "Please install this hledger in PATH then run setup again.")
      (return ()   , " Some of this info may not apply to that hledger version. Continuing anyway..")
  case pathexes of
    [] -> p N failmsg >> failaction
    exe:_ -> do
      eerrout <- tryHledgerArgs [["--version", "--no-conf"], ["--version"]]
      case eerrout of
        Left  err -> p U (progname <> " --version failed: " <> err) >> failaction
        Right out -> do
          case parseHledgerVersion out of
            Left  _ -> p U ("couldn't parse " <> progname <> " --version: " <> rstrip out) >> exitFailure
            Right pathbin -> do
              let pathversion = hbinVersionOutput pathbin
              if pathversion /= prognameandversion
              then p N (chomp $ unlines [
                 ""
                ," A different hledger version was found in PATH: " <> pathversion
                ," at: " <> exe
                ,failmsg
                ]) >> failaction
              else p Y exe

  pdesc "has a system text encoding configured ?"
  let encoding = localeEncoding  -- the initial system encoding
  if map toLower (show encoding) == "ascii"
  then p N (show encoding <> ", please configure an encoding for non-ascii data")
  else p Y (show encoding <> ", data files must use this encoding")

  -- pdesc "can handle UTF-8 text ?"
  -- let
  --   eAcuteUtf8   = B.pack [0xC3, 0xA9]
  --   eAcuteLatin1 = B.pack [0xE9]
  -- case T.decodeUtf8' eAcuteUtf8 of
  --   Left _  -> p N "hledger's docs and examples use UTF-8"
  --   Right t -> p Y (T.unpack t)

  -- pdesc "can report text decoding failures ?"
  -- i U (T.unpack $ T.decodeUtf8 eAcuteLatin1)

  pdesc "has a user config file ?"
  muf <- activeUserConfFile
  mlf <- activeLocalConfFile
  let
    (ok, msg) = case muf of
      Just f  -> (Y, f <> if isJust mlf then " (overridden)" else "")
      Nothing -> (N, "")
  i ok msg

  pdesc "has a local config file ?"
  let
    (ok, msg) = case mlf of
      Just f  -> (Y, f)
      Nothing -> (N, "")
  i ok msg

  if (isJust muf || isJust mlf) then do
    pdesc "the config file is readable ?"
    econf <- getConf def
    case econf of
      Left e -> p N e >> return (Just $ Left e)
      Right (conf, _) -> do
        p Y ""

        -- pdesc "common general options are configured ?"
        -- --infer-costs"
        -- print --explicit --infer-costs"

        return $ Just $ Right conf
  else
    return Nothing

------------------------------------------------------------------------------

setupTerminal meconf = do
  pgroup "terminal"
  let
    -- Find the last opt/arg matched by a predicate in the general config, if there is one.
    conflookup predicate = case meconf of
      Just (Right conf) -> find predicate $ reverse $ confLookup "general" conf
      _ -> Nothing

  pdesc "the TERM variable is defined ?"
  mterm <- lookupEnv "TERM"
  let dumbterminal = (map toLower <$> mterm) == Just "dumb"
  case mterm of
    Nothing -> i N "terminal type is unknown"
    Just v  -> i Y $ v <> if dumbterminal then " (color and styles will not be used)" else ""

  pdesc "the terminal supports ANSI color ?"
  isterminal <- hIsTerminalDevice stdout
  supportscolor <- hSupportsANSIColor stdout
  truecolor <- supportsTrueColor
  if not supportscolor then i N $ if isterminal then "" else "stdout is not a terminal"
  else i Y $ if
    | truecolor -> "24-bit color (COLORTERM is set)"
    | "256color" `isInfixOf` fromMaybe "" mterm -> "256 colors"
    | otherwise -> "16 colors"

  pdesc "the NO_COLOR variable is defined ?"
  mnocolor <- lookupEnv "NO_COLOR"
  case mnocolor of
    Nothing -> i N ""
    Just _  -> i Y ""

  meconfigcolor <- do
    pdesc "--color is configured by config file ?"
    let mcolorarg = conflookup (\a -> any (`isPrefixOf` a) ["--color", "--colour"])
    case mcolorarg of
      Nothing -> i N "" >> return Nothing
      Just a  -> do
        i Y a
        let
          arg = reverse $ takeWhile (`notElem` ['=',' ']) $ reverse a
        return $ Just $ parseYNA arg

  -- Use the same logic as the rest of hledger, and explain a negative result.
  -- (The config file is not applied to setup itself, so its --color is checked here.)
  pdesc "hledger will use color by default ?"
  usecolor <- case meconfigcolor of
    Just (Right Yes) -> return True
    Just (Right No)  -> return False
    _                -> useColorOnStdout
  coloropt <- colorOption
  if usecolor then p Y ""
  else i N $ if
    | meconfigcolor == Just (Right No) -> "disabled by config file"
    | coloropt == No                   -> "disabled by --color"
    | isJust mnocolor                  -> "disabled by NO_COLOR"
    | dumbterminal                     -> "disabled by TERM=dumb"
    | not isterminal                   -> "stdout is not a terminal"
    | not supportscolor                -> "the terminal does not support ANSI color"
    | otherwise                        -> ""

  pdesc "the PAGER variable is defined ?"
  mv <- lookupEnv "PAGER"
  case mv of
    Nothing -> i N ""
    Just v  -> i Y v

  pdesc "--pager is configured by config file ?"
  let mpagerarg = conflookup ("--pager" `isPrefixOf`)
  meconfpager <- case mpagerarg of
    Nothing -> i N "" >> return Nothing
    Just a  -> do
      i Y a
      let arg = reverse $ takeWhile (`notElem` ['=',' ']) $ reverse a
      return $ Just $ parseYNA arg

  pdesc "hledger will use a pager when needed ?"
  mpager <- findPager
  case mpager of
    Nothing    -> i N "no pager was found"
    Just pager ->
      case meconfpager of
        Just (Right No) -> i N "disabled in config file"
        _ -> do
          p Y pager

          when (map toLower (takeBaseName pager) == "more") $ do
            pdesc "the MORE variable is defined ?"
            mv <- lookupEnv "MORE"
            case mv of
              Nothing -> i N ""
              Just v  -> i Y v

          when (map toLower (takeBaseName pager) == "less") $ do
            mHLEDGER_LESS <- lookupEnv "HLEDGER_LESS"
            mLESS <- lookupEnv "LESS"

            pdesc "the LESS variable is defined ?"
            case mLESS of
              Nothing -> i N ""
              Just v  -> i Y $ v <> if isJust mHLEDGER_LESS then " (overridden)" else ""

            pdesc "the HLEDGER_LESS variable is defined ?"
            case mHLEDGER_LESS of
              Nothing -> i N ""
              Just v  -> i Y v

            when (isNothing mHLEDGER_LESS) $ do
              pdesc "adjusting LESS var for consistent UX ?"
              usecolor <- useColorOnStdout
              i Y $ lessVarValue mHLEDGER_LESS mLESS usecolor

            pdesc "less is working, with these options ?"
            usecolor <- useColorOnStdout
            let newlessvar = lessVarValue mHLEDGER_LESS mLESS usecolor
            env <- getEnvironment
            let customEnv = ("LESS", newlessvar) : filter ((/= "LESS") . fst) env
            lessHasError <- lessIsWorking (Just customEnv)
            if lessHasError
              then p N "less --version shows a problem, check LESS/HLEDGER_LESS settings"
              else p Y ""

  pdesc "box-drawing chars are used by default ?"
  if isJust $ conflookup ("--pretty"==)
  then p Y ""
  else i N "you can add --pretty to enable them"

  -- pdesc "bash shell completions are installed ?" >> p U ""
  -- pdesc "zsh shell completions are installed ?" >> p U ""

------------------------------------------------------------------------------

setupJournal meconf = do
  pgroup "journal"
  let
    -- Find the last opt/arg matched by a predicate in the general config, if there is one.
    conflookup predicate = case meconf of
      Just (Right conf) -> find predicate $ reverse $ confLookup "general" conf
      _ -> Nothing

  -- pdesc "a home directory journal file exists ?"
  -- mh <- getHomeSafe
  -- (ok,msg) <- case mh of
  --   Just h -> do
  --     let f = h </> journalDefaultFilename
  --     e <- doesFileExist f
  --     return (if e then Y else N, if e then f else "")
  --   Nothing -> return (N, "")
  -- i ok msg

  pdesc "the LEDGER_FILE variable is defined ?"
  mf <- lookupEnv journalEnvVar
  let
    (ok, msg) = case mf of
      Just ""  -> (N, "defined, but with a null value")
      Just f  -> (Y, f)
      Nothing -> (N, "")
  i ok msg

  -- case mf of
  --   Nothing -> return ()
  --   Just f -> do
  --     pdesc "$LEDGER_FILE journal exists ?"
  --     e <- doesFileExist f
  --     i e "" ""

  -- when (isJust mh && isJust mf) $ do
  --   pdesc "$LEDGER_FILE is masking home journal ?"
  --   i Y ""

  pdesc "a default journal file is readable ?"
  ef <- defaultJournalPathSafely
  -- let
  --   args = concat [
  --     ["print"],
  --     ["--ignore-assertions" | supportsIgnoreAssertions version],
  --     ["--no-conf" | supportsConfigFiles version]
  --     ]
  -- (exit, _, err) <- readProcessWithExitCode progname args ""
  -- XXX can this ignore assertions and config files, like the above ?
  ej <- defaultJournalSafely
  let trim s = either (const s) id $ regexReplace (toRegex' "^Error: ") "" s
  case (ef, ej) of
    (Left err, _) -> p N $ trim err
    (Right f, Left err) -> do
      -- show a missing file compactly, other read errors in full
      exists <- doesFileExist f
      p N $ if exists then f <> ":\n" <> trim err else f <> " (not found)"
      journalFilesystemCanAppend f
    (Right f, Right j@Journal{..}) -> do
      p Y f
      journalFilesystemCanAppend f

      pdesc "it includes additional files ?"
      let numfiles = length jfiles
      if numfiles > 1
      then i Y (show (numfiles - 1) <> " files")
      else i N ""

      pdesc "all commodities are declared ?"
      let
        numcommodities = length $ journalCommodities j
        undeclaredcommodities = journalUndeclaredCommodities j  -- same logic as "hledger check commodities"
      if null undeclaredcommodities
      then p Y (show numcommodities <> " commodities")
      else p N (show (length undeclaredcommodities) <> " undeclared commodities")

      let
        -- The basic types which the bs/bse/is/cf reports depend on
        -- (subtypes like Cash also count as their parent type, as in those reports),
        -- and the reports which will be empty when a type has no accounts.
        basictypes = [Asset, Liability, Equity, Revenue, Expense, Cash]
        typesdetected = nub $ M.elems jaccounttypes
        hastype t = any (`isAccountSubtypeOf` t) typesdetected
        typesnotfound = filter (not . hastype) basictypes
        missing = any (`elem` typesnotfound)
        reportsaffected = concat
          [ ["bs"  | missing [Asset, Liability]]  -- and bse, implied
          , ["bse" | missing [Equity], not $ missing [Asset, Liability]]
          , ["is"  | missing [Revenue, Expense]]
          , ["cf"  | missing [Cash]]
          ]
        acctswithdeclaredorinferredtype = nub (M.keys jaccounttypes)
        numaccts = length $ journalAccountNames j
        untypedaccts = journalAccountNames j \\ acctswithdeclaredorinferredtype
        undeclaredaccts = journalAccountNamesUsed j \\ journalAccountNamesDeclared j
        -- hasdeclaredaccts t = case M.lookup t jdeclaredaccounttypes of
        --   Just (_ : _) -> True
        --   _ -> False

      -- pdesc "Asset accounts declared ?"    
      -- if hasdeclaredaccts Asset then i Y "" else i N ""

      -- pdesc "Liability accounts declared ?"
      -- if hasdeclaredaccts Liability then i Y "" else i N ""

      -- pdesc "Equity accounts declared ?"
      -- if hasdeclaredaccts Equity then i Y "" else i N ""

      -- pdesc "Revenue accounts declared ?"
      -- if hasdeclaredaccts Revenue then i Y "" else i N ""

      -- pdesc "Expense accounts declared ?"
      -- if hasdeclaredaccts Expense then i Y "" else i N ""

      -- pdesc "Cash accounts declared ?"
      -- if hasdeclaredaccts Cash then i Y "" else i N ""

      -- pdesc "Conversion accounts declared ?"
      -- if hasdeclaredaccts Conversion then i Y "" else i N ""  -- ("--infer-equity will use a default conversion account name")

      -- XXX hard to detect accounts where type was inferred from name
      -- unless arealltypesdeclared $ do
      -- let
      --   acctswithdeclaredtype           = concat (M.elems jdeclaredaccounttypes)
      --   acctswithinferredtype           = acctswithdeclaredorinferredtype \\ acctswithdeclaredtype
      --   arealltypesdeclared = all hasdeclaredaccts accttypes
      --   typesinferredfromnames =
      --     if arealltypesdeclared then []
      --     else sort $ nub $ catMaybes $ map (flip M.lookup jaccounttypes) acctswithinferredtype
      -- pdesc "types detected from account names ?"
      -- if null typesinferredfromnames then i N "" else i Y (concatMap show typesinferredfromnames)

      pdesc "all accounts are declared ?"
      if null undeclaredaccts then p Y (show numaccts <> " accounts") else i N (show (length undeclaredaccts) <> " undeclared accounts")

      pdesc "all accounts have types ?"
      if null untypedaccts then p Y "" else i N (show (length untypedaccts) <> " accounts without types")

      pdesc "accounts of all basic types exist ?"
      if null typesnotfound
      then p Y (concatMap show basictypes <> " accounts detected")
      else i N (intercalate "/" reportsaffected
                <> (if length reportsaffected == 1 then " needs " else " need ")
                <> concatMap show typesnotfound <> " accounts")

      let strict = isJust $ conflookup (\a -> any (==a) ["-s", "--strict"])

      pdesc "balance assertions checked by default ?"
      let ignoreassertions = isJust $ conflookup (\a -> any (==a) ["-I", "--ignore-assertions"])
      if 
        | ignoreassertions && not strict -> i N "you can add -s to check them"
        | not strict -> i Y "you can add -I to ignore them"
        | otherwise -> i Y "and can't be ignored, because strict checks are enabled"

      pdesc "lot movements checked by default ?"
      let ignorelots = isJust $ conflookup (\a -> any (==a) ["-I", "--ignore-lots"])
      if
        | ignorelots && not strict -> i N "you can add -s to check them"
        | not strict -> i Y "you can add -I to ignore them"
        | otherwise -> i Y "and can't be ignored, because strict checks are enabled"

      pdesc "strict checks checked by default ?"
      if strict
      then i Y "commodities and accounts must be declared"
      else i N "you can add -s to check them"

------------------------------------------------------------------------------

-- Test a hledger version for support of various features.
ver >=! str = ver >= (fromJust $ toVersion str)
supportsIgnoreAssertions = (>=! "0.24") -- --ignore-assertions (2014)
supportsCommodityDirective = (>=! "1.0") -- commodity directive (2016)
supportsPretty = (>=! "1.2") -- --pretty, to use box-drawing characters (2017)
supportsAccountDirective = (>=! "1.9") -- account directive (2018)
supportsAccountTypes = (>=! "1.13") -- ALERX account types, type: tag (2019)
supportsCashAccountType = (>=! "1.19") -- C/Cash account type (2020)
supportsBasicColor = (>=! "1.19") -- basic color detection/control (2020)
supportsConversionAccountType = (>=! "1.25") -- V/Conversion account type, accounts --types (2022)
supportsConfigFiles = (>=! "1.40") -- config files (2024)
supportsColor = (>=! "1.41") -- robust color detection/control (2024)
supportsPager = (>=! "1.41") -- use a pager for all output (2024)
supportsBashCompletions = (>=! "1.41") -- up to date bash shell completions (2024)

-- yes, no, unknown
data YNU = Y | N | U deriving (Eq)

-- ANSI styles
good    = bold' . brightGreen'
neutral = bold' . brightBlue'
warning = bold' . brightYellow'
bad     = bold' . brightRed'

-- Show status, in red/green/yellow if supported.
instance Show YNU where
  show Y = good    "yes"    -- ✅ apple emojis - won't work everywhere
  show N = bad     " no"    -- ❌
  show U = warning "  ?"

-- Show status, in blue/yellow if supported.
showInfo Y = neutral "yes"  -- ℹ️
showInfo N = neutral " no"  -- ℹ️
showInfo U = warning "  ?"

-- | Print a test's pass or fail status, as "yes" or "no" or "",
-- in green/red if supported, and the (possibly empty) provided message.
p :: YNU -> String -> IO ()
p ok msg = putStrLn $ unwords ["", show ok, "", msg]

-- | Like p, but display the status as info, in neutral blue.
i :: YNU -> String -> IO ()
i ok msg = putStrLn $ unwords ["", showInfo ok, "", msg]

-- | Print a setup test groups heading.
pgroup :: String -> IO ()
pgroup s = putStrLn $ -- "\n" <> 
            bold' s

-- | Print a setup test's description, formatting and padding it to a fixed width.
pdesc :: String -> IO ()
pdesc s = printf "  %-40s" s

-- | Probe the journal file's directory to confirm it honors O_APPEND,
-- ie that 'hledger add' will be safe there. Reports the result as a
-- setup check. Any IOException (eg unwritable directory) is reported
-- as unknown rather than a failure.
journalFilesystemCanAppend :: FilePath -> IO ()
journalFilesystemCanAppend f = do
  pdesc "its filesystem supports appending ?"
  let dir = takeDirectory f
  eres <- try (ensureFilesystemCanAppend dir) :: IO (Either IOException Bool)
  case eres of
    Right True  -> p Y ""
    Right False -> p N "add/import won't work; use a reliable filesystem"
    Left e      -> i U $ "unknown; " <> show e

(getLatestHledgerVersion, latestHledgerVersionUrlStr) =
  -- (getLatestHledgerVersionFromHackage, "https://hackage.haskell.org/package/hledger/docs")
  (getLatestHledgerVersionFromHledgerOrg, "https://hledger.org/install.html")

httptimeout = 10000000  -- 10s

-- | Get the current hledger release version from the internet.
-- Currently requests the latest doc page from Hackage and inspects the redirect path.
-- Should catch all normal errors, and time out after 10 seconds.
getLatestHledgerVersionFromHackage :: IO (Either String String)
getLatestHledgerVersionFromHackage = do
  let url = https "hackage.haskell.org" /: "package" /: "hledger" /: "docs" /: ""
  result <- try $ runReq defaultHttpConfig{httpConfigRedirectCount=0} $
    req HEAD url NoReqBody bsResponse (R.responseTimeout httptimeout)
  case result of
    Right _ -> return $ Left "expected a redirect"
    Left (VanillaHttpException (HttpExceptionRequest _ (StatusCodeException rsp _))) -> do
      let status = statusCode $ responseStatus rsp
      if status >= 300 && status < 400
        then do
          let locationHeader = lookup hLocation (responseHeaders rsp)
          case fmap T.decodeUtf8 locationHeader of
            Nothing       -> return $ Left "no Location header"
            Just location -> do
              let packagename = take 1 $ drop 1 $ reverse $ T.splitOn "/" location
              case packagename of
                [n] -> return $ Right $ dropWhile (`notElem` ['0'..'9']) $ T.unpack n
                _   -> return $ Left "couldn't parse Location"
        else return $ Left $ "HTTP status " ++ show status
    Left err -> return $ Left $ "other exception: " ++ show err

-- | Like the above, but get the version from the first number
-- in the first line containing "current hledger release"
-- on the hledger.org Install page.
-- (This has been hard coded for a while, so keep those words in the page to avoid breaking this.)
getLatestHledgerVersionFromHledgerOrg :: IO (Either String String)
getLatestHledgerVersionFromHledgerOrg = do
  let url = https "hledger.org" /: "install.html"
  do
    result <- try $ runReq defaultHttpConfig $ req GET url NoReqBody bsResponse (R.responseTimeout httptimeout)
    case result of
      Left (_ :: R.HttpException) -> return $ Left "(HTTP failure)"
      Right rsp -> case T.decodeUtf8' $ R.responseBody rsp of
        Left e  -> return $ Left $ show e
        Right t -> return $
          if null version then Left "couldn't parse version" else Right version
          where
            -- keep synced
            versionline = take 1 $ dropWhile (not . ("current hledger release" `isInfixOf`)) $ lines $ T.unpack t
            version = takeWhile (`elem` ("0123456789."::[Char])) $ dropWhile (not . isDigit) $ headDef "" $ versionline
  -- work around potential failure on mac (& possible security issue, reported upstream)
  `catch` (\(_ :: IOError) -> return $ Left $ "(IO error" <> if os=="darwin" then " - mac PATH issue ?)" else ")")

-- | Try to run the hledger in PATH with one or more sets of command line arguments.
-- Returns the output from the first set of arguments that runs successfully,
-- or the error output from the last set.
tryHledgerArgs :: [[String]] -> IO (Either String String)
tryHledgerArgs [] = pure $ Left "tryHledgerArgs: no arguments provided"
tryHledgerArgs (args:rest) = do
  eresult <- runHledger args
  case eresult of
    Right out -> pure $ Right out
    Left err -> if null rest then pure $ Left err else tryHledgerArgs rest

-- | Run the hledger in PATH with the given command line arguments,
-- returning the output on success or the error output on failure.
runHledger :: [String] -> IO (Either String String)
runHledger args = do
  (exit, out, err) <- readProcessWithExitCode "hledger" args ""
  pure $ case exit of
    ExitSuccess -> Right out
    ExitFailure _ -> Left err

-- | Get the operating system version string, if possible.
-- Uses platform-specific commands to detect the OS version.
getOSVersion :: IO (Maybe String)
getOSVersion = case os of
  "darwin"  -> tryProc "sw_vers" ["-productVersion"]
  -- Use shell mode so process composes the cmd.exe command line itself,
  -- avoiding cmd /c's quirky argument-quote parsing.
  "mingw32" -> tryShell "ver"
  "linux"   -> tryProc "uname" ["-r"]
  _         -> return Nothing
  where
    tryProc cmd args = tryRead $ readProcess cmd args ""
    tryShell cmd    = tryRead $ readCreateProcess (shell cmd) ""
    tryRead action =
      (Just . strip <$> action)
      `catch` (\(_ :: SomeException) -> return Nothing)
