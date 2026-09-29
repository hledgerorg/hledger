{-|

The @payees@ command lists all unique payees (description part before a |) seen in transactions, sorted alphabetically.

-}

{-# LANGUAGE MultiWayIf          #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}

module Hledger.Cli.Commands.Payees (
  payeesmode
 ,payees
) where

import Data.Text qualified as Text
import Data.Text.IO qualified as T
import System.Console.CmdArgs.Explicit

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Utils (printTitle)
import Data.List ((\\))
import Data.List.Extra (nubSort)


-- | Command line options for this command.
payeesmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Payees.txt")
  [flagNone ["used"]         (setboolopt "used")       "list payees used"
  ,flagNone ["declared"]     (setboolopt "declared")   "list payees declared"
  ,flagNone ["undeclared"]   (setboolopt "undeclared") "list payees used but not declared"
  ,flagNone ["unused"]       (setboolopt "unused")     "list payees declared but not used"
  ,flagNone ["find"]         (setboolopt "find")       "list the first payee matched by the first argument (a case-insensitive infix regexp)"
  ,flagNone ["directives"]   (setboolopt "directives") "show as payee directives, for use in journals"
  ]
  cligeneralflagsgroups1
  hiddenflags
  ([], Just $ argsFlag "[QUERY..]")

-- | The payees command.
payees :: CliOpts -> Journal -> IO ()
payees opts@CliOpts{rawopts_=rawopts, reportspec_=ReportSpec{_rsQuery=query, _rsReportOpts=ropts}} j = do
  printTitle ropts
  let
    matchedused       = dbg5 "matchedused"       $ nubSort $ map transactionPayee $ filter (matchesTransaction query) $ jtxns j
    matcheddeclared   = dbg5 "matcheddeclared"   $ nubSort $ filter (matchesPayee query) $ journalPayeesDeclared j
    -- unused/undeclared subtract the full used/declared sets, not the query-filtered ones,
    -- so that eg a date: query can't make a declared payee look undeclared.
    matchedunused     = dbg5 "matchedunused"     $ nubSort $ matcheddeclared \\ allused
    matchedundeclared = dbg5 "matchedundeclared" $ nubSort $ matchedused     \\ alldeclared
    matchedall        = dbg5 "matchedall"        $ nubSort $ matcheddeclared ++ matchedused
    found             = dbg5 "found"             $ findMatchedByArgument rawopts "payee" $ nubSort $ allused <> alldeclared
    allused           = map transactionPayee $ jtxns j
    alldeclared       = journalPayeesDeclared j
    -- With --directives, show as payee directives; a name containing a semicolon is double-quoted.
    showp p
      | boolopt "directives" rawopts = "payee " <> if Text.any (==';') p then "\"" <> p <> "\"" else p
      | otherwise = p
  mapM_ (T.putStrLn . showp) $ case declarablesSelectorFromOpts opts of
    Nothing         -> matchedall
    Just Used       -> matchedused
    Just Declared   -> matcheddeclared
    Just Undeclared -> matchedundeclared
    Just Unused     -> matchedunused
    Just FindFirst  -> [found]

