{-# LANGUAGE CPP #-}
{-|


Data values for zero or more report periods, and for the pre-report period.
Report periods are assumed to be contiguous, and represented only by start dates
(as keys of an IntMap).

-}
module Hledger.Data.PeriodData
( periodDataFromList
, periodDataToList

, lookupPeriodData
, lookupPeriodDataOrHistorical
, insertPeriodData
, opPeriodData
, mergePeriodData
, padPeriodData

, tests_PeriodData
) where

#if MIN_VERSION_base(4,18,0)
import Data.Foldable1 (Foldable1(..))
#else
import Control.Applicative (liftA2)
#endif
#if !MIN_VERSION_base(4,20,0)
import Data.List (foldl')
#endif
import Data.Map qualified as M
import Data.Time (Day (..), fromGregorian)

import Hledger.Data.Amount
import Hledger.Data.Types
import Hledger.Utils


instance Show a => Show (PeriodData a) where
  showsPrec d (PeriodData h ds) =
    showParen (d > 10) $
        showString "PeriodData"
      . showString "{ pdpre = " . shows h
      . showString ", pdperiods = "
      . showString "fromList " . shows (M.toList ds)
      . showChar '}'

instance Foldable PeriodData where
  foldr f z (PeriodData h as) = foldr f (f h z) as
  foldl f z (PeriodData h as) = foldl f (f z h) as
  foldl' f z (PeriodData h as) = let fzh = f z h in fzh `seq` foldl' f fzh as

#if MIN_VERSION_base(4,18,0)
instance Foldable1 PeriodData where
  foldrMap1 f g (PeriodData h as) = foldr g (f h) as
  foldlMap1 f g (PeriodData h as) = foldl g (f h) as
  foldlMap1' f g (PeriodData h as) = let fh = f h in fh `seq` foldl' g fh as
#endif

instance Traversable PeriodData where
  traverse f (PeriodData h as) = liftA2 PeriodData (f h) $ traverse f as

-- | The Semigroup instance for 'PeriodData' simply takes the union of
-- keys in the date map section. This may not be the result you want if the
-- keys are not identical.
instance Semigroup a => Semigroup (PeriodData a) where
  PeriodData h1 as1 <> PeriodData h2 as2 = PeriodData (h1 <> h2) $ M.unionWith (<>) as1 as2

instance Monoid a => Monoid (PeriodData a) where
  mempty = PeriodData mempty mempty

-- | Construct a 'PeriodData' from a historical data value and a list of (period start, period data) pairs.
periodDataFromList :: a -> [(Day, a)] -> PeriodData a
periodDataFromList h = PeriodData h . M.fromList

-- | Convert 'PeriodData' to a historical data value and a list of (period start, period data) pairs.
periodDataToList :: PeriodData a -> (a, [(Day, a)])
periodDataToList (PeriodData h as) = (h, M.toList as)

-- | Get the data for the period containing the given 'Day', and that period's start date.
-- If the day is after the end of the last period, it is assumed to be within the last period.
-- If the day is before the start of the first period (ie, in the historical period), return Nothing.
lookupPeriodData :: Day -> PeriodData a -> Maybe (Day, a)
lookupPeriodData d (PeriodData _ as) = M.lookupLE d as

-- | Get the data for the period containing the given 'Day', and that period's start date.
-- If the day is after the end of the last period, it is assumed to be within the last period.
-- If the day is before the start of the first period (ie, in the historical period),
-- return the data for the historical period and no start date.
lookupPeriodDataOrHistorical :: Day -> PeriodData a -> (Maybe Day, a)
lookupPeriodDataOrHistorical d pd@(PeriodData h _) = case lookupPeriodData d pd of
  Nothing     -> (Nothing, h)
  Just (a, b) -> (Just a, b)

-- | Set historical or period data in the appropriate location in a 'PeriodData'.
insertPeriodData :: Semigroup a => Maybe Day -> a -> PeriodData a -> PeriodData a
insertPeriodData mday b balances = case mday of
    Nothing  -> balances{pdpre = pdpre balances <> b}
    Just day -> balances{pdperiods = M.insertWith (<>) day b $ pdperiods balances}

-- | Merge two 'PeriodData', using the given operation to combine their data values.
--
-- This will drop keys if they are not present in both 'PeriodData'.
opPeriodData :: (a -> b -> c) -> PeriodData a -> PeriodData b -> PeriodData c
opPeriodData f (PeriodData h1 as1) (PeriodData h2 as2) =
  PeriodData (f h1 h2) $ M.intersectionWith f as1 as2

-- | Merge two 'PeriodData', using the given operations for combining data
-- that's only in the first, only in the second, or in both, respectively.
mergePeriodData :: (a -> c) -> (b -> c) -> (a -> b -> c) -> PeriodData a -> PeriodData b -> PeriodData c
mergePeriodData only1 only2 f = \(PeriodData h1 as1) (PeriodData h2 as2) ->
  PeriodData (f h1 h2) $ merge as1 as2
  where
    merge = M.mergeWithKey (\_ x y -> Just $ f x y) (fmap only1) (fmap only2)

-- | Pad out the date map of a 'PeriodData' so that every key from another 'PeriodData' is present.
padPeriodData :: a -> PeriodData b -> PeriodData a -> PeriodData a
padPeriodData x pad bal = bal{pdperiods = pdperiods bal <> (x <$ pdperiods pad)}


-- tests

tests_PeriodData =
  let
    dayMap  = periodDataFromList (mixed [usd 1]) [(fromGregorian 2000 01 01, mixed [usd 2]), (fromGregorian 2004 02 28, mixed [usd 3])]
    dayMap2 = periodDataFromList (mixed [usd 2]) [(fromGregorian 2000 01 01, mixed [usd 4]), (fromGregorian 2004 02 28, mixed [usd 6])]
  in testGroup "PeriodData" [

       testCase "periodDataFromList" $ do
         length dayMap @?= 3,

       testCase "Semigroup instance" $ do
         dayMap <> dayMap @?= dayMap2,

       testCase "Monoid instance" $ do
         dayMap <> mempty @?= dayMap
     ]
