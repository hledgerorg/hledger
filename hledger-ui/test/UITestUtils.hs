{-# LANGUAGE OverloadedStrings #-}

{- |
A small headless harness for testing hledger-ui (a brick/vty terminal UI)
without a real terminal.

How it works: brick always hands vty a complete 'V.Picture' each frame (vty does
incremental diffing only when writing to a real terminal). So we run the real
'brickApp' event loop against a custom headless 'V.Vty' whose @update@ records the
full picture and whose @nextEvent@ replays a scripted list of events. brick reads
input only via @nextEvent vty@, so scripted events are fed by overriding that one
field. We capture, per event, both a 'UIState' snapshot (for semantic assertions)
and the full picture (converted to text only by tests that want it).

Limitations:

* Don't script the external-process keybindings (@a@ add, @A@ iadd, @E@ editor) or
  anything using @suspendAndResume@ - those shell out / suspend the terminal and are
  not unit-testable. The testable surface is navigation, selection, toggles, filter
  and reload (@g@), which is what we care about.

* Handlers call 'getCurrentDay', so keep fixture journals date-stable (no future or
  relative dates). 'uiOptsForArgs' pins the startup report date for reproducibility,
  but the handler date is still "today"; with a date-stable journal it doesn't matter.

* Every script is automatically terminated with a quit key so the loop halts;
  'driveUI' also wraps the run in a timeout so a mis-scripted test fails fast instead
  of hanging on the blocking @nextEvent@.
-}

module UITestUtils
( -- * Driving the UI
  driveUI
, region
  -- * Building options
, uiOptsForArgs
, withDay
  -- * Event helpers
, key
, keyEnter
, keyRight
, keyLeft
, keyDown
, keyUp
  -- * State accessors
, screenPath
, activeScreenTag
, selectedIndex
, selectedAccount
, selectedItemAccount
  -- * Rendering
, renderText
) where

import Control.Concurrent.STM (TChan, atomically, newTChanIO, readTChan, tryReadTChan, writeTChan)
import Control.Monad (void)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.State.Class (get)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Time.Calendar (Day)
import Data.Vector qualified as Vector
import System.Timeout (timeout)

import Brick (App(..), customMain)
import Brick.Widgets.List (listSelected, listSelectedElement)
import Graphics.Vty (Vty(..), Event(..), Key(..), Picture, DisplayRegion)
import Graphics.Vty.Input (Input(..))
import Graphics.Vty.Output.Mock (mockTerminal)
import Graphics.Vty.PictureToSpans (displayOpsForPic)
import Graphics.Vty.Span (SpanOp(..))

import Hledger (AccountName, Journal)
import Hledger.Cli (CliOpts(..), ReportSpec(..), ensureDebugFlagHasVal, process, replaceNumericFlags, usageError)
import Hledger.UI.Main (brickApp, uiHandle, uiInitialState)
import Hledger.UI.UIOptions (UIOpts(..), rawOptsToUIOpts, uimode)
import Hledger.UI.UITypes
import Hledger.UI.UIUtils (showScreenId)

-- | The fixed terminal size used for all headless rendering.
region :: DisplayRegion
region = (80, 40)

-- | Build a 'UIOpts' the way hledger-ui does at startup, but from an explicit
-- argument list instead of the process arguments. Eg @["-f", journalpath]@.
uiOptsForArgs :: [String] -> IO UIOpts
uiOptsForArgs args =
  rawOptsToUIOpts $ either usageError id $ process uimode args'
  where args' = ensureDebugFlagHasVal $ replaceNumericFlags args

-- | Pin the startup report date, so the initial screen state is reproducible.
withDay :: Day -> UIOpts -> UIOpts
withDay d uo = uo{uoCliOpts = copts{reportspec_ = rspec{_rsDay = d}}}
  where
    copts = uoCliOpts uo
    rspec = reportspec_ copts

-- | Build a headless 'Vty': captures every rendered picture, replays scripted
-- events, and stubs out all real terminal I/O. brick only reads input via
-- 'nextEvent' and only queries 'displayBounds' on the output, both satisfied here.
headlessVty :: DisplayRegion -> TChan Event -> IORef [Picture] -> IO Vty
headlessVty r evchan frames = do
  out <- snd <$> mockTerminal r
  stubChan <- newTChanIO  -- never read; brick reads via nextEvent below
  let input = Input
        { eventChannel      = stubChan
        , shutdownInput     = pure ()
        , restoreInputState = pure ()
        , inputLogMsg       = const (pure ())
        }
  pure Vty
    { update               = \pic -> modifyIORef' frames (pic:)
    , nextEvent            = atomically (readTChan evchan)
    , nextEventNonblocking = atomically (tryReadTChan evchan)
    , inputIface           = input
    , outputIface          = out
    , refresh              = pure ()
    , shutdown             = pure ()
    , isShutdown           = pure False
    }

-- | Run the real hledger-ui event loop headlessly over a scripted list of events,
-- returning a 'UIState' snapshot before any event (index 0) and after each scripted
-- event, plus every rendered picture (in chronological order). A quit key is appended
-- automatically to halt the loop; its snapshot/frame are not returned.
driveUI :: UIOpts -> Journal -> [Event] -> IO ([UIState], [Picture])
driveUI uopts j events = do
  let ui0 = uiInitialState uopts j
  snaps  <- newIORef [ui0]
  frames <- newIORef []
  evchan <- newTChanIO
  atomically $ mapM_ (writeTChan evchan) (events ++ [key 'q'])
  vty <- headlessVty region evchan frames
  let snapshot = get >>= \s -> liftIO (modifyIORef' snaps (s:))
      app = (brickApp (uoTheme uopts)){appHandleEvent = \ev -> uiHandle ev >> snapshot}
  mres <- timeout (10 * 1000 * 1000) $ void $ customMain vty (pure vty) Nothing app ui0
  case mres of
    Nothing -> ioError $ userError "driveUI: timed out (did the script fail to halt?)"
    Just () -> pure ()
  rawsnaps <- reverse <$> readIORef snaps
  fs       <- reverse <$> readIORef frames
  pure (dropLast rawsnaps, fs)  -- drop the quit-key snapshot
  where dropLast xs = if null xs then xs else init xs

-- Event helpers ------------------------------------------------------------------

key :: Char -> Event
key c = EvKey (KChar c) []

keyEnter, keyRight, keyLeft, keyDown, keyUp :: Event
keyEnter = EvKey KEnter []
keyRight = EvKey KRight []
keyLeft  = EvKey KLeft  []
keyDown  = EvKey KDown  []
keyUp    = EvKey KUp    []

-- State accessors ----------------------------------------------------------------

-- | The screen-id letters from the root (menu) screen down to the active screen,
-- eg @"MAR"@ for menu -> accounts -> register. Useful for asserting the nav path.
screenPath :: UIState -> String
screenPath ui = concatMap showScreenId $ reverse (aScreen ui : aPrevScreens ui)

-- | The active screen's id letter (eg @"R"@ for a register screen).
activeScreenTag :: UIState -> String
activeScreenTag = showScreenId . aScreen

-- | The selected list index on the active screen (the displayed transaction's
-- position on a transaction screen), if any.
selectedIndex :: UIState -> Maybe Int
selectedIndex ui = case aScreen ui of
  MS s -> listSelected (_mssList s)
  AS s -> listSelected (_assList s)
  RS s -> listSelected (_rssList s)
  TS s -> Just $ fromInteger $ fst (_tssTransaction s)
  ES _ -> Nothing

-- | The accounts-like screen's saved selected-account backup, if any. Note this
-- lags the live selection by one event (the handler saves it /before/ moving), so
-- for assertions about the current selection prefer 'selectedItemAccount'.
selectedAccount :: UIState -> Maybe AccountName
selectedAccount ui = case aScreen ui of
  AS s -> Just (_assSelectedAccount s)
  _    -> Nothing

-- | The account currently selected in the active accounts-like list (read live
-- from the list's selected element), if any.
selectedItemAccount :: UIState -> Maybe AccountName
selectedItemAccount ui = case aScreen ui of
  AS s -> acct (_assList s)
  _    -> Nothing
  where acct l = asItemAccountName . snd <$> listSelectedElement l

-- Rendering ----------------------------------------------------------------------

-- | Render a captured picture to lines of text (one per terminal row), for the
-- given region. Tests can then assert on whatever slice they like - a substring,
-- a specific row, a cropped region - without maintaining full golden screens.
renderText :: DisplayRegion -> Picture -> [Text]
renderText r pic = map rowText . Vector.toList $ displayOpsForPic pic r
  where
    rowText = T.concat . map opText . Vector.toList
    opText (TextSpan _ _ _ t) = TL.toStrict t
    opText (Skip n)           = T.replicate n " "
    opText (RowEnd n)         = T.replicate n " "
