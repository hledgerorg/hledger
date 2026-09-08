{-|
hledger-web - a basic but robust web UI and JSON API server for hledger.

SPDX-License-Identifier: GPL-3.0-or-later
Copyright (c) 2007-2025 (each year in this range) Simon Michael <simon@joyful.com> and contributors.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.
If not, see <https://www.gnu.org/licenses/>.

-}

{-# LANGUAGE CPP #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Hledger.Web.Main where

import Control.Concurrent (forkIO, threadDelay, newEmptyMVar, putMVar, takeMVar)
import Control.Concurrent.Async (race)
import Control.Exception (bracket)
#if MIN_VERSION_base(4,20,0)
import Control.Exception.Backtrace (setBacktraceMechanismState, BacktraceMechanism(..))
#endif
import Control.Monad (when, void)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Streaming.Network (bindRandomPortTCP)
import Data.String (fromString)
import Data.Text qualified as T
import GHC.Clock (getMonotonicTime)
import Network.HTTP.Types (status204)
import Network.Socket
import Network.Wai (Application, Middleware, pathInfo, responseLBS)
import Network.Wai.Handler.Warp (runSettings, runSettingsSocket, defaultSettings, setBeforeMainLoop, setHost, setPort)
import System.Directory (removeFile)
import System.Environment ( getArgs, withArgs )
import System.IO (hFlush, stdout)
import System.PosixCompat.Files (getFileStatus, isSocket)
import Text.Printf (printf)
import Yesod.Default.Config
import Yesod.Default.Main (defaultDevelApp)

import Hledger
import Hledger.Cli hiding (progname,prognameandversion)
import Hledger.Cli.Commands.Quickref (showQuickref)
import Hledger.Web.Application (makeApplication)
import Hledger.Web.Settings (Extra(..), parseExtra, defbaseurl)
import Hledger.Web.Test (hledgerWebTest)
import Hledger.Web.WebOptions

-- Run in fast reloading mode for yesod devel.
hledgerWebDev :: IO (Int, Application)
hledgerWebDev =
  withJournal (cliopts_ defwebopts) (defaultDevelApp loader . makeApplication defwebopts)
  where
    loader =
      Yesod.Default.Config.loadConfig
        (configSettings Development) {csParseExtra = parseExtra}

-- Run normally.
hledgerWebMain :: IO ()
hledgerWebMain = handleExit $ withGhcDebug' $ do
  when (ghcDebugMode == GDPauseAtStart) $ ghcDebugPause'

#if MIN_VERSION_base(4,20,0)
  -- Control ghc 9.10+'s stack traces.
  -- CostCentreBacktrace   - collect cost-centre stack backtraces (only available when built with profiling)
  -- HasCallStackBacktrace - collect HasCallStack backtraces
  -- ExecutionBacktrace    - collect backtraces from native execution stack unwinding
  -- IPEBacktrace          - collect backtraces from Info Table Provenance Entries
#ifdef DEBUG
  setBacktraceMechanismState HasCallStackBacktrace True
#else
  setBacktraceMechanismState HasCallStackBacktrace False
#endif
#endif

  wopts@WebOpts{cliopts_=copts@CliOpts{debug_, rawopts_}} <- getHledgerWebOpts
  when (debug_ > 0) $ printf "%s\n" prognameandversion >> printf "opts: %s\n" (show wopts)
  if
    | boolopt "quickref"        rawopts_ -> showQuickref
    | boolopt "help"            rawopts_ -> runPager $ showModeUsage webmode ++ "\n"
    | boolopt "examples"        rawopts_ -> runTldrForPage "hledger-web"
    | boolopt "info"            rawopts_ -> runInfoForTopic "hledger-web" Nothing
    | boolopt "man"             rawopts_ -> runManForTopic  "hledger-web" Nothing
    | boolopt "webman"          rawopts_ -> void $ openBrowserOn $ webManualUrl "hledger-web" Nothing
    | boolopt "version"         rawopts_ -> putStrLn prognameandversion
    -- boolopt "binary-filename" rawopts_ -> putStrLn (binaryfilename progname)
    | boolopt "test"            rawopts_ -> do
      -- remove --test and --, leaving other args for hspec
      (`withArgs` hledgerWebTest) . filter (`notElem` ["--test","--"]) =<< getArgs
    | otherwise                              -> withJournal copts (web wopts)

  when (ghcDebugMode == GDPauseAtEnd) $ ghcDebugPause'

-- | The hledger web command.
web :: WebOpts -> Journal -> IO ()
web opts0 j = do
  -- Refresh the startup ReportSpec against the loaded journal so cur:
  -- terms in the startup query are expanded against the journal's
  -- commodity aliases.
  let copts = cliopts_ opts0
      opts  = case reportSpecExpandCurQueries j (reportspec_ copts) of
                Right rs -> opts0{cliopts_ = copts{reportspec_ = rs}}
                Left _   -> opts0
  let depthlessinitialq = filterQuery (not . queryIsDepth) . _rsQuery . reportspec_ $ cliopts_ opts
      j' = filterJournalTransactions depthlessinitialq j
      h = host_ opts
      p0 = port_ opts
      staticRoot = T.pack <$> file_url_ opts  -- XXX not used #2139

  -- --port 0 means "let the operating system choose a free port". To learn which
  -- port it chose (so we can report it and build the base url), we must bind the
  -- listening socket ourselves rather than let warp do it. This isn't supported in
  -- --serve-browse mode, which needs a known port up front to open the browser at.
  when (p0 == 0 && socket_ opts == Nothing && server_mode_ opts == ServeBrowse) $
    error' $ unlines  -- PARTIAL:
      ["--port 0 (let the operating system choose a free port) is not supported with --serve-browse."
      ,"Please use --serve or --serve-api instead, which will report the chosen port."]
  mtcpsock <- if p0 == 0 && socket_ opts == Nothing
                then Just <$> bindRandomPortTCP (fromString h)
                else return Nothing
  let p = maybe p0 fst mtcpsock
      -- If the base url is the default one (built from host and port), rebuild it
      -- with the chosen port; if the user set --base-url, leave it untouched.
      u | base_url_ opts == defbaseurl h p0 = defbaseurl h p
        | otherwise                         = base_url_ opts
      appconfig = AppConfig{appEnv = Development
                           ,appHost = fromString h
                           ,appPort = p
                           ,appRoot = T.pack u
                           ,appExtra = Extra "" staticRoot
                           }
  app <- makeApplication opts j' appconfig

  -- show configuration
  let
    services
      | server_mode_ opts == ServeJson = "json API"
      | otherwise                      = "web UI and json API"
    prettyip ip
        | ip == "127.0.0.1" = ip ++ " (local access)"
        | ip == "0.0.0.0"   = ip ++ " (all interfaces)"
        | otherwise         = ip
    listenat =
      case socket_ opts of
        Just s  -> printf "socket %s" s
        Nothing -> printf "IP address %s, port %d" (prettyip h) p
  printf "Serving %s at %s\nwith base url %s\n" (services::String) (listenat::String) u
  case file_url_ opts of
    Just fu -> printf "and static files base url %s\n" fu
    Nothing -> pure ()

  -- start server and maybe browser
  if server_mode_ opts == ServeBrowse
    then do
      putStrLn "This server will exit after 2m with no browser windows open (or press ctrl-c)"
      putStrLn "Opening web browser..."
      hFlush stdout
      -- returns normally only after the idle exit (ctrl-c or a server failure raises instead)
      serveAndBrowse h p u app
      putStrLn "No browser windows were open for 2m, exiting. (Use --serve to serve without this timeout.)"

    else do
      putStrLn "Press ctrl-c to quit"
      hFlush stdout
      let warpsettings = setHost (fromString h) (setPort p defaultSettings)
      case (socket_ opts, mtcpsock) of
        (Just s, _) -> do
          if isUnixDomainSocketAvailable then
            bracket
              (do
                  sock <- socket AF_UNIX Stream 0
                  setSocketOption sock ReuseAddr 1
                  bind sock $ SockAddrUnix s
                  listen sock maxListenQueue
                  return sock
              )
              (\_ -> do
                  sockstat <-  getFileStatus s
                  when (isSocket sockstat) $ removeFile s
              )
              (\sock -> Network.Wai.Handler.Warp.runSettingsSocket warpsettings sock app)
            else error' $ unlines
              ["Unix domain sockets are not available on your operating system."
              ,"Please try again without --socket."
              ]

        -- --port 0: serve on the socket we already bound to the OS-chosen port.
        (Nothing, Just (_, sock)) -> Network.Wai.Handler.Warp.runSettingsSocket warpsettings sock app
        (Nothing, Nothing)        -> Network.Wai.Handler.Warp.runSettings warpsettings app

-- | Browse mode: serve the app, open the default web browser on it once it
-- is listening, and return when no browser window has shown it for two
-- minutes. A page says it is open by pinging /_ping while it is (see
-- browsePingInit in static/hledger.js). The pings are answered here, before
-- they reach the app, and the time of the latest one is kept.
serveAndBrowse :: String -> Int -> String -> Application -> IO ()
serveAndBrowse h p u app = do
  listening <- newEmptyMVar
  lastping  <- newIORef =<< getMonotonicTime
  let warpsettings =
        setBeforeMainLoop (putMVar listening ()) $
        setHost (fromString h) $ setPort p defaultSettings
  -- Run these concurrently: when either one finishes or fails, so does the other.
  void $ race
    (runSettings warpsettings $ answerPings lastping app)
    (do
      takeMVar listening
      _ <- forkIO $ void $ openBrowserOn u
      waitForIdle lastping)

-- | Answer /_ping with 204 No Content, noting the time; pass everything else to the app.
answerPings :: IORef Double -> Middleware
answerPings lastping app req send
  | pathInfo req == ["_ping"] = do
      writeIORef lastping =<< getMonotonicTime
      send $ responseLBS status204 [] ""
  | otherwise = app req send

-- | Return once no ping has arrived for browseIdleSeconds.
waitForIdle :: IORef Double -> IO ()
waitForIdle lastping = do
  t   <- readIORef lastping
  now <- getMonotonicTime
  let remaining = t + browseIdleSeconds - now
  when (remaining > 0) $ do
    threadDelay $ ceiling $ remaining * 1000000
    waitForIdle lastping

-- | How long browse mode keeps serving after the last ping. The pages ping
-- every 30 seconds (hledger.js), so a few pings can go missing before this
-- runs out.
browseIdleSeconds :: Double
browseIdleSeconds = 120
