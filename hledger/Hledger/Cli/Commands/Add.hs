{-|
A history-aware, tab-completing interactive add command to help with data entry.
-}

{-# OPTIONS_GHC -fno-warn-missing-signatures -fno-warn-unused-do-bind #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeOperators #-}

module Hledger.Cli.Commands.Add (
   addmode
  ,add
  ,appendToJournalFileOrStdout
  ,journalAddTransaction
)
where

import Control.Exception as E
import Control.Monad (unless, when)
import Control.Monad.Trans.Class
import Control.Monad.State.Strict (evalState, evalStateT)
import Control.Monad.Trans (liftIO)
import Data.Char (toUpper, toLower)
import Data.Either (isRight)
import Data.Functor.Identity (Identity(..))
import Data.List (isPrefixOf, nub)
import Data.Maybe (fromJust, fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.IO qualified as TL
import Data.Time.Calendar (Day, toGregorian)
import Data.Time.Format (formatTime, defaultTimeLocale)
import Lens.Micro ((^.))
import Safe (headDef, headMay, atMay, lastMay)
import System.Console.CmdArgs.Explicit (flagNone)
import System.Console.Haskeline (runInputT, defaultSettings, setComplete)
import System.Console.Haskeline.Completion (CompletionFunc, completeWord, isFinished, noCompletion, simpleCompletion)
import System.Console.Wizard (Wizard, defaultTo, line, output, outputLn, retryMsg, linePrewritten, nonEmpty, parser, run)
import System.Console.Wizard.Haskeline
import System.FilePath (takeDirectory)
import System.IO (hPutStr, hPutStrLn, stderr)
import Text.Megaparsec
import Text.Megaparsec.Char
import Text.Printf

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Commands.Print (layoutFlag, layoutFromRawOpts)
import Hledger.Cli.Commands.Register (postingsReportAsText)
import Hledger.Cli.Utils (journalSimilarTransaction)


addmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Add.txt")
  [flagNone ["no-new-accounts"]  (setboolopt "no-new-accounts") "don't allow creating new accounts"
  ,layoutFlag
  ]
  [generalflagsgroup2]
  confflags
  ([], Just $ argsFlag "[-f JOURNALFILE] [DATE [DESCRIPTION [ACCOUNT1 [ETC..]]]]]")

data AddState = AddState {
   asOpts               :: CliOpts           -- ^ command line options
  ,asArgs               :: [String]          -- ^ command line arguments remaining to be used as defaults
  ,asToday              :: Day               -- ^ today's date
  ,asDefDate            :: Day               -- ^ the default date to use for the next transaction
  ,asJournal            :: Journal           -- ^ the journal we are adding to
  ,asSimilarTransaction :: Maybe Transaction -- ^ the old transaction most similar to the new one being entered
  ,asPostings           :: [Posting]         -- ^ the new postings entered so far
  ,asInferredAmounts    :: [Maybe MixedAmount]
   -- ^ posting amounts inferred from balance assignments, if any, corresponding to asPostings.
   --   Stored so subsequent amount prompts can offer the inferred amount's negation as a default.
} deriving (Show)

defAddState = AddState {
   asOpts               = defcliopts
  ,asArgs               = []
  ,asToday              = nulldate
  ,asDefDate            = nulldate
  ,asJournal            = nulljournal
  ,asSimilarTransaction = Nothing
  ,asPostings           = []
  ,asInferredAmounts    = []
}

data AddStep =
    GetDate
  | GetDescription (Day, Text)
  | GetPosting TxnData (Maybe Posting)
  | GetAccount TxnData
  | GetAmount TxnData String
  | Confirm Transaction

data TxnData = TxnData {
    txnDate :: Day
  , txnCode :: Text
  , txnDesc :: Text
  , txnCmnt :: Text
} deriving (Show)

type Comment = (Text, [Tag], Maybe Day, Maybe Day)

data PrevInput = PrevInput {
    prevDateAndCode   :: Maybe String
  , prevDescAndCmnt   :: Maybe String
  , prevAccount       :: [String]
  , prevAmountAndCmnt :: [String]
} deriving (Show)

data RestartTransactionException = RestartTransactionException deriving (Show)
instance Exception RestartTransactionException

-- data ShowHelpException = ShowHelpException deriving (Show)
-- instance Exception ShowHelpException

-- | Read multiple transactions from the console, prompting for each
-- field, and append them to the journal file.  If the journal came
-- from stdin, this command has no effect.
add :: CliOpts -> Journal -> IO ()
add opts j
    | journalFilePath j == "-" = return ()
    | otherwise = do
        hPutStrLn stderr $ "Adding transactions to journal file " <> journalFilePath j
        showHelp
        let today = opts^.rsDay
            state = defAddState{asOpts=opts
                              ,asArgs=listofstringopt "args" $ rawopts_ opts
                              ,asToday=today
                              ,asDefDate=today
                              ,asJournal=j
                              }
        addTransactionsLoop state `E.catch` (\(_::UnexpectedEOF) -> putStr "")

showHelp = hPutStr stderr $ unlines [
     "Any command line arguments will be used as defaults."
    ,"Use tab key to complete, readline keys to edit, enter to accept defaults."
    ,"An optional (CODE) may follow transaction dates."
    ,"An optional ; COMMENT may follow descriptions or amounts."
    ,"If you make a mistake, enter < at any prompt to go one step backward."
    ,"To end a transaction, enter . when prompted."
    ,"To quit, enter . at a date prompt or press control-d or control-c."
    ]

-- | Loop reading transactions from the console, prompting, validating
-- and appending each one to the journal file, until end of input or
-- ctrl-c (then raise an EOF exception).  If provided, command-line
-- arguments are used as defaults; otherwise defaults come from the
-- most similar recent transaction in the journal.
addTransactionsLoop :: AddState -> IO ()
addTransactionsLoop state@AddState{..} = (do
  let defaultPrevInput = PrevInput{prevDateAndCode=Nothing, prevDescAndCmnt=Nothing, prevAccount=[], prevAmountAndCmnt=[]}
  mt <- runInputT (setComplete noCompletion defaultSettings) (System.Console.Wizard.run $ haskeline $ transactionWizard defaultPrevInput state [])
  case mt of
    Nothing -> error' "Could not interpret the input, restarting"  -- caught below causing a restart, I believe  -- PARTIAL:
    Just t -> do
      j <- if debug_ asOpts > 0
           then do hPutStrLn stderr "Skipping journal add due to debug mode."
                   return asJournal
           else do j' <- journalAddTransaction asJournal asOpts t
                   hPutStrLn stderr "Saved."
                   return j'
      hPutStrLn stderr "Starting the next transaction (. or ctrl-D/ctrl-C to quit)"
      addTransactionsLoop state{asJournal=j, asDefDate=tdate t}
  )
  `E.catch` (\(_::RestartTransactionException) ->
                 hPutStrLn stderr "Restarting this transaction." >> addTransactionsLoop state)

-- | Interact with the user to get a Transaction.
transactionWizard :: PrevInput -> AddState -> [AddStep] -> Wizard Haskeline Transaction
transactionWizard previnput state [] = transactionWizard previnput state [GetDate]
transactionWizard previnput state@AddState{..} stack@(currentStage : _) = case currentStage of
  GetDate -> dateWizard previnput state >>= \case
    Just (efd, code) -> do
      let
        date = fromEFDay efd
        state' = state{ asArgs = drop 1 asArgs
                , asDefDate = date
                }
        dateAndCodeString = formatTime defaultTimeLocale yyyymmddFormat date
                            ++ T.unpack (if T.null code then "" else " (" <> code <> ")")
        yyyymmddFormat = "%Y-%m-%d"
      transactionWizard previnput{prevDateAndCode=Just dateAndCodeString} state' (GetDescription (date, code) : stack)
    Nothing ->
      transactionWizard previnput state stack

  GetDescription (date, code) -> descriptionWizard previnput state >>= \case
    Just (desc, comment) -> do
      let mbaset = journalSimilarTransaction asOpts asJournal desc
          state' = state
            { asArgs = drop 1 asArgs
            , asPostings = []
            , asInferredAmounts = []
            , asSimilarTransaction = mbaset
            }
          descAndCommentString = T.unpack $ desc <> (if T.null comment then "" else "  ; " <> comment)
          previnput' = previnput{prevDescAndCmnt=Just descAndCommentString}
      when (isJust mbaset) . liftIO $ do
          hPutStrLn stderr "Using this similar transaction for defaults:"
          T.hPutStr stderr $ showTransactionWithLayout (layoutFromRawOpts $ rawopts_ asOpts) (fromJust mbaset)
      transactionWizard previnput' state' ((GetPosting TxnData{txnDate=date, txnCode=code, txnDesc=desc, txnCmnt=comment} Nothing) : stack)
    Nothing ->
      transactionWizard previnput state (drop 1 stack)

  GetPosting txndata@TxnData{..} p -> case (asPostings, p) of
    ([], Nothing) ->
      transactionWizard previnput state (GetAccount txndata : stack)
    (_, Just _) ->
      transactionWizard previnput state (GetAccount txndata : stack)
    (_, Nothing) -> do
      let t = nulltransaction{tdate=txnDate
                             ,tstatus=Unmarked
                             ,tcode=txnCode
                             ,tdescription=txnDesc
                             ,tcomment=txnCmnt
                             ,tpostings=asPostings
                             }
          bopts = balancingopts_ (inputopts_ asOpts)
      case balanceTransactionInJournal t asJournal bopts of
        Right t' ->
          transactionWizard previnput state (Confirm t' : stack)
        Left err -> do
          liftIO (hPutStrLn stderr $ "\n" ++ (capitalize err) ++ ", please re-enter.")
          -- Back up one step: re-prompt for the next account, keeping postings entered so far.
          transactionWizard previnput state (GetAccount txndata : drop 1 stack)

  GetAccount txndata -> accountWizard previnput state >>= \case
    Just account
      | account `elem` [".", ""] ->
          case (asPostings, postingsAreBalanced asJournal asPostings) of
            ([],_)    -> liftIO (hPutStrLn stderr "Please enter some postings first.") >> transactionWizard previnput state stack
            (_,False) -> liftIO (hPutStrLn stderr "Please enter more postings to balance the transaction.") >> transactionWizard previnput state stack
            (_,True)  -> transactionWizard previnput state (GetPosting txndata Nothing : stack)
      | otherwise -> do
          let prevAccount' = replaceNthOrAppend (length asPostings) account (prevAccount previnput)
          transactionWizard previnput{prevAccount=prevAccount'} state{asArgs=drop 1 asArgs} (GetAmount txndata account : stack)
    Nothing -> do
      let notPrevAmountAndNotGetDesc stage = case stage of
            GetAmount _ _ -> False
            GetDescription _ -> False
            _ -> True
      transactionWizard previnput state{asPostings=init asPostings, asInferredAmounts=init asInferredAmounts} (dropWhile notPrevAmountAndNotGetDesc stack)

  GetAmount txndata account -> amountWizard previnput state >>= \case
    Just (mamt, assertion, (comment, tags, pdate1, pdate2)) -> do
      let mixedamt = maybe missingmixedamt mixedAmount mamt
          p = nullposting{paccount=T.pack $ stripbrackets account
                          ,pamount=mixedamt
                          ,pcomment=T.dropAround isNewline comment
                          ,preal=accountNamePostingType $ T.pack account
                          ,pbalanceassertion = assertion
                          ,pdate=pdate1
                          ,pdate2=pdate2
                          ,ptags=tags
                          }
          amountAndCommentString = showMixedAmountOneLine mixedamt ++ T.unpack (if T.null comment then "" else "  ;" <> comment)
          prevAmountAndCmnt' = replaceNthOrAppend (length asPostings) amountAndCommentString (prevAmountAndCmnt previnput)
          -- Include a dummy posting to balance the unfinished transation in assertion checking
          dummytxn = nulltransaction{tpostings = asPostings ++ [p, post "" missingamt]
                                     ,tdate = txnDate txndata
                                     ,tdescription = txnDesc txndata }
          bopts = balancingopts_ (inputopts_ asOpts)
          isbalanceassignment = mixedamt==missingmixedamt && isJust assertion
          -- Balance the transaction in context of the whole journal,
          -- filling any balance assignment, and checking all the journal's balance assertions.
          etxn = balanceTransactionInJournal dummytxn asJournal bopts

      case etxn of
        Left err -> do
          liftIO (hPutStrLn stderr err)
          transactionWizard previnput state (GetAmount txndata account : stack)
        Right balanced -> do
          -- For a balance-assignment posting, remember the amount the balancer
          -- inferred, so the next posting's default can use it.
          let minferredamterredamt
                | isbalanceassignment = pamount <$> tpostings balanced `atMay` length asPostings
                | otherwise = Nothing
              state' = state{asPostings=asPostings++[p]
                            ,asInferredAmounts=asInferredAmounts++[minferredamterredamt]
                            ,asArgs=drop 1 asArgs}
          transactionWizard previnput{prevAmountAndCmnt=prevAmountAndCmnt'} state' (GetPosting txndata (Just posting) : stack)
    Nothing -> transactionWizard previnput state (drop 1 stack)

  Confirm t -> do
    output . T.unpack $ showTransactionWithLayout (layoutFromRawOpts $ rawopts_ asOpts) t
    y <- let def = "y" in
         retryMsg "Please enter y or n." $
          parser ((fmap (\c -> if c == '<' then Nothing else Just c)) . headMay . map toLower . strip) $
          defaultTo' def $ nonEmpty $
          line $ green' $ printf "Save this transaction to the journal ?%s: " (showDefault def)
    case y of
      Just 'y' -> return t
      Just _   -> throw RestartTransactionException
      Nothing  -> transactionWizard previnput state (drop 2 stack)
  where
    replaceNthOrAppend n newElem xs = take n xs ++ [newElem] ++ drop (n + 1) xs

-- | Interact with the user to get a transaction date (accepting smart dates), maybe followed by a " (CODE)". 
-- Returns the date and the code, or nothing if the input was "<".
dateWizard :: PrevInput -> AddState -> Wizard Haskeline (Maybe (EFDay, Text))
dateWizard PrevInput{..} AddState{..} = do
  let def = headDef (T.unpack $ showDate asDefDate) asArgs
  retryMsg "A valid hledger smart date is required. Eg: 2022-08-30, 8/30, 30, yesterday." $
   parser (parseSmartDateAndCode asToday) $
   withCompletion (dateCompleter def) $
   defaultTo' def $ nonEmpty $
   maybeExit $
   -- maybeShowHelp $
   linePrewritten (green' $ printf "Date%s: " (showDefault def)) (fromMaybe "" prevDateAndCode) ""
    where
      parseSmartDateAndCode refdate s = if s == "<" then return Nothing else either (const Nothing) (\(d,c) -> return $ Just (fixSmartDate refdate d, c)) edc
          where
            edc = runParser (dateandcodep <* eof) "" $ T.pack $ lowercase s
            dateandcodep :: SimpleTextParser (SmartDate, Text)
            dateandcodep = do
                d <- smartdate
                c <- optional codep
                skipNonNewlineSpaces
                eof
                return (d, fromMaybe "" c)
      -- defday = fixSmartDate today $ fromparse $ (parse smartdate "" . lowercase) defdate
      -- datestr = showDate $ fixSmartDate defday smtdate

-- | Interact with the user to get a transaction description, maybe followed by a "; COMMENT".
-- Returns the possibly empty description and comment, or nothing if the input is "<".
descriptionWizard :: PrevInput -> AddState -> Wizard Haskeline (Maybe (Text, Text))
descriptionWizard PrevInput{..} AddState{..} = do
  let def = headDef "" asArgs
  s <- withCompletion (descriptionCompleter asJournal def) $
       defaultTo' def $ nonEmpty $
       linePrewritten (green' $ printf "Description%s: " (showDefault def)) (fromMaybe "" prevDescAndCmnt) ""
  if s == "<"
    then return Nothing
    else do
      let (desc,comment) = (T.pack $ strip a, T.pack $ strip $ dropWhile (==';') b) where (a,b) = break (==';') s
      return $ Just (desc, comment)

-- | Interact with the user to get an account name, possibly enclosed in "()" or "[]".
-- Returns the account name, or nothing if the input is "<".
accountWizard :: PrevInput -> AddState -> Wizard Haskeline (Maybe String)
accountWizard PrevInput{..} AddState{..} = do
  let pnum = length asPostings + 1
      historicalp = fmap ((!! (pnum - 1)) . (++ (repeat nullposting)) . tpostings) asSimilarTransaction
      historicalacct = case historicalp of Just p  -> showAccountName Nothing (preal p) (paccount p)
                                           Nothing -> ""
      def = headDef (T.unpack historicalacct) asArgs
      endmsg | canfinish && null def = " (or . or enter to finish this transaction)"
             | canfinish             = " (or . to finish this transaction)"
             | otherwise             = ""
  retryMsg "A valid hledger account name is required. Eg: assets:cash, expenses:food:eating out." $
   parser (parseAccountOrDotOrNull def canfinish) $
   withCompletion (accountCompleter asJournal def) $
   defaultTo' def $ -- nonEmpty $
   linePrewritten (green' $ printf "Account %d%s%s: " pnum (endmsg::String) (showDefault def)) (fromMaybe "" $ prevAccount `atMay` length asPostings) ""
    where
      canfinish = not (null asPostings) && postingsAreBalanced asJournal asPostings
      parseAccountOrDotOrNull :: String -> Bool -> String -> Maybe (Maybe String)
      parseAccountOrDotOrNull _  _ "<"       = dbg' $ Just Nothing
      parseAccountOrDotOrNull _  _ "."       = dbg' $ Just $ Just "." -- . always signals end of txn
      parseAccountOrDotOrNull "" True ""     = dbg' $ Just $ Just ""  -- when there's no default and txn is balanced, "" also signals end of txn
      parseAccountOrDotOrNull def@(_:_) _ "" = dbg' $ Just $ Just def -- when there's a default, "" means use that
      parseAccountOrDotOrNull _ _ s          = dbg' $ fmap (Just . T.unpack) $
        either (const Nothing) validateAccount $
          flip evalState asJournal $ runParserT (accountnamep <* eof) "" (T.pack s) -- otherwise, try to parse the input as an accountname
        where
          validateAccount :: Text -> Maybe Text
          validateAccount t | no_new_accounts_ asOpts && notElem t (journalAccountNamesDeclaredOrImplied asJournal) = Nothing
                            | otherwise = Just t
      dbg' = id -- strace

-- | Interact with the user to get an amount and/or a balance assertion, maybe followed by a "; COMMENT".
-- Returns the amount, balance assertion, and/or comment, or nothing if the input is "<".
amountWizard :: PrevInput -> AddState -> Wizard Haskeline (Maybe (Maybe Amount, Maybe BalanceAssertion, Comment))
amountWizard previnput@PrevInput{..} state@AddState{..} = do
  let pnum = length asPostings + 1
      (mhistoricalp,followedhistoricalsofar) =
          case asSimilarTransaction of
            Nothing                        -> (Nothing,False)
            Just Transaction{tpostings=ps} ->
              ( if length ps >= pnum then Just (ps !! (pnum-1)) else Nothing
              , all sameamount $ zip asPostings ps
              )
              where
                sameamount (p1,p2) = mixedAmountUnstyled (pamount p1) == mixedAmountUnstyled (pamount p2)
      def | (d:_) <- asArgs                                     = d
          | Just hp <- mhistoricalp, followedhistoricalsofar    = showamt $ pamount hp
          | pnum > 1 && not (mixedAmountLooksZero balancingamt) = showamt balancingamtfirstcommodity
          | otherwise                                           = ""
  retryMsg "A valid hledger amount is required. Eg: 1, $2, 3 EUR, \"4 red apples\"." $
   parser' parseAmountAndComment $
   withCompletion (amountCompleter def) $
   defaultTo' def $
   nonEmpty $
   linePrewritten (green' $ printf "Amount  %d%s: " pnum (showDefault def)) (fromMaybe "" $ prevAmountAndCmnt `atMay` length asPostings) ""
    where
      -- Custom parser that combines with Wizard to use IO via outputLn
      parser' f a = a >>= \input ->
        case f input of
          Left err -> do
            outputLn (customErrorBundlePretty err)
            amountWizard previnput state
          Right res -> pure res
      parseAmountAndComment s = 
        if s == "<" then Right Nothing else 
         Just <$> runParser 
            (evalStateT (amountandcommentp <* eof) nodefcommodityj)
            ""
            (T.pack s)
      nodefcommodityj = asJournal{jparsedefaultcommodity=Nothing}
      amountandcommentp :: JournalParser Identity (Maybe Amount, Maybe BalanceAssertion, Comment)
      amountandcommentp = do
        mamt <- optional amountp
        lift skipNonNewlineSpaces
        massertion <- optional balanceassertionp
        com <- T.pack <$> fromMaybe "" `fmap` optional (char ';' >> many anySingle)
        case rtp (postingcommentp (let (y,_,_) = toGregorian asDefDate in Just y)) (T.cons ';' com) of
          Left err -> fail $ customErrorBundlePretty err
          -- Keep our original comment string from the user to add to the journal
          Right (_, tags, date1', date2') -> return $ (mamt, massertion, (com, tags, date1', date2'))
      balancingamt = maNegate . sumPostings $ filter isReal asPostings'
        where
          -- Postings entered so far, with any amounts from balance assignments filled in
          asPostings' =
            [ case minferredamt of
                Just a  -> p{pamount = a}
                Nothing -> p
            | (p, minferredamt) <- zip asPostings (asInferredAmounts ++ repeat Nothing)
            ]
      balancingamtfirstcommodity = mixed . take 1 $ amounts balancingamt
      -- Note, apply the journal's commodity display styles so default
      -- inputs match the journal's format even when summing amounts
      -- that were entered with different or missing styles (#2645).
      -- displayForceDecimalMark ensures that if there are digit group marks,
      -- a decimal mark will also be shown to avoid ambiguity and misparsing (#2656).
      -- will be shown if needed to avoid ambiguity with a digit group mark
      -- NoRounding ensures all significant digits are shown.
      showamt = wbUnpack
              . showMixedAmountB defaultFmt{displayForceDecimalMark=True}
              . styleAmounts (journalCommodityStylesWith NoRounding asJournal)
              . mixedAmountSetPrecision
                  -- what should this be ?
                  -- 1 maxprecision (show all decimal places or none) ?
                  -- 2 maxprecisionwithpoint (show all decimal places or .0 - avoids some but not all confusion with thousands separators) ?
                  -- 3 canonical precision for this commodity in the journal ?
                  -- 4 maximum precision entered so far in this transaction ?
                  -- 5 3 or 4, whichever would show the most decimal places ?
                  -- I think 1 or 4, whichever would show the most decimal places
                  NaturalPrecision
  --
  -- let -- (amt,comment) = (strip a, strip $ dropWhile (==';') b) where (a,b) = break (==';') amtcmt
      -- a           = fromparse $ runParser (amountp <|> return missingamt) (jparsestate asJournal) "" amt
  --     awithoutjps = fromparse $ runParser (amountp <|> return missingamt) mempty              "" amt
  --     defamtaccepted = Just (showAmount a) == mdefamt
  --     as2 = if defamtaccepted then as1 else as1{asHistoricalPostings=Nothing}
  --     mdefaultcommodityapplied = if acommodity a == acommodity awithoutjps then Nothing else Just $ acommodity a
  -- when (isJust mdefaultcommodityapplied) $
  --      liftIO $ hPutStrLn stderr $ printf "using default commodity (%s)" (fromJust mdefaultcommodityapplied)

-- Completion helpers

dateCompleter :: String -> CompletionFunc IO
dateCompleter = completer ["today","tomorrow","yesterday"]

-- Offer payees declared, payees used, or full descriptions used.
descriptionCompleter :: Journal -> String -> CompletionFunc IO
descriptionCompleter j = completer (map T.unpack $ nub $ journalPayeesDeclaredOrUsed j ++ journalDescriptions j)

accountCompleter :: Journal -> String -> CompletionFunc IO
accountCompleter j = completer (map T.unpack $ journalAccountNamesDeclaredOrImplied j)

amountCompleter :: String -> CompletionFunc IO
amountCompleter = completer []

-- | Generate a haskeline completion function from the given
-- completions and default, that case insensitively completes with
-- prefix matches, or infix matches above a minimum length, or
-- completes the null string with the default.
completer :: [String] -> String -> CompletionFunc IO
completer completions def = completeWord Nothing "" completionsFor
    where
      simpleCompletion' s = (simpleCompletion s){isFinished=False}
      completionsFor "" = return [simpleCompletion' def]
      completionsFor i  = return (map simpleCompletion' ciprefixmatches)
          where
            ciprefixmatches = [c | c <- completions, i `isPrefixOf` c]
            -- mixed-case completions require haskeline > 0.7.1.2
            -- ciprefixmatches = [c | c <- completions, lowercase i `isPrefixOf` lowercase c]

--------------------------------------------------------------------------------

-- utilities

maybeExit = parser (\s -> if s == "." then throw UnexpectedEOF else Just s)

-- maybeShowHelp :: Wizard Haskeline String -> Wizard Haskeline String
-- maybeShowHelp wizard = maybe (liftIO showHelp >> wizard) return $
--                        parser (\s -> if s=="?" then Nothing else Just s) wizard

defaultTo' = flip defaultTo

withCompletion f = withSettings (setComplete f defaultSettings)

showDefault "" = ""
showDefault s = " [" ++ s ++ "]"

-- | Balance and check a transaction with awareness of the whole journal it will be added to.
-- This means add it to the journal, balance it, calculate any balance assignments in it,
-- then maybe check all the journal's balance assertions,
-- then return the now fully balanced and checked transaction, or an error message.
balanceTransactionInJournal :: Transaction -> Journal -> BalancingOpts -> Either String Transaction
balanceTransactionInJournal t j bopts = do
  -- Add the transaction at the end of the journal, as the add command will.
  let j' = j{jtxns = jtxns j ++ [t]}
      -- Use the journal's account types so the balancer can identify
      -- Gain postings and exclude them from balancing (#2572).
      bopts' = bopts{account_types_ = jaccounttypes j}
  -- Try to balance and check the whole journal, and specifically the new transaction.
  Journal{jtxns=ts} <- journalBalanceTransactions bopts' j'
  -- Extract the balanced & checked transaction.
  maybe
    (Left "balanceTransactionInJournal: unexpected empty journal") -- should not happen
    Right
    (lastMay ts)

postingsAreBalanced :: Journal -> [Posting] -> Bool
postingsAreBalanced j ps = isRight $ balanceSingleTransaction bopts nulltransaction{tpostings = ps}
  where bopts = defbalancingopts{account_types_ = jaccounttypes j}

-- | Append this transaction to the journal's file and transaction list.
journalAddTransaction :: Journal -> CliOpts -> Transaction -> IO Journal
journalAddTransaction j@Journal{jtxns=ts} opts t = do
  let f = journalFilePath j
      showtxn = showTransactionWithLayout (layoutFromRawOpts $ rawopts_ opts)
  appendToJournalFileOrStdout f $ showtxn t
    -- unelided shows all amounts explicitly, in case there's a price, cf #283
  when (debug_ opts > 0) $ do
    putStrLn $ printf "\nAdded transaction to %s:" f
    TL.putStrLn =<< registerFromString (showtxn t)
  return j{jtxns=ts++[t]}

-- | Append a string, typically one or more transactions, to a journal
-- file, or if the file is "-", dump it to stdout.
-- Tries to avoid adding excess whitespace.
-- Also, this also does a quick append test before the actual append,
-- to avoid data loss in case of filesystems with broken append (see ensureFilesystemCanAppend).
--
-- XXX This writes unix line endings (\n), some at least,
-- even if the file uses dos line endings (\r\n), which could leave
-- mixed line endings in the file. See also writeFileWithBackupIfChanged.
--
appendToJournalFileOrStdout :: FilePath -> Text -> IO ()
appendToJournalFileOrStdout f s
  | f == "-"  = T.putStr s'
  | otherwise = do
      ensureJournalFileExists f
      let dir = takeDirectory f
      ok <- ensureFilesystemCanAppend dir
      unless ok $ error' $ unlines
        [ "Cannot safely append to journal; aborting to avoid data loss."
        , "The filesystem at " <> show dir <> " does not honor O_APPEND."
        , "This can happen eg with FAT/exFAT and Android shared-storage / FUSE mounts."
        , "Please move the journal file to a reliable filesystem and try again."
        ]
      appendFile f $ T.unpack s'
  where s' = "\n" <> ensureOneNewlineTerminated s

-- | Replace a string's 0 or more terminating newlines with exactly one.
ensureOneNewlineTerminated :: Text -> Text
ensureOneNewlineTerminated = (<>"\n") . T.dropWhileEnd (=='\n')

-- | Convert a string of journal data into a register report.
registerFromString :: T.Text -> IO TL.Text
registerFromString s = do
  j <- readJournal'' s
  return . postingsReportAsText opts $ postingsReport rspec j
      where
        ropts = defreportopts{empty_=True}
        rspec = defreportspec{_rsReportOpts=ropts}
        opts = defcliopts{reportspec_=rspec}

capitalize :: String -> String
capitalize "" = ""
capitalize (c:cs) = toUpper c : cs
