#!/usr/bin/env stack
-- stack runghc --verbosity info --package hledger
-- Run from inside the hledger source tree, or compile with compile.sh.
-- See hledger-check-fancyassertions.hs.

{- Construct two balance reports for two different time periods and render them side by side -}

{-# OPTIONS_GHC -Wno-missing-signatures #-}

import System.Environment (getArgs)
import Hledger.Cli.Script
import Data.Map qualified as M
import Data.Map.Merge.Strict
import Data.Text.Lazy.IO qualified as TL

appendReports :: MultiBalanceReport -> MultiBalanceReport -> MultiBalanceReport
appendReports r1 r2 =
  PeriodicReport
  { prDates = prDates r1 ++ prDates r2
  , prRows = map snd $ M.toAscList mergedRows
  , prTotals = mergeRows (prTotals r1) (prTotals r2)
  }
  where
    rowsByAcct report = M.fromList $ map (\r -> (prrName r, r)) (prRows report)
    r1map = rowsByAcct r1
    r2map = rowsByAcct r2

    mergedRows = merge (mapMissing left) (mapMissing right) (zipWithMatched both) r1map r2map
    left _ row = row{prrAmounts = prrAmounts row ++ [nullmixedamt]}
    right _ row = row{prrAmounts = nullmixedamt:(prrAmounts row) }
    both _ = mergeRows

    -- name/depth in the second row would be the same by contruction
    mergeRows (PeriodicReportRow name amt1 tot1 avg1) (PeriodicReportRow _ amt2 tot2 avg2) =
      PeriodicReportRow { prrName = name
        , prrAmounts = amt1++amt2
        , prrTotal = tot1 `maPlus` tot2
        , prrAverage = averageMixedAmounts [avg1,avg2]
        }

------------------------------------------------------------------------------
cmdmode = hledgerCommandMode
  (unlines ["combine-balances"
           ,"Generate two balance reports and render them side by side."
           ,"(Dates in headers could look funky.)"
           ," "
           ,"Pass two sets of hledger-compatible options, separated by --."
           ,"For example, to see Jan 2019 and Jan 2020 together, use:"
           ,"-f 2019.journal -p 2019-01 -- -f 2020eaf.journal -p 2020-01"
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
  (_,report1) <- mbReport report1args
  (rspec2,report2) <- mbReport report2args
  let merged = appendReports report1 report2
  TL.putStrLn $ multiBalanceReportAsText (_rsReportOpts rspec2) merged
  where
    mbReport args = do
      opts@CliOpts{reportspec_=rspec} <- getHledgerCliOpts' cmdmode args
      report <- withJournal opts (return . multiBalanceReport rspec)
      return (rspec,report)
