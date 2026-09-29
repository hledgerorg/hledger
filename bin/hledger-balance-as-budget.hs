#!/usr/bin/env stack
-- stack runghc --verbosity info --package hledger
-- Run from inside the hledger source tree, or compile with compile.sh.
-- See hledger-check-fancyassertions.hs.

-- {-# OPTIONS_GHC -Wno-missing-signatures #-}

{-| Construct two balance reports for two different time periods and use one of the as "budget" for
    the other, thus comparing them
-}
import Data.Text.Lazy.IO as TL
import System.Environment (getArgs)
import Hledger.Cli.Script
import Hledger.Cli.Commands.Balance
import qualified Data.Map as Map
import Data.List (sortOn)

------------------------------------------------------------------------------
cmdmode = hledgerCommandMode
  (unlines ["balance-as-budget"
           ,"Generate two balance reports and use first of them as budget for the second."
           ," "
           ,"Pass two sets of hledger-compatible options, separated by --."
           ,"For example, to use Jan 2019 as budget for Jan 2020, use:"
           ,"-f 2019.journal -p 2019-01 -- -f 2020.journal -p 2020-01"
           ," "
           ,"Display features in the report are driven by the second set of args"
           ])
  []
  [generalflagsgroup1]
  []
  ([], Just $ argsFlag "[QUERY]")
------------------------------------------------------------------------------

main :: IO ()
main = do
  args <- getArgs
  let report1args = takeWhile (/= "--") args
  let report2args = drop 1 $ dropWhile (/= "--") args

  -- Get options for both reports
  opts1@CliOpts{reportspec_=rspec1} <- getHledgerCliOpts' balancemode report1args
  opts2@CliOpts{reportspec_=rspec2} <- getHledgerCliOpts' balancemode report2args

  withJournal opts1 $ \j1 -> do
    withJournal opts2 $ \j2 -> do
      -- Generate both reports with their respective date periods
      let report1 = multiBalanceReport rspec1 j1  -- budget
          report2 = multiBalanceReport rspec2 j2  -- actual
          ropts2 = _rsReportOpts rspec2
          styles = journalCommodityStylesWith HardRounding j2

      -- Combine the reports (using report2's date periods for display)
      let combined = combineBudgetAndActual ropts2 j2 report1 report2

      writeOutputLazyText opts2 $ budgetReportAsText ropts2 $ styleAmounts styles $ combined

-- | Combine two MultiBalanceReports into a BudgetReport, comparing them side by side.
-- The budget report uses the date periods from the actual (second) report.
combineBudgetAndActual :: ReportOpts -> Journal -> MultiBalanceReport -> MultiBalanceReport -> BudgetReport
combineBudgetAndActual ropts j
      (PeriodicReport budgetperiods budgetrows (PeriodicReportRow _ budgettots budgetgrandtot budgetgrandavg))
      (PeriodicReport actualperiods actualrows (PeriodicReportRow _ actualtots actualgrandtot actualgrandavg)) =
    PeriodicReport actualperiods combinedrows totalrow
  where
    -- Build maps of amounts by account name
    budgetMap = Map.fromList
      [ (prrFullName row, (prrAmounts row, prrTotal row, prrAverage row))
      | row <- budgetrows
      ]
    actualMap = Map.fromList
      [ (prrFullName row, (prrAmounts row, prrTotal row, prrAverage row))
      | row <- actualrows
      ]

    -- Accounts with actual amounts (and their budgets if available)
    actualWithBudget =
      [ PeriodicReportRow acct cells total avg
      | PeriodicReportRow acct actualamts actualtot actualavg <- actualrows
      , let budgetamts = maybe (replicate (length actualperiods) Nothing) (\(amts, _, _) -> map Just amts)
                              (Map.lookup (displayFull acct) budgetMap)
      , let cells = zip (map Just actualamts) budgetamts
      , let total = (Just actualtot, fmap (\(_, t, _) -> t) (Map.lookup (displayFull acct) budgetMap))
      , let avg = (Just actualavg, fmap (\(_, _, a) -> a) (Map.lookup (displayFull acct) budgetMap))
      ]

    -- Budget-only accounts (no actual amounts)
    budgetOnly =
      [ PeriodicReportRow acct cells total avg
      | PeriodicReportRow acct budgetamts budgettot budgetavg <- budgetrows
      , let acctName = displayFull acct
      , not (acctName `Map.member` actualMap)  -- Only include if not in actual
      , let cells = zip (replicate (length actualperiods) (Just nullmixedamt)) (map Just budgetamts)
      , let total = (Just nullmixedamt, Just budgettot)
      , let avg = (Just nullmixedamt, Just budgetavg)
      ]

    -- Combine and sort all rows by account name
    combinedrows = sortOn prrFullName (actualWithBudget ++ budgetOnly)

    totalrow = PeriodicReportRow ()
      (zip (map Just actualtots) (map Just budgettots))
      (Just actualgrandtot, Just budgetgrandtot)
      (Just actualgrandavg, Just budgetgrandavg)
