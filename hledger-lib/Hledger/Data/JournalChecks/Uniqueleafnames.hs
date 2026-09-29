{-# LANGUAGE OverloadedStrings #-}

module Hledger.Data.JournalChecks.Uniqueleafnames (
  journalCheckUniqueleafnames
)
where

import Data.Function (on)
import Data.List (groupBy, sortBy)
import Data.Text (Text)
import Data.Text qualified as T
import Safe (headErr)
import Text.Printf (printf)

import Hledger.Data.AccountName (accountLeafName)
import Hledger.Data.Errors (makePostingErrorExcerpt)
import Hledger.Data.Journal (journalPostings, journalAccountNamesUsed)
import Hledger.Data.Posting (isVirtual)
import Hledger.Data.Types
import Hledger.Utils (chomp, textChomp)

-- | Check that all the journal's postings are to accounts with a unique leaf name.
-- Otherwise, return an error message for the first offending posting.
journalCheckUniqueleafnames :: Journal -> Either String ()
journalCheckUniqueleafnames j = do
  -- find all duplicate leafnames, and the full account names they appear in
  case finddupes $ journalLeafAndFullAccountNames j of
    [] -> Right ()
    -- pick the first duplicated leafname and show the transactions of
    -- the first two postings using it, highlighting the second as the error.
    (leaf,fulls):_ ->
      case filter ((`elem` fulls).paccount) $ journalPostings j of
        ps@(p:p2:_) -> Left $ chomp $ printf
          ("%s:%d:\n%s\nChecking for unique account leaf names is enabled, and\n"
          ++"account leaf name %s is not unique.\n"
          ++"It appears in these account names, which are used in %d places:\n%s"
          ++"\nConsider changing these account names so their last parts are different."
          )
          f l ex (show leaf) (length ps) accts
          where
            -- t = fromMaybe nulltransaction ptransaction  -- XXX sloppy
            (_,_,_,ex1) = makePostingErrorExcerpt p (\_ _ _ -> Nothing)
            (f,l,_,ex2) = makePostingErrorExcerpt p2 finderrcols
            -- separate the two excerpts by an empty line, which flycheck-hledger accepts between excerpts
            ex = T.unlines [textChomp ex1, T.pack "", textChomp ex2]
            finderrcols p' _ _ = Just (col, Just col2)
              where
                a = paccount p'
                alen = T.length a
                llen = T.length $ accountLeafName a
                col = 5 + (if isVirtual p' then 1 else 0) + alen - llen
                col2 = col + llen - 1
            accts = T.unlines fulls

        _ -> Right ()  -- shouldn't happen

finddupes :: (Ord leaf, Eq full) => [(leaf, full)] -> [(leaf, [full])]
finddupes leafandfullnames = zip dupLeafs dupAccountNames
  where
    dupAccountNames = map (map snd) dupes
    dupLeafs = case dupes of
      [] -> []
      _  -> map (fst . headErr) dupes  -- PARTIAL headErr succeeds because of pattern
    dupes = fnddupes leafandfullnames
      where
        fnddupes = filter ((> 1) . length)
          . groupBy ((==) `on` fst)
          . sortBy (compare `on` fst)

journalLeafAndFullAccountNames :: Journal -> [(Text, AccountName)]
journalLeafAndFullAccountNames = map leafAndAccountName . journalAccountNamesUsed
  where leafAndAccountName a = (accountLeafName a, a)
