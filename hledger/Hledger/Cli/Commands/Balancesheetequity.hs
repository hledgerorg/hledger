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

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Message qualified as Msg
import Hledger.Cli.CompoundBalanceCommand

balancesheetequitySpec = CompoundBalanceCommandSpec {
  cbcdoc      = $(embedFileRelative "Hledger/Cli/Commands/Balancesheetequity.txt"),
  cbctitle    = Msg.Noun Msg.BalanceSheetWithEquity,
  cbcqueries  = [
     CBCSubreportSpec{
      cbcsubreporttitle=Msg.Assets
     ,cbcsubreportquery=Type [Asset]
     ,cbcsubreportoptions=(\ropts -> ropts{normalbalance_=Just NormallyPositive})
     ,cbcsubreporttransform=id
     ,cbcsubreportincreasestotal=True
     }
    ,CBCSubreportSpec{
      cbcsubreporttitle=Msg.Liabilities
     ,cbcsubreportquery=Type [Liability]
     ,cbcsubreportoptions=(\ropts -> ropts{normalbalance_=Just NormallyNegative})
     ,cbcsubreporttransform=fmap maNegate
     ,cbcsubreportincreasestotal=False
     }
    ,CBCSubreportSpec{
      cbcsubreporttitle=Msg.Equity
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
