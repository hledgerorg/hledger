{-|

The @run@ command allows you to run multiple commands via REPL or from the supplied file(s).

-}

{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Run (
  runmode
 ,run
 ,replmode
 ,repl
 ,runOrReplStub
) where

import Data.List.NonEmpty qualified as NE
import Data.Map.Strict qualified as Map
import Data.Semigroup (sconcat)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import System.Console.CmdArgs.Explicit as C ( Mode )
import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Conf (CommandAlias, CommandLine, ResolvedCommand(..), expandCommandAlias, getConf, confAliases)

import Control.Exception
import Control.Concurrent.MVar
import Control.Monad (forM_, void, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Extra (concatMapM, anyM)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Time.Clock.POSIX (POSIXTime, utcTimeToPOSIXSeconds)

import System.Exit (ExitCode(..), exitWith)
import System.Console.CmdArgs.Explicit (expandArgsAt, modeNames, flagNone)
import System.IO (stdin, stderr, stdout, hIsTerminalDevice, hIsOpen, hPutStrLn, hFlush)
import System.IO.Unsafe (unsafePerformIO)
import System.Console.Haskeline

import Data.Maybe (isJust, fromMaybe, catMaybes)
import Safe (headMay)
import Hledger.Cli.DocFiles (runTldrForPage, runInfoForTopic, runManForTopic)
import Hledger.Cli.Utils (journalTransform, journalFileIsNewer, maybeFileModificationTime)
import Text.Printf (printf)
import System.FilePath (takeBaseName, getSearchPath)
import System.Directory (doesDirectoryExist, getModificationTime)
import System.Process (system)
import Hledger.Cli.Version (packageversion)

-- | Command line options for this command.
runmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Run.txt")
  (
  []
  )
  cligeneralflagsgroups1
  -- A hidden marker flag, inserted before run's first -- (see argsMarkRunCommands), letting run
  -- detect it was given inline commands rather than command files. Not for direct use.
  (flagNone [runCommandsMarker] (setboolopt runCommandsMarker) "" : hiddenflags)
  ([], Just $ argsFlag "[COMMANDS_FILE1 COMMANDS_FILE2 ...] OR [-- command1 args... -- command2 args... -- command3 args...]")

replmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Repl.txt")
  (
  [flagNone ["no-watch"] (setboolopt "no-watch") "disable automatic reloading of changed input files, config aliases and addon commands"]
  )
  cligeneralflagsgroups1
  hiddenflags
  ([], Nothing)

-- | The fake run/repl command introduced to break circular dependency.
-- This module needs access to `findBuiltinCommand`, which is defined in Hledger.Cli.Commands
-- However, Hledger.Cli.Commands imports this module, which creates circular dependency.
-- We expose this do-nothing function so that it could be included in the list of all commands inside
-- Hledger.Cli.Commands and ensure that "run" is recognized as a valid command by the Hledger.Cli top-level
-- command line parser. That parser, however, would not call run'. It has a special case for "run", and
-- will call "run" (see below), passing it `findBuiltinCommand`, thus breaking circular dependency.
runOrReplStub :: CliOpts -> Journal -> IO ()
runOrReplStub _opts _j = return ()

-- | Default input files that would be used by commands if
--   there is no explicit alternative given
newtype DefaultRunJournal = DefaultRunJournal (NE.NonEmpty String) deriving (Show)

-- | The actual run command.
run :: Maybe DefaultRunJournal -> (String -> Maybe (Mode RawOpts, CliOpts -> Journal -> IO ())) -> [String] -> [(CommandAlias,CommandLine)] -> Bool -> CliOpts -> IO ()
run defaultJournalOverride findBuiltinCommand addons cmdaliases shellaliasesallowed cliopts@CliOpts{rawopts_=rawopts} = do
  jpaths <- DefaultRunJournal <$> journalFilePathFromOptsOrDefault defaultJournalOverride cliopts
  let
    args = dbg1 "args" $ listofstringopt "args" rawopts
    rungeneralopts = generalRawOpts rawopts  -- general flags we will propagate to each command
    addonfileargs = concatMap (\f -> ["-f", f]) $ file_ cliopts  -- the session's explicit -f files, to pass through to addons
  isTerminal <- isStdinTerminal
  if
    -- Inline commands (a -- was present, flagged by the marker): split and run them.
    | boolopt runCommandsMarker rawopts ->
        runFromArgs jpaths rungeneralopts addonfileargs findBuiltinCommand addons cmdaliases shellaliasesallowed args
    -- No arguments and stdin is not a terminal: read commands from stdin.
    | args == [] && not isTerminal -> do
        inputFiles <- journalFilePathFromOpts cliopts
        let journalFromStdin = any (== "-") $ map (snd . splitReaderPrefix) $ NE.toList inputFiles
        if journalFromStdin
        then error' "'run' can't read commands from stdin, as one of the input files was stdin as well"
        -- watch is False: run never reloads changed files, in any of its modes
        -- (unlike repl). Its other modes don't, since they don't go through runREPL.
        else runREPL jpaths rungeneralopts addonfileargs findBuiltinCommand addons cmdaliases shellaliasesallowed Nothing Nothing False
    -- Otherwise the arguments are files to read commands from.
    | otherwise ->
        runFromFiles jpaths rungeneralopts addonfileargs findBuiltinCommand addons cmdaliases shellaliasesallowed args

-- | The actual repl command. mconfinfo is the active config file and the raw options
-- needed to re-read it, used to auto-reload command aliases when the config file changes.
-- mrescanAddons is an action that re-scans PATH for addon commands, used to auto-reload the
-- addon command list when PATH's contents change.
repl :: (String -> Maybe (Mode RawOpts, CliOpts -> Journal -> IO ())) -> [String] -> [(CommandAlias,CommandLine)] -> Bool -> Maybe (FilePath, RawOpts) -> Maybe (IO [String]) -> CliOpts -> IO ()
repl findBuiltinCommand addons cmdaliases shellaliasesallowed mconfinfo mrescanAddons cliopts = do
  jpaths <- DefaultRunJournal <$> journalFilePathFromOptsOrDefault Nothing cliopts
  let watch = not $ boolopt "no-watch" $ rawopts_ cliopts  -- reload changed files/aliases/addons unless --no-watch
      addonfileargs = concatMap (\f -> ["-f", f]) $ file_ cliopts  -- the session's explicit -f files, to pass through to addons
  runREPL jpaths (generalRawOpts $ rawopts_ cliopts) addonfileargs findBuiltinCommand addons cmdaliases shellaliasesallowed mconfinfo mrescanAddons watch

-- | Run commands from files given to "run".
runFromFiles :: DefaultRunJournal -> [(String,String)] -> [String] -> (String -> Maybe (Mode RawOpts, CliOpts -> Journal -> IO ())) -> [String] -> [(CommandAlias,CommandLine)] -> Bool -> [String] -> IO ()
runFromFiles defaultJournalOverride rungeneralopts addonfileargs findBuiltinCommand addons cmdaliases shellaliasesallowed inputfiles = do
  dbg1IO "inputfiles" inputfiles
  -- read commands from all the inputfiles
  commands <- (flip concatMapM) inputfiles $ \f -> do
    dbg1IO "reading commands" f
    lines . T.unpack <$> T.readFile f

  forM_ commands (runCommand defaultJournalOverride rungeneralopts addonfileargs findBuiltinCommand addons cmdaliases shellaliasesallowed . parseCommand)

-- | Run commands from command line arguments given to "run".
runFromArgs :: DefaultRunJournal -> [(String,String)] -> [String] -> (String -> Maybe (Mode RawOpts, CliOpts -> Journal -> IO ())) -> [String] -> [(CommandAlias,CommandLine)] -> Bool -> [String] -> IO ()
runFromArgs defaultJournalOverride rungeneralopts addonfileargs findBuiltinCommand addons cmdaliases shellaliasesallowed args = do
  -- read commands from all the inputfiles
  let commands = dbg1 "commands from args" $ splitAtElement "--" args
  forM_ commands (runCommand defaultJournalOverride rungeneralopts addonfileargs findBuiltinCommand addons cmdaliases shellaliasesallowed)

-- When commands are passed on the command line, shell will parse them for us
-- When commands are read from file, we need to split the line into command and arguments
parseCommand :: String -> [String]
parseCommand line =
  case wordsEither line' of
    -- # begins a comment, ignore everything after #
    Right ws -> takeWhile (not. ((Just '#')==) . headMay) ws
    Left err -> error' $ "could not parse this command line:\n" <> err
  where line' = strip line

-- | Interpret the common backslash escape sequences \n, \t, \r and \\ in a string,
-- so the run/repl echo command can print newlines, tabs etc. An unrecognised escape
-- is left as written (its backslash is kept).
unescape :: String -> String
unescape ('\\':c:cs) = case c of
  'n'  -> '\n' : unescape cs
  't'  -> '\t' : unescape cs
  'r'  -> '\r' : unescape cs
  '\\' -> '\\' : unescape cs
  _    -> '\\' : c : unescape cs
unescape (c:cs)      = c : unescape cs
unescape []          = []

-- | Run a shell command, and if it fails, exit with its exit code; on success just return,
-- so a sequence of run/repl commands can continue. Flushes stdout first, so that our own
-- buffered output (eg echo's) appears before the subprocess's output.
runShellCommandOrExit :: String -> IO ()
runShellCommandOrExit shcmd = do
  hFlush stdout
  ec <- system shcmd
  when (ec /= ExitSuccess) $ exitWith ec

-- | Take a single command line (from file, or REPL, or "--"-surrounded block of the args), and run it.
-- addonfileargs are -f options (the session's explicit input files) to pass through to addon commands.
runCommand :: DefaultRunJournal -> [(String,String)] -> [String] -> (String -> Maybe (Mode RawOpts, CliOpts -> Journal -> IO ())) -> [String] -> [(CommandAlias,CommandLine)] -> Bool -> [String] -> IO ()
runCommand defaultJournalOverride rungeneralopts addonfileargs findBuiltinCommand addons cmdaliases shellaliasesallowed cmdline = do
  dbg1IO "runCommand for" cmdline
  case cmdline of
    "echo":args -> putStrLn $ unescape $ unwords args
    cmdname0:args0 ->
      -- The command may be a command alias defined in the config file; expand it.
      case expandCommandAlias (isJust . findBuiltinCommand) cmdaliases cmdname0 of
       -- A !-prefixed shell command alias: run it (if allowed), with any arguments appended.
       ShellCommand shcmd
         | shellaliasesallowed -> runShellCommandOrExit (unwords $ shcmd : map quoteForCommandLine args0)
         | otherwise -> error' $ "the command alias '" ++ cmdname0
             ++ "' runs a shell command, which is only allowed from your user config file or a --conf file"
       -- Otherwise an hledger command, with the alias's arguments preceding this line's own arguments.
       HledgerCommand cmdname defargs ->
        let
          -- Mark run's inline commands (see argsMarkRunCommands), after alias expansion, so it
          -- works whether "run ... -- ..." was typed directly or reached via a command alias
          -- (or a nested run in a commands file).
          args = (if cmdname == "run" then argsMarkRunCommands else id) $ defargs <> args0
          aliasnote = if cmdname /= cmdname0 then " (expanded from the " ++ cmdname0 ++ " command alias)" else ""
        in
        case findBuiltinCommand cmdname of
        Just (cmdmode,cmdaction) -> do
              -- Even though expandArgsAt is done by the Cli.hs, it stops at the first '--', so we need
              -- to do it here as well to make sure that each command can use @ARGFILEs
              args' <- replaceNumericFlags <$> expandArgsAt args
              dbg1IO "runCommand final args" (cmdname,args')
              -- Propagate run/repl's general flags to this command, letting its own flags take precedence
              opts <- insertRawOpts rungeneralopts =<< getHledgerCliOpts' cmdmode args'
              let
                rawopts      = rawopts_ opts
                mmodecmdname = headMay $ modeNames cmdmode
                helpFlag     = boolopt "help"     rawopts
                examplesFlag = boolopt "examples" rawopts
                infoFlag     = boolopt "info"     rawopts
                manFlag      = boolopt "man"      rawopts
              if
                | helpFlag     -> runPager $ showModeUsage cmdmode ++ "\n"
                | examplesFlag -> runTldrForPage $ maybe "hledger" (("hledger-"<>)) mmodecmdname
                | infoFlag  -> runInfoForTopic "hledger" mmodecmdname
                | manFlag   -> runManForTopic "hledger"  mmodecmdname
                | cmdname `elem` journalIgnoringCommandNames ->
                  -- help/setup/test never read the journal, as at the CLI
                  cmdaction opts nulljournal
                | cmdname `elem` journalCreatingCommandNames ->
                  -- add and import can create a nonexistent journal file, as they do at the CLI
                  withPossibleRunJournal defaultJournalOverride opts (cmdaction opts)
                | otherwise -> do
                  withJournalCached (Just defaultJournalOverride) opts $ \(j,jpaths) -> do
                    if cmdname == "run" -- allow "run" to call "run"
                      then run (Just jpaths) findBuiltinCommand addons cmdaliases shellaliasesallowed opts
                      else cmdaction opts j
        Nothing | cmdname `elem` addons ->
          -- Pass the session's explicit input files to the addon, so it uses the same journal
          -- (as the CLI does by forwarding its -f options to addons).
          runShellCommandOrExit (printf "%s-%s %s" progname cmdname (unwords $ map quoteForCommandLine $ addonfileargs <> args))
        Nothing ->
          error' $ "Unrecognized command" ++ aliasnote ++ ": " ++ unwords (cmdname:args)
    [] -> return ()

-- | Run an interactive REPL. mconfinfo is the active config file and the raw options
-- needed to re-read it, used to auto-reload command aliases when the config file changes.
-- mrescanAddons is an action that re-scans PATH for addon commands, used to auto-reload the
-- addon command list when PATH's contents change. Either being Nothing disables that reload
-- (eg for a non-interactive "run").
-- watch enables the automatic reloading of changed files/aliases/addons (disabled by --no-watch).
runREPL :: DefaultRunJournal -> [(String,String)] -> [String] -> (String -> Maybe (Mode RawOpts, CliOpts -> Journal -> IO ())) -> [String] -> [(CommandAlias,CommandLine)] -> Bool -> Maybe (FilePath, RawOpts) -> Maybe (IO [String]) -> Bool -> IO ()
runREPL defaultJournalOverride@(DefaultRunJournal jpaths) rungeneralopts addonfileargs findBuiltinCommand addons cmdaliases shellaliasesallowed mconfinfo mrescanAddons watch = do
  isTerminal <- isStdinTerminal
  -- Mutable alias and addon state, so these can be reloaded when their sources change on disk.
  confmtime0 <- maybe (return 0) (fmap (fromMaybe 0) . maybeFileModificationTime . fst) mconfinfo
  aliasesRef <- newIORef (confmtime0, cmdaliases)
  pathmtime0 <- maybe (return 0) (const maxSearchPathMtime) mrescanAddons
  addonsRef  <- newIORef (pathmtime0, addons)
  if not isTerminal
    then runInputT defaultSettings (loop aliasesRef addonsRef False "")
    else do
      -- Show a startup banner: the program name and version and a usage hint,
      -- coloured with a gradient like the commands list when supported.
      -- w <- fromMaybe 80 <$> getTerminalWidth
      -- The interactive prompt is coloured only in terminals that fully emulate one.
      -- Emacs's M-x shell (comint) advertises xterm but mishandles the cursor movement
      -- haskeline uses to redraw a prompt containing escape codes, garbling the display;
      -- there we use a plain prompt (the banner above is fine, being plain putStrLn output).
      emacs <- insideEmacsNotVterm
      let
        grad intensity row s = gradientStr intensity 2 (length s) row 0 s
        fpath = snd $ splitReaderPrefix $ NE.head jpaths
                  --------------------------------------80----------------------------------------
        title  =  progname <> " " <> packageversion
        hint   = "Ready for hledger or !shell commands. For help: h or h -h. To exit: q or ctrl-d."
        promptbase = takeBaseName fpath ++ "> "
        prompt = if emacs then promptbase else stxMarkEscapes $ grad faint' 2 promptbase
      -- putStrLn $ grad faint' 0 $ replicate w '-'
      putStrLn $ grad bold' 1 title
      putStrLn $ faint' hint
      -- Then run the REPL loop.
      runInputT defaultSettings (loop aliasesRef addonsRef True prompt)

  where
  loop :: IORef (POSIXTime,[(CommandAlias,CommandLine)]) -> IORef (POSIXTime,[String]) -> Bool -> String -> InputT IO ()
  loop aliasesRef addonsRef interactive prompt = do
    minput <- getInputLine prompt
    case minput of
      Nothing -> return ()
      Just "q" -> return ()
      Just "quit" -> return ()
      Just "exit" -> return ()
      Just input -> do
        -- Reload any changed input files, config aliases or addon commands, then run the command.
        -- All are guarded by the handlers below (interactively), so a control-C during any of them
        -- returns to the prompt rather than exiting the REPL.
        let action = do
              when watch $ do
                refreshStaleJournals
                refreshStaleAliases mconfinfo aliasesRef
                refreshStaleAddons mrescanAddons addonsRef
              (_, cmdaliases') <- readIORef aliasesRef
              (_, addons')     <- readIORef addonsRef
              case strip input of
                "!"       -> return ()           -- a bare !, do nothing
                '!':shcmd -> hFlush stdout >> void (system shcmd)  -- !SHELLCMD, run the rest as a shell command
                -- h is a short alias for the help command.
                _         -> runCommand defaultJournalOverride rungeneralopts addonfileargs findBuiltinCommand addons' cmdaliases' shellaliasesallowed $
                             case parseCommand input of
                               "h":rest -> "help":rest
                               cmd      -> cmd
        liftIO $ if interactive
          then action `catches`
                  [Handler (\(e::ErrorCall) -> putStrLn $ rstrip $ show e)
                  ,Handler (\(e::IOError)   -> putStrLn $ rstrip $ show e)
                  ,Handler (\(_::ExitCode)  -> return ())
                  ,Handler (\UserInterrupt  -> hPutStrLn stderr "(interrupted)")
                  ]
          else action
        loop aliasesRef addonsRef interactive prompt

isStdinTerminal = do
  op <- hIsOpen stdin
  if op then hIsTerminalDevice stdin else return False

-- | Mark any ANSI escape sequences (eg SGR colour/style codes) in a string as zero-width
-- for haskeline, by appending a \STX character to each. Haskeline treats text between
-- \ESC and \STX as zero-width; without this, escape codes in the prompt make it
-- miscalculate the prompt's width, garbling the display.
stxMarkEscapes :: String -> String
stxMarkEscapes ('\ESC':cs) =
  case break (=='m') cs of  -- SGR escape sequences end with 'm'
    (code, 'm':rest) -> '\ESC' : code ++ "m\STX" ++ stxMarkEscapes rest
    _                -> '\ESC' : cs  -- unterminated escape sequence, leave as is
stxMarkEscapes (c:cs) = c : stxMarkEscapes cs
stxMarkEscapes ""     = ""

-- | Cache of all journals that have been read by commands given to "run",
-- keyed by the fully-expanded filename.
journalCache :: MVar (Map.Map (InputOpts,PrefixedFilePath) Journal)
journalCache = unsafePerformIO $ newMVar Map.empty
{-# NOINLINE journalCache #-}

-- | Cache of stdin contents, so that we can re-read it if InputOptions change
stdinCache :: MVar (Maybe T.Text)
stdinCache = unsafePerformIO $ newMVar Nothing
{-# NOINLINE stdinCache #-}

-- | A changed file F is being reloaded: print a "(reloading F)" notice, read the new value
-- with the given action (catching synchronous errors so an async exception such as a control-C
-- still propagates), then either apply it with onSuccess, or on failure print
-- "could not reload F, keeping previous THING" and run onKeepPrevious. Shared by the journal-data
-- and config-alias reloads to keep their notices and error handling identical.
reloadChanged :: FilePath -> String -> IO (Either String a) -> (a -> IO ()) -> IO () -> IO ()
reloadChanged fp thing readNew onSuccess onKeepPrevious = do
  hPutStrLn stderr $ "(reloading " ++ fp ++ ")"
  hFlush stderr
  enew <- readNew `catches`
            [Handler (\(e::IOError)   -> return $ Left $ show e)
            ,Handler (\(e::ErrorCall) -> return $ Left $ show e)]
  case enew of
    Right new -> onSuccess new
    Left err  -> do
      hPutStrLn stderr $ "could not reload " ++ fp ++ ", keeping previous " ++ thing ++ ":\n" ++ err
      onKeepPrevious

-- | Re-read any cached journals whose files (main or included) have changed on
-- disk since they were last read, updating the cache in place. Called at the top
-- of each REPL loop iteration so that commands see the latest file contents.
-- Prints a visible notice on stderr for each reload, and, if a changed file no
-- longer parses, keeps the previous version and prints the error.
refreshStaleJournals :: IO ()
refreshStaleJournals = do
  cache <- readMVar journalCache
  forM_ (Map.toList cache) $ \((iopts,fp), j) -> do
    changed <- anyM (journalFileIsNewer j) (journalAllFilePaths j)
    when changed $
      reloadChanged fp "version" (runExceptT $ readJournalFile iopts fp)
        (\j' -> modifyMVar_ journalCache $ return . Map.insert (iopts,fp) j')
        -- On failure advance the cached journal's read time past its current files, so we report
        -- the error once and stay quiet until a file changes again.
        (do newest <- maximum . (jlastreadtime j :) . catMaybes <$> mapM maybeFileModificationTime (journalAllFilePaths j)
            modifyMVar_ journalCache $ return . Map.adjust (journalSetLastReadTime newest) (iopts,fp))

-- | If the config file has changed on disk since its command aliases were last read,
-- re-read them into the given ref. Prints a "(reloading CONFFILE)" notice before reading and,
-- if the file no longer parses, keeps the previous aliases and prints the error - consistent
-- with the journal data reload.
refreshStaleAliases :: Maybe (FilePath, RawOpts) -> IORef (POSIXTime,[(CommandAlias,CommandLine)]) -> IO ()
refreshStaleAliases Nothing _ = return ()
refreshStaleAliases (Just (conffile, rawopts)) ref = do
  mmtime <- maybeFileModificationTime conffile
  case mmtime of
    Nothing    -> return ()  -- config file no longer exists; keep current aliases
    Just mtime -> do
      (lastseen, oldaliases) <- readIORef ref
      when (mtime > lastseen) $
        reloadChanged conffile "aliases" readAliases
          (\as -> writeIORef ref (mtime, as))
          -- On failure advance the marker but keep the old aliases, so we report the error once
          -- and stay quiet until the file changes again.
          (writeIORef ref (mtime, oldaliases))
  where
    -- Re-read the config file's command aliases, forcing them so any error in a malformed
    -- [alias] line is raised here (and caught by reloadChanged) rather than later during expansion.
    readAliases = do
      econf <- getConf rawopts
      case econf of
        Left e          -> return $ Left e
        Right (conf, _) -> do
          let as = reverse $ confAliases conf
          mapM_ evaluate as
          return $ Right as

-- | If a PATH directory has changed since the addon command list was last scanned,
-- re-scan for addon commands with the given action and update the ref. Prints a
-- "(reloaded addons)" notice only when the set of addon commands actually changed
-- (a PATH directory's mtime can change without affecting which hledger-* executables exist).
refreshStaleAddons :: Maybe (IO [String]) -> IORef (POSIXTime,[String]) -> IO ()
refreshStaleAddons Nothing _ = return ()
refreshStaleAddons (Just rescan) ref = do
  mtime <- maxSearchPathMtime
  (lastseen, oldaddons) <- readIORef ref
  when (mtime > lastseen) $ do
    newaddons <- rescan
    writeIORef ref (mtime, newaddons)
    when (newaddons /= oldaddons) $ hPutStrLn stderr "(reloaded addons)"

-- | The most recent modification time among the existing directories on the PATH.
-- A directory's mtime changes when entries are added or removed, so this detects when
-- the set of installed addon commands may have changed.
maxSearchPathMtime :: IO POSIXTime
maxSearchPathMtime = do
  dirs <- getSearchPath
  mtimes <- mapM maybeDirModificationTime dirs
  return $ maximum (0 : catMaybes mtimes)

-- | The last modified time of the specified directory, if it exists.
maybeDirModificationTime :: FilePath -> IO (Maybe POSIXTime)
maybeDirModificationTime d = do
  exists <- doesDirectoryExist d
  if exists then Just . utcTimeToPOSIXSeconds <$> getModificationTime d else return Nothing

-- | Get the journal(s) to read: the command's own -f files if any, else the run/repl session's
-- journal(s) (defaultJournalOverride), else the default journal path. The path need not exist -
-- like add/import at the CLI, we let commands create it or report the error, rather than requiring
-- it up front (which would stop run/repl starting when there is no journal yet).
journalFilePathFromOptsOrDefault :: Maybe DefaultRunJournal -> CliOpts -> IO (NE.NonEmpty PrefixedFilePath)
journalFilePathFromOptsOrDefault defaultJournalOverride cliopts = do
  mbjournalpaths <- journalFilePathFromOptsNoDefault cliopts
  case mbjournalpaths of
    Just journalpaths -> return journalpaths  -- the command's own -f files
    Nothing -> case defaultJournalOverride of
      Just (DefaultRunJournal defaultFiles) -> return defaultFiles  -- the journal(s) given to run/repl
      Nothing -> NE.fromList . pure <$> defaultJournalPath  -- the default journal path (need not exist)

-- | Like withJournalCached, but tolerates a nonexistent first journal file (providing an empty
-- journal with that path set), so add and import can create it - as they do at the CLI. Does not
-- cache, since these commands write to the file.
withPossibleRunJournal :: DefaultRunJournal -> CliOpts -> (Journal -> IO ()) -> IO ()
withPossibleRunJournal defaultJournalOverride cliopts cmd = do
  journalpaths <- journalFilePathFromOptsOrDefault (Just defaultJournalOverride) cliopts
  ej <- runExceptT $ journalTransform cliopts <$> readPossibleJournalFiles (inputopts_ cliopts) (NE.toList journalpaths)
  either error' cmd ej

-- | Similar to `withJournal`, but caches all the journals it reads.
-- When reading from stdin, also caches the stdin contents so that we could reprocess
-- it if a read with different InputOptions is requested.
withJournalCached :: Maybe DefaultRunJournal -> CliOpts -> ((Journal, DefaultRunJournal) -> IO ()) -> IO ()
withJournalCached defaultJournalOverride cliopts cmd = do
  journalpaths <- journalFilePathFromOptsOrDefault defaultJournalOverride cliopts
  j <- readFiles journalpaths
  cmd (j,DefaultRunJournal journalpaths)
  where
    readFiles journalpaths =
      journalTransform cliopts . sconcat <$> mapM (readAndCacheJournalFile (inputopts_ cliopts)) journalpaths
    -- | Read a journal file, caching it (and InputOptions used to read it) if it has not been seen before.
    -- If the same file is requested with different InputOptions, we read it anew and cache
    -- it separately.
    readAndCacheJournalFile :: InputOpts -> PrefixedFilePath -> IO Journal
    readAndCacheJournalFile iopts fp = do
      modifyMVar journalCache $ \cache ->
        case Map.lookup (ioptsWithoutReportSpan,fp) cache of
          Just journal -> do
            dbg1IO ("readAndCacheJournalFile using cache for "++fp) iopts
            return (cache, journal)
          Nothing -> do
            dbg1IO ("readAndCacheJournalFile reading and caching "++fp) iopts
            journal <- runExceptT $ if isStdin fp then readStdin else readJournalFile iopts fp
            either error' (\j -> return (Map.insert (ioptsWithoutReportSpan,fp) j cache, j)) journal
      where
        -- InputOptions contain reportspan_ that is used to calculate forecast period,
        -- that is used by journalFinalise to insert forecast transactions.
        -- For the purposes of caching, we want to ignore it whenever
        -- --forecast is not used, or when explicit dates are requested.
        ioptsWithoutReportSpan = iopts{ reportspan_ = forecastreportspan }
          where
            forecastreportspan = case forecast_ iopts of
              Nothing           -> emptydatespan
              -- This could be better if we had access to the journal (as we
              -- could use 'forecastPeriod') or to the journal end date (as
              -- forecast transactions are never generated before journal end
              -- unless specifically requested).
              Just forecastspan -> forecastspan `spanValidDefaultsFrom` reportspan_ iopts
        -- Read stdin, or if we read it already, use a cache
        -- readStdin :: InputOpts -> ExceptT String IO Journal
        readStdin = do
          stdinContent <- liftIO $ modifyMVar stdinCache $ \cache ->
            case cache of
              Just cached -> do
                dbg1IO "readStdin using cached stdin" "-"
                return (cache, cached)
              Nothing -> do
                dbg1IO "readStdin reading and caching stdin" "-"
                stdinContent <- readFileOrStdinPortably "-"
                return (Just stdinContent, stdinContent)
          hndl <- liftIO $ textToHandle stdinContent
          readJournal iopts Nothing hndl
