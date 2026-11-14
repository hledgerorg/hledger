-- | /holdings handlers.

{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Hledger.Web.Handler.HoldingsR where

import Data.List (zipWith4)
import Data.Text qualified as T
import Text.Blaze.Html5 qualified as H
import Yesod qualified

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Commands.Holdings
import Hledger.Utils.I18n (tr, trf)
import Hledger.Write.Spreadsheet (Cell(..), Class(..), Type(..),
  addHeaderBorders, defaultCell, headerCell)

import Hledger.Web.Import
import Hledger.Web.Widget.AddForm (addModal)
import Hledger.Web.Handler.BalanceR (reportTitle)
import Hledger.Web.Paging (yearsRow)
import Hledger.Web.Param (Param(..), paramLinks, paramSettings)
import Hledger.Web.ReportPage
import Hledger.Web.WebOptions
import Hledger.Web.Widget.Chart (reportChart)
import Hledger.Web.Widget.Common
  (accountParams, closedLinks, commodityLinks, controlsToggle,
   depthLinks, holdingsValueLinks,
   lotsLinks, pricesLinks, realLinks, searchTerms,
   statusLinks, zeroBalanceLinks)

-- | The holdings view: investment holdings and their performance at the
-- report end date, as the holdings command shows them. In tree mode the
-- positions are grouped under account heading rows. With lots=1, each
-- position's lots are shown: one row per lot in list mode, or beneath
-- their position in tree mode.
getHoldingsR :: Handler Html
getHoldingsR = do
  checkServerSideUiEnabled
  VD{perms, j, jfull, lotsShown, q, qopts, qparam, opts, today, trs, hideEmpty, controlsOpen, commoditiesOpen} <- getViewData
  require ViewPermission
  params <- reqGetParams <$> getRequest
  urlrender <- getUrlRenderParams
  mclosedparam <- lookupGetParam "closed"
  let withFilter t = if filterQuery (not . queryIsDepth) q /= Any then trf trs "{title}, filtered" [("title", t)] else t
      rspecOrig = reportspec_ $ cliopts_ opts
      roptsOrig = _rsReportOpts rspecOrig
      -- The journal as displayed: with lots shown it includes the lot
      -- subaccounts, so the Depth row extends to them, as in hledger-ui.
      deepest = deepestDepth j
      -- Fully closed positions are hidden by default, as on the command
      -- line; the closed parameter (or startup -E) shows them. They have
      -- their own parameter because the empty parameter keeps its usual
      -- meaning here: the sidebar's zero-balance accounts.
      closedShown = case mclosedparam of
        Just "1" -> True
        Just "0" -> False
        _        -> empty_ roptsOrig
      -- Holdings are valued at a single date, so value=then has no
      -- meaning here, as on the command line.
      checkValue rp@ReportParams{rpRopts} = case value_ rpRopts of
        Just (AtThen _) -> Left ValueThenUnsupported
        _               -> Right rp

  defaultLayout $ do
    -- the add form, which the a key opens
    when (AddPermission `elem` perms) $ addModal AddR j today
    -- TRANSLATORS: the browser tab title of this page.
    setTitleI (HMsg "holdings - hledger-web")
    case reportParams rspecOrig qparam q qopts hideEmpty params >>= checkValue of
      Left err -> Yesod.toWidget $ do
        H.h2 $ H.toHtml $ withFilter $ reportTitle roptsOrig $ tr trs "Holdings"
        paramError trs err
      Right ReportParams{rpRopts, rpRspec, rpInterval, rpValue} -> do
        let ropts = rpRopts{empty_ = closedShown}
            -- Unlike the other report pages, a depth limit clips the tree
            -- here too, as on the command line, rather than folding it:
            -- clipping merges each clipped account's positions by
            -- commodity, which folding the full tree could not show.
            rspec = rpRspec{_rsQuery = q, _rsReportOpts = ropts}
            -- The report's display lines: flat positions (or lots with
            -- lots shown), or account sections in tree mode (see
            -- holdingsTreeLines).
            rpt = holdingsReport
                    HoldingsReportOpts{hroLots = lotsShown, hroRounding = HardRounding}
                    rspec jfull
            title = reportTitle ropts $
              -- TRANSLATORS: the holdings page's heading; {date} is the report date.
              trf trs "Holdings on {date}" [("date", showDate (hrDate rpt))]

            -- What links staying on this page keep: each report-shaping
            -- parameter that is not at its default, the interval too, which
            -- this page does not use but passes along.
            intervalParams = [("interval", w) | Just w <- [intervalPeriodExpr rpInterval]]
            valParams   = valueParams roptsOrig rpValue
            listParams  = paramSettings listParam (accountlistmode_ roptsOrig) (accountlistmode_ ropts)
            sortParams  = paramSettings sortParam False (sort_amount_ ropts)
            inferParams = [("infer", "1") | infer_prices_ ropts, not (infer_prices_ roptsOrig)]
            closedParams = [("closed", if closedShown then "1" else "0") | closedShown /= empty_ roptsOrig]
            emptyParams = [("empty", if hideEmpty then "0" else "1") | hideEmpty /= empty_ roptsOrig]
            lotsParams  = [("lots", "1") | lotsShown]
            pageParams =
              dbg1 "holdings pageParams" $
              intervalParams ++ valParams ++ listParams ++ sortParams ++
              inferParams ++ closedParams ++ emptyParams ++ lotsParams ++ depthParams q
            qParams = [("q", qparam) | not (T.null qparam)]
            -- An account cell links to the account's register, keeping
            -- the states that page reads.
            registerKept = removeAttributes ["interval", paramName sortParam, "closed"] pageParams
            acctlink acct = urlrender RegisterR $
              qParams ++ accountParams True acct ++ registerKept
            -- A position's cell links to that register filtered to the
            -- holding's commodity: the transactions behind the row's figures.
            poslink acct com = urlrender RegisterR $
              ("q", T.unwords $
                 map quoteIfSpaced (filter (not . T.isPrefixOf "cur:") (searchTerms qparam))
                 ++ [quoteIfSpaced $ "cur:" <> regexEscape com]) : accountParams True acct ++ registerKept

            -- TRANSLATORS: the holdings table's column headings. The cost
            -- heading is "Unit cost", "Avg cost", or "Unit/Avg cost".
            colheadings =
              [ tr trs "Date", tr trs "Age", tr trs "Units", tr trs (hrUnitCostHeading rpt)
              , tr trs "Unit price", tr trs "Total cost", tr trs "Total value", tr trs "Weight"
              , tr trs "UGain", tr trs "UGain%", tr trs "RGain", tr trs "XIRR" ]
            -- The figure columns' headings carry .amount too, aligning
            -- them over their right-aligned figures (hledger.css).
            header = [ addHeaderBorders $ zipWith3 hcell (TypeString : coltypes) ("account" : colclasses) (tr trs "Account" : colheadings) ]
            hcell typ cls t = (headerCell t){cellClass = Class $ if typ == TypeString then cls else cls <> " amount"}
            -- per-column css classes, as the holdings command's html output has
            colclasses = ["date","age","units","unitcost","unitprice","totalcost","totalvalue","weight","ugain","ugainpct","rgain","xirr"]
            -- which columns' cell parts are amounts, each shown in its own span
            amountcols = [False, False, True, True, True, True, True, False, True, False, True, False]
            -- the types give body cells their alignment: dates left, the rest right
            coltypes = TypeString : repeat TypeMixedAmount

            showpct  = showPercentWith (hrStyles rpt)
            showxirr = showpct . realToFrac
            showamt  = T.pack . showAmountWith noCostFmt
            showamtz = T.pack . showAmountWith noCostFmt{displayZeroCommodity=True}

            isTree = accountlistmode_ ropts == ALTree

            -- In list mode, what the account names share above their leaves
            -- is shown once, as a group heading over the table, and each row
            -- shows only the rest, with the part before its leaf dimmed
            -- (acct-split; see reportTable and .acct-path in hledger.css).
            -- The register links and their tooltips keep the full names.
            prefix
              | isTree = []
              | otherwise = case map (accountNameComponents . prrFullName . fst) (hrRows rpt) of
                  []    -> []
                  comps -> foldl1 commonPrefix (map init comps)  -- init: each leaf stays in its row
            commonPrefix (x:xs) (y:ys) | x == y = x : commonPrefix xs ys
            commonPrefix _ _ = []
            mprefixHeading = if null prefix then Nothing else Just (accountNameFromComponents prefix)
            strippedName = accountNameFromComponents . drop (length prefix) . accountNameComponents

            acctcell acct =
              (defaultCell $ strippedName acct)
                { cellClass = Class $ T.unwords $
                    ["account", "acct-split"] ++
                    ["lot" | isJust $ lotSubaccountName acct]
                , cellAnchor = acctlink acct
                , cellTitle = acct <> "\n" <>
                    -- TRANSLATORS: the tooltip of an account heading or lot's register link.
                    tr trs "Show this account's register"
                }

            -- In tree mode, an account, commodity, or lot cell at the given
            -- indent (a fold point; hledger.js), linking to the register.
            treecell d extracls content acct =
              (defaultCell content)
                { cellClass = Class $ T.unwords $
                    ["account", "indent-" <> T.pack (show (d :: Int))] ++ extracls
                , cellAnchor = acctlink acct
                , cellTitle = acct <> "\n" <> tr trs "Show this account's register"
                }

            -- a sign class for coloring gains, from the amounts' overall sign
            signcls amts = case compare (sum $ map aquantity amts) 0 of
              GT -> " positive"
              LT -> " negative"
              EQ -> ""

            -- a holding's cells (cf the holdings command's holdingCellParts)
            holdingRow acctc h =
              acctc :
              zipWith4 datacell coltypes
                [ "date", "age", "units", "unitcost", "unitprice", "totalcost", "totalvalue", "weight"
                , "ugain" <> signcls (hUgain h), "ugainpct", "rgain" <> signcls (hRgain h), "xirr" ]
                amountcols
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
            datacell typ cls isamount parts =
              (defaultCell $ T.intercalate ", " parts')
                { cellType = typ
                , cellClass = Class cls
                , cellParts = if isamount then parts' else []
                }
              where parts' = filter (not . T.null) parts

            -- A display line's row. In tree mode the lines are account
            -- sections (see holdingsTreeLines): heading rows showing each
            -- account's subtree totals, its positions named by their
            -- commodity beneath it, and with lots shown, each position's
            -- lots beneath it.
            lineRow (HoldingsHeading d acct disp tot) = headingRow d disp acct tot
            lineRow (HoldingsPosition d acct disp islot h)
              | isTree    = holdingRow (positioned $ treecell d cls disp acct) h
              | otherwise = holdingRow (positioned $ acctcell acct) h
              where
                cls | islot                 = ["lot"]
                    | disp == hCommodity h  = ["commodity"]
                    | otherwise             = []
                -- A lot subaccount's register holds only its commodity, so
                -- a lot cell keeps the plain account link.
                positioned c
                  | islot = c
                  | otherwise = c
                      { cellAnchor = poslink acct (hCommodity h)
                      , cellTitle = acct <> "\n" <>
                          -- TRANSLATORS: the tooltip of a position's register link, which filters to its commodity.
                          tr trs "Show this holding's register"
                      }

            -- An account heading row: the account's subtree totals,
            -- computed like the totals row (see hrAccountTotals).
            headingRow d disp acct tot =
              treecell d ["acctheading"] disp acct :
              zipWith4 datacell coltypes
                [ "date", "age", "units", "unitcost", "unitprice", "totalcost", "totalvalue", "weight"
                , "ugain" <> signcls (fromMaybe [] $ htUgain tot), "ugainpct", "rgain" <> signcls (htRgain tot), "xirr" ]
                amountcols
                (totalsParts tot)

            -- A totals row's data cell parts: the grand total's, or an
            -- account heading row's.
            totalsParts tot =
              [ []
              , []
              , maybe [] ((:[]) . showamt) (htUnits tot)
              , maybe [] ((:[]) . showamt) (htAvgCost tot)
              , []
              , map showamt (htCost tot)
              , maybe [] (map showamt) (htValue tot)
              , [maybe "" showpct (htWeight tot)]
              , maybe [] (map showamtz) (htUgain tot)
              , [maybe "" showpct (htUgainPct tot)]
              , map showamt (htRgain tot)
              , [maybe "" showxirr (htXirr tot)]
              ]

            body = map lineRow (hrLines rpt)

            totals =
              [ zipWith4 datacell (TypeString : coltypes)
                  ("account coltotal" : map (<> " coltotal") colclasses)
                  (False : amountcols) $
                  -- TRANSLATORS: the heading of the holdings table's totals row.
                  [tr trs "Total:"] : totalsParts (hrTotals rpt)
              ]
            -- The years the search matches in, ignoring all date
            -- narrowing: a year link sets the period, so the page shows
            -- the holdings at that year's end.
            yearsDays = map tdate $
              entriesReport rspecOrig{_rsQuery = filterQuery (\x -> not (queryIsDateOrDate2 x || queryIsDepth x)) q} jfull
            yearsNav = yearsRow trs HoldingsR qparam today pageParams yearsDays
            controlRows = controlsToggle trs controlsOpen (optionsSummary trs deepest pageParams) $ \render -> foldMap ($ render) $
              [ yearsNav
              , statusLinks trs HoldingsR pageParams qparam
              , realLinks trs HoldingsR pageParams qparam
              , commodityLinks trs HoldingsR pageParams qparam commoditiesOpen
                  -- TRANSLATORS: the hint below the commodity filter row.
                  (tr trs "Shift-click selects several commodities.") jfull ] ++
              [ depthLinks trs HoldingsR pageParams qparam deepest | deepest > 1 ] ++
              [ paramLinks listParam trs HoldingsR (qParams ++ pageParams) (accountlistmode_ roptsOrig) (accountlistmode_ ropts)
              , holdingsValueLinks trs HoldingsR (qParams ++ removeAttributes ["value"] pageParams) (isJust $ value_ ropts)
              , pricesLinks trs HoldingsR (qParams ++ removeAttributes ["infer"] pageParams) (infer_prices_ ropts)
              , zeroBalanceLinks trs HoldingsR (qParams ++ removeAttributes ["empty"] pageParams) (empty_ roptsOrig) hideEmpty
              , lotsLinks trs HoldingsR (qParams ++ removeAttributes ["lots"] pageParams) lotsShown
              , closedLinks trs HoldingsR (qParams ++ removeAttributes ["closed"] pageParams) (not $ empty_ roptsOrig) (not closedShown)
              , paramLinks sortParam trs HoldingsR (qParams ++ pageParams) False (sort_amount_ ropts) ]
        Yesod.toWidget controlRows
        Yesod.toWidget $ H.h2 $ H.toHtml $ withFilter title
        -- the chart, as holdings --chart draws it: a bar per holding, or per lot
        reportChart trs (withFilter title) $ holdingsReportAsChart ropts "" rpt
        Yesod.toWidget $ reportTable isTree Nothing header [(mprefixHeading, body, [])] totals
