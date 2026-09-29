#!/usr/bin/env stack
-- stack runghc --verbosity error --package hledger --package hledger-lib --package text --package safe 
-- (use the local hledger source)
-- -- stack script --compile --resolver nightly-2026-06-01 --verbosity info --package hledger --package text
-- -- (use a released hledger from stackage)

-- A custom compound report - like incomestatement but with different,
-- customisable subheadings/subreports. More verbose and haskelly than
-- hledger-report1.sh but also more robust and powerful.

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}

import Hledger.Cli.Script
import qualified "text" Data.Text as T
import qualified "text" Data.Text.IO as T

cmdmode = hledgerCommandMode (unlines
  ["report1"
  ,"A custom compound report - like the incomestatement command but easier to  customise."
  ,"Usage: hledger-report1 [OPTS] [ARGS]"
  ,"or:    hledger report1 -- [OPTS] [ARGS]"
  ]) [] [generalflagsgroup1] [] ([], Just $ argsFlag "[ARGS]")

main = do
  opts@CliOpts{reportspec_=rspec} <- getHledgerCliOpts cmdmode
  withJournal opts $ flip compoundBalanceCommand opts $

    -- see https://hackage.haskell.org/package/hledger/docs/Hledger-Cli-CompoundBalanceCommand.html
    -- and https://hackage.haskell.org/package/hledger-lib-1.31/docs/Hledger-Query.html
    CompoundBalanceCommandSpec {
      cbcdoc     = "report1 help text",
      cbctitle   = "Report1 Statement",
      cbcaccum   = PerPeriod,
      cbcqueries = [

         CBCSubreportSpec{
            cbcsubreporttitle="Revenues"
          ,cbcsubreportquery=Type [Revenue]
          ,cbcsubreportoptions=(\ropts -> ropts{normalbalance_=Just NormallyNegative})
          ,cbcsubreporttransform=fmap maNegate
          ,cbcsubreportincreasestotal=True
          }

        ,CBCSubreportSpec{
            cbcsubreporttitle="Operating Expenses"
          ,cbcsubreportquery=And [Type [Expense], Acct $ toRegex' "Operating"]
          ,cbcsubreportoptions=(\ropts -> ropts{normalbalance_=Just NormallyPositive})
          ,cbcsubreporttransform=id
          ,cbcsubreportincreasestotal=False
          }

        ,CBCSubreportSpec{
            cbcsubreporttitle="Other Expenses"
          ,cbcsubreportquery=And [Type [Expense], Not $ Acct $ toRegex' "Operating"]
          ,cbcsubreportoptions=(\ropts -> ropts{normalbalance_=Just NormallyPositive})
          ,cbcsubreporttransform=id
          ,cbcsubreportincreasestotal=False
          }
        ]

    }
