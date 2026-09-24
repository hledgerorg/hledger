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
  , helplink
  , mixedAmountAsHtml
  , fromFormSuccess
  , writeJournalTextIfValidAndChanged
  , journalFile404
  , transactionFragment
  , removeDates
  , removeInacct
  , replaceInacct
  ) where

import Control.Monad.Except (ExceptT, mapExceptT)
import Data.Foldable (find, for_)
import Data.List (elemIndex)
import Data.Text (Text)
import Data.Text qualified as T
import System.FilePath (takeFileName)
import Text.Blaze ((!), textValue)
import Text.Blaze.Html5 qualified as H
import Text.Blaze.Html5.Attributes qualified as A
import Text.Blaze.Internal (preEscapedString)
import Text.Hamlet (hamletFile)
import Text.Printf (printf)
import Yesod

import Hledger.Utils.I18n (Translations, tr, trc)
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

-- | Render a "BalanceReport" as html.
balanceReportAsHtml :: Eq r => (r, r) -> r -> Bool -> Translations -> Journal -> Text -> [QueryOpt] -> BalanceReport -> HtmlUrl r
balanceReportAsHtml (journalR, registerR) here hideEmpty trs j qparam qopts (items, total) =
  $(hamletFile "templates/balance-report.hamlet")
  where
    l = ledgerFromJournal Any j
    indent a = preEscapedString $ concat $ replicate (2 + 2 * a) "&nbsp;"
    hasSubAccounts acct = maybe True (not . null . asubs) $ ledgerAccount l acct
    isInterestingAccount acct = maybe False isInteresting $ ledgerAccount l acct
      where isInteresting a = not (all (mixedAmountLooksZero . bdexcludingsubs) . pdperiods $ adata a) || any isInteresting (asubs a)
    matchesAcctSelector acct = Just True == ((`matchesAccount` acct) <$> inAccountQuery qopts)

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

-- | Links to the same report page showing balance changes or ending
-- balances, keeping the given parameters; the one being shown is marked.
accumulationLinks :: Translations -> r -> [(Text, Text)] -> BalanceAccumulation -> HtmlUrl r
accumulationLinks trs route kept current =
  -- TRANSLATORS: the label before a report's accumulation mode links, and the links' text and tooltips.
  linksRow (tr trs "Show:")
    [ (tr trs "Balance changes", tr trs "Show how much each balance changed in each period",
        (route, kept), current /= Historical)
    , (tr trs "Ending balances", tr trs "Show each balance at the end of each period, including everything before it",
        (route, kept ++ [("accum", "historical")]), current == Historical)
    ]

accountQuery :: AccountName -> Text
accountQuery = ("inacct:" <>) .  quoteIfSpaced

accountOnlyQuery :: AccountName -> Text
accountOnlyQuery = ("inacctonly:" <>) . quoteIfSpaced

mixedAmountAsHtml :: MixedAmount -> HtmlUrl a
mixedAmountAsHtml b _ =
  for_ (lines (showMixedAmountWith noCostFmt{displayZeroCommodity=True} b)) $ \t -> do
    H.span ! A.class_ c $ toHtml t
    H.br
  where
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
removeDates = map quoteIfSpaced . Anchor.removeDates . Query.words'' queryprefixes

-- | The search's terms without those naming an account, each quoted if it needs to be.
removeInacct :: Text -> [Text]
removeInacct = map quoteIfSpaced . Anchor.removeInacct . Query.words'' queryprefixes

replaceInacct :: Text -> Text -> Text
replaceInacct q acct = T.unwords $ acct : removeInacct q
