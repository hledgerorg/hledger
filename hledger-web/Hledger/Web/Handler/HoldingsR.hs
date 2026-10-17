-- | /holdings handlers.

{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Hledger.Web.Handler.HoldingsR where

import Data.List (sortOn, zipWith4)
import Data.Map.Strict qualified as M
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
   lotsLinks, removeInacct, replaceInacct, reportLinks, sortLinks,
   zeroBalanceLinks)

-- | The holdings view: investment holdings and their performance at the
-- report end date, as the holdings command shows them. In tree mode the
-- positions are grouped under account heading rows. With lots=1, each
-- position's lots are shown: one row per lot in list mode, or folded
-- under their position in tree mode.
getHoldingsR :: Handler Html
getHoldingsR = do
  checkServerSideUiEnabled
  VD{jfull, jHasLots, lotsShown, q, qopts, qparam, opts, today, trs} <- getViewData
  require ViewPermission
  hideEmpty <- hideEmptyAccounts
  params <- reqGetParams <$> getRequest
  urlrender <- getUrlRenderParams
  mclosedparam <- lookupGetParam "closed"
  let withFilter t = if q /= Any then trf trs "{title}, filtered" [("title", t)] else t
      rspecOrig = reportspec_ $ cliopts_ opts
      roptsOrig = _rsReportOpts rspecOrig
      deepest = deepestDepth rspecOrig jfull
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
    -- TRANSLATORS: the browser tab title of this page.
    setTitleI (HMsg "holdings - hledger-web")
    case reportParams today rspecOrig qparam q qopts hideEmpty params >>= checkValue of
      Left err -> Yesod.toWidget $ do
        H.h2 $ H.toHtml $ withFilter $ reportTitle roptsOrig $ tr trs "Holdings"
        paramError trs err
      Right ReportParams{rpRopts, rpRspec, rpPeriod, rpValue} -> do
        let ropts = rpRopts
              { empty_ = closedShown
              -- Keep the command line's boring parent squashing in tree
              -- mode (reportParams turns it off for the balance pages):
              -- the account tree built below squashes childless chains
              -- the same way.
              , no_elide_ = no_elide_ roptsOrig
              }
            -- The displayed positions, always computed as the flat report:
            -- disjoint rows, one per account and commodity (or per lot,
            -- with lots shown in list mode). Tree mode groups them below.
            rspec = rpRspec{_rsReportOpts = ropts{accountlistmode_ = ALFlat}}
            rpt = holdingsReport
                    HoldingsReportOpts{hroLots = lotsShown && not isTree, hroRounding = HardRounding}
                    rspec jfull
            -- With lots shown in tree mode, a second report gives each
            -- position's lots, shown folded under it.
            mlotsrpt
              | isTree && lotsShown = Just $ holdingsReport
                  HoldingsReportOpts{hroLots = True, hroRounding = HardRounding} rspec jfull
              | otherwise = Nothing
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
            closedParams = [("closed", if closedShown then "1" else "0") | closedShown /= empty_ roptsOrig]
            emptyParams = [("empty", if hideEmpty then "0" else "1") | hideEmpty /= empty_ roptsOrig]
            lotsParams  = [("lots", "1") | lotsShown]
            pageParams =
              dbg1 "holdings pageParams" $
              periodParams ++ valParams ++ listParams ++ sortParams ++
              inferParams ++ closedParams ++ emptyParams ++ lotsParams
            qParams = [("q", qparam) | not (T.null qparam)]
            -- Links to the other reports keep the search, minus any
            -- account term, which the reports ignore, and this page's
            -- parameters.
            menuParams = [("q", qt) | let qt = T.unwords $ removeInacct qparam, not (T.null qt)] ++ pageParams
            -- An account cell links to the account's register, keeping
            -- the states that page reads.
            registerKept = removeAttributes ["period", "sort", "closed"] pageParams
            acctlink acct = urlrender RegisterR $
              ("q", replaceInacct qparam $ accountQuery acct) : registerKept

            -- TRANSLATORS: the holdings table's column headings. The cost
            -- heading is "Unit cost", "Avg cost", or "Unit/Avg cost".
            colheadings =
              [ tr trs "Date", tr trs "Age", tr trs "Units", tr trs (hrUnitCostHeading $ fromMaybe rpt mlotsrpt)
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

            acctcell r =
              (defaultCell $ strippedName (prrFullName r))
                { cellClass = Class $ T.unwords $
                    ["account", "acct-split"] ++
                    ["lot" | isJust $ lotSubaccountName $ prrFullName r]
                , cellAnchor = acctlink (prrFullName r)
                , cellTitle = prrFullName r <> "\n" <>
                    -- TRANSLATORS: the tooltip of a holding's account link.
                    tr trs "Show this account's register"
                }

            -- In tree mode, an account, commodity, or lot cell at the given
            -- depth (a fold point; hledger.js), linking to the register.
            treecell d extracls content acct =
              (defaultCell content)
                { cellClass = Class $ T.unwords $
                    ["account", "depth-" <> T.pack (show (d :: Int))] ++ extracls
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

            -- Tree mode groups the flat rows by account itself, rather
            -- than using the CLI tree report, whose account-and-commodity
            -- rows repeat every commodity at every tree level, multiplying
            -- the rows beyond use on a many-commodity journal. An account
            -- with subaccounts or several commodities is a heading row,
            -- with its own positions beneath it, named by their commodity,
            -- then its subaccounts; an account with one commodity and no
            -- subaccounts is a single combined row. With lots shown, each
            -- position's lots are beneath it, starting folded.
            posByAcct = M.fromListWith (flip (++)) [(hAccount h, [h]) | (_, h) <- hrRows rpt]
            lotsByPos = case mlotsrpt of
              Nothing -> M.empty
              Just lr -> M.fromListWith (flip (++))
                [((lotBaseAccount (hAccount h), hCommodity h), [h]) | (_, h) <- hrRows lr]
            -- each account's subtree's first flat row, ordering subtrees
            -- as the flat report's sort ordered their rows
            subtreeIxMap = M.fromListWith min
              [(a, ix) | (ix, (_, h)) <- zip [0 :: Int ..] (hrRows rpt), a <- expandAccountName (hAccount h)]
            allaccts = M.keys subtreeIxMap
            kidsMap = M.map (sortOn (`M.lookup` subtreeIxMap)) $ M.fromListWith (++)
              [(parentAccountName a, [a]) | a <- allaccts, accountNameLevel a > 1]
            kidsOf a = M.findWithDefault [] a kidsMap
            subtreeHoldings a = concat [hs | (a2, hs) <- M.toList posByAcct, a == a2 || a `isAccountNamePrefixOf` a2]
            -- squash boring parents into their child, as the CLI tree does
            elide disp acct
              | not (no_elide_ ropts), M.notMember acct posByAcct, [c] <- kidsOf acct =
                  elide (disp <> ":" <> accountLeafName c) c
              | otherwise = (disp, acct)
            treeRows = concatMap (treeNode 0) [a | a <- allaccts, accountNameLevel a == 1]
            treeNode d acct0 = case (M.findWithDefault [] acct posByAcct, kidsOf acct) of
              ([h], []) -> holdingRow (treecell d [] disp acct) h : lotRows (d+1) acct h
              (own, kids) ->
                headingRow d disp acct :
                concat [ holdingRow (treecell (d+1) ["commodity"] (hCommodity h) acct) h
                           : lotRows (d+2) acct h
                       | h <- own ] ++
                concatMap (treeNode (d+1)) kids
              where (disp, acct) = elide (accountLeafName acct0) acct0
            lotRows d acct h =
              [ holdingRow (treecell d ["lot"] (fromMaybe (hAccount lh) $ lotSubaccountName $ hAccount lh) (hAccount lh)) lh
              | lh <- M.findWithDefault [] (acct, hCommodity h) lotsByPos ]

            -- An account heading row: the summable dollar columns, summed
            -- over the subtree's rows with the totals row's rules; dates,
            -- units, unit prices, and XIRR do not aggregate and stay blank.
            headingRow d disp acct =
              treecell d ["acctheading"] disp acct :
              zipWith4 datacell coltypes
                [ "date", "age", "units", "unitcost", "unitprice", "totalcost", "totalvalue", "weight"
                , "ugain" <> signcls ugainsum, "ugainpct", "rgain" <> signcls rgainsum, "xirr" ]
                amountcols
                [ [], [], [], [], []
                , map showamt costsum
                , maybe [] (map showamtz) mvaluesum
                , [maybe "" showpct mweightsum]
                , map showamtz ugainsum
                , [maybe "" showpct mugainpct]
                , map showamt rgainsum
                , []
                ]
              where
                hs = subtreeHoldings acct
                sumAmts as = if null as then [] else amounts (mixed as)
                costsum  = sumAmts $ concatMap hCost hs
                rgainsum = sumAmts $ concatMap hRgain hs
                -- as in the totals row, no value or gains are shown unless
                -- every position beneath has a market value
                mvaluesum
                  | all (not . null . hValue) hs = Just $ sumAmts $ concatMap hValue hs
                  | otherwise = Nothing
                mweightsum = sum <$> traverse hWeight hs
                ugainsum = fromMaybe [] $ do
                  vs <- mvaluesum
                  guard $ not (null vs) && map acommodity vs == map acommodity costsum
                  Just $ zipWith gain1 vs costsum
                gain1 v c = styleAmounts (hrStyles rpt) $ amountSetFullPrecisionUpTo Nothing
                  nullamt{acommodity = acommodity v, aquantity = aquantity v - aquantity c}
                mugainpct = do
                  [g] <- Just ugainsum
                  [c] <- Just costsum
                  guard $ acommodity g == acommodity c && aquantity c /= 0
                  Just $ 100 * aquantity g / abs (aquantity c)

            body | isTree    = treeRows
                 | otherwise = [holdingRow (acctcell r) h | (r, h) <- hrRows rpt]

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
              , closedLinks trs HoldingsR (qParams ++ removeAttributes ["closed"] pageParams) (not $ empty_ roptsOrig) (not closedShown)
              , zeroBalanceLinks trs HoldingsR (qParams ++ removeAttributes ["empty"] pageParams) (empty_ roptsOrig) hideEmpty ] ++
              [ depthLinks trs HoldingsR pageParams qparam deepest | deepest > 1 ] ++
              [ listModeLinks trs HoldingsR (qParams ++ removeAttributes ["list"] pageParams) (accountlistmode_ roptsOrig) (accountlistmode_ ropts)
              , holdingsValueLinks trs HoldingsR (qParams ++ removeAttributes ["value"] pageParams) (isJust $ value_ ropts)
              , sortLinks trs HoldingsR (qParams ++ removeAttributes ["sort"] pageParams) (sort_amount_ ropts) ]
        Yesod.toWidget $ H.h2 $ H.toHtml $ withFilter title
        Yesod.toWidget controlRows
        Yesod.toWidget $ reportTable isTree (isTree && lotsShown) mfold header [(mprefixHeading, body, [])] totals
