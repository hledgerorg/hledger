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
  cbctitle    = i18n "Balance Sheet With Equity",
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
