{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ParallelListComp  #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE TupleSections     #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE ViewPatterns #-}
{-|

The @roi@ command prints internal rate of return and time-weighted rate of return for an investment.

-}

module Hledger.Cli.Commands.Roi (
  roimode
  , roi
) where

import Control.Monad
import Data.Time.Calendar
import Text.Printf
import Data.Bifunctor (second)
import Data.List
import Numeric.RootFinding
import Data.Decimal
import Data.Set qualified as S
import Data.Text qualified as T
import Data.Text.Lazy.IO qualified as TL
import System.Console.CmdArgs.Explicit as CmdArgs

import Text.Tabular.AsciiWide as Tab

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Utils (printTitle, warnIfLargeMultiPeriodReport)


roimode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Roi.txt")
  [flagNone ["cashflow"] (setboolopt "cashflow") "show all amounts that were used to compute returns"
  ,flagReq ["investment"] (\s opts -> Right $ setopt "investment" s opts) "QUERY"
    "query to select your investment transactions"
  ,flagReq ["profit-loss","pnl"] (\s opts -> Right $ setopt "pnl" s opts) "QUERY"
    "query to select profit-and-loss or appreciation/valuation transactions (optional)"
  ]
  cligeneralflagsgroups1
  hiddenflags
  ([], Just $ argsFlag "[QUERY]")

-- One reporting span,
data OneSpan = OneSpan
  Day -- start date, inclusive
  Day   -- end date, exclusive
  MixedAmount -- value of investment at the beginning of day on spanBegin_
  MixedAmount -- value of investment at the end of day on spanEnd_
  [(Day,MixedAmount)] -- all deposits and withdrawals (but not changes of value) in the DateSpan [spanBegin_,spanEnd_)
  [(Day,MixedAmount)] -- all PnL changes of the value of investment in the DateSpan [spanBegin_,spanEnd_)
 deriving (Show)

roi ::  CliOpts -> Journal -> IO ()
roi CliOpts{rawopts_=rawopts, reportspec_=rspec@ReportSpec{_rsReportOpts=ropts@ReportOpts{..}}} j = do
  warnIfLargeMultiPeriodReport rspec j
  printTitle ropts
  -- We may be converting posting amounts to value, per hledger_options.m4.md "Effect of --value on reports".
  let
    -- lbl = lbl_ "roi"
    today = _rsDay rspec
    priceOracle = journalPriceOracle infer_prices_ j
    styles = journalCommodityStylesWith HardRounding j
    mixedAmountValue periodlast date =
        -- These calculations can generate very precise decimals. To avoid showing too many digits:
        -- If we have no style for the valuation commodity, generate one that will limit the precision ?
        -- But it's not easy to find out the valuation commodity (or commodities) here if it's implicit,
        -- as that information is buried in the price graph.
        -- Instead, do what we don't like to do: hard code a max precision, overriding commodity styles.
        mixedAmountSetPrecisionMax defaultMaxDisplayPrecision
      . maybe id (mixedAmountApplyValuation priceOracle styles periodlast today date) value_
      . maybe id (mixedAmountToCost styles) conversionop_

  let
    wd = whichDate ropts
    showCashFlow = boolopt "cashflow" rawopts
    prettyTables = pretty_
    makeQuery flag = do
        q <- either usageError (return . fst) . parseQuery today . T.pack $ stringopt flag rawopts
        return . simplifyQuery . queryExpandCurAliases j $ And [queryFromFlags ropts{period_=PeriodAll}, q]
    cantCompute msg = error' $ msg ++ " - will be unable to compute the rates of return"

  investmentsQuery <- makeQuery "investment"
  pnlQuery         <- case maybestringopt "pnl" rawopts of
                         Nothing -> return None
                         Just _  -> makeQuery "pnl"

  when (pnlQuery == Any) $
    cantCompute "Need some transactions classed as investment and not pnl, but the pnl query matches any transaction"

  let
    filteredj = filterJournalTransactions investmentsQuery j
    trans = dbg3 "investments" $ jtxns filteredj

  when (null trans) $
    error' "No relevant transactions found. Check your investments query"

  let (fullPeriodDateSpan, mspans) = reportSpan filteredj rspec

  let err = cantCompute "Undefined start or end of the period"
      spans = maybe err (map (second (addDays 1)) . dayPartitionToList) mspans
      fullPeriod = case fullPeriodDateSpan of
        DateSpan (Just b) (Just e) -> (fromEFDay b, fromEFDay e)
        _ -> err

  let processSpan (b, e) = do
        -- Spans are [begin,end), and end is 1 day after the actual end date we are interested in
        let
          spn = DateSpan (Just $ Exact b) (Just $ Exact e)

          cashFlowApplyCostValue = map (\(d,amt) -> (d,mixedAmountValue e d amt))

          valueBefore = dbg3 "valueBefore" $
            mixedAmountValue e b $
            total trans (And [ investmentsQuery
                             , Date (DateSpan Nothing (Just $ Exact b))])

          valueAfter  = dbg3 "valueAfter" $
            mixedAmountValue e e $
            total trans (And [investmentsQuery
                             , Date (DateSpan Nothing (Just $ Exact e))])

          cashFlow = dbg3 "cashFlow" $
            cashFlowApplyCostValue $
            calculateCashFlow wd trans (And [ Not investmentsQuery
                                            , Not pnlQuery
                                            , Date spn ] )

          pnl = dbg3 "pnl" $
            cashFlowApplyCostValue $
            calculateCashFlow wd trans (And [ Not investmentsQuery
                                            , pnlQuery
                                            , Date spn ] )

          spanCommodities = dbg3 "spanCommodities" $
            S.unions $ (maCommodities valueBefore) : (maCommodities valueAfter) : map (maCommodities.snd) (cashFlow ++ pnl)

          thisSpan = dbg3 "processing span" $
                     OneSpan b e valueBefore valueAfter cashFlow pnl

        when (S.size spanCommodities > 1) $
          multiCommodityError $ "Period " ++ show (b,e) ++ " has multiple commodities: " ++ (T.unpack $ T.intercalate ", " $ map showCommoditySymbol (S.toList spanCommodities))

        let pDirectiveDates =
              sort . nub . map pddate $
              filter (\pd -> pddate pd >= b && pddate pd < e) $
              jpricedirectives j
        irr <- internalRateOfReturn styles showCashFlow prettyTables thisSpan
        (periodTwr, annualizedTwr) <- timeWeightedReturn styles showCashFlow prettyTables investmentsQuery trans mixedAmountValue pDirectiveDates thisSpan
        let cashFlowAmt = maNegate . maSum $ map snd cashFlow
        let smallIsZero x = if abs x < 0.01 then 0.0 else x
        return [ showDate b
               , showDate (addDays (-1) e)
               , T.pack $ showMixedAmountOneLineWithoutCost False $ styleAmounts styles $ valueBefore
               , T.pack $ showMixedAmountOneLineWithoutCost False $ styleAmounts styles $ cashFlowAmt
               -- , T.pack $ showMixedAmount $
               --   -- dbg0With (lbl "cashflow after styling".showMixedAmountOneLine) $
               --   mapMixedAmount (amountSetFullPrecisionUpTo (Just defaultMaxDisplayPrecision)) $
               --   styleAmounts (styles
               --                 -- & dbg0With (lbl "styles".show))
               --   cashFlowAmt
               --   -- & dbg0With (lbl "cashflow before styling".showMixedAmountOneLine)
               , T.pack $ showMixedAmountOneLineWithoutCost False $ styleAmounts styles $ valueAfter
               , T.pack $ showMixedAmountOneLineWithoutCost False $ styleAmounts styles $ (valueAfter `maMinus` (valueBefore `maPlus` cashFlowAmt))
               , T.pack $ printf "%0.2f%%" $ smallIsZero irr
               , T.pack $ printf "%0.2f%%" $ smallIsZero periodTwr
               , T.pack $ printf "%0.2f%%" $ smallIsZero annualizedTwr ]

  periodRows <- forM spans processSpan
  totalRow <- case periodRows of
    [singleRow] -> return singleRow
    _           -> processSpan fullPeriod

  let rowTitles = Tab.Group Tab.NoLine (map (Header . T.pack . show) (take (length periodRows) [1..]))

  let isSingleSpan = length spans == 1

  let table = Table
              (if isSingleSpan
                then rowTitles
                else Tab.Group Tab.SingleLine  [ rowTitles, Tab.Group Tab.NoLine [ Header "Total" ]]
              )
              (Tab.Group Tab.DoubleLine
               [ Tab.Group Tab.SingleLine [Header "Begin", Header "End"]
               , Tab.Group Tab.SingleLine [Header "Value (begin)", Header "Cashflow", Header "Value (end)", Header "PnL"]
               , Tab.Group Tab.SingleLine [Header "IRR"]
               , Tab.Group Tab.SingleLine [Header "TWR/period", Header "TWR/year"]])
              (if isSingleSpan then periodRows else periodRows ++ [totalRow])

  TL.putStrLn $ Tab.render prettyTables id id id table


-- One window of the TWR algorithm,
data ActivityWindow = ActivityWindow
  { awStart     :: Day  -- start date
  , awEnd       :: Day  -- end date
  , awVStart    :: Decimal -- value of investment at the start date
  , awVEnd      :: Decimal -- value of investment at the end date
  , awCashFlows :: [(Day, Decimal)]  -- cash flows in (awStart, awEnd]: strictly after start, up to and including end
  } deriving (Show)

timeWeightedReturn _styles showCashFlow prettyTables investmentsQuery trans mixedAmountValue pDirectiveDates (OneSpan begin end _valueBeforeAmt _valueAfterAmt cashflows pnls) = do
  let investmentPostings = concatMap (filter (matchesPosting investmentsQuery) . realPostings) trans

      totalInvestmentPostingsTill date = sumPostings $ filter (matchesPosting (Date (DateSpan Nothing (Just $ Exact date)))) investmentPostings

      -- filter span is (-infinity, date+1), which gives us effectively (-infinity, date]
      valueAfterDate date = unMix $ mixedAmountValue end date $ totalInvestmentPostingsTill (addDays 1 date)

  let pnlDates            = map fst pnls
      sortedValDates      = sort . nub $ [begin, addDays (-1) end] ++ pDirectiveDates ++ pnlDates
      cashFlowsForWindows = sortOn fst [(d, -(unMix ma)) | (d, ma) <- cashflows]
      windows             = dbg3 "activityWindows" $
                            segmentIntoWindows sortedValDates cashFlowsForWindows valueAfterDate
      windowRets          = map computeWindowReturn windows
      twr                 = dbg3 "twr" $
                            foldl' (\acc r -> (1+acc)*(1+r)-1) 0 windowRets
      years = fromIntegral (diffDays end begin) / 365.25 :: Double
      periodTWR     = roundTo 2 (100 * realToFrac twr :: Decimal)
      annualizedTWR = 100 * ((1 + twr) ** (1 / years) - 1) :: Double

  when showCashFlow $ do
    printf "\nTWR activity windows for period %s - %s\n"
      (showDate begin) (showDate (addDays (-1) end))
    let showDecimalT = T.pack . showDecimal
    TL.putStr $ Tab.render prettyTables T.pack id id
      (Table
       (Tab.Group Tab.NoLine [Header (show n) | n <- [1..length windows]])
       (Tab.Group DoubleLine
         [ Tab.Group Tab.SingleLine [Tab.Header "Begin", Tab.Header "End"]
         , Tab.Group Tab.SingleLine [Tab.Header "Value (begin)",   Tab.Header "Value (end)"]
         , Tab.Group Tab.SingleLine [Tab.Header "# flows"]
         , Tab.Group Tab.SingleLine [Tab.Header "Return, %"]])
       [ [ showDate (awStart w), showDate (awEnd w)
         , showDecimalT (roundTo 8 (awVStart w))
         , showDecimalT (roundTo 8 (awVEnd w))
         , T.pack (show (length (awCashFlows w)))
         , showDecimalT (roundTo 2 (realToFrac rate * 100)) ]
       | (w, rate) <- zip windows windowRets ])
    printf "Total period TWR: %s%%.\nPeriod: %.2f years.\nAnnualized TWR: %.2f%%\n\n"
      (showDecimal periodTWR) years annualizedTWR

  return ((realToFrac periodTWR) :: Double, annualizedTWR)

internalRateOfReturn styles showCashFlow prettyTables (OneSpan begin end valueBefore valueAfter cashFlow _pnl) = do
  let prefix = (begin, maNegate valueBefore)

      postfix = (end, valueAfter)

      totalCF = filter (maIsNonZero . snd) $ prefix : (sortOn fst cashFlow) ++ [postfix]

  when showCashFlow $ do
    printf "\nIRR cash flow for %s - %s\n" (showDate begin) (showDate (addDays (-1) end))
    let (dates, amts) = unzip totalCF
    TL.putStrLn $ Tab.render prettyTables id id id
      (Table
       (Tab.Group Tab.NoLine (map (Header . showDate) dates))
       (Tab.Group Tab.SingleLine [Header "Amount"])
       (map ((:[]) . T.pack . showMixedAmountOneLineWithoutCost False . styleAmounts styles) amts))

  -- 0% is always a solution, so require at least something here
  case totalCF of
    [] -> return 0
    _  -> return $
            (solveIRR (interestSum end totalCF)
              "Equation for Internal Rate of Return (IRR) can not be solved.\n\
              \  Possible causes: IRR is huge (>1000000%), balance of investment becomes negative at some point in time."
              "Equation for Internal Rate of Return (IRR) can not be solved.\n\
              \  Either search does not converge to a solution, or converges too slowly."
            - 1) * 100

type CashFlow = [(Day, MixedAmount)]

interestSum :: Day -> CashFlow -> Double -> Double
interestSum referenceDay cf rate = sum $ map go cf
  where go (t,m) = realToFrac (unMix m) * rate ** (fromIntegral (referenceDay `diffDays` t) / 365.25)

-- Note: Holdings.hs's xirrPct duplicates this solver setup and
-- interestSum's rate convention; keep them in sync, or extract a
-- shared helper.
solveIRR :: (Double -> Double) -> String -> String -> Double
solveIRR npv errNotBracketed errSearchFailed =
  case ridders (RiddersParam 100 (AbsTol 0.00001))
               (0.000000000001, 10000)
               npv of
    Root s       -> s
    NotBracketed -> error' errNotBracketed
    SearchFailed -> error' errSearchFailed

calculateCashFlow :: WhichDate -> [Transaction] -> Query -> CashFlow
calculateCashFlow wd trans query =
  [ (postingDateOrDate2 wd p, pamount p) | p <- concatMap (filter (matchesPosting query) . realPostings) trans, maIsNonZero (pamount p) ]

total :: [Transaction] -> Query -> MixedAmount
total trans query = sumPostings (concatMap (filter (matchesPosting query) . realPostings) trans)

unMix :: MixedAmount -> Quantity
unMix a =
  case (unifyMixedAmount a) of
    Just a' -> aquantity a'
    Nothing -> multiCommodityError $ "Amounts could not be converted to a single commodity: " ++ show (map showAmount $ amounts a)

multiCommodityError msg = error' $ msg ++
    "\nConsider using --value to force all costs to be in a single commodity." ++
    "\nFor example, \"--value=end,<commodity> --infer-market-prices\", where commodity is the one that you want to value the investment in."

-- Show Decimal rounded to two decimal places, unless it has less places already. This ensures that "2" won't be shown as "2.00"
showDecimal :: Decimal -> String
showDecimal d = if d == rounded then show d else show rounded
  where
    rounded = roundTo 2 d

-- segmentIntoWindows valueDates cashflows valueFunc will split cashflows into a set of
-- ActivityWindows, bracketed by some dates from valueDates. In theory, every interval
-- between valueDates should define ActivityWindow, but for performance reasons we merge
-- adjacent windows together if they don't contain any cashflows.
-- Precondition: valueDates must be strictly increasing (no duplicates); duplicate dates
-- produce zero-length windows and a divide-by-zero in windowNPV.
segmentIntoWindows :: [Day] -> [(Day, Decimal)] -> (Day -> Decimal) -> [ActivityWindow]
segmentIntoWindows []         _   _       = []
segmentIntoWindows [_]        _   _       = []
segmentIntoWindows (startDate:rest) cashflows valueAt = go startDate rest cashflows
  where
    go _  []     _    = []
    go s  [d]    cfs_ =
      let (here, _) = span (\(cd,_) -> cd <= d) cfs_
          -- cd > s: CFs on s are already in awVStart (valueAfterDate s); including
          -- them here would double-count. They earn zero return as end-boundary CFs
          -- in the preceding window.
          inside    = filter (\(cd,_) -> cd > s) here
      in [ActivityWindow s d (valueAt s) (valueAt d) inside]
    go s  (d:ds) cfs_ =
      let (here, later) = span (\(cd,_) -> cd <= d) cfs_
          -- cd > s: same reasoning as above
          inside        = filter (\(cd,_) -> cd > s) here
      in if null inside
         then case ds of
                (d2:ds2) ->
                  let (here2, later2) = span (\(cd,_) -> cd <= d2) later
                      inside2         = filter (\(cd,_) -> cd > d) here2
                  in if null inside2
                     then go s (d2:ds2) later   -- next window does not have cash flows: compress (skip d)
                     else ActivityWindow s d (valueAt s) (valueAt d) []
                          : ActivityWindow d d2 (valueAt d) (valueAt d2) inside2
                          : go d2 ds2 later2
         else ActivityWindow s d (valueAt s) (valueAt d) inside
              : go d ds later

-- Compute Net Present Value of the ActivityWindow given discount rate r
windowNPV :: ActivityWindow -> Double -> Double
windowNPV w r =
  let d       = fromIntegral (awEnd w `diffDays` awStart w)
      vsTerm  = -(realToFrac (awVStart w)) * r
      cfTerms = sum [ -(realToFrac cf)
                      * r ** (fromIntegral (awEnd w `diffDays` t) / d)
                    | (t, cf) <- awCashFlows w ]
      veTerm  = realToFrac (awVEnd w)
  in vsTerm + cfTerms + veTerm

windowIRR :: ActivityWindow -> Double
windowIRR w =
  solveIRR (windowNPV w)
    ("Cannot compute window IRR for "
     ++ T.unpack (showDate (awStart w)) ++ " - " ++ T.unpack (showDate (awEnd w)) ++ ".\n"
     ++ "  Possible cause: investment balance becomes negative within this window.")
    ("Window IRR search did not converge for "
     ++ T.unpack (showDate (awStart w)) ++ " - " ++ T.unpack (showDate (awEnd w)) ++ ".")
  - 1

computeWindowReturn :: ActivityWindow -> Double
computeWindowReturn w
  | null (awCashFlows w) =
      if awVStart w == 0 then 0
      else realToFrac (awVEnd w / awVStart w) - 1
  | awVStart w == 0, all ((== awEnd w) . fst) (awCashFlows w) = 0  -- zero starting value and all flows on the end date: 0% return, IRR is undefined
  | otherwise = windowIRR w
