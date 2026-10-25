{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE TemplateHaskell   #-}

module Hledger.Web.Widget.Common
  ( accountParams
  , accountRegisterQuery
  , balanceReportAsHtml
  , controlsHint
  , controlsToggle
  , optionsSummary
  , searchHeading
  , inertControls
  , linksRow
  , linksRowClass
  , linksRowGroups
  , pricesLinks
  , commodityLinks
  , depthLinks
  , amountLinks
  , zeroBalanceLinks
  , statusLinks
  , realLinks
  , listModeLinks
  , columnsLinks
  , sortLinks
  , percentLinks
  , calcLinks
  , costsLinks
  , lotsLinks
  , closedLinks
  , holdingsValueLinks
  , typeLinks
  , AmountMode(..)
  , accumWord
  , listWord
  , valueWord
  , searchTerms
  , MovedOptions(..)
  , normalisedSearch
  , splitPeriodExpr
  , helplink
  , mixedAmountAsHtml
  , mixedAmountAsHtmlWith
  , mixedAmountAsHtmlElided
  , runningBalanceAsHtml
  , moreCommodities
  , fromFormSuccess
  , writeJournalTextIfValidAndChanged
  , journalFile404
  , transactionFragment
  , removeDates
  , journalDayQuery
  ) where

import Control.Applicative ((<|>))
import Control.Monad (guard, unless, when)
import Control.Monad.Except (ExceptT, mapExceptT)
import Data.Char (isDigit)
import Data.Foldable (find, for_)
import Data.List (elemIndex, sortOn)
import Data.Set qualified as Set
import Data.Maybe (fromMaybe, isJust, isNothing, listToMaybe, mapMaybe, maybeToList)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar (Day)
import Safe (lastMay, readMay)
import System.FilePath (takeFileName)
import Text.Blaze ((!), (!?), textValue)
import Text.Blaze.Html5 qualified as H
import Text.Blaze.Html5.Attributes qualified as A
import Text.Blaze.Internal (preEscapedString)
import Text.Hamlet (hamletFile)
import Text.Megaparsec (getInput)
import Text.Printf (printf)
import Yesod

import Hledger.Utils.I18n (Translations, tr, trc, trf)
import Hledger
import Hledger.Cli.Anchor qualified as Anchor
import Hledger.Cli.Utils (writeFileWithBackupIfChanged)
import Hledger.Web.Settings (manualurl)
import Hledger.Query qualified as Query


journalFile404 :: FilePath -> Journal -> HandlerFor m (FilePath, Text)
journalFile404 f j =
  case find ((== f) . fst) (jfiles j) of
    Just (_, txt) -> pure (takeFileName f, txt)
    Nothing -> notFound

fromFormSuccess :: Applicative m => m a -> FormResult a -> m a
fromFormSuccess h FormMissing = h
fromFormSuccess h (FormFailure _) = h
fromFormSuccess _ (FormSuccess a) = pure a

-- | A helper for postEditR/postUploadR: check that the given text
-- parses as a Journal, and if so, write it to the given file, if the
-- text has changed. Or, return any error message encountered.
--
-- As a convenience for data received from web forms, which does not
-- have normalised line endings, line endings will be normalised (to \n)
-- before parsing.
--
-- The file will be written (if changed) with the current system's native
-- line endings (see writeFileWithBackupIfChanged).
--
writeJournalTextIfValidAndChanged :: MonadHandler m => FilePath -> Text -> ExceptT String m ()
writeJournalTextIfValidAndChanged f t = mapExceptT liftIO $ do
  -- Ensure unix line endings, since both readJournal (cf
  -- formatdirectivep, #1194) writeFileWithBackupIfChanged require them.
  -- XXX klunky. Any equivalent of "hSetNewlineMode h universalNewlineMode" for form posts ?
  let t' = T.replace "\r" "" t
  j <- readJournal definputopts (Just f) =<< liftIO (textToHandle t')
  _ <- liftIO $ j `seq` writeFileWithBackupIfChanged f t'  -- Only write backup if the journal didn't error
  return ()

-- | Link to a topic in the manual.
helplink :: Text -> Text -> HtmlUrl r
helplink topic label _ = H.a ! A.href u ! A.target "hledgerhelp" $ toHtml label
  where u = textValue $ manualurl <> if T.null topic then "" else T.cons '#' topic

-- | Of the parameters the page links keep, those the sidebar's register
-- links keep: the states the register reads, ie the depth limit (which
-- clips its sidebar), the amounts mode, the accounts mode, inferred
-- prices, zero balances, and lot detail. Each such link rewrites the
-- search itself.
registerKeptParams :: [(Text, Text)] -> [(Text, Text)]
registerKeptParams ps = [p | p@(k, _) <- ps, k `elem` ["depth", "value", "list", "infer", "empty", "lots"]]

-- | Render a "BalanceReport" as the sidebar: the page links (each page's
-- route, label, title, and the key that goes there after g, with the
-- parameters their links carry), then the accounts, linking to their
-- registers. The current page's row is marked.
balanceReportAsHtml ::
  Eq r => r -> r -> [(r, Text, Text, Text)] -> [(Text, Text)] -> Bool -> Text -> Text -> Translations -> Journal -> Text -> Maybe (AccountName, Bool) -> BalanceReport -> HtmlUrl r
balanceReportAsHtml registerR here reports reportParams hideEmpty totlabel tottitle trs j qparam maccount (items, total) =
  $(hamletFile "templates/balance-report.hamlet")
  where
    l = ledgerFromJournal Any j
    indent a = preEscapedString $ concat $ replicate (2 + 2 * a) "&nbsp;"
    -- A depth 0 sidebar's one row, all accounts in one, named "..." by
    -- the report, is labelled as hledger-ui does, and always shown.
    isAll = (== "...")
    -- TRANSLATORS: the name of a depth 0 report's one row, all accounts in one.
    acctLabel acct adisplay = if isAll acct then trc trs "accounts" "All" else adisplay
    hasSubAccounts acct = not (isAll acct) && maybe True (not . null . asubs) (ledgerAccount l acct)
    isInterestingAccount acct = isAll acct || maybe False isInteresting (ledgerAccount l acct)
      -- Costs and cost bases are stripped before the zero test, since they
      -- keep bought-and-fully-sold amounts from cancelling (eg a disposed
      -- lot, +10 A @ one cost and -10 A at another), and the sidebar
      -- displays such balances as zero.
      where isInteresting a = not (all (mixedAmountLooksZero . mixedAmountStripCosts . bdexcludingsubs) . pdperiods $ adata a) || any isInteresting (asubs a)
    matchesAcctSelector acct = maybe False ((`matchesAccount` acct) . accountRegisterQuery) maccount
    kept = registerKeptParams reportParams
    qps = [("q", qparam) | not (T.null qparam)]
    acctlink acct = (registerR, qps ++ accountParams True acct ++ kept)
    acctonlylink acct = (registerR, qps ++ accountParams False acct ++ kept)
    -- The register of everything, for the sidebar's search; the search
    -- form's clear button is the way out of a search.
    totallink = (registerR, qps ++ kept)

-- | A row of links above a report: a label, then each link's label,
-- title, target, and whether it is the one being shown.
-- Each label and title is a whole phrase, not a word slotted into a
-- sentence: an adjective that fits one language's sentence does not fit
-- another's, so a translation cannot be assembled from parts.
linksRow :: Text -> [(Text, Text, (r, [(Text, Text)]), Bool)] -> HtmlUrl r
linksRow = linksRowClass ""

-- | 'linksRow' with an extra class on the row: a hook for hledger.js's
-- keyboard shortcuts.
linksRowClass :: Text -> Text -> [(Text, Text, (r, [(Text, Text)]), Bool)] -> HtmlUrl r
linksRowClass cls rowlabel items =
  linksRowGroups cls rowlabel [[ (label, title, link, current, Nothing) | (label, title, link, current) <- items ]]

-- | 'linksRowClass' with the links in groups, shown a little apart, each
-- link with the key that goes to it after g, if it has one (hledger.js).
linksRowGroups :: Text -> Text -> [[(Text, Text, (r, [(Text, Text)]), Bool, Maybe Text)]] -> HtmlUrl r
linksRowGroups cls rowlabel groups renderUrl =
    H.p ! A.class_ (H.toValue $ T.unwords $ "report-links" : [cls | not (T.null cls)]) $ do
      unless (T.null rowlabel) $ H.span ! A.class_ "row-label" $ H.toHtml rowlabel
      for_ (zip [0 :: Int ..] groups) $ \(g, items) ->
        for_ (zip [0 :: Int ..] items) $ \(i, (label, title, link, current, mgokey)) ->
          let classes = ["current" | current] ++ ["group-start" | g > 0, i == 0]
          in H.a !? (not (null classes), A.class_ (H.toValue $ T.unwords classes))
                 ! A.href (H.toValue $ uncurry renderUrl link)
                 ! A.title (H.toValue title)
                 !? (isJust mgokey, H.dataAttribute "gokey" (H.toValue $ fromMaybe "" mgokey)) $
               H.toHtml label

-- | A page's rows of report controls behind a disclosure, closed by
-- default so the page stays uncluttered. Opening it is remembered per
-- browser in the showcontrols cookie (hledger.js), which the server
-- reads (App.showControls), so each page is born the way the last one
-- was left and nothing moves after paint.
-- Closed, it lists the options in effect, so that the page's state is
-- never hidden (see optionsSummary).
controlsToggle :: Translations -> Bool -> [Text] -> HtmlUrl r -> HtmlUrl r
controlsToggle trs open summary rows =
  -- TRANSLATORS: the disclosure hiding each page's rows of report controls: its text, and its tooltip.
  [hamlet|
<details .report-controls :open:open>
  <summary title=#{tr trs "Show the options that reshape this view"}>
    #{tr trs "Options"}
    $if not (null summary)
      <span .options-summary>#{T.intercalate " · " summary}
  ^{rows}
|]

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
      ["interval", "accum", "depth", "list", "value", "infer", "empty", "lots", "closed",
       "total", "avg", "costs", "sort", "pct", "calc", "date2"]
    phrase = \case
      ("interval", w)     -> Just $ fromMaybe w $ lookup w
        [ ("yearly", tr trs "Yearly"), ("quarterly", tr trs "Quarterly"), ("monthly", tr trs "Monthly")
        , ("weekly", tr trs "Weekly"), ("daily", tr trs "Daily") ]
      -- TRANSLATORS: the depth limit, in the list of options in effect.
      ("depth", n)        -> do
        d <- readMay (T.unpack n) :: Maybe Int
        guard (d < deepest)
        Just $ trf trs "Depth {depth}" [("depth", n)]
      ("accum", a)        -> lookup a
        [ ("change", tr trs "Balance changes"), ("historical", tr trs "Ending balances")
        , ("cumulative", tr trs "Cumulative totals") ]
      ("value", "none")   -> Just $ tr trs "As recorded"
      ("value", "cost")   -> Just $ tr trs "At cost"
      ("value", _)        -> Just $ tr trs "At market value"
      ("list", "tree")    -> Just $ trc trs "accounts" "Tree"
      ("list", "flat")    -> Just $ trc trs "accounts" "List"
      ("sort", "amount")  -> Just $ tr trs "By amount"
      ("pct", "1")        -> Just $ tr trs "Percentages"
      ("calc", c)         -> lookup c
        [ ("valuechange", tr trs "Value change"), ("gain", tr trs "Unrealized gain")
        , ("count", tr trs "Posting counts") ]
      -- TRANSLATORS: options in effect, listed on the closed options disclosure.
      ("total", "1")      -> Just $ tr trs "Row totals"
      ("avg", "1")        -> Just $ tr trs "Row averages"
      ("infer", "1")      -> Just $ tr trs "Inferred prices"
      ("empty", "0")      -> Just $ tr trs "Zero balances hidden"
      ("empty", "1")      -> Just $ tr trs "Zero balances shown"
      ("lots", "1")       -> Just $ tr trs "Lots shown"
      ("costs", "1")      -> Just $ tr trs "Costs shown"
      ("closed", "1")     -> Just $ tr trs "Closed positions shown"
      ("closed", "0")     -> Just $ tr trs "Closed positions hidden"
      ("date2", "1")      -> Just $ tr trs "Secondary dates"
      _                   -> Nothing

-- | A journal or register page's heading: the given title, then the
-- search's dates, if it has any, shown as the balance pages show theirs
-- (eg "General Journal in 2024"), then ", filtered" if it has other
-- filters. A depth limit is not one.
searchHeading :: Translations -> Bool -> Query -> Text -> Text
searchHeading trs secondary q title = case (spn == nulldatespan, filtered) of
  (True,  False) -> title
  (True,  True)  -> trf trs "{title}, filtered" [("title", title)]
  -- TRANSLATORS: a journal or register page's heading when the search has dates, eg "General Journal in 2024".
  (False, False) -> trf trs "{title} in {dates}" [("title", title), ("dates", showDateSpan spn)]
  (False, True)  -> trf trs "{title} in {dates}, filtered" [("title", title), ("dates", showDateSpan spn)]
  where
    spn = queryDateSpan secondary q
    filtered = filterQuery (\t -> not (queryIsDepth t || queryIsDateOrDate2 t)) q /= Any

-- | Rows of controls that take effect on other pages, their labels
-- muted: they show and preserve the url's report state here too, so it
-- is never invisible, and never lost by following a link.
inertControls :: Translations -> HtmlUrl r -> HtmlUrl r
inertControls trs rows =
  -- TRANSLATORS: the tooltip on the muted control rows of the journal and register pages.
  [hamlet|
<div .controls-inert title=#{tr trs "These controls take effect on the report pages"}>
  ^{rows}
|]

-- | A short usage hint below a row of controls, in muted small text.
-- The text arrives already translated, so that the literal at the call
-- site is what the extraction tool collects.
controlsHint :: Text -> HtmlUrl r
controlsHint t _ = H.p ! A.class_ "controls-hint" $ H.toHtml t

-- | Links choosing where market prices come from: declared ones only,
-- or inferred from transaction costs too, keeping the given parameters;
-- the source being used is marked.
pricesLinks :: Translations -> r -> [(Text, Text)] -> Bool -> HtmlUrl r
pricesLinks trs route kept inferOn =
  -- TRANSLATORS: the label before a page's market price source links, and the links' text and tooltips.
  linksRow (tr trs "Prices:")
    [ (tr trs "Declared", tr trs "Value amounts using declared market prices (P directives) only", (route, kept), not inferOn)
    , (tr trs "Inferred too", tr trs "Infer market prices from transaction costs too (--infer-market-prices)", (route, kept ++ [("infer", "1")]), inferOn)
    ]

-- | The accum parameter value naming an accumulation mode.
accumWord :: BalanceAccumulation -> Text
accumWord = \case
  PerPeriod  -> "change"
  Historical -> "historical"
  Cumulative -> "cumulative"

-- | The list parameter value naming an accounts mode.
listWord :: AccountListMode -> Text
listWord ALTree = "tree"
listWord ALFlat = "flat"

-- | How a page shows amounts: in the commodities they were recorded in,
-- converted to cost (as with -B), or converted with one of the market
-- valuations (as with -V, -X, and --value).
data AmountMode = AsRecorded | AtCost | AtVal ValuationType
  deriving (Eq, Show)

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

-- | Links to the same report page limited to each account depth, from 0
-- (only the total, as one row of all accounts, as --depth 0 shows) up
-- to the given deepest one, which removes the limit, as hledger-ui
-- does with a depth at or beyond the deepest. Each keeps the search and
-- the given parameters; the depth being shown, the given parameters'
-- depth, is marked, on the deepest link when there is no limit or it is
-- at or beyond the deepest.
-- The digit keys set a depth through the deepest link's url, and the -
-- and + keys step through the links, going round (hledger.js).
depthLinks :: Translations -> r -> [(Text, Text)] -> Text -> Int -> HtmlUrl r
depthLinks trs route kept qparam deepest =
  -- TRANSLATORS: the label before a report's depth links, and the links' text and tooltips.
  linksRowClass "depth" (tr trs "Depth:")
    [ (T.pack (show n), depthTitle n, link n, marked n) | n <- [0 .. deepest] ]
  where
    current = readMay . T.unpack =<< lookup "depth" kept
    marked n | n == deepest = maybe True (>= deepest) current
             | otherwise    = current == Just n
    -- TRANSLATORS: the tooltips of a report's depth links.
    depthTitle n
      | n == 0       = tr trs "Show only the total"
      | n == deepest = tr trs "Show accounts at every depth"
      | otherwise    = trf trs "Show accounts down to depth {depth}" [("depth", T.pack (show n))]
    link n =
      (route, [("q", qparam) | not (T.null qparam)] ++ filter ((/= "depth") . fst) kept ++ [("depth", T.pack (show (n :: Int))) | n < deepest])

-- | Links to the same report page showing amounts as recorded, at cost,
-- or at market value, keeping the given parameters; the mode being
-- shown, if it is one of these, is marked. The page's default mode, the
-- startup one, needs no parameter. The V key toggles between the first
-- link (as recorded) and the last (market value), and B the second, at
-- cost (hledger.js).
amountLinks :: Translations -> r -> [(Text, Text)] -> Maybe AmountMode -> Maybe AmountMode -> HtmlUrl r
amountLinks trs route kept startup current =
  -- TRANSLATORS: the label before a report's amount conversion links, and the links' text and tooltips.
  linksRowClass "amounts" (tr trs "Amounts:")
    [ (label, title, (route, kept ++ [("value", valueWord m) | Just m /= startup]), Just m == current)
    | (label, title, m) <-
        [ (tr trs "As recorded",     tr trs "Show amounts in the commodities they were recorded in", AsRecorded)
        , (tr trs "At cost",         tr trs "Show amounts converted to their cost, as recorded in transactions (-B)", AtCost)
        , (tr trs "At market value", tr trs "Show amounts converted to their market value at the end of each period, using market prices (-V)", AtVal (AtEnd Nothing))
        ]
    ]

-- | Links that show or hide accounts with zero balances: each rewrites
-- the empty parameter (1 shows them, 0 hides them, the direction of
-- the command line's -E), keeping the given parameters; the state
-- being shown is marked. The page's startup default needs no
-- parameter. The z key follows the other link (hledger.js).
zeroBalanceLinks :: Translations -> r -> [(Text, Text)] -> Bool -> Bool -> HtmlUrl r
zeroBalanceLinks trs route kept dfltHidden hidden =
  -- TRANSLATORS: the label before the links that show or hide zero balances, and the links' text and tooltips.
  [hamlet|
$newline never
<p .report-links .zero-balances>
  <span .row-label>#{tr trs "Zero balances:"}
  <a href=@?{link True} :hidden:.current title=#{tr trs "Hide accounts whose balances are zero"}>#{tr trs "Hidden"}
  <a href=@?{link False} :not hidden:.current title=#{tr trs "Show accounts whose balances are zero"}>#{tr trs "Shown"}
|]
  where link h = (route, kept ++ [("empty", if h then "0" else "1") | h /= dfltHidden])

-- | A row of links that each rewrite one kind of search term: each link
-- replaces the terms the row owns (those the predicate matches) with its
-- own term, or removes them, keeping the search's other terms and the
-- given parameters. The link whose term the search has is marked, or the
-- removing link when it has none.
queryTermRow :: r -> [(Text, Text)] -> Text -> (Text -> Bool) -> Text -> Text -> [(Text, Text, Maybe Text)] -> HtmlUrl r
queryTermRow route kept qparam owns cls rowlabel items =
  linksRowClass cls rowlabel [ (label, title, link mterm, current mterm) | (label, title, mterm) <- items ]
  where
    terms = searchTerms qparam
    rest = map quoteIfSpaced $ filter (not . owns) terms
    current mterm = filter owns terms == maybeToList mterm
    link mterm =
      (route, [("q", t) | let t = T.unwords $ rest ++ map quoteIfSpaced (maybeToList mterm), not (T.null t)] ++ kept)

-- | Links filtering by transaction status, as hledger-ui's U, P, and C
-- keys do: each rewrites the status: term in the search. The same keys
-- follow them, by their order here (hledger.js).
statusLinks :: Translations -> r -> [(Text, Text)] -> Text -> HtmlUrl r
statusLinks trs route kept qparam =
  -- TRANSLATORS: the label before a report's status filter links, and the links' text and tooltips.
  queryTermRow route kept qparam (T.isPrefixOf "status:") "status" (tr trs "Status:")
    [ (trc trs "status" "All", tr trs "Show transactions of any status", Nothing)
    , (tr trs "Unmarked", tr trs "Show only unmarked transactions (status:)",     Just "status:")
    , (tr trs "Pending",  tr trs "Show only pending transactions (status:!)",    Just "status:!")
    , (tr trs "Cleared",  tr trs "Show only cleared transactions (status:*)",    Just "status:*")
    ]

-- | Links filtering to real or virtual postings: each rewrites the
-- real: term in the search. The R key toggles Real, the second link
-- (hledger.js).
realLinks :: Translations -> r -> [(Text, Text)] -> Text -> HtmlUrl r
realLinks trs route kept qparam =
  -- TRANSLATORS: the label before a report's real/virtual filter links, and the links' text and tooltips.
  queryTermRow route kept qparam (T.isPrefixOf "real:") "postings" (tr trs "Postings:")
    [ (trc trs "postings" "All", tr trs "Show real and virtual postings", Nothing)
    , (tr trs "Real",    tr trs "Show only real postings, as -R does (real:1)", Just "real:1")
    , (tr trs "Virtual", tr trs "Show only virtual postings, the parenthesized ones (real:0)", Just "real:0")
    ]

-- | Links showing the report's accounts as a flat list or a tree,
-- keeping the given parameters; the mode being shown is marked, and
-- the page's default mode, the startup one, needs no parameter. The t
-- key toggles them (hledger.js).
listModeLinks :: Translations -> r -> [(Text, Text)] -> AccountListMode -> AccountListMode -> HtmlUrl r
listModeLinks trs route kept dflt mode =
  -- TRANSLATORS: the label before a report's list/tree links, and the links' text and tooltips.
  linksRowClass "accounts" (tr trs "Accounts:")
    [ (trc trs "accounts" "List", tr trs "Show accounts as a flat list (--flat)", link ALFlat, mode == ALFlat)
    , (trc trs "accounts" "Tree", tr trs "Show accounts as a tree (--tree)", link ALTree, mode == ALTree)
    ]
  where link m = (route, kept ++ [("list", listWord m) | m /= dflt])

-- | Toggles adding a row-total and a row-average column to a
-- multi-period report, as -T and -A do; the columns shown are marked.
-- The T and A keys follow these links, by their order here (hledger.js).
columnsLinks :: Translations -> r -> [(Text, Text)] -> Bool -> Bool -> HtmlUrl r
columnsLinks trs route kept total avg =
  -- TRANSLATORS: the label before a report's extra-column toggles, and the toggles' text and tooltips.
  linksRowClass "columns" (tr trs "Extra columns:")
    [ (trc trs "column" "Total", tr trs "Add a column totaling each row (-T)",
        (route, kept ++ [("avg", "1") | avg] ++ [("total", "1") | not total]), total)
    , (trc trs "column" "Average", tr trs "Add a column averaging each row (-A)",
        (route, kept ++ [("total", "1") | total] ++ [("avg", "1") | not avg]), avg)
    ]

-- | Links sorting the report's rows by account name or by amount,
-- keeping the given parameters; the order being shown is marked.
-- The S key toggles By amount, the second link (hledger.js).
sortLinks :: Translations -> r -> [(Text, Text)] -> Bool -> HtmlUrl r
sortLinks trs route kept byAmount =
  -- TRANSLATORS: the label before a report's sort links, and the links' text and tooltips.
  linksRowClass "sort" (tr trs "Sort:")
    [ (tr trs "By account", tr trs "Sort rows by account name", (route, kept), not byAmount)
    , (tr trs "By amount", tr trs "Sort rows by their amounts, largest first (-S)", (route, kept ++ [("sort", "amount")]), byAmount)
    ]

-- | Links showing the report's numbers as amounts or as percentages of
-- their column's total, keeping the given parameters.
percentLinks :: Translations -> r -> [(Text, Text)] -> Bool -> HtmlUrl r
percentLinks trs route kept pct =
  -- TRANSLATORS: the label before a report's amounts/percentages links, and the links' text and tooltips.
  linksRow (tr trs "Numbers:")
    [ (trc trs "numbers" "Amounts", tr trs "Show the amounts", (route, kept), not pct)
    , (tr trs "Percentages", tr trs "Show each amount as a percentage of its column's total (-%)", (route, kept ++ [("pct", "1")]), pct)
    ]

-- | Links choosing what the report's cells calculate, as the balance
-- commands' --valuechange, --gain, and --count flags do.
calcLinks :: Translations -> r -> [(Text, Text)] -> BalanceCalculation -> HtmlUrl r
calcLinks trs route kept calc =
  -- TRANSLATORS: the label before a report's calculation links, and the links' text and tooltips.
  linksRow (tr trs "Calculate:")
    [ (trc trs "calculation" "Sums", tr trs "Show sums of postings", (route, kept), calc == CalcChange)
    , (tr trs "Value change", tr trs "Show how period-end market values changed (--valuechange)", link "valuechange", calc == CalcValueChange)
    , (tr trs "Unrealized gain", tr trs "Show unrealized capital gains: market value minus cost (--gain)", link "gain", calc == CalcGain)
    , (tr trs "Posting counts", tr trs "Count the postings instead of summing them (--count)", link "count", calc == CalcPostingsCount)
    ]
  where link w = (route, kept ++ [("calc", w)])

-- | Links showing or hiding the costs recorded with a register's
-- amounts (10 AAPL @ $95), keeping the given parameters.
costsLinks :: Translations -> r -> [(Text, Text)] -> Bool -> HtmlUrl r
costsLinks trs route kept on =
  -- TRANSLATORS: the label before the register's cost links, and the links' text and tooltips.
  linksRow (tr trs "Costs:")
    [ (trc trs "costs" "Hidden", tr trs "Show amounts without their costs", (route, kept), not on)
    , (trc trs "costs" "Shown", tr trs "Show amounts with the costs recorded in the journal", (route, kept ++ [("costs", "1")]), on)
    ]

-- | Links that show or hide lot detail: each holding's individual lots,
-- shown as lot subaccounts (the lots parameter; 1 shows them).
-- The L key toggles between them (hledger.js).
lotsLinks :: Translations -> r -> [(Text, Text)] -> Bool -> HtmlUrl r
lotsLinks trs route kept on =
  -- TRANSLATORS: the label before a report's lot detail links, and the links' text and tooltips.
  linksRowClass "lots" (tr trs "Lots:")
    [ (trc trs "lots" "Hidden", tr trs "Aggregate each account's lots", (route, kept), not on)
    , (trc trs "lots" "Shown", tr trs "Show each lot separately (--lots)", (route, kept ++ [("lots", "1")]), on)
    ]

-- | Links that show or hide fully closed positions: commodities no
-- longer held, with realized gains to show (the closed parameter;
-- 1 shows them - the empty parameter keeps meaning zero balances).
closedLinks :: Translations -> r -> [(Text, Text)] -> Bool -> Bool -> HtmlUrl r
closedLinks trs route kept dfltHidden hidden =
  -- TRANSLATORS: the label before the holdings page's closed-position links, and the links' text and tooltips.
  linksRow (tr trs "Closed positions:")
    [ (trc trs "closed" "Hidden", tr trs "Show only open positions", link True, hidden)
    , (trc trs "closed" "Shown", tr trs "Also show fully disposed positions and their realized gains (-E)", link False, not hidden)
    ]
  where link h = (route, kept ++ [("closed", if h then "0" else "1") | h /= dfltHidden])

-- | Links choosing how the holdings page values holdings: each lot in
-- its own cost commodity (the default), or all in the market valuation
-- commodity, as -V does.
holdingsValueLinks :: Translations -> r -> [(Text, Text)] -> Bool -> HtmlUrl r
holdingsValueLinks trs route kept valued =
  -- TRANSLATORS: the label before the holdings page's valuation links, and the links' text and tooltips.
  linksRow (tr trs "Values:")
    [ (tr trs "Per cost commodity", tr trs "Value each holding in its own cost commodity", (route, kept), not valued)
    , (tr trs "At market value", tr trs "Convert values and costs to the market valuation commodity (-V)", (route, kept ++ [("value", "end")]), valued)
    ]

-- | Links filtering to accounts of one or more types: a link rewrites
-- the type: term in the search to its own type, and shift-clicking adds
-- or removes a type (hledger.js), the selection carried as one
-- type:AL.. term, whose letters mark their links. Not for the statement
-- pages, which choose their own types.
typeLinks :: Translations -> r -> [(Text, Text)] -> Text -> HtmlUrl r
typeLinks trs route kept qparam renderUrl =
  H.div ! A.class_ "types" $ do
    -- TRANSLATORS: the label before the account type filter links, and the links' text and tooltips.
    linksRow (tr trs "Type:")
      ( (trc trs "account type" "All", tr trs "Show accounts of every type", link Nothing, null selected)
      : [ (label, title, link (Just letter), letter `elem` selected)
        | (label, title, letter) <- types ]) renderUrl
  where
    types =
      [ (tr trs "Asset",      tr trs "Show only asset accounts (type:A)",      'A')
      , (tr trs "Liability",  tr trs "Show only liability accounts (type:L)",  'L')
      , (tr trs "Equity",     tr trs "Show only equity accounts (type:E)",     'E')
      , (tr trs "Revenue",    tr trs "Show only revenue accounts (type:R)",    'R')
      , (tr trs "Expense",    tr trs "Show only expense accounts (type:X)",    'X')
      , (tr trs "Cash",       tr trs "Show only cash accounts (type:C)",       'C')
      , (tr trs "Conversion", tr trs "Show only conversion accounts (type:V)", 'V')
      ]
    terms = searchTerms qparam
    rest = map quoteIfSpaced $ filter (not . T.isPrefixOf "type:") terms
    -- the letters of the search's type: terms
    selected = [c | t <- terms, Just ls <- [T.stripPrefix "type:" t], c <- T.unpack (T.toUpper ls)]
    link mletter =
      (route, [("q", t) | let t = T.unwords $ rest ++ ["type:" <> T.singleton l | Just l <- [mletter]], not (T.null t)] ++ kept)

-- | Links filtering to one or more of the journal's commodities: a link
-- rewrites the cur: term in the search to its own commodity, and
-- shift-clicking adds or removes one (hledger.js), the selection
-- carried as a single cur:A|B term, whose alternatives mark their
-- links. The symbols are regex-escaped, since cur: matches whole
-- symbols as regular expressions. Each link carries its pattern, and
-- the row the search's other terms, as data attributes, so the script
-- composes selections without parsing the search: any symbol works,
-- spaces included, a composed term containing one being quoted whole.
-- The given pre-translated hint renders below the row, and fewer than
-- two commodities render nothing, hint included.
-- The collapsed list's open state is remembered per browser in the
-- showcommodities cookie (hledger.js), rendered here server side like
-- the controls disclosure's.
commodityLinks :: Translations -> r -> [(Text, Text)] -> Text -> Bool -> Text -> Journal -> HtmlUrl r
commodityLinks trs route kept qparam open hint j renderUrl
  | length syms < 2 = mempty
  -- A few commodities are a row like any other; many collapse to a
  -- line showing the selection, the full list opening on demand.
  | length syms <= 6 =
      (H.div ! A.class_ "commodities" ! H.dataAttribute "rest" (H.toValue restText) $
        links True)
      <> hinted
  | otherwise =
      (H.div ! A.class_ "commodities" ! H.dataAttribute "rest" (H.toValue restText) $
        H.details !? (open, A.open "open") $ do
          H.summary ! A.title (H.toValue $ tr trs "List all the commodities") $ do
            -- TRANSLATORS: the label before a page's commodity filter links, and the links' text and tooltips.
            H.span ! A.class_ "row-label" $ H.toHtml $ tr trs "Commodity:"
            H.span ! A.class_ "sel" $ H.toHtml selectionText
          links False)
      <> hinted
  where
    hinted = controlsHint hint renderUrl
    links withLabel =
      H.p ! A.class_ "report-links" $ do
        H.span ! A.class_ "row-label" $
          if withLabel then H.toHtml $ tr trs "Commodity:" else mempty
        H.a !? (null selected, A.class_ "current")
            ! A.href (H.toValue $ uncurry renderUrl alllink)
            ! A.title (H.toValue $ tr trs "Show amounts in every commodity") $
          H.toHtml $ trc trs "commodity" "All"
        for_ syms $ \sym -> do
          let pat = regexEscape sym
          H.a !? (pat `elem` selected, A.class_ "current")
              ! A.href (H.toValue $ uncurry renderUrl $ symlink pat)
              ! A.title (H.toValue $ trf trs "Show only amounts in {commodity}" [("commodity", sym)])
              ! H.dataAttribute "cur" (H.toValue pat) $
            H.toHtml sym
    chosen = [sym | sym <- syms, regexEscape sym `elem` selected]
    selectionText
      | null chosen = trc trs "commodity" "All"
      | otherwise = T.intercalate ", " chosen
    syms = filter (not . T.null) $ Set.toAscList $ journalCommodities j
    terms = searchTerms qparam
    rest = map quoteIfSpaced $ filter (not . T.isPrefixOf "cur:") terms
    restText = T.unwords rest
    -- the alternatives of the search's cur: term(s), marking their links
    selected = concatMap (splitAlternatives . T.drop 4) $ filter (T.isPrefixOf "cur:") terms
    symlink pat = (route, ("q", T.unwords $ rest ++ [quoteIfSpaced $ "cur:" <> pat]) : kept)
    alllink = (route, [("q", restText) | not (T.null restText)] ++ kept)
    -- Split a cur: pattern on its unescaped |s, regex alternation.
    splitAlternatives = map T.pack . go . T.unpack
      where
        go s = case break (== '|') s of
          (a, '|':b)
            | odd (length (takeWhile (== '\\') (reverse a))) ->
                case go b of (c:cs) -> (a ++ "|" ++ c) : cs; [] -> [a ++ "|"]
            | otherwise -> a : go b
          (a, _) -> [a]

-- | The parameters naming an account register's account: with its
-- subaccounts, or with subs=0, without them. (An inacct: or inacctonly:
-- term typed in the search becomes these; see App.normaliseUrlState.)
accountParams :: Bool -> AccountName -> [(Text, Text)]
accountParams = Anchor.accountParams

-- | The query selecting an account register's account, with its
-- subaccounts or without them (as inacct: and inacctonly: do).
accountRegisterQuery :: (AccountName, Bool) -> Query
accountRegisterQuery (a, subs) = Acct $ (if subs then accountNameToAccountRegex else accountNameToAccountOnlyRegex) a

mixedAmountAsHtml :: MixedAmount -> HtmlUrl a
mixedAmountAsHtml = mixedAmountAsHtmlWith noCostFmt{displayZeroCommodity=True}

-- | Like 'mixedAmountAsHtml' with a chosen display format, for a page
-- showing amounts with their costs.
mixedAmountAsHtmlWith :: AmountFormat -> MixedAmount -> HtmlUrl a
mixedAmountAsHtmlWith fmt b _ = amountLinesHtml b $ lines (showMixedAmountWith fmt b)

-- | An amount's lines, one per commodity, colored by the sign of the whole.
amountLinesHtml :: MixedAmount -> [String] -> Html
amountLinesHtml b ls =
  for_ ls $ \t -> do
    H.span ! A.class_ c $ toHtml t
    H.br
  where
    c = case isNegativeMixedAmount b of
      Just True -> "negative amount"
      _ -> "positive amount"

-- | How many commodities a balance shows in full. One of more shows
-- fewer, then a line saying how many more there are.
commoditiesShown :: Int
commoditiesShown = 3

-- | Like 'mixedAmountAsHtml', but showing at most 'commoditiesShown'
-- commodities, then a line saying how many more there are: for the
-- sidebar, where an account holding many commodities would otherwise
-- be a wall of lines. Searching for a commodity (cur:) shows it alone.
mixedAmountAsHtmlElided :: Translations -> MixedAmount -> HtmlUrl a
mixedAmountAsHtmlElided trs b _ = do
    amountLinesHtml b $ take commoditiesShown ls
    when (length ls > commoditiesShown) $ moreCommoditiesHtml trs (length ls - commoditiesShown)
  where
    ls = lines (showMixedAmountWith noCostFmt{displayZeroCommodity=True} b)

-- | Like 'mixedAmountAsHtml', for a register row's running balance, given
-- the row's amount. A balance of more than 'commoditiesShown' commodities
-- shows only those the amount has, at zero if the row closed one out,
-- then a line saying how many more there are, so that what the row
-- changed is not lost among the rest (which, row after row, would also be
-- most of the page). Searching for a commodity (cur:) shows its balance
-- alone.
runningBalanceAsHtml :: Translations -> MixedAmount -> MixedAmount -> HtmlUrl a
runningBalanceAsHtml trs amt bal render
  | length bs <= commoditiesShown = mixedAmountAsHtml bal' render
  | otherwise = do
      amountLinesHtml (mixed shown) $ concatMap (\a -> lines $ showMixedAmountWith fmt $ mixed [a]) shown
      when (hidden > 0) $ moreCommoditiesHtml trs hidden
  where
    fmt = noCostFmt{displayZeroCommodity=True}
    bal' = mixedAmountStripCosts bal
    -- its amounts as shown in full: the nonzero ones, or if none, every zero
    bs = amountsPreservingZeros bal'
    -- the commodities the row posted, including any netting to zero
    cs = Set.fromList $ map acommodity $ amountsRaw amt
    -- the balance in each, zeros included, each shown on its own so that
    -- a zero beside the others is not dropped
    shown = filter ((`Set.member` cs) . acommodity) $ amountsRaw bal'
    hidden = length $ filter ((`Set.notMember` cs) . acommodity) bs

-- | The line below an amount that shows fewer commodities than it has.
moreCommoditiesHtml :: Translations -> Int -> Html
moreCommoditiesHtml trs n = do
  H.span ! A.class_ "more-commodities" $ toHtml $ moreCommodities trs n
  H.br

-- | The note saying how many more commodities there are than an amount,
-- or the register chart, shows.
moreCommodities :: Translations -> Int -> Text
moreCommodities trs n =
  -- TRANSLATORS: the note for a balance, or the register chart, showing fewer commodities than it has.
  trf trs "… and {n} more" [("n", T.pack $ show n)]

-- Make a slug to uniquely identify this transaction
-- in hyperlinks (as far as possible).
transactionFragment :: Journal -> Transaction -> String
transactionFragment j Transaction{tindex, tsourcepos} = 
  printf "transaction-%d-%d" tfileindex tindex
  where
    -- the numeric index of this txn's file within all the journal files,
    -- or 0 if this txn has no known file (eg a forecasted txn)
    tfileindex = maybe 0 (+1) $ elemIndex (sourceName $ fst tsourcepos) (journalFilePaths j)

-- | The search's terms without its date terms, each quoted if it needs to be.
removeDates :: Text -> [Text]
removeDates = map quoteIfSpaced . Anchor.removeDates . searchTerms

-- | What 'normalisedSearch' moves out of a search: the search without
-- it, and the options found.
data MovedOptions = MovedOptions {
    moSearch   :: Text,
    moDepth    :: Maybe Int,
    moInterval :: Maybe Interval,
    moAccount  :: Maybe (AccountName, Bool)  -- ^ the account, and whether with subaccounts
  } deriving (Eq, Show)

-- | The report options in a search and in the old period parameter, which
-- hledger-web keeps in their own parameters (see App.normaliseUrlState):
-- the search without them, the depth of its last depth:N term, the
-- interval of its last date:INTERVAL term, else of the period parameter,
-- and the account of its first inacct: or inacctonly: term (the one an
-- account register used). A date:INTERVAL term is reduced to its date
-- span, if it has one, and the period parameter's date span joins the
-- search as a date: term. A depth:REGEX=N term, limiting some accounts
-- only, stays in the search. Nothing when there is nothing to move.
normalisedSearch :: Day -> Text -> Maybe Text -> Maybe MovedOptions
normalisedSearch today qparam mperiod
  | isNothing mdepth && null termIntervals && isNothing macct && isNothing mperiod = Nothing
  | otherwise = Just $ MovedOptions (T.unwords $ map quoteIfSpaced $ periodTerms ++ concatMap rest terms) mdepth mivl macct
  where
    terms = searchTerms qparam
    mdepth = lastMay $ mapMaybe flatDepth terms
    dateInterval t = T.stripPrefix "date:" t >>= splitPeriodExpr today
    termIntervals = [i | t <- terms, Just (i, _) <- [dateInterval t]]
    accountTerm t = (\a -> (a, False)) <$> T.stripPrefix "inacctonly:" t
                <|> (\a -> (a, True))  <$> T.stripPrefix "inacct:" t
    macct = listToMaybe $ mapMaybe accountTerm terms
    rest t
      | isJust (flatDepth t)           = []
      | isJust (accountTerm t)         = []
      | Just (_, sp) <- dateInterval t = ["date:" <> sp | not (T.null sp)]
      | otherwise                      = [t]
    -- A period that is not an interval and a span is a span only (or
    -- unparseable, which its date: term then reports).
    (periodInterval, periodTerms) = case mperiod of
      Nothing -> (Nothing, [])
      Just p  -> case splitPeriodExpr today p of
        Just (i, sp) -> (Just i, ["date:" <> sp | not (T.null sp)])
        Nothing      -> (Nothing, ["date:" <> p])
    mivl = lastMay termIntervals <|> periodInterval

-- | Split a period expression's reporting interval from its date span,
-- keeping the span as written, eg "monthly in 2025" gives monthly and
-- "in 2025". Nothing when it does not start with an interval, or what
-- follows is not a date span.
splitPeriodExpr :: Day -> Text -> Maybe (Interval, Text)
splitPeriodExpr today s = do
  (ivl, rest) <- either (const Nothing) Just $
    parsewith ((,) <$> (skipNonNewlineSpaces *> reportingintervalp) <*> (skipNonNewlineSpaces *> getInput)) (T.toLower s)
  let sp = T.strip rest
  if T.null sp || either (const False) ((== NoInterval) . fst) (parsePeriodExpr today sp)
    then Just (ivl, sp)
    else Nothing

-- | The depth a depth:N term limits all accounts to.
flatDepth :: Text -> Maybe Int
flatDepth t = do
  n <- T.stripPrefix "depth:" t
  if not (T.null n) && T.all isDigit n then readMay (T.unpack n) else Nothing

-- | The search's terms; none for an empty search.
searchTerms :: Text -> [Text]
searchTerms = filter (not . T.null) . Query.words'' queryprefixes

-- | The search for the journal page narrowed to a day: the day's date
-- term in place of any date terms.
journalDayQuery :: Text -> Day -> Text
journalDayQuery qparam d =
  T.unwords $ ("date:" <> showDate d) : removeDates qparam
