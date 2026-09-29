#!/usr/bin/env cabal
{- cabal:
build-depends: base, directory, hledger, text
-}
{-
hledger-check-tagfiles cabal script (requires cabal 3+).
Read the default journal and give an error if any tag values
containing '/' do not exist as file paths.
Usage:

$ hledger-check-tagfiles.hs    # compiles every time (?)

or:

$ hledger check-tagfiles       # compiles every time (?)
-}

import Control.Monad
import Data.Text qualified as T
import Hledger.Cli.Script
import System.Directory
import System.Exit

main = withJournal defcliopts $ \j -> do
  let filetags = [ (t,v)
                 | (t',v') <- concatMap transactionAllTags $ jtxns j
                 , let t = T.unpack t'
                 , let v = T.unpack v'
                 , '/' `elem` v
                 ]
  forM_ filetags $ \(t,f) -> do
    exists <- doesFileExist f
    unless exists $ do
      putStrLn $ "file not found in tag: " ++ t ++ ": " ++ f
      exitFailure
