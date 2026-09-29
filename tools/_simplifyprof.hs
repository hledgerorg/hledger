#!/usr/bin/env stack
-- stack script --resolver nightly-2026-04-17
-- simplifyprof.hs somefile.prof
-- filter uninteresting fields from GHC profile output
-- tested with GHC 6.8
-- Simon Michael 2007,2008

import Data.List
import System.Environment
import Text.Printf

main = do
  args <- getArgs
  let f = head' args
  s <- readFile f
  let ls = lines s
  let (firstpart, secondpart) = break ("individual    inherited" `isInfixOf`) ls
  putStr $ unlines firstpart
  let fields = map getfields $ filter (not . null) $ drop 2 secondpart
  let maxnamelen = maximum $ map (length . head) fields
  let fmt = "%-" ++ show maxnamelen ++ "s %10s %5s %6s %9s %10s"
  putStrLn $ showheading fmt
  putStr $ unlines $ map (format fmt) fields

getfields s = name:rest
    where
      space = takeWhile (==' ') s
      fields = words s
      name = space ++ head fields
      rest = drop 3 fields

showheading fmt = format fmt ["cost centre","entries","%time","%alloc","%time-inh","%alloc-inh"]

format fmt [s1,s2,s3,s4,s5,s6] = printf fmt s1 s2 s3 s4 s5 s6
