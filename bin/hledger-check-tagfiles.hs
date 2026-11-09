#!/usr/bin/env stack
-- stack runghc --verbosity info --package hledger
-- Run this script from inside the hledger source tree, so that it
-- will use the corresponding source version of hledger, which is the
-- version it is tested with.
--
-- You can compile these scripts by running compile.sh in this directory.
-- The compiled executables can be run from anywhere, so you could add
-- this directory to your $PATH and see them in hledger's command list.
--
-- You could make this a standalone script that runs from anywhere and
-- recompiles itself when changed, by replacing "runghc" above with
-- "script --compile --resolver lts-22" (eg). However this uses the
-- hledger version from that stackage resolver, so in this case you
-- should check out the corresponding release-tagged version of this
-- script for compatibility (eg: git checkout 1.18.1).
--
-- This setup is adapted for some current limitations of stack's
-- ghc/runghc/script commands. Unfortunately it requires repeating
-- package dependencies, to the extent they are required, in multiple
-- places.

{-
hledger-check-tagfiles stack script.
Read the default journal and give an error if any tag values
containing '/' do not exist as file paths.
Usage:

$ hledger-check-tagfiles.hs    # compiles if needed

or:

$ hledger check-tagfiles       # compiles if there's no compiled version
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
