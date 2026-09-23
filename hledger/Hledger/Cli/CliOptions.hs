{-|

Common cmdargs modes and flags, a command-line options type, and
related utilities used by hledger commands.

-}

{-# LANGUAGE CPP                 #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE PackageImports      #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}
{-# LANGUAGE NamedFieldPuns #-}

module Hledger.Cli.CliOptions (
  progname,
  prognameandversion,
  prognameandversionnoarch,
  binaryinfo,

  -- * cmdargs flags & modes
  inputflags,
  reportflags,
  helpflags,
  terminalflags,
  helpflagstitle,
  flattreeflags,
  confflags,
  hiddenflags,
  hiddenflagsformainmode,
  -- outputflags,
  outputFormatFlag,
  outputFileFlag,
  generalflagsgroup1,
  generalflagsgroup2,
  generalflagsgroup3,
  mkgeneralflagsgroups1,
  mkgeneralflagsgroups2,
  mkgeneralflagsgroups3,
  cligeneralflagsgroups1,
  cligeneralflagsgroups2,
  cligeneralflagsgroups3,
  defMode,
  defCommandMode,
  addonCommandMode,
  hledgerCommandMode,
  argsFlag,
  showModeUsage,
  withAliases,
  likelyExecutablesInPath,

  -- * CLI options
  CliOpts(..),
  HasCliOpts(..),
  defcliopts,
  getHledgerCliOpts,
  getHledgerCliOpts',
  rawOptsToCliOpts,
  generalRawOpts,
  insertRawOpts,
  cliOptsDropArgs,
  journalCreatingCommandNames,
  journalIgnoringCommandNames,
  argsMarkRunCommands,
  runCommandsMarker,
  outputFormats,
  defaultOutputFormat,
  CommandHelpStr,
  parseCommandHelp,

  -- possibly these should move into argsToCliOpts
  -- * CLI option accessors
  -- | These do the extra processing required for some options.
  journalFilePathFromOpts,
  journalFilePathFromOptsNoDefault,
  rulesFilePathFromOpts,
  outputFileFromOpts,
  outputFormatFromOpts,
  defaultWidth,
  replaceNumericFlags,
  ensureDebugFlagHasVal,
  -- | For register:
  registerWidthsFromOpts,

  -- * Other utils
  topicForMode,
  DeclarablesSelector(..),
  declarablesSelectorFromOpts,
  findMatchedByArgument,

--  -- * Convenience re-exports
--  module Data.String.Here,
--  module System.Console.CmdArgs.Explicit,
)
where

import Control.Exception qualified as C
import Control.Monad (when)
import Data.Char
import Data.Default
import Data.List.Extra (intercalate, nubSort)
import Data.List.NonEmpty qualified as NE (NonEmpty, fromList, nonEmpty)
import Data.List.Split (splitOn)
import Data.Maybe
--import Data.String.Here
-- import Data.Text (Text)
import Data.Text qualified as T
import Data.Void (Void)
import GitHash (tGitInfoCwdTry)
import Safe
import String.ANSI
import System.Console.CmdArgs hiding (Default,def)
import System.Console.CmdArgs.Explicit
import System.Console.CmdArgs.Text
import System.Directory
import System.Environment
import System.Exit (exitSuccess)
import System.FilePath
import System.Info (os)
import Text.Megaparsec
import Text.Megaparsec.Char

import Hledger.Utils.I18n (translationsForLangOption)
import Hledger
import Hledger.Cli.DocFiles
import Hledger.Cli.Version
import Data.Time.Clock.POSIX (POSIXTime)
import Data.List (dropWhileEnd, find, isPrefixOf, isSuffixOf)
import Data.Function ((&))


-- | The name of this program's executable.
progname :: ProgramName
progname = "hledger"

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

-- | Just the program name and version, without the machine architecture.
prognameandversionnoarch :: String
prognameandversionnoarch = takeWhile (/= ',') prognameandversion

binaryinfo :: HledgerBinaryInfo
Right binaryinfo = parseHledgerVersion prognameandversion
-- ui and web use nullbinaryinfo for a parse failure here to silence an inexhaustive pattern warning.
-- I can't reproduce that warning right now, so here I've stuck with the original approach,
-- which will force a compile error if prognameandversion is ever malformed, eg from unexpected
-- git output.

-- Common options.
-- keep synced: the docs macro in doc/common.m4

-- | Common input-related flags: --file, --rules, --conf, --alias...
inputflags :: [Flag RawOpts]
inputflags = [
   flagReq  ["file","f"]      (\s opts -> Right $ setopt "file" s opts) "[FMT:]FILE" $ unwords [
     "Use this as the journal file (- means stdin)."
    ,"If not specified, $LEDGER_FILE or ~/.hledger.journal will be used."
    ,"If specified more than once, the files will be read in order."
    ,"Each file's format (journal, csv, timeclock, timedot, rules..) is inferred from the file extension or a FMT: prefix."
    ,"Some commands (add, import) write to the (first) file,"
    ,"and expect it to be in journal format."
    ]
  ,flagReq  ["rules"]         (\s opts -> Right $ setopt "rules" s opts) "RULESFILE" "Use rules defined in this rules file for converting subsequent CSV/SSV/TSV files. If not specified, uses FILE.csv.rules for each FILE.csv."  -- see also hiddenflags

  ,flagReq  ["alias"]         (\s opts -> Right $ setopt "alias" s opts)  "A=B|/RGX/=RPL" "transform account names from A to B, or by replacing regular expression matches"
  ,flagNone ["auto"]          (setboolopt "auto") "generate extra postings by applying auto posting rules (\"=\") to all transactions"
  ,flagOpt "" ["forecast"]    (\s opts -> Right $ setopt "forecast" s opts) "PERIOD" (unwords
    [ "Generate extra transactions from periodic rules (\"~\"),"
    , "from after the latest ordinary transaction until 6 months from now. Or, during the specified PERIOD (the equals is required)."
    , "Auto posting rules will also be applied to these transactions."
    , "In hledger-ui, also make future-dated transactions visible at startup."
    ])
  ,flagNone ["ignore-assertions"] (setboolopt "ignore-assertions") "don't check balance assertions by default"
  ,flagNone ["ignore-lots"]       (setboolopt "ignore-lots")       "don't do lot tracking or checking by default"
  ,flagNone ["I"]                 (setboolopt "ignore-assertions" . setboolopt "ignore-lots")
                                  "shortcut for --ignore-assertions --ignore-lots"
  ,flagReq  ["txn-balancing"] (\s opts -> Right $ setopt "txn-balancing" s opts) "..." (unlines [
     "how to check that transactions are balanced:"
    ,"'old':   - use global display precision"
    ,"'exact': - use transaction precision (default)"
    ])
  ,flagNone ["infer-costs"] (setboolopt "infer-costs") "infer costs from conversion equity postings"
  ,flagNone ["infer-equity"] (setboolopt "infer-equity") "infer conversion equity postings from costs"
  -- history of this flag so far, lest we be confused:
  --  originally --infer-value
  --  2021-02 --infer-market-price added, --infer-value deprecated
  --  2021-09
  --   --infer-value hidden
  --   --infer-market-price renamed to --infer-market-prices, old spelling still works
  --   ReportOptions{infer_value_} renamed to infer_prices_, BalancingOpts{infer_prices_} renamed to infer_transaction_prices_
  --   some related prices command changes
  --    --costs deprecated and hidden, uses --infer-market-prices instead
  --    --inverted-costs renamed to --infer-reverse-prices
  ,flagNone ["infer-market-prices"] (setboolopt "infer-market-prices") "infer market prices from costs"
  ,flagReq  ["pivot"]         (\s opts -> Right $ setopt "pivot" s opts)  "TAGNAME" "use a different field or tag as account names"
  ,flagNone ["strict","s"]    (setboolopt "strict") "do extra error checks (and override -I)"
  ]

-- | Common report-related flags: --period, --cost, etc.
reportflags :: [Flag RawOpts]
reportflags = [

  -- report period, interval, dates
  flagReq  ["begin","b"]     (\s opts -> Right $ setopt "begin" s opts) "DATE" "include postings/transactions on/after this date"
 ,flagReq  ["end","e"]       (\s opts -> Right $ setopt "end" s opts) "DATE" "include postings/transactions before this date (with a report interval, will be adjusted to following subperiod end)"
 ,flagNone ["daily","D"]     (setboolopt "daily")     "set report interval: 1 day"
 ,flagNone ["weekly","W"]    (setboolopt "weekly")    "set report interval: 1 week"
 ,flagNone ["monthly","M"]   (setboolopt "monthly")   "set report interval: 1 month"
 ,flagNone ["quarterly","Q"] (setboolopt "quarterly") "set report interval: 1 quarter"
 ,flagNone ["yearly","Y"]    (setboolopt "yearly")    "set report interval: 1 year"
 ,flagReq  ["period","p"]    (\s opts -> Right $ setopt "period" s opts) "PERIODEXP" "set begin date, end date, and/or report interval, with more flexibility"
 ,flagReq  ["today"]         (\s opts -> Right $ setopt "today" s opts) "DATE" "override today's date (affects relative dates)"
 ,flagNone ["date2"]         (setboolopt "date2") "match/use secondary dates instead (deprecated)"  -- see also hiddenflags

  -- status/realness/zero/depth filters
 ,flagNone ["unmarked","U"]  (setboolopt "unmarked") "include only unmarked postings/transactions"
 ,flagNone ["pending","P"]   (setboolopt "pending")  "include only pending postings/transactions"
 ,flagNone ["cleared","C"]   (setboolopt "cleared")  "include only cleared postings/transactions\n(-U/-P/-C can be combined)"
 ,flagNone ["real","R"]      (setboolopt "real")     "include only non-virtual postings"
 ,flagNone ["empty","E"]     (setboolopt "empty") "Show zero items, which are normally hidden.\nIn hledger-ui & hledger-web, do the opposite."
 ,flagReq  ["depth"]         (\s opts -> Right $ setopt "depth" s opts) "DEPTHEXP" "if a number (or -NUM): show only top NUM levels of accounts. If REGEXP=NUM, only apply limiting to accounts matching the regular expression."

  -- valuation
 ,flagNone ["B","cost"]      (setboolopt "B") "convert amounts to their cost basis ({}), or else their cost/sale amount (@/@@)"
    -- ^ no "valuation mode:" prefix for this one, it's not mutually exclusive
 ,flagNone ["V","market"]    (setboolopt "V")
    (unwords
      [valuationprefix ++ "show amounts converted to market value at period end(s) in their default valuation commodity."
      ,"Short for --value=end."
      ])
 ,flagReq ["X","exchange"]   (\s opts -> Right $ setopt "X" s opts) "COMM"
    (unwords
      [valuationprefix ++ "show amounts converted to market value at period end(s) in the specified commodity."
      ,"Short for --value=end,COMM."
      ])
 ,flagReq  ["value"]         (\s opts -> Right $ setopt "value" s opts) "WHEN[,COMM]"
    (unlines
      [valuationprefix ++ "show amounts converted to market value on the specified date(s) in their default valuation commodity or a specified commodity. WHEN can be:"
      ,"'then':     value on transaction dates"
      ,"'end':      value at period end(s)"
      ,"'now':      value today"
      ,"YYYY-MM-DD: value on given date"
      ,"'cost':     cost basis, or else transacted cost (same as -B)"
      ,"'transacted': transacted cost/sale amount (@/@@) only"
      ])

  -- display
 ,flagNone ["lots"] (setboolopt "lots") "show lot subaccounts and other lot details"
 ,flagReq ["commodity-style", "c"] (\s opts -> Right $ setopt "commodity-style" s opts) "S"
    "Override a commodity's display style.\nEg: -c '$1000.' or -c '1.000,00 EUR'"
 ,flagOpt "yes" ["pretty"] (\s opts -> Right $ setopt "pretty" s opts) "YN"
    "Use box-drawing characters in text output? The optional 'y'/'yes' or 'n'/'no' arg requires =."
 ,flagReq ["title"] (\s opts -> Right $ setopt "title" s opts) "T"
    "set or customise a report title"
 ,flagReq ["subreport-titles"] (\s opts -> Right $ setopt "subreport-titles" s opts) "TS"
    "customise subreport headings in compound reports (|-separated)"
 ,flagReq ["period-titles"] (\s opts -> Right $ setopt "period-titles" s opts) "OPT" $ unlines
    ["customise headings in periodic reports:"
    ,"'compact': readable period names when possible"
    ,"'dates':   exact dates/date ranges always"
    ]
 ]
  where
    valuationprefix = "valuation mode: "

helpflags :: [Flag RawOpts]
helpflags = [
  flagNone ["?"]        (setboolopt "quickref") "show the hledger quick reference"
 ,flagNone ["help","h"] (setboolopt "help")    "show this command's usage help"
 ,flagNone ["info"]     (setboolopt "info")    "show this command's manual with info"
 ,flagNone ["man"]      (setboolopt "man")     "show this command's manual with man"
 ,flagNone ["webman"]   (setboolopt "webman")  "show this command's manual on the web"
 ,flagNone ["examples"] (setboolopt "examples") "show examples for this command"
 ,flagNone ["version"]  (setboolopt "version") "show version information"
  -- flagOpt would be more correct for --debug, showing --debug[=LVL] rather than --debug=[LVL] in help.
  -- But flagReq plus special handling in Cli.hs makes the = optional, removing a source of confusion.
 ,flagReq  ["debug"]    (\s opts -> Right $ setopt "debug" s opts) "[1-9]" "show this much debug output (default: 1)"
 ] -- XXX why are these duplicated in defCommandMode below ?
 <> terminalflags

-- Low-level flags affecting terminal output.
-- These are included in helpflags so they appear everywhere.
terminalflags = [
  flagReq  ["pager"] (\s opts -> Right $ setopt "pager" s opts) "YN"
   "use a pager when needed ? y/yes (default) or n/no"

  -- keep synced with hledger-lib:colorOption:
 ,flagReq  ["color","colour"] (\s opts -> Right $ setopt "color" s opts) "YNA"
   "use ANSI color ? y/yes, n/no, or auto (default)"
 ,flagReq  ["lang"] (\s opts -> Right $ setopt "lang" s opts) "LANG"
   "language for report titles and headings: a language tag like de, auto (from the environment), or en (default)"
 ]

-- | Flags for selecting flat/tree mode, used for reports organised by account.
-- With a True argument, shows some extra help about inclusive/exclusive amounts.
flattreeflags :: Bool -> [Flag RawOpts]
flattreeflags showamounthelp = [
   flagNone ["flat","l"] (setboolopt "flat")
     (prefix ++ "show accounts as a flat list (default)"
      ++ if showamounthelp then ". Amounts exclude subaccount amounts, except where the account is depth-clipped." else "")
  ,flagNone ["tree","t"] (setboolopt "tree")
    (prefix ++ "show accounts as a tree" ++ if showamounthelp then ". Amounts include subaccount amounts." else "")
  ]
  where
    prefix = "list/tree mode: "

-- | hledger CLI's --conf/--no-conf flags.
confflags = [
   flagReq ["conf"] (\s opts -> Right $ setopt "conf" s opts) "CONFFILE"
      "Use extra options defined in this config file. If not specified, searches upward and in XDG config dir for hledger.conf (or .hledger.conf in $HOME)."
  ,flagNone ["no-conf","n"] (setboolopt "no-conf") "ignore any config file"
  ]

-- | Common legacy flags that are accepted but not shown in --help, when running the main mode.
hiddenflagsformainmode :: [Flag RawOpts]
hiddenflagsformainmode = [
   flagNone ["effective","aux-date"] (setboolopt "date2") "Ledger-compatible aliases for --date2"
  ,flagNone ["infer-value"]          (setboolopt "infer-market-prices") "legacy flag that was renamed"
  ,flagNone ["pretty-tables"]        (setopt "pretty" "always") "legacy flag that was renamed"
  ,flagNone ["anon"]                 (setboolopt "anon") "deprecated, renamed to --obfuscate"  -- #2133, handled by anonymiseByOpts
  ,flagNone ["obfuscate"]            (setboolopt "obfuscate") "slightly obfuscate hledger's output. Warning, does not give privacy. Formerly --anon."  -- #2133, handled by maybeObfuscate
  ,flagNone ["old-timeclock", "timeclock-old"] (setboolopt "oldtimeclock") "don't pair timeclock entries by account name"
  ,flagNone ["old-glob"]             (setboolopt "oldglob") "deprecated, no longer used as of 1.50.4"  -- #2498
  ,flagReq  ["rules-file"]           (\s opts -> Right $ setopt "rules" s opts) "RULESFILE" "was renamed to --rules"
  ]

-- Hidden flags accepted but not shown, when running subcommand or addon command modes.
-- Here we add the confflags, so their presence won't cause an error,
hiddenflags :: [Flag RawOpts]
hiddenflags = hiddenflagsformainmode ++ confflags

-- | Common output-related flags: --output-file, --output-format...

-- outputflags = [outputFormatFlag, outputFileFlag]

outputFormatFlag :: [String] -> Flag RawOpts
outputFormatFlag fmts = flagReq
  ["output-format","O"] (\s opts -> Right $ setopt "output-format" s opts) "FMT"
  ("select the output format. Supported formats:\n" ++ intercalate ", " fmts ++ ".")

-- This has special support in hledger-lib:outputFileOption, keep synced
outputFileFlag :: Flag RawOpts
outputFileFlag = flagReq
  ["output-file","o"] (\s opts -> Right $ setopt "output-file" s opts) "FILE"
  "write output to FILE. A file extension matching one of the above formats selects that format."

argsFlag :: FlagHelp -> Arg RawOpts
argsFlag = flagArg (\s opts -> Right $ setopt "args" s opts)

generalflagstitle :: String
generalflagstitle = "\nGeneral flags"

-- Several subsets of the standard general flags, as a single list. Old API used by some addons.
generalflagsgroup1, generalflagsgroup2, generalflagsgroup3 :: (String, [Flag RawOpts])
generalflagsgroup1 = (generalflagstitle, inputflags ++ reportflags ++ helpflags)
generalflagsgroup2 = (generalflagstitle, inputflags ++ helpflags)
generalflagsgroup3 = (generalflagstitle, helpflags)

-- Helpers to make several subsets of the standard general flags, in separate groups. The help flags are parameterised. 2024.
mkgeneralflagsgroups1, mkgeneralflagsgroups2, mkgeneralflagsgroups3 :: [Flag RawOpts] -> [(String, [Flag RawOpts])]
mkgeneralflagsgroups1 helpflags' = [
   (inputflagstitle,  inputflags)
  ,(outputflagstitle, reportflags)
  ,(helpflagstitle,   helpflags')
  ]
mkgeneralflagsgroups2 helpflags' = [
   (inputflagstitle, inputflags)
  ,(helpflagstitle, helpflags')
  ]
mkgeneralflagsgroups3 helpflags' = [
   (helpflagstitle, helpflags')
  ]

inputflagstitle  = "\nGeneral input flags"
outputflagstitle = "\nGeneral output flags (affecting some commands)"
helpflagstitle   = "\nGeneral help flags"

-- Several subsets of the standard general flags plus CLI help flags, as separate groups.
cligeneralflagsgroups1, cligeneralflagsgroups2, cligeneralflagsgroups3 :: [(String, [Flag RawOpts])]
cligeneralflagsgroups1 = mkgeneralflagsgroups1 helpflags
cligeneralflagsgroups2 = mkgeneralflagsgroups2 helpflags
cligeneralflagsgroups3 = mkgeneralflagsgroups3 helpflags


-- cmdargs mode constructors

-- | An empty cmdargs mode to use as a template.
-- Modes describe the top-level command, ie the program, or a subcommand,
-- telling cmdargs how to parse a command line and how to
-- generate the command's usage text.
defMode :: Mode RawOpts
defMode = Mode {
  modeNames       = []            -- program/command name(s)
 ,modeHelp        = ""            -- short help for this command
 ,modeHelpSuffix  = []            -- text displayed after the usage
 ,modeGroupFlags  = Group {       -- description of flags accepted by the command
    groupNamed   = []             --  named groups of flags
   ,groupUnnamed = []             --  ungrouped flags
   ,groupHidden  = []             --  flags not displayed in the usage
   }
 ,modeArgs        = ([], Nothing) -- description of arguments accepted by the command
 ,modeValue       = def           -- value returned when this mode is used to parse a command line
 ,modeCheck       = Right         -- whether the mode's value is correct
 ,modeReform      = const Nothing -- function to convert the value back to a command line arguments
 ,modeExpandAt    = True          -- expand @ arguments for program ?
 ,modeGroupModes  = toGroup []    -- sub-modes
 }

-- | A cmdargs mode suitable for a hledger built-in command
-- with the given names (primary name + optional aliases).
-- The usage message shows [QUERY] as argument.
defCommandMode :: [Name] -> Mode RawOpts
defCommandMode names = defMode {
   modeNames=names
  ,modeGroupFlags  = Group {
     groupNamed   = []
    ,groupUnnamed = [
        flagNone ["help"] (setboolopt "help") "show command-line help"
       ,flagNone ["man"]  (setboolopt "man")  "show this program's user manual with man"
       ,flagNone ["info"] (setboolopt "info") "show this program's user manual with info"
      ]
    ,groupHidden  = []             --  flags not displayed in the usage
    }
  ,modeArgs = ([], Just $ argsFlag "[QUERY]")
  ,modeValue=setopt "command" (headDef "" names) def
  }

-- | A cmdargs mode representing the hledger add-on command with the
-- given name, providing hledger's common input/reporting/help flags.
-- Just used when invoking addons.
addonCommandMode :: Name -> Mode RawOpts
addonCommandMode nam = (defCommandMode [nam]) {
   modeHelp = ""
     -- XXX not needed ?
     -- fromMaybe "" $ lookup (stripAddonExtension name) [
     --   ("addon"        , "dummy add-on command for testing")
     --  ,("addon2"       , "dummy add-on command for testing")
     --  ,("addon3"       , "dummy add-on command for testing")
     --  ,("addon4"       , "dummy add-on command for testing")
     --  ,("addon5"       , "dummy add-on command for testing")
     --  ,("addon6"       , "dummy add-on command for testing")
     --  ,("addon7"       , "dummy add-on command for testing")
     --  ,("addon8"       , "dummy add-on command for testing")
     --  ,("addon9"       , "dummy add-on command for testing")
     --  ]
  ,modeGroupFlags = Group {
      groupUnnamed = []
     ,groupHidden  = hiddenflags
     ,groupNamed   = cligeneralflagsgroups1
     }
  }

-- | A command's name, optional official abbreviation, and help preamble & postamble,
-- as a specially formatted single string. Used to generate the CLI help, and also
-- the command's doc in the hledger manual. See parseCommandHelp for the format.
type CommandHelpStr = String

-- | A command's documentation. Used both as part of CLI help, and as
-- part of the hledger manual. See parseCommandHelpStr.
data CommandHelp = CommandHelp {
   cmdName           :: Name        -- the official command name
  ,mcmdShortName     :: Maybe Name  -- optional official name abbreviation
  ,cmdHelpPreamble   :: String      -- help preamble, shown before flags help
  ,cmdHelpPostamble ::  String      -- help postamble, shown after flags help
} deriving (Show)

-- | Build a cmdarg mode for a hledger command,
-- from a help template and flag/argument specifications.
-- Reduces boilerplate a little, though the complicated cmdargs
-- flag and argument specs are still required.
hledgerCommandMode :: CommandHelpStr -> [Flag RawOpts] -> [(String, [Flag RawOpts])]
  -> [Flag RawOpts] -> ([Arg RawOpts], Maybe (Arg RawOpts)) -> Mode RawOpts
hledgerCommandMode helpstr unnamedflaggroup namedflaggroups hiddenflaggroup argsdescr =
  case parseCommandHelp helpstr of
    Nothing -> error' $ "could not parse command doc:\n"++helpstr++"\n"  -- PARTIAL:
    Just CommandHelp{cmdName, mcmdShortName, cmdHelpPreamble, cmdHelpPostamble} ->
      (defCommandMode $ cmdName : maybeToList mcmdShortName) {
         modeHelp        = cmdHelpPreamble
        ,modeHelpSuffix  = lines cmdHelpPostamble
        ,modeGroupFlags  = Group {
            groupUnnamed = unnamedflaggroup
           ,groupNamed   = namedflaggroups
           ,groupHidden  = hiddenflaggroup
           }
        ,modeArgs        = argsdescr
        }

-- | Parse a command's embedded help text (@Somecommand.txt@).
-- That text is generated by @Shake cmdhelp@ from the command's doc source (@Somecommand.md@).
-- @Somecommand.md@ should be formatted as follows:
--
-- - First line: the command name, as a markdown heading.
--
-- - Optional third line: the command's official abbreviated name, parenthesised.
--
-- - From third or fifth line to a @```flags@ line: the command help preamble.
--   Usually one sentence or paragraph; any blank lines will not be rendered.
--
-- - A fenced code block beginning with @```flags@, containing a @Flags:@ line,
--   followed by a snapshot of the command-specific flags help as generated by cmdargs
--   or "none" if there are no command-specific flags.
--   This should contain no blank lines (no extra newlines in the cmdargs command mode help strings).
--   This is shown as-is in manuals, and regenerated at runtime for --help output.
--
-- - Any remaining lines: the command help postamble.
--
-- (Note the difference between
-- @Somecommand.md@, which is the markdown source file, and
-- @Somecommand.txt@, which is the plain text file generated by @Shake cmdhelp@,
-- which this function parses.)
--
parseCommandHelp :: CommandHelpStr -> Maybe CommandHelp
parseCommandHelp t =
  case lines t of
    [] -> Nothing
    (l1:_:l3raw:ls) -> Just $ CommandHelp cmdname (if null cmdalias then Nothing else Just cmdalias) preamble postamble
      where
        cmdname = l1
        -- pandoc's plain writer appends a trailing space after a single-character
        -- parenthetical (eg "(h) "), so strip trailing whitespace before matching.
        l3 = dropWhileEnd isSpace l3raw
        (cmdalias, rest) =
          if "(" `isPrefixOf` l3 && ")" `isSuffixOf` l3
          then (drop 1 $ init l3, ls)
          else ([], l3raw:ls)
        (preamblels, rest2) = break (== "Flags:") $ dropWhile null rest
        postamblels = dropWhile null $ dropWhile (not.null) rest2
        preamble = unlines $ reverse $ dropWhile null $ reverse preamblels
        postamble = unlines postamblels
    _ -> Nothing  -- error' "misformatted command help text file"

-- | Get a mode's usage message as a nicely wrapped string.
showModeUsage :: Mode a -> String
showModeUsage =
  highlightHelp .
  (showText defaultWrap :: [Text] -> String) .
  (helpText [] HelpFormatDefault :: Mode a -> [Text])

-- | Add some ANSI decoration to cmdargs' help output.
highlightHelp
  | not useColorOnStdoutUnsafe = id   -- XXX unsafe boldening help headings - seems to work, even respecting config file
  | otherwise = unlines . zipWith (curry f) [1..] . lines
  where
    f (n,l)
      | n==1 = bold l
      | isHelpHeading l = bold l
      | otherwise = l
    -- keep synced with Hledger.Cli.mainmode:
    isHelpHeading l = isAlphaNum (headDef ' ' l) && (lastDef ' ' l == ':')
      -- any s (`isPrefixOf` s) [
      --    "General input flags"
      --   ,"General reporting flags"
      --   ,"General help flags"
      --   ,"Flags"
      --   ,"General flags"
      --   ,"Examples"
      --   ]
-- | Get the most appropriate documentation topic for a mode.
-- Currently, that is either the hledger, hledger-ui or hledger-web
-- manual.
topicForMode :: Mode a -> Topic
topicForMode m
  | n == "hledger-ui"  = "ui"
  | n == "hledger-web" = "web"
  | otherwise          = "cli"
  where n = headDef "" $ modeNames m

-- | Add command aliases to the command's help string.
withAliases :: String -> [String] -> String
s `withAliases` []     = s
s `withAliases` as = s ++ " (" ++ intercalate ", " as ++ ")"
-- s `withAliases` (a:[]) = s ++ " (alias: " ++ a ++ ")"
-- s `withAliases` as     = s ++ " (aliases: " ++ intercalate ", " as ++ ")"


-- CliOpts

-- | Command line options, used in the @hledger@ package and above.
-- This is the \"opts\" used throughout hledger CLI code.
-- representing the options and arguments that were provided at
-- startup on the command-line.
data CliOpts = CliOpts {
     rawopts_         :: RawOpts
    ,command_         :: String
    ,file_            :: [FilePath]
    ,inputopts_       :: InputOpts
    ,reportspec_      :: ReportSpec
    ,output_file_     :: Maybe FilePath
    ,output_format_   :: Maybe String
    ,pageropt_        :: Maybe Bool     -- ^ --pager
    ,coloropt_        :: Maybe YNA      -- ^ --color. Controls use of ANSI color and ANSI styles.
    ,debug_           :: Int            -- ^ debug level, set by @--debug[=N]@. See also 'Hledger.Utils.debugLevel'.
    ,no_new_accounts_ :: Bool           -- add
    ,width_           :: Maybe String   -- ^ the --width value provided, if any
    ,available_width_ :: Int            -- ^ estimated usable screen width, based on
                                        -- 1. the width reported by the terminal, if supported
                                        -- 2. the default (80)
    ,progstarttime_   :: POSIXTime      -- system POSIX time at start
 } deriving (Show)

instance Default CliOpts where def = defcliopts

defcliopts :: CliOpts
defcliopts = CliOpts
    { rawopts_         = def
    , command_         = ""
    , file_            = []
    , inputopts_       = definputopts
    , reportspec_      = def
    , output_file_     = Nothing
    , output_format_   = Nothing
    , pageropt_        = Nothing
    , coloropt_        = Nothing
    , debug_           = 0
    , no_new_accounts_ = False
    , width_           = Nothing
    , available_width_ = defaultWidth
    , progstarttime_   = 0
    }

-- | Default width for hledger console output, when not otherwise specified.
defaultWidth :: Int
defaultWidth = 80

-- | Replace any numeric flags (eg -2) with their long form (--depth 2),
-- as I'm guessing cmdargs doesn't support this directly.
replaceNumericFlags :: [String] -> [String]
replaceNumericFlags = map replace
  where
    replace ('-':ds) | not (null ds) && all isDigit ds = "--depth="++ds
    replace s = s

-- Convert a valueless --debug flag to one with a value.
-- See also the --debug flag definition in CliOptions.hs.
-- This makes an equals sign unnecessary with this optional-value flag.
ensureDebugFlagHasVal :: [String] -> [String]
ensureDebugFlagHasVal as = case break (=="--debug") as of
  (bs,"--debug":c:cs) | null c || not (all isDigit c) -> bs++"--debug=1" : ensureDebugFlagHasVal (c:cs)
  (bs,["--debug"])                                    -> bs++["--debug=1"]
  _                                                   -> as

-- | Parse raw option string values to the desired final data types.
-- Any relative smart dates will be converted to fixed dates based on
-- today's date. Parsing failures will raise an error.
-- Also records the terminal width, if supported.
rawOptsToCliOpts :: RawOpts -> IO CliOpts
rawOptsToCliOpts rawopts = do
  currentDay <- getCurrentDay
  let
    day = case maybestringopt "today" rawopts of
            Nothing -> currentDay
            Just d  -> either (const err) fromEFDay $ fixSmartDateStrEither' currentDay (T.pack d)
              where err = error' $ "Unable to parse date \"" ++ d ++ "\""
    command = stringopt "command" rawopts
  usecolor <- useColorOnStdout
  let iopts = rawOptsToInputOpts day usecolor rawopts
  rspec0 <- either error' pure $ rawOptsToReportSpec day usecolor rawopts  -- PARTIAL:
  trs <- translationsForLangOption $ maybestringopt "lang" rawopts
  let rspec = rspec0{_rsReportOpts = (_rsReportOpts rspec0){translations_ = trs}}
  mtermwidth <- getTerminalWidth
  let availablewidth = fromMaybe defaultWidth mtermwidth
  return defcliopts {
              rawopts_         = rawopts
             ,command_         = command
             ,file_            = listofstringopt "file" rawopts
             ,inputopts_       = iopts
             ,reportspec_      = rspec
             ,output_file_     = maybestringopt "output-file" rawopts
             ,output_format_   = maybestringopt "output-format" rawopts
             ,pageropt_        = maybeynopt "pager" rawopts
             ,coloropt_        = maybeynaopt "color" rawopts
             ,debug_           = posintopt "debug" rawopts
             ,no_new_accounts_ = boolopt "no-new-accounts" rawopts -- add
             ,width_           = maybestringopt "width" rawopts
             ,available_width_ = availablewidth
             }

-- | The names of the general flags that run/repl propagate to the commands they run:
-- all input, output/report, and terminal flags. Excludes --file (handled separately, as
-- the default journal) and the help-action flags (which just show help and exit).
propagatedGeneralFlagNames :: [String]
propagatedGeneralFlagNames =
  filter (`notElem` (["file","f"] ++ helpactionflags))
    $ concatMap flagNames (inputflags ++ reportflags ++ helpflags)
  where helpactionflags = ["quickref","help","h","examples","info","man","webman","version"]

-- | Extract the propagated general flags from these raw options, as a raw option
-- association list, for passing to run/repl subcommands.
generalRawOpts :: RawOpts -> [(String,String)]
generalRawOpts = collectopts $ \kv ->
  if fst kv `elem` propagatedGeneralFlagNames then Just kv else Nothing

-- | Prepend some extra raw options into a subcommand's options, as defaults that
-- the subcommand's own options take precedence over, recomputing the derived
-- CliOpts fields (inputopts_, file_, reportspec_..) so they stay consistent.
insertRawOpts :: [(String,String)] -> CliOpts -> IO CliOpts
insertRawOpts extraopts subopts = rawOptsToCliOpts $ overRawOpts (extraopts ++) (rawopts_ subopts)

-- | Drop the arguments ("args") from this CliOpts' rawopts field.
cliOptsDropArgs :: CliOpts -> CliOpts
cliOptsDropArgs copts@CliOpts{rawopts_} = copts{rawopts_ = dropRawOpt "args" rawopts_}

-- | Builtin commands that can operate on a nonexistent journal file, creating it
-- (add and import). These are dispatched specially, both at the CLI and in run/repl,
-- so a missing journal file is tolerated rather than an error.
journalCreatingCommandNames :: [String]
journalCreatingCommandNames = ["add","import"]

-- | Names of builtin commands which do not read the journal at all.
-- These are dispatched specially, both at the CLI and in run/repl, so they
-- never read or check the journal (help is handled by the CLI's help hub,
-- which also does not read the journal).
journalIgnoringCommandNames :: [String]
journalIgnoringCommandNames = ["help","setup","test"]

-- | The name of a hidden marker flag used internally by the run command to
-- recognise inline commands. run reads inline commands (rather than command
-- files) when its arguments contain a "--". But cmdargs consumes the first "--"
-- while parsing, so run can't detect it directly. Instead, before parsing we
-- insert this marker flag just before the first "--" (with 'argsMarkRunCommands');
-- cmdargs then parses it like any normal flag, leaving it in the options for run
-- to check. This replaces an older, more fragile workaround which duplicated the
-- first "--" so that one copy survived cmdargs.
runCommandsMarker :: String
runCommandsMarker = "_runcommands"

-- | If these arguments contain a "--" (run's inline-commands introducer), insert
-- the hidden 'runCommandsMarker' flag just before it, so the run command can tell
-- it was given inline commands rather than command files. See 'runCommandsMarker'.
argsMarkRunCommands :: [String] -> [String]
argsMarkRunCommands args'
  | "--" `elem` args' = let (as,bs) = break (=="--") args' in as <> ["--" <> runCommandsMarker] <> bs
  | otherwise = args'

-- | A helper for addon commands: this parses options and arguments from
-- the current command line using the given hledger-style cmdargs mode,
-- and returns a CliOpts. Or, with --help or -h present, it shows
-- the full help (in the pager if appropriate) and exits the program.
-- When --debug is present, also prints some debug output.
-- Note this is not used by the main hledger executable.
--
-- The full help is generated from the mode: the full usage description
-- generated by cmdargs (including all supported options), framed by whatever
-- pre- and postamble text the mode specifies. It's intended that this forms a
-- complete help document or manual. It's the same help shown by CMD -h at the
-- command line, keeping -h consistent everywhere (including in the repl).
--
-- Tips:
-- Empty lines in the pre/postamble are removed by cmdargs;
-- add a space character to preserve them.
--
getHledgerCliOpts' :: Mode RawOpts -> [String] -> IO CliOpts
getHledgerCliOpts' mode' args0 = do
  let rawopts = either usageError id $ process mode' args0
  opts <- rawOptsToCliOpts rawopts
  debugArgs args0 opts
  when (boolopt "help" $ rawopts_ opts) $ runPager longhelp >> exitSuccess
  return opts
  where
    longhelp = showModeUsage mode'
    -- A truncated help (preamble and usage up to the first "flags:" line, plus a
    -- pointer to the common options) was shown here before; disabled for now to
    -- keep -h showing the full help everywhere. To restore it, show this instead:
    -- shorthelp =
    --   unlines $
    --     (reverse $ dropWhile null $ reverse $ takeWhile (not . ("flags:" `isInfixOf`)) $ lines longhelp)
    --     ++ ["", "  See also hledger -h for general hledger options."]
    -- | Print debug info about arguments and options if --debug is present.
    -- XXX use standard dbg helpers
    debugArgs :: [String] -> CliOpts -> IO ()
    debugArgs args1 opts =
      when ("--debug" `elem` args1) $ do
        progname' <- getProgName
        putStrLn $ "running: " ++ progname'
        putStrLn $ "raw args: " ++ show args1
        putStrLn $ "processed opts:\n" ++ show opts
        putStrLn $ "search query: " ++ show (_rsQuery $ reportspec_ opts)

getHledgerCliOpts :: Mode RawOpts -> IO CliOpts
getHledgerCliOpts mode' = do
  args' <- getArgs >>= expandArgsAt
  getHledgerCliOpts' mode' args'

-- CliOpts accessors

-- | Get the (tilde-expanded, absolute) journal file path from
-- 1. options, 2. an environment variable, or 3. the default.
-- Actually, returns one or more file paths. There will be more
-- than one if multiple -f options were provided.
-- File paths can have a READER: prefix naming a reader/data format.
journalFilePathFromOpts :: CliOpts -> IO (NE.NonEmpty String)
journalFilePathFromOpts opts = do
  mbpaths <- journalFilePathFromOptsNoDefault opts
  case mbpaths of
    Just paths -> return paths
    Nothing -> do
      f <- defaultExistingJournalPath
      return $ NE.fromList [f]

-- | Like journalFilePathFromOpts, but does not use defaultJournalPath
journalFilePathFromOptsNoDefault :: CliOpts -> IO (Maybe (NE.NonEmpty String))
journalFilePathFromOptsNoDefault opts = do
  d <- getCurrentDirectory
  case NE.nonEmpty $ file_ opts of
    Nothing -> return Nothing
    Just paths -> Just <$> mapM (expandPathPreservingPrefix d) paths

expandPathPreservingPrefix :: FilePath -> PrefixedFilePath -> IO PrefixedFilePath
expandPathPreservingPrefix d prefixedf = do
  let (p,f) = splitReaderPrefix prefixedf
  f' <- expandPathOrGlob d f
  return $ case p of
    Just p'  -> (show p') ++ ":" ++ f'
    Nothing -> f'

-- | Get the expanded, absolute output file path specified by an
-- -o/--output-file options, or nothing, meaning stdout.
outputFileFromOpts :: CliOpts -> IO (Maybe FilePath)
outputFileFromOpts opts = do
  d <- getCurrentDirectory
  case output_file_ opts of
    Nothing -> return Nothing
    Just f  -> Just <$> expandPath d f

defaultOutputFormat :: String
defaultOutputFormat = "txt"

-- | All the output formats known by any command, for outputFormatFromOpts.
-- To automatically infer it from -o/--output-file, it needs to be listed here.
outputFormats :: [String]
outputFormats = [defaultOutputFormat, "beancount", "csv", "json", "html", "sql", "tsv", "fods"]

-- | Get the output format from the --output-format option,
-- otherwise from a recognised file extension in the --output-file option,
-- otherwise the default (txt).
outputFormatFromOpts :: CliOpts -> String
outputFormatFromOpts opts =
  case output_format_ opts of
    Just f  -> f
    Nothing ->
      case filePathExtension <$> output_file_ opts of
        Just ext | ext `elem` outputFormats -> ext
        _                                   -> defaultOutputFormat

-- | Like outputFormatFromOpts, but works on RawOpts (before CliOpts are constructed).
outputFormatFromRawOpts :: RawOpts -> String
outputFormatFromRawOpts rawopts =
  case maybestringopt "output-format" rawopts of
    Just f  -> f
    Nothing ->
      case filePathExtension <$> maybestringopt "output-file" rawopts of
        Just ext | ext `elem` outputFormats -> ext
        _                                   -> defaultOutputFormat

-- -- | Get the file name without its last extension, from a file path.
-- filePathBaseFileName :: FilePath -> String
-- filePathBaseFileName = fst . splitExtension . snd . splitFileName

-- | Get the last file extension, without the dot, from a file path.
-- May return the null string.
filePathExtension :: FilePath -> String
filePathExtension = dropWhile (=='.') . snd . splitExtension . snd . splitFileName

-- | Get the (tilde-expanded) rules file path from options, if any.
rulesFilePathFromOpts :: CliOpts -> IO (Maybe FilePath)
rulesFilePathFromOpts opts = do
  d <- getCurrentDirectory
  maybe (return Nothing) (fmap Just . expandPath d) $ mrules_file_ $ inputopts_ opts

-- | Get the width in characters to use for the register command's console output,
-- and also the description column width if specified (following the main width, comma-separated).
-- The widths will be as follows:
-- @
-- no --width flag - overall width is the available width (or terminal width, or 80); description width is unspecified (auto)
-- --width W       - overall width is W, description width is auto
-- --width W,D     - overall width is W, description width is D
-- @
-- Will raise a parse error for a malformed --width argument.
registerWidthsFromOpts :: CliOpts -> (Int, Maybe Int)
registerWidthsFromOpts CliOpts{width_=Nothing, available_width_=w} = (w, Nothing)
registerWidthsFromOpts CliOpts{width_=Just s}  =
    case runParser registerwidthp "(unknown)" s of
        Left e   -> usageError $ "could not parse width option: "++errorBundlePretty e
        Right ws -> ws
    where
        registerwidthp :: (Stream s, Char ~ Token s) => ParsecT Void s m (Int, Maybe Int)
        registerwidthp = do
          totalwidth <- read `fmap` some digitChar
          descwidth <- optional (char ',' >> read `fmap` some digitChar)
          eof
          return (totalwidth, descwidth)

-- Some common ways to select items from a list of declarable things.
-- Used by the accounts, commodities, payees, tags commands, eg.
data DeclarablesSelector
  = Used
  | Declared
  | Undeclared
  | Unused
  | FindFirst  -- ^ the first item matched by the first argument (--find)
  deriving (Show, Eq)

-- Get the flag of this kind from opts, or raise an error if there's more than one.
declarablesSelectorFromOpts :: CliOpts -> Maybe DeclarablesSelector
declarablesSelectorFromOpts CliOpts{rawopts_=rawopts} =
  case ( boolopt "used"       rawopts
       , boolopt "declared"   rawopts
       , boolopt "undeclared" rawopts
       , boolopt "unused"     rawopts
       , boolopt "find"       rawopts
       ) of
    (False, False, False, False, False) -> Nothing
    (True,  False, False, False, False) -> Just Used
    (False, True,  False, False, False) -> Just Declared
    (False, False, True,  False, False) -> Just Undeclared
    (False, False, False, True,  False) -> Just Unused
    (False, False, False, False, True ) -> Just FindFirst
    _ -> error' "please pick at most one of --used, --declared, --undeclared, --unused, --find"

-- | A helper for the --find mode offered by commands like accounts, commodities, payees, tags (see also 'DeclarablesSelector').
-- Interpret the first command argument found in rawopts as a case insensitive regular expression,
-- then return the first of the provided items that it matches;
-- or raise an error if there's no valid argument or no matched item.
-- This function's second argument describes the items' type, for the error message.
findMatchedByArgument :: RawOpts -> String -> [T.Text] -> T.Text
findMatchedByArgument rawopts itemtype items =
  let
    arg = headDef err $ listofstringopt "args" rawopts
      where err = error' $ "With --find, please provide a " ++ itemtype ++ " name or\n" ++
              itemtype ++ " pattern (case-insensitive, infix, regexp) as first command argument."
    firstmatch = case toRegexCI $ T.pack arg of  -- keep synced with aregister's matching
      Right re -> find (regexMatchText re)
      Left  _  -> const Nothing
  in firstmatch items
    & fromMaybe (error' $ show arg ++ " did not match any " ++ itemtype ++ ".")

-- Other utils

-- None of https://hackage.haskell.org/package/directory-1.3.8.1/docs/System-Directory.html#g:5
-- do quite what we need (find all the executables in PATH with a filename prefix).
-- | Get all sorted unique filenames in the current user's PATH.
-- We do not currently filter out non-file objects or files without execute permission.
likelyExecutablesInPath :: IO [String]
likelyExecutablesInPath = do
  pathdirs <- splitOn pathsep `fmap` getEnvSafe "PATH"
  pathfiles <- concat `fmap` mapM getDirectoryContentsSafe pathdirs
  return $ nubSort pathfiles
  where pathsep = if os == "mingw32" then ";" else ":"
--
-- Exclude directories and files without execute permission:
-- this would do a stat for each hledger-* file found, which is probably ok.
-- But it needs file paths, not just file names.
--
-- exes'  <- filterM doesFileExist exe'
-- exes'' <- filterM isExecutable exes'
-- return exes''
-- where isExecutable f = getPermissions f >>= (return . executable)

getEnvSafe :: String -> IO String
getEnvSafe v = getEnv v `C.catch` (\(_::C.IOException) -> return "") -- XXX should catch only isDoesNotExistError e

getDirectoryContentsSafe :: FilePath -> IO [String]
getDirectoryContentsSafe d =
    (filter (not . (`elem` [".",".."])) `fmap` getDirectoryContents d) `C.catch` (\(_::C.IOException) -> return [])

-- ** Lenses

makeHledgerClassyLenses ''CliOpts

instance HasInputOpts CliOpts where
    inputOpts = inputopts

instance HasBalancingOpts CliOpts where
    balancingOpts = inputOpts.balancingOpts

instance HasReportSpec CliOpts where
    reportSpec = reportspec

instance HasReportOptsNoUpdate CliOpts where
    reportOptsNoUpdate = reportSpec.reportOptsNoUpdate

instance HasReportOpts CliOpts where
    reportOpts = reportSpec.reportOpts

