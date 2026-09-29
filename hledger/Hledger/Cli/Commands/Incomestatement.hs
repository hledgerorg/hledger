{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-|

The @incomestatement@ command prints a simple income statement (profit & loss report).

-}

module Hledger.Cli.Commands.Incomestatement (
  incomestatementmode
 ,incomestatement
) where

import System.Console.CmdArgs.Explicit

import Hledger.Utils.I18n (i18n)
import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.CompoundBalanceCommand

incomestatementSpec = CompoundBalanceCommandSpec {
  cbcdoc      = $(embedFileRelative "Hledger/Cli/Commands/Incomestatement.txt"),
  -- TRANSLATORS: the report title, with its reporting interval if any. Each is a
  -- whole phrase, so put the words in the order and form your language needs.
  cbctitle    = \case
    NoInterval -> i18n "Income Statement"
    Days 1     -> i18n "Daily Income Statement"
    Weeks 1    -> i18n "Weekly Income Statement"
    Weeks 2    -> i18n "Biweekly Income Statement"
    Months 1   -> i18n "Monthly Income Statement"
    Months 2   -> i18n "Bimonthly Income Statement"
    Months 3   -> i18n "Quarterly Income Statement"
    Months 6   -> i18n "Half-yearly Income Statement"
    Years 1    -> i18n "Yearly Income Statement"
    Years 2    -> i18n "Biennial Income Statement"
    _          -> i18n "Periodic Income Statement",
  cbcqueries  = [
     CBCSubreportSpec{
      cbcsubreporttitle=i18n "Revenues"
     ,cbcsubreportquery=Type [Revenue]
     ,cbcsubreportoptions=(\ropts -> ropts{normalbalance_=Just NormallyNegative})
     ,cbcsubreporttransform=fmap maNegate
     ,cbcsubreportincreasestotal=True
     }
    ,CBCSubreportSpec{
      cbcsubreporttitle=i18n "Expenses"
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
 
