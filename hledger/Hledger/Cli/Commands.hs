{-|
hledger's built-in commands, and helpers for printing the commands list.

New built-in commands should be added in four places below:
the export list, the import list, builtinCommands, commandsListSections.

-}

-- Note: commands list rendering is intensely sensitive to change,
-- very easy to break in ways that tests currently do not catch.

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands (
   commands
  ,mainmode
  ,testcmd
  ,builtinCommands
  ,builtinCommandNames
  ,addonCommandNames
  ,knownAddonCommandNames
  ,findBuiltinCommand
  ,knownCommands
  ,CommandCategories(..)
  ,commandCategories
  ,printCommandsList
  ,tests_Hledger_Cli
  ,module Hledger.Cli.Commands.Accounts
  ,module Hledger.Cli.Commands.Activity
  ,module Hledger.Cli.Commands.Add
  ,module Hledger.Cli.Commands.Aregister
  ,module Hledger.Cli.Commands.Balance
  ,module Hledger.Cli.Commands.Balancesheet
  ,module Hledger.Cli.Commands.Balancesheetequity
  ,module Hledger.Cli.Commands.Cashflow
  ,module Hledger.Cli.Commands.Check
  ,module Hledger.Cli.Commands.Close
  ,module Hledger.Cli.Commands.Codes
  ,module Hledger.Cli.Commands.Commodities
  ,module Hledger.Cli.Commands.Descriptions
  ,module Hledger.Cli.Commands.Diff
  ,module Hledger.Cli.Commands.Files
  ,module Hledger.Cli.Commands.Get
  ,module Hledger.Cli.Commands.Help
  ,module Hledger.Cli.Commands.Holdings
  ,module Hledger.Cli.Commands.Import
  ,module Hledger.Cli.Commands.Incomestatement
  ,module Hledger.Cli.Commands.Notes
  ,module Hledger.Cli.Commands.Payees
  ,module Hledger.Cli.Commands.Prices
  ,module Hledger.Cli.Commands.Print
  ,module Hledger.Cli.Commands.Register
  ,module Hledger.Cli.Commands.Rewrite
  ,module Hledger.Cli.Commands.Roi
  ,module Hledger.Cli.Commands.Run
  ,module Hledger.Cli.Commands.Setup
  ,module Hledger.Cli.Commands.Stats
  ,module Hledger.Cli.Commands.Tags
  ,module Hledger.Cli.Commands.Transactions
) 
where

import Data.Char (isSpace, toLower)
import Data.Either (isRight)
import Data.List
import Data.List.Extra (groupSortOn, nubOrdOn, nubSort)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar
import Safe (headErr, headMay, maximumDef)
import System.Console.CmdArgs.Explicit as C
import System.Environment (withArgs)
import System.FilePath (dropExtension, takeBaseName, takeExtension)
import Test.Tasty (defaultMain)
import Text.Megaparsec
import Text.Megaparsec.Char

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Conf (CommandAlias, CommandLine, confAliases, getConf')
import Hledger.Cli.Commands.Accounts
import Hledger.Cli.Commands.Activity
import Hledger.Cli.Commands.Add
import Hledger.Cli.Commands.Aregister
import Hledger.Cli.Commands.Balance
import Hledger.Cli.Commands.Balancesheet
import Hledger.Cli.Commands.Balancesheetequity
import Hledger.Cli.Commands.Cashflow
import Hledger.Cli.Commands.Check
import Hledger.Cli.Commands.Close
import Hledger.Cli.Commands.Codes
import Hledger.Cli.Commands.Commodities
import Hledger.Cli.Commands.Descriptions
import Hledger.Cli.Commands.Diff
import Hledger.Cli.Commands.Files
import Hledger.Cli.Commands.Get
import Hledger.Cli.Commands.Help
import Hledger.Cli.Commands.Holdings
import Hledger.Cli.Commands.Import
import Hledger.Cli.Commands.Incomestatement
import Hledger.Cli.Commands.Notes
import Hledger.Cli.Commands.Payees
import Hledger.Cli.Commands.Prices
import Hledger.Cli.Commands.Print
import Hledger.Cli.Commands.Register
import Hledger.Cli.Commands.Rewrite
import Hledger.Cli.Commands.Roi
import Hledger.Cli.Commands.Run
import Hledger.Cli.Commands.Setup
import Hledger.Cli.Commands.Stats
import Hledger.Cli.Commands.Tags
import Hledger.Cli.Commands.Transactions
import Hledger.Cli.Utils (tests_Cli_Utils, openBrowserOn)
import Hledger.Cli.Commands.Quickref (showQuickref)
import Hledger.Cli.DocFiles (runTldrForPage)
import Data.Functor ((<&>), void)

-- | The cmdargs subcommand mode (for command-line parsing)
-- and IO action (for doing the command's work) for each builtin command.
-- Command actions take parsed CLI options and a (lazy) finalised journal.
builtinCommands :: [(Mode RawOpts, CliOpts -> Journal -> IO ())]
builtinCommands = [
   (accountsmode           , accounts)
  ,(activitymode           , activity)
  ,(addmode                , add)
  ,(aregistermode          , aregister)
  ,(balancemode            , balance)
  ,(balancesheetequitymode , balancesheetequity)
  ,(balancesheetmode       , balancesheet)
  ,(cashflowmode           , cashflow)
  ,(checkmode              , check)
  ,(closemode              , close)
  ,(codesmode              , codes)
  ,(commoditiesmode        , commodities)
  ,(descriptionsmode       , descriptions)
  ,(diffmode               , diff)
  ,(filesmode              , files)
  ,(getmode                , getcmd)
  ,(helpmode               , help)
  ,(holdingsmode           , holdings)
  ,(importmode             , importcmd)
  ,(incomestatementmode    , incomestatement)
  ,(notesmode              , notes)
  ,(payeesmode             , payees)
  ,(pricesmode             , prices)
  ,(printmode              , print')
  ,(registermode           , register)
  ,(rewritemode            , rewrite)
  ,(roimode                , roi)
  ,(runmode                , runOrReplStub)
  ,(replmode               , runOrReplStub)
  ,(setupmode              , setup)
  ,(statsmode              , stats)
  ,(tagsmode               , tags)
  ,(transactionsmode       , transactions)
  ,(testmode               , testcmd)
  ]

-- | The overall cmdargs mode describing hledger's command-line options and subcommands.
-- The names of known addons are provided so they too can be recognised as commands.
mainmode addons = defMode {
  modeNames = [progname ++ " [COMMAND]"]
 ,modeArgs = ([], Just $ argsFlag "[ARGS]")
 ,modeHelp = unlines ["hledger's main command line interface. Run with no ARGS to list commands."]
 ,modeGroupModes = Group {
    -- subcommands in the unnamed group, shown first:
    groupUnnamed = [
     ]
    -- subcommands in named groups:
   ,groupNamed = [
     ]
    -- subcommands handled but not shown in the help:
   ,groupHidden = map fst builtinCommands ++ map addonCommandMode addons
   }
 ,modeGroupFlags = Group {
     -- flags in named groups: (keep synced with Hledger.Cli.CliOptions.highlightHelp)
     groupNamed = cligeneralflagsgroups1
     -- flags in the unnamed group, shown last: (keep synced with dropUnsupportedOpts)
    ,groupUnnamed = confflags
     -- other flags handled but not shown in help:
    ,groupHidden = hiddenflagsformainmode
    }
 ,modeHelpSuffix = []
 }

-- | The help command: show some part of hledger's documentation, dispatching on
-- its first argument to a subtopic. Recognised subtopics are: quickref (the quick
-- reference card), commands (the commands list), usage [CMD] (command-line usage,
-- general or for CMD), manual [TOPIC] (the manual, optionally at TOPIC),
-- examples [CMD..] (brief tldr examples), and home/install/relnotes/docs/support/sponsor
-- (open the corresponding hledger.org page in a web browser).
-- With no argument it shows the quickref card; any other first argument is
-- treated as a manual topic.
help :: CliOpts -> Journal -> IO ()
help opts _
  -- With -l, always list matching manual topics, bypassing the special
  -- subcommands (commands, usage, examples, install, etc). A leading "manual"
  -- argument is the (now implicit) subcommand name, so it's consumed rather than
  -- treated as a topic; thus `help -l manual` behaves like `help manual -l`.
  | boolopt "help-l" (rawopts_ opts) = manual opts $ headMay $ case args of
      "manual":rest -> rest
      _             -> args
  | otherwise = case args of
    []              -> showQuickref
    "quickref":_    -> showQuickref
    "commands":_    -> commands opts nulljournal
    "usage":rest    ->
      let usagemode = case rest of
            c:_ | Just (m,_) <- findBuiltinCommand c -> m
            _                                        -> mainmode []
      in runPager $ showModeUsage usagemode ++ "\n"
    "manual":rest   -> manual opts (headMay rest)
    "examples":rest -> mapM_ runTldrForPage $
                         if null rest then ["hledger"] else map ("hledger-"<>) rest
    "home":_        -> void $ openBrowserOn "https://hledger.org"
    "install":_     -> void $ openBrowserOn "https://hledger.org/install.html"
    "relnotes":_    -> void $ openBrowserOn "https://hledger.org/relnotes.html"
    "docs":_        -> void $ openBrowserOn "https://hledger.org/doc.html"
    "support":_     -> void $ openBrowserOn "https://hledger.org/support.html"
    "sponsor":_     -> void $ openBrowserOn "https://hledger.org/sponsor.html"
    _               -> manual opts (headMay args)
  where
    args = listofstringopt "args" (rawopts_ opts)

-- figlet -f FONTNAME hledger, then escape backslashes
_banner_slant = drop 1 [""
    -----------------------------------------80-------------------------------------
  ,"    __    __         __               "
  ,"   / /_  / /__  ____/ /___ ____  _____"
  ,"  / __ \\/ / _ \\/ __  / __ `/ _ \\/ ___/"
  ," / / / / /  __/ /_/ / /_/ /  __/ /    "
  ,"/_/ /_/_/\\___/\\__,_/\\__, /\\___/_/     "
  ,"                   /____/             "
  ]

_banner_smslant = drop 1 [""
  ,"   __   __       __            "
  ,"  / /  / /__ ___/ /__ ____ ____"
  ," / _ \\/ / -_) _  / _ `/ -_) __/"
  ,"/_//_/_/\\__/\\_,_/\\_, /\\__/_/   "
  ,"                /___/          "
  ]

_banner_speed = drop 1 [""
  ,"______ ______    _________                    "
  ,"___  /____  /__________  /______ _____________"
  ,"__  __ \\_  /_  _ \\  __  /__  __ `/  _ \\_  ___/"
  ,"_  / / /  / /  __/ /_/ / _  /_/ //  __/  /    "
  ,"/_/ /_//_/  \\___/\\__,_/  _\\__, / \\___//_/     "
  ,"                         /____/               "
  ]

-- accent and gradientStr, used for the commands list and REPL banners, are in Hledger.Utils.IO.

-- | The three categories of command which the commands list can show:
-- the commands built in to hledger, the addon commands installed in PATH,
-- and the command aliases defined in the config file.
data CommandCategories = CommandCategories {
   showbuiltins_ :: Bool
  ,showaddons_   :: Bool
  ,showaliases_  :: Bool
  }

-- | Which command categories are selected by the --builtins, --addons and
-- --aliases flags in these options. Each of those flags limits the commands
-- list to one category; with none of them, all categories are shown.
commandCategories :: RawOpts -> CommandCategories
commandCategories rawopts
  | not (builtins || addons || cmdaliases) = CommandCategories True True True
  | otherwise                              = CommandCategories builtins addons cmdaliases
  where
    builtins   = boolopt "builtins" rawopts
    addons     = boolopt "addons"   rawopts
    cmdaliases = boolopt "aliases"  rawopts

-- | The builtin and known addon commands, with their standard abbreviation and
-- short description, in the sections and order in which the commands list shows them.
-- Each command line has the format
--
--  COMMAND (ABBREV) DESCRIPTION
--
-- prefixed with a space for a builtin command, or a + for a known addon command
-- (which is shown only when hledger-COMMAND is found in $PATH at runtime).
--
-- Keep synced with builtinCommands above, the command docs (Commands/\*.md),
-- commands.m4, and hledger.m4.md -> Commands.
--
-- TODO: generate more of this automatically.
--
commandsListSections :: [(String, [String])]
commandsListSections = [
    -----------------------------------------80-------------------------------------
  ("USER INTERFACES",
  [" help (h)                 show documentation"
  ," repl                     run multiple commands from an interactive prompt"
  ," run                      run multiple commands from a file or command line"
  ,"+ui                       run a terminal UI"
  ,"+web                      run a web UI"
  ])
    -----------------------------------------80-------------------------------------
 ,("ENTERING DATA",
  [" add                      add transactions using terminal prompts"
  ,"+iadd                     add transactions using a TUI (hledger-iadd)"
  ," import                   add new transactions from other files, eg CSV files"
  ,"+edit                     edit specific transactions with $EDITOR"               -- hledger-utils
  ])
    -----------------------------------------80-------------------------------------
 ,("BASIC REPORTS",
  [" accounts (acc)           show account names"
  ," codes                    show transaction codes"
  ," commodities (comm)       show commodity/currency symbols"
  ," descriptions (desc)      show transaction descriptions"
  ," files                    show input files in use"
  ," notes                    show note part of transaction descriptions"
  ," payees                   show payee part of transaction descriptions"
  ," prices                   show market prices"
  ," stats                    show journal statistics"
  ," tags                     show tag names"
  ," transactions (tx)        show transactions, one per line"
  ])
    -----------------------------------------80-------------------------------------
 ,("STANDARD REPORTS",
  [" print                    show journal entries, or export journal data"
  ," aregister (areg)         show transactions & running balance in one account"
  ," register (reg)           show postings & running total across accounts"
  ," balancesheet (bs)        show assets, liabilities and net worth"
  ," balancesheetequity (bse) show assets, liabilities and equity"
  ," cashflow (cf)            show changes in liquid assets"
  ," incomestatement (is)     show revenues and expenses"
  ])
    -----------------------------------------80-------------------------------------
 ,("ADVANCED REPORTS",
  [" balance (bal)            show balance changes, end balances, gains, budgets.."
  ," holdings                 show investment holdings"
  ,"+lots                     show a commodity's lots"                               -- hledger-lots
  ," roi                      show return on investments"
  ])
    -----------------------------------------80-------------------------------------
 ,("CHARTS",
  [" activity                 show posting counts as a bar chart"
  ,"+bar                      show balances or changes as a bar chart"               -- hledger-bar
  ,"+plot                     show advanced matplotlib charts as gui/svg/png/pdf.."  -- hledger-utils
  ])
    -----------------------------------------80-------------------------------------
 ,("GENERATING DATA",
  ["+autosync                 download/deduplicate/show OFX data as transactions"    -- ledger-autosync
  ," close                    generate transactions to zero/restore/assert balances"
  ," get                      fetch new transactions and market price data"
  ,"+interest                 generate transactions transferring accrued interest"   -- hledger-interest
  ,"+lots sell                generate a lot-selling transaction"                    -- hledger-lots
  ,"+pricehist                download historical market prices"                     -- pricehist
  ," rewrite                  generate auto postings, like print --auto"
  ])
    -----------------------------------------80-------------------------------------
 ,("MAINTENANCE",
  [" check                    check for various kinds of error in the data"
  ,"+check-fancyassertions    check more powerful balance assertions"                -- hledger-check-fancyassertions
  ,"+check-tagfiles           check that files referenced in tag values exist"       -- hledger-check-tagfiles
  ," diff                     compare an account's transactions in two journals"
  ,"+git                      save or view journal file history simply in git"       -- hledger-git
  ,"+pijul                    save or view journal file history simply in pijul"     -- hledger-pijul
  ," setup                    check and show the status of the hledger installation"
  ," test                     run self tests"
  ])
    -----------------------------------------80-------------------------------------
 ]

-- | The canonical command names in the sections above, in the order they occur.
-- With a true argument, only the known addon command names.
commandsListCommandNames :: Bool -> [String]
commandsListCommandNames addonsonly =
  [ cmdname
  | (_, cmds)      <- commandsListSections
  , prefixchar:cmd <- cmds
  , prefixchar `elem` '+':[' '|not addonsonly]
  , cmdname:_      <- [words cmd]
  ]

-- | Render the commands list, showing the selected categories of command:
-- the builtin commands and installed known addon commands from the sections above,
-- then the other installed addons, then the config file's command aliases.
-- A section with no commands to show is omitted.
commandsList :: CommandCategories -> [String] -> [(CommandAlias,CommandLine)] -> [String]
commandsList cats installedaddons cmdaliases =
  -- A one-line title heading, in the quickref style.
  titleLine "HLEDGER COMMANDS"
  : concatMap rendersection commandsListSections
  ++ otheraddonssection
  ++ aliasessection
  where
    rendersection (heading, cmds) = case concatMap selectcommand cmds of
      []    -> []
      cmds' -> bold' heading : cmds'

    -- Keep a command line only if it is in a selected category, replacing the
    -- category prefix with a space; a known addon must also be installed.
    selectcommand (prefixchar:cmd) = case prefixchar of
      ' ' | showbuiltins_ cats                    -> [' ':cmd]
      '+' | showaddons_ cats, isinstalled cmdname -> [' ':cmd]
      _                                           -> []
      where cmdname = takeWhile (not.isSpace) cmd
    selectcommand [] = []

    isinstalled cmdname
      | cmdname `elem` installedaddons = True
      | otherwise = dbg9With (const $ "hiding uninstalled addon: " <> cmdname) False

    -- The installed addons which have no slot above, listed in columns.
    -- The heading is always shown, since this is the catch-all addons section.
    otheraddonssection
      | not $ showaddons_ cats = []
      | otherwise = bold' "OTHER ADDONS" : map (' ':) (lines $ multicol 79 otheraddons)
      where otheraddons = installedaddons \\ knownAddonCommandNames

    -- The command aliases (custom commands) defined in the config file, if any.
    aliasessection
      | not (showaliases_ cats) || null cmdaliases = []
      | otherwise = bold' "ALIASES" :
          [" " <> padright aliasw a <> " = " <> def | (a,def) <- cmdaliases]
      where
        aliasw = maximumDef 0 $ map (length.fst) cmdaliases
        padright w s = s <> replicate (w - length s) ' '

-- | Display the commands list, limited to the categories selected by
-- --builtins/--addons/--aliases. Only the selected categories are looked up:
-- the addons in PATH, and the command aliases in the config file.
commands :: CliOpts -> Journal -> IO ()
commands opts _ = do
  installedaddons <- if showaddons_ cats then addonCommandNames else return []
  cmdaliases <-
    if not $ showaliases_ cats then return [] else do
      (conf,_) <- getConf' $ rawopts_ opts
      -- show each alias's effective (last) definition
      return $ reverse $ nubOrdOn fst $ reverse $ confAliases conf
  printCommandsList cats installedaddons cmdaliases
  where
    cats = commandCategories $ rawopts_ opts

{- | Print the commands list, with a pager if appropriate:
the selected categories of command, customised with the addons
installed in PATH and the command aliases defined in the config file.
-}
printCommandsList :: CommandCategories -> [String] -> [(CommandAlias,CommandLine)] -> IO ()
printCommandsList cats installedaddons cmdaliases =
  seq (length $ dbg8 "uninstalledknownaddons" $ knownaddons \\ installedaddons) $ -- for debug output
    seq (length $ dbg8 "installedknownaddons" $ knownaddons `intersect` installedaddons) $
      seq (length $ dbg8 "installedunknownaddons" $ installedaddons \\ knownaddons) $
        runPager $ unlines $ commandsList cats installedaddons cmdaliases
  where
    knownaddons = knownAddonCommandNames

-- | Canonical names of all commands which have a slot in the commands list, in alphabetical order.
-- These include the builtin commands and the known addon commands.
knownCommands :: [String]
knownCommands = nubSort $ commandsListCommandNames False

-- | All names and aliases of the builtin commands.
builtinCommandNames :: [String]
builtinCommandNames = concatMap (modeNames . fst) builtinCommands

-- | Look up a builtin command's mode and action by exact command name or alias.
findBuiltinCommand :: String -> Maybe (Mode RawOpts, CliOpts -> Journal -> IO ()) 
findBuiltinCommand cmdname = find (elem cmdname . modeNames . fst) builtinCommands 

{- | Canonical names of the known addon commands which have a slot in the commands list,
in alphabetical order.
-}
knownAddonCommandNames :: [String]
knownAddonCommandNames = nubSort $ commandsListCommandNames True

-- Search PATH for names of addon commands, that aren't shadowed by builtin commands.
addonCommandNames :: IO [String]
addonCommandNames = installedAddonCommandNames <&> filter (not . (`elem` builtinCommandNames) . dropExtension)

-- | Get the sorted unique canonical names of hledger addon commands
-- found in the current user's PATH. These are used in command line
-- parsing and to display the commands list.
--
-- Canonical addon names are the filenames of hledger-* executables in
-- PATH, without the "hledger-" prefix, and without the file extension
-- except when it's needed for disambiguation (see below).
--
-- When there are exactly two versions of an executable (same base
-- name, different extensions) that look like a source and compiled
-- pair (one has .exe, .com, or no extension), the source version will
-- be excluded (even if it happens to be newer). When there are three
-- or more versions (or two versions that don't look like a
-- source/compiled pair), they are all included, with file extensions
-- intact.
--
installedAddonCommandNames :: IO [String]
installedAddonCommandNames = do
  -- past bug generator
  as1 <- hledgerExecutablesInPath                     -- ["hledger-check","hledger-check-dates","hledger-check-dates.hs","hledger-check.hs","hledger-check.py"]
  let as2 = map stripPrognamePrefix as1               -- ["check","check-dates","check-dates.hs","check.hs","check.py"]
  let as3 = groupSortOn takeBaseName as2              -- [["check","check.hs","check.py"],["check-dates","check-dates.hs"]]
  let as4 = concatMap dropRedundantSourceVersion as3  -- ["check","check.hs","check.py","check-dates"]
  return as4

stripPrognamePrefix = drop (length progname + 1)

dropRedundantSourceVersion [f,g]
  | map toLower (takeExtension f) `elem` compiledExts = [f]
  | map toLower (takeExtension g) `elem` compiledExts = [g]
dropRedundantSourceVersion fs = fs

compiledExts = ["",".com",".exe"]

-- | Get the sorted unique filenames of all hledger-* executables in
-- the current user's PATH. These are files in any of the PATH directories,
-- named hledger-*, with either no extension (and no periods in the name)
-- or one of the addonExtensions.
-- We do not currently filter out non-file objects or files without execute permission.
hledgerExecutablesInPath :: IO [String]
hledgerExecutablesInPath = filter isHledgerExeName <$> likelyExecutablesInPath

isHledgerExeName :: String -> Bool
isHledgerExeName = isRight . parsewith hledgerexenamep . T.pack
 where
  hledgerexenamep = do
    _ <- string $ T.pack progname
    _ <- char '-'
    _ <- some $ noneOf ['.']
    optional (string "." >> choice' (map (string . T.pack) addonExtensions))
    eof

-- stripAddonExtension :: String -> String
-- stripAddonExtension = regexReplace re "" where re = "\\.(" ++ intercalate "|" addonExtensions ++ ")$"

addonExtensions :: [String]
addonExtensions =
  ["bat"
  ,"com"
  ,"exe"
  ,"hs"
  ,"js"
  ,"lhs"
  ,"lua"
  ,"php"
  ,"pl"
  ,"py"
  ,"rb"
  ,"rkt"
  ,"sh"
  ,"osh"
  ,"ysh"
  ]

-- The test command is also defined here for easy access to other modules' tests.

testmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Test.txt")
  []
  [generalflagsgroup3]
  []
  ([], Just $ argsFlag "[-- TASTYOPTS]")

-- | The test command, which runs the hledger and hledger-lib packages' unit tests.
-- Arguments following a -- argument will be passed to the tasty test runner,
-- and any arguments before -- will be passed as test-selecting -p patterns.
--
-- Unlike most hledger commands, this one does not read the user's journal.
-- A 'Journal' argument remains in the type signature, but it should
-- not be used (and would raise an error).
--
testcmd :: CliOpts -> Journal -> IO ()
testcmd opts _undefined = do
  let
    args = listofstringopt "args" $ rawopts_ opts
    (hledgerargs, tastyargs0) = break (== "--") args
    tastyargs = dbg1 "tastyargs" $ ["-p " <> a | a <- hledgerargs] ++ drop 1 tastyargs0
  withArgs tastyargs $
    Test.Tasty.defaultMain $ testGroup "hledger" [
       tests_Hledger
      ,tests_Hledger_Cli
      ]

-- All unit tests for Hledger.Cli, defined here rather than
-- Hledger.Cli so testcmd can use them.
tests_Hledger_Cli = testGroup "Hledger.Cli" [
   tests_Cli_Utils
  ,tests_Commands
  ]

tests_Commands = testGroup "Commands" [
   tests_Balance
  ,tests_Register
  ,tests_Aregister

  -- some more tests easiest to define here:

  ,testGroup "apply account directive" [
     testCase "works" $ do
        let
          ignoresourcepos j = j{jtxns=map (\t -> t{tsourcepos=nullsourcepospair}) (jtxns j), jitems=[]}
          sameParse str1 str2 = do
            j1 <- ignoresourcepos <$> readJournal'' str1  -- PARTIAL:
            j2 <- ignoresourcepos <$> readJournal'' str2  -- PARTIAL:
            j1 @?= j2{jlastreadtime=jlastreadtime j1, jfiles=jfiles j1} --, jparsestate=jparsestate j1}
        sameParse
           ("2008/12/07 One\n  alpha  $-1\n  beta  $1\n" <>
            "apply account outer\n2008/12/07 Two\n  aigh  $-2\n  bee  $2\n" <>
            "apply account inner\n2008/12/07 Three\n  gamma  $-3\n  delta  $3\n" <>
            "end apply account\n2008/12/07 Four\n  why  $-4\n  zed  $4\n" <>
            "end apply account\n2008/12/07 Five\n  foo  $-5\n  bar  $5\n"
           )
           ("2008/12/07 One\n  alpha  $-1\n  beta  $1\n" <>
            "2008/12/07 Two\n  outer:aigh  $-2\n  outer:bee  $2\n" <>
            "2008/12/07 Three\n  outer:inner:gamma  $-3\n  outer:inner:delta  $3\n" <>
            "2008/12/07 Four\n  outer:why  $-4\n  outer:zed  $4\n" <>
            "2008/12/07 Five\n  foo  $-5\n  bar  $5\n"
           )

    ,testCase "preserves \"virtual\" posting type" $ do
      j <- readJournal'' "apply account test\n2008/12/07 One\n  (from)  $-1\n  (to)  $1\n"  -- PARTIAL:
      let p = headErr $ tpostings $ headErr $ jtxns j  -- PARTIAL headErrs succeed because txns & postings provided
      paccount p @?= "test:from"
      preal p @?= VirtualPosting
    ]

  ,testCase "alias directive" $ do
    j <- readJournal'' "!alias expenses = equity:draw:personal\n1/1\n (expenses:food)  1\n"  -- PARTIAL:
    let p = headErr $ tpostings $ headErr $ jtxns j  -- PARTIAL headErrs succeed because txns & postings provided
    paccount p @?= "equity:draw:personal:food"

  ,testCase "Y default year directive" $ do
    j <- readJournal'' defaultyear_journal_txt  -- PARTIAL:
    tdate (headErr $ jtxns j) @?= fromGregorian 2009 1 1  -- PARTIAL headErr succeeds because defaultyear_journal_txt has a txn

  ,testCase "ledgerAccountNames" $
    (ledgerAccountNames ledger7)
    @?=
    ["assets","assets:cash","assets:checking","assets:saving","equity","equity:opening balances",
     "expenses","expenses:food","expenses:food:dining","expenses:phone","expenses:vacation",
     "liabilities","liabilities:credit cards","liabilities:credit cards:discover"]

  -- ,testCase "journalCanonicaliseAmounts" ~:
  --  "use the greatest precision" ~:
  --   (map asprecision $ journalAmountAndPriceCommodities $ journalCanonicaliseAmounts $ journalWithAmounts ["1","2.00"]) @?= [2,2]

  -- don't know what this should do
  -- ,testCase "elideAccountName" ~: do
  --    (elideAccountName 50 "aaaaaaaaaaaaaaaaaaaa:aaaaaaaaaaaaaaaaaaaa:aaaaaaaaaaaaaaaaaaaa"
  --     @?= "aa:aaaaaaaaaaaaaaaaaaaa:aaaaaaaaaaaaaaaaaaaa")
  --    (elideAccountName 20 "aaaaaaaaaaaaaaaaaaaa:aaaaaaaaaaaaaaaaaaaa:aaaaaaaaaaaaaaaaaaaa"
  --     @?= "aa:aa:aaaaaaaaaaaaaa")

  ,testCase "show dollars" $ showAmount (usd 1) @?= "$1.00"

  ,testCase "show hours" $ showAmount (hrs 1) @?= "1.00h"

  ]

-- test data

-- date1 = fromGregorian 2008 11 26
-- t1 = LocalTime date1 midday

{-
samplejournal = readJournal'' sample_journal_str

sample_journal_str = unlines
 ["; A sample journal file."
 ,";"
 ,"; Sets up this account tree:"
 ,"; assets"
 ,";   bank"
 ,";     checking"
 ,";     saving"
 ,";   cash"
 ,"; expenses"
 ,";   food"
 ,";   supplies"
 ,"; income"
 ,";   gifts"
 ,";   salary"
 ,"; liabilities"
 ,";   debts"
 ,""
 ,"2008/01/01 income"
 ,"    assets:bank:checking  $1"
 ,"    income:salary"
 ,""
 ,"2008/06/01 gift"
 ,"    assets:bank:checking  $1"
 ,"    income:gifts"
 ,""
 ,"2008/06/02 save"
 ,"    assets:bank:saving  $1"
 ,"    assets:bank:checking"
 ,""
 ,"2008/06/03 * eat & shop"
 ,"    expenses:food      $1"
 ,"    expenses:supplies  $1"
 ,"    assets:cash"
 ,""
 ,"2008/12/31 * pay off"
 ,"    liabilities:debts  $1"
 ,"    assets:bank:checking"
 ,""
 ,""
 ,";final comment"
 ]
-}

defaultyear_journal_txt :: Text
defaultyear_journal_txt = T.unlines
 ["Y2009"
 ,""
 ,"01/01 A"
 ,"    a  $1"
 ,"    b"
 ]

-- write_sample_journal = writeFile "sample.journal" sample_journal_str

-- entry2_str = unlines
--  ["2007/01/27 * joes diner"
--  ,"    expenses:food:dining                      $10.00"
--  ,"    expenses:gifts                            $10.00"
--  ,"    assets:checking                          $-20.00"
--  ,""
--  ]

-- entry3_str = unlines
--  ["2007/01/01 * opening balance"
--  ,"    assets:cash                                $4.82"
--  ,"    equity:opening balances"
--  ,""
--  ,"2007/01/01 * opening balance"
--  ,"    assets:cash                                $4.82"
--  ,"    equity:opening balances"
--  ,""
--  ,"2007/01/28 coopportunity"
--  ,"  expenses:food:groceries                 $47.18"
--  ,"  assets:checking"
--  ,""
--  ]

-- periodic_entry1_str = unlines
--  ["~ monthly from 2007/2/2"
--  ,"  assets:saving            $200.00"
--  ,"  assets:checking"
--  ,""
--  ]

-- periodic_entry2_str = unlines
--  ["~ monthly from 2007/2/2"
--  ,"  assets:saving            $200.00         ;auto savings"
--  ,"  assets:checking"
--  ,""
--  ]

-- periodic_entry3_str = unlines
--  ["~ monthly from 2007/01/01"
--  ,"    assets:cash                                $4.82"
--  ,"    equity:opening balances"
--  ,""
--  ,"~ monthly from 2007/01/01"
--  ,"    assets:cash                                $4.82"
--  ,"    equity:opening balances"
--  ,""
--  ]

-- journal1_str = unlines
--  [""
--  ,"2007/01/27 * joes diner"
--  ,"  expenses:food:dining                    $10.00"
--  ,"  expenses:gifts                          $10.00"
--  ,"  assets:checking                        $-20.00"
--  ,""
--  ,""
--  ,"2007/01/28 coopportunity"
--  ,"  expenses:food:groceries                 $47.18"
--  ,"  assets:checking                        $-47.18"
--  ,""
--  ,""
--  ]

-- journal2_str = unlines
--  [";comment"
--  ,"2007/01/27 * joes diner"
--  ,"  expenses:food:dining                    $10.00"
--  ,"  assets:checking                        $-47.18"
--  ,""
--  ]

-- journal3_str = unlines
--  ["2007/01/27 * joes diner"
--  ,"  expenses:food:dining                    $10.00"
--  ,";intra-entry comment"
--  ,"  assets:checking                        $-47.18"
--  ,""
--  ]

-- journal4_str = unlines
--  ["include \"somefile\""
--  ,"2007/01/27 * joes diner"
--  ,"  expenses:food:dining                    $10.00"
--  ,"  assets:checking                        $-47.18"
--  ,""
--  ]

-- journal5_str = ""

-- journal6_str = unlines
--  ["~ monthly from 2007/1/21"
--  ,"    expenses:entertainment  $16.23        ;netflix"
--  ,"    assets:checking"
--  ,""
--  ,"; 2007/01/01 * opening balance"
--  ,";     assets:saving                            $200.04"
--  ,";     equity:opening balances                         "
--  ,""
--  ]

-- journal7_str = unlines
--  ["2007/01/01 * opening balance"
--  ,"    assets:cash                                $4.82"
--  ,"    equity:opening balances                         "
--  ,""
--  ,"2007/01/01 * opening balance"
--  ,"    income:interest                                $-4.82"
--  ,"    equity:opening balances                         "
--  ,""
--  ,"2007/01/02 * ayres suites"
--  ,"    expenses:vacation                        $179.92"
--  ,"    assets:checking                                 "
--  ,""
--  ,"2007/01/02 * auto transfer to savings"
--  ,"    assets:saving                            $200.00"
--  ,"    assets:checking                                 "
--  ,""
--  ,"2007/01/03 * poquito mas"
--  ,"    expenses:food:dining                       $4.82"
--  ,"    assets:cash                                     "
--  ,""
--  ,"2007/01/03 * verizon"
--  ,"    expenses:phone                            $95.11"
--  ,"    assets:checking                                 "
--  ,""
--  ,"2007/01/03 * discover"
--  ,"    liabilities:credit cards:discover         $80.00"
--  ,"    assets:checking                                 "
--  ,""
--  ,"2007/01/04 * blue cross"
--  ,"    expenses:health:insurance                 $90.00"
--  ,"    assets:checking                                 "
--  ,""
--  ,"2007/01/05 * village market liquor"
--  ,"    expenses:food:dining                       $6.48"
--  ,"    assets:checking                                 "
--  ,""
--  ]

journal7 :: Journal
journal7 = nulljournal {jtxns =
          [
           txnTieKnot Transaction {
             tindex=0,
             tsourcepos=nullsourcepospair,
             tdate=fromGregorian 2007 01 01,
             tdate2=Nothing,
             tstatus=Unmarked,
             tcode="*",
             tdescription="opening balance",
             tcomment="",
             ttags=[],
             tpostings=
                 ["assets:cash" `post` usd 4.82
                 ,"equity:opening balances" `post` usd (-4.82)
                 ],
             tprecedingcomment=""
           }
          ,
           txnTieKnot Transaction {
             tindex=0,
             tsourcepos=nullsourcepospair,
             tdate=fromGregorian 2007 02 01,
             tdate2=Nothing,
             tstatus=Unmarked,
             tcode="*",
             tdescription="ayres suites",
             tcomment="",
             ttags=[],
             tpostings=
                 ["expenses:vacation" `post` usd 179.92
                 ,"assets:checking" `post` usd (-179.92)
                 ],
             tprecedingcomment=""
           }
          ,
           txnTieKnot Transaction {
             tindex=0,
             tsourcepos=nullsourcepospair,
             tdate=fromGregorian 2007 01 02,
             tdate2=Nothing,
             tstatus=Unmarked,
             tcode="*",
             tdescription="auto transfer to savings",
             tcomment="",
             ttags=[],
             tpostings=
                 ["assets:saving" `post` usd 200
                 ,"assets:checking" `post` usd (-200)
                 ],
             tprecedingcomment=""
           }
          ,
           txnTieKnot Transaction {
             tindex=0,
             tsourcepos=nullsourcepospair,
             tdate=fromGregorian 2007 01 03,
             tdate2=Nothing,
             tstatus=Unmarked,
             tcode="*",
             tdescription="poquito mas",
             tcomment="",
             ttags=[],
             tpostings=
                 ["expenses:food:dining" `post` usd 4.82
                 ,"assets:cash" `post` usd (-4.82)
                 ],
             tprecedingcomment=""
           }
          ,
           txnTieKnot Transaction {
             tindex=0,
             tsourcepos=nullsourcepospair,
             tdate=fromGregorian 2007 01 03,
             tdate2=Nothing,
             tstatus=Unmarked,
             tcode="*",
             tdescription="verizon",
             tcomment="",
             ttags=[],
             tpostings=
                 ["expenses:phone" `post` usd 95.11
                 ,"assets:checking" `post` usd (-95.11)
                 ],
             tprecedingcomment=""
           }
          ,
           txnTieKnot Transaction {
             tindex=0,
             tsourcepos=nullsourcepospair,
             tdate=fromGregorian 2007 01 03,
             tdate2=Nothing,
             tstatus=Unmarked,
             tcode="*",
             tdescription="discover",
             tcomment="",
             ttags=[],
             tpostings=
                 ["liabilities:credit cards:discover" `post` usd 80
                 ,"assets:checking" `post` usd (-80)
                 ],
             tprecedingcomment=""
           }
          ]
         }

ledger7 :: Ledger
ledger7 = ledgerFromJournal Any journal7
