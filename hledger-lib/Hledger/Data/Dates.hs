{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE NoMonoLocalBinds    #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies        #-}
{-|

Date parsing and utilities for hledger.

For date and time values, we use the standard Day and UTCTime types.

A 'SmartDate' is a date which may be partially-specified or relative.
Eg 2008\/12\/31, but also 2008\/12, 12\/31, tomorrow, last week, next year,
in 5 days, in -3 quarters.
We represent these as a triple of strings like (\"2008\",\"12\",\"\"),
(\"\",\"\",\"tomorrow\"), (\"\",\"last\",\"week\").

A 'DateSpan' is the span of time between two specific calendar dates, or
an open-ended span where one or both dates are unspecified. (A date span
with both ends unspecified matches all dates.)

An 'Interval' is ledger's \"reporting interval\" - weekly, monthly,
quarterly, etc.

'Period' will probably replace DateSpan in due course.

-}

-- XXX fromGregorian silently clips bad dates, use fromGregorianValid instead ?

module Hledger.Data.Dates (
  -- * Misc date handling utilities
  fromEFDay,
  modifyEFDay,
  getCurrentDay,
  getCurrentMonth,
  getCurrentYear,
  nulldate,
  spanContainsDate,
  periodContainsDate,
  parsedate,
  showDate,
  showEFDate,
  showDateSpan,
  showDateSpanDebug,
  showDateSpanAbbrev,
  showDateSpanAbbrevWith,
  showDateSpanFull,
  elapsedSeconds,
  prevday,
  periodexprp,
  parsePeriodExpr,
  parsePeriodExpr',
  nulldatespan,
  emptydatespan,
  datesepchar,
  datesepchars,
  isDateSepChar,
  spanStart,
  spanEnd,
  spanStartYear,
  spanEndYear,
  spanYears,
  spansSpan,
  spanIntersect,
  spansIntersect,
  spanDefaultsFrom,
  spanValidDefaultsFrom,
  spanExtend,
  spanUnion,
  spansUnion,
  daysSpan,
  latestSpanContaining,
  smartdate,
  groupByDateSpan,
  fixSmartDate,
  fixSmartDateStr,
  fixSmartDateStrEither,
  fixSmartDateStrEither',
  yearp,
  daysInSpan,

  -- Temp exports
  startofyear,
  startofquarter,
  startofmonth,
  startofweek,
  nextday,
  nextweek,
  nextmonthandday,
  nextnthdayofmonth,
  prevNthWeekdayOfMonth,
  nthdayofweekcontaining,
  addGregorianMonthsToMonthday,
  advanceToNthWeekday,
  nextNthWeekdayOfMonth,
  isEmptySpan
) where

import Prelude hiding (Applicative(..))
import Control.Applicative (Applicative(..))
import Control.Applicative.Permutations
import Control.Monad (guard, unless, when)
import Control.Monad.Fail qualified as Fail (MonadFail, fail)
import Data.Char (digitToInt, isDigit)
import Data.Default (def)
import Data.Foldable (asum)
import Data.Function (on)
import Data.Functor (($>))
import Data.List (elemIndex, group, sort, sortBy)
import Data.Maybe (catMaybes, fromMaybe, isJust, mapMaybe)
import Data.Ord (comparing)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Format hiding (months)
import Data.Time.Calendar
    (Day, addDays, addGregorianYearsClip, addGregorianMonthsClip, diffDays,
     fromGregorian, fromGregorianValid, toGregorian)
import Data.Time.Calendar.OrdinalDate (fromMondayStartWeek, mondayStartWeek)
import Data.Time.Clock (UTCTime, diffUTCTime)
import Data.Time.LocalTime (getZonedTime, localDay, zonedTimeToLocalTime)
import Safe (headErr, headMay, lastMay, maximumMay, minimumMay)
import Text.Megaparsec
import Text.Megaparsec.Char (char, char', digitChar, string, string')
import Text.Megaparsec.Char.Lexer (decimal, signed)
import Text.Printf (printf)

import Hledger.Data.Types
import Hledger.Data.Period
import Hledger.Utils


-- Help ppShow parse and line-wrap DateSpans better in debug output.
instance Show DateSpan where
    show s = "DateSpan " ++ T.unpack (showDateSpan s)

showDate :: Day -> Text
showDate = T.pack . show

showEFDate :: EFDay -> Text
showEFDate = showDate . fromEFDay

-- | Render a datespan as a display string, abbreviating into a
-- compact form if possible.
-- Warning, hides whether dates are Exact or Flex.
showDateSpan :: DateSpan -> Text
showDateSpan = showPeriod . dateSpanAsPeriod

-- | Show a DateSpan with its begin/end dates, exact or flex.
showDateSpanDebug :: DateSpan -> String
showDateSpanDebug (DateSpan b e)= "DateSpan (" <> show b <> ") (" <> show e <> ")"

-- | Like showDateSpan, but show month spans as just the abbreviated month name
-- in the current locale.
showDateSpanAbbrev :: DateSpan -> Text
showDateSpanAbbrev = showPeriodAbbrev . dateSpanAsPeriod

-- | Like showDateSpanAbbrev, but take the month names from this time locale.
showDateSpanAbbrevWith :: TimeLocale -> DateSpan -> Text
showDateSpanAbbrevWith loc = showPeriodAbbrevWith loc . dateSpanAsPeriod

-- | Render a datespan as a full ISO date range "YYYY-MM-DD..YYYY-MM-DD"
-- (inclusive end), regardless of whether it represents a standard
-- calendar period. Open ends are shown as just "..".
showDateSpanFull :: DateSpan -> Text
showDateSpanFull (DateSpan mb me) =
  T.pack $ start <> ".." <> end
  where
    start = maybe "" (formatTime defaultTimeLocale "%F" . fromEFDay) mb
    end   = maybe "" (formatTime defaultTimeLocale "%F" . addDays (-1) . fromEFDay) me

-- | Get the current local date.
getCurrentDay :: IO Day
getCurrentDay = localDay . zonedTimeToLocalTime <$> getZonedTime

-- | Get the current local month number.
getCurrentMonth :: IO Int
getCurrentMonth = second3 . toGregorian <$> getCurrentDay

-- | Get the current local year.
getCurrentYear :: IO Integer
getCurrentYear = first3 . toGregorian <$> getCurrentDay

elapsedSeconds :: Fractional a => UTCTime -> UTCTime -> a
elapsedSeconds t1 = realToFrac . diffUTCTime t1

spanStart :: DateSpan -> Maybe Day
spanStart (DateSpan d _) = fromEFDay <$> d

spanEnd :: DateSpan -> Maybe Day
spanEnd (DateSpan _ d) = fromEFDay <$> d

spanStartDate :: DateSpan -> Maybe EFDay
spanStartDate (DateSpan d _) = d

spanEndDate :: DateSpan -> Maybe EFDay
spanEndDate (DateSpan _ d) = d

spanStartYear :: DateSpan -> Maybe Year
spanStartYear (DateSpan d _) = fmap (first3 . toGregorian . fromEFDay) d

spanEndYear :: DateSpan -> Maybe Year
spanEndYear (DateSpan d _) = fmap (first3 . toGregorian. fromEFDay) d

-- | Get the 0-2 years mentioned explicitly in a DateSpan.
spanYears :: DateSpan -> [Year]
spanYears (DateSpan ma mb) = mapMaybe (fmap (first3 . toGregorian. fromEFDay)) [ma,mb]

-- might be useful later: http://en.wikipedia.org/wiki/Allen%27s_interval_algebra

-- | Get overall span enclosing multiple sequentially ordered spans.
-- The start and end date will be exact or flexible depending on
-- the first span's start date and last span's end date.
spansSpan :: [DateSpan] -> DateSpan
spansSpan spans = DateSpan (spanStartDate =<< headMay spans) (spanEndDate =<< lastMay spans)

-- Like addGregorianMonthsClip, add one month to the given date, clipping when needed
-- to fit it within the next month's length. But also, keep a target day of month in mind,
-- and revert to that or as close to it as possible in subsequent longer months.
-- Eg, using it to step through 31sts gives 1/31, 2/28, 3/31, 4/30, 5/31..
addGregorianMonthsToMonthday :: MonthDay -> Integer -> Day -> Day
addGregorianMonthsToMonthday dom n d =
  let (y,m,_) = toGregorian $ addGregorianMonthsClip n d
  in fromGregorian y m dom

-- | Count the days in a DateSpan, or if it is open-ended return Nothing.
daysInSpan :: DateSpan -> Maybe Integer
daysInSpan (DateSpan (Just d1) (Just d2)) = Just $ diffDays (fromEFDay d2) (fromEFDay d1)
daysInSpan _ = Nothing

-- | Is this an empty span, ie closed with the end date on or before the start date ?
isEmptySpan :: DateSpan -> Bool
isEmptySpan (DateSpan (Just s) (Just e)) = e <= s
isEmptySpan _                            = False

-- | Does the span include the given date ?
spanContainsDate :: DateSpan -> Day -> Bool
spanContainsDate (DateSpan Nothing Nothing)   _ = True
spanContainsDate (DateSpan Nothing (Just e))  d = d < fromEFDay e
spanContainsDate (DateSpan (Just b) Nothing)  d = d >= fromEFDay b
spanContainsDate (DateSpan (Just b) (Just e)) d = d >= fromEFDay b && d < fromEFDay e

-- | Does the period include the given date ?
-- (Here to avoid import cycle).
periodContainsDate :: Period -> Day -> Bool
periodContainsDate p = spanContainsDate (periodAsDateSpan p)

-- | Group elements based on where they fall in a list of 'DateSpan's without
-- gaps. The precondition is not checked.
groupByDateSpan :: Bool -> (a -> Day) -> [DateSpan] -> [a] -> [(DateSpan, [a])]
groupByDateSpan showempty date colspans =
      groupByCols colspans
    . dropWhile (beforeStart . fst)
    . sortBy (comparing fst)
    . map (\x -> (date x, x))
  where
    groupByCols []     _  = []
    groupByCols (c:cs) [] = if showempty then (c, []) : groupByCols cs [] else []
    groupByCols (c:cs) ps = (c, map snd colps) : groupByCols cs laterps
      where (colps, laterps) = span ((spanEnd c >) . Just . fst) ps

    beforeStart = maybe (const False) (>) $ spanStart =<< headMay colspans

-- | Calculate the intersection of a number of datespans.
spansIntersect [] = nulldatespan
spansIntersect [d] = d
spansIntersect (d:ds) = d `spanIntersect` (spansIntersect ds)

-- | Calculate the union of a number of datespans.
spansUnion [] = nulldatespan
spansUnion [d] = d
spansUnion (d:ds) = d `spanUnion` (spansUnion ds)

-- | Calculate the intersection of two datespans.
--
-- For non-intersecting spans, gives an empty span beginning on the second's start date:
-- >>> DateSpan (Just $ Flex $ fromGregorian 2018 01 01) (Just $ Flex $ fromGregorian 2018 01 03) `spanIntersect` DateSpan (Just $ Flex $ fromGregorian 2018 01 03) (Just $ Flex $ fromGregorian 2018 01 05)
-- DateSpan 2018-01-03..2018-01-02
spanIntersect (DateSpan b1 e1) (DateSpan b2 e2) = DateSpan (laterDefinite b1 b2) (earlierDefinite e1 e2)

-- | Fill any unspecified dates in the first span with the dates from
-- the second one (if specified there). Sort of a one-way spanIntersect.
-- This one can create an invalid span that'll always be empty.
--
-- >>> :{
--  DateSpan (Just $ Exact $ fromGregorian 2024 1 1) Nothing
--  `spanDefaultsFrom`
--  DateSpan (Just $ Exact $ fromGregorian 2024 1 1) (Just $ Exact $ fromGregorian 2024 1 2)
-- :}
-- DateSpan 2024-01-01
--
-- >>> :{
--  DateSpan (Just $ Exact $ fromGregorian 2025 1 1) Nothing
--  `spanDefaultsFrom`
--  DateSpan (Just $ Exact $ fromGregorian 2024 1 1) (Just $ Exact $ fromGregorian 2024 1 2)
-- :}
-- DateSpan 2025-01-01..2024-01-01
--
spanDefaultsFrom :: DateSpan -> DateSpan -> DateSpan
spanDefaultsFrom (DateSpan a1 b1) (DateSpan a2 b2) = DateSpan a b
    where a = if isJust a1 then a1 else a2
          b = if isJust b1 then b1 else b2

-- | A smarter version of spanDefaultsFrom that avoids creating invalid
-- spans ending before they begin. Kept separate for now to reduce risk.
--
-- >>> :{
--  DateSpan (Just $ Exact $ fromGregorian 2025 1 1) Nothing
--  `spanValidDefaultsFrom`
--  DateSpan (Just $ Exact $ fromGregorian 2024 1 1) (Just $ Exact $ fromGregorian 2024 1 2)
-- :}
-- DateSpan 2025-01-01..
--
spanValidDefaultsFrom :: DateSpan -> DateSpan -> DateSpan
spanValidDefaultsFrom s1 s2 =
  case s1 `spanDefaultsFrom` s2 of
    DateSpan b e | b >= e -> s1
    s -> s

-- | Calculate the union of two datespans.
-- If either span is open-ended, the union will be too.
--
-- >>> ys2024 = fromGregorian 2024 01 01
-- >>> ys2025 = fromGregorian 2025 01 01
-- >>> to2024 = DateSpan Nothing               (Just $ Exact ys2024)
-- >>> in2024 = DateSpan (Just $ Exact ys2024) (Just $ Exact ys2025)
-- >>> spanUnion to2024 in2024
-- DateSpan ..2024-12-31
-- >>> spanUnion in2024 to2024
-- DateSpan ..2024-12-31
spanUnion (DateSpan b1 e1) (DateSpan b2 e2) = DateSpan (earlier b1 b2) (later e1 e2)

-- | Extend the definite start/end dates of the first span, if needed,
-- to include the definite start/end dates of the second span.
-- And/or, replace open start/end dates in the first span with
-- definite start/end dates from the second.
-- Unlike spanUnion, open start/end dates in the second are ignored.
--
-- >>> ys2024 = fromGregorian 2024 01 01
-- >>> ys2025 = fromGregorian 2025 01 01
-- >>> to2024 = DateSpan Nothing               (Just $ Exact ys2024)
-- >>> all2024 = DateSpan (Just $ Exact ys2024) (Just $ Exact ys2025)
-- >>> partof2024 = DateSpan (Just $ Exact $ fromGregorian 2024 03 01) (Just $ Exact $ fromGregorian 2024 09 01)
-- >>> spanExtend to2024 all2024
-- DateSpan 2024
-- >>> spanExtend all2024 to2024
-- DateSpan 2024
-- >>> spanExtend partof2024 all2024
-- DateSpan 2024
-- >>> spanExtend all2024 partof2024
-- DateSpan 2024
--
spanExtend (DateSpan b1 e1) (DateSpan b2 e2) = DateSpan (earlierDefinite b1 b2) (laterDefinite e1 e2)

-- | Pick the earlier of two DateSpan starts, treating Nothing as infinitely early.
-- An Exact and Flex with the same date are considered equal; the first argument wins.
earlier :: Maybe EFDay -> Maybe EFDay -> Maybe EFDay
earlier = min

-- | Pick the later of two DateSpan starts, treating Nothing as infinitely late.
-- An Exact and Flex with the same date are considered equal; the second argument wins.
later :: Maybe EFDay -> Maybe EFDay -> Maybe EFDay
later _ Nothing = Nothing
later Nothing _ = Nothing
later d1 d2     = max d1 d2

-- | Pick the earlier of two DateSpan ends that is a definite date (if any).
-- An Exact and Flex with the same date are considered equal; the first argument wins.
earlierDefinite :: Maybe EFDay -> Maybe EFDay -> Maybe EFDay
earlierDefinite d1 Nothing = d1
earlierDefinite Nothing d2 = d2
earlierDefinite d1 d2      = min d1 d2

-- | Pick the later of two DateSpan ends that is a definite date (if any).
-- An Exact and Flex with the same date are considered equal; the second argument wins.
laterDefinite :: Maybe EFDay -> Maybe EFDay -> Maybe EFDay
laterDefinite d1 Nothing = d1
laterDefinite Nothing d2 = d2
laterDefinite d1 d2      = max d1 d2

-- | Calculate the minimal DateSpan containing all of the given Days (in the
-- usual exclusive-end-date sense: beginning on the earliest, and ending on
-- the day after the latest).
daysSpan :: [Day] -> DateSpan
daysSpan ds = DateSpan (Exact <$> minimumMay ds) (Exact . addDays 1 <$> maximumMay ds)

-- | Select the DateSpan containing a given Day, if any, from a given list of
-- DateSpans.
--
-- If the DateSpans are non-overlapping, this returns the unique containing
-- DateSpan, if it exists. If the DateSpans are overlapping, it will return the
-- containing DateSpan with the latest start date, and then latest end date.

-- Note: This will currently return `DateSpan (Just s) (Just e)` before it will
-- return `DateSpan (Just s) Nothing`. It's unclear which behaviour is desired.
-- This is irrelevant at the moment as it's never applied to any list with
-- overlapping DateSpans.
latestSpanContaining :: [DateSpan] -> Day -> Maybe DateSpan
latestSpanContaining datespans = go
  where
    go day = do
        spn <- Set.lookupLT supSpan spanSet
        guard $ spanContainsDate spn day
        return spn
      where
        -- The smallest DateSpan larger than any DateSpan containing day.
        supSpan = DateSpan (Just $ Exact $ addDays 1 day) Nothing

    spanSet = Set.fromList $ filter (not . isEmptySpan) datespans

-- | Parse a period expression to an Interval and overall DateSpan using
-- the provided reference date, or return a parse error.
parsePeriodExpr
  :: Day -> Text -> Either HledgerParseErrors (Interval, DateSpan)
parsePeriodExpr refdate s = parsewith (periodexprp refdate <* eof) (T.toLower s)

-- | Like parsePeriodExpr, but call error' on failure.
parsePeriodExpr' :: Day -> Text -> (Interval, DateSpan)
parsePeriodExpr' refdate s =
  either (error' . ("failed to parse:" ++) . customErrorBundlePretty) id $  -- PARTIAL:
  parsePeriodExpr refdate s

-- | Show a DateSpan as a human-readable pseudo-period-expression string.
-- dateSpanAsText :: DateSpan -> String
-- dateSpanAsText (DateSpan Nothing Nothing)   = "all"
-- dateSpanAsText (DateSpan Nothing (Just e))  = printf "to %s" (show e)
-- dateSpanAsText (DateSpan (Just b) Nothing)  = printf "from %s" (show b)
-- dateSpanAsText (DateSpan (Just b) (Just e)) = printf "%s to %s" (show b) (show e)

-- | Convert a single smart date string to a date span using the provided
-- reference date, or raise an error.
-- spanFromSmartDateString :: Day -> String -> DateSpan
-- spanFromSmartDateString refdate s = spanFromSmartDate refdate sdate
--     where
--       sdate = fromparse $ parsewith smartdateonly s

spanFromSmartDate :: Day -> SmartDate -> DateSpan
spanFromSmartDate refdate sdate = DateSpan (Just b) (Just e)
    where
      (ry,rm,_) = toGregorian refdate
      (b,e) = span' sdate
        where
          span' :: SmartDate -> (EFDay, EFDay)
          span' (SmartCompleteDate day)       = (Exact day, Exact $ nextday day)
          span' (SmartAssumeStart y Nothing)  = (Flex $ startofyear day, Flex $ nextyear day) where day = fromGregorian y 1 1
          span' (SmartAssumeStart y (Just m)) = (Flex $ startofmonth day, Flex $ nextmonth day) where day = fromGregorian y m 1
          span' (SmartFromReference m d)      = (Exact day, Exact $ nextday day) where day = fromGregorian ry (fromMaybe rm m) d
          span' (SmartMonth m)                = (Flex $ startofmonth day, Flex $ nextmonth day) where day = fromGregorian ry m 1
          span' (SmartRelative n Day)         = (Exact $ addDays n refdate, Exact $ addDays (n+1) refdate)
          span' (SmartRelative n Week)        = (Flex $ addDays (7*n) d, Flex $ addDays (7*n+7) d) where d = thisweek refdate
          span' (SmartRelative n Month)       = (Flex $ addGregorianMonthsClip n d, Flex $ addGregorianMonthsClip (n+1) d) where d = thismonth refdate
          span' (SmartRelative n Quarter)     = (Flex $ addGregorianMonthsClip (3*n) d, Flex $ addGregorianMonthsClip (3*n+3) d) where d = thisquarter refdate
          span' (SmartRelative n Year)        = (Flex $ addGregorianYearsClip n d, Flex $ addGregorianYearsClip (n+1) d) where d = thisyear refdate
          span' (SmartRelativeMonth   LT m)   = (Flex d, Flex $ nextmonth d) where d = prevnamedmonth m refdate
          span' (SmartRelativeMonth   EQ m)   = (Flex d, Flex $ nextmonth d) where d = thisnamedmonth m refdate
          span' (SmartRelativeMonth   GT m)   = (Flex d, Flex $ nextmonth d) where d = nextnamedmonth m refdate
          span' (SmartRelativeWeekDay LT wd)  = (Exact d, Exact $ nextday d) where d = prevnamedweekday wd refdate
          span' (SmartRelativeWeekDay EQ wd)  = (Exact d, Exact $ nextday d) where d = thisnamedweekday wd refdate
          span' (SmartRelativeWeekDay GT wd)  = (Exact d, Exact $ nextday d) where d = nextnamedweekday wd refdate

-- showDay :: Day -> String
-- showDay day = printf "%04d/%02d/%02d" y m d where (y,m,d) = toGregorian day

-- | Convert a smart date string to an explicit yyyy\/mm\/dd string using
-- the provided reference date, or raise an error.
fixSmartDateStr :: Day -> Text -> Text
fixSmartDateStr d s =
  either (error' . printf "could not parse date %s %s" (show s) . show) id $  -- PARTIAL:
  (fixSmartDateStrEither d s :: Either HledgerParseErrors Text)

-- | A safe version of fixSmartDateStr.
fixSmartDateStrEither :: Day -> Text -> Either HledgerParseErrors Text
fixSmartDateStrEither d = fmap showEFDate . fixSmartDateStrEither' d

fixSmartDateStrEither' :: Day -> Text -> Either HledgerParseErrors EFDay
fixSmartDateStrEither' d s = case parsewith smartdateonly (T.toLower s) of
                               Right sd -> Right $ fixSmartDate d sd
                               Left e -> Left e

-- | Convert a SmartDate to a specific date using the provided reference date.
-- This date will be exact or flexible depending on whether the day was
-- specified exactly. (Missing least-significant parts produces a flex date.)
--
-- ==== Examples:
-- >>> :set -XOverloadedStrings
-- >>> let t = fixSmartDateStr (fromGregorian 2008 11 26)
-- >>> t "0000-01-01"
-- "0000-01-01"
-- >>> t "1999-12-02"
-- "1999-12-02"
-- >>> t "1999.12.02"
-- "1999-12-02"
-- >>> t "1999/3/2"
-- "1999-03-02"
-- >>> t "19990302"
-- "1999-03-02"
-- >>> t "2008/2"
-- "2008-02-01"
-- >>> t "0020/2"
-- "0020-02-01"
-- >>> t "1000"
-- "1000-01-01"
-- >>> t "4/2"
-- "2008-04-02"
-- >>> t "2"
-- "2008-11-02"
-- >>> t "January"
-- "2008-01-01"
-- >>> t "feb"
-- "2008-02-01"
-- >>> t "today"
-- "2008-11-26"
-- >>> t "yesterday"
-- "2008-11-25"
-- >>> t "tomorrow"
-- "2008-11-27"
-- >>> t "this day"
-- "2008-11-26"
-- >>> t "last day"
-- "2008-11-25"
-- >>> t "next day"
-- "2008-11-27"
-- >>> t "this week"  -- last monday
-- "2008-11-24"
-- >>> t "last week"  -- previous monday
-- "2008-11-17"
-- >>> t "next week"  -- next monday
-- "2008-12-01"
-- >>> t "this month"
-- "2008-11-01"
-- >>> t "last month"
-- "2008-10-01"
-- >>> t "next month"
-- "2008-12-01"
-- >>> t "this quarter"
-- "2008-10-01"
-- >>> t "last quarter"
-- "2008-07-01"
-- >>> t "next quarter"
-- "2009-01-01"
-- >>> t "this year"
-- "2008-01-01"
-- >>> t "last year"
-- "2007-01-01"
-- >>> t "next year"
-- "2009-01-01"
--
-- refdate is Wednesday, 2008-11-26
-- >>> t "last wednesday"
-- "2008-11-19"
-- >>> t "this wednesday"
-- "2008-12-03"
-- >>> t "next wednesday"
-- "2008-12-03"
-- >>> t "last january"
-- "2008-01-01"
-- >>> t "this january"
-- "2009-01-01"
-- >>> t "next january"
-- "2009-01-01"
-- >>> t "last november"
-- "2007-11-01"
-- >>> t "this november"
-- "2009-11-01"
-- >>> t "next november"
-- "2009-11-01"
--
-- >>> t "in 5 days"
-- "2008-12-01"
-- >>> t "in 7 months"
-- "2009-06-01"
-- >>> t "in -2 weeks"
-- "2008-11-10"
-- >>> t "1 quarter ago"
-- "2008-07-01"
-- >>> t "1 week ahead"
-- "2008-12-01"
fixSmartDate :: Day -> SmartDate -> EFDay
fixSmartDate refdate = fix
  where
    fix :: SmartDate -> EFDay
    fix (SmartCompleteDate d)     = Exact d
    fix (SmartAssumeStart y m)    = Flex  $ fromGregorian y (fromMaybe 1 m) 1
    fix (SmartFromReference m d)  = Exact $ fromGregorian ry (fromMaybe rm m) d
    fix (SmartMonth m)            = Flex  $ fromGregorian ry m 1
    fix (SmartRelative n Day)     = Exact $ addDays n refdate
    fix (SmartRelative n Week)    = Flex  $ addDays (7*n) $ thisweek refdate
    fix (SmartRelative n Month)   = Flex  $ addGregorianMonthsClip n $ thismonth refdate
    fix (SmartRelative n Quarter) = Flex  $ addGregorianMonthsClip (3*n) $ thisquarter refdate
    fix (SmartRelative n Year)    = Flex  $ addGregorianYearsClip n $ thisyear refdate
    fix (SmartRelativeMonth LT m)    = Flex $ prevnamedmonth m refdate
    fix (SmartRelativeMonth EQ m)    = Flex $ thisnamedmonth m refdate
    fix (SmartRelativeMonth GT m)    = Flex $ nextnamedmonth m refdate
    fix (SmartRelativeWeekDay LT wd) = Exact $ prevnamedweekday wd refdate
    fix (SmartRelativeWeekDay EQ wd) = Exact $ thisnamedweekday wd refdate
    fix (SmartRelativeWeekDay GT wd) = Exact $ nextnamedweekday wd refdate
    (ry, rm, _) = toGregorian refdate

prevday :: Day -> Day
prevday = addDays (-1)
nextday = addDays 1

thisweek = startofweek
prevweek = startofweek . addDays (-7)
nextweek = startofweek . addDays 7
startofweek day = fromMondayStartWeek y w 1
    where
      (y,_,_) = toGregorian day
      (w,_) = mondayStartWeek day

thismonth = startofmonth
prevmonth = startofmonth . addGregorianMonthsClip (-1)
nextmonth = startofmonth . addGregorianMonthsClip 1
startofmonth day = fromGregorian y m 1 where (y,m,_) = toGregorian day
nthdayofmonth d day = fromGregorian y m d where (y,m,_) = toGregorian day

prevnamedmonth :: Month -> Day -> Day
prevnamedmonth targetmonth refdate = fromGregorian y' targetmonth 1
  where
    (y, m, _) = toGregorian refdate
    y' = if targetmonth < m then y else y - 1

nextnamedmonth :: Month -> Day -> Day
nextnamedmonth targetmonth refdate = fromGregorian y' targetmonth 1
  where
    (y, m, _) = toGregorian refdate
    y' = if targetmonth > m then y else y + 1

thisnamedmonth :: Month -> Day -> Day
thisnamedmonth = nextnamedmonth  -- "this" and "next" both mean next occurrence after current month

prevnamedweekday :: WeekDay -> Day -> Day
prevnamedweekday targetwd refdate = addDays (negate $ fromIntegral daysback) refdate
  where
    (_, curwd) = mondayStartWeek refdate
    daysback = 1 + (curwd - targetwd - 1) `mod` 7

nextnamedweekday :: WeekDay -> Day -> Day
nextnamedweekday targetwd refdate = addDays (fromIntegral daysforward) refdate
  where
    (_, curwd) = mondayStartWeek refdate
    daysforward = 1 + (targetwd - curwd - 1) `mod` 7

thisnamedweekday :: WeekDay -> Day -> Day
thisnamedweekday = nextnamedweekday  -- "this" and "next" both mean next occurrence after today

thisquarter = startofquarter
startofquarter day = fromGregorian y (firstmonthofquarter m) 1
    where
      (y,m,_) = toGregorian day
      firstmonthofquarter m2 = ((m2-1) `div` 3) * 3 + 1

thisyear = startofyear
-- prevyear = startofyear . addGregorianYearsClip (-1)
nextyear = startofyear . addGregorianYearsClip 1
startofyear day = fromGregorian y 1 1 where (y,_,_) = toGregorian day

-- | Find the next occurrence of the specified month and day of month, on or after the given date.
-- The month should be 1-12 and the day of month should be 1-31, or an error will be raised.
--
-- >>> let wed22nd = fromGregorian 2017 11 22
-- >>> nextmonthandday 11 21 wed22nd
-- 2018-11-21
-- >>> nextmonthandday 11 22 wed22nd
-- 2017-11-22
-- >>> nextmonthandday 11 23 wed22nd
-- 2017-11-23
nextmonthandday :: Month -> MonthDay -> Day -> Day
nextmonthandday m n date
  -- PARTIAL:
  | not (validMonth m) = error' $ "nextmonthandday: month should be 1..12, not "++show m
  | not (validDay   n) = error' $ "nextmonthandday: day should be 1..31, not "  ++show n
  | mdthisyear >= date = mdthisyear
  | otherwise          = mdnextyear
  where
    s = startofyear date
    advancetomonth = applyN (m-1) nextmonth
    advancetoday = addDays (toInteger n-1)
    mdthisyear = advancetoday $ advancetomonth s
    mdnextyear = advancetoday $ advancetomonth $ nextyear s

-- | Find the next occurrence of the specified day of month, on or after the given date.
-- The day of month should be 1-31, or an error will be raised.
--
-- >>> let wed22nd = fromGregorian 2017 11 22
-- >>> nextnthdayofmonth 21 wed22nd
-- 2017-12-21
-- >>> nextnthdayofmonth 22 wed22nd
-- 2017-11-22
-- >>> nextnthdayofmonth 23 wed22nd
-- 2017-11-23
nextnthdayofmonth :: MonthDay -> Day -> Day
nextnthdayofmonth n date
  -- PARTIAL:
  | not (validDay n)       = error' $ "nextnthdayofmonth: day should be 1..31, not "  ++show n
  | nthofthismonth >= date = nthofthismonth
  | otherwise              = nthofnextmonth
  where
    s = startofmonth date
    nthofthismonth = nthdayofmonth n s
    nthofnextmonth = nthdayofmonth n $ nextmonth s

-- | For given date d find week-long interval that starts on nth day of week
-- and covers it.
--
-- Examples: 2017-11-22 is Wed. Week-long intervals that cover it and
-- start on Mon, Tue or Wed will start in the same week. However
-- intervals that start on Thu or Fri should start in prev week:
-- >>> let wed22nd = fromGregorian 2017 11 22
-- >>> nthdayofweekcontaining 1 wed22nd
-- 2017-11-20
-- >>> nthdayofweekcontaining 2 wed22nd
-- 2017-11-21
-- >>> nthdayofweekcontaining 3 wed22nd
-- 2017-11-22
-- >>> nthdayofweekcontaining 4 wed22nd
-- 2017-11-16
-- >>> nthdayofweekcontaining 5 wed22nd
-- 2017-11-17
nthdayofweekcontaining :: WeekDay -> Day -> Day
nthdayofweekcontaining n d | nthOfSameWeek <= d = nthOfSameWeek
                           | otherwise = nthOfPrevWeek
    where nthOfSameWeek = addDays (toInteger n-1) s
          nthOfPrevWeek = addDays (toInteger n-1) $ prevweek s
          s = startofweek d

-- -- | Find the next occurrence of some weekday, on or after the given date d.
-- --
-- -- >>> let wed22nd = fromGregorian 2017 11 22
-- -- >>> nextnthdayofweek 1 wed22nd
-- -- 2017-11-20
-- -- >>> nextnthdayofweek 2 wed22nd
-- -- 2017-11-21
-- -- >>> nextnthdayofweek 3 wed22nd
-- -- 2017-11-22
-- -- >>> nextnthdayofweek 4 wed22nd
-- -- 2017-11-16
-- -- >>> nextnthdayofweek 5 wed22nd
-- -- 2017-11-17
-- nextdayofweek :: WeekDay -> Day -> Day
-- nextdayofweek n d | nthOfSameWeek <= d = nthOfSameWeek
--                            | otherwise = nthOfPrevWeek
--     where nthOfSameWeek = addDays (toInteger n-1) s
--           nthOfPrevWeek = addDays (toInteger n-1) $ prevweek s
--           s = startofweek d

-- | Find the next occurrence of some nth weekday of a month, on or after the given date d.
--
-- >>> let wed22nd = fromGregorian 2017 11 22
-- >>> nextNthWeekdayOfMonth 3 3 wed22nd  -- next third wednesday
-- 2017-12-20
-- >>> nextNthWeekdayOfMonth 4 3 wed22nd  -- next fourth wednesday
-- 2017-11-22
-- >>> nextNthWeekdayOfMonth 5 3 wed22nd  -- next fifth wednesday
-- 2017-11-29
nextNthWeekdayOfMonth :: Int -> WeekDay -> Day -> Day
nextNthWeekdayOfMonth n wd d
  | nthweekdaythismonth >= d = nthweekdaythismonth
  | otherwise                = nthweekdaynextmonth
  where
    nthweekdaythismonth = advanceToNthWeekday n wd $ startofmonth d
    nthweekdaynextmonth = advanceToNthWeekday n wd $ nextmonth d

-- | Find the previous occurrence of some nth weekday of a month, on or before the given date d.
--
-- >>> let wed22nd = fromGregorian 2017 11 22
-- >>> prevNthWeekdayOfMonth 4 3 wed22nd
-- 2017-11-22
-- >>> prevNthWeekdayOfMonth 5 2 wed22nd
-- 2017-10-31
prevNthWeekdayOfMonth :: Int -> WeekDay -> Day -> Day
prevNthWeekdayOfMonth n wd d
  | nthweekdaythismonth <= d = nthweekdaythismonth
  | otherwise                = nthweekdayprevmonth
  where
    nthweekdaythismonth = advanceToNthWeekday n wd $ startofmonth d
    nthweekdayprevmonth = advanceToNthWeekday n wd $ prevmonth d

-- | Advance to the nth occurrence of the given weekday, on or after the given date.
-- Can call error.
advanceToNthWeekday :: Int -> WeekDay -> Day -> Day
advanceToNthWeekday n wd s =
  -- PARTIAL:
  maybe err (addWeeks (n-1)) $ firstMatch (>=s) $ iterate (addWeeks 1) $ firstweekday s
  where
    err = error' "advanceToNthWeekday: should not happen"
    addWeeks k = addDays (7 * toInteger k)
    firstMatch p = headMay . dropWhile (not . p)
    firstweekday = addDays (toInteger wd-1) . startofweek

----------------------------------------------------------------------
-- parsing

-- -- | Parse a couple of date-time string formats to a time type.
-- parsedatetime :: String -> Maybe LocalTime
-- parsedatetime s = asum [
--     parseTimeM TruedefaultTimeLocale "%Y/%m/%d %H:%M:%S" s,
--     parseTimeM TruedefaultTimeLocale "%Y-%m-%d %H:%M:%S" s
--     ]

-- | A simple date parsing helper: parses these YMD date string formats:
-- `YYYY-MM-DD`, `YYYY/MM/DD`, `YYYY.MM.DD` or `YYYYMMDD`,
-- where the month and day each have two digits and the year has one or more.
--
-- This is different from the Smart Dates of the CLI and period expressions ("smartdate", below)
-- and not quite the same as the Simple Dates of the journal ("datep", in Hledger.Read.Common).
-- It's mainly for internal or interactive use, eg when debugging - 
-- but currently is also used in a few user-facing places, such as:
-- parsing --value's argument, 
-- parsing .latest files,
-- and parsing hledger's --version output (which uses unseparated dates).
--
-- Unseparated dates were added in 2025 for convenience.
-- Note it means many integers will now parse successfully.
--
-- >>> parsedate "2008/02/03"
-- Just 2008-02-03
-- >>> parsedate "2008/02/03/"
-- Nothing
-- >>> parsedate "2008/02/30"
-- Nothing
-- >>> parsedate "2025-01-01"
-- Just 2025-01-01
-- >>> parsedate "2025.01.01"
-- Just 2025-01-01
-- >>> parsedate "20250101"
-- Just 2025-01-01
-- >>> parsedate "00101"
-- Just 0000-01-01
parsedate :: String -> Maybe Day
parsedate s = asum [
     parseTimeM True defaultTimeLocale "%Y-%m-%d" s,
     parseTimeM True defaultTimeLocale "%Y/%m/%d" s,
     parseTimeM True defaultTimeLocale "%Y.%m.%d" s,
     parseTimeM True defaultTimeLocale "%Y%m%d" s
     ]

{-|
Parse a date in any of the formats allowed in Ledger's period expressions, and some others.
Assumes any text in the parse stream has been lowercased.
Returns a SmartDate, to be converted to a full date later (see fixSmartDate).

Examples:

> 2004                                        (start of year, which must have 4+ digits)
> 2004/10                                     (start of month, which must be 1-12)
> 2004/10/1                                   (exact date, day must be 1-31)
> 10/1                                        (month and day in current year)
> 21                                          (day in current month)
> october, oct                                (start of month in current year)
> yesterday, today, tomorrow                  (-1, 0, 1 days from today)
> last/this/next day/week/month/quarter/year  (-1, 0, 1 periods from the current period)
> last/this/next monday/mon                   (the previous or next named weekday; this=next)
> last/next january/jan                       (previous or next start of named month; this disallowed to avoid confusion)
> in n days/weeks/months/quarters/years       (n periods from the current period)
> n days/weeks/months/quarters/years ago      (-n periods from the current period)
> 20181201                                    (8 digit YYYYMMDD with valid year month and day)
> 201812                                      (6 digit YYYYMM with valid year and month)

Note malformed digit sequences might give surprising results:

> 201813                                      (6 digits with an invalid month is parsed as start of 6-digit year)
> 20181301                                    (8 digits with an invalid month is parsed as start of 8-digit year)
> 20181232                                    (8 digits with an invalid day gives an error)
> 201801012                                   (9+ digits beginning with a valid YYYYMMDD gives an error)

Eg:

YYYYMMDD is parsed as year-month-date if those parts are valid
(>=4 digits, 1-12, and 1-31 respectively):
>>> parsewith (smartdate <* eof) "20181201"
Right (SmartCompleteDate 2018-12-01)

YYYYMM is parsed as year-month-01 if year and month are valid:
>>> parsewith (smartdate <* eof) "201804"
Right (SmartAssumeStart 2018 (Just 4))

With an invalid month, it's parsed as a year:
>>> parsewith (smartdate <* eof) "201813"
Right (SmartAssumeStart 201813 Nothing)

A 9+ digit number beginning with valid YYYYMMDD gives an error:
>>> parsewith (smartdate <* eof) "201801012"
Left (...)

Big numbers not beginning with a valid YYYYMMDD are parsed as a year:
>>> parsewith (smartdate <* eof) "201813012"
Right (SmartAssumeStart 201813012 Nothing)

-}
smartdate :: TextParser m SmartDate
smartdate = choice'
  -- XXX maybe obscures date errors ? see ledgerdate
    [ relativeinterval
    , relativemonth
    , relativeweekday
    , yyyymmdd
    , ymd
    , (\(m,d) -> SmartFromReference (Just m) d) <$> md
    , failIfInvalidDate . SmartFromReference Nothing =<< decimal
    , SmartMonth <$> (month <|> mon)
    , SmartRelative (-1) Day <$ string' "yesterday"
    , SmartRelative 0    Day <$ string' "today"
    , SmartRelative 1    Day <$ string' "tomorrow"
    ]
  where
    relativeinterval = do
        optional $ string' "in" <* skipNonNewlineSpaces
        num      <- relativenump <* skipNonNewlineSpaces
        interval <- intervalp <* skipNonNewlineSpaces
        sign     <- choice [negate <$ string' "ago", id <$ string' "ahead", pure id]
        return $ SmartRelative (sign num) interval
        where
          relativenump = choice [ 0 <$ string' "this", -1 <$ string' "last", 1 <$ string' "next", signed skipNonNewlineSpaces decimal ]
          intervalp    = choice [ Day <$ string' "day", Week <$ string' "week", Month <$ string' "month"
                                , Quarter <$ string' "quarter", Year <$ string' "year" ] <* optional (char' 's')
    relativemonth = do
      dir <- choice [LT <$ string' "last", EQ <$ string' "this", GT <$ string' "next"]
      skipNonNewlineSpaces
      m <- (month <|> mon)
      return $ SmartRelativeMonth dir m
    relativeweekday = do
      dir <- choice [LT <$ string' "last", EQ <$ string' "this", GT <$ string' "next"]
      skipNonNewlineSpaces
      w <- weekday
      return $ SmartRelativeWeekDay dir w

-- | Like smartdate, but there must be nothing other than whitespace after the date.
smartdateonly :: TextParser m SmartDate
smartdateonly = smartdate <* skipNonNewlineSpaces <* eof

datesepchars :: String
datesepchars = "/-."

datesepchar :: TextParser m Char
datesepchar = satisfy isDateSepChar

isDateSepChar :: Char -> Bool
isDateSepChar c = c == '-' || c == '/' || c == '.'

validMonth, validDay :: Int -> Bool
validMonth n = n >= 1 && n <= 12
validDay n = n >= 1 && n <= 31

failIfInvalidDate :: Fail.MonadFail m => SmartDate -> m SmartDate
failIfInvalidDate s = unless isValid (Fail.fail $ "bad smart date: " ++ show s) $> s
  where isValid = case s of
            SmartAssumeStart _ (Just m) -> validMonth m
            SmartFromReference mm d     -> isJust $ fromGregorianValid 2004 (fromMaybe 1 mm) d
            SmartMonth m                -> validMonth m
            _                           -> True

showBadDate :: Integer -> Int -> Int -> String
showBadDate y m d = "bad smart date: " ++ show y ++ "-" ++ show m ++ "-" ++ show d

yyyymmdd :: TextParser m SmartDate
yyyymmdd = do
  y <- read <$> count 4 digitChar
  m <- read <$> count 2 digitChar
  mdy <- optional $ read <$> count 2 digitChar
  case mdy of
      Nothing -> failIfInvalidDate $ SmartAssumeStart y (Just m)
      Just d  -> maybe (Fail.fail $ showBadDate y m d) (return . SmartCompleteDate) $
                   fromGregorianValid y m d

ymd :: TextParser m SmartDate
ymd = do
    y <- yearp
    emd <- optional . try $ do
        sep <- datesepchar
        m <- decimal
        unless (validMonth m) $ Fail.fail ("Bad month " <> show m)
        option (Left m) . try $ Right <$> do
            _ <- char sep
            d <- decimal
            maybe (Fail.fail $ showBadDate y m d) return $ fromGregorianValid y m d
    return $ case emd of
        Nothing          -> SmartAssumeStart y Nothing
        Just (Left m)    -> SmartAssumeStart y (Just m)
        Just (Right day) -> SmartCompleteDate day

md :: TextParser m (Month, MonthDay)
md = do
  m <- decimal
  datesepchar
  d <- decimal
  _ <- failIfInvalidDate $ SmartFromReference (Just m) d
  return (m, d)

-- | Parse a year number from a Text, making sure that at least four digits are
-- used.
yearp :: TextParser m Integer
yearp = do
  year <- takeWhile1P (Just "year") isDigit
  unless (T.length year >= 4) . Fail.fail $ "Year must contain at least 4 digits: " <> T.unpack year
  return $ readDecimal year

-- These are compared case insensitively, and should all be kept lower case.
months         = ["january","february","march","april","may","june",
                  "july","august","september","october","november","december"]
monthabbrevs   = ["jan","feb","mar","apr","may","jun","jul","aug","sep","oct","nov","dec"]
weekdays       = ["monday","tuesday","wednesday","thursday","friday","saturday","sunday"]
weekdayabbrevs = ["mon","tue","wed","thu","fri","sat","sun"]

month, mon :: TextParser m Month
month = choice $ zipWith (\i m -> i <$ string' m) [1..12] months
mon   = choice $ zipWith (\i m -> i <$ string' m) [1..12] monthabbrevs

weekday :: TextParser m Int
weekday = do
  wday <- T.toLower <$> (choice . map string' $ weekdays ++ weekdayabbrevs)
  case catMaybes $ [wday `elemIndex` weekdays, wday `elemIndex` weekdayabbrevs] of
    (i:_) -> return (i+1)
    []    -> Fail.fail $ "weekday: should not happen: attempted to find " <>
                         show wday <> " in " <> show (weekdays ++ weekdayabbrevs)

weekdaysp :: TextParser m [Int]
weekdaysp = fmap headErr . group . sort <$> sepBy1 weekday (string' ",")  -- PARTIAL headErr will succeed because of sepBy1

-- | Parse a period expression, specifying a date span and optionally
-- a reporting interval. Requires a reference "today" date for
-- resolving any relative start/end dates (only; it is not needed for
-- parsing the reporting interval).
--
-- >>> let p = parsePeriodExpr (fromGregorian 2008 11 26)
-- >>> p "from Aug to Oct"
-- Right (NoInterval,DateSpan 2008-08-01..2008-09-30)
-- >>> p "aug to oct"
-- Right (NoInterval,DateSpan 2008-08-01..2008-09-30)
-- >>> p "2009q2"
-- Right (NoInterval,DateSpan 2009Q2)
-- >>> p "Q3"
-- Right (NoInterval,DateSpan 2008Q3)
-- >>> p "every 3 days in Aug"
-- Right (Days 3,DateSpan 2008-08)
-- >>> p "daily from aug"
-- Right (Days 1,DateSpan 2008-08-01..)
-- >>> p "every week to 2009"
-- Right (Weeks 1,DateSpan ..2008-12-31)
-- >>> p "every 2nd day of month"
-- Right (MonthDay 2,DateSpan ..)
-- >>> p "every 2nd day"
-- Right (MonthDay 2,DateSpan ..)
-- >>> p "every 2nd day 2009.."
-- Right (MonthDay 2,DateSpan 2009-01-01..)
-- >>> p "every 2nd day 2009-"
-- Right (MonthDay 2,DateSpan 2009-01-01..)
-- >>> p "every 29th Nov"
-- Right (MonthAndDay 11 29,DateSpan ..)
-- >>> p "every 29th nov ..2009"
-- Right (MonthAndDay 11 29,DateSpan ..2008-12-31)
-- >>> p "every nov 29th"
-- Right (MonthAndDay 11 29,DateSpan ..)
-- >>> p "every Nov 29th 2009.."
-- Right (MonthAndDay 11 29,DateSpan 2009-01-01..)
-- >>> p "every 11/29 from 2009"
-- Right (MonthAndDay 11 29,DateSpan 2009-01-01..)
-- >>> p "every 11/29 since 2009"
-- Right (MonthAndDay 11 29,DateSpan 2009-01-01..)
-- >>> p "every 2nd Thursday of month to 2009"
-- Right (NthWeekdayOfMonth 2 4,DateSpan ..2008-12-31)
-- >>> p "every 1st monday of month to 2009"
-- Right (NthWeekdayOfMonth 1 1,DateSpan ..2008-12-31)
-- >>> p "every tue"
-- Right (DaysOfWeek [2],DateSpan ..)
-- >>> p "every 2nd day of week"
-- Right (DaysOfWeek [2],DateSpan ..)
-- >>> p "every 2nd day of month"
-- Right (MonthDay 2,DateSpan ..)
-- >>> p "every 2nd day"
-- Right (MonthDay 2,DateSpan ..)
-- >>> p "every 2nd day 2009.."
-- Right (MonthDay 2,DateSpan 2009-01-01..)
-- >>> p "every 2nd day of month 2009.."
-- Right (MonthDay 2,DateSpan 2009-01-01..)
periodexprp :: Day -> TextParser m (Interval, DateSpan)
periodexprp rdate = do
  skipNonNewlineSpaces
  choice' [ intervalanddateperiodexprp rdate
          , (,) NoInterval <$> periodexprdatespanp rdate
          ]

-- Parse a reporting interval and a date span.
intervalanddateperiodexprp :: Day -> TextParser m (Interval, DateSpan)
intervalanddateperiodexprp rdate = do
  i <- reportingintervalp
  s <- option def . try $ do
      skipNonNewlineSpaces
      periodexprdatespanp rdate
  return (i,s)

-- Parse a reporting interval.
reportingintervalp :: TextParser m Interval
reportingintervalp = choice'
    [ tryinterval "day"     "daily"     Days
    , tryinterval "month"   "monthly"   Months
    , tryinterval "quarter" "quarterly" Quarters
    , tryinterval "year"    "yearly"    Years
    , Weeks 2 <$ string' "biweekly"
    , Weeks 2 <$ string' "fortnightly"
    , Months 2 <$ string' "bimonthly"
    , string' "every" *> skipNonNewlineSpaces *> choice'
        [ DaysOfWeek . pure <$> (nth <* skipNonNewlineSpaces <* string' "day" <* of_ "week")
        , MonthDay <$> (nth <* skipNonNewlineSpaces <* string' "day" <* optOf_ "month")
        , liftA2 NthWeekdayOfMonth nth $ skipNonNewlineSpaces *> weekday <* optOf_ "month"
        , uncurry MonthAndDay <$> (md <* optOf_ "year")
        , DaysOfWeek <$> weekdaysp
        , DaysOfWeek [1..5] <$ string' "weekday"
        , DaysOfWeek [6..7] <$ string' "weekendday"
        , d_o_y <* optOf_ "year"
        ]
    -- NB: the ordering is important here since the parse for `every weekday`
    -- would match the `tryinterval` first and then error on `d`. Perhaps it
    -- would be clearer to factor some of this into the `every` choice or other
    -- left-factorings.
    , tryinterval "week"    "weekly"    Weeks
    ]
  where
    of_ period =
      skipNonNewlineSpaces *> string' "of" *> skipNonNewlineSpaces *> string' period

    optOf_ period = optional . try $ of_ period

    nth = decimal <* choice (map string' ["st","nd","rd","th"])
    d_o_y = runPermutation $ liftA2 MonthAndDay (toPermutation $ (month <|> mon) <* skipNonNewlineSpaces)
                                                (toPermutation $ nth <* skipNonNewlineSpaces)

    -- Parse any of several variants of a basic interval, eg "daily", "every day", "every N days".
    tryinterval :: Text -> Text -> (Int -> Interval) -> TextParser m Interval
    tryinterval singular compact intcons = intcons <$> choice'
        [ 1 <$ string' compact
        , string' "every" *> skipNonNewlineSpaces *> choice
            [ 1 <$ string' singular
            , decimal <* skipNonNewlineSpaces <* string' (singular <> "s")
            ]
        ]

periodexprdatespanp :: Day -> TextParser m DateSpan
periodexprdatespanp rdate = choice' [
                            doubledatespanp rdate,
                            fromdatespanp rdate,
                            todatespanp rdate,
                            indatespanp rdate
                           ]

-- |
-- >>> parsewith (doubledatespanp (fromGregorian 2018 01 01) <* eof) "20180101-201804"
-- Right DateSpan 2018Q1
-- >>> parsewith (doubledatespanp (fromGregorian 2018 01 01) <* eof) "2017..2018"
-- Right DateSpan 2017
-- >>> parsewith (doubledatespanp (fromGregorian 2018 01 01) <* eof) "2017-2018"
-- Right DateSpan 2017
-- >>> parsewith (doubledatespanp (fromGregorian 2018 01 01) <* eof) "2017-01-2018"
-- Right DateSpan 2017
-- >>> parsewith (doubledatespanp (fromGregorian 2018 01 01) <* eof) "2017-01-01-2018"
-- Right DateSpan 2017
--
-- A single number after an unspaced - is not accepted as the end date (a day of the current month),
-- since eg 2008-13 is more likely a mistyped date than "2008 to the 13th":
--
-- >>> either (const "parse error") show $ parsewith (doubledatespanp (fromGregorian 2018 01 01) <* eof) "2008-13"
-- "parse error"
-- >>> parsewith (doubledatespanp (fromGregorian 2018 01 01) <* eof) "2008..13"
-- Right DateSpan 2008-01-01..2018-01-12
doubledatespanp :: Day -> TextParser m DateSpan
doubledatespanp rdate = do
    b <- optional ((string' "from" <|> string' "since") *> skipNonNewlineSpaces) *> smartdateorquarterstartp rdate
    spacedbefore <- skipNonNewlineSpaces'
    sep <- choice [string' "to", string "..", string "-"]
    spacedafter <- skipNonNewlineSpaces'
    e <- smartdateorquarterstartp rdate
    when (sep == "-" && not spacedbefore && not spacedafter && isDayOfMonth e) $
      Fail.fail $ "a single number after - is ambiguous here;"
        ++ " to mean a day of the current month, write .. or to instead of -"
    return $ fromToSpan b e
  where
    fromToSpan = DateSpan `on` (Just . fixSmartDate rdate)
    isDayOfMonth (SmartFromReference Nothing _) = True
    isDayOfMonth _ = False

-- |
-- >>> let p = parsewith (fromdatespanp (fromGregorian 2024 02 02) <* eof)
-- >>> p "2025-01-01.."
-- Right DateSpan 2025-01-01..
-- >>> p "2025Q1.."
-- Right DateSpan 2025-01-01..
-- >>> p "from q2"
-- Right DateSpan 2024-04-01..
fromdatespanp :: Day -> TextParser m DateSpan
fromdatespanp rdate = fromSpan <$> choice
  [ (string' "from" <|> string' "since") *> skipNonNewlineSpaces *> smartdateorquarterstartp rdate
  , smartdateorquarterstartp rdate <* choice [string "..", string "-" <* notFollowedBy digitChar]
  ]
  where
    fromSpan b = DateSpan (Just $ fixSmartDate rdate b) Nothing

-- |
-- >>> let p = parsewith (todatespanp (fromGregorian 2024 02 02) <* eof)
-- >>> p "..2025-01-01"
-- Right DateSpan ..2024-12-31
-- >>> p "..2025Q1"
-- Right DateSpan ..2024-12-31
-- >>> p "to q2"
-- Right DateSpan ..2024-03-31
todatespanp :: Day -> TextParser m DateSpan
todatespanp rdate =
  choice [string' "to", string' "until", string "..", string "-"]
  *> skipNonNewlineSpaces
  *> (DateSpan Nothing . Just . fixSmartDate rdate <$> smartdateorquarterstartp rdate)

-- |j
-- >>> let p = parsewith (indatespanp (fromGregorian 2024 02 02) <* eof)
-- >>> p "2025-01-01"
-- Right DateSpan 2025-01-01
-- >>> p "2025q1"
-- Right DateSpan 2025Q1
-- >>> p "in Q2"
-- Right DateSpan 2024Q2
indatespanp :: Day -> TextParser m DateSpan
indatespanp rdate =
  optional (string' "in" *> skipNonNewlineSpaces)
  *> choice' [
    quarterspanp rdate,
    spanFromSmartDate rdate <$> smartdate
  ]

-- Helper: parse a quarter number, optionally preceded by a year.
quarterp :: Day -> TextParser m (Year, Int)
quarterp rdate = do
  y <- yearp <|> pure (first3 $ toGregorian rdate)
  n <- char' 'q' *> satisfy (`elem` ['1' .. '4']) >>= return . digitToInt
  return (y, n)

-- | Parse a single quarter (YYYYqN or qN, case insensitive q) as a date span.
--
-- >>> parsewith (quarterspanp (fromGregorian 2018 01 01) <* eof) "q1"
-- Right DateSpan 2018Q1
-- >>> parsewith (quarterspanp (fromGregorian 2018 01 01) <* eof) "Q1"
-- Right DateSpan 2018Q1
-- >>> parsewith (quarterspanp (fromGregorian 2018 01 01) <* eof) "2020q4"
-- Right DateSpan 2020Q4
quarterspanp :: Day -> TextParser m DateSpan
quarterspanp rdate = do
  (y,q) <- quarterp rdate
  return . periodAsDateSpan $ QuarterPeriod y q

-- | Parse a quarter (YYYYqN or qN, case insensitive q) as its start date.
--
-- >>> parsewith (quarterstartp (fromGregorian 2025 02 02) <* eof) "q1"
-- Right 2025-01-01
-- >>> parsewith (quarterstartp (fromGregorian 2025 02 02) <* eof) "Q2"
-- Right 2025-04-01
-- >>> parsewith (quarterstartp (fromGregorian 2025 02 02) <* eof) "2025q4"
-- Right 2025-10-01
quarterstartp :: Day -> TextParser m Day
quarterstartp rdate = do
  (y,q) <- quarterp rdate
  return $
    fromMaybe (error' "Hledger.Data.Dates.quarterstartp: invalid date found") $  -- PARTIAL, shouldn't happen
    periodStart $ QuarterPeriod y q

smartdateorquarterstartp :: Day -> TextParser m SmartDate
smartdateorquarterstartp rdate = choice' [SmartCompleteDate <$> quarterstartp rdate, smartdate]

nulldatespan :: DateSpan
nulldatespan = DateSpan Nothing Nothing

-- | An exact datespan of zero length, that matches no date.
emptydatespan :: DateSpan
emptydatespan = DateSpan (Just $ Exact $ addDays 1 nulldate) (Just $ Exact nulldate)

nulldate :: Day
nulldate = fromGregorian 0 1 1
