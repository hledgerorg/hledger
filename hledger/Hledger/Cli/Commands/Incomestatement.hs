{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}
{-|

The @incomestatement@ command prints a simple income statement (profit & loss report).

-}

module Hledger.Cli.Commands.Incomestatement (
  incomestatementmode
 ,incomestatement
) where

import System.Console.CmdArgs.Explicit

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Message qualified as Msg
import Hledger.Cli.CompoundBalanceCommand

incomestatementSpec = CompoundBalanceCommandSpec {
  cbcdoc      = $(embedFileRelative "Hledger/Cli/Commands/Incomestatement.txt"),
  cbctitle    = Msg.Noun Msg.IncomeStatement,
  cbcqueries  = [
     CBCSubreportSpec{
      cbcsubreporttitle=Msg.Revenues
     ,cbcsubreportquery=Type [Revenue]
     ,cbcsubreportoptions=(\ropts -> ropts{normalbalance_=Just NormallyNegative})
     ,cbcsubreporttransform=fmap maNegate
     ,cbcsubreportincreasestotal=True
     }
    ,CBCSubreportSpec{
      cbcsubreporttitle=Msg.Expenses
     ,cbcsubreportquery=Type [Expense]
     ,cbcsubreportoptions=(\ropts -> ropts{normalbalance_=Just NormallyPositive})
     ,cbcsubreporttransform=id
     ,cbcsubreportincreasestotal=False
     }
    ],
  cbcaccum     = PerPeriod
}

incomestatementmode :: Mode RawOpts
incomestatementmode = compoundBalanceCommandMode incomestatementSpec

incomestatement :: CliOpts -> Journal -> IO ()
incomestatement = compoundBalanceCommand incomestatementSpec
{- 
Summary of code flow, 2021-11:

incomestatement
 compoundBalanceCommand
  compoundBalanceReport
   compoundBalanceReportWith
    colps = getPostingsByColumn
    startps = startingPostings
    generateSubreport
     startbals = startingBalances (startps restricted to this subreport)
     generateMultiBalanceReport startbals (colps restricted to this subreport)
      matrix = calculateReportMatrix startbals colps
      displaynames = displayedAccounts
      buildReportRows displaynames matrix
 -}
 
