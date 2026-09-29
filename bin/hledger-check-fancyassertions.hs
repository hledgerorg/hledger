#!/usr/bin/env stack
-- stack runghc --verbosity info --package hledger-lib

-- Run this script from inside the hledger source tree, so that it
-- will use the corresponding source version of hledger, which is the
-- version it is tested with.
--
-- You can compile these scripts by running compile.sh in this directory.
-- The compiled executables can be run from anywhere, so you could add
-- this directory to your $PATH and see them in hledger's command list.
--
-- You could make this a standalone script that runs from anywhere and
-- recompiles itself when changed, by replacing "runghc" above with
-- "script --compile --resolver lts-22" (eg). However this uses the
-- hledger version from that stackage resolver, so in this case you
-- should check out the corresponding release-tagged version of this
-- script for compatibility (eg: git checkout 1.18.1).
--
-- This setup is adapted for some current limitations of stack's
-- ghc/runghc/script commands. Unfortunately it requires repeating
-- package dependencies, to the extent they are required, in multiple
-- places.
-- Keep synced: compile.sh, scripts*.test, hledger-*.hs ...

{-
```
Usage: hledger-check-fancyassertions
                     [-f|--file FILE] [--alias OLD=NEW] [--ignore-assertions]
                     [-b|--begin DATE] [-e|--end DATE] [-C|--cleared]
                     [--pending] [-U|--unmarked] [-R|--real] [--sunday]
                     [-D|--daily ASSERT] [-W|--weekly ASSERT]
                     [-M|--monthly ASSERT] [-Q|--quarterly ASSERT]
                     [-Y|--yearly ASSERT] [ASSERT]
  Complex account balance assertions for hledger journals.

Available options:
  -h,--help                Show this help text
  -f,--file FILE           use a different input file. For stdin, use -
  --alias OLD=NEW          display accounts named OLD as NEW
  --ignore-assertions      ignore any balance assertions in the journal
  -b,--begin DATE          include postings/txns on or after this date
  -e,--end DATE            include postings/txns before this date
  -U,--unmarked            include only unmarked postings/txns
  -P,--pending             include only pending postings/txns
  -C,--cleared             include only cleared postings/txns
  -R,--real                include only non-virtual postings
  --sunday                 weeks start on Sunday
  -D,--daily ASSERT        assertions that must hold at the end of the day
  -W,--weekly ASSERT       assertions that must hold at the end of the week
  -M,--monthly ASSERT      assertions that must hold at the end of the month
  -Q,--quarterly ASSERT    assertions that must hold at the end of the quarter
  -Y,--yearly ASSERT       assertions that must hold at the end of the year
  ASSERT                   assertions that must hold after every transaction
```

Comparison: `<value OR account name>  cmp  <value OR account name>`
-------------------------------------------------------------------

In the simplest form, an assertion is just a comparison between
values. A value is either an amount or an account name (both as
defined by hledger). The comparison operators are `<`, `<=`, `==`,
`>=`, `>`, and `!=` (with the obvious meanings).

Normally, the name of an account refers to the balance of that account
only, without including subaccounts. The syntax `* AccountName` refers
to the sum of the values in both that account and its subaccounts.

**Example:**
```
hledger-check-fancyassertions -D "budget:books  >= £0"
```

"At the end of every day, the books budget is greater than or equal to
£0", implying that if I overspend, I need to take the money out of
some other account. Note the double space after `budget:books`, this
is because account names can contain single spaces.

Combination: `<assertion>  op  <assertion>`
-------------------------------------------

Assertions can be combined with logical connectives. The connectives
are `&&`, `||`, `==>`, and `<==>` (with the obvious meanings).
Assertions can also be wrapped inside parentheses.

**Example:**
```
hledger-check-fancyassertions "(assets:overdraft  < £2000) ==> (*assets:checking  == £0)"
```

"If I have taken money from my overdraft, then I must have no money in
my checking account (including subaccounts)."
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports    #-}

module Main where

import Control.Arrow (first)
import Control.Monad (mplus, mzero, unless, void)
import Control.Monad.Except (runExceptT)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.State.Strict (runStateT)
import Data.String (fromString)
import Data.Function (on)
import Data.Functor (($>))
import Data.Functor.Identity (Identity(..))
import Data.List (foldl', groupBy, intercalate, nub, sortOn)
import Data.List.NonEmpty (NonEmpty(..), nonEmpty, toList)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Time.Calendar (toGregorian)
import Data.Time.Calendar.OrdinalDate (mondayStartWeek, sundayStartWeek, toOrdinalDate)
import Data.Text (Text, isPrefixOf, pack, unpack)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import Hledger.Data qualified as H
import Hledger.Query qualified as H
import Hledger.Read qualified as H
import Hledger.Utils.Parse qualified as H
import Lens.Micro ((&), (.~))
import Options.Applicative
import System.Exit (exitFailure)
import System.FilePath (FilePath)
import Text.Megaparsec qualified as P
import Text.Megaparsec.Char qualified as P

-- Don't know how to preserve newlines yet.
helptxt = unlines [
   "ASSERTIONS can be:"
  ,""
  ,"1. <VALUE_OR_ACCT> CMP <VALUE_OR_ACCT> -"
  ,""
  ,"In the simplest form, an assertion is just a comparison between"
  ,"values. A value is either an amount or an account name (both as"
  ,"defined by hledger). The comparison operators are <, <=, ==,"
  ,">=, >, and != (with the obvious meanings)."
  ,""
  ,"Normally, the name of an account refers to the balance of that account"
  ,"only, without including subaccounts. The syntax `* ACCT` refers"
  ,"to the sum of the values in both that account and its subaccounts."
  ,""
  ,"Example:"
  ,""
  ,"hledger-check-fancyassertions -D 'budget:books  >= £0'"
  ,""
  ,""
  ,"\"At the end of every day, the books budget is greater than or equal to"
  ,"£0\", implying that if I overspend, I need to take the money out of"
  ,"some other account. Note the double space after budget:books, this is"
  ,"because account names can contain single spaces."
  ,""
  ,"2. <ASSERTION> OP <ASSERTION> -"
  ,""
  ,"Assertions can be combined with logical connectives. The connectives"
  ,"are &&, ||, ==>, and <==> (with the obvious meanings)."
  ,"Assertions can also be wrapped inside parentheses."
  ,""
  ,"Example:"
  ,""
  ,"hledger-check-fancyassertions '(assets:overdraft  < £2000) ==> (*assets:checking  == £0)'"
  ,""
  ,""
  ,"\"If I have taken money from my overdraft, then I must have no money in"
  ,"my checking account (including subaccounts).\""
  ]

main :: IO ()
main = do
    opts <- execParser args
    journalFile <- maybe H.defaultJournalPath pure (file opts)
    ejournal    <- runExceptT $ H.readJournalFile (H.definputopts & H.ignore_assertions .~ (ignoreAssertions opts) & H.strict .~ (strict opts)) journalFile
    case ejournal of
      Right j -> do
        (journal, starting) <- fixupJournal opts j
        let postings = H.journalPostings journal
        b1 <- checkAssertions starting (assertionsAlways    opts) (groupByNE ((==) `on` H.ptransaction) postings)
        b2 <- checkAssertions starting (assertionsDaily     opts) (groupByNE sameDay     postings)
        b3 <- checkAssertions starting (assertionsWeekly    opts) (groupByNE (sameWeek (sunday opts))   postings)
        b4 <- checkAssertions starting (assertionsMonthly   opts) (groupByNE sameMonth   postings)
        b5 <- checkAssertions starting (assertionsQuarterly opts) (groupByNE sameQuarter postings)
        b6 <- checkAssertions starting (assertionsYearly    opts) (groupByNE sameYear    postings)
        unless (b1 && b2 && b3 && b4 && b5 && b6)
          exitFailure
      Left err -> putStrLn err >> exitFailure


-------------------------------------------------------------------------------
-- Assertions

-- | Check assertions against a collection of grouped postings:
-- assertions must hold when all postings in the group have been
-- applied. Print out errors as they are found.
checkAssertions :: [(H.AccountName, H.MixedAmount)] -> [(Text, Predicate)] -> [NonEmpty H.Posting] -> IO Bool
checkAssertions balances0 asserts0 postingss
    | null failed = pure True
    | otherwise = T.putStrLn (T.intercalate "\n\n" failed) >> pure False
  where
    (_, _, failed) = foldl' applyAndCheck (balances0, asserts0, []) postingss

    -- Apply a collection of postings and check the assertions.
    applyAndCheck :: ([(H.AccountName, H.MixedAmount)], [(Text, Predicate)], [Text])
                  -> NonEmpty H.Posting
                  -> ([(H.AccountName, H.MixedAmount)], [(Text, Predicate)], [Text])
    applyAndCheck (starting, asserts, errs) ps =
      let ps' = toList ps
          closing  = starting `addAccounts` closingBalances' ps'
          checked  = map (\a -> (a, check (last ps') closing a)) asserts
          asserts' = [a | (a, Nothing) <- checked]
          errs'    = [e | (_, Just e)  <- checked]
      in (closing, asserts', errs ++ errs')

    -- Check an assertion against a collection of account balances,
    -- and return an error on failure.
    check :: H.Posting -> [(H.AccountName, H.MixedAmount)] -> (Text, Predicate) -> Maybe Text
    check lastp balances (pstr, p)
      | checkAssertion balances p = Nothing
      | otherwise = Just . T.unlines $
          let after = case H.ptransaction lastp of
                Just t  ->
                  "after transaction:\n" <> H.showTransaction t <>
                  "(after posting: " <> T.pack (init $ H.showPosting lastp) <> ")\n\n"
                Nothing ->
                  "after posting:\n" <> T.pack (H.showPosting lastp)

              -- Restrict to accounts mentioned in the predicate, and pretty-print balances
              balances' = filter (flip inAssertion p . fst) balances
              maxalen   = maximum $ map (T.length . fst) balances'
              accounts = [ a <> padding <> T.pack (H.showMixedAmount m)
                         | (a,m) <- balances'
                         , let padding = T.replicate (2 + maxalen - T.length a) " "
                         ]
          in [ "assertion '" <> pstr <> "' violated", after <> "relevant balances:"] ++ map ("    "<>) accounts

-- | Check an assertion holds for a collection of account balances.
checkAssertion :: [(H.AccountName, H.MixedAmount)] -> Predicate -> Bool
checkAssertion accounts = checkAssertion'
  where
    checkAssertion' (Not p) = not (checkAssertion' p)
    checkAssertion' (Connect p1 c p2) =
      let p1' = checkAssertion' p1
          p2' = checkAssertion' p2
      in case c of
          AND     -> p1' && p2'
          OR      -> p1' || p2'
          IMPLIES -> not p1' || p2'
          IFF     -> p1' == p2'
    checkAssertion' (Compare v1 c v2) =
      let v1e = evaluate v1
          v2e = evaluate v2
          v1' = fixup v1e v2e
          v2' = fixup v2e v1e
      in case c of
          LLT -> v1' <  v2'
          EEQ -> v1' == v2'
          GGT -> v1' >  v2'
          LTE -> v1' <= v2'
          NEQ -> v1' /= v2'
          GTE -> v1' >= v2'

    evaluate (Account account) =
      fromMaybe H.nullmixedamt $ lookup account accounts
    evaluate (AccountNested account) =
      H.maSum [m | (a,m) <- accounts, account == a || (a <> pack ":") `isPrefixOf` account]
    evaluate (Amount amount) = H.mixed [amount]

    -- Add missing amounts (with 0 value), normalise, throw away style
    -- information, and sort by commodity name.
    fixup m1 m2 =
      let m = H.mixed $ H.amounts m1 ++ [m_ { H.aquantity = 0 } | m_ <- H.amounts m2]
          as = H.amounts m
      in H.mixed $ sortOn H.acommodity . map (\a -> a { H.astyle = H.amountstyle }) $ as

-- | Check if an account name is mentioned in an assertion.
inAssertion :: H.AccountName -> Predicate -> Bool
inAssertion account = inAssertion'
  where
    inAssertion' (Not p) = not (inAssertion' p)
    inAssertion' (Connect p1 _ p2) = inAssertion' p1 || inAssertion' p2
    inAssertion' (Compare v1 _ v2) = inValue v1 || inValue v2

    inValue (Account a) = account == a
    inValue (AccountNested a) = account == a || (a <> pack ":") `isPrefixOf` account
    inValue (Amount _) = False


-------------------------------------------------------------------------------
-- Journals

-- | Apply account aliases, sort transactions by date, and restrict to
-- the date range; return the starting balance of every account.
fixupJournal :: Opts -> H.Journal -> IO (H.Journal, [(H.AccountName, H.MixedAmount)])
fixupJournal opts j = do
    today <- H.getCurrentDay
    let j' = sortTransactions
           . (if cleared   opts then H.filterJournalTransactions (H.StatusQ H.Cleared)  else id)
           . (if pending   opts then H.filterJournalTransactions (H.StatusQ H.Pending)  else id)
           . (if unmarked  opts then H.filterJournalTransactions (H.StatusQ H.Unmarked) else id)
           . (if real      opts then H.filterJournalTransactions (H.Real   True)       else id)
           $ j
    let starting = case begin opts of
          Just _  ->
              let dateSpan = H.DateSpan Nothing (fixDay today begin)
              in closingBalances (H.filterJournalPostings (H.Date dateSpan) j')
          Nothing -> []
    let dateSpan = H.DateSpan (fixDay today begin) (fixDay today end)
    pure (H.filterJournalTransactions (H.Date dateSpan) j', starting)

  where
    fixDay today dayf = H.fixSmartDate today <$> dayf opts
    sortTransactions j'' = j''{H.jtxns = sortOn H.tdate (H.jtxns j'')}

-- | Get the closing balances of every account in the journal.
closingBalances :: H.Journal -> [(H.AccountName, H.MixedAmount)]
closingBalances = closingBalances' . H.journalPostings

-- | Get the closing balances of every account referenced by a group
-- of postings.
closingBalances' :: [H.Posting] -> [(H.AccountName, H.MixedAmount)]
closingBalances' postings =
  let postingsByAccount =
        groupBy ((==) `on` H.paccount) . sortOn H.paccount $ postings
  in map (\ps@(p:_) -> (H.paccount p, H.sumPostings ps)) postingsByAccount

-- | Add balances in matching accounts.
addAccounts :: [(H.AccountName, H.MixedAmount)] -> [(H.AccountName, H.MixedAmount)] -> [(H.AccountName, H.MixedAmount)]
addAccounts as1 as2 = [ (a, a1 `H.maPlus` a2)
                      | a <- nub (map fst as1 ++ map fst as2)
                      , let a1 = fromMaybe H.nullmixedamt $ lookup a as1
                      , let a2 = fromMaybe H.nullmixedamt $ lookup a as2
                      ]

-------------------------------------------------------------------------------
-- Dates

-- | Check if two postings are in the same day.
sameDay :: H.Posting -> H.Posting -> Bool
sameDay = sameish id

-- | Check if two postings are in the same week.
sameWeek :: Bool -> H.Posting -> H.Posting -> Bool
sameWeek startSunday p1 p2 =
  let startWeek = if startSunday then sundayStartWeek else mondayStartWeek
      d1 = H.postingDate p1
      d2 = H.postingDate p2
      y1 = fst (toOrdinalDate d1)
      y2 = fst (toOrdinalDate d2)
      w1 = fst (startWeek d1)
      w2 = fst (startWeek d2)
      sameYearSameWeek =   y1 == y2   && w1 == w2
      week0Week52      =   y1 == y2+1 && w1 == 0  && w2 == 52
      week52Week0      = 1+y1 == y2   && w1 == 52 && w2 == 0
  in sameYearSameWeek || week0Week52 || week52Week0

-- | Check if two postings are in the same month.
sameMonth :: H.Posting -> H.Posting -> Bool
sameMonth = sameish (\(y,m,_) -> (y,m))

-- | Check if two postings are in the same quarter.
sameQuarter :: H.Posting -> H.Posting -> Bool
sameQuarter = sameish (\(y,m,_) -> (y, m `div` 4))

-- | Check if two postings are in the same year.
sameYear :: H.Posting -> H.Posting -> Bool
sameYear = sameish (\(y,_,_) -> y)


-------------------------------------------------------------------------------
-- Command-line Arguments

-- | Parsed command-line arguments.
data Opts = Opts
    { file :: Maybe FilePath
    -- ^ Path to journal file.
    , aliases :: [H.AccountAlias]
    -- ^ Account name aliases: (OLD, NEW).
    , ignoreAssertions :: Bool
    -- ^ Ignore balance assertions while reading the journal file (but
    -- still apply any given to this tool.
    , begin :: Maybe H.SmartDate
    -- ^ Exclude postings/txns before this date.
    , end :: Maybe H.SmartDate
    -- ^ Exclude postings/txns on or after this date.
    , cleared :: Bool
    -- ^ Include only cleared postings/txns.
    , pending :: Bool
    -- ^ Include only pending postings/txns.
    , unmarked :: Bool
    -- ^ Include only unmarked postings/txns.
    , real :: Bool
    -- ^ Include only non-virtual postings.
    , strict :: Bool
    -- ^ Use strict requirements in journal parsing.
    , sunday :: Bool
    -- ^ Week starts on Sunday.
    , assertionsDaily :: [(Text, Predicate)]
    -- ^ Account assertions that must hold at the end of each day.
    , assertionsWeekly :: [(Text, Predicate)]
    -- ^ Account assertions that must hold at the end of each week.
    , assertionsMonthly :: [(Text, Predicate)]
    -- ^ Account assertions that must hold at the end of each month.
    , assertionsQuarterly :: [(Text, Predicate)]
    -- ^ Account assertions that must hold at the end of each quarter.
    , assertionsYearly :: [(Text, Predicate)]
    -- ^ Account assertions that must hold at the end of each year.
    , assertionsAlways :: [(Text, Predicate)]
    -- ^ Account assertions that must hold after each txn.
    }
  deriving (Show)

-- | Command-line arguments.
args :: ParserInfo Opts
args = info (helper <*> parser) $ mconcat
    [ fullDesc
    , progDesc "Complex account balance assertions for hledger journals."
    , footer helptxt
    ]
  where
    parser = Opts <$> (optional . strOption)
                        (arg 'f' "file" "use a different input file. For stdin, use -"             <> metavar "FILE")
                  <*> (many . fmap snd . popt (lift H.accountaliasp))
                        (arg' "alias" "display accounts named OLD as NEW"                          <> metavar "OLD=NEW")
                  <*> switch
                        (arg' "ignore-assertions" "ignore any balance assertions in the journal")
                  <*> (optional . fmap snd . popt' H.smartdate)
                        (arg 'b' "begin" "include postings/txns on or after this date"             <> metavar "DATE")
                  <*> (optional . fmap snd . popt' H.smartdate)
                        (arg 'e' "end" "include postings/txns before this date"                    <> metavar "DATE")
                  <*> switch
                        (arg 'C' "cleared" "include only cleared postings/txns")
                  <*> switch
                        (arg' "pending" "include only pending postings/txns")
                  <*> switch
                        (arg 'U' "unmarked" "include only unmarked postings/txns")
                  <*> switch
                        (arg 'R' "real" "include only non-virtual postings")
                  <*> switch
                        (arg 's' "strict" "use strict mode checking")
                  <*> switch
                        (arg' "sunday" "weeks start on Sunday")
                  <*> (many . popt predicatep)
                        (arg 'D' "daily" "assertions that must hold at the end of the day"         <> metavar "ASSERT")
                  <*> (many . popt predicatep)
                        (arg 'W' "weekly" "assertions that must hold at the end of the week"       <> metavar "ASSERT")
                  <*> (many . popt predicatep)
                        (arg 'M' "monthly" "assertions that must hold at the end of the month"     <> metavar "ASSERT")
                  <*> (many . popt predicatep)
                        (arg 'Q' "quarterly" "assertions that must hold at the end of the quarter" <> metavar "ASSERT")
                  <*> (many . popt predicatep)
                        (arg 'Y' "yearly" "assertions that must hold at the end of the year"       <> metavar "ASSERT")
                  <*> (many . parg predicatep)
                        (help "assertions that must hold after every transaction"                  <> metavar "ASSERT")

    -- Shorthand for options
    arg s l h = arg' l h <> short s
    arg'  l h = long l <> help h

    -- Arguments and options from a Megaparsec parser.
    parg = argument . readParsec
    popt = option . readParsec
    popt' = option . readParsec'

    -- Turn a Parsec parser into a ReadM parser that also returns the
    -- input.
    readParsec :: H.JournalParser ReadM a -> ReadM (Text, a)
    readParsec p = do
      s <- str
      parsed <- P.runParserT (runStateT p H.nulljournal) "" s
      case parsed of
        Right (a, _) -> pure (s, a)
        Left err -> fail ("failed to parse input '" ++ unpack s ++ "': " ++ P.errorBundlePretty err)

    readParsec' :: H.SimpleTextParser a -> ReadM (String, a)
    readParsec' p = do
      s <- str
      let parsed = runIdentity $ P.runParserT p "" (pack s)
      case parsed of
        Right a -> pure (s, a)
        Left err -> fail ("failed to parse input '" ++ s ++ "': " ++ P.errorBundlePretty err)


-------------------------------------------------------------------------------
-- Predicates & Parsers

data Predicate
    = Compare Value Compare Value
    | Connect Predicate Connect Predicate
    | Not Predicate
  deriving (Eq, Ord, Show)

-- | Parse a 'Predicate'.
predicatep :: Monad m => H.JournalParser m Predicate
predicatep = wrap predparensp <|> wrap predcomparep <|> wrap prednotp where
    predparensp  = P.char '(' *> spaces *> predicatep <* spaces <* P.char ')'
    predcomparep = Compare <$> valuep <*> (spaces *> lift comparep <* spaces) <*> valuep
    prednotp     = void (P.char '!') *> (Not <$> predicatep)
    spaces = void . many $ P.char ' '

    wrap p = do
        a <- P.try p
        spaces
        P.try (wrap $ do c <- lift connectp; spaces; Connect a c <$> p) <|> pure a

data Value = Account H.AccountName | AccountNested H.AccountName | Amount H.Amount
  deriving (Eq, Ord, Show)

-- | Parse a 'Value'.
valuep :: Monad m => H.JournalParser m Value
-- Account name parser has to come last because they eat everything.
valuep = P.try valueamountp <|> P.try valueaccountnestedp <|> valueaccountp where
    valueamountp  = Amount  <$> H.amountp
    valueaccountp = Account <$> lift H.accountnamep
    valueaccountnestedp = AccountNested <$> (P.char '*' *> spaces *> lift H.accountnamep)
    spaces = void . many $ P.char ' '

data Compare = LLT | EEQ | GGT | LTE | NEQ | GTE
  deriving (Eq, Ord, Read, Show, Bounded, Enum)

-- | Parse a 'Compare'.
comparep :: Monad m => H.TextParser m Compare
comparep = gostringsp [("<=", LTE), ("<", LLT), ("==", EEQ), (">=", GTE), (">", GGT), ("!=", NEQ)]

data Connect = AND | OR | IMPLIES | IFF
  deriving (Eq, Ord, Read, Show, Bounded, Enum)

-- | Parse a 'Connect'.
connectp :: Monad m => H.TextParser m Connect
connectp = gostringsp [("&&", AND), ("||", OR), ("==>", IMPLIES), ("<==>", IFF)]


-------------------------------------------------------------------------------
-- Utilities

-- | Group values in a list into nonempty subsequences.
groupByNE :: (a -> a -> Bool) -> [a] -> [NonEmpty a]
groupByNE f = mapMaybe nonEmpty . groupBy f

-- | Check if two postings are on the sameish date, given a function
-- to convert the posting date (in (Y,M,D) format) to some comparable
-- value.
sameish :: Eq a => ((Integer, Int, Int) -> a) -> H.Posting -> H.Posting -> Bool
sameish f = (==) `on` f . toGregorian . H.postingDate

-- | Helper for 'Compare' and 'Connect' parsers.
gostringsp :: Monad m => [(String, a)] -> H.TextParser m a
gostringsp ((s,a):rest) = P.try (P.string (fromString s) $> a) `mplus` gostringsp rest
gostringsp [] = mzero
