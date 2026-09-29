--- * -*- outline-regexp:"--- \\*"; -*-
--- ** doc
-- In Emacs, use TAB on lines beginning with "-- *" to collapse/expand sections.
{-|

A reader for CSV (character-separated) data.
This also reads a rules file to help interpret the CSV data.

-}

--- ** language
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeFamilies         #-}

--- ** exports
module Hledger.Read.CsvReader (
  -- * Reader
  reader,
  -- * Tests
  tests_CsvReader,
)
where

--- ** imports
import Prelude hiding (Applicative(..))
import Control.Monad.Except       (ExceptT(..), liftEither, withExceptT)
import Control.Monad.IO.Class     (MonadIO)
import Data.Encoding              (DynEncoding)
import Data.Text                  (Text)
import System.IO                  (Handle, IOMode(..), openFile)

import Hledger.Data
import Hledger.Utils
import Hledger.Read.Common (aliasesFromOpts, Reader(..), InputOpts(..), includeFileParser, journalFinalise)
import Hledger.Read.RulesReader (readParsedJournalFromCsv, getRulesFile, rulesEncoding, readRules)
import Control.Monad.Trans (lift)

--- ** doctest setup
-- $setup
-- >>> :set -XOverloadedStrings

--- ** reader

reader :: MonadIO m => SepFormat -> Reader m
reader sep = Reader
  {rFormat     = Sep sep
  ,rExtensions = [show sep]
  ,rReadFn     = parse sep
  -- When included by a journal file: the --rules option is ignored, the rules file is always FILE.rules,
  -- and the data is not finalised here; the including journal's finalisation handles that.
  -- (So if finalisation then fails on a CSV-generated entry, the "converted from this record"
  -- context is not shown, but the error still cites the CSV file and line.)
  ,rParser     = \_ -> includeFileParser $ \f ->
                   fst <$> readCsvWith sep Nothing f (\enc -> openFile f ReadMode >>= hGetContentsPortably enc)
  }

-- | Parse and post-process a "Journal" from a CSV(/SSV/TSV/*SV) data file, or give an error.
-- This reads the data from the provided input file handle, and reads the corresponding
-- rules file (or the one specified by --rules) to help convert it.
-- This does not check balance assertions.
parse :: SepFormat -> InputOpts -> FilePath -> Handle -> ExceptT String IO Journal
parse sep iopts f h = do
  (j1, adderrorcontext) <- readCsvWith sep (mrules_file_ iopts) f (`hGetContentsPortably` h)
  -- apply any command line account aliases. Can fail with a bad replacement pattern.
  j2 <- liftEither $ journalApplyAliases (aliasesFromOpts iopts) j1
  -- if finalisation fails, show also the CSV record which generated the failing entry
  withExceptT adderrorcontext $
    journalFinalise iopts{balancingopts_=(balancingopts_ iopts){ignore_assertions_=True}} f "" j2

-- | Read the rules file for a CSV data file (the one specified, or the one named after the data file),
-- read the data with the given action (which is told the rules' encoding, if any),
-- and convert it to an unfinalised journal (see 'readParsedJournalFromCsv').
readCsvWith :: SepFormat -> Maybe FilePath -> FilePath -> (Maybe DynEncoding -> IO Text)
            -> ExceptT String IO (ParsedJournal, String -> String)
readCsvWith sep mrulesfile f readdata = do
  let rulesfile = getRulesFile f mrulesfile
  (rules, rulesfiles) <- readRules rulesfile
  mencoding <- rulesEncoding rulesfile rules
  csvtext <- lift $ readdata mencoding
  readParsedJournalFromCsv rulesfile rules rulesfiles f csvtext (Just sep)

--- ** tests

tests_CsvReader = testGroup "CsvReader" [
  ]
