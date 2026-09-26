{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-|

An account-centric transactions report.

-}

module Hledger.Reports.AccountTransactionsReport (
  AccountTransactionsReport,
  AccountTransactionsReportItem,
  accountTransactionsReport,
  accountTransactionsReportWithStart,
  accountTransactionsReportItems,
  transactionRegisterDate,
  transactionRegisterDateExtra,
  triOrigTransaction,
  triDate,
  triAmount,
  triBalance,
  triCommodityAmount,
  triCommodityBalance,
  accountTransactionsReportByCommodity,
  tests_AccountTransactionsReport
)
where

import Data.Foldable (asum)
import Data.List (mapAccumR, nub, partition, sortBy)
import Data.List.Extra (nubSort)
import Data.Maybe (catMaybes, fromMaybe)
import Data.Ord (Down(..), comparing)
import Data.Text qualified as T
import Data.Time.Calendar (Day, fromGregorian)

import Hledger.Data
import Hledger.Query
import Hledger.Reports.PostingsReport (registerRunningCalculationFn)
import Hledger.Reports.ReportOptions
import Hledger.Utils


-- | An account transactions report represents transactions affecting
-- a particular account (or possibly several accounts, but we don't
-- use that). It is used eg by hledger-ui's and hledger-web's register
-- view, and hledger's aregister report, where we want to show one row
-- per transaction, in the context of the current account. Report
-- items consist of:
--
-- - the transaction, unmodified
--
-- - the transaction as seen in the context of the current account and query,
--   which means:
--
--   - the transaction date is set to the "transaction context date":
--     the earliest of the transaction date and any other posting dates
--     of postings to the current account (matched by the report query).
--
--   - the transaction's postings are filtered, excluding any which are not
--     matched by the report query
--
-- - a text description of the other account(s) posted to/from
--
-- - a flag indicating whether there's more than one other account involved
--
-- - the total increase/decrease to the current account
--
-- - the report transactions' running total after this transaction;
--   or if historical balance is requested (-H), the historical running total;
--   or if average is requested (-A), the running average change per transaction
--   (also including transactions before the report start date, with -H).
--   The historical running total includes transactions from before the
--   report start date if one is specified, filtered by the report query.
--   The historical running total may or may not be the account's historical
--   running balance, depending on the report query.
--
-- Items are sorted by transaction register date (the earliest date the transaction
-- posts to the current account), most recent first.
-- Reporting intervals are currently ignored.
--
type AccountTransactionsReport = [AccountTransactionsReportItem] -- line items, one per transaction

type AccountTransactionsReportItem =
  (
   Transaction -- the transaction, unmodified
  ,Transaction -- the transaction, as seen from the current account
  ,Bool        -- is this a split (more than one posting to other accounts) ?
  ,[AccountName] -- the other account(s), if any
  ,MixedAmount -- the amount posted to the current account(s) (or total amount posted)
  ,MixedAmount -- the register's running total or the current account(s)'s historical balance (or running average), after this transaction
  )

instance HasAmounts AccountTransactionsReportItem where
  styleAmounts styles (torig,tacct,b,c,a1,a2) =
    (styleAmounts styles torig,styleAmounts styles tacct,b,c,styleAmounts styles a1,styleAmounts styles a2)

triOrigTransaction (torig,_,_,_,_,_) = torig
triDate (_,tacct,_,_,_,_) = tdate tacct
triAmount (_,_,_,_,a,_) = a
triBalance (_,_,_,_,_,a) = a
triCommodityAmount c = filterMixedAmountByCommodity c  . triAmount
triCommodityBalance c = filterMixedAmountByCommodity c  . triBalance

accountTransactionsReport :: ReportSpec -> Journal -> Query -> AccountTransactionsReport
accountTransactionsReport rspec j = snd . accountTransactionsReportWithStart rspec j

-- | The account transactions report, and the balance its running total
-- starts from: zero, or, with historical balances and a start date in
-- the query, the sum of the account's postings before that date (with
-- --average, their average per transaction). A register can show the
-- latter as a balance brought forward.
accountTransactionsReportWithStart :: ReportSpec -> Journal -> Query -> (MixedAmount, AccountTransactionsReport)
accountTransactionsReportWithStart rspec@ReportSpec{_rsReportOpts=ropts} j thisacctq = (startbal, items)
  where
    -- A depth limit should not affect the account transactions report; it should show all transactions in/below this account.
    -- Queries on currency or amount are also ignored at this stage; they are handled earlier, before valuation.
    reportq = simplifyQuery $ And [aregisterq, periodq]
      where
        aregisterq = filterQuery (not . queryIsCurOrAmt) . filterQuery (not . queryIsDepth) $ _rsQuery rspec
        periodq = Date . periodAsDateSpan $ period_ ropts
    amtq = filterQuery queryIsCurOrAmt $ _rsQuery rspec
    queryIsCurOrAmt q = queryIsCurOrSym q || queryIsAmt q
    wd = whichDate ropts

    -- Note that within this function, we are only allowed limited
    -- transformation of the transaction postings: this is due to the need to
    -- pass the original transactions into accountTransactionsReportItem.
    -- Generally, we either include a transaction in full, or not at all.
    -- Do some limited filtering and valuing of the journal's transactions:
    -- - filter them by the account query if any,
    -- - discard amounts not matched by the currency and amount query if any,
    -- - then apply valuation if any.
    -- Additional reportq filtering, such as date filtering, happens down in 
    -- accountTransactionsReportItem, which discards transactions with no matched postings.
    acctJournal =
        -- With most calls we will not require transaction prices past this point, and can get a big
        -- speed improvement by stripping them early. In some cases, such as in hledger-ui, we still
        -- want to keep prices around, so we can toggle between cost and no cost quickly. We can use
        -- the show_costs_ flag to be efficient when we can, and detailed when we have to.
          (if show_costs_ ropts then id else journalMapPostingAmounts mixedAmountStripCosts)
        . dbg5With (("ts3:\n"++).pshowTransactions.jtxns)
        -- maybe convert these transactions to cost or value
        . journalApplyValuationFromOpts rspec
        . dbg5With (("ts2:\n"++).pshowTransactions.jtxns)
        -- apply any cur: or amt: filters in reportq
        . (if queryIsNull amtq then id else filterJournalAmounts amtq)
        -- only consider transactions which match thisacctq (possibly excluding postings
        -- which are not real or have the wrong status)
        . dbg3Msg ("thisacctq: "++show thisacctq)
        $ dbg5With (("ts1:\n"++).pshowTransactions.jtxns)
          j{jtxns = filter (matchesTransaction thisacctq . relevantPostings) $ jtxns j}
      where
        relevantPostings
          | queryIsNull realq && queryIsNull statusq = id
          | otherwise = filterTransactionPostings . simplifyQuery $ And [realq, statusq]
        realq   = filterQuery queryIsReal reportq
        statusq = filterQuery queryIsStatus reportq

    -- The number of the first report item, and the running total or average before it.
    -- In historical mode, these include the transactions before the report start date.
    (startnum, startbal)
      | balanceaccum_ ropts /= Historical = (1, nullmixedamt)
      | average_ ropts = (numpriorts + 1, divideMixedAmount (fromIntegral numpriorts) priorsum)
      | otherwise      = (numpriorts + 1, priorsum)
      where
        priorpss = dbg5 "priorpss" . filter (not . null) . map (filter hasAmount . tpostings) . jtxns $
                   filterJournalPostings priorq acctJournal
        numpriorts = length priorpss
        priorsum = sumPostings $ concat priorpss
        priorq = dbg5 "priorq" $ And [thisacctq, tostartdateq, datelessreportq]
        -- The postings before the report start, by whichever kind of date
        -- the query's start date is: the report's kind if it has one,
        -- else the other, so that a date2: term selects the prior postings
        -- by secondary date as it selects the report's postings.
        -- With no start date, there are no prior postings.
        tostartdateq = fromMaybe None $ asum [cutoff (date2_ ropts), cutoff (not $ date2_ ropts)]
        cutoff secondary =
          (if secondary then Date2 else Date) . DateSpan Nothing . Just . Exact
            <$> queryStartDate secondary reportq
        datelessreportq = filterQuery (not . queryIsDateOrDate2) reportq

    items =
        accountTransactionsReportItems reportq thisacctq (registerRunningCalculationFn ropts) startnum startbal maNegate (journalAccountType j)
      -- sort by the transaction's register date, then index, for accurate starting balance
      . dbg5With (("ts4:\n"++).pshowTransactions.map snd)
      . sortBy (comparing (Down . fst) <> comparing (Down . tindex . snd))
      . map (\t -> (transactionRegisterDateExtra (journalAccountType j) wd reportq thisacctq t, t))
      . map (if invert_ ropts then (\t -> t{tpostings = map postingNegateMainAmount $ tpostings t}) else id)
      $ jtxns acctJournal

pshowTransactions :: [Transaction] -> String
pshowTransactions = pshow . map (\t -> unwords [show $ tdate t, T.unpack $ tdescription t])

-- | Generate transactions report items from a list of transactions,
-- using the provided user-specified report query, a query specifying
-- which account to use as the focus, a running calculation function
-- (see registerRunningCalculationFn), the starting item number and
-- running total/average, and a sign-setting function.
-- Each transaction is accompanied by the date that should be shown for it
-- in the report. This is not necessarily the transaction date - see
-- transactionRegisterDate.
accountTransactionsReportItems :: Query -> Query -> (Int -> MixedAmount -> MixedAmount -> MixedAmount)
                               -> Int -> MixedAmount -> (MixedAmount -> MixedAmount)
                               -> (AccountName -> Maybe AccountType) -> [(Day, Transaction)]
                               -> [AccountTransactionsReportItem]
accountTransactionsReportItems reportq thisacctq runningcalc i bal signfn accttypefn =
    catMaybes . snd . mapAccumR (accountTransactionsReportItem reportq thisacctq runningcalc signfn accttypefn) (i, bal)

accountTransactionsReportItem :: Query -> Query -> (Int -> MixedAmount -> MixedAmount -> MixedAmount)
                              -> (MixedAmount -> MixedAmount)
                              -> (AccountName -> Maybe AccountType) -> (Int, MixedAmount) -> (Day, Transaction)
                              -> ((Int, MixedAmount), Maybe AccountTransactionsReportItem)
accountTransactionsReportItem reportq thisacctq runningcalc signfn accttypefn (i, bal) (d, t)
    -- 201407: I've lost my grip on this, let's just hope for the best
    -- 201606: we now calculate change and balance from filtered postings, check this still works well for all callers XXX
    | null reportps = ((i, bal), Nothing)  -- no matched postings in this transaction, skip it
    | otherwise     = ((i + 1, bal'), Just (t, tacct{tdate=d}, numotheraccts > 1, otheraccts, amt, bal'))
    where
      tacct@Transaction{tpostings=reportps} = filterTransactionPostingsExtra accttypefn reportq t  -- TODO needs to consider --date2, #1731
      (thisacctps, otheracctps) = partition (matchesPosting thisacctq) reportps
      numotheraccts = length $ nub $ map paccount otheracctps
      otheraccts | thisacctq == None  = summarisePostingAccounts reportps     -- no current account ? summarise all matched postings
                 | numotheraccts == 0 = summarisePostingAccounts thisacctps   -- only postings to current account ? summarise those
                 | otherwise          = summarisePostingAccounts otheracctps  -- summarise matched postings to other account(s)
      -- 202302: Impact of t on thisacct - normally the sum of thisacctps,
      -- but if they are null it probably means reportq is an account filter
      -- and we should sum otheracctps instead.
      -- This fixes hledger areg ACCT ACCT2 (#2007), hopefully it's correct in general.
      amt
        | null thisacctps = signfn $ sumPostings otheracctps
        | otherwise       = signfn . maNegate $ sumPostings thisacctps
      bal' = runningcalc i bal amt

-- TODO needs checking, cf #1731
-- | What date should be shown for a transaction in an account register report ?
-- This will be in context of a particular account (the "this account" query)
-- and any additional report query. It could be:
--
-- - if postings are matched by both thisacctq and reportq, the earliest of those
--   matched postings' dates (or their secondary dates if --date2 was used)
--
-- - the transaction date, or its secondary date if --date2 was used.
--
transactionRegisterDate :: WhichDate -> Query -> Query -> Transaction -> Day
transactionRegisterDate = transactionRegisterDateExtra (const Nothing)

-- | Like 'transactionRegisterDate', but given the accounts' types, so
-- that a type: term in the report query matches postings here as it
-- does in the report itself.
transactionRegisterDateExtra :: (AccountName -> Maybe AccountType) -> WhichDate -> Query -> Query -> Transaction -> Day
transactionRegisterDateExtra accttypefn wd reportq thisacctq t
  | not $ null thisacctps = minimum $ map (postingDateOrDate2 wd) thisacctps
  | otherwise             = transactionDateOrDate2 wd t
  where
    reportps   = tpostings $ filterTransactionPostingsExtra accttypefn reportq t
    thisacctps = filter (matchesPosting thisacctq) reportps

-- -- | Generate a short readable summary of some postings, like
-- -- "from (negatives) to (positives)".
-- summarisePostings :: [Posting] -> String
-- summarisePostings ps =
--     case (summarisePostingAccounts froms, summarisePostingAccounts tos) of
--        ("",t) -> "to "++t
--        (f,"") -> "from "++f
--        (f,t)  -> "from "++f++" to "++t
--     where
--       (froms,tos) = partition (fromMaybe False . isNegativeMixedAmount . pamount) ps

-- | Generate a simplified summary of some postings' accounts.
-- To reduce noise, if there are both real and virtual postings, show only the real ones.
summarisePostingAccounts :: [Posting] -> [AccountName]
summarisePostingAccounts ps = map paccount displayps
  where
    realps = filter isReal ps
    displayps | null realps = ps
              | otherwise   = realps

-- | Split an  account transactions report whose items may involve several commodities,
-- into one or more single-commodity account transactions reports.
accountTransactionsReportByCommodity :: AccountTransactionsReport -> [(CommoditySymbol, AccountTransactionsReport)]
accountTransactionsReportByCommodity tr =
  [(c, filterAccountTransactionsReportByCommodity c tr) | c <- commodities tr]
  where
    commodities = nubSort . map acommodity . concatMap (amounts . triAmount)

-- | Remove account transaction report items and item amount (and running
-- balance amount) components that don't involve the specified
-- commodity. Other item fields such as the transaction are left unchanged.
filterAccountTransactionsReportByCommodity :: CommoditySymbol -> AccountTransactionsReport -> AccountTransactionsReport
filterAccountTransactionsReportByCommodity comm =
    fixTransactionsReportItemBalances . concatMap (filterTransactionsReportItemByCommodity comm)
  where
    filterTransactionsReportItemByCommodity c (t,t2,s,o,a,bal)
      | c `elem` cs = [item']
      | otherwise   = []
      where
        cs = map acommodity $ amounts a
        item' = (t,t2,s,o,a',bal)
        a' = filterMixedAmountByCommodity c a

    fixTransactionsReportItemBalances [] = []
    fixTransactionsReportItemBalances [i] = [i]
    fixTransactionsReportItemBalances items = reverse $ i:(go startbal is)
      where
        i:is = reverse items
        startbal = filterMixedAmountByCommodity comm $ triBalance i
        go _ [] = []
        go bal ((t,t2,s,o,amt,_):is') = (t,t2,s,o,amt,bal'):go bal' is'
          where bal' = bal `maPlus` amt

-- tests

tests_AccountTransactionsReport = testGroup "AccountTransactionsReport" [
  testCase "accountTransactionsReportWithStart" $ do
    let checking = Acct $ toRegex' "assets:bank:checking"
        fromJune = Date $ DateSpan (Just $ Exact $ fromGregorian 2008 6 1) Nothing
        rspec accum = defreportspec{_rsQuery=fromJune, _rsReportOpts=defreportopts{balanceaccum_=accum}}
        (histstart, histitems) = accountTransactionsReportWithStart (rspec Historical) samplejournal checking
        (start, items) = accountTransactionsReportWithStart (rspec PerPeriod) samplejournal checking
    -- with historical balances, the running balance starts from the postings before the start date
    showMixedAmount histstart @?= "$1.00"
    map (showMixedAmount . triBalance) histitems @?= ["$1.00", "$2.00", "$1.00", "$2.00"]
    -- otherwise from zero
    showMixedAmount start @?= "0"
    map (showMixedAmount . triBalance) items @?= ["0", "$1.00", "0", "$1.00"]
    -- a date2: start date counts too, by secondary date (here the same days)
    let fromJune2 = Date2 $ DateSpan (Just $ Exact $ fromGregorian 2008 6 1) Nothing
        (histstart2, _) = accountTransactionsReportWithStart (rspec Historical){_rsQuery=fromJune2} samplejournal checking
    showMixedAmount histstart2 @?= "$1.00"

 ,testCase "transactionRegisterDateExtra" $ do
    let t = nulltransaction{tdate=fromGregorian 2008 1 1, tpostings=[
              ("assets:bank:checking" `post` usd 1){pdate=Just $ fromGregorian 2008 1 5}
             ,"income:salary" `post` usd (-1)]}
        checking = Acct $ toRegex' "assets:bank:checking"
        assettypes a = if "assets" `T.isPrefixOf` a then Just Asset else Nothing
    -- a type: term in the report query matches the posting only when the account types are known
    transactionRegisterDate PrimaryDate (Type [Asset]) checking t @?= fromGregorian 2008 1 1
    transactionRegisterDateExtra assettypes PrimaryDate (Type [Asset]) checking t @?= fromGregorian 2008 1 5
 ]
