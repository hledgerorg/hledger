{-# LANGUAGE LambdaCase        #-}
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
  -- TRANSLATORS: the report title, with its reporting interval if any. Each is a
  -- whole phrase, so put the words in the order and form your language needs.
  cbctitle    = \case
    NoInterval -> i18n "Cashflow Statement"
    Days 1     -> i18n "Daily Cashflow Statement"
    Weeks 1    -> i18n "Weekly Cashflow Statement"
    Weeks 2    -> i18n "Biweekly Cashflow Statement"
    Months 1   -> i18n "Monthly Cashflow Statement"
    Months 2   -> i18n "Bimonthly Cashflow Statement"
    Months 3   -> i18n "Quarterly Cashflow Statement"
    Months 6   -> i18n "Half-yearly Cashflow Statement"
    Years 1    -> i18n "Yearly Cashflow Statement"
    Years 2    -> i18n "Biennial Cashflow Statement"
    _          -> i18n "Periodic Cashflow Statement",
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
