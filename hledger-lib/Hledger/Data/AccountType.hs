{-|

Helpers for working with 'AccountType's.
Subtypes (Cash, Conversion, Gain, UnrealisedGain, Imbalance) are recognised as their parent type
where appropriate.

-}

{-# LANGUAGE OverloadedStrings #-}

module Hledger.Data.AccountType (
  isAccountSubtypeOf,
  isAssetType,
  isLiabilityType,
  isEquityType,
  isRevenueType,
  isExpenseType,
  accountTypeName,
  parseAccountType,
  accountTypeChoices,
  LotDirection(..),
  accountTypeLotDirection,
  lotDirectionSign,
) where

import Data.List (intercalate)
import Data.Text (Text)
import Data.Text qualified as T

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
isAccountSubtypeOf Imbalance      Imbalance      = True
isAccountSubtypeOf Imbalance      Equity         = True
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

-- | An account type's long-form name (its one-letter code is its 'show' value).
accountTypeName :: AccountType -> Text
accountTypeName Asset          = "Asset"
accountTypeName Liability      = "Liability"
accountTypeName Equity         = "Equity"
accountTypeName Revenue        = "Revenue"
accountTypeName Expense        = "Expense"
accountTypeName Cash           = "Cash"
accountTypeName Conversion     = "Conversion"
accountTypeName Gain           = "Gain"
accountTypeName UnrealisedGain = "UnrealisedGain"
accountTypeName Imbalance      = "Imbalance"

-- | Case-insensitively parse an account type's one-letter code,
-- or if permitted, its long-form name (or another accepted spelling of that).
-- On failure, returns the unparseable text.
parseAccountType :: Bool -> Text -> Either String AccountType
parseAccountType allowlongform s =
  maybe (Left $ T.unpack s) Right $ lookup (T.toLower s) $
    [(T.toLower $ T.pack $ show t, t) | t <- [minBound..maxBound]]
    ++ if allowlongform then [(T.toLower $ accountTypeName t, t) | t <- [minBound..maxBound]] ++ otherspellings else []
  where
    otherspellings =
      ("gains", Gain) :
      [(n, UnrealisedGain) | n <- ["unrealised", "unrealised-gain", "unrealised-gains", "unrealized", "unrealizedgain", "unrealized-gain", "unrealized-gains"]]

-- | The account type codes, and if permitted their long-form names, for showing in messages.
accountTypeChoices :: Bool -> String
accountTypeChoices allowlongform = intercalate ", " $
  map show types ++ if allowlongform then map (T.unpack . accountTypeName) types else []
  where types = [minBound..maxBound] :: [AccountType]

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
