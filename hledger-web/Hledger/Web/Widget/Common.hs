{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE TemplateHaskell   #-}

module Hledger.Web.Widget.Common
  ( accountQuery
  , accountOnlyQuery
  , balanceReportAsHtml
  , balanceReportLinks
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

import Hledger
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
balanceReportAsHtml :: Eq r => (r, r) -> r -> Bool -> Journal -> Text -> [QueryOpt] -> BalanceReport -> HtmlUrl r
balanceReportAsHtml (journalR, registerR) here hideEmpty j qparam qopts (items, total) =
  $(hamletFile "templates/balance-report.hamlet")
  where
    l = ledgerFromJournal Any j
    indent a = preEscapedString $ concat $ replicate (2 + 2 * a) "&nbsp;"
    hasSubAccounts acct = maybe True (not . null . asubs) $ ledgerAccount l acct
    isInterestingAccount acct = maybe False isInteresting $ ledgerAccount l acct
      where isInteresting a = not (all (mixedAmountLooksZero . bdexcludingsubs) . pdperiods $ adata a) || any isInteresting (asubs a)
    matchesAcctSelector acct = Just True == ((`matchesAccount` acct) <$> inAccountQuery qopts)

-- | Links to the balance report page, single-period and for each
-- interval, carrying the current search and date span; the report being
-- shown, identified by the interval it was built with, is marked.
balanceReportLinks :: r -> Text -> DateSpan -> Interval -> HtmlUrl r
balanceReportLinks balanceR qparam spn current =
  $(hamletFile "templates/balance-links.hamlet")
  where
    -- Each link's label and title is a whole phrase, not a word slotted
    -- into a sentence: an adjective that fits one language's sentence does
    -- not fit another's, so a translation cannot be assembled from parts.
    reports :: [(Text, Text, Maybe Text, Interval)]
    reports =
      [ ("Balance",   "Show the balance report",           Nothing,          NoInterval)
      , ("Yearly",    "Show the yearly balance report",    Just "yearly",    Years 1)
      , ("Quarterly", "Show the quarterly balance report", Just "quarterly", Quarters 1)
      , ("Monthly",   "Show the monthly balance report",   Just "monthly",   Months 1)
      , ("Weekly",    "Show the weekly balance report",    Just "weekly",    Weeks 1)
      , ("Daily",     "Show the daily balance report",     Just "daily",     Days 1)
      ]
    -- Each link keeps the period's date span, so that changing the
    -- interval does not silently widen the report to the whole journal.
    -- "monthly 2025-01-01..2025-12-31" is a period expression like any other.
    spantext = if spn == nulldatespan then "" else showDateSpan spn
    periodparam mword = case (mword, spantext) of
      (Nothing,   "") -> []
      (Nothing,   sp) -> [("period", sp)]
      (Just w,    "") -> [("period", w)]
      (Just w,    sp) -> [("period", w <> " " <> sp)]
    link mword =
      (balanceR, periodparam mword ++ [("q", qparam) | not (T.null qparam)])

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

removeDates :: Text -> [Text]
removeDates =
    map quoteIfSpaced .
    filter (\term ->
        not $ T.isPrefixOf "date:" term || T.isPrefixOf "date2:" term) .
    Query.words'' queryprefixes

removeInacct :: Text -> [Text]
removeInacct =
    map quoteIfSpaced .
    filter (\term ->
        not $ T.isPrefixOf "inacct:" term || T.isPrefixOf "inacctonly:" term) .
    Query.words'' queryprefixes

replaceInacct :: Text -> Text -> Text
replaceInacct q acct = T.unwords $ acct : removeInacct q
