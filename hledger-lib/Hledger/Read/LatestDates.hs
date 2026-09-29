{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-|

The @.latest@ mechanism: a per-input-file record of the latest transaction
date(s) seen on the previous read, used by @hledger import@ (and any reader
called with @new_=True@) to filter out already-seen transactions.

For an input file @F@, the latest dates are kept in a @.latest.F@ hidden file
in @F@'s directory. They are written after a successful import and read on the
next one. The CSV rules reader's @archive@ rule also consults these to decide
whether a fresh archive is warranted.

These helpers live in their own module so both the high-level reader
('Hledger.Read') and the low-level CSV rules reader ('Hledger.Read.RulesReader')
can use them without a module-graph cycle.

-}

module Hledger.Read.LatestDates (
  LatestDates,
  LatestDatesForFile(..),
  latestDates,
  latestDatesFileFor,
  previousLatestDates,
  saveLatestDates,
  saveLatestDatesForFiles,
  journalFilterSinceLatestDates,
) where

import Control.Monad (forM, when)
import Data.List (group, sort, sortBy)
import Data.Maybe (catMaybes)
import Data.Ord (comparing)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import Data.Time (Day)
import Safe (headDef)
import System.Directory (doesFileExist)
import System.FilePath (splitFileName, (</>), (<.>))
import Text.Printf (printf)

import Hledger.Data.Dates (parsedate, showDate)
import Hledger.Data.Types (Journal(..), Transaction(..))
import Hledger.Utils (error', readFileStrictly)

-- | One or more dates of the same kind, eg the latest transaction date(s) read from a file.
type LatestDates = [Day]

-- | The path of an input file, and its current 'LatestDates'.
data LatestDatesForFile = LatestDatesForFile FilePath LatestDates
  deriving Show

-- | Get all instances of the latest date in an unsorted list of dates.
-- Ie, if the latest date appears once, return it in a one-element list,
-- if it appears three times (anywhere), return three of it.
latestDates :: [Day] -> LatestDates
latestDates = {-# HLINT ignore "Avoid reverse" #-}
  headDef [] . take 1 . group . reverse . sort

-- | Where to save latest transaction dates for the given file path: @.latest.FILE@
-- in @FILE@'s directory.
latestDatesFileFor :: FilePath -> FilePath
latestDatesFileFor f = dir </> ".latest" <.> fname
  where
    (dir, fname) = splitFileName f

-- | Save the given latest date(s) seen in the given data FILE,
-- in a hidden file named @.latest.FILE@, creating it if needed.
-- Unless no latest dates are provided, in which case do nothing.
saveLatestDates :: LatestDates -> FilePath -> IO ()
saveLatestDates dates f = when (not $ null dates) $
  T.writeFile (latestDatesFileFor f) $ T.unlines $ map showDate dates

-- | Save each file's latest dates.
saveLatestDatesForFiles :: [LatestDatesForFile] -> IO ()
saveLatestDatesForFiles = mapM_ (\(LatestDatesForFile f ds) -> saveLatestDates ds f)

-- | What were the latest transaction dates seen the last time this
-- journal file was read ? If there were multiple transactions on the
-- latest date, that number of dates is returned, otherwise just one.
-- Or none if no transactions were read, or if latest dates info is not
-- available for this file.
previousLatestDates :: FilePath -> IO LatestDates
previousLatestDates f = do
  let latestfile = latestDatesFileFor f
  exists <- doesFileExist latestfile
  t <- if exists then readFileStrictly latestfile else return T.empty
  let nls = zip [1::Int ..] $ T.lines t
  fmap catMaybes $ forM nls $ \(n,l) -> do
    let s = T.unpack $ T.strip l
    case (s, parsedate s) of
      ("", _)       -> return Nothing
      (_,  Nothing) -> error' (printf "%s:%d: invalid date: \"%s\"" latestfile n s)
      (_,  Just d)  -> return $ Just d

-- | Given zero or more latest dates (all the same, representing the
-- latest previously seen transaction date, and how many transactions
-- were seen on that date), remove transactions with earlier dates
-- from the journal, and the same number of transactions on the
-- latest date, if any, leaving only transactions that we can assume
-- are newer. Also returns the new latest dates of the new journal.
journalFilterSinceLatestDates :: LatestDates -> Journal -> (Journal, LatestDates)
journalFilterSinceLatestDates [] j       = (j,  latestDates $ map tdate $ jtxns j)
journalFilterSinceLatestDates ds@(d:_) j = (j', ds')
  where
    samedateorlaterts     = filter ((>= d).tdate) $ jtxns j
    (samedatets, laterts) = span ((== d).tdate) $ sortBy (comparing tdate) samedateorlaterts
    newsamedatets         = drop (length ds) samedatets
    j'                    = j{jtxns=newsamedatets++laterts}
    ds'                   = latestDates $ map tdate $ samedatets++laterts
