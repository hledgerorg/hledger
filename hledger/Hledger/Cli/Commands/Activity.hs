{-# LANGUAGE TemplateHaskell #-}

{-|

Print a bar chart of posting activity per day, or other report interval.

-}

module Hledger.Cli.Commands.Activity
where

import Data.List (sortOn)
import Text.Printf (printf)
import Lens.Micro ((^.), set)

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Utils (printTitle, warnIfLargeMultiPeriodReport)

activitymode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Activity.txt")
  []
  cligeneralflagsgroups1
  hiddenflags
  ([], Just $ argsFlag "[QUERY]")

barchar :: Char
barchar = '*'

-- | Print a bar chart of number of postings per report interval.
activity :: CliOpts -> Journal -> IO ()
activity CliOpts{reportspec_=rspec} j = do
  warnIfLargeMultiPeriodReport rspec j
  printTitle $ _rsReportOpts rspec
  putStr $ showHistogram rspec j

showHistogram :: ReportSpec -> Journal -> String
showHistogram rspec@ReportSpec{_rsQuery=q} j =
    concatMap (printDayWith countBar) spanps
  where
    mspans = snd . reportSpan j $ case rspec ^. interval of
      NoInterval -> set interval (Days 1) rspec
      _ -> rspec
    spanps = case mspans of
      Nothing -> []
      Just x  -> map (\spn -> (spn, filter (postingInRange spn) ps)) $ dayPartitionToList x
    postingInRange (b, e) p = postingDate p >= b && postingDate p <= e
    -- same as Register
    -- should count transactions, not postings ?
    -- ps = sortBy (comparing postingDate) $ filterempties $ filter matchapats $ filterdepth $ journalPostings j
    ps = sortOn postingDate $ filter (q `matchesPosting`) $ journalPostings j

printDayWith f ((b, _), ps) = printf "%s %s\n" (show b) (f ps)

countBar ps = replicate (length ps) barchar
