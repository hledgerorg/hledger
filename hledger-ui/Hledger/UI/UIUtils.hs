{- | Rendering & misc. helpers. -}

{-# LANGUAGE CPP               #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE LambdaCase #-}

module Hledger.UI.UIUtils (
   borderDepthStr
  ,borderKeysStr
  ,borderKeysStr'
  ,borderPeriodStr
  ,borderQueryStr
  ,defaultLayout
  ,helpDialog
  ,helpHandle
  ,minibuffer
  ,moveDownEvents
  ,moveLeftEvents
  ,moveRightEvents
  ,moveUpEvents
  ,normaliseMovementKeys
  ,renderToggle
  ,renderToggle1
  ,replaceHiddenAccountsNameWith
  ,scrollSelectionToMiddle
  ,get'
  ,put'
  ,modify'
  ,suspend
  ,redraw
  ,uiInstallWarningCollector
  ,uiTakeWarnings
  ,journalIsFromStdin
  ,reportSpecAddQuery
  ,reportSpecSetFutureAndForecast
  ,listScrollPushingSelection
  ,dbgui
  ,dbguiIO
  ,dbguiEv
  ,dbguiScreensEv
  ,showScreenId
  ,showScreenRegisterDescriptions
  ,showScreenSelection
  ,mapScreens
  ,uiNumBlankItems
  ,showScreenStack
  ,sendVtyEvents  -- currently unused, kept (and exported, to avoid an unused-binding warning) for future use
  )
where

import Brick
import Brick.Widgets.Border
import Brick.Widgets.Border.Style
import Brick.Widgets.Dialog
import Brick.Widgets.Edit
import Brick.Widgets.List (List, listSelectedL, listNameL, listItemHeightL, listSelected, listMoveTo, listElements)
import Control.Concurrent.STM (atomically, writeTChan)  -- GHC only
import Control.Monad.IO.Class
import Data.Bifunctor (second)
import Data.IORef (IORef, newIORef, atomicModifyIORef')
import Data.List
import Data.Text qualified as T
import Data.Time (addDays)
import Graphics.Vty
  (Event(..),Key(..),Modifier(..),Vty(..),Color,Attr,currentAttr,refresh, displayBounds
  -- ,Output(displayBounds,mkDisplayContext),DisplayContext(..)
  ,Vty (inputIface), InternalEvent (InputEvent), Input (eventChannel)
  )
import Lens.Micro.Platform
import System.IO.Unsafe (unsafePerformIO)

import Hledger
-- import Hledger.Cli.CliOptions (CliOpts(reportspec_))
import Hledger.Cli.DocFiles
-- import Hledger.UI.UIOptions (UIOpts(uoCliOpts))
import Hledger.UI.UITypes

import Data.Vector qualified as V

-- | On posix platforms, send the system STOP signal to suspend the
-- current program. On windows, does nothing.
-- (Though, currently hledger-ui is not built on windows.)
#ifdef mingw32_HOST_OS
suspendSignal :: IO ()
suspendSignal = return ()
#else
import System.Posix.Signals
suspendSignal :: IO ()
suspendSignal = raiseSignal sigSTOP
#endif

-- Debug logging for UI state changes.
-- A good place to log things of interest while debugging, see commented examples below.

get' = do
  ui <- get
  dbguiEv $ "getting state: " ++ 
    showScreenStack "" showScreenSelection ui
    -- (head $ lines $ pshow $ aScreen x)
    -- ++ " " ++ (show $ map tdescription $ jtxns $ ajournal x)
  -- dbguiEv $ ("query: "++) $ pshow' $ x  & aopts & uoCliOpts & reportspec_ & _rsQuery
  -- dbguiScreensEv "getting" showScreenId x
  -- dbguiScreensEv "getting, with register descriptions" showScreenRegisterDescriptions x
  return ui

put' ui = do
  dbguiEv $ "putting state: " ++
    showScreenStack "" showScreenSelection ui
    -- (head $ lines $ pshow $ aScreen x)
    -- ++ " " ++ (show $ map tdescription $ jtxns $ ajournal x)
  -- dbguiEv $ ("query: "++) $ pshow' $ x  & aopts & uoCliOpts & reportspec_ & _rsQuery
  -- dbguiScreensEv "putting" showScreenId x
  -- dbguiScreensEv "putting, with register descriptions" showScreenRegisterDescriptions x
  put ui

modify' f = do
  ui <- get
  let ui' = f ui
  dbguiEv $ "getting state: " ++ (showScreenStack "" showScreenSelection ui)
  dbguiEv $ "putting state: " ++ (showScreenStack "" showScreenSelection ui')
    -- (head $ lines $ pshow $ aScreen x')
    -- ++ " " ++ (show $ map tdescription $ jtxns $ ajournal x')
  -- dbguiEv $ ("from: "++) $ pshow' $ x  & aopts & uoCliOpts & reportspec_ & _rsQuery
  -- dbguiEv $ ("to:   "++) $ pshow' $ x' & aopts & uoCliOpts & reportspec_ & _rsQuery
  -- dbguiScreensEv "getting" showScreenId x
  -- dbguiScreensEv "putting" showScreenId x'
  -- dbguiScreensEv "getting, with register descriptions" showScreenRegisterDescriptions x
  -- dbguiScreensEv "putting, with register descriptions" showScreenRegisterDescriptions x'
  modify f

-- | On posix platforms, suspend the program using the STOP signal,
-- like control-z in bash, returning to the original shell prompt,
-- and when resumed, continue where we left off.
-- On windows, does nothing.
suspend :: Ord a => s -> EventM a s ()
suspend st = suspendAndResume $ suspendSignal >> return st

-- | Tell vty to redraw the whole screen.
redraw :: EventM a s ()
redraw = getVtyHandle >>= liftIO . refresh

-- | Where warnings emitted while the TUI is running are collected, oldest first,
-- so they can be shown in the UI instead of being printed to stderr
-- (which would disrupt the terminal display). See uiInstallWarningCollector.
{-# NOINLINE uiWarningsRef #-}
uiWarningsRef :: IORef [String]
uiWarningsRef = unsafePerformIO $ newIORef []

-- | Make warnIO collect warnings in uiWarningsRef instead of printing them to stderr.
-- Call once, before starting the brick app.
uiInstallWarningCollector :: IO ()
uiInstallWarningCollector = setWarningHandler $ \msg ->
  atomicModifyIORef' uiWarningsRef $ \ws -> (ws ++ [msg], ())

-- | Take any warnings collected since last time, clearing the collection.
uiTakeWarnings :: IO [String]
uiTakeWarnings = atomicModifyIORef' uiWarningsRef $ \ws -> ([], ws)

-- | Wrap a widget in the default hledger-ui screen layout.
defaultLayout :: Widget Name -> Widget Name -> Widget Name -> Widget Name
defaultLayout toplabel bottomlabel =
  topBottomBorderWithLabels (str " "<+>toplabel<+>str " ") (str " "<+>bottomlabel<+>str " ") .
  margin 1 0 Nothing
  -- topBottomBorderWithLabel label .
  -- padLeftRight 1 -- XXX should reduce inner widget's width by 2, but doesn't
                    -- "the layout adjusts... if you use the core combinators"

-- | Draw the help dialog, called when help mode is active.
helpDialog :: Widget Name
helpDialog =
  Widget Fixed Fixed $ do
    c <- getContext
    render $
      withDefAttr (attrName "help") $
      renderDialog (dialog (Just $ str "Help (LEFT/ESC/?/q to close help)") Nothing (c^.availWidthL)) $ -- (Just (0,[("ok",())]))
      padTop (Pad 0) $ padLeft (Pad 1) $ padRight (Pad 1) $
        vBox [
           hBox [
              padRight (Pad 1) $
                vBox [
                   withAttr (attrName "help" <> attrName "heading") $ str "Navigation"
                  ,renderKey ("UP/DOWN/PUP/PDN/HOME/END/k/j/C-p/C-n", "")
                  ,str "     move selection up/down"
                  ,renderKey ("RIGHT/l/C-f", "show txns, or txn detail")
                  ,renderKey ("LEFT/h/C-b ", "go back/see other screens")
                  ,renderKey ("ESC ", "cancel, or reset app state")

                  ,str " "
                  ,withAttr (attrName "help" <> attrName "heading") $ str "Accounts screens"
                  ,renderKey ("1234567890-+ ", "set/adjust depth limit")
                  ,renderKey ("t ", "toggle accounts tree/list mode")
                  ,renderKey ("H ", "toggle historical balance/change")
                  ,str " "
                  ,withAttr (attrName "help" <> attrName "heading") $ str "Register screens"
                  ,renderKey ("t ", "toggle subaccount txns\n(and accounts tree/list mode)")
                  ,renderKey ("H ", "toggle historical/period total")
                  ,str " "
                  ,withAttr (attrName "help" <> attrName "heading") $ str "Help"
                  ,renderKey ("?    ", "toggle this help")
                  ,renderKey ("p/m/i", "while help is open:\nshow manual in pager/man/info")
                  ,str " "
                ]
             ,padLeft (Pad 1) $ padRight (Pad 0) $
                vBox [
                   withAttr (attrName "help" <> attrName "heading") $ str "Filtering"
                  ,renderKey ("/   ", "set a filter query")
                  ,renderKey ("F   ", "show future & forecast txns")
                  ,renderKey ("R   ", "show real/all postings")
                  ,renderKey ("z   ", "show nonzero/all amounts")
                  ,renderKey ("U/P/C ", "show unmarked/pending/cleared")
                  ,renderKey ("S-DOWN /S-UP  ", "shrink/grow period")
                  ,renderKey ("S-RIGHT/S-LEFT", "next/previous period")
                  ,renderKey ("T             ", "set period to today")
                  ,renderKey ("DEL ", "reset filters")
                  ,str " "
                  ,withAttr (attrName "help" <> attrName "heading") $ str "Other"
                  ,renderKey ("a   ", "add transaction (hledger add)")
                  ,renderKey ("A   ", "add transaction (hledger-iadd)")
                  ,renderKey ("B   ", "show amounts/costs")
                  ,renderKey ("E   ", "open editor")
                  ,renderKey ("I   ", "toggle balance assertions")
                  ,renderKey ("L   ", "show/hide lot detail")
                  ,renderKey ("V   ", "show amounts/market values")
                  ,renderKey ("g   ", "reload data")
                  ,renderKey ("C-l ", "redraw & recenter")
                  ,renderKey ("C-z ", "suspend")
                  ,renderKey ("q   ", "quit")
                ]
             ]
--           ,vBox [
--              str " "
--             ,hCenter $ padLeftRight 1 $
--               hCenter (str "MANUAL")
--               <=>
--               hCenter (hBox [
--                  renderKey ("t", "text")
--                 ,str " "
--                 ,renderKey ("m", "man page")
--                 ,str " "
--                 ,renderKey ("i", "info")
--                 ])
--             ]
          ]
  where
    renderKey (key,desc) = withAttr (attrName "help" <> attrName "key") (str key) <+> str " " <+> str desc

-- | Event handler used when help mode is active.
-- May invoke $PAGER, less, man or info, which is likely to fail on MS Windows, TODO.
helpHandle :: BrickEvent Name AppEvent -> EventM Name UIState ()
helpHandle ev = do
  ui <- get
  let ui' = ui{aMode=Normal}
  case ev of
    VtyEvent e | e `elem` closeHelpEvents -> put' ui'
    VtyEvent (EvKey (KChar 'p') []) -> suspendAndResume (runPagerForTopic "hledger-ui" Nothing >> return ui')
    VtyEvent (EvKey (KChar 'm') []) -> suspendAndResume (runManForTopic   "hledger-ui" Nothing >> return ui')
    VtyEvent (EvKey (KChar 'i') []) -> suspendAndResume (runInfoForTopic  "hledger-ui" Nothing >> return ui')
    _ -> return ()
  where
    closeHelpEvents = moveLeftEvents ++ [EvKey KEsc [], EvKey (KChar '?') [], EvKey (KChar 'q') []]

-- | Draw the minibuffer with the given label.
minibuffer :: T.Text -> Editor String Name -> Widget Name
minibuffer string ed =
  forceAttr (attrName "border" <> attrName "minibuffer") $
  hBox [txt $ string <> ": ", renderEditor (str . unlines) True ed]

borderQueryStr :: String -> Widget Name
borderQueryStr ""  = str ""
borderQueryStr qry = str " matching " <+> withAttr (attrName "border" <> attrName "query") (str qry)

borderDepthStr :: Maybe Int -> Widget Name
borderDepthStr Nothing  = str ""
borderDepthStr (Just d) = str " to depth " <+> withAttr (attrName "border" <> attrName "query") (str $ show d)

borderPeriodStr :: String -> Period -> Widget Name
borderPeriodStr _           PeriodAll = str ""
borderPeriodStr preposition p         = str (" "++preposition++" ") <+> withAttr (attrName "border" <> attrName "query") (str . T.unpack $ showPeriod p)

borderKeysStr :: [(String,String)] -> Widget Name
borderKeysStr = borderKeysStr' . map (second str)

borderKeysStr' :: [(String,Widget Name)] -> Widget Name
borderKeysStr' keydescs =
  hBox $
  intersperse sep $
  [withAttr (attrName "border" <> attrName "key") (str keys) <+> str ":" <+> desc | (keys, desc) <- keydescs]
  where
    -- sep = str " | "
    sep = str " "

-- | Show both states of a toggle ("aaa/bbb"), highlighting the active one.
renderToggle :: Bool -> String -> String -> Widget Name
renderToggle isright l r =
  let bold = withAttr (attrName "border" <> attrName "selected") in
  if isright
  then str (l++"/") <+> bold (str r)
  else bold (str l) <+> str ("/"++r)

-- | Show a toggle's label, highlighted (bold) when the toggle is active.
renderToggle1 :: Bool -> String -> Widget Name
renderToggle1 isactive l =
  let bold = withAttr (attrName "border" <> attrName "selected") in
  if isactive
  then bold (str l)
  else str l

-- temporary shenanigans:

-- | Replace the special account names "*" and "..." (from balance reports with depth limit 0)
-- to something clearer.
replaceHiddenAccountsNameWith :: AccountName -> AccountName -> AccountName
replaceHiddenAccountsNameWith anew a | a == hiddenAccountsName = anew
                                     | a == "*"                = anew
                                     | otherwise               = a

hiddenAccountsName = "..." -- for now

-- generic

--topBottomBorderWithLabel :: Widget Name -> Widget Name -> Widget Name
--topBottomBorderWithLabel label = \wrapped ->
--  Widget Greedy Greedy $ do
--    c <- getContext
--    let (_w,h) = (c^.availWidthL, c^.availHeightL)
--        h' = h - 2
--        wrapped' = vLimit (h') wrapped
--        debugmsg =
--          ""
--          -- "  debug: "++show (_w,h')
--    render $
--      hBorderWithLabel (label <+> str debugmsg)
--      <=>
--      wrapped'
--      <=>
--      hBorder

topBottomBorderWithLabels :: Widget Name -> Widget Name -> Widget Name -> Widget Name
topBottomBorderWithLabels toplabel bottomlabel body =
  Widget Greedy Greedy $ do
    c <- getContext
    let (_w,h) = (c^.availWidthL, c^.availHeightL)
        h' = h - 2
        body' = vLimit (h') body
        debugmsg =
          ""
          -- "  debug: "++show (_w,h')
    render $
      hBorderWithLabel (withAttr (attrName "border") $ toplabel <+> str debugmsg)
      <=>
      body'
      <=>
      hBorderWithLabel (withAttr (attrName "border") bottomlabel)

---- XXX should be equivalent to the above, but isn't (page down goes offscreen)
--_topBottomBorderWithLabel :: Widget Name -> Widget Name -> Widget Name
--_topBottomBorderWithLabel label = \wrapped ->
-- let debugmsg = ""
-- in hBorderWithLabel (label <+> str debugmsg)
--    <=>
--    wrapped
--    <=>
--    hBorder

-- XXX superseded by pad, in theory
-- | Wrap a widget in a margin with the given horizontal and vertical
-- thickness, using the current background colour or the specified
-- colour.
-- XXX May disrupt border style of inner widgets.
-- XXX Should reduce the available size visible to inner widget, but doesn't seem to (cf rsDraw).
margin :: Int -> Int -> Maybe Color -> Widget Name -> Widget Name
margin h v mcolour w = Widget Greedy Greedy $ do
    ctx <- getContext
    let w' = vLimit (ctx^.availHeightL - v*2) $ hLimit (ctx^.availWidthL - h*2) w
        attr = maybe currentAttr (\c -> c `on` c) mcolour
    render $
      withBorderAttr attr $
      withBorderStyle (borderStyleFromChar ' ') $
      applyN v (hBorder <=>) $
      applyN h (vBorder <+>) $
      applyN v (<=> hBorder) $
      applyN h (<+> vBorder) $
      w'

   -- withBorderAttr attr .
   -- withBorderStyle (borderStyleFromChar ' ') .
   -- applyN n border

withBorderAttr :: Attr -> Widget Name -> Widget Name
withBorderAttr attr = updateAttrMap (applyAttrMappings [(attrName "border", attr)])

---- | Like brick's continue, but first run some action to modify brick's state.
---- This action does not affect the app state, but might eg adjust a widget's scroll position.
--continueWith :: EventM n () -> ui -> EventM n (Next ui)
--continueWith brickaction ui = brickaction >> continue ui

---- | Scroll a list's viewport so that the selected item is at the top
---- of the display area.
--scrollToTop :: List Name e -> EventM Name ()
--scrollToTop list = do
--  let vpname = list^.listNameL
--  setTop (viewportScroll vpname) 0

-- | Scroll a list's viewport so that the selected item is centered in the
-- middle of the display area. When the selected item is near the end of the
-- list, the viewport is capped so that no blank padding is visible below the
-- last real item, and the last real items stay bottom-aligned (so recentering
-- a near-the-end selection doesn't push those items off screen). numitems is
-- the number of non-blank items in the list.
scrollSelectionToMiddle :: Int -> Brick.Widgets.List.List Name item -> EventM Name UIState ()
scrollSelectionToMiddle numitems list = do
  case list^.listSelectedL of
    Nothing -> return ()
    Just selectedrow -> do
      let name = list^.listNameL
      mvp <- lookupViewport name
      -- Use the list viewport's actual height. Before its first render the
      -- viewport isn't known yet, so fall back to the terminal height.
      pageheight <- dbg4 "pageheight" <$> case mvp of
        Just VP{_vpSize=(_,h)} -> return h
        Nothing -> do
          Vty{outputIface} <- getVtyHandle
          snd <$> liftIO (displayBounds outputIface)
      let
        itemheight   = dbg4 "itemheight" $ list^.listItemHeightL
        itemsperpage = dbg4 "itemsperpage" $ pageheight `div` itemheight
        centeredtop  = selectedrow - (itemsperpage `div` 2)
        maxtop       = numitems - itemsperpage
        toprow       = dbg4 "toprow" $ max 0 (min centeredtop maxtop) -- assuming ViewportScroll's row offset is measured in list items not screen rows
      setTop (viewportScroll name) toprow

--                 arrow keys       vi keys               emacs keys                 enter key
moveUpEvents    = [EvKey KUp []   , EvKey (KChar 'k') [], EvKey (KChar 'p') [MCtrl]]
moveDownEvents  = [EvKey KDown [] , EvKey (KChar 'j') [], EvKey (KChar 'n') [MCtrl]]
moveLeftEvents  = [EvKey KLeft [] , EvKey (KChar 'h') [], EvKey (KChar 'b') [MCtrl]]
moveRightEvents = [EvKey KRight [], EvKey (KChar 'l') [], EvKey (KChar 'f') [MCtrl], EvKey KEnter []]

normaliseMovementKeys ev
  | ev `elem` moveUpEvents    = EvKey KUp []
  | ev `elem` moveDownEvents  = EvKey KDown []
  | ev `elem` moveLeftEvents  = EvKey KLeft []
  | ev `elem` moveRightEvents = EvKey KRight []
  | otherwise = ev

-- | Restrict the ReportSpec's query by adding the given additional query.
reportSpecAddQuery :: Query -> ReportSpec -> ReportSpec
reportSpecAddQuery q rspec =
    rspec{_rsQuery=simplifyQuery $ And [_rsQuery rspec, q]}

-- | Update the ReportSpec's query to exclude future transactions (later than its "today" date)
-- and forecast transactions (generated by --forecast), if the given forecast DateSpan is Nothing,
-- and include them otherwise.
reportSpecSetFutureAndForecast :: Maybe DateSpan -> ReportSpec -> ReportSpec
reportSpecSetFutureAndForecast fcast rspec =
    rspec{_rsQuery=simplifyQuery $ And [_rsQuery rspec, periodq, excludeforecastq fcast]}
  where
    periodq = Date . periodAsDateSpan . period_ $ _rsReportOpts rspec
    -- Except in forecast mode, exclude future/forecast transactions.
    excludeforecastq (Just _) = Any
    excludeforecastq Nothing  =  -- not:date:tomorrow- not:tag:generated-transaction
      And [
         Not (Date $ DateSpan (Just $ Exact $ addDays 1 $ _rsDay rspec) Nothing)
        ,Not generatedTransactionTag
      ]

-- Vertically scroll the named list's viewport, which shows the given number of
-- non-blank items, by the given positive or negative number of items (usually 1 or -1).
-- Scrolling stops with the first item at the top or the last item at the bottom,
-- ignoring the blank items that pad the list out to the window height.
-- The selection is pushed along when necessary to keep it within the viewport;
-- without this, brick's list would keep pulling the viewport back to the selection,
-- stopping the scroll as soon as the selection reached the viewport's edge.
-- The (possibly moved) selection is left in the event handler's state.
listScrollPushingSelection :: Name -> Int -> Int -> EventM Name (Brick.Widgets.List.List Name item) ()
listScrollPushingSelection name listheight scrollamt =
  lookupViewport name >>= \case
    Nothing -> return ()
    Just VP{_vpTop, _vpSize=(_,vpheight)} -> do
      let
        lastitem = listheight - 1
        top    = min (max 0 $ listheight - vpheight) $ max 0 $ _vpTop + scrollamt  -- new first visible item
        bottom = min lastitem $ top + vpheight - 1                                 -- new last visible item
      viewportScroll name `vScrollBy` (top - _vpTop)
      modify $ \list -> case listSelected list of
        Just selidx | selidx < top    -> listMoveTo top list
                    | selidx > bottom -> listMoveTo bottom list
        _ -> list

-- | A debug logging helper for hledger-ui code: at any debug level >= 1,
-- logs the string to hledger-ui.log before returning the second argument.
-- Uses unsafePerformIO.
dbgui :: String -> a -> a
dbgui = dbg1Msg

-- | Like dbgui, but convenient to use in IO.
dbguiIO :: String -> IO ()
dbguiIO = dbg1MsgIO

-- | Was this journal's main file read from standard input ?
-- If so it can't be re-read, edited, or watched for changes.
journalIsFromStdin :: Journal -> Bool
journalIsFromStdin j = journalFilePath j == "-"

-- | Like dbgui, but convenient to use in EventM handlers.
dbguiEv :: String -> EventM Name s ()
dbguiEv s = dbg1Msg s $ return ()

-- | Like dbguiEv, but log a compact view of the current screen stack.
-- See showScreenStack.
-- To just log the stack: @dbguiScreensEv "" showScreenId ui@
dbguiScreensEv :: String -> (Screen -> String) -> UIState -> EventM Name UIState ()
dbguiScreensEv postfix showscr ui = dbguiEv $ showScreenStack postfix showscr ui

-- Render a compact labelled view of the current screen stack,
-- adding the given postfix to the label (can be empty),
-- from the topmost screen to the currently-viewed screen,
-- with each screen rendered by the given rendering function.
-- Useful for inspecting states across the whole screen stack.
-- Some screen rendering functions are 
-- @showScreenId@, @showScreenSelection@, @showScreenRegisterDescriptions@.
--
-- Eg to just show the stack: @showScreenStack "" showScreenId ui@
--
-- To to show the stack plus selected item indexes: @showScreenStack "" showScreenSelection ui@
--
showScreenStack :: String -> (Screen -> String) -> UIState -> String
showScreenStack postfix showscr ui = concat [
    "screen stack"
  ,if null postfix then "" else ", " ++ postfix
  ,": "
  ,unwords $ mapScreens showscr ui
  ]

-- | Run a function on each screen in a UIState's screen "stack",
-- from topmost screen down to currently-viewed screen.
mapScreens :: (Screen -> a) -> UIState -> [a]
mapScreens f UIState{aPrevScreens, aScreen} = map f $ reverse $ aScreen : aPrevScreens

-- Show a screen's compact id (first letter of its constructor).
showScreenId :: Screen -> String
showScreenId = \case
  MS _             -> "M"  -- menu
  AS ASS{_assKind} -> accountsScreenKindId _assKind
  RS _             -> "R"  -- register
  TS _             -> "T"  -- transaction
  ES _             -> "E"  -- error

-- | The compact id letter for an accounts-like screen of the given kind.
accountsScreenKindId :: AccountsScreenKind -> String
accountsScreenKindId = \case
  AllAccounts             -> "A"  -- all accounts
  CashAccounts            -> "C"  -- cash accounts
  BalancesheetAccounts    -> "B"  -- balance sheet accounts
  IncomestatementAccounts -> "I"  -- income statement accounts

-- Show a screen's compact id, plus for register screens, the transaction descriptions.
showScreenRegisterDescriptions :: Screen -> String
showScreenRegisterDescriptions scr = case scr of
  RS sst -> ((showScreenId scr ++ ":") ++) $ -- menu
    intercalate "," $ map (T.unpack . rsItemDescription) $
    takeWhile (not . T.null . rsItemDate) $ V.toList $ listElements $ _rssList sst
  _ -> showScreenId scr

-- Show a screen's compact id, plus index of its selected list item if any.
showScreenSelection :: Screen -> String
showScreenSelection = \case
  MS MSS{_mssList}          -> "M" ++ (maybe "" show $ listSelected _mssList)  -- menu
  AS ASS{_assKind,_assList} -> accountsScreenKindId _assKind ++ (maybe "" show $ listSelected _assList)
  RS RSS{_rssList}          -> "R" ++ (maybe "" show $ listSelected _rssList)  -- register
  TS _ -> "T"  -- transaction
  ES _ -> "E"  -- error

-- | How many blank items to add to lists to fill the full window height.
uiNumBlankItems :: Int
uiNumBlankItems
  -- | debugLevel >= uiDebugLevel = 0    -- suppress to improve debug output.
  -- | otherwise 
  = 100  -- 100 ought to be enough for anyone

-- Send some events to vty, atomically so they won't have other events interleaved.
-- (But there may be events already in the channel ahead of them.)
sendVtyEvents :: [Event] -> EventM n s ()
sendVtyEvents evs = do
  input <- eventChannel . inputIface <$> getVtyHandle
  liftIO $ atomically $ mapM_ (writeTChan input . InputEvent) evs
