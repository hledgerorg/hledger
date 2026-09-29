#!/usr/bin/env stack
{- stack script --resolver nightly-2026-04-17 --compile
-}
-- add this to see packages being installed instead of a long silence:
--   --verbosity=info
   --package base-prelude
   --package directory
   --package extra
   --package process
   --package regex
   --package safe
   --package shake
   --package time

{- |
Extract (shell) tests from haddock comments in Haskell code, run them and
verify expected output. Like https://hackage.haskell.org/package/doctest, 
but tests shell commands instead of GHCI commands.

A docshelltest is a haddock literal block whose first line begins with a
$ (leading whitespace ignored), the rest of the line is a shell command
and the remaining lines are the expected output. The exit code is expected
to be zero.

Usage example: $ doctest.hs doctest.hs

@
$ echo This test shall pass
This test shall pass
@

@
$ echo This test shall fail

@

-}

module Main where
import Data.List (isPrefixOf)
import System.Environment (getArgs)
import System.Exit (exitFailure, exitSuccess, exitWith, ExitCode(ExitSuccess)) -- base 3 compatible
import System.IO (hGetContents, hPutStr, hPutStrLn, stderr)
import System.Process (runInteractiveCommand, waitForProcess)
import Text.Printf (printf)

main = do
  f <- head `fmap` getArgs
  s <- readFile f
  let tests = doctests s
  putStrLn $ printf "Running %d doctests from %s" (length tests) f
  ok <-  mapM runShellDocTest $ doctests s
  putStrLn ""
  if all ok then exitSuccess else exitFailure

runShellDocTest :: String -> IO Bool
runShellDocTest s = do
  let (cmd, expected) = splitDocTest s
  putStr $ printf "Testing: %s .. " cmd
  (_, out, _, h) <- runInteractiveCommand cmd
  exit <- waitForProcess h
  output <- hGetContents out
  if exit == ExitSuccess
    then
      if output == expected
        then do
          putStrLn "ok"
          return True
        else do
          hPutStr stderr $ printf "FAILED\nExpected:\n%sGot:\n%s" expected output
          return False
    else do
      hPutStrLn stderr $ printf "ERROR: %s" (show exit)
      return False

splitDocTest s = (strip $ drop 1 $ strip $ head ls, unlines $ tail ls)
    where ls = lines s

-- extract doctests from haskell source code
doctests :: String -> [String]
doctests s = filter isDocTest $ haddockLiterals s
    where
      isDocTest = (("$" `isPrefixOf`) . dropws) . head . lines

-- extract haddock literal blocks from haskell source code
haddockLiterals :: String -> [String]
haddockLiterals "" = []
haddockLiterals s | null lit = []
                  | otherwise = lit : haddockLiterals rest
    where
      ls = drop 1 $ dropWhile (not . isLiteralBoundary) $ lines s
      lit = unlines $ takeWhile (not . isLiteralBoundary) ls
      rest = unlines $ drop 1 $ dropWhile (not . isLiteralBoundary) ls
      isLiteralBoundary = (== "@") . strip

strip = dropws . reverse . dropws . reverse
dropws = dropWhile (`elem` " \t")
