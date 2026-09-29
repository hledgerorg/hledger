-- The menu screen, showing other screens available in hledger-ui.

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Hledger.UI.MenuScreen
 (msNew
 ,msUpdate
 ,msDraw
 ,msHandle
 ,msSetSelectedScreen
 )
where

import Brick
import Brick.Widgets.List
import Control.Monad
import Control.Monad.IO.Class (liftIO)
import Data.Maybe
import Data.Text qualified as T
import Data.Time.Calendar (Day)
import Data.Vector qualified as V
import Data.Vector ((!?))
import Graphics.Vty (Event(..),Key(..),Modifier(..), Button (BLeft, BScrollDown, BScrollUp))
import Lens.Micro.Platform
import System.Console.ANSI
import System.FilePath (takeFileName)

import Hledger.Utils.I18n (Translations, tr)
import Hledger
import Hledger.Cli hiding (mode, progname, prognameandversion)
import Hledger.UI.UIOptions
import Hledger.UI.UITypes
import Hledger.UI.UIState
import Hledger.UI.UIUtils
import Hledger.UI.UIScreens
import Hledger.UI.ErrorScreen (uiReload, uiReloadIfFileChanged, uiToggleBalanceAssertions)
import Hledger.UI.Editor (runIadd, runEditor, endPosition)
import Brick.Widgets.Edit (getEditContents, handleEditorEvent)
import Control.Arrow ((>>>))


msDraw :: MenuScreenState -> UIState -> [Widget Name]
msDraw sst UIState{aopts=_uopts@UIOpts{uoCliOpts=copts@CliOpts{reportspec_=_rspec@ReportSpec{_rsReportOpts=ropts}}}
              ,ajournal=j
              ,aMode=mode
              } = dbgui "msDraw" $
    case mode of
      Help              -> [helpDialog, maincontent]
      _                 -> [maincontent]
  where
    maincontent = Widget Greedy Greedy $ do
      render $ defaultLayout toplabel bottomlabel $ renderList (msDrawItem (translations_ ropts)) True (sst ^. mssList)
      where
        toplabel =
              withAttr (attrName "border" <> attrName "filename") fs
          <+> borderPeriodStr "" (period_ ropts)
          <+> (if ignore_assertions_ . balancingopts_ $ inputopts_ copts
               then withAttr (attrName "border" <> attrName "query") (str " ignoring balance assertions")
               else str "")
          where
            fs = case journalFilePaths j of
                           [] -> str ""
                           f:_ -> str $ takeFileName f
                           -- [f,_:[]] -> (withAttr ("border" <> "bold") $ str $ takeFileName f) <+> str " (& 1 included file)"
                           -- f:fs  -> (withAttr ("border" <> "bold") $ str $ takeFileName f) <+> str (" (& " ++ show (length fs) ++ " included files)")

        bottomlabel = case mode of
                        Minibuffer label ed -> minibuffer label ed
                        _                   -> quickhelp
          where
            quickhelp = borderKeysStr' [
               ("DOWN/UP", str "select")
              ,("RIGHT", str "enter screen")
              -- ,("t", renderToggle (tree_ ropts) "list" "tree")
              -- ,("t", str "tree")
              -- ,("l", str "list")
              -- ,("-+", str "depth")
              -- ,("H", renderToggle (not ishistorical) "end-bals" "changes")
              -- ,("F", renderToggle1 (isJust . forecast_ $ inputopts_ copts) "forecast")
              --,("/", "filter")
              --,("DEL", "unfilter")
              --,("ESC", "cancel/top")
              ,("a", str "add txn")
--               ,("g", "reload")
              ,("?", str "help")
              ,("q", str "quit")
              ]


-- msDrawItem :: (Int,Int) -> Bool -> MenuScreenItem -> Widget Name
-- msDrawItem (_acctwidth, _balwidth) _selected MenuScreenItem{..} =
msDrawItem :: Translations -> Bool -> MenuScreenItem -> Widget Name
msDrawItem trs _selected MenuScreenItem{..} =
  Widget Greedy Fixed $ do
    render $ txt $ tr trs msItemScreenName

-- XXX clean up like asHandle
msHandle :: MenuScreenState -> BrickEvent Name AppEvent -> EventM Name UIState ()
msHandle sst ev = do
  ui0 <- get'
  dbguiEv "msHandle"
  case ui0 of
    ui@UIState{
       aopts=UIOpts{uoCliOpts=copts}
      ,ajournal=j
      ,aMode=mode
      } -> do
      let
        -- save the currently selected account, in case we leave this screen and lose the selection
        mselscr = case listSelectedElement $ _mssList sst of
                    Just (_, MenuScreenItem{..}) -> Just msItemScreen
                    Nothing -> Nothing
        nonblanks = V.takeWhile (not . T.null . msItemScreenName) $ listElements $ _mssList sst
        lastnonblankidx = max 0 (length nonblanks - 1)
        journalspan = journalDateSpan False j
      d <- liftIO getCurrentDay

      case mode of
        Minibuffer _ ed ->
          case ev of
            VtyEvent (EvKey KEsc   []) -> put' $ closeMinibuffer ui
            VtyEvent (EvKey KEnter []) -> put' $ regenerateScreens d $
                case setFilter s $ closeMinibuffer ui of
                  Left bad -> showMinibuffer "Cannot compile regular expression" (Just bad) ui
                  Right ui' -> ui'
              where s = chomp $ unlines $ map strip $ getEditContents ed
            VtyEvent (EvKey (KChar 'l') [MCtrl]) -> redraw
            VtyEvent (EvKey (KChar 'z') [MCtrl]) -> suspend ui
            VtyEvent e -> do
              ed' <- nestEventM' ed $ handleEditorEvent (VtyEvent e)
              put' ui{aMode=Minibuffer "filter" ed'}
            AppEvent _  -> return ()
            MouseDown{} -> return ()
            MouseUp{}   -> return ()

        Help ->
          case ev of
            -- VtyEvent (EvKey (KChar 'q') []) -> halt
            VtyEvent (EvKey (KChar 'l') [MCtrl]) -> redraw
            VtyEvent (EvKey (KChar 'z') [MCtrl]) -> suspend ui
            _ -> helpHandle ev

        Normal ->
          case ev of
            VtyEvent (EvKey (KChar 'q') []) -> halt
            -- EvKey (KChar 'l') [MCtrl] -> do
            VtyEvent (EvKey KEsc        []) -> put' $ resetScreens d ui
            VtyEvent (EvKey (KChar c)   []) | c == '?' -> put' $ setMode Help ui
            -- XXX AppEvents currently handled only in Normal mode
            -- XXX be sure we don't leave unconsumed events piling up
            AppEvent (DateChange old _) | isStandardPeriod p && p `periodContainsDate` old ->
              put' $ regenerateScreens d $ setReportPeriod (DayPeriod d) ui
              where
                p = reportPeriod ui
            e | e `elem` [VtyEvent (EvKey (KChar 'g') []), AppEvent FileChange] -> uiReload copts d ui >>= put'
            VtyEvent (EvKey (KChar 'I') []) -> uiToggleBalanceAssertions d ui
            VtyEvent (EvKey (KChar 'a') []) -> suspendAndResume $ clearScreen >> setCursorPosition 0 0 >> add (cliOptsDropArgs copts) j >> uiReloadIfFileChanged copts d j ui
            VtyEvent (EvKey (KChar 'A') []) -> suspendAndResume $ void (runIadd (journalFilePath j)) >> uiReloadIfFileChanged copts d j ui
            VtyEvent (EvKey (KChar 'E') []) -> suspendAndResume $ void (runEditor endPosition (journalFilePath j)) >> uiReloadIfFileChanged copts d j ui

--             VtyEvent (EvKey (KChar 'B') []) -> put' $ regenerateScreens d $ toggleConversionOp ui
--             VtyEvent (EvKey (KChar 'V') []) -> put' $ regenerateScreens d $ toggleValue ui
--             VtyEvent (EvKey (KChar '0') []) -> put' $ regenerateScreens d $ setDepth (Just 0) ui
--             VtyEvent (EvKey (KChar '1') []) -> put' $ regenerateScreens d $ setDepth (Just 1) ui
--             VtyEvent (EvKey (KChar '2') []) -> put' $ regenerateScreens d $ setDepth (Just 2) ui
--             VtyEvent (EvKey (KChar '3') []) -> put' $ regenerateScreens d $ setDepth (Just 3) ui
--             VtyEvent (EvKey (KChar '4') []) -> put' $ regenerateScreens d $ setDepth (Just 4) ui
--             VtyEvent (EvKey (KChar '5') []) -> put' $ regenerateScreens d $ setDepth (Just 5) ui
--             VtyEvent (EvKey (KChar '6') []) -> put' $ regenerateScreens d $ setDepth (Just 6) ui
--             VtyEvent (EvKey (KChar '7') []) -> put' $ regenerateScreens d $ setDepth (Just 7) ui
--             VtyEvent (EvKey (KChar '8') []) -> put' $ regenerateScreens d $ setDepth (Just 8) ui
--             VtyEvent (EvKey (KChar '9') []) -> put' $ regenerateScreens d $ setDepth (Just 9) ui
--             VtyEvent (EvKey (KChar '-') []) -> put' $ regenerateScreens d $ decDepth ui
--             VtyEvent (EvKey (KChar '_') []) -> put' $ regenerateScreens d $ decDepth ui
--             VtyEvent (EvKey (KChar c)   []) | c `elem` ['+','='] -> put' $ regenerateScreens d $ incDepth ui
--             VtyEvent (EvKey (KChar 'T') []) -> put' $ regenerateScreens d $ setReportPeriod (DayPeriod d) ui

--             -- display mode/query toggles
--             VtyEvent (EvKey (KChar 't') []) -> modify' (regenerateScreens d . toggleTree) >> msCenterAndContinue
--             VtyEvent (EvKey (KChar c) []) | c `elem` ['z','Z'] -> modify' (regenerateScreens d . toggleEmpty) >> msCenterAndContinue
--             VtyEvent (EvKey (KChar 'R') []) -> modify' (regenerateScreens d . toggleReal) >> msCenterAndContinue
--             VtyEvent (EvKey (KChar 'U') []) -> modify' (regenerateScreens d . toggleUnmarked) >> msCenterAndContinue
--             VtyEvent (EvKey (KChar 'P') []) -> modify' (regenerateScreens d . togglePending) >> msCenterAndContinue
--             VtyEvent (EvKey (KChar 'C') []) -> modify' (regenerateScreens d . toggleCleared) >> msCenterAndContinue
--             VtyEvent (EvKey (KChar 'F') []) -> modify' (regenerateScreens d . toggleForecast d)
            -- VtyEvent (EvKey (KChar 'H') []) -> modify' (toggleHistorical >>> regenerateScreens d)

            -- narrow/widen/move the period as on other screens, for consistency
            VtyEvent (EvKey (KDown)     [MShift]) -> modify' (shrinkReportPeriod d             >>> regenerateScreens d)
            VtyEvent (EvKey (KUp)       [MShift]) -> modify' (growReportPeriod d               >>> regenerateScreens d)
            VtyEvent (EvKey (KRight)    [MShift]) -> modify' (nextReportPeriod journalspan     >>> regenerateScreens d)
            VtyEvent (EvKey (KLeft)     [MShift]) -> modify' (previousReportPeriod journalspan >>> regenerateScreens d)
            VtyEvent (EvKey (KChar 'T') [])       -> modify' (setReportPeriod (DayPeriod d)    >>> regenerateScreens d)

            VtyEvent (EvKey (KChar '/') []) -> put' $ regenerateScreens d $ showMinibuffer "filter" Nothing ui
            VtyEvent (EvKey k           []) | k `elem` [KBS, KDel] -> (put' $ regenerateScreens d $ resetFilter ui)

            VtyEvent (EvKey (KChar 'l') [MCtrl]) -> scrollSelectionToMiddle (msListSize $ _mssList sst) (_mssList sst) >> redraw
            VtyEvent (EvKey (KChar 'z') [MCtrl]) -> suspend ui

            -- RIGHT enters selected screen if there is one
            VtyEvent e | e `elem` moveRightEvents
                      , not $ isBlankElement $ listSelectedElement (_mssList sst) ->
              msEnterScreen d (fromMaybe AllAccounts mselscr) ui

            -- MouseDown is sometimes duplicated, https://github.com/jtdaugherty/brick/issues/347
            -- just use it to move the selection
            MouseDown _n BLeft _mods Location{loc=(_x,y)} | not $ (=="") clickedname -> do
              put' ui{aScreen=MS sst}  -- XXX does this do anything ?
              where
                item = listElements (_mssList sst) !? y
                clickedname = maybe "" msItemScreenName item
                -- mclickedscr  = msItemScreen <$> item
            -- and on MouseUp, enter the subscreen
            MouseUp _n (Just BLeft) Location{loc=(_x,y)} ->  -- | not $ (=="") clickedname ->
              case mclickedscr of
                Just scr -> msEnterScreen d scr ui
                Nothing  -> return ()
              where
                item = listElements (_mssList sst) !? y
                -- clickedname = maybe "" msItemScreenName item
                mclickedscr  = msItemScreen <$> item

            -- when selection is at the last item, do nothing
            VtyEvent e | e `elem` moveDownEvents, isBlankElement mnextelement -> return ()
              where mnextelement = listSelectedElement $ listMoveDown (_mssList sst)

            -- mouse scroll wheel scrolls the viewport up or down to its maximum extent,
            -- pushing the selection when necessary.
            MouseDown name btn _mods _loc | btn `elem` [BScrollUp, BScrollDown] -> do
              let scrollamt = if btn==BScrollUp then -1 else 1
              list' <- nestEventM' (_mssList sst) $ listScrollPushingSelection name (msListSize (_mssList sst)) scrollamt
              put' ui{aScreen=MS sst{_mssList=list'}}

            -- if page down or end leads to a blank padding item, stop at last non-blank
            VtyEvent e@(EvKey k           []) | k `elem` [KPageDown, KEnd] -> do
              l <- nestEventM' (_mssList sst) $ handleListEvent e
              if isBlankElement $ listSelectedElement l
              then do
                let l' = listMoveTo lastnonblankidx l
                scrollSelectionToMiddle (msListSize l') l'
                put' ui{aScreen=MS sst{_mssList=l'}}
              else
                put' ui{aScreen=MS sst{_mssList=l}}

            -- fall through to the list's event handler (handles up/down)
            VtyEvent e -> do
              list' <- nestEventM' (_mssList sst) $ handleListEvent (normaliseMovementKeys e)
              put' ui{aScreen=MS $ sst & mssList .~ list'}

            MouseDown{} -> return ()
            MouseUp{}   -> return ()
            AppEvent _  -> return ()


msEnterScreen :: Day -> AccountsScreenKind -> UIState -> EventM Name UIState ()
msEnterScreen d scrname ui@UIState{ajournal=j, aopts=uopts} = do
  dbguiEv "msEnterScreen"
  let scr = asNew scrname uopts d j Nothing  -- scrname is also the accounts-like screen kind
  put' $ pushScreen scr ui

-- | Set the selected list item on the menu screen. Has no effect on other screens.
msSetSelectedScreen :: Int -> Screen -> Screen
msSetSelectedScreen selidx (MS mss@MSS{_mssList=l}) = MS mss{_mssList=listMoveTo selidx l}
msSetSelectedScreen _ s = s

isBlankElement mel = ((msItemScreenName . snd) <$> mel) == Just ""

msListSize = V.length . V.takeWhile ((/="").msItemScreenName) . listElements

