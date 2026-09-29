{- |
New common report types, used by the BudgetReport for now, perhaps all reports later.
-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveFunctor  #-}
{-# LANGUAGE DeriveGeneric  #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE NamedFieldPuns #-}

module Hledger.Reports.ReportTypes
( PeriodicReport(..)
, PeriodicReportRow(..)

, Percentage
, Change
, Balance
, Total
, Average

, periodicReportSpan
, prMapName
, prMapMaybeName

, CompoundPeriodicReport(..)
, CBCSubreportSpec(..)

, DisplayName(..)
, flatDisplayName
, treeDisplayName

, prrShowDebug
, prrFullName
, prrDisplayName
, prrIndent
, prrAdd
) where

import Data.Aeson (ToJSON(..))
import Data.Bifunctor (Bifunctor(..))
import Data.Decimal (Decimal)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import GHC.Generics (Generic)

import Hledger.Data
import Hledger.Query (Query)
import Hledger.Reports.ReportOptions (ReportOpts)
import Data.Text qualified as T
import Data.List (intercalate)

type Percentage = Decimal

type Change  = MixedAmount  -- ^ A change in balance during a certain period.
type Balance = MixedAmount  -- ^ An ending balance as of some date.
type Total   = MixedAmount  -- ^ The sum of 'Change's in a report or a report row. Does not make sense for 'Balance's.
type Average = MixedAmount  -- ^ The average of 'Change's or 'Balance's in a report or report row.

-- | A periodic report is a generic tabular report, where each row corresponds
-- to some label (usually an account name) and each column to a date period.
-- The column periods are usually consecutive subperiods formed by splitting
-- the overall report period by some report interval (daily, weekly, etc.).
-- It has:
--
-- 1. a list of each column's period (date span)
--
-- 2. a list of rows, each containing:
--
--   * an account label
--
--   * the account's depth
--
--   * A list of amounts, one for each column. Depending on the value type,
--     these can represent balance changes, ending balances, budget
--     performance, etc. (for example, see 'BalanceAccumulation' and
--     "Hledger.Cli.Commands.Balance").
--
--   * the total of the row's amounts for a periodic report,
--     or zero for cumulative/historical reports (since summing
--     end balances generally doesn't make sense).
--
--   * the average of the row's amounts
--
-- 3. the column totals, and the overall grand total (or zero for
-- cumulative/historical reports) and grand average.

data PeriodicReport a b =
  PeriodicReport
  { prDates  :: [DateSpan]               -- The subperiods formed by splitting the overall
                                         -- report period by the report interval. For
                                         -- ending-balance reports, only the end date is
                                         -- significant. Usually displayed as report columns.
  , prRows   :: [PeriodicReportRow a b]  -- One row per account in the report.
  , prTotals :: PeriodicReportRow () b   -- The grand totals row.
  } deriving (Show, Functor, Generic, ToJSON)

instance Bifunctor PeriodicReport where
  bimap f g pr = pr{prRows = map (bimap f g) $ prRows pr, prTotals = g <$> prTotals pr}

instance HasAmounts b => HasAmounts (PeriodicReport a b) where
  styleAmounts styles r@PeriodicReport{prRows,prTotals} =
    r{prRows=styleAmounts styles prRows, prTotals=styleAmounts styles prTotals}

data PeriodicReportRow a b =
  PeriodicReportRow
  { prrName    :: a    -- An account name.
  , prrAmounts :: [b]  -- The data value for each subperiod.
  , prrTotal   :: b    -- The total of this row's values.
  , prrAverage :: b    -- The average of this row's values.
  } deriving (Show, Functor, Generic, ToJSON)

instance Bifunctor PeriodicReportRow where
  first f prr = prr{prrName = f $ prrName prr}
  second = fmap

instance Semigroup b => Semigroup (PeriodicReportRow a b) where
  (<>) = prrAdd

instance HasAmounts b => HasAmounts (PeriodicReportRow a b) where
  styleAmounts styles r =
    r{prrAmounts=styleAmounts styles $ prrAmounts r
     ,prrTotal  =styleAmounts styles $ prrTotal r
     ,prrAverage=styleAmounts styles $ prrAverage r
     }

prrShowDebug :: PeriodicReportRow DisplayName MixedAmount -> String
prrShowDebug (PeriodicReportRow dname amts _tot _avg) =
  unwords [
    T.unpack $ displayFull dname,
    "",
    intercalate " | " $ map showMixedAmount amts
    ]

-- | Add two 'PeriodicReportRows', preserving the name of the first.
prrAdd :: Semigroup b => PeriodicReportRow a b -> PeriodicReportRow a b -> PeriodicReportRow a b
prrAdd (PeriodicReportRow n1 amts1 t1 a1) (PeriodicReportRow _ amts2 t2 a2) =
    PeriodicReportRow n1 (zipWithPadded (<>) amts1 amts2) (t1 <> t2) (a1 <> a2)

-- | Version of 'zipWith' which will not end on the shortest list, but will copy the rest of the longer list.
zipWithPadded :: (a -> a -> a) -> [a] -> [a] -> [a]
zipWithPadded f (a:as) (b:bs) = f a b : zipWithPadded f as bs
zipWithPadded _ as     []     = as
zipWithPadded _ []     bs     = bs

-- | Figure out the overall date span of a PeriodicReport
periodicReportSpan :: PeriodicReport a b -> DateSpan
periodicReportSpan (PeriodicReport colspans _ _) =
  case colspans of
    []  -> DateSpan Nothing Nothing
    s:_ -> DateSpan (Exact <$> spanStart s) (Exact <$> spanEnd (last colspans))

-- | Map a function over the row names.
prMapName :: (a -> b) -> PeriodicReport a c -> PeriodicReport b c
prMapName f report = report{prRows = map (prrMapName f) $ prRows report}

-- | Map a function over the row names, possibly discarding some.
prMapMaybeName :: (a -> Maybe b) -> PeriodicReport a c -> PeriodicReport b c
prMapMaybeName f report = report{prRows = mapMaybe (prrMapMaybeName f) $ prRows report}

-- | Map a function over the row names of the PeriodicReportRow.
prrMapName :: (a -> b) -> PeriodicReportRow a c -> PeriodicReportRow b c
prrMapName f row = row{prrName = f $ prrName row}

-- | Map maybe a function over the row names of the PeriodicReportRow.
prrMapMaybeName :: (a -> Maybe b) -> PeriodicReportRow a c -> Maybe (PeriodicReportRow b c)
prrMapMaybeName f row = case f $ prrName row of
    Nothing -> Nothing
    Just a  -> Just row{prrName = a}


-- | A compound balance report has:
--
-- * an overall title
--
-- * the period (date span) of each column
--
-- * one or more named, normal-positive multi balance reports,
--   with columns corresponding to the above, and a flag indicating
--   whether they increased or decreased the overall totals
--
-- * a list of overall totals for each column, and their grand total and average
--
-- It is used in compound balance report commands like balancesheet,
-- cashflow and incomestatement.
data CompoundPeriodicReport a b = CompoundPeriodicReport
  { cbrTitle      :: Text
  , cbrDates      :: [DateSpan]
  , cbrSubreports :: [(Text, PeriodicReport a b, Bool)]
  , cbrTotals     :: PeriodicReportRow () b
  } deriving (Show, Functor, Generic, ToJSON)

instance HasAmounts b => HasAmounts (CompoundPeriodicReport a b) where
  styleAmounts styles cpr@CompoundPeriodicReport{cbrSubreports, cbrTotals} =
    cpr{
        cbrSubreports = styleAmounts styles cbrSubreports
      , cbrTotals     = styleAmounts styles cbrTotals
      }

instance HasAmounts b => HasAmounts (Text, PeriodicReport a b, Bool) where
  styleAmounts styles (a,b,c) = (a,styleAmounts styles b,c)

-- | Description of one subreport within a compound balance report.
-- Part of a "CompoundBalanceCommandSpec", but also used in hledger-lib.
data CBCSubreportSpec a = CBCSubreportSpec
  { cbcsubreporttitle          :: Text                      -- ^ The title to use for the subreport
  , cbcsubreportquery          :: Query                     -- ^ The Query to use for the subreport
  , cbcsubreportoptions        :: ReportOpts -> ReportOpts  -- ^ A function to transform the ReportOpts used to produce the subreport
  , cbcsubreporttransform      :: PeriodicReport DisplayName MixedAmount -> PeriodicReport a MixedAmount  -- ^ A function to transform the result of the subreport
  , cbcsubreportincreasestotal :: Bool                      -- ^ Whether the subreport and overall report total are of the same sign (e.g. Assets are normally
                                                            --   positive in a balance sheet report, as is the overall total. Liabilities are normally of the
                                                            --   opposite sign.)
  }


-- | The number of indentation steps with which to display a report item.
-- 0 means no indentation. 1 means one indent step, which is normally rendered
-- as two spaces in text output, or two no-break spaces in csv/html output.
type NumberOfIndents = Int

-- | A full name, display name, and indent level for an account.
data DisplayName = DisplayName
    { displayFull   :: AccountName
    , displayName   :: AccountName
    , displayIndent :: NumberOfIndents
    } deriving (Show, Eq, Ord)

instance ToJSON DisplayName where
    toJSON = toJSON . displayFull
    toEncoding = toEncoding . displayFull

-- | Construct a display name for a list report, where full names are shown unindented.
flatDisplayName :: AccountName -> DisplayName
flatDisplayName a = DisplayName a a 0

-- | Construct a display name for a tree report, where leaf names (possibly prefixed by
-- boring parents) are shown indented).
treeDisplayName :: AccountName -> DisplayName
treeDisplayName a = DisplayName a (accountLeafName a) (accountNameLevel a)

-- | Get the full canonical account name from a PeriodicReportRow containing a DisplayName.
prrFullName :: PeriodicReportRow DisplayName a -> AccountName
prrFullName = displayFull . prrName

-- | Get the account display name from a PeriodicReportRow containing a DisplayName.
prrDisplayName :: PeriodicReportRow DisplayName a -> AccountName
prrDisplayName = displayName . prrName

-- | Get the indent level from a PeriodicReportRow containing a DisplayName.
prrIndent :: PeriodicReportRow DisplayName a -> Int
prrIndent = displayIndent . prrName
