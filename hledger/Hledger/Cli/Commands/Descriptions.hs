{-|

The @descriptions@ command lists all unique descriptions seen in transactions, sorted alphabetically.

-}

{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Descriptions (
  descriptionsmode
 ,descriptions
) where

import Data.List.Extra (nubSort)
import Data.Text.IO qualified as T

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Utils (printTitle)


-- | Command line options for this command.
descriptionsmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Descriptions.txt")
  []
  cligeneralflagsgroups1
  hiddenflags
  ([], Just $ argsFlag "[QUERY]")

-- | The descriptions command.
descriptions :: CliOpts -> Journal -> IO ()
descriptions CliOpts{reportspec_=rspec} j = do
  printTitle $ _rsReportOpts rspec
  let ts = entriesReport rspec j
      descs = nubSort $ map tdescription ts

  mapM_ T.putStrLn descs
