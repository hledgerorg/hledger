{-|

The help command.

|-}
--TODO rename manuals
--TODO substring matching

{-# LANGUAGE PackageImports #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Help (

   helpmode
  ,manual

  ) where

import Control.Monad (void)
import Data.Char (toLower)
import Data.List (isInfixOf)
import Data.Maybe
import System.Console.CmdArgs.Explicit
import System.Environment
import System.IO

import Hledger.Cli.CliOptions
import Hledger.Cli.DocFiles
import Hledger.Cli.Utils (openBrowserOn)
import Hledger.Cli.Version (webManualUrl)
import Hledger.Data.RawOptions
import Hledger.Utils (embedFileRelative, runPager, titleLine)
--import Hledger.Utils.Debug

helpmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Help.txt")
  -- The help-* names avoid a clash with the --info and --man flags handled in Cli.hs.
  [flagNone ["i"] (setboolopt "help-i") "use info when showing the manual"
  ,flagNone ["m"] (setboolopt "help-m") "use man when showing the manual"
  ,flagNone ["p"] (setboolopt "help-p") "use less (or $PAGER) when showing the manual"
  ,flagNone ["w"] (setboolopt "help-w") "use a web browser when showing the manual"
  ,flagNone ["l"] (setboolopt "help-l") "just list the manual topics matching TOPIC"
  -- These three limit the commands list to one category of command; with none of them, all are shown.
  ,flagNone ["builtins"] (setboolopt "builtins") "with commands: show only builtin commands"
  ,flagNone ["addons"]   (setboolopt "addons")   "with commands: show only addon commands"
  ,flagNone ["aliases"]  (setboolopt "aliases")  "with commands: show only command aliases"
  ]
  [(helpflagstitle, helpflags)]
  hiddenflags  -- accept --conf/--no-conf etc., eg so "help commands" can show config aliases
  ([], Just $ argsFlag "[TOPIC]")

-- | Display the hledger manual in various formats, optionally positioned at the given topic.
-- You can select a docs viewer with one of the `--info`, `--man`, `--pager` flags.
-- Otherwise it will use the first available of: info, man, $PAGER, less, stdout
-- (and always stdout if output is non-interactive, the terminal is dumb, or we are
-- in an Emacs buffer that can't render fullscreen viewers, eg shell/comint or eshell).
manual :: CliOpts -> Maybe Topic -> IO ()
manual opts mtopic
  -- With -l, just list the matching topics rather than showing the manual.
  | listonly  = case manualTopicsMatching topic of
      [] -> notFound
      ts -> listTopics matchingHeading ts
  | otherwise = case resolveManualTopic topic of
      -- The title isn't a line the viewers can scroll to, so show that manual
      -- from the top for it (rather than searching for the title text, which eg
      -- makes info jump to the first node starting with the program name).
      TopicFound tool h
        | Just h == manualTitle tool -> showManualAt tool Nothing
        | otherwise                  -> showManualAt tool (Just h)
      -- No match: show a note on stderr and stop, rather than raising an error.
      TopicNotFound     -> notFound
      -- Several matches (or none requested, ie the empty topic, which matches
      -- every heading): list them so the user can pick a specific topic. This
      -- is what `hledger help manual` (with no topic) does.
      TopicAmbiguous ts -> listTopics ambiguousHeading ts
  where
    listonly = boolopt "help-l" $ rawopts_ opts
    topic    = fromMaybe "" mtopic
    -- Are we listing all the topics (rather than just those matching a TOPIC)?
    listall  = null topic
    -- List the given topic names, in the pager if the list is long and one is available.
    -- When listing all topics, indent each by its manual heading level (minus one)
    -- to show the hierarchy; when listing just the matches, indent them all equally.
    listTopics heading nls = runPager $ unlines $ heading : map fmt nls
      where fmt (n, lvl) = replicate (if listall then lvl - 1 else 2) ' ' <> n
    notFound = hPutStrLn stderr $
      "\"" <> topic <> "\" does not match any manual section heading.\n"
      <> "Run `hledger help manual` to list all topics, or `hledger help` for the quick reference."
    ambiguousHeading
      | null topic = titleLine "HLEDGER MANUAL TOPICS"
      | otherwise  = "\"" <> topic <> "\" matches several manual sections, try a more specific topic:"
    matchingHeading
      | null topic = titleLine "HLEDGER MANUAL TOPICS"
      | otherwise  = "manual topics matching \"" <> topic <> "\":"
    -- Show the given tool's manual, positioned at the given heading if any, in the best viewer.
    showManualAt tool mtopic' = do
      exes <- likelyExecutablesInPath
      pagerprog <- fromMaybe "less" <$> lookupEnv "PAGER"
      interactive <- hIsTerminalDevice stdout
      -- A dumb terminal (eg TERM=dumb, as in emacs shells) can't run info, and
      -- degrades man/less, so fall back to plain text there like the non-interactive case.
      dumbterminal <- ((== "dumb") . map toLower . fromMaybe "") <$> lookupEnv "TERM"
      -- Inside Emacs, only its terminal-emulator modes (term/ansi-term/vterm, whose
      -- INSIDE_EMACS mode contains "term") can render fullscreen viewers like info/man/less;
      -- other modes (shell/comint, eshell) are line-oriented and would garble them, so fall
      -- back to plain text there like the dumb/non-interactive case.
      emacsnonterm <- (\m -> not (null m) && not ("term" `isInfixOf` m)) . fromMaybe "" <$> lookupEnv "INSIDE_EMACS"
      let
        [info, man, pager, cat] =
          [runInfoForTopic, runManForTopic, runPagerForTopic, printHelpForTopic]
        web t mt = void $ openBrowserOn $ webManualUrl t mt
        viewer
          | boolopt "help-w" $ rawopts_ opts = web
          | boolopt "help-i" $ rawopts_ opts = info
          | boolopt "help-m" $ rawopts_ opts = man
          | boolopt "help-p" $ rawopts_ opts = pager
          | not interactive || dumbterminal || emacsnonterm = cat
          | "info"    `elem` exes            = info
          | "man"     `elem` exes            = man
          | pagerprog `elem` exes            = pager
          | "less"    `elem` exes            = pager
          | otherwise                        = cat
      viewer tool mtopic'
