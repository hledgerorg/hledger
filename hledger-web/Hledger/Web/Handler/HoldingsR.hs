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
import Hledger.Web.Handler.BalanceR (reportTitle)
import Hledger.Web.ReportPage
import Hledger.Web.WebOptions
import Hledger.Web.Widget.Common
  (accountQuery, closedLinks, depthLinks, holdingsValueLinks, listModeLinks,
   lotsLinks, removeInacct, replaceInacct, reportLinks, sortLinks)

-- | The holdings view: investment holdings and their performance at the
-- report end date, as the holdings command shows them. With lots=1, one
-- row per lot.
getHoldingsR :: Handler Html
getHoldingsR = do
  checkServerSideUiEnabled
  VD{jfull, jHasLots, lotsShown, q, qopts, qparam, opts, today, trs} <- getViewData
  require ViewPermission
  hideEmpty <- hideEmptyAccounts
  params <- reqGetParams <$> getRequest
  urlrender <- getUrlRenderParams
  memptyparam <- lookupGetParam "empty"
  let withFilter t = if q /= Any then trf trs "{title}, filtered" [("title", t)] else t
      rspecOrig = reportspec_ $ cliopts_ opts
      roptsOrig = _rsReportOpts rspecOrig
      deepest = deepestDepth rspecOrig jfull
      -- Fully closed positions are hidden by default, as on the command
      -- line; the empty parameter (or startup -E) shows them.
      closedShown = case memptyparam of
        Just "1" -> True
        Just "0" -> False
        _        -> empty_ roptsOrig
      -- Holdings are valued at a single date, so value=then has no
      -- meaning here, as on the command line.
      checkValue rp@ReportParams{rpRopts} = case value_ rpRopts of
        Just (AtThen _) -> Left ValueThenUnsupported
        _               -> Right rp

  defaultLayout $ do
    -- TRANSLATORS: the browser tab title of this page.
    setTitleI (HMsg "holdings - hledger-web")
    case reportParams today rspecOrig qparam q qopts hideEmpty params >>= checkValue of
      Left err -> Yesod.toWidget $ do
        H.h2 $ H.toHtml $ withFilter $ reportTitle roptsOrig $ tr trs "Holdings"
        paramError trs err
      Right ReportParams{rpRopts, rpRspec, rpPeriod, rpValue} -> do
        let ropts = rpRopts{empty_ = closedShown}
            rspec = rpRspec{_rsReportOpts = ropts}
            rpt = holdingsReport
                    HoldingsReportOpts{hroLots = lotsShown, hroRounding = HardRounding}
                    rspec jfull
            title = reportTitle ropts $
              -- TRANSLATORS: the holdings page's heading; {date} is the report date.
              trf trs "Holdings on {date}" [("date", showDate (hrDate rpt))]

            -- What links staying on this page keep: the period as given, and each
            -- report-shaping parameter that is not at its default.
            periodParams = [("period", p) | Just p <- [rpPeriod]]
            valParams   = valueParams roptsOrig rpValue
            listParams  = [("list", listWord (accountlistmode_ ropts)) | accountlistmode_ ropts /= accountlistmode_ roptsOrig]
            sortParams  = [("sort", "amount") | sort_amount_ ropts]
            inferParams = [("infer", "1") | infer_prices_ ropts, not (infer_prices_ roptsOrig)]
            emptyParams = [("empty", if closedShown then "1" else "0") | closedShown /= empty_ roptsOrig]
            lotsParams  = [("lots", "1") | lotsShown]
            pageParams =
              dbg1 "holdings pageParams" $
              periodParams ++ valParams ++ listParams ++ sortParams ++
              inferParams ++ emptyParams ++ lotsParams
            qParams = [("q", qparam) | not (T.null qparam)]
            -- Links to the other reports keep the search, minus any
            -- account term, which the reports ignore, and this page's
            -- parameters.
            menuParams = [("q", qt) | let qt = T.unwords $ removeInacct qparam, not (T.null qt)] ++ pageParams
            -- An account cell links to the account's register, keeping
            -- the states that page reads.
            registerKept = removeAttributes ["period", "sort"] pageParams
            acctlink acct = urlrender RegisterR $
              ("q", replaceInacct qparam $ accountQuery acct) : registerKept

            -- TRANSLATORS: the holdings table's column headings. The cost
            -- heading is "Unit cost", "Avg cost", or "Unit/Avg cost".
            colheadings =
              [ tr trs "Date", tr trs "Age", tr trs "Units", tr trs (hrUnitCostHeading rpt)
              , tr trs "Unit price", tr trs "Total cost", tr trs "Total value", tr trs "Weight"
              , tr trs "UGain", tr trs "UGain%", tr trs "RGain", tr trs "XIRR" ]
            header = [ addHeaderBorders $ zipWith hcell ("account" : colclasses) (tr trs "Account" : colheadings) ]
            hcell cls t = (headerCell t){cellClass = Class cls}
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
            mfold = mfilter (const isTree) $ dsFlatDepth $ queryDepth q

            acctcell r =
              (defaultCell $ T.replicate (prrIndent r * 2) "\160" <> prrDisplayName r)
                { cellClass = Class $ T.unwords $
                    -- in tree mode the depth class is a fold point (hledger.js)
                    ["account" <> if isTree then " depth-" <> T.pack (show (prrIndent r)) else ""] ++
                    ["lot" | isJust $ lotSubaccountName $ prrFullName r]
                , cellAnchor = acctlink (prrFullName r)
                -- TRANSLATORS: the tooltip of a holding's account link.
                , cellTitle = tr trs "Show this account's register"
                }

            -- a sign class for coloring gains, from the amounts' overall sign
            signcls amts = case compare (sum $ map aquantity amts) 0 of
              GT -> " positive"
              LT -> " negative"
              EQ -> ""

            -- a holding's cells (cf the holdings command's holdingCellParts)
            holdingCells (r, h) =
              acctcell r :
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

            body = map holdingCells (hrRows rpt)

            tot = hrTotals rpt
            totals =
              [ zipWith4 datacell (TypeString : coltypes)
                  ("account coltotal" : map (<> " coltotal") colclasses)
                  (False : amountcols) $
                  -- TRANSLATORS: the heading of the holdings table's totals row.
                  [tr trs "Total:"] :
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
              ]

            -- Every control the page responds to, one row of links each.
            controlRows render = foldMap ($ render) $
              [ reportLinks trs HoldingsR menuParams $ reportLinkItems $ reportMenuFor jHasLots
              , lotsLinks trs HoldingsR (qParams ++ removeAttributes ["lots"] pageParams) lotsShown
              , closedLinks trs HoldingsR (qParams ++ removeAttributes ["empty"] pageParams) (not $ empty_ roptsOrig) (not closedShown) ] ++
              [ depthLinks trs HoldingsR pageParams qparam deepest | deepest > 1 ] ++
              [ listModeLinks trs HoldingsR (qParams ++ removeAttributes ["list"] pageParams) (accountlistmode_ roptsOrig) (accountlistmode_ ropts)
              , holdingsValueLinks trs HoldingsR (qParams ++ removeAttributes ["value"] pageParams) (isJust $ value_ ropts)
              , sortLinks trs HoldingsR (qParams ++ removeAttributes ["sort"] pageParams) (sort_amount_ ropts) ]
        Yesod.toWidget $ H.h2 $ H.toHtml $ withFilter title
        Yesod.toWidget controlRows
        Yesod.toWidget $ reportTable isTree (isTree && lotsShown) mfold header [(Nothing, body, [])] totals
