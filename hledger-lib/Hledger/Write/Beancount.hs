{-|
Helpers for beancount output.
-}

{-# LANGUAGE OverloadedStrings    #-}

module Hledger.Write.Beancount (
  showTransactionBeancount,
  showPriceDirectiveBeancount,
  beancountTransactions,
  beancountRenameAccounts,
  beancountDirectives,
  beancountItemRenderer,
  -- postingsAsLinesBeancount,
  -- postingAsLinesBeancount,
  -- showAccountNameBeancount,
  tagsToBeancountMetadata,
  showBeancountMetadata,
  accountNameToBeancount,
  commodityToBeancount,
  -- beancountTopLevelAccounts,

  -- * Tests
  tests_WriteBeancount
)
where

-- import Prelude hiding (Applicative(..))
import Data.Char
import Data.Default (def)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Builder qualified as TB
import Data.Time.Calendar (Day, fromGregorian)
import Safe (maximumBound)
import Text.DocLayout (realLength)
import Text.Printf
import Text.Tabular.AsciiWide hiding (render)

import Hledger.Utils
import Hledger.Data.Types
import Hledger.Data.AccountName
import Hledger.Data.Amount
import Hledger.Data.Currency (currencySymbolToCode)
import Hledger.Data.Dates (showDate)
import Hledger.Data.Posting (renderCommentLines, showBalanceAssertion, postingIndent, isReal, postingHasTag, conversionPostingTagName)
import Hledger.Data.Transaction (payeeAndNoteFromDescription', transactionMapPostings)
import Hledger.Data.Journal (journalAccountType)
import Hledger.Write.Journal (ItemRenderer(..), journalItemRenderer)
import Data.Function ((&))
import Data.List.Extra (groupOnKey, nubSort)
import Data.Bifunctor (first)
import Data.List (intersperse, sort, sortOn)
import Data.Map qualified as M
import Data.Maybe (catMaybes, fromMaybe, isJust)
import Safe (minimumDef)

--- ** doctest setup
-- $setup
-- >>> :set -XOverloadedStrings

-- | Like showTransaction, but applies various adjustments to produce valid Beancount journal data.
showTransactionBeancount :: Transaction -> Text
showTransactionBeancount t =
  -- https://beancount.github.io/docs/beancount_language_syntax.html
  -- similar to showTransactionHelper, but I haven't bothered with Builder
     T.unlines (map beancountCommentLine $ T.lines $ tprecedingcomment t)
  <> firstline <> nl
  <> foldMap ((<> nl).postingIndent.showBeancountMetadata (Just maxmdnamewidth)) mds
  <> foldMap ((<> nl)) newlinecomments
  <> foldMap ((<> nl)) (postingsAsLinesBeancount $ tpostings t)
  <> nl
  where
    firstline = T.concat [date, status, payee, note, samelinecomment]
    date = showDate $ tdate t
    status = if tstatus t == Pending then " !" else " *"
    (payee,note) =
      case payeeAndNoteFromDescription' $ tdescription t of
        ("","") -> ("",      ""      )
        ("",n ) -> (""     , wrapq n )
        (p ,"") -> (wrapq p, wrapq "")
        (p ,n ) -> (wrapq p, wrapq n )
      where
        wrapq = wrap " \"" "\"" . escapeDoubleQuotes . escapeBackslash
    mds = tagsToBeancountMetadata $ ttags t
    maxmdnamewidth = maximum' $ map (T.length . fst) mds
    (samelinecomment, newlinecomments) =
      case renderCommentLines (tcomment t) of []   -> ("",[])
                                              c:cs -> (c,cs)

-- | Prepare transactions for Beancount output: remove virtual postings,
-- and remove conversion postings which are redundant with costs
-- (Beancount doesn't allow both; costs are more useful to it).
-- Assumes at most one cost + conversion postings group per transaction.
beancountTransactions :: [Transaction] -> [Transaction]
beancountTransactions ts =
  [ t{tpostings = filter (\p -> not $ isredundantconvp p) ps}
  | t <- ts
  , let ps = filter isReal $ tpostings t
  , let hascost = any (any (isJust . acost) . amounts . pamount) ps
  , let isredundantconvp p = hascost && postingHasTag conversionPostingTagName p
  ]

-- | Rename accounts for Beancount output, in these transactions' postings and in the journal's
-- account declarations: an account whose top-level name is not one of Beancount's required ones
-- is prefixed with the Beancount top-level account corresponding to its hledger account type,
-- if that is known (declared or inferred). Eg with "account bonds  ; type:A", bonds:treasury
-- becomes Assets:bonds:treasury (and then Assets:Bonds:Treasury when rendered).
-- Accounts of unknown type are left unchanged, and will raise an error when rendered.
beancountRenameAccounts :: Journal -> [Transaction] -> (Journal, [Transaction])
beancountRenameAccounts j ts =
  ( j{ jdeclaredaccounts    = map (first rename) $ jdeclaredaccounts j
     , jdeclaredaccounttags = M.mapKeys rename $ jdeclaredaccounttags j
     }
  , map (transactionMapPostings $ \p -> p{paccount = rename $ paccount p}) ts
  )
  where
    rename a
      | hasBeancountTopLevelAccount a = a
      | otherwise = maybe a (\t -> beancountTopLevelAccountFor t <> ":" <> a) $ journalAccountType j a

-- | Does this hledger account name's top-level part convert to one of Beancount's required top-level accounts ?
hasBeancountTopLevelAccount :: AccountName -> Bool
hasBeancountTopLevelAccount a = case accountNameComponents a of
  c:_ -> beancountTopLevelComponent c `elem` beancountTopLevelAccounts
  []  -> False

-- | The Beancount top-level account corresponding to a hledger account type.
beancountTopLevelAccountFor :: AccountType -> BeancountAccountName
beancountTopLevelAccountFor t = case t of
  Asset          -> "Assets"
  Cash           -> "Assets"
  Liability      -> "Liabilities"
  Equity         -> "Equity"
  Conversion     -> "Equity"
  UnrealisedGain -> "Equity"
  Revenue        -> "Income"
  Gain           -> "Income"
  Expense        -> "Expenses"

-- | Options and directives for a Beancount export of this journal and these
-- (Beancount-prepared, possibly filtered) transactions:
-- a sample tolerance option (commented out);
-- operating_currency options for the currencies used in costs;
-- commodity directives for declared commodities, with their tags as metadata;
-- open directives for declared and used accounts, each dated on its earliest posting
-- (or the earliest date overall), with account tags as metadata and a lots: tag as booking method;
-- and price directives, sorted by date.
-- Blank lines separate the sections; the result ends with a newline (or is empty if all sections are empty).
beancountDirectives :: Journal -> [Transaction] -> TL.Text
beancountDirectives j ts =
  TL.fromStrict $ T.intercalate "\n" $ filter (not . T.null) [toleranceoptions, operatingcurrencyoptions, commodities, opens, prices]
  where
    -- https://beancount.github.io/docs/precision_tolerances.html#configuration-for-default-tolerances
    toleranceoptions = ";option \"inferred_tolerance_default\" \"*:0.005\"\n"

    -- "A list of currencies that we single out during reporting and create dedicated columns for ...
    -- This is used to indicate the main currencies that you work with in real life"
    -- We use: all currencies used in costs.
    operatingcurrencyoptions = T.unlines
      [ "option \"operating_currency\" \"" <> commodityToBeancount c <> "\"" | c <- costcurrencies ]
      where
        costcurrencies = nubSort [ acommodity $ costAmount c | t <- ts, p <- tpostings t, a <- amounts $ pamount p, Just c <- [acost a] ]
        costAmount (UnitCost a)  = a
        costAmount (TotalCost a) = a

    -- The earliest transaction date, or failing that the earliest price date, or an arbitrary early date.
    firstdate = minimumDef (minimumDef (fromGregorian 1900 1 1) $ map pddate pricedirs) $ map tdate ts

    -- "DATE commodity CURRENCY": optional in Beancount, but preserves the declarations and their metadata.
    commodities = T.unlines
      [ withMetadata (showDate firstdate <> " commodity " <> commodityToBeancount c) tags
      | (c, tags) <- M.toList $ M.union (jdeclaredcommoditytags j) (M.map (const []) $ jdeclaredcommodities j)
      ]

    -- "all account names that receive postings to them will eventually have to have
    -- a corresponding Open directive with a date that precedes all transactions posted to the account"
    opens = T.unlines
      [ withMetadata (showDate d <> " open " <> accountNameToBeancount a <> bookingmethod) (filter (not . islotstag) tags)
      | a <- nubSort $ map fst (jdeclaredaccounts j) <> M.keys firstpostingdates
      , let d = fromMaybe firstdate $ M.lookup a firstpostingdates
      , let tags = fromMaybe [] $ M.lookup a $ jdeclaredaccounttags j
      , let bookingmethod = maybe "" (\v -> " \"" <> v <> "\"") $ lookup "lots" $ map (first T.toLower) tags
      ]
      where
        firstpostingdates = M.fromListWith min [ (paccount p, tdate t) | t <- ts, p <- tpostings t ]
        islotstag = (== "lots") . T.toLower . fst

    prices = T.unlines $ map showPriceDirectiveBeancount $ sortOn pddate pricedirs
    pricedirs = jpricedirectives j

    -- A directive line, followed by any tags as indented metadata lines.
    withMetadata line tags = T.intercalate "\n" $ line : map (postingIndent . showBeancountMetadata (Just maxwidth)) mds
      where
        mds = tagsToBeancountMetadata tags
        maxwidth = maximum' $ map (T.length . fst) mds

-- | An item renderer for Beancount output (print --export -O beancount).
-- Transactions are rendered with showTransactionBeancount.
-- Directives are dropped: those with Beancount equivalents are generated by beancountDirectives instead.
-- Comment lines and comment blocks are converted to Beancount (;) comments.
beancountItemRenderer :: ItemRenderer
beancountItemRenderer = (journalItemRenderer showTransactionBeancount)
  { irDirective    = const Nothing
  , irComment      = beancountCommentLine
  , irCommentBlock = T.unlines . map ("; " <>) . filter (not . T.isPrefixOf "end comment") . drop 1 . T.lines
  }

-- | Convert a journal comment line (starting with ; # or *) to a Beancount comment line (starting with ;).
beancountCommentLine :: Text -> Text
beancountCommentLine l = if ";" `T.isPrefixOf` T.stripStart l then l else "; " <> l

-- | Render a PriceDirective in Beancount format: DATE price COMMODITY AMOUNT
showPriceDirectiveBeancount :: PriceDirective -> Text
showPriceDirectiveBeancount pd =
  showDate (dateToBeancount $ pddate pd)
  <> " price "
  <> commodityToBeancount (pdcommodity pd)
  <> " "
  <> wbToText (showAmountB beancountPriceFmt $ amountToBeancount $ pdamount pd)
  where
    beancountPriceFmt = defaultFmt{ displayZeroCommodity=True, displayForceDecimalMark=True, displayQuotes=False }

-- | Convert a date to one Beancount will accept.
-- Beancount rejects year 0, which is the date hledger gives to the 1:1 price
-- directives it infers from commodity alias: tags; those become 0001-01-01.
dateToBeancount :: Day -> Day
dateToBeancount d | d == fromGregorian 0 1 1 = fromGregorian 1 1 1
                  | otherwise                = d

nl = "\n"

type BMetadata = Tag

-- https://beancount.github.io/docs/beancount_language_syntax.html#metadata-1
-- | Render a Beancount metadata as a metadata line (without the indentation or newline).
-- If a maximum name length is provided, space will be left after the colon
-- so that successive metadata values will all start at the same column.
showBeancountMetadata :: Maybe Int -> BMetadata -> Text
showBeancountMetadata mmaxnamewidth (n,v) =
  fitText (fmap (+2) mmaxnamewidth) Nothing False True (n <> ": ")
  <> toBeancountMetadataValue v

-- | Make a list of tags ready to be rendered as Beancount metadata:
-- Encode and lengthen names, encode values, and combine repeated tags into one.
-- Metadatas will be sorted by (encoded) name and then value.
tagsToBeancountMetadata :: [Tag] -> [BMetadata]
tagsToBeancountMetadata = sort . map (first toBeancountMetadataName) . uniquifyTags . filter (not.isHiddenTagName.fst)

-- | In a list of tags, replace each tag that appears more than once
-- with a single tag with all of the values combined into one, comma-and-space-separated.
-- This function also sorts all tags by name and then value.
uniquifyTags :: [Tag] -> [Tag]
uniquifyTags ts = [(k, T.intercalate ", " $ map snd $ tags) | (k, tags) <- groupOnKey fst $ sort ts]

toBeancountMetadataName :: TagName -> Text
toBeancountMetadataName name =
  prependStartCharIfNeeded $
  case T.uncons name of
    Nothing -> ""
    Just (c,cs) ->
      T.concatMap (\d -> if isBeancountMetadataNameChar d then T.singleton d else toBeancountMetadataNameChar d) $ T.cons c cs
  where
    -- If the name is empty, make it "mm".
    -- If it has only one character, prepend "m".
    -- If the first character is not a valid one, prepend "m".
    prependStartCharIfNeeded t =
      case T.uncons t of
        Nothing -> T.replicate 2 $ T.singleton beancountMetadataDummyNameStartChar
        Just (c,cs) | T.null cs || not (isBeancountMetadataNameStartChar c) -> T.cons beancountMetadataDummyNameStartChar t
        _ -> t

-- | Is this a valid character to start a Beancount metadata name (lowercase ASCII letter) ?
isBeancountMetadataNameStartChar :: Char -> Bool
isBeancountMetadataNameStartChar = isAsciiLower

-- | Dummy valid starting character to prepend to a Beancount metadata name if needed.
beancountMetadataDummyNameStartChar :: Char
beancountMetadataDummyNameStartChar = 'm'

-- | Is this a valid character in the middle of a Beancount metadata name (a lowercase ASCII letter, digit, _ or -) ?
isBeancountMetadataNameChar :: Char -> Bool
isBeancountMetadataNameChar c = isAsciiLower c || isDigit c || c `elem` ['_', '-']

-- | Convert a character to one or more characters valid inside a Beancount metadata name.
-- ASCII uppercase letters are lowercased, spaces are converted to dashes, and unsupported
-- characters (including non-ASCII letters) are encoded as c<HEXBYTES>.
toBeancountMetadataNameChar :: Char -> Text
toBeancountMetadataNameChar c
  | isBeancountMetadataNameChar c = T.singleton c
  | isAsciiUpper c = T.singleton $ toLower c
  | isSpace c = "-"
  | otherwise = T.pack $ printf "c%x" c

toBeancountMetadataValue :: TagValue -> Text
toBeancountMetadataValue = ("\"" <>) . (<> "\"") . T.concatMap toBeancountMetadataValueChar

-- | Is this a valid character in the middle of a Beancount metadata name (a lowercase letter, digit, _ or -) ?
isBeancountMetadataValueChar :: Char -> Bool
isBeancountMetadataValueChar c = c `notElem` ['"']

-- | Convert a character to one or more characters valid inside a Beancount metadata value:
-- a double quote is encoded as c<HEXBYTES>.
toBeancountMetadataValueChar :: Char -> Text
toBeancountMetadataValueChar c
  | isBeancountMetadataValueChar c = T.singleton c
  | otherwise = T.pack $ printf "c%x" c


-- | Render a transaction's postings as indented lines, suitable for `print -O beancount` output.
-- See also Posting.postingsAsLines.
postingsAsLinesBeancount :: [Posting] -> [Text]
postingsAsLinesBeancount ps = concatMap first3 linesWithWidths
  where
    linesWithWidths = map (postingAsLinesBeancount False maxacctwidth maxamtwidth) ps
    maxacctwidth = maximumBound 0 $ map second3 linesWithWidths
    maxamtwidth  = maximumBound 0 $ map third3  linesWithWidths

-- | Render one posting, on one or more lines, suitable for `print -O beancount` output.
-- Also returns the widths calculated for the account and amount fields.
-- See also Posting.postingAsLines.
postingAsLinesBeancount  :: Bool -> Int -> Int -> Posting -> ([Text], Int, Int)
postingAsLinesBeancount elideamount acctwidth amtwidth p =
    (concatMap (++ (map ("  "<>) $ metadatalines <> newlinecomments)) postingblocks
    ,thisacctwidth
    ,thisamtwidth
    )
  where
    -- This needs to be converted to strict Text in order to strip trailing
    -- spaces. This adds a small amount of inefficiency, and the only difference
    -- is whether there are trailing spaces in print (and related) reports. This
    -- could be removed and we could just keep everything as a Text Builder, but
    -- would require adding trailing spaces to 42 failing tests.
    postingblocks = [map T.stripEnd . T.lines . TL.toStrict $
                       render [ textCell BottomLeft statusandaccount
                              , textCell BottomLeft "  "
                              , Cell BottomLeft [pad amt]
                              , textCell BottomLeft samelinecomment
                              ]
                    | (amt,_assertion) <- shownAmountsAssertions]
    render = renderRow def{tableBorders=False, borderSpaces=False} . Group NoLine . map Header
    pad amt = WideBuilder (TB.fromText $ T.replicate w " ") w <> amt
      where w = max 12 amtwidth - wbWidth amt  -- min. 12 for backwards compatibility

    pacct = showAccountNameBeancount Nothing $ paccount p
    pstatusandacct p' = if pstatus p' == Pending then "! " else "" <> pacct

    -- currently prices are considered part of the amount string when right-aligning amounts
    -- Since we will usually be calling this function with the knot tied between
    -- amtwidth and thisamtwidth, make sure thisamtwidth does not depend on
    -- amtwidth at all.
    shownAmounts
      | elideamount = [mempty]
      | otherwise   = map addCostBasisAndCost amtParts
        where
          -- render amounts without cost or cost basis; we append them in beancount order (costbasis before cost) below
          basefmt = defaultFmt{ displayZeroCommodity=True, displayForceDecimalMark=True, displayQuotes=False, displayCost=False, displayCostBasis=False }
          costfmt = defaultFmt{ displayZeroCommodity=True, displayForceDecimalMark=True, displayQuotes=False }
          a' = mapMixedAmount amountToBeancount $ pamount p
          -- get the display builders (with costs stripped) paired with the original amounts (with costs intact)
          amtParts = zip (map fst $ showMixedAmountLinesPartsB basefmt a') (amounts a')
          addCostBasisAndCost (builder, amt) =
            builder <> showAmountCostBasisBeancountB costfmt amt <> showAmountCostB costfmt amt
    thisamtwidth = maximumBound 0 $ map wbWidth shownAmounts

    -- when there is a balance assertion, show it only on the last posting line
    shownAmountsAssertions = zip shownAmounts shownAssertions
      where
        shownAssertions = replicate (length shownAmounts - 1) mempty ++ [assertion]
          where
            assertion = maybe mempty ((WideBuilder (TB.singleton ' ') 1 <>).showBalanceAssertion) $ pbalanceassertion p

    -- pad to the maximum account name width, plus 2 to leave room for status flags, to keep amounts aligned
    statusandaccount = postingIndent . fitText (Just $ 2 + acctwidth) Nothing False True $ pstatusandacct p
    thisacctwidth = realLength pacct
    mds = tagsToBeancountMetadata $ filter (tagInComment (pcomment p)) (ptags p)
    tagInComment c (n,_) = case toRegex ("\\b" <> n <> ":") of
      Right r -> regexMatchText r c
      Left _  -> False
    metadatalines = map (postingIndent . showBeancountMetadata (Just maxtagnamewidth)) mds
      where maxtagnamewidth = maximum' $ map (T.length . fst) mds
    (samelinecomment, newlinecomments) =
      case renderCommentLines (pcomment p) of []   -> ("",[])
                                              c:cs -> (c,cs)

-- | Like showAccountName for Beancount journal format.
-- Calls accountNameToBeancount first.
showAccountNameBeancount :: Maybe Int -> AccountName -> Text
showAccountNameBeancount w = maybe id T.take w . accountNameToBeancount

type BeancountAccountName = AccountName
type BeancountAccountNameComponent = AccountName

-- | Convert a hledger account name to a valid Beancount account name.
-- It replaces spaces and underscores with dashes and other non-supported characters with C<HEXBYTES>;
-- prepends the letter A to any part which doesn't begin with a letter or number;
-- adds a second :A part if there is only one part;
-- and capitalises each part.
-- It also checks that the first part is one of the required english
-- account names Assets, Liabilities, Equity, Income, or Expenses, and if not
-- raises an informative error.
-- Ref: https://beancount.github.io/docs/beancount_language_syntax.html#accounts
accountNameToBeancount :: AccountName -> BeancountAccountName
accountNameToBeancount a = b
  where
    cs1 = case accountNameComponents $ dbg9 "hledger account name  " a of
      c:cs -> beancountTopLevelComponent c : map accountNameComponentToBeancount cs
      []   -> []
    cs2 =
      case cs1 of
        c:_ | c `notElem` beancountTopLevelAccounts -> error' e
          where
            e = T.unpack $ T.unlines [
              "bad top-level account: " <> c
              ,"in beancount account name:           " <> accountNameFromComponents cs1
              ,"converted from hledger account name: " <> a
              ,"For Beancount, top-level accounts must be one of " <> T.intercalate ", " beancountTopLevelAccounts <> "."
              ,"Declare this account's type (eg: account " <> a <> "  ; type:A) so that hledger can add the right one,"
              ,"or use --alias to rename it."
              ]
        [c] -> [c, "A"]
        cs  -> cs
    b = dbg9 "beancount account name" $ accountNameFromComponents cs2

-- | Convert a hledger account name's top-level part for Beancount:
-- "revenue" or "revenues" (case insensitive) become "Income", otherwise it is converted like any other part.
beancountTopLevelComponent :: AccountName -> BeancountAccountNameComponent
beancountTopLevelComponent c
  | T.toLower c `elem` ["revenue", "revenues"] = "Income"
  | otherwise = accountNameComponentToBeancount c

accountNameComponentToBeancount :: AccountName -> BeancountAccountNameComponent
accountNameComponentToBeancount acctpart =
  prependStartCharIfNeeded $
  case T.uncons acctpart of
    Nothing -> ""
    Just (c,cs) ->
      textCapitalise $
      T.concatMap (\d -> if isBeancountAccountChar d then (T.singleton d) else T.pack $ charToBeancount d) $ T.cons c cs
  where
    prependStartCharIfNeeded t =
      case T.uncons t of
        Just (c,_) | not $ isBeancountAccountStartChar c -> T.cons beancountAccountDummyStartChar t
        _ -> t

-- | Dummy valid starting character to prepend to Beancount account name parts if needed (A).
beancountAccountDummyStartChar :: Char
beancountAccountDummyStartChar = 'A'

-- | Convert a character which is not valid in a Beancount account name
-- (or commodity name) to one or more valid characters: spaces and underscores,
-- which are the usual hledger word separators, become a dash;
-- anything else is encoded as C<HEXBYTES>.
charToBeancount :: Char -> String
charToBeancount c
  | isSpace c || c == '_' = "-"
  | otherwise             = printf "C%x" c

-- XXX these probably allow too much unicode:

-- https://hackage.haskell.org/package/base-4.20.0.1/docs/Data-Char.html#v:isUpperCase would be more correct,
-- but isn't available till base 4.18/ghc 9.6. isUpper is close enough in practice.
isuppercase = isUpper

-- | Is this a valid character to start a Beancount account name part (capital letter or digit) ?
isBeancountAccountStartChar :: Char -> Bool
isBeancountAccountStartChar c = (isLetter c && isuppercase c) || isDigit c

-- | Is this a valid character to appear elsewhere in a Beancount account name part (letter, digit, or -) ?
isBeancountAccountChar :: Char -> Bool
isBeancountAccountChar c = isLetter c || isDigit c || c=='-'

beancountTopLevelAccounts = ["Assets", "Liabilities", "Equity", "Income", "Expenses"]

type BeancountAmount = Amount

-- | Do some best effort adjustments to make an amount that renders
-- in a way that Beancount can read: force the commodity symbol to the right,
-- capitalise all letters, convert a few currency symbols to codes.
amountToBeancount :: Amount -> BeancountAmount
amountToBeancount a@Amount{acommodity=c,astyle=s,acost=mp} = a{acommodity=c', astyle=s', acost=mp'}
  where
    c' = commodityToBeancount c
    s' = s{ascommodityside=R, ascommodityspaced=True}
    mp' = costToBeancount <$> mp
      where
        costToBeancount (TotalCost amt) = TotalCost $ amountToBeancount amt
        costToBeancount (UnitCost  amt) = UnitCost  $ amountToBeancount amt

-- | Show an amount's cost basis in Beancount lot syntax: {cost, date, label}
-- Returns a WideBuilder with the formatted cost basis, or mempty if there's no cost basis.
showAmountCostBasisBeancountB :: AmountFormat -> Amount -> WideBuilder
showAmountCostBasisBeancountB afmt amt = case acostbasis amt of
  Nothing -> mempty
  Just CostBasis{cbCost=Nothing, cbDate=Nothing, cbLabel=Nothing} ->
    WideBuilder (TB.fromString " {}") 3
  Just CostBasis{cbCost, cbDate, cbLabel} ->
    case parts of
      [] -> mempty
      _  -> WideBuilder (TB.fromString " {") 2 <> contents <> WideBuilder (TB.singleton '}') 1
    where
      parts = catMaybes
        [ fmap (showAmountB afmt . amountToBeancount) cbCost
        , fmap (wbFromText . T.pack . show) cbDate
        , fmap (wbFromText . quote) cbLabel
        ]
      contents = mconcat $ Data.List.intersperse (WideBuilder (TB.fromString ", ") 2) parts
      quote t = "\"" <> t <> "\""

type BeancountCommoditySymbol = CommoditySymbol

-- | Convert a hledger commodity name to a valid Beancount commodity name.
-- That is: 2-24 uppercase letters / digits / apostrophe / period / underscore / dash,
-- starting with a letter, and ending with a letter or digit.
-- Ref: https://beancount.github.io/docs/beancount_language_syntax.html#commodities-currencies
-- So this:
-- replaces common currency symbols with their ISO 4217 currency codes,
-- capitalises all letters,
-- replaces spaces with dashes and other invalid characters with C<HEXBYTES>,
-- prepends a C if the first character is not a letter,
-- appends a C if the last character is not a letter or digit,
-- doubles it if less than 2 characters,
-- and disables hledger's enclosing double quotes.
--
-- >>> commodityToBeancount ""
-- "CC"
-- >>> commodityToBeancount "$"
-- "USD"
-- >>> commodityToBeancount "Usd"
-- "USD"
-- >>> commodityToBeancount "\"a1\""
-- "A1"
-- >>> commodityToBeancount "\"A 1!\""
-- "A-1C21"
-- >>> commodityToBeancount "K"
-- "KK"
--
commodityToBeancount :: CommoditySymbol -> BeancountCommoditySymbol
commodityToBeancount "" = "CC"
commodityToBeancount com =
  dbg9 "beancount commodity name" $
  let com' = textStripQuotes com
  in case currencySymbolToCode com' of
    Just code -> code
    Nothing ->
      com'
      & T.toUpper
      & T.concatMap (\d -> if isBeancountCommodityChar d then T.singleton d else T.pack $ charToBeancount d)
      & fixstart
      & fixend
      & fixshort
  where
    fixstart bcom = case T.uncons bcom of
      Just (c,_) | isBeancountCommodityStartChar c -> bcom
      _ -> "C" <> bcom
    fixend bcom = case T.unsnoc bcom of
      Just (_,c) | isBeancountCommodityEndChar c -> bcom
      _ -> bcom <> "C"
    fixshort bcom
      | T.length bcom < 2 = bcom <> bcom   -- e.g. "K" -> "KK"
      | otherwise          = bcom

-- | Is this a valid character in the middle of a Beancount commodity name (a capital letter, digit, or '._-) ?
isBeancountCommodityChar :: Char -> Bool
isBeancountCommodityChar c = (isLetter c && isuppercase c) || isDigit c || c `elem` ['\'', '.', '_', '-']

-- | Is this a valid character to start a Beancount commodity name (a capital letter) ?
isBeancountCommodityStartChar :: Char -> Bool
isBeancountCommodityStartChar c = isLetter c && isuppercase c

-- | Is this a valid character to end a Beancount commodity name (a capital letter or digit) ?
isBeancountCommodityEndChar :: Char -> Bool
isBeancountCommodityEndChar c = (isLetter c && isuppercase c) || isDigit c

--- ** tests

tests_WriteBeancount :: TestTree
tests_WriteBeancount = testGroup "Write.Beancount" [
  ]
