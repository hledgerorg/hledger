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

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Message qualified as Msg
import Hledger.Cli.CompoundBalanceCommand

balancesheetSpec = CompoundBalanceCommandSpec {
  cbcdoc      = $(embedFileRelative "Hledger/Cli/Commands/Balancesheet.txt"),
  cbctitle    = Msg.Noun Msg.BalanceSheet,
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
    ],
  cbcaccum     = Historical
}

balancesheetmode :: Mode RawOpts
balancesheetmode = compoundBalanceCommandMode balancesheetSpec

balancesheet :: CliOpts -> Journal -> IO ()
balancesheet = compoundBalanceCommand balancesheetSpec
