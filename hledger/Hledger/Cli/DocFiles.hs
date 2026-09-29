{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-|

Embedded documentation files in various formats, and helpers for viewing them.

|-}

module Hledger.Cli.DocFiles (

   Topic
  ,TopicResolution(..)
  ,manualTitle
  ,manualHeadings
  ,manualTopicsMatching
  ,resolveManualTopic
  ,printHelpForTopic
  ,runManForTopic
  ,runInfoForTopic
  ,runPagerForTopic
  ,runTldrForPage

  ) where

import Control.Exception
import Data.ByteString (ByteString)
import Data.Char (isUpper, isLower, toLower)
import Data.ByteString.Char8 qualified as BC
import Data.List (dropWhileEnd, isInfixOf, isPrefixOf, nub)
import Data.Maybe (fromMaybe, maybeToList)
import Data.String
import System.Directory (findExecutable)
import System.Environment (setEnv)
import System.IO
import System.IO.Temp
import System.Process

import Hledger.Utils (first3, second3, third3, embedFileRelative, error', shellQuoteIfNeeded)
import Text.Printf (printf)
import System.Environment (lookupEnv)
import Hledger.Utils.Debug

-- The name of any hledger executable.
type Tool = String

-- Any heading in the hledger user manual (and perhaps later the hledger-ui/hledger-web manuals).
type Topic = String

-- Any name of a hledger tldr page (hledger, hledger-ui, hledger-print etc.)
type TldrPage = String

-- | All hledger-related pages from the tldr-pages project.
-- All are symlinked into the hledger package directory to allow embeddeding.
tldrs :: [(TldrPage, ByteString)]
tldrs = [
   ("hledger-accounts",        $(embedFileRelative "embeddedfiles/hledger-accounts.md"))
  ,("hledger-add",             $(embedFileRelative "embeddedfiles/hledger-add.md"))
  ,("hledger-aregister",       $(embedFileRelative "embeddedfiles/hledger-aregister.md"))
  ,("hledger-balance",         $(embedFileRelative "embeddedfiles/hledger-balance.md"))
  ,("hledger-balancesheet",    $(embedFileRelative "embeddedfiles/hledger-balancesheet.md"))
  ,("hledger-import",          $(embedFileRelative "embeddedfiles/hledger-import.md"))
  ,("hledger-incomestatement", $(embedFileRelative "embeddedfiles/hledger-incomestatement.md"))
  ,("hledger-print",           $(embedFileRelative "embeddedfiles/hledger-print.md"))
  ,("hledger-ui",              $(embedFileRelative "embeddedfiles/hledger-ui.md"))
  ,("hledger-web",             $(embedFileRelative "embeddedfiles/hledger-web.md"))
  ,("hledger",                 $(embedFileRelative "embeddedfiles/hledger.md"))
  ]

-- | The main hledger manuals as source for man, info and as plain text.
-- All are symlinked into the hledger package directory to allow embeddeding.
manuals :: [(Tool, (ByteString, ByteString, ByteString))]
manuals = [
   ("hledger",
    ($(embedFileRelative "embeddedfiles/hledger.1")
    ,$(embedFileRelative "embeddedfiles/hledger.txt")
    ,$(embedFileRelative "embeddedfiles/hledger.info")
    ))
  ,("hledger-ui",
    ($(embedFileRelative "embeddedfiles/hledger-ui.1")
    ,$(embedFileRelative "embeddedfiles/hledger-ui.txt")
    ,$(embedFileRelative "embeddedfiles/hledger-ui.info")
    ))
  ,("hledger-web",
    ($(embedFileRelative "embeddedfiles/hledger-web.1")
    ,$(embedFileRelative "embeddedfiles/hledger-web.txt")
    ,$(embedFileRelative "embeddedfiles/hledger-web.info")
    ))
  ]

-- | Get the manual as plain text for this tool, or a not found message.
manualTxt :: Tool -> ByteString
manualTxt name = maybe (fromString $ "No text manual found for tool: "++name) second3 $ lookup name manuals

-- | This tool's manual title, taken from the top running-header line
-- (eg "HLEDGER(1)  hledger User Manuals  HLEDGER(1)"), with the "(N)" section
-- number stripped (eg "HLEDGER"). Nothing if the manual has no such header.
-- Note this title is not itself a line the viewers can scroll to, so callers
-- resolving a topic to it should show the manual from the top.
manualTitle :: Tool -> Maybe Topic
manualTitle tool = case dropWhile null . lines . BC.unpack $ manualTxt tool of
  (l:_) | (w:_) <- words l, '(' `elem` w -> Just $ takeWhile (/= '(') w
  _                                       -> Nothing

-- | The section headings in this tool's manual, each with its hierarchy level,
-- usable as help topics. Some heading hierarchy is lost in the rendered plain
-- text, but we recover an approximate level for each: the manual title (see
-- 'manualTitle') is level 1; an all-caps column-0 heading (eg OPTIONS,
-- PART 1: ...) is level 2; any other column-0 heading (eg Options, Journal) is
-- level 3; and a heading indented three spaces is level 4. Headings are
-- non-blank lines at the left margin or indented exactly three spaces,
-- containing no run of two or more spaces (which would indicate wrapped prose,
-- a table, an option entry, or a running header). The standard man-page
-- headings NAME, SYNOPSIS and DESCRIPTION are dropped, as they aren't useful
-- topics and their generic names could clash with real ones.
manualHeadings :: Tool -> [(Topic, Int)]
manualHeadings tool = maybeToList (fmap (\t -> (t, 1)) $ manualTitle tool) ++ sections
  where
    sections =
      [ hl
      | l <- lines . BC.unpack $ manualTxt tool
      , hl@(h, _) <- maybeToList $ headingOf l
      , map toLower h `notElem` ["name", "synopsis", "description"]
      ]
    headingOf l = case span (==' ') l of
      ("",    rest) -> (\h -> (h, if level2Caps h then 2 else 3)) <$> headingText rest
      ("   ", rest) -> (\h -> (h, 4))                             <$> headingText rest
      _             -> Nothing
    headingText s
      | null s' || "  " `isInfixOf` s' = Nothing
      | otherwise                      = Just s'
      where s' = dropWhileEnd (==' ') s
    -- An all-caps column-0 heading is normally a level-2 section, except for a
    -- few that are really level-3 subsections, eg CSV (a data format, sibling of
    -- the Journal/Timeclock/Timedot sections).
    level2Caps h = allCaps h && h `notElem` ["CSV"]
    allCaps s = any isUpper s && not (any isLower s)

-- | Every matchable help topic as (name, tool, heading): every manual's headings
-- (each with the tool whose manual it belongs to), given a unique name for
-- matching and listing. The name is the heading, but with "-ui"/"-web" appended
-- for a hledger-ui/hledger-web heading whose bare name also occurs in another
-- manual (so eg OPTIONS becomes OPTIONS-ui / OPTIONS-web, keeping every name
-- unique and unambiguously matchable). hledger headings always keep their bare
-- name, as does any section name unique to one manual.
manualTopics :: [(Topic, Tool, Topic, Int)]
manualTopics = [(topicName tool h, tool, h, lvl) | (tool, (h, lvl)) <- rawpairs]
  where
    rawpairs = [(tool, hl) | tool <- map fst manuals, hl <- manualHeadings tool]
    manualsWith lch = nub [tool | (tool, (h, _)) <- rawpairs, map toLower h == lch]
    topicName tool h = case tool of
      "hledger-ui"  | shared -> h ++ "-ui"
      "hledger-web" | shared -> h ++ "-web"
      _                      -> h
      where shared = length (manualsWith (map toLower h)) > 1

-- | The result of resolving a user-supplied topic against all the manuals'
-- topics. A found match carries the tool whose manual it belongs to and the
-- heading to scroll to; an ambiguous match carries the matching topic names,
-- each with its manual heading level (for hierarchical listing).
data TopicResolution = TopicNotFound | TopicFound Tool Topic | TopicAmbiguous [(Topic, Int)]

-- | Resolve a topic to a manual section, searching all the manuals' topic names.
-- A case-insensitive exact match wins; otherwise a unique prefix match is used;
-- otherwise a unique infix match is used. Resolving to a heading (and its tool)
-- lets all viewers (including info and the web anchor) locate the section
-- reliably, and lets callers respond to a bad topic. When the match is
-- ambiguous, all matches of any kind (ie all infix matches) are listed.
resolveManualTopic :: Topic -> TopicResolution
resolveManualTopic topic =
  case exacts of
    [tp] -> found tp
    []   -> case (prefixes, infixes) of
      ([tp], _)  -> found tp
      ([], [tp]) -> found tp
      ([], [])   -> TopicNotFound
      (_,  tps)  -> TopicAmbiguous (map nameLevel tps)
    _    -> TopicAmbiguous (map nameLevel infixes)
  where
    exacts   = nub $ filter ((== t)          . lc . name) manualTopics
    prefixes = nub $ filter ((t `isPrefixOf`) . lc . name) manualTopics
    infixes  = nub $ filter ((t `isInfixOf`)  . lc . name) manualTopics
    found (_, tool, h, _) = TopicFound tool h
    name (n, _, _, _) = n
    nameLevel (n, _, _, lvl) = (n, lvl)
    lc = map toLower
    t  = lc . dropWhileEnd (==' ') $ dropWhile (==' ') topic

-- | The topic names (each with its manual heading level, for hierarchical
-- listing) that contain the given topic as a case-insensitive substring (all
-- topics if the topic is empty). Used by help's -l list mode.
manualTopicsMatching :: Topic -> [(Topic, Int)]
manualTopicsMatching topic = nub $ map nameLevel $ filter ((t `isInfixOf`) . lc . name) manualTopics
  where
    name (n, _, _, _) = n
    nameLevel (n, _, _, lvl) = (n, lvl)
    lc = map toLower
    t  = lc . dropWhileEnd (==' ') $ dropWhile (==' ') topic

-- | Get the manual as man source (nroff) for this tool, or a not found message.
manualMan :: Tool -> ByteString
manualMan name = maybe (fromString $ "No man page found for tool: "++name) first3 $ lookup name manuals

-- | Get the manual as info source (texinfo) for this tool, or a not found message.
manualInfo :: Tool -> ByteString
manualInfo name = maybe (fromString $ "No info manual found for tool: "++name) third3 $ lookup name manuals

-- | Print plain text help for this tool. This is the fallback "viewer" used
-- for non-interactive output or a dumb terminal, where no pager is available.
-- To avoid dumping the whole (large) manual, when no topic is requested we print
-- only the introduction: everything up to and including the DESCRIPTION section
-- (ie stopping at the first all-caps top-level heading after it, such as PART 1),
-- followed by a note on how to read the rest.
-- If a topic is requested, or there's no DESCRIPTION heading (eg the
-- hledger-ui/hledger-web manuals), the whole manual is printed.
printHelpForTopic :: Tool -> Maybe Topic -> IO ()
printHelpForTopic tool mtopic = do
  let manual = manualTxt tool
  case mtopic of
    Just _  -> BC.putStr manual  -- topic requested: show all, so it isn't hidden
    Nothing ->
      case break (== "DESCRIPTION") (BC.lines manual) of
        (_, [])              -> BC.putStr manual  -- no DESCRIPTION heading: show all
        (before, desc:after) ->
          case break isTopHeading after of
            (_, [])       -> BC.putStr manual  -- no following heading: show all
            (body, _)     -> do
              BC.putStr $ BC.unlines $ before ++ desc : body
              BC.putStrLn helpTruncationNote

-- | Is this a top-level manual heading: a non-empty line starting in column 0
-- with an uppercase letter and containing no lowercase letters (eg NAME, PART 1: ...)?
isTopHeading :: ByteString -> Bool
isTopHeading l = case BC.uncons l of
  Just (c, _) -> isUpper c && not (BC.any isLower l)
  Nothing     -> False

-- | Note appended to the truncated plain-text help.
helpTruncationNote :: ByteString
helpTruncationNote =
  "(This is just the introduction. To read the full manual, run `hledger help`\n\
  \in a more capable terminal, or `hledger help -p` (pager), `-m` (man) or `-i`\n\
  \(info), or see https://hledger.org.)"

-- | Display an info manual for this topic, opened at the given topic if provided,
-- using the "info" executable in $PATH.
-- Topic can be an exact heading or a heading prefix; info will favour an exact match.
runInfoForTopic :: Tool -> Maybe Topic -> IO ()
runInfoForTopic tool mtopic =
  withSystemTempFile ("hledger-"++tool++".info") $ \f h -> do
    BC.hPutStrLn h $ manualInfo tool
    hClose h
    callCommand $ dbg1 "info command" $
      "info -f " ++ shellQuoteIfNeeded f ++ maybe "" (printf " -n '%s'") mtopic

-- less with any vertical whitespace squashed, case-insensitive searching, the $ regex metacharacter accessible as \$.
less = "less -s -i --use-backslash"

-- | Display plain text help for this tool, scrolled to the given topic if any, using the users $PAGER or "less".
-- When a topic is provided we always use less, ignoring $PAGER.
--
-- This is less robust than the newer Hledger.Utils.IO.runPager,
-- but that one doesn't yet support scrolling to a topic.
runPagerForTopic :: Tool -> Maybe Topic -> IO ()
runPagerForTopic tool mtopic = do
  withSystemTempFile ("hledger-"++tool++".txt") $ \f h -> do
    BC.hPutStrLn h $ manualTxt tool
    hClose h
    envpager <- fromMaybe less <$> lookupEnv "PAGER"
    let
      exactmatch = True
      (pager, searcharg) =
        case mtopic of
          Nothing -> (envpager, "")
          Just t  -> (less, "-p'^(   )?" ++ t ++ if exactmatch then "\\$'" else "")
    callCommand $ dbg1 "pager command" $ unwords [pager, searcharg, shellQuoteIfNeeded f]

-- | Display a man page for this tool, scrolled to the given topic if provided, using "man".
-- When a topic is provided we force man to use "less", ignoring $MANPAGER and $PAGER.
runManForTopic :: Tool -> Maybe Topic -> IO ()
runManForTopic tool mtopic =
  -- This temp file path should have a slash in it, man requires at least one.
  withSystemTempFile ("hledger-"++tool++".1") $ \f h -> do
    BC.hPutStrLn h $ manualMan tool
    hClose h
    let
      exactmatch = True
      pagerarg =
        case mtopic of
          Nothing -> ""
          Just t  -> "-P \"" ++ less ++ " -p'^(   )?" ++ t ++ (if exactmatch then "\\\\$" else "") ++ "'\""
    callCommand $ dbg1 "man command" $ unwords ["man", pagerarg, shellQuoteIfNeeded f]

-- | Get the named tldr page's source, if we know it.
tldr :: TldrPage -> Maybe ByteString
tldr name = lookup name tldrs

-- | Display one of the hledger tldr pages, using "tldr".
runTldrForPage :: TldrPage -> IO ()
runTldrForPage name =
  case tldr name of
    Nothing -> error' $ "sorry, there are no examples for " <> name <> " yet"
    Just b -> do
      let fallback = do
            hPutStrLn stderr "Warning: could not run tldr --render, using fallback viewer instead.\n"
            BC.putStrLn b
      -- Check for a tldr client first, so we can fall back quietly without the
      -- shell printing a "command not found" error.
      mtldr <- findExecutable "tldr"
      case mtldr of
        Nothing -> fallback
        Just _ -> (do
          withSystemTempFile (name++".md") $ \f h -> do
            BC.hPutStrLn h b
            hClose h
            -- tldr clients tend to auto-update their data, try to discourage that here
            -- tealdeer - doesn't auto-update by default
            -- tlrc - ?
            -- tldr-node-client - undocumented env var suggested in output
            setEnv "TLDR_AUTO_UPDATE_DISABLED" "1"
            callCommand $ dbg1 "tldr command" $ "tldr --render " <> shellQuoteIfNeeded f
          ) `catch` (\(_e::IOException) -> fallback)
