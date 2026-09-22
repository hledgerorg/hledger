{-|

Convert amounts to some related value in various ways. This involves
looking up historical market prices (exchange rates) between commodities.

-}

{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveGeneric #-}

module Hledger.Data.Valuation (
   ConversionOp(..)
  ,ValuationType(..)
  ,PriceOracle
  ,journalPriceOracle
  ,mixedAmountToCost
  ,mixedAmountApplyValuation
  ,mixedAmountValueAtDate
  ,amountValueAtDate
  ,mixedAmountApplyGain
  ,mixedAmountGainAtDate
  ,marketPriceReverse
  ,priceDirectiveToMarketPrice
  ,amountPriceDirectiveFromCost
  ,valuationTypeValuationCommodity
  -- ,priceLookup
  ,tests_Valuation
)
where

import Control.Applicative ((<|>))
import Data.Function ((&))
import Data.List (partition, intercalate, sortBy)
import Data.Map qualified as M
import Data.Set qualified as S
import Data.Text qualified as T
import Data.Time.Calendar (Day, fromGregorian)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.MemoUgly (memo)
import GHC.Generics (Generic)
import Safe (headMay, lastMay)

import Hledger.Utils
import Hledger.Data.Types
import Hledger.Data.Amount
import Hledger.Data.Dates (nulldate)
import Text.Printf (printf)
import Data.Decimal (decimalPlaces, roundTo, Decimal)
import Data.Word (Word8)


------------------------------------------------------------------------------
-- Types

-- | Which cost conversion to perform on amounts, if any:
-- to cost basis where known, otherwise transacted cost (-B/--value=cost);
-- or to transacted cost always (--value=transacted).
-- (There was also an "infer equity postings" operation, but that is now done
-- earlier, in journal finalisation.)
data ConversionOp = NoConversionOp | ToCost | ToTransactedCost
  deriving (Show,Eq)

-- | What kind of value conversion should be done on amounts ?
-- CLI: --value=then|end|now|DATE[,COMM]
data ValuationType =
    AtThen     (Maybe CommoditySymbol)  -- ^ convert to default or given valuation commodity, using market prices at each posting's date
  | AtEnd      (Maybe CommoditySymbol)  -- ^ convert to default or given valuation commodity, using market prices at period end(s)
  | AtNow      (Maybe CommoditySymbol)  -- ^ convert to default or given valuation commodity, using current market prices
  | AtDate Day (Maybe CommoditySymbol)  -- ^ convert to default or given valuation commodity, using market prices on some date
  deriving (Show,Eq)

valuationTypeValuationCommodity :: ValuationType -> Maybe CommoditySymbol
valuationTypeValuationCommodity = \case
    AtThen   (Just c) -> Just c
    AtEnd    (Just c) -> Just c
    AtNow    (Just c) -> Just c
    AtDate _ (Just c) -> Just c
    _                 -> Nothing

-- | A price oracle is a magic memoising function that efficiently
-- looks up market prices (exchange rates) from one commodity to
-- another (or if unspecified, to a default valuation commodity) on a
-- given date.
type PriceOracle = (Day, CommoditySymbol, Maybe CommoditySymbol) -> Maybe (CommoditySymbol, Quantity)

-- | An index of market prices for efficient lookup by commodity pair and date.
-- Maps each (from, to) commodity pair to a Map from date to the effective price,
-- where declared prices take precedence over inferred prices on the same day.
-- This allows O(log n) lookup per pair via M.lookupLE.
type PriceIndex = M.Map (CommoditySymbol, CommoditySymbol) (M.Map Day MarketPrice)

-- | Build a price index from declared and inferred market prices.
-- This is O(n log n) but done only once, enabling fast lookups later.
buildPriceIndex :: [MarketPrice] -> [MarketPrice] -> PriceIndex
buildPriceIndex declaredprices inferredprices =
  let
    -- Label each price with precedence (declared=True > inferred=False) and parse order
    declaredprices' = [(mpdate p, True, i, p) | (i, p) <- zip [1..] declaredprices]
    inferredprices' = [(mpdate p, False, i, p) | (i, p) <- zip [1..] inferredprices]
    allprices = declaredprices' ++ inferredprices'
    -- Group by commodity pair
    grouped = M.fromListWith (++)
      [((mpfrom p, mpto p), [(d, prec, order, p)]) | (d, prec, order, p) <- allprices]
    -- Build inner Map: sort ascending by (date, prec, order), then M.fromList
    -- keeps the last entry per date (highest precedence/parseorder wins)
    buildInnerMap prices =
      prices
      & sortBy compare
      & map (\(d, _, _, p) -> (d, p))
      & M.fromList
  in
    M.map buildInnerMap grouped

-- | Look up effective prices for all commodity pairs at a given date using the index.
-- Returns at most one price per commodity pair: the latest price on or before the date.
-- O(pairs × log n) where n is the number of prices per pair.
lookupEffectivePricesFromIndex :: Day -> PriceIndex -> [MarketPrice]
lookupEffectivePricesFromIndex d idx =
  mapMaybe (fmap snd . M.lookupLE d) (M.elems idx)

-- | Index for default valuation commodity lookup.
-- Maps source commodity to a map of (date -> destination), supporting O(log n) lookup
-- of the latest destination commodity on or before any given date.
type DefaultValuationIndex = M.Map CommoditySymbol (M.Map Day CommoditySymbol)

-- | Build an index for default valuation commodity lookup from a list of market prices.
buildDefaultValuationIndex :: [MarketPrice] -> DefaultValuationIndex
buildDefaultValuationIndex prices =
  let
    -- Label with parse order
    labeled = [(mpfrom p, mpdate p, i, mpto p) | (i, p) <- zip [1..] prices]
    -- Group by source commodity
    grouped = M.fromListWith (++) [(from, [(d, ord, to)]) | (from, d, ord, to) <- labeled]
    -- Build inner Map: sort by (date, parseorder), then M.fromList keeps last (highest parseorder per date)
    buildInnerMap entries = M.fromList [(d, to) | (d, _, to) <- sortBy compare entries]
  in
    M.map buildInnerMap grouped

-- | Combined indexes for efficient price lookup.
data PriceIndexes = PriceIndexes
  { piForward :: !PriceIndex                    -- ^ Index for forward prices (declared + inferred)
  , piDeclaredDefault :: !DefaultValuationIndex -- ^ Index for declared prices (for default valuation)
  , piInferredDefault :: !DefaultValuationIndex -- ^ Index for inferred prices (fallback for default valuation)
  }

-- | Build all price indexes from declared and inferred market prices.
-- This is O(n log n) but done only once.
buildPriceIndexes :: [MarketPrice] -> [MarketPrice] -> PriceIndexes
buildPriceIndexes declaredprices inferredprices = PriceIndexes
  { piForward = buildPriceIndex declaredprices inferredprices
  , piDeclaredDefault = buildDefaultValuationIndex declaredprices
  , piInferredDefault = buildDefaultValuationIndex inferredprices
  }

-- | Look up default valuation commodities for all source commodities at a given date.
-- Fallback logic: declared at date d, then declared at any date, then inferred at date d.
lookupDefaultValuations :: Day -> PriceIndexes -> M.Map CommoditySymbol CommoditySymbol
lookupDefaultValuations d PriceIndexes{..} =
    fromMaybe fallback (tryDeclaredAtDate <|> tryDeclaredLatest)
  where
    nonEmpty m = if M.null m then Nothing else Just m

    tryDeclaredAtDate = nonEmpty $ lookupDefaults (Just d) piDeclaredDefault
    tryDeclaredLatest = nonEmpty $ lookupDefaults Nothing  piDeclaredDefault
    fallback          = lookupDefaults (Just d) piInferredDefault

    lookupDefaults mdate = M.mapMaybe $ \innerMap ->
      case mdate of
        Nothing -> snd <$> M.lookupMax innerMap
        Just dt -> snd <$> M.lookupLE dt innerMap

-- | Generate a price oracle (memoising price lookup function) from a
-- journal's directive-declared and transaction-inferred market
-- prices. For best performance, generate this only once per journal,
-- reusing it across reports if there are more than one, as
-- compoundBalanceCommand does.
-- The boolean argument is whether to infer market prices from
-- transactions or not.
journalPriceOracle :: Bool -> Journal -> PriceOracle
journalPriceOracle infer Journal{jpricedirectives, jinferredmarketprices} =
  let
    declaredprices = map priceDirectiveToMarketPrice jpricedirectives
    inferredprices =
      (if infer then jinferredmarketprices else [])
      & dbg2Msg ("use prices inferred from costs? " <> if infer then "yes" else "no")
    -- Build indexes once for all lookups
    indexes = buildPriceIndexes declaredprices inferredprices
    makepricegraph = memo $ makePriceGraph indexes
  in
    memo $ uncurry3 $ priceLookup makepricegraph

priceDirectiveToMarketPrice :: PriceDirective -> MarketPrice
priceDirectiveToMarketPrice PriceDirective{..} =
  MarketPrice{ mpdate = pddate
             , mpfrom = pdcommodity
             , mpto   = acommodity pdamount
             , mprate = aquantity pdamount
             }

-- | Infer a market price from the given amount and its cost (if any),
-- and make a corresponding price directive on the given date.
-- The price's display precision will be set to show all significant
-- decimal digits; or if they seem to be infinite, defaultPrecisionLimit.
amountPriceDirectiveFromCost :: Day -> Amount -> Maybe PriceDirective
amountPriceDirectiveFromCost d amt@Amount{acommodity=fromcomm, aquantity=n} = case acost amt of
    Just (UnitCost u)           -> Just $ pd{pdamount=u}
    Just (TotalCost t) | n /= 0 -> Just $ pd{pdamount=u}
      where u = amountSetFullPrecisionUpTo Nothing $ divideAmount n t
    _                            -> Nothing
  where
    pd = PriceDirective{pdsourcepos=nullsourcepos, pddate=d, pdcommodity=fromcomm, pdamount=nullamt}

------------------------------------------------------------------------------
-- Converting things to value

-- | Convert all component amounts to cost/selling price if requested, and style them.
mixedAmountToCost :: M.Map CommoditySymbol AmountStyle -> ConversionOp -> MixedAmount -> MixedAmount
mixedAmountToCost styles cost = mapMixedAmount (amountToCost styles cost)

-- | Apply a specified valuation to this mixed amount, using the
-- provided price oracle, commodity styles, and reference dates.
-- See amountApplyValuation.
mixedAmountApplyValuation :: PriceOracle -> M.Map CommoditySymbol AmountStyle -> Day -> Day -> Day -> ValuationType -> MixedAmount -> MixedAmount
mixedAmountApplyValuation priceoracle styles periodlast today postingdate v =
  mapMixedAmount (amountApplyValuation priceoracle styles periodlast today postingdate v)

-- | Convert an Amount to its cost if requested, and style it appropriately.
amountToCost :: M.Map CommoditySymbol AmountStyle -> ConversionOp -> Amount -> Amount
amountToCost styles ToCost           = styleAmounts styles . amountCostBasis
amountToCost styles ToTransactedCost = styleAmounts styles . amountCost
amountToCost _      NoConversionOp   = id

-- | Apply a specified valuation to this amount, using the provided
-- price oracle, and reference dates. Also fix up its display style
-- using the provided commodity styles.
--
-- When the valuation requires converting to another commodity, a
-- valuation (conversion) date is chosen based on the valuation type
-- and the provided reference dates. It will be one of:
--
-- - the date of the posting itself (--value=then)
--
-- - the provided "period end" date - this is typically the last day
--   of a subperiod (--value=end with a multi-period report), or of
--   the specified report period or the journal (--value=end with a
--   single-period report).
--
-- - the provided "today" date (--value=now).
--
-- - a fixed date specified by the ValuationType itself
--   (--value=DATE).
--
-- This is all a bit complicated. See the reference doc at
-- https://hledger.org/hledger.html#effect-of-valuation-on-reports
-- (hledger_options.m4.md "Effect of valuation on reports"), and #1083.
--
amountApplyValuation :: PriceOracle -> M.Map CommoditySymbol AmountStyle -> Day -> Day -> Day -> ValuationType -> Amount -> Amount
amountApplyValuation priceoracle styles periodlast today postingdate v a =
  case v of
    AtThen    mc      -> amountValueAtDate priceoracle styles mc postingdate a
    AtEnd     mc      -> amountValueAtDate priceoracle styles mc periodlast a
    AtNow     mc      -> amountValueAtDate priceoracle styles mc today a
    AtDate d  mc      -> amountValueAtDate priceoracle styles mc d a

-- | Find the market value of each component amount in the given
-- commodity, or its default valuation commodity, at the given
-- valuation date, using the given market price oracle.
-- When market prices available on that date are not sufficient to
-- calculate the value, amounts are left unchanged.
mixedAmountValueAtDate :: PriceOracle -> M.Map CommoditySymbol AmountStyle -> Maybe CommoditySymbol -> Day -> MixedAmount -> MixedAmount
mixedAmountValueAtDate priceoracle styles mc d = mapMixedAmount (amountValueAtDate priceoracle styles mc d)

-- | Find the market value of this amount in the given valuation
-- commodity if any, otherwise the default valuation commodity, at the
-- given valuation date. (The default valuation commodity is the
-- commodity of the latest applicable market price before the
-- valuation date.)
--
-- The returned amount will have its commodity's canonical style applied,
-- (with soft display rounding).
--
-- If the market prices available on that date are not sufficient to
-- calculate this value, the amount is left unchanged.
--
amountValueAtDate :: PriceOracle -> M.Map CommoditySymbol AmountStyle -> Maybe CommoditySymbol -> Day -> Amount -> Amount
amountValueAtDate priceoracle styles mto d a =
  let lbl = lbl_ "amountValueAtDate" in
  case priceoracle (d, acommodity a, mto) of
    Nothing           -> a
    Just (comm, rate) ->
      nullamt{acommodity=comm, aquantity=rate * aquantity a}

      -- Manage style and precision of the new amount. Initially:
      --  rate is a Decimal with the internal precision of the original market price declaration.
      --  aquantity is a Decimal with a's internal precision.
      --  The calculated value's internal precision may be different from these.
      --  Its display precision will be that of nullamt (0).
      -- Now apply the standard display style for comm (if there is one)
      & styleAmounts styles
      -- set the display precision to match the internal precision (showing all digits),
      -- unnormalised (don't strip trailing zeros);
      -- but if it looks like an infinite decimal, limit the precision to 8.
      & amountSetFullPrecisionUpTo Nothing
      & dbg9With (lbl "calculated value".showAmount)

-- | Calculate the gain of each component amount, that is the difference
-- between the valued amount and the value of the cost basis (see
-- mixedAmountApplyValuation).
--
-- Note: the cost subtracted here is the sum of every contributing posting's
-- cost basis where known (lot postings), else transacted cost, regardless of
-- direction. For a non-lot disposal posting recording its sale price with @,
-- the negative quantity flips its cost contribution from acquisition cost to
-- negated sale proceeds, so the result accumulates realised gain alongside
-- any unrealised gain on remaining units. In other words, with bare @ this
-- reports total gain since inception; with lot tracking, the unrealised gain
-- on the remaining units.
--
-- If the commodity we are valuing in is not the same as the commodity of the
-- cost, this will value the cost at the same date as the primary amount. This
-- may not be what you want; for example you may want the cost valued at the
-- posting date. If so, let us know and we can change this behaviour.
mixedAmountApplyGain :: PriceOracle -> M.Map CommoditySymbol AmountStyle -> Day -> Day -> Day -> ValuationType -> MixedAmount -> MixedAmount
mixedAmountApplyGain priceoracle styles periodlast today postingdate v ma =
  mixedAmountApplyValuation priceoracle styles periodlast today postingdate v $ ma `maMinus` mixedAmountCostBasis ma

-- | Calculate the gain of each component amount, that is the
-- difference between the valued amount and the value of the cost basis.
--
-- If the commodity we are valuing in is not the same as the commodity of the
-- cost, this will value the cost at the same date as the primary amount. This
-- may not be what you want; for example you may want the cost valued at the
-- posting date. If so, let us know and we can change this behaviour.
mixedAmountGainAtDate :: PriceOracle -> M.Map CommoditySymbol AmountStyle -> Maybe CommoditySymbol -> Day -> MixedAmount -> MixedAmount
mixedAmountGainAtDate priceoracle styles mto d ma =
  mixedAmountValueAtDate priceoracle styles mto d $ ma `maMinus` mixedAmountCostBasis ma

------------------------------------------------------------------------------
-- Market price lookup

-- | Given a memoising price graph generator, a valuation date, a
-- source commodity and an optional valuation commodity, find the
-- value on that date of one unit of the source commodity in the
-- valuation commodity, or in a default valuation commodity. Returns
-- the valuation commodity that was specified or chosen, and the
-- quantity of it that one unit of the source commodity is worth. Or
-- if no applicable market price can be found or calculated, or if the
-- source commodity and the valuation commodity are the same, returns
-- Nothing.
--
-- See makePriceGraph for how prices are determined.
-- Note that both market prices and default valuation commodities can
-- vary with valuation date, since that determines which market prices
-- are visible.
--
priceLookup :: (Day -> PriceGraph) -> Day -> CommoditySymbol -> Maybe CommoditySymbol -> Maybe (CommoditySymbol, Quantity)
priceLookup makepricegraph d from mto =
  -- trace ("priceLookup ("++show d++", "++show from++", "++show mto++")") $
  let
    PriceGraph{pgEdges=forwardprices
              ,pgEdgesRev=allprices
              ,pgDefaultValuationCommodities=defaultdests
              } =
      dbg1Msg ("valuation date: "++show d) $ makepricegraph d
    mto' = mto <|> mdefaultto
      where
        mdefaultto = dbg1 ("default valuation commodity for "++T.unpack from) $
                     M.lookup from defaultdests
  in
    case mto' of
      Nothing            -> Nothing
      Just to | to==from -> Nothing
      Just to            ->
        -- We have a commodity to convert to. Find the most direct price available,
        -- according to the rules described in makePriceGraph.
        let
          msg = printf "seeking %s to %s price" (showCommoditySymbol from) (showCommoditySymbol to)
          prices =
            (dbg2Msg (msg++" using forward prices") $
             dbg2Msg ("forward prices:\n" <> showMarketPrices forwardprices) $
             pricesShortestPath from to forwardprices)
            <|>
            (dbg2Msg (msg++" using forward and reverse prices") $
             dbg2Msg ("forward and reverse prices:\n" <> showMarketPrices allprices) $
             pricesShortestPath from to $ dbg5 "all forward and reverse prices" allprices)
        in case prices of
          Nothing -> Nothing
          Just [] -> Nothing
          Just ps -> Just (mpto $ last ps, rate)
            where
              rates = map mprate ps
              rate =
                -- aggregate all the prices into one
                product rates
                -- product (Decimal's Num instance) normalises, stripping trailing zeros.
                -- But we want to preserve even those, since the number of decimal digits
                -- here will guide amountValueAtDate in setting the Amount display precision later.
                -- So we restore them. Or rather, we ensure as many decimal digits as the maximum seen among rates.
                -- (Some prices might end up more precise than they were, but that seems harmless here.)
                & setMinDecimalPlaces (maximum $ map decimalPlaces rates)

-- Ensure this Decimal has at least this many decimal places, adding trailing zeros if necessary.
setMinDecimalPlaces :: Word8 -> Decimal -> Decimal
setMinDecimalPlaces n d
  | decimalPlaces d < n = roundTo n d  -- too few, add some zeros
  | otherwise           = d            -- more than enough, keep as-is

tests_priceLookup =
  let
    p y m d from q to = MarketPrice{mpdate=fromGregorian y m d, mpfrom=from, mpto=to, mprate=q}
    ps1 = [
       p 2000 01 01 "A" 10 "B"
      ,p 2000 01 01 "B" 10 "C"
      ,p 2000 01 01 "C" 10 "D"
      ,p 2000 01 01 "E"  2 "D"
      ,p 2001 01 01 "A" 11 "B"
      ]
    makepricegraph = makePriceGraph (buildPriceIndexes ps1 [])
  in testCase "priceLookup" $ do
    priceLookup makepricegraph (fromGregorian 1999 01 01) "A" Nothing    @?= Nothing
    priceLookup makepricegraph (fromGregorian 2000 01 01) "A" Nothing    @?= Just ("B",10)
    priceLookup makepricegraph (fromGregorian 2000 01 01) "B" (Just "A") @?= Just ("A",0.1)
    priceLookup makepricegraph (fromGregorian 2000 01 01) "A" (Just "E") @?= Just ("E",500)

------------------------------------------------------------------------------
-- Market price graph
-- built directly with MarketPrices for now, probably space-inefficient

type Edge = MarketPrice
type Path = [Edge]

data PriceGraph = PriceGraph {
   pgDate :: Day
    -- ^ The date on which these prices are in effect.
  ,pgEdges :: [Edge]
    -- ^ "Forward" exchange rates between commodity pairs, either
    --   declared by P directives or (with --infer-market-prices) inferred from costs,
    --   forming the edges of a directed graph.  
  ,pgEdgesRev :: [Edge]
    -- ^ The same edges, plus any additional edges that can be
    --   inferred by reversing them and inverting the rates.
    --
    --   In both of these there will be at most one edge between each
    --   directed pair of commodities, eg there can be one USD->EUR and one EUR->USD.
    --
  ,pgDefaultValuationCommodities :: M.Map CommoditySymbol CommoditySymbol
    -- ^ The default valuation commodity for each source commodity.
    --   These are used when a valuation commodity is not specified
    --   (-V). They are the destination commodity of each source commodity's
    --   latest (declared or inferred, but not reverse) market price
    --   (on the date of this graph).
  }
  deriving (Show,Generic)

-- | Find the shortest path and corresponding conversion rate, if any, 
-- from one commodity to another using the provided market prices which
-- form the edges of a directed graph. There should be at most one edge
-- between each directed pair of commodities, eg there can be one
-- USD->EUR price and one EUR->USD price.
pricesShortestPath :: CommoditySymbol -> CommoditySymbol -> [Edge] -> Maybe Path
pricesShortestPath start end edges =
  -- at --debug=2 +, print the pretty path and also the detailed prices
  let label = printf "shortest path from %s to %s: " (showCommoditySymbol start) (showCommoditySymbol end) in
  fmap (dbg2With (("price chain:\n"++).showMarketPrices)) $
  dbg2With ((label++).(maybe "none" (pshowpath ""))) $
  find [([],edges)]

  where
    -- Find the first and shortest complete path using a breadth-first search.
    find :: [(Path,[Edge])] -> Maybe Path
    find paths =
      case concatMap extend paths of
        [] -> Nothing 
        _ | pathlength > maxpathlength -> 
          -- Print a non-fatal warning to stderr, something we usually avoid.
          warn ("gave up searching for a price chain at length "++show maxpathlength++", please report a bug")
          Nothing
          where 
            pathlength = 2 + maybe 0 (length . fst) (headMay paths)
            maxpathlength = 1000
        paths' -> 
          case completepaths of
                p:_ -> Just p  -- the left-most complete path at this length
                []  -> find paths'
          where completepaths = [p | (p,_) <- paths', (mpto <$> lastMay p) == Just end]

    -- Use all applicable edges from those provided to extend this path by one step,
    -- returning zero or more new (path, remaining edges) pairs.
    extend :: (Path,[Edge]) -> [(Path,[Edge])]
    extend (path,unusededges) =
      let
        pathnodes = start : map mpto path
        pathend = maybe start mpto $ lastMay path
        (nextedges,remainingedges) = partition ((==pathend).mpfrom) unusededges
      in
        [ (path', remainingedges')
        | e <- nextedges
        , let path' = dbgpath "trying" $ path ++ [e]  -- PERF prepend ?
        , let pathnodes' = mpto e : pathnodes
        , let remainingedges' = [r | r <- remainingedges, mpto r `notElem` pathnodes' ]
        ]

-- debug helpers
dbgpath  label = dbg2With (pshowpath label)
-- dbgedges label = dbg2With (pshowedges label)
pshowpath label = \case
  []      -> prefix label ""
  p@(e:_) -> prefix label $ pshownode (mpfrom e) ++ ">" ++ intercalate ">" (map (pshownode . mpto) p)
-- pshowedges label = prefix label . intercalate ", " . map (pshowedge "")
-- pshowedge label MarketPrice{..} = pshowedge' label mpfrom mpto
-- pshowedge' label from to = prefix label $ pshownode from ++ ">" ++ pshownode to
pshownode = T.unpack . showCommoditySymbol
prefix l = if null l then (""++) else ((l++": ")++)

-- | A snapshot of the known exchange rates between commodity pairs at a given date.
-- This is a home-made version, more tailored to our needs.
-- | Build the graph of commodity conversion prices for a given day.
-- Converts a list of declared market prices in parse order, and a
-- list of transaction-inferred market prices in parse order, to:
--
-- 1. a graph of all known exchange rates declared or inferred from 
-- one commodity to another in effect on that day
--
-- 2. a second graph which includes any additional exchange rates
-- that can be inferred by reversing known rates
--
-- 3. a map of each commodity's default valuation commodity, if any.
--
-- These allow price lookup and valuation to be performed as
-- described in hledger.m4.md -> Valuation:
--
-- "hledger looks for a market price (exchange rate) from commodity A
-- to commodity B in one or more of these ways, in this order of
-- preference:
--
-- 1. A *declared market price* or *inferred market price*:
--    A's latest market price in B on or before the valuation date
--    as declared by a P directive, or (with the `--infer-market-prices` flag)
--    inferred from transaction prices.
--   
-- 2. A *reverse market price*:
--    the inverse of a declared or inferred market price from B to A.
-- 
-- 3. A *a forward chain of market prices*:
--    a synthetic price formed by combining the shortest chain of
--    "forward" (only 1 above) market prices, leading from A to B.
--
-- 4. A *any chain of market prices*:
--    a chain of any market prices, including both forward and
--    reverse prices (1 and 2 above), leading from A to B."
--
-- and: "For each commodity A, hledger picks a default valuation
-- commodity as follows, in this order of preference:
--
-- 1. The price commodity from the latest declared market price for A
--    on or before valuation date.
--
-- 2. The price commodity from the latest declared market price for A
--    on any date. (Allows conversion to proceed if there are inferred
--    prices before the valuation date.)
--
-- 3. If there are no P directives at all (any commodity or date), and
--    the `--infer-market-prices` flag is used, then the price commodity from
--    the latest transaction price for A on or before valuation date."
--
-- | Build the price graph using pre-built indexes for O(pairs × log n) lookup.
makePriceGraph :: PriceIndexes -> Day -> PriceGraph
makePriceGraph indexes d =
  dbg9 ("makePriceGraph "++show d) $
  PriceGraph{
     pgDate = d
    ,pgEdges=forwardprices
    ,pgEdgesRev=allprices
    ,pgDefaultValuationCommodities=defaultdests
    }
  where
    -- XXX logic duplicated in Hledger.Cli.Commands.Prices.prices, keep synced

    -- get the latest effective price for each commodity pair on or before date d
    forwardprices = dbg9 "effective forward prices" $
      lookupEffectivePricesFromIndex d (piForward indexes)

    -- infer any additional reverse prices not already declared or inferred
    reverseprices = dbg9 "additional reverse prices" $
      [p | p@MarketPrice{..} <- map marketPriceReverse forwardprices
         , not $ (mpfrom,mpto) `S.member` forwardpairs
      ]
      where
        forwardpairs = S.fromList [(mpfrom,mpto) | MarketPrice{..} <- forwardprices]
    allprices = forwardprices ++ reverseprices

    -- use indexed lookup for default valuation commodities
    defaultdests = dbg9 "default valuation commodities" $
      lookupDefaultValuations d indexes

marketPriceReverse :: MarketPrice -> MarketPrice
marketPriceReverse mp@MarketPrice{..} = 
  mp{mpfrom=mpto, mpto=mpfrom, mprate=if mprate==0 then 0 else 1/mprate}  -- PARTIAL: /

nullmarketprice :: MarketPrice
nullmarketprice = MarketPrice {
   mpdate=nulldate
  ,mpfrom=""
  ,mpto=""
  ,mprate=0
  }

------------------------------------------------------------------------------

tests_Valuation = testGroup "Valuation" [
   tests_priceLookup
  ,testCase "marketPriceReverse" $ do
    marketPriceReverse nullmarketprice{mprate=2} @?= nullmarketprice{mprate=0.5}
    marketPriceReverse nullmarketprice @?= nullmarketprice  -- the reverse of a 0 price is a 0 price


  ]
