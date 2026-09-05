{-|
Web app settings are centralized, as much as possible, into this file.
This includes database connection settings, static file locations, etc.
In addition, you can configure a number of different aspects of Yesod
by overriding methods in the Yesod typeclass in App.hs.
-}

{-# LANGUAGE CPP               #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

module Hledger.Web.Settings where

import Control.Monad (unless)
import Data.Default (def)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Yaml
import Language.Haskell.TH.Syntax (Q, Exp, runIO)
import System.Directory (doesFileExist)
import System.FilePath ((</>))
import Text.Hamlet
import Yesod.Core.Types (Route(WaiSubsiteRoute))
import Yesod.Default.Config
import Yesod.Default.Util

import Hledger.Cli.Version (packagemajorversion)

development :: Bool
development =
#if DEVELOPMENT
  True
#else
  False
#endif

production :: Bool
production = not development

hledgerorgurl :: Text
hledgerorgurl = "https://hledger.org"

manualurl :: Text
manualurl = hledgerorgurl <> "/" <> T.pack packagemajorversion <> "/hledger.html"

-- | The default IP address to listen on. May be overridden with --host.
defhost :: String
defhost = "127.0.0.1"

-- | The default TCP port to listen on. May be overridden with --port.
defport :: Int
defport = 5000

defbaseurl :: String -> Int -> String
defbaseurl host port =
  if ':' `elem` host
  then  -- ipv6 address
    "http://[" ++ host ++ "]" ++ if port /= 80 then ":" ++ show port else ""
  else
    "http://" ++ host ++ if port /= 80 then ":" ++ show port else ""

-- Static file settings. Changing these requires a recompile.

-- | The file path on your machine where static files can be found.
-- StaticFiles.hs uses this (must be separate for TH reasons).
staticDir :: FilePath
staticDir = "static"

-- | The base URL for static files. As you can see by the default
-- value, this can simply be "static" appended to your application root.
-- A powerful optimization can be serving static files from a separate
-- domain name. This allows you to use a web server optimized for static
-- files, more easily set expires and cache values, and avoid possibly
-- costly transference of cookies on static files.
--
-- If you change the resource pattern for StaticR in App.hs,
-- (or staticDir above), you will have to make a corresponding change here.
--
-- To see how this value is used, see urlRenderOverride in App.hs
--
-- XXX Does not respect --file-url #2139
staticRoot :: AppConfig DefaultEnv Extra -> Text
staticRoot conf = fromMaybe (appRoot conf <> "/static") . extraStaticRoot $ appExtra conf

-- | Make a type-safe URL for a file within the static directory,
-- given its path relative to that directory (using / separators).
-- Checks at compile time that the file exists.
staticFileRoute :: FilePath -> Q Exp
staticFileRoute f = do
  let path = staticDir </> f
  exists <- runIO $ doesFileExist path
  unless exists . fail $ "staticFileRoute: " ++ path ++ " not found"
  [| WaiSubsiteRoute (T.splitOn (T.singleton '/') (T.pack f)) [] |]

-- | Settings for 'widgetFile', such as which template languages to support and
-- default Hamlet settings.
widgetFileSettings :: WidgetFileSettings
widgetFileSettings = def
    { wfsHamletSettings = defaultHamletSettings
        { hamletNewlines = AlwaysNewlines
        }
    }

-- The rest of this file contains settings which rarely need changing by a
-- user.

widgetFile :: String -> Q Exp
widgetFile = (if development then widgetFileReload
                             else widgetFileNoReload)
              widgetFileSettings

data Extra = Extra
    { extraCopyright  :: Text
    , extraAnalytics  :: Maybe Text -- ^ Google Analytics
    , extraStaticRoot :: Maybe Text
    } deriving Show

parseExtra :: DefaultEnv -> Object -> Parser Extra
parseExtra _ o = Extra
    <$> o .:  "copyright"
    <*> o .:? "analytics"
    <*> o .:? "staticRoot"
