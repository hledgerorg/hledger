#!/usr/bin/env stack
{- stack runghc
  --package hledger-lib
  --package text
-}
{- example of generating one CSV line per txn. assumes hledger-lib 1.0+ -}

import Control.Monad
import Data.Text qualified as T
import Data.List
import Hledger

main :: IO ()
main = do
  Right j <- readJournalFile Nothing Nothing False "examples/sample.journal"
  putStrLn $ intercalate ", " $ [
     "date"
    ,"description"
    ,"account1"
    ,"amount1"
    ,"account2"
    ,"amount2"
    ]
  forM_ (jtxns j) $ \t -> do
    let (p1:p2:_) = tpostings t
    putStrLn $ intercalate ", " $ map quoteIfNeeded [
       show $ tdate t
      ,T.unpack $ tdescription t
      ,T.unpack $ paccount p1
      ,show $ pamount p1
      ,T.unpack $ paccount p2
      ,show $ pamount p2
      ]
