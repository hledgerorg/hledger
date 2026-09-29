{-|

A 'Ledger' is derived from a 'Journal' by applying a filter specification
to select 'Transaction's and 'Posting's of interest. It contains the
filtered journal and knows the resulting chart of accounts, account
balances, and postings in each account.

-}

{-# LANGUAGE OverloadedStrings #-}

module Hledger.Data.Ledger (
   nullledger
  ,ledgerFromJournal
  ,ledgerAccountNames
  ,ledgerAccount
  ,ledgerRootAccount
  ,ledgerTopAccounts
  ,ledgerLeafAccounts
  ,ledgerPostings
  ,ledgerDateSpan
  ,ledgerCommodities
  ,tests_Ledger
)
where

import Data.Map qualified as M
import Safe (headDef)
import Text.Printf

import Test.Tasty (testGroup)
import Test.Tasty.HUnit ((@?=), testCase)
import Hledger.Data.Types
import Hledger.Data.Account
import Hledger.Data.Dates (nulldate)
import Hledger.Data.Journal
import Hledger.Query


instance Show Ledger where
    show l = printf "Ledger with %d transactions, %d accounts\n" --"%s"
             (length (jtxns $ ljournal l) +
              length (jtxnmodifiers $ ljournal l) +
              length (jperiodictxns $ ljournal l))
             (length $ ledgerAccountNames l)
             -- (showtree $ ledgerAccountNameTree l)

nullledger :: Ledger
nullledger = Ledger {
  ljournal = nulljournal,
  laccounts = []
  }

-- | Filter a journal's transactions with the given query, then build
-- a "Ledger", containing the journal plus the tree of all its
-- accounts with their subaccount-inclusive and subaccount-exclusive
-- balances. If the query includes a depth limit, the ledger's journal
-- will be depth limited, but the ledger's account tree will not.
ledgerFromJournal :: Query -> Journal -> Ledger
ledgerFromJournal q j = nullledger{ljournal=j'', laccounts=as}
  where
    (q',depthq)  = (filterQuery (not . queryIsDepth) q, filterQuery queryIsDepth q)
    j'  = filterJournalAmounts (filterQuery queryIsCurOrSym q) $ -- remove amount parts which the query's cur:/sym: terms would exclude
          filterJournalPostings q' j
    -- Ledger does not use date-separated balances, so dates are left empty
    as  = accountsFromPostings (const $ Just nulldate) $ journalPostings j'
    j'' = filterJournalPostings depthq j'

-- | List a ledger's account names.
ledgerAccountNames :: Ledger -> [AccountName]
ledgerAccountNames = drop 1 . map aname . laccounts

-- | Get the named account from a ledger.
ledgerAccount :: Ledger -> AccountName -> Maybe (Account BalanceData)
ledgerAccount l a = lookupAccount a $ laccounts l

-- | Get this ledger's root account, which is a dummy "root" account
-- above all others. This should always be first in the account list,
-- if somehow not this returns a null account.
ledgerRootAccount :: Ledger -> Account BalanceData
ledgerRootAccount = headDef nullacct . laccounts

-- | List a ledger's top-level accounts (the ones below the root), in tree order.
ledgerTopAccounts :: Ledger -> [Account BalanceData]
ledgerTopAccounts = asubs . headDef nullacct . laccounts

-- | List a ledger's bottom-level (subaccount-less) accounts, in tree order.
ledgerLeafAccounts :: Ledger -> [Account BalanceData]
ledgerLeafAccounts = filter (null.asubs) . laccounts

-- | List a ledger's postings, in the order parsed.
ledgerPostings :: Ledger -> [Posting]
ledgerPostings = journalPostings . ljournal

-- | The (fully specified) date span containing all the ledger's (filtered) transactions,
-- or DateSpan Nothing Nothing if there are none.
ledgerDateSpan :: Ledger -> DateSpan
ledgerDateSpan = journalDateSpanBothDates . ljournal

-- | All commodities used in this ledger.
ledgerCommodities :: Ledger -> [CommoditySymbol]
ledgerCommodities = M.keys . jinferredcommoditystyles . ljournal

-- tests

tests_Ledger =
  testGroup "Ledger" [
    testCase "ledgerFromJournal" $ do
        length (ledgerPostings $ ledgerFromJournal Any nulljournal) @?= 0
        length (ledgerPostings $ ledgerFromJournal Any samplejournal) @?= 13
        length (ledgerPostings $ ledgerFromJournal (Depth 2) samplejournal) @?= 7
  ]
