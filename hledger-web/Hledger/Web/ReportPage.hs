{-|
What hledger-web's report pages share: resolving their parameters into
report options, translating the startup options into url state, and
rendering a report's cells as the page's table.
-}

{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Hledger.Web.ReportPage (
  ReportParams(..),
  ReportParamError(..),
  reportParams,
  startupUrlState,
  intervalPeriodExpr,
  paramError,
  reportProbe,
  pctError,
  AmountMode(..),
  parseValue,
  readParam,
  accumParam,
  calcParam,
  listParam,
  sortParam,
  optionsSummary,
  registerKeptParams,
  valueWord,
  amountModeOf,
  setAmountMode,
  valueParams,
  addLinkParams,
  labelAllAccounts,
  deepestDepth,
  parseInterval,
  depthParams,
  columnHeading,
  headingParams,
  removeAttributes,
  relinkDateHeaders,
  reportLinks,
  intervalLinks,
  reportTable,
  chartReportSpec,
  splitAccountNames,
) where

import Control.Exception qualified as E
import Control.Monad (guard, mfilter, unless)
import Data.Foldable (find, for_, traverse_)
import Data.List (elemIndex, mapAccumL, sortOn, stripPrefix)
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Text.Encoding qualified as TE
import Network.HTTP.Types.URI (urlEncode)
import Safe (readMay)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Set qualified as Set
import Text.Blaze.Html5 ((!))
import Text.Blaze.Html5 qualified as H
import Text.Blaze.Html5.Attributes qualified as A
import Text.Megaparsec (eof)
import Text.Megaparsec.Error (errorBundlePretty)

import Yesod (HtmlUrl)

import Hledger.Utils.I18n (Translations, tr, trc, trf)
import Hledger
import Hledger.Cli.Anchor (dateTerm, renderPeriodHeading)
import Hledger.Web.Param (Param(..), linksRowClass, paramPhrase, paramSettings, parseParam)
import Hledger.Web.Widget.Common (AmountMode(..), removeDates, valueWord)
import Hledger.Query qualified as Query
import Hledger.Write.Html (Html, formatCell, nl)
import Hledger.Write.Spreadsheet (Cell(..), Class(..), NumLines, textFromClass)

-- | A report page's parameters, resolved.
data ReportParams = ReportParams {
    rpRopts    :: ReportOpts,
      -- ^ The startup report options with the page's search, period, interval,
      --   and zero-item setting applied, and links made relative. The
      --   accumulation mode is left for the page to set.
    rpRspec    :: ReportSpec,
      -- ^ The startup report spec with those options and the page's query.
    rpInterval :: Interval,
      -- ^ The reporting interval: from the interval parameter, else none.
    rpAccum    :: Maybe BalanceAccumulation,
      -- ^ The accum parameter, if one was given.
    rpValue    :: Maybe AmountMode
      -- ^ The value parameter, if one was given. rpRopts converts amounts
      --   as it says.
}

-- | A parameter the page cannot use, with what was given; or a
-- combination of parameters that contradict each other.
data ReportParamError
  = BadInterval String | BadValue Text | BadParamValue Text Text
  | ValuechangeNeedsEnd | GainNotCost | ValueThenUnsupported

-- | Resolve a report page's parameters: the startup report spec, the search parameter and its parsed query and options, whether
-- zero items are hidden, and a lookup for the page's other parameters:
-- interval, accum, value, list, total, avg, sort, pct, and calc.
--
-- The interval parameter is a reporting interval as in a period
-- expression ("monthly", "every 2 weeks"), with no dates: the report's
-- dates are the search's date: terms (App.normaliseUrlState moves the
-- intervals typed there to this parameter). An empty one is no interval.
reportParams ::
  ReportSpec -> Text -> Query -> [QueryOpt] -> Bool -> [(Text, Text)] ->
  Either ReportParamError ReportParams
reportParams rspecOrig qparam q qopts hideEmpty params = do
  let roptsOrig = _rsReportOpts rspecOrig
      param k = lookup k params
  ivl <- case mfilter (not . T.null) (param "interval") of
    Nothing -> Right (interval_ roptsOrig)
    Just t  -> either (Left . BadInterval . errorBundlePretty) Right $ parseInterval t
  rpAccum <- readParam accumParam (param $ paramName accumParam)
  rpValue <- parseValue (param "value")
  mlist   <- readParam listParam (param $ paramName listParam)
  total   <- parseFlag "total" (param "total")
  avg     <- parseFlag "avg" (param "avg")
  sortAmt <- fromMaybe False <$> readParam sortParam (param $ paramName sortParam)
  pct     <- parseFlag "pct" (param "pct")
  calc    <- fromMaybe CalcChange <$> readParam calcParam (param $ paramName calcParam)
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
          querystring_ = filter (not . T.null) (Query.words'' queryprefixes qparam),
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
          depth_           = if tree then mempty else depth_ ropts1,
          fold_depth_      = if folding then dsFlatDepth (queryDepth q) else Nothing,
          row_total_       = total,
          average_         = avg,
          sort_amount_     = sortAmt,
          percent_         = pct,
          balancecalc_     = calc
        }
      -- Unlike the journal and register pages, keep any depth limit:
      -- the report reads it from the query, and it is how a balance
      -- report gets summarized (--depth at startup, or depth: in the
      -- search). In tree mode the report is computed without the flat
      -- depth limit instead, and the page folds it to that limit, with
      -- each deeper group openable in place (see reportTable and
      -- hledger.js); fold_depth_ keeps boring parents from being elided
      -- across it. Per-account depth limits still clip, as on the
      -- command line, and so does depth 0, a single total, which
      -- folding can't show.
      folding = tree && dsFlatDepth (queryDepth q) /= Just 0
      rpRspec =
        rspecOrig {
          _rsQuery = if folding then simplifyQuery $ filterQuery (not . queryIsFlatDepth) q else q,
          _rsReportOpts = rpRopts
        }
  Right ReportParams{..}

-- | The startup report options and query arguments, expressed as url
-- state: the parameters for the url that browse mode opens and --serve
-- prints. Query arguments and query-expressible options
-- (periods, per-account depths, statuses, -R) become the q parameter's
-- search terms; the other options the pages know, a flat --depth
-- among them, become their parameters.
-- Display preferences without a url spelling (the language, period
-- title style, report titles) stay in the spec; report options the web
-- ui has no vocabulary for (--invert, --transpose, ...) are dropped.
startupUrlState :: ReportSpec -> ([(Text, Text)], ReportSpec)
startupUrlState rspec@ReportSpec{_rsReportOpts = ropts} = (params, rspec')
  where
    params =
      [("interval", p)        | Just p <- [intervalPeriodExpr $ interval_ ropts]] ++
      [("depth", T.pack (show n)) | Just n <- [dsFlatDepth $ depth_ ropts]] ++
      paramSettings accumParam PerPeriod (balanceaccum_ ropts) ++
      [("value", valueWord m) | Just m <- [amountModeOf ropts], m /= AsRecorded] ++
      paramSettings listParam ALFlat (accountlistmode_ ropts) ++
      [("total", "1")         | row_total_ ropts] ++
      [("avg", "1")           | average_ ropts] ++
      paramSettings sortParam False (sort_amount_ ropts) ++
      [("pct", "1")           | percent_ ropts] ++
      paramSettings calcParam CalcChange (balancecalc_ ropts) ++
      [("costs", "1")         | show_costs_ ropts] ++
      [("infer", "1")         | infer_prices_ ropts] ++
      [("date2", "1")         | date2_ ropts] ++
      -- -E means the opposite here: hide the zero balances the web ui
      -- shows by default (cf hideEmptyAccounts).
      [("empty", "0")         | empty_ ropts] ++
      [("q", T.unwords qterms) | not (null qterms)]
    qterms =
      map textQuoteIfNeeded (querystring_ ropts) ++
      dateTerm (date2_ ropts) (periodAsDateSpan $ period_ ropts) ++
      map statusTerm (statuses_ ropts) ++
      ["real:1" | real_ ropts] ++
      depthTerms (depth_ ropts)
    statusTerm s = "status:" <> case s of
      Unmarked -> ""
      Pending  -> "!"
      Cleared  -> "*"
    depthTerms (DepthSpec _ regexps) =
      -- quoted when the regexp has a space, like the query terms
      [textQuoteIfNeeded $ "depth:" <> reString r <> "=" <> T.pack (show n) | (r, n) <- regexps]
    rspec' = rspec{
      _rsQuery = Any,
      _rsQueryOpts = [],
      _rsReportOpts = defreportopts{
        -- startup display preferen
        format_           = format_ ropts,
        balance_base_url_ = balance_base_url_ ropts,
        pretty_           = pretty_ ropts,
        sortspec_         = sortspec_ ropts,
        color_            = color_ ropts,
        layout_           = layout_ ropts,
        period_titles_    = period_titles_ ropts,
        title_            = title_ ropts,
        subreport_titles_ = subreport_titles_ ropts,
        translations_     = translations_ ropts
      }
    }

-- | Parse a reporting interval as in a period expression ("monthly",
-- "every 2 weeks"), with nothing else.
parseInterval :: Text -> Either HledgerParseErrors Interval
parseInterval = parsewith (skipNonNewlineSpaces *> reportingintervalp <* skipNonNewlineSpaces <* eof) . T.toLower

-- | A period expression naming the given reporting interval, none for
-- NoInterval: the inverse of parseInterval.
intervalPeriodExpr :: Interval -> Maybe Text
intervalPeriodExpr = \case
  NoInterval -> Nothing
  Days 1     -> Just "daily"
  Weeks 1    -> Just "weekly"
  Months 1   -> Just "monthly"
  Quarters 1 -> Just "quarterly"
  Years 1    -> Just "yearly"
  Days n     -> Just $ every n "days"
  Weeks n    -> Just $ every n "weeks"
  Months n   -> Just $ every n "months"
  Quarters n -> Just $ every n "quarters"
  Years n    -> Just $ every n "years"
  MonthDay n             -> Just $ "every " <> ordinal n <> " day of month"
  NthWeekdayOfMonth n wd -> (\name -> "every " <> ordinal n <> " " <> name <> " of month") <$> weekdayName wd
  MonthAndDay m d        -> Just $ "every " <> T.pack (show m) <> "/" <> T.pack (show d)
  DaysOfWeek [1,2,3,4,5] -> Just "every weekday"
  DaysOfWeek [6,7]       -> Just "every weekendday"
  DaysOfWeek []          -> Nothing
  DaysOfWeek ds          -> ("every " <>) . T.intercalate "," <$> traverse weekdayName ds
  where
    every n unit = "every " <> T.pack (show n) <> " " <> unit
    ordinal n = T.pack (show n) <> suffix
      where
        suffix | n `mod` 100 `elem` [11, 12, 13] = "th"
               | otherwise = case n `mod` 10 of 1 -> "st"; 2 -> "nd"; 3 -> "rd"; _ -> "th"
    -- The period parser accepts any day number in "every Nth day of
    -- week", so days outside 1-7 arrive here: they have no name, and
    -- their interval yields no period expression.
    weekdayName d = lookup d $ zip [1..] ["monday","tuesday","wednesday","thursday","friday","saturday","sunday"]

-- | Links to the report pages, given as route, label, and title, keeping
-- the given parameters; the page being shown is marked. Unlike the other
-- rows of links, this one needs no label: it is the pages' navigation.
reportLinks :: Eq r => Translations -> r -> [(Text, Text)] -> [(r, Text, Text)] -> HtmlUrl r
reportLinks trs here kept items =
  linksRowClass "reports" ""
    [ (tr trs label, tr trs title, (route, kept), route == here) | (route, label, title) <- items ]

-- | Links to the same report page for each reporting interval, keeping
-- the search (and its dates) and the given parameters; the interval
-- being shown is marked.
intervalLinks :: Translations -> r -> [(Text, Text)] -> Text -> Interval -> HtmlUrl r
intervalLinks trs route kept qparam current =
  -- The D, W, M, Q, and Y keys follow these links, by their order
  -- here (hledger.js).
  -- TRANSLATORS: the label before a report's interval links.
  linksRowClass "interval" (tr trs "Interval:")
    [ (label, title, link mword, ivl == current) | (label, title, mword, ivl) <- intervals ]
  where
    -- TRANSLATORS: the interval links above a report: each link's text, and its tooltip.
    intervals :: [(Text, Text, Maybe Text, Interval)]
    intervals =
      [ (trc trs "interval" "None", tr trs "Show one column for the whole period", Nothing,          NoInterval)
      , (tr trs "Yearly",    tr trs "Show a column per year",               Just "yearly",    Years 1)
      , (tr trs "Quarterly", tr trs "Show a column per quarter",            Just "quarterly", Quarters 1)
      , (tr trs "Monthly",   tr trs "Show a column per month",              Just "monthly",   Months 1)
      , (tr trs "Weekly",    tr trs "Show a column per week",               Just "weekly",    Weeks 1)
      , (tr trs "Daily",     tr trs "Show a column per day",                Just "daily",     Days 1)
      ]
    link mword =
      (route, [("q", qparam) | not (T.null qparam)] ++ kept ++ [("interval", w) | Just w <- [mword]])

-- | A parameter that turns something on: "1", or "0" or nothing for off.
parseFlag :: Text -> Maybe Text -> Either ReportParamError Bool
parseFlag name = \case
  Nothing    -> Right False
  Just ""    -> Right False
  Just "0"   -> Right False
  Just "1"   -> Right True
  Just other -> Left $ BadParamValue name other

-- | Read a multiple-choice parameter's value (see 'parseParam'),
-- naming the parameter if the value is unknown.
readParam :: Param a -> Maybe Text -> Either ReportParamError (Maybe a)
readParam p = either (Left . BadParamValue (paramName p)) Right . parseParam p

-- | The accum parameter: whether a report shows balance changes, ending
-- balances, or cumulative totals; absent for the page's own default.
-- The H key toggles Ending balances, the second link (hledger.js).
accumParam :: Param BalanceAccumulation
accumParam = Param
  { paramName  = "accum"
  , paramModes = [PerPeriod, Historical, Cumulative]
  , paramWord  = \case
      PerPeriod  -> "change"
      Historical -> "historical"
      Cumulative -> "cumulative"
  -- TRANSLATORS: the label before a report's accumulation mode links, and the links' text and tooltips.
  , paramRowLabel = \trs -> tr trs "Show:"
  , paramLabel = \trs -> \case
      PerPeriod  -> (tr trs "Balance changes", tr trs "Show how much each balance changed in each period")
      Historical -> (tr trs "Ending balances", tr trs "Show each balance at the end of each period, including everything before it")
      Cumulative -> (tr trs "Cumulative totals", tr trs "Show each balance's change since the start of the report (--cumulative)")
  }

-- | The calc parameter: what a report's cells calculate, as the balance
-- commands' --valuechange, --gain, and --count flags choose.
calcParam :: Param BalanceCalculation
calcParam = Param
  { paramName  = "calc"
  , paramModes = [CalcChange, CalcValueChange, CalcGain, CalcPostingsCount]
  , paramWord  = \case
      CalcChange        -> "change"
      CalcValueChange   -> "valuechange"
      CalcGain          -> "gain"
      CalcPostingsCount -> "count"
      -- Not offered (not in paramModes), so never in a url.
      _                 -> ""
  -- TRANSLATORS: the label before a report's calculation links, and the links' text and tooltips.
  , paramRowLabel = \trs -> tr trs "Calculate:"
  , paramLabel = \trs -> \case
      CalcChange        -> (trc trs "calculation" "Sums", tr trs "Show sums of postings")
      CalcValueChange   -> (tr trs "Value change", tr trs "Show how period-end market values changed (--valuechange)")
      CalcGain          -> (tr trs "Unrealized gain", tr trs "Show unrealized capital gains: market value minus cost (--gain)")
      CalcPostingsCount -> (tr trs "Posting counts", tr trs "Count the postings instead of summing them (--count)")
      _                 -> ("", "")
  }

-- | The list parameter: show accounts as a flat list or a tree; absent
-- for the page's default, the startup one. The t key toggles them
-- (hledger.js).
listParam :: Param AccountListMode
listParam = Param
  { paramName  = "list"
  , paramModes = [ALFlat, ALTree]
  , paramWord  = \case
      ALFlat -> "flat"
      ALTree -> "tree"
  -- TRANSLATORS: the label before a report's list/tree links, and the links' text and tooltips.
  , paramRowLabel = \trs -> tr trs "Accounts:"
  , paramLabel = \trs -> \case
      ALFlat -> (trc trs "accounts" "List", tr trs "Show accounts as a flat list (--flat)")
      ALTree -> (trc trs "accounts" "Tree", tr trs "Show accounts as a tree (--tree)")
  }

-- | The sort parameter: whether rows are sorted by amount, rather than
-- by account display order (declaration order, otherwise name).
-- The S key toggles By amount, the second link (hledger.js).
sortParam :: Param Bool
sortParam = Param
  { paramName  = "sort"
  , paramModes = [False, True]
  , paramWord  = \case
      False -> "account"
      True  -> "amount"
  -- TRANSLATORS: the label before a report's sort links, and the links' text and tooltips.
  , paramRowLabel = \trs -> tr trs "Sort:"
  , paramLabel = \trs -> \case
      False -> (tr trs "By account", tr trs "Sort rows by account display order")
      True  -> (tr trs "By amount", tr trs "Sort rows by their amounts, largest first (-S)")
  }

-- | Of the parameters the page links keep, those the sidebar's register
-- links keep: the states the register reads, ie the depth limit (which
-- clips its sidebar), the amounts mode, the accounts mode, inferred
-- prices, zero balances, and lot detail. Each such link rewrites the
-- search itself.
registerKeptParams :: [(Text, Text)] -> [(Text, Text)]
registerKeptParams ps = [p | p@(k, _) <- ps, k `elem` ["depth", "value", paramName listParam, "infer", "empty", "lots"]]

-- | The report options a page's parameters set, as short phrases for the
-- closed controls disclosure: the controls' own words where those stand
-- alone ("Monthly", "Tree"), a phrase where a control's word would not
-- ("Shown"). The pages' links carry only the options not at their
-- defaults, so these are the options in effect, listed in the order of
-- the controls' rows. The filters are not here: they are search terms,
-- shown in the search box. A depth limit at or beyond the given
-- deepest account's depth is not one: the Depth links show it as none.
optionsSummary :: Translations -> Int -> [(Text, Text)] -> [Text]
optionsSummary trs deepest = mapMaybe phrase . sortOn (rowOrder . fst)
  where
    rowOrder k = fromMaybe maxBound $ elemIndex k
      ["equity", "interval", paramName accumParam, "depth", paramName listParam, "value", "infer", "empty", "lots", "closed",
       "total", "avg", "costs", paramName sortParam, "pct", paramName calcParam, "date2"]
    phrase = \case
      ("interval", w)     -> Just $ fromMaybe w $ lookup w
        [ ("yearly", tr trs "Yearly"), ("quarterly", tr trs "Quarterly"), ("monthly", tr trs "Monthly")
        , ("weekly", tr trs "Weekly"), ("daily", tr trs "Daily") ]
      -- TRANSLATORS: the depth limit, in the list of options in effect.
      ("depth", n)        -> do
        d <- readMay (T.unpack n) :: Maybe Int
        guard (d < deepest)
        Just $ trf trs "Depth {depth}" [("depth", n)]
      (k, w) | k == paramName accumParam -> paramPhrase accumParam trs w
      ("value", "none")   -> Just $ tr trs "As recorded"
      ("value", "cost")   -> Just $ trc trs "amounts" "Cost"
      ("value", _)        -> Just $ trc trs "amounts" "Value"
      (k, w) | k == paramName listParam -> paramPhrase listParam trs w
      (k, w) | k == paramName sortParam -> paramPhrase sortParam trs w
      ("pct", "1")        -> Just $ tr trs "Percentages"
      (k, w) | k == paramName calcParam -> paramPhrase calcParam trs w
      -- TRANSLATORS: options in effect, listed on the closed options disclosure.
      ("total", "1")      -> Just $ trc trs "column" "Total"
      ("avg", "1")        -> Just $ trc trs "column" "Average"
      ("infer", "1")      -> Just $ tr trs "Inferred prices"
      ("empty", "0")      -> Just $ tr trs "Zero balances hidden"
      ("empty", "1")      -> Just $ tr trs "Zero balances shown"
      ("lots", "1")       -> Just $ tr trs "Lots shown"
      ("costs", "1")      -> Just $ tr trs "Costs shown"
      ("closed", "1")     -> Just $ tr trs "Closed positions shown"
      ("closed", "0")     -> Just $ tr trs "Closed positions hidden"
      ("date2", "1")      -> Just $ tr trs "Secondary dates"
      ("equity", "1")     -> Just $ tr trs "Equity shown"
      _                   -> Nothing

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

-- | Add query parameters to a cell's link, if it has one. The values
-- are url-encoded (interval words like "every 2 weeks", and value
-- parameters carrying a commodity, are not url-safe); the keys are our
-- own constant names.
addLinkParams :: [(Text, Text)] -> Cell b Text -> Cell b Text
addLinkParams [] c = c
addLinkParams params c
  | T.null (cellAnchor c) = c
  | otherwise = c {cellAnchor = cellAnchor c <> sep <> T.intercalate "&" [k <> "=" <> enc v | (k, v) <- params]}
  where
    enc = TE.decodeUtf8 . urlEncode True . TE.encodeUtf8
    sep = if "?" `T.isInfixOf` cellAnchor c then "&" else "?"

-- | Label a depth 0 report's "..." row, all accounts in one, with the
-- given word, as hledger-ui does.
labelAllAccounts :: Text -> Cell b Text -> Cell b Text
labelAllAccounts lbl c
  | "account" `elem` T.words (textFromClass (cellClass c))
  , T.dropWhile (== '\160') (cellContent c) == "..." = c {cellContent = lbl}
  | otherwise = c

-- | Force a report enough to surface the error a percentage report
-- raises when its amounts span commodities: that depends on the data,
-- not the parameters, so reportParams cannot catch it. Nothing when
-- the report calculates.
reportProbe :: Show r => r -> IO (Maybe String)
reportProbe r =
  E.handle (\(E.ErrorCall e) -> pure $ Just e) $
    Nothing <$ E.evaluate (length $ show r)

-- | Explain percentages falling back to plain amounts, showing the
-- report's own message.
pctError :: Translations -> String -> Html
pctError trs e =
  H.div ! A.class_ "alert alert-danger" $ do
    H.toHtml $ tr trs "Could not calculate percentages:"
    H.pre $ H.toHtml $ fromMaybe e $ stripPrefix "Error: " e

-- | Explain a parameter the page could not use.
paramError :: Translations -> ReportParamError -> Html
paramError trs = \case
  BadInterval err ->
    H.div ! A.class_ "alert alert-danger" $ do
      H.toHtml $ tr trs "Could not parse the reporting interval:"
      H.pre $ H.toHtml err
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
  ValueThenUnsupported ->
    H.div ! A.class_ "alert alert-danger" $
      H.toHtml $ tr trs "This report is at a single date, so value=then does not apply: use value=end, value=now, or a date."

-- | The depth parameter for the query's depth limit, if it has one, for
-- links keeping it. (Only a depth:REGEX=N term can be in the search,
-- which keeps it there: see App.setDepthFromSearch.)
depthParams :: Query -> [(Text, Text)]
depthParams q = [("depth", T.pack (show n)) | Just n <- [dsFlatDepth $ queryDepth q]]

-- | The deepest account depth a report page can show: that of the
-- journal's deepest account. The journal as displayed with lots shown
-- includes the lot subaccounts, which are ordinary accounts here, so
-- the Depth row extends to them, as in hledger-ui.
deepestDepth :: Journal -> Int
deepestDepth j = maximum (0 : map accountNameLevel (journalAccountNames j))

-- | A column's heading: its period, or for ending balances and
-- cumulative totals the period's end date, which is what those are at.
columnHeading :: ReportOpts -> [DateSpan] -> DateSpan -> Text
columnHeading ropts colspans spn =
  case balanceaccum_ ropts of
    PerPeriod -> renderPeriodHeading (period_titles_ ropts) spn
    _         -> reportPeriodName ropts colspans spn

-- A column heading opens this report for that column's period, in
-- place of any date terms in the search, which the column narrows
-- anyway. The interval is kept (the drilled view is one column of it),
-- so the report's subdivision survives navigating on from there.
headingParams :: Interval -> Text -> [(Text, Text)] -> DateSpan -> [(Text, Text)]
headingParams ivl qparam params spn =
  [("q", T.unwords qt) |
      let qt = dateTerm False spn ++ removeDates qparam,
      not (null qt)] ++
  removeAttributes ["q", "interval"] params ++
  [("interval", w) | Just w <- [intervalPeriodExpr ivl]]

removeAttributes :: [Text] -> [(Text, Text)] -> [(Text, Text)]
removeAttributes attrs =
  let attrSet = Set.fromList attrs
  in filter (flip Set.notMember attrSet . fst)

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

-- | In a flat report's body rows, strip what the account names share
-- above their leaf names, and mark the account cells for path-dimmed
-- rendering (acct-split; see reportTable and .acct-path in hledger.css):
-- the least interesting parents stop repeating down the page. The
-- register links keep the full names, which also head each cell's
-- tooltip. Returns the shared prefix, for showing once in a heading.
splitAccountNames :: [[Cell b Text]] -> (Maybe AccountName, [[Cell b Text]])
splitAccountNames rws = (mprefix, map (map split) rws)
  where
    isAcct c = textFromClass (cellClass c) == "account"
    names = [cellContent c | r <- rws, c <- r, isAcct c]
    prefix = case map accountNameComponents names of
      []    -> []
      comps -> foldl1 commonPrefix (map init comps)  -- init: each leaf stays in its row
    commonPrefix (x:xs) (y:ys) | x == y = x : commonPrefix xs ys
    commonPrefix _ _ = []
    mprefix = if null prefix then Nothing else Just (accountNameFromComponents prefix)
    split c
      | isAcct c = c
          { cellContent = accountNameFromComponents $ drop (length prefix) $ accountNameComponents $ cellContent c
          , cellClass = Class "account acct-split"
          , cellTitle = cellContent c <> "\n" <> cellTitle c
          }
      | otherwise = c

-- | Where a report page folds its tree at the depth limit (see
-- reportParams), the report spec for its chart, given the page's search:
-- one clipping the tree there instead, as the command line does, since a
-- chart can't fold. Otherwise the chart's report is the page's own.
chartReportSpec :: Query -> ReportSpec -> Maybe ReportSpec
chartReportSpec q rspec@ReportSpec{_rsReportOpts = ropts} =
  rspec{_rsQuery = q, _rsReportOpts = ropts{fold_depth_ = Nothing}} <$ fold_depth_ ropts

-- | A report as a table in the page's own style: the heading rows, then
-- a table section per report section (a titled row, its rows, then its
-- subtotal rows), then the total rows as the table's footer. It scrolls
-- sideways within the page when it is wider (see .report-table in
-- hledger.css; bootstrap's .table-responsive does that only on a phone).
-- In tree mode the rows carry indent and depth classes, the indent
-- becomes css padding so hledger.js can put a fold caret at each group,
-- and the table says what depth to fold to initially, if any.
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
        traverse_ (uncurry row) $ zip (foldClasses body) body
        rows (Just "subtotal") subtotals
    rows mcls = traverse_ (row mcls)
    row mcls r =
      maybe id (\c -> (! A.class_ c)) mcls H.tr (traverse_ (formatCell . cellHtml) (stripIndents r)) <> nl
    -- With a depth limit, the rows below it are served already folded,
    -- so the table paints at its folded height and nothing moves after
    -- paint; hledger.js's carets toggle the same class from there.
    -- A row is folded when one of its ancestor rows (the nearest row at
    -- each lesser indent-N) is an account at or below the limit (its
    -- depth-N). The limit counts account name levels, not indents,
    -- which differ where boring parents are elided into a row.
    foldClasses body = case mfold of
      Nothing -> map (const Nothing) body
      Just d -> snd $ mapAccumL (foldStep d) [] body
    -- The ancestors stack holds the (indent, level) of the current
    -- row's ancestor rows, nearest first.
    foldStep d ancestors r = case (rowClassNum "indent-" r, rowClassNum "depth-" r) of
      (Just dep, Just lvl) ->
        let ancestors' = dropWhile ((>= dep) . fst) ancestors
        in ((dep, lvl) : ancestors', "tree-fold-hide" <$ find ((>= d) . snd) ancestors')
      _ -> (ancestors, Nothing)
    rowClassNum prefix r = listToMaybe
      [ n | c <- r, cls <- T.words $ textFromClass $ cellClass c
          , Just ns <- [T.stripPrefix prefix cls]
          , ((n, "") : _) <- [reads (T.unpack ns) :: [(Int, String)]] ]
    -- An account cell marked acct-split renders as two spans, the parent
    -- path and the leaf name, so css can dim the path and shorten it from
    -- the left (.acct-path in hledger.css). The inner span is a bidi
    -- isolate there, keeping that css left-shortening trick
    -- (direction: rtl) from reordering the name.
    cellHtml c
      | "acct-split" `elem` T.words (textFromClass (cellClass c))
      , (path, leaf) <- T.breakOnEnd ":" (cellContent c)
      , not (T.null path)
      = (H.toHtml <$> c)
          { cellContent =
              (H.span ! A.class_ "acct-path") (H.span $ H.toHtml $ T.init path)
              <> H.toHtml (":" :: Text)
              <> (H.span ! A.class_ "acct-leaf") (H.toHtml leaf) }
      | otherwise = H.toHtml <$> c
    -- The nbsp indent the renderer gives tree-mode account names, as
    -- padding instead (hledger.css indents by the depth class), so the
    -- caret sits at the name.
    stripIndents | isTree = map stripCell
                 | otherwise = id
    stripCell c
      | "indent-" `T.isInfixOf` textFromClass (cellClass c) = c{cellContent = T.dropWhile (== '\160') (cellContent c)}
      | otherwise = c
