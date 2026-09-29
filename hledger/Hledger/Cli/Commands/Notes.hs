{-|

The @notes@ command lists all unique notes (description part after a |) seen in transactions, sorted alphabetically.

-}

{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE CPP #-}

module Hledger.Cli.Commands.Notes (
  notesmode
 ,notes
) where

import Data.List.Extra (nubSort)
import Data.Text.IO qualified as T

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Utils (printTitle)


-- | Command line options for this command.
notesmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Notes.txt")
  []
  cligeneralflagsgroups1
  hiddenflags
  ([], Just $ argsFlag "[QUERY]")

-- | The notes command.
notes :: CliOpts -> Journal -> IO ()
notes CliOpts{reportspec_=rspec} j = do
  printTitle $ _rsReportOpts rspec
  let ts = entriesReport rspec j
      notes' = nubSort $ map transactionNote ts
  mapM_ T.putStrLn notes'
