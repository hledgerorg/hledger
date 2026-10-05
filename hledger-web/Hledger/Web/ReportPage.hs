{-|
What hledger-web's report pages share: resolving their parameters
against the startup options, and rendering a report's cells as the
page's table.
-}

{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Hledger.Web.ReportPage (
  ReportParams(..),
  ReportParamError(..),
  reportParams,
  paramError,
  AmountMode(..),
  parseValue,
  parseListMode,
  listWord,
  valueWord,
  amountModeOf,
  setAmountMode,
  valueParams,
  addLinkParams,
  deepestDepth,
  accumWord,
  calcWord,
  columnHeading,
  relinkDateHeaders,
  reportTable,
) where

import Control.Monad (mfilter, unless)
import Data.Foldable (for_, traverse_)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar (Day)
import Text.Blaze.Html5 ((!))
import Text.Blaze.Html5 qualified as H
import Text.Blaze.Html5.Attributes qualified as A
import Text.Megaparsec.Error (errorBundlePretty)

import Hledger.Utils.I18n (Translations, tr, trf)
import Hledger
import Hledger.Cli.Anchor (dateTerm, renderPeriodHeading)
import Hledger.Query qualified as Query
import Hledger.Write.Html (Html, formatCell, nl)
import Hledger.Write.Spreadsheet (Cell(..), NumLines, textFromClass)

-- | A report page's parameters, resolved.
data ReportParams = ReportParams {
    rpRopts    :: ReportOpts,
      -- ^ The startup report options with the page's search, period, interval,
      --   and zero-item setting applied, and links made relative. The
      --   accumulation mode is left for the page to set.
    rpRspec    :: ReportSpec,
      -- ^ The startup report spec with those options and the page's query.
    rpSpan     :: DateSpan,
      -- ^ The period parameter's date span, or the unbounded span.
    rpInterval :: Interval,
      -- ^ The reporting interval: from a date: search term, else the period
      --   parameter, else startup.
    rpPeriod   :: Maybe Text,
      -- ^ The period parameter as given, for links that keep it.
    rpAccum    :: Maybe BalanceAccumulation,
      -- ^ The accum parameter, if one was given.
    rpValue    :: Maybe AmountMode
      -- ^ The value parameter, if one was given. rpRopts converts amounts
      --   as it says.
}

-- | A parameter the page cannot use, with what was given; or a
-- combination of parameters that contradict each other.
data ReportParamError
  = BadPeriod String | BadAccum Text | BadValue Text | BadParamValue Text Text
  | ValuechangeNeedsEnd | GainNotCost

-- | Resolve a report page's parameters: today's date, the startup report
-- spec, the search parameter and its parsed query and options, whether
-- zero items are hidden, and a lookup for the page's other parameters:
-- period, accum, value, list, total, avg, sort, pct, and calc.
--
-- The period parameter is a period expression as for -p: an interval
-- ("monthly"), a date span ("2024"), or both ("monthly in 2024"). An
-- empty one is no period at all, as from a search form with nothing in
-- it; then the startup interval applies. A date: search term can carry
-- an interval too (date:monthly), and as on the command line it wins
-- over the period; cf reportOptsToSpec. The period's date span restricts
-- the report like a date: search term would, and the report's links
-- carry it, so that a row's register is restricted the same way.
reportParams ::
  Day -> ReportSpec -> Text -> Query -> [QueryOpt] -> Bool -> (Text -> Maybe Text) ->
  Either ReportParamError ReportParams
reportParams today rspecOrig qparam q qopts hideEmpty param = do
  let roptsOrig = _rsReportOpts rspecOrig
      rpPeriod = mfilter (not . T.null) (param "period")
  (ivl, rpSpan) <- case rpPeriod of
    Nothing -> Right (interval_ roptsOrig, nulldatespan)
    Just p  -> either (Left . BadPeriod . errorBundlePretty) Right $ parsePeriodExpr today p
  rpAccum <- parseAccum (param "accum")
  rpValue <- parseValue (param "value")
  mlist   <- parseListMode (param "list")
  total   <- parseFlag "total" (param "total")
  avg     <- parseFlag "avg" (param "avg")
  sortAmt <- parseSort (param "sort")
  pct     <- parseFlag "pct" (param "pct")
  calc    <- parseCalc (param "calc")
  infer <- parseFlag "infer" (param "infer")
  dat2  <- parseFlag "date2" (param "date2")
  let rpInterval = fromMaybe ivl $ intervalFromQueryOpts qopts
      ropts1 =
        maybe id setAmountMode rpValue roptsOrig {
          -- -E means the opposite in hledger-ui and hledger-web: hide
          -- zero items, which are shown by default, as the sidebar does.
          empty_ = not hideEmpty,
          balance_base_url_ = Just "",
          date2_ = date2_ roptsOrig || dat2,
          infer_prices_ = infer_prices_ roptsOrig || infer,
          querystring_ = filter (not . T.null) (Query.words'' queryprefixes qparam) ++ dateTerm (date2_ roptsOrig || dat2) rpSpan,
          interval_ = rpInterval
        }
      tree = fromMaybe (accountlistmode_ roptsOrig) mlist == ALTree
  -- The combinations the command line rejects too, judged on the
  -- effective conversion: the value parameter, or startup's options.
  let isEnd (AtEnd _) = True
      isEnd _         = False
      atCost = conversionop_ ropts1 == Just ToCost
      offEnd = rpValue == Just AsRecorded || maybe False (not . isEnd) (value_ ropts1)
  case calc of
    CalcGain | atCost -> Left GainNotCost
    _ | calc `elem` [CalcValueChange, CalcGain], atCost || offEnd -> Left ValuechangeNeedsEnd
    _ -> Right ()
  let
      -- Value changes and gains are figured from period-end market
      -- values; default to that valuation, as the commands do.
      value' | calc `elem` [CalcValueChange, CalcGain], Nothing <- value_ ropts1 = Just $ AtEnd Nothing
             | otherwise = value_ ropts1
      rpRopts = ropts1 {
          value_           = value',
          accountlistmode_ = fromMaybe (accountlistmode_ roptsOrig) mlist,
          -- In tree mode every level is a row of its own, so that each
          -- is a fold point on the page.
          no_elide_        = no_elide_ roptsOrig || tree,
          depth_           = if tree then mempty else depth_ ropts1,
          row_total_       = total,
          average_         = avg,
          sort_amount_     = sortAmt,
          percent_         = pct,
          balancecalc_     = calc
        }
      -- cf queryFromFlags
      dateq
        | rpSpan == nulldatespan = Any
        | date2_ rpRopts         = Date2 rpSpan
        | otherwise              = Date rpSpan
      -- Unlike the journal and register pages, keep any depth limit:
      -- the report reads it from the query, and it is how a balance
      -- report gets summarized (--depth at startup, or depth: in the
      -- search). In tree mode the report is computed at full depth
      -- instead, and the page folds it to the depth limit, with each
      -- deeper group openable in place (see reportTable and hledger.js).
      rpRspec =
        rspecOrig {
          _rsQuery = simplifyQuery $ And [if tree then filterQuery (not . queryIsDepth) q else q, dateq],
          _rsReportOpts = rpRopts
        }
  Right ReportParams{..}

-- | The accum parameter: "historical" for ending balances, "change" for
-- balance changes, "cumulative" for totals since the report's start, or
-- none for the page's default.
parseAccum :: Maybe Text -> Either ReportParamError (Maybe BalanceAccumulation)
parseAccum = \case
  Nothing           -> Right Nothing
  Just ""           -> Right Nothing
  Just "historical" -> Right $ Just Historical
  Just "change"     -> Right $ Just PerPeriod
  Just "cumulative" -> Right $ Just Cumulative
  Just other        -> Left $ BadAccum other

-- | The accum parameter value naming an accumulation mode.
accumWord :: BalanceAccumulation -> Text
accumWord = \case
  PerPeriod  -> "change"
  Historical -> "historical"
  Cumulative -> "cumulative"

-- | The list parameter: show accounts as a "tree" or a "flat" list.
parseListMode :: Maybe Text -> Either ReportParamError (Maybe AccountListMode)
parseListMode = \case
  Nothing     -> Right Nothing
  Just ""     -> Right Nothing
  Just "tree" -> Right $ Just ALTree
  Just "flat" -> Right $ Just ALFlat
  Just other  -> Left $ BadParamValue "list" other

-- | The list parameter value naming an accounts mode.
listWord :: AccountListMode -> Text
listWord ALTree = "tree"
listWord ALFlat = "flat"

-- | A parameter that turns something on: "1", or "0" or nothing for off.
parseFlag :: Text -> Maybe Text -> Either ReportParamError Bool
parseFlag name = \case
  Nothing    -> Right False
  Just ""    -> Right False
  Just "0"   -> Right False
  Just "1"   -> Right True
  Just other -> Left $ BadParamValue name other

-- | The sort parameter: rows in "amount" order, or "account" order (the
-- default).
parseSort :: Maybe Text -> Either ReportParamError Bool
parseSort = \case
  Nothing        -> Right False
  Just ""        -> Right False
  Just "account" -> Right False
  Just "amount"  -> Right True
  Just other     -> Left $ BadParamValue "sort" other

-- | The calc parameter: what a report's cells calculate, as the balance
-- commands' --valuechange, --gain, and --count flags choose.
parseCalc :: Maybe Text -> Either ReportParamError BalanceCalculation
parseCalc = \case
  Nothing            -> Right CalcChange
  Just ""            -> Right CalcChange
  Just "change"      -> Right CalcChange
  Just "valuechange" -> Right CalcValueChange
  Just "gain"        -> Right CalcGain
  Just "count"       -> Right CalcPostingsCount
  Just other         -> Left $ BadParamValue "calc" other

-- | The calc parameter value naming a calculation, for those that have one.
calcWord :: BalanceCalculation -> Maybe Text
calcWord = \case
  CalcValueChange   -> Just "valuechange"
  CalcGain          -> Just "gain"
  CalcPostingsCount -> Just "count"
  _                 -> Nothing

-- | How a page shows amounts: in the commodities they were recorded in,
-- converted to cost (as with -B), or converted with one of the market
-- valuations (as with -V, -X, and --value).
data AmountMode = AsRecorded | AtCost | AtVal ValuationType
  deriving (Eq, Show)

-- | The value parameter, mirroring --value's WHEN[,COMM] syntax:
-- "none", "cost", or a valuation "end", "then", "now", or a date, each
-- optionally with a commodity to convert to (end,EUR = -X EUR). None
-- for the startup options' conversion.
parseValue :: Maybe Text -> Either ReportParamError (Maybe AmountMode)
parseValue = \case
  Nothing -> Right Nothing
  Just "" -> Right Nothing
  Just v ->
    let (w, c) = T.break (== ',') v
        mc = mfilter (not . T.null) $ Just $ T.drop 1 c
        ok = Right . Just
    in case (w, mc) of
      ("none", Nothing) -> ok AsRecorded
      ("cost", Nothing) -> ok AtCost
      ("end",  _)       -> ok $ AtVal $ AtEnd mc
      ("then", _)       -> ok $ AtVal $ AtThen mc
      ("now",  _)       -> ok $ AtVal $ AtNow mc
      _ | Just d <- parsedate (T.unpack w) -> ok $ AtVal $ AtDate d mc
      _ -> Left $ BadValue v

-- | The value parameter naming an amount mode.
valueWord :: AmountMode -> Text
valueWord = \case
  AsRecorded -> "none"
  AtCost     -> "cost"
  AtVal vt   -> case vt of
    AtEnd  mc   -> "end"  <> comm mc
    AtThen mc   -> "then" <> comm mc
    AtNow  mc   -> "now"  <> comm mc
    AtDate d mc -> showDate d <> comm mc
  where comm = maybe "" ("," <>)

-- | Which amount mode report options convert amounts by, if any: only
-- cost combined with a valuation, or conversion to transacted cost, are
-- none of them.
amountModeOf :: ReportOpts -> Maybe AmountMode
amountModeOf ropts =
  case (conversionop_ ropts, value_ ropts) of
    (Just ToCost,           Nothing) -> Just AtCost
    (Just ToCost,           _)       -> Nothing
    (Just ToTransactedCost, _)       -> Nothing
    (_,                     Nothing) -> Just AsRecorded
    (_,                     Just vt) -> Just $ AtVal vt

-- | Report options converting amounts by the given mode, and no other way.
setAmountMode :: AmountMode -> ReportOpts -> ReportOpts
setAmountMode mode ropts =
  case mode of
    AsRecorded -> ropts{conversionop_ = Just NoConversionOp, value_ = Nothing}
    AtCost     -> ropts{conversionop_ = Just ToCost,         value_ = Nothing}
    AtVal vt   -> ropts{conversionop_ = Just NoConversionOp, value_ = Just vt}

-- | The value parameter that links staying on a page keep: the mode
-- given, unless it is the startup options' own.
valueParams :: ReportOpts -> Maybe AmountMode -> [(Text, Text)]
valueParams roptsOrig mmode =
  [("value", valueWord m) | Just m <- [mmode], Just m /= amountModeOf roptsOrig]

-- | Add query parameters to a cell's link, if it has one.
addLinkParams :: [(Text, Text)] -> Cell b Text -> Cell b Text
addLinkParams [] c = c
addLinkParams params c
  | T.null (cellAnchor c) = c
  | otherwise = c {cellAnchor = cellAnchor c <> T.concat ["&" <> k <> "=" <> v | (k, v) <- params]}

-- | Explain a parameter the page could not use.
paramError :: Translations -> ReportParamError -> Html
paramError trs = \case
  BadPeriod err ->
    H.div ! A.class_ "alert alert-danger" $ do
      H.toHtml $ tr trs "Could not parse the period expression:"
      H.pre $ H.toHtml err
  BadAccum v ->
    H.div ! A.class_ "alert alert-danger" $ do
      H.toHtml $ tr trs "Unknown balance accumulation mode:"
      H.pre $ H.toHtml v
  BadValue v ->
    H.div ! A.class_ "alert alert-danger" $ do
      H.toHtml $ tr trs "Unknown amount conversion:"
      H.pre $ H.toHtml v
  BadParamValue name v ->
    H.div ! A.class_ "alert alert-danger" $ do
      H.toHtml $ trf trs "The {name} parameter has a value this page does not know:" [("name", name)]
      H.pre $ H.toHtml v
  ValuechangeNeedsEnd ->
    H.div ! A.class_ "alert alert-danger" $
      H.toHtml $ tr trs "Value changes and gains are figured from period-end market values: leave the value parameter off, or use value=end."
  GainNotCost ->
    H.div ! A.class_ "alert alert-danger" $
      H.toHtml $ tr trs "Gains compare market value against cost, so they do not combine with value=cost."

-- | The deepest account depth a report page can show: that of the
-- journal's deepest account, or the startup depth limit if that is less,
-- as it applies whatever the search says.
deepestDepth :: ReportSpec -> Journal -> Int
deepestDepth rspecOrig j =
  maybe id min (dsFlatDepth $ queryDepth $ _rsQuery rspecOrig) $
    maximum (0 : map accountNameLevel (journalAccountNames j))

-- | A column's heading: its period, or for ending balances and
-- cumulative totals the period's end date, which is what those are at.
columnHeading :: ReportOpts -> [DateSpan] -> DateSpan -> Text
columnHeading ropts colspans spn =
  case balanceaccum_ ropts of
    PerPeriod -> renderPeriodHeading (period_titles_ ropts) spn
    _         -> reportPeriodName ropts colspans spn

-- | Give a report's heading row this page's column headings and links:
-- the cells that link (the columns' periods) get the given heading text
-- and link for their span.
relinkDateHeaders ::
  Translations -> (DateSpan -> Text) -> (DateSpan -> Text) -> [DateSpan] -> [Cell NumLines Text] -> [Cell NumLines Text]
relinkDateHeaders trs heading link = go
  where
    go (spn:spns) (c:cs)
      | not (T.null $ cellAnchor c) =
          c {cellContent = heading spn, cellAnchor = link spn, cellTitle = tr trs "Show this report for this period"} : go spns cs
    go spns (c:cs) = c : go spns cs
    go _ [] = []

-- | A report as a table in the page's own style: the heading rows, then
-- a table section per report section (a titled row, its rows, then its
-- subtotal rows), then the total rows as the table's footer. It scrolls
-- sideways within the page when it is wider (see .report-table in
-- hledger.css; bootstrap's .table-responsive does that only on a phone).
-- In tree mode the rows carry depth classes, the indent becomes css
-- padding so hledger.js can put a fold caret at each group, and the
-- table says what depth to fold to initially, if any.
reportTable ::
  Bool -> Maybe Int ->
  [[Cell NumLines Text]] -> [(Maybe Text, [[Cell NumLines Text]], [[Cell NumLines Text]])] -> [[Cell NumLines Text]] -> Html
reportTable isTree mfold header sections footer =
  H.div ! A.class_ "table-responsive report-table" $
    maybe id (\n t -> t ! H.dataAttribute "depth-fold" (H.toValue n)) mfold
      (H.table ! A.class_ "balancereport table table-condensed") $ do
      H.thead $ rows Nothing header
      traverse_ section sections
      unless (null footer) $ H.tfoot $ rows Nothing footer
  where
    ncols = maybe 1 length $ listToMaybe header
    section (mtitle, body, subtotals) =
      H.tbody $ do
        for_ mtitle $ \t ->
          H.tr ! A.class_ "section" $
            H.th ! A.colspan (H.toValue ncols) ! H.customAttribute "scope" "rowgroup" $ H.toHtml t
        rows Nothing body
        rows (Just "subtotal") subtotals
    rows mcls = traverse_ $ \r ->
      maybe id (\cls -> (! A.class_ cls)) mcls H.tr (traverse_ (formatCell . fmap H.toHtml) (stripIndents r)) <> nl
    -- The nbsp indent the renderer gives tree-mode account names, as
    -- padding instead (hledger.css indents by the depth class), so the
    -- caret sits at the name.
    stripIndents | isTree = map stripCell
                 | otherwise = id
    stripCell c
      | "depth-" `T.isInfixOf` textFromClass (cellClass c) = c{cellContent = T.dropWhile (== '\160') (cellContent c)}
      | otherwise = c
