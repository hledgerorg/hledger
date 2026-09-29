{- |
Overview:
hledger-ui's UIState holds the currently active screen and any previously visited
screens (and their states).
The brick App delegates all event-handling and rendering
to the UIState's active screen.
Screens have their own screen state, render function, event handler, and app state
update function, so they have full control.

@
Brick.defaultMain brickapp st
  where
    brickapp :: App (UIState) V.Event
    brickapp = App {
        appLiftVtyEvent = id
      , appStartEvent   = return
      , appAttrMap      = const theme
      , appChooseCursor = showFirstCursor
      , appHandleEvent  = \st ev -> sHandle (aScreen st) st ev
      , appDraw         = \st    -> sDraw   (aScreen st) st
      }
    st :: UIState
    st = (sInit s) d
         UIState{
            aopts=uopts'
           ,ajournal=j
           ,aScreen=s
           ,aPrevScreens=prevscrs
           ,aMinibuffer=Nothing
           }
@
-}

{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE FlexibleInstances  #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE TemplateHaskell    #-}
{-# LANGUAGE EmptyDataDeriving #-}
-- StrictData makes all screen-state and item record fields strict by default, so a future
-- field that captures prior-generation data cannot silently be lazy and reintroduce the
-- --watch reload leak (#1825). Note: this does not reach brick's GenericList.listSelected,
-- so the explicit index forcing in UIScreens/UIState is still required.
{-# LANGUAGE StrictData #-}

module Hledger.UI.UITypes where

-- import Control.Concurrent (threadDelay)
-- import GHC.IO (unsafePerformIO)
import Data.Text (Text)
import Data.Time.Calendar (Day)
import Brick.Widgets.List (List)
import Brick.Widgets.Edit (Editor)
import Lens.Micro.Platform (makeLenses)
import Text.Show.Functions ()
  -- import the Show instance for functions. Warning, this also re-exports it

import Hledger
import Hledger.Cli (HasCliOpts(..))
import Hledger.UI.UIOptions

data AppEvent =
    FileChange          -- one of the Journal's files has been added/modified/removed
  | DateChange Day Day  -- the current date has changed since last checked (with the old and new values)
  deriving (Eq, Show)

-- | hledger-ui's application state. This holds one or more stateful screens.
-- As you navigate through screens, the old ones are saved in a stack.
-- The app can be in one of several modes: normal screen operation,
-- showing a help dialog, entering data in the minibuffer etc.
data UIState = UIState {
    -- unchanging:
   astartupopts  :: UIOpts    -- ^ the command-line options and query arguments specified at program start
    -- can change while program runs:
  ,aopts         :: UIOpts    -- ^ the command-line options and query arguments currently in effect
  ,ajournal      :: Journal   -- ^ the journal being viewed (can change with --watch).
                              --   This is auncollapsedjournal collapsed for display, unless the lots toggle (--lots) is on.
  ,auncollapsedjournal :: Journal  -- ^ the journal as loaded, retaining full lot detail (lot subaccounts and
                                   --   synthetic lot postings). Kept so the lots toggle can re-derive ajournal in memory.
  -- aScreen together with aPrevScreens forms a non-empty navigation zipper: there is
  -- always an active screen, with zero or more suspended ancestor screens behind it.
  -- "At least one screen" is thus guaranteed by the types, and popScreen at the root is
  -- a no-op. aPrevScreens is kept nearest-first, so pushScreen/popScreen are O(1). Change
  -- the stack only through pushScreen/popScreen/resetScreens, not by editing these fields.
  --
  -- Both fields are kept lazy (~) under StrictData: a screen's construction may read back
  -- from the UIState that will contain it (eg --register startup derives a screen parameter
  -- from the ui's options), and forcing them at construction would turn that benign laziness
  -- knot into a <<loop>> (#1825). Reload regeneration forces screens explicitly
  -- (regenerateScreens), so this does not weaken the leak fix.
  ,aScreen      :: ~Screen   -- ^ the currently active screen (the zipper's focus)
  ,aPrevScreens :: ~[Screen] -- ^ suspended ancestor screens, nearest first
  ,aMode         :: Mode      -- ^ the currently active mode on the current screen
  ,aWarnings     :: [String]  -- ^ warnings collected during the last journal (re)load, oldest first;
                              --   displayed until the next keypress (see warningOverlay)
  } deriving (Show)

-- | Any screen can be in one of several modes, which modifies 
-- its rendering and event handling.
-- The mode resets to Normal when entering a new screen.
data Mode =
    Normal
  | Help
  | Minibuffer Text (Editor String Name)
  deriving (Show,Eq)

-- Ignore the editor when comparing Modes.
instance Eq (Editor l n) where _ == _ = True

-- Unique names required for brick widgets, viewports, cursor locations etc.
data Name =
    HelpDialog
  | MinibufferEditor
  | MenuList
  | AccountsViewport
  | AccountsList
  | RegisterViewport
  | RegisterList
  | TransactionEditor
  deriving (Ord, Show, Eq)

-- The kinds of accounts-like screen, selecting which accounts and balances it shows.
-- Also used as the menu's screen names, since these are the screens reachable from the menu.
data AccountsScreenKind =
    AllAccounts
  | CashAccounts
  | BalancesheetAccounts
  | IncomestatementAccounts
  deriving (Ord, Show, Eq)

----------------------------------------------------------------------------------------------------
-- | hledger-ui screen types, v1, "one screen = one module"
-- These types aimed for maximum decoupling of modules and ease of adding more screens.
-- A new screen requires
-- 1. a new constructor in the Screen type, 
-- 2. a new module implementing init/draw/handle functions, 
-- 3. a call from any other screen which enters it.
-- Each screen type has generically named initialisation, draw, and event handling functions,
-- and zero or more uniquely named screen state fields, which hold the data for a particular
-- instance of this screen. Note the latter create partial functions, which means that some invalid
-- cases need to be handled, and also that their lenses are traversals, not single-value getters.
-- data Screen =
--     AccountsScreen {
--        sInit   :: Day -> Bool -> UIState -> UIState              -- ^ function to initialise or update this screen's state
--       ,sDraw   :: UIState -> [Widget Name]                             -- ^ brick renderer for this screen
--       ,sHandle :: BrickEvent Name AppEvent -> EventM Name UIState ()  -- ^ brick event handler for this screen
--       -- state fields.These ones have lenses:
--       ,_asList            :: List Name AccountsScreenItem  -- ^ list widget showing account names & balances
--       ,_asSelectedAccount :: AccountName              -- ^ a backup of the account name from the list widget's selected item (or "")
--     }
--   | RegisterScreen {
--        sInit   :: Day -> Bool -> UIState -> UIState
--       ,sDraw   :: UIState -> [Widget Name]
--       ,sHandle :: BrickEvent Name AppEvent -> EventM Name UIState ()
--       --
--       ,rsList    :: List Name RegisterScreenItem      -- ^ list widget showing transactions affecting this account
--       ,rsAccount :: AccountName                       -- ^ the account this register is for
--       ,rsForceInclusive :: Bool                       -- ^ should this register always include subaccount transactions,
--                                                       --   even when in flat mode ? (ie because entered from a
--                                                       --   depth-clipped accounts screen item)
--     }
--   | TransactionScreen {
--        sInit   :: Day -> Bool -> UIState -> UIState
--       ,sDraw   :: UIState -> [Widget Name]
--       ,sHandle :: BrickEvent Name AppEvent -> EventM Name UIState ()
--       --
--       ,tsTransaction  :: NumberedTransaction          -- ^ the transaction we are currently viewing, and its position in the list
--       ,tsTransactions :: [NumberedTransaction]        -- ^ list of transactions we can step through
--       ,tsAccount      :: AccountName                  -- ^ the account whose register we entered this screen from
--     }
--   | ErrorScreen {
--        sInit   :: Day -> Bool -> UIState -> UIState
--       ,sDraw   :: UIState -> [Widget Name]
--       ,sHandle :: BrickEvent Name AppEvent -> EventM Name UIState ()
--       --
--       ,esError :: String                              -- ^ error message to show
--     }
--   deriving (Show)

----------------------------------------------------------------------------------------------------
-- | hledger-ui screen types, v2, "more parts, but simpler parts"
-- These types aim to be more restrictive, allowing fewer invalid states, and easier to inspect
-- and debug. The screen types store only state, not behaviour (functions), and there is no longer
-- a circular dependency between UIState and Screen.
-- A new screen requires
-- 1. a new constructor in the Screen type
-- 2. a new screen state type if needed
-- 3. new cases in the uiDraw and uiHandle functions
-- 4. new constructor and updater functions in UIScreens, and a new case in screenUpdate
-- 5. a new module implementing draw and event-handling functions
-- 6. a call from any other screen which enters it (eg the menu screen, a new case in msEnterScreen)
-- 7. if it appears on the main menu: a new menu item in msNew

-- cf https://github.com/jtdaugherty/brick/issues/379#issuecomment-1192000374
-- | The various screens which a user can navigate to in hledger-ui,
-- along with any screen-specific parameters or data influencing what they display.
-- (The separate state types add code noise but seem to reduce partial code/invalid data a bit.)
data Screen =
    MS MenuScreenState
  | AS AccountsScreenState  -- ^ the all-accounts, cash, balance sheet and income statement screens; see _assKind
  | RS RegisterScreenState
  | TS TransactionScreenState
  | ES ErrorScreenState
  deriving (Show)

data MenuScreenState = MSS {
    -- view data:
   _mssList            :: List Name MenuScreenItem  -- ^ list widget showing screen names
  ,_mssUnused          :: ()                        -- ^ dummy field to silence warning
} deriving (Show)

-- Used for the all-accounts, cash, balance sheet and income statement screens,
-- which differ only in which accounts and balances they show (selected by _assKind).
data AccountsScreenState = ASS {
    -- screen parameters:
   _assKind            :: AccountsScreenKind                    -- ^ which accounts-like screen this is
  ,_assSelectedAccount :: AccountName                   -- ^ a copy of the account name from the list's selected item (or "")
    -- view data derived from options, reporting date, journal, and screen parameters:
  ,_assList            :: List Name AccountsScreenItem  -- ^ list widget showing account names & balances
} deriving (Show)

data RegisterScreenState = RSS {
    -- screen parameters:
   _rssAccount        :: AccountName                    -- ^ the account this register is for
  ,_rssForceInclusive :: Bool                           -- ^ should this register always include subaccount transactions,
                                                        --   even when in flat mode ? (ie because entered from a
                                                        --   depth-clipped accounts screen item)
    -- view data derived from options, reporting date, journal, and screen parameters:
  ,_rssList           :: List Name RegisterScreenItem   -- ^ list widget showing transactions affecting this account
} deriving (Show)

data TransactionScreenState = TSS {
    -- screen parameters:
   _tssAccount        :: AccountName                -- ^ the account whose register we entered this screen from
  ,_tssForceInclusive :: Bool                       -- ^ whether the parent register included subaccounts
  ,_tssTransactions   :: [NumberedTransaction]      -- ^ the transactions in that register, which we can step through
  ,_tssTransaction    :: NumberedTransaction        -- ^ the currently displayed transaction, and its position in the list
} deriving (Show)

data ErrorScreenState = ESS {
    -- screen parameters:
   _essError :: String                              -- ^ error message to show
  ,_essUnused :: ()                                 -- ^ dummy field to silence warning
} deriving (Show)

-- | An item in the menu screen's list of screens.
data MenuScreenItem = MenuScreenItem {
   msItemScreenName :: Text                         -- ^ screen display name
  ,msItemScreen     :: AccountsScreenKind                   -- ^ an internal name we can use to find the corresponding screen
  } deriving (Show)

-- | An item in the accounts screen's list of accounts and balances.
data AccountsScreenItem = AccountsScreenItem {
   asItemIndentLevel        :: Int                -- ^ indent level
  ,asItemAccountName        :: AccountName        -- ^ full account name
  ,asItemDisplayAccountName :: AccountName        -- ^ full or short account name to display
  ,asItemMixedAmount        :: Maybe MixedAmount  -- ^ mixed amount to display
  } deriving (Show)

-- | An item in the register screen's list of transactions in the current account.
data RegisterScreenItem = RegisterScreenItem {
   rsItemDate           :: Text         -- ^ date
  ,rsItemStatus         :: Status       -- ^ transaction status
  ,rsItemDescription    :: Text         -- ^ description
  ,rsItemOtherAccounts  :: Text         -- ^ other accounts
  ,rsItemChangeAmount   :: WideBuilder  -- ^ the change to the current account from this transaction
  ,rsItemBalanceAmount  :: WideBuilder  -- ^ the balance or running total after this transaction
  ,rsItemTransaction    :: Transaction  -- ^ the full transaction
  }
  deriving (Show)

type NumberedTransaction = (Integer, Transaction)

-- These TH calls must come after most of the types above.
-- Fields named _foo produce lenses named foo.
-- XXX foo fields producing fooL lenses would be preferable
makeLenses ''MenuScreenState
makeLenses ''AccountsScreenState
makeLenses ''RegisterScreenState
makeLenses ''TransactionScreenState
makeLenses ''ErrorScreenState

----------------------------------------------------------------------------------------------------


-- dummy monoid instance needed make lenses work with List fields not common across constructors
--instance Monoid (List n a)
--  where
--    mempty        = list "" V.empty 1  -- XXX problem in 0.7, every list requires a unique Name
--    mappend l1 l = l1 & listElementsL .~ (l1^.listElementsL <> l^.listElementsL)

uioptslens f ui = (\x -> ui{aopts=x}) <$> f (aopts ui)

instance HasCliOpts UIState where
    cliOpts = uioptslens.cliOpts

instance HasInputOpts UIState where
    inputOpts = uioptslens.inputOpts

instance HasBalancingOpts UIState where
    balancingOpts = uioptslens.balancingOpts

instance HasReportSpec UIState where
    reportSpec = uioptslens.reportSpec

instance HasReportOptsNoUpdate UIState where
    reportOptsNoUpdate = uioptslens.reportOptsNoUpdate

instance HasReportOpts UIState where
    reportOpts = uioptslens.reportOpts

