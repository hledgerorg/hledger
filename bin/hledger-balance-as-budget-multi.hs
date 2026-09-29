#!/usr/bin/env stack
-- stack runghc --verbosity info --package hledger
-- Run from inside the hledger source tree, or compile with compile.sh.
-- See hledger-check-fancyassertions.hs.

-- {-# OPTIONS_GHC -Wno-missing-signatures #-}

{-| Construct two balance reports for two different time periods and use one of the as "budget" for
    the other, thus comparing them
-}
import Data.Text.Lazy.IO qualified as TL
import System.Environment (getArgs)
import Hledger.Cli.Script
import Hledger.Cli.Commands.Balance
import qualified Data.Map as Map
import Data.List (sortOn)

------------------------------------------------------------------------------
cmdmode = hledgerCommandMode
  (unlines ["balance-as-budget-multi"
           ,"Read two journal files and generate multiple balance reports that use first of them as budget for the second."
           ," "
           ,"Pass two journal names and a file that contains sets of 'hledger balance'-compatible options, one per line"
           ,"For example, to use Jan 2019 as budget for Jan 2020, use:"
           ,"2019.journal 2020.journal commands.txt"
           ,"and put '\"assets\" --depth 3 --value=$,then' in the commands.txt"
           ])
  []
  [generalflagsgroup1]
  []
  ([], Just $ argsFlag "BUDGET_JOURNAL ACTUAL_JOURNAL COMMAND_FILE")
------------------------------------------------------------------------------

main :: IO ()
main = do
  args <- getArgs
  case args of
    [budget_f, real_f, commands_f] -> runAllCommands budget_f real_f commands_f
    _ -> error' "expected exactly three arguments"

runAllCommands :: String -> String -> String -> IO ()
runAllCommands budget_f real_f commands_f = do
  d <- getCurrentDay
  budget <- readJournalFile' budget_f
  real <- readJournalFile' real_f
  let styles = journalCommodityStylesWith HardRounding real
  commands <- lines <$> readFile commands_f
  forM_ commands $ \command -> do
    let args = words' command
    case args of
      [] -> return ()
      "echo":args -> putStrLn $ unwords args
      _ -> do
        opts@CliOpts{reportspec_=rspec} <- getHledgerCliOpts' balancemode args
        let reportopts = _rsReportOpts rspec

        -- Generate both reports from their respective journals (unchanged)
        let budgetReport = multiBalanceReport rspec budget
            actualReport = multiBalanceReport rspec real

        -- Combine the reports
        let combined = combineBudgetAndActual reportopts real budgetReport actualReport

        writeOutputLazyText opts $ budgetReportAsText reportopts $ styleAmounts styles $ combined

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
