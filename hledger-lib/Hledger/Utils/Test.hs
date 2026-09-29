{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Hledger.Utils.Test (
   module Test.Tasty
  ,module Test.Tasty.HUnit
  -- ,module QC
  -- ,module SC
  ,assertLeft
  ,assertRight
  ,assertParse
  ,assertParseEq
  ,assertParseEqOn
  ,assertParseError
  ,assertParseE
  ,assertParseEqE
  ,assertParseErrorE
  ,assertParseStateOn
)
where

import Control.Monad (unless)
import Control.Monad.Except (ExceptT(..), liftEither, runExceptT, withExceptT)
import Control.Monad.State.Strict (StateT, evalStateT, execStateT)
import Data.Default (Default(..))
import Data.List (isInfixOf)
import Data.Text qualified as T
import Test.Tasty hiding (defaultMain)
import Test.Tasty.HUnit
-- import Test.Tasty.QuickCheck as QC
-- import Test.Tasty.SmallCheck as SC
import Text.Megaparsec

import Hledger.Utils.IO (pshow)
import Hledger.Utils.Parse
  ( HledgerParseErrorData,
    FinalParseError,
    attachSource,
    customErrorBundlePretty,
    finalErrorBundlePretty,
  )

-- * tasty helpers

-- TODO: pretty-print values in failure messages

-- | Assert any Left value.
assertLeft :: (HasCallStack, Eq b, Show b) => Either a b -> Assertion
assertLeft (Left _)  = return ()
assertLeft (Right b) = assertFailure $ "expected Left, got (Right " ++ show b ++ ")"

-- | Assert any Right value.
assertRight :: (HasCallStack, Eq a, Show a) => Either a b -> Assertion
assertRight (Right _) = return ()
assertRight (Left a)  = assertFailure $ "expected Right, got (Left " ++ show a ++ ")"

-- | Run a parser on the given text and display a helpful error.
parseHelper :: (HasCallStack, Default st, Monad m) =>
  StateT st (ParsecT HledgerParseErrorData T.Text m) a -> T.Text -> ExceptT String m a
parseHelper parser input =
  withExceptT (\e -> "\nparse error at " ++ customErrorBundlePretty e ++ "\n") . ExceptT
  $ runParserT (evalStateT (parser <* eof) def) "" input

-- | Run a stateful parser in IO and process either a failure or success to
-- produce an 'Assertion'. Suitable for hledger's JournalParser parsers.
assertParseHelper :: (HasCallStack, Default st) =>
  (String -> Assertion) -> (a -> Assertion)
  -> StateT st (ParsecT HledgerParseErrorData T.Text IO) a -> T.Text
  -> Assertion
assertParseHelper onFailure onSuccess parser input =
  either onFailure onSuccess =<< runExceptT (parseHelper parser input)

-- | Assert that this stateful parser runnable in IO successfully parses
-- all of the given input text, showing the parse error if it fails.
-- Suitable for hledger's JournalParser parsers.
assertParse :: (HasCallStack, Default st) =>
  StateT st (ParsecT HledgerParseErrorData T.Text IO) a -> T.Text -> Assertion
assertParse = assertParseHelper assertFailure (const $ return ())

-- | Assert a parser produces an expected value.
assertParseEq :: (HasCallStack, Eq a, Show a, Default st) =>
  StateT st (ParsecT HledgerParseErrorData T.Text IO) a -> T.Text -> a -> Assertion
assertParseEq parser input = assertParseEqOn parser input id

-- | Like assertParseEq, but transform the parse result with the given function
-- before comparing it.
assertParseEqOn :: (HasCallStack, Eq b, Show b, Default st) =>
  StateT st (ParsecT HledgerParseErrorData T.Text IO) a -> T.Text -> (a -> b) -> b -> Assertion
assertParseEqOn parser input f expected =
  assertParseHelper assertFailure (assertEqual "" expected . f) parser input

-- | Assert that this stateful parser runnable in IO fails to parse
-- the given input text, with a parse error containing the given string.
assertParseError :: (HasCallStack, Eq a, Show a, Default st) =>
  StateT st (ParsecT HledgerParseErrorData T.Text IO) a -> T.Text -> String -> Assertion
assertParseError parser input errstr = assertParseHelper
  (\e -> unless (errstr `isInfixOf` e) $ assertFailure $ "\nparse error is not as expected:" ++ e)
  (\v -> assertFailure $ "\nparse succeeded unexpectedly, producing:\n" ++ pshow v ++ "\n")
  parser input

-- | Run a stateful parser in IO like assertParse, then assert that the
-- final state (the wrapped state, not megaparsec's internal state),
-- transformed by the given function, matches the given expected value.
assertParseStateOn :: (HasCallStack, Eq b, Show b, Default st) =>
     StateT st (ParsecT HledgerParseErrorData T.Text IO) a -> T.Text -> (st -> b) -> b -> Assertion
assertParseStateOn parser input f expected = do
  es <- runParserT (execStateT (parser <* eof) def) "" input
  case es of
    Left err -> assertFailure $ (++"\n") $ ("\nparse error at "++) $ customErrorBundlePretty err
    Right s  -> assertEqual "" expected $ f s

-- | These "E" variants of the above are suitable for hledger's ErroringJournalParser parsers.
parseHelperE :: (HasCallStack, Default st, Monad m) =>
  StateT st (ParsecT HledgerParseErrorData T.Text (ExceptT FinalParseError m)) a -> T.Text -> ExceptT String m a
parseHelperE parser input = do
  withExceptT (\e -> "\nparse error at " ++ customErrorBundlePretty e ++ "\n") . liftEither
  =<< withExceptT (\e -> "parse error at " ++ finalErrorBundlePretty (attachSource "" input e))
        (runParserT (evalStateT (parser <* eof) def) "" input)

assertParseHelperE :: (HasCallStack, Default st) =>
  (String -> Assertion) -> (a -> Assertion)
  -> StateT st (ParsecT HledgerParseErrorData T.Text (ExceptT FinalParseError IO)) a -> T.Text
  -> Assertion
assertParseHelperE onFailure onSuccess parser input =
  either onFailure onSuccess =<< runExceptT (parseHelperE parser input)

assertParseE
  :: (HasCallStack, Eq a, Show a, Default st)
  => StateT st (ParsecT HledgerParseErrorData T.Text (ExceptT FinalParseError IO)) a -> T.Text -> Assertion
assertParseE = assertParseHelperE assertFailure (const $ return ())

assertParseEqE
  :: (Default st, Eq a, Show a, HasCallStack)
  => StateT st (ParsecT HledgerParseErrorData T.Text (ExceptT FinalParseError IO)) a -> T.Text -> a -> Assertion
assertParseEqE parser input = assertParseEqOnE parser input id

assertParseEqOnE
  :: (HasCallStack, Eq b, Show b, Default st)
  => StateT st (ParsecT HledgerParseErrorData T.Text (ExceptT FinalParseError IO)) a -> T.Text -> (a -> b) -> b -> Assertion
assertParseEqOnE parser input f expected =
  assertParseHelperE assertFailure (assertEqual "" expected . f) parser input

assertParseErrorE
  :: (Default st, Eq a, Show a, HasCallStack)
  => StateT st (ParsecT HledgerParseErrorData T.Text (ExceptT FinalParseError IO)) a -> T.Text -> String -> Assertion
assertParseErrorE parser input errstr = assertParseHelperE
  (\e -> unless (errstr `isInfixOf` e) $ assertFailure $ "\nparse error is not as expected:" ++ e)
  (\v -> assertFailure $ "\nparse succeeded unexpectedly, producing:\n" ++ pshow v ++ "\n")
  parser input
