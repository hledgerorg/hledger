{-|

The @files@ command lists the files read: the main and included data files,
and any rules or data files used to read them.

-}

{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Files (
  filesmode
 ,files
) where

import Data.List (mapAccumL, tails)
import Data.Maybe (fromMaybe)
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
    jfs = withAuxFiles j
    fs
      | tree_ $ _rsReportOpts rspec =
          -- show each file whose subtree has a match, keeping the include hierarchy visible
          [ replicate (2 * jfdepth jf) ' ' ++ shortpath
          | (jf,shortpath):rest <- tails $ withShortPaths jfs
          , any (matches . jfpath) $ jf : map fst (takeWhile ((> jfdepth jf) . jfdepth . fst) rest)
          ]
      | otherwise = filter matches $ map jfpath jfs
  writeOutputWithTitle opts $ T.unlines $ map T.pack fs

-- | The journal's files, each followed by any auxiliary files used to read it
-- (eg a CSV file's rules file, or a rules file's included rules files and data file),
-- as pseudo-files one include level deeper (with no text).
withAuxFiles :: Journal -> [JournalFile]
withAuxFiles j =
  concat [ jf : [JournalFile a T.empty (jfdepth jf + 1) | a <- fromMaybe [] $ lookup (jfpath jf) (jauxfiles j)]
         | jf <- jfiles j ]

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
