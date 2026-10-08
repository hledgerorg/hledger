{-|

A 'Transaction' represents a movement of some commodity(ies) between two
or more accounts. It consists of multiple account 'Posting's which balance
to zero, a date, and optional extras like description, cleared status, and
tags.

-}

{-# LANGUAGE MultiWayIf        #-}
{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}

module Hledger.Data.Transaction
( -- * Transaction
  nulltransaction
, transaction
, txnTieKnot
, txnUntieKnot
  -- * operations
, hasRealPostings
, realPostings
, assignmentPostings
, virtualPostings
, balancedVirtualPostings
, transactionsPostings
, transactionTransformPostings
, transactionApplyValuation
, transactionToCost
, transactionInferEquityPostings
, transactionTagCostsAndEquityAndMaybeInferCosts
, transactionApplyAliases
, transactionMapPostings
, transactionMapPostingAmounts
, transactionAmounts
, transactionCommodityStyles
, transactionCommodityStylesWith
, transactionNegate
, partitionAndCheckConversionPostings
, transactionAddTags
, transactionAddHiddenAndMaybeVisibleTag
  -- * helpers
, TransactionBalancingPrecision(..)
, payeeAndNoteFromDescription
, payeeAndNoteFromDescription'
  -- nonzerobalanceerror
  -- * date operations
, transactionDate2
, transactionDateOrDate2
  -- * transaction description parts
, transactionPayee
, transactionNote
  -- payeeAndNoteFromDescription
  -- * rendering
, showTransaction
, showTransactionWithLayout
, showTransactionOneLineAmounts
, showTransactionOneLine
, showTransactionLineFirstPart
, transactionFile
  -- * transaction errors
, annotateErrorWithTransaction
  -- * tests
, tests_Transaction
) where

import Control.Monad.Trans.State (StateT(..), evalStateT)
import Data.Bifunctor (first, second)
import Data.Foldable (foldlM)
import Data.Maybe (fromMaybe, isJust, isNothing, mapMaybe)
import Data.Semigroup (Endo(..))
import Data.Text (Text)
import Data.Map qualified as M
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Builder qualified as TB
import Data.Time.Calendar (Day, fromGregorian)

import Hledger.Utils
import Hledger.Data.Types
import Hledger.Data.Dates
import Hledger.Data.Posting
import Hledger.Data.Amount
import Hledger.Data.Valuation
import Data.Decimal (normalizeDecimal, decimalPlaces, roundTo)
import Data.Functor ((<&>))
import Data.Function ((&))
import Data.List (union)


-- | How to determine the precision used for checking that transactions are balanced,
-- and so how much imbalance is tolerated (selected by --txn-tolerance). See #2402.
data TransactionBalancingPrecision =
    TBPDisplay
    -- ^ Legacy behaviour, as in hledger <1.50, included to ease upgrades.
    -- use precision inferred from the whole journal, overridable by commodity directive or -c.
    -- Display precision is also transaction balancing precision; increasing it can break journal reading.
    -- Some valid journals are rejected until commodity directives are added.
    -- Larger imbalances can be hidden, and in accounts that are never reconciled, can accumulate over time.
  | TBPEntry
    -- ^ Simpler, more robust behaviour, like Ledger: use precision inferred from the transaction's journal entry.
    -- Display precision and transaction balancing precision are independent; display precision never affects journal reading.
    -- Valid journals from ledger or beancount are accepted without needing commodity directives.
    -- Imbalances smaller than the entry's precision are still tolerated, and can accumulate.

  deriving (Bounded, Enum, Eq, Ord, Read, Show)

instance HasAmounts Transaction where
  styleAmounts styles t = t{tpostings=styleAmounts styles $ tpostings t}

nulltransaction :: Transaction
nulltransaction = Transaction {
                    tindex=0,
                    tsourcepos=nullsourcepospair,
                    tdate=nulldate,
                    tdate2=Nothing,
                    tstatus=Unmarked,
                    tcode="",
                    tdescription="",
                    tcomment="",
                    ttags=[],
                    tpostings=[],
                    tprecedingcomment=""
                  }

-- | Make a simple transaction with the given date and postings.
transaction :: Day -> [Posting] -> Transaction
transaction day ps = txnTieKnot $ nulltransaction{tdate=day, tpostings=ps}

transactionPayee :: Transaction -> Text
transactionPayee = fst . payeeAndNoteFromDescription . tdescription

transactionNote :: Transaction -> Text
transactionNote = snd . payeeAndNoteFromDescription . tdescription

-- | Parse a transaction's description into payee and note (aka narration) fields,
-- assuming a convention of separating these with | (like Beancount).
-- Ie, everything up to the first | is the payee, everything after it is the note.
-- When there's no |, payee == note == description.
payeeAndNoteFromDescription :: Text -> (Text,Text)
payeeAndNoteFromDescription t
  | T.null n = (t, t)
  | otherwise = (T.strip p, T.strip $ T.drop 1 n)
  where
    (p, n) = T.span (/= '|') t

-- | Like payeeAndNoteFromDescription, but if there's no | then payee is empty.
payeeAndNoteFromDescription' :: Text -> (Text,Text)
payeeAndNoteFromDescription' t =
  if isJust $ T.find (=='|') t then payeeAndNoteFromDescription t else ("",t)


{-|
Render a journal transaction as text similar to the style of Ledger's print command.

Adapted from Ledger 2.x and 3.x standard format:

@
yyyy-mm-dd[ *][ CODE] description.........          [  ; comment...............]
    account name 1.....................  ...$amount1[  ; comment...............]
    account name 2.....................  ..$-amount1[  ; comment...............]

pcodewidth    = no limit -- 10          -- mimicking ledger layout.
pdescwidth    = no limit -- 20          -- I don't remember what these mean,
pacctwidth    = 35 minimum, no maximum  -- they were important at the time.
pamtwidth     = 11
pcommentwidth = no limit -- 22
@

The output will be parseable journal syntax.
To facilitate this, postings with explicit multi-commodity amounts
are displayed as multiple similar postings, one per commodity.
(Normally does not happen with this function).
-}
showTransaction :: Transaction -> Text
showTransaction = TL.toStrict . TB.toLazyText . showTransactionHelper False defaultPostingLayout

-- | Like 'showTransaction', but with an explicit posting layout
-- (e.g. to support @print --layout=hledger1@).
showTransactionWithLayout :: PostingLayout -> Transaction -> Text
showTransactionWithLayout layout = TL.toStrict . TB.toLazyText . showTransactionHelper False layout

-- | Like showTransaction, but explicit multi-commodity amounts
-- are shown on one line, comma-separated. In this case the output will
-- not be parseable journal syntax.
showTransactionOneLineAmounts :: Transaction -> Text
showTransactionOneLineAmounts = TL.toStrict . TB.toLazyText . showTransactionHelper True defaultPostingLayout

-- | Show only a transaction's first line: date, status, code, description,
-- and same-line comment, without any comment lines or postings. Used by the transactions command.
-- (Distinct from 'showTransactionOneLineAmounts', which shows the whole transaction
-- but with multi-commodity amounts on one line.)
showTransactionOneLine :: Transaction -> Text
showTransactionOneLine t = transactionFirstLine t <> "\n"

-- | Helper for showTransaction*.
-- Any preceding comment lines (tprecedingcomment, already newline-terminated) are shown first.
showTransactionHelper :: Bool -> PostingLayout -> Transaction -> TB.Builder
showTransactionHelper onelineamounts layout t =
      TB.fromText (tprecedingcomment t)
    <> TB.fromText (transactionFirstLine t) <> newline
    <> foldMap ((<> newline) . TB.fromText) newlinecomments
    <> foldMap ((<> newline) . TB.fromText) (postingsAsLinesWithLayout defaultFmt onelineamounts layout $ tpostings t)
    <> newline
  where
    newlinecomments = drop 1 $ renderCommentLines (tcomment t)
    newline = TB.singleton '\n'

-- | Render a transaction's first line: date, status, code, description, and
-- same-line comment (the part after @;@ on the date line), with trailing whitespace stripped.
transactionFirstLine :: Transaction -> Text
transactionFirstLine t = T.stripEnd $ showTransactionLineFirstPart t <> T.concat [desc, samelinecomment]
  where
    desc = if T.null d then "" else " " <> d where d = tdescription t
    samelinecomment = case renderCommentLines (tcomment t) of []  -> ""
                                                              c:_ -> c

-- Useful when rendering error messages.
showTransactionLineFirstPart t = T.concat [date, status, code]
  where
    date = showDate (tdate t) <> maybe "" (("="<>) . showDate) (tdate2 t)
    status | tstatus t == Cleared = " *"
           | tstatus t == Pending = " !"
           | otherwise            = ""
    code = if T.null (tcode t) then "" else wrap " (" ")" $ tcode t

hasRealPostings :: Transaction -> Bool
hasRealPostings = not . null . realPostings

realPostings :: Transaction -> [Posting]
realPostings = filter isReal . tpostings

assignmentPostings :: Transaction -> [Posting]
assignmentPostings = filter hasBalanceAssignment . tpostings

virtualPostings :: Transaction -> [Posting]
virtualPostings = filter isVirtual . tpostings

balancedVirtualPostings :: Transaction -> [Posting]
balancedVirtualPostings = filter isBalancedVirtual . tpostings

transactionsPostings :: [Transaction] -> [Posting]
transactionsPostings = concatMap tpostings

-- Get a transaction's secondary date, or the primary date if there is none.
transactionDate2 :: Transaction -> Day
transactionDate2 t = fromMaybe (tdate t) $ tdate2 t

-- Get a transaction's primary or secondary date, as specified.
transactionDateOrDate2 :: WhichDate -> Transaction -> Day
transactionDateOrDate2 PrimaryDate   = tdate
transactionDateOrDate2 SecondaryDate = transactionDate2

-- | Ensure a transaction's postings refer back to it, so that eg
-- relatedPostings works right.
txnTieKnot :: Transaction -> Transaction
txnTieKnot t@Transaction{tpostings=ps} = t' where
    t' = t{tpostings=map (postingSetTransaction t') ps}

-- | Ensure a transaction's postings do not refer back to it, so that eg
-- recursiveSize and GHCI's :sprint work right.
txnUntieKnot :: Transaction -> Transaction
txnUntieKnot t@Transaction{tpostings=ps} = t{tpostings=map (\p -> p{ptransaction=Nothing}) ps}

-- | Set a posting's parent transaction.
postingSetTransaction :: Transaction -> Posting -> Posting
postingSetTransaction t p = p{ptransaction=Just t}

-- | Apply a transform function to this transaction's amounts.
transactionTransformPostings :: (Posting -> Posting) -> Transaction -> Transaction
transactionTransformPostings f t@Transaction{tpostings=ps} = t{tpostings=map f ps}

-- | Apply a specified valuation to this transaction's amounts, using
-- the provided price oracle, commodity styles, and reference dates.
-- See amountApplyValuation.
transactionApplyValuation :: PriceOracle -> M.Map CommoditySymbol AmountStyle -> Day -> Day -> ValuationType -> Transaction -> Transaction
transactionApplyValuation priceoracle styles periodlast today v =
  transactionTransformPostings (postingApplyValuation priceoracle styles periodlast today v)

-- | Maybe convert this 'Transaction's amounts to cost.
transactionToCost :: ConversionOp -> Transaction -> Transaction
transactionToCost cost t = t{tpostings = mapMaybe (postingToCost cost) $ tpostings t}

-- | For any costs in this 'Transaction' which don't have associated equity conversion postings,
-- generate and add those. Generated amounts are rounded to the transaction's local display
-- precision to avoid arithmetic artifacts (e.g. 9.216 * 1801.215277778 = 16600.000000002 -> 16600.00),
-- except in a transaction whose imbalance is shown by an imbalance posting (see --infer-imbalance):
-- there, the conversion postings keep their exact cost amounts, so that every commodity balances exactly.
transactionInferEquityPostings :: Bool -> AccountName -> Transaction -> Transaction
transactionInferEquityPostings verbosetags equityAcct t =
  t{tpostings = (if hasimbalanceposting then id else map roundGenerated) $ go $ tpostings t}
  where
    hasimbalanceposting = any (postingHasTag imbalancePostingTagName) (tpostings t)
    -- The consecutive per-lot fragments of one posting (lotsplit-tagged and
    -- sharing poriginal, as in Lots.mergeLotSplits) get one set of conversion
    -- postings after the last fragment, so collapsing lot detail can still merge them.
    go [] = []
    go (p:ps) = postingsAddInferredEquityPostings verbosetags equityAcct (p:run) ++ go rest
      where
        (run, rest)
          | isLotSplit p = span (\q -> isLotSplit q && poriginal q == poriginal p) ps
          | otherwise    = ([], ps)
    isLotSplit = postingHasTag lotsplitPostingTagName
    -- Round generated equity conversion posting amounts (quantities, not just display)
    -- to the transaction's local display precision, avoiding arithmetic artifacts
    -- (e.g. 9.216 * 1801.215277778 = 16600.000000002 -> 16600.00).
    styles = transactionCommodityStyles t
    roundGenerated p
      | generatedPostingTagName `elem` map fst (ptags p) = p{pamount = mapMixedAmount roundAmount (pamount p)}
      | otherwise = p
    roundAmount a = case M.lookup (acommodity a) styles of
      Just s@AmountStyle{asprecision=Precision p} -> a{aquantity = roundTo p (aquantity a), astyle = s}
      _ -> a

type IdxPosting = (Int, Posting)

-- XXX Warning: The following code - for analysing equity conversion postings,
-- inferring missing costs and ignoring redundant costs -
-- is twisty and hard to follow.

label s = ((s <> ": ")++)

-- | Add tags to a transaction, discarding any for which it already has a value.
-- Note this does not add tags to the transaction's comment.
transactionAddTags :: Transaction -> [Tag] -> Transaction
transactionAddTags t@Transaction{ttags} tags = t{ttags=ttags `union` tags}

-- | Add the given hidden tag to a transaction; and with a true argument,
-- also add the equivalent visible tag to the transaction's tags and comment fields.
-- If the transaction already has these tags (with any value), do nothing.
transactionAddHiddenAndMaybeVisibleTag :: Bool -> HiddenTag -> Transaction -> Transaction
transactionAddHiddenAndMaybeVisibleTag verbosetags ht t@Transaction{tcomment=c, ttags} =
  (t `transactionAddTags` ([ht] <> [ vt|verbosetags]))
  {tcomment=if verbosetags && not hadtag then c `commentAddTagNextLine` vt else c}
  where
    vt@(vname,_) = toVisibleTag ht
    hadtag = any ((== (T.toLower vname)) . T.toLower . fst) ttags  -- XXX should regex-quote vname

-- | Find, associate, and tag the corresponding equity conversion postings and costful or potentially costful postings in this transaction.
-- With a true addcosts argument, also generate and add any equivalent costs that are missing.
-- The (previously detected) names of all equity conversion accounts should be provided.
--
-- For every pair of adjacent conversion postings, this first searches for a posting with equivalent cost (1).
-- If no such posting is found, it then searches the costless postings, for one matching one of the conversion amounts (2).
-- If either of these found a candidate posting, it is tagged with costPostingTagName.
-- Then if in addcosts mode, if a costless posting was found, a cost equivalent to the conversion amounts is added to it.
--
-- The name reflects the complexity of this and its helpers; clarification is ongoing.
--
transactionTagCostsAndEquityAndMaybeInferCosts :: Bool -> Bool -> [AccountName] -> Transaction -> Either String Transaction
transactionTagCostsAndEquityAndMaybeInferCosts verbosetags1 addcosts conversionaccts t
  -- Without conversion postings there is nothing to tag or infer, so skip the work (and the rebuild) below.
  | not $ any ((`elem` conversionaccts) . paccount) $ tpostings t = Right t
  | otherwise = first (annotateErrorWithTransaction t . T.unpack) $ do
  -- number the postings
  let npostings = zip [0..] $ tpostings t

  -- Identify all pairs of conversion postings and all other postings (with and without costs) in the transaction.
  (conversionPairs, otherps) <- partitionAndCheckConversionPostings False conversionaccts npostings

  -- Generate a pure function that can be applied to each of this transaction's postings,
  -- possibly modifying it, to produce the following end result:
  -- 1. each pair of conversion postings, and the corresponding postings which balance them, are tagged for easy identification
  -- 2. each pair of balancing postings which did't have an explicit cost, have had a cost calculated and added to one of them
  -- 3. if any ambiguous situation was detected, an informative error is raised
  processposting <- transformIndexedPostingsF (tagAndMaybeAddCostsForEquityPostings verbosetags1 addcosts) conversionPairs otherps

  -- And if there was no error, use it to modify the transaction's postings.
  return t{tpostings = map (snd . processposting) npostings}

  where

    -- Generate the tricksy processposting function,
    -- which when applied to each posting in turn, rather magically has the effect of
    -- applying tagAndMaybeAddCostsForEquityPostings to each pair of conversion postings in the transaction,
    -- matching them with the other postings, tagging them and perhaps adding cost information to the other postings.
    -- General type:
    -- transformIndexedPostingsF :: (Monad m, Foldable t, Traversable t) =>
    --   (a -> StateT s m (a1 -> a1)) ->
    --   t a ->
    --   s ->
    --   m (a1 -> a1)
    -- Concrete type:
    transformIndexedPostingsF ::
      ((IdxPosting, IdxPosting) -> StateT ([IdxPosting],[IdxPosting]) (Either Text) (IdxPosting -> IdxPosting)) ->  -- state update function (tagAndMaybeAddCostsForEquityPostings with the bool applied)
      [(IdxPosting, IdxPosting)] ->   -- initial state: the pairs of adjacent conversion postings in the transaction
      ([IdxPosting],[IdxPosting]) ->  -- initial state: the other postings in the transaction, separated into costful and costless
      (Either Text (IdxPosting -> IdxPosting))  -- returns an error message or a posting transform function
    transformIndexedPostingsF updatefn = evalStateT . fmap (appEndo . foldMap Endo) . traverse (updatefn)

    -- A tricksy state update helper for processposting/transformIndexedPostingsF.
    -- Approximately: given a pair of equity conversion postings to match,
    -- and lists of the remaining unmatched costful and costless other postings,
    -- 1. find (and consume) two other postings whose amounts/cost match the two conversion postings
    -- 2. add hidden identifying tags to the conversion postings and the other posting which has (or could have) an equivalent cost
    -- 3. if in add costs mode, and the potential equivalent-cost posting does not have that explicit cost, add it
    -- 4. or if there is a problem, raise an informative error or do nothing, as appropriate.
    -- Or if there are no costful postings at all, do nothing.
    tagAndMaybeAddCostsForEquityPostings :: Bool -> Bool -> (IdxPosting, IdxPosting) -> StateT ([IdxPosting], [IdxPosting]) (Either Text) (IdxPosting -> IdxPosting)
    tagAndMaybeAddCostsForEquityPostings verbosetags addcosts' ((n1, cp1), (n2, cp2)) = StateT $ \(costps, otherps) -> do
      -- Get the two conversion posting amounts, if possible
      ca1 <- conversionPostingAmountNoCost cp1
      ca2 <- conversionPostingAmountNoCost cp2
      let 
        -- All costful postings whose cost is equivalent to the conversion postings' amounts.
        matchingCostfulPs =
          dbg7With (label "matched costful postings".show.length) $ 
          mapMaybe (mapM $ costfulPostingIfMatchesBothAmounts ca1 ca2) costps

        -- In dry run mode: all other costless, single-commodity postings.
        -- In add costs mode: all other costless, single-commodity postings whose amount matches at least one of the conversion postings,
        -- with the equivalent cost added to one of them. (?)
        matchingCostlessPs =
          dbg7With (label "matched costless postings".show.length) $
          if addcosts'
          then mapMaybe (mapM $ addCostIfMatchesOneAmount ca1 ca2) otherps
          else [(n,(p, a)) | (n,p) <- otherps, let Just a = postingSingleAmount p]

        -- A function that adds a cost and/or tag to a numbered posting if appropriate.
        postingAddCostAndOrTag np costp (n,p) =
          (n, if | n == np            -> costp & postingAddHiddenAndMaybeVisibleTag False verbosetags (costPostingTagName,"")        -- if it's the specified posting number, replace it with the costful posting, and tag it
                 | n == n1 || n == n2 -> p     & postingAddHiddenAndMaybeVisibleTag False verbosetags (conversionPostingTagName,"")  -- if it's one of the equity conversion postings, tag it
                 | otherwise          -> p)

      -- Annotate any errors with the conversion posting pair
      first (annotateWithPostings [cp1, cp2]) $
        if
          -- If a single costful posting matches the conversion postings,
          -- delete it from the list of costful postings in the state, delete the
          -- first matching costless posting from the list of costless postings
          -- in the state, and return the transformation function with the new state.
          | [(np, costp)] <- matchingCostfulPs
          , Just newcostps <- deleteIdx np costps
              -> Right (postingAddCostAndOrTag np costp, (if addcosts' then newcostps else costps, otherps))

          -- If no costful postings match the conversion postings, but some
          -- of the costless postings match, check that the first such posting has a
          -- different amount from all the others, and if so add a cost to it,
          -- then delete it from the list of costless postings in the state,
          -- and return the transformation function with the new state.
          | [] <- matchingCostfulPs
          , (np, (costp, amt)):nps <- matchingCostlessPs
          , not $ any (amountsMatch amt . snd . snd) nps
          , Just newotherps <- deleteIdx np otherps
              -> Right (postingAddCostAndOrTag np costp, (costps, if addcosts' then newotherps else otherps))

          -- Otherwise, do nothing, leaving the transaction unchanged.
          -- We don't want to be over-zealous reporting problems here
          -- since this is always called at least in dry run mode by
          -- journalFinalise > journalMarkRedundantCosts. (#2045)
          | otherwise -> Right (id, (costps, otherps))

    -- If a posting with cost matches both the conversion amounts, return it along
    -- with the matching amount which must be present in another non-conversion posting.
    costfulPostingIfMatchesBothAmounts :: Amount -> Amount -> Posting -> Maybe Posting
    costfulPostingIfMatchesBothAmounts a1 a2 costfulp = do
        a@Amount{acost=Just _} <- postingSingleAmount costfulp
        if
           | dbgamtmatch 1 a1 a (amountsMatch (-a1) a)  &&  dbgcostmatch 2 a2 a (costMatches a2 a) -> Just costfulp
           | dbgamtmatch 2 a2 a (amountsMatch (-a2) a)  &&  dbgcostmatch 1 a1 a (costMatches a1 a) -> Just costfulp
           | otherwise -> Nothing
           where
            -- A conversion posting's amount matches the costful amount's cost
            -- when it equals the transacted cost; or the cost basis (a lot
            -- disposal, whose conversion postings record what the units cost,
            -- the difference from the proceeds being in the gain posting); or,
            -- when a cost basis is written but not yet known (an unspecified
            -- {} basis, filled in by lot matching later), when it is in the
            -- cost's commodity. The balancer and the post-lot gain check
            -- verify the amounts afterwards.
            costMatches c a =
                 amountsMatch c (amountCost a)
              || amountsMatch c (amountCostBasis a)
              || (hasUnspecifiedBasis a && acommodity c == acommodity (amountCost a))
            hasUnspecifiedBasis a = maybe False (isNothing . cbCost) (acostbasis a)
            dbgamtmatch  n a b = dbg7 ("conversion posting "     <>show n<>" "<>showAmount a<>" balances amount "<>showAmountWithoutCost b <>" of costful posting "<>showAmount b<>" at precision "<>dbgShowAmountPrecision a<>" ?")
            dbgcostmatch n a b = dbg7 ("and\nconversion posting "<>show n<>" "<>showAmount a<>" matches cost "   <>showAmount (amountCost b)<>" of costful posting "<>showAmount b<>" at precision "<>dbgShowAmountPrecision a<>" ?") 

    -- Add a cost to a posting if it matches (negative) one of the
    -- supplied conversion amounts, adding the other amount as the cost.
    addCostIfMatchesOneAmount :: Amount -> Amount -> Posting -> Maybe (Posting, Amount)
    addCostIfMatchesOneAmount a1 a2 p = do
        a <- postingSingleAmount p
        let newp cost = p{pamount = mixedAmount a{acost = Just $ TotalCost cost}}
        if
           | amountsMatch (-a1) a -> Just (newp a2, a2)
           | amountsMatch (-a2) a -> Just (newp a1, a1)
           | otherwise            -> Nothing

    -- Get the single-commodity costless amount from a conversion posting, or raise an error.
    conversionPostingAmountNoCost p = case postingSingleAmount p of
        Just a@Amount{acost=Nothing} -> Right a
        Just Amount{acost=Just _} -> Left $ annotateWithPostings [p] "Conversion postings must not have a cost:"
        Nothing                    -> Left $ annotateWithPostings [p] "Conversion postings must have a single-commodity amount:"

    -- Do these amounts look the same when compared at the first's display precision ?
    amountsMatch a b = amountLooksZero $ amountSetPrecision (asprecision $ astyle a) $ a - b

    -- Delete a posting from the indexed list of postings based on either its
    -- index or its posting amount.
    -- Note: traversing the whole list to delete a single match is generally not efficient,
    -- but given that a transaction probably doesn't have more than four postings, it should
    -- still be more efficient than using a Map or another data structure. Even monster
    -- transactions with up to 10 postings, which are generally not a good
    -- idea, are still too small for there to be an advantage.
    -- XXX shouldn't assume transactions have few postings
    deleteIdx n = deleteUniqueMatch ((n==) . fst)
    deleteUniqueMatch p (x:xs) | p x       = if any p xs then Nothing else Just xs
                               | otherwise = (x:) <$> deleteUniqueMatch p xs
    deleteUniqueMatch _ []                 = Nothing
    annotateWithPostings xs str = T.unlines $ str : postingsAsLines defaultFmt False xs

dbgShowAmountPrecision a =
  case asprecision $ astyle a of
    Precision n      -> show n
    NaturalPrecision -> show $ decimalPlaces $ normalizeDecimal $ aquantity a

-- Given the names of conversion equity accounts, sort the given indexed postings
-- into three lists of posting numbers (stored in two pairs), like so:
-- (conversion postings, (costful other postings, costless other postings)).
-- A true first argument activates its secondary function: check that all
-- conversion postings occur in adjacent pairs, otherwise return an error.
partitionAndCheckConversionPostings :: Bool -> [AccountName] -> [IdxPosting] -> Either Text ( [(IdxPosting, IdxPosting)], ([IdxPosting], [IdxPosting]) )
partitionAndCheckConversionPostings check conversionaccts =
  -- Left fold processes postings in parse order, so that eg inferred costs
  -- will be added to the first (top-most) posting, not the last one.
  foldlM select (([], ([], [])), Nothing)
    -- The costless other postings are somehow reversed still; "second (second reverse)" fixes that.
    <&> fmap (second (second reverse) . fst)
  where
    select ((cs, others@(ps, os)), Nothing) np@(_, p)
      | isConversion p = Right ((cs, others),      Just np)
      | hasCost p      = Right ((cs, (np:ps, os)), Nothing)
      | otherwise      = Right ((cs, (ps, np:os)), Nothing)
    select ((cs, others@(ps,os)), Just lst) np@(_, p)
      | isConversion p = Right (((lst, np):cs, others), Nothing)
      | check          = Left "Conversion postings must occur in adjacent pairs"
      | otherwise      = Right ((cs, (ps, np:os)), Nothing)
    isConversion p = paccount p `elem` conversionaccts
    hasCost p = isJust $ acost =<< postingSingleAmount p

-- | Get a posting's amount if it is single-commodity.
postingSingleAmount :: Posting -> Maybe Amount
postingSingleAmount p = case amountsRaw (pamount p) of
  [a] -> Just a
  _   -> Nothing

-- | Apply some account aliases to all posting account names in the transaction, as described by accountNameApplyAliases.
-- This can fail due to a bad replacement pattern in a regular expression alias.
transactionApplyAliases :: [AccountAlias] -> Transaction -> Either RegexError Transaction
transactionApplyAliases aliases t =
  case mapM (postingApplyAliases aliases) $ tpostings t of
    Right ps -> Right $ txnTieKnot $ t{tpostings=ps}
    Left err -> Left err

-- | Apply a transformation to a transaction's postings.
transactionMapPostings :: (Posting -> Posting) -> Transaction -> Transaction
transactionMapPostings f t@Transaction{tpostings=ps} = t{tpostings=map f ps}

-- | Apply a transformation to a transaction's posting amounts.
transactionMapPostingAmounts :: (MixedAmount -> MixedAmount) -> Transaction -> Transaction
transactionMapPostingAmounts f  = transactionMapPostings (postingTransformAmount f)

-- | All posting amounts from this transaction, in order.
transactionAmounts :: Transaction -> [MixedAmount]
transactionAmounts = map pamount . tpostings

-- | Get this transaction's local styles - the commodity styles inferred from
-- its explicitly-written (or generated from balance assignments) posting amounts.
-- Inferred balancing amounts are excluded so that they can't confusingly increase
-- the entry's local balancing precision.
transactionCommodityStyles :: Transaction -> M.Map CommoditySymbol AmountStyle
transactionCommodityStyles =
  either (const mempty) id .  -- ignore style problems, commodityStylesFromAmounts doesn't report them currently
  commodityStylesFromAmounts . concatMap (amountsRaw . pamount) . filter isExplicitAmount . tpostings

-- | Like transactionCommodityStyles, but attach a particular rounding strategy to the styles,
-- affecting how they will affect display precisions when applied.
transactionCommodityStylesWith :: Rounding -> Transaction -> M.Map CommoditySymbol AmountStyle
transactionCommodityStylesWith r = amountStylesSetRounding r . transactionCommodityStyles

-- | Flip the sign of this transaction's posting amounts (and balance assertion amounts).
transactionNegate :: Transaction -> Transaction
transactionNegate = transactionMapPostings postingNegate

-- | The file path from which this transaction was parsed.
transactionFile :: Transaction -> FilePath
transactionFile Transaction{tsourcepos} = sourceName $ fst tsourcepos

-- Add transaction information to an error message.
annotateErrorWithTransaction :: Transaction -> String -> String
annotateErrorWithTransaction t s =
  unlines [ sourcePosPairPretty $ tsourcepos t, s
          , T.unpack . T.stripEnd $ showTransaction t
          ]

-- tests

tests_Transaction :: TestTree
tests_Transaction =
  testGroup "Transaction" [

      testGroup "showPostingLines" [
          testCase "null posting" $ showPostingLines nullposting @?= ["                                                   0"]
        , testCase "non-null posting" $
           let p =
                posting
                  { pstatus = Cleared
                  , paccount = "a"
                  , pamount = mixed [usd 1, hrs 2]
                  , pcomment = "pcomment1\npcomment2\n  tag3: val3  \n"
                  , preal = RealPosting
                  , ptags = [("ptag1", "val1"), ("ptag2", "val2")]
                  }
           in showPostingLines p @?=
              [ "    * a                                           $1.00  ; pcomment1"
              , "    ; pcomment2"
              , "    ;   tag3: val3  "
              , "    * a                                            2.00h  ; pcomment1"
              , "    ; pcomment2"
              , "    ;   tag3: val3  "
              ]
        ]

    , let
        -- one implicit amount
        timp = nulltransaction {tpostings = ["a" `post` usd 1, "b" `post` missingamt]}
        -- explicit amounts, balanced
        texp = nulltransaction {tpostings = ["a" `post` usd 1, "b" `post` usd (-1)]}
        -- explicit amount, only one posting
        texp1 = nulltransaction {tpostings = ["(a)" `post` usd 1]}
        -- explicit amounts, two commodities, explicit balancing price
        texp2 = nulltransaction {tpostings = ["a" `post` usd 1, "b" `post` (hrs (-1) `at` usd 1)]}
        -- explicit amounts, two commodities, implicit balancing price
        texp2b = nulltransaction {tpostings = ["a" `post` usd 1, "b" `post` hrs (-1)]}
        -- one missing amount, not the last one
        t3 = nulltransaction {tpostings = ["a" `post` usd 1, "b" `post` missingamt, "c" `post` usd (-1)]}
        -- unbalanced amounts when precision is limited (#931)
        -- t4 = nulltransaction {tpostings = ["a" `post` usd (-0.01), "b" `post` usd (0.005), "c" `post` usd (0.005)]}
      in testGroup "postingsAsLines" [
              testCase "null-transaction" $ postingsAsLines defaultFmt False (tpostings nulltransaction) @?= []
            , testCase "implicit-amount" $ postingsAsLines defaultFmt False (tpostings timp) @?=
                  [ "    a                                             $1.00"
                  , "    b" -- implicit amount remains implicit
                  ]
            , testCase "explicit-amounts" $ postingsAsLines defaultFmt False (tpostings texp) @?=
                  [ "    a                                             $1.00"
                  , "    b                                            $-1.00"
                  ]
            , testCase "one-explicit-amount" $ postingsAsLines defaultFmt False (tpostings texp1) @?=
                  [ "    (a)                                           $1.00"
                  ]
            , testCase "explicit-amounts-two-commodities" $ postingsAsLines defaultFmt False (tpostings texp2) @?=
                  [ "    a                                             $1.00"
                  , "    b                                             -1.00h @ $1.00"
                  ]
            , testCase "explicit-amounts-not-explicitly-balanced" $ postingsAsLines defaultFmt False (tpostings texp2b) @?=
                  [ "    a                                             $1.00"
                  , "    b                                             -1.00h"
                  ]
            , testCase "implicit-amount-not-last" $ postingsAsLines defaultFmt False (tpostings t3) @?=
                  ["    a                                             $1.00", "    b", "    c                                            $-1.00"]
            -- , testCase "ensure-visibly-balanced" $
            --    in postingsAsLines False (tpostings t4) @?=
            --       ["    a          $-0.01", "    b           $0.005", "    c           $0.005"]

            ]

    , testGroup "showTransaction" [
          testCase "null transaction" $ showTransaction nulltransaction @?= "0000-01-01\n\n"
        , testCase "non-null transaction" $ showTransaction
            nulltransaction
              { tdate = fromGregorian 2012 05 14
              , tdate2 = Just $ fromGregorian 2012 05 15
              , tstatus = Unmarked
              , tcode = "code"
              , tdescription = "desc"
              , tcomment = "tcomment1\ntcomment2\n"
              , ttags = [("ttag1", "val1")]
              , tpostings =
                  [ nullposting
                      { pstatus = Cleared
                      , paccount = "a"
                      , pamount = mixed [usd 1, hrs 2]
                      , pcomment = "\npcomment2\n"
                      , preal = RealPosting
                      , ptags = [("ptag1", "val1"), ("ptag2", "val2")]
                      }
                  ]
              } @?=
          T.unlines
            [ "2012-05-14=2012-05-15 (code) desc  ; tcomment1"
            , "    ; tcomment2"
            , "    * a                                           $1.00"
            , "    ; pcomment2"
            , "    * a                                            2.00h"
            , "    ; pcomment2"
            , ""
            ]
        , testCase "show a balanced transaction" $
          (let t =
                 Transaction
                   0
                   ""
                   nullsourcepospair
                   (fromGregorian 2007 01 28)
                   Nothing
                   Unmarked
                   ""
                   "coopportunity"
                   ""
                   []
                   [ posting {paccount = "expenses:food:groceries", pamount = mixedAmount (usd 47.18), ptransaction = Just t}
                   , posting {paccount = "assets:checking", pamount = mixedAmount (usd (-47.18)), ptransaction = Just t}
                   ]
            in showTransaction t) @?=
          (T.unlines
             [ "2007-01-28 coopportunity"
             , "    expenses:food:groceries                      $47.18"
             , "    assets:checking                             $-47.18"
             , ""
             ])
        , testCase "show an unbalanced transaction, should not elide" $
          (showTransaction
             (txnTieKnot $
              Transaction
                0
                ""
                nullsourcepospair
                (fromGregorian 2007 01 28)
                Nothing
                Unmarked
                ""
                "coopportunity"
                ""
                []
                [ posting {paccount = "expenses:food:groceries", pamount = mixedAmount (usd 47.18)}
                , posting {paccount = "assets:checking", pamount = mixedAmount (usd (-47.19))}
                ])) @?=
          (T.unlines
             [ "2007-01-28 coopportunity"
             , "    expenses:food:groceries                      $47.18"
             , "    assets:checking                             $-47.19"
             , ""
             ])
        , testCase "show a transaction with one posting and a missing amount" $
          (showTransaction
             (txnTieKnot $
              Transaction
                0
                ""
                nullsourcepospair
                (fromGregorian 2007 01 28)
                Nothing
                Unmarked
                ""
                "coopportunity"
                ""
                []
                [posting {paccount = "expenses:food:groceries", pamount = missingmixedamt}])) @?=
          (T.unlines ["2007-01-28 coopportunity", "    expenses:food:groceries", ""])
        , testCase "show a transaction with a priced commodityless amount" $
          (showTransaction
             (txnTieKnot $
              Transaction
                0
                ""
                nullsourcepospair
                (fromGregorian 2010 01 01)
                Nothing
                Unmarked
                ""
                "x"
                ""
                []
                [ posting {paccount = "a", pamount = mixedAmount $ num 1 `at` (usd 2 `withPrecision` Precision 0)}
                , posting {paccount = "b", pamount = missingmixedamt}
                ])) @?=
          (T.unlines ["2010-01-01 x", "    a                                              1 @ $2", "    b", ""])
        ]
    ]
