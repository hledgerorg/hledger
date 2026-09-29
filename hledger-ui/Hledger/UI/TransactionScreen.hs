-- The transaction screen, showing a single transaction's general journal entry.

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TupleSections     #-}
{-# OPTIONS_GHC -Wno-incomplete-record-updates #-}

module Hledger.UI.TransactionScreen
(tsNew
,tsUpdate
,tsDraw
,tsHandle
) where

import Brick
import Brick.Widgets.Edit (editorText, renderEditor)
import Brick.Widgets.List (listElements)
import Control.Monad.IO.Class (liftIO)
import Data.List
import Data.Maybe
import Data.Text qualified as T
import Data.Vector qualified as V
import Graphics.Vty (Event(..),Key(..),Modifier(..), Button (BLeft))
import System.Exit (ExitCode (..))

import Hledger
import Hledger.Cli hiding (mode, prices, progname,prognameandversion)
import Hledger.UI.UIOptions
import Hledger.UI.UITypes
import Hledger.UI.UIState
import Hledger.UI.UIUtils
import Hledger.UI.UIScreens
import Hledger.UI.Editor
import Hledger.UI.ErrorScreen (uiReload, uiReloadIfFileChanged, uiToggleBalanceAssertions)

tsDraw :: TransactionScreenState -> UIState -> [Widget Name]
tsDraw TSS{_tssTransaction=(i,t')
          ,_tssTransactions=nts
          ,_tssAccount=acct
          }
       UIState{aopts=uopts@UIOpts{uoCliOpts=copts@CliOpts{reportspec_=rspec@ReportSpec{_rsReportOpts=ropts}}}
              ,ajournal=j
              ,aMode=mode
              } =
  case mode of
    Help       -> [helpDialog, maincontent]
    _          -> [maincontent]
  where
    maincontent = Widget Greedy Greedy $ render $ defaultLayout toplabel bottomlabel txneditor
      where
        -- The stored transaction, coming from accountTransactionsReport, may have had
        -- amounts excluded by a cur:/amt: query, or valued. This screen should always
        -- show the whole journal entry as written (with any valuation applied by showTxn
        -- below), so look up the original transaction in the journal by its index.
        torig = fromMaybe t' $ journalTransactionAt j (tindex t')
        -- as with print, show amounts with all of their decimal places
        t = transactionMapPostingAmounts mixedAmountSetFullPrecision torig

        -- XXX would like to shrink the editor to the size of the entry,
        -- so handler can more easily detect clicks below it
        txneditor =
          renderEditor (vBox . map txt) False $
          editorText TransactionEditor Nothing $
          showTxn ropts rspec j t

        toplabel =
          str "Transaction "
          -- <+> withAttr ("border" <> "bold") (str $ "#" ++ show (tindex t))
          -- <+> str (" ("++show i++" of "++show (length nts)++" in "++acct++")")
          <+> (str $ "#" ++ show (tindex t))
          <+> str " ("
          <+> withAttr (attrName "border" <> attrName "bold") (str $ show i)
          <+> str (" of "++show (length nts))
          <+> togglefilters
          <+> borderQueryStr (unwords . map (quoteIfNeeded . T.unpack) $ querystring_ ropts)
          <+> str (" in "++T.unpack (replaceHiddenAccountsNameWith "All" $ uiDisplayAccount uopts acct)++")")
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

        bottomlabel = quickhelp
                        -- case mode of
                        -- Minibuffer ed -> minibuffer ed
                        -- _             -> quickhelp
          where
            quickhelp = borderKeysStr [
               ("LEFT", "back")
              ,("UP/DOWN", "prev/next txn")
              --,("ESC", "cancel/top")
              -- ,("a", "add")
              ,("E", "edit")
              ,("g", "reload")
              ,("?", "help")
              -- ,("q", "quit")
              ]


-- Render a transaction suitably for the transaction screen.
showTxn :: ReportOpts -> ReportSpec -> Journal -> Transaction -> T.Text
showTxn ropts rspec j t =
      showTransactionOneLineAmounts
    $ maybe id (transactionApplyValuation prices styles periodlast (_rsDay rspec)) (value_ ropts)
    $ maybe id transactionToCost (conversionop_ ropts) t
    -- (if real_ ropts then filterTransactionPostings (Real True) else id) -- filter postings by --real
  where
    prices = journalPriceOracle (infer_prices_ ropts) j
    styles = journalCommodityStyles j
    periodlast =
      fromMaybe (error' "TransactionScreen: expected a non-empty journal") $  -- PARTIAL: shouldn't happen
      reportPeriodOrJournalLastDay rspec j

tsHandle :: TransactionScreenState -> BrickEvent Name AppEvent -> EventM Name UIState ()
tsHandle TSS{_tssTransaction=(i,t), _tssTransactions=nts} ev = do
  ui0 <- get'
  case ui0 of
    ui@UIState{aopts=UIOpts{uoCliOpts=copts}
              ,ajournal=j
              ,aMode=mode
              } ->
      case mode of
        Help ->
          case ev of
            -- VtyEvent (EvKey (KChar 'q') []) -> halt
            VtyEvent (EvKey (KChar 'l') [MCtrl]) -> redraw
            VtyEvent (EvKey (KChar 'z') [MCtrl]) -> suspend ui
            _ -> helpHandle ev

        _ -> do
          d <- liftIO getCurrentDay
          let
            (iprev,tprev) = maybe (i,t) ((i-1),) $ lookup (i-1) nts
            (inext,tnext) = maybe (i,t) ((i+1),) $ lookup (i+1) nts
          case ev of
            VtyEvent (EvKey (KChar 'q') []) -> halt
            VtyEvent (EvKey KEsc        []) -> put' $ resetScreens d ui
            VtyEvent (EvKey (KChar c)   []) | c == '?' -> put' $ setMode Help ui

            -- g or file change: reload the journal and rebuild app state.
            e | e `elem` [VtyEvent (EvKey (KChar 'g') []), AppEvent FileChange] ->
              tsReload copts d ui

              -- for debugging; leaving these here because they were hard to find
              -- \u -> dbguiEv (pshow u) >> put' u  -- doesn't log
              -- \UIState{aScreen=TS tss} -> error' $ pshow $ _tssTransaction tss

            -- E: run editor, reload the journal.
            VtyEvent (EvKey (KChar 'E') []) -> do
              suspendAndResume' $ do
                let (pos,f) = case tsourcepos t of (SourcePos f' l1 c1,_) -> (Just (unPos l1, Just $ unPos c1),f')
                exitcode <- runEditor pos f
                case exitcode of
                  ExitSuccess   -> return ()
                  ExitFailure c -> error' $ "running the text editor failed with exit code " ++ show c
              tsReloadIfFileChanged copts d j ui

            AppEvent (DateChange old _) | isStandardPeriod p && p `periodContainsDate` old ->
              put' $ regenerateScreens d $ setReportPeriod (DayPeriod d) ui
              where
                p = reportPeriod ui

            VtyEvent (EvKey (KChar 'I') []) -> uiToggleBalanceAssertions d ui

            -- for toggles that may change the current/prev/next transactions,
            -- we must regenerate the transaction list, like the g handler above ? with regenerateTransactions ? TODO WIP
            -- EvKey (KChar 'E') [] -> put' $ regenerateScreens d $ stToggleEmpty ui
            -- EvKey (KChar 'C') [] -> put' $ regenerateScreens d $ stToggleCleared ui
            -- EvKey (KChar 'R') [] -> put' $ regenerateScreens d $ stToggleReal ui
            VtyEvent (EvKey (KChar 'B') []) -> put' . regenerateScreens d $ toggleConversionOp ui
            VtyEvent (EvKey (KChar 'V') []) -> put' . regenerateScreens d $ toggleValue ui
            VtyEvent (EvKey (KChar 'L') []) -> put' . regenerateScreens d $ toggleLots ui

            VtyEvent e | e `elem` moveUpEvents   -> put' $ tsSelect iprev tprev ui
            VtyEvent e | e `elem` moveDownEvents -> put' $ tsSelect inext tnext ui

            -- exit screen on LEFT
            VtyEvent e | e `elem` moveLeftEvents -> put' . popScreen $ tsSelect i t ui  -- Probably not necessary to tsSelect here, but it's safe.
            -- or on a click in the app's left margin.
            VtyEvent (EvMouseUp x _y (Just BLeft)) | x==0 -> put' . popScreen $ tsSelect i t ui

            VtyEvent (EvKey (KChar 'l') [MCtrl]) -> redraw
            VtyEvent (EvKey (KChar 'z') [MCtrl]) -> suspend ui
            _ -> return ()


    where
      -- Reload the journal and regenerate the whole screen stack; tsUpdate now refreshes
      -- this transaction screen in place, so no exit/re-enter dance is needed.
      tsReload copts d ui = uiReload copts d ui >>= put'
      tsReloadIfFileChanged copts d j ui = liftIO (uiReloadIfFileChanged copts d j ui) >>= put'


-- | Select a new transaction and update the previous register screen
tsSelect :: Integer -> Transaction -> UIState -> UIState
tsSelect i t ui@UIState{aScreen=TS sst} = case aPrevScreens ui of
    x:xs -> ui'{aPrevScreens=rsSelect i x : xs}
    []   -> ui'
  where ui' = ui{aScreen=TS sst{_tssTransaction=(i,t)}}
tsSelect _ _ ui = ui

-- | Select the nth item on the register screen; or if it has no real items
-- (eg its account is a lot subaccount and lot display was just toggled off),
-- clear the selection, so no blank item appears selected.
rsSelect :: Integer -> Screen -> Screen
rsSelect i (RS sst@RSS{..}) = RS sst{_rssList=listMoveToIfDisplayItems (fromInteger $ i-1) nonblanks _rssList}
  where nonblanks = V.toList $ V.takeWhile (not . T.null . rsItemDate) $ listElements _rssList
rsSelect _ scr = scr
