--- * -*- outline-regexp:"--- \\*"; -*-
--- ** doc
-- In Emacs, use TAB on lines beginning with "-- *" to collapse/expand sections.
{-|

This is the entry point to hledger's reading system, which can read
Journals from various data formats. Use this module if you want to parse
journal data or read journal files. Generally it should not be necessary
to import modules below this one.

== Journal reading

Reading an input file (in journal, csv, timedot, or timeclock format..)
involves these steps:

- select an appropriate file format "reader"
  based on filename extension/file path prefix/function parameter.
  A reader contains a parser and a finaliser (usually @journalFinalise@).

- run the parser to get a ParsedJournal
  (this may run additional sub-parsers to parse included files)

- run the finaliser to get a complete Journal, which passes standard checks

- if reading multiple files: merge the per-file Journals into one
  overall Journal

- if using -s/--strict: run additional strict checks

- if running print --new: save .latest files for each input file.
  (import also does this, as its final step.)

== Journal merging

Journal implements the Semigroup class, so two Journals can be merged
into one Journal with @j1 <> j2@. This is implemented by the
@journalConcat@ function, whose documentation explains what merging
Journals means exactly.

== Journal finalising

This is post-processing done after parsing an input file, such as
inferring missing information, normalising amount styles,
checking for errors and so on - a delicate and influential stage
of data processing. 
In hledger it is done by @journalFinalise@, which converts a
preliminary ParsedJournal to a validated, ready-to-use Journal.
This is called immediately after the parsing of each input file.
It is not called when Journals are merged.

== Journal reading API

There are three main Journal-reading functions:

- readJournal to read from a Text value.
  Selects a reader and calls its parser and finaliser,
  then does strict checking if needed.

- readJournalFile to read one file, or stdin if the file path is @-@.
  Uses the file path/file name to help select the reader,
  calls readJournal,
  then writes .latest files if needed.

- readJournalFiles to read multiple files.
  Calls readJournalFile for each file (without strict checking or .latest file writing)
  then merges the Journals into one,
  then does strict checking and .latest file writing at the end if needed.

Each of these also has an easier variant with ' suffix,
which uses default options and has a simpler type signature.

One more variant, @readJournalFilesAndLatestDates@, is like
readJournalFiles but exposing the latest transaction date
(and how many on the same day) seen for each file.
This is used by the import command.

-}

--- ** language
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE PackageImports      #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

--- ** exports
module Hledger.Read (

  -- * Journal files
  defaultJournal,
  defaultJournalSafely,
  defaultJournalWith,
  defaultJournalWithSafely,
  defaultJournalPath,
  defaultJournalPathSafely,
  defaultExistingJournalPath,
  defaultExistingJournalPathSafely,
  requireJournalFileExists,
  ensureJournalFileExists,
  journalEnvVar,
  -- journalEnvVar2,
  journalDefaultFilename,

  -- * Journal parsing
  runExceptT,
  readJournal,
  readJournalFile,
  readPossibleJournalFile,
  readPossibleJournalFiles,
  readJournalFiles,
  readJournalFilesAndLatestDates,

  -- * Easy journal parsing
  readJournal',
  readJournal'',
  readJournalFile',
  readJournalFiles',
  orDieTrying,

  -- * Misc
  isWindowsUnsafeDotPath,

  -- * Re-exported
  JournalReader.tmpostingrulep,
  findReader,
  splitReaderPrefix,
  runJournalParser,
  module Hledger.Read.Common,
  module Hledger.Read.InputOptions,
  module Hledger.Read.LatestDates,

  -- * Tests
  tests_Read,

) where

--- ** imports
import Control.Exception qualified as C
import Control.Monad (unless, when, (>=>))
import "mtl" Control.Monad.Except (ExceptT(..), runExceptT, liftEither)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Default (def)
import Data.Foldable (asum)
import Data.List.NonEmpty (nonEmpty, NonEmpty((:|)))
import Data.Maybe (catMaybes, fromMaybe)
import Data.Semigroup (sconcat)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (getEnv)
import System.FilePath ((</>), splitDirectories, takeDirectory, takeFileName)
import System.Info (os)
import System.IO (Handle, hPutStrLn, stderr)

import Hledger.Data.Dates (getCurrentDay)
import Hledger.Data.Journal (journalNumberAndTieTransactions, nulljournal)
import Hledger.Data.JournalChecks (journalStrictChecks)
import Hledger.Data.Types
import Hledger.Read.Common
import Hledger.Read.InputOptions
import Hledger.Read.JournalReader as JournalReader
import Hledger.Read.LatestDates
import Hledger.Read.CsvReader (tests_CsvReader)
import Hledger.Read.RulesReader (tests_RulesReader)
import Hledger.Utils

--- ** doctest setup
-- $setup
-- >>> :set -XOverloadedStrings

--- ** journal reading

journalEnvVar           = "LEDGER_FILE"
journalDefaultFilename  = ".hledger.journal"

-- | Read the default journal file specified by the environment, 
-- with default input options, or raise an error.
defaultJournal :: IO Journal
defaultJournal = defaultJournalSafely >>= either error' return -- PARTIAL:

-- | Like defaultJournal, but return an error message instead of raising an error.
defaultJournalSafely :: IO (Either String Journal)
defaultJournalSafely = defaultJournalWithSafely definputopts

-- | Like defaultJournal, but use the given input options.
defaultJournalWith :: InputOpts -> IO Journal
defaultJournalWith iopts = defaultJournalWithSafely iopts >>= either error' return -- PARTIAL:

-- | Like defaultJournalWith, but return an error message instead of raising an error.
defaultJournalWithSafely :: InputOpts -> IO (Either String Journal)
defaultJournalWithSafely iopts = (do
  f <- defaultJournalPath
  runExceptT $ readJournalFile iopts f
  )
  `C.catches` [  -- XXX
     C.Handler (\(e :: C.ErrorCall)   -> return $ Left $ show e)
    ,C.Handler (\(e :: C.IOException) -> return $ Left $ show e)
    ]

-- | Get the default journal file path - either $LEDGER_FILE or $HOME/.hledger.journal file.
--
-- This looks for the LEDGER_FILE environment variable, like Ledger.
-- The value should be a file path, possibly with ~ at the start meaning the current user's home directory.
-- Or the value can be a glob pattern (containing *, ?, [ or {) ), in which case the first matching file path is used.
-- When it's a glob pattern that matches no existing files, an error is raised.
--
-- If LEDGER_FILE is unset or set to the empty string, this returns a default file path:
-- @.hledger.journal@ in the user's home directory,
-- or if we can't find the user's home directory, in the current directory.
--
-- The referenced file can be nonexistent.
--
defaultJournalPath :: IO String
defaultJournalPath = do
  p <- getEnv journalEnvVar `C.catch` (\(_::C.IOException) -> return "")
  if null p
  then do
    homedir <- fromMaybe "" <$> getHomeSafe
    let defaultfile = homedir </> journalDefaultFilename
    return defaultfile
  else
    expandPathOrGlob "." p

-- | Like defaultJournalPath, but return an error message instead of raising an error.
defaultJournalPathSafely :: IO (Either String String)
defaultJournalPathSafely = (do
  f <- defaultJournalPath
  return $ Right f
  )
  `C.catches` [
     C.Handler (\(e :: C.ErrorCall)   -> return $ Left $ show e)
    ,C.Handler (\(e :: C.IOException) -> return $ Left $ show e)
    ]

-- | Like defaultJournalPath, but also checks that the file exists, and raises an error if it doesn't.
defaultExistingJournalPath :: IO String
defaultExistingJournalPath = do
  f <- defaultJournalPath
  requireJournalFileExists f
  return f

-- | Like defaultExistingJournalPath, but returns an error message instead of raising an error.
defaultExistingJournalPathSafely :: IO (Either String String)
defaultExistingJournalPathSafely = (do
  f <- defaultExistingJournalPath
  return $ Right f
  )
  `C.catches` [
     C.Handler (\(e :: C.ErrorCall)   -> return $ Left $ show e)
    ,C.Handler (\(e :: C.IOException) -> return $ Left $ show e)
    ]

-- | @readJournal iopts mfile txt@
--
-- Read a Journal from some handle, with strict checks if enabled,
-- or return an error message.
--
-- The reader (data format) is chosen based on, in this order:
--
-- - a reader name provided in @iopts@
--
-- - a reader prefix in the @mfile@ path
--
-- - a file extension in @mfile@
--
-- If none of these is available, or if the reader name is unrecognised,
-- the journal reader is used.
--
-- If a file path is not provided, "-" is assumed (and may appear in error messages,
-- `files` output etc, where it will be a slight lie: it will mean "not from a file",
-- not necessarily "from standard input".
--
readJournal :: InputOpts -> Maybe FilePath -> Handle -> ExceptT String IO Journal
readJournal iopts@InputOpts{strict_, _defer} mpath hdl = do
  let r :: Reader IO = fromMaybe JournalReader.reader $ findReader (mformat_ iopts) mpath
  dbg6IO "readJournal: trying reader" (rFormat r)
  j <- rReadFn r iopts (fromMaybe "-" mpath) hdl
  when (strict_ && not _defer) $ liftEither $ journalStrictChecks j
  return j

-- | Read a Journal from this file, or from stdin if the file path is -,
-- with strict checks if enabled, or return an error message.
-- XXX or, calls error if the file does not exist.
--
-- (Note strict checks are disabled temporarily here when this is called by readJournalFiles).
-- The file path can have a READER: prefix.
--
-- The reader (data format) to use is determined from (in priority order):
-- the @mformat_@ specified in the input options, if any;
-- the file path's READER: prefix, if any;
-- a recognised file name extension.
-- if none of these identify a known reader, the journal reader is used.
--
-- The input options can also configure balance assertion checking, automated posting
-- generation, a rules file for converting CSV data, etc.
--
-- If using --new, and if latest-file writing is enabled in input options,
-- and not deferred by readJournalFiles, and after passing strict checks if enabled,
-- a .latest.FILE file will be created/updated (for the main file only, not for included files),
-- to remember the latest transaction date processed.
--
readJournalFile :: InputOpts -> PrefixedFilePath -> ExceptT String IO Journal
readJournalFile iopts@InputOpts{new_, new_save_, _defer} prefixedfile = do
  (j, mlatestdates) <- readJournalFileAndLatestDates iopts prefixedfile
  when (new_ && new_save_ && not _defer) $ liftIO $
    case mlatestdates of
      Nothing                        -> return ()
      Just (LatestDatesForFile f ds) -> saveLatestDates ds f
  return j

-- The implementation of readJournalFile.
-- With --new, it also returns the latest transaction date(s) read from each file.
-- readJournalFiles uses this to update .latest files only after a successful read of all.
readJournalFileAndLatestDates :: InputOpts -> PrefixedFilePath -> ExceptT String IO (Journal, Maybe LatestDatesForFile)
readJournalFileAndLatestDates iopts prefixedfile = do
  let
    (mfmt, f) = splitReaderPrefix prefixedfile
    iopts' = iopts{mformat_=asum [mfmt, mformat_ iopts]}
  liftIO $ requireJournalFileExists f
  h <-
    dbg6Msg ("readJournalFile: "++takeFileName f) $
    liftIO $ openFileOrStdin f
    -- <- T.readFile f  -- or without line ending translation, for testing
  j <- readJournal iopts' (Just f) h
  if new_ iopts
    then do
      ds <- liftIO $ previousLatestDates f
      let (newj, newds) = journalFilterSinceLatestDates ds j
      return (newj, Just $ LatestDatesForFile f newds)
    else
      return (j, Nothing)

-- | Like readJournalFile, but if the file does not exist, returns an empty journal
-- with the file path set. This is useful for commands like add and import that
-- need to work with a potentially non-existent journal file.
readPossibleJournalFile :: InputOpts -> PrefixedFilePath -> ExceptT String IO Journal
readPossibleJournalFile iopts prefixedfile = do
  let (_, f) = splitReaderPrefix prefixedfile
  if f == "-"
    then readJournalFile iopts prefixedfile
    else do
      exists <- liftIO $ doesFileExist f
      if exists
        then readJournalFile iopts prefixedfile
        else return $ nulljournal{jfiles = [(f, "")]}

-- | Like readJournalFiles, but if the first file does not exist, provides an empty
-- journal with that file path set. Other files must exist as normal.
-- This is useful for commands like add and import that write to the first file,
-- which might not exist yet, while also reading other files for completions etc.
readPossibleJournalFiles :: InputOpts -> [PrefixedFilePath] -> ExceptT String IO Journal
readPossibleJournalFiles iopts pfs = case pfs of
  []     -> return nulljournal
  (f:fs) -> do
    let iopts' = iopts{_defer=True}
    j1 <- readPossibleJournalFile iopts' f
    js <- mapM (readJournalFile iopts') fs
    let combined = journalNumberAndTieTransactions $ sconcat (j1 :| js)
    when (strict_ iopts) $ liftEither $ journalStrictChecks combined
    return combined

-- | Read a Journal from each specified file path (using @readJournalFile@)
-- and combine them into one; or return the first error message.
--
-- Combining Journals means concatenating them, basically.
-- The parse state resets at the start of each file, which means that
-- directives & aliases do not affect subsequent sibling or parent files.
-- They do affect included child files though.
-- Also the final parse state saved in the Journal does span all files.
--
-- Strict checks, if enabled, are temporarily deferred until all files are read,
-- to ensure they see the whole journal, and/or to avoid redundant work.
-- (Some checks, like assertions and ordereddates, might still be doing redundant work ?)
--
-- Writing .latest files, if enabled, is also deferred till the end,
-- and is done only if strict checks pass.
--
readJournalFiles :: InputOpts -> [PrefixedFilePath] -> ExceptT String IO Journal
readJournalFiles iopts@InputOpts{strict_, new_, new_save_} prefixedfiles = do
  let iopts' = iopts{_defer=True}
  (j, latestdatesforfiles) <-
    dbg6Msg ("readJournalFiles: "++show prefixedfiles) $
    readJournalFilesAndLatestDates iopts' prefixedfiles
  when strict_ $ liftEither $ journalStrictChecks j
  when (new_ && new_save_) $ liftIO $ saveLatestDatesForFiles latestdatesforfiles
  return j

-- The implementation of readJournalFiles.
-- With --new, it also returns the latest transaction date(s) read in each file
-- (used by the import command).
-- This also renumbers the transactions if needed, ensuring their tindex values are unique;
-- that's also done elsewhere, but some code (accountTransactionsReport) needs it done sooner.
readJournalFilesAndLatestDates :: InputOpts -> [PrefixedFilePath] -> ExceptT String IO (Journal, [LatestDatesForFile])
readJournalFilesAndLatestDates iopts pfs = do
  (js, lastdates) <- unzip <$> mapM (readJournalFileAndLatestDates iopts) pfs
  return (journalNumberAndTieTransactions $ maybe def sconcat $ nonEmpty js, catMaybes lastdates)

-- | An easy version of 'readJournal' which assumes default options, and fails in the IO monad.
readJournal' :: Handle -> IO Journal
readJournal' = orDieTrying . readJournal definputopts Nothing

-- | An even easier version of readJournal' which takes a 'Text' instead of a 'Handle'.
readJournal'' :: Text -> IO Journal
readJournal'' = textToHandle >=> readJournal'

-- | An easy version of 'readJournalFile' which assumes default options, and fails
-- in the IO monad.
readJournalFile' :: PrefixedFilePath -> IO Journal
readJournalFile' = orDieTrying . readJournalFile definputopts

-- | An easy version of 'readJournalFiles'' which assumes default options, and fails
-- in the IO monad.
readJournalFiles' :: [PrefixedFilePath] -> IO Journal
readJournalFiles' = orDieTrying . readJournalFiles definputopts

--- ** utilities

-- | Extract ExceptT to the IO monad, failing with an error message if necessary.
orDieTrying :: MonadIO m => ExceptT String m a -> m a
orDieTrying a = either (liftIO . fail) return =<< runExceptT a

-- | If the specified journal file does not exist (and is not "-"), call error with an informative message.
-- (Using "journal file" generically here; it could be in any of hledger's supported formats.)
requireJournalFileExists :: FilePath -> IO ()
requireJournalFileExists "-" = return ()
requireJournalFileExists f = do
  exists <- doesFileExist f
  unless exists $ error' $ unlines
    [ "data file \"" <> f <> "\" was not found."
    ,"Please create it first, eg with \"hledger add\" or a text editor."
    ,"Or, specify an existing data file with -f or $LEDGER_FILE."
    ]

-- | Ensure there is a journal file at the given path, creating an empty one if needed.
-- On Windows, also ensure that the path contains no trailing dots
-- which could cause data loss (see 'isWindowsUnsafeDotPath').
ensureJournalFileExists :: FilePath -> IO ()
ensureJournalFileExists f = do
  when (os=="mingw32" && isWindowsUnsafeDotPath f) $
    error' $ "Part of file path \"" <> show f <> "\"\n ends with a dot, which is unsafe on Windows; please use a different path.\n"
  exists <- doesFileExist f
  unless exists $ do
    hPutStrLn stderr $ "Creating hledger journal file " <> show f
    -- Create parent directories if they don't exist
    let dir = takeDirectory f
    unless (null dir || dir == ".") $
      createDirectoryIfMissing True dir
    -- note Hledger.Utils.UTF8.* do no line ending conversion on windows,
    -- we currently require unix line endings on all platforms.
    newJournalContent >>= T.writeFile f

-- | Does any part of this path contain non-. characters and end with a . ?
-- Such paths are not safe to use on Windows (cf #1056).
isWindowsUnsafeDotPath :: FilePath -> Bool
isWindowsUnsafeDotPath = any (\x -> last x == '.' && any (/='.') x) . splitDirectories

-- | Give the content for a new auto-created journal file.
newJournalContent :: IO Text
newJournalContent = do
  d <- getCurrentDay
  return $ "; journal created " <> T.pack (show d) <> " by hledger\n"

--- ** tests

tests_Read = testGroup "Read" [
   tests_Common
  ,tests_CsvReader
  ,tests_JournalReader
  ,tests_RulesReader
  ]
