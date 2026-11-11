{-|
Checking assert directives: standing rules declared in the journal,
each a query which must match no rows, or some rows, of the equivalent balance report
(over the whole journal, or in every period of a period expression).
See the hledger manual's "assert directive" section, and doc/PLAN-assert-directive.md.

The rows are calculated here by direct accumulation over the journal's postings,
replicating what @hledger bal -E QUERY@ would show, rather than by running the balance report,
which would make journal reading depend on the reports code.
-}

{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}

module Hledger.Data.JournalChecks.Assert (
  journalCheckAsserts
)
where

import Control.Monad (mfilter)
import Data.Char (isAlphaNum)
import Data.HashMap.Strict qualified as HM
import Data.IntMap qualified as IM
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

-- | Check the rules of all this journal's assert directives, in parse order,
-- returning an error message for the first failure.
-- The day is today's date, for resolving relative dates in queries.
journalCheckAsserts :: Day -> Journal -> Either String ()
journalCheckAsserts today j = mapM_ (checkAssert today j acctids numberedps jspan) $ jasserts j
  where
    -- Calculated once, for all directives: the journal's postings in date order
    -- (stably, so same-day postings stay in parse order), each with its account number
    -- (see assertAccountQueriesEnabled), and the journal's date span.
    (acctids, numberedps) = numberPostingAccounts $ sortBy (comparing postingDate) $ journalPostings j
    jspan = journalDateSpan False j

-- | A posting's account names, as used by account query terms: its account,
-- and its original account (before aliasing or pivoting) if that is different.
type PostingAccounts = (AccountName, Maybe AccountName)

postingAccounts :: Posting -> PostingAccounts
postingAccounts p = (a, mfilter (/= a) $ paccount <$> poriginal p) where a = paccount p

-- | Number the distinct account names of these postings, returning the numbering,
-- and the postings with their numbers (in the same order).
numberPostingAccounts :: [Posting] -> (HM.HashMap PostingAccounts Int, [(Int, Posting)])
numberPostingAccounts ps = (ids, reverse numbered)
  where
    (ids, numbered) = foldl' number (HM.empty, []) ps
    number (m, acc) p = case HM.lookup k m of
      Just i  -> (m, (i, p) : acc)
      Nothing -> let !i = HM.size m in (HM.insert k i m, (i, p) : acc)
      where k = postingAccounts p

-- | Where an assert directive is checked: over the whole journal
-- (within the date: terms' span, if any), or within one period of its period expression.
data Checkpoint = WholeJournal DateSpan | Period DateSpan

-- | What matched at a failing checkpoint, shown in the error message:
-- the matching rows (account, change, balance), or, when the query has no
-- change:/balance: terms and so is about which postings exist, the matching postings.
data Evidence = MatchedRows [(AccountName, MixedAmount, MixedAmount)] | MatchedPostings [Posting]

-- | An account's running balance, and its matching-amount counts (see 'assertCountingEnabled').
data RunningBalance = RunningBalance !MixedAmount ![Int]

-- | Matching-amount counts: an optimisation for periodic rules with balance: terms.
-- These rules re-test an account's balance in each period where it changes, and a balance: term
-- matches a balance if any one of its single-commodity amounts does, so a balance holding many
-- commodities (dozens, or even hundreds) is costly to re-test. Instead, each running balance
-- keeps, for each balance: term, a count of its amounts which match; a posting changes only the
-- amounts in its own commodities, so only those are re-tested to update the counts, and the term
-- matches the balance when its count is above zero. This makes the cost per posting independent
-- of how many commodities the balance holds. (The error message's rows are still calculated
-- directly, see evidenceAt.)
--
-- The one rule for this code: with the counts, balanceMatches must give exactly what testing the
-- whole balance would. To disable the optimisation, eg while investigating a wrong result, set
-- this to False: balances are then re-tested in full, which is slower but simpler.
-- The code it enables is marked "matching-amount counts" in checkAssert.
assertCountingEnabled :: Bool
assertCountingEnabled = True

-- | Per-account queries: an optimisation for selecting each rule's postings.
-- Each rule's query is tested against every posting in the journal, and its account terms
-- (acct:, type:, depth:) are regular expression matches against the posting's account name,
-- which cost much more than the rest. But postings share a few account names, so instead,
-- for each distinct account name the query is partially evaluated (see 'postingQueryForAccount'),
-- leaving a smaller query (usually just "match all" or "match none") to test against that
-- account's postings. This makes selecting postings several times cheaper.
--
-- The one rule for this code: the per-account query must match exactly the postings
-- the whole query would. To disable the optimisation, eg while investigating a wrong result,
-- set this to False: each posting is then tested with the whole query.
assertAccountQueriesEnabled :: Bool
assertAccountQueriesEnabled = True

-- A possible further optimisation, if many rules become common: each rule still scans all
-- of the journal's postings, so with 100 rules (on a large journal, measured 2026-11-10)
-- a bal report took about 3.5 times as long. Grouping the postings by account once, for
-- all rules, would let each rule visit only the accounts its per-account query doesn't
-- rule out (merging their postings by date), so that a rule about a few accounts would
-- cost almost nothing. Rules about many accounts would cost about the same as now.

-- | Check one assert directive's rule, given the journal's account numbering (see 'numberPostingAccounts'),
-- its postings in date order with their account numbers, and its date span.
-- Each checkpoint is the balance report @bal -E -b START -e END QUERY@: its rows are the
-- accounts (clipped to the query's depth) with postings matching the query in the period,
-- plus, when the query has balance: terms, the accounts with earlier postings (whose change
-- may be zero); each row has its change in the period and its balance at the period end.
-- Checking stops at the first failing checkpoint, and only then are its rows calculated in full,
-- for the error message.
checkAssert :: Day -> Journal -> HM.HashMap PostingAccounts Int -> [(Int, Posting)] -> DateSpan -> AssertDirective -> Either String ()
checkAssert today j acctids numberedps jspan ad@AssertDirective{adQuantifier=quant, adPeriod=mperiod, adQueryText=querytxt} = do
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
    selectPostings' clip = filter hasAmount . mapMaybe (prepare clip . snd) . filter selected
    atype = journalAccountType j
    selected (i, p)
      | assertAccountQueriesEnabled = matchesPostingExtra atype (IM.findWithDefault postingq i queriesbyaccount) p
      | otherwise                   = matchesPostingExtra atype postingq p
    -- The posting query, partially evaluated for each account (lazily, when first needed).
    queriesbyaccount = IM.fromList [(i, postingQueryForAccount atype a morig postingq) | ((a, morig), i) <- HM.toList acctids]
    prepare clip p = do
      p' <- if queryIsNull amtq then Just p else filterPostingAmount amtq p
      Just $ postingStripCosts $ if clip then p'{paccount = clipOrEllipsifyAccountName depthspec $ paccount p'} else p'
    ps = selectPostings numberedps

    hasrowterms = not $ queryIsNull rowq
    hasbalanceq = queryHasBalance rowq
    haschangeq  = queryHasChange rowq
    passes anymatched = case quant of
      AssertNone -> not anymatched
      AssertSome -> anymatched
    before mend p    = maybe True (postingDate p <) mend
    onOrAfter mstart p = maybe True (postingDate p >=) mstart

    -- Amounts by account: a period's changes, or (for the error message) the balances.
    addPosting m p = M.insertWith (flip maPlus) (paccount p) (pamount p) m
    amountsOf = foldl' addPosting M.empty
    balanceOf balances a = M.findWithDefault nullmixedamt a balances

    -- The change: and balance: terms, as amount comparisons, each with whether it is negated.
    -- (They are combined by AND, see querySplitRowTerms.)
    changeterms  = [(neg, Amt o n mc) | (neg, Change o n mc)  <- signedRowTerms rowq]
    balanceterms = [(neg, Amt o n mc) | (neg, Balance o n mc) <- signedRowTerms rowq]
    changeMatches chg = and [neg /= matchesMixedAmount t chg | (neg, t) <- changeterms]
    zerochangematches = changeMatches nullmixedamt

    -- Running balances by account. With assertCountingEnabled, these also have the matching-amount counts.
    addPostingRunning m p = M.insert (paccount p) (RunningBalance bal' counts') m
      where
        RunningBalance bal counts = M.findWithDefault (RunningBalance nullmixedamt $ map (const 0) balanceterms) (paccount p) m
        bal'    = bal `maPlus` pamount p
        counts' | assertCountingEnabled = updateMatchCounts bal bal' (pamount p) counts
                | otherwise             = counts
    -- Does this running balance match the balance: terms ?
    balanceMatches (RunningBalance bal@(Mixed amts) counts)
      | assertCountingEnabled && not (M.null amts) = and [neg /= (c > 0) | ((neg, _), c) <- zip balanceterms counts]
      | otherwise = and [neg /= matchesMixedAmount t bal | (neg, t) <- balanceterms]

    --- matching-amount counts (see assertCountingEnabled)
    -- Update an account's matching-amount counts, given its balance before and after a posting, and the
    -- posting's amount: only the amounts in the posting's commodities have changed, so only they are re-tested.
    updateMatchCounts bal bal' (Mixed pamts) counts = forceElems $ zipWith (+) counts
      [ sum [fromEnum (matchesIn bal' k) - fromEnum (matchesIn bal k) | k <- M.keys pamts]
      | (_, t) <- balanceterms
      , let matchesIn (Mixed amts) k = maybe False (matchesAmount t) $ M.lookup k amts ]
      where forceElems xs = foldr seq xs xs
    --- end of matching-amount counts

    -- The first failing checkpoint, if any.
    mfailure = case mperiod of
      -- One checkpoint, the whole journal within the date: span.
      Nothing -> WholeJournal <$> firstFailing M.empty S.empty ps [datespan]
      Just (interval, spn) -> Period <$> firstFailing M.empty S.empty ps periods
        where
          -- The periods, as the balance report would calculate them: from the period expression's span
          -- and the date: terms' span, with open ends filled from the journal's span,
          -- and adjusted to interval boundaries unless a start date was specified.
          requestedspan = spn `spanIntersect` datespan
          periods = splitSpanToDateSpans (isNothing $ spanStart requestedspan) interval $
                    requestedspan `spanValidDefaultsFrom` jspan

    -- Check each period in turn, stopping at the first failure. Postings before the first period
    -- count in the balances only, and postings after the last are ignored.
    -- With balance: terms, this maintains the running balances, and the set of accounts whose
    -- balance matches the balance: terms, updating only the accounts posted to in each period.
    -- Each period's rows are the accounts with postings in it, plus, with balance: terms, the
    -- accounts with earlier postings, whose change is zero. Without change:/balance: terms every
    -- row matches, so it's just whether the period has any postings.
    firstFailing _ _ _ [] = Nothing
    firstFailing !balances !matching remaining (sp:sps)
      | passes anyrowmatches = firstFailing balances' matching' later sps
      | otherwise            = Just sp
      where
        (upto, later) = span (before $ spanEnd sp) remaining
        now           = dropWhile (not . onOrAfter (spanStart sp)) upto
        changes       = amountsOf now
        (balances', matching')
          | hasbalanceq = (bals, foldl' upd matching $ S.fromList $ map paccount upto)
          | otherwise   = (balances, matching)
          where
            bals = foldl' addPostingRunning balances upto
            upd s a = if maybe False balanceMatches (M.lookup a bals) then S.insert a s else S.delete a s
        anyrowmatches
          | not hasrowterms = not $ null now
          | not hasbalanceq = any changeMatches changes
          | not haschangeq  = not $ S.null matching'
          | otherwise       = any (\(a, chg) -> a `S.member` matching' && changeMatches chg) (M.toList changes)
                              || (zerochangematches && any (`M.notMember` changes) (S.toList matching'))

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
        inspan'       = filter (onOrAfter mstart) $ takeWhile (before mend) $ selectPostings' False numberedps
        changes       = amountsOf inspan
        balances      = amountsOf $ pre ++ inspan
        rows | hasbalanceq = [(a, M.findWithDefault nullmixedamt a changes, bal) | (a, bal) <- M.toAscList balances]
             | otherwise   = [(a, chg, balanceOf balances a) | (a, chg) <- M.toAscList changes]

  maybe (Right ()) (\cp -> Left $ assertFailureMessage ad rowq cp $ evidenceAt cp) mfailure

-- | The change: and balance: terms of a row query (see 'querySplitRowTerms'), each with whether it is negated.
signedRowTerms :: Query -> [(Bool, Query)]
signedRowTerms (And qs) = concatMap signedRowTerms qs
signedRowTerms (Not q)  = [(not neg, t) | (neg, t) <- signedRowTerms q]
signedRowTerms q        = [(False, q) | queryIsRowTerm q]

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
