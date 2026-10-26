-- | /register handlers.

{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE QuasiQuotes         #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TupleSections       #-}

module Hledger.Web.Handler.RegisterR where

import Data.List (intersperse, nub, partition, sortOn, zip4)
import Data.Map qualified as M
import Data.Ord (Down(..))
import Data.Set qualified as S
import Data.Text qualified as T
import Safe (readMay, tailSafe)
import Text.Blaze.Html5 qualified as H
import Text.Hamlet (hamletFile)

import Hledger.Utils.I18n (Translations, tr, trc, trf)
import Hledger
import Hledger.Cli.Chart (accountTransactionsReportAsChart)
import Hledger.Cli.CliOptions
import Hledger.Write.Chart (Chart(..))
import Hledger.Write.Chart.Svg (SvgOptions(..), chartSvgMarkupWith, defaultSvgOptions)
import Hledger.Web.Import
import Hledger.Web.Paging
import Hledger.Web.ReportPage qualified as Report
import Hledger.Web.ReportPage (amountModeOf, deepestDepth, depthParams, removeAttributes, listWord, parseCalc, parseInterval, parseListMode, parseValue, setAmountMode, valueParams)
import Hledger.Web.WebOptions
import Hledger.Web.Widget.AddForm (addModal)
import Hledger.Web.Widget.Common qualified as Report
import Hledger.Web.Widget.Common
             (accountParams, accountRegisterQuery,
              controlsToggle, optionsSummary, searchHeading,
              inertControls, mixedAmountAsHtmlElided,
              mixedAmountAsHtmlWith, moreCommodities,
              runningBalanceAsHtml,
              transactionFragment, removeDates, journalDayQuery)

-- | The main journal/account register view, with accounts sidebar.
getRegisterR :: Handler Html
getRegisterR = do
  checkServerSideUiEnabled
  VD{jHasLots, lotsShown, perms, j, q, opts, qparam, account, today, trs, hideEmpty, controlsOpen, commoditiesOpen} <- getViewData
  require ViewPermission
  -- With accum=historical the running balance is the account's balance,
  -- starting from before the query's start date, rather than a total of
  -- the transactions shown; a report's ending balance links here that way,
  -- so that the balance ends on the figure clicked.
  historical <- (== Just "historical") <$> lookupGetParam "accum"
  -- With a value parameter amounts are converted as a report page's
  -- figures were (see Hledger.Web.ReportPage.parseValue), so that its
  -- figures' registers end on them. One it does not know is ignored.
  mmode <- either (const Nothing) id . parseValue <$> lookupGetParam "value"
  mlist <- either (const Nothing) id . parseListMode <$> lookupGetParam "list"
  -- With costs=1 amounts keep the costs recorded with them (10 AAPL @ $95),
  -- which are stripped by default.
  costsOn <- (== Just "1") <$> lookupGetParam "costs"
  inferOn <- (== Just "1") <$> lookupGetParam "infer"
  date2On <- (== Just "1") <$> lookupGetParam "date2"
  minterval <- lookupGetParam "interval"
  totalOn <- (== Just "1") <$> lookupGetParam "total"
  avgOn   <- (== Just "1") <$> lookupGetParam "avg"
  sortAmt <- (== Just "amount") <$> lookupGetParam "sort"
  pctOn   <- (== Just "1") <$> lookupGetParam "pct"
  mcalc   <- lookupGetParam "calc"
  urlrender <- getUrlRenderParams
  pagereq <- pageRequest
  -- How wide to draw the chart: as wide as the page's main column, which
  -- the browser measures and keeps in the chartwidth cookie (hledger.js).
  mchartwidth <- (>>= readMay . T.unpack) <$> uiCookie "chartwidth"

  let title = case account of
        Nothing         -> tr trs "all accounts"
        Just (a, True)  -> a
        Just (a, False) -> trf trs "{account} (excluding subaccounts)" [("account", a)]
      header = searchHeading trs (date2_ (_rsReportOpts (reportspec_ (cliopts_ opts))) || date2On) q title
      -- what the chart's line is named in its tooltips: the account, or all accounts
      chartacct = maybe title fst account

  let rspec0 = reportspec_ (cliopts_ opts)
      ropts = maybe id setAmountMode mmode $
        (_rsReportOpts rspec0){
          balanceaccum_ = if historical then Historical else PerPeriod,
          show_costs_ = costsOn,
          infer_prices_ = infer_prices_ (_rsReportOpts rspec0) || inferOn,
          date2_ = date2_ (_rsReportOpts rspec0) || date2On}
      rspec = rspec0{_rsReportOpts = ropts}
      -- links staying on this register keep its modes
      valParams = valueParams (_rsReportOpts rspec0) mmode
      accumParams = [("accum", "historical") | historical]
      costsParams = [("costs", "1") | costsOn]
      inferParams = [("infer", "1") | inferOn]
      date2Params = [("date2", "1") | date2On]
      dfltHidden = empty_ $ _rsReportOpts rspec0
      emptyParams = [("empty", if hideEmpty then "0" else "1") | hideEmpty /= dfltHidden]
      elist = fromMaybe (accountlistmode_ $ _rsReportOpts rspec0) mlist
      listParams = [("list", listWord elist) | elist /= accountlistmode_ (_rsReportOpts rspec0)]
      -- The report-shaping state shapes nothing here, but it is passed
      -- along and shown dimmed below, so it survives visiting a register.
      stickyParams =
        [("interval", w) | Just w <- [mfilter (not . T.null) minterval]] ++
        [("total", "1") | totalOn] ++
        [("avg", "1") | avgOn] ++
        [("sort", "amount") | sortAmt] ++
        [("pct", "1") | pctOn] ++
        [("calc", c) | Just c <- [mcalc], not (T.null c)]
      lotsParams = [("lots", "1") | lotsShown]
      -- The account this register is for, which its own links keep.
      acctParams = maybe [] (\(a, subs) -> accountParams subs a) account
      modeParams =
        dbg1 "register modeParams" $
        acctParams ++ stickyParams ++ accumParams ++ valParams ++ costsParams ++ inferParams ++ date2Params ++ emptyParams ++ listParams ++ lotsParams ++ depthParams q
      -- Links to the journal carry the sticky state; the account, the
      -- accumulation mode and the costs toggle are this page's own.
      journalCarry = removeAttributes ["account", "subs", "accum", "costs"] modeParams
      -- An entry's date link: the journal on that date, same modes.
      dayParams t = ("q", journalDayQuery qparam (tdate t)) : journalCarry
      -- the rows of links above the chart: the filters (status,
      -- realness, type, tag, commodity, and depth), and the accounts,
      -- amounts, and costs modes
      statusRow = Report.statusLinks trs RegisterR modeParams qparam
      realRow = Report.realLinks trs RegisterR modeParams qparam
      typeRow = Report.typeLinks trs RegisterR modeParams qparam
      -- TRANSLATORS: the hint below the account type filter row.
      typeHintRow = Report.controlsHint $ tr trs "Shift-click selects several types."
      commodityRow = Report.commodityLinks trs RegisterR modeParams qparam commoditiesOpen
        -- TRANSLATORS: the hint below the commodity filter row.
        (tr trs "Shift-click selects several commodities.") j
      -- The depth links clip the sidebar's accounts, or in tree mode
      -- fold them, and carry to the reports; the register's rows always
      -- show in full.
      deepest = deepestDepth j
      depthRow = Report.depthLinks trs RegisterR modeParams qparam deepest
      -- Tree mode adds the sidebar's fold carets.
      listRow = Report.listModeLinks trs RegisterR (qParams qparam ++ removeAttributes ["list"] modeParams) (accountlistmode_ $ _rsReportOpts rspec0) elist
      amountsRow = Report.amountLinks trs RegisterR (qParams qparam ++ removeAttributes ["value"] modeParams)
        (amountModeOf $ _rsReportOpts rspec0) (amountModeOf ropts)
      costsRow = Report.costsLinks trs RegisterR (qParams qparam ++ removeAttributes ["costs"] modeParams) costsOn
      pricesRow = Report.pricesLinks trs RegisterR (qParams qparam ++ removeAttributes ["infer"] modeParams) inferOn
      zeroRow = Report.zeroBalanceLinks trs RegisterR (qParams qparam ++ removeAttributes ["empty"] modeParams) dfltHidden hideEmpty
      -- Lot detail shows lot subaccounts and per-lot postings; row
      -- hidden when the journal has no lots.
      lotsRow = if jHasLots
        then Report.lotsLinks trs RegisterR (qParams qparam ++ removeAttributes ["lots"] modeParams) lotsShown
        else const mempty
      -- The report-shaping controls, operative on the report pages,
      -- shown dimmed with the url's state marked.
      rpInterval = maybe NoInterval (either (const NoInterval) id . parseInterval) minterval
      calcCur = either (const CalcChange) id $ parseCalc mcalc
      -- The years row; its links rewrite the search's date narrowing themselves.
      yearsNav = yearsRow trs RegisterR qparam today modeParams years
      intervalRow = inertControls trs $
        Report.intervalLinks trs RegisterR (removeAttributes ["interval"] modeParams) qparam rpInterval
      inertRows = inertControls trs $ mconcat
        [ Report.columnsLinks trs RegisterR (qParams qparam ++ removeAttributes ["total", "avg"] modeParams) totalOn avgOn
        , Report.sortLinks trs RegisterR (qParams qparam ++ removeAttributes ["sort"] modeParams) sortAmt
        , Report.percentLinks trs RegisterR (qParams qparam ++ removeAttributes ["pct"] modeParams) pctOn
        , Report.calcLinks trs RegisterR (qParams qparam ++ removeAttributes ["calc"] modeParams) calcCur
        ]
      -- All of them behind the controls disclosure, closed by default,
      -- in the same order as on the report pages.
      controlsRows = controlsToggle trs controlsOpen (optionsSummary trs deepest modeParams) $ mconcat $
        [intervalRow, yearsNav, statusRow, realRow, typeRow, typeHintRow, commodityRow] ++ [depthRow | deepest > 1] ++
        [listRow, amountsRow, costsRow, pricesRow, zeroRow, lotsRow, inertRows]
      -- the amount column's display format: with costs when asked
      amtfmt = noCostFmt{displayZeroCommodity = True, displayCost = costsOn}
      qParams t = [("q", t) | not (T.null t)]
      acctQuery = maybe Any accountRegisterQuery account
      -- An account's register, keeping this register's mode, opened on the
      -- page holding this transaction.
      acctlink acc t = (RegisterR, qParams qparam ++ accountParams True acc ++ ("txn", T.pack $ show $ tindex t) : removeAttributes ["account", "subs"] modeParams)
      -- In an account's register a type: term selects the postings
      -- totaled, not the accounts named beside them: a liability's
      -- register names the accounts it was posted against, whatever their
      -- types. A register of all accounts of a type names those accounts.
      otherTransAccounts =
          map (\(acct,(name,comma)) -> (acct, (T.pack name, T.pack comma))) .
          undecorateLinks . elideRightDecorated 40 . decorateLinks .
          addCommas . preferReal . otherTransactionAccounts j displayq acctQuery
      displayq = if isJust account then filterQuery (not . queryIsType) q else q
      -- An account name, which breaks after a colon where the column is
      -- too narrow for it, rather than the amounts beside it.
      breakAtColons = mconcat . intersperse (toHtml (":" :: Text) <> H.wbr) . map toHtml . T.splitOn ":"
      addCommas xs =
          zip xs $
          zip (map (T.unpack . accountSummarisedName . paccount) xs) $
          tailSafe (", "<$xs) ++ [""]
      styles = journalCommodityStylesWith HardRounding j
      -- The matching transactions, newest first, and the balance brought
      -- forward from before them; this page shows one page of them.
      (startbal, allitems) =
        bimap (styleAmounts styles) (styleAmounts styles) $
        accountTransactionsReportWithStart rspec{_rsQuery=q} j acctQuery
      (page, items) = pageOf pagereq (tindex . triOrigTransaction) allitems
      -- The brought-forward row is older than every transaction, so it
      -- ends the last page.
      lastpage = pgNumber page >= pgCount page
      -- The chart is of every matching transaction, not only this page's.
      -- A point on this page links to its row; one on another page, to that
      -- page, opened at the row.
      onpage = S.fromList $ map (tindex . triOrigTransaction) items
      chartLink t
        | S.member (tindex t) onpage = frag
        | otherwise = urlrender RegisterR (qParams qparam ++ modeParams ++ [("txn", T.pack $ show $ tindex t)]) <> frag
        where frag = T.pack $ '#' : transactionFrag t
      -- The years the search matches in, ignoring any date term in it. A
      -- year's count is by register date, while its page matches date:YYYY
      -- against each posting's date, so a transaction with postings dated in
      -- two years is counted once and shown in both.
      years = map triDate $
        maybe allitems (\dq -> accountTransactionsReport rspec{_rsQuery = dq} j acctQuery) $
        datelessQuery today qparam
      balancelabel
        | historical               = trc trs "column heading" "Historical Total"
        | isJust account           = trc trs "column heading" "Period Total"
        | otherwise                = trc trs "column heading" "Total"
      -- The balance column's heading switches the mode, keeping the
      -- register's other modes.
      accumToggle = (RegisterR, qParams qparam ++ removeAttributes ["accum"] modeParams ++ [("accum", "historical") | not historical])
      accumToggleTitle
        | historical = tr trs "Click to show the running balance from the start of this period"
        | otherwise  = tr trs "Click to show the running balance including everything before this period"
      -- In historical mode with a start date, the balance brought forward
      -- from before it is the oldest row, linking to the transactions
      -- before the period: those before the start date by the kind of
      -- date (primary or secondary) the report took it from, as the
      -- report chooses the balance's cutoff.
      mstart = asum [ (,) secondary <$> queryStartDate secondary q
                    | secondary <- [date2_ ropts, not $ date2_ ropts] ]
      broughtForwardLink (secondary, start) =
        (RegisterR, [("q", T.unwords $
          ((if secondary then "date2:.." else "date:..") <> showDate start) : removeDates qparam)] ++
          removeAttributes ["accum"] modeParams)
      transactionFrag = transactionFragment j
  defaultLayout $ do
    -- TRANSLATORS: the browser tab title of this page.
    setTitleI (HMsg "register - hledger-web")
    -- the chart's styles
    unless (null items) $ addStylesheet ChartCssR
    $(widgetFile "register")

-- cf. Hledger.Reports.AccountTransactionsReport.accountTransactionsReportItems
otherTransactionAccounts :: Journal -> Query -> Query -> Transaction -> [Posting]
otherTransactionAccounts j reportq thisacctq torig
    -- no current account ? summarise all matched postings
    | thisacctq == None  = reportps
    -- only postings to current account ? summarise those
    | null otheraccts    = thisacctps
    -- summarise matched postings to other account(s)
    | otherwise          = otheracctps
    where
      -- given the account types, so that a type: term matches postings here as in the report
      reportps = tpostings $ filterTransactionPostingsExtra (journalAccountType j) reportq torig
      (thisacctps, otheracctps) = partition (matchesPosting thisacctq) reportps
      otheraccts = nub $ map paccount otheracctps

-- cf. Hledger.Reports.AccountTransactionsReport.summarisePostingAccounts
preferReal :: [Posting] -> [Posting]
preferReal ps
    | null realps = ps
    | otherwise   = realps
    where realps = filter isReal ps

elideRightDecorated :: Int -> [(Maybe d, Char)] -> [(Maybe d, Char)]
elideRightDecorated width s =
    if length s > width
        then take (width - 2) s ++ map (Nothing,) ".."
        else s

undecorateLinks :: [(Maybe acct, char)] -> [(acct, ([char], [char]))]
undecorateLinks [] = []
undecorateLinks xs0@(x:_) =
    case x of
        (Just acct, _) ->
            let (link, xs1) = span (isJust . fst) xs0
                (comma, xs2) = span (isNothing . fst) xs1
            in (acct, (map snd link, map snd comma)) : undecorateLinks xs2
        _ -> error' "link name not decorated with account"  -- PARTIAL:

decorateLinks :: [(acct, ([char], [char]))] -> [(Maybe acct, char)]
decorateLinks = concatMap $ \(acct, (name, comma)) ->
    map (Just acct,) name ++ map (Nothing,) comma

-- | The register's chart: hledger's SVG chart of the running balance (see
-- "Hledger.Cli.Chart"), drawn from every matching transaction's row, not
-- only this page's, as wide as the page's main column was last measured (or
-- by default, 880px). It has a chart per commodity, each on its own scale;
-- with several, a legend chooses the one shown, first the one with the most
-- transactions, and a note says how many more than ten are left out
-- (searching for a commodity, cur:, charts it). Each point links to its row
-- (see the link function given), and dragging across a plot shows the
-- transactions on those dates (registerChartInit, in hledger.js), so each
-- plot gives its date scale, and the chart the register's url without its
-- date terms. Its styles are served by ChartCssR, since the
-- Content-Security-Policy allows no inline styles.
registerChartHtml ::
  Translations -> Journal -> Day -> Maybe Int -> Text -> [(Text, Text)] -> (Transaction -> Text) -> Text -> Text ->
  AccountTransactionsReport -> HtmlUrl AppRoute
registerChartHtml trs j today mwidth q modeParams pointLink acct balancelabel items = $(hamletFile "templates/chart.hamlet")
 where
   nodatelink = (RegisterR, [("q", t) | let t = T.unwords $ removeDates q, not (T.null t)] ++ modeParams)
   -- The commodities charted: at most ten, those with the most transactions.
   -- The balances keep only those before the chart is made.
   counts = M.fromListWith (+) [(c, 1 :: Int) | i <- items, c <- nub $ map acommodity $ amounts $ triAmount i]
   charted = take 10 . map fst . sortOn (\(c, n) -> (Down n, c)) $ M.toList counts
   leftout = M.size counts - length charted
   -- the rows oldest first, as the chart's x positions are, each at its date in the register.
   -- A balance can hold every commodity, an amount one or two, so
   -- only the oldest balance is cut to the charted commodities; each later one
   -- is the one before plus its row's amount, cut, as the register sums them.
   keep = filterMixedAmount ((`elem` charted) . acommodity)
   rows = case reverse items of
     [] -> []
     (t, ta, s, as, a, b) : later -> scanl next (t, ta, s, as, a, keep b) later
   next (_, _, _, _, _, bal) (t, ta, s, as, a, _) = (t, ta, s, as, a, bal `maPlus` keep a)
   regdates = M.fromList [(tindex $ triOrigTransaction i, triDate i) | i <- rows]
   regdate t = M.findWithDefault (tdate t) (tindex t) regdates
   -- A chart for each commodity, with its one panel, and the rows its points
   -- are at, by position, for their links. It is drawn from the rows where
   -- the commodity's balance changes, and the first and last: the rest add
   -- nothing to its line, and drawing them all is slow when there are many
   -- rows and commodities.
   charts =
     [ (c, chart, M.fromDistinctAscList $ zip [0 ..] crows)
     | c <- charted
     , let crows = [(t, ta, s, as, a, filterMixedAmount ((== c) . acommodity) b) | (t, ta, s, as, a, b) <- changesIn c]
           chart = accountTransactionsReportAsChart (journalAccountType j) "" acct regdate crows
     , not $ null $ chPanels chart
     ]
   changesIn c = case rows of
     [] -> []
     r : later -> r : go (qty r) later
     where
       qty r = sum [aquantity a | a <- amountsRaw $ triBalance r, acommodity a == c]
       go _ [] = []
       go _ [r] = [r]
       go n (r : more) = let n' = qty r in if n' == n then go n more else r : go n' more
   -- the legend's entries: each chart's number, the chart, its commodity's name, and whether it is shown at first
   legend = zip4 [0 :: Int ..] charts (map commodityName charts) (True : repeat False)
   -- TRANSLATORS: the register chart's legend entry for amounts written without a commodity symbol.
   commodityName (c, _, _) = if T.null c then tr trs "no symbol" else c
   svgopts rowsat = defaultSvgOptions
     { svgStyles     = False
     , svgWidth      = maybe (svgWidth defaultSvgOptions) (fromIntegral . max 320 . min 2400) mwidth
     , svgPlotHeight = 150
     , svgPointLink  = \k -> pointLink . triOrigTransaction <$> M.lookup k rowsat
     , svgDateScale  = True
     , svgToday      = Just today
     }
   -- a commodity's chart as SVG, named for screen readers by the balance and the commodity
   svg (c, chart, rowsat) = chartSvgMarkupWith (svgopts rowsat) chart H.! H.customAttribute "aria-label" (H.toValue label)
     where label = if T.null c then balancelabel else balancelabel <> ": " <> c
