{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TemplateHaskell   #-}
{-|

The @cashflow@ command prints a simplified cashflow statement.  It just
shows the change in all "cash" accounts for the period (without the
traditional segmentation into operating, investing, and financing
cash flows.)

-}

module Hledger.Cli.Commands.Cashflow (
  cashflowmode
 ,cashflow
) where

import System.Console.CmdArgs.Explicit

import Hledger.Utils.I18n (i18n)
import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.CompoundBalanceCommand

cashflowSpec = CompoundBalanceCommandSpec {
  cbcdoc      = $(embedFileRelative "Hledger/Cli/Commands/Cashflow.txt"),
  cbctitle    = i18n "Cashflow Statement",
  cbcqueries  = [
     CBCSubreportSpec{
      cbcsubreporttitle=i18n "Cash flows"
     ,cbcsubreportquery=Type [Cash]
     ,cbcsubreportoptions=(\ropts -> ropts{normalbalance_= Just NormallyPositive})
     ,cbcsubreporttransform=id
     ,cbcsubreportincreasestotal=True
     }
    ],
  cbcaccum     = PerPeriod
}

cashflowmode :: Mode RawOpts
cashflowmode = compoundBalanceCommandMode cashflowSpec

cashflow :: CliOpts -> Journal -> IO ()
cashflow = compoundBalanceCommand cashflowSpec
