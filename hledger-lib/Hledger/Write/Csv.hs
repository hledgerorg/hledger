--- * -*- outline-regexp:"--- \\*"; -*-
--- ** doc
{-|

CSV utilities.

-}

--- ** language
{-# LANGUAGE OverloadedStrings    #-}

--- ** exports
module Hledger.Write.Csv (
  CSV, CsvRecord, CsvValue,
  printCSV,
  printTSV,
  -- * Tests
  tests_CsvUtils,
)
where

--- ** imports
import Prelude hiding (Applicative(..))
import Data.List (intersperse)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Builder qualified as TB

import Hledger.Utils

--- ** doctest setup
-- $setup
-- >>> :set -XOverloadedStrings

type CSV       = [CsvRecord]
type CsvRecord = [CsvValue]
type CsvValue  = Text

printCSV :: CSV -> TL.Text
printCSV = TB.toLazyText . unlinesB . map printRecord
    where printRecord = foldMap TB.fromText . intersperse "," . map printField
          printField = wrap "\"" "\"" . T.replace "\"" "\"\""

printTSV :: CSV -> TL.Text
printTSV = TB.toLazyText . unlinesB . map printRecord
    where printRecord = foldMap TB.fromText . intersperse "\t" . map printField
          printField = T.map replaceWhitespace
          replaceWhitespace c | c `elem` ['\t', '\n', '\r'] = ' '
          replaceWhitespace c = c

--- ** tests

tests_CsvUtils :: TestTree
tests_CsvUtils = testGroup "CsvUtils" [
  ]
