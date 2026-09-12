{-|

A ledger-compatible @balance@ command, with additional support for
multi-column reports.

Here is a description/specification for the balance command.  See also
"Hledger.Reports" -> \"Balance reports\".


/Basic balance report/

With no report interval (@--monthly@ etc.), hledger's balance
command emulates ledger's, showing accounts indented according to
hierarchy, along with their total amount posted (including subaccounts).

Here's an example. With @examples/sample.journal@, which defines the following account tree:

@
 assets
   bank
     checking
     saving
   cash
 expenses
   food
   supplies
 income
   gifts
   salary
 liabilities
   debts
@

the basic @balance@ command gives this output:

@
 $ hledger -f sample.journal balance
                 $-1  assets
                  $1    bank:saving
                 $-2    cash
                  $2  expenses
                  $1    food
                  $1    supplies
                 $-2  income
                 $-1    gifts
                 $-1    salary
                  $1  liabilities:debts
--------------------
                   0
@

Subaccounts are displayed indented below their parent. Only the account leaf name (the final part) is shown.
(With @--flat@, account names are shown in full and unindented.)

Each account's \"balance\" is the sum of postings in that account and any subaccounts during the report period.
When the report period includes all transactions, this is equivalent to the account's current balance.

The overall total of the highest-level displayed accounts is shown below the line.
(The @--no-total/-N@ flag prevents this.)

/Eliding and omitting/

Accounts which have a zero balance, and no non-zero subaccount
balances, are normally omitted from the report.
(The @--empty/-E@ flag forces such accounts to be displayed.)
Eg, above @checking@ is omitted because it has a zero balance and no subaccounts.

Accounts which have a single subaccount also being displayed, with the same balance,
are normally elided into the subaccount's line.
(The @--no-elide@ flag prevents this.)
Eg, above @bank@ is elided to @bank:saving@ because it has only a
single displayed subaccount (@saving@) and their balance is the same
($1). Similarly, @liabilities@ is elided to @liabilities:debts@.

/Date limiting/

The default report period is that of the whole journal, including all
known transactions. The @--begin\/-b@, @--end\/-e@, @--period\/-p@
options or @date:@/@date2:@ patterns can be used to report only
on transactions before and/or after specified dates.

/Depth limiting/

The @--depth@ option can be used to limit the depth of the balance report.
Eg, to see just the top level accounts (still including their subaccount balances):

@
$ hledger -f sample.journal balance --depth 1
                 $-1  assets
                  $2  expenses
                 $-2  income
                  $1  liabilities
--------------------
                   0
@

/Account limiting/

With one or more account pattern arguments, the report is restricted
to accounts whose name matches one of the patterns, plus their parents
and subaccounts. Eg, adding the pattern @o@ to the first example gives:

@
 $ hledger -f sample.journal balance o
                  $1  expenses:food
                 $-2  income
                 $-1    gifts
                 $-1    salary
--------------------
                 $-1
@

* The @o@ pattern matched @food@ and @income@, so they are shown.

* @food@'s parent (@expenses@) is shown even though the pattern didn't
  match it, to clarify the hierarchy. The usual eliding rules cause it to be elided here.

* @income@'s subaccounts are also shown.

/Multi-column balance report/

hledger's balance command will show multiple columns when a reporting
interval is specified (eg with @--monthly@), one column for each sub-period.

There are three accumulation strategies for multi-column balance report, indicated by
the heading:

* A \"period balance\" (or \"flow\") report (with @--change@, the default) shows the
  change of account balance in each period, which is equivalent to the sum of postings
  in each period. Here, checking's balance increased by 10 in Feb:

  > Change of balance (flow):
  >
  >                  Jan   Feb   Mar
  > assets:checking   20    10    -5

* A \"cumulative balance\" report (with @--cumulative@) shows the accumulated ending balance
  across periods, starting from zero at the report's start date.
  Here, 30 is the sum of checking postings during Jan and Feb:

  > Ending balance (cumulative):
  >
  >                  Jan   Feb   Mar
  > assets:checking   20    30    25

* A \"historical balance\" report (with @--historical/-H@) also shows ending balances,
  but it includes the starting balance from any postings before the report start date.
  Here, 130 is the balance from all checking postings at the end of Feb, including
  pre-Jan postings which created a starting balance of 100:

  > Ending balance (historical):
  >
  >                  Jan   Feb   Mar
  > assets:checking  120   130   125

/Eliding and omitting, 2/

Here's a (imperfect?) specification for the eliding/omitting behaviour:

* Each account is normally displayed on its own line.

* An account less deep than the report's max depth, with just one
interesting subaccount, and the same balance as the subaccount, is
non-interesting, and prefixed to the subaccount's line, unless
@--no-elide@ is in effect.

* An account with a zero inclusive balance and less than two interesting
subaccounts is not displayed at all, unless @--empty@ is in effect.

* Multi-column balance reports show full account names with no eliding
  (like @--flat@). Accounts (and periods) are omitted as described below.

/Which accounts to show in balance reports/

By default:

* single-column: accounts with non-zero balance in report period.
                 (With @--flat@: accounts with non-zero balance and postings.)

* change:        accounts with postings and non-zero period balance in any period

* cumulative:    accounts with non-zero cumulative balance in any period

* historical:    accounts with non-zero historical balance in any period

With @-E/--empty@:

* single-column: accounts with postings in report period

* change:        accounts with postings in report period

* cumulative:    accounts with postings in report period

* historical:    accounts with non-zero starting balance +
                 accounts with postings in report period

/Which periods (columns) to show in balance reports/

An empty period/column is one where no report account has any postings.
A zero period/column is one where no report account has a non-zero period balance.

Currently,

by default:

* single-column: N/A

* change:        all periods within the overall report period,
                 except for leading and trailing empty periods

* cumulative:    all periods within the overall report period,
                 except for leading and trailing empty periods

* historical:    all periods within the overall report period,
                 except for leading and trailing empty periods

With @-E/--empty@:

* single-column: N/A

* change:        all periods within the overall report period

* cumulative:    all periods within the overall report period

* historical:    all periods within the overall report period

/What to show in empty cells/

An empty periodic balance report cell is one which has no corresponding postings.
An empty cumulative/historical balance report cell is one which has no corresponding
or prior postings, ie the account doesn't exist yet.
Currently, empty cells show 0.

-}

{-# LANGUAGE CPP                  #-}
{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE NamedFieldPuns       #-}
{-# LANGUAGE RecordWildCards      #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TemplateHaskell      #-}

module Hledger.Cli.Commands.Balance (
  -- ** balance command
  balancemode
 ,balance
  -- ** balance output rendering
 ,balanceReportAsText
 ,balanceReportAsCsv
 ,balanceReportAsHtml
 ,balanceReportAsSpreadsheet
 ,balanceReportItemAsText
 ,budgetReportAsText
 ,budgetReportAsCsv
 ,budgetReportAsHtml
 ,budgetReportAsSpreadsheet
 ,multiBalanceRowAsCellBuilders
 ,multiBalanceRowAsCsvText
 ,multiBalanceRowAsText
 ,multiBalanceReportAsText
 ,multiBalanceReportAsCsv
 ,multiBalanceReportAsHtml
 ,multiBalanceReportAsTable
 ,multiBalanceReportAsPartTable
 ,multiBalanceReportTableAsText
 ,multiBalanceReportAsSpreadsheet
 ,multiBalanceReportAsSpreadsheetParts
 ,multiBalanceHasTotalsColumn
 ,setBareWideCommodityOrder
 ,renderPeriodicAcct
 ,addTotalBorders
 ,simpleDateSpanCell
 ,tidyColumnLabels
 ,nbsp
 ,RowClass(..)
  -- ** Tests
 ,tests_Balance
) where

import Control.Arrow (second, (***))
import Control.Monad (guard)
import Data.Decimal (roundTo)
import Data.Default (def)
import Data.Function (on)
import Data.Foldable qualified as Fold
import Data.List.NonEmpty qualified as NonEmpty
import Data.List.NonEmpty (NonEmpty((:|)))
import Data.List (find, transpose)
#if !MIN_VERSION_base(4,20,0)
import Data.List (foldl')
#endif
import Data.Map qualified as Map
import Data.Set qualified as S
import Data.Maybe (mapMaybe, fromMaybe, maybeToList)
import Data.Tuple (swap)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Builder qualified as TB
import Data.Time (addDays, fromGregorian)
import System.Console.CmdArgs.Explicit as C (flagNone, flagReq, flagOpt)
import Safe (headMay, maximumMay)
import Text.Tabular.AsciiWide
    (Header(..), Align(..), Properties(..), Cell(..), Table(..), TableOpts(..),
    cellWidth, concatTables, renderColumns, renderRowB, renderTable, renderTableByRowsB, textCell)

import System.IO qualified as IO

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Utils
import Hledger.Cli.Anchor (setAccountAnchor, dateSpanCell, headerDateSpanCell, renderPeriodHeading)
import Hledger.Write.Csv (CSV, printCSV, printTSV)
import Hledger.Write.Ods (printFods)
import Hledger.Write.Html (Html, titledTableHtml, htmlAsLazyText, toHtml)
import Hledger.Write.Spreadsheet (rawTableContent, headerCell,
            addHeaderBorders, addRowSpanHeader, addRowSpanHeaderNE,
            cellFromMixedAmount, cellsFromMixedAmount, cellFromAmount)
import Hledger.Write.Spreadsheet qualified as Ods


-- | Command line options for this command.
balancemode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Balance.txt")
  (
    -- https://hledger.org/dev/hledger.html#calculation-mode :
    [flagNone ["sum"] (setboolopt "sum")
      (calcprefix ++ "show sum of posting amounts (default)")
    ,flagNone ["valuechange"] (setboolopt "valuechange")
      (calcprefix ++ "show total change of value of period-end historical balances (caused by deposits, withdrawals, market price fluctuations)")
    ,flagNone ["gain"] (setboolopt "gain")
      (calcprefix ++ "show capital gain/loss (historical balance value minus the net of postings' transacted costs; equals unrealised gain if nothing has been disposed of)")
    -- XXX --budget[=DESCPAT], --forecast[=PERIODEXP], could be more consistent
    ,flagOpt "" ["budget"] (\s opts -> Right $ setopt "budget" s opts) "DESCPAT"
      (unlines
      [ calcprefix ++ "show sum of posting amounts together with budget goals defined by periodic"
      , "transactions. With a DESCPAT argument (must be separated by = not space),"
      , "use only periodic transactions with matching description"
      , "(case insensitive substring match)."
      ])
    ,flagNone ["count"] (setboolopt "count")
      (calcprefix ++ "show the count of postings")

    -- https://hledger.org/dev/hledger.html#accumulation-mode :
    ,flagNone ["change"] (setboolopt "change")
      (accumprefix ++ "accumulate amounts from column start to column end (in multicolumn reports, default)")
    ,flagNone ["cumulative"] (setboolopt "cumulative")
      (accumprefix ++ "accumulate amounts from report start (specified by e.g. -b/--begin) to column end")
    ,flagNone ["historical","H"] (setboolopt "historical")
      (accumprefix ++ "accumulate amounts from journal start to column end (includes postings before report start date)")
    ]

    -- other options specific to this command:
    ++ flattreeflags True ++
    [flagReq  ["drop"] (\s opts -> Right $ setopt "drop" s opts) "N" "in list mode, omit N leading account name parts"
    ,flagNone ["declared"] (setboolopt "declared") "include non-parent declared accounts (best used with -E)"
    ,flagNone ["average","A"] (setboolopt "average") "show a row average column (in multicolumn reports)"
    ,flagNone ["row-total","T"] (setboolopt "row-total") "show a row total column (in multicolumn reports)"
    ,flagNone ["summary-only"] (setboolopt "summary-only") "display only row summaries (e.g. row total, average) (in multicolumn reports)"
    ,flagNone ["no-total","N"] (setboolopt "no-total") "omit the final total row"
    ,flagNone ["no-elide"] (setboolopt "no-elide") "in tree mode, don't squash boring parent accounts; in list mode, also show parent accounts (usually zero, hidden without -E)"
    ,flagNone ["full-names"] (setboolopt "full-names") "in tree mode, show full account names instead of indented leaf names"
    ,flagReq  ["format"] (\s opts -> Right $ setopt "format" s opts) "FORMATSTR" "use this custom line format (in simple reports)"
    ,flagNone ["sort-amount","S"] (setboolopt "sort-amount") "sort by amount instead of account code/name (in flat mode). With multiple columns, sorts by the row total, or by row average if that is displayed."
    ,flagNone ["percent", "%"] (setboolopt "percent") "express values in percentage of each column's total"
    ,flagNone ["related","r"] (setboolopt "related") "show the other accounts transacted with, instead"
    ,flagNone ["invert"] (setboolopt "invert") "display all amounts with reversed sign"
    ,flagNone ["transpose"] (setboolopt "transpose") "switch rows and columns (use vertical time axis); repeat to cancel"
    ,flagReq  ["layout"] (\s opts -> Right $ setopt "layout" s opts) "ARG"
      (unlines
        ["how to lay out multi-commodity amounts and the overall table:"
        ,"'wide[,W]': commodities on same line, up to W wide"
        ,"'tall'    : commodities on separate lines"
        ,"'bare'    : commodity symbols in a separate column"
        ,"'tidy'    : each data field in its own column"
        ])
     ,flagReq  ["base-url"] (\s opts -> Right $ setopt "base-url" s opts) "URLPREFIX" "in html output, generate links to hledger-web, with this prefix. (Usually the base url shown by hledger-web; can also be relative.)"

    -- output:
    ,outputFormatFlag ["txt","html","csv","tsv","json","fods"]
    ,outputFileFlag

    ]
  )
  cligeneralflagsgroups1
  (hiddenflags ++
    [ flagNone ["commodity-column"] (setboolopt "commodity-column")
      "show commodity symbols in a separate column, amounts as bare numbers, one row per commodity"
    ])
  ([], Just $ argsFlag "[QUERY]")

  where
    calcprefix = "calculation mode: "
    accumprefix = "accumulation mode: "

-- | The balance command, prints a balance report.
balance :: CliOpts -> Journal -> IO ()
balance opts@CliOpts{reportspec_=rspec} j = case balancecalc_ ropts of
    CalcBudget -> do  -- single or multi period budget report
      let rspan = fst $ reportSpan j rspec
          budgetreport = styleAmounts styles $ budgetReport rspec (balancingopts_ $ inputopts_ opts) rspan j
          render = case fmt of
            "txt"  -> budgetReportAsText ropts
            "json" -> (<>"\n") . toJsonText
            "csv"  -> printCSV . budgetReportAsCsv ropts
            "tsv"  -> printTSV . budgetReportAsCsv ropts
            "html" -> (<>"\n") . htmlAsLazyText . budgetReportAsHtml ropts
            "fods" -> printFods IO.localeEncoding .
                      Map.singleton "Budget Report" . budgetReportAsSpreadsheet oneLineNoCostFmt ropts
            _      -> error' $ unsupportedOutputFormatError fmt
      writeOutputLazyText opts $ render budgetreport

    _ | multiperiod -> do  -- multi period balance report
        let report = styleAmounts styles $ multiBalanceReport rspec j
            render = case fmt of
              "txt"  -> multiBalanceReportAsText ropts
              "csv"  -> printCSV . multiBalanceReportAsCsv ropts
              "tsv"  -> printTSV . multiBalanceReportAsCsv ropts
              "html" -> (<>"\n") . htmlAsLazyText . multiBalanceReportAsHtml ropts
              "json" -> (<>"\n") . toJsonText
              "fods" -> printFods IO.localeEncoding .
                        Map.singleton "Multi-period Balance Report" . multiBalanceReportAsSpreadsheet ropts
              _      -> const $ error' $ unsupportedOutputFormatError fmt  -- PARTIAL:
        writeOutputLazyText opts $ render report

    _ -> do  -- single period simple balance report
        let report = styleAmounts styles $ balanceReport rspec j -- simple Ledger-style balance report
            render = case fmt of
              "txt"  -> withTitle ropts . balanceReportAsText ropts
              "csv"  -> printCSV . balanceReportAsCsv ropts
              "tsv"  -> printTSV . balanceReportAsCsv ropts
              "html" -> (<>"\n") . htmlAsLazyText . balanceReportAsHtml ropts
              "json" -> (<>"\n") . toJsonText
              "fods" -> printFods IO.localeEncoding . Map.singleton "Balance Report" . (,) (1,0) . balanceReportAsSpreadsheet oneLineNoCostFmt ropts
              _      -> error' $ unsupportedOutputFormatError fmt  -- PARTIAL:
        writeOutputLazyText opts $ render report
  where
    styles = journalCommodityStylesWith HardRounding j
    ropts =
        let ropts0 = _rsReportOpts rspec in
        ropts0 {
            -- tidy csv is defined externally and must not include totals or averages
            no_total_ = no_total_ ropts0 || layout_ ropts0 == LayoutTidy
        }
    -- Tidy csv/tsv should be consistent between single period and multiperiod reports.
    multiperiod = interval_ ropts /= NoInterval || (layout_ ropts == LayoutTidy && delimited)
    delimited   = fmt == "csv" || fmt == "tsv"
    fmt         = outputFormatFromOpts opts

-- Rendering

data RowClass = Value | Total
    deriving (Eq, Ord, Enum, Bounded, Show)

amountClass :: RowClass -> Ods.Class
amountClass rc =
    Ods.Class $
    case rc of Value -> "amount"; Total -> "amount coltotal"

budgetClass :: RowClass -> Ods.Class
budgetClass rc =
    Ods.Class $
    case rc of Value -> "budget"; Total -> "budget coltotal"

rowTotalClass :: RowClass -> Ods.Class
rowTotalClass rc =
    Ods.Class $
    case rc of Value -> "amount rowtotal"; Total -> "amount coltotal"

rowAverageClass :: RowClass -> Ods.Class
rowAverageClass rc =
    Ods.Class $
    case rc of Value -> "amount rowaverage"; Total -> "amount colaverage"

budgetTotalClass :: RowClass -> Ods.Class
budgetTotalClass rc =
    Ods.Class $
    case rc of Value -> "budget rowtotal"; Total -> "budget coltotal"

budgetAverageClass :: RowClass -> Ods.Class
budgetAverageClass rc =
    Ods.Class $
    case rc of Value -> "budget rowaverage"; Total -> "budget colaverage"

-- What to show as heading for the totals row in balance reports ?
-- Currently nothing in terminal, Total: in HTML, FODS and xSV output.
totalRowHeadingText        = ""
totalRowHeadingSpreadsheet = "Total:"
totalRowHeadingBudgetText  = ""
totalRowHeadingBudgetCsv   = "Total:"

-- Single-column balance reports

-- | Render a single-column balance report as CSV.
balanceReportAsCsv :: ReportOpts -> BalanceReport -> CSV
balanceReportAsCsv opts =
    rawTableContent . balanceReportAsSpreadsheet machineFmt opts

-- | Render a single-column balance report as plain text.
balanceReportAsText :: ReportOpts -> BalanceReport -> TL.Text
balanceReportAsText originalopts report@((items, total)) =
  case layout_ originalopts of
    LayoutBare | iscustom -> error' "Custom format not supported with commodity columns"  -- PARTIAL:
    LayoutBare ->
      TB.toLazyText $ bareLayoutBalanceReportAsText originalopts report
    LayoutBareWide -> bareWideLayoutBalanceReportAsText originalopts report
    _ ->
      TB.toLazyText $
      unlinesB ls <> unlinesB (if no_total_ opts then [] else [overline, totalLines])
  where
    opts = widenDefaultBalanceLineFormat originalopts report
    (ls, sizes) = unzip $ map (balanceReportItemAsText opts) items
    -- abuse renderBalanceReportItem to render the total with similar format
    (totalLines, _totalSizes) = renderBalanceReportItem opts ("",0,total)
    -- with a custom format, extend the line to the full report width;
    -- otherwise show the amount column's width.
    iscustom = case format_ originalopts of
        OneLine       ((FormatField _ _ _ TotalField):_) -> False
        TopAligned    ((FormatField _ _ _ TotalField):_) -> False
        BottomAligned ((FormatField _ _ _ TotalField):_) -> False
        _ -> True
    isdefault = format_ originalopts == defaultBalanceLineFormat
    overlinewidth
      | iscustom  = sum (map maximum' $ transpose sizes)
      | isdefault = defaultBalanceAmountColumnWidth originalopts report
      | otherwise = 20
    overline   = TB.fromText $ T.replicate overlinewidth "-"

-- | The default balance format historically used a 20-character amount
-- column. Keep that as the minimum, but widen it when any rendered amount
-- needs more room.
widenDefaultBalanceLineFormat :: ReportOpts -> BalanceReport -> ReportOpts
widenDefaultBalanceLineFormat opts report
  | format_ opts == defaultBalanceLineFormat = opts{format_ = setTotalMinWidth amountwidth defaultBalanceLineFormat}
  | otherwise = opts
  where
    amountwidth = defaultBalanceAmountColumnWidth opts report
    setTotalMinWidth w (BottomAligned (FormatField l _ m TotalField : rest)) =
      BottomAligned (FormatField l (Just w) m TotalField : rest)
    setTotalMinWidth _ fmt = fmt

defaultBalanceAmountColumnWidth :: ReportOpts -> BalanceReport -> Int
defaultBalanceAmountColumnWidth opts ((items, total)) =
    maximum' $ 20 : map renderedAmountWidth visibleAmounts
  where
    visibleAmounts =
      map (\(_,_,_,amt) -> amt) items ++
      [total | not (no_total_ opts)]
    renderedAmountWidth =
      wbWidth . showMixedAmountB noCostFmt
        { displayCommodity = layout_ opts /= LayoutBare
        , displayMinWidth = Just 0
        , displayColour = False
        }

-- | Render a single-column balance report as plain text with a separate commodity column (--layout=bare)
bareLayoutBalanceReportAsText :: ReportOpts -> BalanceReport -> TB.Builder
bareLayoutBalanceReportAsText opts (items, total) =
  unlinesB .
  map
    (renderColumns def{tableBorders=singleColumnTableOuterBorder} sizes .
     Group singleColumnTableInterColumnBorder . map Header) $
  ls ++ concat [[[overline], totalline] | not (no_total_ opts)]
  where
    render (_, acctname, dep, amt) =
        [ Cell TopRight damts
        , Cell TopLeft (fmap wbFromText cs)
        , Cell TopLeft (replicate (length damts - 1) mempty ++ [wbFromText dispname]) ]
      where dopts = oneLineNoCostFmt{displayCommodity=layout_ opts /= LayoutBare, displayCommodityOrder=Just cs, displayColour=color_ opts}
            cs    = if mixedAmountLooksZero amt then [""] else S.toList $ maCommodities amt
            dispname = T.replicate ((dep - 1) * 2) " " <> acctname
            damts = showMixedAmountLinesB dopts amt
    ls = fmap render items
    totalline = render ("", "", 0, total)
    sizes = fromMaybe 0 . maximumMay . map cellWidth <$>
        transpose ([totalline | not (no_total_ opts)] ++ ls)
    overline = Cell TopLeft . pure . wbFromText . flip T.replicate "-" . fromMaybe 0 $ headMay sizes
    singleColumnTableOuterBorder       = pretty_ opts
    singleColumnTableInterColumnBorder = if pretty_ opts then SingleLine else NoLine

-- | Render a single-column balance report as plain text with a separate commodity column (--layout=barewide)
bareWideLayoutBalanceReportAsText :: ReportOpts -> BalanceReport -> TL.Text
bareWideLayoutBalanceReportAsText opts br =
  renderTable tableopts (textCell TopLeft) (textCell TopLeft) (textCell TopRight) $
  Table
    (if null totalheadings
        then Group NoLine rowheadings
        else Group SingleLine $ map (Group NoLine) [rowheadings, totalheadings])
    (Group NoLine $ map (Header . Ods.cellContent) $ NonEmpty.tail header)
    (rows++totaldata)
  where
    tableopts = def{tableBorders=singleColumnTableOuterBorder, prettyTable=pretty_ opts}
    (header, body, totals) = balanceReportAsSpreadsheetParts fmt opts br
    fmt = oneLineNoCostFmt{displayColour=color_ opts}
    separateHeaders =
        unzip . map (\(hd:|tl) -> (Header hd, tl)) . rawTableContent
    (rowheadings,rows) = separateHeaders body
    (totalheadings,totaldata) = separateHeaders totals
    singleColumnTableOuterBorder = pretty_ opts

{-
This implementation turned out to be a bit convoluted but implements the following algorithm for formatting:

- If there is a single amount, print it with the account name directly:
- Otherwise, only print the account name on the last line.

    a         USD 1   ; Account 'a' has a single amount
              EUR -1
    b         USD -1  ; Account 'b' has two amounts. The account name is printed on the last line.
-}
-- | Render one balance report line item as plain text suitable for console output (or
-- whatever string format is specified). Note, prices will not be rendered, and
-- differently-priced quantities of the same commodity will appear merged.
-- The output will be one or more lines depending on the format and number of commodities.
balanceReportItemAsText :: ReportOpts -> BalanceReportItem -> (TB.Builder, [Int])
balanceReportItemAsText opts (fullName, displayName, dep, amt)
  | accountlistmode_ opts == ALTree && full_names_ opts =
      renderBalanceReportItem opts (accountNameDrop (drop_ opts) fullName, 0, amt)
  | otherwise =
      renderBalanceReportItem opts (displayName, dep, amt)

-- | Render a balance report item, using the StringFormat specified by --format.
--
renderBalanceReportItem :: ReportOpts -> (AccountName, Int, MixedAmount) -> (TB.Builder, [Int])
renderBalanceReportItem opts (acctname, dep, total) =
  case format_ opts of
      OneLine       comps -> renderRowFromComponents $ renderComponents True  True  comps
      TopAligned    comps -> renderRowFromComponents $ renderComponents True  False comps
      BottomAligned comps -> renderRowFromComponents $ renderComponents False False comps

  where
    -- Combine the rendered component cells horizontally, as a possibly multi-line text (builder),
    -- aligned in borderless columns (? XXX). Also returns the rendered width of each cell.
    renderRowFromComponents :: [Cell] -> (TB.Builder, [Int])
    renderRowFromComponents cs =
      ( renderRowB def{tableBorders=False, borderSpaces=False} . Group NoLine $ map Header cs
      , map cellWidth cs
      )

    -- Render each of the given StringFormat components for the balance report item,
    -- returning each as a Cell.
    renderComponents :: Bool -> Bool -> [StringFormatComponent] -> [Cell]
    renderComponents topaligned oneline = map (renderComponent topaligned oneline opts (acctname, dep, total))

-- Render one StringFormat component for a balance report item.
-- Returns a Cell, containing 0 or more lines of text (as builders).
renderComponent :: Bool -> Bool -> ReportOpts -> (AccountName, Int, MixedAmount) -> StringFormatComponent -> Cell
renderComponent _ _ _ _ (FormatLiteral s) = textCell TopLeft s
renderComponent topaligned oneline opts (acctname, dep, total) (FormatField ljust mmin mmax field) = case field of
    DepthSpacerField -> Cell align [WideBuilder (TB.fromText $ T.replicate d " ") d]
                        where d = maybe id min mmax $ dep * fromMaybe 1 mmin
    AccountField     -> textCell align $ formatText ljust mmin mmax acctname
    TotalField       -> Cell align . pure $ showMixedAmountB dopts total
    _                -> Cell align [mempty]
  where
    align | topaligned && ljust = TopLeft
          | topaligned          = TopRight
          | ljust               = BottomLeft
          | otherwise           = BottomRight
    dopts = noCostFmt{displayCommodity = layout_ opts /= LayoutBare
                  ,displayOneLine   = oneline
                  ,displayMinWidth  = mmin
                  ,displayMaxWidth  = mmax
                  ,displayColour    = color_ opts
                  }


headerWithoutBorders :: [Ods.Cell () text] -> [Ods.Cell Ods.NumLines text]
headerWithoutBorders = map (\c -> c {Ods.cellBorder = Ods.noBorder})

simpleDateSpanCell :: PeriodTitles -> DateSpan -> Ods.Cell Ods.NumLines Text
simpleDateSpanCell ph = Ods.defaultCell . renderPeriodHeading ph

addTotalBorders ::
    (Functor f) =>
    [f (Ods.Cell border text)] -> [f (Ods.Cell Ods.NumLines text)]
addTotalBorders =
    zipWith
        (\border ->
            fmap (\c -> c {
                    Ods.cellStyle = Ods.Body Ods.Total,
                    Ods.cellBorder = Ods.noBorder {Ods.borderTop = border}}))
        (Ods.DoubleLine : repeat Ods.NoLine)


-- | Render a single-column balance report as HTML.
-- This report has no default heading, so one is shown only with --title.
balanceReportAsHtml :: ReportOpts -> BalanceReport -> Html
balanceReportAsHtml ropts br =
  titledTableHtml (effectiveTitle ropts "") . map (map (fmap toHtml)) $
    balanceReportAsSpreadsheet oneLineNoCostFmt ropts br

-- | Render a single-column balance report as FODS.
balanceReportAsSpreadsheet ::
    AmountFormat -> ReportOpts -> BalanceReport -> [[Ods.Cell Ods.NumLines Text]]
balanceReportAsSpreadsheet fmt opts mbr =
    (if transpose_ opts then Ods.transpose else id) $
    map Fold.toList $ header : body ++ totals
    where (header, body, totals) =
            balanceReportAsSpreadsheetParts fmt opts mbr

-- | Render the ODS table rows for a BalanceReport.
-- Returns the heading row, 0 or more body rows, and the totals row if enabled.
balanceReportAsSpreadsheetParts ::
    AmountFormat -> ReportOpts -> BalanceReport ->
    (NonEmpty (Ods.Cell Ods.NumLines Text),
     [NonEmpty (Ods.Cell Ods.NumLines Text)],
     [NonEmpty (Ods.Cell Ods.NumLines Text)])
balanceReportAsSpreadsheetParts fmt opts (items, total) =
    (headers,
     concatMap (rows Value) items,
      if no_total_ opts
        then []
        else addTotalBorders $
          rows Total (totalRowHeadingSpreadsheet, totalRowHeadingSpreadsheet, 0, total))
  where
    cell = Ods.defaultCell
    headers =
      addHeaderBorders $ fmap headerCell $
      "account" :| case layout_ opts of
        LayoutBareWide -> allCommodities
        LayoutBare -> ["commodity", "balance"]
        _          -> ["balance"]
    allCommodities =
        S.toAscList $ foldMap (\(_,_,_,ma) -> maCommodities ma) items
    rows ::
        RowClass -> BalanceReportItem ->
        [NonEmpty (Ods.Cell Ods.NumLines Text)]
    rows rc (name, dispName, dep, ma) =
      let accountCell =
              setAccountAnchor
                  (guard (rc==Value) >> balance_base_url_ opts)
                  (querystring_ opts) name $
              cell $ case rc of
                Total -> dispName  -- show the total row heading as is; --drop etc. don't apply (#2688)
                Value -> renderBalanceAcct opts nbsp (name, dispName, dep) in
      addRowSpanHeaderNE accountCell $
      case layout_ opts of
      LayoutBareWide ->
          let bopts =
                machineFmt {
                    displayCommodity = False,
                    displayCommodityOrder = Just allCommodities
                } in
          [map (\bldAmt ->
                fmap wbToText $ cellFromAmount bopts (amountClass rc, bldAmt)) $
              showMixedAmountLinesPartsB bopts ma]
      LayoutBare ->
          map (\a -> [cell $ acommodity a, renderAmount rc $ mixedAmount a])
          . amounts $ mixedAmountStripCosts ma
      _ -> [[renderAmount rc ma]]

    renderAmount rc mixedAmt =
        wbToText <$> cellFromMixedAmount bopts (amountClass rc, mixedAmt)
      where
        bopts = fmt{displayCommodity=showcomm, displayCommodityOrder = commorder}
        (showcomm, commorder)
          | layout_ opts == LayoutBare = (False, Just $ S.toList $ maCommodities mixedAmt)
          | otherwise                  = (True, Nothing)



-- Multi-column balance reports

-- | Render a multi-column balance report as CSV.
-- The CSV will always include the initial headings row,
-- and will include the final totals row unless --no-total is set.
multiBalanceReportAsCsv :: ReportOpts -> MultiBalanceReport -> CSV
multiBalanceReportAsCsv opts@ReportOpts{..} report =
    (if transpose_ then transpose else id) $
    rawTableContent $ header ++ body ++ totals
  where
    allCommodities = allCommoditiesFromPeriodicReport $ prRows report
    (header, body, totals) =
        multiBalanceReportAsSpreadsheetParts
            (setBareWideCommodityOrder layout_ allCommodities machineFmt)
            opts report

-- | Render the Spreadsheet table rows (CSV, ODS, HTML) for a MultiBalanceReport.
-- Returns the heading row, 0 or more body rows, and the totals row if enabled.
multiBalanceReportAsSpreadsheetParts ::
    AmountFormat -> ReportOpts -> MultiBalanceReport ->
    ([[Ods.Cell Ods.NumLines Text]],
     [[Ods.Cell Ods.NumLines Text]],
     [[Ods.Cell Ods.NumLines Text]])
multiBalanceReportAsSpreadsheetParts fmt opts@ReportOpts{..}
  (PeriodicReport colspans items tr) =
    (allHeaders, concatMap fullRowAsTexts items, addTotalBorders totalrows)
  where
    allCommodities =
        fromMaybe (error "layout bare-wide must always be called with list of all commodities") $
        displayCommodityOrder fmt
    accountCell label =
        (Ods.defaultCell label) {Ods.cellClass = Ods.Class "account"}
    hCell cls label = (headerCell label) {Ods.cellClass = Ods.Class cls}
    allHeaders =
      case layout_ of
      LayoutBareWide ->
          [headerWithoutBorders $
              Ods.emptyCell :
              concatMap (Ods.horizontalSpan allCommodities) dateHeaders,
           headers]
      _ -> [headers]
    headers =
      addHeaderBorders $
      hCell "account" "account" :
      case layout_ of
      LayoutTidy -> map headerCell tidyColumnLabels
      LayoutBareWide -> dateHeaders >> map headerCell allCommodities
      LayoutBare -> headerCell "commodity" : dateHeaders
      _          -> dateHeaders
    dateHeaders =
      (if not summary_only_ then map (headerDateSpanCell period_titles_ balance_base_url_ querystring_) colspans  else [] )++
      [hCell "rowtotal" "total" | multiBalanceHasTotalsColumn opts] ++
      [hCell "rowaverage" "average" | average_]
    fullRowAsTexts row =
        addRowSpanHeader anchorCell $
        rowAsText Value (dateSpanCell period_titles_ balance_base_url_ querystring_ acctName) row
      where acctName = prrFullName row
            anchorCell =
              setAccountAnchor balance_base_url_ querystring_ acctName $
              accountCell $ renderPeriodicAcct opts nbsp row
    totalrows =
      if no_total_
        then []
        else addRowSpanHeader (accountCell totalRowHeadingSpreadsheet) $
                rowAsText Total (simpleDateSpanCell period_titles_) tr
    rowAsText rc dsCell =
        map (map (fmap wbToText)) .
        multiBalanceRowAsCellBuilders
            (setBareWideCommodityOrder layout_ allCommodities fmt)
            opts colspans rc dsCell

tidyColumnLabels :: [Text]
tidyColumnLabels =
    ["period", "start_date", "end_date", "commodity", "value"]


-- | Render a multi-column balance report as HTML.
multiBalanceReportAsHtml :: ReportOpts -> MultiBalanceReport -> Html
multiBalanceReportAsHtml ropts mbr =
  titledTableHtml (multiBalanceReportTitle ropts mbr) . map (map (fmap toHtml)) $
    snd $ multiBalanceReportAsSpreadsheet ropts mbr

-- | Render the ODS table rows for a MultiBalanceReport.
-- Returns the heading row, 0 or more body rows, and the totals row if enabled.
multiBalanceReportAsSpreadsheet ::
  ReportOpts -> MultiBalanceReport ->
  ((Int, Int), [[Ods.Cell Ods.NumLines Text]])
multiBalanceReportAsSpreadsheet ropts mbr =
  let allCommodities = allCommoditiesFromPeriodicReport $ prRows mbr
      (header,body,total) =
            multiBalanceReportAsSpreadsheetParts
                (setBareWideCommodityOrder (layout_ ropts) allCommodities oneLineNoCostFmt)
                ropts mbr
  in  (if transpose_ ropts then swap *** Ods.transpose else id) $
      ((case layout_ ropts of LayoutBareWide -> 2; _ -> 1,
        case layout_ ropts of LayoutWide _ -> 1; _ -> 0),
            header ++ body ++ total)


-- | Render a report title as a text block to prefix to a text report,
-- or nothing if the title is empty.
titleAsTextBuilder :: Text -> TB.Builder
titleAsTextBuilder title
  | T.null title = mempty
  | otherwise    = TB.fromText title <> TB.fromText "\n\n"

-- | Render a multi-column balance report as plain text suitable for console output.
multiBalanceReportAsText :: ReportOpts -> MultiBalanceReport -> TL.Text
multiBalanceReportAsText ropts r = TB.toLazyText $
    titleAsTextBuilder (multiBalanceReportTitle ropts r)
    <> multiBalanceReportTableAsText ropts (multiBalanceReportAsTable ropts r)

-- | The heading for a multi-column balance report: a description of the
-- report, or --title's value if that was provided (possibly empty).
multiBalanceReportTitle :: ReportOpts -> MultiBalanceReport -> Text
multiBalanceReportTitle ropts@ReportOpts{..} r = effectiveTitle ropts defaultTitle
  where
    defaultTitle = mtitle <> " in " <> showDateSpan (periodicReportSpan r) <> valuationdesc <> ":"

    mtitle = case (balancecalc_, balanceaccum_) of
        (CalcValueChange, PerPeriod  ) -> "Period-end value changes"
        (CalcValueChange, Cumulative ) -> "Cumulative period-end value changes"
        (CalcGain,        PerPeriod  ) -> "Incremental gain"
        (CalcGain,        Cumulative ) -> "Cumulative gain"
        (CalcGain,        Historical ) -> "Historical gain"
        (_,               PerPeriod  ) -> "Balance changes"
        (_,               Cumulative ) -> "Ending balances (cumulative)"
        (_,               Historical)  -> "Ending balances (historical)"
    valuationdesc =
        (case conversionop_ of
            Just ToCost -> ", converted to cost"
            _           -> "")
        <> (case value_ of
            Just (AtThen _mc)    -> ", valued at posting date"
            Just (AtEnd _mc) | changingValuation -> ""
            Just (AtEnd _mc)     -> ", valued at period ends"
            Just (AtNow _mc)     -> ", current value"
            Just (AtDate d _mc)  -> ", valued at " <> showDate d
            Nothing              -> "")

    changingValuation = case (balancecalc_, balanceaccum_) of
        (CalcValueChange, PerPeriod)  -> True
        (CalcValueChange, Cumulative) -> True
        _                                     -> False

-- | Given a table representing a multi-column balance report,
-- render it in a format suitable for console output.
-- Amounts with more than two commodities will be elided unless --no-elide is used.
multiBalanceReportTableAsText :: ReportOpts -> Table T.Text T.Text WideBuilder -> TB.Builder
multiBalanceReportTableAsText ReportOpts{..} = renderTableByRowsB tableopts renderCh renderRow
  where
    tableopts = def{tableBorders=multiColumnTableOuterBorder, prettyTable=pretty_}
    multiColumnTableOuterBorder = pretty_

    renderCh :: [Text] -> [Cell]
    renderCh
      | layout_ /= LayoutBare || transpose_ = fmap (textCell TopRight)
      | otherwise = zipWith ($) (textCell TopLeft : repeat (textCell TopRight))

    renderRow :: (Text, [WideBuilder]) -> (Cell, [Cell])
    renderRow (rh, row)
      | layout_ /= LayoutBare || transpose_ =
          (textCell TopLeft rh, fmap (Cell TopRight . pure) row)
      | otherwise =
          (textCell TopLeft rh, zipWith ($) (Cell TopLeft : repeat (Cell TopRight)) (fmap pure row))

-- | Build a 'Table' from a multi-column balance report.
multiBalanceReportAsTable :: ReportOpts -> MultiBalanceReport -> Table T.Text T.Text WideBuilder
multiBalanceReportAsTable opts report@(PeriodicReport _spans items _tr) =
    multiBalanceReportAsPartTable opts
        (allCommoditiesFromPeriodicReport items)
        report

multiBalanceReportAsPartTable ::
    ReportOpts -> [CommoditySymbol] -> MultiBalanceReport ->
    Table T.Text T.Text WideBuilder
multiBalanceReportAsPartTable
    opts@ReportOpts{summary_only_, average_, balanceaccum_}
    allCommodities
    (PeriodicReport spans items tr) =
   maybetranspose $
   addtotalrow $
   Table
     (Group multiColumnTableInterRowBorder    $ map Header $ concat accts)
     (Group multiColumnTableInterColumnBorder $ map Header colheadings)
     (concat rows)
  where
    colheadings =
      ["Commodity" | layout_ opts == LayoutBare]
      ++
      case layout_ opts of
          LayoutBareWide ->
              liftA2 (\s c -> T.concat [s, " (", c, ")"])
                  spanNames allCommodities
          _ -> spanNames
    spanNames =
        (guard (not summary_only_) >>
            map (reportPeriodName (period_titles_ opts) balanceaccum_ spans) spans)
        ++ ["  Total" | multiBalanceHasTotalsColumn opts]
        ++ ["Average" | average_]
    (accts, rows) = unzip $ fmap fullRowAsTexts items'
      where
        isLeaf rs row = not $ any (\r -> T.isPrefixOf (displayFull (prrName row) <> ":") (displayFull (prrName r))) rs
        items' = if transpose_ opts && tree_ opts
                 then filter (isLeaf items) items
                 else items
        fullRowAsTexts row = (replicate (length rs) (renderacct row), rs)
          where
            rs = multiBalanceRowAsText opts allCommodities row
            renderacct row' = renderPeriodicAcct opts " " row'
    addtotalrow
      | no_total_ opts = id
      | otherwise =
        let totalrows = multiBalanceRowAsText opts allCommodities tr
            rowhdrs = Group NoLine $ map Header $ totalRowHeadingText : replicate (length totalrows - 1) ""
            colhdrs = Header [] -- unused, concatTables will discard
        in (flip (concatTables SingleLine) $ Table rowhdrs colhdrs totalrows)
    maybetranspose | transpose_ opts = \(Table rh ch vals) -> Table ch rh (transpose vals)
                   | otherwise       = id
    multiColumnTableInterRowBorder    = NoLine
    multiColumnTableInterColumnBorder = if pretty_ opts then SingleLine else NoLine

allCommoditiesFromPeriodicReport ::
    [PeriodicReportRow a MixedAmount] -> [CommoditySymbol]
allCommoditiesFromPeriodicReport =
    S.toAscList . foldMap (foldMap maCommodities . prrAmounts)

multiBalanceRowAsCellBuilders ::
    AmountFormat -> ReportOpts -> [DateSpan] ->
    RowClass -> (DateSpan -> Ods.Cell Ods.NumLines Text) ->
    PeriodicReportRow a MixedAmount ->
    [[Ods.Cell Ods.NumLines WideBuilder]]
multiBalanceRowAsCellBuilders bopts ropts@ReportOpts{..} colspans
      rc renderDateSpanCell (PeriodicReportRow _acct as rowtot rowavg) =
    case layout_ of
      LayoutWide width -> [fmap (cellFromMixedAmount bopts{displayMaxWidth=width}) clsamts]
      LayoutTall       -> paddedTranspose Ods.emptyCell
                           . map (cellsFromMixedAmount bopts{displayMaxWidth=Nothing})
                           $ clsamts
      LayoutBare       -> zipWith (:) (map wbCell cs)  -- add symbols
                           . transpose                         -- each row becomes a list of Text quantities
                           . map (cellsFromMixedAmount (setDisplayCommodityBare cs bopts))
                           $ clsamts
      LayoutBareWide   -> [concatMap (cellsFromMixedAmount bopts)
                            $ clsamts]
      LayoutTidy       -> concat
                           . zipWith (map . addDateColumns) colspans
                           . map ( zipWith (\c a -> [wbCell c, a]) cs
                                  . cellsFromMixedAmount (setDisplayCommodityBare cs bopts))
                           $ classified
                                 -- Do not include totals column or average for tidy output, as this
                                 -- complicates the data representation and can be easily calculated
  where
    wbCell = Ods.defaultCell . wbFromText
    wbDate content = (wbCell content) {Ods.cellType = Ods.TypeDate}
    cs = if all mixedAmountLooksZero allamts then [""] else S.toList $ foldMap maCommodities allamts
    classified = map ((,) (amountClass rc)) as
    allamts = map snd clsamts
    clsamts = (if not summary_only_ then classified else []) ++
                [(rowTotalClass rc, rowtot) |
                    multiBalanceHasTotalsColumn ropts && not (null as)] ++
                [(rowAverageClass rc, rowavg) | average_ && not (null as)]
    addDateColumns spn@(DateSpan s e) remCols =
        (wbFromText <$> renderDateSpanCell spn) :
        wbDate (maybe "" showEFDate s) :
        wbDate (maybe "" (showEFDate . modifyEFDay (addDays (-1))) e) :
        remCols

    paddedTranspose :: a -> [[a]] -> [[a]]
    paddedTranspose _ [] = [[]]
    paddedTranspose n as1 = take (maximum . map length $ as1) . trans $ as1
        where
          trans ([] : xss)  = (n : map h xss) :  trans ([n] : map t xss)
          trans ((x : xs) : xss) = (x : map h xss) : trans (m xs : map t xss)
          trans [] = []
          h (x:_) = x
          h [] = n
          t (_:xs) = xs
          t [] = [n]
          m (x:xs) = x:xs
          m [] = [n]


multiBalanceHasTotalsColumn :: ReportOpts -> Bool
multiBalanceHasTotalsColumn ropts =
    row_total_ ropts && balanceaccum_ ropts `notElem` [Cumulative, Historical]

multiBalanceRowAsText ::
    ReportOpts -> [CommoditySymbol] -> PeriodicReportRow a MixedAmount -> [[WideBuilder]]
multiBalanceRowAsText opts allCommodities =
    rawTableContent .
    multiBalanceRowAsCellBuilders
        (setBareWideCommodityOrder (layout_ opts) allCommodities
            oneLineNoCostFmt{displayColour=color_ opts})
        opts []
        Value (simpleDateSpanCell $ period_titles_ opts)

multiBalanceRowAsCsvText ::
    ReportOpts -> [DateSpan] ->
    PeriodicReportRow a MixedAmount -> [[T.Text]]
multiBalanceRowAsCsvText opts colspans =
    map (map (wbToText . Ods.cellContent)) .
    multiBalanceRowAsCellBuilders machineFmt opts colspans
        Value (simpleDateSpanCell $ period_titles_ opts)


-- Budget reports

-- A BudgetCell's data values rendered for display - the actual change amount,
-- the budget goal amount if any, and the corresponding goal percentage if possible.
type BudgetDisplayCell = (WideBuilder, Maybe (WideBuilder, Maybe WideBuilder))

-- | A row of rendered budget data cells.
type BudgetDisplayRow  = [BudgetDisplayCell]

-- | An amount render helper for the budget report. Renders each commodity separately.
type BudgetShowAmountsFn   = MixedAmount -> [WideBuilder]

-- | A goal percentage calculating helper for the budget report.
type BudgetCalcPercentagesFn  = Change -> BudgetGoal -> [Maybe Percentage]

-- | Render a budget report as plain text suitable for console output.
budgetReportAsText :: ReportOpts -> BudgetReport -> TL.Text
budgetReportAsText ropts budgetr = TB.toLazyText $
    titleAsTextBuilder (budgetReportTitle ropts budgetr) <>
      multiBalanceReportTableAsText ropts (budgetReportAsTable ropts budgetr)

-- | The heading for a budget report: a description of the report,
-- or --title's value if that was provided (possibly empty).
budgetReportTitle :: ReportOpts -> BudgetReport -> Text
budgetReportTitle ropts@ReportOpts{..} budgetr = effectiveTitle ropts defaultTitle
  where
    defaultTitle = "Budget performance in " <> showDateSpan (periodicReportSpan budgetr)
           <> (case conversionop_ of
                 Just ToCost -> ", converted to cost"
                 _           -> "")
           <> (case value_ of
                 Just (AtThen _mc)   -> ", valued at posting date"
                 Just (AtEnd _mc)    -> ", valued at period ends"
                 Just (AtNow _mc)    -> ", current value"
                 Just (AtDate d _mc) -> ", valued at " <> showDate d
                 Nothing             -> "")
           <> ":"

-- | Build a 'Table' from a multi-column balance report.
budgetReportAsTable :: ReportOpts -> BudgetReport -> Table Text Text WideBuilder
budgetReportAsTable ropts@ReportOpts{..} (PeriodicReport spans items totrow) =
  maybetransposetable $
  addtotalrow $
    Table
      (Group budgetTableInterRowBorder    $ map Header accts)
      (Group budgetTableInterColumnBorder $ map Header colheadings)
      rows
  where
    budgetTableInterRowBorder    = NoLine
    budgetTableInterColumnBorder = if pretty_ then SingleLine else NoLine

    maybetransposetable
      | transpose_ = \(Table rh ch vals) -> Table ch rh (transpose vals)
      | otherwise  = id

    addtotalrow
      | no_total_ = id
      | otherwise =
        let
          rowhdrs = Group NoLine $ map Header $ totalRowHeadingBudgetText : replicate (length totalrows - 1) ""
          colhdrs = Header [] -- ignored by concatTables
        in
          (flip (concatTables SingleLine) $ Table rowhdrs colhdrs totalrows)  -- XXX ?

    colheadings = ["Commodity" | layout_ == LayoutBare]
                  ++ (if not summary_only_ then map (reportPeriodName period_titles_ balanceaccum_ spans) spans else [])
                  ++ ["  Total" | row_total_]
                  ++ ["Average" | average_]

    (accts, rows, totalrows) =
      (accts'
      ,maybecommcol itemscs  $ showcells  texts
      ,maybecommcol totrowcs $ showtotrow totrowtexts)
      where
        -- If --layout=bare, prepend a commodities column.
        maybecommcol :: [WideBuilder] -> [[WideBuilder]] -> [[WideBuilder]]
        maybecommcol cs
          | layout_ == LayoutBare = zipWith (:) cs
          | otherwise             = id

        showcells, showtotrow :: [[BudgetDisplayCell]] -> [[WideBuilder]]
        (showcells, showtotrow) =
          (maybetranspose . map (zipWith showBudgetDisplayCell widths)       . maybetranspose
          ,maybetranspose . map (zipWith showBudgetDisplayCell totrowwidths) . maybetranspose)
          where
            -- | Combine a BudgetDisplayCell's rendered values into a "[PERCENT of GOAL]" rendering,
            -- respecting the given widths.
            showBudgetDisplayCell :: (Int, Int, Int) -> BudgetDisplayCell -> WideBuilder
            showBudgetDisplayCell (actualwidth, budgetwidth, percentwidth) (actual, mbudget) =
              flip WideBuilder (actualwidth + totalbudgetwidth) $
                toPadded actual <> maybe emptycell showBudgetGoalAndPercentage mbudget

              where
                toPadded (WideBuilder b w) = (TB.fromText . flip T.replicate " " $ actualwidth - w) <> b

                (totalpercentwidth, totalbudgetwidth) =
                  let totalpercentwidth' = if percentwidth == 0 then 0 else percentwidth + 5
                   in ( totalpercentwidth'
                      , if budgetwidth == 0 then 0 else budgetwidth + totalpercentwidth' + 3
                      )

                emptycell :: TB.Builder
                emptycell = TB.fromText $ T.replicate totalbudgetwidth " "

                showBudgetGoalAndPercentage :: (WideBuilder, Maybe WideBuilder) -> TB.Builder
                showBudgetGoalAndPercentage (goal, perc) =
                  let perct = case perc of
                        Nothing  -> T.replicate totalpercentwidth " "
                        Just pct -> T.replicate (percentwidth - wbWidth pct) " " <> wbToText pct <> "% of "
                   in TB.fromText $ " [" <> perct <> T.replicate (budgetwidth - wbWidth goal) " " <> wbToText goal <> "]"

            -- | Build a list of widths for each column.
            -- When --transpose is used, the totals row must be included in this list.
            widths :: [(Int, Int, Int)]
            widths = zip3 actualwidths budgetwidths percentwidths
              where
                actualwidths  = map (maximum' . map first3 ) $ cols
                budgetwidths  = map (maximum' . map second3) $ cols
                percentwidths = map (maximum' . map third3 ) $ cols
                catcolumnwidths = foldl' (zipWith (++)) $ repeat []
                cols = maybetranspose $ catcolumnwidths $ map (cellswidth . rowToBudgetCells) items ++ [cellswidth $ rowToBudgetCells totrow]

                cellswidth :: [BudgetCell] -> [[(Int, Int, Int)]]
                cellswidth row =
                  let cs = budgetCellsCommodities row
                      (showmixed, percbudget) = mkBudgetDisplayFns cs
                      disp = showcell showmixed percbudget
                      budgetpercwidth = wbWidth *** maybe 0 wbWidth
                      cellwidth (am, bm) = let (bw, pw) = maybe (0, 0) budgetpercwidth bm in (wbWidth am, bw, pw)
                   in map (map cellwidth . disp) row

            totrowwidths :: [(Int, Int, Int)]
            totrowwidths
              | transpose_ = drop (length texts) widths
              | otherwise = widths

            maybetranspose
              | transpose_ = transpose
              | otherwise  = id

        (accts', itemscs, texts) = unzip3 $ concat shownitems
          where
            shownitems :: [[(AccountName, WideBuilder, BudgetDisplayRow)]]
            shownitems =
              map (\i ->
                let
                  addacctcolumn = map (\(cs, cvals) -> (renderPeriodicAcct ropts " " i, cs, cvals))
                  isunbudgetedrow = displayFull (prrName i) == unbudgetedAccountName
                in addacctcolumn $ showrow isunbudgetedrow $ rowToBudgetCells i)
              items

        (totrowcs, totrowtexts)  = unzip  $ concat showntotrow
          where
            showntotrow :: [[(WideBuilder, BudgetDisplayRow)]]
            showntotrow = [showrow False $ rowToBudgetCells totrow]

        -- | Get the data cells from a row or totals row, maybe adding
        -- the row total and/or row average depending on options.
        rowToBudgetCells :: PeriodicReportRow a BudgetCell -> [BudgetCell]
        rowToBudgetCells (PeriodicReportRow _ as rowtot rowavg) =
            (if not summary_only_ then as else [])
            ++ [rowtot | row_total_ && not (null as)]
            ++ [rowavg | average_   && not (null as)]

        -- | Render a row's data cells as "BudgetDisplayCell"s, and a rendered list of commodity symbols.
        -- Also requires a flag indicating whether this is the special <unbudgeted> row.
        -- (The types make that hard to check here.)
        showrow :: Bool -> [BudgetCell] -> [(WideBuilder, BudgetDisplayRow)]
        showrow isunbudgetedrow cells =
          let
            cs = budgetCellsCommodities cells
            -- #2071 If there are no commodities - because there are no actual or goal amounts -
            -- the zipped list would be empty, causing this row not to be shown.
            -- But rows like this sometimes need to be shown to preserve the account tree structure.
            -- So, ensure 0 will be shown as actual amount(s).
            -- Unfortunately this disables boring parent eliding, as if --no-elide had been used.
            -- (Just turning on --no-elide higher up doesn't work right.)
            -- Note, no goal amount will be shown for these rows,
            -- whereas --no-elide is likely to show a goal amount aggregated from children.
            cs1 = if null cs && not isunbudgetedrow then [""] else cs
            (showmixed, percbudget) = mkBudgetDisplayFns cs1
          in
            zip (map wbFromText cs1) $
            transpose $
            map (showcell showmixed percbudget)
            cells

        budgetCellsCommodities :: [BudgetCell] -> [CommoditySymbol]
        budgetCellsCommodities = S.toList . foldl' S.union mempty . map budgetCellCommodities
          where
            budgetCellCommodities :: BudgetCell -> S.Set CommoditySymbol
            budgetCellCommodities (am, bm) = f am `S.union` f bm
              where f = maybe mempty maCommodities

        -- | Render a "BudgetCell"'s amounts as "BudgetDisplayCell"s (one per commodity).
        showcell :: BudgetShowAmountsFn -> BudgetCalcPercentagesFn -> BudgetCell -> BudgetDisplayRow
        showcell showCommodityAmounts calcCommodityPercentages (mactual, mbudget) =
          zip actualamts budgetinfos
          where
            actual = fromMaybe nullmixedamt mactual
            actualamts = showCommodityAmounts actual
            budgetinfos =
              case mbudget of
                Nothing   -> repeat Nothing
                Just goal -> map Just $ showGoalAmountsAndPercentages goal
                where
                  showGoalAmountsAndPercentages :: MixedAmount -> [(WideBuilder, Maybe WideBuilder)]
                  showGoalAmountsAndPercentages goal = zip amts mpcts
                    where
                      amts  = showCommodityAmounts goal
                      mpcts = map (showrounded <$>) $ calcCommodityPercentages actual goal
                        where showrounded = wbFromText . T.pack . show . roundTo 0

        -- | Make budget info display helpers that adapt to --layout=wide.
        mkBudgetDisplayFns :: [CommoditySymbol] -> (BudgetShowAmountsFn, BudgetCalcPercentagesFn)
        mkBudgetDisplayFns cs = case layout_ of
          LayoutWide width ->
               ( pure . showMixedAmountB oneLineNoCostFmt{displayMaxWidth=width, displayColour=color_}
               , \a -> pure . percentage a)
          _ -> ( showMixedAmountLinesB (setDisplayCommodityBare cs noCostFmt){displayCommodity=layout_/=LayoutBare, displayColour=color_}
               , \a b -> map (percentage' a b) cs)
          where
            -- | Calculate the percentage of actual change to budget goal to show, if any.
            -- If valuing at cost, both amounts are converted to cost before comparing.
            -- A percentage will not be shown if:
            --
            -- - actual or goal are not the same, single, commodity
            --
            -- - the goal is zero
            --
            percentage :: Change -> BudgetGoal -> Maybe Percentage
            percentage actual budget =
              case (costedAmounts actual, costedAmounts budget) of
                ([a], [b]) | (acommodity a == acommodity b || amountLooksZero a) && not (amountLooksZero b)
                    -> Just $ 100 * aquantity a / aquantity b
                _   -> Nothing
              where
                costedAmounts = case conversionop_ of
                    Just ToCost -> amounts . mixedAmountCost
                    _           -> amounts . mixedAmountStripCosts  -- strip any lingering cost info that would prevent unification

            -- | Like percentage, but accept multicommodity actual and budget amounts,
            -- and extract the specified commodity from both.
            percentage' :: Change -> BudgetGoal -> CommoditySymbol -> Maybe Percentage
            percentage' am bm c = case ((,) `on` find ((==) c . acommodity) . amounts) am bm of
                (Just a, Just b) -> percentage (mixedAmount a) (mixedAmount b)
                _                -> Nothing

-- XXX generalise this with multiBalanceReportAsCsv ?
-- | Render a budget report as CSV. Like multiBalanceReportAsCsv,
-- but includes alternating actual and budget amount columns.
budgetReportAsCsv :: ReportOpts -> BudgetReport -> [[Text]]
budgetReportAsCsv ropts report
  = rawTableContent $ snd $
    budgetReportAsSpreadsheet machineFmt ropts report

-- | Render a budget report as HTML.
budgetReportAsHtml :: ReportOpts -> BudgetReport -> Html
budgetReportAsHtml ropts budgetr =
  titledTableHtml (budgetReportTitle ropts budgetr) . map (map (fmap toHtml)) . snd $
    budgetReportAsSpreadsheet oneLineNoCostFmt ropts budgetr

budgetReportAsSpreadsheet ::
  AmountFormat -> ReportOpts -> BudgetReport ->
  ((Int,Int), [[Ods.Cell Ods.NumLines Text]])
budgetReportAsSpreadsheet
  fmt
  ropts@ReportOpts{..}
  (PeriodicReport colspans items totrow)
  = (if transpose_ then swap *** Ods.transpose else id) $
  ((length allHeaders, length leadingHeaders)
   ,
    -- heading row
    allHeaders ++

    -- account rows
    concatMap (\row -> rowAsTexts Value (accountCell row) row) items

    -- totals row
    ++ addTotalBorders
          (concat [ rowAsTexts Total (cell totalRowHeadingBudgetCsv) totrow | not no_total_ ])
    )

  where
    cell = Ods.defaultCell
    accountCell row =
        let name = prrFullName row in
        setAccountAnchor (balance_base_url_) querystring_ name $
        cell $ renderPeriodicAcct ropts nbsp row
    allHeaders =
      case layout_ of
      LayoutBareWide ->
          [headerWithoutBorders $
              Ods.emptyCell :
              concatMap
                  (Ods.horizontalSpan allCommodities . headerCell)
                  dateHeaders,
           addHeaderBorders $ map headerCell $
              leadingHeaders ++ (dateHeaders >> allCommodities)]
      _ -> [addHeaderBorders $ map headerCell $ leadingHeaders ++ dateHeaders]
    leadingHeaders =
      "Account" : ["Commodity" | layout_ == LayoutBare ]
    dateHeaders =
      (if not summary_only_
            then concatMap (\spn -> [renderPeriodHeading period_titles_ spn, "budget"]) colspans
            else [])
       ++ concat [["Total"  ,"budget"] | row_total_]
       ++ concat [["Average","budget"] | average_]
    allCommodities =
       S.toAscList $
       foldMap (foldMap maCommodities . concatMap (\(change,goal) -> maybeToList change ++ maybeToList goal) . prrAmounts) items

    {-
    ToDo: The chosen HTML cell class names are not put in stone.
    If you find you need more systematic names,
    feel free to develop a more sophisticated scheme.
    -}
    flattentuples rc tups =
        concat [[(amountClass rc, a),(budgetClass rc, b)] | (a,b) <- tups]
    showNorm (cls,mval) =
        maybe Ods.emptyCell (fmap wbToText . curry (cellFromMixedAmount fmt) cls) mval

    rowAsTexts :: RowClass
               -> Ods.Cell Ods.NumLines Text
               -> PeriodicReportRow a BudgetCell
               -> [[Ods.Cell Ods.NumLines Text]]
    rowAsTexts rc acctCell (PeriodicReportRow _ as (rowtot,budgettot) (rowavg, budgetavg)) =
      addRowSpanHeader acctCell $
      case layout_ of
        LayoutBare ->
            zipWith (:) (map cell cs)   -- add symbols
          . transpose                   -- each row becomes a list of Text quantities
          . bareCells (setDisplayCommodityBare cs fmt)
          $ vals
        LayoutBareWide -> [concat . bareCells fmt $ vals]
        _ -> [map showNorm vals]
      where
        bareCells fmt_ =
          map (map (fmap wbToText) .
          cellsFromMixedAmount fmt_ .
          second (fromMaybe nullmixedamt))
        cs = S.toList . mconcat . map maCommodities $ mapMaybe snd vals
        vals = flattentuples rc (if not summary_only_ then as else [])
            ++ concat [[(rowTotalClass rc, rowtot),
                        (budgetTotalClass rc, budgettot)]
                            | row_total_]
            ++ concat [[(rowAverageClass rc, rowavg),
                        (budgetAverageClass rc, budgetavg)]
                            | average_]


setBareWideCommodityOrder ::
    Layout -> [CommoditySymbol] -> AmountFormat -> AmountFormat
setBareWideCommodityOrder lay cs fmt =
    case lay of
      LayoutBareWide -> setDisplayCommodityBare cs fmt
      _ -> fmt

setDisplayCommodityBare :: [CommoditySymbol] -> AmountFormat -> AmountFormat
setDisplayCommodityBare cs fmt =
    fmt{
        displayCommodity = False,
        displayCommodityOrder = Just cs,
        displayMinWidth = Nothing
    }


nbsp :: Text
nbsp = "\160"

renderBalanceAcct ::
    ReportOpts -> Text -> (AccountName, AccountName, Int) -> Text
renderBalanceAcct opts space (fullName, displayName, dep) =
  if accountlistmode_ opts == ALTree && not (full_names_ opts)
    then T.replicate (dep*2) space <> displayName
    else accountNameDrop (drop_ opts) fullName

-- FIXME. Have to check explicitly for which to render here, since
-- budgetReport sets accountlistmode to ALTree. Find a principled way to do
-- this.
renderPeriodicAcct ::
    ReportOpts -> Text -> PeriodicReportRow DisplayName a -> Text
renderPeriodicAcct opts space row =
    renderBalanceAcct opts space
        (prrFullName row, prrDisplayName row, prrIndent row)


-- tests

tests_Balance = testGroup "Balance" [

   testGroup "balanceReportAsText" [
    testCase "unicode in balance layout" $ do
      j <- readJournal'' "2009/01/01 * медвежья шкура\n  расходы:покупки  100\n  актив:наличные\n"
      let rspec = defreportspec{_rsReportOpts=defreportopts{no_total_=True}}
      balanceReportAsText (_rsReportOpts rspec) (balanceReport rspec{_rsDay=fromGregorian 2008 11 26} j)
        @?=
        TL.unlines
        ["                -100  актив:наличные"
        ,"                 100  расходы:покупки"
        ]
    ]

  ]
