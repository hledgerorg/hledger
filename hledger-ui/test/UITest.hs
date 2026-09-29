{-# LANGUAGE OverloadedStrings #-}

-- | Proof-of-concept automated tests for hledger-ui, driving the real brick/vty
-- event loop headlessly. See "UITestUtils" for how the harness works and its limits.
-- These exercise the behaviours we most want to protect during refactoring:
-- drill-down, backtracking that preserves each screen's selection, and reload (#1825).

module Main (main) where

import Control.Exception (finally)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import Data.Time.Calendar (fromGregorian)
import System.Directory (getTemporaryDirectory, removeFile)
import System.IO (hClose, openTempFile)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import Hledger (Journal, readJournalFile')
import Hledger.UI.UIOptions (UIOpts)
import UITestUtils

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "hledger-ui"
  [ testCase "drill-down builds the expected screen stack" $
      withFixture $ \uopts j -> do
        (states, _) <- driveUI uopts j [keyRight, keyRight]
        -- menu -> accounts -> register -> transaction
        screenPath (last states) @?= "MART"

  , testCase "backtracking preserves the accounts-screen selection" $
      withFixture $ \uopts j -> do
        (states, _) <- driveUI uopts j [keyDown, keyDown, keyRight, keyLeft]
        let afterDowns = states !! 2  -- accounts screen, selection moved down twice
            afterBack  = last states  -- popped back to the accounts screen
        activeScreenTag     afterDowns @?= "A"
        activeScreenTag     afterBack  @?= "A"
        selectedItemAccount afterBack  @?= selectedItemAccount afterDowns
        selectedIndex       afterBack  @?= selectedIndex       afterDowns

  , testCase "reload preserves the accounts-screen selection (#1825)" $
      withFixture $ \uopts j -> do
        --                          down  down   right(reg) g(reload) left(back)
        (states, _) <- driveUI uopts j [keyDown, keyDown, keyRight, key 'g', keyLeft]
        let beforeReload = states !! 2  -- accounts screen before drilling in
            afterReload  = last states  -- back on the accounts screen after a reload
        activeScreenTag     afterReload @?= "A"
        selectedItemAccount afterReload @?= selectedItemAccount beforeReload
        selectedIndex       afterReload @?= selectedIndex       beforeReload

  , testCase "register screen renders descriptions and amounts" $
      withFixture $ \uopts j -> do
        -- down twice selects expenses:food, then right enters its register
        (states, frames) <- driveUI uopts j [keyDown, keyDown, keyRight]
        activeScreenTag (last states) @?= "R"
        -- scope to the register frame itself (the accounts screen also shows balances)
        let reg = renderText region (last frames)
            hasText t = any (T.isInfixOf t) reg
        -- a description, rendered directly from the list ...
        assertBool "the register should show the 'grocery' transaction description"
          (hasText "grocery")
        -- ... and an amount, rendered via the amount-column width calculation
        assertBool "the register should show the $20 amount"
          (hasText "$20")

  , testCase "reload into a parse error shows, and keeps, the error screen" $
      -- Build the initial screens from a good journal, but point the cli options at a broken
      -- file, so reloading reads the broken file. (No mid-run file mutation needed.)
      withJournalFile fixture $ \goodPath ->
        withJournalFile brokenFixture $ \brokenPath -> do
          uopts <- withDay (fromGregorian 2024 6 1) <$> uiOptsForArgs ["-f", brokenPath, "--all"]
          j <- readJournalFile' goodPath
          (states, frames) <- driveUI uopts j [key 'g', key 'g']
          -- first g: uiReload fails on the broken file and pushes the error screen
          activeScreenTag (states !! 1) @?= "E"
          -- second g: the simplified esReload pops, reloads, and re-pushes; stays on the error screen
          activeScreenTag (last states) @?= "E"
          assertBool "the error screen should show its 'Oops' header"
            (any (T.isInfixOf "Oops") (renderText region (last frames)))

  , testCase "transaction screen shows the whole entry despite a cur: query" $
      withJournalFile multicurFixture $ \path -> do
        uopts <- withDay (fromGregorian 2026 6 1) <$> uiOptsForArgs ["-f", path, "--register", "aaa", "cur:USD"]
        j <- readJournalFile' path
        (states, frames) <- driveUI uopts j [keyRight]
        activeScreenTag (last states) @?= "T"
        let hasText t = any (T.isInfixOf t) $ renderText region (last frames)
        -- the register report excludes the EUR amounts per cur:USD, but the
        -- transaction screen should show the original entry in full
        assertBool "the transaction screen should show the matched USD amount"
          (hasText "10 USD")
        assertBool "the transaction screen should also show the EUR amount excluded by cur:USD"
          (hasText "20 EUR")

  , testCase "L toggles lot detail on the accounts screen, reversibly in memory" $
      withJournalFile lotsFixture $ \path -> do
        uopts <- withDay (fromGregorian 2026 6 1) <$> uiOptsForArgs ["-f", path, "--all"]
        -- readJournalFile' finalises the journal (creating lot subaccounts) but does not
        -- apply the CLI lot-collapse, so this is the uncollapsed journal the ui state expects.
        j <- readJournalFile' path
        (_, frames) <- driveUI uopts j [key 'L', key 'L']
        let lotShown = map (\pic -> any (T.isInfixOf "{2026-01-01") (renderText region pic)) frames
        case lotShown of
          [] -> assertFailure "no frames were rendered"
          (initialShown : _) -> do
            -- collapsed by default: the lot subaccount is hidden on the initial accounts screen
            assertBool "lot subaccounts are hidden by default" (not initialShown)
            -- L reveals the lot subaccount (re-derived in memory, no reload) ...
            assertBool "L reveals the lot subaccount" (or lotShown)
            -- ... and L again collapses it, proving the toggle is reversible without re-reading
            assertBool "L again collapses the lot subaccount" (not (last lotShown))
  , testCase "L on a lot subaccount's transaction screen keeps showing the entry" $
      withJournalFile lotsFixture $ \path -> do
        uopts <- withDay (fromGregorian 2026 6 1) <$> uiOptsForArgs ["-f", path, "--all"]
        j <- readJournalFile' path
        -- uncollapse lots, select the lot subaccount, drill into its transaction,
        -- then collapse lots again (making this screen's account vanish)
        (states, frames) <- driveUI uopts j [key 'L', keyDown, keyRight, keyRight, key 'L']
        activeScreenTag (last states) @?= "T"
        let hasText t = any (T.isInfixOf t) $ renderText region (last frames)
        assertBool "the transaction screen should still show the entry, in collapsed form"
          (hasText "10 AAPL")
        assertBool "the transaction screen should not show a blank transaction"
          (not $ hasText "0000-01-01")
  , testCase "after collapsing lots, the lot subaccount's register shows the base account" $
      withJournalFile lotsFixture $ \path -> do
        uopts <- withDay (fromGregorian 2026 6 1) <$> uiOptsForArgs ["-f", path, "--all"]
        j <- readJournalFile' path
        -- as in the previous test, but also return to the register screen: with lot
        -- detail collapsed, it should show the base account's register, not an empty one
        (states, frames) <- driveUI uopts j [key 'L', keyDown, keyRight, keyRight, key 'L', keyLeft]
        activeScreenTag (last states) @?= "R"
        let hasText t = any (T.isInfixOf t) $ renderText region (last frames)
        assertBool "the register title should show the base account, not the lot subaccount"
          (hasText "assets:stocks transactions" && not (hasText "{2026-01-01"))
        assertBool "the register should show the transaction, selected"
          (hasText "buy" && hasText "(1/1)")
  , testCase "the last screen-selecting flag wins" $
      withJournalFile fixture $ \path -> do
        j <- readJournalFile' path
        let startingscreens args = do
              uopts <- withDay (fromGregorian 2024 6 1) <$> uiOptsForArgs (["-f", path] ++ args)
              (states, _) <- driveUI uopts j []
              return $ screenPath (last states)
        startingscreens ["--bs", "--all"] >>= (@?= "MA")
        startingscreens ["--all", "--bs"] >>= (@?= "MB")
        -- register wins over an earlier accounts flag; checking is a balance sheet account
        startingscreens ["--all", "--register", "checking"] >>= (@?= "MBR")
        -- and an accounts flag wins over an earlier register flag
        startingscreens ["--register", "checking", "--is"] >>= (@?= "MI")
  ]

-- | Run an action with a freshly loaded fixture journal and matching startup
-- options (the all-accounts screen, with a pinned report date for reproducibility).
withFixture :: (UIOpts -> Journal -> IO a) -> IO a
withFixture act =
  withJournalFile fixture $ \path -> do
    uopts <- withDay (fromGregorian 2024 6 1) <$> uiOptsForArgs ["-f", path, "--all"]
    j <- readJournalFile' path
    act uopts j

-- A small date-stable journal: absolute dates, no forecasting.
fixture :: Text
fixture = T.unlines
  [ "2024-01-05 opening"
  , "    assets:checking      $1000"
  , "    equity:opening"
  , ""
  , "2024-02-10 grocery"
  , "    expenses:food          $20"
  , "    assets:checking"
  , ""
  , "2024-03-15 salary"
  , "    assets:checking       $500"
  , "    income:salary"
  ]

-- A journal with a parse error (a bare, non-directive line), so loading it fails.
brokenFixture :: Text
brokenFixture = T.unlines
  [ "2024-01-05 opening"
  , "    assets:checking      $1000"
  , "    equity:opening"
  , ""
  , "this is not a valid journal line"
  ]

-- A journal with a multi-commodity transaction, for testing cur: query filtering.
multicurFixture :: Text
multicurFixture = T.unlines
  [ "2026-01-01 multi"
  , "    aaa    10 USD"
  , "    aaa    20 EUR"
  , "    bbb   -10 USD"
  , "    bbb   -20 EUR"
  ]

-- A journal with a lot-tracked commodity, so accounts have lot subaccounts to show or hide.
lotsFixture :: Text
lotsFixture = T.unlines
  [ "commodity AAPL  ; lots:"
  , ""
  , "2026-01-01 buy"
  , "    assets:stocks    10 AAPL {$50} @ $50"
  , "    assets:cash     $-500"
  ]

withJournalFile :: Text -> (FilePath -> IO a) -> IO a
withJournalFile content act = do
  tmp <- getTemporaryDirectory
  (path, h) <- openTempFile tmp "hledger-ui-test.journal"
  T.hPutStr h content >> hClose h
  act path `finally` removeFile path
