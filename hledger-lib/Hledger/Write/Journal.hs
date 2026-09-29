{-|
Rendering a journal's items back to journal format, reproducing the
original journal file(s). Used by print --export.
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Hledger.Write.Journal (
  ItemRenderer(..),
  journalItemRenderer,
  journalItemsAsText,
) where

import Data.List (mapAccumL)
import Data.Map qualified as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Builder qualified as TB
import Text.Megaparsec.Pos (SourcePos(..), unPos)

import Hledger.Data.Types

-- | How to render each kind of journal item in some output format.
data ItemRenderer = ItemRenderer
  { irTransaction  :: Transaction -> Text  -- ^ render a transaction, without a trailing blank line
  , irDirective    :: Text -> Maybe Text   -- ^ render a directive given as source text, or drop it (Nothing)
  , irComment      :: Text -> Text         -- ^ render a top-level comment line
  , irCommentBlock :: Text -> Text         -- ^ render a comment ... end comment block
  }

-- | An item renderer for hledger's journal format, reproducing directives and comments as written,
-- and rendering transactions with the given showTransaction-like function
-- (whose trailing blank line is removed).
journalItemRenderer :: (Transaction -> Text) -> ItemRenderer
journalItemRenderer showtxn = ItemRenderer
  { irTransaction  = \t -> let s = showtxn t in fromMaybe s $ T.stripSuffix "\n" s
  , irDirective    = Just
  , irComment      = id
  , irCommentBlock = id
  }

-- | Render journal items as journal text, reproducing the journal file(s) they were parsed from,
-- with transactions rendered from the given (possibly filtered and processed) transactions.
--
-- Directive, comment line and comment block items are rendered as the item renderer specifies
-- (verbatim, for hledger's journal format).
-- Non-exported directives are dropped. Include lines are dropped too, and the included file's
-- items follow inline, beginning a new block (so eg there is a blank line between the entries
-- of adjacent included files).
-- Each transaction placeholder is replaced by the rendering of the next given transaction
-- with that source position, or by nothing if there is none (eg it was filtered out).
-- Any transactions not matching a placeholder (eg from non-journal files) are added at the end,
-- in source position order.
--
-- Blank lines are normalised: each transaction, and each group of adjacent directive/comment
-- items (as delimited by blank lines in the source), is a block, and blocks are separated
-- by exactly one blank line. A final transaction is also followed by a blank line, as in
-- ordinary print output.
journalItemsAsText :: ItemRenderer -> [JournalItem] -> [Transaction] -> TL.Text
journalItemsAsText ItemRenderer{..} items txns =
  TB.toLazyText $ renderBlocks $ mergeGroups $ concat blockss <> map txnBlock (concat $ M.elems remaining)
  where
    -- transactions queued by source position, in the given order
    txnsbypos = M.map reverse $ M.fromListWith (++) [(posKey $ fst $ tsourcepos t, [t]) | t <- txns]
    -- A map key comparing line and column before the file path, since comparing
    -- SourcePos directly compares the (usually identical) file paths first, which is slow.
    posKey (SourcePos f l c) = (unPos l, unPos c, f)
    txnBlock = Txn . TB.fromText . irTransaction
    linesBlock = Lines . TB.fromText

    -- Convert each item to a block (or none), consuming the queued transactions.
    -- (Keep this pattern binding flat, so the final state doesn't retain the blocks list.)
    (remaining, blockss) = mapAccumL toBlock txnsbypos items
    toBlock m item = case item of
      JITransaction pos -> case M.lookup k m of
          Just (t:ts) -> (M.insert k ts m, [txnBlock t])
          _           -> (m, [Break])
        where k = posKey pos
      JIBlank                  -> (m, [Break])
      JIComment t              -> (m, [linesBlock $ irComment t])
      JICommentBlock t         -> (m, [linesBlock $ irCommentBlock t])
      JIDirective t            -> (m, map linesBlock $ maybe [] pure $ irDirective t)
      JINonExportedDirective _ -> (m, [])
      JIInclude _              -> (m, [Break])  -- the included file's items begin a new block

-- | An output block: a group of directive/comment lines, a transaction, or a break between groups.
data Block = Lines TB.Builder | Txn TB.Builder | Break

-- | Merge adjacent line groups, and drop the breaks.
mergeGroups :: [Block] -> [Block]
mergeGroups (Lines a : Lines b : bs) = mergeGroups (Lines (a <> b) : bs)
mergeGroups (Break : bs)             = mergeGroups bs
mergeGroups (b : bs)                 = b : mergeGroups bs
mergeGroups []                       = []

-- | Render blocks separated by single blank lines. A final transaction is also
-- followed by a blank line, like ordinary print output; a final line group is not.
renderBlocks :: [Block] -> TB.Builder
renderBlocks []        = mempty
renderBlocks [Lines b] = b
renderBlocks (b : bs)  = blockBuilder b <> TB.singleton '\n' <> renderBlocks bs
  where
    blockBuilder (Lines b') = b'
    blockBuilder (Txn b')   = b'
    blockBuilder Break      = mempty
