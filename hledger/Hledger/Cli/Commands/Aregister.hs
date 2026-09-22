{-|

The @aregister@ command lists a single account's transactions,
like the account register in hledger-ui and hledger-web,
and unlike the register command which lists postings across multiple accounts.

-}

{-# LANGUAGE CPP #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Aregister (
  aregistermode
 ,aregister
 -- ,showPostingWithBalanceForVty
 ,tests_Aregister
) where

import Data.Default (def)
import Data.List (find, nub)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Foldable (for_)
import Data.Map qualified as Map
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Builder qualified as TB
import Control.Monad (unless, when)
import Safe (readMay)
import System.Console.CmdArgs.Explicit (flagNone, flagReq)
import System.IO qualified as IO
import Text.Blaze.Html5 ((!), preEscapedToHtml)
import Text.Blaze.Html5 qualified as H
import Text.Blaze.Html5.Attributes qualified as A
import Text.Tabular.AsciiWide hiding (render)

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Utils
import Hledger.Write.Csv (CSV, printCSV, printTSV)
import Hledger.Write.Html (formatRow, formatTitle, htmlAsLazyText, nl, toHtml)
import Hledger.Write.Html.Attribute (tableStylesheet)
import Hledger.Write.Ods (printFods)
import Hledger.Write.Spreadsheet qualified as Spr

aregistermode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Aregister.txt")
  ([
   flagNone ["txn-dates"] (setboolopt "txn-dates") 
     "filter strictly by transaction date, not posting date. Warning: this can show a wrong running balance."
  ,flagNone ["no-elide"] (setboolopt "no-elide") "don't show only 2 commodities per amount"
  ,flagNone ["cumulative"] (setboolopt "cumulative")
     (accumprefix ++ "show running total from report start date")
  ,flagNone ["historical","H"] (setboolopt "historical")
     (accumprefix ++ "show historical running total/balance (includes postings before report start date) (default)")
  -- ,flagNone ["average","A"] (setboolopt "average")
  --    "show running average of posting amounts instead of total (implies --empty)"
  ,flagNone ["related","r"] (setboolopt "related") "show the other accounts in each transaction (default)"
  ,flagNone ["matched"] (setboolopt "matched") "show the matched accounts (this account or its subaccounts) instead"
  ,flagNone ["invert"] (setboolopt "invert") "display all amounts with reversed sign"
  ,flagReq  ["drop"] (\s opts -> Right $ setopt "drop" s opts) "N" "omit N leading account name parts"
  ,flagReq  ["heading"] (\s opts -> Right $ setopt "heading" s opts) "YN"
     "show heading row above table: yes (default) or no"
  ,flagReq  ["width","w"] (\s opts -> Right $ setopt "width" s opts) "N"
     ("set output width (default: " ++
#ifdef mingw32_HOST_OS
      show defaultWidth
#else
      "terminal width"
#endif
      ++ "). -wN,M sets description width as well."
     )
  ,flagNone ["align-all"] (setboolopt "align-all") "guarantee alignment across all lines (slower)"
  ,outputFormatFlag ["txt","html","csv","tsv","json"]
  ,outputFileFlag
  ])
  cligeneralflagsgroups1
  hiddenflags
  ([], Just $ argsFlag "ACCTPAT [QUERY]")
  where
    accumprefix = "accumulation mode: "

-- based on Hledger.UI.RegisterScreen:

-- | Print an account register report for a specified account.
aregister :: CliOpts -> Journal -> IO ()
aregister opts@CliOpts{rawopts_=rawopts,reportspec_=rspec} j = do
  -- the first argument specifies the account, any remaining arguments are a filter query
  let help = "aregister needs an ACCTPAT argument to select an account"
  (apat,querystr) <- case listofstringopt "args" rawopts of
      []     -> error' $ help <> ".\nPlease provide an account name or a (case-insensitive, infix, regexp) pattern."
      (a:as) -> return (a, map T.pack as)
  let
    -- keep synced with findMatchedByArgument's matching
    acct = fromMaybe (error' $ help <> ", but " ++ show apat++" did not match any account.")   -- PARTIAL:
           . firstMatch $ journalAccountNamesDeclaredOrImplied j
    firstMatch = case toRegexCI $ T.pack apat of
        Right re -> find (regexMatchText re)
        Left  _  -> const Nothing
    -- gather report options
    inclusive = True  -- tree_ ropts
    thisacctq = Acct $ (if inclusive then accountNameToAccountRegex else accountNameToAccountOnlyRegex) acct
    ropts' = (_rsReportOpts rspec) {
        -- ignore any depth limit, as in postingsReport; allows register's total to match balance reports (cf #1468)
        depth_=DepthSpec Nothing []
      , balanceaccum_ =
          case balanceaccum_ $ _rsReportOpts rspec of
            PerPeriod -> Historical
            ba -> ba
      , querystring_ = querystr
      }
    wd = whichDate ropts'
  -- and regenerate the ReportSpec, making sure to use the above
  rspec' <- either fail return $ updateReportSpec ropts' rspec
  let
    -- run the report
    -- TODO: need to also pass the queries so we can choose which date to render - move them into the report ?
    items = accountTransactionsReport rspec' j thisacctq
    items' =
      styleAmounts (journalCommodityStylesWith HardRounding j) $
      (if empty_ ropts' then id else filter (not . mixedAmountLooksZero . fifth6)) $
      reverse items
    -- select renderer
    render | fmt=="txt"  = accountTransactionsReportAsText opts (_rsQuery rspec') thisacctq
           | fmt=="html" = accountTransactionsReportAsHTML opts (_rsQuery rspec') thisacctq
           | fmt=="csv"  = printCSV . accountTransactionsReportAsCsv opts hd wd (_rsQuery rspec') thisacctq
           | fmt=="tsv"  = printTSV . accountTransactionsReportAsCsv opts hd wd (_rsQuery rspec') thisacctq
           | fmt=="fods" =
                printFods IO.localeEncoding . Map.singleton "Aregister" .
                (,) (1,0) .
                accountTransactionsReportAsSpreadsheet opts oneLineNoCostFmt hd wd (_rsQuery rspec') thisacctq
           | fmt=="json" = toJsonText
           | otherwise   = error' $ unsupportedOutputFormatError fmt  -- PARTIAL:
      where
        hd = headingopt opts
        fmt = outputFormatFromOpts opts

  writeOutputLazyText opts $ render items'

accountTransactionsReportAsCsv ::
  CliOpts -> Bool -> WhichDate -> Query -> Query -> AccountTransactionsReport -> CSV
accountTransactionsReportAsCsv opts hd wd reportq thisacctq atr =
  case accountTransactionsReportAsSpreadsheet opts machineFmt hd wd reportq thisacctq atr of
    []                    -> []
    rows@(headerrow : _) -> Spr.rawTableContent $ titleRows headerrow ++ rows
  where
    titleText = effectiveTitle (_rsReportOpts $ reportspec_ opts) ""
    titleRows headerrow
      | T.null titleText = []
      | otherwise        = [Spr.horizontalSpan headerrow (Spr.headerCell titleText)]

accountTransactionsReportAsSpreadsheet ::
  CliOpts -> AmountFormat -> Bool ->
  WhichDate -> Query -> Query -> AccountTransactionsReport ->
  [[Spr.Cell Spr.NumLines Text]]
accountTransactionsReportAsSpreadsheet opts fmt hd wd reportq thisacctq is =
  optional hd
    [Spr.addHeaderBorders $ map Spr.headerCell $
      ["txnidx","date","code","description","otheraccounts","amount","balance"]]
  ++
  map (accountTransactionsReportItemAsRecord opts fmt True wd reportq thisacctq) is

accountTransactionsReportItemAsRecord ::
  CliOpts -> AmountFormat -> Bool ->
  WhichDate -> Query -> Query -> AccountTransactionsReportItem ->
  [Spr.Cell Spr.NumLines Text]
accountTransactionsReportItemAsRecord
  opts fmt internals wd reportq thisacctq
  item@(t@Transaction{tindex,tcode,tdescription}, _, _issplit, _, change, balance)
  = (optional internals [Spr.integerCell tindex]) ++
    date :
    (optional internals [cell tcode]) ++
    [cell tdescription,
     cell $ T.intercalate ", " $ map dropAcct $ itemAccountNames opts thisacctq item,
     amountCell change,
     amountCell balance]
  where
    dropAcct = accountNameDrop (fromMaybe 0 $ readMay =<< maybestringopt "drop" (rawopts_ opts))
    cell = Spr.defaultCell
    date =
        (Spr.defaultCell $ showDate $
         transactionRegisterDate wd reportq thisacctq t)
            {Spr.cellType = Spr.TypeDate}
    amountCell amt =
      wbToText <$> Spr.cellFromMixedAmount fmt (Spr.Class "amount", amt)

-- | Render a register report as a HTML snippet.
accountTransactionsReportAsHTML :: CliOpts -> Query -> Query -> AccountTransactionsReport -> TL.Text
accountTransactionsReportAsHTML copts reportq thisacctq items =
  (<>"\n") $ htmlAsLazyText $ do
    -- the builtin styles, then the optional user stylesheet so it can override them
    H.style $ preEscapedToHtml tableStylesheet
    nl
    H.link ! A.rel "stylesheet" ! A.href "hledger.css"
    nl
    let title = accountTransactionsReportTitle copts reportq thisacctq
    unless (T.null title) $ formatTitle title
    H.table $ do
      nl
      when (headingopt copts) $ do
        H.thead $ H.tr $ do
          H.th "date"
          H.th "description"
          H.th "otheraccounts"
          H.th "amount"
          H.th "balance"
        nl
      H.tbody $ for_ items $
        formatRow . map (fmap toHtml) .
        accountTransactionsReportItemAsRecord copts
          oneLineNoCostFmt False
          (whichDate $ _rsReportOpts $ reportspec_ copts)
          reportq thisacctq

-- | Render a register report as plain text suitable for console output.
accountTransactionsReportAsText :: CliOpts -> Query -> Query -> AccountTransactionsReport -> TL.Text
accountTransactionsReportAsText copts reportq thisacctq items = TB.toLazyText $
    titleBuilder
    <>
    postingsOrTransactionsReportAsText alignAll copts itemAsText itemamt itembal items
  where
    alignAll = boolopt "align-all" $ rawopts_ copts
    itemAsText = accountTransactionsReportItemAsText copts reportq thisacctq
    itemamt (_,_,_,_,a,_) = a
    itembal (_,_,_,_,_,a) = a

    title = accountTransactionsReportTitle copts reportq thisacctq
    titleBuilder | T.null title = mempty
                 | otherwise    = TB.fromText title <> TB.singleton '\n'

-- | The heading for an account transactions report: a description of the
-- account shown, or --title's value if that was provided (possibly empty).
-- Also empty when --heading=no.
accountTransactionsReportTitle :: CliOpts -> Query -> Query -> Text
accountTransactionsReportTitle copts reportq thisacctq
  | not (headingopt copts) = ""
  | otherwise = effectiveTitle (_rsReportOpts $ reportspec_ copts) defaultTitle
  where
    -- show a heading indicating which account was picked, which can be confusing otherwise
    defaultTitle = maybe "" (\s -> T.concat ["Transactions in ", s, " and subaccounts", qmsg, ":"]) macct
      where
        -- XXX temporary hack ? recover the account name from the query
        macct = case filterQuery queryIsAcct thisacctq of
                  Acct r -> Just . T.drop 1 . T.dropEnd 5 $ reString r  -- Acct "^JS:expenses(:|$)"
                  _      -> Nothing  -- shouldn't happen
        -- show a hint in the title when results are restricted by an extra query (other than depth or date or date2)
        qmsg = if hasextraquery then " (matching query)" else ""
          where
            hasextraquery =
              length (querystring_ $ _rsReportOpts $ reportspec_ copts) > 1
              && not (queryIsNull $ filterQuery (not.(\q->queryIsDepth q || queryIsDateOrDate2 q)) reportq)

headingopt :: CliOpts -> Bool
headingopt = fromMaybe True . maybeynopt "heading" . rawopts_

-- | Should the account column show the matched accounts (--matched) rather than
-- the other accounts in each transaction (-r/--related, the default) ?
-- The last of these flags wins.
matchedopt :: CliOpts -> Bool
matchedopt = fromMaybe False . choiceopt parse . rawopts_
  where parse s = lookup s [("matched", True), ("related", False)]

-- | The account names to show for an account register report item:
-- by default, the other accounts involved in the transaction;
-- with --matched, the accounts matched by the account query
-- (this account or its subaccounts), among the postings selected by any extra query.
itemAccountNames :: CliOpts -> Query -> AccountTransactionsReportItem -> [AccountName]
itemAccountNames opts thisacctq (_, tacct, _, otheraccts, _, _)
  | matchedopt opts = nub . map paccount . filter (matchesPosting thisacctq) $ tpostings tacct
  | otherwise       = nub otheraccts

optional :: (Monoid p) => Bool -> p -> p
optional b x = if b then x else mempty


-- | Render one account register report line item as plain text. Layout is like so:
-- @
-- <---------------- width (specified, terminal width, or 80) -------------------->
-- date (10)  description           other accounts       amount (12)   balance (12)
-- DDDDDDDDDD dddddddddddddddddddd  aaaaaaaaaaaaaaaaaaa  AAAAAAAAAAAA  AAAAAAAAAAAA
-- @
-- If description's width is specified, account will use the remaining space.
-- Otherwise, description and account divide up the space equally.
--
-- Returns a string which can be multi-line, eg if the running balance
-- has multiple commodities.
--
accountTransactionsReportItemAsText :: CliOpts -> Query -> Query -> Int -> Int
                                    -> (AccountTransactionsReportItem, [WideBuilder], [WideBuilder])
                                    -> TB.Builder
accountTransactionsReportItemAsText
  copts@CliOpts{reportspec_=ReportSpec{_rsReportOpts=ropts}}
  reportq thisacctq preferredamtwidth preferredbalwidth
  (item@(t@Transaction{tdescription}, _, _issplit, _, _, _), amt, bal) =
    -- Transaction -- the transaction, unmodified
    -- Transaction -- the transaction, as seen from the current account
    -- Bool        -- is this a split (more than one posting to other accounts) ?
    -- [AccountName] -- the other account(s), if any
    -- MixedAmount -- the amount posted to the current account(s) (or total amount posted)
    -- MixedAmount -- the register's running total or the current account(s)'s historical balance, after this transaction
    table <> TB.singleton '\n'
  where
    dropAcct = accountNameDrop (fromMaybe 0 $ readMay =<< maybestringopt "drop" (rawopts_ copts))
    table = renderRowB def{tableBorders=False, borderSpaces=False} . Group NoLine $ map Header
      [ textCell TopLeft $ fitText (Just datewidth) (Just datewidth) True True date
      , spacerCell
      , textCell TopLeft $ fitText (Just descwidth) (Just descwidth) True True tdescription
      , spacerCell2
      , textCell TopLeft $ fitText (Just acctwidth) (Just acctwidth) True True accts
      , spacerCell2
      , Cell TopRight $ map (pad amtwidth) amt
      , spacerCell2
      , Cell BottomRight $ map (pad balwidth) bal
      ]
    spacerCell  = Cell BottomLeft [WideBuilder (TB.singleton ' ') 1]
    spacerCell2 = Cell BottomLeft [WideBuilder (TB.fromString "  ") 2]
    pad fullwidth amt1 = WideBuilder (TB.fromText $ T.replicate w " ") w <> amt1
      where w = fullwidth - wbWidth amt1
    -- calculate widths
    (totalwidth,mdescwidth) = registerWidthsFromOpts copts
    (datewidth, date) = (10, showDate $ transactionRegisterDate wd reportq thisacctq t)
      where wd = whichDate ropts
    (amtwidth, balwidth)
      | shortfall <= 0 = (preferredamtwidth, preferredbalwidth)
      | otherwise      = (adjustedamtwidth, adjustedbalwidth)
      where
        mincolwidth = 2 -- columns always show at least an ellipsis
        maxamtswidth = max 0 (totalwidth - (datewidth + 1 + mincolwidth + 2 + mincolwidth + 2 + 2))
        shortfall = (preferredamtwidth + preferredbalwidth) - maxamtswidth
        amtwidthproportion = fromIntegral preferredamtwidth `divideSafe` fromIntegral (preferredamtwidth + preferredbalwidth)
        adjustedamtwidth = round $ amtwidthproportion * fromIntegral maxamtswidth
        adjustedbalwidth = maxamtswidth - adjustedamtwidth

    remaining = totalwidth - (datewidth + 1 + 2 + amtwidth + 2 + balwidth)
    (descwidth, acctwidth) = (w, remaining - 2 - w)
      where w = fromMaybe ((remaining - 2) `div` 2) mdescwidth

    accts = T.intercalate ", " . map (dropAcct . accountSummarisedName) $ itemAccountNames copts thisacctq item

-- tests

tests_Aregister = testGroup "Aregister" [

 ]
