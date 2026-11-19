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
import Control.Monad (forM, forM_, unless, when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as B
import Data.ByteString.Char8 qualified as B8
import Data.Char (toLower)
import Data.Containers.ListUtils (nubOrd)
import Data.List (find, intercalate, isInfixOf, stripPrefix)
import Data.Map.Strict qualified as M
import Data.Maybe (maybeToList)
import Data.Time.Calendar (toGregorian)
import Safe (maximumDef)
import System.Console.CmdArgs.Explicit
import System.Directory
import System.FilePath
import System.Info (os)

import Hledger
import Hledger.Read.JournalReader qualified as JournalReader
import Hledger.Cli.CliOptions
import Hledger.Cli.Vcs


initmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Init.txt")
  [flagReq  ["layout"] (\s opts -> Right $ setopt "layout" s opts) "LAYOUT"
     ("which file layout to write: " <> intercalate ", " (map lName layouts) <> " (default: " <> lName defaultLayout <> ")")
  ,flagNone ["dry-run"] (setboolopt "dry-run") "just show the files that would be created"
  ,commitflag
  ]
  [generalflagsgroup3]
  hiddenflags
  ([], Just $ argsFlag "[DIR|FILE.journal]")

-- | A file in a layout: its path relative to the layout's root, whether it should be executable, and its content.
data LayoutFile = LayoutFile
  { lfPath       :: FilePath
  , lfExecutable :: Bool
  , lfContent    :: ByteString
  }

-- | A set of files which can be written by init.
data FileLayout = FileLayout
  { lName            :: String
  , lDescription     :: String
  , lFiles           :: [LayoutFile]  -- ^ in the order they are reported
  , lMainJournal     :: FilePath      -- ^ the journal to use day to day, relative to the layout's root
  , lCombinedJournal :: Maybe FilePath  -- ^ a journal combining several main journals, if any
  }

-- | The built-in layouts.
-- Their files are in embeddedfiles/file-layouts/LAYOUT/; keep these definitions synced with those
-- (and with package.yaml's extra-source-files). The init functional tests compare the results with those directories.
layouts :: [FileLayout]
layouts = [simpleLayout, defaultLayout, yearsLayout]

simpleLayout, defaultLayout, yearsLayout :: FileLayout
simpleLayout = FileLayout "simple" "one journal file, with optional declarations commented out"
  [simpleMainJournal] "main.journal" Nothing
defaultLayout = FileLayout "default" "a main journal, declaration files, and directories for data, prices and rules"
  defaultFiles "main.journal" Nothing
yearsLayout = FileLayout "years" "like default, but with a journal for each year, and all.journal to combine them"
  ([ LayoutFile "2026.journal" False $(embedFileRelativeBytes "embeddedfiles/file-layouts/years/2026.journal")
   , LayoutFile "all.journal"  False $(embedFileRelativeBytes "embeddedfiles/file-layouts/years/all.journal")
   ] ++ filter ((/= "main.journal") . lfPath) defaultFiles)
  "2026.journal" (Just "all.journal")

-- | Find a built-in layout by name.
lookupLayout :: String -> Maybe FileLayout
lookupLayout name = find ((== name) . lName) layouts

-- | The year used in layout file names and content, which init replaces with the current year.
layoutYear :: String
layoutYear = "2026"

-- | Adapt a layout to the given year: in files whose name contains 'layoutYear',
-- replace it with this year, in their name and their content.
layoutForYear :: Integer -> FileLayout -> FileLayout
layoutForYear y l = l{lFiles = map forYear $ lFiles l, lMainJournal = forYearPath $ lMainJournal l}
  where
    year = show y
    hasYear = (layoutYear `isInfixOf`) . takeFileName
    forYearPath p = if hasYear p then replaceString layoutYear year p else p
    forYear f
      | hasYear (lfPath f) = f{lfPath = forYearPath $ lfPath f, lfContent = replaceBytes (B8.pack layoutYear) (B8.pack year) $ lfContent f}
      | otherwise          = f

-- | Replace all occurrences of a non-empty string (an empty one changes nothing).
replaceString :: String -> String -> String -> String
replaceString old new = go
  where
    go s | null old                       = s
         | Just rest <- stripPrefix old s = new ++ go rest
         | c:cs <- s                      = c : go cs
         | otherwise                      = []

-- | Replace all occurrences of a non-empty byte string (an empty one changes nothing).
replaceBytes :: ByteString -> ByteString -> ByteString -> ByteString
replaceBytes old new s
  | B.null old = s
  | otherwise  = case B.breakSubstring old s of
      (before, rest) | B.null rest -> before
                     | otherwise   -> before <> new <> replaceBytes old new (B.drop (B.length old) rest)

-- | The simple layout's only file, which is also written to a journal file path argument.
simpleMainJournal :: LayoutFile
simpleMainJournal = LayoutFile "main.journal" False $(embedFileRelativeBytes "embeddedfiles/file-layouts/simple/main.journal")

-- | The default layout's files.
defaultFiles :: [LayoutFile]
defaultFiles =
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

-- | Where to write: a directory (gets a whole layout) or a journal file path (gets the simple layout's main journal).
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
  mlayout <- forM (maybestringopt "layout" rawopts) $ \name ->
    maybe (usageError $ unknownLayoutMsg name) return $ lookupLayout name
  (y, _, _) <- toGregorian <$> getCurrentDay
  flayout <- either usageError (return . layoutForYear y) $ chooseLayout mlayout target
  let
    dests = destinations flayout target
    paths = nubOrd $ map fst dests ++ concatMap (ancestors . fst) dests
  states <- M.fromList <$> mapM (\p -> (p,) <$> pathState p) paths
  actions <- either error' return $ planInit (\p -> M.findWithDefault Absent p states) dests
  mcommit <- prepareCommit rawopts (case target of InitDir d -> d; InitFile f -> takeDirectory f) []
  forM_ actions $ \case
    Create p f
      | dryRun    -> putStrLn $ "would create " <> p
      | otherwise -> writeLayoutFile p f >> putStrLn ("created " <> p)
    Skip p
      | dryRun    -> putStrLn $ "would skip " <> p <> " (exists)"
      | otherwise -> warnIO $ "skipped " <> p <> ", it already exists"
  let
    created = [p | Create p _ <- actions]
    commitmsg = "hledger init: " <> lName flayout <> " layout"
  if dryRun
  then unless (null created) $ showWouldCommit mcommit commitmsg
  else finishCommit mcommit commitmsg created
  unless dryRun $ case target of
    InitFile f -> showNextSteps f Nothing
    InitDir d  -> showNextSteps (normalise $ d </> lMainJournal flayout) ((normalise . (d </>)) <$> lCombinedJournal flayout)

-- | A usage error message for an unknown layout name, listing the layouts.
unknownLayoutMsg :: String -> String
unknownLayoutMsg name = unlines $
  ("There is no " <> show name <> " layout. The layouts are:")
  : ["  " <> lName l <> replicate (width - length (lName l)) ' ' <> "  " <> lDescription l | l <- layouts]
  where width = maximumDef 0 $ map (length . lName) layouts

-- | Choose the layout to write, given the --layout option's layout if any, and the target.
-- A journal file target can only have the simple layout.
chooseLayout :: Maybe FileLayout -> InitTarget -> Either String FileLayout
chooseLayout mlayout target = case (target, mlayout) of
  (InitDir _,  Nothing) -> Right defaultLayout
  (InitDir _,  Just l)  -> Right l
  (InitFile _, Nothing) -> Right simpleLayout
  (InitFile f, Just l)
    | lName l == lName simpleLayout -> Right l
    | otherwise -> Left $ "The " <> lName l <> " layout needs a directory, not a journal file (" <> show f <> ")."

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
-- A journal file target gets the layout's main journal content.
destinations :: FileLayout -> InitTarget -> [(FilePath, LayoutFile)]
destinations l (InitFile f) = [(normalise f, mf) | mf <- take 1 $ filter ((== lMainJournal l) . lfPath) $ lFiles l]
destinations l (InitDir d)  = [(normalise $ d </> lfPath f, f) | f <- lFiles l]

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

-- | Suggest some next steps for using this main journal file, and the combining journal if any.
-- The commands use -f unless LEDGER_FILE already selects the main journal.
showNextSteps :: FilePath -> Maybe FilePath -> IO ()
showNextSteps mainj mcombinedj = do
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
      ] ++
      [ ("hledger -f " <> shellQuoteIfNeeded cj <> " bs", "show a balance sheet using all years' journals") | cj <- maybeToList mcombinedj ] ++
      [ ("hledger setup",               "check/show more details about your hledger installation")
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
  ,testCase "chooseLayout" $ do
    fmap lName (chooseLayout Nothing (InitDir "d"))                  @?= Right "default"
    fmap lName (chooseLayout (Just yearsLayout) (InitDir "d"))       @?= Right "years"
    fmap lName (chooseLayout Nothing (InitFile "f.journal"))         @?= Right "simple"
    fmap lName (chooseLayout (Just simpleLayout) (InitFile "f.journal")) @?= Right "simple"
    either (const True) (const False) (chooseLayout (Just yearsLayout) (InitFile "f.journal")) @?= True
    fmap lName (lookupLayout "years") @?= Just "years"
    fmap lName (lookupLayout "nosuch") @?= Nothing
  ,testCase "layoutForYear" $ do
    let l = layoutForYear 2031 yearsLayout
        yearfile = find ((== "2031.journal") . lfPath) (lFiles l)
    lMainJournal l @?= "2031.journal"
    map lfPath (take 2 $ lFiles l) @?= ["2031.journal", "all.journal"]
    fmap (B.isInfixOf "2026" . lfContent) yearfile @?= Just False
    fmap (B.isInfixOf "2031-01-01" . lfContent) yearfile @?= Just True
    map lfContent (drop 1 $ lFiles l) @?= map lfContent (drop 1 $ lFiles yearsLayout)
  ,testCase "replaceString, replaceBytes" $ do
    replaceString "26" "31" "a26b26" @?= "a31b31"
    replaceString "" "x" "ab"        @?= "ab"
    replaceBytes "26" "31" "a26b26"  @?= "a31b31"
    replaceBytes "" "x" "ab"         @?= "ab"
  ,testCase "planInit" $ do
    let dests = destinations defaultLayout (InitDir "d")
        names = map (\case Create p _ -> "create " <> p; Skip p -> "skip " <> p)
    fmap (take 2 . names) (planInit (\p -> if p == "d" </> "main.journal" then IsOther else Absent) dests)
      @?= Right ["skip " <> ("d" </> "main.journal"), "create " <> ("d" </> "accounts.journal")]
    either (const True) (const False) (planInit (\p -> if p == "d" </> "data" then IsOther else Absent) dests) @?= True
  ]
