{-|

Awareness of version control repositories (jj or git) holding the journal's files:
detecting them, checking files' status, and committing changed files (for the @--commit@ flag).

The tools are run as external programs (@jj@, @git@), with argument lists (no shell),
in the repository's root directory. Their errors are returned as values.

-}

{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}

module Hledger.Cli.Vcs (
  -- * Repositories
  Vcs(..),
  Repo(..),
  vcsTool,
  chooseVcs,
  detectRepo,
  repoToolFound,
  repoRelativePaths,
  -- * File status
  repoTrackedFiles,
  repoChangedFiles,
  -- * Committing
  CommitResult(..),
  repoCommit,
  -- * The --commit flag
  commitflag,
  CommitContext(..),
  prepareCommit,
  prepareCommitEither,
  finishCommit,
  finishCommitEither,
  showWouldCommit,
  -- * Utilities
  jjFileset,
  parseGitStatusZ,
  tests_Vcs,
) where

import Control.Exception (IOException, try)
import Control.Monad (filterM, unless)
import Data.List (intercalate, isPrefixOf, nub, partition)
import Data.Maybe (isJust)
import System.Console.CmdArgs.Explicit (Flag, flagNone)
import System.Directory (canonicalizePath, doesPathExist, findExecutable, makeAbsolute)
import System.Exit (ExitCode(..))
import System.FilePath
import System.IO (hPutStrLn, stderr)
import System.Process (CreateProcess(..), proc, readCreateProcessWithExitCode)

import Hledger


-- | A supported version control system.
data Vcs = Jj | Git
  deriving (Eq, Show)

-- | A repository: its kind, and its root directory (canonical, absolute).
data Repo = Repo { repoVcs :: Vcs, repoRoot :: FilePath }
  deriving (Eq, Show)

-- | The name of a VCS's command line tool, also used as its name in messages.
vcsTool :: Vcs -> String
vcsTool Jj  = "jj"
vcsTool Git = "git"

-- | Which kind of repository a directory is the root of, given whether it has a .jj and a .git entry.
-- jj is preferred, so a colocated jj/git repo is used through jj (which keeps git in sync).
chooseVcs :: Bool -> Bool -> Maybe Vcs
chooseVcs hasjj hasgit
  | hasjj     = Just Jj
  | hasgit    = Just Git
  | otherwise = Nothing

-- | Find the repository containing this directory, if any, by looking for a .jj or .git entry
-- in it and then in each directory above it. The nearest one wins.
-- This only looks at the filesystem; using the repository also needs its tool (see 'repoToolFound').
detectRepo :: FilePath -> IO (Maybe Repo)
detectRepo dir = canonicalOrAbsolute dir >>= go
  where
    go d = do
      hasjj  <- doesPathExist $ d </> ".jj"
      hasgit <- doesPathExist $ d </> ".git"  -- a directory, or a file in git worktrees and submodules
      case chooseVcs hasjj hasgit of
        Just v  -> return $ Just $ Repo v d
        Nothing -> let d' = takeDirectory d in if d' == d then return Nothing else go d'

-- | Canonicalise a path (resolving symbolic links), or if that fails, just make it absolute.
canonicalOrAbsolute :: FilePath -> IO FilePath
canonicalOrAbsolute f = (try (canonicalizePath f) :: IO (Either IOException FilePath)) >>= \case
  Right f' -> return f'
  Left _   -> makeAbsolute f

-- | Is this repository's tool installed (in PATH) ?
repoToolFound :: Repo -> IO Bool
repoToolFound r = isJust <$> findExecutable (vcsTool $ repoVcs r)

-- | Make these paths relative to the repository root (with / separators),
-- returning those inside the repository, and (separately) the ones outside it, unchanged.
repoRelativePaths :: Repo -> [FilePath] -> IO ([FilePath], [FilePath])
repoRelativePaths r fs = do
  rels <- mapM (\f -> (f,) . makeRelative (repoRoot r) <$> canonicalOrAbsolute f) fs
  let (inside, outside) = partition (isRelative . snd) rels
  return (nub [map (\c -> if isPathSeparator c then '/' else c) rel | (_, rel) <- inside], map fst outside)

-- | Run the repository's tool with these arguments and this stdin, in the repository root.
-- Returns the exit code and output, or a message if it could not be run.
runTool :: Repo -> String -> [String] -> IO (Either String (ExitCode, String, String))
runTool r input args = do
  let tool = vcsTool $ repoVcs r
  res <- try $ readCreateProcessWithExitCode (proc tool args){cwd = Just $ repoRoot r} input
  return $ case res of
    Left (e :: IOException) -> Left $ unwords (tool : args) <> ": " <> show e
    Right x                 -> Right x

-- | Like 'runTool', but a non-zero exit code is also an error; returns stdout.
runToolOk :: Repo -> String -> [String] -> IO (Either String String)
runToolOk r input args = runTool r input args >>= return . \case
  Left e                       -> Left e
  Right (ExitSuccess, out, _)  -> Right out
  Right (ExitFailure n, out, err) ->
    Left $ intercalate "\n" $ filter (not . null)
      [unwords (vcsTool (repoVcs r) : args) <> " failed (exit code " <> show n <> "):", rstrip err, rstrip out]

-- | A jj fileset matching this repository-relative path exactly, or the files under it if it is a directory.
-- The path is quoted and escaped, so any characters are safe.
jjFileset :: FilePath -> String
jjFileset f = "root:\"" <> concatMap esc f <> "\""
  where
    esc '"'  = "\\\""
    esc '\\' = "\\\\"
    esc c    = [c]

-- | jj's global options used for all commands.
jjopts :: [String]
jjopts = ["--quiet", "--color=never", "--no-pager"]

-- | Split NUL-separated output into its non-empty parts.
nulSeparated :: String -> [String]
nulSeparated = filter (not . null) . splitOn '\0'
  where
    splitOn c s = case break (== c) s of
      (a, [])     -> [a]
      (a, _:rest) -> a : splitOn c rest

-- | Parse the paths from @git status --porcelain=v1 -z@ output.
-- Each entry is "XY PATH"; renames and copies are followed by an extra entry, the original path, which is skipped.
parseGitStatusZ :: String -> [FilePath]
parseGitStatusZ = go . nulSeparated
  where
    go (e:rest)
      | (x:_y:' ':path) <- e = path : go (if x `elem` ("RC" :: String) then drop 1 rest else rest)
      | otherwise            = go rest
    go [] = []

-- | Which of these repository-relative paths (or the files under them, for directories) are tracked.
-- Returns the tracked files, repository-relative.
repoTrackedFiles :: Repo -> [FilePath] -> IO (Either String [FilePath])
repoTrackedFiles _ [] = return $ Right []
repoTrackedFiles r fs = case repoVcs r of
  Git -> fmap nulSeparated <$> runToolOk r "" (["ls-files", "-z", "--"] <> fs)
  Jj  -> fmap lines <$> runToolOk r "" (jjopts <> ["file", "list"] <> map jjFileset fs)

-- | Which of these repository-relative paths (or the files under them, for directories)
-- have changes not yet recorded (committed). Untracked files are not included
-- (jj may track new files automatically, depending on its snapshot.auto-track setting).
repoChangedFiles :: Repo -> [FilePath] -> IO (Either String [FilePath])
repoChangedFiles _ [] = return $ Right []
repoChangedFiles r fs = case repoVcs r of
  Git -> fmap parseGitStatusZ <$> runToolOk r "" (["status", "--porcelain=v1", "-z", "--untracked-files=no", "--"] <> fs)
  Jj  -> fmap lines <$> runToolOk r "" (jjopts <> ["diff", "--name-only"] <> map jjFileset fs)

-- | The result of trying to commit some paths.
data CommitResult = Committed | NothingToCommit
  deriving (Eq, Show)

-- | Commit the changes in these repository-relative paths (files or directories) with this message,
-- leaving any other changes in the repository as they are. Ignored files are not committed.
repoCommit :: Repo -> String -> [FilePath] -> IO (Either String CommitResult)
repoCommit _ _ [] = return $ Right NothingToCommit
repoCommit r msg fs = case repoVcs r of
  Jj -> do
    -- track any new files first, in case jj is configured not to track them automatically
    -- (jj file track does not track ignored files)
    etrack <- runToolOk r "" (jjopts <> ["file", "track"] <> map jjFileset fs)
    echanged <- either (return . Left) (const $ repoChangedFiles r fs) etrack
    case echanged of
      Left e   -> return $ Left e
      Right [] -> return $ Right NothingToCommit
      Right _  -> fmap (const Committed) <$> runToolOk r "" (jjopts <> ["commit", "-m", msg] <> map jjFileset fs)
  Git -> do
    -- git add refuses paths which are ignored, or which neither exist nor are tracked, so leave those out
    eignored <- runTool r (intercalate "\0" fs <> "\0") ["check-ignore", "-z", "--stdin"]
    etracked <- repoTrackedFiles r fs
    case (eignored, etracked) of
      (Left e, _) -> return $ Left e
      (Right (ExitFailure n, _, err), _) | n /= 1 -> return $ Left $ "git check-ignore failed: " <> rstrip err
      (_, Left e) -> return $ Left e
      (Right (_, ignoredout, _), Right tracked) -> do
        let
          ignored = nulSeparated ignoredout
          istracked f = any (\t -> t == f || (f <> "/") `isPrefixOf` t) tracked
        existing <- filterM (doesPathExist . (repoRoot r </>)) fs
        let fs' = [f | f <- fs, f `notElem` ignored, f `elem` existing || istracked f]
        if null fs' then return $ Right NothingToCommit else do
          eadd <- runToolOk r "" (["add", "-A", "--"] <> fs')
          case eadd of
            Left e -> return $ Left e
            Right _ -> do
              -- anything to commit ? (git diff --quiet exits with 1 when there are differences)
              ediff <- runTool r "" (["diff", "--cached", "--quiet", "--"] <> fs')
              case ediff of
                Left e -> return $ Left e
                Right (ExitSuccess, _, _) -> return $ Right NothingToCommit
                Right (ExitFailure 1, _, _) ->
                  fmap (const Committed) <$> runToolOk r "" (["commit", "-q", "-m", msg, "--"] <> fs')
                Right (ExitFailure _, _, err) -> return $ Left $ "git diff failed: " <> rstrip err

-- | The --commit flag, for commands which change files.
commitflag :: Flag RawOpts
commitflag = flagNone ["commit"] (setboolopt "commit") "record the changed files in the journal's jj or git repository"

-- | What --commit needs to remember between checking (before writing files) and committing (after).
data CommitContext = CommitContext
  { ccRepo           :: Repo
  , ccEarlierChanges :: [FilePath]  -- ^ files to be written which already had unrecorded changes (repository-relative)
  }

-- | If --commit was given: find the repository containing this directory and check that its tool is installed,
-- raising an error if not, and note which of these files (to be written) already have unrecorded changes.
-- Call this before writing anything.
prepareCommit :: RawOpts -> FilePath -> [FilePath] -> IO (Maybe CommitContext)
prepareCommit rawopts dir fs = prepareCommitEither rawopts dir fs >>= either error' return

-- | Like 'prepareCommit', but return a problem as a Left error message.
prepareCommitEither :: RawOpts -> FilePath -> [FilePath] -> IO (Either String (Maybe CommitContext))
prepareCommitEither rawopts dir fs
  | not $ boolopt "commit" rawopts = return $ Right Nothing
  | otherwise = detectRepo dir >>= \case
      Nothing -> makeAbsolute dir >>= \absdir -> return $ Left $
                   "--commit: no jj or git repository found at or above " <> absdir <> ".\n"
                   <> "Create one first (eg with \"jj git init\" or \"git init\"), or run without --commit."
      Just r -> do
        found <- repoToolFound r
        if not found
        then return $ Left $ "--commit: " <> repoRoot r <> " is a " <> vcsTool (repoVcs r)
                             <> " repository, but " <> vcsTool (repoVcs r) <> " was not found in PATH."
        else do
          (rels, _) <- repoRelativePaths r fs
          earlier <- either (const []) id <$> repoChangedFiles r rels
          return $ Right $ Just $ CommitContext r earlier

-- | Commit these changed paths (files or directories) with this message, if --commit was prepared,
-- and report the outcome on stderr. Paths outside the repository are not committed (with a warning).
-- If committing fails, raise an error saying that the files were written but not committed.
finishCommit :: Maybe CommitContext -> String -> [FilePath] -> IO ()
finishCommit mctx msg fs = finishCommitEither mctx msg fs >>= either error' return

-- | Like 'finishCommit', but return a failure as a Left error message (for hledger-web).
finishCommitEither :: Maybe CommitContext -> String -> [FilePath] -> IO (Either String ())
finishCommitEither Nothing _ _ = return $ Right ()
finishCommitEither (Just (CommitContext r earlier)) msg fs = do
  (rels, outside) <- repoRelativePaths r fs
  unless (null outside) $ warnIO $
    "not committing files outside the " <> vcsTool (repoVcs r) <> " repository at " <> repoRoot r <> ": " <> unwords outside
  res <- repoCommit r msg rels
  let tool = vcsTool $ repoVcs r
  case res of
    Left e -> return $ Left $ "the changes were saved, but could not be committed to " <> tool <> ":\n" <> e
    Right NothingToCommit -> return $ Right ()
    Right Committed -> do
      hPutStrLn stderr $ "committed to " <> tool <> ": " <> msg
      let earlier' = filter (\f -> any (\p -> f == p || (p <> "/") `isPrefixOf` f) rels) earlier
      unless (null earlier') $
        hPutStrLn stderr $ "(this includes earlier unrecorded changes in " <> intercalate ", " earlier' <> ")"
      return $ Right ()

-- | For --dry-run: if --commit was prepared, say what would be committed.
showWouldCommit :: Maybe CommitContext -> String -> IO ()
showWouldCommit Nothing _ = return ()
showWouldCommit (Just (CommitContext r _)) msg =
  hPutStrLn stderr $ "would commit to " <> vcsTool (repoVcs r) <> ": " <> msg

tests_Vcs = testGroup "Vcs" [
   testCase "chooseVcs" $ do
    chooseVcs True  True  @?= Just Jj
    chooseVcs True  False @?= Just Jj
    chooseVcs False True  @?= Just Git
    chooseVcs False False @?= Nothing
  ,testCase "jjFileset" $ do
    jjFileset "a b/c.journal" @?= "root:\"a b/c.journal\""
    jjFileset "q\"x\\y"       @?= "root:\"q\\\"x\\\\y\""
  ,testCase "parseGitStatusZ" $ do
    parseGitStatusZ " M a.journal\0?? b\0R  new\0old\0A  c d\0" @?= ["a.journal", "b", "new", "c d"]
    parseGitStatusZ "" @?= []
  ]
