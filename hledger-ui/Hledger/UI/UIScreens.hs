-- | Constructors and updaters for all hledger-ui screens.
--
-- Constructors (*New) create and initialise a new screen with valid state,
-- based on the provided options, reporting date, journal, and screen-specific parameters.
--
-- Updaters (*Update) recalculate an existing screen's state, 
-- based on new options, reporting date, journal, and the old screen state.
--
-- These are gathered in this low-level module so that any screen's handler 
-- can create or regenerate all other screens.
-- Drawing and event-handling code is elsewhere, in per-screen modules.

{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NamedFieldPuns #-}

module Hledger.UI.UIScreens
(screenUpdate
,esNew
,esUpdate
,msNew
,msUpdate
,asNew
,asUpdate
,asItemIndex
,csItemIndex
,bsItemIndex
,isItemIndex
,accountsScreenRoptsMod
,accountsScreenQuery
,rsNew
,rsUpdate
,tsNew
,tsUpdate
,listMoveToIfDisplayItems
,uiDisplayAccount
)
where

import Brick.Widgets.List (listMoveTo, listSelectedElement, list, listSelectedL, GenericList)
import Data.List
import Data.Maybe
import Data.Text qualified as T
import Data.Time.Calendar (Day, diffDays)
import Lens.Micro (over)
import Safe
import Data.Vector qualified as V

import Hledger.Utils.I18n (i18n)
import Hledger.Cli hiding (mode, progname,prognameandversion)
import Hledger.UI.UIOptions
import Hledger.UI.UITypes
import Hledger.UI.UIUtils
import Data.Function ((&))


-- | Regenerate the content of any screen from new options, reporting date and journal.
screenUpdate :: UIOpts -> Day -> Journal -> Screen -> Screen
screenUpdate opts d j = \case
  -- Force each regenerated screen state to WHNF so the strict selection-index
  -- binding in each updater fires, severing references to the previous generation (#1825).
  MS sst -> MS $! msUpdate sst  -- opts d j ass
  AS sst -> AS $! asUpdate opts d j sst
  RS sst -> RS $! rsUpdate opts d j sst
  TS sst -> TS $! tsUpdate opts d j sst
  ES sst -> ES $  esUpdate sst

-- | Construct an error screen.
-- Screen-specific arguments: the error message to show.
esNew :: String -> Screen
esNew msg =
  dbgui "esNew" $
  ES ESS {
    _essError = msg
    ,_essUnused = ()
    }

-- | Update an error screen. Currently a no-op since error screen
-- depends only on its screen-specific state.
esUpdate :: ErrorScreenState -> ErrorScreenState
esUpdate = dbgui "esUpdate`"

-- | Construct a menu screen, with the first item selected.
-- Screen-specific arguments: none.
msNew :: Screen
msNew =
  dbgui "msNew" $
  MS MSS { _mssList = list MenuList (V.fromList items ) 1, _mssUnused = () }
  where
    -- keep synced with: indexes below, initial screen stack setup in UI.Main
    -- TRANSLATORS: the menu screen's entries; translated when drawn.
    items = [
       MenuScreenItem (i18n "Cash accounts") CashAccounts
      ,MenuScreenItem (i18n "Balance sheet accounts") BalancesheetAccounts
      ,MenuScreenItem (i18n "Income statement accounts") IncomestatementAccounts
      ,MenuScreenItem (i18n "All accounts") AllAccounts
      ]

-- keep synced with items above.
-- | Positions of menu screen items, so we can move selection to them.
[
  csItemIndex,
  bsItemIndex,
  isItemIndex,
  asItemIndex
  ] = [0..3] :: [Int]

-- | Update a menu screen. Currently a no-op since menu screen
-- has unchanging content.
msUpdate :: MenuScreenState -> MenuScreenState
msUpdate = dbgui "msUpdate"

nullass kind macct = ASS {
   _assKind            = kind
  ,_assSelectedAccount = fromMaybe "" macct
  ,_assList            = list AccountsList (V.fromList []) 1
  }

-- | Construct an accounts-like screen (all accounts, cash, balance sheet or income
-- statement, selected by the AccountsScreenKind), listing the appropriate set of accounts,
-- with the appropriate one selected.
-- Screen-specific arguments: the kind of screen, and the account to select if any.
asNew :: AccountsScreenKind -> UIOpts -> Day -> Journal -> Maybe AccountName -> Screen
asNew kind uopts d j macct = dbgui "asNew" $ AS $ asUpdate uopts d j $ nullass kind macct

-- | Update an accounts-like screen's state from these options, reporting date, and journal.
-- The report is restricted and accumulated according to the screen's kind (_assKind).
asUpdate :: UIOpts -> Day -> Journal -> AccountsScreenState -> AccountsScreenState
asUpdate uopts d j ass = dbgui "asUpdate" $
  asUpdateHelper rspec d copts (accountsScreenRoptsMod kind) (accountsScreenQuery kind) j ass
  where
    UIOpts{uoCliOpts=copts@CliOpts{reportspec_=rspec}} = uopts
    kind = _assKind ass

-- | The report-options modifier for an accounts-like screen of the given kind:
-- which balance accumulation it forces, if any.
accountsScreenRoptsMod :: AccountsScreenKind -> ReportOpts -> ReportOpts
accountsScreenRoptsMod kind ropts = case kind of
  AllAccounts             -> ropts
  CashAccounts            -> ropts{balanceaccum_=Historical}  -- always show historical end balances
  BalancesheetAccounts    -> ropts{balanceaccum_=Historical}  -- always show historical end balances
  IncomestatementAccounts -> ropts{balanceaccum_=PerPeriod}   -- always show period changes

-- | The extra query restricting an accounts-like screen of the given kind to its account types.
accountsScreenQuery :: AccountsScreenKind -> Query
accountsScreenQuery kind = case kind of
  AllAccounts             -> Any
  CashAccounts            -> Type [Cash]
  BalancesheetAccounts    -> Type [Asset,Liability,Equity]
  IncomestatementAccounts -> Type [Revenue,Expense]

-- | Update an accounts-like screen's state from this report spec, reporting date,
-- cli options, report options modifier, extra query, and journal.
asUpdateHelper :: ReportSpec -> Day -> CliOpts -> (ReportOpts -> ReportOpts) -> Query -> Journal -> AccountsScreenState -> AccountsScreenState
asUpdateHelper rspec0 d copts roptsModify extraquery j ass = dbgui "asUpdateHelper" $
  -- Force the new list, which forces the bang-patterned selidx below, severing the
  -- reference to the previous generation's state (ass) so it can be GC'd (#1825).
  l `seq` ass{_assList=l}
  where
    ropts = roptsModify $ _rsReportOpts rspec0
    rspec =
      updateReportSpec
        ropts
        rspec0{_rsDay=d}  -- update to the current date, might have changed since program start
      & either (error' "asUpdateHelper: adjusting the query, should not have failed") id -- PARTIAL:
      & reportSpecSetFutureAndForecast (forecast_ $ inputopts_ copts)  -- include/exclude future & forecast transactions
      & reportSpecAddQuery extraquery  -- add any extra restrictions

    l = listMoveToIfDisplayItems selidx displayitems $ list AccountsList (V.fromList $ displayitems ++ blankitems) 1
      where
        -- which account should be selected ?
        -- Strict: forced via `l `seq`` above, so the new list holds no thunk over ass (#1825).
        !selidx = headDef 0 $ catMaybes [
           elemIndex a as                               -- the one previously selected, if it can be found
          ,findIndex (a `isAccountNamePrefixOf`) as     -- or the first account found with the same prefix
          ,Just $ max 0 (length (filter (< a) as) - 1)  -- otherwise, the alphabetically preceding account.
          ]
          where
            a = _assSelectedAccount ass
            as = map asItemAccountName displayitems

        displayitems = map displayitem items
          where
            -- run the report
            (items, _) = styleAmounts styles $ balanceReport rspec j
              where
                styles = journalCommodityStylesWith HardRounding j

            -- pre-render a list item
            displayitem (fullacct, shortacct, indent, bal) =
              AccountsScreenItem{asItemIndentLevel        = indent
                                ,asItemAccountName        = fullacct
                                ,asItemDisplayAccountName = replaceHiddenAccountsNameWith "All" $ if tree_ ropts then shortacct else fullacct
                                ,asItemMixedAmount        = Just bal
                                }

        -- blanks added for scrolling control, cf RegisterScreen.
        blankitems = replicate uiNumBlankItems  -- XXX ugly hard-coded value. When debugging, changing to 0 reduces noise.
          AccountsScreenItem{asItemIndentLevel        = 0
                            ,asItemAccountName        = ""
                            ,asItemDisplayAccountName = ""
                            ,asItemMixedAmount        = Nothing
                            }

-- | Construct a register screen listing the appropriate set of transactions,
-- with the appropriate one selected.
-- Screen-specific arguments: the account whose register this is,
-- whether to force inclusive balances.
rsNew :: UIOpts -> Day -> Journal -> AccountName -> Bool -> Screen
rsNew uopts d j acct forceinclusive =  -- XXX forcedefaultselection - whether to force selecting the last transaction.
  dbgui "rsNew" $
  RS $
  rsUpdate uopts d j $
  RSS {
     _rssAccount        = replaceHiddenAccountsNameWith "*" acct
    ,_rssForceInclusive = forceinclusive
    ,_rssList           = list RegisterList (V.fromList []) 1
    }

-- | Update a register screen from these options, reporting date, and journal.
rsUpdate :: UIOpts -> Day -> Journal -> RegisterScreenState -> RegisterScreenState
rsUpdate uopts d j rss@RSS{_rssAccount, _rssForceInclusive, _rssList=oldlist} =
  dbgui "rsUpdate" $
  -- Force the new list, which forces the bang-patterned newselidx below, severing the
  -- reference to the previous generation's list (oldlist) so it can be GC'd (#1825).
  l' `seq` rss{_rssList=l'}
  where
    -- the rendered register items (one per transaction); shared with the transaction screen
    displayitems = registerScreenDisplayItems uopts d j _rssAccount _rssForceInclusive

    -- blank items are added to allow more control of scroll position; we won't allow movement over these.
    -- XXX Ugly. Changing to 0 helps when debugging.
    blankitems = replicate uiNumBlankItems
          RegisterScreenItem{rsItemDate          = ""
                            ,rsItemStatus        = Unmarked
                            ,rsItemDescription   = ""
                            ,rsItemOtherAccounts = ""
                            ,rsItemChangeAmount  = mempty
                            ,rsItemBalanceAmount = mempty
                            ,rsItemTransaction   = nulltransaction
                            }

    -- build the new list widget
    l = list RegisterList (V.fromList $ displayitems ++ blankitems) 1

    -- ensure the appropriate list item is selected:
    -- if forcedefaultselection is true, the last (latest) transaction;  XXX still needed ?
    -- otherwise, the previously selected transaction if possible;
    -- otherwise, the transaction nearest in date to it;
    -- or if there's several with the same date, the nearest in journal order;
    -- otherwise, the last (latest) transaction.
    l' = listMoveToIfDisplayItems newselidx displayitems l
      where
        endidx = max 0 $ length displayitems - 1
        -- Strict: forced via `l' `seq`` above, so the new list holds no thunk over oldlist (#1825).
        !newselidx =
          -- case (forcedefaultselection, listSelectedElement _rssList) of
          --   (True, _)    -> endidx
          --   (_, Nothing) -> endidx
          --   (_, Just (_, RegisterScreenItem{rsItemTransaction=Transaction{tindex=prevselidx, tdate=prevseld}})) ->
          --     headDef endidx $ catMaybes [
          --       findIndex ((==prevselidx) . tindex . rsItemTransaction) displayitems
          --       ,findIndex ((==nearestidbydatethenid) . Just . tindex . rsItemTransaction) displayitems
          --       ]
          --     where
          --       nearestidbydatethenid = third3 <$> (headMay $ sort
          --         [(abs $ diffDays (tdate t) prevseld, abs (tindex t - prevselidx), tindex t) | t <- ts])
          --       ts = map rsItemTransaction displayitems
          case listSelectedElement oldlist of
            Nothing -> endidx
            Just (_, RegisterScreenItem{rsItemTransaction=Transaction{tindex=prevselidx, tdate=prevseld}}) ->
              headDef endidx $ catMaybes [
                findIndex ((==prevselidx) . tindex . rsItemTransaction) displayitems
                ,findIndex ((==nearestidbydatethenid) . Just . tindex . rsItemTransaction) displayitems
                ]
              where
                nearestidbydatethenid = third3 <$> (headMay $ sort
                  [(abs $ diffDays (tdate t) prevseld, abs (tindex t - prevselidx), tindex t) | t <- ts])
                ts = map rsItemTransaction displayitems

-- | The account a register-like screen should display: normally the screen's stored
-- account, but when that is a lot subaccount and lot detail is collapsed (so the
-- account doesn't exist in the display journal), its base account, where the
-- collapsed postings now appear. Keep the collapse condition synced with uiDisplayJournal.
uiDisplayAccount :: UIOpts -> AccountName -> AccountName
uiDisplayAccount uopts a
  | boolopt "lots" ro        = a
  | boolopt "ignore-lots" ro = a
  | otherwise                = lotBaseAccount a
  where ro = rawopts_ $ uoCliOpts uopts

-- | The rendered register items (one per transaction) for an account's register,
-- from these options, reporting date, journal, account name, and whether to include
-- subaccount transactions. Shared by the register screen and the transaction screen
-- so they show the same set of transactions.
-- The account is remapped with uiDisplayAccount, so a lot subaccount's register
-- shows its base account's transactions while lot detail is collapsed.
registerScreenDisplayItems :: UIOpts -> Day -> Journal -> AccountName -> Bool -> [RegisterScreenItem]
registerScreenDisplayItems uopts d j acct0 forceinclusive = map displayitem items'
  where
    acct = uiDisplayAccount uopts acct0
    UIOpts{uoCliOpts=copts@CliOpts{reportspec_=rspec@ReportSpec{_rsReportOpts=ropts}}} = uopts
    inclusive = tree_ ropts || forceinclusive
    thisacctq = Acct $ mkregex acct
      where
        mkregex = if inclusive then accountNameToAccountRegex else accountNameToAccountOnlyRegex

    -- adjust the report options and report spec, carefully as usual to avoid screwups (#1523)
    ropts' = ropts {
        -- ignore any depth limit, as in postingsReport; allows register's total to match accounts screen
        depth_=mempty
        -- do not strip prices so we can toggle costs within the ui
      , show_costs_=True
      }
    rspec' =
      updateReportSpec ropts' rspec{_rsDay=d}
      & either (error' "registerScreenDisplayItems: adjusting the query for register, should not have failed") id -- PARTIAL:
      & reportSpecSetFutureAndForecast (forecast_ $ inputopts_ copts)

    -- gather transactions to display
    items = styleAmounts styles $ accountTransactionsReport rspec' j thisacctq
              where
                styles = journalCommodityStylesWith HardRounding j
    items' =
      (if empty_ ropts then id else filter (not . mixedAmountLooksZero . fifth6)) $  -- without --empty, exclude no-change txns
      reverse  -- most recent last
      items

    displayitem (t, _, _issplit, otheraccts, change, bal) =
      RegisterScreenItem{rsItemDate          = showDate $ transactionRegisterDate wd (_rsQuery rspec') thisacctq t
                        ,rsItemStatus        = tstatus t
                        ,rsItemDescription   = tdescription t
                        ,rsItemOtherAccounts = T.intercalate ", " . map accountSummarisedName $ nub otheraccts
                                                -- _   -> "<split>"  -- should do this if accounts field width < 30
                        ,rsItemChangeAmount  = showamt change
                        ,rsItemBalanceAmount = showamt bal
                        ,rsItemTransaction   = t
                        }
      where
        showamt = showMixedAmountB oneLineNoCostFmt{displayMaxWidth=Just 3}
        wd = whichDate ropts'

-- | Construct a transaction screen showing one of a given list of transactions,
-- with the ability to step back and forth through the list.
-- Screen-specific arguments: the account whose transactions are being shown,
-- whether that register included subaccounts, the list of showable transactions,
-- the currently shown transaction.
tsNew :: AccountName -> Bool -> [NumberedTransaction] -> NumberedTransaction -> Screen
tsNew acct forceinclusive nts nt =
  dbgui "tsNew" $
  TS TSS{
     _tssAccount        = acct
    ,_tssForceInclusive = forceinclusive
    ,_tssTransactions   = nts
    ,_tssTransaction    = nt
    }

-- | Update a transaction screen: rebuild its transaction list from the (possibly reloaded)
-- journal, and reselect the same transaction by its journal index, so the screen refreshes
-- in place on reload. If that transaction is gone, fall back to the one at the same position,
-- else the last, else a blank.
tsUpdate :: UIOpts -> Day -> Journal -> TransactionScreenState -> TransactionScreenState
tsUpdate uopts d j tss@TSS{_tssAccount, _tssForceInclusive, _tssTransaction=(oldpos, oldtxn)} =
  dbgui "tsUpdate" $
  length nts `seq` selected `seq`
  tss{_tssTransactions=nts, _tssTransaction=selected}
  where
    displayitems = registerScreenDisplayItems uopts d j _tssAccount _tssForceInclusive
    numberedtxns = zipWith (\i item -> (i, rsItemTransaction item)) [(1::Integer)..] displayitems
    (nts, selected)
      -- the same transaction is still in this account's register: keep it selected
      | Just sel <- find ((== tindex oldtxn) . tindex . snd) numberedtxns = (numberedtxns, sel)
      -- the register is now empty, eg because this screen's account was a lot subaccount
      -- and lot display was just toggled off: if the entry still exists in the journal,
      -- keep showing it (in its current form); otherwise show a blank transaction
      | null numberedtxns = case journalTransactionAt j (tindex oldtxn) of
          Just t  -> ([(1, t)], (1, t))
          Nothing -> ([], (0, nulltransaction))
      -- the transaction is gone but the register is not empty, eg after a file change:
      -- fall back to the transaction at the same position, or the last one
      | otherwise = (numberedtxns, fromMaybe (last numberedtxns) $ (\t -> (oldpos, t)) <$> lookup oldpos numberedtxns)

-- | Set selected index of a list if there are displayitems.
-- If there are no displayitems, remove the selected index of the list.
listMoveToIfDisplayItems :: Int -> [item] -> GenericList Name V.Vector item -> GenericList Name V.Vector item
listMoveToIfDisplayItems idx displayItems =
    if null displayItems
        then over listSelectedL $ const Nothing
        else listMoveTo idx
