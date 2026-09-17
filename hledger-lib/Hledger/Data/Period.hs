{-|

Manipulate the time periods typically used for reports with Period,
a richer abstraction than DateSpan. See also Types and Dates.

-}

{-# LANGUAGE OverloadedStrings #-}

module Hledger.Data.Period (
   periodAsDateSpan
  ,dateSpanAsPeriod
  ,simplifyPeriod
  ,isLastDayOfMonth
  ,isStandardPeriod
  ,periodTextWidth
  ,showPeriod
  ,showPeriodAbbrev
  ,showPeriodAbbrevWith
  ,periodStart
  ,periodEnd
  ,periodNext
  ,periodPrevious
  ,periodNextIn
  ,periodPreviousIn
  ,periodMoveTo
  ,periodGrow
  ,periodShrink
  ,mondayBefore
  ,thursdayOfWeekContaining
  ,yearMonthContainingWeekStarting
  ,quarterContainingMonth
  ,firstMonthOfQuarter
  ,startOfFirstWeekInMonth
)
where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar
import Data.Time.Calendar.MonthDay
import Data.Time.Calendar.OrdinalDate
import Data.Time.Calendar.WeekDate
import Data.Time.Format
import Text.Printf

import Hledger.Data.Types

-- | Convert Periods to exact DateSpans.
--
-- >>> periodAsDateSpan (MonthPeriod 2000 1) == DateSpan (Just $ Flex $ fromGregorian 2000 1 1) (Just $ Flex $ fromGregorian 2000 2 1)
-- True
periodAsDateSpan :: Period -> DateSpan
periodAsDateSpan (DayPeriod d) = DateSpan (Just $ Exact d) (Just $ Exact $ addDays 1 d)
periodAsDateSpan (WeekPeriod b) = DateSpan (Just $ Flex b) (Just $ Flex $ addDays 7 b)
periodAsDateSpan (MonthPeriod y m) = DateSpan (Just $ Flex $ fromGregorian y m 1) (Just $ Flex $ fromGregorian y' m' 1)
  where
    (y',m') | m==12     = (y+1,1)
            | otherwise = (y,m+1)
periodAsDateSpan (QuarterPeriod y q) = DateSpan (Just $ Flex $ fromGregorian y m 1) (Just $ Flex $ fromGregorian y' m' 1)
  where
    (y', q') | q==4      = (y+1,1)
             | otherwise = (y,q+1)
    quarterAsMonth q2 = (q2-1) * 3 + 1
    m  = quarterAsMonth q
    m' = quarterAsMonth q'
periodAsDateSpan (YearPeriod y) = DateSpan (Just $ Flex $ fromGregorian y 1 1) (Just $ Flex $ fromGregorian (y+1) 1 1)
periodAsDateSpan (PeriodBetween b e) = DateSpan (Just $ Exact b) (Just $ Exact e)
periodAsDateSpan (PeriodFrom b) = DateSpan (Just $ Exact b) Nothing
periodAsDateSpan (PeriodTo e) = DateSpan Nothing (Just $ Exact e)
periodAsDateSpan (PeriodAll) = DateSpan Nothing Nothing

-- | Convert DateSpans to Periods.
--
-- >>> dateSpanAsPeriod $ DateSpan (Just $ Exact $ fromGregorian 2000 1 1) (Just $ Exact $ fromGregorian 2000 2 1)
-- MonthPeriod 2000 1
dateSpanAsPeriod :: DateSpan -> Period
dateSpanAsPeriod (DateSpan (Just b) (Just e)) = simplifyPeriod $ PeriodBetween (fromEFDay b) (fromEFDay e)
dateSpanAsPeriod (DateSpan (Just b) Nothing) = PeriodFrom (fromEFDay b)
dateSpanAsPeriod (DateSpan Nothing (Just e)) = PeriodTo (fromEFDay e)
dateSpanAsPeriod (DateSpan Nothing Nothing) = PeriodAll

-- | Convert PeriodBetweens to a more abstract period where possible.
--
-- >>> simplifyPeriod $ PeriodBetween (fromGregorian 1 1 1) (fromGregorian 2 1 1)
-- YearPeriod 1
-- >>> simplifyPeriod $ PeriodBetween (fromGregorian 2000 10 1) (fromGregorian 2001 1 1)
-- QuarterPeriod 2000 4
-- >>> simplifyPeriod $ PeriodBetween (fromGregorian 2000 2 1) (fromGregorian 2000 3 1)
-- MonthPeriod 2000 2
-- >>> simplifyPeriod $ PeriodBetween (fromGregorian 2016 7 25) (fromGregorian 2016 8 1)
-- WeekPeriod 2016-07-25
-- >>> simplifyPeriod $ PeriodBetween (fromGregorian 2000 1 1) (fromGregorian 2000 1 2)
-- DayPeriod 2000-01-01
-- >>> simplifyPeriod $ PeriodBetween (fromGregorian 2000 2 28) (fromGregorian 2000 3 1)
-- PeriodBetween 2000-02-28 2000-03-01
-- >>> simplifyPeriod $ PeriodBetween (fromGregorian 2000 2 29) (fromGregorian 2000 3 1)
-- DayPeriod 2000-02-29
-- >>> simplifyPeriod $ PeriodBetween (fromGregorian 2000 12 31) (fromGregorian 2001 1 1)
-- DayPeriod 2000-12-31
--
simplifyPeriod :: Period -> Period
simplifyPeriod (PeriodBetween b e) =
  case (toGregorian b, toGregorian e) of
    -- a year
    ((by,1,1), (ey,1,1))   | by+1==ey           -> YearPeriod by
    -- a half-year
    -- ((by,1,1), (ey,7,1))   | by==ey             ->
    -- ((by,7,1), (ey,1,1))   | by+1==ey           ->
    -- a quarter
    ((by,1,1), (ey,4,1))   | by==ey             -> QuarterPeriod by 1
    ((by,4,1), (ey,7,1))   | by==ey             -> QuarterPeriod by 2
    ((by,7,1), (ey,10,1))  | by==ey             -> QuarterPeriod by 3
    ((by,10,1), (ey,1,1))  | by+1==ey           -> QuarterPeriod by 4
    -- a month
    ((by,bm,1), (ey,em,1)) | by==ey && bm+1==em -> MonthPeriod by bm
    ((by,12,1), (ey,1,1))  | by+1==ey           -> MonthPeriod by 12
    -- a week (two successive mondays),
    -- YYYYwN ("week N of year YYYY")
    -- _ | let ((by,bw,bd), (ey,ew,ed)) = (toWeekDate from, toWeekDate to) in by==ey && fw+1==tw && bd==1 && ed==1 ->
    -- a week starting on a monday
    _ | let ((by,bw,bd), (ey,ew,ed)) = (toWeekDate b, toWeekDate (addDays (-1) e))
        in by==ey && bw==ew && bd==1 && ed==7   -> WeekPeriod b
    -- a day
    ((by,bm,bd), (ey,em,ed)) |
        (by==ey && bm==em && bd+1==ed) ||
        (by+1==ey && bm==12 && em==1 && bd==31 && ed==1) || -- crossing a year boundary
        (by==ey && bm+1==em && isLastDayOfMonth by bm bd && ed==1) -- crossing a month boundary
         -> DayPeriod b
    _ -> PeriodBetween b e
simplifyPeriod p = p

isLastDayOfMonth y m d =
  case m of
    1 -> d==31
    2 | isLeapYear y -> d==29
      | otherwise    -> d==28
    3 -> d==31
    4 -> d==30
    5 -> d==31
    6 -> d==30
    7 -> d==31
    8 -> d==31
    9 -> d==30
    10 -> d==31
    11 -> d==30
    12 -> d==31
    _ -> False

-- | Is this period a "standard" period, referencing a particular day, week, month, quarter, or year ?
-- Periods of other durations, or infinite duration, or not starting on a standard period boundary, are not.
isStandardPeriod = isStandardPeriod' . simplifyPeriod
  where
    isStandardPeriod' (DayPeriod _) = True
    isStandardPeriod' (WeekPeriod _) = True
    isStandardPeriod' (MonthPeriod _ _) = True
    isStandardPeriod' (QuarterPeriod _ _) = True
    isStandardPeriod' (YearPeriod _) = True
    isStandardPeriod' _ = False

-- | The width of a period of this type when displayed.
periodTextWidth :: Period -> Int
periodTextWidth = periodTextWidth' . simplifyPeriod
  where
    periodTextWidth' DayPeriod{}     = 10  -- 2021-01-01
    periodTextWidth' WeekPeriod{}    = 13  -- 2021-01-01W52
    periodTextWidth' MonthPeriod{}   = 7   -- 2021-01
    periodTextWidth' QuarterPeriod{} = 6   -- 2021Q1
    periodTextWidth' YearPeriod{}    = 4   -- 2021
    periodTextWidth' PeriodBetween{} = 22  -- 2021-01-01..2021-01-07
    periodTextWidth' PeriodFrom{}    = 12  -- 2021-01-01..
    periodTextWidth' PeriodTo{}      = 12  -- ..2021-01-01
    periodTextWidth' PeriodAll       = 2   -- ..

-- | Render a period as a compact display string suitable for user output.
--
-- >>> showPeriod (WeekPeriod (fromGregorian 2016 7 25))
-- "2016-W30"
-- >>> showPeriod (WeekPeriod (fromGregorian 2024 12 30))
-- "2025-W01"
showPeriod :: Period -> Text
showPeriod (DayPeriod b)       = T.pack $ formatTime defaultTimeLocale "%F" b              -- DATE
showPeriod (WeekPeriod b)      = T.pack $ y <> "-W" <> w                                   -- YYYY-Www
  where
    y = formatTime defaultTimeLocale "%0Y" $ thursdayOfWeekContaining b  -- be careful at year boundary
    w = formatTime defaultTimeLocale "%V" b
showPeriod (MonthPeriod y m)   = T.pack $ printf "%04d-%02d" y m                           -- YYYY-MM
showPeriod (QuarterPeriod y q) = T.pack $ printf "%04dQ%d" y q                             -- YYYYQN
showPeriod (YearPeriod y)      = T.pack $ printf "%04d" y                                  -- YYYY
showPeriod (PeriodBetween b e) = T.pack $ formatTime defaultTimeLocale "%F" b
                                 ++ formatTime defaultTimeLocale "..%F" (addDays (-1) e) -- STARTDATE..INCLUSIVEENDDATE
showPeriod (PeriodFrom b)      = T.pack $ formatTime defaultTimeLocale "%F.." b                   -- STARTDATE..
showPeriod (PeriodTo e)        = T.pack $ formatTime defaultTimeLocale "..%F" (addDays (-1) e)    -- ..INCLUSIVEENDDATE
showPeriod PeriodAll           = ".."

-- | Like showPeriod, but if it's a month or week period show
-- an abbreviated form.
-- >>> showPeriodAbbrev (WeekPeriod (fromGregorian 2016 7 25))
-- "W30"
-- >>> showPeriodAbbrev (WeekPeriod (fromGregorian 2024 12 30))
-- "W01"
showPeriodAbbrev :: Period -> Text
showPeriodAbbrev = showPeriodAbbrevWith defaultTimeLocale

-- | Like showPeriodAbbrev, but take the month names from this time locale.
showPeriodAbbrevWith :: TimeLocale -> Period -> Text
showPeriodAbbrevWith loc (MonthPeriod _ m)                                          -- Jan
  | m > 0 && m <= length monthnames = T.pack . snd $ monthnames !! (m-1)
  where monthnames = months loc
showPeriodAbbrevWith _ (WeekPeriod b) = T.pack $ formatTime defaultTimeLocale "W%V" b -- Www
showPeriodAbbrevWith _ p = showPeriod p

periodStart :: Period -> Maybe Day
periodStart p = fromEFDay <$> mb
  where
    DateSpan mb _ = periodAsDateSpan p

periodEnd :: Period -> Maybe Day
periodEnd p = fromEFDay <$> me
  where
    DateSpan _ me = periodAsDateSpan p

-- | Move a standard period to the following period of same duration.
-- Non-standard periods are unaffected.
periodNext :: Period -> Period
periodNext (DayPeriod b) = DayPeriod (addDays 1 b)
periodNext (WeekPeriod b) = WeekPeriod (addDays 7 b)
periodNext (MonthPeriod y 12) = MonthPeriod (y+1) 1
periodNext (MonthPeriod y m) = MonthPeriod y (m+1)
periodNext (QuarterPeriod y 4) = QuarterPeriod (y+1) 1
periodNext (QuarterPeriod y q) = QuarterPeriod y (q+1)
periodNext (YearPeriod y) = YearPeriod (y+1)
periodNext p = p

-- | Move a standard period to the preceding period of same duration.
-- Non-standard periods are unaffected.
periodPrevious :: Period -> Period
periodPrevious (DayPeriod b) = DayPeriod (addDays (-1) b)
periodPrevious (WeekPeriod b) = WeekPeriod (addDays (-7) b)
periodPrevious (MonthPeriod y 1) = MonthPeriod (y-1) 12
periodPrevious (MonthPeriod y m) = MonthPeriod y (m-1)
periodPrevious (QuarterPeriod y 1) = QuarterPeriod (y-1) 4
periodPrevious (QuarterPeriod y q) = QuarterPeriod y (q-1)
periodPrevious (YearPeriod y) = YearPeriod (y-1)
periodPrevious p = p

-- | Move a standard period to the following period of same duration, staying within enclosing dates.
-- Non-standard periods are unaffected.
periodNextIn :: DateSpan -> Period -> Period
periodNextIn (DateSpan _ (Just e0)) p =
  case mb of
    Just b -> if b < e then p' else p
    _      -> p
  where
    e = fromEFDay e0
    p' = periodNext p
    mb = periodStart p'
periodNextIn _ p = periodNext p

-- | Move a standard period to the preceding period of same duration, staying within enclosing dates.
-- Non-standard periods are unaffected.
periodPreviousIn :: DateSpan -> Period -> Period
periodPreviousIn (DateSpan (Just b0) _) p =
  case me of
    Just e -> if e > b then p' else p
    _      -> p
  where
    b = fromEFDay b0
    p' = periodPrevious p
    me = periodEnd p'
periodPreviousIn _ p = periodPrevious p

-- | Move a standard period stepwise so that it encloses the given date.
-- Non-standard periods are unaffected.
periodMoveTo :: Day -> Period -> Period
periodMoveTo d (DayPeriod _) = DayPeriod d
periodMoveTo d (WeekPeriod _) = WeekPeriod $ mondayBefore d
periodMoveTo d (MonthPeriod _ _) = MonthPeriod y m where (y,m,_) = toGregorian d
periodMoveTo d (QuarterPeriod _ _) = QuarterPeriod y q
  where
    (y,m,_) = toGregorian d
    q = quarterContainingMonth m
periodMoveTo d (YearPeriod _) = YearPeriod y where (y,_,_) = toGregorian d
periodMoveTo _ p = p

-- | Enlarge a standard period to the next larger enclosing standard period, if there is one.
-- Eg, a day becomes the enclosing week.
-- A week becomes whichever month the week's thursday falls into.
-- A year becomes all (unlimited).
-- Non-standard periods (arbitrary dates, or open-ended) are unaffected.
periodGrow :: Period -> Period
periodGrow (DayPeriod b) = WeekPeriod $ mondayBefore b
periodGrow (WeekPeriod b) = MonthPeriod y m
  where (y,m) = yearMonthContainingWeekStarting b
periodGrow (MonthPeriod y m) = QuarterPeriod y (quarterContainingMonth m)
periodGrow (QuarterPeriod y _) = YearPeriod y
periodGrow (YearPeriod _) = PeriodAll
periodGrow p = p

-- | Shrink a period to the next smaller standard period inside it,
-- choosing the subperiod which contains today's date if possible,
-- otherwise the first subperiod. It goes like this:
-- unbounded periods and nonstandard periods (between two arbitrary dates) ->
-- current year ->
-- current quarter if it's in selected year, otherwise first quarter of selected year ->
-- current month if it's in selected quarter, otherwise first month of selected quarter ->
-- current week if it's in selected month, otherwise first week of selected month ->
-- today if it's in selected week, otherwise first day of selected week,
--  unless that's in previous month, in which case first day of month containing selected week.
-- Shrinking a day has no effect.
periodShrink :: Day -> Period -> Period
periodShrink _     p@(DayPeriod _) = p
periodShrink today (WeekPeriod b)
  | today >= b && diffDays today b < 7 = DayPeriod today
  | m /= weekmonth                     = DayPeriod $ fromGregorian weekyear weekmonth 1
  | otherwise                          = DayPeriod b
  where
    (_,m,_) = toGregorian b
    (weekyear,weekmonth) = yearMonthContainingWeekStarting b
periodShrink today (MonthPeriod y m)
  | (y',m') == (y,m) = WeekPeriod $ mondayBefore today
  | otherwise        = WeekPeriod $ startOfFirstWeekInMonth y m
  where (y',m',_) = toGregorian today
periodShrink today (QuarterPeriod y q)
  | quarterContainingMonth thismonth == q = MonthPeriod y thismonth
  | otherwise                             = MonthPeriod y (firstMonthOfQuarter q)
  where (_,thismonth,_) = toGregorian today
periodShrink today (YearPeriod y)
  | y == thisyear = QuarterPeriod y thisquarter
  | otherwise     = QuarterPeriod y 1
  where
    (thisyear,thismonth,_) = toGregorian today
    thisquarter = quarterContainingMonth thismonth
periodShrink today _ = YearPeriod y
  where (y,_,_) = toGregorian today

mondayBefore d = addDays (1 - toInteger wd) d
  where
    (_,_,wd) = toWeekDate d

thursdayOfWeekContaining = (addDays 3).mondayBefore

yearMonthContainingWeekStarting weekstart = (y,m)
  where
    thu = addDays 3 weekstart
    (y,yd) = toOrdinalDate thu
    (m,_) = dayOfYearToMonthAndDay (isLeapYear y) yd

quarterContainingMonth m = (m-1) `div` 3 + 1

firstMonthOfQuarter q = (q-1)*3 + 1

startOfFirstWeekInMonth y m
  | monthstartday <= 4 = mon
  | otherwise          = addDays 7 mon  -- month starts with a fri/sat/sun
  where
    monthstart = fromGregorian y m 1
    mon = mondayBefore monthstart
    (_,_,monthstartday) = toWeekDate monthstart

