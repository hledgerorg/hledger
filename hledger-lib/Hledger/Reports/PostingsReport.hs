{-|

Postings report, used by the register command.

-}

{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections       #-}

module Hledger.Reports.PostingsReport (
  PostingsReport,
  PostingsReportItem,
  postingsReport,
  mkpostingsReportItem,
  SortSpec,
  defsortspec,

  -- * Tests
  tests_PostingsReport
)
where

import Data.List (sortBy, sortOn)
import qualified Data.Map.Strict as M
import Data.Maybe (isJust, isNothing, fromMaybe)
import Data.Ord
import Data.Text (Text)
import Data.Time.Calendar (Day)
import Safe (headMay)

import Hledger.Data
import Hledger.Query
import Hledger.Utils
import Hledger.Reports.ReportOptions


-- | A postings report is a list of postings with a running total, and a little extra
-- transaction info to help with rendering.
-- This is used eg for the register command.
type PostingsReport = [PostingsReportItem] -- line items, one per posting
type PostingsReportItem = (Maybe Day     -- The posting date, if this is the first posting in a
                                         -- transaction or if it's different from the previous
                                         -- posting's date. Or if this a summary posting, the
                                         -- report interval's start date if this is the first
                                         -- summary posting in the interval.
                          ,Maybe Period  -- If this is a summary posting, the report interval's period.
                          ,Maybe Text    -- The posting's transaction's description, if this is the first posting in the transaction.
                          ,Posting       -- The posting, possibly with the account name depth-clipped.
                          ,MixedAmount   -- The running total after this posting, or with --average,
                                         -- the running average posting amount. With --historical,
                                         -- postings before the report start date are included in
                                         -- the running total/average.
                          )

instance HasAmounts PostingsReportItem where
  styleAmounts styles (a,b,c,d,e) = (a,b,c,styleAmounts styles d,styleAmounts styles e)

-- | A summary posting summarises the activity in one account within a report
-- interval. It is by a regular Posting with no description, the interval's
-- start date stored as the posting date, and the interval's Period attached
-- with a tuple.
type SummaryPosting = (Posting, Period)

-- | Select postings from the journal and add running balance and other
-- information to make a postings report. Used by eg hledger's register command.
postingsReport :: ReportSpec -> Journal -> PostingsReport
postingsReport rspec@ReportSpec{_rsReportOpts=ropts@ReportOpts{..}} j = items
    where
      (reportspan, colspans) = reportSpanBothDates j rspec
      whichdate   = whichDate ropts
      depthSpec   = queryDepth $ _rsQuery rspec
      multiperiod = interval_ /= NoInterval

      -- postings to be included in the report, and similarly-matched postings before the report start date
      (precedingps, reportps) = matchedPostingsBeforeAndDuring rspec j reportspan

      -- Postings, or summary postings with their subperiod's end date, to be displayed.
      displayps :: [(Posting, Maybe Period)]
        | multiperiod = [(p', Just period') | (p', period') <- summariseps reportps]
        | otherwise   = [(p', Nothing) | p' <- reportps]
        where
          summariseps = summarisePostingsByInterval whichdate depthSpec showempty colspans
          showempty = empty_ || average_

      sortedps = if sortspec_ /= defsortspec then sortPostings ropts sortspec_ displayps else displayps

      -- Posting report items ready for display.
      items =
        dbg4 "postingsReport items" $
        postingsReportItems postings (nullposting,Nothing) whichdate depthSpec startbal runningcalc startnum
        where
          -- In historical mode we'll need a starting balance, which we
          -- may be converting to value per hledger_options.m4.md "Effect
          -- of --value on reports".
          -- XXX balance report doesn't value starting balance.. should this ?
          historical = balanceaccum_ == Historical
          startbal | average_  = if historical then precedingavg else nullmixedamt
                   | otherwise = if historical then precedingsum else nullmixedamt
            where
              precedingsum = sumPostings precedingps
              precedingavg = divideMixedAmount (fromIntegral $ length precedingps) precedingsum

          runningcalc = registerRunningCalculationFn ropts
          startnum = if historical then length precedingps + 1 else 1
          postings | historical = if sortspec_ /= defsortspec 
                        then error' "--historical and --sort should not be used together" 
                        else sortedps
                   | otherwise = sortedps

-- | Based on the given report options, return a function that does the appropriate
-- running calculation for the register report, ie a running average or running total.
-- This function will take the item number, previous average/total, and new posting amount,
-- and return the new average/total.
registerRunningCalculationFn :: ReportOpts -> (Int -> MixedAmount -> MixedAmount -> MixedAmount)
registerRunningCalculationFn ropts
  | average_ ropts = \i avg amt -> avg `maPlus` divideMixedAmount (fromIntegral i) (amt `maMinus` avg)
  | otherwise      = \_ bal amt -> bal `maPlus` amt

-- | Sort two postings by the current list of value expressions (given in SortSpec).
comparePostings :: ReportOpts -> SortSpec -> (Posting, Maybe Period) -> (Posting, Maybe Period) -> Ordering
comparePostings _ [] _ _ = EQ
comparePostings ropts (ex:es) (a, pa) (b, pb) = 
    let 
    getDescription p = 
        let tx = ptransaction p 
            description = fmap (\t -> tdescription t) tx
        -- If there's no transaction attached, then use empty text for the description
        in fromMaybe "" description
    comparison = case ex of
          AbsAmount' False -> compare (abs (pamount a)) (abs (pamount b))
          Amount' False -> compare (pamount a) (pamount b)
          Account' False -> compare (paccount a) (paccount b)
          Date' False -> compare (postingDateOrDate2 (whichDate ropts) a) (postingDateOrDate2 (whichDate ropts) b)
          Description' False -> compare (getDescription a) (getDescription b)
          AbsAmount' True -> compare (Down (abs (pamount a))) (Down (abs (pamount b)))
          Amount' True -> compare (Down (pamount a)) (Down (pamount b))
          Account' True -> compare (Down (paccount a)) (Down (paccount b))
          Date' True -> compare (Down (postingDateOrDate2 (whichDate ropts) a)) (Down (postingDateOrDate2 (whichDate ropts) b))
          Description' True -> compare (Down (getDescription a)) (Down (getDescription b))
    in 
    if comparison == EQ then comparePostings ropts es (a, pa) (b, pb) else comparison

-- | Sort postings by the current SortSpec.
sortPostings :: ReportOpts -> SortSpec -> [(Posting, Maybe Period)] -> [(Posting, Maybe Period)]
sortPostings ropts sspec = sortBy (comparePostings ropts sspec)

-- | Find postings matching a given query, within a given date span,
-- and also any similarly-matched postings before that date span.
-- Date restrictions and depth restrictions in the query are ignored.
-- A helper for the postings report.
matchedPostingsBeforeAndDuring :: ReportSpec -> Journal -> DateSpan -> ([Posting],[Posting])
matchedPostingsBeforeAndDuring rspec@ReportSpec{_rsReportOpts=ropts,_rsQuery=q} j reportspan =
    dbg5 "beforeps, duringps" $ span (beforestartq `matchesPosting`) beforeandduringps
  where
    beforestartq = dbg3 "beforestartq" $ dateqtype $ DateSpan Nothing (Exact <$> spanStart reportspan)
    beforeandduringps =
        sortOn (postingDateOrDate2 (whichDate ropts))            -- sort postings by date or date2
      . (if invert_ ropts then map postingNegateMainAmount else id)  -- with --invert, invert amounts
      . filter hasAmount                                         -- omit postings with no definite amount (#2571)
      . journalPostings
      -- With most calls we will not require transaction prices past this point, and can get a big
      -- speed improvement by stripping them early. In some cases, such as in hledger-ui, we still
      -- want to keep prices around, so we can toggle between cost and no cost quickly. We can use
      -- the show_costs_ flag to be efficient when we can, and detailed when we have to.
      . (if show_costs_ ropts then id else journalMapPostingAmounts mixedAmountStripCosts)
      $ journalValueAndFilterPostings rspec{_rsQuery=beforeandduringq} j

    -- filter postings by the query, with no start date or depth limit
    beforeandduringq = dbg4 "beforeandduringq" $ And [depthless $ dateless q, beforeendq]
      where
        depthless  = filterQuery (not . queryIsDepth)
        dateless   = filterQuery (not . queryIsDateOrDate2)
        beforeendq = dateqtype $ DateSpan Nothing (Exact <$> spanEnd reportspan)

    dateqtype = if queryIsDate2 dateq || (queryIsDate dateq && date2_ ropts) then Date2 else Date
      where
        dateq = dbg4 "matchedPostingsBeforeAndDuring dateq" $ filterQuery queryIsDateOrDate2 $ dbg4 "matchedPostingsBeforeAndDuring q" q  -- XXX confused by multiple date:/date2: ?

-- | Generate postings report line items from a list of postings or (with
-- non-Nothing periods attached) summary postings.
postingsReportItems :: [(Posting,Maybe Period)] -> (Posting,Maybe Period) -> WhichDate -> DepthSpec -> MixedAmount -> (Int -> MixedAmount -> MixedAmount -> MixedAmount) -> Int -> [PostingsReportItem]
postingsReportItems [] _ _ _ _ _ _ = []
postingsReportItems ((p,mperiod):ps) (pprev,mperiodprev) wd d b runningcalcfn itemnum =
    i:(postingsReportItems ps (p,mperiod) wd d b' runningcalcfn (itemnum+1))
  where
    i = mkpostingsReportItem showdate showdesc wd mperiod p' b'
    (showdate, showdesc) | isJust mperiod = (mperiod /= mperiodprev,          False)
                         | otherwise      = (isfirstintxn || isdifferentdate, isfirstintxn)
    isfirstintxn = ptransaction p /= ptransaction pprev
    isdifferentdate = case wd of PrimaryDate   -> postingDate p  /= postingDate pprev
                                 SecondaryDate -> postingDate2 p /= postingDate2 pprev
    -- Summary postings have already been clipped using their original account names.
    p' | isJust mperiod = p
       | otherwise = p{paccount= clipOrEllipsifyAccountName d $ paccount p}
    b' = runningcalcfn itemnum b $ pamount p

-- | Generate one postings report line item, containing the posting,
-- the current running balance, and optionally the posting date and/or
-- the transaction description.
mkpostingsReportItem :: Bool -> Bool -> WhichDate -> Maybe Period -> Posting -> MixedAmount -> PostingsReportItem
mkpostingsReportItem showdate showdesc wd mperiod p b =
  (if showdate then Just $ postingDateOrDate2 wd p else Nothing
  ,mperiod
  ,if showdesc then tdescription <$> ptransaction p else Nothing
  ,p
  ,b
  )

-- | Convert a list of postings into summary postings, one per interval,
-- aggregated to the specified depth if any.
-- Each summary posting will have a non-Nothing interval end date.
summarisePostingsByInterval :: WhichDate -> DepthSpec -> Bool -> Maybe DayPartition -> [Posting] -> [SummaryPosting]
summarisePostingsByInterval wd depthSpec showempty colspans =
    concatMap (\(s,ps) -> summarisePostingsInDateSpan s wd depthSpec showempty ps)
    -- Group postings into their columns. We try to be efficient, since
    -- there can possibly be a very large number of intervals (cf #1683)
    . groupByDateSpan showempty (postingDateOrDate2 wd) (maybeDayPartitionToDateSpans colspans)

-- | Given a date span (representing a report interval) and a list of
-- postings within it, aggregate the postings into one summary posting per
-- account. Each summary posting will have a non-Nothing interval end date.
--
-- When a depth argument is present, postings to accounts of greater
-- depth are also aggregated where possible. Postings clipped to depth 0
-- are aggregated into a posting with account name "...".
--
-- The showempty flag includes spans with no postings and also postings
-- with 0 amount.
--
summarisePostingsInDateSpan :: DateSpan -> WhichDate -> DepthSpec -> Bool -> [Posting] -> [SummaryPosting]
summarisePostingsInDateSpan spn@(DateSpan b e) wd depthSpec showempty ps
  | null ps && (isNothing b || isNothing e) = []
  | null ps && showempty = [(summaryp, dateSpanAsPeriod spn)]
  | otherwise = summarypes
  where
    postingdate = if wd == PrimaryDate then postingDate else postingDate2
    b' = maybe (maybe nulldate postingdate $ headMay ps) fromEFDay b
    summaryp = nullposting{pdate=Just b',paccount=clipOrEllipsifyAccountName depthSpec ""}
    summaryps = [summaryp{paccount=a,pamount=amount} | (a,amount) <- M.toAscList balances]
    summarypes = map (, dateSpanAsPeriod spn) $ (if showempty then id else filter (not . mixedAmountLooksZero . pamount)) summaryps
    -- Clip each posting before summing, so parent and child rows stay disjoint.
    balances = M.fromListWith (flip maPlus)
      [(clipOrEllipsifyAccountName depthSpec $ paccount p, pamount p) | p <- ps]


-- tests

tests_PostingsReport = testGroup "PostingsReport" [

   testCase "postingsReport" $ do
    let (query, journal) `gives` n = (length $ postingsReport defreportspec{_rsQuery=query} journal) @?= n
    -- with the query specified explicitly
    (Any, nulljournal) `gives` 0
    (Any, samplejournal) `gives` 13
    -- register --depth just clips account names
    (Depth 2, samplejournal) `gives` 13
    (And [Depth 1, StatusQ Cleared, Acct (toRegex' "expenses")], samplejournal) `gives` 2
    (And [And [Depth 1, StatusQ Cleared], Acct (toRegex' "expenses")], samplejournal) `gives` 2
    -- with query and/or command-line options
    (length $ postingsReport defreportspec samplejournal) @?= 13
    (length $ postingsReport defreportspec{_rsReportOpts=defreportopts{interval_=Months 1}} samplejournal) @?= 11
    (length $ postingsReport defreportspec{_rsReportOpts=defreportopts{interval_=Months 1, empty_=True}} samplejournal) @?= 20
    (length $ postingsReport defreportspec{_rsQuery=Acct $ toRegex' "assets:bank:checking"} samplejournal) @?= 5

     -- (defreportopts, And [Acct "a a", Acct "'b"], samplejournal2) `gives` 0
     -- [(Just (fromGregorian 2008 01 01,"income"),assets:bank:checking             $1,$1)
     -- ,(Nothing,income:salary                   $-1,0)
     -- ,(Just (2008-06-01,"gift"),assets:bank:checking             $1,$1)
     -- ,(Nothing,income:gifts                    $-1,0)
     -- ,(Just (2008-06-02,"save"),assets:bank:saving               $1,$1)
     -- ,(Nothing,assets:bank:checking            $-1,0)
     -- ,(Just (2008-06-03,"eat & shop"),expenses:food                    $1,$1)
     -- ,(Nothing,expenses:supplies                $1,$2)
     -- ,(Nothing,assets:cash                     $-2,0)
     -- ,(Just (2008-12-31,"pay off"),liabilities:debts                $1,$1)
     -- ,(Nothing,assets:bank:checking            $-1,0)

    {-
        let opts = defreportopts
        (postingsReportAsText opts $ postingsReport opts (queryFromOpts date1 opts) j) `is` unlines
         ["2008/01/01 income               assets:bank:checking             $1           $1"
         ,"                                income:salary                   $-1            0"
         ,"2008/06/01 gift                 assets:bank:checking             $1           $1"
         ,"                                income:gifts                    $-1            0"
         ,"2008/06/02 save                 assets:bank:saving               $1           $1"
         ,"                                assets:bank:checking            $-1            0"
         ,"2008/06/03 eat & shop           expenses:food                    $1           $1"
         ,"                                expenses:supplies                $1           $2"
         ,"                                assets:cash                     $-2            0"
         ,"2008/12/31 pay off              liabilities:debts                $1           $1"
         ,"                                assets:bank:checking            $-1            0"
         ]

      ,"postings report with cleared option" ~:
       do
        let opts = defreportopts{cleared_=True}
        j <- readJournal'' sample_journal_str
        (postingsReportAsText opts $ postingsReport opts (queryFromOpts date1 opts) j) `is` unlines
         ["2008/06/03 eat & shop           expenses:food                    $1           $1"
         ,"                                expenses:supplies                $1           $2"
         ,"                                assets:cash                     $-2            0"
         ,"2008/12/31 pay off              liabilities:debts                $1           $1"
         ,"                                assets:bank:checking            $-1            0"
         ]

      ,"postings report with uncleared option" ~:
       do
        let opts = defreportopts{uncleared_=True}
        j <- readJournal'' sample_journal_str
        (postingsReportAsText opts $ postingsReport opts (queryFromOpts date1 opts) j) `is` unlines
         ["2008/01/01 income               assets:bank:checking             $1           $1"
         ,"                                income:salary                   $-1            0"
         ,"2008/06/01 gift                 assets:bank:checking             $1           $1"
         ,"                                income:gifts                    $-1            0"
         ,"2008/06/02 save                 assets:bank:saving               $1           $1"
         ,"                                assets:bank:checking            $-1            0"
         ]

      ,"postings report sorts by date" ~:
       do
        j <- readJournal'' $ unlines
            ["2008/02/02 a"
            ,"  b  1"
            ,"  c"
            ,""
            ,"2008/01/01 d"
            ,"  e  1"
            ,"  f"
            ]
        let opts = defreportopts
        registerdates (postingsReportAsText opts $ postingsReport opts (queryFromOpts date1 opts) j) `is` ["2008/01/01","2008/02/02"]

      ,"postings report with account pattern" ~:
       do
        j <- samplejournal
        let opts = defreportopts{patterns_=["cash"]}
        (postingsReportAsText opts $ postingsReport opts (queryFromOpts date1 opts) j) `is` unlines
         ["2008/06/03 eat & shop           assets:cash                     $-2          $-2"
         ]

      ,"postings report with account pattern, case insensitive" ~:
       do
        j <- samplejournal
        let opts = defreportopts{patterns_=["cAsH"]}
        (postingsReportAsText opts $ postingsReport opts (queryFromOpts date1 opts) j) `is` unlines
         ["2008/06/03 eat & shop           assets:cash                     $-2          $-2"
         ]

      ,"postings report with display expression" ~:
       do
        j <- samplejournal
        let gives displayexpr =
                (registerdates (postingsReportAsText opts $ postingsReport opts (queryFromOpts date1 opts) j) `is`)
                    where opts = defreportopts
        "d<[2008/6/2]"  `gives` ["2008/01/01","2008/06/01"]
        "d<=[2008/6/2]" `gives` ["2008/01/01","2008/06/01","2008/06/02"]
        "d=[2008/6/2]"  `gives` ["2008/06/02"]
        "d>=[2008/6/2]" `gives` ["2008/06/02","2008/06/03","2008/12/31"]
        "d>[2008/6/2]"  `gives` ["2008/06/03","2008/12/31"]

      ,"postings report with period expression" ~:
       do
        j <- samplejournal
        let periodexpr `gives` dates = do
              j' <- samplejournal
              registerdates (postingsReportAsText opts $ postingsReport opts (queryFromOpts date1 opts) j') `is` dates
                  where opts = defreportopts{period_=Just $ parsePeriodExpr' date1 periodexpr}
        ""     `gives` ["2008/01/01","2008/06/01","2008/06/02","2008/06/03","2008/12/31"]
        "2008" `gives` ["2008/01/01","2008/06/01","2008/06/02","2008/06/03","2008/12/31"]
        "2007" `gives` []
        "june" `gives` ["2008/06/01","2008/06/02","2008/06/03"]
        "monthly" `gives` ["2008/01/01","2008/06/01","2008/12/01"]
        "quarterly" `gives` ["2008/01/01","2008/04/01","2008/10/01"]
        let opts = defreportopts{period_=Just $ parsePeriodExpr' date1 "yearly"}
        (postingsReportAsText opts $ postingsReport opts (queryFromOpts date1 opts) j) `is` unlines
         ["2008/01/01 - 2008/12/31         assets:bank:saving               $1           $1"
         ,"                                assets:cash                     $-2          $-1"
         ,"                                expenses:food                    $1            0"
         ,"                                expenses:supplies                $1           $1"
         ,"                                income:gifts                    $-1            0"
         ,"                                income:salary                   $-1          $-1"
         ,"                                liabilities:debts                $1            0"
         ]
        let opts = defreportopts{period_=Just $ parsePeriodExpr' date1 "quarterly"}
        registerdates (postingsReportAsText opts $ postingsReport opts (queryFromOpts date1 opts) j) `is` ["2008/01/01","2008/04/01","2008/10/01"]
        let opts = defreportopts{period_=Just $ parsePeriodExpr' date1 "quarterly",empty_=True}
        registerdates (postingsReportAsText opts $ postingsReport opts (queryFromOpts date1 opts) j) `is` ["2008/01/01","2008/04/01","2008/07/01","2008/10/01"]

      ]

      , "postings report with depth arg" ~:
       do
        j <- samplejournal
        let opts = defreportopts{depth_=Just 2}
        (postingsReportAsText opts $ postingsReport opts (queryFromOpts date1 opts) j) `is` unlines
         ["2008/01/01 income               assets:bank                      $1           $1"
         ,"                                income:salary                   $-1            0"
         ,"2008/06/01 gift                 assets:bank                      $1           $1"
         ,"                                income:gifts                    $-1            0"
         ,"2008/06/02 save                 assets:bank                      $1           $1"
         ,"                                assets:bank                     $-1            0"
         ,"2008/06/03 eat & shop           expenses:food                    $1           $1"
         ,"                                expenses:supplies                $1           $2"
         ,"                                assets:cash                     $-2            0"
         ,"2008/12/31 pay off              liabilities:debts                $1           $1"
         ,"                                assets:bank                     $-1            0"
         ]

    -}

  ,testCase "summarisePostingsByInterval" $
    summarisePostingsByInterval PrimaryDate (DepthSpec Nothing []) False Nothing [] @?= []

  -- ,tests_summarisePostingsInDateSpan = [
    --  "summarisePostingsInDateSpan" ~: do
    --   let gives (b,e,depth,showempty,ps) =
    --           (summarisePostingsInDateSpan (DateSpan b e) depth showempty ps `is`)
    --   let ps =
    --           [
    --            nullposting{lpdescription="desc",lpaccount="expenses:food:groceries",lpamount=mixedAmount (usd 1)}
    --           ,nullposting{lpdescription="desc",lpaccount="expenses:food:dining",   lpamount=mixedAmount (usd 2)}
    --           ,nullposting{lpdescription="desc",lpaccount="expenses:food",          lpamount=mixedAmount (usd 4)}
    --           ,nullposting{lpdescription="desc",lpaccount="expenses:food:dining",   lpamount=mixedAmount (usd 8)}
    --           ]
    --   ("2008/01/01","2009/01/01",0,9999,False,[]) `gives`
    --    []
    --   ("2008/01/01","2009/01/01",0,9999,True,[]) `gives`
    --    [
    --     nullposting{lpdate=fromGregorian 2008 01 01,lpdescription="- 2008/12/31"}
    --    ]
    --   ("2008/01/01","2009/01/01",0,9999,False,ts) `gives`
    --    [
    --     nullposting{lpdate=fromGregorian 2008 01 01,lpdescription="- 2008/12/31",lpaccount="expenses:food",          lpamount=mixedAmount (usd 4)}
    --    ,nullposting{lpdate=fromGregorian 2008 01 01,lpdescription="- 2008/12/31",lpaccount="expenses:food:dining",   lpamount=mixedAmount (usd 10)}
    --    ,nullposting{lpdate=fromGregorian 2008 01 01,lpdescription="- 2008/12/31",lpaccount="expenses:food:groceries",lpamount=mixedAmount (usd 1)}
    --    ]
    --   ("2008/01/01","2009/01/01",0,2,False,ts) `gives`
    --    [
    --     nullposting{lpdate=fromGregorian 2008 01 01,lpdescription="- 2008/12/31",lpaccount="expenses:food",lpamount=mixedAmount (usd 15)}
    --    ]
    --   ("2008/01/01","2009/01/01",0,1,False,ts) `gives`
    --    [
    --     nullposting{lpdate=fromGregorian 2008 01 01,lpdescription="- 2008/12/31",lpaccount="expenses",lpamount=mixedAmount (usd 15)}
    --    ]
    --   ("2008/01/01","2009/01/01",0,0,False,ts) `gives`
    --    [
    --     nullposting{lpdate=fromGregorian 2008 01 01,lpdescription="- 2008/12/31",lpaccount="",lpamount=mixedAmount (usd 15)}
    --    ]

 ]
