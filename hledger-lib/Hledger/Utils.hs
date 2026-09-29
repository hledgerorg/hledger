{-|
Utilities used throughout hledger, or needed low in the module hierarchy.
These are the bottom of hledger's module graph.
-}

{-# LANGUAGE CPP #-}

module Hledger.Utils (

  -- * Functions
  applyN,
  mapM',
  sequence',
  curry2,
  uncurry2,
  curry3,
  uncurry3,
  curry4,
  uncurry4,

  divideSafe,

  -- * Lists
  maximum',
  maximumStrict,
  minimumStrict,
  splitAtElement,
  sumStrict,
  all1,
  takeUntilFails,
  takeUntilFailsNE,

  -- * Trees
  treeLeaves,

  -- * Tuples
  first3,
  second3,
  third3,
  first4,
  second4,
  third4,
  fourth4,
  first5,
  second5,
  third5,
  fourth5,
  fifth5,
  first6,
  second6,
  third6,
  fourth6,
  fifth6,
  sixth6,

  -- * Misc
  multicol,
  numDigitsInt,
  numDigitsInteger,
  makeHledgerClassyLenses,

  -- * Other
  module Hledger.Utils.Debug,
  module Hledger.Utils.Parse,
  module Hledger.Utils.IO,
  module Hledger.Utils.Regex,
  module Hledger.Utils.String,
  module Hledger.Utils.Text,

  -- * Tests
  tests_Utils,
  module Hledger.Utils.Test,

)
where

import Data.Char (toLower)
import Data.List (intersperse)
import Data.List.Extra (chunksOf, foldl1', uncons, unsnoc)
import qualified Data.List.NonEmpty as NE
#if !MIN_VERSION_base(4,20,0)
import Data.List (foldl')
#endif
import Data.Set qualified as Set
import Data.Text qualified as T (pack, unpack)
import Data.Tree (foldTree, Tree (Node, subForest))
import Language.Haskell.TH (DecsQ, Name, mkName, nameBase)
import Lens.Micro ((&), (.~))
import Lens.Micro.TH (DefName(TopName), lensClass, lensField, makeLensesWith, classyRules)

import Hledger.Utils.Debug
import Hledger.Utils.I18n (tests_I18n)
import Hledger.Utils.Parse
import Hledger.Utils.IO
import Hledger.Utils.Regex
import Hledger.Utils.String
import Hledger.Utils.Text
import Hledger.Utils.Test


-- Functions

-- | Apply a function the specified number of times,
-- which should be > 0 (otherwise does nothing).
-- Possibly uses O(n) stack ?
applyN :: Int -> (a -> a) -> a -> a
applyN n f | n < 1     = id
           | otherwise = (!! n) . iterate f
-- from protolude, compare
-- applyN :: Int -> (a -> a) -> a -> a
-- applyN n f = X.foldr (.) identity (X.replicate n f)

-- | Like mapM but uses sequence'.
{-# INLINABLE mapM' #-}
mapM' :: Monad f => (a -> f b) -> [a] -> f [b]
mapM' f = sequence' . map f

-- | This is a version of sequence based on difference lists. It is
-- slightly faster but we mostly use it because it uses the heap
-- instead of the stack. This has the advantage that Neil Mitchell’s
-- trick of limiting the stack size to discover space leaks doesn’t
-- show this as a false positive.
{-# INLINABLE sequence' #-}
sequence' :: Monad f => [f a] -> f [a]
sequence' ms = do
  h <- go id ms
  return (h [])
  where
    go h [] = return h
    go h (m:ms') = do
      x <- m
      go (h . (x :)) ms'

curry2 :: ((a, b) -> c) -> a -> b -> c
curry2 f x y = f (x, y)

uncurry2 :: (a -> b -> c) -> (a, b) -> c
uncurry2 f (x, y) = f x y

curry3 :: ((a, b, c) -> d) -> a -> b -> c -> d
curry3 f x y z = f (x, y, z)

uncurry3 :: (a -> b -> c -> d) -> (a, b, c) -> d
uncurry3 f (x, y, z) = f x y z

curry4 :: ((a, b, c, d) -> e) -> a -> b -> c -> d -> e
curry4 f w x y z = f (w, x, y, z)

uncurry4 :: (a -> b -> c -> d -> e) -> (a, b, c, d) -> e
uncurry4 f (w, x, y, z) = f w x y z

-- | Division, returning 0 when the denominator is 0.
divideSafe :: (Eq a, Fractional a) => a -> a -> a
divideSafe _ 0 = 0
divideSafe a b = a / b

-- Lists

-- | Total version of maximum, for integral types, giving 0 for an empty list.
maximum' :: Integral a => [a] -> a
maximum' [] = 0
maximum' xs = maximumStrict xs

-- | Strict version of maximum that doesn’t leak space
{-# INLINABLE maximumStrict #-}
maximumStrict :: Ord a => [a] -> a
maximumStrict = foldl1' max

-- | Strict version of minimum that doesn’t leak space
{-# INLINABLE minimumStrict #-}
minimumStrict :: Ord a => [a] -> a
minimumStrict = foldl1' min

splitAtElement :: Eq a => a -> [a] -> [[a]]
splitAtElement x l =
  case l of
    []          -> []
    e:es | e==x -> split es
    es          -> split es
  where
    split es = let (first,rest) = break (x==) es
               in first : splitAtElement x rest

-- | Strict version of sum that doesn’t leak space
{-# INLINABLE sumStrict #-}
sumStrict :: Num a => [a] -> a
sumStrict = foldl' (+) 0

-- | Version of all that fails on an empty list.
{-# INLINABLE all1 #-}
all1 :: (a -> Bool) -> [a] -> Bool
all1 _ [] = False
all1 p as = all p as

-- | Take elements from a non-empty list until a predicate fails, and then keep
-- the first failing element as well.
takeUntilFailsNE :: (a -> Bool) -> NE.NonEmpty a -> NE.NonEmpty a
takeUntilFailsNE p = NE.fromList . takeUntilFails p . NE.toList  -- Result guaranteed to be non-empty

-- | Take elements from a list until a predicate fails, and then keep the first
-- failing element as well.
takeUntilFails :: (a -> Bool) -> [a] -> [a]
takeUntilFails p = foldr (\x -> if p x then (x :) else const [x]) []

-- Trees

-- | Get the leaves of this tree as a list. 
-- The topmost node ("root" in hledger account trees) is not counted as a leaf.
treeLeaves :: Tree a -> [a]
treeLeaves Node{subForest=[]} = []
treeLeaves t = foldTree (\a bs -> (if null bs then (a:) else id) $ concat bs) t

-- Tuples

first3  (x,_,_) = x
second3 (_,x,_) = x
third3  (_,_,x) = x

first4  (x,_,_,_) = x
second4 (_,x,_,_) = x
third4  (_,_,x,_) = x
fourth4 (_,_,_,x) = x

first5  (x,_,_,_,_) = x
second5 (_,x,_,_,_) = x
third5  (_,_,x,_,_) = x
fourth5 (_,_,_,x,_) = x
fifth5  (_,_,_,_,x) = x

first6  (x,_,_,_,_,_) = x
second6 (_,x,_,_,_,_) = x
third6  (_,_,x,_,_,_) = x
fourth6 (_,_,_,x,_,_) = x
fifth6  (_,_,_,_,x,_) = x
sixth6  (_,_,_,_,_,x) = x

-- Misc

-- | Convert a list of strings to a multi-line multi-column list
-- fitting within the given width. Not wide character aware.
multicol :: Int -> [String] -> String
multicol _ [] = []
multicol width strs =
  let
    maxwidth = maximum' $ map length strs
    numcols = min (length strs) (width `div` (maxwidth+2))
    itemspercol = length strs `div` numcols
    colitems = chunksOf itemspercol strs
    cols = map unlines colitems
    sep = " "
  in
    T.unpack $ textConcatBottomPadded $ map T.pack $ intersperse sep cols

-- | Find the number of digits of an 'Int'.
{-# INLINE numDigitsInt #-}
numDigitsInt :: Integral a => Int -> a
numDigitsInt n
    | n == minBound = 19  -- negate minBound is out of the range of Int
    | n < 0         = go (negate n)
    | otherwise     = go n
  where
    go a | a < 10                 = 1
         | a < 100                = 2
         | a < 1000               = 3
         | a < 10000              = 4
         | a >= 10000000000000000 = 16 + go (a `quot` 10000000000000000)
         | a >= 100000000         = 8  + go (a `quot` 100000000)
         | otherwise              = 4  + go (a `quot` 10000)

-- | Find the number of digits of an Integer.
-- The integer should not have more digits than an Int can count.
-- This is probably inefficient.
numDigitsInteger :: Integer -> Int
numDigitsInteger = length . dropWhile (=='-') . show

-- | Make classy lenses for Hledger options fields.
-- This is intended to be used with BalancingOpts, InputOpt, ReportOpts,
-- ReportSpec, and CliOpts.
-- When run on X, it will create a typeclass named HasX (except for ReportOpts,
-- which will be named HasReportOptsNoUpdate) containing all the lenses for that type.
-- If the field name starts with an underscore, the lens name will be created
-- by stripping the underscore from the front on the name. If the field name ends with
-- an underscore, the field name ends with an underscore, the lens name will be
-- mostly created by stripping the underscore, but a few names for which this
-- would create too many conflicts instead have a second underscore appended.
-- ReportOpts fields for which updating them requires updating the query in
-- ReportSpec are instead names by dropping the trailing underscore and
-- appending NoUpdate to the name, e.g. querystring_ -> querystringNoUpdate.
--
-- There are a few reasons for the complicated rules.
-- - We have some legacy field names ending in an underscore (e.g. value_)
--   which we want to temporarily accommodate, before eventually switching to
--   a more modern style (e.g. _rsReportOpts)
-- - Certain fields in ReportOpts need to update the enclosing ReportSpec when
--   they are updated, and it is a common programming error to forget to do
--   this. We append NoUpdate to those lenses which will not update the
--   enclosing field, and reserve the shorter name for manually define lenses
--   (or at least something lens-like) which will update the ReportSpec.
-- cf. the lengthy discussion here and in surrounding comments:
-- https://github.com/hledgerorg/hledger/pull/1545#issuecomment-881974554
makeHledgerClassyLenses :: Name -> DecsQ
makeHledgerClassyLenses x = flip makeLensesWith x $ classyRules
    & lensField .~ (\_ _ n -> fieldName $ nameBase n)
    & lensClass .~ (className . nameBase)
  where
    fieldName n | Just ('_', name) <- uncons n   = [TopName (mkName name)]
                | Just (name, '_') <- unsnoc n,
                  name `Set.member` queryFields  = [TopName (mkName $ name ++ "NoUpdate")]
                | Just (name, '_') <- unsnoc n,
                  name `Set.member` commonFields = [TopName (mkName $ name ++ "__")]
                | Just (name, '_') <- unsnoc n   = [TopName (mkName name)]
                | otherwise                      = []

    -- Fields which would cause too many conflicts if we exposed lenses with these names.
    commonFields = Set.fromList
        [ "empty", "drop", "color", "transpose", "title"  -- ReportOpts
        , "anon", "new", "auto"                           -- InputOpts
        , "rawopts", "file", "debug", "width"             -- CliOpts
        ]

    -- When updating some fields of ReportOpts within a ReportSpec, we need to
    -- update the rsQuery term as well. To do this we implement a special
    -- HasReportOpts class with some special behaviour. We therefore give the
    -- basic lenses a special NoUpdate name to avoid conflicts.
    className "ReportOpts" = Just (mkName "HasReportOptsNoUpdate", mkName "reportOptsNoUpdate")
    className (x':xs)       = Just (mkName ("Has" ++ x':xs), mkName (toLower x' : xs))
    className []           = Nothing

    -- Fields of ReportOpts which need to update the Query when they are updated.
    queryFields = Set.fromList ["period", "statuses", "depth", "date2", "real", "querystring"]

tests_Utils = testGroup "Utils" [
  tests_I18n,
  tests_Text
  ]
