{-# LANGUAGE CPP #-}
{-|


A 'BalanceData is a data type tracking a number of postings, exclusive, and inclusive balance
for given date ranges.

-}
module Hledger.Data.BalanceData
( mapBalanceData
, opBalanceData

, tests_BalanceData
) where


import Test.Tasty (testGroup)
import Test.Tasty.HUnit ((@?=), testCase)

import Hledger.Data.Amount
import Hledger.Data.Types


instance Show BalanceData where
  showsPrec d (BalanceData e i n) =
    showParen (d > 10) $
        showString "BalanceData"
      . showString "{ bdexcludingsubs = " . showString (wbUnpack (showMixedAmountB defaultFmt e))
      . showString ", bdincludingsubs = " . showString (wbUnpack (showMixedAmountB defaultFmt i))
      . showString ", bdnumpostings = " . shows n
      . showChar '}'

instance Semigroup BalanceData where
  BalanceData e i n <> BalanceData e' i' n' = BalanceData (maPlus e e') (maPlus i i') (n + n')

instance Monoid BalanceData where
  mempty = BalanceData nullmixedamt nullmixedamt 0

-- | Apply an operation to both 'MixedAmount' in an 'BalanceData'.
mapBalanceData :: (MixedAmount -> MixedAmount) -> BalanceData -> BalanceData
mapBalanceData f a = a{bdexcludingsubs = f $ bdexcludingsubs a, bdincludingsubs = f $ bdincludingsubs a}

-- | Merge two 'BalanceData', using the given operation to combine their amounts.
opBalanceData :: (MixedAmount -> MixedAmount -> MixedAmount) -> BalanceData -> BalanceData -> BalanceData
opBalanceData f a b = a{bdexcludingsubs = f (bdexcludingsubs a) (bdexcludingsubs b), bdincludingsubs = f (bdincludingsubs a) (bdincludingsubs b)}


-- tests

tests_BalanceData = testGroup "BalanceData" [

  testCase "opBalanceData maPlus" $ do
    opBalanceData maPlus (BalanceData (mixed [usd 1]) (mixed [usd 2]) 5) (BalanceData (mixed [usd 3]) (mixed [usd 4]) 0)
      @?= BalanceData (mixed [usd 4]) (mixed [usd 6]) 5,

  testCase "opBalanceData maMinus" $ do
    opBalanceData maMinus (BalanceData (mixed [usd 1]) (mixed [usd 2]) 5) (BalanceData (mixed [usd 3]) (mixed [usd 4]) 0)
      @?= BalanceData (mixed [usd (-2)]) (mixed [usd (-2)]) 5
  ]
