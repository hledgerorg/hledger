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
             (accountQuery, mixedAmountAsHtml,
              transactionFragment, removeDates, removeInacct, replaceInacct)

-- | The main journal/account register view, with accounts sidebar.
getRegisterR :: Handler Html
getRegisterR = do
  checkServerSideUiEnabled
  VD{perms, j, q, opts, qparam, qopts, today} <- getViewData
  require ViewPermission

  let (a,inclsubs) = fromMaybe ("all accounts",True) $ inAccount qopts
      s1 = if inclsubs then "" else " (excluding subaccounts)"
      s2 = if q /= Any then ", filtered" else ""
      header = a <> s1 <> s2

  let rspec = reportspec_ (cliopts_ opts)
      acctQuery = fromMaybe Any (inAccountQuery qopts)
      acctlink acc = (RegisterR, [("q", replaceInacct qparam $ accountQuery acc)])
      otherTransAccounts =
          map (\(acct,(name,comma)) -> (acct, (T.pack name, T.pack comma))) .
          undecorateLinks . elideRightDecorated 40 . decorateLinks .
          addCommas . preferReal . otherTransactionAccounts q acctQuery
      addCommas xs =
          zip xs $
          zip (map (T.unpack . accountSummarisedName . paccount) xs) $
          tailSafe (", "<$xs) ++ [""]
      items =
        styleAmounts (journalCommodityStylesWith HardRounding j) $
        accountTransactionsReport rspec{_rsQuery=q} j acctQuery
      balancelabel
        | isJust (inAccount qopts), balanceaccum_ (_rsReportOpts rspec) == Historical = "Historical Total"
        | isJust (inAccount qopts) = "Period Total"
        | otherwise                = "Total"
      transactionFrag = transactionFragment j
  defaultLayout $ do
    setTitle "register - hledger-web"
    $(widgetFile "register")

-- cf. Hledger.Reports.AccountTransactionsReport.accountTransactionsReportItems
otherTransactionAccounts :: Query -> Query -> Transaction -> [Posting]
otherTransactionAccounts reportq thisacctq torig
    -- no current account ? summarise all matched postings
    | thisacctq == None  = reportps
    -- only postings to current account ? summarise those
    | null otheraccts    = thisacctps
    -- summarise matched postings to other account(s)
    | otherwise          = otheracctps
    where
      reportps = tpostings $ filterTransactionPostings reportq torig
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
registerChartHtml :: Text -> String -> [(CommoditySymbol, [AccountTransactionsReportItem])] -> HtmlUrl AppRoute
registerChartHtml q title percommoditytxnreports = $(hamletFile "templates/chart.hamlet")
 where
   charttitle = if null title then "" else title ++ ":"
   nodatelink = (RegisterR, [("q", T.unwords $ removeDates q)])
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
                     , toJSON . tindex $ triOrigTransaction i
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
