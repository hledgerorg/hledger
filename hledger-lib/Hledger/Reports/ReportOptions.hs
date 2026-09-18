{-|

Options common to most hledger reports.

-}

{-# LANGUAGE BangPatterns          #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE RecordWildCards       #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators #-}

module Hledger.Reports.ReportOptions (
  ReportOpts(..),
  HasReportOptsNoUpdate(..),
  HasReportOpts(..),
  ReportSpec(..),
  HasReportSpec(..),
  SortField(..),
  SortSpec,
  sortKeysDescription,
  overEither,
  setEither,
  BalanceCalculation(..),
  BalanceAccumulation(..),
  AccountListMode(..),
  ValuationType(..),
  Layout(..),
  PeriodTitles(..),
  effectiveTitle,
  defreportopts,
  rawOptsToReportOpts,
  defreportspec,
  defsortspec,
  setDefaultConversionOp,
  reportOptsToSpec,
  updateReportSpec,
  updateReportSpecWith,
  rawOptsToReportSpec,
  reportSpecExpandCurQueries,
  balanceAccumulationOverride,
  flat_,
  tree_,
  reportOptsToggleStatus,
  simplifyStatuses,
  whichDate,
  journalValueAndFilterPostings,
  journalValueAndFilterPostingsWith,
  journalApplyValuationFromOpts,
  journalApplyValuationFromOptsWith,
  mixedAmountApplyValuationAfterSumFromOptsWith,
  valuationAfterSum,
  requiresHistorical,
  intervalFromRawOpts,
  queryFromFlags,
  transactionDateFn,
  postingDateFn,
  reportSpan,
  reportSpanBothDates,
  reportStartDate,
  reportEndDate,
  reportPeriodStart,
  reportPeriodOrJournalStart,
  reportPeriodLastDay,
  reportPeriodOrJournalLastDay,
  reportPeriodName
)
where

import Prelude hiding (Applicative(..))
import Control.Applicative (Applicative(..), Const(..), (<|>))
import Control.Monad (guard, join)
import Data.Char (toLower)
import Data.Either (fromRight)
import Data.Either.Extra (eitherToMaybe)
import Data.Functor.Identity (Identity(..))
import Data.List (partition)
import Data.List.Extra (find, isPrefixOf, nubSort, stripPrefix)
import Data.Maybe (fromMaybe, isJust, isNothing, mapMaybe)
import Data.Text qualified as T
import Data.Gettext (Catalog)
import Data.Time.Calendar (Day, addDays)
import Data.Default (Default(..))
import Safe (lastDef, lastMay, maximumMay, readMay)

import Hledger.Data
import Hledger.Query
import Hledger.Utils
import Data.Function ((&))

-- | What to calculate for each cell in a balance report.
-- "Balance report types -> Calculation type" in the hledger manual.
data BalanceCalculation =
    CalcChange        -- ^ Sum of posting amounts in the period.
  | CalcBudget        -- ^ Sum of posting amounts and the goal for the period.
  | CalcValueChange   -- ^ Change from previous period's historical end value to this period's historical end value.
  | CalcGain          -- ^ Change from previous period's gain, i.e. valuation minus cost basis.
  | CalcPostingsCount -- ^ Number of postings in the period.
  deriving (Eq, Show)

instance Default BalanceCalculation where def = CalcChange

-- | How to accumulate calculated values across periods (columns) in a balance report.
-- "Balance report types -> Accumulation type" in the hledger manual.
data BalanceAccumulation =
    PerPeriod   -- ^ No accumulation. Eg, shows the change of balance in each period.
  | Cumulative  -- ^ Accumulate changes across periods, starting from zero at report start.
  | Historical  -- ^ Accumulate changes across periods, including any from before report start.
                --   Eg, shows the historical end balance of each period.
  deriving (Eq,Show)

instance Default BalanceAccumulation where def = PerPeriod

-- | Should accounts be displayed: in the command's default style, hierarchically, or as a flat list ?
data AccountListMode = ALFlat | ALTree deriving (Eq, Show)

instance Default AccountListMode where def = ALFlat

data Layout = LayoutWide (Maybe Int)
            | LayoutTall
            | LayoutBare
            | LayoutBareWide
            | LayoutTidy
  deriving (Eq, Show)

-- | How to render period column headings in periodic reports.
data PeriodTitles = PTCompact | PTDates deriving (Eq, Show)

instance Default PeriodTitles where def = PTCompact

-- | Standard options for customising report filtering and output.
-- Most of these correspond to standard hledger command-line options
-- or query arguments, but not all. Some are used only by certain
-- commands, as noted below.
data ReportOpts = ReportOpts {
     -- for most reports:
     period_           :: Period
    ,interval_         :: Interval
    ,statuses_         :: [Status]  -- ^ Zero, one, or two statuses to be matched
    ,conversionop_     :: Maybe ConversionOp  -- ^ Which operation should we apply to conversion transactions?
    ,value_            :: Maybe ValuationType  -- ^ What value should amounts be converted to ?
    ,infer_prices_     :: Bool      -- ^ Infer market prices from transactions ?
    ,depth_            :: DepthSpec
    ,date2_            :: Bool
    ,empty_            :: Bool
    ,no_elide_         :: Bool
    ,full_names_       :: Bool
    ,real_             :: Bool
    ,format_           :: StringFormat
    ,balance_base_url_ :: Maybe T.Text
    ,pretty_           :: Bool
    ,querystring_      :: [T.Text]
    --
    ,average_          :: Bool
    -- for posting reports (register)
    ,related_          :: Bool
    -- for sorting reports (register)
    ,sortspec_             :: SortSpec
    -- for account transactions reports (aregister)
    ,txn_dates_        :: Bool
    -- for balance reports (bal, bs, cf, is)
    ,balancecalc_      :: BalanceCalculation  -- ^ What to calculate in balance report cells
    ,balanceaccum_     :: BalanceAccumulation -- ^ How to accumulate balance report values over time
    ,budgetpat_        :: Maybe T.Text  -- ^ A case-insensitive description substring
                                        --   to select periodic transactions for budget reports.
                                        --   (Not a regexp, nor a full hledger query, for now.)
    ,accountlistmode_  :: AccountListMode
    ,drop_             :: Int
    ,declared_         :: Bool  -- ^ Include accounts declared but not yet posted to ?
    ,row_total_        :: Bool
    ,no_total_         :: Bool
    ,summary_only_     :: Bool
    ,show_costs_       :: Bool  -- ^ Show costs for reports which normally don't show them ?
    ,sort_amount_      :: Bool
    ,percent_          :: Bool
    ,invert_           :: Bool  -- ^ Flip all amount signs in reports ?
    ,normalbalance_    :: Maybe NormalSign
      -- ^ This can be set when running balance reports on a set of accounts
      --   with the same normal balance type (eg all assets, or all incomes).
      -- - It helps --sort-amount know how to sort negative numbers
      --   (eg in the income section of an income statement)
      -- - It helps compound balance report commands (is, bs etc.) do
      --   sign normalisation, converting normally negative subreports to
      --   normally positive for a more conventional display.
    ,color_            :: Bool
      -- ^ Whether to use ANSI color codes in text output.
      --   Influenced by the --color/colour flag (cf CliOptions),
      --   whether stdout is an interactive terminal, and the value of
      --   TERM and existence of NO_COLOR environment variables.
    ,transpose_        :: Bool
    ,layout_           :: Layout
    ,catalog_          :: Maybe Catalog
    ,period_titles_  :: PeriodTitles
    -- | Explicit --title value if given (possibly empty to
    -- suppress); otherwise Nothing, in which case each report falls
    -- back to its own default heading. Resolved via effectiveTitle.
    ,title_   :: Maybe T.Text
    -- | Explicit --subreport-titles value, a |-separated list of
    -- subreport titles to use in compound reports. An empty string
    -- means "suppress all default subreport titles".
    ,subreport_titles_ :: Maybe T.Text
 } deriving (Show)

instance Default ReportOpts where def = defreportopts

defreportopts :: ReportOpts
defreportopts = ReportOpts
    { period_           = PeriodAll
    , interval_         = NoInterval
    , statuses_         = []
    , conversionop_     = Nothing
    , value_            = Nothing
    , infer_prices_     = False
    , depth_            = DepthSpec Nothing []
    , date2_            = False
    , empty_            = False
    , no_elide_         = False
    , full_names_       = False
    , real_             = False
    , format_           = def
    , balance_base_url_ = Nothing
    , pretty_           = False
    , querystring_      = []
    , average_          = False
    , related_          = False
    , sortspec_         = defsortspec 
    , txn_dates_        = False
    , balancecalc_      = def
    , balanceaccum_     = def
    , budgetpat_        = Nothing
    , accountlistmode_  = ALFlat
    , drop_             = 0
    , declared_         = False
    , row_total_        = False
    , no_total_         = False
    , summary_only_     = False
    , show_costs_       = False
    , sort_amount_      = False
    , percent_          = False
    , invert_           = False
    , normalbalance_    = Nothing
    , color_            = False
    , transpose_        = False
    , layout_           = LayoutWide Nothing
    , catalog_          = Nothing
    , period_titles_  = PTCompact
    , title_   = Nothing
    , subreport_titles_ = Nothing
    }

-- | Generate a ReportOpts from raw command-line input, given a day and whether to use ANSI colour/styles in standard output.
-- This will fail with a usage error if it is passed
-- - an invalid --format argument,
-- - an invalid --value argument,
-- - if --valuechange is called with a valuation type other than -V/--value=end.
-- - an invalid --pretty argument,
rawOptsToReportOpts :: Day -> Bool -> RawOpts -> ReportOpts
rawOptsToReportOpts d usecoloronstdout rawopts =

    -- Bang-let-bind the results of every option parser that can call usageError.
    -- This forces validation eagerly, so a malformed argument is rejected even
    -- when the current command would not otherwise read the corresponding field.
    -- Note: layoutopt is intentionally left lazy because the print command
    -- defines its own --layout flag with different semantics (column number or
    -- "hledger1"), reusing the same raw "layout" key.
    let formatstring = T.pack <$> maybestringopt "format" rawopts
        querystring  = map T.pack $ listofstringopt "args" rawopts  -- doesn't handle an arg like "" right

        !format = case parseStringFormat <$> formatstring of
            Nothing         -> defaultBalanceLineFormat
            Just (Right x)  -> x
            Just (Left err) -> usageError $ "could not parse format option: " ++ err
        !pretty           = fromMaybe False $ ynopt "pretty" rawopts
        !period           = periodFromRawOpts d rawopts
        !interval         = intervalFromRawOpts rawopts
        !conversionop     = conversionOpFromRawOpts rawopts
        !value            = valuationTypeFromRawOpts rawopts
        !depth            = depthFromRawOpts rawopts
        !sortspec         = getSortSpec rawopts
        !drop_n           = posintopt "drop" rawopts
        !periodTitles     = periodTitlesOpt rawopts

    in defreportopts
          {period_           = period
          ,interval_         = interval
          ,statuses_         = statusesFromRawOpts rawopts
          ,conversionop_     = conversionop
          ,value_            = value
          ,infer_prices_     = boolopt "infer-market-prices" rawopts
          ,depth_            = depth
          ,date2_            = boolopt "date2" rawopts
          ,empty_            = boolopt "empty" rawopts
          ,no_elide_         = boolopt "no-elide" rawopts
          ,full_names_       = boolopt "full-names" rawopts
          ,real_             = boolopt "real" rawopts
          ,format_           = format
          ,balance_base_url_ = T.pack <$> maybestringopt "base-url" rawopts
          ,querystring_      = querystring
          ,average_          = boolopt "average" rawopts
          ,related_          = boolopt "related" rawopts
          ,sortspec_         = sortspec
          ,txn_dates_        = boolopt "txn-dates" rawopts
          ,balancecalc_      = balancecalcopt rawopts
          ,balanceaccum_     = balanceaccumopt rawopts
          ,budgetpat_        = maybebudgetpatternopt rawopts
          ,accountlistmode_  = accountlistmodeopt rawopts
          ,drop_             = drop_n
          ,declared_         = boolopt "declared" rawopts
          ,row_total_        = boolopt "row-total" rawopts
          ,no_total_         = boolopt "no-total" rawopts
          ,summary_only_     = boolopt "summary-only" rawopts
          ,show_costs_       = boolopt "show-costs" rawopts
          ,sort_amount_      = boolopt "sort-amount" rawopts
          ,percent_          = boolopt "percent" rawopts
          ,invert_           = boolopt "invert" rawopts
          ,pretty_           = pretty
          ,color_            = usecoloronstdout
          ,transpose_        = toggleopt "transpose" rawopts
          ,layout_           = layoutopt rawopts
          ,period_titles_  = periodTitles
          ,title_   = unescapeNewlines . T.pack <$> maybestringopt "title" rawopts
          ,subreport_titles_ = unescapeNewlines . T.pack <$> maybestringopt "subreport-titles" rawopts
          }

-- | A fully-determined set of report parameters 
-- (report options with all partial values made total, eg the begin and end
-- dates are known, avoiding date/regex errors; plus the reporting date),
-- and the query successfully calculated from them.
--
-- If you change the report options or date in one of these, you should
-- use `reportOptsToSpec` to regenerate the whole thing, avoiding inconsistency.
--
data ReportSpec = ReportSpec
  { _rsReportOpts :: ReportOpts  -- ^ The underlying ReportOpts used to generate this ReportSpec
  , _rsDay        :: Day         -- ^ The Day this ReportSpec is generated for
  , _rsQuery      :: Query       -- ^ The generated Query for the given day
  , _rsQueryOpts  :: [QueryOpt]  -- ^ A list of QueryOpts for the given day
  } deriving (Show)

instance Default ReportSpec where def = defreportspec

defreportspec :: ReportSpec
defreportspec = ReportSpec
    { _rsReportOpts = def
    , _rsDay        = nulldate
    , _rsQuery      = Any
    , _rsQueryOpts  = []
    }

-- | Set the default ConversionOp.
setDefaultConversionOp :: ConversionOp -> ReportSpec -> ReportSpec
setDefaultConversionOp defop rspec@ReportSpec{_rsReportOpts=ropts} =
    rspec{_rsReportOpts=ropts{conversionop_=conversionop_ ropts <|> Just defop}}

accountlistmodeopt :: RawOpts -> AccountListMode
accountlistmodeopt =
  fromMaybe ALFlat . choiceopt parse where
    parse = \case
      "tree" -> Just ALTree
      "flat" -> Just ALFlat
      _      -> Nothing

periodTitlesOpt :: RawOpts -> PeriodTitles
periodTitlesOpt rawopts = case maybestringopt "period-titles" rawopts of
  Nothing        -> PTCompact
  Just "compact" -> PTCompact
  Just "dates"   -> PTDates
  Just s         -> usageError $ "--period-titles's argument should be \"compact\" or \"dates\", not " ++ show s

-- | Resolve the effective report heading: if --title was given
-- on the command line, use that value (which may be empty to suppress
-- the heading); otherwise return the supplied per-report default.
effectiveTitle :: ReportOpts -> T.Text -> T.Text
effectiveTitle ropts dflt = fromMaybe dflt (title_ ropts)

-- | Replace the literal two-character sequence "\n" with a real newline.
unescapeNewlines :: T.Text -> T.Text
unescapeNewlines = T.replace "\\n" "\n"

-- Get the argument of the --budget option if any, or the empty string.
maybebudgetpatternopt :: RawOpts -> Maybe T.Text
maybebudgetpatternopt = fmap T.pack . maybestringopt "budget"

balancecalcopt :: RawOpts -> BalanceCalculation
balancecalcopt =
  fromMaybe CalcChange . choiceopt parse where
    parse = \case
      "sum"         -> Just CalcChange
      "valuechange" -> Just CalcValueChange
      "gain"        -> Just CalcGain
      "budget"      -> Just CalcBudget
      "count"       -> Just CalcPostingsCount
      _             -> Nothing

balanceaccumopt :: RawOpts -> BalanceAccumulation
balanceaccumopt = fromMaybe PerPeriod . balanceAccumulationOverride

ynopt :: String -> RawOpts -> Maybe Bool
ynopt opt rawopts = case maybestringopt opt rawopts of
    Just "always" -> Just True
    Just "yes"    -> Just True
    Just "y"      -> Just True
    Just "never"  -> Just False
    Just "no"     -> Just False
    Just "n"      -> Just False
    Just _        -> usageError "this argument should be one of y, yes, n, no"
    _             -> Nothing

balanceAccumulationOverride :: RawOpts -> Maybe BalanceAccumulation
balanceAccumulationOverride rawopts = choiceopt parse rawopts <|> reportbal
  where
    parse = \case
      "historical" -> Just Historical
      "cumulative" -> Just Cumulative
      "change"     -> Just PerPeriod
      _            -> Nothing
    reportbal = case balancecalcopt rawopts of
      CalcValueChange -> Just PerPeriod
      _               -> Nothing

layoutopt :: RawOpts -> Layout
layoutopt rawopts = fromMaybe (LayoutWide Nothing) $ layout <|> column
  where
    layout = parse <$> maybestringopt "layout" rawopts
    column = LayoutBare <$ guard (boolopt "commodity-column" rawopts)

    parse opt = maybe err snd $ guard (not $ null s) *> find (isPrefixOf s . fst) checkNames
      where
        checkNames = [ ("wide", LayoutWide w)
                     , ("tall", LayoutTall)
                     , ("bare", LayoutBare)
                     , ("tidy", LayoutTidy)
                     , ("barewide", LayoutBareWide)
                     ]
        -- For `--layout=elided,n`, elide to the given width
        (s,n) = break (==',') $ map toLower opt
        w = case drop 1 n of
              "" -> Nothing
              c | Just w' <- readMay c -> Just w'
              _ -> usageError "width in --layout=wide,WIDTH must be an integer"

        err = usageError "--layout's argument should be \"wide[,WIDTH]\", \"tall\", \"bare\", \"barewide\", or \"tidy\""

-- Get the period specified by any -b/--begin, -e/--end and/or -p/--period
-- options appearing in the command line.
-- Its bounds are the rightmost begin date specified by a -b or -p, and
-- the rightmost end date specified by a -e or -p. Cf #1011.
-- Today's date is provided to help interpret any relative dates.
periodFromRawOpts :: Day -> RawOpts -> Period
periodFromRawOpts d rawopts =
  case (mlastb, mlaste) of
    (Nothing, Nothing) -> PeriodAll
    (Just b, Nothing)  -> PeriodFrom b
    (Nothing, Just e)  -> PeriodTo e
    (Just b, Just e)   -> simplifyPeriod $ PeriodBetween b e
  where
    mlastb = case beginDatesFromRawOpts d rawopts of
                   [] -> Nothing
                   bs -> Just $ fromEFDay $ last bs
    mlaste = case endDatesFromRawOpts d rawopts of
                   [] -> Nothing
                   es -> Just $ fromEFDay $ last es

-- Get all begin dates specified by -b/--begin or -p/--period options, in order,
-- using the given date to interpret relative date expressions.
beginDatesFromRawOpts :: Day -> RawOpts -> [EFDay]
beginDatesFromRawOpts d = collectopts (begindatefromrawopt d)
  where
    begindatefromrawopt d' (n,v)
      | n == "begin" =
          either (\e -> usageError $ "could not parse "++n++" date: "++customErrorBundlePretty e) Just $
          fixSmartDateStrEither' d' (T.pack v)
      | n == "period" =
        case
          either (\e -> usageError $ "could not parse period option: "++customErrorBundlePretty e) id $
          parsePeriodExpr d' (textStripQuotes $ T.pack v)
        of
          (_, DateSpan (Just b) _) -> Just b
          _                        -> Nothing
      | otherwise = Nothing

-- Get all end dates specified by -e/--end or -p/--period options, in order,
-- using the given date to interpret relative date expressions.
endDatesFromRawOpts :: Day -> RawOpts -> [EFDay]
endDatesFromRawOpts d = collectopts (enddatefromrawopt d)
  where
    enddatefromrawopt d' (n,v)
      | n == "end" =
          either (\e -> usageError $ "could not parse "++n++" date: "++customErrorBundlePretty e) Just $
          fixSmartDateStrEither' d' (T.pack v)
      | n == "period" =
        case
          either (\e -> usageError $ "could not parse period option: "++customErrorBundlePretty e) id $
          parsePeriodExpr d' (textStripQuotes $ T.pack v)
        of
          (_, DateSpan _ (Just e)) -> Just e
          _                        -> Nothing
      | otherwise = Nothing

-- | Get the report interval, if any, specified by the last of -p/--period,
-- -D/--daily, -W/--weekly, -M/--monthly etc. options.
-- An interval from --period counts only if it is explicitly defined.
intervalFromRawOpts :: RawOpts -> Interval
intervalFromRawOpts = lastDef NoInterval . collectopts intervalfromrawopt
  where
    intervalfromrawopt (n,v)
      | n == "period" =
          either
            (\e -> usageError $ "could not parse period option: "++customErrorBundlePretty e)
            extractIntervalOrNothing $
            parsePeriodExpr
              (error' "intervalFromRawOpts: did not expect to need today's date here")  -- PARTIAL: should not happen; we are just getting the interval, which does not use the reference date
              (textStripQuotes $ T.pack v)
      | n == "daily"     = Just $ Days 1
      | n == "weekly"    = Just $ Weeks 1
      | n == "monthly"   = Just $ Months 1
      | n == "quarterly" = Just $ Quarters 1
      | n == "yearly"    = Just $ Years 1
      | otherwise = Nothing

-- | Extract the interval from the parsed -p/--period expression.
-- Return Nothing if an interval is not explicitly defined.
extractIntervalOrNothing :: (Interval, DateSpan) -> Maybe Interval
extractIntervalOrNothing (NoInterval, _) = Nothing
extractIntervalOrNothing (interval, _) = Just interval

-- | Get the last interval specified in query opts, if any.
-- date: queries can specify a reporting interval.
intervalFromQueryOpts :: [QueryOpt] -> Maybe Interval
intervalFromQueryOpts = lastMay . mapMaybe getInterval
  where
    getInterval (QueryOptInterval i) = Just i
    getInterval _ = Nothing

-- | Get any statuses to be matched, as specified by -U/--unmarked,
-- -P/--pending, -C/--cleared flags. -UPC is equivalent to no flags,
-- so this returns a list of 0-2 unique statuses.
statusesFromRawOpts :: RawOpts -> [Status]
statusesFromRawOpts = simplifyStatuses . collectopts statusfromrawopt
  where
    statusfromrawopt (n,_)
      | n == "unmarked"  = Just Unmarked
      | n == "pending"   = Just Pending
      | n == "cleared"   = Just Cleared
      | otherwise        = Nothing

-- | Reduce a list of statuses to just one of each status,
-- and if all statuses are present return the empty list.
simplifyStatuses l
  | length l' >= numstatuses = []
  | otherwise                = l'
  where
    l' = nubSort l
    numstatuses = length [minBound .. maxBound :: Status]

-- | Add/remove this status from the status list. Used by hledger-ui.
reportOptsToggleStatus s ropts@ReportOpts{statuses_=ss}
  | s `elem` ss = ropts{statuses_=filter (/= s) ss}
  | otherwise   = ropts{statuses_=simplifyStatuses (s:ss)}

-- | Parse the type of valuation to be performed, if any, specified by -V,
-- -X/--exchange, or --value flags. If there's more than one valuation type,
-- the rightmost flag wins. This will fail with a usage error if an invalid
-- argument is passed to --value, or if --valuechange is called with a
-- valuation type other than -V/--value=end.
valuationTypeFromRawOpts :: RawOpts -> Maybe ValuationType
valuationTypeFromRawOpts rawopts = case (balancecalcopt rawopts, directval) of
    (CalcValueChange, Nothing       ) -> Just $ AtEnd Nothing  -- If no valuation requested for valuechange, use AtEnd
    (CalcValueChange, Just (AtEnd _)) -> directval             -- If AtEnd valuation requested, use it
    (CalcValueChange, _             ) -> usageError "--valuechange only produces sensible results with --value=end"
    (CalcGain,        Nothing       ) -> Just $ AtEnd Nothing  -- If no valuation requested for gain, use AtEnd
    (_,               _             ) -> directval             -- Otherwise, use requested valuation
  where
    directval = lastMay $ collectopts valuationfromrawopt rawopts
    valuationfromrawopt (n,v)  -- option name, value
      | n == "V"     = Just $ AtEnd Nothing
      | n == "X"     = Just $ AtEnd (Just $ T.pack v)
      | n == "value" = valueopt v
      | otherwise    = Nothing
    valueopt v
      | t `elem` ["cost","c"]  = AtEnd . Just <$> mc  -- keep supporting --value=cost,COMM for now
      | t `elem` ["then" ,"t"] = Just $ AtThen mc
      | t `elem` ["end" ,"e"]  = Just $ AtEnd  mc
      | t `elem` ["now" ,"n"]  = Just $ AtNow  mc
      | otherwise = case parsedate t of
            Just d  -> Just $ AtDate d mc
            Nothing -> usageError $ "could not parse \""++t++"\" as valuation type, should be: then|end|now|t|e|n|YYYY-MM-DD"
      where
        -- parse --value's value: TYPE[,COMM]
        (t,c') = break (==',') v
        mc     = case drop 1 c' of
                   "" -> Nothing
                   c  -> Just $ T.pack c

-- | Parse the type of costing to be performed, if any, specified by -B/--cost
-- or --value flags. If there's more than one costing type, the rightmost flag
-- wins. This will fail with a usage error if an invalid argument is passed to
-- --cost or if a costing type is requested with --gain.
conversionOpFromRawOpts :: RawOpts -> Maybe ConversionOp
conversionOpFromRawOpts rawopts
    | isJust costFlag && balancecalcopt rawopts == CalcGain = usageError "--gain cannot be combined with --cost"
    | otherwise = costFlag
  where
    costFlag = lastMay $ collectopts conversionopfromrawopt rawopts
    conversionopfromrawopt (n,v)  -- option name, value
      | n == "B"                                    = Just ToCost
      | n == "value", takeWhile (/=',') v `elem` ["cost", "c"] = Just ToCost  -- keep supporting --value=cost for now
      | otherwise                                   = Nothing

-- | Parse the depth arguments. This can be either a flat depth that applies to
-- all accounts, or a regular expression and depth, which only matches certain
-- accounts. If an account name is matched by a regular expression, then the
-- smallest depth is used. Otherwise, if no regular expressions match, then the
-- flat depth is used. If more than one flat depth is supplied, use only the
-- last one.
depthFromRawOpts :: RawOpts -> DepthSpec
depthFromRawOpts rawopts = lastDef mempty flats <> mconcat regexps
  where
    (flats, regexps) = partition (\(DepthSpec f rs) -> isJust f && null rs) depthSpecs
    depthSpecs = case mapM (parseDepthSpec . T.pack) depths of
      Right d -> d
      Left err -> usageError $ "Unable to parse depth specification: " ++ err
    depths = listofstringopt "depth" rawopts

-- | Select the Transaction date accessor based on --date2.
transactionDateFn :: ReportOpts -> (Transaction -> Day)
transactionDateFn ReportOpts{..} = if date2_ then transactionDate2 else tdate

-- | Select the Posting date accessor based on --date2.
postingDateFn :: ReportOpts -> (Posting -> Day)
postingDateFn ReportOpts{..} = if date2_ then postingDate2 else postingDate

-- | Report which date we will report on based on --date2.
whichDate :: ReportOpts -> WhichDate
whichDate ReportOpts{..} = if date2_ then SecondaryDate else PrimaryDate

-- | Legacy-compatible convenience aliases for accountlistmode_.
tree_ :: ReportOpts -> Bool
tree_ ReportOpts{accountlistmode_ = ALTree} = True
tree_ ReportOpts{accountlistmode_ = ALFlat} = False

flat_ :: ReportOpts -> Bool
flat_ = not . tree_

-- depthFromOpts :: ReportOpts -> Int
-- depthFromOpts opts = min (fromMaybe 99999 $ depth_ opts) (queryDepth $ queryFromOpts nulldate opts)

-- | Convert a 'Journal''s amounts to cost and/or to value (see
-- 'journalApplyValuationFromOpts'), and filter by the 'ReportSpec' 'Query'.
--
-- We make sure to first filter by amt: and cur: terms, then value the
-- 'Journal', then filter by the remaining terms.
journalValueAndFilterPostings :: ReportSpec -> Journal -> Journal
journalValueAndFilterPostings rspec j =
  -- dbg4With (\j2 -> "valuedfilteredj" <> pshow (jtxns j2)) $
  journalValueAndFilterPostingsWith rspec j priceoracle
  where priceoracle = journalPriceOracle (infer_prices_ $ _rsReportOpts rspec) j

{- [Querying before valuation]
This helper is used by multiBalanceReport (all balance reports).
Previously, at least since #1625 (2021), it was filtering with the cur:/amt: parts
of the query before valuation, and with the other parts after valuation.
Now, since #2387 (2025), it does all filtering before valuation.
This avoids breaking boolean queries (#2371), avoids a strictness bug (#2385),
is simpler, and we think it's otherwise equivalent.
-}
-- | Like 'journalValueAndFilterPostings', but takes a 'PriceOracle' as an argument.
journalValueAndFilterPostingsWith :: ReportSpec -> Journal -> PriceOracle -> Journal
journalValueAndFilterPostingsWith = _journalValueAndFilterPostingsWith1431

-- 1.42
-- #2371 This goes wrong with complex boolean queries, splitting them apart in a lossy way.
-- _journalValueAndFilterPostingsWith142 rspec@ReportSpec{_rsQuery=q, _rsReportOpts=ropts} j =
--     -- Third, filter by the non amt:/cur: parts of the query
--       filterJournalPostings' reportq
--     -- Second, apply valuation and costing
--     . journalApplyValuationFromOptsWith rspec
--     -- First, filter by the amt:/cur: parts of the query, so they match pre-valuation amounts
--       (if queryIsNull amtsymq then j else filterJournalAmounts amtsymq j)
--   where
--     -- with -r, replace each posting with its sibling postings
--     filterJournalPostings' = if related_ ropts then filterJournalRelatedPostings else filterJournalPostings
--     amtsymq = dbg1 "amtsymq" $ filterQuery queryIsAmtOrCurOrSym q
--     reportq = dbg1 "reportq" $ filterQuery (not . queryIsAmtOrCurOrSym) q

-- 1.43
-- XXX #2396 This goes wrong with cur:. filterJournal*Postings keep all postings containing the matched commodity,
-- but do not remove the unmatched commodities from multicommodity postings, as filterJournalAmounts would.
-- _journalValueAndFilterPostingsWith143 rspec@ReportSpec{_rsQuery = q, _rsReportOpts = ropts} =
--   journalApplyValuationFromOptsWith rspec .
--   dbg1With (\j1 -> "j1" <> pshow (jtxns j1)) .
--   (if related_ ropts then filterJournalRelatedPostings else filterJournalPostings) q

-- 1.43.1
_journalValueAndFilterPostingsWith1431 rspec@ReportSpec{_rsQuery = q, _rsReportOpts = ropts} =
  journalApplyValuationFromOptsWith rspec . filterjournal q
  where
    filterjournal q2 =
      filterJournalAmounts (filterQuery queryIsAmtOrCurOrSym q2) .  -- an extra amount filtering pass for #2396
      (if related_ ropts then filterJournalRelatedPostings q2 else filterJournalPostings q2)

-- | Convert this journal's postings' amounts to cost and/or to value, if specified
-- by options (-B/--cost/-V/-X/--value etc.). Strip prices if not needed. This
-- should be the main stop for performing costing and valuation. The exception is
-- whenever you need to perform valuation _after_ summing up amounts, as in a
-- historical balance report with --value=end. valuationAfterSum will check for this
-- condition.
journalApplyValuationFromOpts :: ReportSpec -> Journal -> Journal
journalApplyValuationFromOpts rspec j =
  journalApplyValuationFromOptsWith rspec j priceoracle
  where priceoracle = journalPriceOracle (infer_prices_ $ _rsReportOpts rspec) j

-- | Like journalApplyValuationFromOpts, but takes PriceOracle as an argument.
journalApplyValuationFromOptsWith :: ReportSpec -> Journal -> PriceOracle -> Journal
journalApplyValuationFromOptsWith rspec@ReportSpec{_rsReportOpts=ropts} j priceoracle =
  costfn j
  & journalMapPostings (\p -> p
    & dbg9With (lbl "before calc".showMixedAmountOneLine.pamount)
    & postingTransformAmount (calcfn p)
    & dbg9With (lbl (show calc).showMixedAmountOneLine.pamount)
    )
  where
    lbl = lbl_ "journalApplyValuationFromOptsWith"
    -- Which custom calculation to do for balance reports. For all other reports, it will be CalcChange.
    calc = balancecalc_ ropts
    calcfn = case calc of
      CalcGain -> \p -> maybe id (mixedAmountApplyGain      priceoracle styles (postingperiodend p) (_rsDay rspec) (postingDate p)) (value_ ropts)
      _        -> \p -> maybe id (mixedAmountApplyValuation priceoracle styles (postingperiodend p) (_rsDay rspec) (postingDate p)) (value_ ropts)
    costfn = case calc of
      CalcGain -> id
      _        -> journalToCost costop where costop = fromMaybe NoConversionOp $ conversionop_ ropts

    -- Find the "end" valuation date for this posting.
    -- With a report interval, this is the last day of the report subperiod containing this posting;
    -- with no interval it's the last date of the overall report period
    -- (which for an end value report may have been extended to include the latest non-future P directive).
    -- To get the period's last day, we subtract one from the (exclusive) period end date.
    postingperiodend = postingPeriodEnd . postingDateOrDate2 (whichDate ropts)
      where
        postingPeriodEnd d = fromMaybe err $ case interval_ ropts of
          NoInterval -> fmap (snd . dayPartitionStartEnd)    . snd $ reportSpan j rspec
          _          -> fmap (snd . dayPartitionFind d) . snd $ reportSpanBothDates j rspec
        -- Should never happen, because there are only invalid dayPartitions
        -- when there are no transactions, in which case this function is never called
        err = error' "journalApplyValuationFromOpts: expected all spans to have an end date"


    styles = journalCommodityStyles j

-- | Select the Account valuation functions required for performing valuation after summing
-- amounts. Used in MultiBalanceReport to value historical and similar reports.
mixedAmountApplyValuationAfterSumFromOptsWith :: ReportOpts -> Journal -> PriceOracle
                                              -> (Day -> MixedAmount -> MixedAmount)
mixedAmountApplyValuationAfterSumFromOptsWith ropts j priceoracle =
  case valuationAfterSum ropts of
    Nothing -> const id
    Just mc -> case balancecalc_ ropts of
      CalcGain -> mixedAmountGainAtDate  priceoracle styles mc
      _        -> mixedAmountValueAtDate priceoracle styles mc
  where styles = journalCommodityStyles j

-- | If the ReportOpts specify that we are performing valuation after summing amounts,
-- return Just of the commodity symbol we're converting to, Just Nothing for the default,
-- and otherwise return Nothing.
-- Used for example with historical reports with --value=end.
valuationAfterSum :: ReportOpts -> Maybe (Maybe CommoditySymbol)
valuationAfterSum ropts = case value_ ropts of
    Just (AtEnd mc) | requiresHistorical ropts -> Just mc
    _                                          -> Nothing

-- | If the ReportOpts specify that we will need to consider historical
-- postings, either because this is a historical report, or because the
-- valuation strategy requires historical amounts.
requiresHistorical :: ReportOpts -> Bool
requiresHistorical ReportOpts{balanceaccum_ = accum, balancecalc_ = calc} =
    accum == Historical || calc == CalcValueChange || calc == CalcGain

-- | Convert report options to a query, ignoring any non-flag command line arguments.
queryFromFlags :: ReportOpts -> Query
queryFromFlags ReportOpts{..} = simplifyQuery $ And flagsq
  where
    flagsq = consIf   Real  real_
           . consJust Depth flatDepth
           $ map (uncurry DepthAcct) regexpDepths
           ++  [ (if date2_ then Date2 else Date) $ periodAsDateSpan period_
               , Or $ map StatusQ statuses_
               ]
    consIf f b = if b then (f True:) else id
    DepthSpec flatDepth regexpDepths = depth_
    consJust f = maybe id ((:) . f)

-- Methods/types needed for --sort argument

-- Possible arguments taken by the --sort command
-- Each of these takes a bool, which shows if it has been inverted
-- (True -> has been inverted, reverse the order)
data SortField
    = AbsAmount' Bool
    | Account' Bool
    | Amount' Bool
    | Date' Bool
    | Description' Bool
    deriving (Show, Eq)
type SortSpec = [SortField]

-- By default, sort by date in ascending order
defsortspec :: SortSpec
defsortspec = [Date' False]

-- Load a SortSpec from the argument given to --sort
-- If there is no spec given, then sort by [Date' False] by default
getSortSpec :: RawOpts -> SortSpec
getSortSpec opts = 
    let opt = maybestringopt "sort" opts
        optParser s = 
          let terms = map strip $ splitAtElement ',' s 
              termParser t = case trimmed of
                "date"        -> Date'        isNegated
                "desc"        -> Description' isNegated
                "description" -> Description' isNegated
                "account"     -> Account'     isNegated
                "amount"      -> Amount'      isNegated
                "absamount"   -> AbsAmount'   isNegated
                _ -> error' $ "unknown --sort key " ++ t ++ ". Supported keys are: " <> sortKeysDescription <> "."
                where isNegated = isPrefixOf "-" t
                      trimmed = fromMaybe t (stripPrefix "-" t)
          in map termParser terms
    in maybe defsortspec optParser opt 

-- for option's help and parse error message
sortKeysDescription = "date, desc, account, amount, absamount"  -- 'description' is also accepted

-- Report dates.

-- | The effective report span is the start and end dates requested by options or queries.
-- If the start date is unspecified, the earliest transaction or posting date is used.
-- If the end date is unspecified, the latest transaction or posting date
-- (or non-future market price date, when doing an end value report) is used.
-- If none of these things are present, the null date span is returned.
-- The report sub-periods caused by a report interval, if any, are also returned.
reportSpan :: Journal -> ReportSpec -> (DateSpan, Maybe DayPartition)
reportSpan = reportSpanHelper False
-- Note: In end value reports, the report end date and valuation date are the same.
-- If valuation date ever needs to be different, journalApplyValuationFromOptsWith is the place.

-- | Like reportSpan, but considers both primary and secondary dates, not just one or the other.
reportSpanBothDates :: Journal -> ReportSpec -> (DateSpan, Maybe DayPartition)
reportSpanBothDates = reportSpanHelper True

reportSpanHelper :: Bool -> Journal -> ReportSpec -> (DateSpan, Maybe DayPartition)
reportSpanHelper bothdates j ReportSpec{_rsQuery=query, _rsReportOpts=ropts, _rsDay=today} =
    (enlargedreportspan, intervalspans)
  where
    -- The date span specified by -b/-e/-p options and query args if any.
    requestedspan = dbg3 "requestedspan" $
      if bothdates then queryDateSpan' query else queryDateSpan (date2_ ropts) query

    -- If the requested span has open ends, fill them with defaults.
    reportspan = dbg3 "reportspan" $ requestedspan `spanValidDefaultsFrom` txnsorpricespan
      where
        txnsorpricespan = dbg3 "txnsorpricespan" $ DateSpan mfirsttxn mlatesttxnorprice
          where
            DateSpan mfirsttxn mlasttxn = dbg3 "txnsspan" $
              if bothdates then journalDateSpanBothDates j else journalDateSpan (date2_ ropts) j
            mlatesttxnorprice =
              case value_ ropts of
                Just (AtEnd _) -> mlasttxn `max` mlatestnonfutureprice
                _              -> mlasttxn
              where
                mlatestnonfutureprice = dbg3 "latestnonfutureprice" $ -- #2445
                  fmap (Exact . addDays 1) . maximumMay . filter (not . (> today)) . map pddate $ jpricedirectives j

    -- The list of interval spans enclosing the requested span.
    -- This list can be empty if the journal was empty,
    -- or if hledger-ui has added its special date:-tomorrow to the query
    -- and all txns are in the future.
    intervalspans = dbg3 "intervalspans" $ splitSpan adjust (interval_ ropts) reportspan
      where
        -- When calculating report periods, we will adjust the start date back to the nearest interval boundary
        -- unless a start date was specified explicitly.
        adjust = isNothing $ spanStart requestedspan

    -- The requested span enlarged to enclose a whole number of intervals.
    -- This can be the null span if there were no intervals.
    enlargedreportspan = dbg3 "enlargedreportspan" $
        maybe (DateSpan Nothing Nothing) (mkSpan . dayPartitionStartEnd) intervalspans
      where mkSpan (s, e) = DateSpan (Just $ Exact s) (Just . Exact $ addDays 1 e)

reportStartDate :: Journal -> ReportSpec -> Maybe Day
reportStartDate j = spanStart . fst . reportSpan j

reportEndDate :: Journal -> ReportSpec -> Maybe Day
reportEndDate j = spanEnd . fst . reportSpan j

-- Some pure alternatives to the above. XXX review/clean up

-- Get the report's start date.
-- If no report period is specified, will be Nothing.
reportPeriodStart :: ReportSpec -> Maybe Day
reportPeriodStart = queryStartDate False . _rsQuery

-- Get the report's start date, or if no report period is specified,
-- the journal's start date (the earliest posting date). If there's no
-- report period and nothing in the journal, will be Nothing.
reportPeriodOrJournalStart :: ReportSpec -> Journal -> Maybe Day
reportPeriodOrJournalStart rspec j =
  reportPeriodStart rspec <|> journalStartDate False j

-- Get the last day of the overall report period.
-- This the inclusive end date (one day before the
-- more commonly used, exclusive, report end date).
-- If no report period is specified, will be Nothing.
reportPeriodLastDay :: ReportSpec -> Maybe Day
reportPeriodLastDay = fmap (addDays (-1)) . queryEndDate False . _rsQuery

-- Get the last day of the overall report period, or if no report
-- period is specified, the last day of the journal (ie the latest
-- posting date). If we're doing period-end valuation, include price
-- directive dates. If there's no report period and nothing in the
-- journal, will be Nothing.
reportPeriodOrJournalLastDay :: ReportSpec -> Journal -> Maybe Day
reportPeriodOrJournalLastDay rspec j = reportPeriodLastDay rspec <|> journalOrPriceEnd
  where
    journalOrPriceEnd = case value_ $ _rsReportOpts rspec of
        Just (AtEnd _) -> max (journalLastDay False j) lastPriceDirective
        _              -> journalLastDay False j
    lastPriceDirective = fmap (addDays 1) . maximumMay . map pddate $ jpricedirectives j

-- | Make a name for the given period in a multiperiod report, given
-- the type of balance being reported and the full set of report
-- periods. This will be used as a column heading (or row heading, in
-- a register summary report). We try to pick a useful name as follows:
--
-- - ending-balance reports: the period's end date
--
-- - balance change reports where the periods are months and all in the same year:
--   the short month name in the current locale
--
-- - all other balance change reports: a description of the datespan,
--   abbreviated to compact form if possible (see showDateSpan).
reportPeriodName :: PeriodTitles -> BalanceAccumulation -> [DateSpan] -> DateSpan -> T.Text
reportPeriodName ph balanceaccumulation spans =
  case balanceaccumulation of
    PerPeriod -> case ph of
      PTDates   -> showDateSpanFull
      PTCompact -> if multiyear then showDateSpan else showDateSpanAbbrev
      where
        multiyear = (>1) $ length $ nubSort $ map spanStartYear spans
    _ -> maybe "" (showDate . prevday) . spanEnd

-- lenses

-- Reportable functors are so that we can create special lenses which can fail
-- and report on their failure.
class Functor f => Reportable f e where
    report :: a -> f (Either e a) -> f a

instance Reportable (Const r) e where
    report _ (Const x) = Const x

instance Reportable Identity e where
    report a (Identity i) = Identity $ fromRight a i

instance Reportable Maybe e where
    report _ = (eitherToMaybe =<<)

instance (e ~ a) => Reportable (Either a) e where
    report _ = join

-- | Apply a function over a lens, but report on failure.
overEither :: ((a -> Either e b) -> s -> Either e t) -> (a -> b) -> s -> Either e t
overEither l f = l (pure . f)

-- | Set a field using a lens, but report on failure.
setEither :: ((a -> Either e b) -> s -> Either e t) -> b -> s -> Either e t
setEither l = overEither l . const

type ReportableLens' s a = forall f. Reportable f String => (a -> f a) -> s -> f s

-- | Lenses for ReportOpts.

-- Implement HasReportOptsNoUpdate, the basic lenses for ReportOpts.
makeHledgerClassyLenses ''ReportOpts
makeHledgerClassyLenses ''ReportSpec

-- | Special lenses for ReportOpts which also update the Query and QueryOpts in ReportSpec.
-- Note that these are not true lenses, as they have a further restriction on
-- the functor. This will work as a normal lens for all common uses, but since they
-- don't obey the lens laws for some fancy cases, they may fail in some exotic circumstances.
--
-- Note that setEither/overEither should only be necessary with
-- querystring and reportOpts: the other lenses should never fail.
--
-- === Examples:
-- >>> import Lens.Micro (set)
-- >>> _rsQuery <$> setEither querystring ["assets"] defreportspec
-- Right (Acct (RegexpCI "assets"))
-- >>> _rsQuery <$> setEither querystring ["(assets"] defreportspec
-- Left "This regular expression is invalid or unsupported, please correct it: (assets"
-- >>> _rsQuery $ set querystring ["assets"] defreportspec
-- Acct (RegexpCI "assets")
-- >>> _rsQuery $ set period (MonthPeriod 2021 08) defreportspec
-- Date DateSpan 2021-08
--
-- XXX testing error output isn't working since adding color to it:
-- > import System.Environment
-- > setEnv "NO_COLOR" "1" >> return (_rsQuery $ set querystring ["(assets"] defreportspec)
-- *** Exception: Error: Updating ReportSpec failed: try using overEither instead of over or setEither instead of set
class HasReportOptsNoUpdate a => HasReportOpts a where
    reportOpts :: ReportableLens' a ReportOpts
    reportOpts = reportOptsNoUpdate
    {-# INLINE reportOpts #-}

    -- XXX these names are a bit clashy

    period :: ReportableLens' a Period
    period = reportOpts.periodNoUpdate
    {-# INLINE period #-}

    statuses :: ReportableLens' a [Status]
    statuses = reportOpts.statusesNoUpdate
    {-# INLINE statuses #-}

    depth :: ReportableLens' a DepthSpec
    depth = reportOpts.depthNoUpdate
    {-# INLINE depth #-}

    date2 :: ReportableLens' a Bool
    date2 = reportOpts.date2NoUpdate
    {-# INLINE date2 #-}

    real :: ReportableLens' a Bool
    real = reportOpts.realNoUpdate
    {-# INLINE real #-}

    querystring :: ReportableLens' a [T.Text]
    querystring = reportOpts.querystringNoUpdate
    {-# INLINE querystring #-}

instance HasReportOpts ReportOpts

instance HasReportOptsNoUpdate ReportSpec where
    reportOptsNoUpdate = rsReportOpts

instance HasReportOpts ReportSpec where
    reportOpts f rspec = report (error' "Updating ReportSpec failed: try using overEither instead of over or setEither instead of set") $  -- PARTIAL:
      reportOptsToSpec (_rsDay rspec) <$> f (_rsReportOpts rspec)
    {-# INLINE reportOpts #-}

-- | Generate a ReportSpec from a set of ReportOpts on a given day.
reportOptsToSpec :: Day -> ReportOpts -> Either String ReportSpec
reportOptsToSpec day ropts = do
    (argsquery, queryopts) <- parseQueryList day $ querystring_ ropts
    -- If there's an interval in the query opts, it overrides the interval from -p/--period/etc
    let ropts' = case intervalFromQueryOpts queryopts of
                   Just i  -> ropts{interval_=i}
                   Nothing -> ropts
    return ReportSpec
      { _rsReportOpts = ropts'
      , _rsDay        = day
      , _rsQuery      = simplifyQuery $ And [queryFromFlags ropts', argsquery]
      , _rsQueryOpts  = queryopts
      }

-- | Update the ReportOpts and the fields derived from it in a ReportSpec,
-- or return an error message if there is a problem such as missing or
-- unparseable options data. This is the safe way to change a ReportSpec,
-- ensuring that all fields (_rsQuery, _rsReportOpts, querystring_, etc.) are in sync.
updateReportSpec :: ReportOpts -> ReportSpec -> Either String ReportSpec
updateReportSpec = setEither reportOpts

-- | Like updateReportSpec, but takes a ReportOpts-modifying function.
updateReportSpecWith :: (ReportOpts -> ReportOpts) -> ReportSpec -> Either String ReportSpec
updateReportSpecWith = overEither reportOpts

-- | Generate a ReportSpec from RawOpts and a provided day, or return an error
-- string if there are regular expression errors.
rawOptsToReportSpec :: Day -> Bool -> RawOpts -> Either String ReportSpec
rawOptsToReportSpec day coloronstdout = reportOptsToSpec day . rawOptsToReportOpts day coloronstdout

-- | Associate this journal with this ReportSpec, returning a refreshed
-- ReportSpec whose @_rsQuery@ is rebuilt from the user's @querystring_@
-- and has any @cur:@ terms expanded against the journal's current
-- commodity-alias declarations.
--
-- This is the canonical way to (re)attach a journal to a ReportSpec:
-- @querystring_@ is the source of truth, and @_rsQuery@ is a derived
-- cache that goes stale whenever the journal's commodity/alias
-- declarations change. Long-lived sessions (hledger-ui watch,
-- hledger-web) should call this on every reload.
reportSpecExpandCurQueries :: Journal -> ReportSpec -> Either String ReportSpec
reportSpecExpandCurQueries j rs = do
  rs' <- reportOptsToSpec (_rsDay rs) (_rsReportOpts rs)
  Right rs'{_rsQuery = queryExpandCurAliases j (_rsQuery rs')}
