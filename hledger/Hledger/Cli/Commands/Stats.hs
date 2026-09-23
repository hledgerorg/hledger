{-|

Print some statistics for the journal.

-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RecordWildCards #-}

module Hledger.Cli.Commands.Stats (
  statsmode
 ,stats
)
where

import Control.Monad (when)
import Data.Default (def)
import Data.List (intercalate, nub, sortOn)
import Data.List.Extra (nubSort)
import Data.Map qualified as Map
import Data.Maybe (fromMaybe)
import Data.HashSet (size, fromList)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock.POSIX (getPOSIXTime)
import GHC.Stats
import GitHash (tGitInfoCwdTry)
import System.Console.CmdArgs.Explicit hiding (Group)
import System.FilePath (takeFileName)
import System.Mem (performMajorGC)
import Text.Printf (printf)
import Text.Tabular.AsciiWide

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Utils (writeOutput, printTitle)
import Hledger.Cli.Version (packageversion, versionStringWith)


statsmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Stats.txt")
  [ flagNone ["oneline"] (setboolopt "oneline") "show a single line of output"
      -- Cli.hs converts -1 to --depth=1, no point giving it another name here
  , flagNone ["verbose","v"] (setboolopt "verbose") "show more detailed output"
  ,flagReq  ["output-file","o"] (\s opts -> Right $ setopt "output-file" s opts) "FILE" "write output to FILE."
  ]
  cligeneralflagsgroups1
  hiddenflags
  ([], Just $ argsFlag "[QUERY]")

-- like Register.summarisePostings
-- | Print various statistics for the journal.
stats :: CliOpts -> Journal -> IO ()
stats opts@CliOpts{rawopts_=rawopts, reportspec_=rspec, progstarttime_} j = do
  printTitle $ _rsReportOpts rspec
  t <- getPOSIXTime
  -- the first lines - general journal stats for one or more periods
  let
    today = _rsDay rspec
    oneline = intopt "depth" rawopts == 1
    verbose = boolopt "verbose" rawopts
    q = _rsQuery rspec
    l = ledgerFromJournal q j
    intervalspans = snd $ reportSpanBothDates j rspec
    ismultiperiod = length intervalspans > 1
    (txts, tnums) = unzip . map (showLedgerStats verbose l today) $ maybeDayPartitionToDateSpans intervalspans
    out1 = (if ismultiperiod then id else init) $ unlines txts

  -- the last line - overall performance stats, with memory info if available,
  -- in human-friendly or machine-friendly format
  -- normal:
  --  Runtime stats       : 0.14 s elapsed, 7606 txns/s
  --  Runtime stats       : 0.14 s elapsed, 7606 txns/s, 6 MB live, 18 MB alloc
  -- oneline:
  --  SHORTVERSION(<SPC><TAB>VALUE[<SPC>DESC])+
  --  1.50.99<SPC><TAB>hledger 1.50.99-g0835a2485-20251119, mac-aarch64<SPC><TAB>2025.journal<SPC><TAB>1.99 s elapsed<SPC><TAB>524 txns/s
  --  1.50.99<SPC><TAB>hledger 1.50.99-g0835a2485-20251119, mac-aarch64<SPC><TAB>2025.journal<SPC><TAB>1.99 s elapsed<SPC><TAB>524 txns/s<SPC><TAB>788 MB live<SPC><TAB>2172 MB alloc
  -- 
  rtsstats <- getRTSStatsEnabled
  (maxlivemb, maxinusemb) <- if rtsstats
  then do
    -- do one last garbage collection; probably little effect, hopefully little wasted time
    performMajorGC
    RTSStats{..} <- getRTSStats
    return (toMegabytes max_live_bytes, toMegabytes max_mem_in_use_bytes)
  else
    return (0,0)
  let
    (label, sep)
      | oneline   = (lstrip $ versionStringWith $$tGitInfoCwdTry False "" packageversion <> "\t", "\t")
      | otherwise = (printf "%-*s: " labelwidth ("Runtime stats" :: String), ", ")
    dt = t - progstarttime_
    tnum = sum tnums
    ss =
      [ takeFileName $ journalFilePath j | oneline ]
      <> [
       printf "%.2f s elapsed" (realToFrac dt :: Float)
      ,printf "%.0f txns/s" (fromIntegral tnum / realToFrac dt :: Float)
      ]
      <> if rtsstats then [
       printf "%0.0f MB live" maxlivemb
      ,printf "%0.0f MB alloc" maxinusemb
      -- printf "%0.0f MB avg live" (toMegabytes $ fromIntegral cumulative_live_bytes / fromIntegral major_gcs)
      ]
      else [
       "(add +RTS -T -RTS for more)"
      ]
    out2 = label <> intercalate sep ss <> "\n"

  when (not oneline) $ writeOutput opts out1
  when (oneline && debugLevel>0) $ do
    let tabstops = intercalate (replicate 7 ' ') (replicate 21 ".") <> "\n"
    writeOutput opts tabstops
  writeOutput opts $ (if ismultiperiod then "\n" else "") <> out2

toMegabytes n = realToFrac n / 1000000 ::Float  -- SI preferred definition, 10^6
-- toMebibytes n = realToFrac n / 1048576 ::Float  -- traditional computing definition, 2^20

labelwidth :: Int
labelwidth = 20  -- adjust to suit labels

-- | Generate multiline stats output, possibly verbose,
-- for the given ledger and date period and current date.
-- Also return the number of transactions in the period.
showLedgerStats :: Bool -> Ledger -> Day -> DateSpan -> (String, Int)
showLedgerStats verbose l today spn =
    (unlines $ map (TL.unpack . renderRow def{tableBorders=False, borderSpaces=False} . showRow) stts
    ,tnum)
  where
    showRow (label, val) = Group NoLine $ map (Header . textCell TopLeft)
      [fitText (Just w) (Just w) False True label `T.append` ": ", T.pack val]
    w = labelwidth
    -- w = maximum $ map (T.length . fst) stts
    (stts, tnum) = ([
       ("Main file", path' :: String) -- ++ " (from " ++ source ++ ")")
      ,("Included files", if verbose then unlines includedpaths else show (length includedpaths))
      ,("Txns span", printf "%s to %s (%d days)" (showstart spn) (showend spn) days)
      ,("Last txn", maybe "none" show lastdate ++ showelapsed lastelapsed)
      ,("Txns", printf "%d (%0.1f per day)" tnum txnrate)
      ,("Txns last 30 days", printf "%d (%0.1f per day)" tnum30 txnrate30)
      ,("Txns last 7 days", printf "%d (%0.1f per day)" tnum7 txnrate7)
      ,("Payees/descriptions", show $ size $ fromList $ map (tdescription) ts)
      ,("Accounts", printf "%d (depth %d)" acctnum acctdepth)
      ,("Commodities",   printf "%s%s" (show $ length cs)        (if verbose then " (" <> T.intercalate ", " cs <> ")" else ""))
      ,("Base currency",  basecurrency)
      ,("Market prices", printf "%s%s" (show $ length mktprices) (if verbose then " (" <> T.intercalate ", " mktpricecommodities <> ")" else ""))
    -- Txns this month     : %(monthtxns)s (last month in the same period: %(lastmonthtxns)s)
    -- Unmarked txns      : %(unmarked)s
    -- Days since reconciliation   : %(reconcileelapsed)s
    -- Days since last txn : %(recentelapsed)s
     ]
     ,tnum1)
       where
         j = ljournal l
         path' = if verbose then path else ".../" <> takeFileName path where path = journalFilePath j
         -- The guessed base currency: the journal's symbol, with its ISO
         -- 4217 code alongside when that differs, eg "$ (USD)"; or "none".
         basecurrency = case journalBaseCurrency j of
           Nothing -> "none"
           Just (sym, code) | sym == code -> T.unpack code
                            | otherwise   -> T.unpack $ sym <> " (" <> code <> ")"
         includedpaths = drop 1 $ journalFilePaths j
         ts = sortOn tdate $ filter (spanContainsDate spn . tdate) $ jtxns j
         as = nub $ map paccount $ concatMap tpostings ts
         cs = either error' Map.keys $ commodityStylesFromAmounts $ concatMap (amountsRaw . pamount) $ concatMap tpostings ts  -- PARTIAL:
         lastdate | null ts = Nothing
                  | otherwise = Just $ tdate $ last ts
         lastelapsed = fmap (diffDays today) lastdate
         showelapsed Nothing = ""
         showelapsed (Just dys) = printf " (%d %s)" dys' direction
                                   where dys' = abs dys
                                         unit = if dys' == 1 then "day" else "days" :: String
                                         direction | dys >= 0 = unit ++ " ago"
                                                   | otherwise = unit ++ " from now"
         tnum1 = length ts  -- Integer would be better
         showstart (DateSpan (Just efd) _) = show $ fromEFDay efd
         showstart _ = ""
         showend (DateSpan _ (Just efd)) = show $ fromEFDay efd
         showend _ = ""
         days = fromMaybe 0 $ daysInSpan spn
         txnrate | days==0 = 0
                 | otherwise = fromIntegral tnum1 / fromIntegral days :: Double
         tnum30 = length $ filter withinlast30 ts
         withinlast30 t = d >= addDays (-30) today && (d<=today) where d = tdate t
         txnrate30 = fromIntegral tnum30 / 30 :: Double
         tnum7 = length $ filter withinlast7 ts
         withinlast7 t = d >= addDays (-7) today && (d<=today) where d = tdate t
         txnrate7 = fromIntegral tnum7 / 7 :: Double
         acctnum = length as
         acctdepth | null as = 0
                   | otherwise = maximum $ map accountNameLevel as
         mktprices = jpricedirectives j
         mktpricecommodities = nubSort $ map pdcommodity mktprices
