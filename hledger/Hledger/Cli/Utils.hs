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
     withTitle,
     printTitle,
     journalTransform,
     journalReload,
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

import Control.Exception (IOException, try)
import Control.Monad.Except (ExceptT)
import Control.Monad.IO.Class (liftIO)
import Data.List
import Data.List.NonEmpty qualified as NE (head, toList)
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
import System.Directory (getModificationTime, getDirectoryContents, copyFile, doesFileExist)
import System.Exit
import System.FilePath ((</>), splitFileName, takeDirectory)
import System.Info (os)
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
unsupportedOutputFormatError :: String -> String
unsupportedOutputFormatError fmt = "Sorry, output format \""++fmt++"\" is unrecognised or not yet supported for this kind of report."

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
-- amounts are already denominated. Also suggest a journal commodity
-- equivalent under ISO 4217 currency code normalisation, if any
-- (eg $ for USD).
maybeWarnUnknownValuationCommodity :: CliOpts -> Journal -> IO ()
maybeWarnUnknownValuationCommodity opts j =
  case valuationTypeValuationCommodity =<< value_ (_rsReportOpts $ reportspec_ opts) of
    Just c
      | c `S.notMember` journalCommoditiesFromPriceDirectives j
      , c `S.notMember` journalCommoditiesFromTransactions j ->
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
-- --pivot, --anonymise error message, --obfuscate, and (when --lots is off) collapsing lot detail.
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
  <&> maybeCollapseLotDetail opts

-- | Collapse lot-tracking detail (strip lot subaccounts, drop synthetic lot-processing
-- postings) so reports show the user's original form. Skipped when --lots is set,
-- or when --ignore-lots/-I is set (in which case leaf-@{...}@ accounts are
-- treated as ordinary account names).
maybeCollapseLotDetail :: CliOpts -> Journal -> Journal
maybeCollapseLotDetail opts
  | boolopt "lots" rawopts        = id
  | boolopt "ignore-lots" rawopts = id
  | command_ opts == "holdings"   = id  -- holdings always needs lot detail; it aggregates lots itself
  | otherwise                     = journalCollapseLotDetail
  where rawopts = rawopts_ opts

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
      ,"please see https://github.com/plaintextaccounting/hledger/issues/2133 ."
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
  f <- outputFileFromOpts opts
  (maybe putStr writeFile f) s

-- | Write some output, to a file specified by --output-file if any,
-- otherwise to stdout.
-- If writing to a file and the file exists, it will be overwritten.
-- If writing to stdout, a pager is used when appropriate and possible.
writeOutputLazyText :: CliOpts -> TL.Text -> IO ()
writeOutputLazyText opts s = do
  mf <- outputFileFromOpts opts
  maybe (runPager . TL.unpack) TL.writeFile mf s

-- | Prepend the effective report heading (followed by a blank line) to a
-- report's lazy text output, if non-empty. Used by reports whose default
-- heading is empty; pass the explicit --title value or "" via
-- effectiveTitle.
withTitle :: ReportOpts -> TL.Text -> TL.Text
withTitle ropts body =
  let h = effectiveTitle ropts ""
  in if T.null h then body
     else TL.fromStrict h <> "\n\n" <> body

-- | Print the effective report heading (followed by a blank line) to stdout
-- if non-empty. For commands whose output is written directly via putStrLn,
-- call this before producing the main output.
printTitle :: ReportOpts -> IO ()
printTitle ropts =
  let h = effectiveTitle ropts ""
  in if T.null h then pure ()
     else T.putStrLn h >> putStrLn ""

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
journalReload opts = do
  journalpaths <- liftIO $ dbg6 "reloading files" <$> journalFilePathFromOpts opts
  let iopts = (inputopts_ opts){_journaldir = Just (takeDirectory (NE.head journalpaths))}
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
-- First through the open-browser package, which uses the Win32 API on
-- Windows, `open` on mac and `xdg-open` on Linux and the BSDs; then, on
-- Linux, through some other launchers that may be installed (one that is
-- not counts as failing). If nothing starts, print the url instead.
openBrowserOn :: String -> IO ExitCode
openBrowserOn u = do
  ok <- openBrowser u
  if ok then return ExitSuccess else trylaunchers launchers
    where
      trylaunchers (cmd:rest) = do
        r <- try $ readProcessWithExitCode cmd [u] ""
        case r of
          Right (ExitSuccess,_,_)    -> return ExitSuccess
          Right (ExitFailure _,_,_)  -> trylaunchers rest
          Left (_ :: IOException)    -> trylaunchers rest
      trylaunchers [] = do
        putStrLn $ printf "Could not start a web browser (tried: %s)" $ intercalate ", " $ launcher0 : launchers
        putStrLn $ printf "Please open your browser and visit %s" u
        return $ ExitFailure 127
      launcher0 | os == "darwin"  = "open"
                | os == "mingw32" = "ShellExecute"
                | otherwise       = "xdg-open"
      launchers | os `elem` ["darwin", "mingw32"] = []
                | otherwise = ["sensible-browser", "gnome-www-browser", "firefox"]

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
