{- | 

Here are debug tracing/logging helpers built on Debug.Trace, extracted from the hledger project.
Features:

- they can be built in to your program permanently, and activated by a --debug [LEVEL] option
- they can optionally log to a file instead of stderr (for TUI apps)
- they can be used in IO, pure, or startup code
- values are printed with a label, and pretty-printed (using pretty-simple)
- ANSI colour is used when appropriate.

Insert these @dbg*@ helpers at points of interest in your code,
either temporarily while debugging,
or permanently in production code, and activate them with @--debug [1-9]@ on the command line
(@--debug@ with no value means level 1).
For example, this expression:

> dbg4 "foo" foo

will pretty-print foo with a "foo:" label when it is evaluated, but only if --debug's value is 4 or greater.
In other words: use dbg1 for the most useful debug output, dbg9 for the most specialised/verbose.

They are intended to be easy to use and to find in your code, with a consistent naming scheme:

> dbg<LEVEL>Msg   STR    VAL  -- trace/log a string in pure code
> dbg<LEVEL>MsgIO STR         -- trace/log a string in IO
>
> dbg<LEVEL>      STR    VAL  -- trace/log a showable value in pure code
> dbg<LEVEL>IO    STR    VAL  -- trace/log a showable value in IO
>
> dbg<LEVEL>With  SHOWFN VAL  -- trace/log any value

Or if you prefer you can ignore the numbered variants and write an extra argument:

> dbgMsg   LEVEL  STR    VAL
> dbgMsgIO LEVEL  STR
>
> dbg      LEVEL  STR    VAL
> dbgIO    LEVEL  STR    VAL
>
> dbgWith  LEVEL  SHOWFN VAL
>
> dbgTime   LEVEL  STR    VAL  -- trace/log a phase timing: STR, and the time and memory allocated since the previous one, after deep-forcing VAL
> dbgTimeIO LEVEL  STR    VAL  -- the same, in IO

Haskell values will be pretty-printed by default, using pretty-simple.

ANSI color will also be used if appropriate,
respecting output capabilities, @NO_COLOR@, and/or a @--color [YNA]@ (or @--colour@) command line option.

These helpers normally print output on stderr, but can automatically log to a file instead,
which can be useful for TUI apps which are redrawing the screen.
To enable this logging mode, use @withProgName@ to add a ".log" suffix to the program name:

> main = withProgName "PROGRAM.log" $ do ...

Now all dbg calls will log to @PROGRAM.log@ in the current directory.

Logging, and reading the command line\/program name\/output context use unsafePerformIO,
so that these can be used anywhere, including early in your program before command line parsing is complete.
As a consequence, if you are testing in GHCI and want to change the debug level, you'll need to reload this module.

The @dbg@ function name clashes with the one in Text.Megaparsec.Debug, unfortunately; sorry about that.
If you are also using that, use qualified imports, or our @dbg_@ alias, to avoid the clash.

The meaning of debug levels is up to you. Eg hledger uses them as follows:

@
Debug level:  What to show:
------------  ---------------------------------------------------------
0             normal program output only
1             useful warnings, most common troubleshooting info, phase timings
2             common troubleshooting info, more detail
3             report options selection
4             report generation
5             report generation, more detail
6             input file reading
7             input file reading, more detail
8             command line parsing
9             any other rarely needed / more in-depth info
@

It's not yet possible to select debug output by topic; that would be useful.

-}

-- Disabled until 0.1.2.0 is released with windows support:
--  This module also exports Debug.Trace and the breakpoint package's Debug.Breakpoint.

-- more:
-- http://hackage.haskell.org/packages/archive/TraceUtils/0.1.0.2/doc/html/Debug-TraceUtils.html
-- http://hackage.haskell.org/packages/archive/trace-call/0.1/doc/html/Debug-TraceCall.html
-- http://hackage.haskell.org/packages/archive/htrace/0.1/doc/html/Debug-HTrace.html
-- http://hackage.haskell.org/packages/archive/traced/2009.7.20/doc/html/Debug-Traced.html
-- https://hackage.haskell.org/package/debug

-- internal helpers, currently not exported:

-- * Tracing to stderr
-- These print to stderr.
-- This output will be interleaved with the program's normal output,
-- which can be helpful for understanding code execution.
--
-- ,traceWith
-- ,traceAt
-- ,traceAtWith
-- ,ptrace
-- ,ptraceAt
-- ,ptraceAtIO

-- * Logging to a log file
-- These append to a PROGRAM.log file in the current directory.
-- PROGRAM is normally the name of the executable, but it can change
-- eg when running in GHCI. So when using these, you should call
-- @withProgName@ to ensure a stable program name.
-- Eg: @main = withProgName "PROGRAM" $ do ...@.
--
-- ,log'
-- ,logAt
-- ,logIO
-- ,logAtIO
-- ,logWith
-- ,logAtWith
-- ,plogAt
-- ,plogAtIO

{-# LANGUAGE CPP #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

module Hledger.Utils.Debug (

  -- * Debug level
  debugLevel

  -- * Trace/log a string
  ,dbgMsg
  ,dbg0Msg
  ,dbg1Msg
  ,dbg2Msg
  ,dbg3Msg
  ,dbg4Msg
  ,dbg5Msg
  ,dbg6Msg
  ,dbg7Msg
  ,dbg8Msg
  ,dbg9Msg

  -- * Trace/log a string in IO
  ,dbgMsgIO
  ,dbg0MsgIO
  ,dbg1MsgIO
  ,dbg2MsgIO
  ,dbg3MsgIO
  ,dbg4MsgIO
  ,dbg5MsgIO
  ,dbg6MsgIO
  ,dbg7MsgIO
  ,dbg8MsgIO
  ,dbg9MsgIO

  -- * Trace/log a value
  ,dbg
  ,dbg_
  ,dbg0
  ,dbg1
  ,dbg2
  ,dbg3
  ,dbg4
  ,dbg5
  ,dbg6
  ,dbg7
  ,dbg8
  ,dbg9

  -- * Trace/log a value in IO
  ,dbgIO
  ,dbg0IO
  ,dbg1IO
  ,dbg2IO
  ,dbg3IO
  ,dbg4IO
  ,dbg5IO
  ,dbg6IO
  ,dbg7IO
  ,dbg8IO
  ,dbg9IO

  -- * Trace/log a value with a show function
  ,dbgWith
  ,dbg0With
  ,dbg1With
  ,dbg2With
  ,dbg3With
  ,dbg4With
  ,dbg5With
  ,dbg6With
  ,dbg7With
  ,dbg8With
  ,dbg9With

  -- * Trace/log phase timings
  ,dbgTime
  ,dbgTimeIO
  ,dbgTimeResetIO

  -- * Utilities
  ,lbl_
  ,progName

  -- * ghc-debug helpers
  ,ghcDebugSupportedInLib
  ,GhcDebugMode(..)
  ,ghcDebugMode
  ,withGhcDebug'
  ,ghcDebugPause'

  -- * Re-exports: Debug.Trace
  -- ,module Debug.Breakpoint
  ,module Debug.Trace

  )
where

import Control.DeepSeq (NFData, force)
import Control.Exception (evaluate)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Int (Int64)
import Data.List hiding (uncons)
import Debug.Trace (trace, traceIO, traceShowId)
import GHC.Clock (getMonotonicTime)
import GHC.Conc (getAllocationCounter)
#ifdef GHCDEBUG
import GHC.Debug.Stub (pause, withGhcDebug)
#endif
import Safe (readDef)
import System.Environment (getProgName)
-- import System.Exit (exitFailure)
import System.IO.Unsafe (unsafePerformIO)
import Text.Printf (printf)

import Hledger.Utils.IO (progArgs, pshow, pshow')


-- | The program name as returned by @getProgName@.
-- It's best to set this explicitly at program startup with @withProgName@,
-- otherwise when running in GHCI (eg) it will change to "<interactive>".
-- Setting it with a ".log" suffix causes some functions below
-- to log instead of trace.
{-# NOINLINE modifiedProgName #-}
modifiedProgName :: String
modifiedProgName = unsafePerformIO getProgName

-- | The progam name, with any ".log" suffix removed.
progName :: String
progName =
  if ".log" `isSuffixOf` modifiedProgName
  then reverse $ drop 4 $ reverse modifiedProgName
  else modifiedProgName

-- | The program's debug output verbosity, from 0 to 9.
-- The default is 0 meaning no debug output.
-- This can be overridden by running the program with a --debug [1-9] command line option;
-- a --debug flag with no value means 1.
-- Uses unsafePerformIO to read the command line.
-- When running in GHCI, changing this requires reloading this module.
debugLevel :: Int
debugLevel = case dropWhile (/="--debug") progArgs of
               ["--debug"]   -> 1
               "--debug":n:_ -> readDef 1 n
               _             ->
                 case take 1 $ filter ("--debug" `isPrefixOf`) progArgs of
                   ['-':'-':'d':'e':'b':'u':'g':'=':v] -> readDef 1 v
                   _                                   -> 0

-- | Trace (print to stderr) a string if the program debug level is at
-- or above the specified level. At level 0, always prints. Otherwise,
-- uses unsafePerformIO.
traceAt :: Int -> String -> a -> a
traceAt level
    | level > 0 && debugLevel < level = const id
    | otherwise = trace

-- | Like traceAt, but sequences properly in IO.
traceAtIO :: (MonadIO m) => Int -> String -> m ()
traceAtIO level msg =
  if level > 0 && debugLevel < level
  then return ()
  else liftIO $ traceIO msg

-- -- | Trace a value with the given show function before returning it.
-- traceWith :: (a -> String) -> a -> a
-- traceWith f a = trace (f a) a

-- | Trace (print to stderr) a showable value using a custom show function,
-- if the program debug level is at or above the specified level.
-- At level 0, always prints. Otherwise, uses unsafePerformIO.
traceAtWith :: Int -> (a -> String) -> a -> a
traceAtWith level f a = traceAt level (f a) a

-- -- | Pretty-trace a showable value before returning it.
-- -- Like Debug.Trace.traceShowId, but pretty-printing and easier to type.
-- ptrace :: Show a => a -> a
-- ptrace = traceWith pshow

-- | Pretty-print a label and a showable value to the console
-- if the program debug level is at or above the specified level.
-- At level 0, always prints. Otherwise, uses unsafePerformIO.
ptraceAt :: Show a => Int -> String -> a -> a
ptraceAt level
    | level > 0 && debugLevel < level = const id
    | otherwise = \lbl a -> trace (labelledPretty True lbl a) a

-- Pretty-print a showable value with a label, with or without allowing ANSI color.
labelledPretty :: Show a => Bool -> String -> a -> String
labelledPretty allowcolour lbl a = lbl ++ ":" ++ nlorspace ++ intercalate "\n" ls'
  where
    ls = lines $ (if allowcolour then pshow else pshow') a
    nlorspace | length ls > 1 = "\n"
              | otherwise     = replicate (max 1 $ 11 - length lbl) ' '
    ls' | length ls > 1 = map (' ':) ls
        | otherwise     = ls

-- | Like ptraceAt, but sequences properly in IO.
ptraceAtIO :: (MonadIO m, Show a) => Int -> String -> a -> m ()
ptraceAtIO level label a =
  if level > 0 && debugLevel < level
  then return ()
  else liftIO $ traceIO (labelledPretty True label a)


-- | The debug log file: PROGNAME.log in the current directory.
-- See modifiedProgName.
debugLogFile :: FilePath
debugLogFile = progName ++ ".log"

-- | Log a string to the debug log before returning the second argument.
-- Uses unsafePerformIO.
log' :: String -> a -> a
log' s x = unsafePerformIO $ do
  evaluate (force s)  -- to complete any previous logging before we attempt more
  appendFile debugLogFile (s ++ "\n")
  return x

-- | Log a string to the debug log before returning the second argument,
-- if the program debug level is at or above the specified level.
-- At level 0, always logs. Otherwise, uses unsafePerformIO.
logAt :: Int -> String -> a -> a
logAt level str
  | level > 0 && debugLevel < level = id
  | otherwise = log' str

-- | Like log' but sequences properly in IO.
logIO :: MonadIO m => String -> m ()
logIO s = do
  liftIO $ evaluate (force s)  -- to complete any previous logging before we attempt more
  liftIO $ appendFile debugLogFile (s ++ "\n")

-- | Like logAt, but convenient to use in IO.
logAtIO :: (MonadIO m) => Int -> String -> m ()
logAtIO level str
  | level > 0 && debugLevel < level = return ()
  | otherwise = logIO str

-- -- | Log a value to the debug log with the given show function before returning it.
-- logWith :: (a -> String) -> a -> a
-- logWith f a = log' (f a) a

-- | Log a string to the debug log before returning the second argument,
-- if the program debug level is at or above the specified level.
-- At level 0, always logs. Otherwise, uses unsafePerformIO.
logAtWith :: Int -> (a -> String) -> a -> a
logAtWith level f a = logAt level (f a) a

-- | Pretty-log a label and showable value to the debug log,
-- if the program debug level is at or above the specified level. 
-- At level 0, always prints. Otherwise, uses unsafePerformIO.
plogAt :: (Show a) => Int -> String -> a -> a
plogAt level
  | level > 0 && debugLevel < level = const id
  | otherwise = \lbl a -> log' (labelledPretty False lbl a) a

-- | Like ptraceAt, but sequences properly in IO.
plogAtIO :: (MonadIO m, Show a) => Int -> String -> a -> m ()
plogAtIO level label a =
  if level > 0 && debugLevel < level
  then return ()
  else logIO (labelledPretty False label a)


-- | Should dbg* log to a file instead of tracing to stderr ?
-- True if the (internal) program name ends with ".log".
shouldLog :: Bool
shouldLog = ".log" `isSuffixOf` modifiedProgName


-- | Trace or log a string if the program debug level is at or above the specified level,
-- then return the second argument.
dbgMsg :: Int -> String -> a -> a
dbgMsg = if shouldLog then logAt else traceAt

dbg0Msg :: String -> a -> a
dbg0Msg = dbgMsg 0

dbg1Msg :: String -> a -> a
dbg1Msg = dbgMsg 1

dbg2Msg :: String -> a -> a
dbg2Msg = dbgMsg 2

dbg3Msg :: String -> a -> a
dbg3Msg = dbgMsg 3

dbg4Msg :: String -> a -> a
dbg4Msg = dbgMsg 4

dbg5Msg :: String -> a -> a
dbg5Msg = dbgMsg 5

dbg6Msg :: String -> a -> a
dbg6Msg = dbgMsg 6

dbg7Msg :: String -> a -> a
dbg7Msg = dbgMsg 7

dbg8Msg :: String -> a -> a
dbg8Msg = dbgMsg 8

dbg9Msg :: String -> a -> a
dbg9Msg = dbgMsg 9


-- | Like dbgMsg, but sequences properly in IO.
dbgMsgIO :: (MonadIO m) => Int -> String -> m ()
dbgMsgIO = if shouldLog then logAtIO else traceAtIO

dbg0MsgIO :: (MonadIO m) => String -> m ()
dbg0MsgIO = dbgMsgIO 0

dbg1MsgIO :: (MonadIO m) => String -> m ()
dbg1MsgIO = dbgMsgIO 1

dbg2MsgIO :: (MonadIO m) => String -> m ()
dbg2MsgIO = dbgMsgIO 2

dbg3MsgIO :: (MonadIO m) => String -> m ()
dbg3MsgIO = dbgMsgIO 3

dbg4MsgIO :: (MonadIO m) => String -> m ()
dbg4MsgIO = dbgMsgIO 4

dbg5MsgIO :: (MonadIO m) => String -> m ()
dbg5MsgIO = dbgMsgIO 5

dbg6MsgIO :: (MonadIO m) => String -> m ()
dbg6MsgIO = dbgMsgIO 6

dbg7MsgIO :: (MonadIO m) => String -> m ()
dbg7MsgIO = dbgMsgIO 7

dbg8MsgIO :: (MonadIO m) => String -> m ()
dbg8MsgIO = dbgMsgIO 8

dbg9MsgIO :: (MonadIO m) => String -> m ()
dbg9MsgIO = dbgMsgIO 9


-- | Trace or log a label and showable value, pretty-printed,
-- if the program debug level is at or above the specified level;
-- then return the value.
dbg :: (Show a) => Int -> String -> a -> a
dbg = if shouldLog then plogAt else ptraceAt

-- | Alias for dbg, can be used to avoid namespace clashes.
dbg_ :: (Show a) => Int -> String -> a -> a
dbg_ = dbg

dbg0 :: Show a => String -> a -> a
dbg0 = dbg 0

dbg1 :: Show a => String -> a -> a
dbg1 = dbg 1

dbg2 :: Show a => String -> a -> a
dbg2 = dbg 2

dbg3 :: Show a => String -> a -> a
dbg3 = dbg 3

dbg4 :: Show a => String -> a -> a
dbg4 = dbg 4

dbg5 :: Show a => String -> a -> a
dbg5 = dbg 5

dbg6 :: Show a => String -> a -> a
dbg6 = dbg 6

dbg7 :: Show a => String -> a -> a
dbg7 = dbg 7

dbg8 :: Show a => String -> a -> a
dbg8 = dbg 8

dbg9 :: Show a => String -> a -> a
dbg9 = dbg 9


-- | Like dbg, but sequences properly in IO.
dbgIO :: (MonadIO m, Show a) => Int -> String -> a -> m ()
dbgIO = if shouldLog then plogAtIO else ptraceAtIO

dbg0IO :: (MonadIO m, Show a) => String -> a -> m ()
dbg0IO = dbgIO 0

dbg1IO :: (MonadIO m, Show a) => String -> a -> m ()
dbg1IO = dbgIO 1

dbg2IO :: (MonadIO m, Show a) => String -> a -> m ()
dbg2IO = dbgIO 2

dbg3IO :: (MonadIO m, Show a) => String -> a -> m ()
dbg3IO = dbgIO 3

dbg4IO :: (MonadIO m, Show a) => String -> a -> m ()
dbg4IO = dbgIO 4

dbg5IO :: (MonadIO m, Show a) => String -> a -> m ()
dbg5IO = dbgIO 5

dbg6IO :: (MonadIO m, Show a) => String -> a -> m ()
dbg6IO = dbgIO 6

dbg7IO :: (MonadIO m, Show a) => String -> a -> m ()
dbg7IO = dbgIO 7

dbg8IO :: (MonadIO m, Show a) => String -> a -> m ()
dbg8IO = dbgIO 8

dbg9IO :: (MonadIO m, Show a) => String -> a -> m ()
dbg9IO = dbgIO 9


-- | Like dbg, but with a custom show function.
dbgWith :: Int -> (a -> String) -> a -> a
dbgWith = if shouldLog then logAtWith else traceAtWith

dbg0With :: (a -> String) -> a -> a
dbg0With = dbgWith 0

dbg1With :: (a -> String) -> a -> a
dbg1With = dbgWith 1

dbg2With :: (a -> String) -> a -> a
dbg2With = dbgWith 2

dbg3With :: (a -> String) -> a -> a
dbg3With = dbgWith 3

dbg4With :: (a -> String) -> a -> a
dbg4With = dbgWith 4

dbg5With :: (a -> String) -> a -> a
dbg5With = dbgWith 5

dbg6With :: (a -> String) -> a -> a
dbg6With = dbgWith 6

dbg7With :: (a -> String) -> a -> a
dbg7With = dbgWith 7

dbg8With :: (a -> String) -> a -> a
dbg8With = dbgWith 8

dbg9With :: (a -> String) -> a -> a
dbg9With = dbgWith 9


-- | Wall clock seconds (from a monotonic clock), and the current thread's allocation counter
-- (which counts downwards, so bytes allocated = earlier reading - later reading).
type TimeReadings = (Double, Int64)

timeReadings :: IO TimeReadings
timeReadings = (,) <$> getMonotonicTime <*> getAllocationCounter

-- | The sum of the phase times reported so far (since program start, or the last dbgTimeResetIO),
-- and the readings taken at the most recent phase timing (or at first use).
{-# NOINLINE dbgTimeState #-}
dbgTimeState :: IORef (Double, TimeReadings)
dbgTimeState = unsafePerformIO $ timeReadings >>= \r -> newIORef (0, r)

-- | Reset the baseline for phase timings (see dbgTime) to now.
-- hledger calls this at program start, so that the first timing line includes startup time.
dbgTimeResetIO :: MonadIO m => m ()
dbgTimeResetIO = liftIO $ timeReadings >>= \r -> writeIORef dbgTimeState (0, r)

-- | Trace or log a phase timing line, if the program debug level is at or above the specified level:
-- the label, the wall clock time and megabytes allocated since the previous phase timing
-- (or since program start), and the sum of the phase times reported so far; then return the value.
-- The value is deep-forced first, so that the work of producing it is charged to this phase;
-- the cost of the deep-forcing itself (traversing the whole value) is measured and excluded.
-- When the debug level is lower, the value is returned unforced.
-- Uses unsafePerformIO; in IO code, prefer dbgTimeIO.
dbgTime :: NFData a => Int -> String -> a -> a
dbgTime level lbl x
  | level > 0 && debugLevel < level = x
  | otherwise = unsafePerformIO $ dbgTimeIO level lbl x
{-# NOINLINE dbgTime #-}

-- | Like dbgTime, but sequences properly in IO.
dbgTimeIO :: (MonadIO m, NFData a) => Int -> String -> a -> m a
dbgTimeIO level lbl x
  | level > 0 && debugLevel < level = return x
  | otherwise = liftIO $ do
      _ <- readIORef dbgTimeState  -- initialise the baseline now, if this is the first use
      x' <- evaluate (force x)
      (total, (tprev, aprev)) <- readIORef dbgTimeState  -- (the latest timing may have happened during the forcing)
      (t1, a1) <- timeReadings
      -- Deep-forcing a large value costs something even when it is already evaluated;
      -- measure that by traversing it once more, and exclude it from this phase's figures.
      _ <- evaluate (force x')
      (t2, a2) <- timeReadings
      let dt = max 0 $ (t1 - tprev) - (t2 - t1)
          da = max 0 $ (aprev - a1) - (a1 - a2)
          total' = total + dt
      writeIORef dbgTimeState (total', (t2, a2))
      dbgMsgIO level $ printf "%-44s %7.3fs %9.1f MB  (%.3fs so far)" lbl dt (fromIntegral da / 1e6 :: Double) total'
      return x'

-- | Helper for producing debug messages:
-- concatenates a name (eg a function name),
-- short description of the value being logged,
-- and string representation of the value.
--
-- Eg: @let lbl = lbl_ "print"@,
-- @dbg1With (lbl "part 1".show) ...@.
--
lbl_ :: String -> String -> String -> String
lbl_ name desc val = name <> ": " <> desc <> ":" <> " " <> val

-- XXX the resulting function is constrained to only one value type
-- -- | A helper for defining a local "dbg" function.
-- -- Given a debug level and a topic string (eg, a function name),
-- -- it generates a function which takes
-- -- - a description string,
-- -- - a value-to-string show function,
-- -- - and a value to be inspected,
-- -- debug-logs the topic, description and result of calling the show function on the value,
-- -- formatted nicely, at the specified debug level or above,
-- -- then returns the value.
-- dbg_ :: forall a. Int -> String -> (String -> (a -> String) -> a -> a)
-- dbg_ level topic =
--   \desc showfn val ->
--     dbgWith level (lbl_ topic desc . showfn) val
-- {-# HLINT ignore "Redundant lambda" #-}


-- | Whether ghc-debug support is included in this build, and if so, how it will behave.
-- When hledger is built with the @ghcdebug@ cabal flag (off by default, because of extra deps),
-- it can listen (on unix ?) for connections from ghc-debug clients like ghc-debug-brick,
-- for pausing/resuming the program and inspecting memory usage and profile information.
--
-- With a ghc-debug-supporting build, ghc-debug can be enabled by running hledger with
-- a negative --debug level. There are three different modes:
-- --debug=-1 - run normally (can be paused/resumed by a ghc-debug client),
-- --debug=-2 - pause and await client commands at program start (not useful currently),
-- --debug=-3 - pause and await client commands at program end.
data GhcDebugMode =
    GDNotSupported
  | GDDisabled
  | GDNoPause
  | GDPauseAtStart
  | GDPauseAtEnd
  -- keep synced with ghcDebugMode
  deriving (Eq,Ord,Show)

-- | Is the hledger-lib package built with ghc-debug support ?
ghcDebugSupportedInLib :: Bool
ghcDebugSupportedInLib =
#ifdef GHCDEBUG
  True
#else
  False
#endif

-- | Should the program open a socket allowing control by ghc-debug-brick or similar ghc-debug client ?
-- See GhcDebugMode.
ghcDebugMode :: GhcDebugMode
ghcDebugMode =
#ifdef GHCDEBUG
  case debugLevel of
    _ | not ghcDebugSupportedInLib -> GDNotSupported
    (-1) -> GDNoPause
    (-2) -> GDPauseAtStart
    (-3) -> GDPauseAtEnd
    _    -> GDDisabled
    -- keep synced with GhcDebugMode
#else
  GDNotSupported
#endif

-- | When ghc-debug support has been built into the program and enabled at runtime with --debug=-N,
-- this calls ghc-debug's withGhcDebug; otherwise it's a no-op.
withGhcDebug' =
#ifdef GHCDEBUG
  if ghcDebugMode > GDDisabled then withGhcDebug else id
#else
  id
#endif

-- | When ghc-debug support has been built into the program, this calls ghc-debug's pause, otherwise it's a no-op.
ghcDebugPause' :: IO ()
ghcDebugPause' =
#ifdef GHCDEBUG
  pause
#else
  return ()
#endif
