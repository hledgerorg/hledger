-- | /register handlers.

{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE QuasiQuotes         #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TupleSections       #-}

module Hledger.Web.Handler.RegisterR where

import Data.Aeson.Text (encodeToLazyText)
import Data.List (nub, partition)
import Data.Text qualified as T
import Safe (tailSafe)
import Text.Hamlet (hamletFile)

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Web.Import
import Hledger.Web.WebOptions
import Hledger.Web.Widget.AddForm (addModal)
import Hledger.Web.Widget.Common
             (accountQuery, accountOnlyQuery, mixedAmountAsHtml,
              transactionFragment, removeDates, removeInacct, replaceInacct, journalDayQuery)

-- | The main journal/account register view, with accounts sidebar.
getRegisterR :: Handler Html
getRegisterR = do
  checkServerSideUiEnabled
  VD{perms, j, q, opts, qparam, qopts, today} <- getViewData
  require ViewPermission
  -- With accum=historical the running balance is the account's balance,
  -- starting from before the query's start date, rather than a total of
  -- the transactions shown; a report's ending balance links here that way,
  -- so that the balance ends on the figure clicked.
  historical <- (== Just "historical") <$> lookupGetParam "accum"

  let (a,inclsubs) = fromMaybe ("all accounts",True) $ inAccount qopts
      s1 = if inclsubs then "" else " (excluding subaccounts)"
      s2 = if q /= Any then ", filtered" else ""
      header = a <> s1 <> s2

  let rspec0 = reportspec_ (cliopts_ opts)
      ropts = (_rsReportOpts rspec0){balanceaccum_ = if historical then Historical else PerPeriod}
      rspec = rspec0{_rsReportOpts = ropts}
      -- links staying on this register keep its mode
      accumParams = [("accum", "historical") | historical]
      qParams t = [("q", t) | not (T.null t)]
      acctQuery = fromMaybe Any (inAccountQuery qopts)
      acctlink acc = (RegisterR, ("q", replaceInacct qparam $ accountQuery acc) : accumParams)
      -- In an account's register a type: term selects the postings
      -- totaled, not the accounts named beside them: a liability's
      -- register names the accounts it was posted against, whatever their
      -- types. A register of all accounts of a type names those accounts.
      otherTransAccounts =
          map (\(acct,(name,comma)) -> (acct, (T.pack name, T.pack comma))) .
          undecorateLinks . elideRightDecorated 40 . decorateLinks .
          addCommas . preferReal . otherTransactionAccounts j displayq acctQuery
      displayq = if isJust (inAccount qopts) then filterQuery (not . queryIsType) q else q
      addCommas xs =
          zip xs $
          zip (map (T.unpack . accountSummarisedName . paccount) xs) $
          tailSafe (", "<$xs) ++ [""]
      styles = journalCommodityStylesWith HardRounding j
      (startbal, items) =
        bimap (styleAmounts styles) (styleAmounts styles) $
        accountTransactionsReportWithStart rspec{_rsQuery=q} j acctQuery
      balancelabel
        | historical               = "Historical Total"
        | isJust (inAccount qopts) = "Period Total"
        | otherwise                = "Total"
      -- The balance column's heading switches the mode.
      accumToggle = (RegisterR, qParams qparam ++ [("accum", "historical") | not historical])
      accumToggleTitle
        | historical = "Show the running balance from the start of this period" :: Text
        | otherwise  = "Show the running balance including everything before this period"
      -- In historical mode with a start date, the balance brought forward
      -- from before it is the oldest row, linking to the transactions
      -- before the period: those before the start date by the kind of
      -- date (primary or secondary) the report took it from, as the
      -- report chooses the balance's cutoff.
      mstart = asum [ (,) secondary <$> queryStartDate secondary q
                    | secondary <- [date2_ ropts, not $ date2_ ropts] ]
      broughtForwardLink (secondary, start) =
        (RegisterR, [("q", T.unwords $
          maybe [] (\(acc, incl) -> [if incl then accountQuery acc else accountOnlyQuery acc]) (inAccount qopts) ++
          [(if secondary then "date2:.." else "date:..") <> showDate start] ++
          removeDates (T.unwords $ removeInacct qparam))])
      transactionFrag = transactionFragment j
  defaultLayout $ do
    setTitle "register - hledger-web"
    $(widgetFile "register")

-- cf. Hledger.Reports.AccountTransactionsReport.accountTransactionsReportItems
otherTransactionAccounts :: Journal -> Query -> Query -> Transaction -> [Posting]
otherTransactionAccounts j reportq thisacctq torig
    -- no current account ? summarise all matched postings
    | thisacctq == None  = reportps
    -- only postings to current account ? summarise those
    | null otheraccts    = thisacctps
    -- summarise matched postings to other account(s)
    | otherwise          = otheracctps
    where
      -- given the account types, so that a type: term matches postings here as in the report
      reportps = tpostings $ filterTransactionPostingsExtra (journalAccountType j) reportq torig
      (thisacctps, otheracctps) = partition (matchesPosting thisacctq) reportps
      otheraccts = nub $ map paccount otheracctps

-- cf. Hledger.Reports.AccountTransactionsReport.summarisePostingAccounts
preferReal :: [Posting] -> [Posting]
preferReal ps
    | null realps = ps
    | otherwise   = realps
    where realps = filter isReal ps

elideRightDecorated :: Int -> [(Maybe d, Char)] -> [(Maybe d, Char)]
elideRightDecorated width s =
    if length s > width
        then take (width - 2) s ++ map (Nothing,) ".."
        else s

undecorateLinks :: [(Maybe acct, char)] -> [(acct, ([char], [char]))]
undecorateLinks [] = []
undecorateLinks xs0@(x:_) =
    case x of
        (Just acct, _) ->
            let (link, xs1) = span (isJust . fst) xs0
                (comma, xs2) = span (isNothing . fst) xs1
            in (acct, (map snd link, map snd comma)) : undecorateLinks xs2
        _ -> error' "link name not decorated with account"  -- PARTIAL:

decorateLinks :: [(acct, ([char], [char]))] -> [(Maybe acct, char)]
decorateLinks = concatMap $ \(acct, (name, comma)) ->
    map (Just acct,) name ++ map (Nothing,) comma

-- | The register balance chart: its markup, carrying the per-commodity
-- series as JSON in a data attribute. hledger.js draws it with flot on page
-- load; see registerChartInit there.
registerChartHtml ::
  Text -> [(Text, Text)] -> (Transaction -> String) -> String ->
  [(CommoditySymbol, [AccountTransactionsReportItem])] -> HtmlUrl AppRoute
registerChartHtml q accumParams transactionFrag title percommoditytxnreports = $(hamletFile "templates/chart.hamlet")
 where
   charttitle = if null title then "" else title ++ ":"
   nodatelink = (RegisterR, [("q", t) | let t = T.unwords $ removeDates q, not (T.null t)] ++ accumParams)
   -- One entry per commodity: its symbol, and per transaction the point flot
   -- plots followed by the texts the tooltip and click handler show.
   seriesjson = encodeToLazyText $ map commoditySeries percommoditytxnreports
   commoditySeries (c, items) = object
     [ "label"  .= c
     , "points" .= [ [ toJSON . dayToUtcNoonTimestamp $ triDate i
                     , toJSON . quantityAsDouble $ triCommodityBalance c i
                     , toJSON . showZeroCommodity $ triCommodityAmount c i
                     , toJSON . showZeroCommodity $ triCommodityBalance c i
                     , toJSON . T.stripEnd . showTransaction $ triOrigTransaction i
                     , toJSON . transactionFrag $ triOrigTransaction i
                     ]
                   | i <- reverse items ]
     ]
   -- The first amount's quantity, or 0. (Decimal's own ToJSON instance is an
   -- object; the chart wants a plain number.)
   quantityAsDouble :: MixedAmount -> Double
   quantityAsDouble = maybe 0 (realToFrac . aquantity) . listToMaybe . amounts . mixedAmountStripCosts
   showZeroCommodity = wbUnpack . showMixedAmountB oneLineNoCostFmt{displayCost=False,displayZeroCommodity=True}

-- | Makes a unix timestamp (milliseconds since epoch) corresponding to noon on the given date in UTC.
dayToUtcNoonTimestamp :: Day -> Integer
dayToUtcNoonTimestamp d =
  read (formatTime defaultTimeLocale "%s" t) * 1000 -- XXX read
  where
    t = UTCTime d (secondsToDiffTime $ 12 * 60 * 60)
