{- | 
General and hledger-specific input/output-related helpers for
pretty-printing haskell values, error reporting, time, files, command line parsing,
terminals, pager output, ANSI colour/styles, etc.
-}

{-# LANGUAGE ImplicitParams      #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE PackageImports      #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE MultiWayIf #-}

module Hledger.Utils.IO (

  -- * Pretty showing/printing
  pshow,
  pshow',
  pprint,
  pprint',

  -- * Errors
  error',
  usageError,
  warn,
  warnIO,
  setWarningHandler,
  ansiFormatError,
  ansiFormatWarning,
  printError,
  exitWithErrorMessage,
  handleExit,

  -- * Time
  getCurrentLocalTime,
  getCurrentZonedTime,

  -- * Files
  dataDirName,
  rulesDirName,
  getHomeSafe,
  embedFileRelative,
  embedFileRelativeBytes,
  expandHomePath,
  expandPath,
  expandGlob,
  expandPathOrGlob,
  sortByModTime,
  openFileOrStdin,
  withFileOrStdout,
  ensureFilesystemCanAppend,
  readFileOrStdinPortably,
  readFileOrStdinPortably',
  readFileStrictly,
  readFilePortably,
  hGetContentsPortably,
  -- hereFileRelative,
  textToHandle,

  -- * Command line parsing
  progArgs,
  getFlag,
  getOpt,
  parseYN,
  parseYNA,
  YNA(..),
  -- hasOutputFile,
  -- outputFileOption,

  -- * Terminal size
  getTerminalHeightWidth,
  getTerminalHeight,
  getTerminalWidth,
  insideEmacsNotVterm,

  -- * Pager output
  findPager,
  runPager,
  lessVarValue,
  lessIsWorking,

  -- * ANSI colour/styles

  -- ** hledger-specific

  colorOption,
  useColorOnStdout,
  useColorOnStderr,
  useColorOnStdoutUnsafe,
  useColorOnStderrUnsafe,
  supportsTrueColor,
  supportsTrueColorUnsafe,
  bold',
  faint',
  black',
  red',
  green',
  yellow',
  blue',
  magenta',
  cyan',
  white',
  brightBlack',
  brightRed',
  brightGreen',
  brightYellow',
  brightBlue',
  brightMagenta',
  brightCyan',
  brightWhite',
  rgb',
  sgrresetall,
  accent,
  gradientStr,
  titleLine,
  titleAndVersionLine,

  -- ** Generic

  color,
  bgColor,
  colorB,
  bgColorB,
  -- XXX Types used with color/bgColor/colorB/bgColorB,
  -- not re-exported because clashing with UIUtils:
  -- Color(..),
  -- ColorIntensity(..),

  terminalIsLight,
  terminalLightness,
  terminalFgColor,
  terminalBgColor,

  )
where

import           Control.Concurrent (forkIO)
import           Control.Exception
import           Control.Monad (when, forM, guard, void)
import           Data.Char (toLower, isSpace)
import Data.ByteString qualified as BS
import           Data.Colour.RGBSpace (RGB(RGB))
import           Data.Colour.RGBSpace.HSL (lightness)
import           Data.Colour.SRGB (sRGB)
import           Data.Encoding (DynEncoding)
import           Data.FileEmbed (makeRelativeToProject, embedFile, embedStringFile)
import           Data.Functor ((<&>))
import           Data.IORef (IORef, newIORef, readIORef, writeIORef)
import           Data.List hiding (uncons)
import           Data.Maybe (isJust, catMaybes)
import Data.Text qualified as T
import           Data.Text.Encoding.Error (UnicodeException)
import Data.Text.IO qualified as T
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Builder qualified as TB
import           Data.Time.Clock (getCurrentTime)
import           Data.Time.LocalTime (LocalTime, ZonedTime, getCurrentTimeZone, utcToLocalTime, utcToZonedTime)
import           Data.Word (Word16)
import           Debug.Trace
import           Foreign.C.Error (Errno(..), ePIPE)
import           GHC.IO.Encoding (getLocaleEncoding, textEncodingName)
import           GHC.IO.Exception (IOException(..), IOErrorType (ResourceVanished))
import           Language.Haskell.TH.Syntax (Q, Exp)
import           Safe (headMay, maximumDef)
import           System.Console.ANSI (Color(..),ColorIntensity(..), ConsoleLayer(..), SGR(..), hSupportsANSIColor, setSGRCode, getLayerColor, ConsoleIntensity (..), xterm6LevelRGB)
import           System.Console.Terminal.Size (Window (Window), size)
import           System.Directory (getHomeDirectory, getModificationTime, findExecutable)
import           System.Environment (getArgs, getEnvironment, lookupEnv, getProgName)
import           System.Exit (ExitCode(ExitSuccess), exitFailure)
import           System.FilePath (isRelative, (</>), takeBaseName)
import "Glob"    System.FilePath.Glob (glob)
import           System.Info (os)
import           System.IO (Handle, IOMode (..), hClose, hGetEncoding, hIsTerminalDevice, hPutStr, hPutStrLn, hSetNewlineMode, hSetEncoding, openFile, stderr, stdin, stdout, universalNewlineMode, utf8_bom, utf8, withFile)
import System.IO.Encoding qualified as Enc
import           System.IO.Temp (withTempFile)
import           System.IO.Unsafe (unsafePerformIO)
import           System.Process (CreateProcess(..), StdStream(CreatePipe), createPipe, proc, readCreateProcessWithExitCode, shell, waitForProcess, withCreateProcess)
import           System.Timeout (timeout)
import           Text.Pretty.Simple (CheckColorTty(..), OutputOptions(..), defaultOutputOptionsDarkBg, defaultOutputOptionsNoColor, pShowOpt, pPrintOpt)

import Hledger.Utils.Text (WideBuilder(WideBuilder))
import Control.Monad.IO.Class (MonadIO, liftIO)


-- Pretty showing/printing
-- using pretty-simple

-- https://hackage.haskell.org/package/pretty-simple/docs/Text-Pretty-Simple.html#t:OutputOptions

-- | pretty-simple options with colour enabled if allowed.
prettyopts =
  (if useColorOnStderrUnsafe then defaultOutputOptionsDarkBg else defaultOutputOptionsNoColor)
    { outputOptionsIndentAmount = 2
    -- , outputOptionsCompact      = True  -- fills lines, but does not respect page width (https://github.com/cdepillabout/pretty-simple/issues/126)
    -- , outputOptionsPageWidth    = fromMaybe 80 $ unsafePerformIO getTerminalWidth
    }

-- | pretty-simple options with colour disabled.
prettyoptsNoColor =
  defaultOutputOptionsNoColor
    { outputOptionsIndentAmount=2
    }

-- | Pretty show. An easier alias for pretty-simple's pShow.
-- This will probably show in colour if useColorOnStderrUnsafe is true.
pshow :: Show a => a -> String
pshow = TL.unpack . pShowOpt prettyopts

-- | Monochrome version of pshow. This will never show in colour.
pshow' :: Show a => a -> String
pshow' = TL.unpack . pShowOpt prettyoptsNoColor

-- | Pretty print a showable value. An easier alias for pretty-simple's pPrint.
-- This will print in colour if useColorOnStderrUnsafe is true.
pprint :: Show a => a -> IO ()
pprint = pPrintOpt (if useColorOnStderrUnsafe then CheckColorTty else NoCheckColorTty) prettyopts

-- | Monochrome version of pprint. This will never print in colour.
pprint' :: Show a => a -> IO ()
pprint' = pPrintOpt NoCheckColorTty prettyoptsNoColor

-- "Avoid using pshow, pprint, dbg* in the code below to prevent infinite loops." (?)



-- Errors

-- | Call errorWithoutStackTrace, prepending a "Error:" label.
error' :: String -> a
error' = errorWithoutStackTrace . ("Error: "<>)

-- | Like error', but add a hint about using -h
-- (on its own line, if the message has several lines).
usageError :: String -> a
usageError msg = error' $ msg' ++ sep ++ "(use -h to see usage)"
  where
    msg' = dropWhileEnd (== '\n') msg
    sep  = if '\n' `elem` msg' then "\n" else " "

-- | Apply standard ANSI SGR formatting (red, bold) suitable for console error text.
ansiFormatError :: String -> String
ansiFormatError = (<> sgrresetall) . ((sgrbrightred <> sgrbold) <>)

-- | Show a warning message on stderr before returning the given value.
-- Like trace, but prepends a "Warning:" label, and does some ANSI styling of the first line when allowed (using unsafe IO).
-- Currently we use this very sparingly in hledger; we prefer to either quietly work, or loudly raise an error.
-- Varying output can make scripting harder. But on stderr, it shouldn't cause much hassle.
warn :: String -> a -> a
warn = trace . formatWarning

-- | The action warnIO uses to emit a warning message:
-- by default, print it to stderr with a "Warning:" prefix and ANSI styling when supported.
{-# NOINLINE warningHandler #-}
warningHandler :: IORef (String -> IO ())
warningHandler = unsafePerformIO $ newIORef $ traceIO . formatWarning

-- | Replace the action warnIO uses to emit warning messages (which receives
-- the message with no "Warning:" prefix or styling). Eg TUI apps can collect
-- warnings for in-app display, instead of disrupting the terminal with stderr output.
setWarningHandler :: (String -> IO ()) -> IO ()
setWarningHandler = writeIORef warningHandler

-- | Like warn, but take extra care to sequence properly in IO.
-- Emits the warning with the current warning handler (see setWarningHandler).
warnIO :: MonadIO m => String -> m ()
warnIO msg = liftIO $ readIORef warningHandler >>= ($ msg)

formatWarning =
  (if useColorOnStderrUnsafe then modifyFirstLine ansiFormatWarning else id) .
  ("Warning: " <>)

-- | Apply standard ANSI SGR formatting (yellow, bold) suitable for console warning text.
ansiFormatWarning :: String -> String
ansiFormatWarning = (<> sgrresetall) . ((sgrbrightyellow <> sgrbold) <>)

-- Transform a string's first line.
-- Note, this won't add a trailing newline if there isn't one,
-- and it will remove one if there is one or more.
modifyFirstLine :: (String -> String) -> String -> String
modifyFirstLine f s = intercalate "\n" $ map f l <> ls where (l,ls) = splitAt 1 $ lines s  -- total

-- | Print an error message to stderr, with a consistent "programname: " prefix,
-- and applying ANSI styling (bold bright red) to the first line if that is supported and allowed.
printError :: String -> IO ()
printError msg = do
  progname <- getProgName
  usecolor <- useColorOnStderr
  let
    style = if usecolor then modifyFirstLine ansiFormatError else id
    prefix =
      progname
        <> ": "
        -- error' prepends an "Error: " prefix. But that seems to have been removed when I catch the ErrorCall exception - unless I'm running in GHCI.
        -- Is it possible something in GHC or base is removing it ?
        -- Use a stupid heuristic for now: add it again unless already there.
        <> (if "Error:" `isPrefixOf` msg then "" else "Error: ")
  hPutStrLn stderr $ style $ prefix <> msg

-- | Print an error message with printError,
-- then exit the program with a non-zero exit code.
exitWithErrorMessage :: String -> IO ()
exitWithErrorMessage msg = printError msg >> exitFailure

-- | This wraps a program's main routine so as to display more consistent,
-- useful, and GHC-version-independent error output when the program exits
-- because of certain common exceptions. It
--
-- 1. disables SIGPIPE errors, which are usually harmless,
--    caused when our output is truncated in a piped command.
--
-- 2. catches these common exceptions:
--
--    - UnicodeException, caused eg by text decoding errors in pure code
--
--    - IOException, caused by I/O errors, including text decoding errors during I/O
--
--    - ErrorCall - @error@ / @errorWithoutStackTrace@ calls
--
-- 3. compensates for GHC output bugs:
--
--    - removes the trailing newlines added by some GHC 9.10.* versions
--
--    - removes "uncaught exception" output added by some GHC 9.12.* versions
--
--    - ensures a consistent "PROGNAME: " prefix
--
-- 4. applies bold bright red ANSI styling to the first line of error output,
--    if that is supported and allowed
--
-- 5. for unicode exceptions and I/O exceptions which look like they were
--    unicode-related, it adds a message (in english) explaining the problem and what to do.
--
-- Some exceptions this does not catch are ExitCode (exitSuccess/exitFailure/exitWith)
-- and UserInterrupt (control-C).
--
handleExit :: IO () -> IO ()
handleExit = flip catches [
   -- Handler (\(e::SomeException) -> error' $ pshow e),  -- debug
   Handler (\(e::UnicodeException) -> exitUnicode e)
  ,Handler (\(e::IOException) -> if
    | isUnicodeError e    -> exitUnicode e
    | otherwise           -> exitOther e)
  ,Handler (\(e::ErrorCall) -> exitOther e)
  ] . ignoreSigPipe

  where
    -- | Ignore SIGPIPE errors.
    -- This is copied from System.Process.Internals in process 1.6.20.0+,
    -- since that version of process comes only with ghc 9.10.2+.
    ignoreSigPipe :: IO () -> IO ()
    ignoreSigPipe = handle $ \e -> case e of
      IOError { ioe_type  = ResourceVanished
              , ioe_errno = Just ioe }
        | Errno ioe == ePIPE -> return ()
      _ -> throwIO e

    -- Many decoding failures do not produce a UnicodeException, unfortunately.
    -- So this fragile hack detects them from the error message.
    -- But there are many variant wordings and they probably change over time.
    -- It's not ideal.
    isUnicodeError :: Exception e => e -> Bool
    isUnicodeError ex =
      let msg = map toLower (show ex) in any (`isInfixOf` msg) [
          "illegal byte sequence"
        , "invalid byte sequence"
        , "cannot decode byte sequence"
        , "invalid character"
        , "invalid or incomplete multibyte"
        , "mkTextEncoding: invalid argument"
        ]

    exitUnicode :: Exception e => e -> IO ()
    exitUnicode ex = do
      enc <- getSystemEncoding
      let
        noencoding = map toLower enc == "ascii"
        msg = unlines $ [
            rstrip $ show ex
          , "Some text could not be decoded with the system's text encoding, " <> enc
          , "(or, the text encoding specified by CSV rules)."
          ] ++
          if noencoding
          then [
            "Please configure a system locale which can decode this text."
          ]
          else [
            "Please either convert the text to this encoding,"
          , "or configure a system locale which can decode this text."
          ]
      exitWithErrorMessage msg

    exitOther :: Exception e => e -> IO ()
    exitOther = exitWithErrorMessage . rstrip . show

    rstrip = reverse . dropWhile isSpace . reverse

-- I18n

-- encoding has a similar getSystemEncoding :: IO (Maybe DynEncoding)
-- but it returns Nothing on Windows or if there's an error.

-- | Get the name of the text encoding used by the current locale, using GHC's API.
getSystemEncoding :: IO String
getSystemEncoding = do
  localeEncoding <- getLocaleEncoding
  return $ textEncodingName localeEncoding

-- -- | Get the name of the text encoding currently configured for stdout, using GHC's API.
-- getStdoutEncoding :: IO (Maybe String)
-- getStdoutEncoding = do
--   mEncoding <- hGetEncoding stdout
--   return $ fmap textEncodingName mEncoding

-- Time

getCurrentLocalTime :: IO LocalTime
getCurrentLocalTime = do
  t <- getCurrentTime
  tz <- getCurrentTimeZone
  return $ utcToLocalTime tz t

getCurrentZonedTime :: IO ZonedTime
getCurrentZonedTime = do
  t <- getCurrentTime
  tz <- getCurrentTimeZone
  return $ utcToZonedTime tz t



-- Files

-- | Like getHomeDirectory, but in case of IO error (home directory not found, not understood, etc.), returns "".
getHomeSafe :: IO (Maybe FilePath)
getHomeSafe = fmap Just getHomeDirectory `catch` (\(_ :: IOException) -> return Nothing)

-- | Expand a single tilde (representing home directory) at the start of a file path.
-- ~username is not supported. This can raise an IO error.
expandHomePath :: FilePath -> IO FilePath
expandHomePath = \case
    "~"          -> getHomeDirectory
    ('~':'/':p)  -> (</> p) <$> getHomeDirectory
    ('~':'\\':p) -> (</> p) <$> getHomeDirectory
    ('~':_)      -> ioError $ userError "~USERNAME in paths is not supported"
    p            -> return p

-- | Given a current directory, convert a possibly relative, possibly tilde-prefixed
-- file path to an absolute one.
-- ~username is not supported.
-- If the file path is "-", it is left as-is.
-- This can an raise an IO error.
expandPath :: FilePath -> FilePath -> IO FilePath -- general type sig for use in reader parsers
expandPath _ "-" = return "-"
expandPath curdir p = (if isRelative p then (curdir </>) else id) <$> expandHomePath p  -- PARTIAL:

-- | The name of the data directory used by hledger commands and rules that
-- read or write CSV files (located next to the main journal file).
-- This is where the get command saves downloaded transactions data,
-- where the CSV source rule looks for input files,
-- and where the CSV archive rule saves imported files.
dataDirName :: FilePath
dataDirName = "data"

-- | The name of the rules directory used by `hledger import`
-- (located next to the main journal file).
-- This is where import looks for .rules files when invoked with no arguments.
rulesDirName :: FilePath
rulesDirName = "rules"

-- | Like @expandPath@, but treats the expanded path as a glob, and returns
-- zero or more matched absolute file paths, alphabetically sorted.
-- Can raise an error.
-- For a more elaborate glob expander, see 'findMatchedFiles' (used by the include directive).
expandGlob :: FilePath -> FilePath -> IO [FilePath]
expandGlob curdir p = expandPath curdir p >>= glob <&> sort  -- PARTIAL:

-- | Like expandPath, but if the path contains glob metacharacters (* ? [ {),
-- treats it as a glob pattern and expands it, returning the first match.
-- Raises an error if the glob pattern matches no files.
-- If the path contains no glob metacharacters, just expands ~ and returns the path,
-- even if the file doesn't exist yet.
-- This is useful for options like -f and LEDGER_FILE that should:
-- - accept non-existent files (for commands like add/import that create them)
-- - expand glob patterns and error if they don't match anything
expandPathOrGlob :: FilePath -> FilePath -> IO FilePath
expandPathOrGlob curdir p = do
  let hasGlobChars = any (`elem` p) ("*?[{" :: [Char])
  if hasGlobChars
    then do
      matches <- expandGlob curdir p `catch` (\(_::IOException) -> return [])
      case headMay matches of
        Just f -> return f
        Nothing -> error' $ "glob pattern \"" <> p <> "\" matched no files"
    else
      expandPath curdir p

-- | Given a list of existing file paths, sort them by modification time (from oldest to newest).
sortByModTime :: [FilePath] -> IO [FilePath]
sortByModTime fs = do
  ftimes <- forM fs $ \f -> do {t <- getModificationTime f; return (t,f)}
  return $ map snd $ sort ftimes

-- | Like readFilePortably, but read all of the file before proceeding.
readFileStrictly :: FilePath -> IO T.Text
readFileStrictly f = readFilePortably f >>= \t -> evaluate (T.length t) >> return t

-- | Read text from a file,
-- converting any \r\n line endings to \n,,
-- using the system locale's text encoding,
-- ignoring any utf8 BOM prefix (as seen in paypal's 2018 CSV, eg) if that encoding is utf8.
readFilePortably :: FilePath -> IO T.Text
readFilePortably f = openFile f ReadMode >>= hGetContentsPortably Nothing

-- | Like readFilePortably, but read from standard input if the path is "-".
readFileOrStdinPortably :: String -> IO T.Text
readFileOrStdinPortably = readFileOrStdinPortably' Nothing

-- | Like readFileOrStdinPortably, but take an optional converter.
readFileOrStdinPortably' :: Maybe DynEncoding -> String -> IO T.Text
readFileOrStdinPortably' c f = openFileOrStdin f >>= hGetContentsPortably c

-- | Open a file for reading, using the standard System.IO.openFile.
-- This opens the handle in text mode, using the initial system locale's text encoding.
openFileOrStdin :: String -> IO Handle
openFileOrStdin "-" = return stdin
openFileOrStdin f' = openFile f' ReadMode

-- | Run an action with a handle for writing, opening the given file path in
-- the given mode, or returning 'stdout' if the path is "-". When opening a
-- real file, the handle is closed at the end (like 'withFile'); when using
-- stdout, it is left open for the rest of the program.
withFileOrStdout :: FilePath -> IOMode -> (Handle -> IO r) -> IO r
withFileOrStdout "-" _    action = action stdout
withFileOrStdout f   mode action = withFile f mode action

-- | Verify that the filesystem at 'dir' honors O_APPEND, by doing a
-- quick test with a dummy file there (.hledger-append-test*).
-- Returns True if writes opened in 'AppendMode' actually land at end-of-file,
-- False if they don't.
-- This is needed because some filesystems (FAT/exFAT, Android shared-storage
-- and some FUSE mounts) silently drop O_APPEND, so 'appendFile' actually
-- overwrites the file, potentially causing severe data loss (#2577).
ensureFilesystemCanAppend :: FilePath -> IO Bool
ensureFilesystemCanAppend dir =
  withTempFile dir ".hledger-append-test-" $ \path h -> do
    let chunk1 = "can this filesystem\n"
        chunk2 = "append ?\n"
        expected = chunk1 <> chunk2
    BS.hPut h chunk1
    hClose h
    withFile path AppendMode $ \h2 -> BS.hPut h2 chunk2
    actual <- BS.readFile path
    return (actual == expected)

-- | Read text from a handle, perhaps using a specified encoding from the encoding package.
-- Or if no encoding is specified, using the handle's current encoding,
-- changing it to UTF-8BOM if it was UTF-8, to ignore any Byte Order Mark at the start.
-- Also it converts Windows line endings to newlines.
-- If decoding fails, this throws an IOException (or possibly a UnicodeException or something else from the encoding package).
hGetContentsPortably :: Maybe DynEncoding -> Handle -> IO T.Text
hGetContentsPortably Nothing h = do
  hSetNewlineMode h universalNewlineMode
  menc <- hGetEncoding h
  when (fmap show menc == Just "UTF-8") $ hSetEncoding h utf8_bom
  T.hGetContents h
hGetContentsPortably (Just e) h =
  -- convert newlines manually, because Enc.hGetContents uses bytestring's hGetContents
  T.replace "\r\n" "\n" . T.pack <$> let ?enc = e in Enc.hGetContents h

-- | Create a handle from which the given text can be read. Its encoding will be UTF-8.
textToHandle :: T.Text -> IO Handle
textToHandle t = do
  (r, w) <- createPipe
  hSetEncoding r utf8
  hSetEncoding w utf8
  -- use a separate thread so that we don't deadlock if we can't write all of the text at once
  forkIO $ T.hPutStr w t >> hClose w
  return r

-- | Like embedFile, but takes a path relative to the package directory.
embedFileRelative :: FilePath -> Q Exp
embedFileRelative f = makeRelativeToProject f >>= embedStringFile

-- | Like embedFileRelative, but embeds the file's raw bytes as a ByteString,
-- so that its encoding does not depend on the build machine's locale.
embedFileRelativeBytes :: FilePath -> Q Exp
embedFileRelativeBytes f = makeRelativeToProject f >>= embedFile

-- -- | Like hereFile, but takes a path relative to the package directory.
-- -- Similar to embedFileRelative ?
-- hereFileRelative :: FilePath -> Q Exp
-- hereFileRelative f = makeRelativeToProject f >>= hereFileExp
--   where
--     QuasiQuoter{quoteExp=hereFileExp} = hereFile



-- Command line parsing

-- | The program's command line arguments.
-- Uses unsafePerformIO; tends to stick in GHCI until reloaded,
-- and may or may not detect args provided by a hledger config file.
{-# NOINLINE progArgs #-}
progArgs :: [String]
progArgs = unsafePerformIO getArgs
-- XX currently this affects:
--  the enabling of orderdates and assertions checks in journalFinalise
--  a few cases involving --color (see useColorOnStdoutUnsafe)
--  --debug

-- | Given one or more long or short flag names,
-- report whether this flag is present in the command line.
-- Concatenated short flags (-a -b written as -ab) are not supported.
getFlag :: [String] -> IO Bool
getFlag names = do
  let flags = map toFlag names
  args <- getArgs
  return $ any (`elem` args) flags

-- | Given one or more long or short option names, read the rightmost value of this option from the command line arguments.
-- If the value is missing raise an error.
-- Concatenated short flags (-a -b written as -ab) are not supported.
getOpt :: [String] -> IO (Maybe String)
getOpt names = do
  rargs <- reverse . splitFlagsAndVals <$> getArgs
  let flags = map toFlag names
  return $
    case break ((`elem` flags)) rargs of
      (_,[])        -> Nothing
      ([],flag:_)   -> error' $ flag <> " requires a value"
      (argsafter,_) -> Just $ last argsafter

-- | Given a list of command line arguments, split any of the form --flag=VAL or -fVAL into two list items.
-- Concatenated short flags (-a -b written as -ab) are not supported.
splitFlagsAndVals :: [String] -> [String]
splitFlagsAndVals = concatMap $
  \case
    a@('-':'-':_) | '=' `elem` a -> let (x,y) = break (=='=') a in [x, drop 1 y]
    a@('-':f:_:_) | not $ f=='-' -> [take 2 a, drop 2 a]
    a -> [a]

-- | Convert a short or long flag name to a flag with leading hyphen(s).
toFlag [c] = ['-',c]
toFlag s   = '-':'-':s

-- | Parse y/yes/always or n/no/never to true or false, or return an error message.
parseYN :: String -> Either String Bool
parseYN s
  | l `elem` ["y","yes","always"] = Right True
  | l `elem` ["n","no","never"]   = Right False
  | otherwise = Left $ "value should be one of " <> (intercalate ", " ["y","yes","n","no"])
  where l = map toLower s

data YNA = Yes | No | Auto deriving (Eq,Show)

-- | Parse y/yes/always or n/no/never or a/auto to a YNA choice, or return an error message.
parseYNA :: String -> Either String YNA
parseYNA s
  | l `elem` ["y","yes","always"] = Right Yes
  | l `elem` ["n","no","never"]   = Right No
  | l `elem` ["a","auto"]         = Right Auto
  | otherwise = Left $ "value should be one of " <> (intercalate ", " ["y","yes","n","no","a","auto"])
  where l = map toLower s

-- | Is there a --output-file or -o option in the command line arguments ?
-- Uses getOpt; sticky in GHCI until reloaded, may not always be affected by a hledger config file, etc.
hasOutputFile :: IO Bool
hasOutputFile = do
  mv <- getOpt ["output-file","o"]
  return $
    case mv of
      Nothing  -> False
      Just "-" -> False
      _        -> True

-- -- | Get the -o/--output-file option's value, if any, from the command line arguments.
-- -- Uses getOpt; sticky in GHCI until reloaded, may not always be affected by a hledger config file, etc.
-- outputFileOption :: IO (Maybe String)
-- outputFileOption = getOpt ["output-file","o"]



-- Terminal size

-- [NOTE: Alternative methods of getting the terminal size]
-- terminal-size uses the TIOCGWINSZ ioctl to get the window size on Unix
-- systems, which may not be completely portable according to people in
-- #linux@liberachat.
--
-- If this turns out to be the case, supplementary coverage can be given by
-- using the terminfo package.
--
-- Conversely, terminfo on its own is not a full solution, firstly because it
-- only works on Unix (not Windows), and secondly since in some scenarios (eg
-- stripped-down build systems) the terminfo database may be limited and lack
-- the correct entries. (A hack that sometimes works but which isn't robust
-- enough to be relied upon is to set TERM=dumb -- while this advice does appear
-- in some places, it's not guaranteed to work)
--
-- In any case, $LINES/$COLUMNS should not be used as a source for the terminal
-- size - they are not available or do not update reliably in all shells.
--
-- See #2332 for details

-- | An alternative to ansi-terminal's getTerminalSize, based on
-- the more robust-looking terminal-size package.
--
-- Tries to get stdout's terminal's current height and width.
getTerminalHeightWidth :: IO (Maybe (Int,Int))
getTerminalHeightWidth = fmap (fmap unwindow) size
  where unwindow (Window h w) = (h,w)

getTerminalHeight :: IO (Maybe Int)
getTerminalHeight = fmap fst <$> getTerminalHeightWidth

getTerminalWidth :: IO (Maybe Int)
getTerminalWidth  = fmap snd <$> getTerminalHeightWidth

-- | Are we running inside an Emacs subprocess other than vterm ?
-- Terminals like Emacs's M-x shell (comint) advertise a full xterm terminal
-- but only partially emulate it (SGR colours render, but cursor movement and
-- terminal queries do not), so interactive line editing, paging and background
-- colour detection tend to misbehave there.
-- vterm is excluded because it emulates a terminal fully.
-- Emacs sets INSIDE_EMACS to eg "30.1,comint" or "30.1,vterm", so we look for a
-- "vterm" component rather than an exact match.
insideEmacsNotVterm :: IO Bool
insideEmacsNotVterm = maybe False (not . ("vterm" `isInfixOf`)) <$> lookupEnv "INSIDE_EMACS"



-- Pager output
-- somewhat hledger-specific

-- | Try to find a pager executable robustly, safely handling various error conditions
-- like an unset PATH var or the specified pager not being found as an executable.
-- The pager can be specified by a path or program name in the PAGER environment variable.
-- If that is unset or has a problem, "less" is tried, then "more".
-- If successful, the pager's path or program name is returned.
findPager :: IO (Maybe String)  -- XXX probably a ByteString in fact ?
findPager = do
  mpagervar <- lookupEnv "PAGER"
  let pagers = [p | Just p <- [mpagervar]] <> ["less", "more"]
  headMay . catMaybes <$> mapM findExecutable pagers

-- | Should a pager be used for displaying the given text on stdout, and if so, which one ?
-- Uses a pager if findPager finds one and none of the following conditions are true:
-- We're running in a native MS Windows environment like cmd or powershell.
-- Or the --pager=n|no option is in effect.
-- Or the -o/--output-file option is in effect.
-- Or INSIDE_EMACS is set, to something other than "vterm".
-- Or the terminal's current height and width can't be detected.
-- Or the output text is less wide and less tall than the terminal.
-- Throws an error if the --pager option's value could not be parsed.
maybePagerFor :: String -> IO (Maybe String)
maybePagerFor output = do
  let
    ls = lines output
    oh = length ls
    ow = maximumDef 0 $ map length ls
    windows = os == "mingw32"
  pagerno    <- maybe False (not . either error' id . parseYN) <$> getOpt ["pager"]
  outputfile <- hasOutputFile
  emacsterm  <- insideEmacsNotVterm
  mhw        <- getTerminalHeightWidth
  mpager     <- findPager
  return $ do
    guard $ not $ windows || pagerno || outputfile || emacsterm
    (th,tw) <- mhw
    guard $ oh > th || ow > tw
    mpager

-- | Display the given text on the terminal, trying to use a pager ($PAGER, less, or more)
-- when appropriate (see maybePagerFor), otherwise printing to standard output.
-- Also, if the pager is less, we modify the LESS environment variable (see lessVarValue)
-- and check for problems which could cause confusing output (see lessIsWorking).
runPager :: String -> IO ()
runPager s = do
  mpager <- maybePagerFor s
  case mpager of
    Nothing -> putStr s
    Just pager -> do

      -- If using less, customise the LESS environment variable and check if it works
      let pagerIsLess = map toLower (takeBaseName pager) == "less"
      (mCustomEnv, shouldUsePager) <- if not pagerIsLess
        then return (Nothing, True)
        else do
          mHLEDGER_LESS <- lookupEnv "HLEDGER_LESS"
          mLESS         <- lookupEnv "LESS"
          usecolor      <- useColorOnStdout
          let newlessvar = lessVarValue mHLEDGER_LESS mLESS usecolor
          env <- getEnvironment
          let customEnv = ("LESS", newlessvar) : filter ((/= "LESS") . fst) env
          -- Check that less --version is working (using our custom LESS) (#2544)
          lessHasError <- lessIsWorking (Just customEnv) `catch` \(_::IOException) -> return True
          when lessHasError $ warnIO $
            "less --version fails with current LESS settings; disabling. Check 'hledger setup' for details.\n"
          return (Just customEnv, not lessHasError)

      -- Run the pager, providing the text as input. Or if we found a problem already, just print.
      if not shouldUsePager
        then putStr s
        else (withCreateProcess (shell pager){std_in=CreatePipe, env=mCustomEnv} $
          \mhin _ _ p -> do
            case mhin of
              Nothing  -> fail "Failed to create pipe to pager"
              Just hin -> void $ forkIO $   -- Write from another thread to avoid deadlock ? Maybe unneeded, but just in case.
                (hPutStr hin s >> hClose hin)  -- Be sure to close the pipe so the pager knows we're done.
                  -- If the pager quits early, we'll receive an EPIPE error; hide that.
                  `catch` \(e::IOException) -> case e of
                    IOError{ioe_type=ResourceVanished, ioe_errno=Just ioe, ioe_handle=Just hdl} | Errno ioe==ePIPE, hdl==hin -> return ()
                    _ -> throwIO e
            void $ waitForProcess p)
          `catch` \(_::IOException) -> putStr s

-- | Test @less@, by running less --version and looking for a nonzero exit, timeout, or stderr output.
-- Uses the provided environment, containing a LESS variable, if any.
-- We do this because various LESS settings can cause some less versions to fail or cause confusing output without failing.
lessIsWorking :: Maybe [(String, String)] -> IO Bool
lessIsWorking mCustomEnv = do
  result <- timeout 300000 $ readCreateProcessWithExitCode (proc "less" ["--version"]){env=mCustomEnv} ""
  return $ case result of
    Nothing -> True  -- Timeout
    Just (exitCode, _, stderrOut) -> exitCode /= ExitSuccess || not (null stderrOut)

-- | Compute the LESS environment variable value that hledger will use for the less pager.
-- This used in runPager when invoking less, and also in the setup command for display.
-- It takes the current HLEDGER_LESS and LESS env var values, and whether we are showing colour on stdout,
-- and returns the adjusted LESS value that should be used. Specifically:
--
-- - If HLEDGER_LESS is defined, we use it in place of the LESS environment variable.
--
-- - Otherwise, if LESS is defined, append some preferred options (lessOptions and maybe lessColourOptions) to it.
--
-- - Otherwise, we set LESS to just use those preferred options.
--
lessVarValue :: Maybe String -> Maybe String -> Bool -> String
lessVarValue mHLEDGER_LESS mLESS usecolor =
  let extraopts = words lessOptions <> [lessColourOptions | usecolor]
  in case (mHLEDGER_LESS, mLESS) of
       (Just hledgerlessvar, _) -> hledgerlessvar
       (_, Just lessvar) ->
         let existing = words lessvar
             new = filter (`notElem` existing) extraopts
         in if null new then lessvar else unwords (lessvar : new)
       _ -> unwords extraopts

-- keep synced: hledger.m4.md > Paging
-- | hledger's preferred less options, which it will append to the user's LESS environment variable.
-- The thinking here is: "Many people don't have their LESS optimised to get the best experience from modern less, as I didn't.
-- Also as they use hledger on different machines, LESS is likely not consistent. 
-- So let's add some settings that I have found reasonably robust, compatible, and good for usability.
-- That will help provide a consistent good experience when viewing hledger's long outputs.
-- And power users can prevent this by setting exactly the options they want in HLEDGER_LESS."
-- Here's what they mean: https://manned.org/man/less#head5
--
-- Flags that might break older less versions (causing hledger to fall back to unpaged output) are avoided here.
-- Such as --mouse and --wheel-lines (less >=530, 2018) and --use-color (less >=551, 2019).
-- --hilite-unread (less >=443, 2011) is useful and considered old enough.
--
lessOptions = unwords [
   "--chop-long-lines"
  ,"--hilite-unread"
  ,"--ignore-case"
  ,"--no-init"
  ,"--quit-if-one-screen"
  ,"--shift=8"
  ,"--squeeze-blank-lines"
  ,"--use-backslash"
  ] 

-- | Additional less options to use if we are showing colour on stdout.
lessColourOptions = unwords [
   "--RAW-CONTROL-CHARS"
  ]


-- ANSI colour/styles
-- Some of these use unsafePerformIO to read info.

-- hledger-specific:

-- | Get the value of the rightmost --color or --colour option from the program's command line arguments.
-- Throws an error if the option's value could not be parsed.
colorOption :: IO YNA
colorOption = maybe Auto (either error' id . parseYNA) <$> getOpt ["color","colour"]

-- | Should ANSI color and styles be used with this output handle ?
-- Considers the --color/--colour option, and in auto mode the NO_COLOR and TERM
-- environment variables and whether the handle is an ANSI-capable terminal.
-- In auto mode we never use colour when TERM=dumb (the conventional request for
-- plain output); otherwise we use it when ansi-terminal's hSupportsANSIColor says
-- the handle supports colour. Note hSupportsANSIColor reports colour support for an
-- Emacs subshell even on a captured pipe when TERM=dumb, which would leak escape
-- codes into redirected output (eg shelltest); the TERM=dumb check prevents that.
useColorOnHandle :: Handle -> IO Bool
useColorOnHandle h = do
  no_color       <- isJust <$> lookupEnv "NO_COLOR"
  dumbterminal   <- (== Just "dumb") . fmap (map toLower) <$> lookupEnv "TERM"
  supports_color <- hSupportsANSIColor h
  yna            <- colorOption
  return $ yna==Yes || (yna==Auto && not no_color && not dumbterminal && supports_color)

-- | Should ANSI color and styles be used for standard output ?
-- Considers useColorOnHandle stdout and hasOutputFile.
useColorOnStdout :: IO Bool
useColorOnStdout = do
  nooutputfile <- not <$> hasOutputFile
  usecolor <- useColorOnHandle stdout
  return $ nooutputfile && usecolor

-- | Should ANSI color and styles be used for standard error output ?
-- Considers useColorOnHandle stderr; is not affected by an --output-file option.
useColorOnStderr :: IO Bool
useColorOnStderr = useColorOnHandle stderr

-- | Like useColorOnStdout, but using unsafePerformIO. Useful eg for low-level debug code.
-- Sticky in GHCI until reloaded, may not always be affected by --color in a hledger config file, etc.
useColorOnStdoutUnsafe :: Bool
useColorOnStdoutUnsafe = unsafePerformIO useColorOnStdout

-- | Like useColorOnStdoutUnsafe, but for stderr.
useColorOnStderrUnsafe :: Bool
useColorOnStderrUnsafe = unsafePerformIO useColorOnStderr

-- | Does the terminal appear to support 24-bit "true colour" ?
-- Detected from the COLORTERM environment variable being "truecolor" or "24bit",
-- the de-facto convention. This errs conservative: it can miss truecolor terminals
-- that don't set COLORTERM (eg across ssh/tmux/sudo), in which case we fall back to
-- 256-colour; and it can't help terminals that set it but don't actually render
-- truecolor. When false, 'rgb'' downgrades to the nearest xterm 256-colour.
supportsTrueColor :: IO Bool
supportsTrueColor = maybe False (`elem` ["truecolor","24bit"]) <$> lookupEnv "COLORTERM"

-- | Like 'supportsTrueColor', but using unsafePerformIO.
supportsTrueColorUnsafe :: Bool
supportsTrueColorUnsafe = unsafePerformIO supportsTrueColor

-- | Detect whether ANSI should be used on stdout using useColorOnStdoutUnsafe,
-- and if so prepend and append the given SGR codes to a string.
-- Currently used in a few places (the commands list, the recentassertions error message, add);
-- see useColorOnStdoutUnsafe's limitations.
ansiWrapUnsafe :: SGRString -> SGRString -> String -> String
ansiWrapUnsafe pre post s = if useColorOnStdoutUnsafe then pre<>s<>post else s

type SGRString = String

sgrbold          = setSGRCode [SetConsoleIntensity BoldIntensity]
sgrfaint         = setSGRCode [SetConsoleIntensity FaintIntensity]
sgrnormal        = setSGRCode [SetConsoleIntensity NormalIntensity]
sgrresetfg       = setSGRCode [SetDefaultColor Foreground]
sgrresetbg       = setSGRCode [SetDefaultColor Background]
sgrresetall      = sgrresetfg <> sgrresetbg <> sgrnormal
sgrblack         = setSGRCode [SetColor Foreground Dull Black]
sgrred           = setSGRCode [SetColor Foreground Dull Red]
sgrgreen         = setSGRCode [SetColor Foreground Dull Green]
sgryellow        = setSGRCode [SetColor Foreground Dull Yellow]
sgrblue          = setSGRCode [SetColor Foreground Dull Blue]
sgrmagenta       = setSGRCode [SetColor Foreground Dull Magenta]
sgrcyan          = setSGRCode [SetColor Foreground Dull Cyan]
sgrwhite         = setSGRCode [SetColor Foreground Dull White]
sgrbrightblack   = setSGRCode [SetColor Foreground Vivid Black]
sgrbrightred     = setSGRCode [SetColor Foreground Vivid Red]
sgrbrightgreen   = setSGRCode [SetColor Foreground Vivid Green]
sgrbrightyellow  = setSGRCode [SetColor Foreground Vivid Yellow]
sgrbrightblue    = setSGRCode [SetColor Foreground Vivid Blue]
sgrbrightmagenta = setSGRCode [SetColor Foreground Vivid Magenta]
sgrbrightcyan    = setSGRCode [SetColor Foreground Vivid Cyan]
sgrbrightwhite   = setSGRCode [SetColor Foreground Vivid White]
-- Emit a 24-bit truecolor foreground code, or if the terminal doesn't advertise
-- truecolor support (see supportsTrueColorUnsafe), the nearest xterm 256-colour.
sgrrgb r g b
  | supportsTrueColorUnsafe = setSGRCode [SetRGBColor Foreground $ sRGB r g b]
  | otherwise               = setSGRCode [SetPaletteColor Foreground $ xterm6LevelRGB (lvl r) (lvl g) (lvl b)]
  where lvl v = max 0 $ min 5 $ round (v * 5)  -- map a 0..1 intensity to a 0..5 colour-cube level

-- | Set various ANSI styles/colours in a string, only if useColorOnStdoutUnsafe says we should.
bold' :: String -> String
bold'  = ansiWrapUnsafe sgrbold sgrnormal

faint' :: String -> String
faint'  = ansiWrapUnsafe sgrfaint sgrnormal

black' :: String -> String
black'  = ansiWrapUnsafe sgrblack sgrresetfg

red' :: String -> String
red'  = ansiWrapUnsafe sgrred sgrresetfg

green' :: String -> String
green'  = ansiWrapUnsafe sgrgreen sgrresetfg

yellow' :: String -> String
yellow'  = ansiWrapUnsafe sgryellow sgrresetfg

blue' :: String -> String
blue'  = ansiWrapUnsafe sgrblue sgrresetfg

magenta' :: String -> String
magenta'  = ansiWrapUnsafe sgrmagenta sgrresetfg

cyan' :: String -> String
cyan'  = ansiWrapUnsafe sgrcyan sgrresetfg

white' :: String -> String
white'  = ansiWrapUnsafe sgrwhite sgrresetfg

brightBlack' :: String -> String
brightBlack'  = ansiWrapUnsafe sgrbrightblack sgrresetfg

brightRed' :: String -> String
brightRed'  = ansiWrapUnsafe sgrbrightred sgrresetfg

brightGreen' :: String -> String
brightGreen'  = ansiWrapUnsafe sgrbrightgreen sgrresetfg

brightYellow' :: String -> String
brightYellow'  = ansiWrapUnsafe sgrbrightyellow sgrresetfg

brightBlue' :: String -> String
brightBlue'  = ansiWrapUnsafe sgrbrightblue sgrresetfg

brightMagenta' :: String -> String
brightMagenta'  = ansiWrapUnsafe sgrbrightmagenta sgrresetfg

brightCyan' :: String -> String
brightCyan'  = ansiWrapUnsafe sgrbrightcyan sgrresetfg

brightWhite' :: String -> String
brightWhite'  = ansiWrapUnsafe sgrbrightwhite sgrresetfg

rgb' :: Float -> Float -> Float -> String -> String
rgb' r g b  = ansiWrapUnsafe (sgrrgb r g b) sgrresetfg

-- | Choose and apply an accent color for hledger output, if possible
-- picking one that will contrast with the current terminal background colour.
accent :: String -> String
accent
  | not useColorOnStdoutUnsafe    = id  -- XXX unsafe accenting the title banner - seems to work, even respecting config file
  | terminalIsLight == Just False = brightWhite'
  | terminalIsLight == Just True  = brightBlack'
  | otherwise                     = id

-- | Colour a string with hledger's diagonal blue-to-green gradient: each
-- character's colour depends on its position (@row@, and column counting from
-- @col0@) within a grid @h@ rows tall and @w@ columns wide, fading blue at the
-- top-left to green at the bottom-right. The gradient is brighter on a dark
-- terminal background and darker on a light one. The whole string is wrapped in
-- the given intensity style (eg 'bold'' or 'faint''); the per-character colour
-- codes only touch the foreground, so the intensity is kept across the string.
-- When the background lightness can't be detected (eg inside emacs, where the
-- background-colour query doesn't work), it uses the light-background palette,
-- whose deeper shades stay legible on both light and dark backgrounds; only a
-- background known to be dark gets the brighter dark-background palette.
-- Colouring is skipped entirely only when colour is off.
gradientStr :: (String -> String) -> Int -> Int -> Int -> Int -> String -> String
gradientStr intensity h w row col0 s
  | not useColorOnStdoutUnsafe = s
  | otherwise =
      let light      = terminalIsLight /= Just False  -- deep palette unless the background is known dark
          (r1,g1,b1) = if light then (0.12,0.44,0.69) else (0.16,0.71,0.85)  -- start (blue)
          (r2,g2,b2) = if light then (0.25,0.49,0.12) else (0.48,0.75,0.26)  -- end   (green)
          fullspan   = fromIntegral (max 1 (h + w - 2)) :: Float
          paint c ch
            | ch == ' ' = " "  -- leave gaps uncoloured, and out of the escape-code noise
            | otherwise = rgb' (mix r1 r2) (mix g1 g2) (mix b1 b2) [ch]
            where t     = fromIntegral (row + c) / fullspan  -- 0 at top-left, 1 at bottom-right
                  mix a b = a + (b - a) * t
      in intensity $ concat $ zipWith paint [col0..] s

-- | Render a title heading coloured with hledger's blue-to-green bold gradient,
-- when colour is enabled.
titleLine :: String -> String
titleLine title = gradientStr bold' 1 (length title) 0 0 title

-- | Render a one-line heading with a title at the left and a version (or other
-- short annotation) right-aligned to the given width, both coloured with
-- hledger's blue-to-green gradient (bold title, faint version) when colour is
-- enabled.
titleAndVersionLine :: Int -> String -> String -> String
titleAndVersionLine width title version = styledtitle <> pad <> styledversion
  where
    styledtitle   = gradientStr bold'  1 (length title)   0 0 title
    styledversion = gradientStr faint' 1 (length version) 0 0 version
    pad = replicate (max 1 $ width - length title - length version) ' '

-- Generic:

-- | Wrap a string in ANSI codes to set and reset foreground colour.
-- ColorIntensity is @Dull@ or @Vivid@ (ie normal and bold).
-- Color is one of @Black@, @Red@, @Green@, @Yellow@, @Blue@, @Magenta@, @Cyan@, @White@.
-- Eg: @color Dull Red "text"@.
color :: ColorIntensity -> Color -> String -> String
color int col s = setSGRCode [SetColor Foreground int col] ++ s ++ setSGRCode []

-- | Wrap a string in ANSI codes to set and reset background colour.
bgColor :: ColorIntensity -> Color -> String -> String
bgColor int col s = setSGRCode [SetColor Background int col] ++ s ++ setSGRCode []

-- | Wrap a WideBuilder in ANSI codes to set and reset foreground colour.
colorB :: ColorIntensity -> Color -> WideBuilder -> WideBuilder
colorB int col (WideBuilder s w) =
    WideBuilder (TB.fromString (setSGRCode [SetColor Foreground int col]) <> s <> TB.fromString (setSGRCode [])) w

-- | Wrap a WideBuilder in ANSI codes to set and reset background colour.
bgColorB :: ColorIntensity -> Color -> WideBuilder -> WideBuilder
bgColorB int col (WideBuilder s w) =
    WideBuilder (TB.fromString (setSGRCode [SetColor Background int col]) <> s <> TB.fromString (setSGRCode [])) w


-- | Detect whether the terminal currently has a light background colour,
-- if possible, using unsafePerformIO.
-- If the terminal is transparent, its apparent light/darkness may be different.
terminalIsLight :: Maybe Bool
terminalIsLight = (> 0.5) <$> terminalLightness

-- | Detect the terminal's current background lightness (0..1), if possible, using unsafePerformIO.
-- If the terminal is transparent, its apparent lightness may be different.
terminalLightness :: Maybe Float
terminalLightness = lightness <$> terminalColor Background

-- | Detect the terminal's current background colour, if possible, using unsafePerformIO.
terminalBgColor :: Maybe (RGB Float)
terminalBgColor = terminalColor Background

-- | Detect the terminal's current foreground colour, if possible, using unsafePerformIO.
terminalFgColor :: Maybe (RGB Float)
terminalFgColor = terminalColor Foreground

-- | Detect the terminal's current foreground or background colour, if possible, using unsafePerformIO.
{-# NOINLINE terminalColor #-}
terminalColor :: ConsoleLayer -> Maybe (RGB Float)
terminalColor = unsafePerformIO . getLayerColor'

-- A version of ansi-terminal's getLayerColor that is less likely to leak escape sequences to output,
-- and that returns a RGB of Floats (0..1) that is more compatible with the colour package.
-- This does nothing in a non-interactive context (eg when piping stdout to another command),
-- inside emacs (comint shell buffers show the query's escape sequence instead of answering it,
-- and vterm doesn't answer the query at all), or in a non-colour-supporting terminal.
getLayerColor' :: ConsoleLayer -> IO (Maybe (RGB Float))
getLayerColor' l = do
  inemacs       <- not . null <$> lookupEnv "INSIDE_EMACS"
  interactive   <- hIsTerminalDevice stdout
  supportscolor <- hSupportsANSIColor stdout
  if inemacs || not interactive || not supportscolor then return Nothing
  else fmap fractionalRGB <$> getLayerColor l
  where
    fractionalRGB :: (Fractional a) => RGB Word16 -> RGB a
    fractionalRGB (RGB r g b) = RGB (fromIntegral r / 65535) (fromIntegral g / 65535) (fromIntegral b / 65535)  -- chatgpt

