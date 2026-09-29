{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TemplateHaskell   #-}
{-|

The @balancesheet@ command prints a simple balance sheet.

-}

module Hledger.Cli.Commands.Balancesheet (
  balancesheetmode
 ,balancesheet
) where

import System.Console.CmdArgs.Explicit

import Hledger.Utils.I18n (i18n)
import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.CompoundBalanceCommand

balancesheetSpec = CompoundBalanceCommandSpec {
  cbcdoc      = $(embedFileRelative "Hledger/Cli/Commands/Balancesheet.txt"),
  -- TRANSLATORS: the report title, with its reporting interval if any. Each is a
  -- whole phrase, so put the words in the order and form your language needs.
  cbctitle    = \case
    NoInterval -> i18n "Balance Sheet"
    Days 1     -> i18n "Daily Balance Sheet"
    Weeks 1    -> i18n "Weekly Balance Sheet"
    Weeks 2    -> i18n "Biweekly Balance Sheet"
    Months 1   -> i18n "Monthly Balance Sheet"
    Months 2   -> i18n "Bimonthly Balance Sheet"
    Months 3   -> i18n "Quarterly Balance Sheet"
    Months 6   -> i18n "Half-yearly Balance Sheet"
    Years 1    -> i18n "Yearly Balance Sheet"
    Years 2    -> i18n "Biennial Balance Sheet"
    _          -> i18n "Periodic Balance Sheet",
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
    ],
  cbcaccum     = Historical
}

balancesheetmode :: Mode RawOpts
balancesheetmode = compoundBalanceCommandMode balancesheetSpec

balancesheet :: CliOpts -> Journal -> IO ()
balancesheet = compoundBalanceCommand balancesheetSpec
