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
import Data.Map qualified as M
import Data.Set qualified as S
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import System.Console.CmdArgs.Explicit as CmdArgs

import Text.Tabular.AsciiWide as Tab

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Utils (warnIfLargeMultiPeriodReport, withTitle, writeOutput)


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
roi opts@CliOpts{rawopts_=rawopts, reportspec_=rspec@ReportSpec{_rsReportOpts=ropts@ReportOpts{..}}} j = do
  warnIfLargeMultiPeriodReport rspec j
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
        return . simplifyQuery $ And [queryFromFlags ropts{period_=PeriodAll}, q]
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

    postingDay   = postingDateOrDate2 wd
    isInvestment = matchesPosting investmentsQuery
    isPnl p      = not (isInvestment p) && matchesPosting pnlQuery p

    -- The investment's holdings at the end of each day which changes them, accumulated once.
    holdingsByDay = M.fromAscList . drop 1 . scanl (\(_, acc) (d, a) -> (d, acc `maPlus` a)) (nulldate, nullmixedamt) . M.toAscList $
      M.fromListWith maPlus [ (postingDay p, pamount p) | t <- trans, p <- realPostings t, isInvestment p ]
    -- the investment's holdings at the end of this day
    holdingsAt d = maybe nullmixedamt snd $ M.lookupLE d holdingsByDay

    -- The unit prices of the investment's own purchases and sales, by commodity and date (the last one recorded on a
    -- date wins, as with --infer-market-prices), for valuing holdings which have no market price.
    -- (fromListWith passes the later entry first, and union keeps its first argument's entries.)
    tradePrices = M.fromListWith M.union
      [ (pdcommodity pd, M.singleton (postingDay p) (pdamount pd))
      | t <- trans, p <- realPostings t, isInvestment p, a <- amounts (pamount p)
      , Just pd <- [amountPriceDirectiveFromCost (postingDay p) a] ]
    -- the price of the investment's latest purchase or sale of this commodity, on or before this date
    latestTradePrice c d = M.lookup c tradePrices >>= fmap snd . M.lookupLE d

    -- The investment's cash flows from b to lastDay, measured from its own side: for each transaction and each date of
    -- its investment postings, the cost of those postings, less the transaction's profit and loss (counted on the first
    -- of those dates), valued with valueOn. So other postings in the same transaction (eg fees, or gains and losses on
    -- other holdings) don't count, and flows are dated like the changes they make to the investment.
    -- Deposits are negative and withdrawals positive, like the postings of the money that pays for them.
    investmentCashFlows valueOn b lastDay =
      [ InvestmentFlow d (tdescription t) cost gain (maNegate $ cost `maMinus` gain)
      | t <- trans
      , let ps     = realPostings t
            byDay  = M.fromListWith (flip (++)) [ (postingDay p, [p]) | p <- ps, isInvestment p ]
            pnlAmt = sumPostings (filter isPnl ps)
      , (i, (d, invps)) <- zip [0 :: Int ..] (M.toAscList byDay)
      , d >= b, d <= lastDay
      , let cost = valueOn d $ mixedAmountToCost styles ToCost $ sumPostings invps
            gain = if i == 0 then maNegate (valueOn d pnlAmt) else nullmixedamt
      , maIsNonZero (cost `maMinus` gain) ]

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
          -- the last day of the span, which --value=end and the value at the end of the span are valued on
          lastDay = addDays (-1) e

          cashFlowApplyCostValue = map (\(d,amt) -> (d,mixedAmountValue lastDay d amt))

          -- With valuation, the investment's value should end up in the same commodity as the cash flows and PnL, which
          -- are valued the same way (that need not be the one given to --value, if nothing converts to it).
          -- Without cash flows or PnL, it should be in the one given to --value.
          expectedCommodity = case value_ of
            Nothing -> Nothing
            Just vt -> case S.toList (S.unions $ map (maCommodities . snd) (otherFlows ++ pnl)) of
              [c] -> Just c
              []  -> valuationTypeValuationCommodity vt
              _   -> Nothing
          -- Value an amount of the investment on a date. Positions fully closed by then are dropped first. A commodity
          -- with no market price known on or before that date is valued at the price of the investment's latest purchase
          -- or sale of it (as --infer-market-prices would, but only from the investment's own transactions, and only when
          -- no market price is known). Its net cost would be wrong after a sale at a different price, and could even be
          -- negative.
          valueOn date amt0 =
            let amt      = dropClosedPositions amt0
                valued   = mixedAmountValue lastDay date amt
                unpriced = S.fromList [ acommodity a | Just c <- [expectedCommodity], a <- amounts valued
                                                     , acommodity a /= c, not (amountIsZero a) ]
                isUnpriced = (`S.member` unpriced) . acommodity
                valued'
                  | S.null unpriced = valued
                  | otherwise = mixedAmountValue lastDay date $ mixed
                      [ if isUnpriced a then maybe a (\pr -> pr{aquantity = aquantity pr * aquantity a}) (latestTradePrice (acommodity a) date) else a
                      | a <- amounts amt ]
            in checkValued (value_ >>= valuationTypeValuationCommodity) expectedCommodity date valued'

          -- the value at the start of the span is the value at the end of the previous day, so that it equals the value
          -- at the end of the previous span (except with --value=end, which values each span at its own end)
          valueBefore = dbg3 "valueBefore" $ valueOn (addDays (-1) b) $ holdingsAt (addDays (-1) b)

          valueAfter  = dbg3 "valueAfter" $ valueOn lastDay $ holdingsAt lastDay

          flowDetails = investmentCashFlows valueOn b lastDay
          cashFlow = dbg3 "cashFlow" $ [ (ifDate f, ifFlow f) | f <- flowDetails ]

          -- The other postings of the investment transactions, which are where the money comes from or goes to.
          -- Only used to tell which commodity the money is in, after valuation.
          otherFlows = dbg3 "otherFlows" $
            cashFlowApplyCostValue $ inSpan $
            calculateCashFlow wd trans (And [Not investmentsQuery, Not pnlQuery])

          pnl = dbg3 "pnl" $
            cashFlowApplyCostValue $ inSpan $
            calculateCashFlow wd trans (And [Not investmentsQuery, pnlQuery])

          -- postings dated (like the cash flows and holdings) within the span
          inSpan = filter (\(d, _) -> d >= b && d <= lastDay)

          spanCommodities = dbg3 "spanCommodities" $
            S.unions $ (maCommodities valueBefore) : (maCommodities valueAfter) : map (maCommodities.snd) (cashFlow ++ pnl)

          thisSpan = dbg3 "processing span" $
                     OneSpan b e valueBefore valueAfter cashFlow pnl

        when (S.size spanCommodities > 1) $
          multiCommodityError $ "Period " ++ show (b,e) ++ " has multiple commodities: " ++ (T.unpack $ T.intercalate ", " $ map showCommoditySymbol (S.toList spanCommodities))

        let -- show a quantity of the span's (single) commodity, styled
            showAmt q = T.pack $ showMixedAmountOneLineWithoutCost False $ styleAmounts styles $
              mixedAmount nullamt{acommodity = maybe "" id (S.lookupMin spanCommodities), aquantity = q}
        (irrdetails, eirr) <- internalRateOfReturn styles showCashFlow prettyTables flowDetails thisSpan
        (twrdetails, (periodTwr, annualizedTwr)) <- timeWeightedReturn showCashFlow prettyTables showAmt holdingsAt valueOn thisSpan
        let cashFlowAmt = maNegate . maSum $ map snd cashFlow
        let smallIsZero x = if abs x < 0.01 then 0.0 else x
        let spanrow irr = [ showDate b
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
        return (irrdetails <> twrdetails, spanrow <$> eirr)

  (perioddetails, periodRows) <- unzip <$> forM spans processSpan
  (totaldetails, totalRow) <- case periodRows of
    [singleRow] -> return ("", singleRow)
    _           -> processSpan fullPeriod

  let rowTitles = Tab.Group Tab.NoLine (map (Header . T.pack . show) (take (length periodRows) [1..]))

  let isSingleSpan = length spans == 1
      details = mconcat perioddetails <> totaldetails

  rows <- case sequence $ if isSingleSpan then periodRows else periodRows ++ [totalRow] of
    Right rows -> return rows
    Left e -> do
      -- show any --cashflow details before the error, to help troubleshoot it
      unless (TL.null details) $ writeOutput opts $ TL.unpack details
      error' e

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
              rows

  writeOutput opts $ TL.unpack $ withTitle ropts $
    details <> Tab.render prettyTables id id id table <> "\n"


-- | Time-weighted rate of return, computed from the investment's value at the end of each day.
--
-- Only end-of-day values are used, which are always well defined: the day's closing balance, valued with the prices in
-- effect that day, whatever the order of transactions and prices within the day. Between days with cash flows, the
-- return is the ratio of values. A day with cash flows is split in two: first the day's price changes, applied to the
-- holdings carried over from the previous day; then the flows, as if made at the day's closing prices, with deposits
-- counted at the start and withdrawals at the end of that part (any difference between the trade prices and the
-- closing prices is part of its return). A stretch with nothing invested earns nothing, and contributes a factor of 1.
-- All returns are chained.
--
-- Cash flows are measured from the investment's side (see investmentCashFlows), so that they always agree with the
-- changes in its value.
timeWeightedReturn showCashFlow prettyTables showAmt holdingsAt valueOn (OneSpan begin end _valueBeforeAmt _valueAfterAmt cashflows _pnls) = do
  let
    lastDay      = addDays (-1) end
    valueAt d    = unMix $ valueOn d $ holdingsAt d

    -- deposits and withdrawals on each day of the period (each transaction's flows are netted, deposits are positive)
    flowsByDay = M.fromListWith (\(i1, o1) (i2, o2) -> (i1 + i2, o1 + o2))
      [ (d, (max 0 f, min 0 f)) | (d, ma) <- cashflows, let f = negate (unMix ma) ]

    -- Each row is a part of the period: (begin, end, what it is, value at begin, deposits, withdrawals, value at end).
    -- Every row's return is (value at end - withdrawals) / (value at begin + deposits) - 1 (withdrawals are negative),
    -- or 0 when nothing was invested at the start; the time-weighted return chains them.
    -- Stretches without cash flows get one row. A day with cash flows gets a row for its price changes (when there are
    -- any), from the previous day's closing value to the holdings carried over at this day's prices, and a row for its
    -- cash flows, from there to its closing value.
    go (prevDay, prevValue) [] =
      [ (addDays 1 prevDay, lastDay, "no cash flows", prevValue, 0, 0, valueAt lastDay) | prevDay < lastDay ]
    go (prevDay, prevValue) ((d, (deposits, withdrawals)) : rest) =
      let startValue = valueAt (addDays (-1) d)
          movedValue = unMix $ valueOn d $ holdingsAt (addDays (-1) d)
          endValue   = valueAt d
      in [ (addDays 1 prevDay, addDays (-1) d, "no cash flows", prevValue, 0, 0, startValue) | addDays 1 prevDay <= addDays (-1) d ]
         ++ [ (d, d, "prices", startValue, 0, 0, movedValue) | movedValue /= startValue ]
         ++ (d, d, "cash flows", movedValue, deposits, withdrawals, endValue)
         :  go (d, endValue) rest

    rowReturn (b, e, part, v0, dep, wdr, v1)
      | base == 0 && final == 0 = 0
      | base == 0 = 0  -- nothing invested at the start
      | base < 0  = error' $ "Cannot compute the time-weighted return for "
                    ++ T.unpack (if b == e then showDate b else showDate b <> " to " <> showDate e) ++ " (" ++ T.unpack part ++ "): "
                    ++ "the investment's value at the start (" ++ T.unpack (showAmt v0) ++ ") plus deposits ("
                    ++ T.unpack (showAmt dep) ++ ") is negative."
      | otherwise = realToFrac final / realToFrac base - 1 :: Double
      where base = v0 + dep; final = v1 - wdr

    rows    = dbg3 "twr rows" $ go (addDays (-1) begin, valueAt (addDays (-1) begin)) (M.toAscList flowsByDay)
    returns = map rowReturn rows
    cumulative = drop 1 $ scanl (\acc r -> (1 + acc) * (1 + r) - 1) 0 returns
    twr     = dbg3 "twr" $ if null cumulative then 0 else last cumulative

    years = fromIntegral (diffDays end begin) / 365.25 :: Double
    periodTWR     = roundTo 2 (100 * realToFrac twr :: Decimal)
    annualizedTWR = 100 * ((1 + twr) ** (1 / years) - 1) :: Double

    showPercent r = T.pack (showDecimal (roundTo 2 (realToFrac r * 100 :: Decimal)))
    details = if not showCashFlow then "" else
      TL.pack (printf "\nTWR returns for period %s - %s\n" (showDate begin) (showDate lastDay))
      <> Tab.render prettyTables T.pack id id
        (Table
         (Tab.Group Tab.NoLine [Header (show n) | n <- [1..length rows]])
         (Tab.Group DoubleLine
           [ Tab.Group Tab.SingleLine [Tab.Header "Begin", Tab.Header "End", Tab.Header "Part"]
           , Tab.Group Tab.SingleLine [Tab.Header "Value (begin)", Tab.Header "Deposits", Tab.Header "Withdrawals", Tab.Header "Value (end)"]
           , Tab.Group Tab.SingleLine [Tab.Header "Return, %", Tab.Header "Cumulative, %"]])
         [ [ showDate b, showDate e, part
           , showAmt v0, showAmt dep, showAmt wdr, showAmt v1
           , showPercent r, showPercent c ]
         | ((b, e, part, v0, dep, wdr, v1), r, c) <- zip3 rows returns cumulative ])
      <> TL.pack (printf "Each row's return is (Value (end) - Withdrawals) / (Value (begin) + Deposits) - 1; they are chained.\n")
      <> TL.pack (printf "Total period TWR: %s%%.\nPeriod: %.2f years.\nAnnualized TWR: %.2f%%\n\n"
           (showDecimal periodTWR) years annualizedTWR)

  return (details, ((realToFrac periodTWR) :: Double, annualizedTWR))

internalRateOfReturn styles showCashFlow prettyTables flowDetails (OneSpan begin end valueBefore valueAfter cashFlow _pnl) = do
  let prefix = (begin, maNegate valueBefore)

      postfix = (end, valueAfter)

      totalCF = filter (maIsNonZero . snd) $ prefix : (sortOn fst cashFlow) ++ [postfix]

      showMA = T.pack . showMixedAmountOneLineWithoutCost False . styleAmounts styles
      -- one row per cash flow, with the transaction it comes from, between the values at the start and the end
      -- (dated like the IRR uses them: the value at the end of the last day, on the day after it)
      rows =
           [ (begin, "value at the start", "", "", maNegate valueBefore) | maIsNonZero valueBefore ]
        ++ [ (ifDate f, ifDescription f, showMA (ifCost f), showMA (ifPnl f), ifFlow f) | f <- sortOn ifDate flowDetails ]
        ++ [ (end, "value at the end of " <> showDate (addDays (-1) end), "", "", valueAfter) | maIsNonZero valueAfter ]
      details = if not showCashFlow then "" else
        TL.pack (printf "\nIRR cash flows for %s - %s\n" (showDate begin) (showDate (addDays (-1) end)))
        <> Tab.render prettyTables id id id
          (Table
           (Tab.Group Tab.NoLine [ Header (showDate d) | (d, _, _, _, _) <- rows ])
           (Tab.Group Tab.SingleLine [Header "Description", Header "Investment, at cost", Header "Profit/loss", Header "Amount"])
           [ [desc, cost, pnl, showMA amt] | (_, desc, cost, pnl, amt) <- rows ])
        <> "Amounts are from your point of view: what you put in is negative, what you take out (or still have) positive.\n\n"

  -- 0% is always a solution, so require at least something here
  case totalCF of
    [] -> return (details, Right 0)
    _  -> return . (details,) . fmap (\r -> (r - 1) * 100) $
            solveIRR (interestSum end totalCF)
              "Equation for Internal Rate of Return (IRR) can not be solved.\n\
              \  Possible causes: IRR is huge (>1000000%), balance of investment becomes negative at some point in time."
              "Equation for Internal Rate of Return (IRR) can not be solved.\n\
              \  Either search does not converge to a solution, or converges too slowly."

type CashFlow = [(Day, MixedAmount)]

interestSum :: Day -> CashFlow -> Double -> Double
interestSum referenceDay cf rate = sum $ map go cf
  where go (t,m) = realToFrac (unMix m) * rate ** (fromIntegral (referenceDay `diffDays` t) / 365.25)

-- Note: Holdings.hs's xirrPct duplicates this solver setup and
-- interestSum's rate convention; keep them in sync, or extract a
-- shared helper.
solveIRR :: (Double -> Double) -> String -> String -> Either String Double
solveIRR npv errNotBracketed errSearchFailed =
  case ridders (RiddersParam 100 (AbsTol 0.00001))
               (0.000000000001, 10000)
               npv of
    Root s       -> Right s
    NotBracketed -> Left errNotBracketed
    SearchFailed -> Left errSearchFailed

calculateCashFlow :: WhichDate -> [Transaction] -> Query -> CashFlow
calculateCashFlow wd trans query =
  [ (postingDateOrDate2 wd p, pamount p) | p <- concatMap (filter (matchesPosting query) . realPostings) trans, maIsNonZero (pamount p) ]

unMix :: MixedAmount -> Quantity
unMix a =
  case (unifyMixedAmount a) of
    Just a' -> aquantity a'
    Nothing -> multiCommodityError $ "Amounts could not be converted to a single commodity: " ++ show (map showAmount $ amounts a)

-- | One cash flow of the investment, with the parts it is computed from (shown by --cashflow).
data InvestmentFlow = InvestmentFlow
  { ifDate        :: Day
  , ifDescription :: T.Text
  , ifCost        :: MixedAmount  -- ^ the cost of the transaction's investment postings on that date
  , ifPnl         :: MixedAmount  -- ^ the transaction's profit and loss (gains positive)
  , ifFlow        :: MixedAmount  -- ^ the cash flow: deposits negative, withdrawals positive
  }

-- | Drop the amounts of commodities whose quantities add up to zero (positions fully closed). Summing postings can keep
-- these as separate amounts with different costs, which don't cancel out when valued at cost.
dropClosedPositions :: MixedAmount -> MixedAmount
dropClosedPositions ma = filterMixedAmount ((`S.notMember` closed) . acommodity) ma
  where closed = M.keysSet . M.filter (== 0) $ M.fromListWith (+) [ (acommodity a, aquantity a) | a <- amounts ma ]

-- | After valuation, an amount of the investment should be in the expected commodity, if we know it. If some of it is
-- still in another commodity, there was no market price for that commodity on that date. Say so, rather than mistake
-- its quantity for a value or report a confusing mix of commodities later.
-- The expected commodity can differ from the one requested with --value, when nothing converts to that; mention it then.
checkValued :: Maybe CommoditySymbol -> Maybe CommoditySymbol -> Day -> MixedAmount -> MixedAmount
checkValued _ Nothing _ amt = amt
checkValued requested (Just c) date amt =
  case nub [ acommodity a | a <- amounts amt, acommodity a /= c, not (amountIsZero a) ] of
    []       -> amt
    unpriced -> error' $ "Could not value the investment on " ++ T.unpack (showDate date) ++ ": "
                ++ "no market price in " ++ showc c ++ " is known for "
                ++ intercalate ", " (map showc unpriced) ++ " on or before that date."
                ++ (case requested of
                      Just r | r /= c -> "\n" ++ showc r ++ " was requested with --value, but the cash flows and PnL"
                                         ++ " are in " ++ showc c ++ ", as no market price converts them to " ++ showc r ++ "."
                      _ -> "")
                ++ "\nAdd a P directive, or use --infer-market-prices to also use the prices recorded in transactions."
  where showc = T.unpack . showCommoditySymbol

multiCommodityError msg = error' $ msg ++
    "\nConsider using --value to force all costs to be in a single commodity." ++
    "\nFor example, \"--value=end,<commodity> --infer-market-prices\", where commodity is the one that you want to value the investment in."

-- Show Decimal rounded to two decimal places, unless it has less places already. This ensures that "2" won't be shown as "2.00"
showDecimal :: Decimal -> String
showDecimal d = if d == rounded then show d else show rounded
  where
    rounded = roundTo 2 d
