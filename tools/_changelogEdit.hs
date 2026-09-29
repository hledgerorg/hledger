#!/usr/bin/env stack
{- stack script --resolver nightly-2026-04-17
    --package data-default
    --package extra
    --package process
    --package text
-}
{-
    --package hledger-lib
-}
-- changelog.hs CHANGELOGFILE
--
-- Manipulate a hledger changelog. Currently does one thing: prompts
-- for a rewrite of the oldest uncategorised pending changelog item
-- and updates the file, printing a diff.
--
-- My workflow:
-- - In a terminal window (not emacs shell, it will hang) run this on a CHANGES.md file
-- - Edit the changelog item to changelog-readiness (if needed)
-- - Save and quit (C-x #) to do the next; it will exit after the last.
-- - On the side keep an auto-reverting editor open on the file to watch progress or for fixups.
--
-- Motivation:
-- This might seem a bit pointless, but it made this old chore more pleasant. 
-- I can make incremental progress by doing just one item, or more as I feel it,
-- without having all the other pending items drag on my attention.
--
-- Limitations/Wishes:
--
-- - Parsing of uncategorised pending items currently assumes the section headings
--   are Features, Improvements, Fixes. This does not work for other section headings,
--   as used in the project changelog. Workaround: add those three headings at the top.
--
-- - It's not obvious how to stop; C-x C-x just loads the next item.

{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
-- {-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE PackageImports #-}
{-# LANGUAGE RecordWildCards #-}

import Data.Char
import Data.Default
import GHC.Generics
import "extra" Data.List.Extra
-- import Data.Text qualified as T
import System.Environment
import System.IO.Extra
-- import System.IO
import System.Process
import Text.Printf
-- import Hledger.Utils (toRegex')

-- A top level section in the changelog, corresponding to one release.
data ChangelogSection = ChangelogSection {
   heading          :: ChangelogHeading
  ,unknownitems     :: [ChangelogItem]
  ,featureitems     :: [ChangelogItem]
  ,improvementitems :: [ChangelogItem]
  ,fixitems         :: [ChangelogItem]
  }
  deriving (Show, Eq, Generic, Default)

-- The one-line heading for a top level section in the changelog,
-- with the leading #(s) removed.
type ChangelogHeading = String

-- One change description in the changelog, with the list bullet and
-- corresponding indentation removed.
type ChangelogItem = String

main = do
  (f:_) <- getArgs
  go f

go f = do
  -- read specified changelog
  (preamble:first:rest) <- splitOn "\n# " <$> readFile f
  let
    g = f ++ ".new"
    s@ChangelogSection{} = readSection first

  -- ask for an edit of this item's text
  s' <- editOneUnknown s

  if s' == s
  then return ()  -- if it's unchanged, quit
  else do
    -- otherwise write to a temp file
    writeFile g $ init $ unlines $
      preamble :
      showSection s' :
      map ("# "++) rest
    -- and show the diff
    system' $ printf "diff %s %s" f g
    -- and replace the old file
    system' $ printf "mv %s %s" g f
    -- and repeat
    go f

editOneUnknown :: ChangelogSection -> IO ChangelogSection
editOneUnknown s@ChangelogSection{..}
  | null unknownitems = return s
  | otherwise = do
    let
      s' = s{unknownitems=init unknownitems}
      u = last unknownitems
    new <- textEditEditor u
    return $ case new of
      'f':'e':'a':'t':':':' ':t -> s'{featureitems     = readItem t : featureitems}
      'f':'i':'x':':':' ':t     -> s'{fixitems         = readItem t : fixitems}
      'i':'m':'p':':':' ':t     -> s'{improvementitems = readItem t : improvementitems}
      t                         -> s'{improvementitems = readItem t : improvementitems}

textEditEditor t = withTempFile $ \f -> do
  writeFile f t
  ed <- getEnv "EDITOR"
  system $ printf "%s %s" ed f
  readFile f

-- textEditTty u = do    
--     putStrLn "Old:"
--     putStrLn u
--     putStrLn "New: (prefix with feat:/imp:/fix: to categorise, ctrl-d to finish):\n" -- Just an = keeps it unchanged, empty string removes it."
--     getContents

-- Parse a changelog section which may or may not have the Features/Improvements/Fixes subheadings.
readSection :: String -> ChangelogSection
readSection s =
  let
    (heading,rest) = break (=='\n') s
    parts = splitOn "\nFeatures\n" rest
    (unknownitems, featureitems, improvementitems, fixitems) =
      case parts of
        []       -> ([], [], [], [])
        [u]      -> (readItems u, [], [], [])
        (u:xs:_) -> (readItems u, readItems f, readItems i, readItems x)
          where
            (f:ys:_) = splitOn "\nImprovements\n" xs
            (i:x:_)  = splitOn "\nFixes\n" ys
  in ChangelogSection{..}
  where
    readItems = map readItem . filter (not.all isSpace) . splitOn "\n- "

showSection ChangelogSection{..} =
  unlines $
       [("# "++heading), ""]
    ++ map showItem unknownitems
    ++ ["Features", ""]
    ++ map showItem featureitems
    ++ ["Improvements", ""]
    ++ map showItem improvementitems
    ++ ["Fixes", ""]
    ++ map showItem fixitems

readItem :: String -> ChangelogItem
readItem "" = def
readItem s =
  let
    (first:rest) = lines s
    stripto2spaces (' ':' ':t) = t
    stripto2spaces (' ':t) = t
    stripto2spaces t = t
  in unlines $
     first :
     map stripto2spaces rest

showItem "" = ""
showItem i =
  let (first:rest) = lines i
  in unlines $ ("- "++first) : map ("  "++) rest

system' s = putStrLn s >> system s

-- re = toRegex' . T.pack

