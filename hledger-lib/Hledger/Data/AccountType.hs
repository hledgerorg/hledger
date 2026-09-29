{-|

Helpers for working with 'AccountType's.
Subtypes (Cash, Conversion, Gain, UnrealisedGain) are recognised as their parent type
where appropriate.

-}

module Hledger.Data.AccountType (
  isAccountSubtypeOf,
  isAssetType,
  isLiabilityType,
  isEquityType,
  isRevenueType,
  isExpenseType,
) where

import Hledger.Data.Types (AccountType(..))

-- | Check whether the first argument is a subtype of the second: either equal
-- or one of the defined subtypes.
isAccountSubtypeOf :: AccountType -> AccountType -> Bool
isAccountSubtypeOf Asset          Asset          = True
isAccountSubtypeOf Liability      Liability      = True
isAccountSubtypeOf Equity         Equity         = True
isAccountSubtypeOf Revenue        Revenue        = True
isAccountSubtypeOf Expense        Expense        = True
isAccountSubtypeOf Cash           Cash           = True
isAccountSubtypeOf Cash           Asset          = True
isAccountSubtypeOf Conversion     Conversion     = True
isAccountSubtypeOf Conversion     Equity         = True
isAccountSubtypeOf Gain           Gain           = True
isAccountSubtypeOf Gain           Revenue        = True
isAccountSubtypeOf UnrealisedGain UnrealisedGain = True
isAccountSubtypeOf UnrealisedGain Equity         = True
isAccountSubtypeOf _              _              = False

-- | Is this an Asset or Cash (subtype of Asset) account type ?
isAssetType :: AccountType -> Bool
isAssetType = (`isAccountSubtypeOf` Asset)

-- | Is this a Liability account type ?
isLiabilityType :: AccountType -> Bool
isLiabilityType = (`isAccountSubtypeOf` Liability)

-- | Is this an Equity or Conversion (subtype of Equity) account type ?
isEquityType :: AccountType -> Bool
isEquityType = (`isAccountSubtypeOf` Equity)

-- | Is this a Revenue or Gain (subtype of Revenue) account type ?
isRevenueType :: AccountType -> Bool
isRevenueType = (`isAccountSubtypeOf` Revenue)

-- | Is this an Expense account type ?
isExpenseType :: AccountType -> Bool
isExpenseType = (`isAccountSubtypeOf` Expense)
