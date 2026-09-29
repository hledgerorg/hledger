#!/usr/bin/env stack
-- stack runghc --verbosity info --package hledger-lib --package hledger --package string-qq --package safe --package text

--  --package time

{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}

-- import Data.Either
import Data.Maybe
import Data.String.QQ (s)
import Text.Printf
import Control.Monad
import Data.List
import Data.Text qualified as T
-- import Data.Time.Calendar
import Safe
import System.Exit
import Hledger
import Hledger.Cli.Script

------------------------------------------------------------------------------
cmdmode :: Mode RawOpts
cmdmode = hledgerCommandMode
  [s| check-postable
Check that no postings are made to accounts with a postable:(n|no) tag.
  |]
  [] 
  [generalflagsgroup1]
  []
  ([], Nothing) -- Just $ argsFlag "[QUERY]")
------------------------------------------------------------------------------

main :: IO ()
main = do
  opts@CliOpts{reportspec_=_rspec} <- getHledgerCliOpts cmdmode
  withJournal opts $ \j -> do
    let
      postedaccts = journalAccountNamesUsed j
      checkAcctPostable :: Journal -> AccountName -> Either AccountName ()
      checkAcctPostable j a =
        case lookup "postable" $ journalInheritedAccountTags j a of
          Just v | T.toLower v `elem` ["no","n"] -> Left a
          _ -> Right ()
    case mapM_ (checkAcctPostable j) postedaccts of
      Right () -> exitSuccess
      Left a   -> putStrLn errmsg >> exitFailure
        where
          firstp = headDef (error' "(unexpected: missing account)") $  -- PARTIAL: shouldn't happen
                   filter ((==a).paccount) $ journalPostings j
          errmsg = chomp $ printf 
            (unlines [
              "%s:%d:"
              ,"%s\n"
              ,"The postable check is enabled, so postings are disallowed in accounts with"
              ,"a postable:n (or postable:no) tag. This account (or one of its parents) was"
              ,"declared with that tag:"
              ,"%s"
              ,""
              ,"%s"
              ])
            f l (textChomp excerpt) a recommendation
            where
              (f,l,_mcols,excerpt) = makePostingAccountErrorExcerpt firstp
              recommendation = chomp $ unlines [
                 "Consider posting to a more specific account, or removing the postable: tag"
                ,"from the appropriate account directive."
                ]
