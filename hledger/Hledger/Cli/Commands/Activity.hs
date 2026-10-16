{-# LANGUAGE TemplateHaskell #-}

{-|

Show a bar chart of posting counts per week, or other report interval.
This is a shortcut for @balance --count --chart -W@.

-}

module Hledger.Cli.Commands.Activity
where

import Hledger
import Hledger.Cli.Chart (chartWidthFlag)
import Hledger.Cli.CliOptions
import Hledger.Cli.Commands.Balance (balance)

activitymode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Activity.txt")
  [ outputFormatFlag ["txt","svg","html","csv","tsv","json"]
  , outputFileFlag
  , chartWidthFlag
  ]
  cligeneralflagsgroups1
  hiddenflags
  ([], Just $ argsFlag "[QUERY]")

-- | Show a bar chart of the number of postings per report interval (weekly by default), by account,
-- by running the balance command with --count and --chart.
activity :: CliOpts -> Journal -> IO ()
activity opts@CliOpts{rawopts_, reportspec_=rspec@ReportSpec{_rsReportOpts=ropts}} =
  balance opts
    { rawopts_    = setopt "chart" "auto" rawopts_
    , reportspec_ = rspec{_rsReportOpts = ropts
        { balancecalc_ = CalcPostingsCount
        , interval_    = if interval_ ropts == NoInterval then Weeks 1 else interval_ ropts
        }}
    }
