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
 ,balancesheetequitySpec
) where

import System.Console.CmdArgs.Explicit

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.CompoundBalanceCommand

balancesheetequitySpec :: CompoundBalanceCommandSpec
balancesheetequitySpec = CompoundBalanceCommandSpec {
  cbcdoc      = $(embedFileRelative "Hledger/Cli/Commands/Balancesheetequity.txt"),
  cbctitle    = "Balance Sheet With Equity",
  cbcqueries  = [
     CBCSubreportSpec{
      cbcsubreporttitle="Assets"
     ,cbcsubreportquery=Type [Asset]
     ,cbcsubreportoptions=(\ropts -> ropts{normalbalance_=Just NormallyPositive})
     ,cbcsubreporttransform=id
     ,cbcsubreportincreasestotal=True
     }
    ,CBCSubreportSpec{
      cbcsubreporttitle="Liabilities"
     ,cbcsubreportquery=Type [Liability]
     ,cbcsubreportoptions=(\ropts -> ropts{normalbalance_=Just NormallyNegative})
     ,cbcsubreporttransform=fmap maNegate
     ,cbcsubreportincreasestotal=False
     }
    ,CBCSubreportSpec{
      cbcsubreporttitle="Equity"
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
