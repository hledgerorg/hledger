{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TemplateHaskell   #-}
{-|

The @balancesheetequity@ command prints a simple balance sheet.

-}

module Hledger.Cli.Commands.Balancesheetequity (
  balancesheetequitymode
 ,balancesheetequity
) where

import System.Console.CmdArgs.Explicit

import Hledger.Utils.I18n (i18n)
import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.CompoundBalanceCommand

balancesheetequitySpec = CompoundBalanceCommandSpec {
  cbcdoc      = $(embedFileRelative "Hledger/Cli/Commands/Balancesheetequity.txt"),
  -- TRANSLATORS: the report title, with its reporting interval if any. Each is a
  -- whole phrase, so put the words in the order and form your language needs.
  cbctitle    = \case
    NoInterval -> i18n "Balance Sheet With Equity"
    Days 1     -> i18n "Daily Balance Sheet With Equity"
    Weeks 1    -> i18n "Weekly Balance Sheet With Equity"
    Weeks 2    -> i18n "Biweekly Balance Sheet With Equity"
    Months 1   -> i18n "Monthly Balance Sheet With Equity"
    Months 2   -> i18n "Bimonthly Balance Sheet With Equity"
    Months 3   -> i18n "Quarterly Balance Sheet With Equity"
    Months 6   -> i18n "Half-yearly Balance Sheet With Equity"
    Years 1    -> i18n "Yearly Balance Sheet With Equity"
    Years 2    -> i18n "Biennial Balance Sheet With Equity"
    _          -> i18n "Periodic Balance Sheet With Equity",
  cbcqueries  = [
     CBCSubreportSpec{
      cbcsubreporttitle=i18n "Assets"
     ,cbcsubreportquery=Type [Asset]
     ,cbcsubreportoptions=(\ropts -> ropts{normalbalance_=Just NormallyPositive})
     ,cbcsubreporttransform=id
     ,cbcsubreportincreasestotal=True
     }
    ,CBCSubreportSpec{
      cbcsubreporttitle=i18n "Liabilities"
     ,cbcsubreportquery=Type [Liability]
     ,cbcsubreportoptions=(\ropts -> ropts{normalbalance_=Just NormallyNegative})
     ,cbcsubreporttransform=fmap maNegate
     ,cbcsubreportincreasestotal=False
     }
    ,CBCSubreportSpec{
      cbcsubreporttitle=i18n "Equity"
     ,cbcsubreportquery=Type [Equity]
     ,cbcsubreportoptions=(\ropts -> ropts{normalbalance_=Just NormallyNegative})
     ,cbcsubreporttransform=fmap maNegate
     ,cbcsubreportincreasestotal=False
     }
    ],
  cbcaccum     = Historical
}

balancesheetequitymode :: Mode RawOpts
balancesheetequitymode = compoundBalanceCommandMode balancesheetequitySpec

balancesheetequity :: CliOpts -> Journal -> IO ()
balancesheetequity = compoundBalanceCommand balancesheetequitySpec
