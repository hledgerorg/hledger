{-|
Checking assert directives: standing rules declared in the journal,
each a query which must match no rows, or some rows, of the equivalent balance report
(over the whole journal, or in every period of a period expression).
See the hledger manual's "assert directive" section, and doc/PLAN-assert-directive.md.

The rows are calculated here by direct accumulation over the journal's postings,
replicating what @hledger bal -E QUERY@ would show, rather than by running the balance report,
which would make journal reading depend on the reports code.
-}

{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}

module Hledger.Data.JournalChecks.Assert (
  journalCheckAssertDirectives
)
where

import Data.Char (isAlphaNum)
#if !MIN_VERSION_base(4,20,0)
import Data.List (foldl')
#endif
import Data.List (sortBy, transpose)
import Data.Map.Strict qualified as M
import Data.Maybe (isNothing, mapMaybe)
import Data.Ord (comparing)
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar (Day, addDays)
import Text.Printf (printf)
import Text.Megaparsec (SourcePos(..), unPos)

import Hledger.Data.AccountName (clipOrEllipsifyAccountName)
import Hledger.Data.Amount (maPlus, nullmixedamt, showMixedAmountOneLine)
import Hledger.Data.Dates (showDate, showDateSpan, spanEnd, spanIntersect, spanStart, spanValidDefaultsFrom)
import Hledger.Data.DayPartition (splitSpanToDateSpans)
import Hledger.Data.Errors (decorateExcerpt)
import Hledger.Data.Journal (filterPostingAmount, journalAccountType, journalDateSpan, journalPostings)
import Hledger.Data.Posting (hasAmount, postingDate, postingStripCosts)
import Hledger.Data.Types
import Hledger.Query
import Hledger.Utils (fitText)
import Text.DocLayout (realLength)

-- | Check all of this journal's assert directives, in parse order,
-- returning an error message for the first failure.
-- The day is today's date, for resolving relative dates in queries.
journalCheckAssertDirectives :: Day -> Journal -> Either String ()
journalCheckAssertDirectives today j = mapM_ (checkAssertDirective today j sortedps jspan) $ jasserts j
  where
    -- Calculated once, for all directives: the journal's postings in date order
    -- (stably, so same-day postings stay in parse order), and its date span.
    sortedps = sortBy (comparing postingDate) $ journalPostings j
    jspan    = journalDateSpan False j

-- | Where an assert directive is checked: over the whole journal
-- (within the date: terms' span, if any), or within one period of its period expression.
data Checkpoint = WholeJournal DateSpan | Period DateSpan

-- | What matched at a failing checkpoint, shown in the error message:
-- the matching rows (account, change, balance), or, when the query has no
-- change:/balance: terms and so is about which postings exist, the matching postings.
data Evidence = MatchedRows [(AccountName, MixedAmount, MixedAmount)] | MatchedPostings [Posting]

-- | Check one assert directive, given the journal's postings in date order and its date span.
-- Each checkpoint is the balance report @bal -E -b START -e END QUERY@: its rows are the
-- accounts (clipped to the query's depth) with postings matching the query in the period,
-- plus, when the query has balance: terms, the accounts with earlier postings (whose change
-- may be zero); each row has its change in the period and its balance at the period end.
-- Checking stops at the first failing checkpoint, and only then are its rows calculated in full,
-- for the error message.
checkAssertDirective :: Day -> Journal -> [Posting] -> DateSpan -> AssertDirective -> Either String ()
checkAssertDirective today j sortedps jspan ad@AssertDirective{adQuantifier=quant, adPeriod=mperiod, adQueryText=querytxt} = do
  (rowq, otherq) <- either (Left . (errorPrefix ad <>)) Right $ querySplitRowTerms . fst =<< parseQuery today querytxt
  let
    -- As in the balance report, date: terms don't select postings; they set the report period,
    -- intersected with the period expression's span if any. (date2: terms are ignored, as in bal without --date2.)
    datespan = queryDateSpan False otherq

    -- The postings selected by the other non-row query terms, prepared as the balance report would:
    -- amounts limited to the parts matching amt:/cur: terms, costs stripped,
    -- account names clipped to the depth: terms' depth. Still in date order. Generated lazily, so checks can stop early.
    -- (selectPostings' False leaves account names unclipped, for showing postings in an error message.)
    depthspec = queryDepth otherq
    postingq  = filterQuery (not . queryIsDateOrDate2) $ filterQuery (not . queryIsDepth) otherq
    amtq      = filterQuery queryIsAmtOrCur postingq
    selectPostings = selectPostings' True
    selectPostings' clip = filter hasAmount . mapMaybe (prepare clip) . filter (matchesPostingExtra (journalAccountType j) postingq)
    prepare clip p = do
      p' <- if queryIsNull amtq then Just p else filterPostingAmount amtq p
      Just $ postingStripCosts $ if clip then p'{paccount = clipOrEllipsifyAccountName depthspec $ paccount p'} else p'
    ps = selectPostings sortedps

    hasrowterms = not $ queryIsNull rowq
    hasbalanceq = queryHasBalance rowq
    passes anymatched = case quant of
      AssertNone -> not anymatched
      AssertSome -> anymatched
    before mend p    = maybe True (postingDate p <) mend
    onOrAfter mstart p = maybe True (postingDate p >=) mstart

    -- Amounts by account: a period's changes, or the running balances.
    addPosting m p = M.insertWith (flip maPlus) (paccount p) (pamount p) m
    amountsOf = foldl' addPosting M.empty
    balanceOf balances a = M.findWithDefault nullmixedamt a balances

    -- Does a checkpoint have a matching row ? Given the period's changes by account, the balances
    -- at the period end, and the "quiet matches": the accounts whose row would match if they had
    -- no change in the period (maintained incrementally across periods, when balance: terms make
    -- such accounts rows). Without change:/balance: terms every row matches, so it's just whether
    -- the period has any postings.
    anyRowMatches changes balances quiet
      | not hasrowterms = not $ M.null changes
      | otherwise = any (\(a, chg) -> matchesRowAmounts rowq chg $ balanceOf balances a) (M.toList changes)
                 || any (`M.notMember` changes) (S.toList quiet)
    -- Update the quiet matches for these accounts, whose balances have changed.
    updateQuiet balances quiet accts
      | not hasbalanceq = quiet
      | otherwise = foldl' upd quiet accts
      where upd s a = if matchesRowAmounts rowq nullmixedamt (balanceOf balances a) then S.insert a s else S.delete a s

    -- The first failing checkpoint, if any.
    mfailure = case mperiod of
      Nothing ->
        -- One checkpoint, the whole journal within the date: span: postings before it count in the balances, postings after it not at all.
        let (pre, inspan) = span (not . onOrAfter (spanStart datespan)) $ takeWhile (before $ spanEnd datespan) ps
            changes  = amountsOf inspan
            balances = amountsOf $ pre ++ inspan
            quiet    = updateQuiet balances S.empty $ M.keys balances
        in if passes (anyRowMatches changes balances quiet) then Nothing else Just (WholeJournal datespan)
      Just (interval, spn) -> firstFailing M.empty S.empty ps periods
        where
          -- The periods, as the balance report would calculate them: from the period expression's span
          -- and the date: terms' span, with open ends filled from the journal's span,
          -- and adjusted to interval boundaries unless a start date was specified.
          requestedspan = spn `spanIntersect` datespan
          periods = splitSpanToDateSpans (isNothing $ spanStart requestedspan) interval $
                    requestedspan `spanValidDefaultsFrom` jspan

    -- Check each period in turn, accumulating the running balances (postings before the first
    -- period count in them) and the quiet matches, and stopping at the first failure.
    firstFailing _ _ _ [] = Nothing
    firstFailing balances quiet remaining (sp:sps)
      | passes (anyRowMatches changes balances' quiet') = firstFailing balances' quiet' later sps
      | otherwise = Just (Period sp)
      where
        (upto, later) = span (before $ spanEnd sp) remaining
        now           = dropWhile (not . onOrAfter (spanStart sp)) upto  -- postings before the first period count in the balances only
        changes       = amountsOf now
        balances'     = foldl' addPosting balances upto
        quiet'        = updateQuiet balances' quiet $ map paccount upto

    -- The evidence for the error message, calculated again from the start at the failing checkpoint.
    evidenceAt cp
      | not hasrowterms = MatchedPostings inspan'
      | otherwise = MatchedRows
          [ (a, chg, bal) | (a, chg, bal) <- rows, matchesRowAmounts rowq chg bal ]
      where
        (mstart, mend) = case cp of
          WholeJournal sp -> (spanStart sp, spanEnd sp)
          Period sp       -> (spanStart sp, spanEnd sp)
        (pre, inspan) = span (not . onOrAfter mstart) $ takeWhile (before mend) ps
        inspan'       = filter (onOrAfter mstart) $ takeWhile (before mend) $ selectPostings' False sortedps
        changes       = amountsOf inspan
        balances      = amountsOf $ pre ++ inspan
        rows | hasbalanceq = [(a, M.findWithDefault nullmixedamt a changes, bal) | (a, bal) <- M.toAscList balances]
             | otherwise   = [(a, chg, balanceOf balances a) | (a, chg) <- M.toAscList changes]

  maybe (Right ()) (\cp -> Left $ assertFailureMessage ad rowq cp $ evidenceAt cp) mfailure

-- | The first line(s) of an assert directive error: file position and excerpt.
errorPrefix :: AssertDirective -> String
errorPrefix AssertDirective{adSourcePos=SourcePos f l _, adSourceText=txt} =
  printf "%s:%d:\n%s\n" f (unPos l) (decorateExcerpt (unPos l) Nothing $ txt <> "\n")

-- | Explain an assert directive's failure at a checkpoint: which rows (changes, balances, or both)
-- or postings matched, up to a limit, or that none did, and the equivalent report command:
-- a balance report for rows, a register for postings.
assertFailureMessage :: AssertDirective -> Query -> Checkpoint -> Evidence -> String
assertFailureMessage ad@AssertDirective{adQuantifier=quant, adQueryText=querytxt} rowq cp evidence =
  errorPrefix ad <> T.unpack (T.unlines $ explanation <> [reportline])
  where
    maxshown = 10
    (noun, lines', cmd) = case evidence of
      MatchedPostings ps -> ("postings", showPostings ps, ["reg"])
      -- With balance: terms, -H makes bal show the balances which were tested, not the period's changes.
      MatchedRows rows   -> (rowsnoun, showRows rows, ["bal", "-E"] <> ["-H" | queryHasBalance rowq])
    -- What the rows' tested amounts are called, and which are shown.
    (rowsnoun, showRows) = case (queryHasChange rowq, queryHasBalance rowq) of
      (True, False) -> ("changes",  \rows -> alignColumns [False, True]       [[a, showamt chg] | (a, chg, _) <- rows])
      (False, _)    -> ("balances", \rows -> alignColumns [False, True]       [[a, showamt bal] | (a, _, bal) <- rows])
      (True, True)  -> ("accounts", \rows -> alignColumns [False, True, True] [[a, showamt chg, showamt bal] | (a, chg, bal) <- rows])
    showamt = T.pack . showMixedAmountOneLine
    (shown, hidden) = splitAt maxshown lines'
    explanation = case quant of
      AssertNone ->
        ("This assert directive failed " <> checkpointdesc <> ".")
        : ("These " <> noun <> " matched" <> (if rowsnoun == "accounts" && noun == rowsnoun then " (change, balance)" else "") <> ":")
        : map ("  " <>) shown
        <> ["  ...and " <> T.pack (show $ length hidden) <> " more." | not $ null hidden]
      AssertSome -> ["This assert directive failed " <> checkpointdesc <> ": no " <> noun <> " matched."]
    reportline = (if null hidden then "To see the report: " else "To see them all: ") <> reportcmd

    checkpointdesc = case cp of
      WholeJournal (DateSpan Nothing Nothing) -> "(checked over the whole journal)"
      WholeJournal sp -> "(checked over the period " <> showDateSpan sp <> ")"
      Period sp -> case (spanStart sp, fmap (addDays (-1)) $ spanEnd sp) of
        (Just s, Just e) | s == e -> "on " <> showDate e
        _                         -> "for the period " <> showDateSpan sp

    reportcmd = T.unwords $ ["hledger"] <> cmd <> periodflags <> map shellQuote (filter (not . T.null) $ words'' queryprefixes querytxt)
    periodflags = case cp of
      WholeJournal _ -> []
      Period sp      -> dateflag "-b" (spanStart sp) <> dateflag "-e" (spanEnd sp)
    dateflag flag = maybe [] (\d -> [flag, showDate d])

-- | Render postings as aligned lines: date, description (abbreviated), account name, right-aligned amount.
showPostings :: [Posting] -> [Text]
showPostings ps = alignColumns [False, False, False, True]
  [ [showDate $ postingDate p, fitText Nothing (Just 30) True True desc, paccount p, T.pack $ showMixedAmountOneLine $ pamount p]
  | p <- ps, let desc = maybe "" tdescription $ ptransaction p ]

-- | Lay out a table as lines of text, with two spaces between columns,
-- each column left- or right-aligned (if its flag is true) to its widest cell.
-- Columns which are empty in every row are left out.
alignColumns :: [Bool] -> [[Text]] -> [Text]
alignColumns rightaligns rows = map T.stripEnd $ map (T.intercalate "  ") $ transpose
  [map (pad right $ foldl' max 0 $ map realLength col) col | (right, col) <- zip rightaligns $ transpose rows, any (not . T.null) col]
  where pad right w = fitText (Just w) Nothing False (not right)

-- | Quote a query term for a shell command line, if needed.
shellQuote :: Text -> Text
shellQuote t
  | not (T.null t) && T.all safe t = t
  | otherwise = "'" <> T.replace "'" "'\\''" t <> "'"
  where safe c = isAlphaNum c || c `elem` (":._-/+=@,%" :: String)
