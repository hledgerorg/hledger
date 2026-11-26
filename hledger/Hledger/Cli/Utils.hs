{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-|

Utilities for top-level modules and ghci. See also Hledger.Read and
Hledger.Utils.

-}

module Hledger.Cli.Utils
    (
     unsupportedOutputFormatError,
     withJournal,
     withJournalDo,
     withPossibleJournal,
     writeOutput,
     writeOutputLazyText,
     warnIfLargeMultiPeriodReport,
     withTitle,
     writeOutputWithTitle,
     journalTransform,
     journalPrepareLotDetail,
     journalReload,
     journalCheckChange,
     journalReloadIfChanged,
     journalFileIsNewer,
     maybeFileModificationTime,
     openBrowserOn,
     writeFileWithBackup,
     writeFileWithBackupIfChanged,
     journalSimilarTransaction,
     postingsOrTransactionsReportAsText,
     tests_Cli_Utils,
    )
where

import Control.Exception (IOException, evaluate, try)
import Control.Monad.Except (ExceptT)
import Control.Monad.IO.Class (liftIO)
import Data.List
import Data.List.NonEmpty qualified as NE (head, toList)
import Data.Map qualified as M
import Data.Maybe
import Data.Set qualified as S
import Data.Text qualified as T
import Data.Text.IO qualified as T
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Builder qualified as TB
import Data.Text.Lazy.IO qualified as TL
import Data.Time (Day)
import Data.Time.Clock.POSIX (POSIXTime, utcTimeToPOSIXSeconds)
import Lens.Micro ((^.))
import Safe (readMay, headMay)
import System.Console.CmdArgs
import System.Directory (canonicalizePath, getModificationTime, getDirectoryContents, copyFile, createDirectoryIfMissing, doesFileExist, getXdgDirectory, renameFile, XdgDirectory(..))
import System.Exit
import System.FilePath ((</>), splitFileName, takeDirectory)
import System.Info (os)
import System.IO (hClose, openTempFile, hPutStrLn, stderr)
import System.Process (readProcessWithExitCode)
import Text.Printf
import Text.Regex.TDFA ((=~))
import Web.Browser (openBrowser)

import Hledger.Cli.CliOptions
import Hledger.Cli.Anon
import Hledger.Data
import Hledger.Read
import Hledger.Reports
import Hledger.Utils
import Control.Monad (when)
import Data.Functor ((<&>))

-- | Standard error message for a bad output format specified with -O/-o.
-- If it looks like a file name with a known format's extension, it suggests -o.
unsupportedOutputFormatError :: String -> String
unsupportedOutputFormatError fmt =
  "Sorry, output format \""++fmt++"\" is unrecognised or not yet supported for this kind of report."
  ++ if '.' `elem` fmt && filePathExtension fmt `elem` outputFormats
     then "\nTo write to a file named " ++ fmt ++ ", use -o (--output-file), not -O (--output-format)."
     else ""

-- | If a multi-period report has an implausible number of periods (more than 10,000;
-- in practice this means a mistyped date in the journal, making the report span thousands of years),
-- print a warning on stderr before starting it, so the user can cancel (#1683).
-- Such a report can need a lot of memory (a balance report needs a column per period).
-- The periods are counted without building the report, in constant memory.
--
-- This is called explicitly by each command that runs such a report (balance, the compound
-- balance commands, stats, roi, activity), rather than living in the report code: the report functions
-- are pure, so warning from them would need unsafePerformIO or trace, with no guarantee the
-- message appears before the work starts. Doing it in the command's IO, before the report is
-- forced, keeps the ordering reliable. New multi-period report commands should call this too.
warnIfLargeMultiPeriodReport :: ReportSpec -> Journal -> IO ()
warnIfLargeMultiPeriodReport rspec@ReportSpec{_rsReportOpts=ropts} j =
  when (interval_ ropts /= NoInterval && nperiods > maxExpectedPeriods) $ warnIO $ printf
    ("this report has %d periods (%s), and may use a lot of memory.\n"
    <> "If not intended, press control-C now, and check for a mistyped date, or narrow the report.")
    nperiods (showDateSpan rspan)
  where
    (rspan, spans) = reportSpanLazy j rspec
    nperiods = length spans  -- constant memory: the lazy spans are counted, not kept
    maxExpectedPeriods = 10000 :: Int

-- | Parse the user's specified journal file(s) as a Journal, maybe apply some
-- transformations according to options, and run a hledger command with it.
-- Or, throw an error.
--
-- Sets 'InputOpts._journaldir' on the iopts used for this read, so CSV
-- @source@/@archive@ rules find the journal's @data/@ directory. If the
-- callback subsequently performs another 'readJournalFile' / 'readJournalFiles'
-- call (eg in the @import@ command), it should apply 'inputOptsSetJournalDir'
-- to those iopts using the loaded journal — the local @opts.inputopts_@ does
-- not yet carry @_journaldir@ at the call site here.
withJournal :: CliOpts -> (Journal -> IO a) -> IO a
withJournal opts cmd = do
  -- We kludgily read the file before parsing to grab the full text, unless
  -- it's stdin, or it doesn't exist and we are adding. We read it strictly
  -- to let the add command work.
  journalpaths <- journalFilePathFromOpts opts
  let iopts = (inputopts_ opts){_journaldir = Just (takeDirectory (NE.head journalpaths))}
  ej <- runExceptT $ journalTransform opts <$> readJournalFiles iopts (NE.toList journalpaths)
  case ej of
    Left e  -> error' e  -- PARTIAL:
    Right j -> do
      maybeWarnUnknownValuationCommodity opts j
      cmd j

-- | Warn on stderr if -X/--value requests a valuation commodity for which
-- valuation will certainly have no effect: one appearing in no P directive
-- or cost (from which conversion prices could come) and in which no
-- amounts are already denominated, and which is not a commodity alias. Also suggest a journal commodity
-- equivalent under ISO 4217 currency code normalisation, if any
-- (eg $ for USD).
maybeWarnUnknownValuationCommodity :: CliOpts -> Journal -> IO ()
maybeWarnUnknownValuationCommodity opts j =
  case valuationTypeValuationCommodity =<< value_ (_rsReportOpts $ reportspec_ opts) of
    Just c
      | c `S.notMember` journalCommoditiesFromPriceDirectives j
      , c `S.notMember` journalCommoditiesFromTransactions j
      , c `notElem` concatMap commodityAliases (jdeclaredcommodities j) ->
          warnIO $ "no conversion prices to \"" <> T.unpack c <> "\" can be found." <> suggestion c
    _ -> return ()
  where
    suggestion c = case [s | s <- S.toList (journalCommodities j), s /= c, toCurrencyCode s == toCurrencyCode c] of
      (s:_) -> " Did you mean \"" <> T.unpack s <> "\" ?"
      []    -> ""

{-# DEPRECATED withJournalDo "renamed, please use withJournal instead" #-}
withJournalDo = withJournal

-- | Like withJournal, but if the first journal file does not exist, provides an empty
-- journal with that file path set. This is useful for commands like add and import
-- that need to work with a potentially non-existent first journal file,
-- while still reading all specified files (for completions, etc).
--
-- See 'withJournal' for the note about 'inputOptsSetJournalDir' and secondary reads.
withPossibleJournal :: CliOpts -> (Journal -> IO a) -> IO a
withPossibleJournal opts cmd = do
  journalpaths <- journalFilePathFromOptsNoDefault opts
  fs <- case journalpaths of
    Just paths -> return $ NE.toList paths
    Nothing -> (:[]) <$> defaultJournalPath
  let iopts = (inputopts_ opts){_journaldir = takeDirectory <$> headMay fs}
  j <- runExceptT $ journalTransform opts <$> readPossibleJournalFiles iopts fs
  either error' cmd j  -- PARTIAL:

-- | Apply some journal transformations, if enabled by options, that should happen late.
-- These happen after parsing, finalising the journal, strict checks, and .latest filtering/updating,
-- but before report calculation. They are, in processing order:
-- --pivot, --anonymise error message, --obfuscate, and preparing lot detail
-- (converting to cost basis for -B or --gain, then, when --lots is off, collapsing it).
--
-- Why not do these in journalFinalise ?
-- That step is supposed to check the data's intrinsic correctness, regardless of view options;
-- whereas here we assume correctness and are just transforming the view (based only on InputOpts).
-- XXX But it's easy to forget to call this. Current callers include withJournal, journalReload, uiReload, withJournalCached.
journalTransform :: CliOpts -> Journal -> Journal
journalTransform opts =
      maybePivot opts
  <&> maybeWarnAboutAnon opts
  <&> maybeObfuscate opts
  <&> maybePrepareLotDetail opts

-- | Prepare lot detail for the report options (see 'journalPrepareLotDetail'),
-- collapsing it so reports show the user's original form. Collapsing is skipped
-- when --lots is set, or when --ignore-lots/-I is set (in which case leaf-@{...}@
-- accounts are treated as ordinary account names).
-- The holdings command gets the journal unchanged: it aggregates lots itself,
-- and needs their units unconverted even with -B.
maybePrepareLotDetail :: CliOpts -> Journal -> Journal
maybePrepareLotDetail opts
  | command_ opts == "holdings" = id
  | otherwise = journalPrepareLotDetail (_rsReportOpts $ reportspec_ opts) keeplots
  where
    rawopts = rawopts_ opts
    keeplots = boolopt "lots" rawopts
            || boolopt "ignore-lots" rawopts

-- | Prepare a journal's lot detail for reports with these options: convert lot
-- postings to their cost basis where -B or --gain needs it, then, unless
-- keeplots is true, collapse lot detail ('journalCollapseLotDetail').
-- hledger, hledger-ui, and hledger-web all display lots this way, so that
-- they report the same amounts.
journalPrepareLotDetail :: ReportOpts -> Bool -> Journal -> Journal
journalPrepareLotDetail ropts keeplots
  | keeplots  = setCostsToBasisForGain
  | otherwise = journalCollapseLotDetail . setCostsToBasisForGain . convertFragmentsToCostBasis
  where
    -- With -B/--value=cost, when lot detail will be collapsed, convert the
    -- per-lot fragments of split postings (eg a disposal from several lots)
    -- to their cost basis now: collapsing merges them into one amount with an
    -- unspecified basis, after which the basis values would be lost. The later
    -- per-report cost conversion is then a no-op for these amounts.
    -- Other amounts are left for that per-report conversion, which comes after
    -- query matching, so that cur: and amt: still match their original
    -- commodity and quantity (as they do with -V/-X).
    convertFragmentsToCostBasis
      | conversionop_ ropts == Just ToCost = \j -> j{jtxns = map convertTxn $ jtxns j}
      | otherwise = id
    convertTxn t
      | any isfragment (tpostings t) = t{tpostings = mapMaybe (\p -> if isfragment p then postingToCost ToCost p else Just p) $ tpostings t}
      | otherwise = t
    isfragment = postingHasTag lotsplitPostingTagName
    -- With --gain, replace lot postings' transacted costs with their cost basis
    -- now, before lot detail is collapsed, for the same reason: the gain
    -- calculation subtracts cost from summed account balances, and summing
    -- merges amounts by commodity and transacted cost (dropping differing
    -- bases), so the basis is carried in the transacted cost, which sums
    -- correctly. Then gain is value minus cost basis for lot postings however
    -- their costs were written (@ or @@), as it already was for -B (#2751).
    setCostsToBasisForGain
      | balancecalc_ ropts == CalcGain = journalMapPostingAmounts (mapMixedAmount amountSetCostToBasis)
      | otherwise = id

-- | If the --pivot option is present, replace the journal's account names by specified other values.
maybePivot :: CliOpts -> Journal -> Journal
maybePivot opts =
  case maybestringopt "pivot" . rawopts_ $ opts of
    Just tag -> journalPivot $ T.pack tag
    Nothing  -> id

-- #2133
-- | If the --anon flag is present, raise an informative error.
maybeWarnAboutAnon :: CliOpts -> Journal -> Journal
maybeWarnAboutAnon opts =
  if boolopt "anon" $ rawopts_ opts
    then error' $ unlines [
       "--anon does not give privacy, and perhaps should be avoided;"
      ,"please see https://github.com/hledgerorg/hledger/issues/2133 ."
      ,"For now it has been renamed to --obfuscate (a hidden flag)."
      ]
    else id

-- | If the --obfuscate flag is present, apply light obfuscation to the journal data.
maybeObfuscate :: CliOpts -> Journal -> Journal
maybeObfuscate opts =
  if anon_ . inputopts_ $ opts
      then anon
      else id

-- | Write some output to stdout or to a file selected by --output-file.
-- If the file exists it will be overwritten.
writeOutput :: CliOpts -> String -> IO ()
writeOutput opts s = do
  mf <- outputFileOrViewFile opts
  case mf of
    Nothing -> putStr s
    Just f  -> evaluate (length s) >> writeFile f s >> viewIfRequested opts f  -- generate all output first, see writeOutputLazyText

-- | Write some output, to a file specified by --output-file if any,
-- otherwise to stdout.
-- If writing to a file and the file exists, it will be overwritten.
-- If writing to stdout, a pager is used when appropriate and possible.
writeOutputLazyText :: CliOpts -> TL.Text -> IO ()
writeOutputLazyText opts s = do
  mf <- outputFileOrViewFile opts
  case mf of
    Nothing -> runPager $ TL.unpack s
    -- Generate all of the output before opening the file, so that an error while generating it
    -- doesn't leave an empty or truncated file.
    Just f  -> evaluate (TL.length s) >> TL.writeFile f s >> viewIfRequested opts f

-- | The file to write output to: the --output-file if any; or with --view, hledger's view file
-- (see 'viewFile'); or Nothing for stdout.
outputFileOrViewFile :: CliOpts -> IO (Maybe FilePath)
outputFileOrViewFile opts = do
  mf <- outputFileFromOpts opts
  case mf of
    Nothing | viewRequested opts -> Just <$> viewFile opts
    _ -> return mf

-- | Create (or replace) view.FMT in hledger's cache directory (eg ~/.cache/hledger), to write output to,
-- and return its path. It's in the user's own files, not a shared temporary directory,
-- so that other users can't interfere with it; and it's created readable only by the user (on unix),
-- since a home directory may be readable by others.
-- Since it is in a place the user didn't choose, this always warns where it is, before creating it.
viewFile :: CliOpts -> IO FilePath
viewFile opts = do
  d <- getXdgDirectory XdgCache "hledger"
  createDirectoryIfMissing True d
  let f = d </> "view." ++ outputFormatFromOpts opts
  hPutStrLn stderr $ "writing " ++ f ++ " (if it's sensitive, delete it after viewing)"
  -- openTempFile creates a file with owner-only permissions, which writing it later keeps
  (tmp, h) <- openTempFile d "view.tmp"
  hClose h
  renameFile tmp f
  return f

-- | With --view, open a written output file in the system's default viewer for it.
-- If that fails, the file is still there.
viewIfRequested :: CliOpts -> FilePath -> IO ()
viewIfRequested opts f = when (viewRequested opts) $
  launch f >>= either couldnotopen return
  where
    couldnotopen tried = warnIO $ printf "could not open a viewer (tried: %s)" (intercalate ", " tried)

-- | Prepend the effective report heading (followed by a blank line) to a
-- report's lazy text output, if non-empty. Used by reports whose default
-- heading is empty; pass the explicit --title value or "" via
-- effectiveTitle.
withTitle :: ReportOpts -> TL.Text -> TL.Text
withTitle ropts body =
  let h = effectiveTitle ropts ""
  in if T.null h then body
     else TL.fromStrict h <> "\n\n" <> body

-- | Write some text output with 'writeOutput', after the effective report heading
-- if any (see 'withTitle'). For commands producing simple text, like lists of names.
writeOutputWithTitle :: CliOpts -> T.Text -> IO ()
writeOutputWithTitle opts =
  writeOutput opts . TL.unpack . withTitle (_rsReportOpts $ reportspec_ opts) . TL.fromStrict

-- -- | Get a journal from the given string and options, or throw an error.
-- readJournal :: CliOpts -> String -> IO Journal
-- readJournal opts s = readJournal def Nothing s >>= either error' return

-- | Re-read the option-specified journal file(s), but only if any of
-- them has changed since last read. (If the file is standard input,
-- this will either do nothing or give an error, not tested yet).
-- Returns a journal or error message, and a flag indicating whether
-- it was re-read or not.  Like withJournal and journalReload, reads
-- the full journal, without filtering.
journalReloadIfChanged :: CliOpts -> Day -> Journal -> ExceptT String IO (Journal, Bool)
journalReloadIfChanged opts _d j = do
  let maybeChangedFilename f = do newer <- journalFileIsNewer j f
                                  return $ if newer then Just f else Nothing
  changedfiles <- liftIO $ catMaybes <$> mapM maybeChangedFilename (journalAllFilePaths j)
  case changedfiles of
    []  -> return (j, False)
    f:_ -> do
      -- XXX not sure why we use cmdarg's verbosity here, but keep it for now
      verbose <- liftIO isLoud
      when (verbose || debugLevel >= 6) . liftIO $ printf "%s has changed, reloading\n" f
      newj <- journalReload opts
      return (newj, True)

-- | Re-read the journal file(s) specified by options, applying any
-- transformations specified by options. Or return an error string.
-- Reads the full journal, without filtering.
--
-- Sets 'InputOpts._journaldir' on the iopts used for this read. Callers that
-- subsequently do another 'readJournalFile' / 'readJournalFiles' call should
-- apply 'inputOptsSetJournalDir' to those iopts (see 'withJournal').
journalReload :: CliOpts -> ExceptT String IO Journal
journalReload opts = journalReloadWithOverrides opts M.empty

-- | Check a change to one of the journal's files before writing it:
-- re-read the journal as 'journalReload' would after this text was written to this file
-- (which need not exist yet), without writing anything.
-- Return the journal that read gives, or its error message.
-- So the change passes exactly the checks the next read will make, with these options
-- (balancing, balance assertions, lots, strict checks, etc), in the context of all the journal's files.
-- The text should have \n line endings.
journalCheckChange :: CliOpts -> FilePath -> T.Text -> ExceptT String IO Journal
journalCheckChange opts f t = do
  cf <- liftIO $ canonicalizePath f
  journalReloadWithOverrides opts $ M.singleton cf t

-- | Like 'journalReload', but reading the given replacement text for some files (see 'InputOpts._fileoverrides').
journalReloadWithOverrides :: CliOpts -> M.Map FilePath T.Text -> ExceptT String IO Journal
journalReloadWithOverrides opts overrides = do
  journalpaths <- liftIO $ dbg6 "reloading files" <$> journalFilePathFromOpts opts
  let iopts = (inputopts_ opts){_journaldir = Just (takeDirectory (NE.head journalpaths)), _fileoverrides = overrides}
  journalTransform opts <$> readJournalFiles iopts (NE.toList journalpaths)

-- | Has the specified file changed since the journal was last read ?
-- Typically this is one of the journal's journalFilePaths. These are
-- not always real files, so the file's existence is tested first;
-- for non-files the answer is always no.
journalFileIsNewer :: Journal -> FilePath -> IO Bool
journalFileIsNewer Journal{jlastreadtime=tread} f = do
  mtmod <- maybeFileModificationTime f
  return $
    case mtmod of
      Just tmod -> tmod > tread
      Nothing   -> False

-- | Get the last modified time of the specified file, if it exists.
maybeFileModificationTime :: FilePath -> IO (Maybe POSIXTime)
maybeFileModificationTime f = do
  exists <- doesFileExist f
  if exists
  then do
    utc <- getModificationTime f
    return . Just $ utcTimeToPOSIXSeconds utc
  else
    return Nothing

-- | Attempt to open a web browser on the given url, all platforms.
-- On Windows this goes through the open-browser package, which asks the
-- Win32 API to open the url. Elsewhere it runs the platform's launchers in
-- turn until one exits successfully (one that is not installed counts as
-- failing): `open` on mac; `xdg-open` and then some older launchers that
-- may be installed on Linux. If nothing starts, print the url instead.
openBrowserOn :: String -> IO ExitCode
openBrowserOn u = launch u >>= either couldnotstart (const $ return ExitSuccess)
  where
    couldnotstart tried = do
      putStrLn $ printf "Could not start a web browser (tried: %s)" $ intercalate ", " tried
      putStrLn $ printf "Please open your browser and visit %s" u
      return $ ExitFailure 127

-- | Open a url or file with the platform's default application for it, as described for 'openBrowserOn'.
-- If nothing could be started, return what was tried.
launch :: String -> IO (Either [String] ())
launch u
  | os == "mingw32" = do
      ok <- openBrowser u
      return $ if ok then Right () else Left ["the Win32 API"]
  | otherwise = trylaunchers launchers
    where
      trylaunchers (cmd:rest) = do
        r <- try $ readProcessWithExitCode cmd [u] ""
        case r of
          Right (ExitSuccess,_,_)    -> return $ Right ()
          Right (ExitFailure _,_,_)  -> trylaunchers rest
          Left (_ :: IOException)    -> trylaunchers rest
      trylaunchers [] = return $ Left launchers
      launchers | os == "darwin" = ["open"]
                | otherwise      = ["xdg-open", "sensible-browser", "gnome-www-browser", "firefox"]

-- | Back up this file with a (incrementing) numbered suffix then
-- overwrite it with this new text, or give an error, but only if the text
-- is different from the current file contents, and return a flag
-- indicating whether we did anything.
--
-- The given text should have unix line endings (\n); the existing
-- file content will be normalised to unix line endings before
-- comparing the two. If the file is overwritten, the new file will
-- have the current system's native line endings (\n on unix, \r\n on
-- windows). This could be different from the file's previous line
-- endings, if working with a DOS file on unix or vice-versa.
--
writeFileWithBackupIfChanged :: FilePath -> T.Text -> IO Bool
writeFileWithBackupIfChanged f t = do
  s <- readFilePortably f
  if t == s then return False
            else backUpFile f >> T.writeFile f t >> return True

-- | Back up this file with a (incrementing) numbered suffix, then
-- overwrite it with this new text, or give an error.
writeFileWithBackup :: FilePath -> String -> IO ()
writeFileWithBackup f t = backUpFile f >> writeFile f t

-- | Back up this file with a (incrementing) numbered suffix, or give an error.
backUpFile :: FilePath -> IO ()
backUpFile fp = do
  fs <- safeGetDirectoryContents $ takeDirectory $ fp
  let (d,f) = splitFileName fp
      versions = mapMaybe (f `backupNumber`) fs
      next = maximum (0:versions) + 1
      f' = printf "%s.%d" f next
  copyFile fp (d </> f')

safeGetDirectoryContents :: FilePath -> IO [FilePath]
safeGetDirectoryContents "" = getDirectoryContents "."
safeGetDirectoryContents fp = getDirectoryContents fp

-- | Does the second file represent a backup of the first, and if so which version is it ?
-- XXX nasty regex types intruding, add a simpler api to Hledger.Utils.Regex
backupNumber :: FilePath -> FilePath -> Maybe Int
backupNumber f g = case g =~ ("^" ++ f ++ "\\.([0-9]+)$") of
                        (_::FilePath, _::FilePath, _::FilePath, [ext::FilePath]) -> readMay ext
                        _ -> Nothing

-- Identify the closest match for this description in past/future transactions,
-- considering both similarity and proximity to today's date.
-- If the options specify a query, only matched transactions are considered.
journalSimilarTransaction :: CliOpts -> Journal -> T.Text -> Maybe Transaction
journalSimilarTransaction cliopts j desc =
  fmap fourth4 $ headMay $ journalTransactionsSimilarTo j today desc q 0 1
  where
    today = cliopts ^. rsDay
    q = queryFromFlags $ _rsReportOpts $ reportspec_ cliopts

-- | Render a 'PostingsReport' or 'AccountTransactionsReport' as Text,
-- determining the appropriate starting widths and increasing as necessary.
postingsOrTransactionsReportAsText
    :: Bool -> CliOpts -> (Int -> Int -> (a, [WideBuilder], [WideBuilder]) -> TB.Builder)
    -> (a -> MixedAmount) -> (a -> MixedAmount) -> [a] -> TB.Builder
postingsOrTransactionsReportAsText alignAll opts itemAsText itemamt itembal report =
    mconcat . snd $ mapAccumL renderItem (startWidth amt, startWidth bal) itemsWithAmounts
  where
    minWidth  = 12
    chunkSize = 1000

    renderItem (amtWidth, balWidth) item@(_, amt1, bal1) = ((amtWidth', balWidth'), itemBuilder)
      where
        itemBuilder = itemAsText amtWidth' balWidth' item
        amtWidth' = if alignAll then amtWidth else maximumStrict $ amtWidth : map wbWidth amt1
        balWidth' = if alignAll then balWidth else maximumStrict $ balWidth : map wbWidth bal1

    startWidth f = maximum $ minWidth : map wbWidth (concatMap f startAlign)
      where
        startAlign = (if alignAll then id else take chunkSize) itemsWithAmounts

    itemsWithAmounts = map (\x -> (x, showAmt $ itemamt x, showAmt $ itembal x)) report
    showAmt = showMixedAmountLinesB oneLineNoCostFmt{displayColour=opts^.color__}
    amt = second3
    bal = third3

tests_Cli_Utils = testGroup "Utils" [

  --  testGroup "journalApplyValue" [
  --    -- Print the time required to convert one of the sample journals' amounts to value.
  --    -- Pretty clunky, but working.
  --    -- XXX sample.journal has no price records, but is always present.
  --    -- Change to eg examples/5000x1000x10.journal to make this useful.
  --    testCase "time" $ do
  --      ej <- io $ readJournalFile definputopts "examples/3000x1000x10.journal"
  --      case ej of
  --        Left e  -> crash $ T.pack e
  --        Right j -> do
  --          (t,_) <- io $ timeItT $ do
  --            -- Enable -V, and ensure the valuation date is later than
  --            -- all prices for consistent timing.
  --            let ropts = defreportopts{
  --              value_=True,
  --              period_=PeriodTo $ fromGregorian 3000 01 01
  --              }
  --            j' <- journalApplyValue ropts j
  --            sum (journalAmounts j') `seq` return ()
  --          io $ printf "[%.3fs] " t
  --          ok
  -- ]

 ]
