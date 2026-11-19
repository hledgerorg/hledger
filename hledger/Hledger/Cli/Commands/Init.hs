{-|

The @init@ command writes starter files for a new hledger setup,
or adds missing ones to an existing setup.
The files are example file layouts, kept in hledger/embeddedfiles/file-layouts/
(also linked from examples/file-layouts/), and embedded in the executable.
Existing files are never changed.

-}

{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TupleSections #-}

module Hledger.Cli.Commands.Init (
  initmode
 ,initcmd
 ,tests_Init
) where

import Control.Exception (IOException, try)
import Control.Monad (forM_, unless, when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as B
import Data.Char (toLower)
import Data.Containers.ListUtils (nubOrd)
import Data.List (intercalate)
import Data.Map.Strict qualified as M
import Safe (maximumDef)
import System.Console.CmdArgs.Explicit
import System.Directory
import System.FilePath
import System.Info (os)

import Hledger
import Hledger.Read.JournalReader qualified as JournalReader
import Hledger.Cli.CliOptions


initmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Init.txt")
  [flagNone ["dry-run"] (setboolopt "dry-run") "just show the files that would be created"]
  [generalflagsgroup3]
  hiddenflags
  ([], Just $ argsFlag "[DIR|FILE.journal]")

-- | A file in a layout: its path relative to the layout's root, whether it should be executable, and its content.
data LayoutFile = LayoutFile
  { lfPath       :: FilePath
  , lfExecutable :: Bool
  , lfContent    :: ByteString
  }

-- | The simple layout's only file, which is written to a journal file path argument.
simpleMainJournal :: LayoutFile
simpleMainJournal = LayoutFile "main.journal" False $(embedFileRelativeBytes "embeddedfiles/file-layouts/simple/main.journal")

-- | The default layout's files, in the order they are reported.
-- Keep synced with the files in embeddedfiles/file-layouts/default/ (and with package.yaml's extra-source-files);
-- the init functional tests compare the result with that directory.
defaultLayout :: [LayoutFile]
defaultLayout =
  [ LayoutFile "main.journal"                                   False $(embedFileRelativeBytes "embeddedfiles/file-layouts/default/main.journal")
  , LayoutFile "accounts.journal"                               False $(embedFileRelativeBytes "embeddedfiles/file-layouts/default/accounts.journal")
  , LayoutFile "commodities.journal"                            False $(embedFileRelativeBytes "embeddedfiles/file-layouts/default/commodities.journal")
  , LayoutFile "payees.journal"                                 False $(embedFileRelativeBytes "embeddedfiles/file-layouts/default/payees.journal")
  , LayoutFile ("data" </> "getdata")                           True  $(embedFileRelativeBytes "embeddedfiles/file-layouts/default/data/getdata")
  , LayoutFile ("data" </> "bankofireland-checking.csv")        False $(embedFileRelativeBytes "embeddedfiles/file-layouts/default/data/bankofireland-checking.csv")
  , LayoutFile ("data" </> "archive" </> "README.md")           False $(embedFileRelativeBytes "embeddedfiles/file-layouts/default/data/archive/README.md")
  , LayoutFile ("prices" </> "getprices")                       True  $(embedFileRelativeBytes "embeddedfiles/file-layouts/default/prices/getprices")
  , LayoutFile ("rules" </> "bankofireland-checking.csv.rules") False $(embedFileRelativeBytes "embeddedfiles/file-layouts/default/rules/bankofireland-checking.csv.rules")
  ]

-- | Where to write: a directory (gets the default layout) or a journal file path (gets the simple layout's main journal).
data InitTarget = InitDir FilePath | InitFile FilePath
  deriving (Eq, Show)

-- | What is at a path.
data PathState = Absent | IsDir | IsOther
  deriving (Eq, Show)

-- | What to do with one file.
data InitAction = Create FilePath LayoutFile | Skip FilePath

initcmd :: CliOpts -> Journal -> IO ()
initcmd CliOpts{rawopts_=rawopts} _ = do
  let dryRun = boolopt "dry-run" rawopts
  target <- case listofstringopt "args" rawopts of
    []    -> return $ InitDir "."
    [arg] -> do
      when (os == "mingw32" && isWindowsUnsafeDotPath arg) $
        error' $ "Part of file path " <> show arg <> " ends with a dot, which is unsafe on Windows; please use a different path."
      isdir <- doesDirectoryExist arg
      either usageError return $ classifyInitArg isdir arg
    _     -> usageError "init takes at most one argument, a directory or a journal file path."
  let
    dests = destinations target
    paths = nubOrd $ map fst dests ++ concatMap (ancestors . fst) dests
  states <- M.fromList <$> mapM (\p -> (p,) <$> pathState p) paths
  actions <- either error' return $ planInit (\p -> M.findWithDefault Absent p states) dests
  forM_ actions $ \case
    Create p f
      | dryRun    -> putStrLn $ "would create " <> p
      | otherwise -> writeLayoutFile p f >> putStrLn ("created " <> p)
    Skip p
      | dryRun    -> putStrLn $ "would skip " <> p <> " (exists)"
      | otherwise -> warnIO $ "skipped " <> p <> ", it already exists"
  unless dryRun $ showNextSteps $ case target of
    InitFile f -> f
    InitDir d  -> normalise $ d </> "main.journal"

-- | Decide what kind of path the command argument is, given whether it is an existing directory.
-- A path ending with a path separator is a directory; a path with a journal file extension is a journal file;
-- a path with any other extension is an error (most likely a file name meant for some other purpose);
-- anything else is a directory.
classifyInitArg :: Bool -> FilePath -> Either String InitTarget
classifyInitArg isdir arg
  | isdir || hasTrailingPathSeparator arg = Right $ InitDir arg
  | ext `elem` journalExtensions          = Right $ InitFile arg
  | not $ null ext                        = Left $ unlines
      [ show arg <> " has a ." <> ext <> " extension; init writes journal files or directories."
      , "For a journal file, use a " <> extensions <> " extension; for a directory with this name, add a trailing " <> [pathSeparator] <> "."
      ]
  | otherwise                             = Right $ InitDir arg
  where
    ext = map toLower $ drop 1 $ takeExtension arg
    journalExtensions = rExtensions (JournalReader.reader :: Reader IO)
    extensions = intercalate ", " $ map ('.':) journalExtensions

-- | The files to write, at their destination paths.
destinations :: InitTarget -> [(FilePath, LayoutFile)]
destinations (InitFile f) = [(normalise f, simpleMainJournal)]
destinations (InitDir d)  = [(normalise $ d </> lfPath f, f) | f <- defaultLayout]

-- | All the directories above a path, nearest first, as far as the path reaches
-- (eg "a/b/c" -> ["a/b", "a", "."], "/a/b" -> ["/a", "/"]).
ancestors :: FilePath -> [FilePath]
ancestors = go . takeDirectory
  where
    go d = d : let d' = takeDirectory d in if d' == d then [] else go d'

-- | Decide what to do with each file, given what is at each destination path and the directories above it.
-- If something other than a directory is where a directory is needed, give an error.
-- Otherwise, files whose path is free are created and the rest are skipped.
planInit :: (FilePath -> PathState) -> [(FilePath, LayoutFile)] -> Either String [InitAction]
planInit stateOf dests =
  case filter ((== IsOther) . stateOf) $ nubOrd $ concatMap (ancestors . fst) dests of
    d:_ -> Left $ show d <> " needs to be a directory, but a file is there. Nothing was written."
    []  -> Right [if stateOf p == Absent then Create p f else Skip p | (p, f) <- dests]

-- | Check what is at a path. A symbolic link counts as present even when its target does not exist.
pathState :: FilePath -> IO PathState
pathState p = do
  isdir <- doesDirectoryExist p
  exists <- doesPathExist p
  islink <- either (const False) id <$> (try (pathIsSymbolicLink p) :: IO (Either IOException Bool))
  return $ if | isdir            -> IsDir
              | exists || islink -> IsOther
              | otherwise        -> Absent

-- | Write a layout file at the given path, creating directories as needed.
-- The content is written as is, with no line ending conversion.
writeLayoutFile :: FilePath -> LayoutFile -> IO ()
writeLayoutFile p f = do
  createDirectoryIfMissing True $ takeDirectory p
  B.writeFile p $ lfContent f
  when (lfExecutable f) $ getPermissions p >>= setPermissions p . setOwnerExecutable True

-- | Suggest some next steps for using this main journal file.
-- The commands use -f unless LEDGER_FILE already selects it.
showNextSteps :: FilePath -> IO ()
showNextSteps mainj = do
  absj <- makeAbsolute mainj
  isdefault <- defaultJournalPathSafely >>= \case
    Left _  -> return False
    Right f -> either (const False) id <$>
      (try (equalFilePath <$> canonicalizePath f <*> canonicalizePath absj) :: IO (Either IOException Bool))
  let
    fopt = if isdefault then "" else " -f " <> shellQuoteIfNeeded mainj
    commands =
      [ ("hledger" <> fopt <> " check", "check the journal")
      , ("hledger" <> fopt <> " bs",    "show a balance sheet")
      , ("hledger" <> fopt <> " is",    "show an income statement")
      , ("hledger" <> fopt <> " add",   "add transactions")
      , ("hledger setup",               "check/show more details about your hledger installation")
      ]
    width = maximumDef 0 $ map (length . fst) commands
  putStr $ unlines $
    [ ""
    , "Next steps:"
    ] ++
    [ "  " <> c <> replicate (width - length c) ' ' <> "  # " <> desc | (c, desc) <- commands ] ++
    [ l | not isdefault, l <-
      [ "To make this your default journal, so -f is not needed, set LEDGER_FILE to"
      , "  " <> absj
      , "(see https://hledger.org/hledger.html#setting-ledger_file)."
      ]]

tests_Init = testGroup "Init" [
   testCase "classifyInitArg" $ do
    classifyInitArg True  "x.journal"      @?= Right (InitDir "x.journal")
    classifyInitArg False "x.journal"      @?= Right (InitFile "x.journal")
    classifyInitArg False "a/x.J"          @?= Right (InitFile "a/x.J")
    classifyInitArg False "a/x.j/"         @?= Right (InitDir "a/x.j/")
    classifyInitArg False "finance"        @?= Right (InitDir "finance")
    either (const True) (const False) (classifyInitArg False "x.csv") @?= True
  ,testCase "ancestors" $ do
    ancestors ("a" </> "b" </> "c") @?= ["a" </> "b", "a", "."]
    ancestors "c"                   @?= ["."]
  ,testCase "planInit" $ do
    let dests = destinations (InitDir "d")
        names = map (\case Create p _ -> "create " <> p; Skip p -> "skip " <> p)
    fmap (take 2 . names) (planInit (\p -> if p == "d" </> "main.journal" then IsOther else Absent) dests)
      @?= Right ["skip " <> ("d" </> "main.journal"), "create " <> ("d" </> "accounts.journal")]
    either (const True) (const False) (planInit (\p -> if p == "d" </> "data" then IsOther else Absent) dests) @?= True
  ]
