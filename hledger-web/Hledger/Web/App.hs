{-|
Most of the definition of the web app is here.
In the usual Yesod style, this defines the web app's core types and configuration,
and then Application.hs completes the job.
-}

{-# OPTIONS_GHC -fno-warn-orphans  #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE PackageImports        #-}
{-# LANGUAGE QuasiQuotes           #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TupleSections         #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE ViewPatterns          #-}

module Hledger.Web.App where

import Control.Applicative ((<|>))
import Control.Monad (join, mfilter, when, unless)
-- import Control.Monad.Except (runExceptT)  -- now re-exported by Hledger
import "base64-bytestring" Data.ByteString.Base64 qualified as B64  -- not base64's module of the same name
import Data.ByteString.Char8 qualified as BC
import Data.Foldable (for_)
import Data.Map qualified as M
import Data.Traversable (for)
import Data.IORef (IORef, readIORef, writeIORef)
import Data.Maybe (catMaybes, fromMaybe, isJust, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Calendar (Day)
import Network.HTTP.Conduit (Manager)
import Network.HTTP.Types (status403)
import Network.Wai (rawPathInfo, rawQueryString, requestHeaders, requestMethod)
import Safe (atMay, readMay)
import System.Directory (XdgDirectory (..), createDirectoryIfMissing,
                         getXdgDirectory)
import System.Entropy (getEntropy)
import System.FilePath (takeFileName, (</>))
import Text.Blaze (Markup)
import Text.Hamlet (hamletFile)
import Yesod
import Yesod.Default.Config
import Yesod.Form.I18n.Chinese (chineseFormMessage)
import Yesod.Form.I18n.German (germanFormMessage)
import Yesod.Form.I18n.Russian (russianFormMessage)
import Yesod.Form.I18n.Spanish (spanishFormMessage)

import Hledger.Utils.I18n (Translations(..), i18n, langTagCandidates, resolveLang, tr, trc)
import Hledger
import Hledger.Cli (CliOpts(..), journalReloadIfChanged)
import Hledger.Cli.Commands.Balancesheet (balancesheetSpec)
import Hledger.Cli.Commands.Balancesheetequity (balancesheetequitySpec)
import Hledger.Cli.Commands.Cashflow (cashflowSpec)
import Hledger.Cli.Commands.Incomestatement (incomestatementSpec)
import Hledger.Cli.CompoundBalanceCommand (CompoundBalanceCommandSpec(..))
import Hledger.Web.ReportPage (AmountMode(..), accumWord, amountModeOf, intervalPeriodExpr, parseListMode, parseValue, reportLinks, setAmountMode)
import Hledger.Web.Settings (Extra(..), widgetFile)
import Hledger.Web.Settings.StaticFiles
import Hledger.Web.WebOptions
import Hledger.Web.Widget.Common (MovedOptions(..), accountParams, balanceReportAsHtml, normalisedSearch)
import Data.List (findIndex, isPrefixOf, partition)

-- | The site argument for your application. This can be a good place to
-- keep settings and values requiring initialization before your application
-- starts running, such as database connections. Every handler will have
-- access to the data present here.
data App = App
    { settings :: AppConfig DefaultEnv Extra
    , getStatic :: WaiSubsite -- ^ The static file serving site (see StaticFiles.hs).
    , httpManager :: Manager
      --
    , appOpts    :: WebOpts
    , appJournal :: IORef JournalState
        -- ^ the current journal and its derived forms, reloaded from
        --   its files when they change.
    , appTranslations :: M.Map Text Translations
        -- ^ the translation catalogs available to viewers, by language tag
        --   (built-in and from the user's config directory), loaded at startup.
    }

-- | The shared journal state: the current journal as loaded, with any
-- lot detail (lot subaccounts and synthetic postings) retained - the
-- journal is always loaded with --lots forced on (see Main.hs) - plus
-- forms derived from it once per (re)load.
data JournalState = JournalState
  { jsFull      :: Journal  -- ^ the journal as loaded, lot detail retained
  , jsCollapsed :: Journal  -- ^ the same with lot detail collapsed, as pages show by default
  , jsHasLots   :: Bool     -- ^ does the journal use lots at all ? (cached; it scans all postings)
  }

-- | Make the journal state for a newly (re)loaded journal.
mkJournalState :: Journal -> JournalState
mkJournalState j = JournalState
  { jsFull      = j
  , jsCollapsed = journalCollapseLotDetail j
  , jsHasLots   = journalHasLotFeatures j
  }


-- This is where we define all of the routes in our application. For a full
-- explanation of the syntax, please see:
-- http://www.yesodweb.com/book/handler
--
-- This function does three things:
--
-- * Creates the route datatype AppRoute. Every valid URL in your
--   application can be represented as a value of this type.
-- * Creates the associated type:
--       type instance Route App = AppRoute
-- * Creates the value resourcesApp which contains information on the
--   resources declared below. This is used in Handler.hs by the call to
--   mkYesodDispatch
--
-- What this function does *not* do is create a YesodSite instance for App.
-- AppCreating that instance requires all of the handler functions
-- for our application to be in scope. However, the handler functions
-- usually require access to the AppRoute datatype. Therefore, we
-- split these actions into two functions and place the other in a
-- separate file (Application.hs).
-- mkYesodData defines things like:
--
-- * type Handler = HandlerFor App   -- HandlerT App IO, https://www.yesodweb.com/book/routing-and-handlers#routing-and-handlers_handler_monad
-- * type Widget = WidgetFor App ()  -- WidgetT App IO (), https://www.yesodweb.com/book/widgets
--
mkYesodData "App" $(parseRoutesFile "config/routes")

type AppRoute = Route App
type Form a = Html -> MForm Handler (FormResult a, Widget)

-- Please see the documentation for the Yesod typeclass. There are a number
-- of settings which can be configured by overriding methods here.
instance Yesod App where

  -- Configure the app root, AKA base url, which is prepended to relative hyperlinks.
  -- 1. when a --base-url was specified, use that
  -- 2. otherwise, guess it from request headers, which helps us respond from the same hostname/IP address when accessible via multiple IPs
  -- 3. otherwise, leave it empty (relative links stay relative).
  -- Past issues: #2099, #2100, #2127, #hledger-2024-07-18
  approot
    | hasbaseurl = ApprootMaster (T.pack . base_url_ . appOpts)
    | otherwise  = guessApprootOr (ApprootMaster (appRoot . settings))
    where
      hasbaseurl = any ("--base-url" `isPrefixOf`) progArgs
        -- needs unsafePerformIO; does not detect abbreviations like --base

  makeSessionBackend _ = do
    hledgerdata <- getXdgDirectory XdgCache "hledger"
    createDirectoryIfMissing True hledgerdata
    let sessionexpirysecs = 120
    Just <$> defaultClientSessionBackend sessionexpirysecs (hledgerdata </> "hledger-web_client_session_key.aes")

  -- defaultLayout :: WidgetFor site () -> HandlerFor site Html
  defaultLayout widget = do

    -- Don't run if server-side UI is disabled.
    -- This single check probably covers all the HTML-returning handlers,
    -- but for now they do the check as well.
    checkServerSideUiEnabled

    master <- getYesod
    here <- fromMaybe RootR <$> getCurrentRoute
    VD{opts, j, jHasLots, qparam, q, account, perms, trs} <- getViewData
    msg <- getMessage
    -- Unless --lang fixes the language: an explicit ?_LANG= choice is
    -- remembered in a cookie, which Yesod's languages reads on later
    -- requests; only a tag naming an available catalog is accepted. And
    -- since the page varies by language, say so for any cache in front of
    -- a shared server.
    unless (langFixed master) $ do
      mlangparam <- lookupGetParam "_LANG"
      for_ (mlangparam >>= \l -> resolveLang (M.keys $ appTranslations master) [l]) $ \l ->
        addHeader "Set-Cookie" $ "_LANG=" <> l <> "; Path=/; Max-Age=31536000; SameSite=Lax"
      addHeader "Vary" "Cookie, Accept-Language"
    let lang = trLang trs
    showSidebar <- shouldShowSidebar
    -- The policy is sent from here rather than from a middleware, so that
    -- the header and the page's script tags always carry the same nonce;
    -- error pages come through here too, in a handler state of their own.
    nonce <- liftIO newCspNonce
    addHeader "Content-Security-Policy" $ cspHeader nonce
    -- In browse mode the page pings the server while it is open (hledger.js);
    -- the body attribute this sets is how the page knows to.
    let browsemode = server_mode_ opts == ServeBrowse

    -- The sidebar shows amounts the way the page does: converted as the
    -- value parameter asks, with inferred market prices if asked.
    mvalmode <- either (const Nothing) id . parseValue <$> lookupGetParam "value"
    inferparam <- (== Just "1") <$> lookupGetParam "infer"
    mlistmode <- either (const Nothing) id . parseListMode <$> lookupGetParam "list"
    let rspec = reportspec_ (cliopts_ opts)
        -- In the page's tree mode the sidebar gets fold carets (the
        -- inline script in default-layout.hamlet); its shape never changes.
        sidebarFold = fromMaybe (accountlistmode_ (_rsReportOpts rspec)) mlistmode == ALTree
        -- whether a depth limit folds the sidebar rather than clipping
        -- it: in tree mode, except depth 0, a single total
        sidebarFolds = sidebarFold && dsFlatDepth (queryDepth q) /= Just 0
        ropts' = maybe id setAmountMode mvalmode $ (_rsReportOpts rspec)
          {accountlistmode_ = ALTree  -- always the account tree; tree mode only adds folding (data-fold below)
          ,empty_           = True    -- show zero items by default
          ,interval_        = NoInterval  -- one balance per account, over the search's own span
          ,infer_prices_    = infer_prices_ (_rsReportOpts rspec) || inferparam
          ,fold_depth_      = mfilter (const sidebarFolds) $ dsFlatDepth $ queryDepth q
          }
        -- A depth limit clips the sidebar's accounts, except in tree
        -- mode, where the sidebar is served without the flat limit and
        -- that becomes its initial fold, as in the report tables: the
        -- carets open the deeper accounts in place. fold_depth_ keeps
        -- boring parents from being elided across it. Per-account depth
        -- limits still clip, and so does depth 0.
        sidebarQ = if sidebarFolds then filterQuery (not . queryIsFlatDepth) q else q
        sidebarFoldDepth
          | sidebarFolds = maybe "" (T.pack . show) $ dsFlatDepth $ queryDepth q
          | otherwise   = ""
        rspec' = rspec{_rsQuery=sidebarQ,_rsReportOpts=ropts'}

    -- The parameters the search form and its clear button keep, so that
    -- a search does not reset the page: a report page's interval, depth,
    -- accumulation mode, and amount conversion, and the register's modes.
    -- The accumulation mode is kept only when it is not the default, as
    -- the pages' own links carry it.
    let keepable :: Text -> Text -> Bool
        keepable "accum" v = v `elem` keptAccums here
        keepable _       v = not (T.null v)
    keptParams <- fmap catMaybes . for (keptParamNames here) $ \name ->
      fmap (name,) . mfilter (keepable name) <$> lookupGetParam name

    hideEmptyAccts <- hideEmptyAccounts

    -- The sidebar's links keep the search, minus any account term,
    -- which the reports ignore, and the sticky report state the page
    -- keeps; the page-local parameters (accum, costs) stay behind.
    let sidebarReports = reportLinkItems $ filter rmInSidebar $ reportMenuFor jHasLots
        sidebarParams =
          [p | p@("interval", _) <- keptParams] ++
          [("q", qparam) | not (T.null qparam)] ++
          [p | p@(k, _) <- keptParams, k /= "interval", k `elem` stickyParamNames]
        -- The pages g then a key goes to (hledger.js), with the sidebar
        -- links' parameters.
        goItems :: [(Text, (Route App, [(Text, Text)]), Text, Text)]
        goItems = [ (rmGoKey i, (rmRoute i, sidebarParams), tr trs (rmLabel i), tr trs (rmTitle i)) | i <- reportMenuFor jHasLots ]
        -- After them, g then n or p goes to the next or previous page in
        -- the menu's order, going round; from a page not in the menu, to
        -- the first or the last.
        goSteps :: [(Text, (Route App, [(Text, Text)]), Text, Text)]
        goSteps =
          [ (key, (rmRoute i, sidebarParams), label, title)
          | (key, step, label, title) <-
              -- TRANSLATORS: the go menu's items for the next and previous page, and their tooltips.
              [ ("n", 1,  tr trs "Next report",     tr trs "Go to the next report")
              , ("p", -1, tr trs "Previous report", tr trs "Go to the previous report") ]
          , Just i <- [goStep step] ]
        goMenu = reportMenuFor jHasLots
        goStep step = atMay goMenu $ case findIndex ((== here) . rmRoute) goMenu of
          Just i  -> (i + step) `mod` length goMenu
          Nothing -> if step > 0 then 0 else length goMenu - 1
        -- The links to the journal and reports at the top of every page,
        -- above the search, with the sidebar links' parameters.
        reportsRow = reportLinks trs here sidebarParams $ reportLinkGroups $ reportMenuFor jHasLots
        -- What the sidebar's bottom row is, in the current amounts mode:
        -- the whole journal's net. Label it by what that means.
        (totlabel, tottitle) = case amountModeOf ropts' of
          Just AtCost ->
            (tr trs "Net, at cost:",
             tr trs "The sum of every account, converted to cost: zero for balanced books; anything left comes from unbalanced virtual postings.")
          Just (AtVal _) ->
            (tr trs "Unbooked gains:",
             tr trs "The sum of every account at market value: appreciation not booked by any entry. If realized gains are booked, this is the unrealized gains.")
          _ ->
            (tr trs "Net flows:",
             tr trs "The sum of every account: open positions in each commodity, and the cash that paid for them. Zero when nothing crosses commodities.")
        accounts =
          balanceReportAsHtml RegisterR here sidebarReports sidebarParams hideEmptyAccts totlabel tottitle trs j qparam account $
          styleAmounts (journalCommodityStylesWith HardRounding j) $
          balanceReport rspec' j

        topShowmd = if showSidebar then "col-md-4" else "col-any-0" :: Text
        topShowsm = if showSidebar then "col-sm-4" else "" :: Text
        sideShowmd = if showSidebar then "col-md-4" else "col-any-0" :: Text
        sideShowsm = if showSidebar then "col-sm-4" else "" :: Text
        mainShowmd = if showSidebar then "col-md-8" else "col-md-12" :: Text
        mainShowsm = if showSidebar then "col-sm-8" else "col-sm-12" :: Text

    -- We break up the default layout into two components:
    -- default-layout is the contents of the body tag, and
    -- default-layout-wrapper is the entire page. Since the final
    -- value passed to hamletToRepHtml cannot be a widget, this allows
    -- you to use normal widget features in default-layout.
    pc <- widgetToPageContent $ do
      addStylesheet $ StaticR css_bootstrap_min_css
      addStylesheet $ StaticR hledger_css
      addScript $ StaticR hledger_js
      $(widgetFile "default-layout")

    withUrlRenderer $(hamletFile "templates/default-layout-wrapper.hamlet")

----------------------------------------------------------------------
-- translations

-- | The translations for a viewer. When hledger-web was started with a
-- --lang naming a language, that one, whatever the viewer asks for.
-- Otherwise the first available one in the viewer's preferences (as listed
-- by Yesod's 'languages': the _LANG query parameter, cookie and session
-- variable, then the Accept-Language header), trying each preference with
-- its subtags dropped before moving on to the next; falling back to English,
-- or with --lang=auto, the language of hledger-web's environment.
translationsFor :: App -> [Lang] -> Translations
translationsFor app@App{appTranslations} langs
  | langFixed app = servertrs
  | otherwise = fromMaybe servertrs $ (`M.lookup` appTranslations) =<< resolveLang (M.keys appTranslations) langs
  where servertrs = translations_ $ _rsReportOpts $ reportspec_ $ cliopts_ $ appOpts app

-- | Was hledger-web started with a --lang naming a language, which then
-- applies to every page? (--lang=auto leaves the choice to each viewer.)
langFixed :: App -> Bool
langFixed = maybe False (/= "auto") . maybestringopt "lang" . rawopts_ . cliopts_ . appOpts

-- | The translations for the current request's language.
requestTranslations :: Handler Translations
requestTranslations = translationsFor <$> getYesod <*> languages

-- | A translatable text, for @_{HMsg "..."}@ in templates and 'setMessageI'.
newtype HMsg = HMsg Text

instance RenderMessage App HMsg where
  renderMessage app langs (HMsg s) = tr (translationsFor app langs) s

-- | Like 'HMsg', with a context disambiguating a short text used in
-- more than one sense, eg @_{HMsgc "column heading" "Total"}@.
data HMsgc = HMsgc Text Text

instance RenderMessage App HMsgc where
  renderMessage app langs (HMsgc ctx s) = trc (translationsFor app langs) ctx s

-- | yesod-form's validation messages, in the request's language when
-- yesod-form ships that language.
instance RenderMessage App FormMessage where
  renderMessage app langs = fromMaybe defaultFormMessage $ listToMaybe
    [ m | c <- langTagCandidates (trLang $ translationsFor app langs), Just m <- [lookup c formMessages] ]
    where
      formMessages =
        [ ("de",      germanFormMessage)
        , ("es",      spanishFormMessage)
        , ("ru",      russianFormMessage)
        , ("zh-Hans", chineseFormMessage)
        ]


----------------------------------------------------------------------
-- content security policy

-- | The Content-Security-Policy sent with every HTML page. Everything loads
-- from our own origin, and the only inline scripts allowed are the ones
-- carrying this response's nonce: the two in default-layout.hamlet and its
-- wrapper. The templates have no inline styles or event handlers, and
-- hledger.js sets its styles through the CSSOM, which the policy does not govern.
-- frame-ancestors stops the pages being framed by another origin
-- (clickjacking of the add and edit forms); the other responses get
-- X-Frame-Options instead, see Application.hs.
--
-- 'self' assumes the static files come from our own origin. If --file-url
-- (extraStaticRoot, #2139) is ever re-enabled, that origin has to be added
-- to default-src as well, or every page will lose its styles and scripts.
cspHeader :: Text -> Text
cspHeader nonce = T.intercalate "; "
  [ "default-src 'self'"
  , "script-src 'self' 'nonce-" <> nonce <> "'"
  , "object-src 'none'"
  , "base-uri 'self'"
  , "form-action 'self'"
  , "frame-ancestors 'self'"
  ]

-- | A nonce for the policy above: 16 random bytes, base64 encoded.
newCspNonce :: IO Text
newCspNonce = TE.decodeUtf8 . B64.encode <$> getEntropy 16

----------------------------------------------------------------------
-- template and handler utilities

-- view data, used by the add form and handlers
-- XXX Parameter p - show/hide postings

-- | A bundle of data useful for hledger-web request handlers and templates.
data ViewData = VD
  { opts  :: WebOpts    -- ^ the command-line options at startup
  , today :: Day        -- ^ today's date (for queries containing relative dates)
  , j     :: Journal    -- ^ the up-to-date parsed unfiltered journal, as displayed:
                        --   lot detail collapsed unless lotsShown    -- XXX rename
  , jfull :: Journal    -- ^ the same journal with lot detail retained,
                        --   for reports that aggregate lots themselves
  , jHasLots :: Bool    -- ^ does the journal use lots at all ?
  , lotsShown :: Bool   -- ^ is lot detail shown, by the lots=1 parameter ?
  , qparam :: Text       -- ^ the current "q" request parameter
  , q     :: Query      -- ^ a query parsed from the q parameter. A depth parameter's limit
                        --   is also added hereas a Depth term, since the reports use it.
  , qopts :: [QueryOpt] -- ^ query options parsed from the q parameter
  , account :: Maybe (AccountName, Bool)  -- ^ the account an account register is for, from the account
                        --   parameter, and whether with its subaccounts (not with subs=0)
  , perms :: [Permission]  -- ^ permissions enabled for this request (by --allow and/or X-Sandstorm-Permissions)
  , trs   :: Translations  -- ^ translations for this request's language
  , hideEmpty :: Bool      -- ^ hide zero-balance accounts ? (the empty parameter, cf hideEmptyAccounts)
  , controlsOpen :: Bool   -- ^ is the controls disclosure open ? (the showcontrols cookie)
  , commoditiesOpen :: Bool -- ^ is the commodity filter's list open ? (the showcommodities cookie)
  } deriving (Show)

instance Show Text.Blaze.Markup where show _ = "<blaze markup>"

-- | Gather data used by handlers and templates in the current request.
getViewData :: Handler ViewData
getViewData = do
  App{
    appOpts=opts0@WebOpts{ cliopts_=copts@CliOpts{ reportspec_=rspec@ReportSpec{_rsReportOpts} } },
    appJournal
  } <- getYesod
  -- With --debug, show each request's url as received
  req <- waiRequest
  dbg1IO "url" $ BC.unpack (rawPathInfo req) ++ BC.unpack (rawQueryString req)
  let today = _rsDay rspec
  -- the request's language, applied to the options too so that any
  -- report text rendered by hledger-lib matches the page
  trs <- requestTranslations
  let opts = opts0{cliopts_ = copts{reportspec_ = rspec{_rsReportOpts = _rsReportOpts{translations_ = trs}}}}

  -- try to read the latest journal content, keeping the old content
  -- if there's an error
  (js, mjerr) <- getCurrentJournal
                appJournal
                copts{reportspec_=rspec{_rsReportOpts=_rsReportOpts{no_elide_=True}}}
                today

  -- With lots=1, show lot detail (lot subaccounts and per-lot postings),
  -- which is collapsed by default.
  lotsShown <- (== Just "1") <$> lookupGetParam "lots"
  let jHasLots = jsHasLots js
      jfull = jsFull js
      j = if lotsShown then jfull else jsCollapsed js

  -- Get the query specified by the q request parameter, or no query if this fails.
  qparam <- fromMaybe "" <$> lookupGetParam "q"
  normaliseUrlState today qparam
  -- The depth parameter's limit joins the parsed query, as a depth:N term
  -- would, since the reports read depth limits from the query (as the
  -- command line's --depth does); qparam, the search text that the search
  -- box and links show, is left as it is.
  mdepth <- (mfilter (>= 0) . readMay . T.unpack =<<) <$> lookupGetParam "depth"
  (q, qopts, mqerr) <- do
    case parseQuery today qparam of
      Right (q0, qopts) -> return (maybe q0 (\d -> simplifyQuery $ And [q0, Depth d]) mdepth, qopts, Nothing)
      Left err         -> return (Any, [], Just err)
  subs <- (/= Just "0") <$> lookupGetParam "subs"
  account <- fmap (, subs) . mfilter (not . T.null) <$> lookupGetParam "account"
  dbg1IO "q parameter" qparam
  dbg1IO "query" q

  -- if either of the above gave an error, display it
  maybe (pure ()) (setMessage . toHtml) $ mjerr <|> mqerr

  -- find out which permissions are enabled
  perms <- case allow_ opts of
    -- if started with --allow=sandstorm, take permissions from X-Sandstorm-Permissions header
    SandstormAccess -> do
      let h = "X-Sandstorm-Permissions"
      hs <- fmap (BC.split ',' . snd) . filter ((== h) . fst) . requestHeaders <$> waiRequest
      fmap join . for (join hs) $ \x -> case parsePermission x of
        Left  e -> [] <$ addMessage "" ("Unknown permission: " <> toHtml e)
        Right p -> pure [p]
    -- otherwise take them from the access level specified by --allow's access level
    cliaccess -> pure $ accessLevelToPermissions cliaccess

  -- the view preferences: zero balances hidden, and the disclosures' state
  hideEmpty <- hideEmptyAccounts
  controlsOpen <- showControls
  commoditiesOpen <- showCommodities

  return VD{opts, today, j, jfull, jHasLots, lotsShown, qparam, q, qopts, account, perms, trs, hideEmpty, controlsOpen, commoditiesOpen}

-- | Move the report options in a page's search, and in the old period
-- parameter, to their own parameters, by reloading the page: the search
-- holds the terms selecting data, and the parameters, set by the
-- controls, the report's shape. A depth:N term (typed, or from a link
-- written before hledger-web had a depth parameter) becomes the depth
-- parameter, a date:INTERVAL term's interval the interval parameter,
-- leaving its date span in the search, where the old period parameter's
-- span goes too, and an inacct: or inacctonly: term the account (and
-- subs) parameters naming an account register's account. See
-- normalisedSearch.
normaliseUrlState :: Day -> Text -> Handler ()
normaliseUrlState today qparam = do
  isget <- (== "GET") . requestMethod <$> waiRequest
  mroute <- getCurrentRoute
  mperiod <- lookupGetParam "period"
  case (isget, mroute, normalisedSearch today qparam (mfilter (not . T.null) mperiod)) of
    (True, Just route, Just MovedOptions{moSearch, moDepth, moInterval, moAccount}) -> do
      params <- reqGetParams <$> getRequest
      let mivltext = intervalPeriodExpr =<< moInterval
          replaced = ["q", "period"] ++ ["depth" | isJust moDepth] ++ ["interval" | isJust mivltext]
                     ++ concat [["account", "subs"] | isJust moAccount]
          params' =
            [("q", moSearch) | not (T.null moSearch)] ++
            maybe [] (\(a, subs) -> accountParams subs a) moAccount ++
            [p | p@(k, _) <- params, k `notElem` replaced] ++
            [("interval", w) | Just w <- [mivltext]] ++
            [("depth", T.pack (show n)) | Just n <- [moDepth]]
      redirect (route, params')
    _ -> return ()

checkServerSideUiEnabled :: Handler ()
checkServerSideUiEnabled = do
  VD{opts=WebOpts{server_mode_}} <- getViewData
  when (server_mode_ == ServeJson) $
    -- this one gives 500 internal server error when called from defaultLayout:
    --  permissionDenied "server-side UI is disabled due to --serve-api"
    sendResponseStatus status403 ("server-side UI is disabled due to --serve-api" :: Text)

-- | A page as the menus show it: the journal, or a report page.
data ReportMenuItem = ReportMenuItem {
    rmRoute     :: Route App,
    rmLabel     :: Text,
    rmTitle     :: Text,
    rmAccum     :: Maybe BalanceAccumulation,
      -- ^ a report page's default accumulation mode: its command's own for
      --   a statement, balance changes for the balance report; the journal,
      --   not a report page, has none
    rmInSidebar :: Bool,
      -- ^ has a row in the sidebar (the others are one click away, in the
      --   pages' own Report row)
    rmGeneral   :: Bool,
      -- ^ a general report, listed after the named pages, a little apart
    rmGoKey     :: Text
      -- ^ the key that goes to it after g (hledger.js); not translated,
      --   like the other keys
}

-- | The pages, in menu order: the journal and the named reports, as in the
-- sidebar, then the general reports.
reportMenu :: [ReportMenuItem]
reportMenu =
  -- TRANSLATORS: the report links above each report page and in the sidebar: each link's text, and its tooltip.
  [ ReportMenuItem JournalR            (i18n "Journal")                   (i18n "Show general journal entries, most recent first")     Nothing                                  True  False "j"
  , ReportMenuItem BalancesheetR       (i18n "Balance sheet")             (i18n "Show assets, liabilities, and net worth")             (Just $ cbcaccum balancesheetSpec)       True  False "b"
  , ReportMenuItem IncomestatementR    (i18n "Income statement")          (i18n "Show revenues and expenses")                          (Just $ cbcaccum incomestatementSpec)    True  False "i"
  , ReportMenuItem CashflowR           (i18n "Cashflow statement")        (i18n "Show changes in liquid assets")                       (Just $ cbcaccum cashflowSpec)           True  False "c"
  , ReportMenuItem HoldingsR           (i18n "Holdings")                  (i18n "Show investment holdings, lots, and gains")           (Just PerPeriod)                         True  False "h"
  , ReportMenuItem BalanceR            (i18n "All accounts")              (i18n "Show the balances of all accounts, by period, like the balance command") (Just PerPeriod) False True  "a"
  , ReportMenuItem BalancesheetequityR (i18n "Balance sheet with equity") (i18n "Show assets, liabilities, and equity")                (Just $ cbcaccum balancesheetequitySpec) False True  "e"
  ]

-- | The pages that apply to this journal: a journal with no lot features
-- gets no Holdings page.
reportMenuFor :: Bool -> [ReportMenuItem]
reportMenuFor hasLots = [i | i <- reportMenu, hasLots || rmRoute i /= HoldingsR]

-- | The pages' routes, labels, and titles, for a row of links.
reportLinkItems :: [ReportMenuItem] -> [(Route App, Text, Text)]
reportLinkItems items = [(rmRoute i, rmLabel i, rmTitle i) | i <- items]

-- | The pages' routes, labels, titles, and go keys, in two groups, the named
-- pages and the general reports, for a row of links that shows the groups
-- apart.
reportLinkGroups :: [ReportMenuItem] -> [[(Route App, Text, Text, Text)]]
reportLinkGroups items = filter (not . null) [keyed named, keyed general]
  where
    (general, named) = partition rmGeneral items
    keyed is = [(rmRoute i, rmLabel i, rmTitle i, rmGoKey i) | i <- is]

-- | The report pages: those that take a period and an accumulation mode.
reportRoutes :: [Route App]
reportRoutes = [rmRoute i | i <- reportMenu, isJust (rmAccum i)]

-- | The accum parameter values a page's links keep: the modes that are
-- not the page's default. (The register totals the period by default.)
keptAccums :: Route App -> [Text]
keptAccums route =
  case [dflt | i <- reportMenu, rmRoute i == route, Just dflt <- [rmAccum i]] of
    [dflt]                 -> [accumWord a | a <- [PerPeriod, Historical, Cumulative], a /= dflt]
    _ | route == RegisterR -> ["historical"]
    _                      -> []

-- | The query parameters a page's own links keep: the sticky report
-- state, which every page shows and preserves even where it shapes
-- nothing (the journal is the landing page, and the url hledger-web
-- opens for its startup options), plus the page-local parameters, the
-- accumulation mode (each page has its own default) and the register's
-- account and costs.
keptParamNames :: Route App -> [Text]
keptParamNames route
  | route == HoldingsR        = "closed" : stickyParamNames
  | route `elem` reportRoutes = "accum" : stickyParamNames
  | route == RegisterR        = "account" : "subs" : "accum" : "costs" : stickyParamNames
  | route == JournalR         = stickyParamNames
  | otherwise                 = []

-- | The report-state parameters every page preserves: a link changes
-- only the control it names. date2 has no control, being deprecated,
-- but is preserved like the rest.
stickyParamNames :: [Text]
stickyParamNames = ["interval", "depth", "value", "list", "total", "avg", "sort", "pct", "calc", "infer", "date2", "empty", "lots"]

-- | Are zero-balance accounts hidden ? The empty parameter says (1
-- shows them, 0 hides them, the direction of the command line's
-- -E/--empty); without one, they are hidden when hledger-web was
-- started with -E, and shown otherwise.
hideEmptyAccounts :: Handler Bool
hideEmptyAccounts = do
  App{appOpts} <- getYesod
  memptyp <- lookupGetParam "empty"
  return $ case memptyp of
    Just "0" -> True
    Just "1" -> False
    _        -> empty_ $ _rsReportOpts $ reportspec_ $ cliopts_ appOpts

-- | Find out if the sidebar should be visible. Show it, unless there is a
-- showsidebar cookie set to "0", or a ?sidebar=0 query parameter.
shouldShowSidebar :: Handler Bool
shouldShowSidebar = do
  msidebarparam <- lookupGetParam "sidebar"
  msidebarcookie <- uiCookie "showsidebar"
  return $
    let disablevalues = ["","0"]
    in maybe True (`notElem` disablevalues) $ msidebarparam <|> msidebarcookie

-- | Is the report controls disclosure open? Only when the showcontrols
-- cookie, which the browser sets when it is toggled (hledger.js), says
-- so. Read server side, so each page is born the way the last one was
-- left and nothing moves after paint.
showControls :: Handler Bool
showControls = (== Just "1") <$> uiCookie "showcontrols"

-- | Is the commodity filter's collapsed list open? Like showControls,
-- via the showcommodities cookie.
showCommodities :: Handler Bool
showCommodities = (== Just "1") <$> uiCookie "showcommodities"

-- | One of the cookies in which the browser remembers this hledger-web's
-- UI state (hledger.js). A browser shares cookies between all servers on
-- a host, whatever their port, so their names end with the port (see
-- uiCookieSuffix), keeping several hledger-webs' states apart.
-- Cookies, because the server renders this state; full window mode, which
-- it needn't know, is kept in the browser's session storage instead.
uiCookie :: Text -> Handler (Maybe Text)
uiCookie name = do
  App{appOpts} <- getYesod
  lookup (name <> uiCookieSuffix appOpts) . reqCookies <$> getRequest

-- | The end of this hledger-web's UI cookie names, also given to the
-- page's script (default-layout-wrapper.hamlet).
uiCookieSuffix :: WebOpts -> Text
uiCookieSuffix wopts = "_" <> T.pack (show $ port_ wopts)

-- | Update our copy of the journal if the file changed. If there is an
-- error while reloading, keep the old one and return the error, and set a
-- ui message.
getCurrentJournal :: IORef JournalState -> CliOpts -> Day -> Handler (JournalState, Maybe String)
getCurrentJournal jref opts d = do
  -- XXX put this inside atomicModifyIORef' for thread safety
  js <- liftIO (readIORef jref)
  ej <- liftIO . runExceptT $ journalReloadIfChanged opts d (jsFull js)
  case ej of
    Left e -> do
      setMessage "error while reading journal"
      return (js, Just e)
    Right (j', True) -> do
      let js' = mkJournalState j'
      liftIO $ writeIORef jref js'
      return (js', Nothing)
    Right (_, False) -> return (js, Nothing)

-- | In a request handler, check for the given permission
-- and fail with a message if it's not present.
require :: Permission -> Handler ()
require p = do
  VD{perms} <- getViewData
  unless (p `elem` perms) $ permissionDenied $
    "Missing the '" <> T.pack (showPermission p) <> "' permission"
