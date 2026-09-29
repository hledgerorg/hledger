#!/usr/bin/env stack
-- stack runghc --verbosity info
--   --package hledger --package string-qq --package text --package time --package microlens
--
-- Using unreleased hledger: from inside the hledger source tree,
--
-- Run interpreted:
-- bin/hledger-move.hs
--
-- Compile:
-- stack ghc -- bin/hledger-move.hs -ihledger-lib -ihledger
-- or use bin/compile.sh
--
-- Debug:
-- stack ghci bin/hledger-move.hs --ghc-options=-'ihledger-lib -ihledger'
--
-- Watch compilation:
-- stack exec ghcid bin/hledger-move.hs -- --command="ghci -ihledger-lib -ihledger"
--
-- There are some tests in hledger/test/_move.test

{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}

import Control.Monad (when)
import Data.Function (on)
import Data.List (find, groupBy, mapAccumL)
import Data.Maybe (fromMaybe, isNothing)
import Data.String.QQ (s)
import Data.Time (addDays)
import Safe (headDef)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)
import System.IO.Unsafe (unsafePerformIO)
import Lens.Micro ((^.))
import Text.Printf
import Data.Text qualified as T
import Data.Text.IO qualified as T

import Hledger.Cli.Script

------------------------------------------------------------------------------
cmdmode = hledgerCommandMode
  -- Command name and help text goes here. Note blank lines will not be displayed.
  [s| hledger-move
Print an entry to move funds between accounts, preserving costs and subaccounts
.
Usage: hledger-move AMT FROMACCT TOACCT
.
This command prints a journal entry which you can add to your journal,
representing a transfer of some amount from a source account (and/or
its subaccounts) to a destination account.
It is mainly intended for moving assets, especially investment assets
with subaccounts representing lots.
.
AMT is a positive hledger amount, including a commodity symbol.
.
FROMACCT is the source account (an account name, or a regular expression
whose alphanumerically first match is the source account).
.
TOACCT is the destination account (or account-matching regexp).
.
This command can also transfer from, and to, child accounts.
It will move amounts first out of FROMACCT if possible,
then as needed out of its subaccounts in alphanumerical order,
until the total requested amount is moved.
Ie, if subaccounts are named by acquisition date (eg ":YYYYMMDD"),
they will be withdrawn in FIFO order.
.
Any subaccounts withdrawn from will be recreated under TOACCT,
unless the --consolidate flag is used. With --consolidate,
all amounts are transferred to TOACCT, discarding lot information.
.
If there is not a sufficient positive balance in FROMACCT and its subaccounts
to supply the requested amount, the command will fail.
.
Examples:
.
$ hledger-move $50 assets:checking assets:cash  # withdraw cash from bank
$ hledger-move ADA1000 ada:wallet1 ada:wallet2  # move 1000 ADA, keeping lots
|]
{- NOT YET IMPLEMENTED:

- As a convenience, no symbol means "move the account's only commodity";
this works when the source account contains just one commodity.
$ hledger-move 50 checking cash                 # the same, less typing

- A zero AMT means "move all of the specified commodity".
$ hledger-move $0 checking cash                 # move all $ from checking

- The "all" AMT does the same, but for any and all commodities present,
without having to write the commodity symbol(s).
It requires that all of the source account's commodities are positive.
$ hledger-move all savings checking             # move all from savings
$ hledger-move all assets:broker1:FOO assets:broker2:FOO  # move all FOO lots to broker2

- It is aware of account balances, and prevents overdraft or overpay:
  it will fail if the requested transfer would change
  the source account's balance from positive to negative (as when overdrawing an asset)
  or the destination account's balance from negative to positive (as when over-paying a liability).
  You can disable this validation by adding the --force flag.

- balance assertions

- respecting end date, for calculating balances and generated txn date

-}

------------------------------------------------------------------------------
  [flagNone ["consolidate"]   (setboolopt "consolidate") "don't recreate subaccounts"
  -- ,flagNone ["force"]         (setboolopt "force") "don't prevent overdraw/overpay"
  ]
  [generalflagsgroup1]
  []
  ([arg "AMT"
   ,arg "FROMACCT"
   ,arg "TOACCT"
   ], 
   Nothing
  )
  where
    arg name = flagArg (\val rawopts -> Right $ setopt name val rawopts) name
------------------------------------------------------------------------------

main :: IO ()
main = do
  copts@CliOpts{rawopts_=rawopts, reportspec_=rspec0} <- getHledgerCliOpts cmdmode
  withJournal copts $ \j -> do
    -- d <- getCurrentDay
    let
      -- arg errors
      -- clunky
      shortusage = "Usage: hledger-move AMT FROMACCT TOACCT"
      longusage  = unlines
        [ shortusage
        , "AMT       the total amount to move, as a hledger amount with commodity symbol"
        , "FROMACCT  the main account to move it from; subaccounts can also be drained"
        , "TOACCT    the main account to move it to; subaccounts can be recreated here"
        ]
      -- No args should show usage, not "Error:" (but I guess still needs a failure exit code)
      exitUsage = unsafePerformIO $ hPutStrLn stderr longusage >> exitFailure
      mamtarg      = maybestringopt "AMT" rawopts
      mfromacctarg = maybestringopt "FROMACCT" rawopts
      mtoacctarg   = maybestringopt "TOACCT" rawopts
      noargs       = all isNothing [mamtarg, mfromacctarg, mtoacctarg]
      amtarg       = fromMaybe (error' $ "Please specify the amount to move as first argument.\n"++shortusage) mamtarg  -- won't happen
      fromacctarg  = fromMaybe (error' $ "Please specify a source account name or pattern as second argument.\n"++shortusage) mfromacctarg
      toacctarg    = fromMaybe (error' $ "Please specify a destination account name or pattern as third argument.\n"++shortusage) mtoacctarg

      consolidate = boolopt "consolidate" rawopts
      force       = boolopt "force" rawopts

      -- parse the AMT arg as a cost-less Amount (any provided cost is ignored)
      eamt = styleAmounts (journalCommodityStyles j) . amountStripCost <$> parseamount amtarg
      amt = case eamt of
        Left err ->
          error' $ "could not parse " ++ show amtarg ++ " as a hledger amount\n" ++ customErrorBundlePretty err ++ "\n" ++shortusage
        Right a | isNegativeAmount a ->
          error' $ amtarg ++ " is negative, please specify a positive amount to move.\n"++shortusage
        Right a -> a
      comm = acommodity amt
      -- when comparing with zero, it needs to have the same commodity
      zero = amt{aquantity=0}
      accts = journalAccountNamesDeclaredOrImplied j
      fromacct = amt `seq` fromMaybe (error' $ fromacctarg ++ " did not match any account.") $ firstMatch (T.pack fromacctarg) accts
      fromacctlen = length $ accountNameComponents fromacct
      toacct   = fromacct `seq` fromMaybe (error' $ toacctarg   ++ " did not match any account.") $ firstMatch (T.pack toacctarg) accts

      -- get account names and balances of fromacct and any subs, ordered by name
      ropts = (_rsReportOpts rspec0){balanceaccum_=Historical, accountlistmode_=ALFlat}
      rspec =
        setDefaultConversionOp NoConversionOp  -- ?
        rspec0{
           _rsReportOpts = ropts
          ,_rsQuery      = Acct $ accountNameToAccountRegex $ fromacct
          }
      acctbals = fst $ balanceReport rspec j
      availablebal =
        headDef zero $ amounts $
        filterMixedAmountByCommodity comm $
        mixedAmountStripCosts $ sum $ map fourth4 acctbals

      -- Take just enough of these account balances, in the order given,
      -- to cover the requested AMT. Or if there is not enough, take what is there.
      -- AMT is a single-commodity, cost-less amount.
      -- Account balances can be multi-commodity, but only AMT's commodity will be moved.
      -- An account balance could also possibly have multiple costs in that commodity;
      -- in that case we raise an error, for now. (Could take amounts in order of cost's
      -- commodity and amount).
      (unmoved, moveamts) = go (dbgamt "requested amt to move" amt) [] acctbals
        where
          dbgamt lbl  = id  -- dbg0With (((lbl++": ")++).showAmount)
          dbgmamt lbl = id  -- dbg0With (((lbl++": ")++).showMixedAmountOneLine)

          go :: Amount -> [(AccountName, MixedAmount)] -> [BalanceReportItem] -> (Amount, [(AccountName, MixedAmount)])
          go stilltomove balscollected [] = (stilltomove, reverse balscollected)
          go stilltomove balscollected ((acct,_,_,bal):rest)
            | stilltomovenext > zero = go stilltomovenext ((acct,balincomm) : balscollected) rest 
            | otherwise =
                let
                  -- the final balance portion to move
                  finalamt = dbgamt "final amt to move" $
                    (balincommsinglecost + stilltomovenext)
                      {acost=acost balincommsinglecost}  -- + discards cost, need to restore it
                in (0, reverse $ (acct, mixed [finalamt]) : balscollected)
            where
              -- how much of the requested commodity is in this account
              comm = acommodity stilltomove
              balincomm = filterMixedAmountByCommodity comm bal
              -- for now, ensure there is at most one cost basis (and convert to Amount)
              balincommsinglecost =
                case amounts $ balincomm of
                  [b] -> dbgamt ("acct balance in "++show comm) b
                  _   -> error' $ "sorry, we can't yet move funds out of a multi-cost balance ("
                            ++ showMixedAmountOneLine balincomm ++ ")"
              -- subtract this from the amount remaining to move (ignoring cost)
              stilltomovenext = dbgamt "remaining amt to move" $
                stilltomove - amountStripCost balincommsinglecost

      -- since balance assertion amounts are required to be exact, the
      -- amounts in opening/closing transactions should be too (#941, #1137)
      -- amountSetFullPrecision
      fromps = [
        posting{paccount = a
                ,pamount = mixedAmount $ negate b
                -- ,pbalanceassertion = Just nullassertion{baamount=precise b{aquantity=0, acost=Nothing}}
                }

        | -- get the balances for each commodity and transaction price
          (a,mixedb) <- moveamts
        , let bs0 = amounts mixedb
          -- mark the last balance in each commodity with True
        , let bs2 = concat [reverse $ zip (reverse bs1) (True : repeat False)
                            | bs1 <- groupBy ((==) `on` acommodity) bs0]
        , (b, islast) <- bs2
        ]

      tops = if consolidate
        then [
          posting{paccount = toacct, pamount = mixed [amt]}
          ]
        else [
          posting{paccount = a', pamount = negate b}
          | Posting{paccount=a, pamount=b} <- fromps
          , let subacctcomps = drop fromacctlen $ accountNameComponents a
          , let a' = accountNameFromComponents $ toacctcomps ++ subacctcomps
          ]
          where
            toacctcomps = accountNameComponents toacct

    if
      | noargs -> exitUsage
      | unmoved > zero -> error' $
        "could not move " ++ showAmount amt ++ ", only " ++ showAmount availablebal ++ " is available in commodity " ++ show comm 
      | otherwise ->
        T.putStr $ showTransaction $ nulltransaction{
          tdate        = _rsDay rspec
          ,tdescription = ""
          ,tpostings    = fromps ++ tops
        }

firstMatch :: T.Text -> [T.Text] -> Maybe T.Text
firstMatch pat vals =
  let re = toRegexCI' pat
  in find (regexMatchText re) vals
