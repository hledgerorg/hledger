{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE TemplateHaskell   #-}

module Hledger.Web.Widget.Common
  ( accountQuery
  , accountOnlyQuery
  , balanceReportAsHtml
  , linksRow
  , reportLinks
  , intervalLinks
  , accumulationLinks
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
  , typeLinks
  , searchTerms
  , helplink
  , mixedAmountAsHtml
  , mixedAmountAsHtmlWith
  , mixedAmountAsHtmlElided
  , fromFormSuccess
  , writeJournalTextIfValidAndChanged
  , journalFile404
  , transactionFragment
  , removeDates
  , removeInacct
  , replaceInacct
  , journalDayQuery
  ) where

import Control.Monad (when)
import Control.Monad.Except (ExceptT, mapExceptT)
import Data.Char (isDigit)
import Data.Foldable (find, for_)
import Data.List (elemIndex)
import Data.Maybe (isNothing, mapMaybe, maybeToList)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar (Day)
import Safe (lastMay, readMay)
import System.FilePath (takeFileName)
import Text.Blaze ((!), textValue)
import Text.Blaze.Html5 qualified as H
import Text.Blaze.Html5.Attributes qualified as A
import Text.Blaze.Internal (preEscapedString)
import Text.Hamlet (hamletFile)
import Text.Printf (printf)
import Yesod

import Hledger.Utils.I18n (Translations, tr, trc, trf)
import Hledger
import Hledger.Cli.Anchor qualified as Anchor
import Hledger.Cli.Utils (writeFileWithBackupIfChanged)
import Hledger.Web.ReportPage (AmountMode(..), accumWord, listWord, valueWord)
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

-- | Render a "BalanceReport" as the sidebar: the journal and report
-- links (each report's route, label, and title, with the parameters
-- their links carry), then the accounts. The current page's row is marked.
balanceReportAsHtml ::
  Eq r => (r, r) -> r -> [(r, Text, Text)] -> [(Text, Text)] -> Bool -> Text -> Text -> Translations -> Journal -> Text -> [QueryOpt] -> BalanceReport -> HtmlUrl r
balanceReportAsHtml (journalR, registerR) here reports reportParams hideEmpty totlabel tottitle trs j qparam qopts (items, total) =
  $(hamletFile "templates/balance-report.hamlet")
  where
    l = ledgerFromJournal Any j
    indent a = preEscapedString $ concat $ replicate (2 + 2 * a) "&nbsp;"
    hasSubAccounts acct = maybe True (not . null . asubs) $ ledgerAccount l acct
    isInterestingAccount acct = maybe False isInteresting $ ledgerAccount l acct
      where isInteresting a = not (all (mixedAmountLooksZero . bdexcludingsubs) . pdperiods $ adata a) || any isInteresting (asubs a)
    matchesAcctSelector acct = Just True == ((`matchesAccount` acct) <$> inAccountQuery qopts)
    -- The journal and register links keep the states those pages read:
    -- the amounts mode, the accounts mode, inferred prices, and zero
    -- balances; each link rewrites the search itself.
    kept = [p | p@(k, _) <- reportParams, k `elem` ["value", "list", "infer", "empty"]]
    acctlink acct = (registerR, ("q", replaceInacct qparam $ accountQuery acct) : kept)
    acctonlylink acct = (registerR, ("q", replaceInacct qparam $ accountOnlyQuery acct) : kept)
    -- The journal, and the register of everything, for the sidebar's
    -- search minus any account term; the search form's clear button is
    -- the way out of a search.
    journallink = (journalR, [("q", t) | let t = T.unwords $ removeInacct qparam, not (T.null t)] ++ kept)
    totallink = (registerR, [("q", t) | let t = T.unwords $ removeInacct qparam, not (T.null t)] ++ kept)

-- | A row of links above a report: a label, then each link's label,
-- title, target, and whether it is the one being shown.
-- Each label and title is a whole phrase, not a word slotted into a
-- sentence: an adjective that fits one language's sentence does not fit
-- another's, so a translation cannot be assembled from parts.
linksRow :: Text -> [(Text, Text, (r, [(Text, Text)]), Bool)] -> HtmlUrl r
linksRow rowlabel items = $(hamletFile "templates/balance-links.hamlet")

-- | Links to the report pages, given as route, label, and title,
-- keeping the given parameters; the page being shown is marked.
reportLinks :: Eq r => Translations -> r -> [(Text, Text)] -> [(r, Text, Text)] -> HtmlUrl r
reportLinks trs here kept menu =
  -- TRANSLATORS: the label before a page's report links.
  linksRow (tr trs "Report:") [ (tr trs label, tr trs title, (route, kept), route == here) | (route, label, title) <- menu ]

-- | Links to the same report page for each reporting interval, keeping
-- the search, the period's date span, and the given parameters; the
-- interval being shown is marked.
intervalLinks :: Translations -> r -> [(Text, Text)] -> Text -> DateSpan -> Interval -> HtmlUrl r
intervalLinks trs route kept qparam spn current =
  -- TRANSLATORS: the label before a report's interval links.
  linksRow (tr trs "Interval:")
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
    -- Each link keeps the period's date span, so that changing the
    -- interval does not silently widen the report to the whole journal.
    -- "monthly 2025-01-01..2025-12-31" is a period expression like any other.
    spantext = if spn == nulldatespan then "" else showDateSpanForQuery spn
    periodparam mword = case (mword, spantext) of
      (Nothing,   "") -> []
      (Nothing,   sp) -> [("period", sp)]
      (Just w,    "") -> [("period", w)]
      (Just w,    sp) -> [("period", w <> " " <> sp)]
    link mword =
      (route, periodparam mword ++ [("q", qparam) | not (T.null qparam)] ++ kept)

-- | Links to the same report page for each accumulation mode: balance
-- changes, ending balances, or cumulative totals. They keep the given
-- parameters; the page's own default mode needs none. The mode being
-- shown is marked.
accumulationLinks :: Translations -> r -> [(Text, Text)] -> BalanceAccumulation -> BalanceAccumulation -> HtmlUrl r
accumulationLinks trs route kept dflt current =
  -- TRANSLATORS: the label before a report's accumulation mode links, and the links' text and tooltips.
  linksRow (tr trs "Show:")
    [ (tr trs "Balance changes", tr trs "Show how much each balance changed in each period",
        link PerPeriod, current == PerPeriod)
    , (tr trs "Ending balances", tr trs "Show each balance at the end of each period, including everything before it",
        link Historical, current == Historical)
    , (tr trs "Cumulative totals", tr trs "Show each balance's change since the start of the report (--cumulative)",
        link Cumulative, current == Cumulative)
    ]
  where link m = (route, kept ++ [("accum", accumWord m) | m /= dflt])

-- | Links to the same report page limited to each account depth, from 1
-- up to (but not including) the given deepest one, after an All link
-- that removes the limit. Each replaces the search's depth limit and
-- keeps its other terms and the given parameters; the depth being shown
-- is marked. (A depth:0 term, a single total, can be typed in the search.)
depthLinks :: Translations -> r -> [(Text, Text)] -> Text -> Int -> HtmlUrl r
depthLinks trs route kept qparam deepest =
  -- TRANSLATORS: the label before a report's depth links, and the links' text and tooltips.
  linksRow (tr trs "Depth:") $
    (trc trs "depth" "All", tr trs "Show accounts at every depth", link Nothing, maybe True (>= deepest) current)
    : [ (T.pack (show n), depthTitle n, link (Just n), current == Just n)
      | n <- [1 .. deepest - 1] ]
  where
    current = searchDepth qparam
    -- TRANSLATORS: the tooltips of a report's depth links.
    depthTitle n = trf trs "Show accounts down to depth {depth}" [("depth", T.pack (show n))]
    link mn =
      (route, [("q", t) | let t = T.unwords $ removeDepth qparam ++ ["depth:" <> T.pack (show (n :: Int)) | Just n <- [mn]], not (T.null t)] ++ kept)

-- | Links to the same report page showing amounts as recorded, at cost,
-- or at market value, keeping the given parameters; the mode being
-- shown, if it is one of these, is marked. The page's default mode, the
-- startup one, needs no parameter.
amountLinks :: Translations -> r -> [(Text, Text)] -> Maybe AmountMode -> Maybe AmountMode -> HtmlUrl r
amountLinks trs route kept startup current =
  -- TRANSLATORS: the label before a report's amount conversion links, and the links' text and tooltips.
  linksRow (tr trs "Amounts:")
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
-- parameter. The e key follows the other link (hledger.js).
zeroBalanceLinks :: Translations -> r -> [(Text, Text)] -> Bool -> Bool -> HtmlUrl r
zeroBalanceLinks trs route kept dfltHidden hidden =
  -- TRANSLATORS: the label before the links that show or hide zero balances, and the links' text and tooltips.
  [hamlet|
<p .report-links .zero-balances>
  #{tr trs "Zero balances:"}
  <a href=@?{link False} :not hidden:.current title=#{tr trs "Show accounts whose balances are zero"}>#{tr trs "Shown"}
  <a href=@?{link True} :hidden:.current title=#{tr trs "Hide accounts whose balances are zero"}>#{tr trs "Hidden"}
|]
  where link h = (route, kept ++ [("empty", if h then "0" else "1") | h /= dfltHidden])

-- | A row of links that each rewrite one kind of search term: each link
-- replaces the terms the row owns (those the predicate matches) with its
-- own term, or removes them, keeping the search's other terms and the
-- given parameters. The link whose term the search has is marked, or the
-- removing link when it has none.
queryTermRow :: r -> [(Text, Text)] -> Text -> (Text -> Bool) -> Text -> [(Text, Text, Maybe Text)] -> HtmlUrl r
queryTermRow route kept qparam owns rowlabel items =
  linksRow rowlabel [ (label, title, link mterm, current mterm) | (label, title, mterm) <- items ]
  where
    terms = searchTerms qparam
    rest = map quoteIfSpaced $ filter (not . owns) terms
    current mterm = filter owns terms == maybeToList mterm
    link mterm =
      (route, [("q", t) | let t = T.unwords $ rest ++ map quoteIfSpaced (maybeToList mterm), not (T.null t)] ++ kept)

-- | Links filtering by transaction status, as hledger-ui's U, P, and C
-- keys do: each rewrites the status: term in the search.
statusLinks :: Translations -> r -> [(Text, Text)] -> Text -> HtmlUrl r
statusLinks trs route kept qparam =
  -- TRANSLATORS: the label before a report's status filter links, and the links' text and tooltips.
  queryTermRow route kept qparam (T.isPrefixOf "status:") (tr trs "Status:")
    [ (trc trs "status" "All", tr trs "Show transactions of any status", Nothing)
    , (tr trs "Unmarked", tr trs "Show only unmarked transactions (status:)",     Just "status:")
    , (tr trs "Pending",  tr trs "Show only pending transactions (status:!)",    Just "status:!")
    , (tr trs "Cleared",  tr trs "Show only cleared transactions (status:*)",    Just "status:*")
    ]

-- | Links filtering to real or virtual postings: each rewrites the
-- real: term in the search.
realLinks :: Translations -> r -> [(Text, Text)] -> Text -> HtmlUrl r
realLinks trs route kept qparam =
  -- TRANSLATORS: the label before a report's real/virtual filter links, and the links' text and tooltips.
  queryTermRow route kept qparam (T.isPrefixOf "real:") (tr trs "Postings:")
    [ (trc trs "postings" "All", tr trs "Show real and virtual postings", Nothing)
    , (tr trs "Real",    tr trs "Show only real postings, as -R does (real:1)", Just "real:1")
    , (tr trs "Virtual", tr trs "Show only virtual postings, the parenthesized ones (real:0)", Just "real:0")
    ]

-- | Links showing the report's accounts as a flat list or a tree,
-- keeping the given parameters; the mode being shown is marked, and
-- the page's default mode, the startup one, needs no parameter.
listModeLinks :: Translations -> r -> [(Text, Text)] -> AccountListMode -> AccountListMode -> HtmlUrl r
listModeLinks trs route kept dflt mode =
  -- TRANSLATORS: the label before a report's list/tree links, and the links' text and tooltips.
  linksRow (tr trs "Accounts:")
    [ (trc trs "accounts" "List", tr trs "Show accounts as a flat list (--flat)", link ALFlat, mode == ALFlat)
    , (trc trs "accounts" "Tree", tr trs "Show accounts as a tree (--tree)", link ALTree, mode == ALTree)
    ]
  where link m = (route, kept ++ [("list", listWord m) | m /= dflt])

-- | Toggles adding a row-total and a row-average column to a
-- multi-period report, as -T and -A do; the columns shown are marked.
columnsLinks :: Translations -> r -> [(Text, Text)] -> Bool -> Bool -> HtmlUrl r
columnsLinks trs route kept total avg =
  -- TRANSLATORS: the label before a report's extra-column toggles, and the toggles' text and tooltips.
  linksRow (tr trs "Extra columns:")
    [ (trc trs "column" "Total", tr trs "Add a column totaling each row (-T)",
        (route, kept ++ [("avg", "1") | avg] ++ [("total", "1") | not total]), total)
    , (trc trs "column" "Average", tr trs "Add a column averaging each row (-A)",
        (route, kept ++ [("total", "1") | total] ++ [("avg", "1") | not avg]), avg)
    ]

-- | Links sorting the report's rows by account name or by amount,
-- keeping the given parameters; the order being shown is marked.
sortLinks :: Translations -> r -> [(Text, Text)] -> Bool -> HtmlUrl r
sortLinks trs route kept byAmount =
  -- TRANSLATORS: the label before a report's sort links, and the links' text and tooltips.
  linksRow (tr trs "Sort:")
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

-- | Links filtering to accounts of one type: each rewrites the type:
-- term in the search. Not for the statement pages, which choose their
-- own types.
typeLinks :: Translations -> r -> [(Text, Text)] -> Text -> HtmlUrl r
typeLinks trs route kept qparam =
  -- TRANSLATORS: the label before the balance report's account type links, and the links' text and tooltips.
  queryTermRow route kept qparam (T.isPrefixOf "type:") (tr trs "Type:")
    [ (trc trs "account type" "All", tr trs "Show accounts of every type", Nothing)
    , (tr trs "Asset",      tr trs "Show only asset accounts (type:A)",      Just "type:A")
    , (tr trs "Liability",  tr trs "Show only liability accounts (type:L)",  Just "type:L")
    , (tr trs "Equity",     tr trs "Show only equity accounts (type:E)",     Just "type:E")
    , (tr trs "Revenue",    tr trs "Show only revenue accounts (type:R)",    Just "type:R")
    , (tr trs "Expense",    tr trs "Show only expense accounts (type:X)",    Just "type:X")
    , (tr trs "Cash",       tr trs "Show only cash accounts (type:C)",       Just "type:C")
    , (tr trs "Conversion", tr trs "Show only conversion accounts (type:V)", Just "type:V")
    ]

accountQuery :: AccountName -> Text
accountQuery = ("inacct:" <>) .  quoteIfSpaced

accountOnlyQuery :: AccountName -> Text
accountOnlyQuery = ("inacctonly:" <>) . quoteIfSpaced

mixedAmountAsHtml :: MixedAmount -> HtmlUrl a
mixedAmountAsHtml = mixedAmountAsHtmlWith noCostFmt{displayZeroCommodity=True}

-- | Like 'mixedAmountAsHtml' with a chosen display format, for a page
-- showing amounts with their costs.
mixedAmountAsHtmlWith :: AmountFormat -> MixedAmount -> HtmlUrl a
mixedAmountAsHtmlWith fmt b _ =
  for_ (lines (showMixedAmountWith fmt b)) $ \t -> do
    H.span ! A.class_ c $ toHtml t
    H.br
  where
    c = case isNegativeMixedAmount b of
      Just True -> "negative amount"
      _ -> "positive amount"

-- | Like 'mixedAmountAsHtml', but showing at most the given number of
-- commodities, then a line saying how many more there are: for the
-- sidebar, where an account holding many commodities would otherwise
-- be a wall of lines. Searching for a commodity (cur:) shows it alone.
mixedAmountAsHtmlElided :: Translations -> Int -> MixedAmount -> HtmlUrl a
mixedAmountAsHtmlElided trs n b _ = do
    for_ (take n ls) $ \t -> do
      H.span ! A.class_ c $ toHtml t
      H.br
    when (length ls > n) $ do
      -- TRANSLATORS: the sidebar's note for a balance with more commodities than it shows.
      H.span ! A.class_ "more-commodities" $ toHtml $
        trf trs "… and {n} more" [("n", T.pack $ show $ length ls - n)]
      H.br
  where
    ls = lines (showMixedAmountWith noCostFmt{displayZeroCommodity=True} b)
    c = case isNegativeMixedAmount b of
      Just True -> "negative amount"
      _ -> "positive amount"

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

-- | The search's terms without those naming an account, each quoted if it needs to be.
removeInacct :: Text -> [Text]
removeInacct = map quoteIfSpaced . Anchor.removeInacct . searchTerms

-- | The search's terms without its depth:N terms, each quoted if it needs
-- to be. Its depth:REGEX=N terms, which limit some accounts, stay.
removeDepth :: Text -> [Text]
removeDepth = map quoteIfSpaced . filter (isNothing . flatDepth) . searchTerms

-- | The search's depth limit, from its last depth:N term.
searchDepth :: Text -> Maybe Int
searchDepth = lastMay . mapMaybe flatDepth . searchTerms

-- | The depth a depth:N term limits all accounts to.
flatDepth :: Text -> Maybe Int
flatDepth t = do
  n <- T.stripPrefix "depth:" t
  if not (T.null n) && T.all isDigit n then readMay (T.unpack n) else Nothing

-- | The search's terms; none for an empty search.
searchTerms :: Text -> [Text]
searchTerms = filter (not . T.null) . Query.words'' queryprefixes

-- | The search for the journal page narrowed to a day: the day's date
-- term in place of any date terms, and without any account term, which
-- the journal page does not use.
journalDayQuery :: Text -> Day -> Text
journalDayQuery qparam d =
  T.unwords $ ("date:" <> showDate d) : removeDates (T.unwords $ removeInacct qparam)

replaceInacct :: Text -> Text -> Text
replaceInacct q acct = T.unwords $ acct : removeInacct q
