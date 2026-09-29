{-|

A ledger-compatible @print@ command.

-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

module Hledger.Cli.Commands.Print (
  printmode
 ,print'
 ,journalApplyMatchOpt
 ,entriesReportAsTextHelper
 ,roundFlag
 ,roundFromRawOpts
 ,amountStylesSetRoundingFromRawOpts
 ,layoutFlag
 ,layoutFromRawOpts
 ,transactionWithMostlyOriginalPostings
)
where


import Data.Function ((&))
import Data.List (intersperse, intercalate)
import Data.Text (Text)
import Data.Map (Map)
import Data.Map qualified as Map
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Builder qualified as TB
import Lens.Micro ((^.), _Just, has)
import Safe (lastMay, readMay)
import System.Console.CmdArgs.Explicit

import Hledger
import Hledger.Write.Beancount (showTransactionBeancount, beancountTransactions, beancountRenameAccounts, beancountDirectives, beancountItemRenderer)
import Hledger.Write.Ledger (showTransactionLedger, ledgerItemRenderer)
import Hledger.Write.Journal (ItemRenderer(..), journalItemRenderer, journalItemsAsText)
import Hledger.Write.Csv (CSV, printCSV, printTSV)
import Hledger.Write.Ods (printFods)
import Hledger.Write.Html (styledTableHtml, htmlAsLazyText, toHtml)
import Hledger.Write.Spreadsheet qualified as Spr
import Hledger.Cli.CliOptions
import Hledger.Cli.Utils
import Hledger.Cli.Anchor (setAccountAnchor)
import System.IO qualified as IO
import Data.Maybe (isJust, isNothing)

printmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Print.txt")
  ([
   flagNone ["all","a"] (setboolopt "explicit" . setboolopt "lots" . setboolopt "verbose-tags")
    "show all details (--explicit --lots --verbose-tags)"
  ,flagNone ["explicit","x"] (setboolopt "explicit") "show all inferred info explicitly"
  ,flagNone ["verbose-tags"] (setboolopt "verbose-tags") "add tags indicating generated/modified data"
  ,flagNone ["invert"] (setboolopt "invert") "display all amounts with reversed sign"
  ,flagNone ["locations"] (setboolopt "locations") "add tags showing file paths and line numbers"
  ,flagNone ["export"] (setboolopt "export") "reproduce the whole journal, with directives and comments preserved and included files inlined"
  ,let arg = "DESC" in
   flagReq  ["match","m"] (\s opts -> Right $ setopt "match" s opts) arg
    ("fuzzy search for one recent transaction with description closest to "++arg)
  ,flagNone ["new"] (setboolopt "new") "show only newer-dated transactions added in each file since last run"
  ,roundFlag
  ,layoutFlag
  ,flagReq  ["base-url"] (\s opts -> Right $ setopt "base-url" s opts) "URLPREFIX"
    "in html output, generate links to hledger-web, with this prefix. (Usually the base url shown by hledger-web; can also be relative.)"
  ,outputFormatFlag ["txt","ledger","beancount","csv","tsv","html","fods","json","sql"]
  ,outputFileFlag
  ])
  cligeneralflagsgroups1
  hiddenflags
  ([], Just $ argsFlag "[QUERY]")

roundFlag = flagReq  ["round"] (\s opts -> Right $ setopt "round" s opts) "TYPE" $
  intercalate "\n"
  ["how much rounding or padding should be done when displaying amounts ?"
  ,"none - show original decimal digits,"
  ,"       as in journal (default)"
  ,"soft - just add or remove decimal zeros"
  ,"       to match precision"
  ,"hard - round posting amounts to precision"
  ,"       (can unbalance transactions)"
  ,"all  - also round cost amounts to precision"
  ,"       (can unbalance transactions)"
  ]

-- | Get the --round option's value, if any. Can fail with a parse error.
roundFromRawOpts :: RawOpts -> Maybe Rounding
roundFromRawOpts = lastMay . collectopts roundfromrawopt
  where
    roundfromrawopt (n,v)
      | n=="round", v=="none" = Just NoRounding
      | n=="round", v=="soft" = Just SoftRounding
      | n=="round", v=="hard" = Just HardRounding
      | n=="round", v=="all"  = Just AllRounding
      | n=="round"            = error' $ "--round's value should be none, soft, hard or all; got: "++v
      | otherwise             = Nothing

-- | Set these amount styles' rounding strategy when they are being applied to amounts,
-- according to the value of the --round option, if any.
amountStylesSetRoundingFromRawOpts :: RawOpts -> Map CommoditySymbol AmountStyle -> Map CommoditySymbol AmountStyle
amountStylesSetRoundingFromRawOpts rawopts styles =
  case roundFromRawOpts rawopts of
    Just r  -> amountStylesSetRounding r styles
    Nothing -> styles

-- | The --layout flag for the print command, selecting how posting lines are aligned.
layoutFlag :: Flag RawOpts
layoutFlag = flagReq ["layout"] (\s opts -> Right $ setopt "layout" s opts) "hledger1|COL" $
  intercalate "\n"
  ["how should posting amounts be aligned ?"
  ,"hledger1 - right-align amounts, as in hledger 1"
  ,"COL      - align decimal marks at column COL (default: 53)"
  ]

-- | Parse the --layout option. Defaults to 'defaultPostingLayout' if absent.
-- Errors with a clear message if the value is neither \"hledger1\" nor a positive integer.
layoutFromRawOpts :: RawOpts -> PostingLayout
layoutFromRawOpts rawopts = case maybestringopt "layout" rawopts of
  Nothing         -> defaultPostingLayout
  Just "hledger1" -> LayoutHledger1
  Just s -> case readMay s of
    Just n | n >= 0 -> LayoutDecimal n
    _ -> error' $ "--layout's value should be 'hledger1' or a positive integer column number; got: " ++ s

-- | Print journal transactions in standard format.
print' :: CliOpts -> Journal -> IO ()
print' opts@CliOpts{rawopts_=rawopts} j = do
  -- The print command should show all amounts with their original decimal places,
  -- but as part of journal reading the posting amounts have already been normalised
  -- according to commodity display styles, and currently it's not easy to avoid
  -- that. For now we try to reverse it by increasing all amounts' decimal places
  -- sufficiently to show the amount exactly. The displayed amounts may have minor
  -- differences from the originals, such as trailing zeroes added.
  -- But, we skip this for inferred postings.
  -- This avoids eg showing too many decimals by default for inferred gain amounts.
  let
    -- lbl = lbl_ "print'"
    hasPtype t p = ("_ptype", t) `elem` ptags p
    isGeneratedGainPosting p = hasPtype "gain" p
    setFullPrecisionExceptGain p
      | isGeneratedGainPosting p = p
      | otherwise = postingTransformAmount mixedAmountSetFullPrecision p
    j' = j
      -- & dbg9With (lbl "amounts before setting full precision".showJournalPostingAmountsDebug)
      & journalMapPostings setFullPrecisionExceptGain
      -- & dbg9With (lbl "amounts after  setting full precision: ".showJournalPostingAmountsDebug)
      & if boolopt "locations" rawopts then journalMapTransactions addLocationTag else id

  printEntries opts $ journalApplyMatchOpt opts j'

-- | With --match DESC, keep only the one recent transaction whose description
-- is most similar to DESC, erroring if there is none. Otherwise, return the journal unchanged.
-- XXX should match similarly to register --match
journalApplyMatchOpt :: CliOpts -> Journal -> Journal
journalApplyMatchOpt opts j =
  case maybestringopt "match" $ rawopts_ opts of
    Nothing   -> j
    Just desc ->
      case journalSimilarTransaction opts j (dbg1 "finding best match for description" $ T.pack desc) of
        Just t  -> j{jtxns=[t]}
        Nothing -> error' $ "no transactions found with descriptions like " <> show desc

printEntries :: CliOpts -> Journal -> IO ()
printEntries opts@CliOpts{rawopts_=rawopts, reportspec_=rspec} j =
  writeOutputLazyText opts $
    if boolopt "export" rawopts
    then renderExport $ entriesReportUnsorted rspec j
    else render $ entriesReport rspec j
  where
    -- print does user-specified rounding or (by default) no rounding, in all output formats
    styles = amountStylesSetRoundingFromRawOpts rawopts $ journalCommodityStyles j
    styledPrices = map (\pd -> pd{pdamount = styleAmounts styles $ pdamount pd}) $ jpricedirectives j

    fmt = outputFormatFromOpts opts
    baseUrl = balance_base_url_ $ _rsReportOpts rspec
    query = querystring_ $ _rsReportOpts rspec
    postinglayout = layoutFromRawOpts rawopts

    -- With --export, reproduce the journal file(s): directives and comments verbatim,
    -- the (filtered, processed) transactions in their original positions, and blank lines normalised.
    -- Transactions and postings generated by --forecast, --auto etc. are included when those flags
    -- are used, and then the periodic transaction rules / auto posting rules which generated them are dropped.
    renderExport
      | fmt=="txt"    = exportWith (journalItemRenderer $ showTransactionWithLayout postinglayout)
      | fmt=="ledger" = exportWith ledgerItemRenderer
      | fmt=="beancount" = \ts ->
          let (j', ts') = beancountRenameAccounts j{jpricedirectives=styledPrices} $ beancountTransactions $ styleAmounts styles $ map fillBalanceAssignments ts
          -- (beancountItemRenderer drops all directives, including rules; anything generated is exported)
          in beancountDirectives j' ts' <> "\n" <> journalItemsAsText beancountItemRenderer (jitems j') ts'
      | otherwise     = error' "print --export supports only the txt, ledger and beancount output formats"  -- PARTIAL:
      where
        exportWith renderer = journalItemsAsText (withoutAppliedRules renderer) (jitems j) . styleAmounts styles . map (maybeoriginalamountsWith False)
        withoutAppliedRules renderer = renderer{irDirective = \txt -> if isAppliedRule txt then Nothing else irDirective renderer txt}
        isAppliedRule txt = (forecasting && "~" `T.isPrefixOf` txt) || (autoposting && "=" `T.isPrefixOf` txt)
        forecasting = isJust $ forecast_ $ inputopts_ opts
        autoposting = auto_ $ inputopts_ opts

    render | fmt=="txt"       = withTitle (_rsReportOpts rspec) . entriesReportAsTextHelper (showTransactionWithLayout postinglayout) . styleAmounts styles . map maybeoriginalamounts
           | fmt=="ledger"   = withTitle (_rsReportOpts rspec) . entriesReportAsTextHelper showTransactionLedger . styleAmounts styles . map maybeoriginalamounts
           | fmt=="beancount" = entriesReportAsTextHelper showTransactionBeancount . snd . beancountRenameAccounts j . beancountTransactions . styleAmounts styles . map fillBalanceAssignments
           | fmt=="csv"       = printCSV . entriesReportAsCsv . styleAmounts styles
           | fmt=="tsv"       = printTSV . entriesReportAsCsv . styleAmounts styles
           | fmt=="json"      = toJsonText                    . styleAmounts styles
           | fmt=="sql"       = entriesReportAsSql            . styleAmounts styles
           | fmt=="html" =
                (<>"\n") . htmlAsLazyText . styledTableHtml .
                map (map (fmap toHtml)) .
                entriesReportAsSpreadsheet oneLineNoCostFmt baseUrl query .
                styleAmounts styles
           | fmt=="fods" =
                printFods IO.localeEncoding . Map.singleton "Print" .
                (,) (1,0) .
                entriesReportAsSpreadsheet oneLineNoCostFmt baseUrl query .
                styleAmounts styles
           | otherwise = error' $ unsupportedOutputFormatError fmt  -- PARTIAL:

    -- For plain print, lot postings also get the cost basis annotation inferred
    -- by lot processing, making the output self-describing; not for --export,
    -- which reproduces the journal's directives instead and keeps entries as written.
    maybeoriginalamounts = maybeoriginalamountsWith True
    maybeoriginalamountsWith showinferredbasis
      -- Use the fully inferred and amount-styled/rounded transaction in the following situations:
      -- with -x/--explicit:
      | boolopt "explicit" (rawopts_ opts) = id
      -- with --infer-costs
      | opts ^. infer_costs = id
      -- with -B/-V/-X/--value ("because of #551, and because of print -V valuing only one posting when there's an implicit txn price.")
      | has (value . _Just) opts = id
      | isJust (conversionop_ $ _rsReportOpts rspec) = id
      -- For transactions containing priced auto-split postings (from lot transfer
      -- auto-split), keep the explicit form: reverting to the original would drop
      -- the priced dispose fragment while keeping its generated gain postings,
      -- leaving an unbalanced entry. (Priceless fee fragments generate no gain
      -- postings, so those transactions can safely revert to the user's original
      -- entry - except with --lots, where fragments must be kept to round-trip.)
      -- Otherwise, keep the transaction's amounts close to how they were written in the journal.
      | otherwise = \t ->
          if any keptFeesplit (tpostings t)
          then t
          else transactionWithMostlyOriginalPostings showinferredbasis t
      where
        hasTag name p = name `elem` map fst (ptags p)
        keptFeesplit p = hasTag feesplitPostingTagName p
          && (boolopt "lots" (rawopts_ opts) || any (isJust . acost) (amountsRaw (pamount p)))

    -- Like maybeoriginalamounts, but also keeps the inferred amount for
    -- balance assignment postings (which had no explicit amount).
    -- Beancount requires all amounts to be explicit.
    fillBalanceAssignments t = (maybeoriginalamountsWith False t)
      { tpostings = zipWith fillIfBalAssign (tpostings t) (tpostings $ maybeoriginalamountsWith False t) }
      where
        fillIfBalAssign inferred reverted
          | isJust (pbalanceassertion orig) && isMissingMixedAmount (pamount orig) = reverted { pamount = pamount inferred }
          | otherwise = reverted
          where orig = originalPosting inferred

-- | Replace this transaction's postings with the original postings if any, but keep the
-- current possibly rewritten account names, and the inferred values of any auto postings.
-- Drops postings tagged 'feesplitPostingTagName' (synthetic fragments carved off other
-- postings, eg by lot transfer auto-split), so the user sees their original entry.
-- Postings tagged 'lotsplitPostingTagName' (per-lot dispose/transfer split fragments)
-- are retained, keeping their fragment 'pamount' rather than reverting to 'poriginal' —
-- so 'print --lots' shows the per-lot detail, while 'journalCollapseLotDetail' has
-- already merged them down to one posting when --lots is off.
-- With a true first argument, lot postings whose original amount had no cost basis
-- annotation get the one inferred by lot processing (see withInferredBasis below).
-- This is mainly for showing transactions with the amounts in their original journal format.
transactionWithMostlyOriginalPostings :: Bool -> Transaction -> Transaction
transactionWithMostlyOriginalPostings showinferredbasis t =
  transactionMapPostings postingMostlyOriginal
    t{tpostings = filter (not . hasTag feesplitPostingTagName) (tpostings t)}
  where
    postingMostlyOriginal p = orig
        { paccount = paccount p
        , pamount = newAmt
        -- Keep the current comment and tags: journal processing only appends
        -- to these (eg visible ptype tags added by lot classification, which
        -- runs after the original was snapshotted), never rewrites the
        -- user's text.
        , pcomment = pcomment p
        , ptags = ptags p
        -- When paccount equals the original (no collapse), trust the
        -- original's assertion. When paccount has been changed (eg a lot
        -- subaccount was collapsed away), use the current state's
        -- assertion — which 'journalCollapseLotDetail' has already cleared
        -- if the assertion targeted the now-hidden lot subaccount.
        , pbalanceassertion =
            if paccount orig == paccount p
            then pbalanceassertion orig
            else pbalanceassertion p }
      where
        orig = originalPosting p
        newAmt
          | hasTag generatedPostingTagName p = pamount p
          -- For per-lot dispose/transfer fragments, use the user's original
          -- amount but with the fragment's quantity (so 'print --lots' shows
          -- e.g. "-1 A {} @ $60" rather than the full inferred form).
          -- When the original was elided or a balance assignment (no amount),
          -- show the fragment's current amount: several sibling fragments
          -- can't re-infer their amounts on re-reading (#2692).
          | hasTag lotsplitPostingTagName p  =
              withInferredBasis $ if hasAmount orig then scaleToFragment (pamount orig) (pamount p) else pamount p
          | otherwise                        = withInferredBasis (pamount orig)
        -- Show the cost basis annotation inferred by lot processing, when the
        -- user didn't write one, so lot entries are self-describing (they can
        -- be re-read without the commodity's lots: declaration, under the
        -- default method). Not needed with --lots, where the lot subaccount
        -- name already carries it.
        withInferredBasis ma
          | not showinferredbasis = ma
          | isJust (lotSubaccountName (paccount p)) = ma
          | otherwise = case (amountsRaw ma, amountsRaw (pamount p)) of
              ([oa], [ca]) | isNothing (acostbasis oa), Just cb <- acostbasis ca -> mixedAmount oa{acostbasis = Just cb}
              _ -> ma
    scaleToFragment origAmt curAmt = case (amountsRaw origAmt, amountsRaw curAmt) of
      ([oa], [ca]) -> mixedAmount oa{aquantity = aquantity ca}
      _            -> curAmt
    hasTag name p = name `elem` map fst (ptags p)

entriesReportAsTextHelper :: (Transaction -> T.Text) -> EntriesReport -> TL.Text
entriesReportAsTextHelper showtxn = TB.toLazyText . foldMap (TB.fromText . showtxn)

entriesReportAsSql :: EntriesReport -> TL.Text
entriesReportAsSql txns = TB.toLazyText $ mconcat
    [ TB.fromText "create table if not exists postings(id serial,txnidx int,date1 date,date2 date,status text,code text,description text,comment text,account text,amount numeric,commodity text,debit numeric,credit numeric,posting_status text,posting_comment text);\n"
    , TB.fromText "insert into postings(txnidx,date1,date2,status,code,description,comment,account,amount,commodity,debit,credit,posting_status,posting_comment) values\n"
    , mconcat . intersperse (TB.fromText ",") $ map values csv
    , TB.fromText ";\n"
    ]
  where
    values vs = TB.fromText "(" <> mconcat (intersperse (TB.fromText ",") $ map toSql vs) <> TB.fromText ")\n"
    toSql "" = TB.fromText "NULL"
    toSql s  = TB.fromText "'" <> TB.fromText (T.replace "'" "''" s) <> TB.fromText "'"
    csv =
        Spr.rawTableContent . transactionToSpreadsheet machineFmt Nothing [] .
        transactionMapPostingAmounts (mapMixedAmount setDecimalPoint)
            =<< txns
      where
        setDecimalPoint a = a{astyle=(astyle a){asdecimalmark=Just '.'}}

entriesReportAsCsv :: EntriesReport -> CSV
entriesReportAsCsv =
  Spr.rawTableContent . entriesReportAsSpreadsheet machineFmt Nothing []

entriesReportAsSpreadsheet ::
  AmountFormat -> Maybe Text -> [Text] ->
  EntriesReport -> [[Spr.Cell Spr.NumLines Text]]
entriesReportAsSpreadsheet fmt baseUrl query txns =
  Spr.addHeaderBorders
    (map Spr.headerCell
        ["txnidx","date","date2","status","code","description","comment",
         "account","amount","commodity","debit","credit",
         "posting-status","posting-comment"])
  :
  concatMap (transactionToSpreadsheet fmt baseUrl query) txns

-- | Generate one record per posting, duplicating the common transaction fields.
-- The txnidx field (transaction index) allows postings to be grouped back into transactions.
transactionToSpreadsheet ::
  AmountFormat -> Maybe Text -> [Text] ->
  Transaction -> [[Spr.Cell Spr.NumLines Text]]
transactionToSpreadsheet fmt baseUrl query t =
  addRowSpanHeader (idx:d:d2:status:code:description:comment:[])
    (postingToSpreadsheet fmt baseUrl query =<< tpostings t)
  where
    cell = Spr.defaultCell
    idx = Spr.integerCell $ tindex t
    description = cell $ tdescription t
    dateCell date =
        (Spr.defaultCell $ showDate date) {Spr.cellType = Spr.TypeDate}
    d = dateCell $ tdate t
    d2 = maybe Spr.emptyCell dateCell $ tdate2 t
    status = cell $ T.pack . show $ tstatus t
    code = cell $ tcode t
    comment = cell $ T.strip $ tcomment t

addRowSpanHeader ::
    [Spr.Cell border text] ->
    [[Spr.Cell border text]] -> [[Spr.Cell border text]]
addRowSpanHeader common rows =
    case rows of
        [] -> []
        [row] -> [common++row]
        _ ->
            let setSpan spn cell = cell{Spr.cellSpan = spn} in
            zipWith (++)
                (map (setSpan $ Spr.SpanVertical $ length rows) common :
                 repeat (map (setSpan Spr.Covered) common))
                rows

postingToSpreadsheet ::
  (Spr.Lines border) =>
  AmountFormat -> Maybe Text -> [Text] ->
  Posting -> [[Spr.Cell border Text]]
postingToSpreadsheet fmt baseUrl query p =
  map (\(a@(Amount {aquantity=q,acommodity=c})) ->
    -- commodity goes into separate column, so we suppress it, along with digit group
    -- separators and prices
    let a_ = amountStripCost a{acommodity=""} in
    let credit = if q < 0 then amountCell $ negate a_ else Spr.emptyCell in
    let debit  = if q >= 0 then amountCell a_ else Spr.emptyCell in
    [setAccountAnchor baseUrl query (paccount p) $ cell account,
     amountCell a_, cell c,
     debit, credit, cell status, cell comment])
    . amounts $ pamount p
  where
    cell = Spr.defaultCell
    amountCell amt =
      Spr.cellFromAmount fmt
        (Spr.Class "amount", (wbToText $ showAmountB machineFmt amt, amt))
    status = T.pack . show $ pstatus p
    account = showAccountName Nothing (preal p) (paccount p)
    comment = T.strip $ pcomment p

addLocationTag :: Transaction -> Transaction
addLocationTag t = t{tcomment = tcomment t `commentAddTagNextLine` loctag}
  where
    loctag = ("location", T.pack . sourcePosPairPretty $ tsourcepos t)