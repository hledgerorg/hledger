{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TupleSections #-}

module Hledger.Cli.Commands.Tags (
  tagsmode
 ,tags
)
where

import Control.Monad.Fail qualified as Fail
import Data.List.Extra (nubSort)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import Safe
import System.Console.CmdArgs.Explicit

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Utils (printTitle)
import Data.Function ((&))
import Data.Maybe (fromMaybe)
import Data.List (find)


tagsmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Tags.txt")
  [
   flagNone ["used"]         (setboolopt "used")       "list tags used"
  ,flagNone ["declared"]     (setboolopt "declared")   "list tags declared"
  ,flagNone ["undeclared"]   (setboolopt "undeclared") "list tags used but not declared"
  ,flagNone ["unused"]       (setboolopt "unused")     "list tags declared but not used"
  ,flagNone ["find"]         (setboolopt "find")       "list the first tag whose name is matched by the first argument (a case-insensitive infix regexp)"
  ,flagNone ["values"]       (setboolopt "values")     "list tag values instead of tag names"
  ,flagNone ["parsed"]       (setboolopt "parsed")     "show them in the order they were parsed (mostly), including duplicates"
  ,flagNone ["directives"]   (setboolopt "directives") "show tag names as tag directives, for use in journals"
  ]
  cligeneralflagsgroups1
  hiddenflags
  ([], Just $ argsFlag "[TAGREGEX [QUERY..]]")

tags :: CliOpts -> Journal -> IO ()
tags opts@CliOpts{rawopts_=rawopts, reportspec_=rspec@ReportSpec{_rsQuery=_q, _rsReportOpts=ropts}} j = do
  printTitle ropts
  let today = _rsDay rspec
      args = listofstringopt "args" rawopts
  -- For convenience/power, the first argument is a tag name regex, 
  -- separate from the main query arguments: hledger tags [TAGREGEX [QUERYARGS..]]
  -- So we have to re-parse the query here. Overcomplicated ?
  mtagpat <- mapM (either Fail.fail pure . toRegexCI . T.pack) $ headMay args
  let
    values   = boolopt "values" rawopts
    parsed   = boolopt "parsed" rawopts
    directives = boolopt "directives" rawopts && not values
    empty    = empty_ ropts
    querystr = map T.pack $ drop 1 args
  query <- either usageError (return . fst) $ parseQueryList today querystr
  let
    q = simplifyQuery $ And [queryFromFlags ropts, query]
    txns = filter (q `matchesTransaction`) $ jtxns $ journalApplyValuationFromOpts rspec j
    accts =
      -- also search for tags in matched account declarations,
      -- unless there is a query for something transaction-specific, like date: or amt:.
      if dbg5 "queryIsTransactionRelated" $ queryIsTransactionRelated $ dbg4 "q" q
      then []
      else filter (matchesAccountExtra (journalAccountType j) (journalInheritedAccountTags j) q) $
           map fst $ jdeclaredaccounts j
    -- bit of a mess.
    used       = dbg5 "used"       $ concatMap (journalAccountTags j) accts ++ concatMap transactionAllTags txns
    declared'  = dbg5 "declared'"  $ map (,"") $ journalTagsDeclared j
    filtereddeclared  = dbg5 "filtereddeclared'"  $ filter (q `matchesTag`) declared'
    (usednames, declarednames) = (map fst used, map fst filtereddeclared)
    unused     = dbg5 "unused"     $ filter (not . (`elem` usednames) . fst) filtereddeclared
    undeclared = dbg5 "undeclared" $ filter (not . (`elem` declarednames) . fst) used
    all'       = dbg5 "all''"      $ filtereddeclared <> used
    found      = dbg5 "found"      $ foundtag
      where
        -- First find the name, then the first occurrence of that tag.
        -- So that --values and --parsed still work with --find (in some reasonably stable way).
        alltags = declared' <> used
        allnames = dbg5 "allnames" $ nubSort $ map fst alltags
        foundname = dbg5 "foundname" $ findMatchedByArgument rawopts "tag name" allnames
        foundtag = find ((==foundname).fst) alltags
          & fromMaybe (error' "tags: could not find a tag's first occurrence")  -- PARTIAL: should not happen because allnames and alltags correspond

    tags' =
      case declarablesSelectorFromOpts opts of
        Nothing         -> all'
        Just Used       -> used
        Just Declared   -> declared'
        Just Undeclared -> undeclared
        Just Unused     -> unused
        Just FindFirst  -> [found]

    results =
      (if parsed then id else nubSort)
      [ r
      | (t,v) <- tags'
      , maybe True (`regexMatchText` t) mtagpat
      , let r = if values then v else if directives then "tag " <> t else t
      , not (values && T.null v && not empty)
      ]

  mapM_ T.putStrLn results
