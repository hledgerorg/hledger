{-|
Helpers for making error messages.
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Hledger.Data.Errors (
  decorateExcerpt,
  makeAccountTagErrorExcerpt,
  makeCommodityTagErrorExcerpt,
  makePriceDirectiveErrorExcerpt,
  makeTransactionErrorExcerpt,
  makePostingErrorExcerpt,
  makePostingErrorExcerptByIndex,
  makePostingAccountErrorExcerpt,
  makeBalanceAssertionErrorExcerpt,
  transactionFindPostingIndex,
)
where

import Data.Function ((&))
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as T

import Hledger.Data.Transaction (showTransaction)
import Hledger.Data.Posting (postingStripCosts)
import Hledger.Data.Types
import Hledger.Utils
import Data.Maybe
import Safe (headMay)
import Hledger.Data.Posting (isVirtual)
import Hledger.Data.Amount (showPriceDirective)


-- | Given an account name and its account directive, and a problem tag within the latter:
-- render it as a megaparsec-style excerpt, showing the original line number and
-- marked column or region.
-- Returns the file path, line number, column(s) if known,
-- and the rendered excerpt, or as much of these as is possible.
-- The returned columns will be accurate for the rendered error message but not for the original journal data.
makeAccountTagErrorExcerpt :: (AccountName, AccountDeclarationInfo) -> TagName -> (FilePath, Int, Maybe (Int, Maybe Int), Text)
makeAccountTagErrorExcerpt (a, adi) _t = (f, l, merrcols, ex)
  -- XXX findtxnerrorcolumns is awkward, I don't think this is the final form
  where
    SourcePos f pos _ = adisourcepos adi
    l = unPos pos
    txt   = showAccountDirective (a, adi) & textChomp & (<>"\n")
    ex = decorateExcerpt l merrcols txt
    -- Calculate columns which will help highlight the region in the excerpt
    -- (but won't exactly match the real data, so won't be shown in the main error line)
    merrcols = Nothing
      -- don't bother for now
      -- Just (col, Just col2)
      -- where
      --   col  = undefined -- T.length (showTransactionLineFirstPart t') + 2
      --   col2 = undefined -- col + T.length tagname - 1      

showAccountDirective (a, AccountDeclarationInfo{..}) =
  "account " <> a
  <> (if not $ T.null adicomment then "    ; " <> adicomment else "")

-- | Given a commodity and a problem tag within it:
-- render it as a megaparsec-style excerpt, showing the original line number.
-- Returns the file path, line number, column(s) if known, and the rendered excerpt.
makeCommodityTagErrorExcerpt :: Commodity -> TagName -> (FilePath, Int, Maybe (Int, Maybe Int), Text)
makeCommodityTagErrorExcerpt comm _t = (f, l, merrcols, ex)
  where
    SourcePos f pos _ = csourcepos comm
    l = unPos pos
    txt = showCommodityDirective comm & textChomp & (<>"\n")
    ex = decorateExcerpt l merrcols txt
    merrcols = Nothing

showCommodityDirective :: Commodity -> Text
showCommodityDirective Commodity{..} =
  "commodity " <> csymbol
  <> (if not $ T.null ccomment then "  ; " <> ccomment else "")

-- | Decorate a data excerpt with megaparsec-style left margin, line number,
-- and marker/underline for the column(s) if known, for inclusion in an error message.
decorateExcerpt :: Int -> Maybe (Int, Maybe Int) -> Text -> Text
decorateExcerpt l mcols txt =
  T.unlines $ ls' <> colmarkerline <> map (lineprefix<>) ms
  where
    (ls,ms) = splitAt 1 $ T.lines txt
    ls' = map ((T.pack (show l) <> " | ") <>) ls
    colmarkerline =
      [lineprefix <> T.replicate (col-1) " " <> T.replicate regionw "^"
      | Just (col, mendcol) <- [mcols]
      , let regionw = maybe 1 (subtract col) mendcol + 1
      ]
    lineprefix = T.replicate marginw " " <> "| "
      where  marginw = length (show l) + 1

-- | Given a problem price directive,
-- and maybe a function to calculate the error region's column(s) (currently ignored):
-- generate a megaparsec-style error message with highlighted excerpt.
-- Returns the source file path, line number, column(s) if known, and the rendered excerpt,
-- or as much of these as possible.
-- Columns will be accurate for the rendered error message, not for the original journal entry.
makePriceDirectiveErrorExcerpt :: PriceDirective -> Maybe (PriceDirective -> Text -> Maybe (Int, Maybe Int)) -> (FilePath, Int, Maybe (Int, Maybe Int), Text)
makePriceDirectiveErrorExcerpt pd _finderrorcolumns = (file, line, merrcols, excerpt)
  where
    SourcePos file pos _ = pdsourcepos pd
    line = unPos pos
    merrcols = Nothing
    excerpt = decorateExcerpt line merrcols $ showPriceDirective pd <> "\n"

-- | Given a problem transaction and a function calculating the best
-- column(s) for marking the error region:
-- render it as a megaparsec-style excerpt, showing the original line number
-- on the transaction line, and a column(s) marker.
-- Returns the file path, line number, column(s) if known,
-- and the rendered excerpt, or as much of these as is possible.
-- The returned columns will be accurate for the rendered error message but not for the original journal data.
-- | Render a transaction for an error excerpt: without its preceding comment lines
-- (which are not part of the entry, and would shift the line numbering), chomped and newline-terminated.
showTransactionForExcerpt :: Transaction -> Text
showTransactionForExcerpt t = showTransaction t{tprecedingcomment=""} & textChomp & (<>"\n")

makeTransactionErrorExcerpt :: Transaction -> (Transaction -> Maybe (Int, Maybe Int)) -> (FilePath, Int, Maybe (Int, Maybe Int), Text)
makeTransactionErrorExcerpt t findtxnerrorcolumns = (f, tl, merrcols, ex)
  -- XXX findtxnerrorcolumns is awkward, I don't think this is the final form
  where
    SourcePos f tpos _ = fst $ tsourcepos t
    tl = unPos tpos
    txntxt = showTransactionForExcerpt t
    merrcols = findtxnerrorcolumns t
    ex = decorateTransactionErrorExcerpt tl merrcols txntxt

-- | Add megaparsec-style left margin, line number, and optional column marker(s).
decorateTransactionErrorExcerpt :: Int -> Maybe (Int, Maybe Int) -> Text -> Text
decorateTransactionErrorExcerpt l mcols txt =
  T.unlines $ ls' <> colmarkerline <> map (lineprefix<>) ms
  where
    (ls,ms) = splitAt 1 $ T.lines txt
    ls' = map ((T.pack (show l) <> " | ") <>) ls
    colmarkerline =
      [lineprefix <> T.replicate (col-1) " " <> T.replicate regionw "^"
      | Just (col, mendcol) <- [mcols]
      , let regionw = maybe 1 (subtract col) mendcol + 1
      ]
    lineprefix = T.replicate marginw " " <> "| "
      where  marginw = length (show l) + 1

-- | Given a problem posting and a function calculating the best
-- column(s) for marking the error region:
-- look up error info from the parent transaction, and render the transaction
-- as a megaparsec-style excerpt, showing the original line number
-- on the problem posting's line, and a column indicator.
-- Returns the file path, line number, column(s) if known,
-- and the rendered excerpt, or as much of these as is possible.
-- A limitation: columns will be accurate for the rendered error message but not for the original journal data.
makePostingErrorExcerpt :: Posting -> (Posting -> Transaction -> Text -> Maybe (Int, Maybe Int)) -> (FilePath, Int, Maybe (Int, Maybe Int), Text)
makePostingErrorExcerpt p findpostingerrorcolumns =
  case ptransaction p of
    Nothing -> ("-", 0, Nothing, "")
    Just t  -> (f, errabsline, merrcols, ex)
      where
        (SourcePos f tl _) = fst $ tsourcepos t
        -- p had cost removed in balanceTransactionAndCheckAssertionsB,
        -- must remove them from t's postings too (#2083)
        mpindex = transactionFindPostingIndex ((==p).postingStripCosts) t
        errrelline = case mpindex of
          Nothing -> 0
          Just pindex ->
            commentExtraLines (tcomment t) +
            sum (map postingLines $ take pindex $ tpostings t)
            where
              -- How many lines are used to render this posting ?
              postingLines p' = 1 + commentExtraLines (pcomment p')
              -- How many extra lines does this comment add to a transaction or posting rendering ?
              commentExtraLines c = max 0 (length (T.lines c) - 1)
        errabsline = clampToTransactionLines t $ unPos tl + errrelline
        txntxt = showTransactionForExcerpt t
        merrcols = findpostingerrorcolumns p t txntxt
        ex = decoratePostingErrorExcerpt errabsline errrelline merrcols txntxt

-- | Add megaparsec-style left margin, line number, and optional column marker(s).
decoratePostingErrorExcerpt :: Int -> Int -> Maybe (Int, Maybe Int) -> Text -> Text
decoratePostingErrorExcerpt absline relline mcols txt =
  T.unlines $ js' <> ks' <> colmarkerline <> ms'
  where
    (ls,ms) = splitAt (relline+1) $ T.lines txt
    (js,ks) = splitAt (length ls - 1) ls
    (js',ks') = case ks of
      [k] -> (map (lineprefix<>) js, [T.pack (show absline) <> " | " <> k])
      _   -> ([], [])
    ms' = map (lineprefix<>) ms
    colmarkerline =
      [lineprefix <> T.replicate (col-1) " " <> T.replicate regionw "^"
      | Just (col, mendcol) <- [mcols]
      , let regionw = 1 + maybe 0 (subtract col) mendcol
      ]
    lineprefix = T.replicate marginw " " <> "| "
      where  marginw = length (show absline) + 1

-- | Like 'makePostingErrorExcerpt', but identifies the posting by its
-- 0-based index in the transaction rather than by equality search.
-- This avoids false mismatches when postings have been modified after parsing
-- (e.g. by the balancer), and is unambiguous when duplicate postings exist.
-- The optional column tuple, if provided, adds a "^^^^" highlight under the posting.
makePostingErrorExcerptByIndex :: Transaction -> Int -> Maybe (Int, Maybe Int)
                               -> (FilePath, Int, Maybe (Int, Maybe Int), Text)
makePostingErrorExcerptByIndex t idx mcols = (f, errabsline, mcols, ex)
  where
    (SourcePos f tl _) = fst $ tsourcepos t
    errrelline =
      commentExtraLines (tcomment t) +
      sum (map postingLines $ take (idx + 1) $ tpostings t)
      where
        postingLines p' = 1 + commentExtraLines (pcomment p')
        commentExtraLines c = max 0 (length (T.lines c) - 1)
    errabsline = clampToTransactionLines t $ unPos tl + errrelline
    txntxt = showTransactionForExcerpt t
    ex = decoratePostingErrorExcerpt errabsline errrelline mcols txntxt

-- | Clamp a calculated error line number to this transaction's source line
-- range. Calculated posting line numbers count the lines of the rendered
-- entry, which can have more lines than the source region that produced it
-- (notably with CSV, where a one-line record can produce a many-line entry);
-- don't let them point beyond the entry's recorded source lines.
clampToTransactionLines :: Transaction -> Int -> Int
clampToTransactionLines t = max startline . min lastline
  where
    (SourcePos _ l1 _, SourcePos _ l2 c2) = tsourcepos t
    startline = unPos l1
    -- the end position is usually the start of the line after the entry
    lastline  = max startline $ unPos l2 - if unPos c2 == 1 then 1 else 0

-- | Find the 1-based index of the first posting in this transaction
-- satisfying the given predicate.
transactionFindPostingIndex :: (Posting -> Bool) -> Transaction -> Maybe Int
transactionFindPostingIndex ppredicate = 
  fmap fst . find (ppredicate.snd) . zip [1..] . tpostings

-- | From the given posting, make an error excerpt showing the transaction with
-- this posting's account part highlighted.
makePostingAccountErrorExcerpt :: Posting -> (FilePath, Int, Maybe (Int, Maybe Int), Text)
makePostingAccountErrorExcerpt p = makePostingErrorExcerpt p finderrcols
  where
    -- Calculate columns suitable for highlighting the synthetic excerpt.
    finderrcols p' _ _ = Just (col, Just col2)
      where
        col = 5 + if isVirtual p' then 1 else 0
        col2 = col + T.length (paccount p') - 1

-- | From the given posting, make an error excerpt showing the transaction with
-- the balance assertion highlighted.
makeBalanceAssertionErrorExcerpt :: Posting -> (FilePath, Int, Maybe (Int, Maybe Int), Text)
makeBalanceAssertionErrorExcerpt p = makePostingErrorExcerpt p finderrcols
  where
    finderrcols p' t trendered = Just (col, Just col2)
      where
        -- Analyse the rendering to find the columns to highlight.
        tlines = dbg5 "tlines" $ max 1 $ length $ T.lines $ tcomment t  -- transaction comment can generate extra lines
        (col, col2) =
          let def = (5, maximum (map T.length $ T.lines trendered))  -- fallback: underline whole posting. Shouldn't happen.
          in
            case transactionFindPostingIndex (==p') t of
              Nothing  -> def
              Just idx -> fromMaybe def $ do
                let
                  beforeps = take (idx-1) $ tpostings t
                  beforepslines = dbg5 "beforepslines" $ sum $ map (max 1 . length . T.lines . pcomment) beforeps   -- posting comment can generate extra lines (assume only one commodity shown)
                assertionline <- dbg5 "assertionline" $ headMay $ drop (tlines + beforepslines) $ T.lines trendered
                let
                  col2' = T.length assertionline
                  l = dropWhile (/= '=') $ reverse $ T.unpack assertionline
                  l' = dropWhile (`elem` ['=','*']) l
                  col' = length l' + 1
                return (col', col2')

