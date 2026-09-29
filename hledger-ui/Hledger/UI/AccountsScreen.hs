-- The accounts screen, showing accounts and balances like the CLI balance command.

{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TupleSections #-}

module Hledger.UI.AccountsScreen
 (asNew
 ,asUpdate
 ,asDraw
 ,asDrawHelper
 ,asHandle
 ,handleHelpMode
 ,handleMinibufferMode
 ,asHandleNormalMode
 ,enterRegisterScreen
 ,asSetSelectedAccount
 )
where

import Brick
import Brick.Widgets.List
import Brick.Widgets.Edit
import Control.Monad
import Control.Monad.IO.Class (liftIO)
#if MIN_VERSION_base(4,19,0)
import Data.List hiding (reverse, (!?))
#else
import Data.List hiding (reverse)
#endif
import Data.Maybe
import Data.Text qualified as T
import Data.Time.Calendar (Day)
import Data.Vector qualified as V
import Data.Vector ((!?))
import Graphics.Vty (Event(..),Key(..),Modifier(..), Button (BLeft, BScrollDown, BScrollUp))
import Lens.Micro.Platform
import System.Console.ANSI
import System.FilePath (takeFileName)
import Text.DocLayout (realLength)

import Hledger.Utils.I18n (tr)
import Hledger
import Hledger.Cli hiding (Mode, mode, progname, prognameandversion)
import Hledger.UI.UIOptions
import Hledger.UI.UITypes
import Hledger.UI.UIState
import Hledger.UI.UIUtils
import Hledger.UI.UIScreens
import Hledger.UI.Editor
import Hledger.UI.ErrorScreen (uiReload, uiReloadIfFileChanged, uiToggleBalanceAssertions)
import Hledger.UI.RegisterScreen (rsCenterSelection)
import Data.Either (fromRight)
import Control.Arrow ((>>>))
import Safe (headDef)


asDraw :: AccountsScreenState -> UIState -> [Widget Name]
asDraw ass@ASS{_assKind=kind} ui = dbgui "asDraw" $ asDrawHelper ass ui ropts' scrname
  where
    ropts'  = accountsScreenRoptsMod kind $ _rsReportOpts $ reportspec_ $ uoCliOpts $ aopts ui
    scrname = accountsScreenName kind ropts'

-- | The display name shown in an accounts-like screen's header, for the given kind.
accountsScreenName :: AccountsScreenKind -> ReportOpts -> String
accountsScreenName kind ropts = T.unpack $ case kind of
  AllAccounts | balanceaccum_ ropts == Historical -> tr trs "account balances"
              | otherwise                         -> tr trs "account changes"
  CashAccounts            -> tr trs "cash balances"
  BalancesheetAccounts    -> tr trs "balance sheet balances"
  IncomestatementAccounts -> tr trs "income statement changes"
  where trs = translations_ ropts

-- | Help draw any accounts-like screen (all accounts, balance sheet, income statement..).
-- The provided ReportOpts are used instead of the ones in the UIState.
-- The other argument is the screen display name.
asDrawHelper :: AccountsScreenState -> UIState -> ReportOpts -> String -> [Widget Name]
asDrawHelper ass UIState{aopts=uopts, ajournal=j, aMode=mode} ropts scrname =
  dbgui "asDrawHelper" $
  case mode of
      Help -> [helpDialog, maincontent]
      _    -> [maincontent]
      where
        UIOpts{uoCliOpts=copts} = uopts
        maincontent = Widget Greedy Greedy $ do
          c <- getContext
          let
            availwidth =
              -- ltrace "availwidth" $
              c^.availWidthL
              - 2 -- XXX due to margin ? shouldn't be necessary (cf UIUtils)
            displayitems = ass ^. assList . listElementsL

            acctwidths = V.map (\AccountsScreenItem{..} -> asItemIndentLevel + realLength asItemDisplayAccountName) displayitems
            balwidths  = V.map (maybe 0 (wbWidth . showMixedAmountB oneLineNoCostFmt) . asItemMixedAmount) displayitems
            preferredacctwidth = V.maximum acctwidths
            totalacctwidthseen = V.sum acctwidths
            preferredbalwidth  = V.maximum balwidths
            totalbalwidthseen  = V.sum balwidths

            totalwidthseen = totalacctwidthseen + totalbalwidthseen
            shortfall = preferredacctwidth + preferredbalwidth + 2 - availwidth
            acctwidthproportion = fromIntegral totalacctwidthseen `divideSafe` fromIntegral totalwidthseen
            adjustedacctwidth = min preferredacctwidth . max 15 . round $ acctwidthproportion * fromIntegral (availwidth - 2)  -- leave 2 whitespace for padding
            adjustedbalwidth  = availwidth - 2 - adjustedacctwidth

            -- XXX how to minimise the balance column's jumping around as you change the depth limit ?

            colwidths | shortfall <= 0 = (preferredacctwidth, preferredbalwidth)
                      | otherwise      = (adjustedacctwidth, adjustedbalwidth)

          render $ defaultLayout toplabel bottomlabel $ renderList (asDrawItem colwidths) True (ass ^. assList)

          where
            ishistorical = balanceaccum_ ropts == Historical

            toplabel =
                  withAttr (attrName "border" <> attrName "filename") fs
              <+> toggles
              <+> str (" " ++ scrname)
              <+> borderPeriodStr (if ishistorical then "at end of" else "in") (period_ ropts)
              <+> borderQueryStr (T.unpack . T.unwords . map textQuoteIfNeeded $ querystring_ ropts)
              <+> borderDepthStr mdepth
              <+> str (" ("++curidx++"/"++totidx++")")
              <+> (if ignore_assertions_ . balancingopts_ $ inputopts_ copts
                  then withAttr (attrName "border" <> attrName "query") (str " ignoring balance assertions")
                  else str "")
              where
                fs = case journalFilePaths j of
                              [] -> str ""
                              f:_ -> str $ takeFileName f
                              -- [f,_:[]] -> (withAttr ("border" <> "bold") $ str $ takeFileName f) <+> str " (& 1 included file)"
                              -- f:fs  -> (withAttr ("border" <> "bold") $ str $ takeFileName f) <+> str (" (& " ++ show (length fs) ++ " included files)")
                toggles = withAttr (attrName "border" <> attrName "query") $ str $ unwords $ concat [
                  [""]
                  ,if empty_ ropts then [] else ["nonzero"]
                  ,uiShowStatus copts $ statuses_ ropts
                  ,if real_ ropts then ["real"] else []
                  ]
                mdepth = dsFlatDepth $ depth_ ropts
                curidx = case ass ^. assList . listSelectedL of
                          Nothing -> "-"
                          Just i -> show (i + 1)
                totidx = show $ V.length nonblanks
                  where
                    nonblanks = V.takeWhile (not . T.null . asItemAccountName) $ ass ^. assList . listElementsL

            bottomlabel = case mode of
                            Minibuffer label ed -> minibuffer label ed
                            _                   -> quickhelp
              where
                quickhelp = borderKeysStr' [
                   ("LEFT", str "back")
                  -- ,("RIGHT", str "register")
                  ,("t", renderToggle (tree_ ropts) "list" "tree")
                  -- ,("t", str "tree")
                  -- ,("l", str "list")
                  ,("-+", str "depth")
                  ,case _assKind ass of
                    BalancesheetAccounts    -> ("", str "")
                    IncomestatementAccounts -> ("", str "")
                    _                       -> ("H", renderToggle (not ishistorical) "end-bals" "changes")
                  ,("F", renderToggle1 (isJust . forecast_ $ inputopts_ copts) "forecast")
                  ,("L", renderToggle1 (boolopt "lots" $ rawopts_ copts) "lots")
                  --,("/", "filter")
                  --,("DEL", "unfilter")
                  --,("ESC", "cancel/top")
                  -- ,("a", str "add")
                  -- ,("g", "reload")
                  ,("?", str "help")
                  -- ,("q", str "quit")
                  ]

asDrawItem :: (Int,Int) -> Bool -> AccountsScreenItem -> Widget Name
asDrawItem (acctwidth, balwidth) selected AccountsScreenItem{..} =
  Widget Greedy Fixed $ do
    -- c <- getContext
      -- let showitem = intercalate "\n" . balanceReportItemAsText defreportopts fmt
    render $
      txt (fitText (Just acctwidth) (Just acctwidth) True True $ T.replicate (asItemIndentLevel) " " <> asItemDisplayAccountName) <+>
      txt balspace <+>
      splitAmounts balBuilder
      where
        balBuilder = maybe mempty showamt asItemMixedAmount
        showamt = showMixedAmountB oneLineNoCostFmt{displayMinWidth=Just balwidth, displayMaxWidth=Just balwidth}
        balspace = T.replicate (2 + balwidth - wbWidth balBuilder) " "
        splitAmounts = foldr1 (<+>) . intersperse (str ", ") . map renderamt . T.splitOn ", " . wbToText
        renderamt :: T.Text -> Widget Name
        renderamt a | T.any (=='-') a = withAttr (sel $ attrName "list" <> attrName "balance" <> attrName "negative") $ txt a
                    | otherwise       = withAttr (sel $ attrName "list" <> attrName "balance" <> attrName "positive") $ txt a
        sel | selected  = (<> attrName "selected")
            | otherwise = id

-- | Handle events on any accounts-like screen (all accounts, balance sheet, income statement..).
asHandle :: AccountsScreenState -> BrickEvent Name AppEvent -> EventM Name UIState ()
asHandle ass ev = do
  dbguiEv "asHandle"
  ui0@UIState{aMode=mode} <- get'
  -- save the currently selected account, in case we leave this screen and lose the selection
  put' ui0{aScreen=AS ass{_assSelectedAccount=asSelectedAccount ass}}
  case mode of
    Normal          -> asHandleNormalMode ass ev
    Minibuffer _ ed -> handleMinibufferMode ed ev
    Help            -> handleHelpMode ev

-- | Handle events when in normal mode on any accounts-like screen.
-- The provided state should be the ui state's current screen.
asHandleNormalMode :: AccountsScreenState -> BrickEvent Name AppEvent -> EventM Name UIState ()
asHandleNormalMode ass ev = do
  dbguiEv "asHandleNormalMode"

  ui@UIState{aopts=UIOpts{uoCliOpts=copts}, ajournal=j} <- get'
  d <- liftIO getCurrentDay
  let
    l = _assList ass
    selacct = asSelectedAccount ass
    centerSelection = scrollSelectionToMiddle (asListSize l) l
    clickedAcctAt y =
      case asItemAccountName <$> listElements l !? y of
        Just t | not $ T.null t -> Just t
        _ -> Nothing
    nonblanks = V.takeWhile (not . T.null . asItemAccountName) $ listElements l
    lastnonblankidx = max 0 (length nonblanks - 1)
    journalspan = journalDateSpan False j

  case ev of

    VtyEvent (EvKey (KChar 'q') []) -> halt                               -- q: quit
    VtyEvent (EvKey (KChar 'z') [MCtrl]) -> suspend ui                    -- C-z: suspend
    VtyEvent (EvKey (KChar 'l') [MCtrl]) -> centerSelection >> redraw     -- C-l: redraw
    VtyEvent (EvKey KEsc        []) -> modify' (resetScreens d)           -- ESC: reset
    VtyEvent (EvKey (KChar c)   []) | c == '?' -> modify' (setMode Help)  -- ?: enter help mode
    
    -- AppEvents come from the system, in --watch mode.
    -- XXX currently they are handled only in Normal mode
    -- XXX be sure we don't leave unconsumed app events piling up
    -- A data file has changed (or the user has pressed g): reload.
    e | e `elem` [AppEvent FileChange, VtyEvent (EvKey (KChar 'g') [])] ->
      uiReload copts d ui >>= put'

    -- The date has changed (and we are viewing a standard period which contained the old date):
    -- adjust the viewed period and regenerate, just in case needed.
    -- (Eg: when watching data for "today" and the time has just passed midnight.)
    AppEvent (DateChange old _) | isStandardPeriod p && p `periodContainsDate` old ->
      modify' (setReportPeriod (DayPeriod d) >>> regenerateScreens d)
      where p = reportPeriod ui

    -- set or reset a filter:
    VtyEvent (EvKey (KChar '/') []) -> modify' (showMinibuffer "filter" Nothing >>> regenerateScreens d)
    VtyEvent (EvKey k           []) | k `elem` [KBS, KDel] -> modify' (resetFilter >>> regenerateScreens d)

    -- run external programs:
    VtyEvent (EvKey (KChar 'a') []) -> suspendAndResume $ clearScreen >> setCursorPosition 0 0 >> add (cliOptsDropArgs copts) j >> uiReloadIfFileChanged copts d j ui
    VtyEvent (EvKey (KChar 'A') []) -> suspendAndResume $ void (runIadd (journalFilePath j)) >> uiReloadIfFileChanged copts d j ui
    VtyEvent (EvKey (KChar 'E') []) -> suspendAndResume $ void (runEditor endPosition (journalFilePath j)) >> uiReloadIfFileChanged copts d j ui
    -- J/K Jumps: move 10 rows at a time
    VtyEvent (EvKey (KChar 'J') []) -> do
      let l' = listMoveBy 10 l
      -- Ensure we don't jump into the blank padding at the end
      let l'' = if isBlankItem (listSelectedElement l')
                then listMoveTo lastnonblankidx l'
                else l'
      put' ui{aScreen=AS ass{_assList=l''}}

    VtyEvent (EvKey (KChar 'K') []) -> do
      let l' = listMoveBy (-10) l
      put' ui{aScreen=AS ass{_assList=l'}}

    -- adjust the period displayed:
    VtyEvent (EvKey (KChar 'T') []) ->       modify' (setReportPeriod (DayPeriod d)    >>> regenerateScreens d)
    VtyEvent (EvKey (KDown)     [MShift]) -> modify' (shrinkReportPeriod d             >>> regenerateScreens d)
    VtyEvent (EvKey (KUp)       [MShift]) -> modify' (growReportPeriod d               >>> regenerateScreens d)
    VtyEvent (EvKey (KRight)    [MShift]) -> modify' (nextReportPeriod journalspan     >>> regenerateScreens d)
    VtyEvent (EvKey (KLeft)     [MShift]) -> modify' (previousReportPeriod journalspan >>> regenerateScreens d)

    -- various toggles and settings:
    VtyEvent (EvKey (KChar 'I') []) -> get' >>= uiToggleBalanceAssertions d
    VtyEvent (EvKey (KChar 'F') []) -> modify' (toggleForecast d   >>> regenerateScreens d)
    VtyEvent (EvKey (KChar 'B') []) -> modify' (toggleConversionOp >>> regenerateScreens d)
    VtyEvent (EvKey (KChar 'V') []) -> modify' (toggleValue        >>> regenerateScreens d)
    VtyEvent (EvKey (KChar '0') []) -> modify' (setDepth (Just 0)  >>> regenerateScreens d)
    VtyEvent (EvKey (KChar '1') []) -> modify' (setDepth (Just 1)  >>> regenerateScreens d)
    VtyEvent (EvKey (KChar '2') []) -> modify' (setDepth (Just 2)  >>> regenerateScreens d)
    VtyEvent (EvKey (KChar '3') []) -> modify' (setDepth (Just 3)  >>> regenerateScreens d)
    VtyEvent (EvKey (KChar '4') []) -> modify' (setDepth (Just 4)  >>> regenerateScreens d)
    VtyEvent (EvKey (KChar '5') []) -> modify' (setDepth (Just 5)  >>> regenerateScreens d)
    VtyEvent (EvKey (KChar '6') []) -> modify' (setDepth (Just 6)  >>> regenerateScreens d)
    VtyEvent (EvKey (KChar '7') []) -> modify' (setDepth (Just 7)  >>> regenerateScreens d)
    VtyEvent (EvKey (KChar '8') []) -> modify' (setDepth (Just 8)  >>> regenerateScreens d)
    VtyEvent (EvKey (KChar '9') []) -> modify' (setDepth (Just 9)  >>> regenerateScreens d)
    VtyEvent (EvKey (KChar c) []) | c `elem` ['-','_'] -> modify' (decDepth >>> regenerateScreens d)
    VtyEvent (EvKey (KChar c) []) | c `elem` ['+','='] -> modify' (incDepth >>> regenerateScreens d)
    -- toggles after which the selection should be recentered:
    VtyEvent (EvKey (KChar 'L') []) -> modify' (toggleLots         >>> regenerateScreens d) >> centerSelection
    VtyEvent (EvKey (KChar 'H') []) -> modify' (toggleHistorical   >>> regenerateScreens d) >> centerSelection  -- harmless on BS/IS screens
    VtyEvent (EvKey (KChar 't') []) -> modify' (toggleTree         >>> regenerateScreens d) >> centerSelection
    VtyEvent (EvKey (KChar 'R') []) -> modify' (toggleReal         >>> regenerateScreens d) >> centerSelection
    VtyEvent (EvKey (KChar 'U') []) -> modify' (toggleUnmarked     >>> regenerateScreens d) >> centerSelection
    VtyEvent (EvKey (KChar 'P') []) -> modify' (togglePending      >>> regenerateScreens d) >> centerSelection
    VtyEvent (EvKey (KChar 'C') []) -> modify' (toggleCleared      >>> regenerateScreens d) >> centerSelection
    VtyEvent (EvKey (KChar c) []) | c `elem` ['z','Z'] -> modify' (toggleEmpty >>> regenerateScreens d) >> centerSelection  -- back compat: accept Z as well as z

    -- LEFT key or a click in the app's left margin: exit to the parent screen.
    VtyEvent e | e `elem` moveLeftEvents  -> modify' popScreen
    VtyEvent (EvMouseUp 0 _ (Just BLeft)) -> modify' popScreen  -- this mouse click is a VtyEvent since not in a clickable widget

    -- RIGHT key or MouseUp on an account: enter the register screen for the selected account
    VtyEvent e | e `elem` moveRightEvents, not $ isBlankItem $ listSelectedElement l -> enterRegisterScreen d selacct ui
    MouseUp _n (Just BLeft) Location{loc=(_,y)} | Just clkacct <- clickedAcctAt y    -> enterRegisterScreen d clkacct ui

    -- MouseDown: this is not debounced and can repeat (https://github.com/jtdaugherty/brick/issues/347)
    -- so we only let it do something harmless: move the selection.
    MouseDown _n BLeft _mods Location{loc=(_,y)} | not $ isBlankItem clickeditem ->
      put' ui{aScreen=AS ass'}
      where
        clickeditem = (0,) <$> listElements l !? y
        ass' = ass{_assList=listMoveTo y l}

    -- Mouse scroll wheel: scroll up or down to the maximum extent, pushing the selection when necessary.
    MouseDown name btn _mods _loc | btn `elem` [BScrollUp, BScrollDown] -> do
      let scrollamt = if btn==BScrollUp then -1 else 1
      l' <- nestEventM' l $ listScrollPushingSelection name (asListSize l) scrollamt
      put' ui{aScreen=AS ass{_assList=l'}}

    -- PGDOWN/END keys: handle with List's default handler, but restrict the selection to stop
    -- (and center) at the last non-blank item.
    VtyEvent e@(EvKey k []) | k `elem` [KPageDown, KEnd] -> do
      l1 <- nestEventM' l $ handleListEvent e
      if isBlankItem $ listSelectedElement l1
      then do
        let l2 = listMoveTo lastnonblankidx l1
        scrollSelectionToMiddle (asListSize l2) l2
        put' ui{aScreen=AS ass{_assList=l2}}
      else
        put' ui{aScreen=AS ass{_assList=l1}}

    -- DOWN key when selection is at the last item: do nothing
    VtyEvent e | e `elem` moveDownEvents, isBlankItem mnextelement -> return ()
      where mnextelement = listSelectedElement $ listMoveDown l

    -- Any other vty event (UP, DOWN, PGUP etc): handle with List's default handler.
    VtyEvent e -> do
      l' <- nestEventM' l $ handleListEvent (normaliseMovementKeys e)
      put' ui{aScreen=AS $ ass & assList .~ l' & assSelectedAccount .~ selacct}

    -- Any other mouse/app event: ignore
    MouseDown{} -> return ()
    MouseUp{}   -> return ()
    AppEvent _  -> return ()

-- | Handle events when in minibuffer mode on any screen.
handleMinibufferMode ed ev = do
  ui <- get'
  d <- liftIO getCurrentDay
  case ev of
    VtyEvent (EvKey KEsc   []) -> put' $ closeMinibuffer ui
    VtyEvent (EvKey KEnter []) -> put' $ regenerateScreens d ui'
      where
        ui' = setFilter s (closeMinibuffer ui)
          & fromRight (showMinibuffer "Cannot compile regular expression" (Just s) ui)
          where s = chomp $ unlines $ map strip $ getEditContents ed
    VtyEvent (EvKey (KChar 'l') [MCtrl]) -> redraw
    VtyEvent (EvKey (KChar 'z') [MCtrl]) -> suspend ui
    VtyEvent e -> do
      ed' <- nestEventM' ed $ handleEditorEvent (VtyEvent e)
      put' ui{aMode=Minibuffer "filter" ed'}
    AppEvent _  -> return ()
    MouseDown{} -> return ()
    MouseUp{}   -> return ()

-- | Handle events when in help mode on any screen.
handleHelpMode ev = do
  ui <- get'
  case ev of
    -- VtyEvent (EvKey (KChar 'q') []) -> halt
    VtyEvent (EvKey (KChar 'l') [MCtrl]) -> redraw
    VtyEvent (EvKey (KChar 'z') [MCtrl]) -> suspend ui
    _ -> helpHandle ev

enterRegisterScreen :: Day -> AccountName -> UIState -> EventM Name UIState ()
enterRegisterScreen d acct ui@UIState{ajournal=j, aopts=uopts} = do
  dbguiEv "enterRegisterScreen"
  let
    regscr = rsNew uopts d j acct isdepthclipped
      where
        isdepthclipped = case getDepth ui of
                          Just de -> accountNameLevel acct >= de
                          Nothing -> False
    ui1 = pushScreen regscr ui
  rsCenterSelection ui1 >>= put'

-- | From any accounts screen's state, get the account name from the 
-- currently selected list item, or otherwise the last known selected account name.
asSelectedAccount :: AccountsScreenState -> AccountName
asSelectedAccount ass =
  case listSelectedElement $ _assList ass of
    Just (_, AccountsScreenItem{..}) -> asItemAccountName
    Nothing -> ass ^. assSelectedAccount

-- | Set the selected account on any of the accounts screens. Has no effect on other screens.
-- Sets the high-level property _assSelectedAccount and also selects the corresponding or
-- best alternative item in the list widget (_assList).
asSetSelectedAccount :: AccountName -> Screen -> Screen
asSetSelectedAccount acct scr =
  case scr of
    (AS ass) -> AS $ assSetSelectedAccount acct ass
    _        -> scr
    where
      assSetSelectedAccount a ass@ASS{_assList=l} =
        ass{_assSelectedAccount=a, _assList=listMoveTo selidx l}
        where
          -- which list item should be selected ?
          selidx = headDef 0 $ catMaybes [
            elemIndex a as                                -- the specified account, if it can be found
            ,findIndex (a `isAccountNamePrefixOf`) as     -- or the first account found with the same prefix
            ,Just $ max 0 (length (filter (< a) as) - 1)  -- otherwise, the alphabetically preceding account.
            ]
            where
              as = map asItemAccountName $ V.toList $ listElements l

-- | Is this a blank account-list item, or no item at all (empty list / no selection) ?
-- Either way there is no real account here to act on.
isBlankItem mitem = maybe True (T.null . asItemAccountName . snd) mitem

asListSize = V.length . V.takeWhile ((/="").asItemAccountName) . listElements



