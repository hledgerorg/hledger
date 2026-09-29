{-|

The @transactions@ command lists transactions one per line.

-}

{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Transactions (
  transactionsmode
 ,transactions
) where

import System.Console.CmdArgs.Explicit

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Utils (withTitle, writeOutputLazyText)
import Hledger.Cli.Commands.Print (journalApplyMatchOpt, entriesReportAsTextHelper)


-- | Command line options for this command.
transactionsmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Transactions.txt")
  [
   let arg = "DESC" in
   flagReq  ["match","m"] (\s opts -> Right $ setopt "match" s opts) arg
    ("fuzzy search for one recent transaction with description closest to "++arg)
  ]
  cligeneralflagsgroups1
  hiddenflags
  ([], Just $ argsFlag "[QUERY]")

-- | The transactions command: show each transaction's first line only.
transactions :: CliOpts -> Journal -> IO ()
transactions opts@CliOpts{reportspec_=rspec} =
  writeOutputLazyText opts
  . withTitle (_rsReportOpts rspec)
  . entriesReportAsTextHelper showTransactionOneLine
  . entriesReport rspec
  . journalApplyMatchOpt opts
