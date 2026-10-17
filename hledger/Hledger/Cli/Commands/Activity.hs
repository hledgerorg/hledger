{-# LANGUAGE TemplateHaskell #-}

{-|

Show a bar chart of transaction counts per week, or other report interval.
With --postings, show posting counts by account instead;
this is a shortcut for @balance --count --chart -W@.

-}

module Hledger.Cli.Commands.Activity
where

import Data.Maybe (fromMaybe)
import System.Console.CmdArgs.Explicit (flagNone)

import Hledger
import Hledger.Cli.Chart (chartWidthFlag)
import Hledger.Cli.CliOptions
import Hledger.Cli.Commands.Balance (balance)

activitymode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Activity.txt")
  [ outputFormatFlag ["txt","svg","html","csv","tsv","json"]
  , outputFileFlag
  , chartWidthFlag
  , flagNone ["txns"] (setboolopt "txns") "count transactions, showing just the total (default)"
  , flagNone ["postings"] (setboolopt "postings") "count postings, showing each account's count"
  , flagNone ["sort-amount","S"] (setboolopt "sort-amount") "with --postings, sort accounts by posting count, largest first"
  , flagNone ["total","T"] (setboolopt "row-total") "show the total count, below the chart"
  , flagNone ["average","A"] (setboolopt "average") "show the average count per period, below the chart (and as a line in SVG charts)"
  ]
  cligeneralflagsgroups1
  hiddenflags
  ([], Just $ argsFlag "[QUERY]")

-- | Show a bar chart of the number of transactions per report interval (weekly by default),
-- as a single total (like depth 0), since a transaction's postings may be in several accounts.
-- Or with --postings, the number of postings, by account.
-- This runs the balance command with --count (or its transaction-counting equivalent) and --chart.
-- If both --txns and --postings are given, the last one wins.
activity :: CliOpts -> Journal -> IO ()
activity opts@CliOpts{rawopts_, reportspec_=rspec@ReportSpec{_rsReportOpts=ropts}} j = do
  rspec' <- either fail return $ updateReportSpec ropts' rspec
  balance opts
    { rawopts_    = setopt "chart" "auto" rawopts_
    , reportspec_ = rspec'
    } j
  where
    txns = fromMaybe True $ choiceopt countopt rawopts_
      where
        countopt "txns"     = Just True
        countopt "postings" = Just False
        countopt _          = Nothing
    ropts' = ropts
      { balancecalc_ = if txns then CalcTransactionsCount else CalcPostingsCount
      , interval_    = if interval_ ropts == NoInterval then Weeks 1 else interval_ ropts
      , depth_       = if txns then DepthSpec (Just 0) [] else depth_ ropts
      }
