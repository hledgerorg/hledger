-- | /journal handlers.

{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Web.Handler.JournalR where

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Web.Import
import Hledger.Web.WebOptions
import Hledger.Web.Widget.AddForm (addModal)
import Hledger.Web.Widget.Common
            (accountQuery, mixedAmountAsHtml,
             transactionFragment, replaceInacct)

-- | The formatted journal view, with sidebar.
getJournalR :: Handler Html
getJournalR = do
  checkServerSideUiEnabled
  VD{perms, j, q, opts, qparam, qopts, today} <- getViewData
  require ViewPermission
  let title = case inAccount qopts of
        Nothing -> "General Journal"
        Just (a, inclsubs) -> "Transactions in " <> a <> if inclsubs then "" else " (excluding subaccounts)"
      title' = title <> if q /= Any then ", filtered" else ""
      acctlink a = (RegisterR, [("q", replaceInacct qparam $ accountQuery a)])
      rspec = (reportspec_ $ cliopts_ opts){_rsQuery = filterQuery (not . queryIsDepth) q}
      items = reverse $
        styleAmounts (journalCommodityStylesWith HardRounding j) $
        entriesReport rspec j
      transactionFrag = transactionFragment j

  defaultLayout $ do
    setTitle "journal - hledger-web"
    $(widgetFile "journal")
