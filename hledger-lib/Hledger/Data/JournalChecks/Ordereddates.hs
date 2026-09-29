module Hledger.Data.JournalChecks.Ordereddates (
  journalCheckOrdereddates
)
where

import Control.Monad (forM)
import Data.List (groupBy)
import Text.Printf (printf)
import Data.Text qualified as T (pack, unlines)

import Hledger.Data.Errors (makeTransactionErrorExcerpt)
import Hledger.Data.Transaction (transactionFile)
import Hledger.Data.Types
import Hledger.Utils (textChomp)

journalCheckOrdereddates :: Journal -> Either String ()
journalCheckOrdereddates j = do
  let
    -- we check date ordering within each file, not across files
    -- note, relying on txns always being sorted by file here
    txnsbyfile = groupBy (\t1 t2 -> transactionFile t1 == transactionFile t2) $ jtxns j
    compare' a b = tdate a <= tdate b
  (const $ Right ()) =<< (forM txnsbyfile $ \ts ->
    case checkTransactions compare' ts of
      FoldAcc{fa_previous=Nothing} -> Right ()
      FoldAcc{fa_error=Nothing}    -> Right ()
      FoldAcc{fa_error=Just t, fa_previous=Just tprev} -> Left $ printf
        ("%s:%d:\n%s\nOrdered dates checking is enabled, and this transaction's\n"
          ++ "date (%s) is out of order with the previous transaction.\n"
          ++ "Consider moving this entry into date order, or adjusting its date.")
        f l ex (show $ tdate t)
        where
          (_,_,_,ex1) = makeTransactionErrorExcerpt tprev (const Nothing)
          (f,l,_,ex2) = makeTransactionErrorExcerpt t finderrcols
          -- separate the two excerpts by an empty line, which flycheck-hledger accepts between excerpts
          ex = T.unlines [textChomp ex1, T.pack "", textChomp ex2]
          finderrcols _t = Just (1, Just 10)
    )

data FoldAcc a b = FoldAcc
 { fa_error    :: Maybe a
 , fa_previous :: Maybe b
 }

checkTransactions :: (Transaction -> Transaction -> Bool)
  -> [Transaction] -> FoldAcc Transaction Transaction
checkTransactions compare' = foldWhile f FoldAcc{fa_error=Nothing, fa_previous=Nothing}
  where
    f current acc@FoldAcc{fa_previous=Nothing} = acc{fa_previous=Just current}
    f current acc@FoldAcc{fa_previous=Just previous} =
      if compare' previous current
      then acc{fa_previous=Just current}
      else acc{fa_error=Just current}

foldWhile :: (a -> FoldAcc a b -> FoldAcc a b) -> FoldAcc a b -> [a] -> FoldAcc a b
foldWhile _ acc [] = acc
foldWhile fold acc (a:as) =
  case fold a acc of
   acc'@FoldAcc{fa_error=Just _} -> acc'
   acc' -> foldWhile fold acc' as
