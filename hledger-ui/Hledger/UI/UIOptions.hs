{-# LANGUAGE CPP #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.UI.UIOptions where

import Data.Default (def)
import Data.Either (fromRight)
import Data.List (intercalate)
import Data.Map qualified as M
import Data.Maybe (fromMaybe)
import GitHash (tGitInfoCwdTry)
import Lens.Micro (set)
import System.Environment (getArgs)

import Hledger.Cli hiding (packageversion, progname, prognameandversion)
import Hledger.UI.Theme (themes, themeNames)

-- cf Hledger.Cli.Version

packageversion :: PackageVersionString
packageversion =
#ifdef VERSION
  VERSION
#else
  ""
#endif

progname :: ProgramName
progname = "hledger-ui"

-- | Generate the version string for this program.
-- The template haskell call is here rather than in Hledger.Cli.Version to avoid wasteful recompilation.
prognameandversion :: String
prognameandversion =
  versionStringWith
  $$tGitInfoCwdTry
#ifdef GHCDEBUG
  True
#else
  False
#endif
  progname
  packageversion

binaryinfo :: HledgerBinaryInfo
binaryinfo = fromRight nullbinaryinfo $ parseHledgerVersion prognameandversion


uiflags = [
   flagNone ["watch","w"] (setboolopt "watch") "watch for data and date changes and reload automatically (default)"
  ,flagNone ["no-watch"] (setboolopt "no-watch") "don't watch; reload only with the g key"
  ,flagReq  ["theme"] (\s opts -> Right $ setopt "theme" s opts) "THEME" ("use this custom display theme ("++intercalate ", " themeNames++")")
  ,flagNone ["cash"] (setboolopt "cash") "start in: the cash accounts screen"
  ,flagNone ["bs"] (setboolopt "bs") "start in: the balance sheet accounts screen"
  ,flagNone ["is"] (setboolopt "is") "start in: the income statement accounts screen"
  ,flagNone ["all"] (setboolopt "all") "start in: the all accounts screen"
  ,flagReq  ["register"] (\s opts -> Right $ setopt "register" s opts) "ACCTREGEX" "start in: the (first matched) account's register"
  ,flagNone ["change"] (setboolopt "change")
    "show period balances (changes) at startup instead of historical balances"
  -- ,flagNone ["cumulative"] (setboolopt "cumulative")
  --   "show balance change accumulated across periods (in multicolumn reports)"
  -- ,flagNone ["historical","H"] (setboolopt "historical")
  --   "show historical ending balance in each period (includes postings before report start date)\n "
  ]
  ++ flattreeflags False
--  ,flagNone ["present"] (setboolopt "present") "exclude transactions dated later than today (default)"
  -- ,flagReq ["drop"] (\s opts -> Right $ setopt "drop" s opts) "N" "with --flat, omit this many leading account name components"
  -- ,flagReq  ["format"] (\s opts -> Right $ setopt "format" s opts) "FORMATSTR" "use this custom line format"
  -- ,flagNone ["no-elide"] (setboolopt "no-elide") "don't compress empty parent accounts on one line"

--uimode :: Mode RawOpts
uimode =
  (mode "hledger-ui" (setopt "command" "ui" def)
    "browse accounts, postings and entries in a full-window TUI"
    (argsFlag "[--cash|--bs|--is|--all|--register=ACCT] [QUERY]") [])
  {modeGroupFlags = Group {
       groupUnnamed = uiflags
      ,groupHidden = hiddenflags
        ++
        [flagNone ["future"] (setboolopt "forecast") "old flag, use --forecast instead"
        ,flagNone ["menu"] (setboolopt "menu") "old flag, menu screen is now the default"
        ]
      ,groupNamed = mkgeneralflagsgroups1 helpflags
      }
  ,modeHelpSuffix=[
    -- "Reads your ~/.hledger.journal file, or another specified by $LEDGER_FILE or -f, and starts the full-window TUI."
  ]
  }

-- hledger-ui options, used in hledger-ui and above
data UIOpts = UIOpts
  { uoWatch    :: Bool
  , uoTheme    :: Maybe String
  , uoRegister :: Maybe String
  , uoCliOpts  :: CliOpts
  } deriving (Show)

defuiopts = UIOpts
  { uoWatch    = True
  , uoTheme    = Nothing
  , uoRegister = Nothing
  , uoCliOpts  = defcliopts
  }

-- | Process a RawOpts into a UIOpts.
-- An invalid --theme name will raise an error.
rawOptsToUIOpts :: RawOpts -> IO UIOpts
rawOptsToUIOpts rawopts = do
  cliopts <- set balanceaccum accum <$> rawOptsToCliOpts rawopts
  return
    defuiopts {
       uoWatch    = fromMaybe True $ choiceopt watchflag rawopts
      ,uoTheme    = checkTheme <$> maybestringopt "theme" rawopts
      ,uoRegister = maybestringopt "register" rawopts
      ,uoCliOpts  = cliopts
      }
  where
    -- watch mode is enabled by default; the rightmost --watch/--no-watch flag wins
    watchflag "watch"    = Just True
    watchflag "no-watch" = Just False
    watchflag _          = Nothing
    -- show historical balance by default (unlike hledger)
    accum = fromMaybe Historical $ balanceAccumulationOverride rawopts
    checkTheme t = let t' = if t == "default" then "light" else t  -- "default" is a deprecated alias for "light"
                   in if t' `M.member` themes then t' else usageError $ "invalid theme name: " ++ t

-- XXX some refactoring seems due
getHledgerUIOpts :: IO UIOpts
--getHledgerUIOpts = processArgs uimode >>= return >>= rawOptsToUIOpts
getHledgerUIOpts = do
  args <- getArgs >>= expandArgsAt
  let args' = ensureDebugFlagHasVal $ replaceNumericFlags args
  let cmdargopts = either usageError id $ process uimode args'
  rawOptsToUIOpts cmdargopts

instance HasCliOpts UIOpts where
    cliOpts f uiopts = (\x -> uiopts{uoCliOpts=x}) <$> f (uoCliOpts uiopts)

instance HasInputOpts UIOpts where
    inputOpts = cliOpts.inputOpts

instance HasBalancingOpts UIOpts where
    balancingOpts = cliOpts.balancingOpts

instance HasReportSpec UIOpts where
    reportSpec = cliOpts.reportSpec

instance HasReportOptsNoUpdate UIOpts where
    reportOptsNoUpdate = cliOpts.reportOptsNoUpdate

instance HasReportOpts UIOpts where
    reportOpts = cliOpts.reportOpts
