{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE MultiWayIf #-}

module Hledger.Cli.Commands.Close (
  closemode
 ,close
)
where

import Data.Function (on)
import Data.List (groupBy)
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import Data.Time.Calendar (addDays)
import System.Console.CmdArgs.Explicit as C

import Hledger
import Hledger.Cli.CliOptions
import Safe (lastDef, readMay, readDef)
import System.FilePath (takeBaseName)
import Data.Char (isDigit)
import Hledger.Read.RulesReader (parseBalanceAssertionType)
import Hledger.Cli.Commands.Print (roundFlag, amountStylesSetRoundingFromRawOpts, layoutFlag, layoutFromRawOpts)

defclosedesc  = "closing balances"
defopendesc   = "opening balances"
defretaindesc = "retain earnings"

defcloseacct  = "equity:opening/closing balances"
defretainacct = "equity:retained earnings"

closemode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Close.txt")
  [flagOpt "" ["clopen"]     (\s opts -> Right $ setopt "clopen" s opts) "TAGVAL" "show closing and opening balances transactions, for AL accounts by default"
  ,flagOpt "" ["close"]      (\s opts -> Right $ setopt "close" s opts)  "TAGVAL" "show just a closing balances transaction"
  ,flagOpt "" ["open"]       (\s opts -> Right $ setopt "open" s opts)   "TAGVAL" "show just an opening balances transaction"
  ,flagOpt "" ["assert"]     (\s opts -> Right $ setopt "assert" s opts) "TAGVAL" "show a balance assertions transaction"
  ,flagOpt "" ["assign"]     (\s opts -> Right $ setopt "assign" s opts) "TAGVAL" "show a balance assignments transaction"
  ,flagOpt "" ["retain"]     (\s opts -> Right $ setopt "retain" s opts) "TAGVAL" "show a retain earnings transaction, for RX accounts by default"
  ,flagNone ["explicit","x"] (setboolopt "explicit")                              "show all amounts explicitly"
  ,flagNone ["show-costs"]   (setboolopt "show-costs")                            "show amounts with different costs separately"
  ,flagNone ["interleaved"]  (setboolopt "interleaved")                           "show source and destination postings together"
  ,flagReq  ["assertion-type"]  (\s opts -> Right $ setopt "assertion-type" s opts) "TYPE" "=, ==, =* or ==*"
  ,flagReq  ["close-desc"]   (\s opts -> Right $ setopt "close-desc" s opts) "DESC" "set closing transaction's description"
  ,flagReq  ["close-acct"]   (\s opts -> Right $ setopt "close-acct" s opts) "ACCT" "set closing transaction's destination account"
  ,flagReq  ["open-desc"]    (\s opts -> Right $ setopt "open-desc"  s opts) "DESC" "set opening transaction's description"
  ,flagReq  ["open-acct"]    (\s opts -> Right $ setopt "open-acct"  s opts) "ACCT" "set opening transaction's source account"
  ,roundFlag
  ,layoutFlag
  ]
  cligeneralflagsgroups1
  (hiddenflags
    ++  -- keep supporting old flag names for compatibility
    [flagNone ["closing"]   (setboolopt "close")                                   "old spelling of --close"
    ,flagNone ["opening"]   (setboolopt "open")                                    "old spelling of --open"
    ,flagNone ["migrate"]   (setboolopt "clopen")                                  "old spelling of --clopen"
    ,flagReq  ["close-to"]  (\s opts -> Right $ setopt "close-acct" s opts) "ACCT" "old spelling of --close-acct"
    ,flagReq  ["open-from"] (\s opts -> Right $ setopt "open-acct"  s opts) "ACCT" "old spelling of --open-acct"
    ]
  )
  ([], Just $ argsFlag "[--close|--open|--clopen|--assign|--assert|--retain] [ACCTQUERY]")

-- | The close command's mode (subcommand).
-- The code depends on these spellings.
data CloseMode = Clopen | Close | Open | Assign | Assert | Retain deriving (Eq,Show,Read)

-- | Pick the rightmost flag spelled like a CloseMode (--clopen, --close, --open, etc), or default to Close.
closeModeFromRawOpts :: RawOpts -> CloseMode
closeModeFromRawOpts rawopts = lastDef Close $ collectopts (\(name,_) -> readMay (capitalise name)) rawopts

-- Debugger, beware: close is incredibly devious; simple rules combine to make a horrid maze.
-- Tests are in hledger/test/close.test.
close CliOpts{rawopts_=rawopts, reportspec_=rspec0} j = do
  let
    mode_ = closeModeFromRawOpts rawopts
    defacctsq_    = if mode_ == Retain then Type [Revenue, Expense] else Type [Asset, Liability]
    defcloseacct_ = if mode_ == Retain then defretainacct else defcloseacct
    closeacct = T.pack $ fromMaybe defcloseacct_ $ maybestringopt "close-acct" rawopts
    openacct  = maybe closeacct T.pack $ maybestringopt "open-acct" rawopts

    -- For easy matching and exclusion, a recognisable tag is added to all generated transactions
    tagval = fromMaybe "" $ maybestringopt modeflag rawopts where modeflag = lowercase $ show mode_
    comment = T.pack $ if
      | mode_ == Assert -> "assert:" <> tagval
      | mode_ == Assign -> "assign:" <> tagval
      | mode_ == Retain -> "retain:" <> tagval
      | otherwise       -> "clopen:" <> if null tagval then inferredval else tagval
      where
        inferredval = newfilebasename
          where
            oldfilebasename = takeBaseName $ journalFilePath j
            (nonnum, rest) = break isDigit $ reverse oldfilebasename
            (oldnum, rest2) = span isDigit rest
            newfilebasename = case oldnum of
              [] -> ""
              _  -> reverse rest2 <> newnum <> reverse nonnum
                where
                  newnum = show $ 1 + readDef err (reverse oldnum)  -- PARTIAL: should not fail
                    where err = error' $ "could not read " <> show oldnum <> " as a number in Hledger.Cli.Commands.Close.close"

    ropts = (_rsReportOpts rspec0){balanceaccum_=Historical, accountlistmode_=ALFlat}
    rspec1 = setDefaultConversionOp NoConversionOp rspec0{_rsReportOpts=ropts}

    -- Dates of the closing and opening transactions.
    -- "The default closing date is yesterday, or the journal's end date, whichever is later.
    -- You can change this by specifying a [report end date](#report-start--end-date) with `-e`.
    -- The last day of the report period will be the closing date, eg `-e 2024` means "close on 2023-12-31".
    -- The opening date is always the day after the closing date."
    argsq = _rsQuery rspec1
    yesterday = addDays (-1) $ _rsDay rspec1
    yesterdayorjournalend = case journalLastDay False j of
      Just journalend -> max yesterday journalend
      Nothing         -> yesterday
    mreportlastday = addDays (-1) <$> queryEndDate False argsq
    closedate = fromMaybe yesterdayorjournalend  mreportlastday
    opendate = addDays 1 closedate

    -- should we show the amount(s) on the equity posting(s) ?
    explicit = boolopt "explicit" rawopts

    -- the accounts to close
    argsacctq = filterQuery (\q -> queryIsAcct q || queryIsType q) argsq
    q2 = if queryIsNull argsacctq then And [argsq, defacctsq_] else argsq
    -- always exclude the balancing equity account
    q3 = And [q2, Not $ Acct $ accountNameToAccountOnlyRegex closeacct]
    -- the balances to close
    rspec3 = rspec1{_rsQuery=q3}
    (acctbals',_) = balanceReport rspec3 j
    showcosts = show_costs_ ropts
    -- Strip costs unless --show-costs is used, and drop any accounts whose
    -- balance thereby becomes zero (unless -E). These are accounts which were
    -- emptied by postings with mismatched costs; without this they would
    -- generate zero postings, and with --lots, duplicate lot ids (#2689).
    -- Lot subaccounts are stripped even with --show-costs: their cost info
    -- lives in the lot name, and transacted prices on their postings would
    -- make the output unparseable (lot transfers may not have one).
    acctbals = [ (a, b')
               | (a,_,_,b) <- acctbals'
               , let keepcosts = showcosts && not (isLotSubaccount a)
               , let b' = if keepcosts then b else mixedAmountStripCosts b
               , keepcosts || empty_ ropts || not (mixedAmountLooksZero b')
               ]
    totalamt = maSum $ map snd acctbals

    -- since balance assertion amounts are required to be exact, the
    -- amounts in opening/closing transactions should be too (#941, #1137)
    precise = amountSetFullPrecision

    -- does this account have a lot subaccount component (e.g. assets:stocks:{2026-01-15, $50}) ?
    isLotSubaccount a = lotBaseAccount a /= a

    -- interleave equity postings next to the corresponding closing posting, or put them all at the end ?
    interleaved = boolopt "interleaved" rawopts

    -- a balance assertion template of the right type
    assertion =
      case maybestringopt "assertion-type" rawopts >>= parseBalanceAssertionType of
        Nothing                 -> nullassertion
        Just (total, inclusive) -> nullassertion{batotal=total, bainclusive=inclusive}

    -- the closing (balance-asserting or balance-zeroing) transaction
    mclosetxn
      | mode_ `notElem` [Clopen, Close, Assert, Retain] = Nothing
      | otherwise = Just nulltransaction{
          tdate=closedate, tdescription=closedesc, tcomment=comment, tpostings=closeps
          }
      where
        closedesc = T.pack $ fromMaybe defclosedesc_ $ maybestringopt "close-desc" rawopts
          where
            defclosedesc_
              | mode_ == Retain = defretaindesc
              | mode_ == Assert = "assert balances"
              | otherwise       = defclosedesc
        closeps
          -- XXX some duplication
          | mode_ == Assert =
            [ posting{
                   paccount          = a
                  ,pamount           = mixedAmount $ precise b{aquantity=0, acost=Nothing}
                  -- after each commodity's last posting, assert 0 balance (#1035)
                  -- balance assertion amounts are unpriced (#824)
                  -- lot subaccounts are skipped: assertions run before lot calculation,
                  -- so the subaccount balance would be wrong when re-read
                  ,pbalanceassertion =
                      if islast && not (isLotSubaccount a)
                      then Just assertion{baamount=precise b}
                      else Nothing
                  }
              | -- get the balances for each commodity and transaction price
                (a,mb) <- acctbals
              , let bs0 = amounts mb
                -- mark the last balance in each commodity with True
              , let bs2 = concat [reverse $ zip (reverse bs1) (True : repeat False)
                                | bs1 <- groupBy ((==) `on` acommodity) bs0]
              , (b, islast) <- bs2
            ]

          | otherwise =
            concat [
              posting{paccount          = a
                    ,pamount           = mixedAmount . precise $ negate b
                    -- after each commodity's last posting, assert 0 balance (#1035)
                    -- balance assertion amounts are unpriced (#824)
                    -- lot subaccounts are skipped (see Assert branch above)
                    ,pbalanceassertion =
                        if islast && not (isLotSubaccount a)
                        then Just assertion{baamount=precise b{aquantity=0, acost=Nothing}}
                        else Nothing
                    }

              -- maybe an interleaved posting transferring this balance to equity
              : [posting{paccount=closeacct, pamount=mixedAmount $ precise b} | interleaved]

              | -- get the balances for each commodity and transaction price
                (a,mb) <- acctbals
              , let bs0 = amounts mb
                -- mark the last balance in each commodity with True
              , let bs2 = concat [reverse $ zip (reverse bs1) (True : repeat False)
                                | bs1 <- groupBy ((==) `on` acommodity) bs0]
              , (b, islast) <- bs2
            ]

            -- or a final multicommodity posting transferring all balances to equity
            -- (print will show this as multiple single-commodity postings)
            ++ [posting{paccount=closeacct, pamount=if explicit then mixedAmountSetFullPrecision totalamt else missingmixedamt} | not interleaved]

    -- the opening (balance-assigning or balance-unzeroing) transaction
    mopentxn
      | mode_ `notElem` [Clopen, Open, Assign] = Nothing
      | otherwise = Just nulltransaction{
          tdate=opendate, tdescription=opendesc, tcomment=comment, tpostings=openps
          }
      where
        opendesc  = T.pack $ fromMaybe defopendesc  $ maybestringopt "open-desc"  rawopts
        openps
          | mode_ == Assign =
            [ posting{paccount         = a
                    ,pamount           = missingmixedamt
                    ,pbalanceassertion = Just assertion{baamount=b}
                        -- case mcommoditysum of
                        --   Just s  -> Just nullassertion{baamount=precise s}
                        --   Nothing -> Nothing
                    }

              | (a,mb) <- acctbals
              , let bs0 = amounts mb
                -- mark the last balance in each commodity with the unpriced sum in that commodity (for a balance assertion)
              , let bs2 = concat [reverse $ zip (reverse bs1) (Just commoditysum : repeat Nothing)
                                | bs1 <- groupBy ((==) `on` acommodity) bs0
                                , let commoditysum = (sum bs1)]
              , (b, _mcommoditysum) <- bs2
            ]
            ++ [posting{paccount=openacct, pamount=if explicit then mixedAmountSetFullPrecision (maNegate totalamt) else missingmixedamt} | not interleaved]

          | otherwise =
            concat [
              posting{paccount          = a
                    ,pamount           = mixedAmount $ precise b
                    -- lot subaccounts are skipped: assertions run before lot
                    -- calculation, so the subaccount balance would be wrong
                    -- when re-read (mirrors the close branch above)
                    ,pbalanceassertion =
                        case mcommoditysum of
                          Just s | not (isLotSubaccount a) ->
                            Just assertion{baamount=precise s{acost=Nothing}}
                          _ -> Nothing
                    }
              : [posting{paccount=openacct, pamount=mixedAmount . precise $ negate b} | interleaved]

              | (a,mb) <- acctbals
              , let bs0 = amounts mb
                -- mark the last balance in each commodity with the unpriced sum in that commodity (for a balance assertion)
              , let bs2 = concat [reverse $ zip (reverse bs1) (Just commoditysum : repeat Nothing)
                                | bs1 <- groupBy ((==) `on` acommodity) bs0
                                , let commoditysum = (sum bs1)]
              , (b, mcommoditysum) <- bs2
            ]
            ++ [posting{paccount=openacct, pamount=if explicit then mixedAmountSetFullPrecision (maNegate totalamt) else missingmixedamt} | not interleaved]

  -- print them
  -- allow user-specified rounding with --round, like print
  let styles = amountStylesSetRoundingFromRawOpts rawopts $ journalCommodityStyles j
      postinglayout = layoutFromRawOpts rawopts
      showtxn = showTransactionWithLayout postinglayout . styleAmounts styles
  maybe (pure ()) (T.putStr . showtxn) mclosetxn
  maybe (pure ()) (T.putStr . showtxn) mopentxn
 
