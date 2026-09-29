{- | UIState operations. -}

module Hledger.UI.UIState
(uiState
,uiShowStatus
,setFilter
,setMode
,setReportPeriod
,showMinibuffer
,closeMinibuffer
,toggleCleared
,toggleConversionOp
,toggleIgnoreBalanceAssertions
,toggleEmpty
,toggleForecast
,toggleHistorical
,toggleLots
,uiDisplayJournal
,togglePending
,toggleUnmarked
,toggleReal
,toggleTree
,setTree
,setList
,toggleValue
,reportPeriod
,shrinkReportPeriod
,growReportPeriod
,nextReportPeriod
,previousReportPeriod
,resetReportPeriod
,moveReportPeriodToDate
,getDepth
,setDepth
,decDepth
,incDepth
,resetDepth
,popScreen
,pushScreen
,enableForecast
,resetFilter
,resetScreens
,regenerateScreens
)
where

import Brick.Widgets.Edit
import Data.Bifunctor (first)
import Data.Foldable (asum)
import Data.Either (fromRight)
import Data.List ((\\), sort)
import Data.Maybe (fromMaybe)
import Data.Semigroup (Max(..))
import Data.Text qualified as T
import Data.Text.Zipper (gotoEOL)
import Data.Time.Calendar (Day)
import Lens.Micro ((^.), over, set)
import Safe

import Hledger
import Hledger.Cli.CliOptions
import Hledger.UI.UITypes
import Hledger.UI.UIOptions (UIOpts(uoCliOpts))
import Hledger.UI.UIScreens (screenUpdate)
import Hledger.UI.UIUtils (showScreenId, showScreenStack)

-- | Make an initial UI state with the given options, journal,
-- parent screen stack if any, and starting screen.
-- The provided journal should be the uncollapsed journal (with full lot detail);
-- the display journal (ajournal) is derived from it according to the lots toggle.
uiState :: UIOpts -> Journal -> [Screen] -> Screen -> UIState
uiState uopts j prevscrs scr = UIState {
   astartupopts        = uopts
  ,aopts               = uopts
  ,auncollapsedjournal = j
  ,ajournal            = uiDisplayJournal uopts j
  ,aMode               = Normal
  ,aScreen             = scr
  ,aPrevScreens        = prevscrs
  ,aWarnings           = []
  }

-- | Derive the display journal (what screens show) from the uncollapsed journal:
-- collapse lot detail unless the lots toggle (--lots) is on. Mirrors the CLI's
-- maybeCollapseLotDetail, so UI and CLI agree (and --ignore-lots is honored).
uiDisplayJournal :: UIOpts -> Journal -> Journal
uiDisplayJournal uopts
  | boolopt "lots" ro        = id
  | boolopt "ignore-lots" ro = id
  | otherwise                = journalCollapseLotDetail
  where ro = rawopts_ $ uoCliOpts uopts

-- | Toggle display of lot detail (lot subaccounts and synthetic lot postings), like the
-- CLI's --lots flag. This only flips the option; 'regenerateScreens' then re-derives the
-- display journal from the stored uncollapsed journal, in memory, without reloading from disk.
toggleLots :: UIState -> UIState
toggleLots ui = ui{aopts = uopts'}
  where
    copts  = uoCliOpts $ aopts ui
    ro     = rawopts_ copts
    ro'    = (if boolopt "lots" ro then unsetboolopt "lots" else setboolopt "lots") ro
    uopts' = (aopts ui){uoCliOpts = copts{rawopts_ = ro'}}

-- | Toggle between showing only unmarked items or all items.
toggleUnmarked :: UIState -> UIState
toggleUnmarked = over statuses (toggleStatus1 Unmarked)

-- | Toggle between showing only pending items or all items.
togglePending :: UIState -> UIState
togglePending = over statuses (toggleStatus1 Pending)

-- | Toggle between showing only cleared items or all items.
toggleCleared :: UIState -> UIState
toggleCleared = over statuses (toggleStatus1 Cleared)

-- TODO testing different status toggle styles

-- | Generate zero or more indicators of the status filters currently active,
-- which will be shown comma-separated as part of the indicators list.
uiShowStatus :: CliOpts -> [Status] -> [String]
uiShowStatus copts ss =
  case style of
    -- in style 2, instead of "Y, Z" show "not X"
    Just 2 | length ss == numstatuses-1
      -> map (("not "++). showstatus) $ sort $ complement ss  -- should be just one
    _ -> map showstatus $ sort ss
  where
    numstatuses = length [minBound..maxBound::Status]
    style = maybeposintopt "status-toggles" $ rawopts_ copts
    showstatus Cleared  = "cleared"
    showstatus Pending  = "pending"
    showstatus Unmarked = "unmarked"

-- various toggle behaviours:

-- 1 UPC toggles only X/all
toggleStatus1 :: Status -> [Status] -> [Status]
toggleStatus1 s ss = if ss == [s] then [] else [s]

-- 2 UPC cycles X/not-X/all
-- repeatedly pressing X cycles:
-- [] U [u]
-- [u] U [pc]
-- [pc] U []
-- pressing Y after first or second step starts new cycle:
-- [u] P [p]
-- [pc] P [p]
-- toggleStatus s ss
--   | ss == [s]            = complement [s]
--   | ss == complement [s] = []
--   | otherwise            = [s]  -- XXX assume only three values

-- 3 UPC toggles each X
-- toggleStatus3 s ss
--   | s `elem` ss = filter (/= s) ss
--   | otherwise   = simplifyStatuses (s:ss)

-- 4 upc sets X, UPC sets not-X
-- toggleStatus4 s ss
--  | s `elem` ss = filter (/= s) ss
--  | otherwise   = simplifyStatuses (s:ss)

-- 5 upc toggles X, UPC toggles not-X
-- toggleStatus5 s ss
--  | s `elem` ss = filter (/= s) ss
--  | otherwise   = simplifyStatuses (s:ss)

-- | Given a list of unique enum values, list the other possible values of that enum.
complement :: (Bounded a, Enum a, Eq a) => [a] -> [a]
complement = ([minBound..maxBound] \\)

--

-- | Toggle between showing all and showing only nonempty (more precisely, nonzero) items.
toggleEmpty :: UIState -> UIState
toggleEmpty = over empty__ not

-- | Toggle between showing the primary amounts or costs.
toggleConversionOp :: UIState -> UIState
toggleConversionOp ui = (over value valOff) (over conversionop toggleCostMode ui)
  where
    toggleCostMode Nothing                     = Just ToCost
    toggleCostMode (Just NoConversionOp)       = Just ToCost
    toggleCostMode (Just ToCost)               = Just NoConversionOp
    toggleCostMode (Just ToTransactedCost)     = Just NoConversionOp
    valOff _                             = Nothing

-- | Toggle between showing primary amounts or values (using valuation specified at startup, or a default).
toggleValue :: UIState -> UIState
toggleValue ui = (over conversionop costOff) (over value (valuationToggleValue mstartupvaluation0) ui)
  where
    mstartupvaluation0 = value_ $ _rsReportOpts $ reportspec_ $ uoCliOpts $ astartupopts ui
    mdefvaluation = Just (AtEnd Nothing)
    -- valuationToggleValue (maybe startupvaluation) (maybe currentvaluation) = ...
    valuationToggleValue Nothing           Nothing  = mdefvaluation
    valuationToggleValue Nothing           (Just _) = Nothing
    valuationToggleValue mstartupvaluation Nothing  = mstartupvaluation
    valuationToggleValue _                 (Just _) = Nothing
    costOff _ = Just NoConversionOp

-- | Set hierarchic account tree mode.
-- Also sets no_elide, which hledger-ui wants in tree mode only (see uiInitialState).
setTree :: UIState -> UIState
setTree = set no_elide True . set accountlistmode ALTree

-- | Set flat account list mode.
-- Also unsets no_elide, which hledger-ui wants in tree mode only (see uiInitialState).
setList :: UIState -> UIState
setList = set no_elide False . set accountlistmode ALFlat

-- | Toggle between flat and tree mode. If current mode is unspecified/default, assume it's flat.
toggleTree :: UIState -> UIState
toggleTree ui = case ui ^. accountlistmode of
    ALTree -> setList ui
    ALFlat -> setTree ui

-- | Toggle between historical balances and period balances.
toggleHistorical :: UIState -> UIState
toggleHistorical = over balanceaccum toggleBalanceAccum
  where
    toggleBalanceAccum Historical = PerPeriod
    toggleBalanceAccum _          = Historical

-- | Toggle hledger-ui's "forecast/future mode". When this mode is enabled,
-- hledger-shows regular transactions which have future dates, and
-- "forecast" transactions generated by periodic transaction rules
-- (which are usually but not necessarily future-dated).
-- In normal mode, both of these are hidden.
toggleForecast :: Day -> UIState -> UIState
toggleForecast _d ui = set forecast newForecast ui
  where
    newForecast = case ui^.forecast of
      Just _  -> Nothing
      Nothing -> enableForecast (astartupopts ui) (ui^.cliOpts) ^. forecast

-- | Enable forecasting in this CliOpts.
-- If it previously specified a forecast period, or else if the given ui startup options did,
-- preserve that as the forecast period.
enableForecast :: UIOpts -> CliOpts -> CliOpts
enableForecast startopts currentopts = set forecast mforecast currentopts
  where
    mforecast = asum [mcurrentforecastperiod, mstartupforecastperiod, mdefaultforecastperiod]
      where
        mcurrentforecastperiod = currentopts ^. forecast
        mstartupforecastperiod = startopts ^. forecast
        mdefaultforecastperiod = Just nulldatespan

-- | Toggle between showing all and showing only real (non-virtual) items.
toggleReal :: UIState -> UIState
toggleReal = fromRight err . overEither real not  -- PARTIAL:
  where err = error' "toggleReal: updating Real should not result in an error"

-- | Toggle the ignoring of balance assertions.
toggleIgnoreBalanceAssertions :: UIState -> UIState
toggleIgnoreBalanceAssertions = over ignore_assertions not

-- | Step through larger report periods, up to all.
growReportPeriod :: Day -> UIState -> UIState
growReportPeriod _d = updateReportPeriod periodGrow

-- | Step through smaller report periods, down to a day.
shrinkReportPeriod :: Day -> UIState -> UIState
shrinkReportPeriod d = updateReportPeriod (periodShrink d)

-- | Step the report start/end dates to the next period of same duration,
-- remaining inside the given enclosing span.
nextReportPeriod :: DateSpan -> UIState -> UIState
nextReportPeriod enclosingspan = updateReportPeriod (periodNextIn enclosingspan)

-- | Step the report start/end dates to the next period of same duration,
-- remaining inside the given enclosing span.
previousReportPeriod :: DateSpan -> UIState -> UIState
previousReportPeriod enclosingspan = updateReportPeriod (periodPreviousIn enclosingspan)

-- | If a standard report period is set, step it forward/backward if needed so that
-- it encloses the given date.
moveReportPeriodToDate :: Day -> UIState -> UIState
moveReportPeriodToDate d = updateReportPeriod (periodMoveTo d)

-- | Clear any report period limits.
resetReportPeriod :: UIState -> UIState
resetReportPeriod = setReportPeriod PeriodAll

-- | Get the report period.
reportPeriod :: UIState -> Period
reportPeriod = (^.period)

-- | Set the report period.
setReportPeriod :: Period -> UIState -> UIState
setReportPeriod p = updateReportPeriod (const p)

-- | Update report period by a applying a function.
updateReportPeriod :: (Period -> Period) -> UIState -> UIState
updateReportPeriod updatePeriod = fromRight err . overEither period updatePeriod  -- PARTIAL:
  where err = error' "updateReportPeriod: updating period should not result in an error"

-- | Apply a new filter query, or return the failing query.
-- Also re-expands cur: terms against the journal's commodity aliases,
-- so a freshly typed @cur:@ query is alias-aware even when the journal
-- has been reloaded since startup.
setFilter :: String -> UIState -> Either String UIState
setFilter s ui = do
  ui' <- first (const s) $ setEither querystring (words'' queryprefixes $ T.pack s) ui
  let copts  = uoCliOpts (aopts ui')
      rspec  = reportspec_ copts
      rspec' = rspec{_rsQuery = queryExpandCurAliases (ajournal ui') (_rsQuery rspec)}
      opts'  = (aopts ui'){uoCliOpts = copts{reportspec_ = rspec'}}
  Right ui'{aopts = opts'}

-- | Reset some filters & toggles.
resetFilter :: UIState -> UIState
resetFilter = set querystringNoUpdate [] . set realNoUpdate False . set statusesNoUpdate []
            . set empty__ True  -- set period PeriodAll
            . set rsQuery Any . set rsQueryOpts []

-- -- | Reset all options state to exactly what it was at startup
-- -- (preserving any command-line options/arguments).
-- resetOpts :: UIState -> UIState
-- resetOpts ui@UIState{astartupopts} = ui{aopts=astartupopts}

resetDepth :: UIState -> UIState
resetDepth = updateReportDepth (const mempty)

-- | Get the maximum account depth in the current journal.
maxDepth :: UIState -> Int
maxDepth UIState{ajournal=j} = getMax . foldMap (Max . accountNameLevel) $ journalAccountNamesDeclaredOrImplied j

-- | Decrement the current depth limit towards 0. If there was no depth limit,
-- set it to one less than the maximum account depth.
decDepth :: UIState -> UIState
decDepth ui = updateReportDepth dec ui
  where
    dec (DepthSpec (Just d) _) = DepthSpec (Just $ max 0 (d-1)) []
    dec (DepthSpec Nothing  _) = DepthSpec (Just $ maxDepth ui - 1) []

-- | Increment the current depth limit. If this makes it equal to the
-- the maximum account depth, remove the depth limit.
incDepth :: UIState -> UIState
incDepth = updateReportDepth inc
  where
    inc (DepthSpec Nothing  _) = DepthSpec Nothing []
    inc (DepthSpec (Just d) _) = DepthSpec (Just $ d + 1) []

-- | Set the current depth limit to the specified depth, or remove the depth limit.
-- Also remove the depth limit if the specified depth is greater than the current
-- maximum account depth. If the specified depth is negative, reset the depth limit
-- to whatever was specified at uiartup.
setDepth :: Maybe Int -> UIState -> UIState
setDepth mdepth = updateReportDepth (const $ DepthSpec mdepth [])

getDepth :: UIState -> Maybe Int
getDepth = dsFlatDepth . (^.depth)

-- | Update report depth by a applying a function. If asked to set a depth less
-- than zero, it will leave it unchanged.
updateReportDepth :: (DepthSpec -> DepthSpec) -> UIState -> UIState
updateReportDepth updateDepth ui = over reportSpec update ui
  where
    update = fromRight (error' "updateReportDepth: updating depth should not result in an error")  -- PARTIAL:
           . updateReportSpecWith (\ropts -> ropts{depth_=clipDepth ropts $ updateDepth (depth_ ropts)})
    clipDepth _        (DepthSpec Nothing  _) = mempty
    clipDepth ropts ds@(DepthSpec (Just d) _) | d < 0            = depth_ ropts
                                              | d >= maxDepth ui = mempty
                                              | otherwise        = ds

-- | Open the minibuffer, setting its content to the current query with the cursor at the end.
showMinibuffer :: T.Text -> Maybe String -> UIState -> UIState
showMinibuffer label moldq ui = setMode (Minibuffer label e) ui
  where
    e = applyEdit gotoEOL $ editor MinibufferEditor (Just 1) oldq
    oldq = fromMaybe (T.unpack . T.unwords . map textQuoteIfNeeded $ ui^.querystring) moldq

-- | Close the minibuffer, discarding any edit in progress.
closeMinibuffer :: UIState -> UIState
closeMinibuffer = setMode Normal

setMode :: Mode -> UIState -> UIState
setMode m ui = ui{aMode=m}

-- | Descend into a new screen, making it active and suspending the current one
-- onto the navigation stack. The canonical way to push the zipper.
pushScreen :: Screen -> UIState -> UIState
pushScreen scr ui =
  dbg1Msg ("pushing screen " <> showScreenId scr <> ". " <> showScreenStack "" showScreenId ui1)
  ui1
  where ui1 = ui{aPrevScreens=aScreen ui:aPrevScreens ui, aScreen=scr }

-- | Return to the parent screen, discarding the active one. At the root screen this
-- is a no-op, since the stack always keeps at least one screen. The canonical way to
-- pop the zipper.
popScreen :: UIState -> UIState
popScreen ui@UIState{aPrevScreens = s : ss} =
  dbg1Msg ("popping screen " <> showScreenId (aScreen ui) <> ". " <> showScreenStack "" showScreenId ui1)
  ui1
  where ui1 = ui{aPrevScreens = ss ,aScreen = s }
popScreen ui = ui

-- | Reset options to their startup values, discard screen navigation history,
-- and return to the top screen, regenerating it with the startup options 
-- and the provided reporting date.
resetScreens :: Day -> UIState -> UIState
resetScreens d ui@UIState{astartupopts=origopts, auncollapsedjournal=jraw, aScreen=s,aPrevScreens=ss} =
  ui{aopts=origopts, ajournal=jdisplay, aPrevScreens=[], aScreen=topscreen', aMode=Normal}
  where
    -- restore the startup lots state too, re-deriving the display journal from the uncollapsed one
    jdisplay   = uiDisplayJournal origopts jraw
    topscreen' = screenUpdate origopts d jdisplay $ lastDef s ss

-- | Regenerate the content of all screens in the stack from the ui state's current
-- options and stored journal, preserving the screen navigation history.
-- Note, does not save the reporting date.
--
-- This is the single place that establishes the display journal (ajournal) from the
-- stored uncollapsed journal and the current options, so the two journals can never
-- drift out of sync. To change the journal (eg on reload), set auncollapsedjournal and
-- then call this. To change the lots toggle, flip the option (toggleLots) and call this.
--
-- Every screen regenerates from its own stored parameters (plus the options, date and journal),
-- not from any other screen, so the whole stack refreshes uniformly here.
regenerateScreens :: Day -> UIState -> UIState
regenerateScreens d ui@UIState{aopts=opts, auncollapsedjournal=jraw, aScreen=s,aPrevScreens=ss} =
  -- Re-derive _rsQuery from the user's querystring_ and re-expand cur:
  -- terms against the (possibly reloaded) journal's commodity aliases.
  -- If re-derivation fails, fall back to the existing query.
  let copts    = uoCliOpts opts
      rspec    = reportspec_ copts
      rspec'   = case reportSpecExpandCurQueries jraw rspec of
                   Right rs -> rs
                   Left _   -> rspec
      opts'    = opts{uoCliOpts = copts{reportspec_ = rspec'}}
      -- the display journal, derived here so it always matches the stored journal and options
      jdisplay = uiDisplayJournal opts' jraw
      -- Regenerate the active screen and the whole hidden stack strictly, so no
      -- previous-generation screen/list/journal is retained after a reload (#1825).
      s'  = screenUpdate opts' d jdisplay s
      ss' = strictMapScreens (screenUpdate opts' d jdisplay) ss
  in s' `seq` ss' `seq` ui{aopts=opts', ajournal=jdisplay, aScreen=s', aPrevScreens=ss'}

-- | Like @map@ over a screen stack, but strict in the list spine and in each regenerated
-- screen (forced to WHNF), so the lazy-map accumulation of previous-generation screens is
-- collapsed on each reload rather than chaining up over time (#1825).
strictMapScreens :: (Screen -> Screen) -> [Screen] -> [Screen]
strictMapScreens _ []     = []
strictMapScreens f (s:ss) = let s' = f s; ss' = strictMapScreens f ss in s' `seq` ss' `seq` (s' : ss')
