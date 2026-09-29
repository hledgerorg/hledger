{-|

The @accounts@ command lists account names:

- in flat mode (default), it lists the full names of accounts posted to by matched postings,
  clipped to the specified depth, possibly with leading components dropped.

- in tree mode, it shows the indented short names of accounts posted to by matched postings,
  and their parents, to the specified depth.

-}

{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Accounts (
  accountsmode
 ,accounts
) where

import Control.Monad (forM_)
import Data.List
import Data.Text qualified as T
import Data.Text.IO qualified as T
import System.Console.CmdArgs.Explicit as C

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Utils (printTitle)


-- | Command line options for this command.
accountsmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Accounts.txt")
  (
  [flagNone ["used","u"]     (setboolopt "used")       "list accounts used"
  ,flagNone ["declared","d"] (setboolopt "declared")   "list accounts declared"
  ,flagNone ["undeclared"]   (setboolopt "undeclared") "list accounts used but not declared"
  ,flagNone ["unused"]       (setboolopt "unused")     "list accounts declared but not used"
  ,flagNone ["find"]         (setboolopt "find")       "list the first account matched by the first argument (a case-insensitive infix regexp)"
  ,flagNone ["directives"]   (setboolopt "directives") "show as account directives, for use in journals"
  ,flagNone ["locations"]    (setboolopt "locations")  "also show where accounts were declared"
  ,flagNone ["types"]        (setboolopt "types")      "also show account types when known"
  ]
  ++ flattreeflags False ++
  [flagReq  ["drop"] (\s opts -> Right $ setopt "drop" s opts) "N" "flat mode: omit N leading account name parts"]
  )
  cligeneralflagsgroups1
  (hiddenflags ++
  [flagNone ["positions"]    (setboolopt "locations") "deprecated, use --locations instead"
  ])
  ([], Just $ argsFlag "[QUERY..]")

-- | The accounts command.
accounts :: CliOpts -> Journal -> IO ()
accounts opts@CliOpts{rawopts_=rawopts, reportspec_=ReportSpec{_rsQuery=query,_rsReportOpts=ropts}} j = do
  printTitle ropts

  -- 1. identify the accounts we'll show
  let tree     = tree_ ropts
      directives = boolopt "directives" rawopts
      locations = boolopt "locations" rawopts
      types = boolopt "types" rawopts
      -- Modified queries. These may not work with boolean queries (#2371).
      -- a depth limit will clip and exclude account names later, but we don't want to exclude accounts at this stage
      nodepthq = dbg4 "nodepthq" $ filterQuery (not . queryIsDepth) query
      -- just the acct: part of the query will be reapplied later, after clipping
      acctq = dbg4 "acctq" $ filterQuery queryIsAcct query
      dep = dbg4 "depth" $ queryDepth $ filterQuery queryIsDepth query
      -- when finding accounts used by postings, we remove tags that were declared on the posting,
      -- so that a tag: query will match account tags and not posting tags.
      matchedused = dbg5 "matchedused" $ nub $ map paccount $ journalPostings $
        filterJournalPostings nodepthq $ journalPostingsKeepAccountTagsOnly j
      matcheddeclared = dbg5 "matcheddeclared" $
        nub $
        filter (matchesAccountExtra (journalAccountType j) (journalInheritedAccountTags j) nodepthq) $
        map fst $ jdeclaredaccounts j
      -- unused/undeclared subtract the full used/declared sets, not the query-filtered ones,
      -- so that eg a date: query can't make a declared account look undeclared.
      matchedundeclared = dbg5 "matchedundeclared" $ nub $ matchedused \\ alldeclared
      matchedunused = dbg5 "matchedunused" $ nub $ matcheddeclared \\ allused
      allused = map paccount $ journalPostings j
      alldeclared = map fst $ jdeclaredaccounts j
      found = dbg5 "matchedacct" $ findMatchedByArgument rawopts "account" $ journalAccountNamesDeclaredOrImplied j
      matchedall = matcheddeclared ++ matchedused
      accts = dbg5 "accts to show" $
        case declarablesSelectorFromOpts opts of
          Nothing         -> matchedall
          Just Used       -> matchedused
          Just Declared   -> matcheddeclared
          Just Undeclared -> matchedundeclared
          Just Unused     -> matchedunused
          Just FindFirst  -> [found]

  -- 2. sort them by declaration order (then undeclared accounts alphabetically)
  -- within each group of siblings
      sortedaccts = sortAccountNamesByDeclaration j tree accts

  -- 2a. in tree mode, add parent accounts for tree structure context
      acctswithparents =
        if tree
        then dbg4 "acctswithparents" $
             sortAccountNamesByDeclaration j tree $  -- re-sort after adding parents
             expandAccountNames sortedaccts          -- add all parent accounts
        else sortedaccts

  -- 3. if there's a depth limit, depth-clip and remove any no longer useful items
      clippedaccts =
        dbg4 "clippedaccts" $
        (if tree then id else filter (matchesAccount acctq)) $  -- in tree mode, keep parent accounts even if they don't match
        nub $                            -- clipping can leave duplicates (adjacent, hopefully)
        filter (not . T.null) $          -- depth:0 can leave nulls
        map (clipAccountName dep) $      -- clip at depth if specified
        acctswithparents                 -- use expanded list instead of sortedaccts

  -- 4. print what remains as a list or tree, maybe applying --drop in the former case.
  -- Add various bits of info if enabled.
  let
    showKeyword = if directives then "account " else ""
    -- some contortions here to show types nicely aligned
    showName a = case accountlistmode_ ropts of
      ALTree -> indent <> accountLeafName droppedName
      ALFlat -> droppedName
      where
        indent      = T.replicate (2 * (max 0 (accountNameLevel a - drop_ ropts) - 1)) " "
        droppedName = accountNameDrop (drop_ ropts) a
    showType a =
      case (types, journalAccountType j a) of
        (True, Just t) -> pad a <> "    ; type: " <> T.pack (show t)
        _ -> ""
    showAcctDeclOrder a
      | locations =
        (if types then "," else pad a <> "    ;") <>
        case lookup a $ jdeclaredaccounts j of
          Just adi ->
            " declared at " <> (T.pack $ sourcePosPretty $ adisourcepos adi) <>  -- TODO: hide the column number
            ", overall declaration order " <> (T.pack $ show $ adideclarationorder adi)
          Nothing -> " undeclared"
      | otherwise = ""
    pad a = T.replicate (maxwidth - T.length (showName a)) " "
    maxwidth = maximum $ map (T.length . showName) clippedaccts

  forM_ clippedaccts $ \a -> T.putStrLn $ showKeyword <> showName a <> showType a <> showAcctDeclOrder a
