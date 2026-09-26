-- | The financial statement pages: /balancesheet, /balancesheetequity,
-- /incomestatement, and /cashflow, showing the reports of the commands
-- of the same names.

{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Hledger.Web.Handler.StatementsR (
  getBalancesheetR,
  getBalancesheetequityR,
  getIncomestatementR,
  getCashflowR,
) where

import Text.Blaze.Html5 ((!))
import Text.Blaze.Html5 qualified as H
import Text.Blaze.Html5.Attributes qualified as A
import Yesod qualified
import Data.Text qualified as T

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Commands.Balancesheet (balancesheetSpec)
import Hledger.Cli.Commands.Balancesheetequity (balancesheetequitySpec)
import Hledger.Cli.Commands.Cashflow (cashflowSpec)
import Hledger.Cli.Commands.Incomestatement (incomestatementSpec)
import Hledger.Cli.CompoundBalanceCommand
import Hledger.Write.Spreadsheet qualified as Spr

import Hledger.Web.Import
import Hledger.Web.ReportPage
import Hledger.Web.WebOptions
import Hledger.Web.Widget.Common (helplink, intervalLinks, removeDates, removeInacct, reportLinks)

getBalancesheetR, getBalancesheetequityR, getIncomestatementR, getCashflowR :: Handler Html
getBalancesheetR       = statementPage BalancesheetR       "balance sheet - hledger-web"             balancesheetSpec
getBalancesheetequityR = statementPage BalancesheetequityR "balance sheet with equity - hledger-web" balancesheetequitySpec
getIncomestatementR    = statementPage IncomestatementR    "income statement - hledger-web"          incomestatementSpec
getCashflowR           = statementPage CashflowR           "cashflow statement - hledger-web"        cashflowSpec

-- | A statement page: the command's report for the page's search and
-- period, with sidebar. The report's own accumulation mode applies
-- (ending balances for the balance sheets, changes for the others)
-- unless an accum parameter overrides it, which the heading then says,
-- as the command's does.
statementPage :: AppRoute -> Text -> CompoundBalanceCommandSpec -> Handler Html
statementPage here tabtitle spec = do
  checkServerSideUiEnabled
  VD{j, q, qopts, qparam, opts, today} <- getViewData
  require ViewPermission
  mperiod <- lookupGetParam "period"
  maccum <- lookupGetParam "accum"
  hideEmpty <- hideEmptyAccounts
  urlrender <- getUrlRenderParams
  let filtered = if q /= Any then ", filtered" else "" :: Text
      rspecOrig = reportspec_ $ cliopts_ opts
      roptsOrig = _rsReportOpts rspecOrig
      menu = reportLinkItems reportMenu

  defaultLayout $ do
    setTitle $ H.toHtml tabtitle
    case reportParams today rspecOrig qparam q qopts hideEmpty mperiod maccum of
      Left err -> Yesod.toWidget $ do
        H.h2 $ H.toHtml $ effectiveTitle roptsOrig (T.pack $ cbctitle spec) <> filtered
        paramError err
      Right ReportParams{rpRopts, rpRspec, rpSpan, rpInterval, rpPeriod, rpAccum} -> do
        let accum = fromMaybe (cbcaccum spec) rpAccum
            override = mfilter (/= cbcaccum spec) rpAccum
            ropts = rpRopts{balanceaccum_ = accum}
            rspec = rpRspec{_rsReportOpts = ropts}
            cbr0 =
              styleAmounts (journalCommodityStylesWith HardRounding j) $
                compoundBalanceReport rspec j (cbcqueries spec)
            cbr =
              applySubreportTitles ropts $
                cbr0{cbrTitle = effectiveTitle ropts $ compoundBalanceReportTitle spec rpRopts override cbr0}
            colspans = cbrDates cbr
            -- What links staying on this page keep: the period as given, and
            -- the mode when it is not the report's own.
            periodParams = [("period", p) | Just p <- [rpPeriod]]
            accumParams = [("accum", if accum == Historical then "historical" else "change") | isJust override]
            -- Links to the other reports keep the search, minus any account
            -- term, which the reports ignore, and the period as given.
            menuParams = periodParams ++ [("q", qt) | let qt = T.unwords $ removeInacct qparam, not (T.null qt)]
            -- A column heading opens this report for that column's period,
            -- in place of any date terms in the search, which the column
            -- narrows anyway.
            headinglink spn = urlrender here $
              ("period", showDateSpanForQuery spn) :
              [("q", qt) | let qt = T.unwords $ removeDates qparam, not (T.null qt)] ++
              accumParams
            CompoundBalanceReportParts{cbrpLeadingHeaders, cbrpDataHeaders, cbrpSections, cbrpNetRows} =
              compoundBalanceReportAsSpreadsheetParts oneLineNoCostFmt "account" ropts (cbcqueries spec) cbr
            -- The heading row with the classes the stylesheet aligns the
            -- columns by, and this page's column headings and links.
            withClass c cell = cell{Spr.cellClass = Spr.Class c}
            header =
              map (withClass "account") cbrpLeadingHeaders ++
              relinkDateHeaders (columnHeading ropts colspans) headinglink colspans (map (withClass "amount") cbrpDataHeaders)
            sections = [(mfilter (not . T.null) (Just title), body, subtotals) | (title, body, subtotals) <- cbrpSections]
            noRows = all (\(_, r, _) -> null $ prRows r) . cbrSubreports
            empty = noRows cbr
            -- An empty report with zero balances hidden may have them all: look again showing them.
            zerosHidden = hideEmpty && not (noRows $ compoundBalanceReport rspec{_rsReportOpts = ropts{empty_ = True}} j (cbcqueries spec))
        Yesod.toWidget $ H.h2 $ H.toHtml $ cbrTitle cbr <> filtered
        Yesod.toWidget $ reportLinks here menuParams menu
        Yesod.toWidget $ intervalLinks here accumParams qparam rpSpan rpInterval
        if empty
          then Yesod.toWidget $ emptyNotice zerosHidden (q == Any && rpSpan == nulldatespan)
          else Yesod.toWidget $ reportTable [header] sections cbrpNetRows

-- | What an empty statement shows instead of a table: that its accounts
-- all have zero balances, which are hidden; or, for the whole journal,
-- that it has no accounts of the types the report shows, with a pointer
-- to how types are found; or, for a search or a period, that nothing
-- matched.
emptyNotice :: Bool -> Bool -> HtmlUrl AppRoute
emptyNotice zerosHidden whole render =
  H.div ! A.class_ "alert alert-info" $
    if zerosHidden then "All the accounts this report shows have zero balances, which are hidden. Press e to show them."
    else if whole
      then do
        "No accounts of the types this report shows were found. Declare account types, or use hledger's standard top-level account names. "
        helplink "account-types" "How hledger finds account types" render
      else "Nothing matches this search in this period."
