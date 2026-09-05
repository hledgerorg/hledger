{-# LANGUAGE TemplateHaskell #-}
{-|
Serving of the web app's static files, and type-safe routes for them.
-}
module Hledger.Web.Settings.StaticFiles where

import Data.FileEmbed (embedDir)
import Network.Wai.Application.Static (defaultFileServerSettings, embeddedSettings, staticApp)
import System.IO (stdout, hFlush)
import WaiAppStatic.Types (StaticSettings(..))
import Yesod.Core (WaiSubsite(..))

import Hledger.Web.Settings (staticDir, development, staticFileRoute)

-- | Create the static file serving site (a WAI app used as a Yesod subsite).
-- In development builds it serves the files in the static directory,
-- re-reading them from disk on each request;
-- otherwise it serves the static directory's files as they were
-- at compile time, embedded in the executable.
staticSite :: IO WaiSubsite
staticSite =
  if development
   then do
     putStrLn ("Running in dev mode, will read static files from " ++ staticDir ++ "/") >> hFlush stdout
     return $ serve $ defaultFileServerSettings staticDir
   else
     -- putStrLn "Using built-in web files" >> hFlush stdout
     return $ serve $ embeddedSettings $(embedDir staticDir)
  where
    -- serve files with hash-based ETag headers, so browsers can cache them
    serve settings = WaiSubsite $ staticApp settings{ssUseHash = True}

-- Type-safe routes for the static files used by the app,
-- verified to exist at compile time.
css_bootstrap_min_css                       = $(staticFileRoute "css/bootstrap.min.css")
css_bootstrap_datepicker_standalone_min_css = $(staticFileRoute "css/bootstrap-datepicker.standalone.min.css")
js_bootstrap_min_js                         = $(staticFileRoute "js/bootstrap.min.js")
js_bootstrap_datepicker_min_js              = $(staticFileRoute "js/bootstrap-datepicker.min.js")
js_excanvas_min_js                          = $(staticFileRoute "js/excanvas.min.js")
js_jquery_cookie_js                         = $(staticFileRoute "js/jquery.cookie.js")
js_jquery_flot_min_js                       = $(staticFileRoute "js/jquery.flot.min.js")
js_jquery_flot_selection_min_js             = $(staticFileRoute "js/jquery.flot.selection.min.js")
js_jquery_flot_time_min_js                  = $(staticFileRoute "js/jquery.flot.time.min.js")
js_jquery_flot_tooltip_min_js               = $(staticFileRoute "js/jquery.flot.tooltip.min.js")
js_jquery_hotkeys_js                        = $(staticFileRoute "js/jquery.hotkeys.js")
js_jquery_min_js                            = $(staticFileRoute "js/jquery.min.js")
js_jquery_url_js                            = $(staticFileRoute "js/jquery.url.js")
js_typeahead_bundle_min_js                  = $(staticFileRoute "js/typeahead.bundle.min.js")
hledger_css                                 = $(staticFileRoute "hledger.css")
hledger_js                                  = $(staticFileRoute "hledger.js")
