{-|

A 'TimeclockEntry' is a clock-in, clock-out, or other directive in a timeclock
file (see timeclock.el or the command-line version). These can be
converted to 'Transactions' and queried like a ledger.

-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}

module Hledger.Data.Timeclock (
   timeclockToTransactions
  ,timeclockToTransactionsOld
  ,tests_Timeclock
)
where

import Data.List (intercalate, partition, sortBy, sortOn, uncons)
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Time.Calendar (addDays)
import Data.Time.Clock (addUTCTime, getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime, parseTimeM)
import Data.Time.LocalTime (LocalTime(..), TimeOfDay(..), getCurrentTimeZone,
                            localTimeToUTC, midnight, utc, utcToLocalTime)
import Text.Printf (printf)

import Hledger.Utils
import Hledger.Data.Types
import Hledger.Data.Dates
import Hledger.Data.Amount
import Hledger.Data.Posting

-- detailed output for debugging
-- deriving instance Show TimeclockEntry

-- compact output
instance Show TimeclockEntry where
  show t = printf "%s %s %s  %s" (show $ tlcode t) (show $ tldatetime t) (tlaccount t) (tldescription t)

instance Show TimeclockCode where
  show SetBalance = "b"
  show SetRequiredHours = "h"
  show In = "i"
  show Out = "o"
  show FinalOut = "O"

instance Read TimeclockCode where
  readsPrec _ ('b':xs) = [(SetBalance, xs)]
  readsPrec _ ('h':xs) = [(SetRequiredHours, xs)]
  readsPrec _ ('i':xs) = [(In, xs)]
  readsPrec _ ('o':xs) = [(Out, xs)]
  readsPrec _ ('O':xs) = [(FinalOut, xs)]
  readsPrec _ _ = []

data Session = Session {
  in' :: TimeclockEntry,
  out :: TimeclockEntry
} deriving Show

data Sessions = Sessions {
  completed :: [Session],
  active :: [TimeclockEntry]
} deriving Show

-- | Convert timeclock entries to journal transactions.
-- This is the old version from hledger <1.43, now enabled by --old-timeclock.
-- It requires strictly alternating clock-in and clock-entries.
-- It was documented as allowing only one clocked-in session at a time,
-- but in fact it allows concurrent sessions, even with the same account name.
--
-- Entries must be a strict alternation of in and out, beginning with in.
-- When there is no clockout, one is added with the provided current time. 
-- Sessions crossing midnight are split into days to give accurate per-day totals.
-- If entries are not in the expected in/out order, an error is raised.
--
timeclockToTransactionsOld :: LocalTime -> [TimeclockEntry] -> [Transaction]
timeclockToTransactionsOld _ [] = []
timeclockToTransactionsOld now [i]
  | tlcode i /= In = errorExpectedCodeButGot In i
  | odate > idate = entryFromTimeclockInOut True i o' : timeclockToTransactionsOld now [i',o]
  | otherwise = [entryFromTimeclockInOut True i o]
  where
    o = TimeclockEntry (tlsourcepos i) Out end "" "" "" []
    end = if itime > now then itime else now
    (itime,otime) = (tldatetime i,tldatetime o)
    (idate,odate) = (localDay itime,localDay otime)
    o' = o{tldatetime=itime{localDay=idate, localTimeOfDay=TimeOfDay 23 59 59}}
    i' = i{tldatetime=itime{localDay=addDays 1 idate, localTimeOfDay=midnight}}
timeclockToTransactionsOld now (i:o:rest)
  | tlcode i /= In  = errorExpectedCodeButGot In i
  | tlcode o /= Out = errorExpectedCodeButGot Out o
  | odate > idate   = entryFromTimeclockInOut True i o' : timeclockToTransactionsOld now (i':o:rest)
  | otherwise       = entryFromTimeclockInOut True i o : timeclockToTransactionsOld now rest
  where
    (itime,otime) = (tldatetime i,tldatetime o)
    (idate,odate) = (localDay itime,localDay otime)
    o' = o{tldatetime=itime{localDay=idate, localTimeOfDay=TimeOfDay 23 59 59}}
    i' = i{tldatetime=itime{localDay=addDays 1 idate, localTimeOfDay=midnight}}
{- HLINT ignore timeclockToTransactionsOld -}

-- | Convert timeclock entries to journal transactions.
-- This is the new, default version added in hledger 1.43 and improved in 1.50.
-- It allows concurrent clocked-in sessions (though not with the same account name),
-- and clock-in/clock-out entries in any order.
--
-- Entries are processed in parse order.
-- Sessions crossing midnight are split into days to give accurate per-day totals.
-- At the end, any sessions with no clockout get an implicit clockout with the provided "now" time.
-- If any entries cannot be paired as expected, an error is raised.
--
timeclockToTransactions :: LocalTime -> [TimeclockEntry] -> [Transaction]
timeclockToTransactions now entries0 = transactions
  where
    -- don't sort by time, it messes things up; just reverse to get the parsed order
    entries = dbg7 "timeclock entries" $ reverse entries0
    sessions = dbg6 "sessions" $ pairClockEntries entries [] []
    transactionsFromSession s = entryFromTimeclockInOut False (in' s) (out s)
    -- If any "in" sessions are in the future, then set their out time to the initial time
    outtime te = max now (tldatetime te)
    createout te = TimeclockEntry (tlsourcepos te) Out (outtime te) (tlaccount te) "" "" []
    outs = map createout (active sessions)
    stillopen = dbg6 "stillopen" $ pairClockEntries ((active sessions) <> outs) [] []
    transactions = map transactionsFromSession $ sortBy (\s1 s2 -> compare (in' s1) (in' s2)) (completed sessions ++ completed stillopen)

    -- | Assuming that entries have been sorted, we go through each time log entry.
    -- We collect all of the "i" in the list "actives," and each time we encounter
    -- an "o," we look for the corresponding "i" in actives.
    -- If we cannot find it, then it is an error (since the list is sorted).
    -- If the "o" is recorded on a different day than the "i" then we close the
    -- active entry at the end of its day, replace it in the active list
    -- with a start at midnight on the next day, and try again.
    -- This raises an error if any outs cannot be paired with an in.
    pairClockEntries :: [TimeclockEntry] -> [TimeclockEntry] -> [Session] -> Sessions
    pairClockEntries [] actives sessions1 = Sessions {completed = sessions1, active = actives}
    pairClockEntries (entry:es) actives sessions1
      | tlcode entry == In  = pairClockEntries es inentries sessions1
      | tlcode entry == Out = pairClockEntries es' actives' sessions2
      | otherwise = pairClockEntries es actives sessions1
      where
        (inentry, newactive) = findInForOut entry (partition (\e -> tlaccount e == tlaccount entry) actives)
        (itime, otime) = (tldatetime inentry, tldatetime entry)
        (idate, odate) = (localDay itime, localDay otime)
        omidnight = entry {tldatetime = itime {localDay = idate, localTimeOfDay = TimeOfDay 23 59 59}}
        imidnight = inentry {tldatetime = itime {localDay = addDays 1 idate, localTimeOfDay = midnight}}
        (sessions2, actives', es')
          | odate > idate = (Session {in' = inentry, out = omidnight} : sessions1, imidnight:newactive, entry:es)
          | otherwise     = (Session {in' = inentry, out = entry} : sessions1, newactive, es)
        inentries = case filter ((== tlaccount entry) . tlaccount) actives of
          []                -> entry:actives
          activesinthisacct -> error' $ timeclockEntryError activesinthisacct entry $
            "This clockin overlaps the session in the same account which began on line "
            ++ intercalate ", " (map (show . timeclockEntryLine) activesinthisacct) ++ ".\n"
            ++ "Overlapping sessions with the same account name are not supported."

        -- | Find the relevant clockin in the actives list that should be paired with this clockout.
        -- If there is a session that has the same account name, then use that.
        -- Otherwise, if there is an active anonymous session, use that.
        -- Otherwise, raise an error.
        findInForOut :: TimeclockEntry -> ([TimeclockEntry], [TimeclockEntry]) -> (TimeclockEntry, [TimeclockEntry])
        findInForOut _ (matchingout:othermatches, rest) = (matchingout, othermatches <> rest)
        findInForOut o ([], activeins) =
            if emptyname then (first, rest) else error' errmsg
            where
                l = show $ unPos $ sourceLine $ tlsourcepos o
                c = unPos $ sourceColumn $ tlsourcepos o
                emptyname = tlaccount o == ""
                (first, rest) = case uncons activeins of
                    Just (hd, tl) -> (hd, tl)
                    Nothing -> error' errmsg
                errmsg =
                    printf
                      "%s:\n%s\n%s\n\nCould not find previous clockin to match this clockout."
                      (sourcePosPretty $ tlsourcepos o)
                      (l ++ " | " ++ show o)
                      (replicate (length l) ' ' ++ " |" ++ replicate c ' ' ++ "^")

errorExpectedCodeButGot :: TimeclockCode -> TimeclockEntry -> a
errorExpectedCodeButGot expected actual = error' $ printf
  ("%s:\n%s\n%s\n\nExpected a timeclock %s entry but got %s.\n"
  ++"Please alternate i and o, beginning with i.")
  (sourcePosPretty $ tlsourcepos actual)
  (l ++ " | " ++ show actual)
  (replicate (length l) ' ' ++ " |" ++ replicate c ' ' ++ "^")
  (show expected)
  (show $ tlcode actual)
  where
    l = show $ unPos $ sourceLine $ tlsourcepos actual
    c = unPos $ sourceColumn $ tlsourcepos actual

-- | Make an error message about a timeclock entry, in hledger's standard error format:
-- its position; an excerpt showing it, marked with ^, after any related earlier entries;
-- and the given explanation.
timeclockEntryError :: [TimeclockEntry] -> TimeclockEntry -> String -> String
timeclockEntryError related e msg = intercalate "\n" $
  [sourcePosPretty (tlsourcepos e) ++ ":"]
  ++ concat (zipWith excerptLines (Nothing : map Just es) es)
  ++ [replicate (length $ show $ timeclockEntryLine e) ' ' ++ " |" ++ replicate col ' ' ++ "^", "", msg]
  where
    es = sortOn timeclockEntryLine related ++ [e]
    col = unPos $ sourceColumn $ tlsourcepos e
    -- each entry's line, preceded by an empty line if it's not adjacent to the previous one
    excerptLines prev x =
      [ "" | Just p <- [prev], timeclockEntryLine x > timeclockEntryLine p + 1 ]
      ++ [show (timeclockEntryLine x) ++ " | " ++ T.unpack (T.stripEnd $ T.pack $ show x)]

-- | A timeclock entry's line number.
timeclockEntryLine :: TimeclockEntry -> Int
timeclockEntryLine = unPos . sourceLine . tlsourcepos

-- | Convert a timeclock clockin and clockout entry to an equivalent journal
-- transaction, representing the time expenditure. Note this entry is  not balanced,
-- since we omit the \"assets:time\" transaction for simpler output.
entryFromTimeclockInOut :: Bool -> TimeclockEntry -> TimeclockEntry -> Transaction
entryFromTimeclockInOut requiretimeordered i o
    | not requiretimeordered || otime >= itime = t
    | otherwise =
      -- Clockout time earlier than clockin is an error.
      -- (Clockin earlier than preceding clockin/clockout is allowed.)
      -- We should never encounter this case now that we sort the entries,
      -- but let's leave it in case of error.
      error' $ printf
        ("%s:\n%s\nThis clockout time (%s) is earlier than the previous clockin.\n"
        ++"Please adjust it to be later than %s.")
        (sourcePosPretty $ tlsourcepos o)
        (unlines [
          replicate (length l) ' '++ " | " ++ show i,
          l ++ " | " ++ show o,
          (replicate (length l) ' ' ++ " |" ++ replicate c ' ' ++ replicate 19 '^')
          ])
        (show $ tldatetime o)
        (show $ tldatetime i)
    where
      l = show $ unPos $ sourceLine $ tlsourcepos o
      c = (unPos $ sourceColumn $ tlsourcepos o) + 2
      t = Transaction {
            tindex       = 0,
            tsourcepos   = (tlsourcepos i, tlsourcepos i),
            tdate        = idate,
            tdate2       = Nothing,
            tstatus      = Cleared,
            tcode        = "",
            tdescription = desc,
            tcomment     = tlcomment i <> tlcomment o,
            ttags        = tltags i ++ tltags o,
            tpostings    = ps,
            tprecedingcomment=""
          }
      itime    = tldatetime i
      otime    = tldatetime o
      itod     = localTimeOfDay itime
      otod     = localTimeOfDay otime
      idate    = localDay itime
      desc     | T.null (tldescription i) = T.pack $ showtime itod ++ "-" ++ showtime otod
               | otherwise                = tldescription i
      showtime = take 5 . show
      hours    = elapsedSeconds (toutc otime) (toutc itime) / 3600 where toutc = localTimeToUTC utc
      acctname = tlaccount i
      -- Generate an hours amount. Unusually, we also round the internal Decimal value,
      -- since otherwise it will often have large recurring decimal parts which (since 1.21)
      -- print would display all 255 digits of. timeclock amounts have one second resolution,
      -- so two decimal places is precise enough (#1527).
      amt = case mixedAmount $ setAmountInternalPrecision 2 $ hrs hours of
        a | not $ a < 0 -> a
        _ -> error' $ timeclockEntryError [i] o $
          printf "This clockout is earlier than its clockin, on line %d." (timeclockEntryLine i)
      ps = [posting{paccount=acctname, pamount=amt, preal=VirtualPosting, ptransaction=Just t}]


-- tests

tests_Timeclock = testGroup "Timeclock" [
  testCaseSteps "timeclockToTransactions tests" $ \step -> do
      step "gathering data"
      today <- getCurrentDay
      now' <- getCurrentTime
      tz <- getCurrentTimeZone
      let now = utcToLocalTime tz now'
          nowstr = showtime now
          yesterday = prevday today
          clockin = TimeclockEntry (initialPos "") In
          clockout = TimeclockEntry (initialPos "") Out
          mktime d = LocalTime d . fromMaybe midnight .
                     parseTimeM True defaultTimeLocale "%H:%M:%S"
          showtime = formatTime defaultTimeLocale "%H:%M"
          txndescs = map (T.unpack . tdescription) . timeclockToTransactions now
          future = utcToLocalTime tz $ addUTCTime 100 now'
          futurestr = showtime future
      step "started yesterday, split session at midnight"
      txndescs [clockin (mktime yesterday "23:00:00") "" "" "" []] @?= ["23:00-23:59","00:00-"++nowstr]
      step "split multi-day sessions at each midnight"
      txndescs [clockin (mktime (addDays (-2) today) "23:00:00") "" "" "" []] @?= ["23:00-23:59","00:00-23:59","00:00-"++nowstr]
      step "auto-clock-out if needed"
      txndescs [clockin (mktime today "00:00:00") "" "" "" []] @?= ["00:00-"++nowstr]
      step "use the clockin time for auto-clockout if it's in the future"
      txndescs [clockin future "" "" "" []] @?= [printf "%s-%s" futurestr futurestr]
      step "multiple open sessions"
      txndescs (reverse [
        clockin (mktime today "00:00:00") "a" "" "" [],
        clockin (mktime today "01:00:00") "b" "" "" [],
        clockin (mktime today "02:00:00") "c" "" "" [],
        clockout (mktime today "03:00:00") "b" "" "" [],
        clockout (mktime today "04:00:00") "a" "" "" [],
        clockout (mktime today "05:00:00") "c" "" "" []
        ])
        @?= ["00:00-04:00", "01:00-03:00", "02:00-05:00"]
 ]
