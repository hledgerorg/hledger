#!/usr/bin/env stack
-- stack script --resolver nightly-2026-06-01
{-
generatejournal.hs NUMTXNS NUMACCTS ACCTDEPTH [--chinese|--mixed]

This generates synthetic journal data for benchmarking & profiling. It
prints a dummy journal on stdout, with NUMTXNS transactions, one per
day, using NUMACCTS account names with depths up to ACCTDEPTH. It will
also contain NUMACCTS P records, one per day. By default it uses only
ascii characters, with --chinese it uses wide chinese characters, or
with --mixed it uses both.
-}

module Main
where
import Data.Char
import Data.Decimal
import Data.List
import Data.Time.Calendar
import Data.Time.LocalTime
import Numeric
import Safe (tailErr)
import System.Environment
import Text.Printf
-- import Hledger.Utils.Debug

main = do
  rawargs <- getArgs
  let (opts,args) = partition (isPrefixOf "-") rawargs
  let [numtxns, numaccts, acctdepth] = map read args :: [Int]
  -- today <- getCurrentDay
  -- let (year,_,_) = toGregorian today
  let d = fromGregorian 2000 1 1
  let dates = iterate (addDays 1) d
  let accts = pair $ cycle $ take numaccts $ uniqueAccountNames opts acctdepth
  let comms  = cycle ['A'..'Z']
  let rates = [0.70, 0.71 .. 1.3]
  mapM_ (\(n,d,(a,b),c,p) -> putStr $ showtxn n d a b c p) $ take numtxns $ zip5 [1..] dates accts comms (drop 1 comms)
  mapM_ (\(d,rate) -> putStr $ showmarketprice d rate) $ take numtxns $ zip dates (cycle $ rates ++ init (tailErr (reverse rates)))  -- PARTIAL tailErr succeeds because non-null rates list

showtxn :: Int -> Day -> String -> String -> Char -> Char -> String
showtxn txnno date acct1 acct2 comm pricecomm =
    printf "%s transaction %d\n  %-40s  %2d %c%s\n  %-40s  %s %c\n\n" d txnno acct1 amt comm pricesymbol acct2 (show amt2) amt2comm
    where
      d = show date
      amt = txnno
      (amt2, amt2comm, pricesymbol)
        | txnno `rem` 3 == 0 = (fromIntegral (-amt) :: Decimal, comm, "")
        | txnno `rem` 3 == 1 = (fromIntegral (-amt) * rate, pricecomm, printf " @ %s %c" (show rate) pricecomm)
        | otherwise         = (fromIntegral (-amt), pricecomm, printf " @@ %s %c" (show amt) pricecomm)
      rate = 0.70 + 0.01 * fromIntegral (txnno `rem` 60) :: Decimal

showmarketprice :: Day -> Double -> String
showmarketprice date = printf "P %s A  %.2f B\n" (show date)

uniqueAccountNames :: [String] -> Int -> [String]
uniqueAccountNames opts depth =
  mkacctnames uniquenames
  where
    mkacctnames names = mkacctnamestodepth some ++ mkacctnames rest
      where
        (some, rest) = splitAt depth names
        -- mkacctnamestodepth ["a", "b", "c"] = ["a","a:b","a:b:c"]
        mkacctnamestodepth :: [String] -> [String]
        mkacctnamestodepth [] = []
        mkacctnamestodepth (a:as) = a : map ((a++":")++) (mkacctnamestodepth as)
    uniquenames
      | "--mixed" `elem` opts   = concat $ zipWith (\a b -> [a,b]) uniqueNamesHex uniqueNamesWide
      | "--chinese" `elem` opts = uniqueNamesWide
      | otherwise               = uniqueNamesHex

uniqueNamesHex = map hex [1..] where hex = flip showHex ""

uniqueNamesWide = concat [sequences n wideChars | n <- [1..]]

-- Get the sequences of specified size starting at each element of a list,
-- cycling it if needed to fill the last sequence. If the list's elements
-- are unique, then the sequences will be too.
sequences :: Show a => Int -> [a] -> [[a]]
sequences n l = go l
  where
    go [] = []
    go l' = s : go (tailErr l')  -- PARTIAL tailErr succeeds because of pattern
      where
        s' = take n l'
        s | length s' == n = s'
          | otherwise      = take n (l' ++ cycle l)

wideChars = map chr [0x3400..0x4db0]


pair :: [a] -> [(a,a)]
pair [] = []
pair [a] = [(a,a)]
pair (a:b:rest) = (a,b):pair rest

-- getCurrentDay :: IO Day
-- getCurrentDay = do
--     t <- getZonedTime
--     return $ localDay (zonedTimeToLocalTime t)

