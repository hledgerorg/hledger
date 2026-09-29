{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE NamedFieldPuns #-}

module Hledger.Cli.Commands.Import (
  importmode
 ,importcmd
)
where

import Control.Monad
import Data.List
import Data.Text.IO qualified as T
import System.Console.CmdArgs.Explicit
import Text.Printf

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Commands.Add (journalAddTransaction)
import Hledger.Cli.Commands.Get (getcmd)
import Hledger.Cli.Commands.Print (layoutFlag, layoutFromRawOpts)
import System.Directory (doesDirectoryExist, listDirectory)
import System.IO (stderr)
import System.FilePath (takeDirectory, takeFileName, (</>))

importmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Import.txt")
  [flagNone ["get","g"] (setboolopt "get") "fetch new data first by running the get command"
  ,flagNone ["catchup"] (setboolopt "catchup") "just mark all transactions as already imported"
  ,flagNone ["dry-run"] (setboolopt "dry-run") "just show the transactions to be imported"
  ,layoutFlag
  ]
  cligeneralflagsgroups1
  hiddenflags
  ([], Just $ argsFlag "[-f JOURNALFILE] [DATAFILES]")

importcmd opts@CliOpts{rawopts_=rawopts,inputopts_=iopts} j = do
  -- With -g/--get, run the get command first to fetch new data before importing.
  when (boolopt "get" rawopts) $ getcmd opts j
  -- XXX could be helpful to show the last-seen date, and number of old transactions, too
  let
    argfiles = listofstringopt "args" rawopts
    rulesdir = takeDirectory (journalFilePath j) </> rulesDirName
    catchup = boolopt "catchup" rawopts
    dryRun = boolopt "dry-run" rawopts
    postinglayout = layoutFromRawOpts rawopts
    combinedStyles = 
      let
        maybeInputStyles = commodity_styles_ . balancingopts_ $ iopts
        inferredStyles =  journalCommodityStyles j
      in
        case maybeInputStyles of
          Nothing -> Just inferredStyles
          Just inputStyles -> Just $ inputStyles <> inferredStyles

    -- Note: inputOptsSetJournalDir is needed here because this is a secondary
    -- read after the main journal has been loaded; without it the CSV rules
    -- reader would fall back to the rules file's directory for source/archive
    -- lookups instead of the main journal's data/ directory.
    iopts' = inputOptsSetJournalDir j $ iopts{
      new_=True,  -- read only new transactions since last time
      new_save_=False,  -- defer saving .latest files until the end
      strict_=False,  -- defer strict checks until the end
      _importing=True,  -- let the CSV rules reader do its import-specific things (oldest source file, archiving)
      _dryrun=dryRun,   -- but with --dry-run, archive nothing and remove no data file
      balancingopts_=defbalancingopts{commodity_styles_= combinedStyles}  -- use amount styles from both when balancing txns
      }

  inputfiles <- case argfiles of
    [] -> discoverRulesFiles rulesdir
    fs -> return fs
  let inputstr = intercalate ", " $ map (quoteIfNeeded.takeFileName) inputfiles

  case inputfiles of
    [] -> error' $  -- PARTIAL:
      "please specify one or more data files to import from,\n"
      ++ "or add .rules files in a rules/ directory next to the journal."
    fs -> do
      enewjandlatestdatesforfiles <- runExceptT $ readJournalFilesAndLatestDates iopts' fs
      case enewjandlatestdatesforfiles of
        Left err -> error' err
        Right (newj, latestdatesforfiles) ->
          case sortOn tdate $ jtxns newj of
            [] -> hPrintf stderr "no new transactions found in %s\n" inputstr

            newts | catchup ->
              if dryRun
                then hPrintf stderr "would skip %d new transactions (dry run)\n\n" (length newts)
                else do
                  hPrintf stderr "marked %s as caught up, skipping %d transactions\n\n" inputstr (length newts)
                  saveLatestDatesForFiles latestdatesforfiles

            newts -> do
              if dryRun
              then do
                -- show txns to be imported
                hPrintf stderr "would import %d new transactions from %s:\n\n" (length newts) inputstr
                mapM_ (T.putStr . showTransactionWithLayout postinglayout) newts

                -- then check the whole journal with them added, if in strict mode
                when (strict_ iopts) $ strictChecks

              else do
                -- first check the whole journal with them added, if in strict mode
                when (strict_ iopts) $ strictChecks

                -- then append the transactions to the main journal file.
                -- XXX This writes unix line endings (\n), some at least,
                -- even if the file uses dos line endings (\r\n), which could leave
                -- mixed line endings in the file. See also writeFileWithBackupIfChanged.
                foldM_ (`journalAddTransaction` opts) j newts  -- gets forced somehow.. (how ?)

                hPrintf stderr "imported %d new transactions from %s to %s\n" (length newts) inputstr (journalFilePath j)

                -- and if we got this far, update each file's .latest file
                saveLatestDatesForFiles latestdatesforfiles

              where
                -- add the new transactions to the journal in memory and check the whole thing
                strictChecks = either fail pure $ journalStrictChecks j'
                  where j' = foldl' (flip addTransaction) j newts

-- | List the .rules files in the given directory, in alphabetical order,
-- skipping files whose name begins with '.' (hidden) or '_'
-- (disabled, or shared rules included by others).
-- Returns an empty list if the directory does not exist.
discoverRulesFiles :: FilePath -> IO [FilePath]
discoverRulesFiles dir = do
  exists <- doesDirectoryExist dir
  if not exists
    then return []
    else do
      names <- listDirectory dir
      return $ sort [ dir </> n | n <- names
                                , ".rules" `isSuffixOf` n
                                , not (any (`isPrefixOf` n) [".", "_"]) ]
