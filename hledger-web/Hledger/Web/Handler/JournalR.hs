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
import Hledger.Web.ReportPage (amountModeOf, deepestDepth, listWord, parseListMode, parseValue, setAmountMode, valueParams)
import Hledger.Web.Widget.Common
            (accountQuery, amountLinks, depthLinks,
             listModeLinks, mixedAmountAsHtml, realLinks, statusLinks, typeLinks,
             transactionFragment, replaceInacct, journalDayQuery, zeroBalanceLinks)

-- | The formatted journal view, with sidebar.
getJournalR :: Handler Html
getJournalR = do
  checkServerSideUiEnabled
  VD{perms, j, q, opts, qparam, qopts, today, trs} <- getViewData
  require ViewPermission
  hideEmpty <- hideEmptyAccounts
  mmode <- either (const Nothing) id . parseValue <$> lookupGetParam "value"
  mlist <- either (const Nothing) id . parseListMode <$> lookupGetParam "list"
  inferOn <- (== Just "1") <$> lookupGetParam "infer"
  pagereq <- pageRequest
  let title = case inAccount qopts of
        Nothing         -> tr trs "General Journal"
        Just (a, True)  -> trf trs "Transactions in {account}" [("account", a)]
        Just (a, False) -> trf trs "Transactions in {account} (excluding subaccounts)" [("account", a)]
      title' = if q /= Any then trf trs "{title}, filtered" [("title", title)] else title
      -- An account's register, opened on the page holding this transaction.
      acctlink a t = (RegisterR, ("q", replaceInacct qparam $ accountQuery a) : ("txn", T.pack $ show $ tindex t) : carried)
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
        datelessQuery today qparam
      transactionFrag = transactionFragment j
      -- Links staying on this page keep the states that shape the
      -- sidebar: zero balances, amounts, the accounts mode, and
      -- inferred prices. The journal's entries always show as written.
      roptsStartup = _rsReportOpts $ reportspec_ $ cliopts_ opts
      dfltHidden = empty_ roptsStartup
      emptyParams = [("empty", if hideEmpty then "0" else "1") | hideEmpty /= dfltHidden]
      valParams = valueParams roptsStartup mmode
      elist = fromMaybe (accountlistmode_ roptsStartup) mlist
      listParams = [("list", listWord elist) | elist /= accountlistmode_ roptsStartup]
      inferParams = [("infer", "1") | inferOn]
      carried = dbg1 "journal carried params" $ valParams ++ listParams ++ inferParams ++ emptyParams
      qps = [("q", qparam) | not (T.null qparam)]
      -- the rows of links above the entries: the filters (status,
      -- realness, type, tag, commodity, and depth), and the sidebar's
      -- accounts and amounts modes
      statusRow = statusLinks trs JournalR carried qparam
      realRow = realLinks trs JournalR carried qparam
      typeRow = typeLinks trs JournalR carried qparam
      -- The depth links clip the sidebar's accounts, or in tree mode
      -- fold them, and carry to the reports.
      deepest = deepestDepth (reportspec_ $ cliopts_ opts) j
      depthRow = depthLinks trs JournalR carried qparam deepest
      -- The amounts mode converts the sidebar's amounts, and tree mode
      -- adds its fold carets; the journal's entries always show as written.
      listRow = listModeLinks trs JournalR (qps ++ valParams ++ inferParams ++ emptyParams) (accountlistmode_ roptsStartup) elist
      amountsRow = amountLinks trs JournalR (qps ++ listParams ++ inferParams ++ emptyParams)
        (amountModeOf roptsStartup) (amountModeOf $ maybe id setAmountMode mmode roptsStartup)
      zeroRow = zeroBalanceLinks trs JournalR (qps ++ valParams ++ listParams ++ inferParams) dfltHidden hideEmpty

  defaultLayout $ do
    -- TRANSLATORS: the browser tab title of this page.
    setTitleI (HMsg "journal - hledger-web")
    $(widgetFile "journal")
