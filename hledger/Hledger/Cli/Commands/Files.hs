{-|

The @files@ command lists included files.

-}

{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Files (
  filesmode
 ,files
) where

import Data.List (mapAccumL, tails)
import Data.Text qualified as T
import Safe (headMay)
import System.Console.CmdArgs.Explicit (flagNone)
import System.FilePath (makeRelative, takeDirectory)

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Utils (writeOutputWithTitle)


-- | Command line options for this command.
filesmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Files.txt")
  [flagNone ["flat","l"] (setboolopt "flat") "list/tree mode: show files as a flat list (default)"
  ,flagNone ["tree","t"] (setboolopt "tree") "list/tree mode: show files as a tree, indenting included files below the file that includes them"
  ]
  cligeneralflagsgroups2
  hiddenflags
  ([], Just $ argsFlag "[REGEX]")

-- | The files command.
files :: CliOpts -> Journal -> IO ()
files opts@CliOpts{rawopts_=rawopts, reportspec_=rspec} j = do
  let args = listofstringopt "args" rawopts
  regex <- mapM (either fail pure . toRegex . T.pack) $ headMay args
  let
    matches = maybe (const True) regexMatch regex
    fs
      | tree_ $ _rsReportOpts rspec =
          -- show each file whose subtree has a match, keeping the include hierarchy visible
          [ replicate (2 * jfdepth jf) ' ' ++ shortpath
          | (jf,shortpath):rest <- tails $ withShortPaths $ jfiles j
          , any (matches . jfpath) $ jf : map fst (takeWhile ((> jfdepth jf) . jfdepth . fst) rest)
          ]
      | otherwise = filter matches $ journalFilePaths j
  writeOutputWithTitle opts $ T.unlines $ map T.pack fs

-- | Pair each journal file with its path relative to the directory of the file including it, if any.
-- For a file included by a literal path, this is the path as written in the include directive.
withShortPaths :: [JournalFile] -> [(JournalFile, FilePath)]
withShortPaths = snd . mapAccumL shorten []
  where
    -- the accumulator is the chain of including files' paths, most recent first
    shorten includers jf = (f : parents, (jf, maybe f (\p -> makeRelative (takeDirectory p) f) $ headMay parents))
      where
        f = jfpath jf
        parents = drop (length includers - jfdepth jf) includers
