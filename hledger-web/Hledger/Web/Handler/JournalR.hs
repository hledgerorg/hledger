-- | /journal handlers.

{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Web.Handler.JournalR where

import Data.Text qualified as T
import Hledger.Utils.I18n (tr, trf)
import Hledger
import Hledger.Cli.CliOptions
import Hledger.Web.Import
import Hledger.Web.Paging
import Hledger.Web.WebOptions
import Hledger.Web.Widget.AddForm (addModal)
import Hledger.Web.Widget.Common
            (accountQuery, mixedAmountAsHtml,
             transactionFragment, replaceInacct, journalDayQuery)

-- | The formatted journal view, with sidebar.
getJournalR :: Handler Html
getJournalR = do
  checkServerSideUiEnabled
  VD{perms, j, q, opts, qparam, qopts, today, trs} <- getViewData
  require ViewPermission
  pagereq <- pageRequest
  let title = case inAccount qopts of
        Nothing         -> tr trs "General Journal"
        Just (a, True)  -> trf trs "Transactions in {account}" [("account", a)]
        Just (a, False) -> trf trs "Transactions in {account} (excluding subaccounts)" [("account", a)]
      title' = if q /= Any then trf trs "{title}, filtered" [("title", title)] else title
      -- An account's register, opened on the page holding this transaction.
      acctlink a t = (RegisterR, [("q", replaceInacct qparam $ accountQuery a), ("txn", T.pack $ show $ tindex t)])
      q' = filterQuery (not . queryIsDepth) q
      rspec = (reportspec_ $ cliopts_ opts){_rsQuery = q'}
      -- The matching transactions, newest first; this page shows one page of them.
      alltxns = reverse $
        styleAmounts (journalCommodityStylesWith HardRounding j) $
        entriesReport rspec j
      (page, items) = pageOf pagereq tindex alltxns
      -- The years the search matches in, ignoring any date term in it.
      years = map tdate $
        maybe alltxns (\dq -> entriesReport rspec{_rsQuery = filterQuery (not . queryIsDepth) dq} j) $
        datelessQuery today j qparam
      transactionFrag = transactionFragment j

  defaultLayout $ do
    -- TRANSLATORS: the browser tab title of this page.
    setTitleI (HMsg "journal - hledger-web")
    $(widgetFile "journal")
