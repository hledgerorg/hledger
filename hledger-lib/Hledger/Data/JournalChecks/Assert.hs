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
import Safe (headMay, lastMay)
import Data.Ord (comparing)
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar (Day, addDays)
import Text.Printf (printf)
import Text.Megaparsec (SourcePos(..), unPos)

import Hledger.Data.AccountName (clipOrEllipsifyAccountName)
import Hledger.Data.Amount (maPlus, nullmixedamt, showMixedAmountOneLine)
import Hledger.Data.Dates (showDate, showDateSpan, spanContainsDate, spanEnd, spanIntersect, spanStart, spanValidDefaultsFrom)
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

-- | What matched at a failing checkpoint, shown in the error message:
-- the matching rows (account, change, balance), or, when the query has no
-- change:/balance: terms and so is about which postings exist, the matching postings.
-- (At a failing checkpoint of a some rule, nothing matched.)
data Evidence = MatchedRows [(AccountName, MixedAmount, MixedAmount)] | MatchedPostings [Posting]

-- | A failing checkpoint: its span, how many rows or postings matched there,
-- and the first of them (as many as the error message may still show).
data Failure = Failure !DateSpan !Int Evidence

-- | Keep only the first n items of some evidence.
takeEvidence :: Int -> Evidence -> Evidence
takeEvidence n (MatchedRows rows)   = MatchedRows $ take n rows
takeEvidence n (MatchedPostings ps) = MatchedPostings $ take n ps

-- | How many items some evidence has.
evidenceSize :: Evidence -> Int
evidenceSize (MatchedRows rows)   = length rows
evidenceSize (MatchedPostings ps) = length ps

-- | Evaluate some evidence fully, so that it doesn't keep the checking state of its checkpoint alive.
forceEvidence :: Evidence -> ()
forceEvidence (MatchedPostings ps) = length ps `seq` ()
forceEvidence (MatchedRows rows)   = foldr (\(a, chg, bal) r -> a `seq` chg `seq` bal `seq` r) () rows

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
-- All checkpoints are checked, so that a failure can report every failing checkpoint, and what matched there.
checkAssert :: Day -> Journal -> HM.HashMap PostingAccounts Int -> [(Int, Posting)] -> DateSpan -> AssertDirective -> Either String ()
checkAssert today j acctids numberedps jspan ad@AssertDirective{adQuantifier=quant, adPeriod=mperiod, adQueryText=querytxt, adSkips=skips} = do
  (rowq, otherq) <- either (Left . (errorPrefix ad <>)) Right $ querySplitRowTerms . fst =<< parseQuery today querytxt
  let
    -- As in the balance report, date: terms don't select postings; they set the report period,
    -- intersected with the period expression's span if any. (date2: terms are ignored, as in bal without --date2.)
    datespan = queryDateSpan False otherq

    -- The postings selected by the other non-row query terms, prepared as the balance report would:
    -- amounts limited to the parts matching amt:/cur: terms, and costs stripped. Still in date order,
    -- and generated lazily. Each is paired with a copy whose account name is clipped to the depth: terms'
    -- depth: the copies are what is checked, the originals are what an error message shows.
    depthspec = queryDepth otherq
    postingq  = filterQuery (not . queryIsDateOrDate2) $ filterQuery (not . queryIsDepth) otherq
    amtq      = filterQuery queryIsAmtOrCur postingq
    atype = journalAccountType j
    selected (i, p)
      | assertAccountQueriesEnabled = matchesPostingExtra atype (IM.findWithDefault postingq i queriesbyaccount) p
      | otherwise                   = matchesPostingExtra atype postingq p
    -- The posting query, partially evaluated for each account (lazily, when first needed).
    queriesbyaccount = IM.fromList [(i, postingQueryForAccount atype a morig postingq) | ((a, morig), i) <- HM.toList acctids]
    prepare p = do
      p' <- if queryIsNull amtq then Just p else filterPostingAmount amtq p
      Just $ postingStripCosts p'
    ps = [ (p, p{paccount = clipOrEllipsifyAccountName depthspec $ paccount p})
         | p <- filter hasAmount $ mapMaybe (prepare . snd) $ filter selected numberedps ]

    hasrowterms = not $ queryIsNull rowq
    hasbalanceq = queryHasBalance rowq
    haschangeq  = queryHasChange rowq
    passes anymatched = case quant of
      AssertNone -> not anymatched
      AssertSome -> anymatched
    before mend (_, p)    = maybe True (postingDate p <) mend
    onOrAfter mstart (_, p) = maybe True (postingDate p >=) mstart

    -- A period's changes by account.
    addPosting m p = M.insertWith (flip maPlus) (paccount p) (pamount p) m
    amountsOf = foldl' addPosting M.empty

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

    -- The checkpoints: the whole journal within the date: span, or each period of the period expression.
    checkpoints = case mperiod of
      Nothing -> [datespan]
      Just (interval, spn) ->
        -- The periods, as the balance report would calculate them: from the period expression's span
        -- and the date: terms' span, with open ends filled from the journal's span,
        -- and adjusted to interval boundaries unless a start date was specified.
        let requestedspan = spn `spanIntersect` datespan
        in splitSpanToDateSpans (isNothing $ spanStart requestedspan) interval $
           requestedspan `spanValidDefaultsFrom` jspan

    -- Check each checkpoint in turn, returning the failing ones, each with the number of matches there,
    -- and the first of them, until the error message has as many as it will show (so that a rule
    -- failing in many periods doesn't accumulate all of their matches).
    -- Postings before the first checkpoint count in the balances only, and postings after the last are ignored.
    -- With balance: terms, this maintains the running balances, and the set of accounts whose
    -- balance matches the balance: terms, updating only the accounts posted to in each period.
    -- Each period's rows are the accounts with postings in it, plus, with balance: terms, the
    -- accounts with earlier postings, whose change is zero. Without change:/balance: terms every
    -- row matches, so it's just whether the period has any postings.
    -- Checkpoints in the periods of skip subdirectives are skipped, but their postings still count in the balances.
    checkPeriods _ _ _ _ [] = []
    checkPeriods !want !balances !matching remaining (sp:sps)
      | isSkipped sp || passes anyrowmatches = rest want
      | otherwise            = let !failure = Failure sp nmatched kept  -- evaluated now, not when the message reads it
                               in forceEvidence kept `seq` (failure : rest (want - evidenceSize kept))
      where
        rest w        = checkPeriods w balances' matching' later sps
        kept          = takeEvidence want evidence
        (upto, later) = span (before $ spanEnd sp) remaining
        now           = dropWhile (not . onOrAfter (spanStart sp)) upto
        changes       = amountsOf $ map snd now
        (balances', matching')
          | hasbalanceq = (bals, foldl' upd matching $ S.fromList $ map (paccount . snd) upto)
          | otherwise   = (balances, matching)
          where
            bals = foldl' addPostingRunning balances $ map snd upto
            upd s a = if maybe False balanceMatches (M.lookup a bals) then S.insert a s else S.delete a s
        anyrowmatches
          | not hasrowterms = not $ null now
          | not hasbalanceq = any changeMatches changes
          | not haschangeq  = not $ S.null matching'
          | otherwise       = any (\(a, chg) -> a `S.member` matching' && changeMatches chg) (M.toList changes)
                              || (zerochangematches && any (`M.notMember` changes) (S.toList matching'))
        -- What matched here, for the error message, and how many (counted without listing them).
        nmatched
          | not hasrowterms = length now
          | not hasbalanceq = length $ filter changeMatches $ M.elems changes
          | not haschangeq  = S.size matching'
          | otherwise       = length [() | (a, chg) <- M.toList changes, a `S.member` matching', changeMatches chg]
                              + (if zerochangematches then S.size matching' - length (filter (`S.member` matching') $ M.keys changes) else 0)
        evidence
          | not hasrowterms = MatchedPostings $ map fst now
          | hasbalanceq     = MatchedRows [ (a, chg, bal) | a <- S.toAscList matching'
                                          , let chg = M.findWithDefault nullmixedamt a changes, changeMatches chg
                                          , Just (RunningBalance bal _) <- [M.lookup a balances'] ]
          | otherwise       = MatchedRows [ (a, chg, nullmixedamt) | (a, chg) <- M.toAscList changes, changeMatches chg ]

    -- Is this checkpoint skipped, because a skipped date is among the dates it examines ?
    -- A rule with balance: and no change: terms examines the period's last day (where the balance is tested);
    -- any other rule examines the whole period.
    isSkipped sp
      | null skips = False
      | hasbalanceq && not haschangeq = maybe False (\e -> any (`spanContainsDate` addDays (-1) e) skips) $ spanEnd sp
      | otherwise = any (spansOverlap sp) skips
    spansOverlap a b = case (spanStart i, spanEnd i) of
      (Just s, Just e) -> s < e
      _                -> True
      where i = a `spanIntersect` b

  case checkPeriods maxMatchesShown M.empty S.empty ps checkpoints of
    []       -> Right ()
    failures -> Left $ assertFailureMessage ad rowq (length $ filter (not . isSkipped) checkpoints) failures

-- | The change: and balance: terms of a row query (see 'querySplitRowTerms'), each with whether it is negated.
signedRowTerms :: Query -> [(Bool, Query)]
signedRowTerms (And qs) = concatMap signedRowTerms qs
signedRowTerms (Not q)  = [(not neg, t) | (neg, t) <- signedRowTerms q]
signedRowTerms q        = [(False, q) | queryIsRowTerm q]

-- | The first line(s) of an assert directive error: file position and excerpt.
errorPrefix :: AssertDirective -> String
errorPrefix AssertDirective{adSourcePos=SourcePos f l _, adSourceText=txt} =
  printf "%s:%d:\n%s\n" f (unPos l) (decorateExcerpt (unPos l) Nothing $ txt <> "\n")

-- | Explain an assert directive's failure, given its row query, its number of checkpoints, and the
-- failing checkpoints with what matched there: where it failed, which rows (changes, balances, or both)
-- or postings matched, up to a limit, or that none did, and the equivalent report command
-- (a balance report for rows, a register for postings), covering all the failing checkpoints.
assertFailureMessage :: AssertDirective -> Query -> Int -> [Failure] -> String
assertFailureMessage ad@AssertDirective{adQuantifier=quant, adPeriod=mperiod, adPeriodText=periodtxt, adQueryText=querytxt}
                     rowq ncheckpoints failures =
  errorPrefix ad <> T.unpack (T.unlines $ explanation <> [reportline])
  where
    maxperiodsshown = 5
    hasrowterms = not $ queryIsNull rowq
    periodic = ncheckpoints > 1
    nfailed = length failures

    -- What the matches are called, and the matches as table rows, from all failing checkpoints.
    -- Rows get a period column when there are several checkpoints (postings have their date).
    noun | hasrowterms = rowsnoun
         | otherwise   = "postings"
    (rowsnoun, amountcells) = case (queryHasChange rowq, queryHasBalance rowq) of
      (True, False) -> ("changes",  \chg _   -> [showamt chg])
      (False, _)    -> ("balances", \_ bal   -> [showamt bal])
      (True, True)  -> ("accounts", \chg bal -> [showamt chg, showamt bal])
    showamt = T.pack . showMixedAmountOneLine
    tablerows = flip concatMap failures $ \(Failure sp _ ev) -> case ev of
      MatchedRows rows   -> [(if periodic then periodLabel sp else "") : a : amountcells chg bal | (a, chg, bal) <- rows]
      MatchedPostings ps -> [ [showDate $ postingDate p, fitText Nothing (Just 30) True True desc, paccount p, showamt $ pamount p]
                            | p <- ps, let desc = maybe "" tdescription $ ptransaction p ]
    matchlines = alignColumns (if hasrowterms then [False, False, True, True] else [False, False, False, True]) tablerows
    nhidden = sum [n | Failure _ n _ <- failures] - length matchlines

    explanation = case quant of
      AssertNone ->
        ("This assert directive failed " <> wherefailed <> ".")
        : ("These " <> noun <> " matched" <> (if noun == "accounts" then " (change, balance)" else "") <> ":")
        : map ("  " <>) matchlines
        <> ["  ...and " <> T.pack (show nhidden) <> " more." | nhidden > 0]
      AssertSome
        | periodic  -> ["This assert directive failed " <> wherefailed <> ".",
                        "No " <> noun <> " matched in " <> (if nfailed == 1 then "that period." else "those periods.")]
        | otherwise -> ["This assert directive failed " <> wherefailed <> ": no " <> noun <> " matched."]
    reportline = (if nhidden > 0 then "To see them all: " else "To see the report: ") <> reportcmd

    -- Where it failed: over the whole journal (or the date: terms' span), in its one period, or in some of its periods.
    wherefailed = case (mperiod, failures) of
      (Nothing, [Failure (DateSpan Nothing Nothing) _ _]) -> "(checked over the whole journal)"
      (Nothing, [Failure sp _ _])                         -> "(checked over the period " <> showDateSpan sp <> ")"
      (_, [Failure sp _ _]) | not periodic                -> if isOneDay sp then "on " <> periodLabel sp else "for the period " <> periodLabel sp
      _ -> "in " <> T.pack (show nfailed) <> " of " <> T.pack (show ncheckpoints) <> " periods: "
           <> T.intercalate ", " (map failureLabel $ take maxperiodsshown failures)
           <> (if nfailed > maxperiodsshown then " and " <> T.pack (show $ nfailed - maxperiodsshown) <> " more" else "")

    -- The report command, covering the failing checkpoints: from the start of the first to the end of the last.
    -- It has -I, since reading the journal would otherwise fail on this rule again.
    -- For a balance report covering several periods, it has the period expression's report interval
    -- (from its text; -b and -e override its dates), and leaves out the change:/balance: terms,
    -- since in a multi-period report those test each row's total, not each period.
    reportcmd = T.unwords $ ["hledger"] <> cmd <> periodflags <> map shellQuote queryterms
    -- With balance: terms, -H makes bal show the balances which were tested, not the period's changes.
    cmd | hasrowterms = ["bal", "-I", "-E"] <> ["-H" | queryHasBalance rowq]
        | otherwise   = ["reg", "-I"]
    multiperiod = hasrowterms && nfailed > 1
    periodflags = case mperiod of
      Nothing -> []
      Just _  -> ["-p " <> shellQuote periodtxt | multiperiod]
                 <> dateflag "-b" (spanStart . failureSpan =<< headMay failures)
                 <> dateflag "-e" (spanEnd . failureSpan =<< lastMay failures)
    queryterms = filter (\t -> not (T.null t) && not (multiperiod && isRowTermText t)) $ words'' queryprefixes querytxt
    isRowTermText t = any (`T.isPrefixOf` stripNots t) ["change:", "balance:"]
    stripNots t = maybe t stripNots $ T.stripPrefix "not:" t
    dateflag flag = maybe [] (\d -> [flag, showDate d])
    failureSpan (Failure sp _ _) = sp
    failureLabel = periodLabel . failureSpan

-- | The most matches an assert rule's error message shows.
maxMatchesShown :: Int
maxMatchesShown = 10

-- | How a checkpoint is shown in an error message: as a date if it's one day, otherwise as a period.
periodLabel :: DateSpan -> Text
periodLabel sp
  | isOneDay sp = maybe "" showDate $ spanStart sp
  | otherwise   = showDateSpan sp

isOneDay :: DateSpan -> Bool
isOneDay sp = case (spanStart sp, spanEnd sp) of
  (Just s, Just e) -> addDays 1 s == e
  _                -> False

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
