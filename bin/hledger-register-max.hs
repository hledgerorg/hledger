#!/usr/bin/env stack
-- stack runghc
-- (requires hledger > 1.34)
-- -- stack script --compile --resolver nightly-2026-06-01 --verbosity error --package hledger-lib --package hledger --package text --package safe

-- hledger-register-max - runs "hledger register" and prints the posting with largest running total/balance.
-- Usage:
-- hledger-register-max [REGISTERARGS]
-- hledger register-max -- [REGISTERARGS]
-- For historical balances, add -H. To see the smallest, add --invert. For value, add -V --infer-market-prices, etc.

-- Examples:
-- $ hledger-register-max -f examples/bcexample.journal -H checking
-- 2013-01-03 Hoogle | Payroll                Assets:US:BofA:Checking                    1350.60 USD    8799.22 USD
-- $ hledger register-max -- -f examples/bcexample.journal income --invert
-- 2014-10-09 Hoogle | Payroll                Income:US:Hoogle:Vacation                   4.62 VACHR   52000.00 IRAUSD, 365071.44 USD, 337.26 VACHR


{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}

import Control.Monad
import Data.List
import Data.Maybe
import Data.Ord
import qualified "text" Data.Text as T
import Data.Text.IO qualified as T
import Safe
import System.Environment
import Hledger.Cli.Script

-- XXX needs --help, see hledger-addon-example.hs

main = do
  args <- getArgs
  opts <- argsToCliOpts ("register" : args) []
  withJournal opts $ \j -> do
    let
      r = postingsReport (reportspec_ opts) j
      getamt = pamount.fourth5
      maxbal = getamt $ maximumBy (comparing getamt) r
      is = filter ((== maxbal).getamt) r
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
