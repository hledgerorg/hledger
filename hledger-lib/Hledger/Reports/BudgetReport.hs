{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Hledger.Reports.BudgetReport (
  BudgetGoal,
  BudgetTotal,
  BudgetAverage,
  BudgetCell,
  BudgetReportRow,
  BudgetReport,
  budgetReport,
  -- * Tests
  tests_BudgetReport
)
where

import Control.Applicative ((<|>))
import Control.Monad ((>=>))
import Data.Bifunctor (bimap)
import Data.Foldable (toList)
import Data.List (find, maximumBy, intercalate)
import Data.Maybe (catMaybes, fromMaybe, isJust)
import Data.Ord (comparing)
import Data.Set qualified as S
import Data.Text qualified as T
import Data.These (These(..), these)
import Safe (minimumDef)

import Hledger.Data
import Hledger.Query
import Hledger.Utils
import Hledger.Reports.ReportOptions
import Hledger.Reports.ReportTypes
import Hledger.Reports.MultiBalanceReport

-- All MixedAmounts:
type BudgetGoal    = Change
type BudgetTotal   = Total
type BudgetAverage = Average

-- | A budget report tracks expected and actual changes per account and subperiod.
-- Each table cell has an actual change amount and/or a budget goal amount.
type BudgetCell = (Maybe Change, Maybe BudgetGoal)
-- | A row in a budget report table - account name and data cells.
type BudgetReportRow = PeriodicReportRow DisplayName BudgetCell
-- | A full budget report table.
type BudgetReport    = PeriodicReport    DisplayName BudgetCell

_brrShowDebug :: BudgetReportRow -> String
_brrShowDebug (PeriodicReportRow dname budgetpairs _tot _avg) =
  unwords [
    T.unpack $ displayFull dname,
    "",
    intercalate " | "
      [ maybe "-" showMixedAmount mactual <> " [" <> maybe "-" showMixedAmount mgoal <> "]"
      | (mactual,mgoal) <- budgetpairs ]
    ]

-- | Calculate per-account, per-period budget (balance change) goals
-- from all periodic transactions, calculate actual balance changes
-- from the regular transactions, and compare these to get a 'BudgetReport'.
-- Unbudgeted accounts may be hidden or renamed (see journalWithBudgetAccountNames).
budgetReport :: ReportSpec -> BalancingOpts -> DateSpan -> Journal -> BudgetReport
budgetReport rspec bopts reportspan j = dbg4 "sortedbudgetreport" budgetreport
  where
    -- Budget report demands ALTree mode to ensure subaccounts and subaccount budgets are properly handled
    -- and that reports with and without --empty make sense when compared side by side
    ropts = (_rsReportOpts rspec){ accountlistmode_ = ALTree }
    -- ropts = _rsReportOpts rspec
    showunbudgeted = empty_ ropts

    budgetedaccts =
      dbg3 "budgetedacctsinperiod" $
      S.fromList $
      expandAccountNames $
      accountNamesFromPostings $
      concatMap tpostings $
      concatMap (\pt -> runPeriodicTransaction False pt reportspan) $
      jperiodictxns j

    actualj = journalWithBudgetAccountNames budgetedaccts showunbudgeted j
    budgetj = journalAddBudgetGoalTransactions bopts ropts reportspan j
    priceoracle = journalPriceOracle (infer_prices_ ropts) j

    -- The report spec used for selecting budget goals, with the query terms
    -- that describe actual transactions/postings dropped. (#2545)
    budgetrspec = rspec{_rsQuery = budgetGoalQuery $ _rsQuery rspec}

    (_, actualspans) = dbg5 "actualspans" $ reportSpan actualj rspec
    (_, budgetspans) = dbg5 "budgetspans" $ reportSpan budgetj budgetrspec
    allspans = dbg5 "allspans" $ case (interval_ ropts, budgetspans) of
        -- If no interval is specified:
        -- budgetgoalreport's span might be shorter actualreport's due to periodic txns;
        -- it should be safe to replace it with the latter, so they combine well.
        (NoInterval, _) -> actualspans
        (_,    Nothing) -> actualspans
        (_, Just bspan) -> unionDayPartitions bspan =<< actualspans

    actualps = dbg5 "actualps" $ getPostings rspec actualj priceoracle reportspan
    budgetps = dbg5 "budgetps" $ getPostings budgetrspec budgetj priceoracle reportspan

    actualAcct = dbg5 "actualAcct" $ generateMultiBalanceAccount rspec actualj priceoracle actualspans actualps
    budgetAcct = dbg5 "budgetAcct" $ generateMultiBalanceAccount budgetrspec budgetj priceoracle budgetspans budgetps

    combinedAcct = dbg5 "combinedAcct" $ if null budgetps
        -- If no budget postings, just use actual account, to avoid unnecssary budget zeros
        then This <$> actualAcct
        else mergeAccounts actualAcct budgetAcct

    budgetreport = generateBudgetReport ropts allspans combinedAcct

-- | Reduce a report query to the terms which are meaningful for selecting budget goals:
-- the account, account type, depth, date and commodity terms.
-- The remaining terms (status, code, description, payee, note, tag, realness, amount)
-- describe actual transactions and postings, and are dropped;
-- budget goal transactions are synthetic, so applying those terms to them
-- would discard budget goals unexpectedly (#2545).
budgetGoalQuery :: Query -> Query
budgetGoalQuery = filterQuery selectsAccountOrPeriod
  where
    selectsAccountOrPeriod q = case q of
      Acct{}      -> True
      DepthAcct{} -> True
      Depth{}     -> True
      Type{}      -> True
      Date{}      -> True
      Date2{}     -> True
      Sym{}       -> True
      Cur{}       -> True
      None        -> True
      Not q'      -> selectsAccountOrPeriod q'
      _           -> False

-- | Lay out a set of postings grouped by date span into a regular matrix with rows
-- given by AccountName and columns by DateSpan, then generate a MultiBalanceReport
-- from the columns.
generateBudgetReport :: ReportOpts -> Maybe DayPartition -> Account (These BalanceData BalanceData) -> BudgetReport
generateBudgetReport = generatePeriodicReport makeBudgetReportRow treeActualBalance flatActualBalance
  where
    treeActualBalance = these bdincludingsubs (const nullmixedamt) (const . bdincludingsubs)
    flatActualBalance = fromMaybe nullmixedamt . fst

-- | Build a report row.
--
-- Calculate the column totals. These are always the sum of column amounts.
makeBudgetReportRow :: ReportOpts -> (BalanceData -> MixedAmount)
                    -> a -> Account (These BalanceData BalanceData) -> PeriodicReportRow a BudgetCell
makeBudgetReportRow ropts balance =
    makePeriodicReportRow (Just nullmixedamt, Nothing) avg ropts (theseToMaybe . bimap balance balance)
  where
    avg xs = ((actualtotal, budgettotal), (actualavg, budgetavg))
      where
        (actuals, budgets) = unzip $ toList xs
        (actualtotal, actualavg) = bimap Just Just . sumAndAverageMixedAmounts $ catMaybes actuals
        (budgettotal, budgetavg) = bimap Just Just . sumAndAverageMixedAmounts $ catMaybes budgets

    theseToMaybe (This a) = (Just a, Nothing)
    theseToMaybe (That b) = (Just nullmixedamt, Just b)
    theseToMaybe (These a b) = (Just a, Just b)

-- | Use all (or all matched by --budget's argument) periodic transactions in the journal 
-- to generate budget goal transactions in the specified date span (and before, to support
-- --historical. The precise start date is the natural start date of the largest interval
-- of the active periodic transaction rules that is on or before the earlier of journal start date,
-- report start date.)
-- Budget goal transactions are similar to forecast transactions except their purpose 
-- and effect is to define balance change goals, per account and period, for BudgetReport.
--
journalAddBudgetGoalTransactions :: BalancingOpts -> ReportOpts -> DateSpan -> Journal -> Journal
journalAddBudgetGoalTransactions bopts ropts reportspan j =
  either error' id $  -- PARTIAL:
    (journalStyleAmounts >=> journalBalanceTransactions bopts) j{ jtxns = budgetts }
  where
    budgetspan = dbg3 "budget span" $ DateSpan (Exact <$> mbudgetgoalsstartdate) (Exact <$> spanEnd reportspan)
      where
        mbudgetgoalsstartdate =
          -- We want to also generate budget goal txns before the report start date, in case -H is used.
          -- What should the actual starting date for goal txns be ? This gets tricky. 
          -- Consider a journal with a "~ monthly" periodic transaction rule, where the first transaction is on 1/5.
          -- Users will certainly expect a budget goal for january, but "~ monthly" generates transactions
          -- on the first of month, and starting from 1/5 would exclude 1/1.
          -- Secondly, consider a rule like "~ every february 2nd from 2020/01"; we should not start that
          -- before 2020-02-02.
          -- Hopefully the following algorithm produces intuitive behaviour in general:
          -- from the earlier of the journal start date and the report start date,
          -- move backward to the nearest natural start date of the largest period seen among the
          -- active periodic transactions, unless that is disallowed by a start date in the periodic rule.
          -- (Do we need to pay attention to an end date in the rule ? Don't think so.)
          -- (So with "~ monthly", the journal start date 1/5 is adjusted to 1/1.)
          case minimumDef Nothing $ filter isJust [journalStartDate False j, spanStart reportspan] of
            Nothing -> Nothing
            Just d  -> Just d'
              where
                -- the interval and any date span of the periodic transaction with longest period
                (intervl, spn) =
                  case budgetpts of
                    []  -> (Days 1, nulldatespan)
                    pts -> (ptinterval pt, ptspan pt)
                      where pt = maximumBy (comparing ptinterval) pts  -- PARTIAL: maximumBy won't fail
                -- the natural start of this interval on or before the journal/report start
                intervalstart = intervalBoundaryBefore intervl d
                -- the natural interval start before the journal/report start,
                -- or the rule-specified start if later,
                -- but no later than the journal/report start.
                d' = min d $ maybe intervalstart (max intervalstart) $ spanStart spn

    -- select periodic transactions matching a pattern
    -- (the argument of the (final) --budget option).
    -- XXX two limitations/wishes, requiring more extensive type changes:
    -- - give an error if pat is non-null and matches no periodic txns
    -- - allow a regexp or a full hledger query, not just a substring
    pat = fromMaybe "" $ dbg3 "budget pattern" $ T.toLower <$> budgetpat_ ropts
    budgetpts = [pt | pt <- jperiodictxns j, pat `T.isInfixOf` T.toLower (ptdescription pt)]
    budgetts =
      dbg5 "budget goal txns" $
      [makeBudgetTxn t
      | pt <- budgetpts
      , t <- runPeriodicTransaction False pt budgetspan
      ]
    makeBudgetTxn t = txnTieKnot $ t { tdescription = T.pack "Budget transaction" }

-- | Adjust a journal's account names for budget reporting, in two ways:
--
-- 1. accounts with no budget goal anywhere in their ancestry are moved
--    under the "unbudgeted" top level account.
--
-- 2. subaccounts with no budget goal are merged with their closest parent account
--    with a budget goal, so that only budgeted accounts are shown.
--    This can be disabled by -E/--empty.
--
journalWithBudgetAccountNames :: S.Set AccountName -> Bool -> Journal -> Journal
journalWithBudgetAccountNames budgetedaccts showunbudgeted j =
  dbg5With (("budget account names: "++).pshow.journalAccountNamesUsed) $
  j { jtxns = remapTxn <$> jtxns j }
  where
    remapTxn = txnTieKnot . transactionTransformPostings remapPosting
    remapPosting p = p { paccount = remapAccount $ paccount p, poriginal = poriginal p <|> Just p }
    remapAccount a
      | a `S.member` budgetedaccts = a
      | Just p <- budgetedparent   = if showunbudgeted then a else p
      | otherwise                  = if showunbudgeted then u <> acctsep <> a else u
      where
        budgetedparent = find (`S.member` budgetedaccts) $ parentAccountNames a
        u = unbudgetedAccountName


-- tests

tests_BudgetReport = testGroup "BudgetReport" [
 ]
