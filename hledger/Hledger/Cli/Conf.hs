{-|
Read extra CLI arguments from a hledger config file.
-}

{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE TupleSections #-}

module Hledger.Cli.Conf (
   Conf
  ,SectionName
  ,CommandAlias
  ,CommandLine
  ,getConf
  ,getConf'
  ,nullconf
  ,confLookup
  ,confAliases
  ,ResolvedCommand(..)
  ,expandCommandAlias
  ,confFileIsTrusted
  ,activeConfFile
  ,activeLocalConfFile
  ,activeUserConfFile
  ,confFiles
  ,userConfFiles
  ,parseConf
)
where

import Control.Exception (handle)
import Control.Monad (void, forM, guard)
import Control.Monad.Identity (Identity)
import Data.Functor ((<&>))
import Data.Map qualified as M
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as T (empty, lines, pack, unpack)
import Safe (headDef, headMay, lastDef)
import System.Directory (getHomeDirectory, getXdgDirectory, XdgDirectory (XdgConfig), doesFileExist, getCurrentDirectory)
import System.FilePath ((</>), takeDirectory)
import Text.Megaparsec as M
import Text.Megaparsec.Char
import Text.Printf (printf)

import Hledger (decorateExcerpt, error', strip, words', wordsmay, RawOpts, expandPath)
import Hledger.Read.Common
import Hledger.Utils.Parse
import Hledger.Utils.Debug
import Hledger.Data.RawOptions (collectopts)


-- | A hledger config file.
data Conf = Conf {
   confFile :: FilePath
  ,confText :: Text
  ,confFormat :: Int
  ,confSections :: [ConfSection]
} deriving (Eq,Show)

-- | One section in a hledger config file.
data ConfSection = ConfSection {
   csName :: SectionName
  ,csArgs :: [(Int, Arg)]  -- ^ arguments, with the config file line number where each appeared
} deriving (Eq,Show)

-- | The name of a config file section, with surrounding brackets and whitespace removed.
type SectionName = String

-- | A command line argument to be passed to CmdArgs.process.
-- It seems this should be a single command line argument (or flag or flag value).
-- If it contains spaces, those are treated as part of a single argument, as with CMD a "b c".
type Arg = String

-- | The name of a command alias (a custom command) defined in a config file.
type CommandAlias = String

-- | A command line (a command name followed by arguments), as a single string.
-- Eg the command line which a command alias expands to.
type CommandLine = String

nullconf = Conf {
   confFile = ""
  ,confText = T.empty
  ,confFormat = 1
  ,confSections = []
}

-- | The --conf or --no-conf or default config file specified by command line options.
data ConfFileSpec =
    SomeConfFile FilePath  -- ^ use config file specified with --conf
  | NoConfFile             -- ^ don't use any config file (--no-conf)
  | AutoConfFile           -- ^ use the config file found by directory search (default)
  deriving (Eq,Show)

-- Get the conf file specification from options,
-- considering the rightmost --conf or --no-conf option if any.
confFileSpecFromRawOpts :: RawOpts -> ConfFileSpec
confFileSpecFromRawOpts = lastDef AutoConfFile . collectopts cfsFromRawOpt
  where
    cfsFromRawOpt ("conf",f)    = Just $ SomeConfFile f
    cfsFromRawOpt ("no-conf",_) = Just $ NoConfFile
    cfsFromRawOpt _             = Nothing

-- config reading

-- | Fetch all the arguments/options defined in a section with this name, if it exists.
-- This should be "general" for the unnamed first section, or a hledger command name.
confLookup :: SectionName -> Conf -> [Arg]
confLookup cmd Conf{confSections} =
  maybe [] (concatMap $ words' . snd) $  -- XXX PARTIAL
  M.lookup cmd $
  M.fromList [(csName,csArgs) | ConfSection{csName,csArgs} <- confSections]

-- | Get the command aliases (custom commands) defined in this config file,
-- in order of definition. They are defined git-style in an @[alias]@
-- section, like @NAME = CMDLINE@; a value may continue on following, more-indented lines.
-- If a name is defined more than once, the last definition should win (callers can rely
-- on the ordering here). An [alias] section line without an @=@ raises a usage error.
-- (In practice it won't, since readConfFile validates with confAliasesE first.)
confAliases :: Conf -> [(CommandAlias, CommandLine)]
confAliases = either error' id . confAliasesE

-- | Like confAliases, but return a (pretty, multiline) error message
-- if a bad alias definition is found.
confAliasesE :: Conf -> Either String [(CommandAlias, CommandLine)]
confAliasesE conf@Conf{confSections} = concat <$> mapM sectionaliases confSections
  where
    sectionaliases ConfSection{csName, csArgs}
      | csName == "alias" = mapM aliasline csArgs
      | otherwise = Right []
    aliasline (lnum, l) = case break (=='=') l of
      (name, '=':cmdline) | not $ null $ strip name -> Right (strip name, strip cmdline)
      _ -> Left $ confErrorAt conf lnum l
           "an [alias] section line should look like: NAME = COMMAND [ARGS..]"

-- | Check that each argument line in this config file can be parsed as command line
-- arguments (eg, quotes must be balanced); return a pretty, multiline error message if not.
confArgsE :: Conf -> Either String ()
confArgsE conf@Conf{confSections} =
  mapM_ argline [lnuma | ConfSection{csArgs} <- confSections, lnuma <- csArgs]
  where
    argline (lnum, l) = case wordsmay l of
      Just _  -> Right ()
      Nothing -> Left $ confErrorAt conf lnum l $
        "this config file line could not be parsed as command line arguments.\n"
        <> "Is there an unclosed quote? (A # outside quotes starts a comment.)"

-- | Make a pretty, multiline error message about a problem on the given line
-- of this config file: file path and line number, an excerpt showing the line
-- as written (or the given fallback text), and an explanation.
confErrorAt :: Conf -> Int -> String -> String -> String
confErrorAt Conf{confFile, confText} lnum fallbacktxt explanation =
  printf "%s:%d:\n%s%s" confFile lnum (T.unpack excerpt) explanation
  where
    excerpt = decorateExcerpt lnum Nothing $ (<> T.pack "\n") $
      headDef (T.pack fallbacktxt) $ drop (lnum-1) $ T.lines confText

-- | The result of resolving a command name that may be a command alias.
data ResolvedCommand
  = HledgerCommand String [Arg]  -- ^ a resolved hledger command name, and arguments to prepend
  | ShellCommand String          -- ^ a shell command line (from a !-prefixed alias, ! stripped)
  deriving (Eq,Show)

-- | Resolve a command name which may be a command alias, to either a real hledger command
-- (with any arguments to prepend) or a shell command line (for a @!@-prefixed alias).
-- Aliases can refer to other aliases; a name that is an exact builtin command name (per the
-- given predicate), or already seen during this expansion (a self-reference or cycle), stops
-- the recursion. If a name is defined more than once, the first definition in the given list
-- wins (callers wanting the config file's last-definition-wins behaviour should pass
-- @reverse (confAliases conf)@). This does not enforce the shell-alias trust policy; callers do.
expandCommandAlias :: (String -> Bool) -> [(CommandAlias, CommandLine)] -> String -> ResolvedCommand
expandCommandAlias isbuiltincmd cmdaliases = go []
  where
    go seen name
      | name `notElem` seen
      , not $ isbuiltincmd name
      , Just cmdline <- lookup name cmdaliases =
          case strip cmdline of
            '!':shellcmd -> ShellCommand (strip shellcmd)
            hledgercmd   -> case words' hledgercmd of
              (realcmd:defargs) -> case go (name:seen) realcmd of
                HledgerCommand realcmd' defargs' -> HledgerCommand realcmd' (defargs' <> defargs)
                ShellCommand shellcmd            -> ShellCommand (unwords $ shellcmd : defargs)
              [] -> HledgerCommand name []
      | otherwise = HledgerCommand name []

-- | Is the active config file trusted enough to run its @!@-prefixed shell command aliases?
-- True if the config file was given explicitly with --conf, or is a user-level config file
-- (~/.hledger.conf or the XDG hledger.conf). False for a config file found automatically in the
-- current directory or a parent (which could come from an untrusted downloaded/shared directory),
-- or when there is no config file.
confFileIsTrusted :: RawOpts -> Maybe FilePath -> IO Bool
confFileIsTrusted _ Nothing = return False
confFileIsTrusted rawopts (Just f) =
  case confFileSpecFromRawOpts rawopts of
    SomeConfFile _ -> return True
    _              -> (f `elem`) <$> userConfFiles

-- | Try to read a hledger config from a config file specified by --conf,
-- or the first config file found in any of several default file paths.
-- If --no-conf was used, or if no file was specified or found, this returns a null Conf.
-- If a specified file, or the first file found, can not be read or parsed, this returns an error message.
-- Otherwise this returns the parsed Conf, and the file path.
getConf :: RawOpts -> IO (Either String (Conf, Maybe FilePath))
getConf rawopts = do
  -- As in Cli.hs, conf debug output always goes to stderr;
  -- that's ok as conf is a hledger cli feature for now.
  case confFileSpecFromRawOpts rawopts of
    NoConfFile     -> return $ Right $ dbg1Msg "ignoring config files" (nullconf, Nothing)
    SomeConfFile f -> getCurrentDirectory >>= flip expandPath f >>= readConfFile . dbg1 "using specified config file"
    AutoConfFile   -> do
      fs <- confFiles
      case fs of
        f:_ -> dbg8IO "found config files" fs >> dbg1IO "using nearest config file" f >> readConfFile f
        []  -> return $ Right $ dbg1Msg "no config file found" (nullconf, Nothing)

-- | Like getConf but throws an error on failure.
getConf' :: RawOpts -> IO (Conf, Maybe FilePath)
getConf' rawopts = getConf rawopts >>= either error' return

-- | Read this config file and parse its contents, or return an error message.
readConfFile :: FilePath -> IO (Either String (Conf, Maybe FilePath))
readConfFile f = handle (\(e::IOError) -> return $ Left $ show e) $ do
  -- avoid GHC 9.10.1's ugly stack trace when calling readFile on a nonexistent file
  exists <- doesFileExist f
  case exists of
    False -> return $ Left $ f <> " does not exist"
    True -> do
      txt <- readFile f <&> T.pack
      case parseConf f txt of
        Left err -> return $ Left $ customErrorBundlePretty err
        Right cs -> do
          let conf = nullconf{
                 confFile     = f
                ,confText     = txt
                ,confFormat   = 1
                ,confSections = cs
                }
          -- validate the config now, so problems are reported promptly:
          -- argument lines must be parseable as command line arguments,
          -- and command alias definitions must be well formed
          return $ (conf, Just f) <$ (confArgsE conf >> confAliasesE conf)

-- -- | Like readConf, but throw an error on failure.
-- readConfFile' :: FilePath -> IO (Conf, Maybe FilePath)
-- readConfFile' f = readConfFile f >>= either (error' . show) return

-- | Get the highest precedence config file, based on the current directory.
activeConfFile :: IO (Maybe FilePath)
activeConfFile = headMay <$> confFiles

-- | Get the highest precedence local config file: 
-- a config file in the current directory or above, that is not a user-wide config file.
activeLocalConfFile :: IO (Maybe FilePath)
activeLocalConfFile = do
  ufs <- userConfFiles
  mf <- headMay <$> confFiles
  return $ case mf of
    Just f | f `notElem` ufs -> Just f
    _ -> Nothing

-- | Get the highest precedence user-wide config file, based on the current directory.
-- (This may not be the active config file.)
activeUserConfFile :: IO (Maybe FilePath)
activeUserConfFile = headMay <$> userConfFiles

-- | Get the possibleConfFiles which exist, based on the current directory.
confFiles :: IO [FilePath]
confFiles = possibleConfFiles >>= existingFiles

-- | Get the possibleUserConfFiles which exist, based on the current directory.
userConfFiles :: IO [FilePath]
userConfFiles = possibleUserConfFiles >>= existingFiles

-- | Filter a list of paths to just the existing files.
existingFiles :: [FilePath] -> IO [FilePath]
existingFiles fs =
  fmap catMaybes $ forM fs $ \f -> do
    exists <- doesFileExist f
    return $ if exists then Just f else Nothing

-- | Get the possible paths for a hledger config file, highest precedence first:
-- hledger.conf in the current directory, 
-- hledger.conf in any parent directory, 
-- .hledger.conf in the home directory,
-- or hledger.conf in the XdgConfig directory.
possibleConfFiles :: IO [FilePath]
possibleConfFiles = do
  ds   <- possibleConfDirs
  home <- getHomeDirectory
  return $ dbg8 "possible config file paths" $
    flip map ds $ \d -> d </> if d==home then ".hledger.conf" else "hledger.conf"

-- | Like possibleConfFiles, but consider only user-wide hledger config files:
-- .hledger.conf in the home directory,
-- or hledger.conf in the XdgConfig directory.
possibleUserConfFiles :: IO [FilePath]
possibleUserConfFiles = do
  home <- getHomeDirectory
  xdgc <- getXdgDirectory XdgConfig "hledger"
  let ds = [home,xdgc]
  return $ dbg8 "possible user config file paths" $
    flip map ds $ \d -> d </> if d==home then ".hledger.conf" else "hledger.conf"

-- | Get the directories where a hledger config file could be, highest precedence first:
-- the current directory, any parent directory, the home directory, or the XdgConfig directory.
possibleConfDirs :: IO [FilePath]
possibleConfDirs = do
  xdgc <- getXdgDirectory XdgConfig "hledger"
  home <- getHomeDirectory
  here <- getCurrentDirectory
  dirs <- getDirsUpToRoot here
  let dirs2 = if home `elem` dirs then dirs else dirs <> [home]
  let dirs3 = if xdgc `elem` dirs2 then dirs2 else dirs2 <> [xdgc]
  return $ dbg8 "searching config dirs" dirs3

-- | Get this directory and all of its parents up to /.
getDirsUpToRoot :: FilePath -> IO [FilePath]
getDirsUpToRoot dir = return $ go [] dir
  where
    go seen d = if
      | d `elem` seen || length seen >= 100 -> []  -- just in case
      | d=="/"    -> [d]
      | otherwise -> d : go (d:seen) (takeDirectory d)

-- config file parsing

parseConf :: FilePath -> Text -> Either (ParseErrorBundle Text HledgerParseErrorData) [ConfSection]
parseConf = runParser confp

dp :: String -> TextParser m ()
dp = const $ return ()  -- no-op
-- dp = dbgparse 0  -- trace parse state at this --debug level

-- get the config file line number at the current parse position
sourceLineNumberp :: TextParser Identity Int
sourceLineNumberp = unPos . sourceLine <$> getSourcePos

whitespacep, commentlinesp, restoflinep :: TextParser Identity ()
whitespacep   = void $ {- dp "whitespacep"   >> -} many spacenonewline
-- Uses try so that a non-empty, non-comment line (possibly indented) is left for
-- another parser instead of failing here after consuming its leading whitespace.
commentlinesp = void $ {- dp "commentlinesp" >> -} many (try $ emptyorcommentlinep2 "#")
restoflinep   = void $ {- dp "restoflinep"   >> -} whitespacep >> emptyorcommentlinep2 "#"

confp :: TextParser Identity [ConfSection]  -- a monadic TextParser to allow reusing other hledger parsers
confp = do
  dp "confp"
  commentlinesp
  genas <- many arglinep
  let s = ConfSection "general" genas
  ss <- many $ do
    (n, ma) <- sectionstartp
    -- In an [alias] section, a NAME = ... value can span more-indented lines; parse each
    -- alias as one logical (joined) line. Other sections keep one argument per line.
    as <- if n == "alias" then many aliasdefp else many arglinep
    return $ ConfSection n (maybe as (:as) ma)
  whitespacep  -- tolerate trailing whitespace with no final newline (a blank last line)
  eof
  return $ s:ss

-- parse a section name and possibly arguments written on the same line
sectionstartp :: TextParser Identity (String, Maybe (Int, Arg))
sectionstartp = do
  dp "sectionstartp"
  try (whitespacep <* lookAhead (char '['))  -- ignore any leading whitespace before the [
  char '['
  n <- fmap strip $ some $ noneOf "]#\n"
  char ']'
  -- dp "sectionstartp2"
  whitespacep
  -- dp "sectionstartp3"
  lnum <- sourceLineNumberp
  ma <- fmap (fmap strip) $ optional argtextp
  -- dp "sectionstartp4"
  restoflinep
  -- dp "sectionstartp5"
  commentlinesp
  -- dp "sectionstartp6"
  return (n, (lnum,) <$> ma)

-- | Parse config argument-line text up to an unquoted '#' (which starts a comment) or end of line,
-- keeping any '#' that appears inside single or double quotes (so quoted arguments can contain '#').
argtextp :: TextParser Identity String
argtextp = fmap concat $ some $
      quotedspanp '\'' <|> quotedspanp '"' <|> some (noneOf "'\"#\n")
  where
    quotedspanp q = do
      _  <- char q
      s  <- many (noneOf [q,'\n'])
      qc <- optional (char q)
      return $ q : s ++ maybe "" pure qc

-- Uses try so that an indented section header ([..]) is left for sectionstartp
-- rather than failing here after consuming its leading whitespace.
arglinep :: TextParser Identity (Int, Arg)
arglinep = try $ do
  dp "arglinep"
  whitespacep  -- ignore any leading whitespace
  -- dp "arglinep2"
  notFollowedBy $ char '['  -- an indented section header is not an argument line
  -- dp "arglinep3"
  lnum <- sourceLineNumberp
  a <- argtextp
  -- dp "arglinep4"
  restoflinep <|> whitespacep  -- whitespace / same-line comment, possibly with no newline
  commentlinesp
  return (lnum, strip a)

-- | Parse one alias definition in an [alias] section: a "NAME = ..." line, plus any
-- following lines indented more than it, joined (whitespace-normalised) into one logical line.
-- Blank and comment lines are skipped; a line indented no more than the NAME line, a section
-- header, or end of file ends the definition. This is what lets an alias's command line span
-- several indented lines.
aliasdefp :: TextParser Identity (Int, Arg)
aliasdefp = try $ do
  whitespacep  -- ignore any leading whitespace
  notFollowedBy $ char '['  -- an indented section header is not an alias definition
  lnum <- sourceLineNumberp
  ref  <- indentcolp  -- the column of this alias's NAME
  first <- argtextp
  restoflinep <|> whitespacep
  conts <- many (continuationp ref)
  commentlinesp  -- consume trailing blank/comment lines before the next definition or header
  return (lnum, strip $ unwords $ strip first : conts)
  where
    -- a line indented more than ref (the NAME column), continuing the alias's command line
    continuationp ref = try $ do
      commentlinesp  -- skip any blank/comment lines within the indented block
      whitespacep
      col <- indentcolp
      guard $ col > ref
      notFollowedBy $ char '['  -- a section header ends the definition even if indented
      s <- argtextp
      restoflinep <|> whitespacep
      return $ strip s

-- the column (1-based) at the current parse position, used to compare indentation
indentcolp :: TextParser Identity Int
indentcolp = unPos . sourceColumn <$> getSourcePos


-- initialiseAndParseJournal :: ErroringJournalParser IO ParsedJournal -> InputOpts
--                           -> FilePath -> Text -> ExceptT String IO Journal
-- initialiseAndParseJournal parser iopts f txt =
--     prettyParseErrors $ runParserT (evalStateT parser initJournal) f txt
--   where
--     y = first3 . toGregorian $ _ioDay iopts
--     initJournal = nulljournal{jparsedefaultyear = Just y, jparseincludefilestack = [f]}
--     -- Flatten parse errors and final parse errors, and output each as a pretty String.
--     prettyParseErrors :: ExceptT FinalParseError IO (Either (ParseErrorBundle Text HledgerParseErrorData) a)
--                       -> ExceptT String IO a
--     prettyParseErrors = withExceptT customErrorBundlePretty . liftEither
--                     <=< withExceptT (finalErrorBundlePretty . attachSource f txt)
