{-# LANGUAGE CPP                 #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections       #-}
{-|

Multi-column balance reports, used by the balance command.

-}

module Hledger.Reports.MultiBalanceReport (
  MultiBalanceReport,
  MultiBalanceReportRow,

  multiBalanceReport,
  multiBalanceReportWith,

  compoundBalanceReport,
  compoundBalanceReportWith,

  -- * Helper functions
  makeReportQuery,
  getPostings,
  generateMultiBalanceAccount,
  generatePeriodicReport,
  makePeriodicReportRow,

  -- -- * Tests
  tests_MultiBalanceReport
)
where

#if !MIN_VERSION_base(4,18,0)
import Control.Applicative (liftA2)
#endif
import Control.Monad (guard)
import Data.Foldable (toList)
import Data.HashSet qualified as HS
import Data.List (sortOn)
import Data.List.NonEmpty (NonEmpty((:|)))
import Data.Map qualified as M
import Data.Maybe (fromMaybe, isJust)
import Data.Ord (Down(..))
import Data.Semigroup (sconcat)
import Data.These (these)
import Data.Time.Calendar (Day(..), fromGregorian)
import Data.Traversable (mapAccumL)

import Hledger.Data
import Hledger.Query
import Hledger.Utils
import Hledger.Reports.ReportOptions
import Hledger.Reports.ReportTypes


-- | A multi balance report is a kind of periodic report, where the amounts
-- correspond to balance changes or ending balances in a given period. It has:
--
-- 1. a list of each column's period (date span)
--
-- 2. a list of rows, each containing:
--
--   * the full account name, display name, and display depth
--
--   * A list of amounts, one for each column.
--
--   * the total of the row's amounts for a periodic report
--
--   * the average of the row's amounts
--
-- 3. the column totals, and the overall grand total (or zero for
-- cumulative/historical reports) and grand average.

type MultiBalanceReport    = PeriodicReport    DisplayName MixedAmount
type MultiBalanceReportRow = PeriodicReportRow DisplayName MixedAmount


-- | Generate a multicolumn balance report for the matched accounts,
-- showing the change of balance, accumulated balance, or historical balance
-- in each of the specified periods. If the normalbalance_ option is set, it
-- adjusts the sorting and sign of amounts (see ReportOpts and
-- CompoundBalanceCommand). hledger's most powerful and useful report, used
-- by the balance command (in multiperiod mode) and (via compoundBalanceReport)
-- by the bs/cf/is commands.
multiBalanceReport :: ReportSpec -> Journal -> MultiBalanceReport
multiBalanceReport rspec j = multiBalanceReportWith rspec j (journalPriceOracle infer j)
  where infer = infer_prices_ $ _rsReportOpts rspec

-- | A helper for multiBalanceReport. This one takes some extra arguments,
-- a 'PriceOracle' to be used for looking up market prices, and a set of
-- 'AccountName's which should not be elided. Commands which run multiple
-- reports (bs etc.) can generate the price oracle just once for efficiency,
-- passing it to each report by calling this function directly.
multiBalanceReportWith :: ReportSpec -> Journal -> PriceOracle -> MultiBalanceReport
multiBalanceReportWith rspec' j priceoracle = report
  where
    -- Queries, report/column dates.
    (reportspan, colspans) = dbg5 "multiBalanceReportWith reportSpan" $ reportSpan j rspec'
    rspec = dbg3 "multiBalanceReportWith rspec" $ makeReportQuery rspec' reportspan
    -- force evaluation order to show price lookup after date spans in debug output (XXX not working)
    -- priceoracle = reportspan `seq` priceoracle0

    -- Get postings
    ps = dbg5 "multiBalanceReportWith ps" $ getPostings rspec j priceoracle reportspan

    -- Process changes into normal, cumulative, or historical amounts, plus value them and mark which are uninteresting
    acct = dbg5 "multiBalanceReportWith acct" $ generateMultiBalanceAccount rspec j priceoracle colspans ps

    -- Generate and postprocess the report, negating balances and taking percentages if needed
    report = dbg4 "multiBalanceReportWith report" $ generateMultiBalanceReport (_rsReportOpts rspec) colspans acct

-- | Generate a compound balance report from a list of CBCSubreportSpec. This
-- shares postings between the subreports.
compoundBalanceReport :: ReportSpec -> Journal -> [CBCSubreportSpec a]
                      -> CompoundPeriodicReport a MixedAmount
compoundBalanceReport rspec j = compoundBalanceReportWith rspec j (journalPriceOracle infer j)
  where infer = infer_prices_ $ _rsReportOpts rspec

-- | A helper for compoundBalanceReport, similar to multiBalanceReportWith.
compoundBalanceReportWith :: ReportSpec -> Journal -> PriceOracle
                          -> [CBCSubreportSpec a]
                          -> CompoundPeriodicReport a MixedAmount
compoundBalanceReportWith rspec' j priceoracle subreportspecs = cbr
  where
    -- Queries, report/column dates.
    (reportspan, colspans) = dbg5 "compoundBalanceReportWith reportSpan" $ reportSpan j rspec'
    rspec = dbg3 "compoundBalanceReportWith rspec" $ makeReportQuery rspec' reportspan

    -- Get postings
    ps = dbg5 "compoundBalanceReportWith ps" $ getPostings rspec j priceoracle reportspan

    subreports = map generateSubreport subreportspecs
      where
        generateSubreport CBCSubreportSpec{..} =
            ( cbcsubreporttitle
            -- Postprocess the report, negating balances and taking percentages if needed
            , cbcsubreporttransform $ generateMultiBalanceReport ropts colspans acct
            , cbcsubreportincreasestotal
            )
          where
            ropts = cbcsubreportoptions $ _rsReportOpts rspec
            -- Add a restriction to this subreport to the report query.
            -- XXX in non-thorough way, consider updateReportSpec ?
            rspecsub = rspec{_rsReportOpts=ropts, _rsQuery=And [cbcsubreportquery, _rsQuery rspec]}
            -- Match and postings for the subreport
            subreportps = filter (matchesPostingExtra (journalAccountType j) cbcsubreportquery) ps
            -- Account representing this subreport
            acct = generateMultiBalanceAccount rspecsub j priceoracle colspans subreportps

    -- Sum the subreport totals by column. Handle these cases:
    -- - no subreports
    -- - empty subreports, having no subtotals (#588)
    -- - subreports with a shorter subtotals row than the others
    overalltotals = case subreports of
        []     -> PeriodicReportRow () [] nullmixedamt nullmixedamt
        (r:rs) -> sconcat $ fmap subreportTotal (r:|rs)
      where
        subreportTotal (_, sr, increasestotal) =
            (if increasestotal then id else fmap maNegate) $ prTotals sr

    cbr = CompoundPeriodicReport "" (maybeDayPartitionToDateSpans colspans) subreports overalltotals


-- | Remove any date queries and insert queries from the report span.
-- The user's query expanded to the report span
-- if there is one (otherwise any date queries are left as-is, which
-- handles the hledger-ui+future txns case above).
makeReportQuery :: ReportSpec -> DateSpan -> ReportSpec
makeReportQuery rspec reportspan
    | reportspan == nulldatespan = rspec
    | otherwise = rspec{_rsQuery=query}
  where
    query            = simplifyQuery $ And [dateless $ _rsQuery rspec, reportspandatesq]
    reportspandatesq = dbg3 "makeReportQuery reportspandatesq" $ dateqcons reportspan
    dateless         = dbg3 "makeReportQuery dateless" . filterQuery (not . queryIsDateOrDate2)
    dateqcons        = if date2_ (_rsReportOpts rspec) then Date2 else Date

-- | Gather postings matching the query within the report period.
getPostings :: ReportSpec -> Journal -> PriceOracle -> DateSpan -> [Posting]
getPostings rspec@ReportSpec{_rsQuery=query, _rsReportOpts=ropts} j priceoracle reportspan =
    setPostingsCount
    . filter hasAmount  -- omit postings with no definite amount (#2571)
    . journalPostings
    $ journalValueAndFilterPostingsWith rspec' j priceoracle
  where
    -- If doing --count, set all posting amounts to "1".
    setPostingsCount = case balancecalc_ ropts of
        CalcPostingsCount -> map (postingTransformAmount (const $ mixed [num 1]))
        _                 -> id

    rspec' = rspec{_rsQuery=fullreportq,_rsReportOpts=ropts'}
    -- If we're re-valuing every period, we need to have the unvalued start
    -- balance, so we can do it ourselves later.
    ropts' = if isJust (valuationAfterSum ropts)
        then ropts{period_=dateSpanAsPeriod fullreportspan, value_=Nothing}  -- If we're valuing after the sum, don't do it now
        else ropts{period_=dateSpanAsPeriod fullreportspan}

    -- q projected back before the report start date.
    -- When there's no report start date, in case there are future txns (the hledger-ui case above),
    -- we use emptydatespan to make sure they aren't counted as starting balance.
    fullreportq = dbg3 "getPostings fullreportq" $ And [datelessq, fullreportspanq]
    datelessq   = dbg3 "getPostings datelessq" $ filterQuery (not . queryIsDateOrDate2) depthlessq

    -- The user's query with no depth limit, and expanded to the report span
    -- if there is one (otherwise any date queries are left as-is, which
    -- handles the hledger-ui+future txns case above).
    depthlessq = dbg3 "getPostings depthlessq" $ filterQuery (not . queryIsDepth) query

    fullreportspan  = if requiresHistorical ropts then DateSpan Nothing (Exact <$> spanEnd reportspan) else reportspan
    fullreportspanq = (if date2_ ropts then Date2 else Date) $ case fullreportspan of
        DateSpan Nothing Nothing -> emptydatespan
        a -> a

-- | Generate the 'Account' for the requested multi-balance report from a list
-- of 'Posting's.
generateMultiBalanceAccount :: ReportSpec -> Journal -> PriceOracle -> Maybe DayPartition -> [Posting] -> Account BalanceData
generateMultiBalanceAccount rspec@ReportSpec{_rsReportOpts=ropts} j priceoracle colspans =
    -- Set account declaration info (for sorting purposes)
    mapAccounts (accountSetDeclarationInfo j)
    -- Add declared accounts if called with --declared and --empty
    . (if (declared_ ropts && empty_ ropts) then addDeclaredAccounts rspec j else id)
    -- Negate amounts if applicable
    . (if invert_ ropts then fmap (mapBalanceData maNegate) else id)
    -- Mark which accounts are boring and which are interesting
    . markAccountBoring rspec
    -- Process changes into normal, cumulative, or historical amounts, plus value them
    . calculateReportAccount rspec j priceoracle colspans
    -- Clip account names
    . map clipPosting
  where
    -- Clip postings to the requested depth according to the query
    clipPosting p = p{paccount = clipOrEllipsifyAccountName depthSpec $ paccount p}
    depthSpec = dbg3 "generateMultiBalanceAccount depthSpec"
              . queryDepth . filterQuery queryIsDepth $ _rsQuery rspec

-- | Add declared accounts to the account tree.
addDeclaredAccounts :: Monoid a => ReportSpec -> Journal -> Account a -> Account a
addDeclaredAccounts rspec j acct =
    these id id const <$> mergeAccounts acct declaredTree
  where
    declaredTree =
        mapAccounts (\a -> a{aboring = not $ aname a `HS.member` HS.fromList declaredAccounts}) $
          accountTreeFromBalanceAndNames "root" (mempty <$ adata acct) declaredAccounts

    -- With --declared, add the query-matching declared accounts (as dummy postings
    -- so they are processed like the rest).
    declaredAccounts =
      map (clipOrEllipsifyAccountName depthSpec) .
      filter (matchesAccountExtra (journalAccountType j) (journalAccountTags j) accttypetagsq) $
      journalAccountNamesDeclared j

    accttypetagsq  = dbg3 "addDeclaredAccounts accttypetagsq" .
      filterQueryOrNotQuery (\q -> queryIsAcct q || queryIsType q || queryIsTag q) $
      _rsQuery rspec

    depthSpec = queryDepth . filterQuery queryIsDepth $ _rsQuery rspec


-- | Gather the account balance changes into a regular matrix, then
-- accumulate and value amounts, as specified by the report options.
-- Makes sure all report columns have an entry.
calculateReportAccount :: ReportSpec -> Journal -> PriceOracle -> Maybe DayPartition -> [Posting] -> Account BalanceData
calculateReportAccount _ _ _ Nothing _ =
    accountFromBalances "root" $ periodDataFromList mempty [(nulldate, mempty)]
calculateReportAccount rspec@ReportSpec{_rsReportOpts=ropts} j priceoracle (Just colspans) ps =
    mapPeriodData rowbals changesAcct
  where
    -- The valued row amounts to be displayed: per-period changes,
    -- zero-based cumulative totals, or
    -- starting-balance-based historical balances.
    rowbals :: PeriodData BalanceData -> PeriodData BalanceData
    rowbals unvaluedChanges = case balanceaccum_ ropts of
        PerPeriod  -> changes
        Cumulative -> cumulative
        Historical -> historical
      where
        -- changes to report on: usually just the valued changes themselves, but use the
        -- differences in the valued historical amount for CalcValueChange and CalcGain.
        changes = case balancecalc_ ropts of
            CalcChange        -> avalue unvaluedChanges
            CalcBudget        -> avalue unvaluedChanges
            CalcValueChange   -> periodChanges historical
            CalcGain          -> periodChanges historical
            CalcPostingsCount -> avalue unvaluedChanges
        -- the historical balance is the valued cumulative sum of all unvalued changes
        historical = avalue $ cumulativeSum unvaluedChanges
        -- since this is a cumulative sum of valued amounts, it should not be valued again
        cumulative = cumulativeSum changes{pdpre = mempty}
        avalue = periodDataValuation ropts j priceoracle colspans

    changesAcct = dbg5With (\x -> "calculateReportAccount changesAcct\n" ++ showAccounts x) .
        mapPeriodData (padPeriodData mempty (dayPartitionToPeriodData colspans)) $
        accountFromPostings getIntervalStartDate ps

    getIntervalStartDate p = fst $ dayPartitionFind (getPostingDate p) colspans
    getPostingDate = postingDateOrDate2 (whichDate (_rsReportOpts rspec))

-- | The valuation function to use for the chosen report options.
periodDataValuation :: ReportOpts -> Journal -> PriceOracle -> DayPartition
                    -> PeriodData BalanceData -> PeriodData BalanceData
periodDataValuation ropts j priceoracle colspans =
    opPeriodData valueBalanceData (dayPartitionToPeriodData colspans)
  where
    valueBalanceData :: Day -> BalanceData -> BalanceData
    valueBalanceData d = mapBalanceData (valueMixedAmount d)

    valueMixedAmount :: Day -> MixedAmount -> MixedAmount
    valueMixedAmount = mixedAmountApplyValuationAfterSumFromOptsWith ropts j priceoracle

-- | Mark which nodes of an 'Account' are boring, and so should be omitted from reports.
markAccountBoring :: ReportSpec -> Account BalanceData -> Account BalanceData
markAccountBoring ReportSpec{_rsQuery=query,_rsReportOpts=ropts}
    -- If depth 0, all accounts except the top-level account are boring
    | qdepthIsZero = markBoring False . mapAccounts (markBoring True)
    -- Otherwise the top level account is boring, and subaccounts are boring if
    -- they are both boring in and of themselves and are boring parents
    | otherwise    = markBoring True . mapAccounts (markBoringBy (liftA2 (&&) isBoring isBoringParent))
  where
    -- Accounts boring on their own
    isBoring :: Account BalanceData -> Bool
    isBoring acct = tooDeep || allZeros
      where
        tooDeep = d > qdepth                                       -- Throw out anything too deep
        allZeros = isZeroRow balance amts && not keepEmptyAccount  -- Throw away everything with a zero balance in the row, unless..
        keepEmptyAccount = empty_ ropts && keepWhenEmpty acct      -- We are keeping empty rows and this row meets the criteria

        amts = pdperiods $ adata acct
        d = accountNameLevel $ aname acct

        qdepth = fromMaybe maxBound . getAccountNameClippedDepth depthspec $ aname acct
        balance = maybeStripPrices . case accountlistmode_ ropts of
            ALTree | d == qdepth -> bdincludingsubs
            _                    -> bdexcludingsubs

    -- Accounts which don't have enough interesting subaccounts
    isBoringParent :: Account a -> Bool
    isBoringParent acct = case accountlistmode_ ropts of
        ALTree -> notEnoughSubs || droppedAccount
        ALFlat -> True
      where
        notEnoughSubs = length interestingSubs < minimumSubs
        droppedAccount = accountNameLevel (aname acct) <= drop_ ropts
        interestingSubs = filter (anyAccounts (not . aboring)) $ asubs acct
        minimumSubs = if no_elide_ ropts then 1 else 2

    isZeroRow balance = all (mixedAmountLooksZero . balance)
    keepWhenEmpty acct = case accountlistmode_ ropts of
        ALTree -> null $ asubs acct     -- In tree mode, keep only empty leaves
        ALFlat -> hasPostings acct      -- In list mode, keep all accounts that have postings;
          || no_elide_ ropts && accountNameLevel (aname acct) > drop_ ropts && anyAccounts hasPostings acct
                                        -- or with --no-elide, also (undropped) parents of such accounts
      where hasPostings = any ((0<) . bdnumpostings) . pdperiods . adata
    maybeStripPrices = if conversionop_ ropts == Just NoConversionOp then id else mixedAmountStripCosts

    qdepthIsZero = depthspec == DepthSpec (Just 0) []
    depthspec = queryDepth query

    markBoring   v a = a{aboring = v}
    markBoringBy f a = a{aboring = f a}


-- | Build a report row.
--
-- Calculate the column totals. These are always the sum of column amounts.
generateMultiBalanceReport :: ReportOpts -> Maybe DayPartition -> Account BalanceData -> MultiBalanceReport
generateMultiBalanceReport ropts colspans =
    reportPercent ropts . generatePeriodicReport makeMultiBalanceReportRow bdincludingsubs id ropts colspans

-- | Lay out a set of postings grouped by date span into a regular matrix with rows
-- given by AccountName and columns by DateSpan, then generate a MultiBalanceReport
-- from the columns.
generatePeriodicReport :: Show c =>
    (forall a. ReportOpts -> (BalanceData -> MixedAmount) -> a -> Account b -> PeriodicReportRow a c)
    -> (b -> MixedAmount) -> (c -> MixedAmount)
    -> ReportOpts -> Maybe DayPartition -> Account b -> PeriodicReport DisplayName c
generatePeriodicReport makeRow treeAmt flatAmt ropts colspans acct =
    PeriodicReport (maybeDayPartitionToDateSpans colspans) (buildAndSort acct) totalsrow
  where
    -- Build report rows and sort them
    buildAndSort = dbg5 "generatePeriodicReport buildAndSort" . case accountlistmode_ ropts of
        ALTree | sort_amount_ ropts -> buildRows . sortTreeByAmount
        ALFlat | sort_amount_ ropts -> sortFlatByAmount . buildRows
        _                           -> buildRows . sortAccountTreeByDeclaration

    buildRows = buildReportRows makeRow ropts

    -- Calculate column totals from the inclusive balances of the root account
    totalsrow = dbg5 "generatePeriodicReport totalsrow" $ makeRow ropts bdincludingsubs () acct

    sortTreeByAmount = case fromMaybe NormallyPositive $ normalbalance_ ropts of
        NormallyPositive -> sortAccountTreeOn (\r -> (Down $ amt r, aname r))
        NormallyNegative -> sortAccountTreeOn (\r -> (amt r, aname r))
      where
        amt = mixedAmountStripCosts . sortKey . fmap treeAmt . pdperiods . adata
        sortKey = case balanceaccum_ ropts of
          PerPeriod -> maSum
          _         -> maybe nullmixedamt snd . M.lookupMax

    sortFlatByAmount = case fromMaybe NormallyPositive $ normalbalance_ ropts of
        NormallyPositive -> sortOn (\r -> (Down $ amt r, prrFullName r))
        NormallyNegative -> sortOn (\r -> (amt r, prrFullName r))
      where amt = mixedAmountStripCosts . flatAmt . prrTotal

-- | Build the report rows.
-- One row per account, with account name info, row amounts, row total and row average.
-- Rows are sorted according to the order in the 'Account' tree.
buildReportRows :: forall b c.
                (ReportOpts -> (BalanceData -> MixedAmount) -> DisplayName -> Account b -> PeriodicReportRow DisplayName c)
                -> ReportOpts -> Account b -> [PeriodicReportRow DisplayName c]
buildReportRows makeRow ropts = mkRows True (-drop_ ropts) 0
  where
    -- Build the row for an account at a given depth with some number of boring parents
    mkRows :: Bool -> Int -> Int -> Account b -> [PeriodicReportRow DisplayName c]
    mkRows isRoot d boringParents acct
        -- Account is boring and has no interesting children at any depth, so we stop
        | allBoring acct                 = []
        -- Account is a boring root account, and should be bypassed entirely
        | aboring acct && isRoot         = buildSubrows d 0
        -- Account is boring and has been dropped, so should be skipped and move up the hierarchy
        | aboring acct && d < 0          = buildSubrows (d + 1) 0
        -- Account is boring, and we can omit boring parents, so we should omit but keep track
        | aboring acct && canOmitParents = buildSubrows d (boringParents + 1)
        -- Account is not boring or otherwise should be displayed.
        | otherwise = makeRow ropts balance displayname acct : buildSubrows (d + 1) 0
      where
        displayname = displayedName d boringParents $ aname acct
        buildSubrows i b = concatMap (mkRows False i b) $ asubs acct

    canOmitParents = flat_ ropts || not (no_elide_ ropts)
    allBoring a = aboring a && all allBoring (asubs a)
    balance = case accountlistmode_ ropts of
        ALTree -> bdincludingsubs
        ALFlat -> bdexcludingsubs

    displayedName d boringParents name
        | d == 0 && name == "root" = DisplayName "..." "..." 0
        | otherwise = case accountlistmode_ ropts of
            ALTree -> DisplayName name leaf $ max 0 d
            ALFlat -> DisplayName name droppedName 0
      where
        leaf = accountNameFromComponents
               . reverse . take (boringParents + 1) . reverse
               $ accountNameComponents droppedName
        droppedName = accountNameDrop (drop_ ropts) name


-- | Build a report row.
--
-- Calculate the column totals. These are always the sum of column amounts.
makeMultiBalanceReportRow :: ReportOpts -> (BalanceData -> MixedAmount)
                          -> a -> Account BalanceData -> PeriodicReportRow a MixedAmount
makeMultiBalanceReportRow = makePeriodicReportRow nullmixedamt sumAndAverageMixedAmounts

-- | Build a report row.
--
-- Calculate the column totals. These are always the sum of column amounts.
makePeriodicReportRow :: c -> (M.Map Day c -> (c, c))
                      -> ReportOpts -> (b -> c)
                      -> a -> Account b -> PeriodicReportRow a c
makePeriodicReportRow nullEntry totalAndAverage ropts balance name acct =
    PeriodicReportRow name (toList rowbals) rowtotal avg
  where
    rowbals = fmap balance . pdperiods $ adata acct
    (total, avg) = totalAndAverage rowbals
    -- Total for a cumulative/historical report is always the last column.
    rowtotal = case balanceaccum_ ropts of
        PerPeriod -> total
        _         -> maybe nullEntry snd $ M.lookupMax rowbals

-- | Map the report rows to percentages if needed
reportPercent :: ReportOpts -> MultiBalanceReport -> MultiBalanceReport
reportPercent ropts report@(PeriodicReport spans rows totalrow)
  | percent_ ropts = PeriodicReport spans (map percentRow rows) (percentRow totalrow)
  | otherwise      = report
  where
    percentRow (PeriodicReportRow name rowvals rowtotal rowavg) =
      PeriodicReportRow name
        (zipWith perdivide rowvals $ prrAmounts totalrow)
        (perdivide rowtotal $ prrTotal totalrow)
        (perdivide rowavg $ prrAverage totalrow)

-- | A helper: what percentage is the second mixed amount of the first ?
-- Keeps the sign of the first amount.
-- Uses unifyMixedAmount to unify each argument and then divides them.
-- Both amounts should be in the same, single commodity.
-- This can call error if the arguments are not right.
perdivide :: MixedAmount -> MixedAmount -> MixedAmount
perdivide a b = fromMaybe (error' errmsg) $ do  -- PARTIAL:
    a' <- unifyMixedAmount a
    b' <- unifyMixedAmount b
    guard $ amountIsZero a' || amountIsZero b' || acommodity a' == acommodity b'
    return $ mixed [per $ if aquantity b' == 0 then 0 else aquantity a' / abs (aquantity b') * 100]
  where errmsg = "Cannot calculate percentages if accounts have different commodities (Hint: Try --cost, -V or similar flags.)"

-- | Calculate a cumulative sum from a list of period changes.
cumulativeSum :: Traversable t => t BalanceData -> t BalanceData
cumulativeSum = snd . mapAccumL (\prev new -> let z = prev <> new in (z, z)) mempty

-- | Extract period changes from a cumulative list.
periodChanges :: Traversable t => t BalanceData -> t BalanceData
periodChanges = snd . mapAccumL (\prev new -> (new, opBalanceData maMinus new prev)) mempty

-- tests

tests_MultiBalanceReport = testGroup "MultiBalanceReport" [

  let
    amt0 = Amount {acommodity="$", aquantity=0, acost=Nothing, acostbasis=Nothing,
      astyle=AmountStyle {ascommodityside = L, ascommodityspaced = False, asdigitgroups = Nothing,
      asdecimalmark = Just '.', asprecision = Precision 2, asrounding = NoRounding}}
    (rspec,journal) `gives` r = do
      let rspec' = rspec{_rsQuery=And [queryFromFlags $ _rsReportOpts rspec, _rsQuery rspec]}
          (eitems, etotal) = r
          (PeriodicReport _ aitems atotal) = multiBalanceReport rspec' journal
          showw (PeriodicReportRow a lAmt amt amt')
              = (displayFull a, displayName a, displayIndent a, map showMixedAmountDebug lAmt, showMixedAmountDebug amt, showMixedAmountDebug amt')
      (map showw aitems) @?= (map showw eitems)
      showMixedAmountDebug (prrTotal atotal) @?= showMixedAmountDebug etotal -- we only check the sum of the totals
  in
   testGroup "multiBalanceReport" [
      testCase "null journal"  $
      (defreportspec, nulljournal) `gives` ([], nullmixedamt)

     ,testCase "with -H on a populated period"  $
      (defreportspec{_rsReportOpts=defreportopts{period_= PeriodBetween (fromGregorian 2008 1 1) (fromGregorian 2008 1 2), balanceaccum_=Historical}}, samplejournal) `gives`
       (
        [ PeriodicReportRow (flatDisplayName "assets:bank:checking") [mixedAmount $ usd 1]    (mixedAmount $ usd 1)    (mixedAmount amt0{aquantity=1})
        , PeriodicReportRow (flatDisplayName "income:salary")        [mixedAmount $ usd (-1)] (mixedAmount $ usd (-1)) (mixedAmount amt0{aquantity=(-1)})
        ],
        mixedAmount $ usd 0)

     -- ,testCase "a valid history on an empty period"  $
     --  (defreportopts{period_= PeriodBetween (fromGregorian 2008 1 2) (fromGregorian 2008 1 3), balanceaccum_=Historical}, samplejournal) `gives`
     --   (
     --    [
     --     ("assets:bank:checking","checking",3, [mamountp' "$1.00"], mamountp' "$1.00",mixedAmount amt0 {aquantity=1})
     --    ,("income:salary","salary",2, [mamountp' "$-1.00"], mamountp' "$-1.00",mixedAmount amt0 {aquantity=(-1)})
     --    ],
     --    mixedAmount usd0)

     -- ,testCase "a valid history on an empty period (more complex)"  $
     --  (defreportopts{period_= PeriodBetween (fromGregorian 2009 1 1) (fromGregorian 2009 1 2), balanceaccum_=Historical}, samplejournal) `gives`
     --   (
     --    [
     --    ("assets:bank:checking","checking",3, [mamountp' "$1.00"], mamountp' "$1.00",mixedAmount amt0 {aquantity=1})
     --    ,("assets:bank:saving","saving",3, [mamountp' "$1.00"], mamountp' "$1.00",mixedAmount amt0 {aquantity=1})
     --    ,("assets:cash","cash",2, [mamountp' "$-2.00"], mamountp' "$-2.00",mixedAmount amt0 {aquantity=(-2)})
     --    ,("expenses:food","food",2, [mamountp' "$1.00"], mamountp' "$1.00",mixedAmount amt0 {aquantity=(1)})
     --    ,("expenses:supplies","supplies",2, [mamountp' "$1.00"], mamountp' "$1.00",mixedAmount amt0 {aquantity=(1)})
     --    ,("income:gifts","gifts",2, [mamountp' "$-1.00"], mamountp' "$-1.00",mixedAmount amt0 {aquantity=(-1)})
     --    ,("income:salary","salary",2, [mamountp' "$-1.00"], mamountp' "$-1.00",mixedAmount amt0 {aquantity=(-1)})
     --    ],
     --    mixedAmount usd0)
    ]
 ]
