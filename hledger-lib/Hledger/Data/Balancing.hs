{-|
Functions for ensuring transactions and journals are balanced.
-}

{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE PackageImports      #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}

module Hledger.Data.Balancing
( -- * BalancingOpts
  BalancingOpts(..)
, HasBalancingOpts(..)
, defbalancingopts
  -- * transaction balancing
, isTransactionBalanced
, balanceSingleTransaction
, balanceTransactionHelper
, transactionBalanceError
  -- * assertion validation
, transactionCheckAssertions
  -- * journal balancing
, journalBalanceTransactions
, journalBalanceTransactionsAndDeferAssertions
  -- * tests
, tests_Balancing
)
where

import Control.Applicative ((<|>))
import Control.Monad (forM, forM_, when, unless)
import Control.Monad.Except (ExceptT(..), runExceptT, throwError, catchError)
import Control.Monad.Reader as R (ReaderT, reader, runReaderT, ask, asks)
import Control.Monad.ST (ST, runST)
import Control.Monad.Trans.Class (lift)
import Data.Array.ST (STArray, getElems, newListArray, writeArray)
import Data.Bifunctor (second)
import Data.Foldable (asum)
import Data.Function ((&))
import Data.Functor ((<&>), void)
import Data.HashTable.Class qualified as H (toList)
import Data.HashTable.ST.Cuckoo qualified as H
import Data.List (partition, sortOn, intercalate)
import Data.List.Extra (nubSort)
import Data.Maybe (fromJust, fromMaybe, isJust, isNothing, mapMaybe)
import Data.STRef (STRef, newSTRef, readSTRef, modifySTRef')
import Data.Set qualified as S
import Data.Text qualified as T
import Data.Time.Calendar (addDays, fromGregorian)
import Data.Map qualified as M
import Safe (headErr)
import Text.Printf (printf)

import Hledger.Data.Types
import Hledger.Data.AccountName (accountNameType, isAccountNamePrefixOf)
import Hledger.Data.Amount
import Hledger.Data.Journal
import Hledger.Data.Lots (isGainPosting, lotBaseAccount, transactionAutoSplitFeeOutflows, transactionTagGainPostings)
import Hledger.Data.Posting
import Hledger.Data.Transaction
import Hledger.Data.Errors
import Hledger.Utils


data BalancingOpts = BalancingOpts
  { ignore_assertions_     :: Bool  -- ^ should failing balance assertions be ignored ?
  , infer_balancing_costs_ :: Bool  -- ^ Are we permitted to infer missing costs to balance transactions ?
                                    --   Distinct from InputOpts{infer_costs_}.
  , commodity_styles_      :: Maybe (M.Map CommoditySymbol AmountStyle)  -- ^ commodity display styles
  , txn_balancing_         :: TransactionBalancingPrecision
  , account_types_         :: M.Map AccountName AccountType  -- ^ account type map, passed through for any balancing helpers that need it
  , lotful_commodities_    :: S.Set CommoditySymbol  -- ^ commodities declared lotful, used to guide balancing cost inference (when lots are enabled)
  , account_lots_tags_     :: M.Map AccountName T.Text  -- ^ declared lots: tag values by account, used to detect lots: NONE opt-outs (when lots are enabled)
  , lenient_lots_          :: Bool  -- ^ with --ignore-lots: relax the lot quantity mismatch veto, inferring a balancing conversion cost anyway
  , verbose_balancing_tags_        :: Bool  -- ^ should tags added by balancing helpers (eg lot fee splits) also be made visible in comments ?
  } deriving (Eq, Ord, Show)

defbalancingopts :: BalancingOpts
defbalancingopts = BalancingOpts
  { ignore_assertions_     = False
  , infer_balancing_costs_ = True
  , commodity_styles_      = Nothing
  , txn_balancing_         = TBPExact
  , account_types_         = M.empty
  , lotful_commodities_    = S.empty
  , account_lots_tags_     = M.empty
  , lenient_lots_          = False
  , verbose_balancing_tags_        = False
  }

-- | Check that this transaction would appear balanced to a human when displayed.
-- On success, returns the empty list, otherwise one or more error messages.
--
-- In more detail:
-- For the real postings, and separately for the balanced virtual postings:
--
-- 1. Convert amounts to cost where possible
--
-- 2. When there are two or more non-zero amounts
--    (appearing non-zero when displayed, using the given display styles if provided),
--    are they a mix of positives and negatives ?
--    This is checked separately to give a clearer error message.
--    (Best effort; could be confused by postings with multicommodity amounts.)
--
-- 3. Does the amounts' sum appear non-zero when displayed ?
--    (using the given display styles if provided)
--
transactionCheckBalanced :: BalancingOpts -> Transaction -> [String]
transactionCheckBalanced BalancingOpts{commodity_styles_=_mglobalstyles, txn_balancing_, lotful_commodities_, lenient_lots_} t = errs
  where
    -- get real and balanced virtual postings, to be checked separately
    (rps, bvps) = foldr partitionPosting ([], []) $ tpostings t
      where
        partitionPosting p ~(l, r) = case preal p of
            RealPosting            -> (p:l, r)
            BalancedVirtualPosting -> (l, p:r)
            VirtualPosting         -> (l, r)

    -- convert a posting's amount to cost,
    -- unless it has been marked as a redundant cost (equivalent to some nearby equity conversion postings),
    -- in which case ignore it;
    -- or it is a disposal's realised gain posting, which is set aside: a disposal
    -- balances at cost basis, which is equivalent to its non-gain postings balancing
    -- at transacted cost (see Hledger.Data.Lots.transactionTagGainPostings).
    postingBalancingAmount p
      | costPostingTagName `elem` map fst (ptags p) = mixedAmountStripCosts $ pamount p
      | isGainPosting p                            = nullmixedamt
      | otherwise                                   = mixedAmountCost $ pamount p

    lookszero = case txn_balancing_ of
      TBPOld    -> lookszeroatglobaldisplayprecision
      TBPExact  -> lookszeroatlocaltransactionprecision

    lookszeroatlocaltransactionprecision = mixedAmountLooksZero . styleAmounts (transactionCommodityStylesWith HardRounding t)
    lookszeroatglobaldisplayprecision    = mixedAmountLooksZero . maybe id styleAmounts _mglobalstyles

    -- check that the sum looks like zero
    (rsumcost,  bvsumcost)  = (foldMap postingBalancingAmount rps, foldMap postingBalancingAmount bvps)
    (rsumamts,  bvsumamts)  = (map postingBalancingAmount (nongain rps), map postingBalancingAmount (nongain bvps))
    nongain = filter (not . isGainPosting)
    gainnote ps = if any isGainPosting ps then "  (excluding gain postings)" else ""
    (rsumok,    bvsumok)    = (lookszero rsumcost, lookszero bvsumcost)
    (rsumokold, bvsumokold) = (lookszeroatglobaldisplayprecision rsumcost, lookszeroatglobaldisplayprecision bvsumcost)

    -- when there's multiple non-zeros, check they do not all have the same sign
    (rsignsok, bvsignsok)   = (signsOk rps, signsOk bvps)
      where
        signsOk ps = length nonzeros < 2 || length nonzerosigns > 1
          where
            nonzeros = filter (not.lookszero) $ map postingBalancingAmount ps
            nonzerosigns = nubSort $ mapMaybe isNegativeMixedAmount nonzeros

    -- Generate error messages if any. Show amounts with their original precisions.
    errs = filter (not.null) [rmsg, bvmsg]
      where
        showamt =
          showMixedAmountWith oneLineNoCostFmt{displayZeroCommodity=True} .
          mixedAmountSetFullPrecisionUpTo Nothing .
          mixedAmountSetFullPrecision
        rmsg
          | rsumok        = ""
          | not rsignsok  = "The real postings all have the same sign."
          | otherwise     = "The real postings' sum should be 0 but is "
              ++ showamt rsumcost
              ++ "\n  " ++ intercalate "  +  " (map showamt rsumamts) ++ "  =  " ++ showamt rsumcost ++ gainnote rps
              ++ (if rsumokold then oldbalancingmsg else "")
              ++ lotmismatchmsg rps
        bvmsg
          | bvsumok       = ""
          | not bvsignsok = "The balanced virtual postings all have the same sign."
          | otherwise     = "The balanced virtual postings' sum should be 0 but is: "
              ++ showamt bvsumcost
              ++ "\n  " ++ intercalate " + " (map showamt bvsumamts) ++ " = " ++ showamt bvsumcost ++ gainnote bvps
              ++ (if bvsumokold then oldbalancingmsg else "")
              ++ lotmismatchmsg bvps
        -- When a balancing conversion cost was not inferred because of a
        -- lot quantity mismatch (see lotMismatchCommodities), explain that,
        -- since a user unaware of lot processing might expect this entry
        -- to balance by inference.
        lotmismatchmsg ps = case map T.unpack $ lotMismatchCommodities lotful_commodities_ ps of
          [] -> ""
          cs -> unlines $ [
             "\nNote, " ++ intercalate ", " cs ++ " is a lot-tracked commodity being transferred between accounts,"
            ,"so no balancing conversion cost was inferred; its quantities are expected"
            ,"to add up. If the difference is a fee, you can either"
            ,"- record the fee expense in the lot-tracked commodity, with posting(s)"
            ,"  adding up to the missing quantity"
            ,"- or split the sending posting into a transfer part and fee part(s)"
            ,"  matching the fee expense(s)."
            ]
            ++ ["(With --ignore-lots, a balancing conversion cost is inferred instead.)" | not lenient_lots_]
        oldbalancingmsg = unlines [
          -- -------------------------------------------------------------------------------
           "\nNote, hledger <1.50 accepted this entry because of the global display precision,"
          ,"but hledger 1.50+ checks more strictly, using the entry's local precision."
          ,"You can use --txn-balancing=old to keep it working, or fix it (recommended);"
          ,"see 'Transaction balancing' in the hledger manual."
          ]

-- | Legacy form of transactionCheckBalanced.
isTransactionBalanced :: BalancingOpts -> Transaction -> Bool
isTransactionBalanced bopts = null . transactionCheckBalanced bopts

-- | Verify that any assertions in this transaction hold 
-- when included in the larger journal.
transactionCheckAssertions :: BalancingOpts -> Journal -> Transaction -> Either String Transaction
transactionCheckAssertions bopts j t =
  if (ignore_assertions_ bopts) then Right t else do
    j' <- journalStyleAmounts j 
    let newtxns = sortOn tdate (jtxns j' ++ [ t ])
    case journalBalanceTransactions bopts j'{jtxns = newtxns} of
      Right _ -> Right t
      Left e -> Left e

-- | Balance this isolated transaction, ensuring that its postings
-- (and its balanced virtual postings) sum to 0,
-- by inferring a missing amount or conversion price(s) if needed.
-- Or if balancing is not possible, because the amounts don't sum to 0 or
-- because there's more than one missing amount, return an error message.
--
-- Note this is not as accurate as @balanceTransactionInJournal@,
-- which considers the whole journal when calculating balance assignments and balance assertions.
balanceSingleTransaction :: BalancingOpts -> Transaction -> Either String Transaction
balanceSingleTransaction bopts = fmap fst . balanceTransactionHelper bopts

-- | Like 'balanceTransactionHelper', but in a lots journal, first try
-- balancing the transaction with its lot fee outflows auto-split
-- ('transactionAutoSplitFeeOutflows'): a lot transfer with a priced fee
-- only balances at cost in split form. If no split applies or the split
-- form doesn't balance, balance the unsplit form as usual (preserving its
-- error message if both fail). Lot classification runs after balancing and
-- will classify the split postings (#2686, #2692).
balanceTransactionHelperMaybeSplittingLotFees :: BalancingOpts -> Transaction -> Either String (Transaction, [(AccountName, MixedAmount)])
balanceTransactionHelperMaybeSplittingLotFees bopts t0
  | S.null lotfulcomms = balanceTransactionHelper bopts t  -- not a lots journal
  | length (tpostings t2) == length (tpostings t) = balanceTransactionHelper bopts t  -- no split applied
  | otherwise = case balanceTransactionHelper bopts t2 of
      r@(Right _) -> r
      Left _      -> balanceTransactionHelper bopts t
  where
    lotfulcomms = lotful_commodities_ bopts
    -- Tag any user-written gain postings in a disposal first, so the balancer
    -- sets them aside. (journalFinalise does this too, but callers balancing a
    -- single entry, like hledger add, rely on it happening here.)
    t = transactionTagGainPostings (not $ lenient_lots_ bopts) (verbose_balancing_tags_ bopts) (accountNameType (account_types_ bopts)) (`S.member` lotfulcomms)
          (accountUsesNoLotsWith (account_lots_tags_ bopts)) t0
    t2 = transactionAutoSplitFeeOutflows (verbose_balancing_tags_ bopts) (accountNameType (account_types_ bopts)) (`S.member` lotfulcomms)
           (accountUsesNoLotsWith (account_lots_tags_ bopts)) t

-- | Helper used by balanceSingleTransaction and balanceTransactionWithBalanceAssignmentAndCheckAssertionsB;
-- use one of those instead.
-- It also returns a list of accounts and amounts that were inferred.
balanceTransactionHelper :: BalancingOpts -> Transaction -> Either String (Transaction, [(AccountName, MixedAmount)])
balanceTransactionHelper bopts t = do
  let lbl = lbl_ "balanceTransactionHelper"
  (t', inferredamtsandaccts) <- t
    & (if infer_balancing_costs_ bopts then transactionInferBalancingCosts (lenient_lots_ bopts) (lotful_commodities_ bopts) else id)
    & dbg9With (lbl "amounts after balancing-cost-inferring".show.map showMixedAmountOneLine.transactionAmounts)
    & transactionInferBalancingAmount (fromMaybe M.empty $ commodity_styles_ bopts) (account_types_ bopts)
    <&> dbg9With (lbl "balancing amounts inferred".show.map (second showMixedAmountOneLine).snd)
  case transactionCheckBalanced bopts t' of
    []   -> Right (txnTieKnot t', inferredamtsandaccts)
    errs -> Left $ transactionBalanceError t' errs'
      where
        ismulticommodity = (length $ transactionCommodities t') > 1
        errs' =
          [ "Automatic commodity conversion is disabled by strict mode or the balanced check."
          | ismulticommodity && not (infer_balancing_costs_ bopts)
          ] ++
          errs
          -- silence hints for now
          -- ++
          -- if ismulticommodity
          -- then
          -- [ "Consider adjusting this entry's amounts, adding missing postings,"
          -- , "or recording conversion price(s) with @, @@ or equity postings." 
          -- ]
          -- else []

transactionCommodities :: Transaction -> S.Set CommoditySymbol
transactionCommodities t = mconcat $ map (maCommodities . pamount) $ tpostings t

-- | Generate a transaction balancing error message, given the transaction
-- and one or more suberror messages.
transactionBalanceError :: Transaction -> [String] -> String
transactionBalanceError t errs = printf "%s:\n%s\n\nThis %stransaction is unbalanced.\n%s"
  (sourcePosPairPretty $ tsourcepos t)
  (textChomp ex)
  (if ismulticommodity then "multi-commodity " else "" :: String)
  (chomp $ unlines errs)
  where
    ismulticommodity = (length $ transactionCommodities t) > 1
    (_f,_l,_mcols,ex) = makeTransactionErrorExcerpt t finderrcols
      where
        finderrcols _ = Nothing
        -- finderrcols t = Just (1, Just w)
        --   where
        --     w = maximumDef 1 $ map T.length $ T.lines $ showTransaction t

-- | Infer up to one missing amount for this transactions's real postings, and
-- likewise for its balanced virtual postings, if needed; or return an error
-- message if we can't. Returns the updated transaction and any inferred posting amounts,
-- with the corresponding accounts, in order).
--
-- We can infer a missing amount when there are multiple postings and exactly
-- one of them is amountless. If the amounts had price(s) the inferred amount
-- have the same price(s), and will be converted to the price commodity.
transactionInferBalancingAmount ::
     M.Map CommoditySymbol AmountStyle -- ^ commodity display styles
  -> M.Map AccountName AccountType     -- ^ account type map (passed through; reserved for future use)
  -> Transaction
  -> Either String (Transaction, [(AccountName, MixedAmount)])
transactionInferBalancingAmount styles _atypes t@Transaction{tpostings=ps}
  | length amountlessrealps > 1
      = Left $ transactionBalanceError t
        ["There can't be more than one real posting with no amount."
        ,"(Remember to put two or more spaces between account and amount.)"]
  | length amountlessbvps > 1
      = Left $ transactionBalanceError t
        ["There can't be more than one balanced virtual posting with no amount."
        ,"(Remember to put two or more spaces between account and amount.)"]
  | otherwise
      = let psandinferredamts = map inferamount ps
            inferredacctsandamts = [(paccount p, amt) | (p, Just amt) <- psandinferredamts]
        in Right (
           t{tpostings=map fst psandinferredamts}
          ,inferredacctsandamts
           -- & dbg9With (lbl "inferred".show.map (showMixedAmountOneLine.snd))
          )
  where
    lbl = lbl_ "transactionInferBalancingAmount"
    -- Gain postings in a disposal are set aside (see transactionCheckBalanced):
    -- they don't contribute to the sum, and an amountless one is not inferred
    -- here (journalAddOrCheckGainPostings fills it in after lot matching).
    (amountfulrealps, amountlessrealps) = partition hasAmount $ filter (not . isGainPosting) (realPostings t)
    realsum = maSum $ map (mixedAmountCost . pamount) amountfulrealps
      -- & dbg9With (lbl "real balancing amount".showMixedAmountOneLine)
    (amountfulbvps, amountlessbvps) = partition hasAmount $ filter (not . isGainPosting) (balancedVirtualPostings t)
    bvsum = maSum $ map (mixedAmountCost . pamount) amountfulbvps

    inferamount :: Posting -> (Posting, Maybe MixedAmount)
    inferamount p | isGainPosting p = (p, Nothing)
    inferamount p =
      let
        minferredamt = case preal p of
          RealPosting            | not (hasAmount p) -> Just realsum
          BalancedVirtualPosting | not (hasAmount p) -> Just bvsum
          VirtualPosting         | not (hasAmount p) -> Just 0
          _                                          -> Nothing
      in
        case minferredamt of
          Nothing -> (p, Nothing)
          Just a  -> (p{pamount=a', poriginal=Just $ originalPosting p}, Just a')
            where
              -- Inferred amounts are converted to cost.
              -- Also ensure the new amount has the standard style for its commodity
              -- (since the main amount styling pass happened before this balancing pass);
              a' = maNegate a
                & mixedAmountCost
                -- Apply global commodity styles for formatting, but keep the precision unchanged.
                -- This inferred amount's precision won't influence local or global precisions.
                & styleAmounts (styles & amountStylesSetRounding NoRounding)
                & dbg9With (lbl "balancing amount styled".showMixedAmountOneLine)

-- | Infer costs for this transaction's posting amounts, if needed to make
-- the postings balance, and if permitted. This is done once for the real
-- postings and again (separately) for the balanced virtual postings. When
-- it's not possible, the transaction is left unchanged.
--
-- The simplest example is a transaction with two postings, each in a
-- different commodity, with no costs specified. In this case we'll add a
-- cost to the first posting such that it can be converted to the commodity
-- of the second posting (with -B), and such that the postings balance.
--
-- In general, we can infer a cost (conversion rate) when the sum of posting amounts
-- contains exactly two different commodities and no explicit costs.  Also
-- all postings are expected to contain an explicit amount (no missing
-- amounts) in a single commodity. Otherwise no cost inferring is attempted.
--
-- The transaction itself could contain more than two commodities, and/or
-- costs, if they cancel out; what matters is that the sum of posting amounts
-- contains exactly two commodities and zero costs.
--
-- There can also be more than two postings in either of the commodities.
--
-- We want to avoid excessive display of digits when the calculated cost is
-- an irrational number, while hopefully also ensuring the displayed numbers
-- make sense if the user does a manual calculation. This is (mostly) achieved
-- in two ways:
--
-- - when there is only one posting in the "from" commodity, a total cost
--   (@@) is used, and all available decimal digits are shown
--
-- - otherwise, a suitable averaged unit cost (@) is applied to the relevant
--   postings, with display precision equal to the summed display precisions
--   of the two commodities being converted between, or 2, whichever is larger.
--
-- (We don't always calculate a good-looking display precision for unit costs
-- when the commodity display precisions are low, eg when a journal doesn't
-- use any decimal places. The minimum of 2 helps make the costs shown by the
-- print command a bit less surprising in this case. Could do better.)
--
transactionInferBalancingCosts :: Bool -> S.Set CommoditySymbol -> Transaction -> Transaction
transactionInferBalancingCosts lenientlots lotfulcomms t@Transaction{tpostings=ps} = t{tpostings=ps'}
  where
    ps' = map (costInferrerFor lenientlots lotfulcomms t BalancedVirtualPosting . costInferrerFor lenientlots lotfulcomms t RealPosting) ps

-- | Does one of these postings make this commodity look lot-related ?
-- True if the commodity appears in a posting amount with a cost basis
-- annotation.
-- (Lot classification runs after balancing, so ptype tags can't be used
-- here; this is a shape check.)
commodityHasLotPosting :: [Posting] -> CommoditySymbol -> Bool
commodityHasLotPosting postings comm = any (\p ->
    any (\a -> acommodity a == comm && isJust (acostbasis a)) (amountsRaw $ pamount p)
  ) postings

-- | Is this commodity lot-related (see commodityHasLotPosting, or declared
-- lotful) and appearing with both signs among these postings (a
-- transfer-like shape) ?
lotRelatedBothSigns :: S.Set CommoditySymbol -> [Posting] -> CommoditySymbol -> Bool
lotRelatedBothSigns lotfulcomms postings c =
  (commodityHasLotPosting postings c || c `S.member` lotfulcomms)
  && any (\x -> acommodity x == c && aquantity x > 0) pamounts
  && any (\x -> acommodity x == c && aquantity x < 0) pamounts
  where pamounts = concatMap (amountsRaw . pamount) postings

-- | The lot-related commodities among these postings (of one realness)
-- whose quantities look mismatched: the commodity appears with both signs
-- (a transfer-like shape), yet its residual is nonzero and not exactly one
-- posting's amount. Balancing cost inference is declined for such entries
-- (see costInferrerFor): an inferred cost would attach to both sides, mask
-- the imbalance (eg a fee deducted in kind but recorded in cash), and
-- surface later as a confusing lot error; the balancedness check reports
-- it better, with a note (see transactionCheckBalanced). When the residual
-- equals one posting's amount (a dispose posting alongside a matched
-- transfer pair, eg a same-account reclassify+fee entry), or the commodity
-- appears with one sign only (a bare sale or purchase), a cost is inferred
-- as documented. Returns [] unless the postings' residual is exactly two
-- unpriced opposite-signed commodities (the case where a balancing cost
-- could otherwise be inferred).
lotMismatchCommodities :: S.Set CommoditySymbol -> [Posting] -> [CommoditySymbol]
lotMismatchCommodities lotfulcomms postings =
  case sumamounts of
    [a,b] | all (isNothing . acost) sumamounts
          , signum (aquantity a) /= signum (aquantity b)
          -> map acommodity $ filter lotrelatedMismatch [a,b]
    _ -> []
  where
    sumamounts = amounts $ sumPostings postings
    pamounts = concatMap (amountsRaw . pamount) postings
    lotrelatedMismatch a =
      lotRelatedBothSigns lotfulcomms postings c
      && not (any (\x -> acommodity x == c && aquantity x == aquantity a) pamounts)
      where c = acommodity a

-- | Generate a posting update function which assigns a suitable cost to
-- balance the posting, if and as appropriate for the given transaction and
-- posting realness (real or balanced virtual) (or if we cannot or should not infer
-- costs, leaves the posting unchanged).
costInferrerFor :: Bool -> S.Set CommoditySymbol -> Transaction -> PostingRealness -> (Posting -> Posting)
costInferrerFor lenientlots lotfulcomms t pt = maybe id infercost inferFromAndTo
  where
    lbl = lbl_ "costInferrerFor"
    postings     = filter (\p -> preal p == pt && not (isGainPosting p)) $ tpostings t  -- gain postings are set aside, as in transactionCheckBalanced
    pcommodities = map acommodity $ concatMap (amounts . pamount) postings
    sumamounts   = amounts $ sumPostings postings  -- amounts normalises to one amount per commodity & price

    -- We can infer prices if there are no prices given, exactly two commodities in the normalised
    -- sum of postings in this transaction, these two have opposite signs, and neither looks like
    -- a lot quantity mismatch (see lotMismatchCommodities; this veto is skipped in lenient
    -- --ignore-lots mode, letting such entries load). The amount we are
    -- converting from is normally the first commodity to appear in the ordered list of postings;
    -- but if exactly one of the two commodities looks lot-related (its posting has a cost basis
    -- annotation or an inherited lots: account tag), or failing that, is a declared lotful
    -- commodity (#2686), prefer that one, so the inferred cost is attached to the posting that
    -- needs it for lot tracking. (Lot classification runs after balancing, so tags can't be
    -- used here; these are shape checks.)
    -- If we cannot infer prices, return Nothing.
    inferFromAndTo = case sumamounts of
      [a,b] | noprices, oppositesigns, lenientlots || null (lotMismatchCommodities lotfulcomms postings) ->
        prefer (commodityHasLotPosting postings) <|> prefer (`S.member` lotfulcomms) <|> asum (map orderIfMatches pcommodities)
        where
          prefer hasquality = case (hasquality (acommodity a), hasquality (acommodity b)) of
            (True, False) -> Just (a, b)
            (False, True) -> Just (b, a)
            _             -> Nothing
          noprices      = all (isNothing . acost) sumamounts
          oppositesigns = signum (aquantity a) /= signum (aquantity b)
          orderIfMatches x | x == acommodity a = Just (a,b)
                           | x == acommodity b = Just (b,a)
                           | otherwise         = Nothing
      _ -> Nothing

    -- When the from commodity is lot-related and appears with both signs,
    -- and exactly one single-amount posting equals the residual, attach the
    -- whole cost to that posting only (as a total cost), leaving the others
    -- unpriced: they form matched transfer pairs, which must stay unpriced
    -- for lot classification; only the odd one out (a dispose, eg a fee
    -- disposal alongside a transfer) needs the cost (#2692).
    isTargeted fromamount =
      lotRelatedBothSigns lotfulcomms postings (acommodity fromamount)
      && length residualPostings == 1
      where
        residualPostings =
          [ () | q <- postings, [a] <- [amounts (pamount q)]
               , acommodity a == acommodity fromamount, aquantity a == aquantity fromamount ]

    -- For each posting, if the posting type matches, there is only a single amount in the posting,
    -- and the commodity of the amount matches the amount we're converting from
    -- (and, in the targeted case above, its quantity is the whole residual),
    -- then set its cost based on the ratio between fromamount and toamount.
    infercost (fromamount, toamount) p
        | [a] <- amounts (pamount p), preal p == pt, acommodity a == acommodity fromamount
        , not (isTargeted fromamount) || aquantity a == aquantity fromamount
            = p{ pamount   = mixedAmount a{acost=Just conversionprice}
                  & dbg9With (lbl "inferred cost".showMixedAmountOneLine)
               , poriginal = Just $ originalPosting p }
        | otherwise = p
      where
        -- In the targeted case, or if only one Amount in the posting list matches fromamount,
        -- we can use TotalCost.
        -- Otherwise divide the conversion equally among the Amounts by using a unit price.
        conversionprice
          | isTargeted fromamount = TotalCost $ negate toamount
          | otherwise = case filter (== acommodity fromamount) pcommodities of
              [_] -> TotalCost $ negate toamount
              _   -> UnitCost  $ negate unitcost `withPrecision` unitprecision

        unitcost     = aquantity fromamount `divideAmount` toamount
        unitprecision = case (asprecision $ astyle fromamount, asprecision $ astyle toamount) of
            (Precision a, Precision b) -> Precision . max 2 $ saturatedAdd a b
            _                          -> NaturalPrecision
        saturatedAdd a b = if maxBound - a < b then maxBound else a + b


-- "Transaction balancing", including: inferring missing amounts,
-- applying balance assignments, checking transaction balancedness,
-- checking balance assertions, respecting posting dates. These things
-- are all interdependent.
-- WARN tricky algorithm and code ahead. 
--
-- Code overview as of 20190219, this could/should be simplified/documented more:
--  parseAndFinaliseJournal['] (Cli/Utils.hs), journalAddForecast (Common.hs), journalAddBudgetGoalTransactions (BudgetReport.hs), tests (BalanceReport.hs)
--   journalBalanceTransactions
--    runST
--     runExceptT
--      balanceSingleTransaction (Transaction.hs)
--       balanceTransactionHelper
--      runReaderT
--       balanceTransactionAndCheckAssertionsB
--        addAmountAndCheckAssertionB
--        addOrAssignAmountAndCheckAssertionB
--        balanceTransactionHelper (Transaction.hs)
--  uiCheckBalanceAssertions d ui@UIState{aopts=UIOpts{cliopts_=copts}, ajournal=j} (ErrorScreen.hs)
--   journalCheckBalanceAssertions
--    journalBalanceTransactions
--  transactionWizard, postingsBalanced (Add.hs), tests (Transaction.hs)
--   balanceSingleTransaction (Transaction.hs)  XXX hledger add won't allow balance assignments + missing amount ?

-- | Monad used for statefully balancing/amount-inferring/assertion-checking
-- a sequence of transactions.
-- Perhaps can be simplified, or would a different ordering of layers make sense ?
-- If you see a way, let us know.
type Balancing s = ReaderT (BalancingState s) (ExceptT String (ST s))

-- | Whether and how to check balance assertions while balancing:
-- not at all; erroring at the first failure; or checking but deferring
-- a failure - recording the first one in the given mutable slot and
-- continuing, so it can be reported later
-- (see journalBalanceTransactionsAndDeferAssertions).
data AssertionsMode s
  = DontCheckAssertions
  | CheckAssertions
  | DeferAssertions (STRef s (Maybe String))

-- | The state used while balancing a sequence of transactions.
data BalancingState s = BalancingState {
   -- read only
   bsStyles       :: Maybe (M.Map CommoditySymbol AmountStyle)  -- ^ commodity display styles
  ,bsUnassignable :: S.Set AccountName                          -- ^ accounts where balance assignments may not be used (because of auto posting rules)
  ,bsAssrt        :: AssertionsMode s                           -- ^ whether/how to check balance assertions
  ,bsAccountTypes :: M.Map AccountName AccountType              -- ^ account type map (used when splitting lot fee outflows)
  ,bsLotfulCommodities :: S.Set CommoditySymbol                 -- ^ commodities declared lotful (for guiding balancing cost inference)
  ,bsVerboseTags  :: Bool                                       -- ^ make tags added by balancing helpers (eg lot fee splits) visible in comments ?
   -- mutable
  ,bsBalances     :: H.HashTable s AccountName MixedAmount      -- ^ running account balances, initially empty
  ,bsTransactions :: STArray s Integer Transaction              -- ^ a mutable array of the transactions being balanced
    -- (for efficiency ? journalBalanceTransactions says: not strictly necessary but avoids a sort at the end I think)
  }

-- | Access the current balancing state, and possibly modify the mutable bits,
-- lifting through the Except and Reader layers into the Balancing monad.
withRunningBalance :: (BalancingState s -> ST s a) -> Balancing s a
withRunningBalance f = ask >>= lift . lift . f

-- | Get this account's current exclusive running balance.
getRunningBalanceB :: AccountName -> Balancing s MixedAmount
getRunningBalanceB acc = withRunningBalance $ \BalancingState{bsBalances} -> do
  fromMaybe nullmixedamt <$> H.lookup bsBalances acc

-- | Add this amount to this account's exclusive running balance.
-- Returns the new running balance.
addToRunningBalanceB :: AccountName -> MixedAmount -> Balancing s MixedAmount
addToRunningBalanceB acc amt = withRunningBalance $ \BalancingState{bsBalances} -> do
  old <- fromMaybe nullmixedamt <$> H.lookup bsBalances acc
  let new = maPlus old amt
  H.insert bsBalances acc new
  return new

-- | Set this account's exclusive running balance to this amount.
-- Returns the change in exclusive running balance.
setRunningBalanceB :: AccountName -> MixedAmount -> Balancing s MixedAmount
setRunningBalanceB acc amt = withRunningBalance $ \BalancingState{bsBalances} -> do
  old <- fromMaybe nullmixedamt <$> H.lookup bsBalances acc
  H.insert bsBalances acc amt
  return $ maMinus amt old

-- | Set this account's exclusive running balance to whatever amount
-- makes its *inclusive* running balance (the sum of exclusive running
-- balances of this account and any subaccounts) be the given amount.
-- Returns the change in exclusive running balance.
setInclusiveRunningBalanceB :: AccountName -> MixedAmount -> Balancing s MixedAmount
setInclusiveRunningBalanceB acc newibal = withRunningBalance $ \BalancingState{bsBalances} -> do
  oldebal  <- fromMaybe nullmixedamt <$> H.lookup bsBalances acc
  allebals <- H.toList bsBalances
  let subsibal =  -- sum of any subaccounts' running balances
        maSum . map snd $ filter ((acc `isAccountNamePrefixOf`).fst) allebals
  let newebal = maMinus newibal subsibal
  H.insert bsBalances acc newebal
  return $ maMinus newebal oldebal

-- | Update (overwrite) this transaction in the balancing state.
updateTransactionB :: Transaction -> Balancing s ()
updateTransactionB t = withRunningBalance $ \BalancingState{bsTransactions}  ->
  void $ writeArray bsTransactions (tindex t) t

-- | Infer any missing amounts and/or conversion costs
-- (as needed to balance transactions and satisfy balance assignments);
-- and check that all transactions are balanced;
-- and (optional) check that all balance assertions pass.
-- Or, return an error message (just the first error encountered).
--
-- Assumes journalStyleAmounts has been called, since amount styles
-- affect transaction balancing.
--
-- This does multiple things at once because amount inferring, balance
-- assignments, balance assertions and posting dates are interdependent.
--
journalBalanceTransactions :: BalancingOpts -> Journal -> Either String Journal
journalBalanceTransactions bopts j = fst <$> journalBalanceTransactionsHelper False bopts j

-- | Like journalBalanceTransactions, but instead of erroring at the first
-- failed balance assertion, keep going and also return the first assertion
-- failure's error message, if any. This lets callers (journalFinalise) run
-- further checks, eg the lot stages, and report their errors first.
journalBalanceTransactionsAndDeferAssertions :: BalancingOpts -> Journal -> Either String (Journal, Maybe String)
journalBalanceTransactionsAndDeferAssertions = journalBalanceTransactionsHelper True

journalBalanceTransactionsHelper :: Bool -> BalancingOpts -> Journal -> Either String (Journal, Maybe String)
journalBalanceTransactionsHelper deferassertions bopts' j' =
  let
    -- ensure transactions are numbered, so we can store them by number
    j@Journal{jtxns=ts} = journalNumberTransactions j'
    -- display precisions used in balanced checking
    styles = Just $
      -- Use all the specified commodity display precisions, with hard rounding, when checking txn balancedness.
      -- XXX Problem, those precisions will also be used when inferring balancing amounts;
      -- it would be better to give those the precision of the amount they are balancing.
      journalCommodityStylesWith HardRounding
      j
    bopts = bopts'{commodity_styles_=styles}
      -- XXX ^ The commodity directive styles and default style and inferred styles
      -- are merged into the command line styles in commodity_styles_ - why ?
      -- Mainly for the precisions, used during amount and cost inference and balanced checking ?
    -- balance assignments are not allowed on accounts affected by auto postings
    autopostingaccts = S.fromList . map (paccount . tmprPosting) . concatMap tmpostingrules $ jtxnmodifiers j
  in
    -- Store the transactions in a mutable array, which we'll update as we balance them.
    -- Not strictly necessary but avoids a sort at the end I think.
    runST $ do
      balancedtxns <- newListArray (1, toInteger $ length ts) ts
      -- Holds the first deferred balance assertion failure, if any.
      massertionerr <- newSTRef Nothing
      let assertionsmode
            | ignore_assertions_ bopts = DontCheckAssertions
            | deferassertions          = DeferAssertions massertionerr
            | otherwise                = CheckAssertions

      -- Process all transactions, or short-circuit with an error.
      runExceptT $ do

        -- Two passes are required:
        -- 1. Step through the transactions, balancing the ones which don't have balance assignments,
        -- postponing those which do until later. The balanced ones are split into their postings,
        -- keeping these and the not-yet-balanced transactions in the same relative order.
        psandts :: [Either Posting Transaction] <- fmap concat $ forM ts $ \case
          t | null $ assignmentPostings t -> case fst <$> balanceTransactionHelperMaybeSplittingLotFees bopts t of
              Left  e  -> throwError e
              Right t' -> do
                lift $ writeArray balancedtxns (tindex t') t'
                return $ map Left $ tpostings t'
          t -> return [Right t]

        -- 2. Step through these items in date order (and preserved same-day order),
        -- keeping running balances for all accounts.
        runningbals <- lift $ H.newSized (length $ journalAccountNamesUsed j)
        flip runReaderT (BalancingState styles autopostingaccts assertionsmode (account_types_ bopts) (lotful_commodities_ bopts) (verbose_balancing_tags_ bopts) runningbals balancedtxns) $ do
          -- On encountering any not-yet-balanced transaction with a balance assignment,
          -- enact the balance assignment then finish balancing the transaction.
          -- And, check any balance assertions encountered along the way.
          void $ mapM' balanceTransactionAndCheckAssertionsB $ sortOn (either postingDate tdate) psandts

        -- Return the now fully-balanced and checked transactions,
        -- and any deferred balance assertion failure.
        ts' <- lift $ getElems balancedtxns
        merr <- lift $ readSTRef massertionerr
        return (j{jtxns=ts'}, merr)

-- Before #2039: "Costs are removed, which helps eg assertions.test: 15. Mix different commodities and assignments."

-- | This function is called statefully on each of a date-ordered sequence of
-- 1. fully explicit postings from already-balanced transactions and
-- 2. not-yet-balanced transactions containing balance assignments.
-- It executes balance assignments and finishes balancing the transactions,
-- and checks balance assertions on each posting as it goes.
-- An error will be thrown if a transaction can't be balanced
-- or if an illegal balance assignment is found (cf checkIllegalBalanceAssignment).
-- This stores the balanced transactions in case 2 but not in case 1.
balanceTransactionAndCheckAssertionsB :: Either Posting Transaction -> Balancing s ()
balanceTransactionAndCheckAssertionsB (Left p@Posting{}) =
  -- Update the account's running balance and check the balance assertion if any.
  -- Cost is ignored when checking balance assertions currently.
  void $ addAmountAndCheckAssertionB $ postingStripCosts p
balanceTransactionAndCheckAssertionsB (Right t@Transaction{tpostings=ps}) = do
  -- make sure we can handle the balance assignments
  mapM_ checkIllegalBalanceAssignmentB ps
  -- for each posting, in date order (though without disturbing their display order),
  -- 1. infer its amount from the balance assignment if applicable,
  -- 2. update the account's running balance, and
  -- 3. check the balance assertion if any.
  ps' <- ps
    & zip [1..]                 -- attach original positions
    & sortOn (postingDate.snd)  -- sort by date
    & mapM addOrAssignAmountAndCheckAssertionB  -- infer amount, check assertion on each one
    <&> sortOn fst              -- restore original order
    <&> map snd                 -- discard positions

  -- infer any remaining missing amounts, and make sure the transaction is now fully balanced
  styles <- R.reader bsStyles
  atypes <- R.reader bsAccountTypes
  lotfulcomms <- R.reader bsLotfulCommodities
  verbosetags <- R.reader bsVerboseTags
  let bopts1 = defbalancingopts{commodity_styles_=styles, account_types_=atypes, lotful_commodities_=lotfulcomms, verbose_balancing_tags_=verbosetags}
      t1 = t{tpostings=ps'}
      -- The transaction may be a lot transfer with a fee (whose outflow amount
      -- possibly was only just inferred from a balance assignment): a priced
      -- fee's entry only balances in split form, and any elided posting must
      -- infer the post-split residual (rather than wrongly absorbing the fee's
      -- cost value). (#2686)
      balanceres = balanceTransactionHelperMaybeSplittingLotFees bopts1 t1
  case balanceres of
    Left err -> throwError err
    Right (t', inferredacctsandamts) -> do
      -- for each amount just inferred, update the running balance
      mapM_ (uncurry addToRunningBalanceB) inferredacctsandamts
      -- and save the balanced transaction.
      updateTransactionB t'

type NumberedPosting = (Integer, Posting)

-- | If this posting has an explicit amount, add it to the account's running balance.
-- If it has a missing amount and a balance assignment, infer the amount from, and
-- reset the running balance to, the assigned balance.
-- If it has a missing amount and no balance assignment, leave it for later.
-- Then test the balance assertion if any.
addOrAssignAmountAndCheckAssertionB :: NumberedPosting -> Balancing s NumberedPosting
addOrAssignAmountAndCheckAssertionB (i,p@Posting{paccount=acc, pamount=amt, pbalanceassertion=mba})
  -- an explicit posting amount
  | hasAmount p = do
      newbal <- addToRunningBalanceB acc amt
      checkOrDeferBalanceAssertionB p newbal
      return (i,p)

  -- no explicit posting amount, but there is a balance assignment
  | Just BalanceAssertion{baamount,batotal,bainclusive} <- mba = do
      newbal <- if batotal
                   -- a total balance assignment (==, all commodities)
                   then return $ mixedAmount baamount
                   -- a partial balance assignment (=, one commodity)
                   else do
                     oldbalothercommodities <- filterMixedAmount ((acommodity baamount /=) . acommodity) <$> getRunningBalanceB acc
                     return $ maAddAmount oldbalothercommodities baamount
      diff <- (if bainclusive then setInclusiveRunningBalanceB else setRunningBalanceB) acc newbal
      let p' = p{pamount=filterMixedAmount (not . amountIsZero) diff, poriginal=Just $ originalPosting p}
      checkOrDeferBalanceAssertionB p' newbal
      return (i,p')

  -- no explicit posting amount, no balance assignment
  | otherwise = return (i,p)

-- | Add the posting's amount to its account's running balance, and
-- optionally check the posting's balance assertion if any.
-- The posting is expected to have an explicit amount (otherwise this does nothing).
-- Adding and checking balance assertions are tightly paired because we
-- need to see the balance as it stands after each individual posting.
addAmountAndCheckAssertionB :: Posting -> Balancing s Posting
addAmountAndCheckAssertionB p | hasAmount p = do
  newbal <- addToRunningBalanceB (paccount p) $ pamount p
  checkOrDeferBalanceAssertionB p newbal
  return p
addAmountAndCheckAssertionB p = return p

-- | Check the posting's balance assertion (if any) against the given balance,
-- per the current assertions mode: not at all; erroring immediately on a
-- failure; or recording the first failure and continuing.
checkOrDeferBalanceAssertionB :: Posting -> MixedAmount -> Balancing s ()
checkOrDeferBalanceAssertionB p newbal = R.reader bsAssrt >>= \case
  DontCheckAssertions -> return ()
  CheckAssertions     -> checkBalanceAssertionB p newbal
  DeferAssertions ref -> checkBalanceAssertionB p newbal `catchError` \e ->
    lift . lift $ modifySTRef' ref (<|> Just e)

-- | Check a posting's balance assertion against the given actual balance, and
-- return an error if the assertion is not satisfied.
-- If the assertion is partial, unasserted commodities in the actual balance
-- are ignored; if it is total, they will cause the assertion to fail.
checkBalanceAssertionB :: Posting -> MixedAmount -> Balancing s ()
checkBalanceAssertionB p@Posting{pbalanceassertion=Just (BalanceAssertion{baamount,batotal})} actualbal =
  forM_ (baamount : otheramts) $ \amt -> checkBalanceAssertionOneCommodityB p amt actualbal
  where
    assertedcomm = acommodity baamount
    otheramts | batotal   = map (\a -> a{aquantity=0}) . amountsRaw
                          $ filterMixedAmount ((/=assertedcomm).acommodity) actualbal
              | otherwise = []
checkBalanceAssertionB _ _ = return ()

-- | Does this (single commodity) expected balance match the amount of that
-- commodity in the given (multicommodity) actual balance, ignoring costs ?
-- If not, returns a balance assertion failure message based on the provided posting.
-- To match, the amounts must be exactly equal (display precision is ignored here).
-- If the assertion is inclusive, the expected amount is compared with the account's
-- subaccount-inclusive balance; otherwise, with the subaccount-exclusive balance.
checkBalanceAssertionOneCommodityB :: Posting -> Amount -> MixedAmount -> Balancing s ()
checkBalanceAssertionOneCommodityB p@Posting{paccount=assertedacct} assertedcommbal actualbal = do
  let isinclusive = maybe False bainclusive $ pbalanceassertion p
  let istotal     = maybe False batotal     $ pbalanceassertion p
  -- mstyles <- R.reader bsStyles
  -- let styled = maybe id styleAmounts mstyles
  actualbal' <-
    if isinclusive
    then
      -- sum the running balances of this account and any of its subaccounts seen so far
      withRunningBalance $ \BalancingState{bsBalances} ->
        H.foldM
          (\ibal (acc, amt) -> return $
            if assertedacct==acc || assertedacct `isAccountNamePrefixOf` acc then maPlus ibal amt else ibal)
          nullmixedamt
          bsBalances
    else return actualbal
  let
    assertedcomm = acommodity assertedcommbal

    -- The asserted single-commodity balance, without cost
    assertedcommbalcostless = amountStripCost assertedcommbal

    -- The balance in this commodity, from the current multi-commodity running balance at this point.
    -- This is unnormalised, and could include one or more different costs.
    actualcommbal           = filterMixedAmountByCommodity assertedcomm $ actualbal'

    -- The above balance without costs, as a single Amount (Amount's + discards costs).
    actualcommbalcostless   = sum $ amountsRaw actualcommbal

    -- test the assertion
    pass =
      aquantity assertedcommbalcostless
      ==
      aquantity actualcommbalcostless

    errmsg = chomp $ printf (unlines
      [ "%s:",
        "%s\n",
        "Balance assertion failed in %s",
        "%s at this point, %s, ignoring costs,",
        "the asserted balance is:        %s",
        "but the calculated balance is:  %s",
        "(difference: %s)",
        "To troubleshoot, check this account's running balance with assertions disabled, eg:",
        "hledger reg -E --ignore-assertions '%s'%s%s -e %s"
      ])

      (sourcePosPretty pos)  -- position
      (textChomp ex)  -- journal excerpt
      acct  -- asserted account
      (if istotal then "Across all commodities" else "In commodity " <> assertedcommstr)  -- asserted commodity or all commodities ?
      (if isinclusive then "including subaccounts" else "excluding subaccounts" :: String)  -- inclusive or exclusive balance asserted ?
      (pad assertedstr  -- asserted amount, without cost
        <> if debugLevel >= 2 then " (with cost:  " <> T.pack (showAmountWith fmt assertedcommbal) <> ")" else ""
      )
      (pad actualstr    -- actual amount, without cost
        <> if debugLevel >= 2 then " (with costs: " <> T.pack (showMixedAmountWith fmt actualcommbal) <> ")" else ""
      )
      diffstr  -- their difference
      (show $ addDays 1 $ postingDate p)  -- exclusive end date just after the assertion's date
      (T.unpack (regexEscape (paccount p)) ++ if isinclusive then "" else "$")  -- query matching the account(s) postings
      (if istotal then "" else (" cur:" ++ quoteForCommandLine (T.unpack (regexEscape (assertedcomm)))))  -- query matching the commodity(ies)
      lotSubHint  -- lot subaccount hint (empty for non-lot accounts)

      where
        acct = T.unpack $ paccount p
        ass = fromJust $ pbalanceassertion p  -- PARTIAL: fromJust won't fail, there is a balance assertion
        pos = baposition ass
        (_,_,_,ex) = makeBalanceAssertionErrorExcerpt p
        assertedcommstr = if T.null assertedcomm then "\"\"" else assertedcomm
        fmt = oneLineFmt{displayZeroCommodity=True}
        (assertedstr, actualstr) =
          showAmountsDistinctly fmt assertedcommbalcostless actualcommbalcostless
        diffstr     = showAmountWith fmt $ assertedcommbalcostless - actualcommbalcostless
        pad = fitText (Just w) Nothing False False . T.pack where w = max (length assertedstr) (length actualstr)
        -- If this is a lot subaccount assertion, remind that balance assertions generally
        -- don't work on lot subaccounts. (#2659)
        lotSubHint
          | isLotSub =
              "\n\nNote '" ++ T.unpack assertedacct ++ "' is a lot subaccount.\n"
              ++ "Balance assertions aren't supported here unless all postings\n"
              ++ "to this lot mention the lot subaccount name explicitly.\n"
              ++ "So it's probably best to avoid using balance assertions on this account.\n"
              ++ "If needed, you could assert the parent account's balance instead."
          | otherwise = ""
          where
            isLotSub = assertedacct /= lotBaseAccount assertedacct

  unless pass $ throwError errmsg
{- XXX
When the posting amount has a cost, the highlight region expands to the full line:

*** Exception: Error: /Users/simon/src/hledger/2024-01-21.j:12:69:
   | 2023-12-31 closing balances
12 |     assets:cash:petty:saved:rent       -4.00 EUR @ 2 UAH == 0.00 EUR
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   |     equity:opening/closing balances                8 UAH

Maybe it's better than the normal region ?

*** Exception: Error: /Users/simon/src/hledger/2024-01-21.j:12:61:
   | 2023-12-31 closing balances
12 |     assets:cash:petty:saved:rent          -4.00 EUR == 0.00 EUR @ 3 UAH
   |                                                     ^^^^^^^^^^^^^^^^^^^
   |     equity:opening/closing balances        4.00 EUR

If changed also check flycheck-hledger, which currently highlights the equals:

    assets:cash:petty:saved:rent                  -4.00 EUR @ 2 UAH == 0.00 EUR @ 3 UAH 
                                                                    --
-}

-- | Throw an error if this posting is trying to do an illegal balance assignment.
checkIllegalBalanceAssignmentB :: Posting -> Balancing s ()
checkIllegalBalanceAssignmentB p = do
  checkBalanceAssignmentPostingDateB p
  checkBalanceAssignmentUnassignableAccountB p

-- XXX these should show position. annotateErrorWithTransaction t ?

-- | Throw an error if this posting is trying to do a balance assignment and
-- has a custom posting date (which makes amount inference too hard/impossible).
checkBalanceAssignmentPostingDateB :: Posting -> Balancing s ()
checkBalanceAssignmentPostingDateB p =
  when (hasBalanceAssignment p && isJust (pdate p)) $
    throwError $ chomp $ unlines [
       "Balance assignments and custom posting dates may not be combined."
      ,""
      ,chomp1 $ T.unpack $ maybe (T.unlines $ showPostingLines p) showTransaction $ ptransaction p
      ,"Balance assignments may not be used on postings with a custom posting date"
      ,"(it makes balancing the journal impossible)."
      ,"Please write the posting amount explicitly (or remove the posting date)."
      ]

-- | Throw an error if this posting is trying to do a balance assignment and
-- the account does not allow balance assignments (eg because it is referenced
-- by an auto posting rule, which might generate additional postings to it).
checkBalanceAssignmentUnassignableAccountB :: Posting -> Balancing s ()
checkBalanceAssignmentUnassignableAccountB p = do
  unassignable <- R.asks bsUnassignable
  when (hasBalanceAssignment p && paccount p `S.member` unassignable) $
    throwError $ chomp $ unlines [
       "Balance assignments and auto postings may not be combined."
      ,""
      ,chomp1 $ T.unpack $ maybe (T.unlines $ showPostingLines p) (showTransaction) $ ptransaction p
      ,"Balance assignments may not be used on accounts affected by auto posting rules"
      ,"(it makes balancing the journal impossible)."
      ,"Please write the posting amount explicitly (or remove the auto posting rule(s))."
      ]

-- lenses

makeHledgerClassyLenses ''BalancingOpts

-- tests

tests_Balancing :: TestTree
tests_Balancing =
  testGroup "Balancing" [

      testCase "transactionInferBalancingAmount" $ do
         (fst <$> transactionInferBalancingAmount M.empty M.empty nulltransaction) @?= Right nulltransaction
         (fst <$> transactionInferBalancingAmount M.empty M.empty nulltransaction{tpostings = ["a" `post` usd (-5), "b" `post` missingamt]}) @?=
           Right nulltransaction{tpostings = ["a" `post` usd (-5), "b" `post` usd 5]}
         (fst <$> transactionInferBalancingAmount M.empty M.empty nulltransaction{tpostings = ["a" `post` usd (-5), "b" `post` (eur 3 @@ usd 4), "c" `post` missingamt]}) @?=
           Right nulltransaction{tpostings = ["a" `post` usd (-5), "b" `post` (eur 3 @@ usd 4), "c" `post` usd 1]}

    , testGroup "balanceSingleTransaction" [
         testCase "detect unbalanced entry, sign error" $
          assertLeft
            (balanceSingleTransaction defbalancingopts
               (Transaction
                  0
                  ""
                  nullsourcepospair
                  (fromGregorian 2007 01 28)
                  Nothing
                  Unmarked
                  ""
                  "test"
                  ""
                  []
                  [posting {paccount = "a", pamount = mixedAmount (usd 1)}, posting {paccount = "b", pamount = mixedAmount (usd 1)}]))
        ,testCase "detect unbalanced entry, multiple missing amounts" $
          assertLeft $
             balanceSingleTransaction defbalancingopts
               (Transaction
                  0
                  ""
                  nullsourcepospair
                  (fromGregorian 2007 01 28)
                  Nothing
                  Unmarked
                  ""
                  "test"
                  ""
                  []
                  [ posting {paccount = "a", pamount = missingmixedamt}
                  , posting {paccount = "b", pamount = missingmixedamt}
                  ])
        ,testCase "one missing amount is inferred" $
          (pamount . last . tpostings <$>
           balanceSingleTransaction defbalancingopts
             (Transaction
                0
                ""
                nullsourcepospair
                (fromGregorian 2007 01 28)
                Nothing
                Unmarked
                ""
                ""
                ""
                []
                [posting {paccount = "a", pamount = mixedAmount (usd 1)}, posting {paccount = "b", pamount = missingmixedamt}])) @?=
          Right (mixedAmount $ usd (-1))
        ,testCase "conversion price is inferred" $
          (pamount . headErr . tpostings <$>  -- PARTIAL headErr succeeds because non-null postings list
           balanceSingleTransaction defbalancingopts
             (Transaction
                0
                ""
                nullsourcepospair
                (fromGregorian 2007 01 28)
                Nothing
                Unmarked
                ""
                ""
                ""
                []
                [ posting {paccount = "a", pamount = mixedAmount (usd 1.35)}
                , posting {paccount = "b", pamount = mixedAmount (eur (-1))}
                ])) @?=
          Right (mixedAmount $ usd 1.35 @@ eur 1)
        ,testCase "balanceSingleTransaction balances based on cost if there are unit prices" $
          assertRight $
          balanceSingleTransaction defbalancingopts
            (Transaction
               0
               ""
               nullsourcepospair
               (fromGregorian 2011 01 01)
               Nothing
               Unmarked
               ""
               ""
               ""
               []
               [ posting {paccount = "a", pamount = mixedAmount $ usd 1 `at` eur 2}
               , posting {paccount = "a", pamount = mixedAmount $ usd (-2) `at` eur 1}
               ])
        ,testCase "balanceSingleTransaction balances based on cost if there are total prices" $
          assertRight $
          balanceSingleTransaction defbalancingopts
            (Transaction
               0
               ""
               nullsourcepospair
               (fromGregorian 2011 01 01)
               Nothing
               Unmarked
               ""
               ""
               ""
               []
               [ posting {paccount = "a", pamount = mixedAmount $ usd 1 @@ eur 1}
               , posting {paccount = "a", pamount = mixedAmount $ usd (-2) @@ eur (-1)}
               ])
        ]
    , testGroup "isTransactionBalanced" [
         testCase "detect balanced" $
          assertBool "" $
          isTransactionBalanced defbalancingopts $
          Transaction
            0
            ""
            nullsourcepospair
            (fromGregorian 2009 01 01)
            Nothing
            Unmarked
            ""
            "a"
            ""
            []
            [ posting {paccount = "b", pamount = mixedAmount (usd 1.00)}
            , posting {paccount = "c", pamount = mixedAmount (usd (-1.00))}
            ]
        ,testCase "detect unbalanced" $
          assertBool "" $
          not $
          isTransactionBalanced defbalancingopts $
          Transaction
            0
            ""
            nullsourcepospair
            (fromGregorian 2009 01 01)
            Nothing
            Unmarked
            ""
            "a"
            ""
            []
            [ posting {paccount = "b", pamount = mixedAmount (usd 1.00)}
            , posting {paccount = "c", pamount = mixedAmount (usd (-1.01))}
            ]
        ,testCase "detect unbalanced, one posting" $
          assertBool "" $
          not $
          isTransactionBalanced defbalancingopts $
          Transaction
            0
            ""
            nullsourcepospair
            (fromGregorian 2009 01 01)
            Nothing
            Unmarked
            ""
            "a"
            ""
            []
            [posting {paccount = "b", pamount = mixedAmount (usd 1.00)}]
        ,testCase "one zero posting is considered balanced for now" $
          assertBool "" $
          isTransactionBalanced defbalancingopts $
          Transaction
            0
            ""
            nullsourcepospair
            (fromGregorian 2009 01 01)
            Nothing
            Unmarked
            ""
            "a"
            ""
            []
            [posting {paccount = "b", pamount = mixedAmount (usd 0)}]
        ,testCase "virtual postings don't need to balance" $
          assertBool "" $
          isTransactionBalanced defbalancingopts $
          Transaction
            0
            ""
            nullsourcepospair
            (fromGregorian 2009 01 01)
            Nothing
            Unmarked
            ""
            "a"
            ""
            []
            [ posting {paccount = "b", pamount = mixedAmount (usd 1.00)}
            , posting {paccount = "c", pamount = mixedAmount (usd (-1.00))}
            , posting {paccount = "d", pamount = mixedAmount (usd 100), preal = VirtualPosting}
            ]
        ,testCase "balanced virtual postings need to balance among themselves" $
          assertBool "" $
          not $
          isTransactionBalanced defbalancingopts $
          Transaction
            0
            ""
            nullsourcepospair
            (fromGregorian 2009 01 01)
            Nothing
            Unmarked
            ""
            "a"
            ""
            []
            [ posting {paccount = "b", pamount = mixedAmount (usd 1.00)}
            , posting {paccount = "c", pamount = mixedAmount (usd (-1.00))}
            , posting {paccount = "d", pamount = mixedAmount (usd 100), preal = BalancedVirtualPosting}
            ]
        ,testCase "balanced virtual postings need to balance among themselves (2)" $
          assertBool "" $
          isTransactionBalanced defbalancingopts $
          Transaction
            0
            ""
            nullsourcepospair
            (fromGregorian 2009 01 01)
            Nothing
            Unmarked
            ""
            "a"
            ""
            []
            [ posting {paccount = "b", pamount = mixedAmount (usd 1.00)}
            , posting {paccount = "c", pamount = mixedAmount (usd (-1.00))}
            , posting {paccount = "d", pamount = mixedAmount (usd 100), preal = BalancedVirtualPosting}
            , posting {paccount = "3", pamount = mixedAmount (usd (-100)), preal = BalancedVirtualPosting}
            ]
        ]

  ,testGroup "journalBalanceTransactions" [

     testCase "missing-amounts" $ do
      let ej = journalBalanceTransactions defbalancingopts $ samplejournalMaybeExplicit False
      assertRight ej
      journalPostings <$> ej @?= Right (journalPostings samplejournal)

    ,testCase "balance-assignment" $ do
      let ej = journalBalanceTransactions defbalancingopts $
            --2019/01/01
            --  (a)            = 1
            nulljournal{ jtxns = [
              transaction (fromGregorian 2019 01 01) [ vpost' "a" missingamt (balassert (num 1)) ]
            ]}
      assertRight ej
      case ej of Right j -> (jtxns j & headErr & tpostings & headErr & pamount & amountsRaw) @?= [num 1]  -- PARTIAL headErrs succeed because non-null txns & postings lists given
                 Left _  -> error' "balance-assignment test: shouldn't happen"

    ,testCase "same-day-1" $ do
      assertRight $ journalBalanceTransactions defbalancingopts $
            --2019/01/01
            --  (a)            = 1
            --2019/01/01
            --  (a)          1 = 2
            nulljournal{ jtxns = [
               transaction (fromGregorian 2019 01 01) [ vpost' "a" missingamt (balassert (num 1)) ]
              ,transaction (fromGregorian 2019 01 01) [ vpost' "a" (num 1)    (balassert (num 2)) ]
            ]}

    ,testCase "same-day-2" $ do
      assertRight $ journalBalanceTransactions defbalancingopts $
            --2019/01/01
            --    (a)                  2 = 2
            --2019/01/01
            --    b                    1
            --    a
            --2019/01/01
            --    a                    0 = 1
            nulljournal{ jtxns = [
               transaction (fromGregorian 2019 01 01) [ vpost' "a" (num 2)    (balassert (num 2)) ]
              ,transaction (fromGregorian 2019 01 01) [
                 post' "b" (num 1)     Nothing
                ,post' "a"  missingamt Nothing
              ]
              ,transaction (fromGregorian 2019 01 01) [ post' "a" (num 0)     (balassert (num 1)) ]
            ]}

    ,testCase "out-of-order" $ do
      assertRight $ journalBalanceTransactions defbalancingopts $
            --2019/1/2
            --  (a)    1 = 2
            --2019/1/1
            --  (a)    1 = 1
            nulljournal{ jtxns = [
               transaction (fromGregorian 2019 01 02) [ vpost' "a" (num 1)    (balassert (num 2)) ]
              ,transaction (fromGregorian 2019 01 01) [ vpost' "a" (num 1)    (balassert (num 1)) ]
            ]}

    ]

    ,testGroup "transactionCheckAssertions" $ [
      testCase "simple assertion on same day" $ do 
        assertRight $ 
          transactionCheckAssertions defbalancingopts nulljournal{ jtxns = [
            transaction (fromGregorian 2025 01 01) [ vpost' "a" (usd 1) Nothing ]
            ] } (transaction (fromGregorian 2025 01 01) [ vpost' "a" (usd 1) (balassert (usd 2)) ])

      ,testCase "inclusive assertions" $ do 
        assertRight $ 
          transactionCheckAssertions defbalancingopts nulljournal{ jtxns = [
            transaction (fromGregorian 2025 01 01) [ vpost' "a:a" (usd 1) Nothing ] 
            ,transaction (fromGregorian 2025 01 02) [ vpost' "a:b" (usd 2) Nothing]
            ,transaction (fromGregorian 2025 01 02) [ vpost' "a:c" (usd 5) Nothing]
            ,transaction (fromGregorian 2025 01 03) [ vpost' "a:d" (eur 10) Nothing]
            ] } (transaction (fromGregorian 2025 01 04) [ vpost' "a" (usd 2) (balassertParInc (usd 10))])

      ,testCase "multicommodity assertion" $ do 
        assertRight $ 
          transactionCheckAssertions defbalancingopts nulljournal{ jtxns = [
            transaction (fromGregorian 2025 01 01) [ vpost' "a" (usd 1) Nothing ] 
            ,transaction (fromGregorian 2025 01 02) [ vpost' "a:b" (eur 2) Nothing ]
            ,transaction (fromGregorian 2025 01 02) [ vpost' "a:c" (usd 5) Nothing ]
            ,transaction (fromGregorian 2025 01 03) [ vpost' "a:b" (eur (-2)) Nothing ]
            ] } (transaction (fromGregorian 2025 01 03) [ vpost' "a" (usd 2) (balassertTotInc (usd 8)) ])
    ]

    ,testGroup "commodityStylesFromAmounts" $ [

      -- Journal similar to the one on #1091:
      -- 2019/09/24
      --     (a)            1,000.00
      -- 
      -- 2019/09/26
      --     (a)             1000,000
      --
      testCase "1091a" $ do
        commodityStylesFromAmounts [
           nullamt{aquantity=1000, astyle=AmountStyle L False Nothing (Just ',') (Precision 3) NoRounding}
          ,nullamt{aquantity=1000, astyle=AmountStyle L False (Just (DigitGroups ',' [3])) (Just '.') (Precision 2) NoRounding}
          ]
         @?=
          -- The commodity style should have period as decimal mark
          -- and comma as digit group mark.
          Right (M.fromList [
            ("", AmountStyle L False (Just (DigitGroups ',' [3])) (Just '.') (Precision 3) NoRounding)
          ])
        -- same journal, entries in reverse order
      ,testCase "1091b" $ do
        commodityStylesFromAmounts [
           nullamt{aquantity=1000, astyle=AmountStyle L False (Just (DigitGroups ',' [3])) (Just '.') (Precision 2) NoRounding}
          ,nullamt{aquantity=1000, astyle=AmountStyle L False Nothing (Just ',') (Precision 3) NoRounding}
          ]
         @?=
          -- The commodity style should have period as decimal mark
          -- and comma as digit group mark.
          Right (M.fromList [
            ("", AmountStyle L False (Just (DigitGroups ',' [3])) (Just '.') (Precision 3) NoRounding)
          ])

     ]

  ]
