{-|
Helpers for Ledger-compatible output.
-}

{-# LANGUAGE OverloadedStrings #-}

module Hledger.Write.Ledger (
  showTransactionLedger,
  ledgerItemRenderer,
)
where

import Data.Char (isDigit)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Builder qualified as TB

import Hledger.Data.Amount (defaultFmt, AmountFormat(..))
import Hledger.Data.Posting (postingsAsLines, renderCommentLines)
import Hledger.Data.Transaction (showTransactionLineFirstPart)
import Hledger.Data.Types (Transaction(..), tdescription)
import Hledger.Write.Journal (ItemRenderer(..), journalItemRenderer)

ledgerFmt :: AmountFormat
ledgerFmt = defaultFmt{displayLedgerLotSyntax = True}

-- | Like showTransaction, but renders cost basis using Ledger-style lot syntax
-- ({COST} [DATE] (LABEL)) instead of hledger consolidated syntax.
showTransactionLedger :: Transaction -> Text
showTransactionLedger t =
  TL.toStrict . TB.toLazyText $
      TB.fromText (tprecedingcomment t)
    <> TB.fromText descriptionline <> newline
    <> foldMap ((<> newline) . TB.fromText) newlinecomments
    <> foldMap ((<> newline) . TB.fromText) (postingsAsLines ledgerFmt False $ tpostings t)
    <> newline
  where
    descriptionline = T.stripEnd $ showTransactionLineFirstPart t <> T.concat [desc, samelinecomment]
    desc = if T.null d then "" else " " <> d where d = tdescription t
    (samelinecomment, newlinecomments) =
      case renderCommentLines (tcomment t) of []   -> ("",[])
                                              c:cs -> (c,cs)
    newline = TB.singleton '\n'

-- | An item renderer for Ledger output (print --export -O ledger): like the journal one,
-- but transactions use Ledger lot syntax, and directives which hledger accepts but Ledger
-- (detectably) does not are commented out, with an explanatory comment.
ledgerItemRenderer :: ItemRenderer
ledgerItemRenderer = (journalItemRenderer showTransactionLedger){ irDirective = Just . ledgerDirective }

-- | Reproduce a directive for Ledger, commenting it out with a note if it is one of
-- the hledger directive forms known not to be supported by Ledger.
ledgerDirective :: Text -> Text
ledgerDirective txt
  | isLedgerIncompatible txt = "; not supported as-is:\n" <> T.unlines (map ("; " <>) $ T.lines txt)
  | otherwise = txt

-- | Detect some hledger directive forms which Ledger does not support:
-- the decimal-mark directive; a one-line commodity directive with an amount
-- (Ledger uses a format subdirective); a periodic transaction rule with a description
-- (Ledger would read it as part of the period expression); and auto posting rules
-- using hledger's *N amount multipliers.
isLedgerIncompatible :: Text -> Bool
isLedgerIncompatible txt = case T.lines txt of
  [] -> False
  firstline : otherlines -> case T.words firstline of
    "decimal-mark" : _    -> True
    "commodity" : sym : _ -> T.any isDigit sym
    "~" : _               -> "  " `T.isInfixOf` (T.strip $ T.takeWhile (/=';') $ T.drop 1 firstline)
    "=" : _               -> any hasMultiplier otherlines
    _                     -> False
  where
    hasMultiplier l = T.any isDigit $ T.take 1 $ T.drop 1 $ snd $ T.breakOn "*" l
