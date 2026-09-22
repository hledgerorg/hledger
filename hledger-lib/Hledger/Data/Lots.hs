{-|
Lot tracking for investment accounting.

This module implements two pipeline stages (see doc\/SPEC-finalising.md):

1. Classification ('journalClassifyLotPostings'): identifies lot postings
   and tags them as acquire, dispose, transfer-from, or transfer-to.

2. Calculation ('journalCalculateLots'): walks transactions in date order,
   accumulating a map from commodities to their lots, and:

   - For acquire postings: generates lot names from cost basis and appends
     them to the account name as subaccounts.

   - For dispose postings: selects an existing lot subaccount matched by
     the posting's lot selector, using the configured reduction method
     (FIFO by default, configurable per account\/commodity via @lots:@ tag).
     If needed and if the lot selector permits it, selects multiple lots,
     splitting the posting into one per lot.
     Dispose postings with a transacted price (selling price) generate gain postings.
     Bare disposes without a price (e.g. fee deductions) get lot subaccounts but no gain.

   - For transfer postings: selects lots from the source account (like
     dispose) and recreates them under the destination account. The lot's
     cost basis is preserved through the transfer.
     Multi-lot transfers are supported (eg via @{}@ to transfer all lots).

For background, see doc\/SPEC-lots.md and doc\/PLAN-lots.md.

== Errors

User-visible errors from this module. See also Hledger.Data.Errors and doc/ERRORS.md.

journalCalculateLots:

* validateUserLabels:
  "lot id is not unique: commodity X, date D, label L"

* processAcquirePosting:
  "acquire posting has no cost basis",
  "...has multiple cost basis amounts",
  "X is lotful but this acquire posting has no cost basis or price",
  "...has no lot cost",
  "duplicate lot id: {...} for commodity X"

* processDisposePosting:
  "dispose posting has no cost basis",
  "...has no transacted price (selling price)",
  "...has non-negative quantity",
  "SPECID requires a lot selector",
  "lot ... has no cost basis (internal error)",
  "lot subaccount ... does not match resolved lot"

* groupIndexedTransferPostings:
  "transfer-to/from posting ... has no matching ... posting",
  "Mismatched transfer quantities for lot-tracked commodity X",
  "... posting has no lotful commodity"

* processTransferGroup:
  "transfer-from posting has no cost basis",
  "...has multiple cost basis amounts",
  "lot transfers should have no transacted price",
  "transfer-from posting has non-negative quantity",
  "transfer-to posting has no single positive X amount",
  "could not distribute transferred lots exactly (internal error)",
  "lot ... has no cost basis (internal error)",
  "lot cost basis ... does not match transfer-to cost basis"

* selectLots:
  "SPECID requires an explicit lot selector",
  "no X lots available for transfer/disposal from account Y on DATE",
  "no lots matching {...} for commodity X in account Y on DATE",
  "lot selector is ambiguous, matches N lots in account Y",
  "Insufficient lots for commodity X in account Y"

* validateGlobalCompliance:
  "METHOD: lot(s) on other account(s) have higher priority than the lots in ACCT"

* poolWeightedAvgCost:
  "no lots with cost basis available for averaging",
  "cannot average lots with different cost commodities",
  "cannot average lots with zero total quantity"

* foldMPostings (via isUnclassifiedLotfulPosting):
  "X is declared lotful ... but this posting was not classified"
  (exempt: zero-amount lotful postings)

-}

{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NamedFieldPuns #-}

module Hledger.Data.Lots (
  journalClassifyLotPostings,
  journalStripBalancerCopiedBases,
  transactionAutoSplitFeeOutflows,
  journalCalculateLots,
  journalCheckAcquireBasis,
  journalCheckLotsMethodCoherence,
  journalCollapseLotDetail,
  journalTagGainPostings,
  transactionTagGainPostings,
  journalAddOrCheckGainPostings,
  isGainPosting,
  lotBaseAccount,
  lotSubaccountName,
  mergeCostBasis,
  parseLotName,
  resolveReductionMethodForAccount,
  showLotName,
) where

import Control.Applicative ((<|>))
import Data.Bifunctor (first)
import Control.Monad (foldM, guard, unless, when)
import Data.List (intercalate, partition, sortOn)
import Data.Ord (Down(..))
#if !MIN_VERSION_base(4,20,0)
import Data.List (foldl')
#endif
import Data.Map.Strict qualified as M
import Data.Maybe (catMaybes, fromMaybe, isJust, isNothing, listToMaybe, mapMaybe)
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import Data.Char (isDigit)
import Data.Decimal (roundTo)
import Data.Time.Calendar (Day, fromGregorianValid)
import Text.Printf (printf)

import Hledger.Data.AccountName (accountNameType, parentAccountNames)
import Hledger.Data.AccountType (isAssetType, isEquityType, isLiabilityType)
import Hledger.Data.Amount (AmountFormat(..), amountRoundedQuantity, amountSetPrecisionMin, amountSetQuantity, amountsRaw, divideAmountAndUpdatePrecision, isNegativeAmount, maNegate, maSum, mapMixedAmount, mixedAmount, mixedAmountCost, mixedAmountIsZero, mixedAmountLooksZero, nullmixedamt, noCostFmt, oneLineNoCostFmt, showAmountWith, showAmountsDistinctly, showMixedAmountOneLine, showMixedAmountsDistinctly)
import Hledger.Data.Errors (makeAccountTagErrorExcerpt, makeCommodityTagErrorExcerpt, makePostingErrorExcerptByIndex, makeTransactionErrorExcerpt, transactionFindPostingIndex)
import Hledger.Data.Journal (journalAccountType, journalAccountUsesNoLots, journalBaseGainAccount, journalCommodityLotsMethod, journalCommodityStylesWith, journalCommodityUsesLots, journalInheritedAccountTags, journalMapPostings, journalMapTransactions, journalPostings, journalTieTransactions, parseReductionMethod)
import Hledger.Data.Posting (generatedPostingTagName, hasAmount, isReal, isVirtual, lotParentAssertionTagName, lotsplitPostingTagName, nullposting, originalPosting, postingAddHiddenAndMaybeVisibleTag, postingHasTag, postingStripCosts, feesplitPostingTagName)
import Hledger.Data.Transaction (transactionCommodityStyles, txnTieKnot)
import Hledger.Data.Types
import Hledger.Utils (dbg5, dbg5With)

-- Types

-- | Map from commodity to (map from lot id to (map from account name to lot balance)).
-- Keyed by commodity at the top level so lots of different commodities don't clash.
-- The inner Map LotId is ordered by date then label, supporting FIFO/LIFO naturally.
-- The innermost Map AccountName allows the same lot to exist at multiple accounts
-- (eg after a partial lot transfer).
type LotState = M.Map CommoditySymbol (M.Map LotId (M.Map AccountName Amount))

-- | Resolve which reduction method to use for a posting, and where it came from.
-- Checks account-inherited tags first, then commodity tags, defaulting to FIFO.
-- Since commodity tags are propagated to ptags, we distinguish by checking the
-- commodity's own declared tags separately.
resolveReductionMethodWithSource :: Journal -> Posting -> CommoditySymbol -> (ReductionMethod, String)
resolveReductionMethodWithSource j p = resolveReductionMethodForAccount j (paccount p)

-- | Resolve which reduction method is in effect for an account and commodity,
-- and where it came from: the account's (inherited) lots: tag if any,
-- else the commodity's lots: tag value if any, else FIFO.
resolveReductionMethodForAccount :: Journal -> AccountName -> CommoditySymbol -> (ReductionMethod, String)
resolveReductionMethodForAccount j acct commodity =
  case accountLotsMethod of
    Just m  -> (m, "from account tag on " ++ T.unpack acct)
    Nothing -> case journalCommodityLotsMethod j commodity of
      Just m  -> (m, "from commodity tag on " ++ T.unpack commodity)
      Nothing -> (FIFO, "default")
  where
    -- Check account-inherited tags only (excluding commodity-propagated tags).
    accountLotsMethod =
      let acctTags = journalInheritedAccountTags j acct
      in case [v | (k, v) <- acctTags, T.toLower k == "lots"] of
           (v:_) -> parseReductionMethod v
           []    -> Nothing

-- | Check that global (*ALL) reduction methods are used coherently:
-- when any account holding a lot-tracked commodity resolves to a global
-- method, every account holding that commodity must resolve to the same
-- method. Mixing a global method with any other is rejected, because the
-- global validation (and, for AVERAGEALL, the global pool updates) only
-- make sense when every account participates. Local methods (FIFO, LIFO,
-- HIFO, SPECID, AVERAGE) may be mixed per account freely.
journalCheckLotsMethodCoherence :: Journal -> Either String Journal
journalCheckLotsMethodCoherence j = do
    mapM_ checkCommodity (M.toList holdings)
    Right j
  where
    -- The base accounts holding each lot-tracked commodity (postings with
    -- a cost basis annotation, or a lotful commodity in an account that
    -- hasn't opted out of lot tracking with lots: NONE).
    holdings :: M.Map CommoditySymbol (S.Set AccountName)
    holdings = M.fromListWith S.union
      [ (acommodity a, S.singleton acct)
      | p <- journalPostings j
      , let acct = lotBaseAccount (paccount p)
      , a <- amountsRaw (pamount p)
      , isJust (acostbasis a)
        || (journalCommodityUsesLots j (acommodity a) && not (journalAccountUsesNoLots j acct)) ]

    resolutions c accts = [ (acct, m, src)
                          | acct <- S.toList accts
                          , let (m, src) = resolveReductionMethodForAccount j acct c ]

    checkCommodity (c, accts) =
      case [r | r@(_, m, _) <- rs, methodIsGlobal m] of
        [] -> Right ()
        (gacct, gmethod, gsrc):_ ->
          case [r | r@(_, m, _) <- rs, m /= gmethod] of
            []        -> Right ()
            conflicts -> Left $ errmsg c gacct gmethod gsrc conflicts
      where rs = resolutions c accts

    errmsg c gacct gmethod gsrc conflicts =
         maybe "" (\(f, l, _, ex) -> printf "%s:%d:\n%s\n" f l ex) (methodDecl gacct c)
      ++ T.unpack c ++ " uses the global method " ++ show gmethod ++ " (" ++ gsrc ++ ")"
      ++ " in " ++ T.unpack gacct ++ ",\nbut a different method elsewhere:\n"
      ++ unlines ["  " ++ T.unpack acct ++ " uses " ++ show m ++ " (" ++ src ++ ")" | (acct, m, src) <- conflicts]
      ++ "A global (*ALL) method must be used by every account holding the commodity.\n"
      ++ "Declare it once on the commodity declaration, and remove conflicting account lots: tags."

    -- The declaration providing an account's method for a commodity,
    -- rendered as an error excerpt: the nearest self-or-ancestor account
    -- declaration with a method-valued lots: tag, else the commodity's
    -- declaration. Mirrors resolveReductionMethodForAccount's precedence.
    methodDecl :: AccountName -> CommoditySymbol -> Maybe (FilePath, Int, Maybe (Int, Maybe Int), Text)
    methodDecl acct c =
      case [ (a', adi) | a' <- acct : parentAccountNames acct
                       , Just adi <- [lookup a' (jdeclaredaccounts j)]
                       , any isMethodTag (aditags adi) ] of
        ((a', adi):_) -> Just $ makeAccountTagErrorExcerpt (a', adi) "lots"
        []            -> (`makeCommodityTagErrorExcerpt` "lots") <$> M.lookup c (jdeclaredcommodities j)
      where isMethodTag (k, v) = T.toLower k == "lots" && isJust (parseReductionMethod v)

-- | If the account name's final colon-separated component is enclosed in @{@
-- and @}@, treat it as a lot subaccount and return @Just (base, "{...}")@.
-- Otherwise return @Nothing@.
-- Full validation of the lot name (parts, dates, costs) is left to 'parseLotName';
-- this function only identifies candidates so they can be validated uniformly.
splitLotSubaccount :: AccountName -> Maybe (AccountName, Text)
splitLotSubaccount a = do
  let (prefix, leaf) = T.breakOnEnd ":" a
  guard $ not (T.null prefix)
  guard $ "{" `T.isPrefixOf` leaf
  guard $ "}" `T.isSuffixOf` leaf
  Just (T.dropEnd 1 prefix, leaf)

-- | Strip any trailing lot subaccount (a final @:{...}@ component) from an
-- account name. E.g., @\"assets:broker:{2026-01-15, $50}\"@ becomes
-- @\"assets:broker\"@.
lotBaseAccount :: AccountName -> AccountName
lotBaseAccount a = maybe a fst (splitLotSubaccount a)

-- | Render a lot name in the consolidated hledger format for use as a subaccount name.
-- Format: @{YYYY-MM-DD, COST}@ or @{YYYY-MM-DD, \"LABEL\", COST}@.
-- The cost amount is rendered using its own intrinsic style. Callers that want
-- the journal's canonical commodity styles applied (eg when building a lot
-- subaccount name) should pre-style the 'CostBasis' with 'styleLotCbCost'.
showLotName :: CostBasis -> T.Text
showLotName CostBasis{cbDate, cbLabel, cbCost} =
  "{" <> T.intercalate ", " parts <> "}"
  where
    parts = catMaybes
      [ fmap (T.pack . show) cbDate
      , fmap (\l -> "\"" <> l <> "\"") cbLabel
      -- Show a zero cost with its commodity symbol (eg $0), not as a bare 0:
      -- the name is the lot's basis of record, and must round-trip faithfully.
      , fmap (T.pack . showAmountWith noCostFmt{displayZeroCommodity=True}) cbCost
      ]

-- | Apply the journal's canonical commodity styles to a 'CostBasis's cost
-- amount, for consistent rendering of the amount inside a lot subaccount name.
-- Styles should have been computed with 'NoRounding' (preserving the original
-- decimal digits); all other style fields — decimal mark, digit group separators,
-- commodity position and spacing — come from the canonical style.
styleLotCbCost :: M.Map CommoditySymbol AmountStyle -> CostBasis -> CostBasis
styleLotCbCost styles cb = cb{cbCost = styleAmounts styles <$> cbCost cb}

-- | Widen a 'CostBasis's cost amount's display precision to at least the
-- commodity style's declared precision (if any), so eg with @commodity €1.00@
-- an inferred per-unit cost of 2.5 renders as @2.50@. For user-written
-- explicit costs, prefer 'styleLotCbCost' alone (no widening).
widenLotCbCost :: M.Map CommoditySymbol AmountStyle -> CostBasis -> CostBasis
widenLotCbCost styles cb = cb{cbCost = widen <$> cbCost cb}
  where
    widen a = case M.lookup (acommodity a) styles of
      Just AmountStyle{asprecision = Precision p} -> amountSetPrecisionMin p a
      _                                           -> a

-- | Render a lot subaccount name, dropping the cost component under AVERAGE/AVERAGEALL.
-- AVERAGE pools share a single running per-unit cost that changes on every
-- acquisition; embedding it in the subaccount name would make the subaccount
-- unstable across acquisitions. The running cost remains on each lot's
-- @acostbasis@ for use by reports and @print --lots@.
showLotNameForMethod :: ReductionMethod -> CostBasis -> T.Text
showLotNameForMethod method cb
  | methodIsAverage method = showLotName cb{cbCost = Nothing}
  | otherwise              = showLotName cb

-- | Like 'mergeCostBasis', but under AVERAGE/AVERAGEALL the cost field is
-- ignored: the pool's running cost legitimately differs from what the user
-- wrote on any specific acquire posting.
mergeCostBasisForMethod :: ReductionMethod -> CostBasis -> CostBasis -> Either String CostBasis
mergeCostBasisForMethod method a b
  | methodIsAverage method = mergeCostBasis a{cbCost = Nothing} b{cbCost = Nothing}
  | otherwise              = mergeCostBasis a b

-- | Extract the lot subaccount name (the @{...}@ component) from an account name,
-- or @Nothing@ if there is none.
-- E.g., @\"assets:broker:{2026-01-15, $50}\"@ returns @Just \"{2026-01-15, $50}\"@.
lotSubaccountName :: AccountName -> Maybe Text
lotSubaccountName = fmap snd . splitLotSubaccount

-- | Parse a lot name (as produced by 'showLotName') back into a 'CostBasis'.
-- The input should be the full @{...}@ string including braces.
-- Parts are comma-separated and all optional: date (@YYYY-MM-DD@),
-- label (@\"LABEL\"@), and cost (parsed by the supplied callback).
-- The callback avoids an import cycle (Lots.hs cannot import Read-layer parsers).
parseLotName :: (String -> Maybe Amount) -> Text -> Either String CostBasis
parseLotName parseAmt t = do
  inner <- case T.stripPrefix "{" t >>= T.stripSuffix "}" of
    Just s  -> Right (T.strip s)
    Nothing -> Left $ "lot name must be enclosed in braces: " ++ T.unpack t
  if T.null inner
    then Right $ CostBasis Nothing Nothing Nothing
    else do
      let parts = map T.strip $ splitParts inner
      parseParts parts
  where
    parseParts parts = go parts Nothing Nothing Nothing
      where
        go [] d l c = Right $ CostBasis d l c
        go (p:ps) d l c
          | isDatePart p = case parseDate p of
              Just day -> go ps (Just day) l c
              Nothing  -> Left $ "invalid date in lot name: " ++ T.unpack p
          | isLabelPart p = go ps d (Just (T.drop 1 (T.dropEnd 1 p))) c
          | otherwise = case parseAmt (T.unpack p) of
              Just amt -> go ps d l (Just amt)
              Nothing  -> Left $ fromMaybe ("invalid lot name: " ++ T.unpack p)
                                           (missingDateCommaHint p)

        -- If a part starts with what looks like a date but no comma followed,
        -- the user probably forgot the comma (eg @{2026-01-15 $10}@). Show a
        -- corrected form to make the fix obvious.
        missingDateCommaHint :: Text -> Maybe String
        missingDateCommaHint p
          | T.length p > 10
          , let (candidate, rest) = T.splitAt 10 p
          , isDatePart candidate
          , let rest' = T.stripStart rest
          , not (T.null rest')
          , T.head rest' /= ','
          = Just $ "Missing comma in lot name: " ++ T.unpack p
                ++ "\nDid you mean:              " ++ T.unpack candidate ++ ", " ++ T.unpack rest' ++ " ?"
          | otherwise = Nothing

    isDatePart p = T.length p == 10 && T.all (\c -> isDigit c || c == '-') p
    isLabelPart p = "\"" `T.isPrefixOf` p && "\"" `T.isSuffixOf` p && T.length p >= 2

    parseDate p = do
      let s = T.unpack p
      case s of
        [y1,y2,y3,y4,'-',m1,m2,'-',d1,d2] ->
          fromGregorianValid
            (read [y1,y2,y3,y4])
            (read [m1,m2])
            (read [d1,d2])
        _ -> Nothing

    -- Split the inner text of a lot name into up to 3 parts (date, label, cost)
    -- by peeling known-format prefixes in DLC order, exploiting the fact that
    -- dates and labels have unambiguous syntax.  This avoids splitting on commas,
    -- which would break when the cost amount contains a decimal comma (e.g. @1,5@)
    -- or when the commodity symbol contains commas (e.g. @"an, odd, commodity"@).
    -- After each part, @,@ followed by optional whitespace is consumed.
    --
    -- Examples:
    -- @"2026-01-15, \"my, label\", €1,50"@               -> @["2026-01-15", "\"my, label\"", "€1,50"]@
    -- @"2026-01-15, \"an, odd, commodity\" 1,5"@          -> @["2026-01-15", "\"an, odd, commodity\" 1,5"]@
    -- @"2026-01-15, \"a, b\", \"an, odd, commodity\" 1,5" -> @["2026-01-15", "\"a, b\"", "\"an, odd, commodity\" 1,5"]@
    -- @"$100"@                                            -> @["$100"]@
    splitParts :: Text -> [Text]
    splitParts s =
      let (mdate, s1) = peelDate s
          (mlabel, s2) = peelLabel s1
          mcost = let c = T.strip s2 in if T.null c then Nothing else Just c
      in catMaybes [mdate, mlabel, mcost]

    -- Try to peel a date (YYYY-MM-DD) from the front. Returns the date text
    -- and the remainder after stripping a comma separator, or Nothing and the
    -- unchanged input. Requires that the date candidate is followed by end of
    -- string or a comma with optional surrounding whitespace (to keep the 
    -- syntax regular; gives a helpful error if the comma is missing).
    peelDate :: Text -> (Maybe Text, Text)
    peelDate s
      | T.length s >= 10
      , let (candidate, rest) = T.splitAt 10 s
      , isDatePart candidate
      , properBoundary rest
      = (Just candidate, stripSep rest)
      | otherwise = (Nothing, s)
      where
        properBoundary txt = case T.uncons (T.stripStart txt) of
          Nothing       -> True
          Just (',', _) -> True
          _             -> False

    -- Try to peel a double-quoted label from the front. Scans from the opening
    -- quote to the next closing quote. A quoted string is only treated as a
    -- label if it is followed by a comma separator or end of input. If it is
    -- followed by digits or other amount-starting characters (after optional
    -- whitespace), it is a quoted commodity symbol that belongs to the cost
    -- amount, so we leave it alone.
    peelLabel :: Text -> (Maybe Text, Text)
    peelLabel s
      | Just s' <- T.stripPrefix "\"" s
      = let (inner, rest) = T.break (== '"') s'
        in case T.uncons rest of
             Just ('"', rest')
               | looksLikeCostRemainder rest' -> (Nothing, s)  -- quoted commodity symbol, not a label
               | otherwise -> (Just ("\"" <> inner <> "\""), stripSep rest')
             _ -> (Nothing, s)  -- malformed, leave for parseAmt
      | otherwise = (Nothing, s)

    -- After a closing quote, does the remainder look like it continues as a
    -- cost amount (i.e. the quoted string was a commodity symbol, not a label)?
    -- True when the next non-space character is a digit, sign, or decimal mark.
    looksLikeCostRemainder :: Text -> Bool
    looksLikeCostRemainder t' =
      case T.uncons (T.stripStart t') of
        Just (c, _) -> isDigit c || c == '+' || c == '-' || c == '.'
        Nothing     -> False

    -- Strip an optional comma and any surrounding whitespace.
    stripSep :: Text -> Text
    stripSep s0 =
      let s1 = T.stripStart s0
      in case T.uncons s1 of
           Just (',', s2) -> T.stripStart s2
           _              -> s1

-- | Do two lot cost amounts refer to the same cost, for lot identification ?
-- True if their commodities match and their quantities are equal exactly,
-- or one equals the other's display-rounded value. The latter lets a
-- displayed lot name (eg an inferred $10/3 cost rendered as $3.33333333)
-- be written back in a journal and still identify the lot, while stored
-- lot costs keep full precision for exact gain arithmetic (#2689).
lotCostsMatch :: Amount -> Amount -> Bool
lotCostsMatch x y =
  acommodity x == acommodity y &&
  (aquantity x == aquantity y
   || aquantity x == amountRoundedQuantity y
   || amountRoundedQuantity x == aquantity y)

-- | Merge two 'CostBasis' values. For each field, if both are @Just@, they
-- must agree (returns error if not); otherwise takes whichever is @Just@.
-- The first argument is typically the account-name basis (more complete),
-- the second is the amount's existing basis.
mergeCostBasis :: CostBasis -> CostBasis -> Either String CostBasis
mergeCostBasis a b = do
  d <- mergeField "date"  show     (cbDate a) (cbDate b)
  l <- mergeField "label" T.unpack (cbLabel a) (cbLabel b)
  c <- mergeCostField (cbCost a) (cbCost b)
  Right $ CostBasis d l c
  where
    mergeField :: Eq a => String -> (a -> String) -> Maybe a -> Maybe a -> Either String (Maybe a)
    mergeField _ _ Nothing  y       = Right y
    mergeField _ _ x       Nothing  = Right x
    mergeField name showVal (Just x) (Just y)
      | x == y    = Right (Just x)
      | otherwise = Left $ "conflicting cost basis " ++ name
                      ++ ": account name has " ++ showVal x
                      ++ " but amount has " ++ showVal y

    mergeCostField :: Maybe Amount -> Maybe Amount -> Either String (Maybe Amount)
    mergeCostField Nothing  y       = Right y
    mergeCostField x       Nothing  = Right x
    mergeCostField (Just x) (Just y)
      | lotCostsMatch x y = Right (Just x)
      | otherwise = Left $ "conflicting cost basis cost"
                      ++ ": account name has " ++ showAmountWith noCostFmt x
                      ++ " but amount has " ++ showAmountWith noCostFmt y

-- Classification (pipeline stage 1)

-- | Classify lot-related postings by adding ptype tags.
-- Must be called after journalAddAccountTypes so account types are available,
-- and after transaction balancing, so that all posting amounts (including
-- ones inferred from elided amounts or balance assignments) are known:
-- classification then gives the same result for every entry shape as if all
-- amounts had been written explicitly (#2686, #2690, #2692).
-- The verbosetags parameter controls whether the ptype tags will be made visible in comments.
-- Before classification, try to auto-split lot transfers with fees
-- into a transfer portion and a dispose portion, so both get classified correctly.
journalClassifyLotPostings :: Bool -> Journal -> Journal
journalClassifyLotPostings verbosetags j =
  journalMapTransactions
    ( txnTieKnot  -- retie the postings' transaction pointers (nothing else does after this)
    . transactionClassifyLotPostings verbosetags lookupType commodityIsLotful accountUsesNoLots
    . transactionAutoSplitFeeOutflows verbosetags lookupType commodityIsLotful accountUsesNoLots
    ) j
  where
    lookupType = journalAccountType j
    commodityIsLotful = journalCommodityUsesLots j
    accountUsesNoLots = journalAccountUsesNoLots j

-- | Detect a lot transfer with a fee - an unpriced negative lotful asset
-- posting (bare in a lotful commodity, or carrying a cost basis annotation)
-- whose absolute quantity exceeds the positive quantities received by
-- asset accounts, where the excess matches a non-asset posting (typically a
-- fee paid in the lotful commodity) - and split it into a transfer portion
-- (matching the positive sum) and a dispose portion, so classification can
-- correctly tag the two roles. When the fee counterpart has a transacted
-- price, the dispose portion carries it (and a gain will be calculated);
-- otherwise the dispose portion is priceless (lots are still reduced, but
-- no gain is calculated).
--
-- If no such pattern is found, the transaction is returned unchanged.
-- The transfer portion inherits the original's identity (poriginal preserves
-- the unsplit quantity, so plain print shows the user's original entry).
-- The dispose portion is tagged `_feesplit-posting` so plain print hides it,
-- and `_generated-posting` to mark its provenance; -x or --verbose-tags
-- reveals it.
-- The original posting's balance assertion is kept only on the dispose
-- portion (the last of the two), so it is still checked after the full
-- original quantity has been posted.
transactionAutoSplitFeeOutflows
  :: Bool
  -> (AccountName -> Maybe AccountType)
  -> (CommoditySymbol -> Bool)
  -> (AccountName -> Bool)
  -> Transaction -> Transaction
transactionAutoSplitFeeOutflows verbosetags lookupAccountType commodityIsLotful accountUsesNoLots t =
    t{tpostings = concatMap (\p -> fromMaybe [p] (trySplit p)) (tpostings t)}
  where
    ps = tpostings t
    isAsset    acct = maybe False isAssetType (lookupAccountType (lotBaseAccount acct))
    isNonAsset acct = not (isAsset acct)
    -- An account with a lots: NONE tag doesn't participate in lot tracking,
    -- unless the posting carries explicit cost basis annotations.
    optedOut p = accountUsesNoLots (lotBaseAccount (paccount p))
                 && not (any (isJust . acostbasis) (amountsRaw (pamount p)))

    -- Try to split posting p into a transfer portion and dispose portion(s).
    -- Requires: a single unpriced negative asset amount, either bare in a
    -- lotful commodity or carrying a cost basis annotation, with matching
    -- non-asset counterpart(s). Positive postings naturally exclude p itself.
    -- Fee fragments from an earlier split (during balancing) are left alone.
    trySplit p = do
      guard $ not (postingHasTag feesplitPostingTagName p)
      guard $ isAsset (paccount p)
      guard $ not (optedOut p)
      [a] <- Just $ amountsRaw (pamount p)
      guard $ aquantity a < 0
           && (commodityIsLotful (acommodity a) || isJust (acostbasis a))
           && isNothing (acost a)
      let comm    = acommodity a
          fromQty = negate (aquantity a)
          toQty   = sum [ aquantity pa
                        | q  <- ps
                        , isAsset (paccount q)
                        , not (optedOut q)
                        , pa <- amountsRaw (pamount q)
                        , acommodity pa == comm
                        , aquantity pa > 0
                        , isNothing (acost pa)
                        ]
          feeQty  = fromQty - toQty
      guard $ toQty > 0 && feeQty > 0
      feeAmts <- findFeeCounterparts comm feeQty
      let origP = originalPosting p
          p1    = p{ pamount = mixedAmount (amountSetQuantity (negate toQty)  a)
                   , poriginal = Just origP
                   , pbalanceassertion = Nothing }
          -- Any balance assertion is kept only on the last portion posted.
          mkFeePart islast fa
                = addTag feesplitPostingTagName
                $ addTag generatedPostingTagName
                $ p{ pamount = mixedAmount (amountSetQuantity (negate (aquantity fa)) a){ acost = acost fa }
                   , poriginal = Just origP
                   , pbalanceassertion = if islast then pbalanceassertion p else Nothing }
          n = length feeAmts
      Just (p1 : [mkFeePart (i == n) fa | (i, fa) <- zip [1..] feeAmts])

    addTag name = postingAddHiddenAndMaybeVisibleTag False verbosetags (name, "")

    -- Find non-asset counterpart posting amounts accounting for the given
    -- fee quantity in the given commodity: the first single amount equal to
    -- it, or otherwise all of the positive amounts, if they sum to it exactly.
    findFeeCounterparts comm qty
      | (fa:_) <- [fa | fa <- candidates, aquantity fa == qty] = Just [fa]
      | not (null candidates) && sum (map aquantity candidates) == qty = Just candidates
      | otherwise = Nothing
      where
        candidates =
          [ pa
          | q  <- ps, isNonAsset (paccount q)
          , pa <- amountsRaw (pamount q)
          , acommodity pa == comm, aquantity pa > 0
          ]

-- | Classify lot-related postings by adding a ptype tag.
-- For each posting with a cost basis (any account type):
-- - determine if it's of type "acquire" or "dispose" (based on amount sign)
-- - or "transfer-from" or "transfer-to" (if counterposting with same commodity exists in a different account).
-- For asset postings without cost basis:
-- - a lotful posting can be classified as "transfer-to" (see shouldClassifyLotful)
-- - a bare positive posting can be classified as "transfer-to" if there's a
--   matching transfer-from counterpart (see shouldClassifyBareTransferTo).
-- The lookupAccountType function should typically be `journalAccountType journal`.
-- The commodityIsLotful function should typically be `journalCommodityUsesLots journal`.
-- The verbosetags parameter controls whether the tags are made visible in comments.
--
-- For more detail on classification rules, please see doc/SPEC-lots.md > Lot postings.
--
transactionClassifyLotPostings :: Bool -> (AccountName -> Maybe AccountType) -> (CommoditySymbol -> Bool) -> (AccountName -> Bool) -> Transaction -> Transaction
transactionClassifyLotPostings verbosetags lookupAccountType commodityIsLotful accountUsesNoLots t@Transaction{tpostings=ps}
  | not (any hasLotRelevantAmount ps)
    = lotDbg t "no lot-relevant amounts, skipping" t
  | otherwise = lotDbg t "classifying" $ t{tpostings=zipWith classifyAt [0..] ps}
  where
    hasCostBasis :: Posting -> Bool
    hasCostBasis p = let amts = amountsRaw (pamount p)
                         result = any (isJust . acostbasis) amts
                     in dbg5 ("classifyLotPostings: hasCostBasis " ++ show (paccount p) ++ " amts=" ++ show (length amts)) result

    -- An account with a lots: NONE tag doesn't participate in lot tracking:
    -- its postings are not classified and are invisible to counterpart
    -- detection - unless they carry explicit cost basis annotations
    -- (the more specific declaration wins).
    optedOut :: Posting -> Bool
    optedOut p = accountUsesNoLots (lotBaseAccount (paccount p)) && not (hasCostBasis p)

    hasLotRelevantAmount :: Posting -> Bool
    hasLotRelevantAmount p = isReal p && not (hasBalancerCopiedBasis p) && not (optedOut p)
      && (hasCostBasis p || hasNegativeLotfulAmount p || hasPositiveLotfulAmount p)

    hasNegativeLotfulAmount :: Posting -> Bool
    hasNegativeLotfulAmount p =
      let amts = amountsRaw (pamount p)
      in not (any (isJust . acostbasis) amts)
         && any isNegativeAmount amts
         && amountsAreLotful amts

    hasPositiveLotfulAmount :: Posting -> Bool
    hasPositiveLotfulAmount p =
      let amts = amountsRaw (pamount p)
      in not (any (isJust . acostbasis) amts)
         && not (any isNegativeAmount amts)
         && any (\a -> aquantity a > 0) amts  -- has a strictly positive amount (not zero or amountless)
         && amountsAreLotful amts

    -- Same-account transfer pairs: within each account, match positive and negative
    -- unpriced postings with the same commodity and absolute quantity as transfer pairs.
    -- When there are more of one sign than the other, the excess are left unmatched
    -- (and will be classified normally as acquire/dispose).
    -- Priced postings are excluded (a priced posting is a deliberate trade,
    -- eg a stock split's dispose/re-acquire postings; and lot transfers may
    -- not have a transacted price, so pairing one would only force an error).
    sameAcctTransferSet :: S.Set Int
    sameAcctTransferSet = S.fromList $ concatMap matchPairs $ M.elems grouped
      where
        grouped :: M.Map (AccountName, CommoditySymbol, Quantity) ([Int], [Int])
        grouped = foldl' addPosting M.empty (zip [0..] ps)
        addPosting m (i, p)
          | not (isReal p) = m
          | not (hasLotRelevantAmount p) = m
          | otherwise = foldl' (addAmt i (lotBaseAccount (paccount p))) m (amountsRaw (pamount p))
        addAmt i acct m a
          | isJust (acost a) = m
          | q < 0     = M.insertWith mergePair (acct, acommodity a, negate q) ([i], []) m
          | q > 0     = M.insertWith mergePair (acct, acommodity a, q)        ([], [i]) m
          | otherwise = m
          where q = aquantity a
        mergePair (n1, p1) (n2, p2) = (n1++n2, p1++p2)
        matchPairs (negs, poss) =
          let n = min (length negs) (length poss)
          in take n negs ++ take n poss

    -- Could this balancer-copied-basis posting (see 'hasBalancerCopiedBasis')
    -- serve as the elided destination or source of a lot transfer? True for
    -- a nonzero, unpriced amount in a lot-tracking asset account. Such
    -- postings are otherwise invisible to classification, since they may be
    -- the artifact of a disposal missing its selling price (positive mirror)
    -- or an acquisition missing its cost (negative mirror); but those
    -- readings would fail anyway (no price / no lot cost), so preferring the
    -- transfer reading only makes otherwise-erroring entries work.
    -- (A forgotten-price disposal is thus read as a lot transfer to the
    -- elided account, quietly; print -a shows the result for checking.)
    isMirroredTransferCandidate :: Posting -> Bool
    isMirroredTransferCandidate p =
      let amts = amountsRaw (pamount p)
          baseAcct = lotBaseAccount (paccount p)
      in maybe False isAssetType (lookupAccountType baseAcct)
         && not (accountUsesNoLots baseAcct)
         && any ((/= 0) . aquantity) amts
         && not (any (isJust . acost) amts)

    -- Precompute per-commodity, per-quantity transfer counterpart info (O(n)).
    -- Keyed by (commodity, |quantity|) for exact quantity matching, the primary
    -- transfer detection; see negSums/posSums below for the sum-based fallback.
    -- For each key, which accounts have:
    --   negative postings with cost basis  (transfer-from candidates; any account type)
    --   positive postings with cost basis  (transfer-to candidates, standard path; any account type)
    --   positive asset postings without cost basis  (transfer-to candidates, bare path; asset only)
    -- Account lists are deduplicated (typically 1-2 accounts per commodity).
    negCBAccts, posCBAccts, posNoCBAccts :: M.Map (CommoditySymbol, Quantity) [AccountName]
    (negCBAccts, posCBAccts, posNoCBAccts) = foldl' collect (M.empty, M.empty, M.empty) (zip [0..] ps)
      where
        collect (!neg, !pos, !noCB) (i, p)
              | not (isReal p) = (neg, pos, noCB)  -- skip virtual postings
              -- skip balancer-copied basis annotations, except elided
              -- transfer source/destination candidates (isMirroredTransferCandidate)
              | hasBalancerCopiedBasis p, not (isMirroredTransferCandidate p) = (neg, pos, noCB)
              | i `S.member` sameAcctTransferSet = (neg, pos, noCB)  -- skip same-account transfer pairs
              | optedOut p = (neg, pos, noCB)  -- skip lots: NONE accounts' postings
              | otherwise =
              let baseAcct = lotBaseAccount (paccount p)
                  isAsset  = maybe False isAssetType (lookupAccountType baseAcct)
                  amts     = amountsRaw (pamount p)
                  acct     = baseAcct
                  isNeg    = any isNegativeAmount amts
                  hasCB    = any (isJust . acostbasis) amts
                  isLotful = amountsAreLotful amts
                  cbKeys   = [(acommodity a, abs (aquantity a)) | a <- amts, isJust (acostbasis a)]
                  allKeys  = [(acommodity a, abs (aquantity a)) | a <- amts]
                  -- Include cost-basis negatives (any account type) and bare lotful
                  -- negatives on asset accounts. Non-asset bare lotful negatives
                  -- (e.g. revenue) are excluded — they shouldn't be transfer counterparts.
                  -- Equity transfers are handled separately via hasEquityCounterpart.
                  neg'     = if isNeg && (hasCB || (isLotful && isAsset))
                             then foldl' (addAcct acct) neg (if hasCB then cbKeys else allKeys) else neg
                  pos'     = if not isNeg && hasCB
                             then foldl' (addAcct acct) pos cbKeys else pos
                  noCB'    = if not isNeg && isAsset && not hasCB
                             then foldl' (addAcct acct) noCB allKeys else noCB
              in (neg', pos', noCB')
        -- Add an account to a (commodity, quantity) key's account list, deduplicating.
        addAcct acct m k = M.insertWith (\_ old -> if acct `elem` old then old else acct : old) k [acct] m

    -- Is there a transfer counterpart for a posting in this account, with this sign,
    -- in this commodity and quantity?
    hasCounterpart :: AccountName -> Bool -> CommoditySymbol -> Quantity -> Bool
    hasCounterpart acct isNeg c q
      | isNeg     = anyOtherAcct posCBAccts || anyOtherAcct posNoCBAccts
      | otherwise = anyOtherAcct negCBAccts
      where anyOtherAcct m = any (/= acct) (M.findWithDefault [] (c, abs q) m)

    -- Is there a transfer-from counterpart (negative with cost basis or lotful)
    -- for this commodity and quantity?
    hasTransferFromCounterpart :: AccountName -> CommoditySymbol -> Quantity -> Bool
    hasTransferFromCounterpart acct c q = any (/= acct) (M.findWithDefault [] (c, abs q) negCBAccts)

    -- Commodity-only transfer-from check (ignores quantity).
    -- Fallback for transfer+fee patterns where quantities don't match exactly.
    hasTransferFromCommodityMatch :: AccountName -> CommoditySymbol -> Bool
    hasTransferFromCommodityMatch acct c =
      any (\((c', _), accts) -> c' == c && any (/= acct) accts)
          (M.toList negCBAccts)

    -- Per-commodity totals of unpriced transfer-candidate amounts, with their
    -- accounts. Used for sum-based transfer detection when quantities don't
    -- pair one to one (a split or consolidating transfer, #2692).
    -- Priced amounts are excluded (a priced posting is a deliberate trade,
    -- eg a fee disposal), as are auto-split fee dispose fragments (feesplit
    -- tag), which would otherwise inflate the outflow total.
    -- Side criteria mirror the counterpart maps above: negatives need cost
    -- basis (any account type) or bare lotful in an asset account; positives
    -- need cost basis (any account type) or an asset account.
    negSums, posSums :: M.Map CommoditySymbol (Quantity, [AccountName])
    (negSums, posSums) = foldl' collectSums (M.empty, M.empty) (zip [0..] ps)
      where
        collectSums (!neg, !pos) (i, p)
          | not (isReal p) = (neg, pos)
          | hasBalancerCopiedBasis p = (neg, pos)
          | i `S.member` sameAcctTransferSet = (neg, pos)
          | postingHasTag feesplitPostingTagName p = (neg, pos)
          | optedOut p = (neg, pos)
          | otherwise = foldl' addAmt (neg, pos) amts
          where
            acct = lotBaseAccount (paccount p)
            isAsset = maybe False isAssetType (lookupAccountType acct)
            isLotful = amountsAreLotful amts
            amts = amountsRaw (pamount p)
            addAmt (!neg', !pos') a
              | isJust (acost a) = (neg', pos')
              | q < 0, hasCB || (isLotful && isAsset) = (addTo neg' (negate q), pos')
              | q > 0, hasCB || isAsset               = (neg', addTo pos' q)
              | otherwise = (neg', pos')
              where
                q = aquantity a
                hasCB = isJust (acostbasis a)
                addTo m qty = M.insertWith merge (acommodity a) (qty, [acct]) m
                merge (newq, newaccts) (oldq, oldaccts) =
                  (newq + oldq, foldr insertAcct oldaccts newaccts)
                insertAcct x xs = if x `elem` xs then xs else x : xs

    -- Is there a sum-matched transfer counterpart for this commodity ?
    -- True when the commodity's total unpriced outflow equals its total
    -- unpriced inflow (per the sum maps above), and the opposite side
    -- includes an account other than this posting's. Detects transfers
    -- whose postings don't pair one to one (#2692).
    hasSumCounterpart :: AccountName -> Bool -> CommoditySymbol -> Bool
    hasSumCounterpart acct isNeg c =
      case (M.lookup c negSums, M.lookup c posSums) of
        (Just (nq, naccts), Just (pq, paccts)) ->
          nq == pq && any (/= acct) (if isNeg then paccts else naccts)
        _ -> False

    classifyAt :: Int -> Posting -> Posting
    classifyAt i p
      | not (isReal p) = p  -- skip virtual (parenthesised) postings
      | isClassifiedPosting p = p  -- skip postings already carrying a ptype tag (eg gain postings tagged by transactionTagGainPostings)
      -- A balancer-copied basis posting is normally left unclassified,
      -- except when it can be read as the elided destination or source of
      -- a lot transfer (see isMirroredTransferCandidate).
      | hasBalancerCopiedBasis p =
          let baseAcct = lotBaseAccount (paccount p)
              cbPairs = [(acommodity a, aquantity a) | a <- amountsRaw (pamount p), isJust (acostbasis a)]
              isNeg = any isNegativeAmount (amountsRaw (pamount p))
              hasMatch
                | isNeg     = any (\(c, q) -> hasCounterpart baseAcct True c q) cbPairs
                | otherwise = any (\(c, q) -> hasTransferFromCounterpart baseAcct c q) cbPairs
          in if isMirroredTransferCandidate p && hasMatch
             then addTag (if isNeg then "transfer-from" else "transfer-to") p
             else p
      | i `S.member` sameAcctTransferSet =
          let amts = amountsRaw (pamount p)
              cls = if any isNegativeAmount amts then "transfer-from" else "transfer-to"
          in addTag cls p
      | otherwise =
      case dbg5 ("classifyLotPostings: classifyPosting " ++ show (paccount p) ++ " result") $ shouldClassify p of
        Just classification -> addTag classification p
        Nothing -> p
      where addTag cls = postingAddHiddenAndMaybeVisibleTag True verbosetags (toHiddenTag ("ptype", cls))

    -- Check if posting should be classified and return the classification:
    -- one of acquire, dispose, transfer-from, transfer-to.
    shouldClassify :: Posting -> Maybe Text
    shouldClassify p = do
      let amts = amountsRaw $ pamount p
          baseAcct = lotBaseAccount (paccount p)
      -- Zero-amount postings (eg balance assertion carriers) move no lots and
      -- are left unclassified, consistent with isUnclassifiedLotfulPosting's
      -- zero exemption. (Eg a zero posting beside a transfer must not become
      -- a transfer-to via commodity matching.)
      guard $ any ((/= 0) . aquantity) amts
      guard $ not (optedOut p)
      if any (isJust . acostbasis) amts
        -- Cost basis present: classify regardless of account type (fix A)
        then dbg5 ("classifyLotPostings: shouldClassify " ++ show (paccount p) ++ " withCostBasis") $
             shouldClassifyWithCostBasis p amts
        else do
          -- No cost basis: require asset account type
          acctType <- dbg5 ("classifyLotPostings: shouldClassify " ++ show (paccount p) ++ " acctType") $
                      lookupAccountType baseAcct
          guard $ isAssetType acctType
          dbg5 ("classifyLotPostings: shouldClassify " ++ show (paccount p) ++ " lotful/bare") $
            shouldClassifyNegativeLotful p amts <|> shouldClassifyLotful p amts <|> shouldClassifyBareTransferTo p amts <|> shouldClassifyPositiveLotful p amts

    -- True when the transaction has an equity posting with no explicit cost-basis amounts.
    -- This indicates an equity transfer: lots move to/from equity in two parts
    -- (e.g. close --clopen --lots generates a closing txn transferring lots into equity,
    -- and an opening txn transferring them back out), allowing the negative lot postings
    -- to be classified as transfer-from rather than dispose.
    hasEquityCounterpart :: Bool
    hasEquityCounterpart = any isEquityNonLotPosting ps
      where
        isEquityNonLotPosting q =
          maybe False isEquityType (lookupAccountType (lotBaseAccount (paccount q)))
          -- A balancer-copied basis annotation is not user-written
          -- (an elided equity posting still counts as an equity counterpart).
          && (hasBalancerCopiedBasis q || not (any (isJust . acostbasis) (amountsRaw (pamount q))))

    -- Classify a posting that has cost basis: acquire, dispose, transfer-from, or transfer-to.
    shouldClassifyWithCostBasis :: Posting -> [Amount] -> Maybe Text
    shouldClassifyWithCostBasis p amts = do
      let
        baseAcct = lotBaseAccount (paccount p)
        isNeg = any isNegativeAmount amts
        primaryType = if isNeg then "dispose" else "acquire"
        cbAmts = [(acommodity a, aquantity a) | a <- amts, isJust (acostbasis a)]
        -- A transfer counterpart can match by exact quantity, or by commodity
        -- sums when postings don't pair one to one (#2692). The sum fallback
        -- is only for unpriced postings (a priced posting is a deliberate
        -- trade) and not for auto-split fee fragments (which must remain
        -- disposals even though the remaining transfer sums match).
        isTransfer = any (\(c, q) -> hasCounterpart baseAcct isNeg c q) cbAmts
          || (not (any (isJust . acost) amts)
              && not (postingHasTag feesplitPostingTagName p)
              && any (hasSumCounterpart baseAcct isNeg . fst) cbAmts)
        -- Also treat as equity transfer when: no transacted price written,
        -- and an equity counterpart posting is present. This handles lots moving
        -- to/from equity (e.g. close --clopen --lots generates a closing txn with
        -- negative lot postings and an opening txn with positive lot postings).
        isEquityTransfer = not (any (isJust . acost) amts) && hasEquityCounterpart
      if isTransfer || isEquityTransfer
        then return $ if isNeg then "transfer-from" else "transfer-to"
        else do
          -- Don't classify income statement accounts (Revenue, Expense, Gain) as acquire/dispose.
          -- These are flow accounts that should not track lots or get lot subaccounts.
          -- E.g. expenses:fees 0.1 ETSY {$80} @ $90 in a stock-fee disposal.
          guard $ not $ maybe False isIncomeStatementAccountType (lookupAccountType baseAcct)
          return primaryType

    -- Classify a negative lotful posting without cost basis as dispose or transfer-from.
    -- If the posting has no transacted price and another asset account in the same
    -- transaction receives a positive lotful amount of the same commodity (even at
    -- different quantity), skip classification — it's a transfer+fee pattern and
    -- global FIFO will handle the lot reduction when the destination account trades.
    shouldClassifyNegativeLotful :: Posting -> [Amount] -> Maybe Text
    shouldClassifyNegativeLotful p amts = do
      guard $ amountsAreLotful amts
      guard $ any isNegativeAmount amts
      let baseAcct = lotBaseAccount (paccount p)
          hasPrice = any (isJust . acost) amts
          negAmts = [a | a <- amts, isNegativeAmount a]
          negCommodities = S.fromList [acommodity a | a <- negAmts]
          amtPairs = [(acommodity a, aquantity a) | a <- amts]
          isTransfer = any (\(c, q) -> hasCounterpart baseAcct True c q) amtPairs
          -- Check for positive lotful amounts in other asset accounts (same commodity).
          otherAssetReceives = any isOtherAssetWithLotful (filter (/= p) ps)
          isOtherAssetWithLotful q =
            let qAmts = amountsRaw (pamount q)
                qBase = lotBaseAccount (paccount q)
            in qBase /= baseAcct
               && maybe False isAssetType (lookupAccountType qBase)
               && not (optedOut q)
               && amountsAreLotful qAmts
               && any (\a -> aquantity a > 0 && acommodity a `S.member` negCommodities) qAmts
          -- Does a non-asset posting receive exactly this commodity+quantity?
          -- If so, this posting is likely a fee/dispose (e.g. paired with expenses:fees),
          -- not part of a transfer to another asset account.
          hasFeeCounterpart = any isFeeCounterpart (filter (/= p) ps)
          isFeeCounterpart q =
            let qAmts = amountsRaw (pamount q)
                qBase = lotBaseAccount (paccount q)
            in not (maybe False isAssetType (lookupAccountType qBase))
               && any (\a -> aquantity a > 0
                          && any (\na -> acommodity na == acommodity a
                                      && abs (aquantity na) == aquantity a) negAmts) qAmts
      -- The other-asset-receives heuristic (transfer+fee pattern) applies only
      -- to unpriced postings: a transacted price signals dispose intent, eg an
      -- explicit priced fee disposal written alongside a matched transfer pair.
      if isTransfer || (otherAssetReceives && not hasFeeCounterpart && not hasPrice)
        then return "transfer-from"
        else do
          guard $ hasPrice || hasFeeCounterpart || not otherAssetReceives
          return "dispose"

    -- Classify a lotful posting without cost basis.
    -- A positive posting in a lotful commodity/account, with no transacted price,
    -- and with a matching transfer-from counterpart, is classified as transfer-to.
    shouldClassifyLotful :: Posting -> [Amount] -> Maybe Text
    shouldClassifyLotful p amts = do
      guard $ amountsAreLotful amts
      guard $ not $ any isNegativeAmount amts
      guard $ not $ any (isJust . acost) amts
      let baseAcct = lotBaseAccount (paccount p)
          amtPairs = [(acommodity a, aquantity a) | a <- amts]
      guard $ any (\(c, q) -> hasTransferFromCounterpart baseAcct c q) amtPairs
           || any (\(c, _) -> hasTransferFromCommodityMatch baseAcct c) amtPairs
      return "transfer-to"

    -- Classify a bare positive asset posting (no cost basis, not necessarily lotful)
    -- as transfer-to if there's a matching transfer-from counterpart (fix C).
    shouldClassifyBareTransferTo :: Posting -> [Amount] -> Maybe Text
    shouldClassifyBareTransferTo p amts = do
      guard $ not $ any isNegativeAmount amts
      guard $ not $ any (isJust . acost) amts
      let baseAcct = lotBaseAccount (paccount p)
          amtPairs = [(acommodity a, aquantity a) | a <- amts]
      guard $ any (\(c, q) -> hasTransferFromCounterpart baseAcct c q) amtPairs
           || any (\(c, _) -> hasTransferFromCommodityMatch baseAcct c) amtPairs
      return "transfer-to"

    -- Classify a positive lotful posting without cost basis as acquire.
    -- This is the fallback for positive lotful postings that aren't transfer-to.
    -- Requires a plausible cost source: transacted price, different-commodity posting
    -- (for balancer inference), or a transfer-from counterpart (whose lot cost is inherited).
    -- Without any of these, no lot can be created so we skip classification.
    shouldClassifyPositiveLotful :: Posting -> [Amount] -> Maybe Text
    shouldClassifyPositiveLotful p amts = do
      guard $ amountsAreLotful amts
      guard $ any (\a -> aquantity a > 0) amts
      let commodities = S.fromList [acommodity a | a <- amts]
          hasPrice = any (isJust . acost) amts
          hasDiffCommodity = any (\q -> any ((`S.notMember` commodities) . acommodity) (amountsRaw (pamount q)))
                               (filter (\q -> q /= p && hasAmount q) ps)
          baseAcct = lotBaseAccount (paccount p)
          hasTransferFrom = any (\(c, q) -> hasTransferFromCounterpart baseAcct c q)
                              [(acommodity a, aquantity a) | a <- amts]
      guard $ hasPrice || hasDiffCommodity || hasTransferFrom
      return "acquire"

    -- Check if a posting's amounts are lotful: one of their commodities has a lots: tag.
    amountsAreLotful :: [Amount] -> Bool
    amountsAreLotful = any (commodityIsLotful . acommodity)

-- Lot calculation (pipeline stage 2)

-- | Calculate detailed lot movements by walking transactions in date order.
-- Handles acquire postings (generating lot names as subaccounts),
-- dispose postings (matching to existing lots using FIFO, splitting if needed),
-- and transfer postings (moving lots between accounts, preserving cost basis).
-- The verbosetags parameter controls whether generated-posting tags are made visible in comments.
-- All lot selection/classification failures are hard errors.
journalCalculateLots :: Bool -> Journal -> Either String Journal
journalCalculateLots verbosetags j
  | not $ any (any isLotPosting . tpostings) txns = do
      mapM_ checkUnclassified [(t, i, p) | t <- txns, (i, p) <- zip [0..] (tpostings t)]
      Right j
  | otherwise = do
      validateUserLabels txns
      let needsLabels = findDatesNeedingLabels txns
      (_, txns') <- foldM (processTransaction styles verbosetags j needsLabels) (M.empty, []) (sortOn tdate txns)
      Right (journalTieTransactions $ j{jtxns = reverse txns'})
  where
    txns = jtxns j
    -- Journal's canonical commodity styles, used for rendering the cost amount
    -- in lot subaccount names. NoRounding preserves the original decimal digits
    -- while still applying the canonical decimal mark, digit group separators,
    -- and commodity position/spacing.
    styles = journalCommodityStylesWith NoRounding j
    checkUnclassified (t, i, p)
      | isUnclassifiedLotfulPosting j p = Left (unclassifiedLotWarning j t i p)
      | otherwise                       = Right ()

-- Disposal gain postings

-- | Make a generated realised-gain posting with the given account and amount,
-- tagged @_ptype:gain@ and @_generated-posting@ (the latter visible as
-- @generated-posting:@ in @print --verbose-tags@).
mkGeneratedGainPosting :: Bool -> AccountName -> MixedAmount -> Posting
mkGeneratedGainPosting verbosetags acc amt =
    tagGain verbosetags
  $ postingAddHiddenAndMaybeVisibleTag False verbosetags (generatedPostingTagName, "")
  $ nullposting{paccount = acc, pamount = amt}

-- | Tag a posting as a gain posting (@_ptype:gain@).
tagGain :: Bool -> Posting -> Posting
tagGain verbosetags = postingAddHiddenAndMaybeVisibleTag True verbosetags (toHiddenTag ("ptype", "gain"))

-- | Does this posting look like a lot disposal (or transfer source) ?
-- True if it has a negative amount with a cost basis annotation, or in a
-- lotful commodity (unless the account opts out with lots: NONE).
-- A shape check, usable before lot classification has run.
postingHasDisposeShape :: (CommoditySymbol -> Bool) -> (AccountName -> Bool) -> Posting -> Bool
postingHasDisposeShape commodityIsLotful accountUsesNoLots p =
  any (\a -> isNegativeAmount a
          && (isJust (acostbasis a)
              || (commodityIsLotful (acommodity a)
                  && not (accountUsesNoLots (lotBaseAccount (paccount p))))))
      (amountsRaw (pamount p))

-- | In a disposal transaction, tag the user-written realised gain
-- postings with @_ptype:gain@, so that the transaction balancer sets them
-- aside (see 'Hledger.Data.Balancing.transactionCheckBalanced').
--
-- A disposal balances at cost basis: the dispose posting counts as its
-- quantity times its basis, and the gain posting accounts for the
-- difference from the transacted proceeds. The basis is not known until
-- lot matching, which runs after balancing; but since
-- @q*B + q*(T-B) == q*T@, balancing the non-gain postings at transacted
-- cost is equivalent, and that is what the balancer does. Whether the gain
-- amount is right is checked afterwards by 'journalAddOrCheckGainPostings'.
--
-- Disposal transactions are recognised by shape, since classification has
-- not run yet: a real posting with a negative lotful or cost-basis amount
-- ('postingHasDisposeShape'; this also matches transfer sources, where a
-- gain posting is later rejected by journalAddOrCheckGainPostings, the
-- gain being zero). Gain postings are recognised in one of two ways:
--
-- 1. By account type: real postings on a Gain-typed account. These may be
--    amountless (unless the first argument is false, in lenient --ignore-lots
--    mode, where there'll be no lot matching to fill the amount in): the
--    balancer leaves such a posting alone and 'journalAddOrCheckGainPostings'
--    sets its amount to the calculated gain.
--
-- 2. Heuristically, when there is no Gain-typed posting: real, amountful
--    postings whose account type is not Asset, Liability or Equity (or a
--    subtype), and which don't carry a lotful or cost-basis amount; accepted
--    only if all postings have amounts and the remaining postings sum to
--    zero at transacted cost (a well-formed disposal), or to a
--    multi-commodity amount (which balancing cost inference will resolve).
--    This lets a gain posting be written on any account without declaring
--    it type:G, for simple entries.
--
-- Virtual (parenthesised) postings are ignored throughout, as the balancer
-- and the lot machinery ignore them. A transaction which already has a
-- tagged gain posting is returned unchanged, so this is safe to run
-- repeatedly: it runs as a journalFinalise step, and again inside the
-- balancer for callers which balance single entries (hledger add, hledger-web).
transactionTagGainPostings
  :: Bool                                -- ^ also tag amountless Gain-typed postings (not in lenient mode)
  -> Bool                                -- ^ also add visible tags
  -> (AccountName -> Maybe AccountType)  -- ^ account type lookup
  -> (CommoditySymbol -> Bool)           -- ^ is this a lotful commodity ?
  -> (AccountName -> Bool)               -- ^ does this account use lots: NONE ?
  -> Transaction -> Transaction
transactionTagGainPostings tagamountless verbosetags lookupAccountType commodityIsLotful accountUsesNoLots t
  | any isGainPosting realps  = t
  | not (any hasDisposeShape realps) = t
  | any isGainTyped realps     = tagPostings isGainTyped
  | heuristicOk                = tagPostings isCandidate
  | otherwise                  = t
  where
    realps = filter isReal (tpostings t)
    hasDisposeShape = postingHasDisposeShape commodityIsLotful accountUsesNoLots
    isGainTyped p = (tagamountless || hasAmount p) && lookupAccountType (paccount p) == Just Gain
    hasLotfulOrBasisAmount p =
      any (\a -> isJust (acostbasis a) || commodityIsLotful (acommodity a)) (amountsRaw (pamount p))
    tagPostings isgain = txnTieKnot t{tpostings = map tag (tpostings t)}
      where tag p = if isReal p && isgain p then tagGain verbosetags p else p

    -- Heuristic gain candidates, and whether the other postings balance without them.
    isCandidate p = hasAmount p && notALE p && not (hasLotfulOrBasisAmount p)
      where
        notALE q = case lookupAccountType (paccount q) of
          Just ty -> not (isAssetType ty || isLiabilityType ty || isEquityType ty)
          Nothing -> True
    heuristicOk =
         all hasAmount realps          -- with an elided amount, leave it to the balancer
      && not (null candidates)
      && (mixedAmountIsZero residual   -- well-formed disposal: net zero
          || length nonzeroresidual >= 2)  -- multi-commodity: cost inference will resolve
      where
        (candidates, noncandidates) = partition isCandidate realps
        residual = foldMap (mixedAmountCost . pamount) noncandidates
        nonzeroresidual = filter ((/= 0) . aquantity) (amountsRaw residual)

-- | Apply 'transactionTagGainPostings' to each transaction. In lenient
-- (--ignore-lots) mode, amountless gain postings are left untagged, for the
-- balancer to infer like any other posting.
journalTagGainPostings :: Bool -> Bool -> Journal -> Either String Journal
journalTagGainPostings lenient verbosetags j =
  Right $ journalMapTransactions
    (transactionTagGainPostings (not lenient) verbosetags (journalAccountType j) (journalCommodityUsesLots j) (journalAccountUsesNoLots j))
    j

-- | Error for a disposal with a gain posting whose amount was inferred by
-- the balancer because the disposal could only be recognised afterwards
-- (eg its amounts came from a balance assignment).
amountlessErr :: Transaction -> String
amountlessErr t =
  txnErrPrefix t
  ++ "This disposal has an amountless gain posting, which can't be inferred here.\n"
  ++ "Write the amount explicitly, or omit the posting entirely\n"
  ++ "(hledger will then infer the realised gain from the cost basis)."

-- | Error for a disposal with more than one amountless gain posting.
multipleAmountlessErr :: Transaction -> String
multipleAmountlessErr t =
  txnErrPrefix t
  ++ "This disposal has more than one amountless gain posting.\n"
  ++ "At most one gain posting can have its amount inferred."

-- | Check that no acquire posting has a disagreement between its cost basis and transacted cost.
--
-- We require acquisitions to always have the same cost basis and transacted cost now.
-- (Real world use cases like a gift with carryover basis can be handled with simpler journal entries.)
--
-- This runs after 'journalCalculateLots' so that cost basis is populated on
-- acquire postings, and before 'journalAddOrCheckGainPostings' so the
-- error surfaces before gain calculations.
journalCheckAcquireBasis :: Journal -> Either String Journal
journalCheckAcquireBasis j = mapM_ checkTxn (jtxns j) >> Right j
  where
    checkTxn t = case badps of
      []                              -> Right ()
      ((idx, p, basis, transacted):_) -> Left (acquireBasisErr t idx p basis transacted)
      where
        badps =
          [ (idx, p, basis, transacted)
          | (idx, p) <- zip [0..] (tpostings t)
          , isAcquirePosting p
          , a <- amountsRaw (pamount p)
          , Just basis <- [acostbasis a >>= cbCost]
          , Just tc <- [acost a]
          , let transacted = amountCostToUnitCost (abs (aquantity a)) tc
          , aquantity basis /= aquantity transacted
          ]

    acquireBasisErr t idx p basis transacted =
      printf "%s:%d:\n%s\n" f l (T.unpack ex)
      ++ "This acquire posting's cost basis (" ++ basisStr
      ++ ") differs from its transacted cost (" ++ transactedStr ++ ").\n"
      ++ "Options:\n"
      ++ "  - drop {} or {{}} so basis is inferred from the transacted cost\n"
      ++ "  - drop @ or @@ so transacted cost is inferred from the basis\n"
      ++ "  - use {{TotalCost}} or write the per-unit basis at higher precision\n"
      ++ "  - if the difference is real (gift, NSO, RSU, etc.), fund it via a separate posting"
      where
        col1 = 5 + if isVirtual p then 1 else 0
        col2 = col1 + T.length (paccount p) - 1
        (f, l, _mcols, ex) = makePostingErrorExcerptByIndex t idx (Just (col1, Just col2))
        (basisStr, transactedStr) =
          showAmountsDistinctly oneLineNoCostFmt{displayZeroCommodity=True} basis transacted

-- | For each disposal transaction with a transacted price, add a realised-gain
-- posting to a 'Gain'-type account (default @revenues:gain@) with
-- the negated gain amount; or if the transaction already has gain posting(s)
-- (user-written; see 'transactionTagGainPostings'), check that their sum
-- matches the calculated gain.
--
-- With the gain posting present, the disposal balances at cost basis, and
-- no counter posting is needed: hledger records gains by the historical cost
-- convention, in which unrealised gains are not posted (though they can be
-- reported from market prices).
--
-- The gain amount is the disposal gain: for each dispose posting amount with
-- both a cost basis and a transacted cost, contribute @aquantity * (B - T)@
-- (equivalently: cost-basis value minus transacted-cost value). Acquire and
-- other postings do not contribute. Eg for @-5 AAPL {$50} \@ $70@: gain
-- contribution is @-5 * ($50 - $70) = $100@.
--
-- Runs after 'journalCalculateLots' so that cost basis is populated on dispose
-- postings. The generated posting carries the @_generated-posting@ hidden tag,
-- visible as @generated-posting:@ in @print --verbose-tags@.
journalAddOrCheckGainPostings :: Bool -> Journal -> Either String Journal
journalAddOrCheckGainPostings verbosetags j = do
    txns' <- mapM addOrCheck (jtxns j)
    Right j{jtxns = txns'}
  where
    atypes = jaccounttypes j
    gainAccount = journalBaseGainAccount j

    -- Within a disposal, gain postings are identified by the _ptype:gain
    -- hidden tag (added by transactionTagGainPostings), or by account type
    -- (declared or inferred from name). Only real postings count, as in
    -- transactionTagGainPostings and the balancer.
    isGainTyped p = isReal p && accountNameType atypes (paccount p) == Just Gain
    isGain p = isReal p && (isGainPosting p || isGainTyped p)
    disposeHasPrice p = isDisposePosting p && any (isJust . acost) (amountsRaw (pamount p))

    addOrCheck t
      | any isGainPosting ps           = fillOrCheck t  -- tagged gain posting(s), possibly in a non-disposal (then the gain is zero)
      | not (any disposeHasPrice ps)   = Right t
      | any isAmountlessGain ps        = Left (amountlessErr t)
      | any isGainTyped ps             = checkGain t
      | otherwise                      = Right (addGain t)
      where
        ps = tpostings t
        -- An untagged gain posting the user left amountless: the disposal was
        -- not recognisable when the balancer tagged gain postings, so it has
        -- inferred an amount for it by now, which can't be corrected; check
        -- the original posting. (Rare: balance assignments are resolved before
        -- tagging, so the #2686 shape no longer gets here.)
        isAmountlessGain p = isGainTyped p && not (hasAmount (originalPosting p))

    -- With tagged gain postings: if exactly one is amountless, set its amount
    -- to the calculated gain (less any other written gain amounts); otherwise
    -- check the written amount(s).
    fillOrCheck t = case filter (\p -> isGain p && not (hasAmount p)) (tpostings t) of
      []  -> checkGain t
      [_] -> Right (fillGain t)
      _   -> Left (multipleAmountlessErr t)

    fillGain t = txnTieKnot t{tpostings = map fill (tpostings t)}
      where
        ps      = tpostings t
        gain    = foldMap postingDisposalGain ps
        written = foldMap pamount (filter (\p -> isGain p && hasAmount p) ps)
        amt     = setLocalGainPrecision t (maNegate gain <> maNegate written)
        fill p
          | isGain p && not (hasAmount p) = p{pamount = amt, poriginal = Just (originalPosting p)}
          | otherwise                      = p

    addGain t
      | mixedAmountIsZero gain = t
      | otherwise = txnTieKnot t{tpostings = tpostings t ++ [gainP]}
      where
        gain   = foldMap postingDisposalGain (tpostings t)
        gainP = mkGeneratedGainPosting verbosetags gainAccount (setLocalGainPrecision t $ maNegate gain)

    -- Check that the user-written gain amount(s) sum to the calculated
    -- disposal gain (negated). The gain is zero when there is no priced
    -- disposal, eg a gain posting mistakenly written in a lot transfer.
    checkGain t =
      let ps       = tpostings t
          gain     = foldMap postingDisposalGain ps
          writtenGain = foldMap pamount (filter isGain ps)
          -- writtenGain should equal -gain. Tolerate sub-ULP noise at the
          -- precision chosen by setLocalGainPrecision, matching how the
          -- balancer tolerates balancing imprecision.
          diff = setLocalGainPrecision t (writtenGain <> gain)
      in if mixedAmountLooksZero diff
           then Right t
           else Left (mismatchErr t gain writtenGain)

    -- Set each component amount's display precision to the entry's local
    -- precision for that commodity.
    -- Special rule for the 0 decimals case (when the local precision is 0,
    -- or there are no amounts of the commodity present):
    -- display with 2 decimals if either of them is non-zero, otherwise
    -- display with 0 decimals.
    -- The full precision is preserved internally, so reports like
    -- `print -c '$1.0000' --round=soft` can still reveal sub-cent detail.
    setLocalGainPrecision t = mapMixedAmount setOne
      where
        styles = transactionCommodityStyles t
        setOne a@Amount{aquantity = q, astyle = s} =
          case M.lookup (acommodity a) styles of
            Just AmountStyle{asprecision = Precision n} | n >= 1 ->
              a{astyle = s{asprecision = Precision n}}
            _ ->
              let q2 = roundTo 2 q
              in if roundTo 0 q2 == q2
                 then a{astyle = s{asprecision = Precision 0}}
                 else a{astyle = s{asprecision = Precision 2}}

    mismatchErr t gain writtenGain =
      txnErrPrefix t
      ++ "This disposal's realised gain amount is wrong.\n"
      ++ "  written:    " ++ writtenStr ++ "\n"
      ++ "  calculated: " ++ calculatedStr
      where
        (writtenStr, calculatedStr) =
          showMixedAmountsDistinctly oneLineNoCostFmt{displayZeroCommodity=True}
            writtenGain (maNegate gain)

    -- | The realised-capital-gain contribution from a single posting.
    --
    -- Sums 'amountBasisVsTransactedGap' across the posting's amounts,
    -- treating each non-zero gap as realised gain on the lot units changing
    -- hands. Eg @assets:broker -5 AAPL {$50} \@ $70@ contributes
    -- @-5 * ($50 - $70) = $100@ — five shares sold at a $20 profit each.
    --
    -- Acquire postings are excluded: a fresh acquisition with
    -- @basis ≠ transacted@ is a carryover or bookkeeping imbalance, not
    -- realised gain, and is dealt with separately. Every other kind of
    -- posting contributes, including postings the lot classifier did not
    -- explicitly tag as @_ptype:dispose@ (eg a fee paid in lot-tracked
    -- stock — its disposal economics are real even without the tag).
    postingDisposalGain :: Posting -> MixedAmount
    postingDisposalGain p
      | isAcquirePosting p = nullmixedamt
      | not (hasAmount p)  = nullmixedamt
      | otherwise = foldMap amountBasisVsTransactedGap (amountsRaw (pamount p))

    -- | The per-amount cost-basis-vs-transacted-cost gap.
    --
    -- An amount can carry two unit prices: its /cost basis/ from a @{...}@
    -- annotation, and its /transacted cost/ from @\@@ or @\@\@@. When both
    -- are present, this returns @aquantity * (basis - transacted)@,
    -- equivalently the amount's value at cost basis minus its value at
    -- transacted cost. Returns 'nullmixedamt' if either side is missing.
    --
    -- Pure arithmetic; the caller decides what the gap /means/ in context
    -- (realised gain on a disposal, carryover/imbalance on an acquire, etc).
    amountBasisVsTransactedGap :: Amount -> MixedAmount
    amountBasisVsTransactedGap a = case (acostbasis a >>= cbCost, acost a) of
      (Just basisCost, Just transactedCost) ->
        let basisVal      = mixedAmount basisCost{aquantity = aquantity a * aquantity basisCost}
            transactedVal = case transactedCost of
              UnitCost  c -> mixedAmount c{aquantity = aquantity a * aquantity c}
              TotalCost c -> mixedAmount c
        in basisVal <> maNegate transactedVal
      _ -> nullmixedamt

-- | Collapse lot-tracking detail from a journal for display when --lots is off.
-- Makes these targeted changes to each transaction:
--
-- * drops postings tagged @_lot-parent-assertion@ (synthetic balance-assertion
--   carriers added when splitting a posting into lot subaccounts);
-- * strips any lot subaccount (the trailing @{...}@ component) from each remaining
--   posting's account name;
-- * merges per-lot split fragments back into one posting (see mergeLotSplits).
--
-- Lot-inferred cost basis annotations (@acostbasis@) are kept on the amounts:
-- 'print' shows them, so that lot entries are self-describing and can be
-- re-read without the commodity's @lots:@ declaration (under the default
-- method). A merged multi-lot posting gets an unspecified basis (@{}@),
-- meaning "lots selected by the account's method".
--
-- Postings tagged @_feesplit-posting@ (synthetic fee fragments from auto-split) are
-- retained so transactions stay balanced in reports like 'print'.
--
-- 'print' relies on its existing 'transactionWithMostlyOriginalPostings' logic to
-- revert pamount to 'poriginal' when displaying non-explicit output (carrying
-- the inferred basis over).
--
-- Journals with no lot content are returned unchanged.
journalCollapseLotDetail :: Journal -> Journal
journalCollapseLotDetail j
  | any (any needsCollapse . tpostings) (jtxns j) = journalMapTransactions collapseTransaction j
  | otherwise                                      = j
  where
    needsCollapse p = postingHasTag feesplitPostingTagName p
                   || postingHasTag lotsplitPostingTagName p
                   || postingHasTag lotParentAssertionTagName p
                   || isJust (lotSubaccountName (paccount p))

    collapseTransaction t =
      txnTieKnot t{tpostings = mergeLotSplits (mapMaybe collapsePosting (tpostings t))}

    collapsePosting p
      | postingHasTag lotParentAssertionTagName p = Nothing
      | otherwise = Just p
          { paccount          = newAcct
          -- An assertion originally written on the base account (eg by CSV
          -- balanceN rules) targets the parent, which is what this collapsed
          -- posting shows again; keep it, so writing out the collapsed view
          -- (eg by import) preserves it. But an assertion the user wrote on
          -- the lot subaccount itself asserts that lot's balance, which was
          -- checked against the pre-collapse paccount during journalFinalise;
          -- drop it here so the collapsed view isn't re-validated against
          -- the parent total.
          , pbalanceassertion =
              if newAcct == paccount p || originalAcct == newAcct
              then pbalanceassertion p
              else Nothing
          }
      where
        newAcct = lotBaseAccount (paccount p)
        -- The account the user actually wrote (before lot processing).
        originalAcct = paccount (originalPosting p)

    -- Merge consecutive lotsplit-tagged postings that share the same original
    -- (poriginal) into one. The survivor's pamount is taken from its
    -- 'poriginal' (the user's full original amount); the lotsplit tag is
    -- removed so the rest of the pipeline sees a normal single posting.
    -- Sharing 'poriginal' identifies siblings from the same per-lot split,
    -- distinguishing them from unrelated lotsplit postings (eg the from- and
    -- to-side runs of a same-account transfer).
    mergeLotSplits = go
      where
        go [] = []
        go (p:ps)
          | postingHasTag lotsplitPostingTagName p =
              let sameRun q = postingHasTag lotsplitPostingTagName q && poriginal q == poriginal p
                  (run, rest) = span sameRun ps
                  -- The merged posting's amount is the sum of the run's
                  -- (already-collapsed) fragment amounts. This equals the
                  -- original's amount, except when the original had no amount
                  -- (elided or a balance assignment - using the original would
                  -- lose the amount entirely) or when a fee portion was split
                  -- off (using the original would double-count the retained
                  -- feesplit posting's amount). (#2692)
                  -- Summing several fragments drops their (differing) cost
                  -- bases; show an unspecified basis instead, meaning lots
                  -- selected by method, which re-reads equivalently under
                  -- the default method.
                  merged = maSum (map pamount (p:run))
                  hadBasis = any (any (isJust . acostbasis) . amountsRaw . pamount) (p:run)
                  survivor = (untagLotsplit p){pamount = if null run || not hadBasis then merged else mapMixedAmount unspecifiedBasis merged}
                  unspecifiedBasis a = a{acostbasis = Just (CostBasis Nothing Nothing Nothing)}
              in survivor : go rest
          | otherwise = p : go ps
        untagLotsplit p = p{ptags = filter ((/= lotsplitPostingTagName) . fst) (ptags p)}

-- Posting type predicates

-- | When an implicit-lot-subaccount posting (one whose account was a plain account,
-- not already a lot subaccount) is converted to explicit lot subaccount posting(s),
-- and it had a balance assertion, move the assertion to a new zero-amount generated
-- posting on the original parent account, making it subaccount-inclusive (=* style).
-- This preserves the assertion's meaning when the output is re-read without --lots:
-- the assertion checks the total of all lot subaccounts rather than the (empty)
-- direct balance of the parent.
-- If the original account was already a lot subaccount, the split postings are
-- returned unchanged (the assertion already targets the right account).
preserveParentAssertion :: Bool -> AccountName -> Maybe BalanceAssertion -> [Posting] -> [Posting]
preserveParentAssertion _           _        Nothing  ps = ps
preserveParentAssertion _           origAcct (Just _) ps
    | lotBaseAccount origAcct /= origAcct = ps  -- already an explicit lot subaccount; leave as-is
preserveParentAssertion verbosetags origAcct (Just ba) ps =
    map (\p -> p{pbalanceassertion = Nothing}) ps
    ++ [ postingAddHiddenAndMaybeVisibleTag False verbosetags (lotParentAssertionTagName, "")
       $ postingAddHiddenAndMaybeVisibleTag False verbosetags (generatedPostingTagName, "")
           nullposting
             { paccount          = origAcct
             , pamount           = mixedAmount (baamount ba){aquantity = 0}
             , pbalanceassertion = Just ba{bainclusive = True}
             } ]

-- | Check if a posting has any lot-related ptype tag.
isLotPosting :: Posting -> Bool
isLotPosting p = isAcquirePosting p || isDisposePosting p
             || isTransferFromPosting p || isTransferToPosting p
             || isGainPosting p

-- | True if this posting has any _ptype tag (was classified by lot classification,
-- or is a generated gain posting).
isClassifiedPosting :: Posting -> Bool
isClassifiedPosting p = any ((== "_ptype") . fst) (ptags p)

-- | Check if a posting is an acquire posting (has _ptype:acquire tag).
isAcquirePosting :: Posting -> Bool
isAcquirePosting p = ("_ptype", "acquire") `elem` ptags p

-- | Check if a posting is a dispose posting (has _ptype:dispose tag).
isDisposePosting :: Posting -> Bool
isDisposePosting p = ("_ptype", "dispose") `elem` ptags p

-- | Check if a posting is a transfer-from posting (has _ptype:transfer-from tag).
isTransferFromPosting :: Posting -> Bool
isTransferFromPosting p = ("_ptype", "transfer-from") `elem` ptags p

-- | Check if a posting is a transfer-to posting (has _ptype:transfer-to tag).
isTransferToPosting :: Posting -> Bool
isTransferToPosting p = ("_ptype", "transfer-to") `elem` ptags p

-- | Check if a posting is a gain posting (has _ptype:gain tag):
-- user-written and tagged by transactionTagGainPostings, or generated by
-- journalAddOrCheckGainPostings.
isGainPosting :: Posting -> Bool
isGainPosting p = ("_ptype", "gain") `elem` ptags p

-- | Does this posting carry a cost basis annotation that was copied into it
-- by the transaction balancer, rather than written by the user ?
-- True when the posting's amount was wholly inferred (its original had no
-- amount) yet carries a cost basis annotation: the balancer fills elided
-- postings with the negated sum of the other postings' amounts, and any
-- basis annotation rides along incidentally.
--
-- Such an annotation is not a lot selector - a cost basis annotation is
-- posting-specific user intent - but we deliberately keep it until lot
-- classification has run, when it identifies the elided destination or
-- source of a lot transfer (see 'isMirroredTransferCandidate' - the
-- mirrored posting of eg @stocks -5 AAPL {$50} / cash@ could equally be
-- the artifact of a sale missing its price, but the dispose reading would
-- fail for lack of a price, so the transfer reading is preferred).
-- Mirrored postings which can't be a transfer counterpart stay
-- unclassified and invisible to counterpart detection; afterwards
-- 'journalStripBalancerCopiedBases' removes their annotations, so
-- downstream code and reports only ever see user-written or
-- lot-machinery-derived cost bases.
hasBalancerCopiedBasis :: Posting -> Bool
hasBalancerCopiedBasis p =
  not (hasAmount (originalPosting p)) && any (isJust . acostbasis) (amountsRaw (pamount p))

-- | Remove balancer-copied cost basis annotations (see
-- 'hasBalancerCopiedBasis') from postings that lot classification left
-- unclassified, now that lot processing has used them as evidence.
-- Lot-processed (classified) postings are left alone: lot calculation
-- legitimately gives machinery-derived cost bases to postings whose amounts
-- were inferred, eg the per-lot fragments of an elided transfer source.
journalStripBalancerCopiedBases :: Journal -> Journal
journalStripBalancerCopiedBases = journalMapPostings strip
  where
    strip p
      | hasBalancerCopiedBasis p && not (isClassifiedPosting p) =
          p{pamount = mapMixedAmount (\a -> a{acostbasis = Nothing}) (pamount p)}
      | otherwise = p

-- | True if this posting involves a lotful commodity in an asset account
-- but has no _ptype tag (wasn't classified as acquire/dispose/transfer/gain).
-- Postings with zero amount in the lotful commodity are exempt (no lot tracking needed).
isUnclassifiedLotfulPosting :: Journal -> Posting -> Bool
isUnclassifiedLotfulPosting j p =
  isReal p
  && hasAmount p
  && not (isLotPosting p)
  && maybe False isAssetType (journalAccountType j (lotBaseAccount (paccount p)))
  -- lots: NONE accounts' postings are exempt (not lot-tracked).
  && not (journalAccountUsesNoLots j (lotBaseAccount (paccount p)))
  && hasNonzeroLotfulAmount
  -- Postings with balancer-copied basis annotations are deliberately left
  -- unclassified (see 'hasBalancerCopiedBasis'); the posting they mirror
  -- produces the relevant error.
  && not (hasBalancerCopiedBasis p)
  where
    lotfulAmts = filter (journalCommodityUsesLots j . acommodity) (amountsRaw (pamount p))
    -- Flag only when the lotful commodity itself has nonzero quantity.
    hasNonzeroLotfulAmount = any ((/= 0) . aquantity) lotfulAmts

-- | Build an error message for an unclassified lotful posting.
-- Takes the transaction and the 0-based posting index for precise source location.
-- The excerpt shows the transaction as the user wrote it: postings are
-- reverted to their original (parse time) form and generated postings are
-- dropped, so it matches the journal file rather than the processed
-- in-memory entry (#2686). When the problem posting's amount was inferred
-- (and so is not visible in the excerpt), it is mentioned in the message.
unclassifiedLotWarning :: Journal -> Transaction -> Int -> Posting -> String
unclassifiedLotWarning j t idx p =
  let amts = amountsRaw (pamount p)
      lotfulCommodities = [acommodity a | a <- amts, journalCommodityUsesLots j (acommodity a)]
      source = case lotfulCommodities of
        (c:_) -> T.unpack c ++ " is declared lotful (commodity lots: tag)"
        []    -> "this posting involves a lotful commodity"
      inferrednote = if hasAmount (originalPosting p) then "" else
        " (with inferred amount " ++ showMixedAmountOneLine (pamount p) ++ ")"
      (f, line, _, ex) = makePostingErrorExcerptByIndex (transactionAsWritten t) (asWrittenPostingIndex t idx) Nothing
  in printf "%s:%d:\n%s\n%s" f line ex (postingsReadAs t)
     ++ source ++ " but this posting" ++ inferrednote ++ " was not classified as\n"
     ++ "acquire, dispose, or transfer. Lot state will not be updated.\n"
     ++ "Possible fixes: add a cost basis ({$X}), a price (@ $X),\n"
     ++ "or check the account type declaration."

-- Validation and label generation

-- | Validate that user-provided labels don't create duplicate lot ids.
validateUserLabels :: [Transaction] -> Either String ()
validateUserLabels txns =
    case M.toList duplicates of
      [] -> Right ()
      (((c, d, l), t2:_):_) ->
        let (f, line, _, ex) = makeTransactionErrorExcerpt t2 (const Nothing)
        in Left $ printf (unlines [
              "%s:%d:"
             ,"%s"
             ,"lot id is not unique: commodity %s, date %s, label \"%s\""
             ]) f line ex (T.unpack c) (show d) (T.unpack l)
      _ -> Right ()  -- shouldn't happen
  where
    labeled = [ ((acommodity a, getLotDate t cb, l), t)
              | t <- txns
              , p <- tpostings t
              , isAcquirePosting p
              , a <- amountsRaw (pamount p)
              , Just cb <- [acostbasis a]
              , Just l  <- [cbLabel cb]
              ]
    txnsByKey = foldl' (\m (k, t) -> M.insertWith (++) k [t] m) M.empty labeled
    duplicates = M.filter (\ts -> length ts > 1) txnsByKey

-- | Find (commodity, date) pairs where there are multiple unlabeled
-- acquisitions, and thus need auto-generated labels to disambiguate.
-- Acquisitions with a user-provided label are already unique by that label,
-- so they don't force unlabeled siblings on the same date to be labelled.
-- (Duplicate user labels on the same date are caught later by the
-- duplicate-lot-id check in 'processAcquirePosting'.)
-- Bare acquire postings (no acostbasis) use the transaction date.
findDatesNeedingLabels :: [Transaction] -> S.Set (CommoditySymbol, Day)
findDatesNeedingLabels txns =
    M.keysSet $ M.filter (> 1) counts
  where
    counts = foldl' countAcquire M.empty
      [ (acommodity a, acquireDate t a)
      | t <- txns
      , p <- tpostings t
      , isAcquirePosting p
      , a <- amountsRaw (pamount p)
      , isNothing (acostbasis a >>= cbLabel)   -- only count unlabeled
      ]
    countAcquire m (c, d) = M.insertWith (+) (c, d) (1 :: Int) m
    acquireDate t a = case acostbasis a of
      Just cb -> getLotDate t cb
      Nothing -> tdate t

-- | Revert a transaction to (approximately) the form the user wrote, for
-- error display: postings are reverted to their original parse-time form,
-- and generated postings are dropped. This keeps error excerpts looking
-- like the journal file rather than the processed in-memory entry (#2686).
transactionAsWritten :: Transaction -> Transaction
transactionAsWritten t =
  t{tpostings = [originalPosting q | q <- tpostings t, not (isGeneratedPosting q)]}

-- | Map a 0-based index into a transaction's postings to the corresponding
-- index in the 'transactionAsWritten' form (which omits generated postings).
asWrittenPostingIndex :: Transaction -> Int -> Int
asWrittenPostingIndex t idx = length [() | q <- take idx (tpostings t), not (isGeneratedPosting q)]

-- | True if this posting was generated by processing (has the _generated-posting tag).
isGeneratedPosting :: Posting -> Bool
isGeneratedPosting = postingHasTag generatedPostingTagName

-- | A one-line summary of how lot classification read a transaction's
-- postings, to include in error messages after the as-written excerpt:
-- each non-generated posting's classification ("_ptype" tag value, or
-- "unclassified") in posting order, plus a count of any generated postings.
-- Returns "" when classification hasn't run yet (no posting has a ptype
-- tag), eg for errors raised at earlier pipeline stages.
-- The excerpt always shows what the user wrote; this line shows how
-- hledger interpreted it, since the interpretation (and any error arising
-- from it) may not be obvious from the entry alone.
postingsReadAs :: Transaction -> String
postingsReadAs t
  | not (any isClassifiedPosting ps) = ""
  | otherwise =
      "Postings were read as: " ++ intercalate ", " (map readAs written)
      ++ (case generated of
            [] -> ""
            gs -> "; and generated: " ++ intercalate ", " (map readAs gs))
      ++ ".\n"
  where
    ps = tpostings t
    (generated, written) = partition isGeneratedPosting ps
    readAs p = case lookup "_ptype" (ptags p) of
      Just ptype -> T.unpack ptype
      Nothing | postingHasTag lotParentAssertionTagName p -> "balance-assertion"
              | otherwise -> "unclassified"

-- | Format a verbose error prefix for a transaction: "file:line:\nexcerpt\n\n",
-- plus a summary of how the postings were classified, if they were ('postingsReadAs').
-- Prepend to an error message to show source position and a transaction excerpt,
-- rendered as the user wrote it ('transactionAsWritten').
txnErrPrefix :: Transaction -> String
txnErrPrefix t = printf "%s:%d:\n%s\n%s" f line ex (postingsReadAs t)
  where (f, line, _, ex) = makeTransactionErrorExcerpt (transactionAsWritten t) (const Nothing)

-- | Format a verbose error prefix for a posting: "file:line:\nexcerpt\n\n",
-- plus a classification summary, like 'txnErrPrefix', but marking the
-- specific posting's line, found by comparing cost-stripped postings
-- (falling back to the transaction line if the posting can't be identified).
postingErrPrefix :: Posting -> String
postingErrPrefix p = case ptransaction p of
  Nothing -> printf "%s:%d:\n%s\n" ("-"::String) (0::Int) (""::Text)
  Just t  -> case transactionFindPostingIndex ((== postingStripCosts p) . postingStripCosts) t of
    Nothing -> txnErrPrefix t
    Just i1 -> printf "%s:%d:\n%s\n%s" f line ex (postingsReadAs t)
      where (f, line, _, ex) =
              makePostingErrorExcerptByIndex (transactionAsWritten t) (asWrittenPostingIndex t (i1-1)) Nothing

-- | Emit a dbg5 trace for a lot operation: "lots: FILE:LINE DATE DESC: message".
lotDbg :: Transaction -> String -> a -> a
lotDbg t msg = dbg5With (\_ -> "lots: " ++ txnDbgPrefix t ++ ": " ++ msg)

-- | Format a one-line transaction summary for debug traces: "FILE:LINE DATE DESC".
txnDbgPrefix :: Transaction -> String
txnDbgPrefix t = printf "%s:%d %s %s" f line (show (tdate t)) (T.unpack (tdescription t))
  where (f, line, _, _) = makeTransactionErrorExcerpt t (const Nothing)

-- | Get the lot date from cost basis, falling back to the transaction date.
getLotDate :: Transaction -> CostBasis -> Day
getLotDate t cb = fromMaybe (tdate t) (cbDate cb)

-- | Generate a label for a lot that needs one (due to same-date collision).
-- Uses the smallest sequence number, formatted as four (or more) digits
-- ("0001", "0002", ...), that isn't already a label of an existing same-date
-- lot. Skipping used numbers avoids colliding with user-provided labels
-- that happen to be in the same format. Fully disposed lots remain visible
-- here as tombstones (see 'reduceLotState'), so their labels are not reused.
generateLabel :: CommoditySymbol -> Day -> LotState -> T.Text
generateLabel commodity date lotState = nextFree 1
  where
    existingLots = M.findWithDefault M.empty commodity lotState
    -- Use takeWhileAntitone/dropWhileAntitone for O(log n) range extraction.
    -- LotId is ordered by date first, so same-date lots form a contiguous range.
    sameDate = M.takeWhileAntitone (\(LotId d _) -> d == date)
             $ M.dropWhileAntitone (\(LotId d _) -> d < date) existingLots
    usedLabels = S.fromList $ mapMaybe (\(LotId _ ml) -> ml) (M.keys sameDate)
    nextFree :: Int -> T.Text
    nextFree n =
      let l = T.pack (printf "%04d" n)
      in if S.notMember l usedLabels then l else nextFree (n + 1)

-- Transaction dispatch

-- | Process a single transaction: transform its acquire, dispose, and transfer postings.
-- Transfer pairs are processed first (so that transferred lots are available for
-- subsequent disposals in the same transaction), then acquire and dispose postings.
-- Accumulates (LotState, [Transaction]) — transactions in reverse order.
processTransaction :: M.Map CommoditySymbol AmountStyle -> Bool -> Journal -> S.Set (CommoditySymbol, Day) -> (LotState, [Transaction]) -> Transaction
                       -> Either String (LotState, [Transaction])
processTransaction styles verbosetags j needsLabels (ls, acc) t = do
    -- Partition postings into transfer pairs and others
    let (transferFroms, transferTos, otherPs) = partitionTransferPostings (tpostings t)
        hasEquityOther = any (isEquityPosting j) otherPs
    -- Closing equity transfer: transfer-from postings with no transfer-to counterpart,
    -- where an equity posting receives the lots (e.g. close --clopen --lots).
    -- Reduce lots from state; pass all postings through unchanged (equity does not track lots).
    if not (null transferFroms) && null transferTos && hasEquityOther
      then do
        ls' <- foldM (reduceLotTransferToEquity j t) ls transferFroms
        return (ls', t : acc)
    -- Opening equity transfer: transfer-to postings with no transfer-from counterpart,
    -- where an equity posting is the source (e.g. opening balances from close --clopen --lots).
    -- Process transfer-to postings as acquires to add lots to the state.
    else if null transferFroms && not (null transferTos) && hasEquityOther
      then do
        -- Build map of processed transfer-to postings, then reconstruct in original order.
        let indexedTos = [(i, p) | (i, p) <- zip [0..] (tpostings t), isTransferToPosting p]
        (ls', toMap) <- foldM (\(st, m) (i, p) -> do
            (st', p') <- processAcquirePosting styles j needsLabels txnDate t st p
            return (st', M.insert i p' m)
          ) (ls, M.empty) indexedTos
        let allPs = [maybe p id (M.lookup i toMap) | (i, p) <- zip [0..] (tpostings t)]
        return (ls', t{tpostings = allPs} : acc)
    else do
        let indexedFroms = [(i, p) | (i, p) <- zip [0..] (tpostings t), isTransferFromPosting p]
            indexedTos   = [(i, p) | (i, p) <- zip [0..] (tpostings t), isTransferToPosting p]
            -- Fee-split dispose postings, which are by construction in the
            -- transfer source account (where the lots already exist).
            indexedFeeDisposes =
              [(i, p) | (i, p) <- zip [0..] (tpostings t)
                      , isDisposePosting p, postingHasTag feesplitPostingTagName p]
        -- Process fee-split disposes before the transfer pairs, so the
        -- disposal method in effect (FIFO, LIFO, ...) selects from the full
        -- pre-transfer lot set - eg under FIFO a transfer fee consumes the
        -- oldest lot - and the transfer carries the remainder. (#2692)
        (ls0, disposeMap) <- foldM processOneFeeDispose (ls, M.empty) indexedFeeDisposes
        groups <- groupIndexedTransferPostings t indexedFroms indexedTos
        -- Then transfer groups, building an IntMap from original index to expanded postings.
        (ls', transferMap) <- foldM processOneGroup (ls0, M.empty) groups
        -- Walk all postings in original order, substituting expanded results.
        (ls'', allPs) <- foldMPostings ls' [] (zip [0..] (tpostings t)) (M.union transferMap disposeMap)
        return (ls'', t{tpostings = reverse allPs} : acc)
  where
    txnDate = tdate t

    -- Process a fee-split dispose posting; record expanded postings keyed by original index.
    processOneFeeDispose (st, m) (i, p) = do
      (st', newPs) <- processDisposePosting styles verbosetags j t st p
      return (st', M.insert i newPs m)

    -- Process one commodity's transfer group; record expanded postings keyed by original index.
    processOneGroup (st, m) g = do
      (st', m') <- processTransferGroup styles verbosetags j t st g
      return (st', M.union m m')

    -- Walk postings in original order, looking up transfer results or processing normally.
    foldMPostings :: LotState -> [Posting] -> [(Int, Posting)] -> M.Map Int [Posting]
                  -> Either String (LotState, [Posting])
    foldMPostings st acc' [] _ = Right (st, acc')
    foldMPostings st acc' ((i,p):ps) tmap
      | Just expanded <- M.lookup i tmap =
          foldMPostings st (reverse expanded ++ acc') ps tmap
      | isAcquirePosting p = do
          (st', p') <- processAcquirePosting styles j needsLabels txnDate t st p
          foldMPostings st' (p':acc') ps tmap
      | isDisposePosting p = do
          (st', newPs) <- processDisposePosting styles verbosetags j t st p
          foldMPostings st' (reverse newPs ++ acc') ps tmap
      | isUnclassifiedLotfulPosting j p =
          Left (unclassifiedLotWarning j t i p)
      | otherwise =
          foldMPostings st (p:acc') ps tmap

-- | True if the posting is in an equity account.
isEquityPosting :: Journal -> Posting -> Bool
isEquityPosting j p = maybe False isEquityType (journalAccountType j (lotBaseAccount (paccount p)))

-- | Reduce lots from the lot state for a transfer-from posting going to an equity account.
-- Used when lots are transferred to equity (e.g. close --clopen --lots): reduces the lots
-- without requiring a matching transfer-to posting, since equity does not track lots.
reduceLotTransferToEquity :: Journal -> Transaction -> LotState -> Posting -> Either String LotState
reduceLotTransferToEquity j t ls p =
    case [(a, cb) | a <- amountsRaw (pamount p), Just cb <- [acostbasis a], isNegativeAmount a] of
      [(a, cb)] -> do
        let commodity = acommodity a
            qty       = negate (aquantity a)
            acct      = lotBaseAccount (paccount p)
            (method, methodSource) = resolveReductionMethodWithSource j p commodity
        selected <- selectLots (method, methodSource) (postingErrPrefix p) "transfer" (tdate t) acct commodity qty cb ls
        let consumed = [(lotId, qty') | (lotId, _, qty') <- selected]
        return $ lotDbg t ("equity-transfer " ++ show qty ++ " " ++ T.unpack commodity
                           ++ " from " ++ T.unpack acct
                           ++ " (lots: " ++ showSelectedLots selected ++ ")")
               $ reduceLotState acct commodity consumed ls
      _ -> Right ls  -- no single lot amount (e.g. cash posting): pass through

-- | Partition a transaction's postings into transfer-from, transfer-to, and others.
partitionTransferPostings :: [Posting] -> ([Posting], [Posting], [Posting])
partitionTransferPostings = go [] [] []
  where
    go froms tos others [] = (reverse froms, reverse tos, reverse others)
    go froms tos others (p:ps)
      | isTransferFromPosting p = go (p:froms) tos others ps
      | isTransferToPosting p   = go froms (p:tos) others ps
      | otherwise               = go froms tos (p:others) ps

-- | Group indexed transfer-from and transfer-to postings by commodity, and
-- check each group's consistency: both sides present, and total from/to
-- quantities equal (#2692). Transfer postings need not pair up one to one:
-- one source posting can feed several destinations, or several sources one
-- destination, as long as the totals match. Within each group, froms and
-- tos are sorted by cost basis fields (date, label, cost) so explicit
-- per-lot annotations align. Cost basis mismatches are caught later by
-- validation, not here.
groupIndexedTransferPostings :: Transaction -> [(Int, Posting)] -> [(Int, Posting)]
  -> Either String [(CommoditySymbol, [(Int, Posting)], [(Int, Posting)])]
groupIndexedTransferPostings _ [] [] = Right []
groupIndexedTransferPostings t froms tos = do
    fromGroups <- groupByCommodity "transfer-from" froms
    toGroups   <- groupByCommodity "transfer-to" tos
    let allComms = S.union (M.keysSet fromGroups) (M.keysSet toGroups)
    mapM (checkCommodityGroup fromGroups toGroups) (S.toList allComms)
  where
    showPos = txnErrPrefix t

    -- Group indexed postings by their lotful commodity.
    groupByCommodity :: String -> [(Int, Posting)] -> Either String (M.Map CommoditySymbol [(Int, Posting)])
    groupByCommodity label ips = do
      tagged <- mapM (\ip -> (,ip) <$> postingCommodity label (snd ip)) ips
      Right $ M.map reverse $ M.fromListWith (++) [(c, [ip]) | (c, ip) <- tagged]

    postingCommodity :: String -> Posting -> Either String CommoditySymbol
    postingCommodity label p =
      case [acommodity a | a <- amountsRaw (pamount p), isJust (acostbasis a)] of
        [c] -> Right c
        -- Transfer-to postings without {} have no cost basis; use the raw commodity.
        _   -> case [acommodity a | a <- amountsRaw (pamount p)] of
                 [c] -> Right c
                 _   -> Left $ showPos ++ label ++ " posting has no lotful commodity"

    -- Sort key for aligning explicit per-lot annotations within a commodity group.
    postingSortKey :: (Int, Posting) -> (Maybe Day, Maybe T.Text, Maybe (CommoditySymbol, Quantity))
    postingSortKey (_, p) =
      case [cb | a <- amountsRaw (pamount p), Just cb <- [acostbasis a]] of
        [cb] -> (cbDate cb, cbLabel cb,
                 fmap (\a -> (acommodity a, aquantity a)) (cbCost cb))
        _    -> (Nothing, Nothing, Nothing)

    checkCommodityGroup fromGroups toGroups comm = do
      let fs = M.findWithDefault [] comm fromGroups
          ts = M.findWithDefault [] comm toGroups
      case (fs, ts) of
        ([], _) -> Left $ showPos ++ "transfer-to posting for " ++ T.unpack comm
                            ++ " has no matching transfer-from posting"
        (_, []) -> Left $ showPos ++ "transfer-from posting for " ++ T.unpack comm
                            ++ " has no matching transfer-to posting"
        _ -> do
          -- The total from/to quantities must agree; a difference indicates an
          -- analysis failure or an unrecorded fee (#2692). (Transfer fees
          -- should be recorded as their own posting(s) in the same commodity;
          -- hledger then splits off matching disposal(s) automatically.)
          let qtyTotal ips = sum [ abs (aquantity a)
                                 | (_, p) <- ips, a <- amountsRaw (pamount p)
                                 , acommodity a == comm ]
              fromTotal = qtyTotal fs
              toTotal   = qtyTotal ts
          when (fromTotal /= toTotal) $
            Left $ showPos ++ "Mismatched transfer quantities for lot-tracked commodity " ++ T.unpack comm
                       ++ ": " ++ show fromTotal ++ " transferred out but "
                       ++ show toTotal ++ " received.\n"
                       ++ if toTotal > fromTotal
                          then "More was received than sent, which a fee can't explain;\n"
                            ++ "check the entry for sign errors or rounding adjustments."
                          else "If the difference is a fee, you can either\n"
                            ++ "- record the fee expense in the lot-tracked commodity, with posting(s)\n"
                            ++ "  adding up to the missing quantity\n"
                            ++ "- or split the sending posting into a transfer part and fee part(s)\n"
                            ++ "  matching the fee expense(s)."
          Right (comm, sortOn postingSortKey fs, sortOn postingSortKey ts)

-- | Extract a per-unit cost Amount from an AmountCost, normalising TotalCost by quantity.
-- If quantity is zero, returns the TotalCost amount as-is (avoiding division by zero).
-- Uses 'divideAmountAndUpdatePrecision' so the derived unit cost renders with the
-- quotient's digits rather than inheriting the total cost's narrower display style.
amountCostToUnitCost :: Quantity -> AmountCost -> Amount
amountCostToUnitCost _   (UnitCost c)  = c
amountCostToUnitCost qty (TotalCost c) = divideAmountAndUpdatePrecision qty c

-- | Normalize an amount's transacted cost to UnitCost form (converting TotalCost by dividing by quantity).
-- Returns Nothing if the amount has no transacted cost.
amountNormalizeCostToUnit :: Amount -> Maybe AmountCost
amountNormalizeCostToUnit a = fmap (UnitCost . amountCostToUnitCost (aquantity a)) (acost a)


-- Per-type posting processing

-- | Process a single acquire posting: generate a lot name and append it as a subaccount.
processAcquirePosting :: M.Map CommoditySymbol AmountStyle -> Journal -> S.Set (CommoditySymbol, Day) -> Day -> Transaction -> LotState -> Posting
                      -> Either String (LotState, Posting)
processAcquirePosting styles j needsLabels txnDate t lotState p = do
    let lotAmts = [(a, cb) | a <- amountsRaw (pamount p), Just cb <- [acostbasis a]]
    (lotAmt, cb, isBare) <- case lotAmts of
      [x] -> Right (fst x, snd x, False)
      _   -> do
        let bareAmts = [a | a <- amountsRaw (pamount p), not (isNegativeAmount a)]
        case bareAmts of
          [a] -> Right (a, CostBasis Nothing Nothing Nothing, True)
          _   -> Left $ showPos ++ "acquire posting has no cost basis"

    let commodity = acommodity lotAmt
        date      = fromMaybe txnDate (cbDate cb)

    -- Get the original (pre-balancing) amount to check for explicit transacted price.
    -- A unit cost on the original can be used directly as the cost basis;
    -- a total cost on the balanced amount is normalised to a per-unit cost basis.
    let origAmt = case poriginal p of
          Just orig -> case [a | a <- amountsRaw (pamount orig), acommodity a == commodity] of
                         (a:_) -> a
                         []    -> lotAmt
          Nothing   -> lotAmt

    let maybeLotBasis = case cbCost cb of
          Just c  -> Just c
          Nothing
            | Just (UnitCost c) <- acost origAmt -> Just c
            | Just cost <- acost lotAmt -> Just $ amountCostToUnitCost (aquantity lotAmt) cost
            | otherwise                 -> Nothing

    case maybeLotBasis of
      Nothing | isBare    -> Left $ showPos ++ T.unpack commodity
                                      ++ " is lotful but this acquire posting has no cost basis or price.\n"
                                      ++ "No lot will be created."
              | otherwise -> Left $ showPos ++ "acquire posting has no lot cost"
      Just lotBasis -> do
        let cbInferred = isNothing (cbCost cb)
            needsLabel = S.member (commodity, date) needsLabels
            lotLabel'  = cbLabel cb <|> if needsLabel then Just (generateLabel commodity date lotState) else Nothing
            -- If the lot id already exists (e.g. an equity transfer-to on the same date
            -- as a regular acquire, not predicted by findDatesNeedingLabels), auto-generate
            -- a label to disambiguate.
            existingLots = M.findWithDefault M.empty commodity lotState
            lotId0     = LotId date lotLabel'
            (lotId, lotLabel'')
              | isNothing (cbLabel cb) && M.member lotId0 existingLots
                = let l = generateLabel commodity date lotState
                  in (LotId date (Just l), Just l)
              | otherwise = (lotId0, lotLabel')
            baseAcct = lotBaseAccount (paccount p)
            (method, _methodSource) = resolveReductionMethodWithSource j p commodity

        -- Under AVERAGE/AVERAGEALL, merge this acquisition into the running pool
        -- (returns the new shared per-unit cost and an updated LotState where
        -- every existing pool lot's cbCost has been rewritten to that new cost).
        (lotBasisStored, lotState0) <-
          if methodIsAverage method
          then updatePoolOnAcquire showPos (methodIsGlobal method)
                 baseAcct commodity (aquantity lotAmt) lotBasis lotState
          else Right (lotBasis, lotState)

        let -- For an inferred cost, widen precision to the commodity style's
            -- declared minimum (eg 2.5 -> 2.50 with 'commodity €1.00'); for
            -- a user-written explicit cost, preserve their formatting.
            widenIfInferred = if cbInferred then widenLotCbCost styles else id
            -- The stored cost basis is styled/widened the same way as the lot
            -- subaccount name, so that later renderings of this lot's name
            -- (on dispose and transfer postings) match the acquire's.
            fullCb     = widenIfInferred $ styleLotCbCost styles
                           CostBasis{cbDate = Just date, cbLabel = lotLabel'', cbCost = Just lotBasisStored}
            lotName    = showLotNameForMethod method fullCb
            -- When cost basis was inferred, fill it in on the user's original cb
            -- so that print shows {$50} not {}. Style it the same way as the
            -- lot subaccount name.
            filledCb   = widenIfInferred $ styleLotCbCost styles cb{cbCost = Just lotBasis}
            -- The lot state stores the full cost basis (date/label/cost).
            -- Under AVERAGE this is the running pool cost; under other methods
            -- it is the original per-acquisition cost.
            lotStateAmt = lotAmt{acostbasis = Just fullCb}
            -- The displayed posting amount preserves the user's literal cost
            -- annotation (filling in only when they wrote `{}`). Under AVERAGE
            -- the running pool cost is a derived state — surfaced via bal -B
            -- and visible on disposal postings (where the user wrote `{}`
            -- and the system fills in the lot's stored cost).
            postingAmt  = if cbInferred then lotAmt{acostbasis = Just filledCb} else lotAmt

        let hasExplicitLotAcct = baseAcct /= paccount p
            expectedAcct = baseAcct <> ":" <> lotName

        -- If the user wrote an explicit lot subaccount, check that its parsed
        -- CostBasis is compatible with the resolved lot's.
        when hasExplicitLotAcct $
          case mergeCostBasisForMethod method cb fullCb of
            Right _ -> Right ()
            Left _  -> Left $ showPos ++ "lot subaccount " ++ T.unpack (paccount p)
                              ++ " does not match the resolved lot " ++ T.unpack expectedAcct

        -- Only a live lot (with account entries) is a duplicate; a tombstone
        -- (fully disposed lot, see 'reduceLotState') may be revived by an
        -- explicitly-labelled acquisition, eg re-opening balances after
        -- close --clopen --lots.
        when (maybe False (not . M.null) (M.lookup lotId existingLots)) $
          Left $ showPos ++ "duplicate lot id: " ++ T.unpack lotName
                  ++ " for commodity " ++ T.unpack commodity

        let p' = p{paccount = expectedAcct
                   ,pamount  = mixedAmount postingAmt
                   ,poriginal = Just (originalPosting p)}
        let lotState' = addLotState commodity lotId baseAcct lotStateAmt lotState0
        return $ lotDbg t ("acquired " ++ show (aquantity lotAmt) ++ " "
                           ++ T.unpack commodity ++ " " ++ T.unpack lotName
                           ++ " on " ++ T.unpack baseAcct)
               (lotState', p')
  where
    showPos = txnErrPrefix t

-- | Process a dispose posting: match to existing lots using the resolved reduction method,
-- split into multiple postings if the disposal spans multiple lots.
-- Returns the list of resulting postings (one per matched lot).
processDisposePosting :: M.Map CommoditySymbol AmountStyle -> Bool -> Journal -> Transaction -> LotState -> Posting
                      -> Either String (LotState, [Posting])
processDisposePosting styles verbosetags j t lotState p = do
    -- Extract lotful amount and lot selector. When cost basis is present, use it directly.
    -- When absent (bare dispose on a lotful commodity), use a wildcard selector.
    let lotAmts = [(a, cb) | a <- amountsRaw (pamount p), Just cb <- [acostbasis a]]
    (lotAmt, cb, isBare) <- case lotAmts of
      [x] -> Right (fst x, snd x, False)
      _   -> do
        let bareAmts = [a | a <- amountsRaw (pamount p), isNegativeAmount a]
        case bareAmts of
          [a] -> Right (a, CostBasis Nothing Nothing Nothing, True)
          _   -> Left $ showPos ++ "dispose posting has no cost basis"

    let commodity = acommodity lotAmt
        disposeQty = aquantity lotAmt

    -- Non-bare dispose (explicit {}) without price is an error - unless the
    -- entry's non-asset postings receive the same commodity in the same
    -- total quantity as its priceless disposals (an in-kind outflow: a
    -- transfer fee, a donation, etc): then it proceeds as a priceless
    -- disposal, like a bare one, with no gain calculated. This also lets
    -- print --lots output of unpriced-fee transfers (whose fee dispose
    -- fragment carries an explicit lot reference) round-trip (#2692).
    -- Bare dispose without price proceeds to lot matching (but skips gain generation).
    let isAsset acct = maybe False isAssetType (journalAccountType j (lotBaseAccount acct))
        nonAssetReceipts = sum [ aquantity a
                               | q <- tpostings t, not (isAsset (paccount q))
                               , a <- amountsRaw (pamount q)
                               , acommodity a == commodity, aquantity a > 0 ]
        pricelessDisposals = sum [ negate (aquantity a)
                                 | q <- tpostings t, isDisposePosting q
                                 , a <- amountsRaw (pamount q)
                                 , acommodity a == commodity, aquantity a < 0, isNothing (acost a) ]
        isInKindOutflow = nonAssetReceipts > 0 && nonAssetReceipts == pricelessDisposals
    case acost lotAmt of
      Nothing | not isBare && not isInKindOutflow ->
        Left $ showPos ++ "dispose posting has no transacted price (selling price) for " ++ T.unpack commodity
      _ -> do

        when (disposeQty >= 0) $
          Left $ showPos ++ "dispose posting has non-negative quantity for " ++ T.unpack commodity

        let posQty = negate disposeQty
            (method, methodSource) = resolveReductionMethodWithSource j p commodity
            -- All methods are per-account, scoped to the posting's base account
            -- (stripping any explicit lot subaccount the user may have written).
            scopeAcct = lotBaseAccount (paccount p)

        when (isBare && method == SPECID) $
          Left $ showPos ++ "SPECID requires a lot selector on dispose postings"
                 ++ "\nUsing SPECID (" ++ methodSource ++ ")."

        selected <- selectLots (method, methodSource) (postingErrPrefix p) "disposal" (tdate t) scopeAcct commodity posQty cb lotState

        let baseAcct = lotBaseAccount (paccount p)
            hasExplicitLotAcct = baseAcct /= paccount p
            mkPosting (lotId, storedAmt, consumedQty) = do
              -- Under AVERAGE/AVERAGEALL the stored cost is already the running
              -- pool cost (maintained in lock-step on each acquisition); for
              -- other methods it's the per-acquisition cost. Either way, just
              -- read it from the stored lot.
              origBasis <- case acostbasis storedAmt >>= cbCost of
                Just c  -> Right c
                Nothing -> Left $ showPos ++ "lot " ++ T.unpack (T.pack (show lotId))
                                    ++ " for commodity " ++ T.unpack commodity
                                    ++ " has no cost basis (internal error)"
              let lotCb = CostBasis
                    { cbDate  = Just (lotDate lotId)
                    , cbLabel = lotLabel lotId
                    , cbCost  = Just origBasis
                    }
                  lotName = showLotNameForMethod method (styleLotCbCost styles lotCb)
                  expectedAcct = baseAcct <> ":" <> lotName
              -- If the user wrote an explicit lot subaccount, check that its
              -- parsed CostBasis is compatible with the resolved lot's.
              when hasExplicitLotAcct $
                case mergeCostBasisForMethod method cb lotCb of
                  Right _ -> Right ()
                  Left _  -> Left $ showPos ++ "lot subaccount " ++ T.unpack (paccount p)
                                    ++ " does not match the resolved lot " ++ T.unpack expectedAcct
              let acctWithLot = expectedAcct
                  -- Build the dispose amount: negative consumed quantity,
                  -- keeping the original amount's commodity, style, cost, and cost basis.
                  disposeAmt = (amountSetQuantity (negate consumedQty) lotAmt){acostbasis = Just lotCb}
              let -- For bare disposes without a price (e.g. fee deductions), keep no cost.
                  -- When splitting across multiple lots, normalize TotalCost to UnitCost
                  -- (since TotalCost would be wrong for the split quantity).
                  disposeAmt' | isNothing (acost lotAmt) = disposeAmt{acost = Nothing}
                              | isBare && length selected > 1 = disposeAmt{acost = amountNormalizeCostToUnit lotAmt}
                              | otherwise = disposeAmt
              Right p{ paccount  = acctWithLot
                     , pamount   = mixedAmount disposeAmt'
                     , poriginal = Just (originalPosting p)
                     }

        newPostings0 <- mapM mkPosting selected
        -- For multi-lot disposals, tag each fragment as a per-lot split so
        -- journalCollapseLotDetail can merge them back to a single posting
        -- (when --lots is off). Single-lot disposals need no tag — they
        -- already represent the user's original posting.
        -- See also [better lot splitting].
        let taggedPostings = case newPostings0 of
              [_] -> newPostings0
              _   -> map (postingAddHiddenAndMaybeVisibleTag False verbosetags (lotsplitPostingTagName, "")) newPostings0
        let consumed  = [(lotId, qty) | (lotId, _, qty) <- selected]
            lotState' = reduceLotState scopeAcct commodity consumed lotState
            -- A single-fragment dispose with no other lots remaining for this
            -- commodity on scopeAcct doesn't need the =* parent-assertion
            -- synthetic: the lot subaccount balance equals the parent balance,
            -- so the user's assertion is correct as-is on the single fragment.
            noOtherLots = all (M.notMember scopeAcct) $ M.elems
                        $ M.findWithDefault M.empty commodity lotState'
            finalPostings = case taggedPostings of
              [_] | noOtherLots -> taggedPostings
              _ -> preserveParentAssertion verbosetags (paccount p) (pbalanceassertion p) taggedPostings

        return $ lotDbg t ("disposed " ++ show posQty ++ " " ++ T.unpack commodity
                           ++ " from " ++ T.unpack scopeAcct
                           ++ " (" ++ show method ++ ", lots: " ++ showSelectedLots selected ++ ")")
               (lotState', finalPostings)
  where
    showPos = txnErrPrefix t

-- [better lot splitting]
-- "If you want it bulletproof: the robust fix is a per-call group ID.
-- In processDisposePosting / the transfer caller, mint a small unique tag value 
-- (e.g. the source position string of p, or a counter, or T.pack (show (psourcepos p)))
-- and store it on each fragment as (lotsplitPostingTagName, groupId).
-- Then mergeLotSplits groups by tag value, not poriginal equality.
-- That removes the "Eq Posting must include something distinguishing" invariant entirely.

-- | Process one commodity's transfer group: select lots from each source
-- (transfer-from) posting's account, in group order, then distribute the
-- selected lots across the destination (transfer-to) postings in group
-- order, splitting lots at destination boundaries. Sources and destinations
-- need not pair up one to one; the group's total from/to quantities have
-- already been checked equal by 'groupIndexedTransferPostings'.
-- Returns the updated LotState and each original posting index's expanded postings.
processTransferGroup :: M.Map CommoditySymbol AmountStyle -> Bool -> Journal -> Transaction -> LotState
                     -> (CommoditySymbol, [(Int, Posting)], [(Int, Posting)])
                     -> Either String (LotState, M.Map Int [Posting])
processTransferGroup styles verbosetags j t lotState0 (commodity, ifroms, itos) = do
    -- Select lots for each transfer-from posting, reducing the lot state.
    (lotState1, fromDoneR) <- foldM doFrom (lotState0, []) ifroms
    let fromDone = reverse fromDoneR
        -- All selected lot fragments, in group order, available for distribution.
        queue0 = [ (lotId, storedAmt, qty, fromAmt)
                 | (_, _, fromAmt, selected) <- fromDone
                 , (lotId, storedAmt, qty) <- selected ]
    -- Distribute the fragments across the transfer-to postings.
    (lotState2, toDoneR, rest) <- foldM doTo (lotState1, [], queue0) itos
    -- The group's totals are equal, so distribution must come out exact.
    unless (null rest) $
      Left $ showPos ++ "could not distribute transferred lots exactly (internal error)"
    fromEntries <- mapM mkFromEntry fromDone
    Right (lotState2, M.fromList (fromEntries ++ reverse toDoneR))
  where
    showPos = txnErrPrefix t

    -- Extract a from posting's lotful amount and lot selector, validate it,
    -- and select the lots it consumes from its account.
    doFrom (st, acc) (i, fromP) = do
      -- When cost basis is present, use it directly as the lot selector.
      -- When absent (bare transfer on a lotful commodity), use a wildcard selector.
      (fromAmt, fromCb) <- case [(a, cb) | a <- amountsRaw (pamount fromP), Just cb <- [acostbasis a]] of
        [x] -> Right x
        _   -> case [a | a <- amountsRaw (pamount fromP), isNegativeAmount a] of
                 [a] -> Right (a, CostBasis Nothing Nothing Nothing)
                 _   -> Left $ showPos ++ "transfer-from posting has no cost basis"
      checkNoTransactedPrice fromP
      when (aquantity fromAmt >= 0) $
        Left $ showPos ++ "transfer-from posting has non-negative quantity for " ++ T.unpack commodity
      let fromQty = negate (aquantity fromAmt)
          -- Transfers are always per-account (scoped to source), but ordering follows the method.
          (method, methodSource) = resolveReductionMethodWithSource j fromP commodity
          fromBaseAcct = lotBaseAccount (paccount fromP)
      selected <- selectLots (method, methodSource) (postingErrPrefix fromP) "transfer" (tdate t) fromBaseAcct commodity fromQty fromCb st
      let st' = reduceLotState fromBaseAcct commodity [(lid, qty) | (lid, _, qty) <- selected] st
      return $ lotDbg t ("transferred out " ++ show fromQty ++ " " ++ T.unpack commodity
                          ++ " from " ++ T.unpack fromBaseAcct
                          ++ " (lots: " ++ showSelectedLots selected ++ ")")
             (st', (i, fromP, fromAmt, selected) : acc)

    -- Generate a from posting's per-lot display fragments.
    mkFromEntry (i, fromP, fromAmt, selected) = do
      ps <- mapM mk selected
      Right (i, preserveParentAssertion verbosetags (paccount fromP) (pbalanceassertion fromP) (tagIfMulti ps))
      where
        mk (lotId, storedAmt, qty) = do
          lotCb <- lotCbOf lotId storedAmt
          let (fromMethod, _) = resolveReductionMethodWithSource j fromP commodity
              lotName = showLotNameForMethod fromMethod (styleLotCbCost styles lotCb)
              -- Use base accounts to avoid double-appending lot subaccounts.
              fromAcct = lotBaseAccount (paccount fromP) <> ":" <> lotName
              fromAmt' = (amountSetQuantity (negate qty) fromAmt){acostbasis = Just lotCb}
          -- poriginal preserves the user's original annotations, unmodified.
          Right fromP{ paccount = fromAcct
                     , pamount  = mixedAmount fromAmt'
                     , poriginal = Just (originalPosting fromP)
                     }

    -- Give a to posting its share of the selected lot fragments, generating
    -- its display fragments and re-adding the lots under its account.
    doTo (st, acc, queue) (i, toP) = do
      checkNoTransactedPrice toP
      toQty <- case [aquantity a | a <- amountsRaw (pamount toP), acommodity a == commodity, aquantity a > 0] of
        [q] -> Right q
        _   -> Left $ showPos ++ "transfer-to posting has no single positive "
                        ++ T.unpack commodity ++ " amount"
      -- Extract the transfer-to cost basis for optional validation.
      let toCb = case [(a, cb) | a <- amountsRaw (pamount toP), Just cb <- [acostbasis a]] of
                   [(_, cb)] -> Just cb
                   _         -> Nothing
          (portions, queue') = drawFromQueue toQty queue
          (toMethod, _) = resolveReductionMethodWithSource j toP commodity
          toBaseAcct = lotBaseAccount (paccount toP)
      when (sum [qty | (_, _, qty, _) <- portions] /= toQty) $
        Left $ showPos ++ "could not distribute transferred lots exactly (internal error)"
      toPs <- mapM (mkToPosting toMethod toP toCb) portions
      st' <- foldM (addTransferredLot toMethod toBaseAcct) st
                   [(lid, amt, qty) | (lid, amt, qty, _) <- portions]
      return $ lotDbg t ("transferred in " ++ show toQty ++ " " ++ T.unpack commodity
                          ++ " to " ++ T.unpack toBaseAcct)
             (st', (i, preserveParentAssertion verbosetags (paccount toP) (pbalanceassertion toP) (tagIfMulti toPs)) : acc, queue')

    mkToPosting toMethod toP toCb (lotId, storedAmt, qty, fromAmt) = do
      lotCb <- lotCbOf lotId storedAmt
      -- Validate transfer-to cost basis if it has specific fields
      validateToCb toMethod toCb lotCb
      let lotName = showLotNameForMethod toMethod (styleLotCbCost styles lotCb)
          toAcct = lotBaseAccount (paccount toP) <> ":" <> lotName
          toAmt' = (amountSetQuantity qty fromAmt){acostbasis = Just lotCb}
      Right toP{ paccount = toAcct
               , pamount  = mixedAmount toAmt'
               , poriginal = Just (originalPosting toP)
               }

    -- Take fragments totalling the given quantity from the front of the
    -- queue, splitting the boundary fragment if needed.
    drawFromQueue :: Quantity -> [(LotId, Amount, Quantity, Amount)]
                  -> ([(LotId, Amount, Quantity, Amount)], [(LotId, Amount, Quantity, Amount)])
    drawFromQueue 0 queue = ([], queue)
    drawFromQueue _ [] = ([], [])
    drawFromQueue need ((lid, amt, qty, fa):rest)
      | need >= qty = let (taken, rest') = drawFromQueue (need - qty) rest
                      in ((lid, amt, qty, fa):taken, rest')
      | otherwise   = ([(lid, amt, need, fa)], (lid, amt, qty - need, fa):rest)

    -- Check that a transfer posting has no user-written transacted price (@ or @@).
    -- Use originalPosting to distinguish user-written @ from pipeline-inferred acost.
    checkNoTransactedPrice p =
      when (any (isJust . acost) (amountsRaw $ pamount $ originalPosting p)) $
        Left $ showPos ++ "lot transfers should have no transacted price"

    -- For multi-fragment postings, tag each fragment as a per-lot split so
    -- journalCollapseLotDetail can merge them back to a single posting when
    -- --lots is off. Single-fragment postings need no tag.
    tagIfMulti ps = case ps of
      [_] -> ps
      _   -> map (postingAddHiddenAndMaybeVisibleTag False verbosetags (lotsplitPostingTagName, "")) ps

    -- Reconstruct a lot's full cost basis from its id and stored amount.
    lotCbOf lotId storedAmt = case acostbasis storedAmt >>= cbCost of
      Just c  -> Right CostBasis{cbDate = Just (lotDate lotId), cbLabel = lotLabel lotId, cbCost = Just c}
      Nothing -> Left $ showPos ++ "lot " ++ show lotId
                          ++ " for commodity " ++ T.unpack commodity
                          ++ " has no cost basis (internal error)"

    -- If the transfer-to posting has any attributes specified in a lot annotation,
    -- make sure they correspond to the source lot's attributes.
    -- Transfers are not allowed to change a lot's identity.
    -- Under an AVERAGE destination method the cost check is skipped:
    -- the pool's running cost legitimately differs from any written cost
    -- (cf mergeCostBasisForMethod).
    validateToCb _ Nothing _ = Right ()
    validateToCb method (Just toCb') lotCb =
        when (dateMismatch || labelMismatch || costMismatch) $
          Left $ showPos <> unlines
            ["Destination lot info " <> T.unpack (showLotName toCb') <> " does not match the source lot " <> T.unpack (showLotName lotCb) <> "."
            ,"Transfers must preserve the source lot's identity."
            ,"Remove the destination lot annotation, or make it match the source lot's info."
            ]

      where
        dateMismatch  = case cbDate toCb' of
          Just d  -> cbDate lotCb /= Just d
          Nothing -> False
        labelMismatch = case cbLabel toCb' of
          Just l  -> cbLabel lotCb /= Just l
          Nothing -> False
        costMismatch  = not (methodIsAverage method) &&
          case (cbCost toCb', cbCost lotCb) of
            (Just c, Just lc) -> not (lotCostsMatch c lc)
            _                 -> False

    -- Re-add a transferred lot to LotState under the destination account.
    -- If the destination uses an AVERAGE method, first re-average its pool
    -- with the incoming quantity at its carried cost, like an acquisition;
    -- the incoming lot is then stored at the new pool cost. (Under
    -- AVERAGEALL this is a no-op: the lot never left the global pool, so
    -- the carried cost equals the pool cost.)
    addTransferredLot method destAcct ls (lotId, storedAmt, consumedQty)
      | methodIsAverage method = do
          lotCb <- lotCbOf lotId storedAmt
          carried <- maybe (Left $ showPos ++ "lot " ++ show lotId
                              ++ " has no carried cost (internal error)") Right (cbCost lotCb)
          (newAvg, ls') <- updatePoolOnAcquire showPos (methodIsGlobal method)
                             destAcct commodity consumedQty carried ls
          let amt = storedAmt{aquantity = consumedQty, acostbasis = Just lotCb{cbCost = Just newAvg}}
          Right $ addLotState commodity lotId destAcct amt ls'
      | otherwise =
          let amt = storedAmt{aquantity = consumedQty}
          in Right $ addLotState commodity lotId destAcct amt ls

-- Lot state operations

-- | Add an amount to LotState for a specific account/commodity/lot.
-- If the lot already exists on that account, quantities are summed (not overwritten).
-- This can happen when the same lot is transferred to the same destination account
-- by multiple transactions (e.g. two transfers on the same date both move portions
-- of the same lot).
addLotState :: CommoditySymbol -> LotId -> AccountName -> Amount -> LotState -> LotState
addLotState commodity lotId account amt =
  M.insertWith (M.unionWith (M.unionWith addQty)) commodity
    (M.singleton lotId (M.singleton account amt))
  where addQty a1 a2 = a1{aquantity = aquantity a1 + aquantity a2}


-- | Select lots to consume using the given reduction method.
-- All methods select from the specified account only.
-- Ordering: FIFO\/FIFOALL oldest-first; LIFO\/LIFOALL newest-first;
-- HIFO\/HIFOALL highest per-unit cost first; AVERAGE\/AVERAGEALL FIFO order;
-- SPECID requires an explicit selector matching one lot.
-- The *ALL variants additionally validate that the selected lots would also be
-- chosen first if all accounts' lots were considered together (see 'validateGlobalCompliance').
-- The lot selector filters which lots are eligible: each non-Nothing field
-- in the selector must match the corresponding field in the lot's cost basis.
-- An all-Nothing selector (from @{}@) matches all lots.
-- Returns a list of (lot id, lot amount, quantity consumed from this lot).
-- Errors if total available quantity in matching lots is insufficient.
selectLots :: (ReductionMethod, String) -> String -> String -> Day -> AccountName -> CommoditySymbol
           -> Quantity -> CostBasis -> LotState
           -> Either String [(LotId, Amount, Quantity)]
selectLots (method, methodSource) posStr operation date account commodity qty selector lotState = do
    when (method == SPECID && isWildcardSelector selector) $
      Left $ posStr ++ "SPECID requires an explicit lot selector" ++ methodline
    let allLots = M.findWithDefault M.empty commodity lotState
        -- Flatten to (LotId, Amount) pairs, taking only the specified account's balance.
        flatLots = M.mapMaybe (M.lookup account) allLots
        matchingLots = M.filter (lotMatchesSelector selector) flatLots
    when (M.null matchingLots) $
      Left $ posStr ++
        if M.null flatLots
        then "no " ++ T.unpack commodity
              ++ " lots available for " ++ operation
              ++ " from account " ++ T.unpack account
              ++ " on " ++ show date
              ++ showOtherAccountLots allLots
        else "no lots matching " ++ T.unpack (showLotName selector)
              ++ " for commodity " ++ T.unpack commodity
              ++ " in account " ++ T.unpack account
              ++ " on " ++ show date
              ++ "\nAvailable lots in this account:" ++ showLotList flatLots
    when (method == SPECID && M.size matchingLots > 1) $
      Left $ posStr ++ "lot selector is ambiguous, matches " ++ show (M.size matchingLots)
              ++ " lots in account " ++ T.unpack account ++ ":"
              ++ showLotList matchingLots ++ methodline
    let available = sum [aquantity a | a <- M.elems matchingLots]
    when (available < qty) $
      Left $ posStr ++ "Insufficient lots for commodity " ++ T.unpack commodity
              ++ " in account " ++ T.unpack account
              ++ ": need " ++ show qty ++ " but only " ++ show available ++ " available"
              -- with an explicit lot selector, show what it matched;
              -- for a generic outflow the lot details wouldn't help
              ++ (if isWildcardSelector selector then ""
                  else "\nLots matching " ++ T.unpack (showLotName selector) ++ ":"
                        ++ showLotList matchingLots)
              ++ showOtherAccountLots allLots
    let base = methodBaseOrdering method
        orderedLots = case base of
          FIFO    -> M.toAscList matchingLots
          LIFO    -> M.toDescList matchingLots
          HIFO    -> sortOn (Down . lotPerUnitCost) (M.toList matchingLots)
          AVERAGE -> M.toAscList matchingLots
          SPECID  -> M.toAscList matchingLots
          _       -> M.toAscList matchingLots  -- unreachable after methodBaseOrdering
        selected = go qty orderedLots
    when (methodIsGlobal method) $
      first (++ methodline) $
      validateGlobalCompliance method posStr account commodity qty selector lotState selected
    Right selected
  where
    -- The reduction method and where it came from; appended to the errors
    -- where the method matters (the availability errors omit it).
    methodline = "\nUsing " ++ show method ++ " (" ++ methodSource ++ ")."

    go 0 _ = []
    go _ [] = []  -- shouldn't happen after the check above
    go remaining ((lotId, lotAmt):rest)
      | remaining >= lotBal = (lotId, lotAmt, lotBal) : go (remaining - lotBal) rest
      | otherwise           = [(lotId, lotAmt, remaining)]
      where lotBal = aquantity lotAmt

    -- Show lots one per line, at most 10; a final line counts any more,
    -- and another shows the total quantity.
    showLotList :: M.Map LotId Amount -> String
    showLotList lots = concatMap fmt shown ++ more ++ totalline
      where
        (shown, rest) = splitAt 10 (M.toAscList lots)
        fmt (lid, a) = "\n  " ++ T.unpack (showLotName (lotIdToCb lid a))
                        ++ "  " ++ show (aquantity a)
        more = case length rest of
          0 -> ""
          1 -> "\n  ...and 1 more lot"
          n -> "\n  ...and " ++ show n ++ " more lots"
        totalline = "\n  Total: " ++ show (sum (map aquantity (M.elems lots)))
                     ++ " " ++ T.unpack commodity

    -- Summarise this commodity's lots in accounts other than the specified
    -- one: for each account, the total quantity and number of lots; and
    -- when there are several accounts, the total quantity overall.
    showOtherAccountLots :: M.Map LotId (M.Map AccountName Amount) -> String
    showOtherAccountLots allLots' =
      let others = [(acct, a) | (_, acctMap) <- M.toAscList allLots'
                              , (acct, a) <- M.toList acctMap, acct /= account]
          byAcct = M.fromListWith (\(q1, n1) (q2, n2) -> (q1 + q2, n1 + n2))
                     [(acct, (aquantity a, 1 :: Int)) | (acct, a) <- others]
          totalline
            | M.size byAcct < 2 = ""
            | otherwise = "\n  Total: " ++ show (sum [q | (q, _) <- M.elems byAcct])
                           ++ " " ++ T.unpack commodity
      in if M.null byAcct then ""
         else "\nLots of " ++ T.unpack commodity ++ " in other accounts:"
           ++ concatMap fmtAcct (M.toAscList byAcct)
           ++ totalline
      where fmtAcct (acct, (q, n)) = "\n  " ++ T.unpack acct ++ ": "
              ++ show q ++ " " ++ T.unpack commodity
              ++ " in " ++ show n ++ (if n == 1 then " lot" else " lots")

-- | Extract the per-unit cost quantity from a lot entry, for HIFO sorting.
lotPerUnitCost :: (LotId, Amount) -> Quantity
lotPerUnitCost (_, a) = maybe 0 aquantity (acostbasis a >>= cbCost)

-- | Whether a reduction method uses weighted average cost basis for disposals.
methodIsAverage :: ReductionMethod -> Bool
methodIsAverage AVERAGE    = True
methodIsAverage AVERAGEALL = True
methodIsAverage _          = False

-- | Whether a reduction method requires global validation across all accounts.
methodIsGlobal :: ReductionMethod -> Bool
methodIsGlobal FIFOALL    = True
methodIsGlobal LIFOALL    = True
methodIsGlobal HIFOALL    = True
methodIsGlobal AVERAGEALL = True
methodIsGlobal _          = False

-- | Map a *ALL method to its base ordering, or return the method unchanged.
methodBaseOrdering :: ReductionMethod -> ReductionMethod
methodBaseOrdering FIFOALL    = FIFO
methodBaseOrdering LIFOALL    = LIFO
methodBaseOrdering HIFOALL    = HIFO
methodBaseOrdering AVERAGEALL = AVERAGE
methodBaseOrdering m          = m

-- | Flatten lots across all accounts, summing quantities for shared lot IDs.
-- From @Map LotId (Map AccountName Amount)@ to @Map LotId Amount@,
-- combining quantities across accounts (taking the first Amount's metadata).
flattenAllAccountLots :: M.Map LotId (M.Map AccountName Amount) -> M.Map LotId Amount
flattenAllAccountLots = M.mapMaybe flattenAccts
  where
    flattenAccts acctMap =
      case M.elems acctMap of
        []       -> Nothing
        (a:rest) -> Just a{aquantity = aquantity a + sum (map aquantity rest)}

-- | Validate that the per-account selected lots would also be chosen first
-- under a global ordering across all accounts. Errors if lots on other accounts
-- have higher priority than the selected lots.
validateGlobalCompliance :: ReductionMethod -> String -> AccountName -> CommoditySymbol
                         -> Quantity -> CostBasis -> LotState
                         -> [(LotId, Amount, Quantity)] -> Either String ()
validateGlobalCompliance method posStr account commodity qty selector lotState selected = do
    let allLots = M.findWithDefault M.empty commodity lotState
        globalFlat = flattenAllAccountLots allLots
        globalMatching = M.filter (lotMatchesSelector selector) globalFlat
        base = methodBaseOrdering method
        globalOrdered = case base of
          FIFO    -> M.toAscList globalMatching
          LIFO    -> M.toDescList globalMatching
          HIFO    -> sortOn (Down . lotPerUnitCost) (M.toList globalMatching)
          AVERAGE -> M.toAscList globalMatching
          _       -> M.toAscList globalMatching
        -- Greedily consume qty from the globally-ordered list
        globalSelectedIds = S.fromList $ map fst3 $ goConsume qty globalOrdered
        selectedIds = S.fromList [lid | (lid, _, _) <- selected]
        -- Lot IDs that would be globally selected but are NOT in the per-account selection
        -- (i.e. they exist on other accounts and have higher priority)
        higherPriorityElsewhere = S.difference globalSelectedIds selectedIds
    unless (S.null higherPriorityElsewhere) $ do
      -- Build detailed error showing which accounts hold the higher-priority lots
      let otherLots = [(acct, lid, a)
                      | lid <- S.toList higherPriorityElsewhere
                      , Just acctMap <- [M.lookup lid allLots]
                      , (acct, a) <- M.toList acctMap]
          byAcct = M.fromListWith (++) [(acct, [(lid, a)]) | (acct, lid, a) <- otherLots]
          fmtAcct (acct, lots) = "\n  " ++ T.unpack acct ++ ": "
            ++ intercalate ", " [T.unpack (showLotName (lotIdToCb lid a)) ++ "  " ++ show (aquantity a)
                                | (lid, a) <- lots]
          fmtSelected = concatMap (\(lid, a, q) -> "\n  " ++ T.unpack (showLotName (lotIdToCb lid a))
                                                    ++ "  " ++ show q) selected
      Left $ posStr ++ show method ++ ": lot(s) on other account(s) have higher priority than the lots in "
              ++ T.unpack account ++ ":"
              ++ concatMap fmtAcct (M.toAscList byAcct)
              ++ "\nSelected from " ++ T.unpack account ++ ":"
              ++ fmtSelected
              ++ "\nConsider disposing from the account(s) listed above first, or use "
              ++ show (methodBaseOrdering method) ++ " for per-account scope."
  where
    goConsume 0 _ = []
    goConsume _ [] = []
    goConsume remaining ((lotId, lotAmt):rest)
      | remaining >= aquantity lotAmt = (lotId, lotAmt, aquantity lotAmt) : goConsume (remaining - aquantity lotAmt) rest
      | otherwise = [(lotId, lotAmt, remaining)]
    fst3 (x, _, _) = x

-- | Under AVERAGE / AVERAGEALL: integrate a new acquisition into the running
-- pool and return (new shared per-unit cost, lot state with every existing
-- pool lot's stored cbCost updated to that new cost).
--
-- @globalPool@ = True for AVERAGEALL — the pool spans all accounts holding
-- this commodity. False for AVERAGE — the pool is restricted to lots living
-- under @scopeAcct@; lots under other accounts have their own independent pools.
updatePoolOnAcquire
  :: String           -- ^ error-message position prefix
  -> Bool             -- ^ globalPool (AVERAGEALL if True)
  -> AccountName      -- ^ scopeAcct (used when not globalPool)
  -> CommoditySymbol
  -> Quantity         -- ^ this acquisition's quantity
  -> Amount           -- ^ this acquisition's per-unit cost
  -> LotState
  -> Either String (Amount, LotState)
updatePoolOnAcquire posStr globalPool scopeAcct commodity acqQty acqCost lotState = do
    let commLots = M.findWithDefault M.empty commodity lotState
        -- The per-LotId Amounts belonging to the pool: all accounts if global,
        -- otherwise just the one under scopeAcct.
        poolAmts accts
          | globalPool = M.elems accts
          | otherwise  = maybe [] pure (M.lookup scopeAcct accts)
        existingEntries = [(aquantity a, c) | accts <- M.elems commLots
                                            , a     <- poolAmts accts
                                            , Just cb <- [acostbasis a]
                                            , Just c  <- [cbCost cb]]
    -- All pool entries (including this acquisition) must agree on cost commodity.
    case listToMaybe existingEntries of
      Just (_, firstCost) | acommodity firstCost /= acommodity acqCost ->
        Left $ posStr ++ "cannot average lots with different cost commodities"
      _ -> Right ()
    let totalQty  = acqQty + sum [q | (q, _) <- existingEntries]
        totalCost = acqQty * aquantity acqCost
                  + sum [q * aquantity c | (q, c) <- existingEntries]
    when (totalQty == 0) $
      Left $ posStr ++ "cannot average lots with zero total quantity"
    let newAvg = acqCost{aquantity = totalCost / totalQty}
        rewriteAmt a = case acostbasis a of
          Nothing -> a
          Just cb -> a{acostbasis = Just cb{cbCost = Just newAvg}}
        rewriteAccts accts
          | globalPool = M.map rewriteAmt accts
          | otherwise  = M.adjust rewriteAmt scopeAcct accts
        lotState' = M.insert commodity (M.map rewriteAccts commLots) lotState
    return (newAvg, lotState')

-- | Is this an all-Nothing (wildcard) lot selector, i.e. from @{}@?
isWildcardSelector :: CostBasis -> Bool
isWildcardSelector (CostBasis Nothing Nothing Nothing) = True
isWildcardSelector _ = False

-- | Does a lot match a lot selector?
-- Each non-Nothing field in the selector must match the lot's stored cost basis.
lotMatchesSelector :: CostBasis -> Amount -> Bool
lotMatchesSelector selector a =
    case acostbasis a of
      Nothing    -> False
      Just lotCb -> matchCost (cbCost selector) (cbCost lotCb)
                 && matchField cbDate selector lotCb
                 && matchField cbLabel selector lotCb
  where
    matchField :: Eq b => (CostBasis -> Maybe b) -> CostBasis -> CostBasis -> Bool
    matchField f sel lot = case f sel of
      Nothing -> True   -- selector doesn't constrain this field
      Just v  -> f lot == Just v
    -- Compare costs by commodity and quantity, ignoring style differences
    -- (but accepting a display-rounded rendering, see 'lotCostsMatch').
    matchCost :: Maybe Amount -> Maybe Amount -> Bool
    matchCost Nothing    _          = True
    matchCost (Just _)   Nothing    = False
    matchCost (Just sel) (Just lot) = lotCostsMatch sel lot

-- | Subtract consumed quantities from LotState for a specific account.
-- Removes lot-account entries whose balance reaches zero.
-- A fully consumed lot's id is kept as a tombstone (a lot with no account
-- entries), so that its label is never reused by a later same-date
-- acquisition ('generateLabel'), keeping lot histories unambiguous.
-- Tombstones are invisible elsewhere: lot selection, transfers, and pool
-- updates all look only at lots' per-account amounts.
reduceLotState :: AccountName -> CommoditySymbol -> [(LotId, Quantity)] -> LotState -> LotState
reduceLotState account commodity consumed = M.adjust adjustCommodity commodity
  where
    adjustCommodity lots = foldl' reduceLot lots consumed
    reduceLot lots (lotId, qty) = M.adjust shrinkLot lotId lots
      where
        shrinkLot = M.update (shrinkAmt qty) account
        shrinkAmt q a
          | aquantity a <= q = Nothing
          | otherwise        = Just a{aquantity = aquantity a - q}

-- Debug trace helpers

-- | Reconstruct a CostBasis from a LotId and a stored Amount (for display in trace messages).
lotIdToCb :: LotId -> Amount -> CostBasis
lotIdToCb lid a = CostBasis (Just (lotDate lid)) (lotLabel lid) (acostbasis a >>= cbCost)

-- | Show selected lots for trace messages: "{2026-01-15, $50} 5, {2026-02-01, $60} 3"
showSelectedLots :: [(LotId, Amount, Quantity)] -> String
showSelectedLots = intercalate ", " . map fmt
  where fmt (lid, a, qty) = T.unpack (showLotName (lotIdToCb lid a)) ++ " " ++ show qty
