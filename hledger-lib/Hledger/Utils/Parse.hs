{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module Hledger.Utils.Parse (

  -- * Some basic hledger parser flavours
  SimpleStringParser,
  SimpleTextParser,
  TextParser,

  -- * SourcePos
  SourcePos(..),
  mkPos,
  unPos,
  initialPos,
  sourcePosPretty,
  sourcePosPairPretty,

  -- * Parsers and helpers
  choice',
  choiceInState,
  surroundedBy,
  parsewith,
  runTextParser,
  rtp,
  parsewithString,
  parseWithState,
  parseWithState',
  fromparse,
  parseerror,
  nonspace,
  isNewline,
  isNonNewlineSpace,
  restofline,
  eolof,
  spacenonewline,
  skipNonNewlineSpaces,
  skipNonNewlineSpaces1,
  skipNonNewlineSpaces',
  peekChar,
  peekChars2,
  peekAfterSpaces,
  manyWhile,

  -- ** Trace the state of hledger parsers
  dbgparse,

  -- * More helpers, previously in Text.Megaparsec.Custom

  -- ** Custom parse error types
  HledgerParseErrorData,
  HledgerParseErrors,

  -- ** Failing with an arbitrary source position
  parseErrorAt,
  parseErrorAtRegion,

  -- ** Re-parsing
  SourceExcerpt,
  getExcerptText,
  excerpt_,
  reparseExcerpt,

  -- ** Pretty-printing custom parse errors
  customErrorBundlePretty,
  finalizeCustomErrorBundle,

  -- ** "Final" parse errors
  FinalParseError,
  FinalParseError',
  FinalParseErrorBundle,
  FinalParseErrorBundle',

  -- *** Constructing "final" parse errors
  finalError,
  finalFancyFailure,
  finalFail,
  finalCustomFailure,
  finalMessageFailure,

  -- *** Pretty-printing "final" parse errors
  finalErrorBundlePretty,
  attachSource,

  -- *** Handling parse errors from include files with "final" parse errors
  parseIncludeFile,

)
where

import Control.Monad (MonadPlus, when)
import Data.Text qualified as T
import Text.Megaparsec
import Text.Printf
import Control.Monad.State.Strict (StateT, evalStateT)
import Data.Char
import Data.Functor (void)
import Data.Functor.Identity (Identity(..))
import Data.Text (Text)
import Text.Megaparsec.Char
-- import Text.Megaparsec.Debug (dbg)

import Control.Monad.Except (ExceptT, MonadError, catchError, throwError)
import Control.Monad.Trans.Class (lift)
import Data.List.NonEmpty qualified as NE
import Data.Monoid (Alt(..))
import Data.Set qualified as S

import Hledger.Utils.Debug (debugLevel, dbg0Msg)

-- | A parser of string to some type.
type SimpleStringParser a = Parsec HledgerParseErrorData String a

-- | A parser of strict text to some type.
type SimpleTextParser = Parsec HledgerParseErrorData Text  -- XXX an "a" argument breaks the CsvRulesParser declaration somehow

-- | A parser of text that runs in some monad.
type TextParser m a = ParsecT HledgerParseErrorData Text m a

-- class (Stream s, MonadPlus m) => MonadParsec e s m 
-- dbgparse :: (MonadPlus m, MonadParsec e String m) => Int -> String -> m ()

-- | Trace to stderr or log to debug log the provided label (if non-null)
-- and current parser state (position and next input),
-- if the global debug level is at or above the specified level.
-- See also: Hledger.Utils.Debug, megaparsec's dbg.
-- Uses unsafePerformIO.
-- XXX Can be hard to make this evaluate.
dbgparse :: Int -> String -> TextParser m ()
dbgparse level msg = when (level <= debugLevel) $ do
  pos <- getSourcePos
  next <- (T.take peeklength) `fmap` getInput
  let (l,c) = (sourceLine pos, sourceColumn pos)
      s  = printf "at line %2d col %2d: %s" (unPos l) (unPos c) (show next) :: String
      s' = printf ("%-"++show (peeklength+30)++"s") s ++ " " ++ msg
  dbg0Msg s' $ return ()
  where
    peeklength = 30

-- | Render a pair of source positions in human-readable form, only displaying the range of lines,
-- or just the one line number if the range is a single line.
sourcePosPairPretty :: (SourcePos, SourcePos) -> String
sourcePosPairPretty (SourcePos fp l1 _, SourcePos _ l2 c2) =
    fp ++ ":" ++ show l1' ++ (if l2' > l1' then "-" ++ show l2' else "")
  where
    l1' = unPos l1
    l2' = if unPos c2 == 1 then unPos l2 - 1 else unPos l2  -- might be at end of file with a final new line

-- | Backtracking choice, use this when alternatives share a prefix.
-- Consumes no input if all choices fail.
choice' :: [TextParser m a] -> TextParser m a
choice' = choice . map try

-- | Backtracking choice, use this when alternatives share a prefix.
-- Consumes no input if all choices fail.
choiceInState :: [StateT s (ParsecT HledgerParseErrorData Text m) a] -> StateT s (ParsecT HledgerParseErrorData Text m) a
choiceInState = choice . map try

surroundedBy :: Applicative m => m openclose -> m a -> m a
surroundedBy p = between p p

parsewith :: Parsec e Text a -> Text -> Either (ParseErrorBundle Text e) a
parsewith p = runParser p ""

-- | Run a text parser in the identity monad. See also: parseWithState.
runTextParser, rtp :: TextParser Identity a -> Text -> Either HledgerParseErrors a
runTextParser = parsewith
rtp = runTextParser

parsewithString :: Parsec e String a -> String -> Either (ParseErrorBundle String e) a
parsewithString p = runParser p ""

-- | Run a stateful parser with some initial state on a text.
-- See also: runTextParser, runJournalParser.
parseWithState
  :: Monad m
  => st
  -> StateT st (ParsecT HledgerParseErrorData Text m) a
  -> Text
  -> m (Either HledgerParseErrors a)
parseWithState ctx p = runParserT (evalStateT p ctx) ""

parseWithState'
  :: (Stream s)
  => st
  -> StateT st (ParsecT e s Identity) a
  -> s
  -> (Either (ParseErrorBundle s e) a)
parseWithState' ctx p = runParser (evalStateT p ctx) ""

fromparse :: (Show t, Show (Token t), Show e) => Either (ParseErrorBundle t e) a -> a
fromparse = either parseerror id

parseerror :: (Show t, Show (Token t), Show e) => ParseErrorBundle t e -> a
parseerror e = errorWithoutStackTrace $ showParseError e  -- PARTIAL:

showParseError :: (Show t, Show (Token t), Show e) => ParseErrorBundle t e -> String
showParseError e = "parse error at " ++ show e


isNewline :: Char -> Bool 
isNewline '\n' = True
isNewline _    = False

nonspace :: TextParser m Char
nonspace = satisfy (not . isSpace)

isNonNewlineSpace :: Char -> Bool
isNonNewlineSpace c = not (isNewline c) && isSpace c

spacenonewline :: (Stream s, Char ~ Token s) => ParsecT HledgerParseErrorData s m Char
spacenonewline = satisfy isNonNewlineSpace
{-# INLINABLE spacenonewline #-}

restofline :: TextParser m String
restofline = T.unpack <$> takeWhileP Nothing (/= '\n') <* eolof

-- Skip many non-newline spaces.
skipNonNewlineSpaces :: (Stream s, Token s ~ Char) => ParsecT HledgerParseErrorData s m ()
skipNonNewlineSpaces = void $ takeWhileP Nothing isNonNewlineSpace
{-# INLINABLE skipNonNewlineSpaces #-}

-- Skip many non-newline spaces, failing if there are none.
skipNonNewlineSpaces1 :: (Stream s, Token s ~ Char) => ParsecT HledgerParseErrorData s m ()
skipNonNewlineSpaces1 = void $ takeWhile1P Nothing isNonNewlineSpace
{-# INLINABLE skipNonNewlineSpaces1 #-}

-- | Skip any non-newline whitespace, and return whether there was any.
skipNonNewlineSpaces' :: (Stream s, Token s ~ Char) => ParsecT HledgerParseErrorData s m Bool
skipNonNewlineSpaces' = do
  o <- getOffset
  skipNonNewlineSpaces
  (> o) <$> getOffset
{-# INLINABLE skipNonNewlineSpaces' #-}

-- | Look at the next character of the input, if any, without consuming it.
-- Unlike a failed parse attempt this constructs no parse error, so it is a cheap
-- way to decide whether an optional or alternative parser could succeed before running it.
peekChar :: TextParser m (Maybe Char)
peekChar = fmap fst . T.uncons <$> getInput
{-# INLINABLE peekChar #-}

-- | Like peekChar, but returning the next two characters, if any.
peekChars2 :: TextParser m (Maybe Char, Maybe Char)
peekChars2 = do
  s <- getInput
  pure $ case T.uncons s of
    Nothing       -> (Nothing, Nothing)
    Just (c1, s') -> (Just c1, fst <$> T.uncons s')
{-# INLINABLE peekChars2 #-}

-- | Like peekChar, but looking past any non-newline whitespace (not consuming that either).
-- Returns whether there was such whitespace, and the character following it, if any.
peekAfterSpaces :: TextParser m (Bool, Maybe Char)
peekAfterSpaces = do
  s <- getInput
  let spaced = maybe False (isNonNewlineSpace . fst) $ T.uncons s
  pure (spaced, fst <$> T.uncons (T.dropWhile isNonNewlineSpace s))
{-# INLINABLE peekAfterSpaces #-}

-- | Run a parser repeatedly, collecting the results, like many; but continue only
-- while a test (typically a cheap look at the next input, like peekChar) says it
-- could succeed, so that the end of the sequence is found without a failed parse
-- attempt. As with many, the parser failing without consuming input also ends the sequence.
manyWhile :: MonadPlus m => m Bool -> m a -> m [a]
manyWhile test p = go
  where
    go = do
      continue <- test
      if continue then ((:) <$> p <*> go) <|> pure [] else pure []
{-# INLINABLE manyWhile #-}

eolof :: TextParser m ()
eolof = void newline <|> eof



-- A bunch of megaparsec helpers, eg for re-parsing (formerly in Text.Megaparsec.Custom).
-- I think these are generic apart from the HledgerParseError name.

--- * Custom parse error types

-- | Custom error data for hledger parsers. Specialised for a 'Text' parse stream.
-- ReparseableTextParseErrorData ?
data HledgerParseErrorData
  -- | Fail with a message at a specific source position interval. The
  -- interval must be contained within a single line.
  = ErrorFailAt Int -- Starting offset
                Int -- Ending offset
                String -- Error message
  -- | Re-throw parse errors obtained from the "re-parsing" of an excerpt
  -- of the source text.
  | ErrorReparsing
      (NE.NonEmpty (ParseError Text HledgerParseErrorData)) -- Source fragment parse errors
  deriving (Show, Eq, Ord)

-- | A specialised version of ParseErrorBundle: 
-- a non-empty collection of hledger parse errors, 
-- equipped with PosState to help pretty-print them.
-- Specialised for a 'Text' parse stream.
type HledgerParseErrors = ParseErrorBundle Text HledgerParseErrorData

-- We require an 'Ord' instance for 'CustomError' so that they may be
-- stored in a 'Set'. The actual instance is inconsequential, so we just
-- derive it, but the derived instance requires an (orphan) instance for
-- 'ParseError'. Hopefully this does not cause any trouble.

deriving instance Ord (ParseError Text HledgerParseErrorData)

-- Note: the pretty-printing of our 'HledgerParseErrorData' type is only partally
-- defined in its 'ShowErrorComponent' instance; we perform additional
-- adjustments in 'customErrorBundlePretty'.

instance ShowErrorComponent HledgerParseErrorData where
  showErrorComponent (ErrorFailAt _ _ errMsg) = errMsg
  showErrorComponent (ErrorReparsing _) = "" -- dummy value

  errorComponentLen (ErrorFailAt startOffset endOffset _) =
    endOffset - startOffset
  errorComponentLen (ErrorReparsing _) = 1 -- dummy value


--- * Failing with an arbitrary source position

-- | Fail at a specific source position, given by the raw offset from the
-- start of the input stream (the number of tokens processed at that
-- point).
parseErrorAt :: Int -> String -> HledgerParseErrorData
parseErrorAt offset = ErrorFailAt offset (offset+1)

-- | Fail at a specific source interval, given by the raw offsets of its
-- endpoints from the start of the input stream (the numbers of tokens
-- processed at those points).
--
-- Note that care must be taken to ensure that the specified interval does
-- not span multiple lines of the input source. This will not be checked.
parseErrorAtRegion
  :: Int    -- ^ Start offset
  -> Int    -- ^ End end offset
  -> String -- ^ Error message
  -> HledgerParseErrorData
parseErrorAtRegion startOffset endOffset msg =
  if startOffset < endOffset
    then ErrorFailAt startOffset endOffset msg'
    else ErrorFailAt startOffset (startOffset+1) msg'
  where
    msg' = "\n" ++ msg


--- * Re-parsing

-- | A fragment of source suitable for "re-parsing". The purpose of this
-- data type is to preserve the content and source position of the excerpt
-- so that parse errors raised during "re-parsing" may properly reference
-- the original source.
data SourceExcerpt = SourceExcerpt Int  -- Offset of beginning of excerpt
                                   Text -- Fragment of source file

-- | Get the raw text of a source excerpt.
getExcerptText :: SourceExcerpt -> Text
getExcerptText (SourceExcerpt _ txt) = txt

-- | 'excerpt_ p' applies the given parser 'p' and extracts the portion of
-- the source consumed by 'p', along with the source position of this
-- portion. This is the only way to create a source excerpt suitable for
-- "re-parsing" by 'reparseExcerpt'.

-- This function could be extended to return the result of 'p', but we don't
-- currently need this.

excerpt_ :: MonadParsec HledgerParseErrorData Text m => m a -> m SourceExcerpt
excerpt_ p = do
  offset <- getOffset
  (!txt, _) <- match p
  pure $ SourceExcerpt offset txt

-- | 'reparseExcerpt s p' "re-parses" the source excerpt 's' using the
-- parser 'p'. Parse errors raised by 'p' will be re-thrown at the source
-- position of the source excerpt.
--
-- In order for the correct source file to be displayed when re-throwing
-- parse errors, we must ensure that the source file during the use of
-- 'reparseExcerpt s p' is the same as that during the use of 'excerpt_'
-- that generated the source excerpt 's'. However, we can usually expect
-- this condition to be satisfied because, at the time of writing, the
-- only changes of source file in the codebase take place through include
-- files, and the parser for include files neither accepts nor returns
-- 'SourceExcerpt's.

reparseExcerpt
  :: Monad m
  => SourceExcerpt
  -> ParsecT HledgerParseErrorData Text m a
  -> ParsecT HledgerParseErrorData Text m a
reparseExcerpt (SourceExcerpt offset txt) p = do
  (_, res) <- lift $ runParserT' p (offsetInitialState offset txt)
  case res of
    Right result -> pure result
    Left errBundle -> customFailure $ ErrorReparsing $ bundleErrors errBundle

  where
    offsetInitialState :: Int -> s ->
#if MIN_VERSION_megaparsec(8,0,0)
      State s e
#else
      State s
#endif
    offsetInitialState initialOffset s = State
      { stateInput  = s
      , stateOffset = initialOffset
      , statePosState = PosState
        { pstateInput = s
        , pstateOffset = initialOffset
        , pstateSourcePos = initialPos ""
        , pstateTabWidth = defaultTabWidth
        , pstateLinePrefix = ""
        }
#if MIN_VERSION_megaparsec(8,0,0)
      , stateParseErrors = []
#endif
      }

--- * Pretty-printing custom parse errors

-- | Pretty-print our custom parse errors. It is necessary to use this
-- instead of 'errorBundlePretty' when custom parse errors are thrown.
--
-- This function intercepts our custom parse errors and applies final
-- adjustments ('finalizeCustomError') before passing them to
-- 'errorBundlePretty'. These adjustments are part of the implementation
-- of the behaviour of our custom parse errors.
--
-- Note: We must ensure that the offset of the 'PosState' of the provided
-- 'ParseErrorBundle' is no larger than the offset specified by a
-- 'ErrorFailAt' constructor. This is guaranteed if this offset is set to
-- 0 (that is, the beginning of the source file), which is the
-- case for 'ParseErrorBundle's returned from 'runParserT'.

customErrorBundlePretty :: HledgerParseErrors -> String
customErrorBundlePretty = errorBundlePretty . finalizeCustomErrorBundle

-- | Apply the final adjustments to the custom parse errors in this error
-- bundle (see 'customErrorBundlePretty'), leaving errors which megaparsec's
-- standard 'errorBundlePretty' can render correctly. Exposed for callers
-- which need to adjust the bundle further before rendering it.
finalizeCustomErrorBundle :: HledgerParseErrors -> HledgerParseErrors
finalizeCustomErrorBundle errBundle =
  errBundle { bundleErrors =
    NE.sortWith errorOffset $ -- megaparsec requires that the list of errors be sorted by their offsets
    bundleErrors errBundle >>= finalizeCustomError }

  where
    finalizeCustomError
      :: ParseError Text HledgerParseErrorData -> NE.NonEmpty (ParseError Text HledgerParseErrorData)
    finalizeCustomError err = case findCustomError err of
      Nothing -> pure $ limitExpected err

      Just errFailAt@(ErrorFailAt startOffset _ _) ->
        -- Adjust the offset
        pure $ FancyError startOffset $ S.singleton $ ErrorCustom errFailAt

      Just (ErrorReparsing errs) ->
        -- Extract and finalize the inner errors
        errs >>= finalizeCustomError

    -- If any custom errors are present, arbitrarily take the first one
    -- (since only one custom error should be used at a time).
    findCustomError :: ParseError Text HledgerParseErrorData -> Maybe HledgerParseErrorData
    findCustomError err = case err of
      FancyError _ errSet ->
        finds (\case {ErrorCustom e -> Just e; _ -> Nothing}) errSet
      _ -> Nothing

    finds :: (Foldable t) => (a -> Maybe b) -> t a -> Maybe b
    finds f = getAlt . foldMap (Alt . f)

    -- Megaparsec lists every alternative the parser expected; for some parsers
    -- (eg period expressions, CSV rule field names) that's dozens or hundreds.
    -- When there are that many, show just the first few.
    limitExpected :: ParseError Text HledgerParseErrorData -> ParseError Text HledgerParseErrorData
    limitExpected (TrivialError o u es) | S.size es > 20 =
      TrivialError o u $ S.fromList (take 10 $ S.toAscList es) <> S.singleton (Label $ 'o' NE.:| ("ther valid values (" ++ show (S.size es - 10) ++ " more)"))
    limitExpected e = e


--- * "Final" parse errors
--
-- | A type representing "final" parse errors that cannot be backtracked
-- from and are guaranteed to halt parsing. The anti-backtracking
-- behaviour is implemented by an 'ExceptT' layer in the parser's monad
-- stack, using this type as the 'ExceptT' error type.
--
-- We have three goals for this type:
-- (1) it should be possible to convert any parse error into a "final"
-- parse error,
-- (2) it should be possible to take a parse error thrown from an include
-- file and re-throw it in the context of the parent file, and
-- (3) the pretty-printing of "final" parse errors should be consistent
-- with that of ordinary parse errors, but should also report the stack of
-- parent files when errors are thrown from included files, and
-- (4) readers of non-journal formats (like CSV), which produce complete
-- error messages rather than parse errors, should be able to throw those
-- as "final" parse errors too, so they get the same include file stack.
--
-- In order to pretty-print a "final" parse error (goal 3), it must be
-- bundled with include filepaths and its full source text. When a "final"
-- parse error is thrown from within a parser, we do not have access to
-- the full source, so we must hold the parse error ('FinalParseError')
-- until it can be combined with the full source (and any parent file paths)
-- by the parser's caller ('FinalParseErrorBundle').

data FinalParseError' e
  -- a parse error thrown as a "final" parse error
  = FinalError           (ParseError Text e)
  -- a parse error obtained from running a parser, e.g. using 'runParserT'
  | FinalBundle          (ParseErrorBundle Text e)
  -- a parse error thrown from an include file
  | FinalBundleWithStack (FinalParseErrorBundle' e)
  -- a complete error message from a non-megaparsec reader (eg for CSV), shown without a source excerpt
  | FinalMessage         String
  deriving (Show)

type FinalParseError = FinalParseError' HledgerParseErrorData

-- We need a 'Monoid' instance for 'FinalParseError' so that 'ExceptT
-- FinalParseError m' is an instance of Alternative and MonadPlus, which
-- is needed to use some parser combinators, e.g. 'many'.
--
-- This monoid instance simply takes the first (left-most) error.

instance Semigroup (FinalParseError' e) where
  e <> _ = e

instance Monoid (FinalParseError' e) where
  mempty = FinalError $ FancyError 0 $
            S.singleton (ErrorFail "default parse error")
  mappend = (<>)

-- | A type bundling a 'ParseError' with its full source text, filepath,
-- and stack of include files. Suitable for pretty-printing.
--
-- Megaparsec's 'ParseErrorBundle' type already bundles a parse error with
-- its full source text and filepath, so we just add a stack of include
-- files. Or, it can hold a complete error message instead (see 'FinalMessage').
data FinalParseErrorBundle' e = FinalParseErrorBundle'
  { finalErrorBundle :: Either String (ParseErrorBundle Text e)
  , includeFileStack :: [FilePath]
  } deriving (Show)

type FinalParseErrorBundle = FinalParseErrorBundle' HledgerParseErrorData


--- * Constructing and throwing final parse errors

-- | Convert a "regular" parse error into a "final" parse error.
finalError :: ParseError Text e -> FinalParseError' e
finalError = FinalError

-- | Like megaparsec's 'fancyFailure', but as a "final" parse error.
finalFancyFailure
  :: (MonadParsec e s m, MonadError (FinalParseError' e) m)
  => S.Set (ErrorFancy e) -> m a
finalFancyFailure errSet = do
  offset <- getOffset
  throwError $ FinalError $ FancyError offset errSet

-- | Like 'fail', but as a "final" parse error.
finalFail :: (MonadParsec e s m, MonadError (FinalParseError' e) m) => String -> m a
finalFail = finalFancyFailure . S.singleton . ErrorFail

-- | Like megaparsec's 'customFailure', but as a "final" parse error.
finalCustomFailure :: (MonadParsec e s m, MonadError (FinalParseError' e) m) => e -> m a
finalCustomFailure = finalFancyFailure . S.singleton . ErrorCustom

-- | Throw a complete error message, eg from a non-megaparsec reader, as a "final" parse error.
-- It will be shown with the include file stack, but without a source excerpt.
finalMessageFailure :: MonadError (FinalParseError' e) m => String -> m a
finalMessageFailure = throwError . FinalMessage


--- * Pretty-printing "final" parse errors

-- | Pretty-print a "final" parse error: print the stack of include files,
-- then apply the pretty-printer for parse error bundles.
-- Note that 'attachSource' must be used on a "final" parse error before it can be pretty-printed.
finalErrorBundlePretty :: FinalParseErrorBundle' HledgerParseErrorData -> String
finalErrorBundlePretty bundle =
     concatMap showIncludeFilepath (includeFileStack bundle)
  <> either id customErrorBundlePretty (finalErrorBundle bundle)
  where
    showIncludeFilepath path = "in file included from " <> path <> ",\n"

-- | Attach a filepath and source text to a "final" parse error so that it can be pretty-printed.
-- You must ensure that you provide the appropriate source text and filepath.
attachSource :: FilePath -> Text -> FinalParseError' e -> FinalParseErrorBundle' e
attachSource filePath sourceText finalParseError = case finalParseError of

  -- A parse error thrown directly with the 'FinalError' constructor
  -- requires both source and filepath.
  FinalError err ->
    let bundle = ParseErrorBundle
          { bundleErrors = err NE.:| []
          , bundlePosState = initialPosState filePath sourceText }
    in  FinalParseErrorBundle'
          { finalErrorBundle = Right bundle
          , includeFileStack  = [] }

  -- A 'ParseErrorBundle' already has the appropriate source and filepath
  -- and so needs neither.
  FinalBundle peBundle -> FinalParseErrorBundle'
    { finalErrorBundle = Right peBundle
    , includeFileStack = [] }

  -- A parse error from a 'FinalParseErrorBundle' was thrown from an
  -- include file, so we add the filepath to the stack.
  FinalBundleWithStack fpeBundle -> fpeBundle
    { includeFileStack = filePath : includeFileStack fpeBundle }

  -- A complete error message needs neither source nor filepath.
  FinalMessage msg -> FinalParseErrorBundle'
    { finalErrorBundle = Left msg
    , includeFileStack = [] }


--- * Handling parse errors from include files with "final" parse errors

-- | Parse an include file with the given parser and initial state,
-- discarding the resulting state,
-- and re-throwing any parse errors as final parse errors with the file's info attached.
parseIncludeFile
  :: Monad m
  => StateT st (ParsecT HledgerParseErrorData Text (ExceptT FinalParseError m)) a
  -> st
  -> FilePath
  -> Text
  -> StateT st (ParsecT HledgerParseErrorData Text (ExceptT FinalParseError m)) a
parseIncludeFile parser initialState filepath text = catchError parser' handler
  where
    parser' = do
      eResult <- lift $ lift $ runParserT (evalStateT parser initialState) filepath text
      case eResult of
        Left parseErrorBundle -> throwError $ FinalBundle parseErrorBundle
        Right result -> pure result
    -- Attach source and filepath of the include file to its parse errors
    handler e = throwError $ FinalBundleWithStack $ attachSource filepath text e


--- * Helpers

-- | Like megaparsec's 'initialState', but instead for 'PosState'.
-- Used when constructing 'ParseErrorBundle's.
-- The values for "tab width" and "line prefix" are taken from 'initialState'.
initialPosState :: FilePath -> Text -> PosState Text
initialPosState filePath sourceText = PosState
  { pstateInput      = sourceText
  , pstateOffset     = 0
  , pstateSourcePos  = initialPos filePath
  , pstateTabWidth   = defaultTabWidth
  , pstateLinePrefix = "" }
