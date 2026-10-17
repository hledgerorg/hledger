{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE TemplateHaskell   #-}

module Hledger.Web.Widget.Common
  ( accountQuery
  , accountOnlyQuery
  , balanceReportAsHtml
  , helplink
  , mixedAmountAsHtml
  , fromFormSuccess
  , writeJournalTextIfValidAndChanged
  , journalFile404
  , transactionFragment
  , removeDates
  , removeInacct
  , replaceInacct
  , journalDayQuery
  ) where

import Control.Monad.Except (ExceptT, mapExceptT)
import Data.Foldable (find, for_)
import Data.List (elemIndex)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar (Day)
import System.FilePath (takeFileName)
import Text.Blaze ((!), textValue)
import Text.Blaze.Html5 qualified as H
import Text.Blaze.Html5.Attributes qualified as A
import Text.Blaze.Internal (preEscapedString)
import Text.Hamlet (hamletFile)
import Text.Printf (printf)
import Yesod

import Hledger.Utils.I18n (Translations, tr)
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

-- | Render a "BalanceReport" as the sidebar: the journal and report
-- links (each report's route, label, and title, with the parameters
-- their links carry), then the accounts. The current page's row is marked.
balanceReportAsHtml ::
  Eq r => (r, r) -> r -> [(r, Text, Text)] -> [(Text, Text)] -> Bool -> Translations -> Journal -> Text -> [QueryOpt] -> BalanceReport -> HtmlUrl r
balanceReportAsHtml (journalR, registerR) here reports reportParams hideEmpty trs j qparam qopts (items, total) =
  $(hamletFile "templates/balance-report.hamlet")
  where
    l = ledgerFromJournal Any j
    indent a = preEscapedString $ concat $ replicate (2 + 2 * a) "&nbsp;"
    hasSubAccounts acct = maybe True (not . null . asubs) $ ledgerAccount l acct
    isInterestingAccount acct = maybe False isInteresting $ ledgerAccount l acct
      where isInteresting a = not (all (mixedAmountLooksZero . bdexcludingsubs) . pdperiods $ adata a) || any isInteresting (asubs a)
    matchesAcctSelector acct = Just True == ((`matchesAccount` acct) <$> inAccountQuery qopts)
    -- The journal, and the register of everything, for the sidebar's
    -- search minus any account term; the search form's clear button is
    -- the way out of a search.
    journallink = (journalR, [("q", t) | let t = T.unwords $ removeInacct qparam, not (T.null t)])
    totallink = (registerR, [("q", t) | let t = T.unwords $ removeInacct qparam, not (T.null t)])

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
removeDates = map quoteIfSpaced . Anchor.removeDates . searchTerms

-- | The search's terms without those naming an account, each quoted if it needs to be.
removeInacct :: Text -> [Text]
removeInacct = map quoteIfSpaced . Anchor.removeInacct . searchTerms

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
