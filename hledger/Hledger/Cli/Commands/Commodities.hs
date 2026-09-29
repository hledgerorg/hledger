{-|

The @commodities@ command lists commodity/currency symbols.

-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Commodities (
  commoditiesmode
 ,commodities
) where

import Data.Char (isDigit)
import Data.Map qualified as M
import Data.Maybe (fromMaybe)
import Data.Set qualified as S
import Data.Text qualified as Text
import Data.Text.IO qualified as T
import System.Console.CmdArgs.Explicit

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Utils (printTitle)
import Data.List.Extra (nubSort)
import Data.List ((\\))


-- | Command line options for this command.
commoditiesmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Commodities.txt")
  [flagNone ["used"]         (setboolopt "used")       "list commodities used in transactions"
  ,flagNone ["priced"]       (setboolopt "priced")     "list commodities appearing in P directives"
  ,flagNone ["declared"]     (setboolopt "declared")   "list commodities declared by commodity directives"
  ,flagNone ["undeclared"]   (setboolopt "undeclared") "list commodities used or priced but not declared"
  ,flagNone ["unused"]       (setboolopt "unused")     "list commodities declared but not used or priced"
  ,flagNone ["find"]         (setboolopt "find")       "list the first commodity matched by the first argument (a case-insensitive infix regexp)"
  ,flagNone ["directives"]   (setboolopt "directives") "show as commodity directives (with their display styles), for use in journals"
  ]
  [generalflagsgroup2]
  confflags
  ([], Just $ argsFlag "[QUERY..]")

commodities :: CliOpts -> Journal -> IO ()
commodities opts@CliOpts{rawopts_=rawopts, reportspec_=ReportSpec{_rsQuery=query, _rsReportOpts=ropts}} j = do
  printTitle ropts
  let
    -- The "used" set is commodities appearing in transactions (postings and
    -- their costs). The "priced" set is commodities appearing in P (price)
    -- directives. A date query (or report period) narrows both sets to the
    -- matching transactions/directives. Dateless sources (commodity
    -- directives) are excluded under a date query, which is why --declared
    -- and --unused ignore it. Other query terms (cur:, tag:, ...) filter
    -- the final commodity name list.
    dateq    = filterQuery queryIsDate query
    nondateq = filterQuery (not . queryIsDate) query
    hasdateq = not $ queryIsNull dateq
    jmatched = j { jtxns = dbg5With (\xs -> "txnsmatched: " <> show (length xs))
                      $ filter (matchesTransaction    dateq) (jtxns j)
                 , jpricedirectives = dbg5With (\xs -> "pricedirectivesmatched: " <> show (length xs))
                      $ filter (matchesPriceDirective dateq) (jpricedirectives j)
                 }
    filt = filter (matchesCommodityExtra (journalCommodityTags j) nondateq)
    txusedmatched = dbg5 "txusedmatched" $ S.toList $ journalCommoditiesFromTransactions    jmatched
    pricedmatched = dbg5 "pricedmatched" $ S.toList $ journalCommoditiesFromPriceDirectives jmatched
    refdmatched   = dbg5 "refdmatched"   $ nubSort $ txusedmatched <> pricedmatched
    refdall       = dbg5 "refdall"       $ S.toList $
                      journalCommoditiesFromTransactions    j
                   <> journalCommoditiesFromPriceDirectives j
    declared'     = dbg5 "declared"      $ M.keys $ jdeclaredcommodities j
    unused        = dbg5 "unused"        $ declared'   \\ refdall      -- whole-journal hygiene; date ignored
    undeclared    = dbg5 "undeclared"    $ refdmatched \\ declared'    -- date narrows the used+priced side
    -- Default: declared ∪ transacted ∪ priced. Under a date query, declarations are dropped (dateless).
    all'          = dbg5 "all"           $ if hasdateq then refdmatched
                                                       else nubSort $ declared' <> refdall
    -- --find is a name lookup over all known commodity names; date queries don't apply.
    found         = dbg5 "found"         $ findMatchedByArgument rawopts "commodity" $
                      nubSort $ declared' <> refdall

    -- With --directives, show each commodity as a commodity directive declaring its
    -- (declared or inferred) display style, using a sample amount. A decimal mark is
    -- always included, since the directive requires one (eg: commodity 1000. AAPL).
    showc c
      | boolopt "directives" rawopts = "commodity " <> ensureDecimalMark (wbToText $ showAmountB fmt sample)
      | otherwise = c
      where
        style  = M.findWithDefault amountstyle c $ journalCommodityStyles j
        sample = nullamt{acommodity=c, aquantity=1000, astyle=style}
        fmt    = defaultFmt{displayForceDecimalMark=True}
        mark   = fromMaybe '.' $ asdecimalmark style
        -- add a decimal mark after the last digit, if the number has none
        ensureDecimalMark t
          | Text.any (==mark) (if Text.null c then t else Text.replace c "" t) = t
          | otherwise = case Text.findIndex isDigit (Text.reverse t) of
              Just i  -> let n = Text.length t - i in Text.take n t <> Text.singleton mark <> Text.drop n t
              Nothing -> t

  -- --priced is specific to commodities, not part of the shared DeclarablesSelector.
  -- Enforce the mutex with the other selectors locally.
  mapM_ (T.putStrLn . showc) $
    case (boolopt "priced" rawopts, declarablesSelectorFromOpts opts) of
      (True,  Nothing)         -> filt pricedmatched
      (True,  Just _)          -> error' "please pick at most one of --used, --priced, --declared, --undeclared, --unused, --find"
      (False, Nothing)         -> filt all'
      (False, Just Used)       -> filt txusedmatched
      (False, Just Declared)   -> filt declared'
      (False, Just Undeclared) -> filt undeclared
      (False, Just Unused)     -> filt unused
      (False, Just FindFirst)  -> [found]
