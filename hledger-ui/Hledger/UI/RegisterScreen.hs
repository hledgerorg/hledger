-- The account register screen, showing transactions in an account, like hledger-web's register.

{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# OPTIONS_GHC -Wno-incomplete-record-updates #-}

module Hledger.UI.RegisterScreen
(rsNew
,rsUpdate
,rsDraw
,rsHandle
,rsSetAccount
,rsCenterSelection
)
where

import Control.Monad
import Control.Monad.IO.Class (liftIO)
import Data.Bifunctor (bimap, Bifunctor (second))
#if MIN_VERSION_base(4,19,0)
import Data.List hiding ((!?))
#else
import Data.List
#endif
import Data.Maybe
import Data.Text qualified as T
import Data.Vector qualified as V
import Data.Vector ((!?))
import Graphics.Vty (Event(..),Key(..),Modifier(..), Button (BLeft, BScrollDown, BScrollUp))
import Brick
import Brick.Widgets.List hiding (reverse)
import Brick.Widgets.Edit
import Lens.Micro.Platform
import System.Console.ANSI

import Hledger
import Hledger.Cli hiding (mode, progname,prognameandversion)
import Hledger.UI.UIOptions
import Hledger.UI.UITypes
import Hledger.UI.UIState
import Hledger.UI.UIUtils
import Hledger.UI.UIScreens
import Hledger.UI.Editor
import Hledger.UI.ErrorScreen (uiReload, uiReloadIfFileChanged, uiToggleBalanceAssertions)

rsDraw :: RegisterScreenState -> UIState -> [Widget Name]
rsDraw RSS{..} UIState{aopts=uopts@UIOpts{uoCliOpts=copts@CliOpts{reportspec_=rspec}}
              ,aMode=mode
              } = dbgui "rsDraw" $
  case mode of
    Help       -> [helpDialog, maincontent]
    _          -> [maincontent]
  where
    displayitems = V.toList $ listElements $ _rssList
    maincontent = Widget Greedy Greedy $ do
      -- calculate column widths, based on current available width
      c <- getContext
      let
        totalwidth = c^.availWidthL
                     - 2 -- XXX due to margin ? shouldn't be necessary (cf UIUtils)
        -- the date column is fixed width
        datewidth = 10
        -- multi-commodity amounts rendered on one line can be
        -- arbitrarily wide.  Give the two amounts as much space as
        -- they need, while reserving a minimum of space for other
        -- columns and whitespace.  If they don't get all they need,
        -- allocate it to them proportionally to their maximum widths.
        whitespacewidth = 10 -- inter-column whitespace, fixed width
        minnonamtcolswidth = datewidth + 1 + 2 + 2 -- date column plus at least 1 for status and 2 for desc and accts
        maxamtswidth = max 0 (totalwidth - minnonamtcolswidth - whitespacewidth)
        maxchangewidthseen = maximum' $ map (wbWidth . rsItemChangeAmount) displayitems
        maxbalwidthseen = maximum' $ map (wbWidth . rsItemBalanceAmount) displayitems
        changewidthproportion = fromIntegral maxchangewidthseen `divideSafe` fromIntegral (maxchangewidthseen + maxbalwidthseen)
        maxchangewidth = round $ changewidthproportion * fromIntegral maxamtswidth
        maxbalwidth = maxamtswidth - maxchangewidth
        changewidth = min maxchangewidth maxchangewidthseen
        balwidth = min maxbalwidth maxbalwidthseen
        -- assign the remaining space to the description and accounts columns
        -- maxdescacctswidth = totalwidth - (whitespacewidth - 4) - changewidth - balwidth
        maxdescacctswidth =
          -- trace (show (totalwidth, datewidth, changewidth, balwidth, whitespacewidth)) $
          max 0 (totalwidth - datewidth - 1 - changewidth - balwidth - whitespacewidth)
        -- allocating proportionally.
        -- descwidth' = maximum' $ map (strWidth . second6) displayitems
        -- acctswidth' = maximum' $ map (strWidth . third6) displayitems
        -- descwidthproportion = (descwidth' + acctswidth') / descwidth'
        -- maxdescwidth = min (maxdescacctswidth - 7) (maxdescacctswidth / descwidthproportion)
        -- maxacctswidth = maxdescacctswidth - maxdescwidth
        -- descwidth = min maxdescwidth descwidth'
        -- acctswidth = min maxacctswidth acctswidth'
        -- allocating equally.
        descwidth = maxdescacctswidth `div` 2
        acctswidth = maxdescacctswidth - descwidth
        colwidths = (datewidth,descwidth,acctswidth,changewidth,balwidth)

      render $ defaultLayout toplabel bottomlabel $ renderList (rsDrawItem colwidths) True _rssList

      where
        ropts = _rsReportOpts rspec
        ishistorical = balanceaccum_ ropts == Historical
        -- inclusive = tree_ ropts || rsForceInclusive

        toplabel =
              withAttr (attrName "border" <> attrName "bold") (str $ T.unpack $ replaceHiddenAccountsNameWith "All" $ uiDisplayAccount uopts _rssAccount)
--           <+> withAttr ("border" <> "query") (str $ if inclusive then "" else " exclusive")
          <+> togglefilters
          <+> str " transactions"
          -- <+> str (if ishistorical then " historical total" else " period total")
          <+> borderQueryStr (T.unpack . T.unwords . map textQuoteIfNeeded $ querystring_ ropts)
          -- <+> str " and subs"
          <+> borderPeriodStr "in" (period_ ropts)
          <+> str " ("
          <+> cur
          <+> str "/"
          <+> total
          <+> str ")"
          <+> (if ignore_assertions_ . balancingopts_ $ inputopts_ copts then withAttr (attrName "border" <> attrName "query") (str " ignoring balance assertions") else str "")
          where
            togglefilters =
              case concat [
                   uiShowStatus copts $ statuses_ ropts
                  ,if real_ ropts then ["real"] else []
                  ,if empty_ ropts then [] else ["nonzero"]
                  ] of
                [] -> str ""
                fs -> withAttr (attrName "border" <> attrName "query") (str $ " " ++ intercalate ", " fs)
            cur = str $ case listSelected _rssList of
                         Nothing -> "-"
                         Just i -> show (i + 1)
            total = str $ show $ length nonblanks
            nonblanks = V.takeWhile (not . T.null . rsItemDate) $ listElements $ _rssList

            -- query = query_ $ reportopts_ $ cliopts_ opts

        bottomlabel = case mode of
                        Minibuffer label ed -> minibuffer label ed
                        _                   -> quickhelp
          where
            quickhelp = borderKeysStr' [
               ("LEFT", str "back")
              -- ,("RIGHT", str "transaction")

              -- tree/list mode - rsForceInclusive may override, but use tree_ to ensure a visible toggle effect
              ,("t", renderToggle (tree_ ropts) "list(-subs)" "tree(+subs)")
              -- ,("t", str "tree(+subs)")
              -- ,("l", str "list(-subs)")

              ,("H", renderToggle (not ishistorical) "historical" "period")
              ,("F", renderToggle1 (isJust . forecast_ . inputopts_ $ copts) "forecast")
              ,("L", renderToggle1 (boolopt "lots" $ rawopts_ copts) "lots")
              -- ,("a", "add")
              -- ,("g", "reload")
              ,("?", str "help")
              -- ,("q", "quit")
              ]


rsDrawItem :: (Int,Int,Int,Int,Int) -> Bool -> RegisterScreenItem -> Widget Name
rsDrawItem (datewidth,descwidth,acctswidth,changewidth,balwidth) selected RegisterScreenItem{..} =
  Widget Greedy Fixed $ do
    render $
      txt (fitText (Just datewidth) (Just datewidth) True True rsItemDate) <+>
      txt " " <+>
      txt (fitText (Just 1) (Just 1) True True (T.pack $ show rsItemStatus)) <+>
      txt " " <+>
      txt (fitText (Just descwidth) (Just descwidth) True True rsItemDescription) <+>
      txt "  " <+>
      txt (fitText (Just acctswidth) (Just acctswidth) True True rsItemOtherAccounts) <+>
      txt "   " <+>
      withAttr changeattr (txt $ fitText (Just changewidth) (Just changewidth) True False changeAmt) <+>
      txt "   " <+>
      withAttr balattr (txt $ fitText (Just balwidth) (Just balwidth) True False balanceAmt)
  where
    changeAmt  = wbToText rsItemChangeAmount
    balanceAmt = wbToText rsItemBalanceAmount
    changeattr | T.any (=='-') changeAmt  = sel $ attrName "list" <> attrName "amount" <> attrName "decrease"
               | otherwise                = sel $ attrName "list" <> attrName "amount" <> attrName "increase"
    balattr    | T.any (=='-') balanceAmt = sel $ attrName "list" <> attrName "balance" <> attrName "negative"
               | otherwise                = sel $ attrName "list" <> attrName "balance" <> attrName "positive"
    sel | selected  = (<> attrName "selected")
        | otherwise = id

-- XXX clean up like asHandle
rsHandle :: RegisterScreenState -> BrickEvent Name AppEvent -> EventM Name UIState ()
rsHandle sst@RSS{..} ev = do
  ui0 <- get'
  dbguiEv "rsHandle"
  case ui0 of
    ui@UIState{
      aopts=UIOpts{uoCliOpts=copts}
      ,ajournal=j
      ,aMode=mode
      } -> do
      d <- liftIO getCurrentDay
      let
        journalspan = journalDateSpan False j
        nonblanks = V.takeWhile (not . T.null . rsItemDate) $ listElements $ _rssList
        lastnonblankidx = max 0 (length nonblanks - 1)
        numberedtxns = zipWith (curry (second rsItemTransaction)) [(1::Integer)..] (V.toList nonblanks)
        -- the transactions being shown and the currently selected or last transaction, if any:
        mtxns :: Maybe ([NumberedTransaction], NumberedTransaction)
        mtxns = case numberedtxns of
          []        -> Nothing
          nts@(_:_) -> Just (nts, maybe (last nts) (bimap ((+1).fromIntegral) rsItemTransaction) $
                              listSelectedElement _rssList)  -- PARTIAL: last won't fail
      case mode of
        Minibuffer _ ed ->
          case ev of
            VtyEvent (EvKey KEsc   []) -> modify' closeMinibuffer
            VtyEvent (EvKey KEnter []) -> put' $ regenerateScreens d $
                case setFilter s $ closeMinibuffer ui of
                  Left bad -> showMinibuffer "Cannot compile regular expression" (Just bad) ui
                  Right ui' -> ui'
              where s = chomp . unlines . map strip $ getEditContents ed
            -- VtyEvent (EvKey (KChar '/') []) -> put' $ regenerateScreens d $ showMinibuffer ui
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
            VtyEvent (EvKey KEsc        []) -> put' $ resetScreens d ui
            VtyEvent (EvKey (KChar c)   []) | c == '?' -> put' $ setMode Help ui

            -- AppEvents arrive in --watch mode, see AccountsScreen
            AppEvent (DateChange old _) | isStandardPeriod p && p `periodContainsDate` old ->
              put' $ regenerateScreens d $ setReportPeriod (DayPeriod d) ui
              where
                p = reportPeriod ui

            e | e `elem` [AppEvent FileChange, VtyEvent (EvKey (KChar 'g') [])] -> uiReload copts d ui >>= put'

            VtyEvent (EvKey (KChar 'I') []) -> uiToggleBalanceAssertions d ui
            VtyEvent (EvKey (KChar 'a') []) -> suspendAndResume $ clearScreen >> setCursorPosition 0 0 >> add (cliOptsDropArgs copts) j >> uiReloadIfFileChanged copts d j ui
            VtyEvent (EvKey (KChar 'A') []) -> suspendAndResume $ void (runIadd (journalFilePath j)) >> uiReloadIfFileChanged copts d j ui
            VtyEvent (EvKey (KChar 'T') []) -> put' $ regenerateScreens d $ setReportPeriod (DayPeriod d) ui
            VtyEvent (EvKey (KChar 'E') []) -> suspendAndResume $ void (runEditor pos f) >> uiReloadIfFileChanged copts d j ui
              where
                (pos,f) = case listSelectedElement _rssList of
                            Nothing -> (endPosition, journalFilePath j)
                            Just (_, RegisterScreenItem{
                              rsItemTransaction=Transaction{tsourcepos=(SourcePos f' l c,_)}}) -> (Just (unPos l, Just $ unPos c),f')

            -- display mode/query toggles
            VtyEvent (EvKey (KChar 'B') []) -> rsCenterSelection (regenerateScreens d $ toggleConversionOp ui) >>= put'
            VtyEvent (EvKey (KChar 'V') []) -> rsCenterSelection (regenerateScreens d $ toggleValue ui) >>= put'
            VtyEvent (EvKey (KChar 'H') []) -> rsCenterSelection (regenerateScreens d $ toggleHistorical ui) >>= put'
            VtyEvent (EvKey (KChar 't') []) -> rsCenterSelection (regenerateScreens d $ toggleTree ui) >>= put'
            VtyEvent (EvKey (KChar c) []) | c `elem` ['z','Z'] -> rsCenterSelection (regenerateScreens d $ toggleEmpty ui) >>= put'
            VtyEvent (EvKey (KChar 'R') []) -> rsCenterSelection (regenerateScreens d $ toggleReal ui) >>= put'
            VtyEvent (EvKey (KChar 'U') []) -> rsCenterSelection (regenerateScreens d $ toggleUnmarked ui) >>= put'
            VtyEvent (EvKey (KChar 'P') []) -> rsCenterSelection (regenerateScreens d $ togglePending ui) >>= put'
            VtyEvent (EvKey (KChar 'C') []) -> rsCenterSelection (regenerateScreens d $ toggleCleared ui) >>= put'
            VtyEvent (EvKey (KChar 'F') []) -> rsCenterSelection (regenerateScreens d $ toggleForecast d ui) >>= put'
            VtyEvent (EvKey (KChar 'L') []) -> rsCenterSelection (regenerateScreens d $ toggleLots ui) >>= put'
            VtyEvent (EvKey (KChar 'J') []) -> do
              let l' = listMoveBy 10 _rssList
              let l'' = if isBlankElement (listSelectedElement l')
                        then listMoveTo lastnonblankidx l'
                        else l'
              put' ui{aScreen=RS sst{_rssList=l''}}

            VtyEvent (EvKey (KChar 'K') []) -> do
              let l' = listMoveBy (-10) _rssList
              put' ui{aScreen=RS sst{_rssList=l'}}
            VtyEvent (EvKey (KChar '/') []) -> put' $ regenerateScreens d $ showMinibuffer "filter" Nothing ui
            VtyEvent (EvKey (KDown)     [MShift]) -> put' $ regenerateScreens d $ shrinkReportPeriod d ui
            VtyEvent (EvKey (KUp)       [MShift]) -> put' $ regenerateScreens d $ growReportPeriod d ui
            VtyEvent (EvKey (KRight)    [MShift]) -> put' $ regenerateScreens d $ nextReportPeriod journalspan ui
            VtyEvent (EvKey (KLeft)     [MShift]) -> put' $ regenerateScreens d $ previousReportPeriod journalspan ui
            VtyEvent (EvKey k           []) | k `elem` [KBS, KDel] -> (put' $ regenerateScreens d $ resetFilter ui)
            VtyEvent (EvKey (KChar 'l') [MCtrl]) -> scrollSelectionToMiddle (rsListSize _rssList) _rssList >> redraw
            VtyEvent (EvKey (KChar 'z') [MCtrl]) -> suspend ui

            -- exit screen on LEFT
            VtyEvent e | e `elem` moveLeftEvents  -> put' $ popScreen ui
            -- or on a click in the app's left margin. This is a VtyEvent since not in a clickable widget.
            VtyEvent (EvMouseUp x _y (Just BLeft)) | x==0 -> put' $ popScreen ui

            -- enter transaction screen on RIGHT
            VtyEvent e | e `elem` moveRightEvents ->
              case mtxns of Nothing -> return (); Just (nts, nt) -> rsEnterTransactionScreen _rssAccount _rssForceInclusive nts nt ui
            -- or on transaction click
            -- MouseDown is sometimes duplicated, https://github.com/jtdaugherty/brick/issues/347
            -- just use it to move the selection
            MouseDown _n BLeft _mods Location{loc=(_x,y)} | not $ (=="") clickeddate -> do
              put' $ ui{aScreen=RS sst{_rssList=listMoveTo y _rssList}}
              where clickeddate = maybe "" rsItemDate $ listElements _rssList !? y
            -- and on MouseUp, enter the subscreen
            MouseUp _n (Just BLeft) Location{loc=(_x,y)} | not $ (=="") clickeddate -> do
              case mtxns of Nothing -> return (); Just (nts, nt) -> rsEnterTransactionScreen _rssAccount _rssForceInclusive nts nt ui
              where clickeddate = maybe "" rsItemDate $ listElements _rssList !? y

            -- when selection is at the last item, do nothing
            VtyEvent e | e `elem` moveDownEvents, isBlankElement mnextelement -> return ()
              where mnextelement = listSelectedElement $ listMoveDown _rssList

            -- mouse scroll wheel scrolls the viewport up or down to its maximum extent,
            -- pushing the selection when necessary.
            MouseDown name btn _mods _loc | btn `elem` [BScrollUp, BScrollDown] -> do
              let scrollamt = if btn==BScrollUp then -1 else 1
              list' <- nestEventM' _rssList $ listScrollPushingSelection name (rsListSize _rssList) scrollamt
              put' ui{aScreen=RS sst{_rssList=list'}}

            -- if page down or end leads to a blank padding item, stop at last non-blank
            VtyEvent e@(EvKey k           []) | k `elem` [KPageDown, KEnd] -> do
              l <- nestEventM' _rssList $ handleListEvent e
              if isBlankElement $ listSelectedElement l
              then do
                let l' = listMoveTo lastnonblankidx l
                scrollSelectionToMiddle (rsListSize l') l'
                put' ui{aScreen=RS sst{_rssList=l'}}
              else
                put' ui{aScreen=RS sst{_rssList=l}}

            -- fall through to the list's event handler (handles other [pg]up/down events)
            VtyEvent e -> do
              let e' = normaliseMovementKeys e
              newitems <- nestEventM' _rssList $ handleListEvent e'
              put' ui{aScreen=RS sst{_rssList=newitems}}

            MouseDown{}       -> return ()
            MouseUp{}         -> return ()
            AppEvent _        -> return ()


isBlankElement mel = ((rsItemDate . snd) <$> mel) == Just ""

rsListSize = V.length . V.takeWhile ((/="").rsItemDate) . listElements

rsSetAccount :: AccountName -> Bool -> Screen -> Screen
rsSetAccount a forceinclusive (RS st@RSS{}) =
  RS st{_rssAccount=replaceHiddenAccountsNameWith "*" a, _rssForceInclusive=forceinclusive}
rsSetAccount _ _ st = st

-- | Scroll the selected item to the middle of the screen, when on the register screen.
-- No effect on other screens.
rsCenterSelection :: UIState -> EventM Name UIState UIState
rsCenterSelection ui@UIState{aScreen=RS sst} = do
  scrollSelectionToMiddle (rsListSize $ _rssList sst) (_rssList sst)
  return ui  -- ui is unchanged, but this makes the function more chainable
rsCenterSelection ui = return ui

rsEnterTransactionScreen :: AccountName -> Bool -> [NumberedTransaction] -> NumberedTransaction -> UIState -> EventM Name UIState ()
rsEnterTransactionScreen acct forceinclusive nts nt ui = do
  dbguiEv "rsEnterTransactionScreen"
  put' $ pushScreen (tsNew acct forceinclusive nts nt) ui
