{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE NamedFieldPuns #-}

module Hledger.Cli.Commands.Prices (
  pricesmode
 ,prices
)
where

import Data.List
import Data.Set qualified as S
import Data.Text qualified as T
import Data.Text.IO qualified as T
import Data.Time.Calendar (Day, DayOfWeek(..), dayOfWeek)
import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Utils (printTitle)
import System.Console.CmdArgs.Explicit
import Data.Maybe (mapMaybe)
import Data.Function ((&))
import Text.Printf (printf)

pricesmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Prices.txt")
  [flagNone ["show-reverse"] (setboolopt "show-reverse") "also show the prices inferred by reversing known prices"
  ,flagNone ["summary"] (setboolopt "summary") "summarise declared prices per commodity instead of listing them"
  ,flagNone ["locations"] (setboolopt "locations") "also show where prices where declared"
  ]
  cligeneralflagsgroups1
  (hiddenflags ++
  [flagNone ["costs"]                (setboolopt "infer-market-prices") "deprecated, use --infer-market-prices instead"
  ,flagNone ["inverted-costs"]       (setboolopt "show-reverse") "deprecated, use --show-reverse instead"
  ,flagNone ["infer-reverse-prices"] (setboolopt "show-reverse") "deprecated, use --show-reverse instead"
  ])
  ([], Just $ argsFlag "[QUERY]")

instance HasAmounts PriceDirective where
  styleAmounts styles pd = pd{pdamount=styleAmounts styles $ pdamount pd}

-- List market prices.
prices opts j = do
  printTitle $ _rsReportOpts $ reportspec_ opts
  let
    q       = _rsQuery $ reportspec_ opts
    showloc = boolopt "locations" (rawopts_ opts)
    styles  = journalCommodityStyles j
    render pd =
      showPriceDirective (styleAmounts styles pd)
      <> if showloc then locationComment pd else ""

    -- XXX duplicates logic in Hledger.Data.Valuation.makePriceGraph, keep synced

    declaredprices =
      -- dbg0 "declaredprices" $
      jpricedirectives j

    -- Use the location-preserving helper only when --locations is set,
    -- to avoid the per-directive record update otherwise.
    pricesfromcosts =
      -- dbg0 "pricesfromcosts" $
      concatMap (if showloc then postingPriceDirectivesWithLoc
                            else postingPriceDirectivesFromCost) $
      journalPostings j

    forwardprices =
      -- dbg0 "forwardprices" $
      if boolopt "infer-market-prices" (rawopts_ opts)
      then declaredprices `mergePriceDirectives` pricesfromcosts
      else declaredprices

    reverseprices =
      -- dbg0 "reverseprices" $
      mapMaybe reversePriceDirective forwardprices

    allprices =
      -- dbg0 "allprices" $
      if boolopt "show-reverse" (rawopts_ opts)
      then forwardprices `mergePriceDirectives` reverseprices
      else forwardprices

    filteredprices =
      -- dbg0 "filtered unsorted" $
      filter (matchesPriceDirective q) allprices

  if boolopt "summary" (rawopts_ opts)
    then printSummary j q (filter (matchesPriceDirective q) declaredprices)
    else mapM_ (T.putStrLn . render) $ sortOn pddate filteredprices

-- | Like 'postingPriceDirectivesFromCost', but tags each inferred
-- price directive with the source position of the parent transaction
-- (if known) so it can be reported by --locations.
postingPriceDirectivesWithLoc :: Posting -> [PriceDirective]
postingPriceDirectivesWithLoc p =
  [ pd{pdsourcepos = pos} | pd <- postingPriceDirectivesFromCost p ]
  where
    pos = maybe nullsourcepos (fst . tsourcepos) (ptransaction p)

-- | A trailing journal comment showing the file and line where a
-- price directive was declared or inferred. Reversed prices inherit
-- the source position of the directive they were derived from. Empty
-- only when no source position is available.
locationComment :: PriceDirective -> T.Text
locationComment PriceDirective{pdsourcepos=SourcePos fp l _}
  | null fp   = ""
  | otherwise = "  ; location: " <> T.pack fp <> ":" <> T.pack (show (unPos l))

-- | Per-commodity stats from the journal's declared price directives.
data PriceStats = PriceStats
  { psCommodity :: CommoditySymbol
  , psCount     :: Int
  , psEarliest  :: Maybe Day
  , psLatest    :: Maybe Day
  , psDays      :: S.Set Day   -- distinct price dates
  }

-- | Stats for one ISO commodity code, gathered from raw P directives.
-- Symbol variants (eg "$" / "USD") are grouped together via 'toCurrencyCode'.
priceStatsFor :: [PriceDirective] -> CurrencyCode -> PriceStats
priceStatsFor pds c =
  let xs  = filter ((== c) . toCurrencyCode . pdcommodity) pds
      dset = S.fromList (map pddate xs)
  in PriceStats c (length xs)
       (fst <$> S.minView dset)
       (fst <$> S.maxView dset)
       dset

isWeekday :: Day -> Bool
isWeekday d = case dayOfWeek d of
  Saturday -> False
  Sunday   -> False
  _        -> True

-- | Compact human duration: "45d", "11mo", "1y 3mo".
-- Approximates with 365-day years and 30-day months — display only.
compactDuration :: Int -> T.Text
compactDuration n
  | n < 60    = T.pack (show n) <> "d"
  | n < 365   = T.pack (show (n `div` 30)) <> "mo"
  | otherwise =
      let (y, r) = n `divMod` 365
          mo     = r `div` 30
      in T.pack (show y) <> "y" <>
         (if mo == 0 then "" else " " <> T.pack (show mo) <> "mo")

-- | The text for the period and coverage columns of a stats row.
-- Both are blank when the commodity has fewer than two prices.
-- Coverage is computed on a weekdays-only basis (Mon–Fri), so
-- weekday-only sources (eg FX) approach 100% rather than ~71%.
periodAndCoverage :: PriceStats -> (T.Text, T.Text)
periodAndCoverage ps@PriceStats{psEarliest=Just s, psLatest=Just e}
  | psCount ps < 2 = ("", "")
  | otherwise      = (compactDuration nDays, T.pack (printf "%.f%%" pct))
  where
    days      = [s..e]
    nDays     = length days
    weekdays  = filter isWeekday days
    nWeekdays = length weekdays
    nCovered  = length (filter (`S.member` psDays ps) weekdays)
    pct | nWeekdays == 0 = 0
        | otherwise      =
            fromIntegral nCovered / fromIntegral nWeekdays * 100 :: Double
periodAndCoverage _ = ("", "")

-- | Render the per-commodity summary table.
-- Lists every commodity used in the journal except the base currency,
-- normalised to ISO codes and deduplicated. The 'cur:' portion of the
-- query (if any) narrows the listed commodities. The supplied price
-- directives (already query-filtered by the caller) drive the counts.
printSummary :: Journal -> Query -> [PriceDirective] -> IO ()
printSummary j q pds = do
  let
    base    = journalBaseCurrencyCode j
    -- Just the cur: terms of the query; non-cur terms become Any so
    -- they don't reject every commodity.
    symq    = filterQuery queryIsCurOrSym q
    codes   = sort . nub . filter (/= base) . filter (matchesCommodity symq)
              . map toCurrencyCode
              $ journalCommoditiesUsed j
    rows    = map (statsRow . priceStatsFor pds) codes
    header  = ["Commodity", "Prices", "Earliest", "Latest", "Period", "Coverage"]
    aligns  = [AlignL, AlignR, AlignL, AlignL, AlignR, AlignR]
  T.putStr $ renderColumns aligns (header : rows)

statsRow :: PriceStats -> [T.Text]
statsRow ps =
  let (perTxt, covTxt) = periodAndCoverage ps
  in [ psCommodity ps
     , T.pack (show (psCount ps))
     , maybe "-" (T.pack . show) (psEarliest ps)
     , maybe "-" (T.pack . show) (psLatest ps)
     , perTxt
     , covTxt
     ]

data ColAlign = AlignL | AlignR

-- | Render a list of equal-length rows as a column-aligned plain-text
-- table, two spaces between columns, one row per line.
renderColumns :: [ColAlign] -> [[T.Text]] -> T.Text
renderColumns aligns rs =
  let widths = map (maximum . map T.length) (transpose rs)
      pad a w t = case a of AlignL -> T.justifyLeft w ' ' t
                            AlignR -> T.justifyRight w ' ' t
      renderRow r = T.stripEnd (T.intercalate "  " (zipWith3 pad aligns widths r))
  in T.unlines (map renderRow rs)

-- XXX performance
-- | Append any new price directives (with different from commodity,
-- to commodity, or date) from the second list to the first.
-- (Does not remove redundant prices from the first; just avoids adding more.)
mergePriceDirectives :: [PriceDirective] -> [PriceDirective] -> [PriceDirective]
mergePriceDirectives pds1 pds2 =
  pds1 ++ [ pd | pd <- pds2 , pdid pd `notElem` pds1ids ]
  where
    pds1ids = map pdid pds1
    pdid PriceDirective{pddate,pdcommodity,pdamount} = (pddate, pdcommodity, acommodity pdamount)

-- | Convert a market price directive to a corresponding one in the
-- opposite direction, if possible. (A price directive with a zero
-- price can't be reversed.)
--
-- The price's display precision will be set to show all significant
-- decimal digits (or if they appear infinite, a smaller default precision (8).
-- This is visible eg in the prices command's output.
--
reversePriceDirective :: PriceDirective -> Maybe PriceDirective
reversePriceDirective pd@PriceDirective{pdcommodity=c, pdamount=a}
  | amountIsZero a = Nothing
  | otherwise      = Just pd{pdcommodity=acommodity a, pdamount=a'}
    where
      lbl = lbl_ "reversePriceDirective"
      a' =
        amountSetFullPrecisionUpTo (Just defaultMaxDisplayPrecision) $
        invertAmount a{acommodity=c}
        & dbg9With (lbl "calculated reverse price".showAmount)
        -- & dbg9With (lbl "precision of reverse price".show.amountDisplayPrecision)
