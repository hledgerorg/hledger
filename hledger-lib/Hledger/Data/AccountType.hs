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
  LotDirection(..),
  accountTypeLotDirection,
  lotDirectionSign,
) where

import Hledger.Data.Types (AccountType(..), Quantity)

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

-- | Which way lots flow in a lot-tracking account. In a Long account
-- (assets) a positive posting opens a lot and a negative one closes it; in
-- a Short account (liabilities, holding short positions) it is the reverse:
-- a negative posting opens a short lot and a positive one closes (covers) it.
data LotDirection = Long | Short
  deriving (Eq, Ord, Show)

-- | The lot direction of an account type: Long for assets (and Cash),
-- Short for liabilities, none for other types, which don't hold lots.
accountTypeLotDirection :: AccountType -> Maybe LotDirection
accountTypeLotDirection t
  | isAssetType t     = Just Long
  | isLiabilityType t = Just Short
  | otherwise         = Nothing

-- | The sign of a posting that opens a lot in this direction: 1 or -1.
-- Multiplying a posting quantity by this gives its lot flow: positive
-- when it opens or receives a lot, negative when it closes or sends one.
lotDirectionSign :: LotDirection -> Quantity
lotDirectionSign Long  = 1
lotDirectionSign Short = -1
