-- | /journal handlers.

{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Web.Handler.JournalR where

import Hledger.Utils.I18n (tr, trf)
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
  VD{perms, j, q, opts, qparam, qopts, today, trs} <- getViewData
  require ViewPermission
  let title = case inAccount qopts of
        Nothing         -> tr trs "General Journal"
        Just (a, True)  -> trf trs "Transactions in {account}" [("account", a)]
        Just (a, False) -> trf trs "Transactions in {account} (excluding subaccounts)" [("account", a)]
      title' = if q /= Any then trf trs "{title}, filtered" [("title", title)] else title
      acctlink a = (RegisterR, [("q", replaceInacct qparam $ accountQuery a)])
      rspec = (reportspec_ $ cliopts_ opts){_rsQuery = filterQuery (not . queryIsDepth) q}
      items = reverse $
        styleAmounts (journalCommodityStylesWith HardRounding j) $
        entriesReport rspec j
      transactionFrag = transactionFragment j

  defaultLayout $ do
    -- TRANSLATORS: the browser tab title of this page.
    setTitleI (HMsg "journal - hledger-web")
    $(widgetFile "journal")
