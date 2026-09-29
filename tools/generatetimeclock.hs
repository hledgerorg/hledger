#!/usr/bin/env stack
-- stack script --resolver nightly-2026-06-01
{-
generatetimeclock.hs NUMENTRIES

Outputs a dummy timeclock log with the specified number of clock-in/clock-out entries,
one per day.

-}

module Main
where
import System.Environment
import Data.Time.LocalTime
import Data.Time.Calendar
import Text.Printf

main = do
  args <- getArgs
  let [numentries] = map read args :: [Integer]
  today <- getCurrentDay
  let startdate = addDays (-numentries) today
  mapM_ (putStr . showentry) [startdate..today]

showentry d =
  printf "i %s 09:00:00 dummy\no %s 17:00:00\n" (show d) (show d)

getCurrentDay = localDay . zonedTimeToLocalTime <$> getZonedTime
