{-# LANGUAGE OverloadedStrings #-}
{-|

The Hledger.Data library allows parsing and querying of C++ ledger-style
journal files.  It generally provides a compatible subset of C++ ledger's
functionality.  This package re-exports all the Hledger.Data.* modules
(except UTF8, which requires an explicit import.)

-}

module Hledger.Data (
               module Hledger.Data.Account,
               module Hledger.Data.AccountName,
               module Hledger.Data.AccountType,
               module Hledger.Data.Amount,
               module Hledger.Data.BalanceData,
               module Hledger.Data.Balancing,
               module Hledger.Data.Currency,
               module Hledger.Data.Dates,
               module Hledger.Data.DayPartition,
               module Hledger.Data.Errors,
               module Hledger.Data.Journal,
               module Hledger.Data.JournalChecks,
               module Hledger.Data.Json,
               module Hledger.Data.Ledger,
               module Hledger.Data.Lots,
               module Hledger.Data.Period,
               module Hledger.Data.PeriodData,
               module Hledger.Data.PeriodicTransaction,
               module Hledger.Data.Posting,
               module Hledger.Data.RawOptions,
               module Hledger.Data.StringFormat,
               module Hledger.Data.Timeclock,
               module Hledger.Data.Transaction,
               module Hledger.Data.TransactionModifier,
               module Hledger.Data.Types,
               module Hledger.Data.Valuation,
               tests_Data
              )
where

import Test.Tasty (testGroup)
import Hledger.Data.Account
import Hledger.Data.BalanceData
import Hledger.Data.AccountName
import Hledger.Data.AccountType
import Hledger.Data.Amount
import Hledger.Data.Balancing
import Hledger.Data.Currency
import Hledger.Data.Dates
import Hledger.Data.DayPartition
import Hledger.Data.Errors
import Hledger.Data.Journal
import Hledger.Data.JournalChecks
import Hledger.Data.Json
import Hledger.Data.Ledger
import Hledger.Data.Lots
import Hledger.Data.Period
import Hledger.Data.PeriodData
import Hledger.Data.PeriodicTransaction
import Hledger.Data.Posting
import Hledger.Data.RawOptions
import Hledger.Data.StringFormat
import Hledger.Data.Timeclock
import Hledger.Data.Transaction
import Hledger.Data.TransactionModifier
import Hledger.Data.Types hiding (MixedAmountKey, Mixed)
import Hledger.Data.Valuation

tests_Data = testGroup "Data" [
   tests_Account
  ,tests_AccountName
  ,tests_Amount
  ,tests_BalanceData
  ,tests_Balancing
  ,tests_DayPartition
  -- ,tests_Currency
  ,tests_Journal
  ,tests_Ledger
  ,tests_PeriodData
  ,tests_Posting
  ,tests_Valuation
  ,tests_StringFormat
  ,tests_Timeclock
  ,tests_Transaction
  ]
