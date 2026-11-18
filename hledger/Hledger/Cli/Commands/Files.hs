{-|

The @files@ command lists the files read: the main and included data files,
and any rules or data files used to read them.

-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Files (
  filesmode
 ,files
) where

import Data.Aeson (ToJSON(..), object, (.=))
import Data.List (mapAccumL, tails)
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Safe (headMay)
import System.Console.CmdArgs.Explicit (flagNone)
import System.Directory (doesFileExist)
import System.FilePath (makeRelative, takeDirectory)

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Utils (unsupportedOutputFormatError, writeOutputLazyText, writeOutputWithTitle)


-- | Command line options for this command.
filesmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Files.txt")
  [flagNone ["flat","l"] (setboolopt "flat") "list/tree mode: show files as a flat list (default)"
  ,flagNone ["tree","t"] (setboolopt "tree") "list/tree mode: show files as a tree, indenting included files below the file that includes them"
  ,outputFormatFlag ["txt","json"]
  ,outputFileFlag
  ]
  cligeneralflagsgroups2
  hiddenflags
  ([], Just $ argsFlag "[REGEX]")

-- | One entry in the list of files read.
data FileEntry = FileEntry {
   fePath      :: FilePath        -- ^ the file's path
  ,feShortPath :: FilePath        -- ^ its path relative to its parent's directory, if it has a parent
  ,feDepth     :: Int             -- ^ its depth in the tree of files: 0 for a main file
  ,feParent    :: Maybe FilePath  -- ^ the file which included it, or which it was used to read
  ,feExists    :: Bool            -- ^ does it exist ? (Missing included files are recorded, not an error, when finding the files read.)
  }

instance ToJSON FileEntry where
  toJSON e = object
    [ "path"   .= fePath e
    , "depth"  .= feDepth e
    , "parent" .= feParent e
    , "exists" .= feExists e
    ]

-- | The files command.
files :: CliOpts -> Journal -> IO ()
files opts@CliOpts{rawopts_=rawopts, reportspec_=rspec} j = do
  let args = listofstringopt "args" rawopts
  regex <- mapM (either fail pure . toRegex . T.pack) $ headMay args
  es <- mapM setExists $ fileEntries j
  let
    matches = maybe (const True) regexMatch regex . fePath
    matched = filter matches es
    -- text output shows only existing files, and warns about missing ones
    existing = filter feExists es
    warnMissing = mapM_ (warnIO . ("file not found: " <>) . fePath) $ filter (not . feExists) matched
  case outputFormatFromOpts opts of
    "json" -> writeOutputLazyText opts $ toJsonText matched
    "txt"
      | tree_ $ _rsReportOpts rspec -> do
          warnMissing
          -- show each file whose subtree has a match, keeping the tree visible
          writeLines [ replicate (2 * feDepth e) ' ' ++ feShortPath e
                     | e:rest <- tails existing
                     , any matches $ e : takeWhile ((> feDepth e) . feDepth) rest
                     ]
      | otherwise -> do
          warnMissing
          writeLines $ map fePath $ filter matches existing
    fmt -> exitWithErrorMessage $ unsupportedOutputFormatError fmt
  where
    writeLines = writeOutputWithTitle opts . T.unlines . map T.pack
    setExists e = do
      exists <- if fePath e == "-" then return True else doesFileExist $ fePath e
      return e{feExists=exists}

-- | The journal's files in the order they were read, each followed by any auxiliary files
-- used to read it (eg a CSV file's rules file, or a rules file's included rules files and data file),
-- which appear one level deeper in the tree. (Whether they exist is checked later.)
fileEntries :: Journal -> [FileEntry]
fileEntries j = snd $ mapAccumL entry [] filesanddepths
  where
    filesanddepths = concat
      [ (jfpath jf, jfdepth jf) : [(a, jfdepth jf + 1) | a <- fromMaybe [] $ lookup (jfpath jf) (jauxfiles j)]
      | jf <- jfiles j ]
    -- the accumulator is the chain of parent files' paths, most recent first
    entry parents0 (f, d) = (f : parents, FileEntry f shortpath d mparent True)
      where
        parents = drop (length parents0 - d) parents0
        mparent = headMay parents
        -- For a file included by a literal path, this is the path as written in the include directive.
        shortpath = maybe f (\p -> makeRelative (takeDirectory p) f) mparent
