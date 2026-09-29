#!/usr/bin/env stack
-- stack runghc --package hledger --package text
-- (to see setup progress output, add --verbosity info)

-- hledger-example-read - a short hledger stack script example

{-# LANGUAGE OverloadedStrings #-}

import Hledger.Cli.Script
import Data.Text qualified as T
import Data.Text.IO qualified as T

cmdmode = hledgerCommandMode (unlines
    ---------------------------standard terminal width-----------------------------
  ["example-hello"
  ,"Usage: hledger-example-hello [OPTS] [ARGS]"
  ,"or:    hledger example-hello -- [OPTS] [ARGS]"
  ,"Examples:"
  ,"$ hledger-example-hello         # do the thing"
  ,"$ hledger-example-hello --help  # print help"
  ])
  [] [generalflagsgroup1] [] ([], Just $ argsFlag "[ARGS]")

main = do
  opts@CliOpts{reportspec_=rspec} <- getHledgerCliOpts cmdmode
  withJournal opts $ \j -> do
    putStrLn $ "successfully read journal: " <> journalFilePath j
