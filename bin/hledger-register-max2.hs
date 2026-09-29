#!/usr/bin/env stack
-- stack runghc --verbosity error --package hledger
-- stack runghc --verbosity error --package hledger --package hledger-lib --package text --package safe 
-- stack script --compile --resolver nightly-2026-06-01 --verbosity error --package hledger --package text
-- stack script --compile --resolver nightly-2026-06-01 --verbosity error --package hledger --package hledger-lib --package text --package safe
-- The topmost stack command above is used to run this script.
-- stack script uses released hledger, stack runghc uses local hledger source.
-- This script currently requires local hledger source, for Hledger.Cli.Script.
------------------------------------78----------------------------------------

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}

import Hledger.Cli.Script
import qualified "text" Data.Text as T
import qualified "text" Data.Text.IO as T

cmdmode = hledgerCommandMode (unlines
    -- Command name, then --help text. Note, empty help lines get stripped.
  ["register-match"
  ,"Show the register item(s) with maximum (or with --invert, minimum) balance."
  ,"Usage: hledger-register-max [REGISTERARGS]"
  ,"or:    hledger register-max -- [REGISTERARGS]"
  ,"For historical balances, add -H. For value, add -V --infer-market-prices."
  ,"Examples:"
  ,"$ hledger-register-max -f examples/bcexample.journal -H checking"
  ,"2013-01-03 Payroll  Assets:US:BofA:Checking  1350.60 USD  8799.22 USD"
    ------------------------------------78----------------------------------------
  ])
  [] [generalflagsgroup1] [] ([], Just $ argsFlag "[ARGS]")  -- or Nothing

main = do
  opts@CliOpts{reportspec_=rspec} <- getHledgerCliOpts cmdmode
  withJournal opts $ \j -> do
    let
      r = postingsReport rspec j
      maxbal = fifth5 $ maximumBy (comparing fifth5) r
      is = filter ((== maxbal).fifth5) r
    mapM_ printItem is

printItem (_, _, _, p, bal) = do
  let
    d      = postingDate p
    mt     = ptransaction p
    desc   = fmt  30 $ maybe "-" tdescription mt
    acct   = fmt  30 $ paccount p
    amt    = fmta 12 $ T.pack $ showMixedAmountOneLine $ pamount p
    baltxt = fmta 12 $ T.pack $ showMixedAmountOneLine bal
  T.putStrLn $ T.unwords [showDate d, desc, "", acct, "", amt, " ", baltxt]
  where
    fmt w  = formatText True (Just w) (Just w) . textElideRight w
    fmta w = formatText False (Just w) Nothing
