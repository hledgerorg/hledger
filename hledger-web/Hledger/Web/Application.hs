{-|
Complete the definition of the web app begun in App.hs.
This is always done in two files for (TH?) reasons.
-}

{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ViewPatterns #-}

module Hledger.Web.Application
  ( makeApplication
  , makeApp
  , makeAppWith
  ) where

import Data.IORef (newIORef, writeIORef)
import Network.Wai.Middleware.AddHeaders (addHeaders)
import Network.Wai.Middleware.RequestLogger (logStdoutDev, logStdout)
import Network.HTTP.Client (defaultManagerSettings)
import Network.HTTP.Conduit (newManager)
import Yesod.Default.Config

import Hledger.Data (Journal, nulljournal)

import Hledger.Web.Handler.AddR
import Hledger.Web.Handler.MiscR
import Hledger.Web.Handler.EditR
import Hledger.Web.Handler.UploadR
import Hledger.Web.Handler.JournalR
import Hledger.Web.Handler.RegisterR
import Hledger.Web.Import
import Hledger.Web.WebOptions (ServerMode(..), WebOpts(server_mode_), corsPolicy)

-- mkYesodDispatch creates our YesodDispatch instance. 
-- It complements the mkYesodData call in App.hs,
-- but must be in a separate file for (TH?) reasons.
mkYesodDispatch "App" resourcesApp

-- This function allocates resources (such as a database connection pool),
-- performs initialization and creates a WAI application. This is also the
-- place to put your migrate statements to have automatic database
-- migrations handled by Yesod.
makeApplication :: WebOpts -> Journal -> AppConfig DefaultEnv Extra -> IO Application
makeApplication opts' j' conf' = do
    app <- makeApp conf' opts'
    writeIORef (appJournal app) j'
    (logWare . corsPolicy opts' . securityHeaders) <$> toWaiApp app
  where
    logWare | development  = logStdoutDev
            | server_mode_ opts' `elem` [Serve, ServeJson] = logStdout
            | otherwise    = id
    -- Headers for every response, at the WAI level so that error pages and
    -- the static subsite get them too. X-Content-Type-Options stops the
    -- browser guessing a content type other than the one we send;
    -- X-Frame-Options stops any response being framed from another origin.
    -- HTML pages also carry a Content-Security-Policy (cspHeader in App.hs),
    -- whose frame-ancestors says the same thing and takes precedence in
    -- browsers that understand it; this covers everything else.
    securityHeaders = addHeaders
      [ ("X-Content-Type-Options", "nosniff")
      , ("X-Frame-Options", "SAMEORIGIN")
      ]

makeApp :: AppConfig DefaultEnv Extra -> WebOpts -> IO App
makeApp = makeAppWith nulljournal

-- Make an "App" (defined in App.hs), 
-- with the given Journal as its state
-- and the given "AppConfig" and "WebOpts" as its configuration.
makeAppWith :: Journal -> AppConfig DefaultEnv Extra -> WebOpts -> IO App
makeAppWith j' aconf wopts = do
  s    <- staticSite
  m    <- newManager defaultManagerSettings
  jref <- newIORef j'
  return App{
      settings    = aconf
    , getStatic   = s
    , httpManager = m
    , appOpts     = wopts
    , appJournal  = jref
    }
