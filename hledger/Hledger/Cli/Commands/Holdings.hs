{-|

The @holdings@ command shows a report of investment holdings (lot-tracked assets).

Work in progress; see doc/SPEC-holdings.md.
Currently it shows the Date, Age, Units, Unit/Avg cost, Price, Cost,
Value, Weight, UGain, UGain%, RGain and XIRR columns, one row per
account (or lot subaccount, with --lots) and held commodity.

-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Holdings (
  holdingsmode
 ,holdings
) where

import Control.Applicative ((<|>))
import Control.Monad (guard)
import Data.Aeson (Value, object, (.=))
import Data.Decimal (roundTo)
import Data.Default (def)
import Data.List.Extra (intercalate, intersperse, nubSort, nubSortOn, sortOn)
import Data.Map.Strict qualified as M
import Data.Maybe (fromMaybe, isJust, mapMaybe)
import Data.Ord (Down(..))
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Time.Calendar (Day, addDays, diffDays)
import System.Console.CmdArgs.Explicit (flagNone, flagReq)
import Text.Printf (printf)

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Commands.Balance (addTotalBorders, renderPeriodicAcct)
import Hledger.Cli.Commands.Print (roundFromRawOpts)
import Hledger.Cli.Utils (unsupportedOutputFormatError, writeOutputLazyText)
import Hledger.Write.Csv (CSV, printCSV, printTSV)
import Hledger.Write.Html (Html, htmlAsLazyText, titledTableHtml, toHtml)
import Hledger.Write.Ods (printFods)
import Hledger.Write.Spreadsheet (addHeaderBorders, headerCell)
import Hledger.Write.Spreadsheet qualified as Ods
import Numeric.RootFinding (RiddersParam(..), Root(..), Tolerance(..), ridders)
import System.IO qualified as IO
import Text.Blaze.Html5 ((!))
import Text.Blaze.Html5 qualified as H
import Text.Blaze.Html5.Attributes qualified as A
import Text.Tabular.AsciiWide

-- | Command line options for this command.
holdingsmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Holdings.txt")
  (flattreeflags True ++
   [flagNone ["no-elide"] (setboolopt "no-elide") "in tree mode, don't squash boring parent accounts; in list mode, also show parent accounts (usually zero, hidden without -E)"
   ,flagNone ["full-names"] (setboolopt "full-names") "in tree mode, show full account names instead of indented leaf names"
   ,flagReq  ["drop"] (\s opts -> Right $ setopt "drop" s opts) "N" "in list mode, omit N leading account name parts"
   ,flagNone ["sort-amount","S"] (setboolopt "sort-amount") "sort by value (or cost) instead of account name, largest first"
   ,flagNone ["no-total","N"] (setboolopt "no-total") "omit the final total row"
   ,flagReq ["round"] (\s opts -> Right $ setopt "round" s opts) "TYPE" $
     intercalate "\n"
     ["how much rounding or padding should be done when displaying amounts ?"
     ,"none - show original decimal digits"
     ,"soft - just add or remove decimal zeros"
     ,"       to match precision"
     ,"hard - round amounts to precision (default)"
     ,"all  - also round cost amounts to precision"
     ]
   ,outputFormatFlag ["txt","csv","tsv","html","fods","json"]
   ,outputFileFlag])
  cligeneralflagsgroups1
  hiddenflags
  ([], Just $ argsFlag "[QUERY]")

-- | One holding: one commodity held in one displayed account (or lot
-- subaccount), with its report attributes. Each holding is one row of
-- the text/html/fods table and one record of the csv/tsv/json output.
-- A commodity fully disposed from a displayed account also gets a
-- holding, with zero units, so its realised gain stays visible.
data Holding = Holding {
   hAccount   :: AccountName
  ,hCommodity :: CommoditySymbol
  ,hDate      :: Maybe Day        -- ^ acquisition date, when the lots share one
  ,hAge       :: Maybe Integer    -- ^ days held at the report date
  ,hUnits     :: Amount           -- ^ units held, styled
  ,hUnitCost  :: Maybe Amount     -- ^ unit or average cost
  ,hPrice     :: [Amount]         -- ^ market price(s) at the valuation date (several if the lots' value commodities differ)
  ,hCost      :: [Amount]         -- ^ total cost basis (multiple amounts if cost commodities are mixed)
  ,hValue     :: [Amount]         -- ^ market value, when all lots are priced (multiple amounts if value commodities are mixed)
  ,hWeight    :: Maybe Quantity   -- ^ percentage of the portfolio's value, unrounded
  ,hUgain     :: [Amount]         -- ^ unrealised gain, when values and costs cover the same commodities
  ,hUgainPct  :: Maybe Quantity   -- ^ unrealised gain percent, unrounded
  ,hRgain     :: [Amount]         -- ^ realised gain, from disposals so far
  ,hXirr      :: Maybe Double     -- ^ annualised internal rate of return percent
  }

-- Machine-readable fields for the csv/tsv output: full account name, age
-- in days, bare units and rounded gain percent numbers, machine-format
-- amounts (no digit group marks).
holdingCsv :: Holding -> [T.Text]
holdingCsv h =
  [hAccount h
  ,hCommodity h
  ,maybe "" showDate (hDate h)
  ,maybe "" (T.pack . show) (hAge h)
  ,T.pack $ showAmountWith machineFmt{displayCommodity=False} (hUnits h)
  ,maybe "" showamt (hUnitCost h)
  ,showamts (hPrice h)
  ,T.pack $ showMixedAmountWith machineFmt $ mixed $ hCost h
  ,showamts (hValue h)
  ,maybe "" (T.pack . show . roundTo 1) (hWeight h)
  ,showamts (hUgain h)
  ,maybe "" (T.pack . show . roundTo 1) (hUgainPct h)
  ,showamts (hRgain h)
  ,maybe "" (T.pack . printf "%.1f") (hXirr h)
  ]
  where
    showamt  = T.pack . showAmountWith machineFmt
    showamts [] = ""
    showamts as = T.pack $ showMixedAmountWith machineFmt $ mixed as

holdingJson :: Holding -> Value
holdingJson h = object
  ["account"   .= hAccount h
  ,"commodity" .= hCommodity h
  ,"date"      .= hDate h
  ,"age"       .= hAge h
  ,"units"     .= aquantity (hUnits h)
  ,"unitcost"  .= (showamt <$> hUnitCost h)
  ,"price"     .= mshowamts (hPrice h)
  ,"cost"      .= showamts (hCost h)
  ,"value"     .= mshowamts (hValue h)
  ,"weight"    .= (roundTo 1 <$> hWeight h)
  ,"ugain"     .= mshowamts (hUgain h)
  ,"ugainpct"  .= (roundTo 1 <$> hUgainPct h)
  ,"rgain"     .= mshowamts (hRgain h)
  ,"xirr"      .= hXirr h
  ]
  where
    showamt  = T.pack . showAmountWith machineFmt
    showamts = T.pack . showMixedAmountWith machineFmt . mixed
    mshowamts as = case as of [] -> Nothing; _ -> Just $ showamts as

-- | Show an age in days compactly: in days, or if a year or more,
-- in years with one decimal digit (approximating years as 365 days):
-- eg 44d, 1.1y.
showage :: Integer -> T.Text
showage d
  | d >= 365  = T.pack (show (roundTo 1 (fromIntegral d / 365))) <> "y"
  | otherwise = T.pack (show d) <> "d"

-- | Show the holdings report: the assets held in lot-tracked accounts
-- as of the report end date, one row per account (or per lot, with --lots).
--
-- This command receives the journal with lot detail (lot subaccounts and
-- synthetic postings) uncollapsed, regardless of --lots
-- (see maybeCollapseLotDetail); it aggregates lots itself.
holdings :: CliOpts -> Journal -> IO ()
holdings opts@CliOpts{rawopts_=rawopts, reportspec_=rspec@ReportSpec{_rsQuery=q, _rsReportOpts=ropts}} j = do
  if (case mvalue of Just (AtThen _) -> True; _ -> False)
  then error' "holdings: --value=then is not supported"
  else rounding `seq`  -- validate the --round value before any output
    writeOutputLazyText opts $ case outputFormatFromOpts opts of
      "txt"  -> txtoutput
      "csv"  -> printCSV csvoutput
      "tsv"  -> printTSV csvoutput
      "html" -> (<>"\n") $ htmlAsLazyText $ titledTableHtml title htmltable
      "fods" -> printFods IO.localeEncoding $ M.singleton "Holdings" ((1,0), fodstable)
      "json" -> (<>"\n") $ toJsonText $ map holdingJson holdingrecords
      fmt    -> error' $ unsupportedOutputFormatError fmt
  where
    -- The default title can be customised or suppressed with --title.
    title = effectiveTitle ropts ("Holdings on " <> showDate reportdate)
    txtoutput =
      (case title of
         "" -> ""
         t  -> TL.fromStrict t <> "\n\n")
      <>
      if null rows
      then "(no holdings)\n"
      else renderTable
        def{tableBorders=False}
        (textCell TopLeft)
        (textCell TopRight)
        (textCell TopRight)
        tbl
    showlots = boolopt "lots" rawopts
    tree = accountlistmode_ ropts == ALTree

    -- The date this report shows holdings at: the day before the (exclusive)
    -- report end date if specified, otherwise today.
    mend = queryEndDate False q
    reportdate = maybe (_rsDay rspec) (addDays (-1)) mend

    -- The query used to select lot subaccount postings: the report query
    -- without its date terms (holdings are cumulative to the end date,
    -- added here) and depth terms (--depth only clips the displayed rows;
    -- the lots beneath still count).
    endq = And [filterQuery (\x -> not $ queryIsDateOrDate2 x || queryIsDepth x) q
               ,Date $ DateSpan Nothing (Exact <$> mend)]

    -- The postings contributing to each lot subaccount, keyed by account
    -- and commodity (so amounts in different commodities, not expected in
    -- a lot subaccount but possible, don't merge wrongly).
    lotpostings :: [((AccountName, CommoditySymbol), (Day, Amount))]
    lotpostings =
      [ ((paccount p, acommodity a), (postingDate p, a))
      | p <- journalPostings j
      , isJust $ lotSubaccountName $ paccount p
      , endq `matchesPosting` p
      , a <- amountsRaw $ pamount p
      ]

    -- The units held in each lot subaccount.
    lotmap :: M.Map (AccountName, CommoditySymbol) Amount
    lotmap = M.fromListWith (+) [(k, amountStripCost a) | (k, (_, a)) <- lotpostings]

    -- Each lot subaccount's cashflows in the cost commodity, for XIRR:
    -- each posting's transacted cost if any (so, proceeds when disposing),
    -- otherwise its cost basis value. Negative = money invested.
    flowmap :: M.Map (AccountName, CommoditySymbol) [(Day, Amount)]
    flowmap = M.fromListWith (++)
      [ (k, [(d, negate flowamt)])
      | (k, (d, a)) <- lotpostings
      , Just flowamt <- [case acost a of
          Just _  -> Just $ amountCost a
          Nothing -> multiplyAmount (aquantity a) <$> (cbCost =<< acostbasis a)]
      ]

    -- Each lot subaccount's realised gains, in the cost commodity:
    -- for each dispose posting (negative, with a transacted price and a
    -- cost basis), the proceeds minus the cost basis of the disposed units.
    -- The gains get their commodity's display style, since the cost bases
    -- they are derived from can have more precision (eg from inferred
    -- per-unit costs).
    rgainmap :: M.Map (AccountName, CommoditySymbol) Amount
    rgainmap = M.map (styleAmounts styles) $ M.fromListWith (+)
      [ (k, proceeds - basis)
      | (k, (_, a)) <- lotpostings
      , aquantity a < 0
      , isJust $ acost a
      , let proceeds = negate $ amountCost a
      , Just ub <- [cbCost =<< acostbasis a]
      , let basis = multiplyAmount (negate $ aquantity a) ub
      , acommodity proceeds == acommodity basis
      ]

    -- The current average unit cost of each AVERAGE/AVERAGEALL pool, as of
    -- the report end date, keyed by (base account, commodity): the sum of
    -- quantity * unit cost basis over the pool's lot postings, divided by
    -- the total units. Acquisitions carry their acquisition cost and
    -- disposals/transfers the then-current average, so this works out to
    -- the pool's running average. It is valid only summed over the whole
    -- pool: the base account's lots for AVERAGE, or all accounts' lots for
    -- AVERAGEALL. Used to fill in the cost missing from AVERAGE lots'
    -- costless subaccount names (see lotsUnder).
    poolavgmap :: M.Map (AccountName, CommoditySymbol) Amount
    poolavgmap = M.fromList
      [ ((base, c), styleAmounts styles $ avgcost unitsamt costtot)
      | (base, c) <- nubSort [ (lotBaseAccount sub, c') | ((sub, c'), _) <- lotpostings ]
      , let method = fst $ resolveReductionMethodForAccount j base c
      , method `elem` [AVERAGE, AVERAGEALL]
      , let entries = [ (a, ub)
                      | ((sub, c'), (_, a)) <- lotpostings
                      , c' == c
                      , method == AVERAGEALL || lotBaseAccount sub == base
                      , Just ub <- [cbCost =<< acostbasis a] ]
      , (ub1:_) <- [map snd entries]
      , all ((== acommodity ub1) . acommodity) (map snd entries)
      , let units = sum [aquantity a | (a, _) <- entries]
      , units /= 0
      , let unitsamt = nullamt{acommodity=c, aquantity=units}
            costtot  = ub1{aquantity = sum [aquantity a * aquantity ub | (a, ub) <- entries]}
      ]

    -- Which accounts (lot subaccounts, or the keys of the per-lot maps)
    -- belong to a displayed row's own scope: those at or under the row's
    -- account - excluding, in list mode, those at or under a deeper
    -- candidate row, which displays them itself. (In tree mode, and for
    -- totals, a row includes everything at or under it; see the *Under
    -- helpers.) This is what makes overlapping list-mode rows disjoint,
    -- eg when lots are held in both an account and its subaccount (each
    -- of which then gets its own row).
    rowScope :: AccountName -> (AccountName -> Bool)
    rowScope acct = \sub -> covers acct sub && not (any (`covers` sub) deeper)
      where
        covers p s = p == s || p `isAccountNamePrefixOf` s
        deeper | tree = []
               | otherwise = [c | c <- candaccts, c /= acct, acct `isAccountNamePrefixOf` c]

    -- The values in a map whose keys are at or under the given account
    -- (and in the given held commodity, if specified).
    underIn :: M.Map (AccountName, CommoditySymbol) v -> AccountName -> Maybe CommoditySymbol -> [v]
    underIn m acct = scopedIn m (\sub -> acct == sub || acct `isAccountNamePrefixOf` sub)

    -- The values in a map whose keys satisfy the given account test
    -- (and are in the given held commodity, if specified).
    scopedIn :: M.Map (AccountName, CommoditySymbol) v -> (AccountName -> Bool) -> Maybe CommoditySymbol -> [v]
    scopedIn m intest mc =
      [ v | ((sub, c), v) <- M.toAscList m
      , intest sub
      , maybe True (== c) mc
      ]

    -- The cashflows of the lots at or under an account, optionally of one held commodity.
    flowsUnder :: AccountName -> Maybe CommoditySymbol -> [(Day, Amount)]
    flowsUnder acct mc = concat $ underIn flowmap acct mc

    -- The cashflows of the lots in a row account's own scope.
    flowsOf :: AccountName -> Maybe CommoditySymbol -> [(Day, Amount)]
    flowsOf acct mc = concat $ scopedIn flowmap (rowScope acct) mc

    -- The realised gains of the lots at or under an account, optionally of one held commodity.
    rgainsUnder :: AccountName -> Maybe CommoditySymbol -> [Amount]
    rgainsUnder = underIn rgainmap

    -- The realised gains of the lots in a row account's own scope.
    rgainsOf :: AccountName -> Maybe CommoditySymbol -> [Amount]
    rgainsOf acct = scopedIn rgainmap (rowScope acct)

    -- A lot subaccount's cost basis, parsed from its name
    -- (which by construction contains the acquisition date and unit cost).
    -- The cost gets its commodity's display style, including display
    -- precision (lot names can have more precision, eg from inferred
    -- per-unit costs), so derived amounts (Unit cost, Cost) are displayed
    -- with the standard display precision.
    lotBasis :: AccountName -> Maybe CostBasis
    lotBasis acct = do
      name <- lotSubaccountName acct
      cb <- either (const Nothing) Just $ parseLotName parseAmt name
      Just cb{cbCost = styleAmounts styles <$> cbCost cb}
      where parseAmt = either (const Nothing) Just . parseamount

    -- Amounts are displayed normalised to their commodity's display
    -- precision by default; --round can choose another rounding strategy.
    rounding = fromMaybe HardRounding $ roundFromRawOpts rawopts
    styles = journalCommodityStylesWith rounding j

    priceoracle = journalPriceOracle (infer_prices_ ropts) j

    -- The valuation strategy requested with -V/-X/--value, if any.
    -- It selects the valuation date and/or the valuation commodity;
    -- --value=then is rejected above.
    mvalue = value_ ropts
    (valuationdate, mtargetcomm) = case mvalue of
      Nothing            -> (reportdate, Nothing)
      Just (AtEnd  mc)   -> (reportdate, mc)
      Just (AtNow  mc)   -> (_rsDay rspec, mc)
      Just (AtDate d mc) -> (d, mc)
      Just (AtThen mc)   -> (reportdate, mc)  -- not supported, rejected above

    -- The valuation target commodity for a lot: the commodity requested
    -- with -V/-X/--value if any, otherwise the lot's own cost commodity
    -- when known, otherwise none (the price oracle picks a default).
    lotValuationComm :: Maybe CostBasis -> Maybe CommoditySymbol
    lotValuationComm mcb = case mvalue of
      Nothing -> acommodity <$> (cbCost =<< mcb)
      Just _  -> mtargetcomm

    -- Value one lot at the valuation date: Just (unit price, total value)
    -- if it has a market price to its target commodity.
    lotValuation :: (Amount, Maybe CostBasis) -> Maybe (Amount, Amount)
    lotValuation (a, mcb) = do
      (pcomm, rate) <- priceoracle (valuationdate, acommodity a, lotValuationComm mcb)
      let mkamt n = styleAmounts styles $ amountSetFullPrecisionUpTo Nothing
                      nullamt{acommodity=pcomm, aquantity=n}
      Just (mkamt rate, mkamt (rate * aquantity a))

    -- Value some lots at the valuation date: Just (their distinct unit
    -- prices, their total value per value commodity) if every lot has a
    -- market price, otherwise Nothing. Each lot is valued separately in
    -- its own target commodity, so values (and their sums, like the
    -- totals row) don't depend on how lots are grouped into display rows
    -- (by --depth, --pivot, tree mode etc).
    lotsValuation :: [(Amount, Maybe CostBasis)] -> Maybe ([Amount], [Amount])
    lotsValuation lots = do
      pvs <- mapM lotValuation lots
      Just (nubSortOn (\a -> (acommodity a, aquantity a)) $ map fst pvs
           ,sumAmounts $ map snd pvs)

    -- The market value of the lots at or under an account, per value
    -- commodity, when they are all priced.
    mvalueUnder :: AccountName -> Maybe [Amount]
    mvalueUnder acct = snd <$> lotsValuation (lotsUnder acct)

    -- The market value of the lots in a row account's own scope, per
    -- value commodity, when they are all priced.
    mvalueOf :: AccountName -> Maybe [Amount]
    mvalueOf acct = snd <$> lotsValuation (lotsOf acct)

    -- How to convert cost amounts (Cost, Unit/Avg cost, RGain, and the
    -- cost side of UGain) for display when -V/-X/--value is in effect:
    -- convert to the requested commodity, or to the given fallback
    -- commodity (the row's or portfolio's value commodity), at the
    -- valuation date. Costs already in the target commodity, or with no
    -- target or no market price, are left unchanged.
    costValuerTo :: Maybe CommoditySymbol -> Amount -> Amount
    costValuerTo mfallback = case mvalue of
      Nothing -> id
      Just _ -> case mtargetcomm <|> mfallback of
        Nothing -> id
        -- styleAmounts is reapplied after conversion, since
        -- amountValueAtDate leaves full precision displayed
        Just tc -> \a -> if acommodity a == tc then a
                         else styleAmounts styles $
                              amountValueAtDate priceoracle styles (Just tc) valuationdate a

    rowCostValuer :: PeriodicReportRow DisplayName MixedAmount -> Amount -> Amount
    rowCostValuer r = costValuerTo mrowvaluecomm
      where
        mrowvaluecomm = case mvalueUnder (prrFullName r) of
          Just [v] -> Just $ acommodity v
          _        -> Nothing

    -- The annualised internal rate of return implied by dated cashflows
    -- (negative = money invested) up to the report date, as a percentage,
    -- calculated like roi's IRR. Nothing if it can not be solved.
    -- Note: this duplicates the solver setup and rate convention of
    -- Roi.hs's solveIRR/interestSum (not exported); keep them in sync,
    -- or extract a shared helper.
    xirrPct :: [(Day, Quantity)] -> Maybe Double
    xirrPct cf =
      case ridders (RiddersParam 100 (AbsTol 0.00001)) (0.000000000001, 10000) npv of
        Root rate -> Just $ (rate - 1) * 100
        _         -> Nothing
      where
        npv rate = sum [realToFrac n * rate ** (fromIntegral (diffDays reportdate t) / 365.25) | (t, n) <- cf]

    -- XIRR from cashflows plus a final value amount at the report date,
    -- when they are all in one commodity.
    xirrOf :: [(Day, Amount)] -> Amount -> Maybe Double
    xirrOf flows finalv = do
      guard $ not $ null flows
      guard $ all ((== acommodity finalv) . acommodity . snd) flows
      xirrPct $ (reportdate, aquantity finalv) : [(d, aquantity a) | (d, a) <- flows]

    -- The total value of the displayed holdings, per value commodity,
    -- when all are priced; and its commodity, when it has just one.
    mportfoliovalue :: Maybe [Amount]
    mportfoliovalue = do
      vs <- mapM (mvalueUnder . prrFullName) toprows
      Just $ sumAmounts $ concat vs
    mportvaluecomm = case mportfoliovalue of
      Just [v] -> Just $ acommodity v
      _        -> Nothing

    -- The distinct base accounts of the displayed rows (excluding any
    -- contained in another). Account-level totals (RGain, XIRR) are
    -- computed from these, so that they include fully disposed lots,
    -- which have no displayed row of their own (eg with --lots).
    -- (Fully disposed accounts are included only when -E displays them.)
    topbases :: [AccountName]
    topbases = [ b | b <- bases, not $ any (`isAccountNamePrefixOf` b) bases ]
      where bases = nubSort $ map (lotBaseAccount . prrFullName) toprows

    -- A value's percentage of the portfolio's total value, when both are
    -- single amounts in the same commodity.
    weightPct :: [Amount] -> Maybe Quantity
    weightPct val = do
      tot <- mportfoliovalue
      [t] <- Just tot
      [v] <- Just val
      guard $ acommodity v == acommodity t && aquantity t /= 0
      Just $ 100 * aquantity v / aquantity t

    -- The commodity display styles, plus a default style for the "%"
    -- commodity if none is declared or inferred: one decimal digit,
    -- and the % sign on the right with no space.
    pctstyles = M.union styles $ M.singleton "%" $
      amountstyle{ascommodityside=R, asprecision=Precision 1, asrounding=HardRounding}

    -- Show a percentage (for the Weight, UGain% and XIRR columns) as a
    -- "%" commodity amount, using the display style of "%" (eg from a
    -- commodity directive or -c) or the default above: eg 64.3%.
    showpct :: Quantity -> T.Text
    showpct p =
      T.pack $ showAmountWith noCostFmt{displayZeroCommodity=True} $
      styleAmounts pctstyles nullamt{acommodity="%", aquantity=p}

    -- Show an XIRR percentage, like showpct: eg 12.3%.
    showxirr :: Double -> T.Text
    showxirr = showpct . realToFrac

    -- The unrealised gains implied by value and cost amounts: value minus
    -- cost per commodity, when they cover exactly the same (nonempty) set
    -- of commodities; otherwise Nothing.
    gainAmounts :: [Amount] -> [Amount] -> Maybe [Amount]
    gainAmounts vals costs = do
      guard $ not (null vs) && map acommodity vs == map acommodity cs
      Just $ zipWith gain1 vs cs
      where
        vs = sumAmounts vals
        cs = sumAmounts costs
        gain1 v c = styleAmounts styles $ amountSetFullPrecisionUpTo Nothing
                      nullamt{acommodity=acommodity v, aquantity=aquantity v - aquantity c}

    -- The percent gain, when the gains and the costs are single amounts
    -- in the same commodity and the cost is nonzero.
    gainPct :: [Amount] -> [Amount] -> Maybe Quantity
    gainPct gains costs = do
      [g] <- Just gains
      [c] <- Just $ sumAmounts costs
      guard $ acommodity g == acommodity c && aquantity c /= 0
      Just $ 100 * aquantity g / aquantity c

    -- A row's units of lot-tracked commodities: the sum of the lots in
    -- its own scope, one amount per commodity. (Not the row's report
    -- balance: a depth-clipped or pivoted row could also aggregate
    -- same-commodity balances from non-lot-tracked accounts, which would
    -- make Units inconsistent with the lot-derived Cost and gain columns.)
    rowUnitAmounts :: PeriodicReportRow DisplayName MixedAmount -> [Amount]
    rowUnitAmounts r =
      filter (not . amountLooksZero) $ sumAmounts $
      map fst $ lotsOf $ prrFullName r

    -- The lots held at or under the given account, excluding empty ones.
    lotsUnder :: AccountName -> [(Amount, Maybe CostBasis)]
    lotsUnder acct = lotsWhere (\sub -> acct == sub || acct `isAccountNamePrefixOf` sub)

    -- The lots in a row account's own scope, excluding empty ones.
    lotsOf :: AccountName -> [(Amount, Maybe CostBasis)]
    lotsOf acct = lotsWhere (rowScope acct)

    -- The nonempty lots whose subaccounts satisfy the given test.
    -- A lot's cost basis comes from its subaccount name; when the name has
    -- no cost part (AVERAGE lots' names omit it, staying stable across
    -- re-averaging), the pool's current average cost is filled in instead.
    lotsWhere :: (AccountName -> Bool) -> [(Amount, Maybe CostBasis)]
    lotsWhere intest =
      [ (a, addPoolAvg sub a <$> lotBasis sub) | ((sub, _), a) <- M.toAscList lotmap
      , intest sub
      , not $ amountLooksZero a
      ]
      where
        addPoolAvg sub a cb@CostBasis{cbCost=Nothing} =
          cb{cbCost = M.lookup (lotBaseAccount sub, acommodity a) poolavgmap}
        addPoolAvg _ _ cb = cb

    -- Report rows come from a single-period, end-balances multiBalanceReport:
    -- on the lot-detailed journal with --lots (rows are lot subaccounts),
    -- on the collapsed journal otherwise (rows are the base accounts).
    -- Non-holding accounts are filtered out.
    -- Cost conversion and valuation (-B/-V/--value) are disabled:
    -- holdings does its own valuation, and units should stay units.
    mbr = multiBalanceReport rspec' j'
      where
        rspec' = rspec{_rsReportOpts=ropts{balanceaccum_=Historical, interval_=NoInterval
                                          ,conversionop_=Just NoConversionOp, value_=Nothing
                                          ,sort_amount_=False}}  -- -S sorts by value/cost below, not by units
        j' = if showlots then j else journalCollapseLotDetail j
    -- Candidate rows: those with lots at or beneath them; with -E/--empty,
    -- also those with realised gains at or beneath them (fully disposed
    -- accounts/lots, normally hidden).
    candidates = filter isholdingrow $ prRows mbr
      where
        isholdingrow r = not (null (lotsUnder acct))
                      || (empty_ ropts && hasRgainsUnder acct)
          where acct = prrFullName r
    candaccts = map prrFullName candidates

    -- Rows to display: the candidates, except - in list mode - those with
    -- nothing in their own scope (eg a base account row whose lots all
    -- appear in displayed lot subaccount rows); in tree mode all are
    -- wanted. A row holding lots directly is kept even when a deeper row
    -- also displays; it shows just its own lots (see rowScope).
    rows = filter keeprow candidates
      where
        keeprow r = tree || not (null (lotsOf acct))
                 || (empty_ ropts && hasRgainsOf acct)
          where acct = prrFullName r

    -- Are there nonzero realised gains at or under this account ?
    hasRgainsUnder :: AccountName -> Bool
    hasRgainsUnder acct = any (not . amountLooksZero) $ rgainsUnder acct Nothing

    -- Are there nonzero realised gains in this row account's own scope ?
    hasRgainsOf :: AccountName -> Bool
    hasRgainsOf acct = any (not . amountLooksZero) $ rgainsOf acct Nothing

    -- The topmost displayed rows: those not contained in another displayed
    -- row. Totals are computed from these, to avoid double counting.
    toprows = [ r | r <- rows
              , not $ any (\r2 -> prrFullName r2 `isAccountNamePrefixOf` prrFullName r) rows ]

    -- The display order: by account name, or with -S by each row's Value
    -- (falling back to Cost), largest first. Sorting compares the keys
    -- along each row's chain of displayed ancestors, so in tree mode each
    -- level is sorted and subtrees stay together. Ties (and rows mixing
    -- commodities, which are summed crudely) keep the account name order.
    sortedrows
      | not $ sort_amount_ ropts = rows
      | otherwise = sortOn keypath rows
      where
        keymap = M.fromList [(prrFullName r, Down $ rowSortKey r) | r <- rows]
        keypath r = mapMaybe (`M.lookup` keymap) $ reverse (parentAccountNames a) ++ [a]
          where a = prrFullName r
        rowSortKey r = case mvalueOf (prrFullName r) of
          Just val -> sumq val
          Nothing  -> sumq $ rowLotCosts r
          where sumq = sum . map aquantity

    -- The displayed table lines: each report row's holdings, one line per
    -- commodity, with the report row kept for rendering the account cell
    -- (repeated on each of its lines).
    rowlines :: [(PeriodicReportRow DisplayName MixedAmount, Holding)]
    rowlines = [(r, h) | r <- sortedrows, h <- rowHoldings r]

    tbl = maybe id addtotalrow (map (T.intercalate ", ") <$> mtotalrowparts) $ Table
      (Group NoLine $ map (Header . renderacct . fst) rowlines)
      (Group NoLine $ map Header colheadings)
      (map (map (T.intercalate ", ") . holdingCellParts . snd) rowlines)
      where
        addtotalrow totalrow tbl' = concatTables SingleLine tbl' $
          Table (Group NoLine [Header ""]) (Header []) [totalrow]
    colheadings = ["Date", "Age", "Units", unitcostheading, "Price", "Cost", "Value", "Weight", "UGain", "UGain%", "RGain", "XIRR"]

    -- The cost column's heading matches what's shown: "Avg cost" on rows
    -- aggregating multiple lots (the default) or when the lots shown all
    -- belong to AVERAGE/AVERAGEALL pools (whose per-lot rows show the
    -- pool's average cost); "Unit cost" when each lot shows its own cost;
    -- "Unit/Avg cost" when both kinds of lot are shown.
    unitcostheading :: T.Text
    unitcostheading
      | not showlots || allavg = "Avg cost"
      | anyavg = "Unit/Avg cost"
      | otherwise = "Unit cost"
      where
        avgs = [ fst (resolveReductionMethodForAccount j (lotBaseAccount sub) c)
                 `elem` [AVERAGE, AVERAGEALL]
               | (sub, c) <- M.keys lotmap ]
        allavg = not (null avgs) && and avgs
        anyavg = or avgs
    renderacct r = renderPeriodicAcct ropts " " r

    rowLotCosts r = [rowCostValuer r $ multiplyAmount (aquantity a) c
                    | (a, mcb) <- lotsOf $ prrFullName r, Just c <- [cbCost =<< mcb]]

    -- A holding's cells, each as a list of parts: possibly several in Cost
    -- and RGain (when cost commodities are mixed), at most one elsewhere.
    -- Units show a commodity symbol even when zero (for rgain-only rows).
    holdingCellParts :: Holding -> [[T.Text]]
    holdingCellParts h =
      [ [maybe "" showDate (hDate h)]
      , [maybe "" showage (hAge h)]
      , [T.pack $ showAmountWith noCostFmt{displayZeroCommodity=True} (hUnits h)]
      , [maybe "" showamt (hUnitCost h)]
      , map showamt $ hPrice h
      , map showamt $ hCost h
      , map showamtz $ hValue h
      , [maybe "" showpct (hWeight h)]
      , map showamtz $ hUgain h
      , [maybe "" showpct (hUgainPct h)]
      , map showamt $ hRgain h
      , [maybe "" showxirr (hXirr h)]
      ]
      where
        showamt  = T.pack . showAmountWith noCostFmt
        showamtz = T.pack . showAmountWith noCostFmt{displayZeroCommodity=True}

    -- Spreadsheet-shaped tables for the html and fods output: like the
    -- text table, but with single-line cells, an Account column heading,
    -- and a Total: row heading. Parameterised on how to convert plain
    -- text, and a cell's list of (possibly amount) parts, to content.
    spreadsheetWith :: forall content. (T.Text -> content) -> (Bool -> [T.Text] -> content)
                    -> [[Ods.Cell Ods.NumLines content]]
    spreadsheetWith plain parts =
      addHeaderBorders (zipWith hcell colclasses ("Account" : colheadings))
      : [ zipWith3 bodycell [0..] colclasses
            (plain (acctcell r) : zipWith parts amountcols (holdingCellParts h))
        | (r, h) <- rowlines ]
      ++ maybe [] (\tot -> addTotalBorders
           [zipWith3 totalcell [0..] colclasses
              (plain "Total:" : zipWith parts amountcols tot) :: [Ods.Cell () content]])
           mtotalrowparts
      where
        -- per-column css classes, so the html cells can be styled
        colclasses = ["account","date","age","units","unitcost","price","cost","value","weight","ugain","ugainpct","rgain","xirr"]
        -- which of the other columns' cell parts are amounts
        amountcols = [False, False, True, True, True, True, True, False, True, False, True, False]
        hcell cls t = plain <$> (headerCell t){Ods.cellClass = Ods.Class cls}
        -- body cells are right-aligned, except the first two columns
        -- (Account and Date); headings are unaffected
        bodycell :: Ods.Lines border => Int -> T.Text -> content' -> Ods.Cell border content'
        bodycell i cls t = (Ods.defaultCell t)
          {Ods.cellType = if i < 2 then Ods.TypeString else Ods.TypeMixedAmount
          ,Ods.cellClass = Ods.Class cls}
        totalcell i cls = bodycell i (cls <> " coltotal")
        -- indent tree-mode account names with no-break spaces
        acctcell r = T.replicate (prrIndent r * 2) "\160" <> prrDisplayName r

    -- Each commodity amount gets its own span with an "amount" class,
    -- so eg wrapping within amounts can be prevented with css.
    htmltable :: [[Ods.Cell Ods.NumLines Html]]
    htmltable = spreadsheetWith toHtml partsHtml
      where
        partsHtml isamount parts =
          mconcat $ intersperse (toHtml (", "::T.Text)) $
          map (\p -> if isamount then (H.span ! A.class_ "amount") (toHtml p) else toHtml p) $
          filter (not . T.null) parts

    fodstable :: [[Ods.Cell Ods.NumLines T.Text]]
    fodstable = spreadsheetWith id (\_ -> T.intercalate ", " . filter (not . T.null))

    -- Sum amounts per commodity, keeping an empty list empty
    -- (unlike amounts . mixed, which would make it a single zero).
    sumAmounts :: [Amount] -> [Amount]
    sumAmounts [] = []
    sumAmounts as = amounts $ mixed as

    -- A report row's holdings, one per commodity, in the same order as its
    -- unit amounts. With -E/--empty, these are followed by a zero-units
    -- holding for each commodity no longer held at or under the row's
    -- account but with realised gains, keeping those visible (eg a
    -- commodity fully sold off); without -E such rows are hidden (their
    -- gains still count in the totals row).
    rowHoldings :: PeriodicReportRow DisplayName MixedAmount -> [Holding]
    rowHoldings r = map rec $ heldamts ++ rgainonlyamts
      where
        acct = prrFullName r
        heldamts = rowUnitAmounts r
        rgainonlyamts
          | not $ empty_ ropts = []
          | otherwise =
              [ nullamt{acommodity=c}
              | c <- nubSort [ c2 | ((sub, c2), g) <- M.toAscList rgainmap
                                  , rowScope acct sub
                                  , not $ amountLooksZero g ]
              , c `notElem` map acommodity heldamts
              ]
        rec qa = Holding
          { hAccount   = acct
          , hCommodity = c
          , hDate      = mdate
          , hAge       = diffDays reportdate <$> mdate
          , hUnits     = styleAmounts styles qa
          , hUnitCost  = mucost
          , hCost      = sumAmounts ccosts
          , hPrice     = prices
          , hValue     = vals
          , hWeight    = weightPct vals
          , hUgain     = gains
          , hUgainPct  = gainPct gains ccosts
          , hRgain     = sumAmounts $ map (rowCostValuer r) $ rgainsOf acct (Just c)
          , hXirr      = mxirr
          }
          where
            c = acommodity qa
            clots = filter ((==c) . acommodity . fst) $ lotsOf acct
            dates = nubSort [cbDate =<< mcb | (_, mcb) <- clots]
            mdate = case dates of
              [Just dt] -> Just dt
              _         -> Nothing
            ccosts = [rowCostValuer r $ multiplyAmount (aquantity a) cb | (a, mcb) <- clots, Just cb <- [cbCost =<< mcb]]
            mucost = case (clots, ccosts) of
              ([(_, mcb)], _) -> rowCostValuer r <$> (cbCost =<< mcb)
              (_, _:_) | [totcost] <- amounts (mixed ccosts)
                       , not $ amountLooksZero qa
                       -> Just $ avgcost qa totcost
              _ -> Nothing
            -- The line's lots to value; a zero-units (rgain-only) line
            -- values a synthetic zero lot, so a market price and a zero
            -- value can still be shown.
            vlots = if null clots then [(qa, Nothing)] else clots
            (prices, vals) = fromMaybe ([], []) $ lotsValuation vlots
            gains = fromMaybe [] $ gainAmounts vals ccosts
            mxirr = do
              [v] <- Just vals
              xirrOf (flowsOf acct (Just c)) v

    -- Machine-readable records for the csv/tsv/json output, one per
    -- displayed table line. No totals records.
    holdingrecords :: [Holding]
    holdingrecords = map snd rowlines

    csvoutput :: CSV
    csvoutput =
      ["account","commodity","date","age","units","unitcost","price","cost","value","weight","ugain","ugainpct","rgain","xirr"]
      : map holdingCsv holdingrecords

    -- Grand totals row (as cell parts, like rowCellParts): the Units,
    -- Avg cost, Cost, Value and gain columns, summed over the topmost
    -- displayed rows (which include everything below them).
    -- Units, and the average cost per unit, are shown only when the
    -- holdings are all in one commodity (a multi-commodity total would
    -- widen the column for everyone, and a multi-commodity average is
    -- not meaningful); the average also needs a single cost commodity.
    -- Value and gains are blank unless all rows have a market price.
    mtotalrowparts :: Maybe [[T.Text]]
    mtotalrowparts
      | no_total_ ropts = Nothing
      | otherwise = Just [[], [], unitsparts, avgcostparts, [], costparts, valueparts, [weightcell], ugainparts, [ugainpctcell], rgainparts, [xirrcell]]
      where
        totunits = filter (not . amountLooksZero) $ sumAmounts $
                   concatMap (map fst . lotsUnder . prrFullName) toprows
        unitsparts = case totunits of
          [u] -> [showamt u]
          _   -> []
        avgcostparts = case (totunits, sumAmounts totcosts) of
          ([u], [c]) -> [showamt $ avgcost u c]
          _          -> []
        totcosts = [ rowCostValuer r $ multiplyAmount (aquantity a) c
                   | r <- toprows, (a, mcb) <- lotsUnder (prrFullName r), Just c <- [cbCost =<< mcb] ]
        costparts = map showamt $ amounts $ mixed totcosts
        (valueparts, weightcell, ugainparts, ugainpctcell) = case mportfoliovalue of
          Nothing -> ([], "", [], "")
          Just totvalue -> ( map showamt totvalue
                           , maybe "" showpct $ weightPct totvalue
                           , maybe [] (map showamtz) mtotgains
                           , maybe "" showpct $ gainPct (fromMaybe [] mtotgains) totcosts)
            where mtotgains = gainAmounts totvalue totcosts
        rgainparts = case map (costValuerTo mportvaluecomm) $ concatMap (\b -> rgainsUnder b Nothing) topbases of
          [] -> []
          rs -> map showamt $ amounts $ mixed rs
        xirrcell = fromMaybe "" $ do
          totvalue <- mportfoliovalue
          [tv] <- Just totvalue
          showxirr <$> xirrOf (concatMap (\b -> flowsUnder b Nothing) topbases) tv
        showamt = T.pack . showAmountWith noCostFmt
        showamtz = T.pack . showAmountWith noCostFmt{displayZeroCommodity=True}

    -- An average cost: total cost / total units, shown like other amounts
    -- in the cost commodity's display precision - but with at least 2
    -- decimal digits when the division is inexact and the display
    -- precision is less, so eg an average of $56.666... is not shown as
    -- the misleading $57.
    avgcost qtya costa = amountSetPrecision (Precision p) avg
      where
        avg  = divideAmountAndUpdatePrecision (aquantity qtya) costa
        p = clamp pstyle (max 2 pstyle) pdiv
        clamp lo hi = max lo . min hi
        pdiv = case asprecision (astyle avg) of Precision n -> n; _ -> defaultMaxDisplayPrecision
        pstyle = case asprecision (astyle costa) of Precision n -> n; _ -> 2
