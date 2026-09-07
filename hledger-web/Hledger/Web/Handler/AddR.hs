{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Hledger.Web.Handler.AddR
  ( getAddR
  , postAddR
  , putAddR
  ) where

import Data.Aeson.Types (Result(..))
import Data.List (intersperse)
import Data.Text qualified as T
import Network.HTTP.Types.Status (status400)
import Text.Blaze.Html (preEscapedToHtml)
import Yesod

import Hledger
import Hledger.Cli.Commands.Add (appendToJournalFileOrStdout, journalAddTransaction)
import Hledger.Web.Import
import Hledger.Web.WebOptions (WebOpts(..))
import Hledger.Web.Widget.AddForm (addForm)

-- | Replace newlines with spaces in the transaction fields which are written
-- to the journal file verbatim: the description, the code, and the posting
-- account names. A newline in one of these would split the rendered entry
-- across lines, letting arbitrary journal directives (eg an include) be
-- written into the file. The journal format can't represent a newline in
-- these fields anyway - their parsers stop at end of line - and the CSV
-- reader collapses them likewise, so nothing that could round trip is lost.
-- Comments are left alone: they are rendered as one ";" line per line, so
-- newlines in them are safe.
transactionCollapseNewlines :: Transaction -> Transaction
transactionCollapseNewlines t = t
  { tdescription = collapse $ tdescription t
  , tcode        = collapse $ tcode t
  , tpostings    = map collapseacct $ tpostings t
  }
  where
    collapse = T.map (\c -> if c == '\n' || c == '\r' then ' ' else c)
    -- Account names are also normalised to single spaces, since two spaces
    -- would end the account name when the entry is read back.
    collapseacct p = p{paccount = T.unwords . T.words $ paccount p}

getAddR :: Handler ()
getAddR = do
  checkServerSideUiEnabled
  postAddR

postAddR :: Handler ()
postAddR = do
  checkServerSideUiEnabled
  VD{j, today} <- getViewData
  require AddPermission

  ((res, view), enctype) <- runFormPost $ addForm j today
  case res of
    FormSuccess (t,f) -> do
      let t' = txnTieKnot $ transactionCollapseNewlines t
      liftIO $ do
        ensureJournalFileExists f
        appendToJournalFileOrStdout f (showTransaction t')
      setMessage "Transaction added."
      redirect JournalR
    FormMissing -> showForm view enctype
    FormFailure errs -> do
      -- Escape each error, then join the lines with <br>. An unbalanced
      -- transaction's error embeds an excerpt of the submitted entry (account
      -- names, amounts), so it must be escaped; only the <br> we insert is
      -- raw. (Cf EditR, which uses toHtml.)
      mapM_ (setMessage . mconcat . intersperse (preEscapedToHtml ("<br>" :: T.Text)) . map toHtml . T.lines) errs
      showForm view enctype
  where
    showForm view enctype =
      sendResponse =<< defaultLayout [whamlet|
        <h2>Add transaction
        <div .row.add-page>
          <form#addform.form.col-xs-12.col-sm-11 method=post enctype=#{enctype}>
            ^{view}
      |]

-- Add a single new transaction, send as JSON via PUT, to the journal.
-- The web form handler above should probably use PUT as well.
putAddR :: Handler RepJson
putAddR = do
  VD{j, opts} <- getViewData
  require AddPermission

  (r :: Result Transaction) <- parseCheckJsonBody
  case r of
    Error err -> sendStatusJSON status400 ("could not parse json: " ++ err ::String)
    Success t -> do
      void $ liftIO $ journalAddTransaction j (cliopts_ opts) $ transactionCollapseNewlines t
      sendResponseCreated TransactionsR
