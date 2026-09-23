{-|
Internationalization support for hledger's user-facing output.

Translations live in catalogs in the gettext PO file format, which the
usual translator tools (Poedit, Weblate, Lokalize) understand. Built-in
catalogs are embedded in the executables; a user can override one, or add
a language, with a file in their hledger config directory (see
'translationsOverrideDir'). Lookups are pure functions of a 'Translations'
value, so there is no process-global locale state, and hledger-web can
serve a different language to each request.

Conventions:

- The msgid is the English text. A missing or empty translation falls
  back to it, and 'noTranslations' is the identity, so English output is
  unaffected by this machinery.

- Parameters are @{name}@ placeholders substituted after lookup ('trf'),
  never printf formats: a translation can not crash the program.

- Short words used in more than one sense carry a context ('trc').

- A malformed catalog is reported as a warning and ignored.

This module is experimental and its API may change.
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

module Hledger.Utils.I18n (
  -- * Translations
  Translations(..),
  PluralForms(..),
  noTranslations,
  tr,
  trc,
  trf,
  trn,
  i18n,
  i18nc,
  trTimeLocale,
  translationsForLangOption,
  substitutePlaceholders,
  placeholders,
  -- * Catalogs
  parsePo,
  mergeTranslations,
  builtinTranslations,
  builtinLanguages,
  availableLanguages,
  loadTranslations,
  loadAllTranslations,
  translationsOverrideDir,
  -- * Language tags
  isValidLangTag,
  normalizeLangTag,
  langTagCandidates,
  resolveLang,
  langPrefsFromEnv,
  -- * Plural forms
  parsePluralForms,
  -- * Tests
  tests_I18n,
) where

import Control.Monad (unless, void, when)
import Control.Monad.Combinators.Expr (Operator(..), makeExprParser)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (chr, isAlpha, isAlphaNum, isAscii, isHexDigit, toLower)
import Data.Either (isLeft, rights)
import Data.List (inits, intercalate, partition, sort, sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as M
import Data.Maybe (fromMaybe, isJust, isNothing, listToMaybe, mapMaybe)
import Data.Set (Set)
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (UTCTime, diffUTCTime, getCurrentTime)
import Data.Time.Format (TimeLocale(..), defaultTimeLocale)
import Data.Void (Void)
import Numeric (readHex, readOct)
import System.Directory (XdgDirectory(..), doesDirectoryExist, getFileSize, getXdgDirectory, listDirectory)
import System.Environment (getEnvironment)
import System.FilePath ((</>), dropExtension, takeExtension)
import Text.Megaparsec
import Text.Megaparsec.Char
import Text.Megaparsec.Char.Lexer qualified as L
import Text.Printf (printf)
import Text.Read (readMaybe)

import Hledger.Utils.Debug (debugLevel, dbg1MsgIO)
import Hledger.Utils.IO (embedFileRelativeBytes, usageError, warnIO)
import Hledger.Utils.Test

-- * Translations

-- | A set of translations for one language, looked up by English text
-- (optionally qualified by a context, see 'trc').
data Translations = Translations
  { trLang        :: Text               -- ^ language tag, eg "de", "pt-BR", "zh-Hans"
  , trMessages    :: Map Text Text      -- ^ msgid (or "context\x04msgid") -> translation
  , trPlurals     :: Map Text [Text]    -- ^ singular msgid -> one translation per plural form
  , trPluralForms :: Maybe PluralForms  -- ^ this language's plural rule, from the catalog header
  }

-- | A language's plural rule: how many forms it has, and which form a
-- count selects.
data PluralForms = PluralForms
  { pfCount :: Int
  , pfRule  :: Int -> Int
  }

-- | Shows only the language, so that option dumps stay readable.
instance Show Translations where
  show t = "Translations " ++ show (trLang t)

-- | English: every lookup returns its argument.
noTranslations :: Translations
noTranslations = Translations "en" M.empty M.empty Nothing

-- | Translate this English text, or return it unchanged if there is no translation.
tr :: Translations -> Text -> Text
tr t s = fromMaybe s $ M.lookup s (trMessages t)

-- | Like 'tr', but for a short text that is used in more than one sense.
-- The context (eg "column heading") disambiguates it in the catalog.
trc :: Translations -> Text -> Text -> Text
trc t ctx s = fromMaybe s $ M.lookup (msgKey (Just ctx) s) (trMessages t)

-- | Translate this English template, then fill in its @{name}@ placeholders.
-- Placeholders that are not given stay as they are. Values are inserted
-- verbatim, without being scanned for placeholders themselves.
trf :: Translations -> Text -> [(Text, Text)] -> Text
trf t s params = substitutePlaceholders params (tr t s)

-- | Translate a count phrase, choosing the plural form this language uses
-- for the count, then fill in the @{n}@ placeholder. The two English forms
-- are the msgid and msgid_plural; without a translation, the singular is
-- used for 1 and the plural otherwise.
trn :: Translations -> Int -> Text -> Text -> Text
trn t n singular plural = substitutePlaceholders [("n", T.pack (show n))] form
  where
    form = fromMaybe english $ do
      forms <- M.lookup singular (trPlurals t)
      let i = maybe (\k -> if k == 1 then 0 else 1) pfRule (trPluralForms t) n
      f <- if i >= 0 && i < length forms then Just (forms !! i) else Nothing
      if T.null f then Nothing else Just f
    english = if n == 1 then singular else plural

-- | Mark an English literal that will be translated later, by 'tr', at the
-- point where it is displayed. This is the identity; the catalog
-- extraction tool looks for it. (Like gettext's N_.)
i18n :: Text -> Text
i18n = id

-- | Like 'i18n', for a literal that will be translated with a context by 'trc'.
i18nc :: Text -> Text -> Text
i18nc _ctx s = s

-- | The default time locale with month names translated, for formatting
-- dates. The names are looked up with contexts "month" (full name) and
-- "month abbrev" (short name, used as a column heading).
trTimeLocale :: Translations -> TimeLocale
trTimeLocale t = defaultTimeLocale{ months = zipWith (\f a -> (name "month" f, name "month abbrev" a)) fulls abbrevs }
  where
    name ctx = T.unpack . trc t ctx
    -- TRANSLATORS: stand-alone (nominative) month names, as used in a column heading.
    fulls =
      [ i18nc "month" "January", i18nc "month" "February", i18nc "month" "March"
      , i18nc "month" "April", i18nc "month" "May", i18nc "month" "June"
      , i18nc "month" "July", i18nc "month" "August", i18nc "month" "September"
      , i18nc "month" "October", i18nc "month" "November", i18nc "month" "December"
      ]
    -- TRANSLATORS: short stand-alone month names, as used in a column heading.
    abbrevs =
      [ i18nc "month abbrev" "Jan", i18nc "month abbrev" "Feb", i18nc "month abbrev" "Mar"
      , i18nc "month abbrev" "Apr", i18nc "month abbrev" "May", i18nc "month abbrev" "Jun"
      , i18nc "month abbrev" "Jul", i18nc "month abbrev" "Aug", i18nc "month abbrev" "Sep"
      , i18nc "month abbrev" "Oct", i18nc "month abbrev" "Nov", i18nc "month abbrev" "Dec"
      ]

-- | Choose translations according to the value of a --lang option.
-- No option means English, without reading any files. "auto" follows the
-- LANGUAGE, LC_ALL, LC_MESSAGES and LANG environment variables (see
-- 'langPrefsFromEnv'), falling back to English. Anything else is a
-- language tag, which must have a catalog, built-in or in
-- 'translationsOverrideDir'; otherwise a usage error is raised.
translationsForLangOption :: Maybe String -> IO Translations
translationsForLangOption Nothing = return noTranslations
translationsForLangOption (Just "auto") = do
  available <- availableLanguages
  prefs <- langPrefsFromEnv <$> getEnvironment
  maybe (return noTranslations) loadTranslations $ resolveLang available prefs
translationsForLangOption (Just s)
  | map toLower s `elem` ["c", "posix"] = return noTranslations
  | otherwise = do
      available <- availableLanguages
      case resolveLang available [T.pack s] of
        Just lang -> loadTranslations lang
        Nothing -> usageError $ "--lang: no translations are available for " ++ show s
                     ++ " (available: " ++ T.unpack (T.intercalate ", " available) ++ ")"

-- | Split a template into its literal text and its @{name}@ placeholders.
scanPlaceholders :: Text -> [Either Text Text]
scanPlaceholders s = case T.breakOn "{" s of
  (before, rest)
    | T.null rest -> [Left before | not (T.null before)]
    | otherwise ->
        let (name, rest') = T.break (\c -> c == '}' || c == '{' || not (isNameChar c)) (T.drop 1 rest)
        in case T.uncons rest' of
             Just ('}', remaining) | not (T.null name) -> Left before : Right name : scanPlaceholders remaining
             _ -> Left (before <> "{") : scanPlaceholders (T.drop 1 rest)

-- | Replace each @{name}@ in the text with the value given for that name.
-- Names not given are left in place; values are not scanned again.
substitutePlaceholders :: [(Text, Text)] -> Text -> Text
substitutePlaceholders params = T.concat . map (either id fill) . scanPlaceholders
  where fill name = fromMaybe ("{" <> name <> "}") (lookup name params)

-- | The placeholder names in a template.
placeholders :: Text -> Set Text
placeholders = S.fromList . rights . scanPlaceholders

isNameChar :: Char -> Bool
isNameChar c = isAlphaNum c || c == '_'

msgKey :: Maybe Text -> Text -> Text
msgKey mctx s = maybe s (\c -> c <> "\x04" <> s) mctx

-- * Catalogs

-- | The built-in catalogs, embedded at build time.
builtinCatalogSources :: [(Text, ByteString)]
builtinCatalogSources =
  [ ("de", $(embedFileRelativeBytes "locale/de.po"))
  ]

-- | The built-in catalogs, parsed. A catalog that fails to parse is
-- omitted; the unit tests ensure that does not happen in a release.
builtinTranslations :: Map Text Translations
builtinTranslations = M.fromList
  [ (lang, t)
  | (lang, bs) <- builtinCatalogSources
  , Right s <- [TE.decodeUtf8' bs]
  , Right t <- [parsePo ("built-in catalog " ++ T.unpack lang) lang s]
  ]

-- | The languages with a built-in catalog, plus English.
builtinLanguages :: [Text]
builtinLanguages = "en" : M.keys builtinTranslations

-- | The directory where a user can put a translation catalog named
-- LANG.po, to override a built-in one or to add a language:
-- the locale subdirectory of hledger's config directory
-- (~/.config/hledger/locale on unix, %APPDATA%\\hledger\\locale on windows).
translationsOverrideDir :: IO FilePath
translationsOverrideDir = (</> "locale") <$> getXdgDirectory XdgConfig "hledger"

-- | The largest user catalog we will read.
maxCatalogSize :: Integer
maxCatalogSize = 1024 * 1024

-- | The user's catalog files, by language tag. The tag is taken from the
-- file name and normalized, so DE.po and de.po both serve "de".
overrideCatalogFiles :: IO [(Text, FilePath)]
overrideCatalogFiles = do
  dir <- translationsOverrideDir
  exists <- doesDirectoryExist dir
  files <- if exists then listDirectory dir else return []
  return [ (tag, dir </> f) | f <- sort files, takeExtension f == ".po"
         , Just tag <- [normalizeLangTag (T.pack (dropExtension f))] ]

-- | Read the user's catalog for this language tag, if there is one and it
-- is usable, returning it with its path. Problems are reported as
-- warnings and the catalog ignored.
readOverrideCatalog :: Text -> IO (Maybe (FilePath, Translations))
readOverrideCatalog lang = do
  files <- overrideCatalogFiles
  case lookup lang files of
    Nothing -> return Nothing
    Just f -> do
      size <- getFileSize f
      if size > maxCatalogSize
        then Nothing <$ warnIO ("ignoring translation catalog " ++ f ++ ": it is larger than 1 MiB")
        else do
          bs <- BS.readFile f
          case TE.decodeUtf8' bs of
            Left _ -> Nothing <$ warnIO ("ignoring translation catalog " ++ f ++ ": it is not valid UTF-8")
            Right t -> case parsePo f lang t of
              Left err -> Nothing <$ warnIO ("ignoring translation catalog " ++ f ++ ":\n" ++ err)
              Right c  -> return (Just (f, c))

-- | The language tags for which a catalog exists, built-in or in the
-- user's override directory. Always includes "en".
--
-- Listing the built-in languages parses the built-in catalogs (whichever
-- of them parse are the ones available), once per process. With --debug,
-- reports how long that took.
availableLanguages :: IO [Text]
availableLanguages = do
  t0 <- getCurrentTime
  let nbuiltin = length builtinLanguages - 1
  t1 <- nbuiltin `seq` getCurrentTime
  when (debugLevel >= 1) $
    dbg1MsgIO $ printf "translations: parsed %d built-in catalogs, %.1f ms" nbuiltin (msSince t0 t1)
  overrides <- map fst <$> overrideCatalogFiles
  return $ S.toList $ S.fromList $ builtinLanguages ++ overrides

-- | Load the translations for this language tag (which should be one
-- returned by 'availableLanguages'): the built-in catalog if any, with
-- the user's catalog merged over it if any. With --debug, reports what
-- was loaded, its size, and how long it took.
loadTranslations :: Text -> IO Translations
loadTranslations lang = do
  t0 <- getCurrentTime
  let mbuiltin = M.lookup lang builtinTranslations
      builtin = fromMaybe noTranslations{trLang = lang} mbuiltin
  moverride <- readOverrideCatalog lang
  let trs = maybe builtin (mergeTranslations builtin . snd) moverride
  when (debugLevel >= 1) $ do
    -- Force the merged catalog so that the time is real.
    let entries = M.size (trMessages trs) + M.size (trPlurals trs)
    t1 <- entries `seq` getCurrentTime
    let chars = sum (map T.length (M.keys (trMessages trs) ++ M.elems (trMessages trs)))
              + sum (map T.length (M.keys (trPlurals trs) ++ concat (M.elems (trPlurals trs))))
    let sources = [ "built-in" | isJust mbuiltin ] ++ [ f | Just (f, _) <- [moverride] ]
    dbg1MsgIO $ printf "translations: loaded %s (%s): %d entries, ~%d KB of text, %.1f ms"
      (T.unpack lang) (if null sources then "no catalog" else intercalate ", " sources) entries (chars `div` 1024) (msSince t0 t1)
  return trs

-- | Milliseconds between two times, for debug output.
msSince :: UTCTime -> UTCTime -> Double
msSince t0 t1 = realToFrac (diffUTCTime t1 t0) * 1000

-- | Load the translations for every available language.
loadAllTranslations :: IO (Map Text Translations)
loadAllTranslations = do
  langs <- availableLanguages
  M.fromList <$> mapM (\l -> (,) l <$> loadTranslations l) langs

-- | Merge two catalogs; entries in the second take precedence.
mergeTranslations :: Translations -> Translations -> Translations
mergeTranslations base override = Translations
  { trLang        = trLang override
  , trMessages    = M.union (trMessages override) (trMessages base)
  , trPlurals     = M.union (trPlurals override) (trPlurals base)
  , trPluralForms = trPluralForms override <|> trPluralForms base
  }

-- ** PO parsing

type PoParser = Parsec Void Text

data PoEntry = PoEntry
  { peFlags    :: [Text]
  , peCtx      :: Maybe Text
  , peId       :: Text
  , peIdPlural :: Maybe Text
  , peStr      :: Text
  , peStrs     :: [(Int, Text)]
  }

-- | Parse a catalog in PO format. The arguments are a name for error
-- messages, the language tag to record, and the file's content.
--
-- Handles what translator tools produce: the header entry, translator and
-- extracted comments, references, flags, previous-msgid comments,
-- obsolete entries, contexts, plural forms, multi-line strings, C escapes,
-- a byte order mark and CRLF line endings. Entries flagged fuzzy are
-- skipped (except that the header's Plural-Forms is still used), and an
-- empty translation counts as untranslated. Duplicate entries and a
-- non-UTF-8 charset are errors.
parsePo :: String -> Text -> Text -> Either String Translations
parsePo name lang input = do
  entries <- first errorBundlePretty $ runParser poEntries name (cleanup input)
  buildTranslations name lang entries
  where
    cleanup = T.replace "\r\n" "\n" . T.dropWhile (== '\xFEFF')

poEntries :: PoParser [PoEntry]
poEntries = do
  space
  done <- atEnd
  if done
    then return []
    else do
      flagss <- many commentLine
      mentry <- optional entryFields
      case mentry of
        Nothing
          | null flagss -> fail "expected a comment line or a msgid"
          | otherwise   -> poEntries  -- comments with no entry, eg an obsolete (#~) entry
        Just e -> (e{peFlags = concat flagss} :) <$> poEntries

-- | A comment line. Returns the flags if it is a "#," flags line.
commentLine :: PoParser [Text]
commentLine = do
  _ <- char '#'
  flags <- (char ',' *> (map T.strip . T.splitOn "," <$> restOfLine)) <|> ([] <$ restOfLine)
  space
  return flags
  where restOfLine = takeWhileP Nothing (/= '\n')

entryFields :: PoParser PoEntry
entryFields = do
  ctx <- optional (keyword "msgctxt" *> strings)
  mid <- keyword "msgid" *> strings
  mpl <- optional (keyword "msgid_plural" *> strings)
  case mpl of
    Nothing -> do
      s <- keyword "msgstr" *> strings
      return PoEntry{peFlags = [], peCtx = ctx, peId = mid, peIdPlural = Nothing, peStr = s, peStrs = []}
    Just pl -> do
      ss <- some indexedMsgstr
      return PoEntry{peFlags = [], peCtx = ctx, peId = mid, peIdPlural = Just pl, peStr = "", peStrs = ss}

keyword :: Text -> PoParser ()
keyword k = void $ try (string k <* notFollowedBy (satisfy (\c -> isAlphaNum c || c == '_' || c == '[')) <* hspace)

indexedMsgstr :: PoParser (Int, Text)
indexedMsgstr = do
  _ <- try (string "msgstr[")
  n <- L.decimal
  _ <- char ']'
  hspace
  s <- strings
  return (n, s)

-- | One or more quoted strings, possibly on several lines, concatenated.
strings :: PoParser Text
strings = T.concat <$> some (quotedString <* space)

-- Runs of ordinary characters are taken as slices of the input; only
-- escapes are handled a character at a time.
quotedString :: PoParser Text
quotedString = T.concat <$> (char '"' *> manyTill piece (char '"'))
  where
    piece = takeWhile1P Nothing (\c -> c /= '"' && c /= '\\' && c /= '\n')
        <|> (T.singleton <$> (char '\\' *> escape))
    escape = choice
      [ '\n' <$ char 'n'
      , '\t' <$ char 't'
      , '\r' <$ char 'r'
      , '\\' <$ char '\\'
      , '"'  <$ char '"'
      , '\a' <$ char 'a'
      , '\b' <$ char 'b'
      , '\f' <$ char 'f'
      , '\v' <$ char 'v'
      , char 'x' *> (fromCode readHex <$> takeWhile1P (Just "hex digit") isHexDigit)
      , fromCode readOct . T.pack <$> count' 1 3 octDigitChar
      , anySingle  -- an unknown escape: keep the character
      ]
    fromCode reader s = case reader (T.unpack s) of
      [(n, "")] | n <= 0x10FFFF -> chr n
      _ -> '\xFFFD'

buildTranslations :: String -> Text -> [PoEntry] -> Either String Translations
buildTranslations name lang entries = do
  let (headers, rest) = partition isHeader entries
      headerFields = maybe [] (parseHeader . peStr) (listToMaybe headers)
  case lookup "content-type" headerFields >>= charsetOf of
    Just cs | cs `notElem` ["utf-8", "utf8", "charset"] ->
      Left $ name ++ ": unsupported charset " ++ T.unpack cs ++ " (translation catalogs must be UTF-8)"
    _ -> Right ()
  pf <- case lookup "plural-forms" headerFields of
    Nothing -> Right Nothing
    Just s  -> maybe (Left $ name ++ ": could not parse the Plural-Forms header: " ++ T.unpack s)
                     (Right . Just) (parsePluralForms s)
  let live = filter (notElem "fuzzy" . peFlags) rest
      dups = M.keys $ M.filter (> 1) $ M.fromListWith (+) [ (entryKey e, 1 :: Int) | e <- live ]
  unless (null dups) $
    Left $ name ++ ": duplicate entries for: " ++ unwords (map (show . T.replace "\x04" "|") dups)
  let msgs    = M.fromList [ (entryKey e, s) | e <- live, let s = singularStr e, not (T.null s) ]
      plurals = M.fromList [ (entryKey e, forms) | e <- live, isJust (peIdPlural e)
                           , let forms = map snd (sortOn fst (peStrs e)), any (not . T.null) forms ]
  return Translations{trLang = lang, trMessages = msgs, trPlurals = plurals, trPluralForms = pf}
  where
    isHeader e = T.null (peId e) && isNothing (peCtx e) && isNothing (peIdPlural e)
    entryKey e = msgKey (peCtx e) (peId e)
    singularStr e = case peIdPlural e of
      Nothing -> peStr e
      Just _  -> fromMaybe "" (lookup 0 (peStrs e))
    parseHeader s =
      [ (T.toLower (T.strip k), T.strip (T.drop 1 v))
      | l <- T.lines s, let (k, v) = T.breakOn ":" l, not (T.null v) ]
    charsetOf ct = listToMaybe
      [ T.strip (T.drop 8 p) | p <- map (T.toLower . T.strip) (T.splitOn ";" ct), "charset=" `T.isPrefixOf` p ]

-- ** Plural forms

-- | Parse a PO header's Plural-Forms value, eg
-- "nplurals=2; plural=(n != 1);". The plural expression is the C
-- expression subset gettext allows: n, integers, parentheses, !, %,
-- comparisons, &&, ||, and ?:.
parsePluralForms :: Text -> Maybe PluralForms
parsePluralForms s = do
  let fields = [ (T.strip k, T.strip (T.drop 1 v)) | p <- T.splitOn ";" s, let (k, v) = T.breakOn "=" p, not (T.null v) ]
  n <- lookup "nplurals" fields >>= readMaybe . T.unpack
  e <- lookup "plural" fields
  expr <- parseMaybe (space *> pluralExpr <* eof) e
  return PluralForms{pfCount = n, pfRule = \k -> evalPlural k expr}

data PExpr
  = PN
  | PLit Int
  | PNot PExpr
  | PBin Text PExpr PExpr
  | PCond PExpr PExpr PExpr

evalPlural :: Int -> PExpr -> Int
evalPlural n = go
  where
    go PN = n
    go (PLit i) = i
    go (PNot e) = if go e == 0 then 1 else 0
    go (PCond c a b) = if go c /= 0 then go a else go b
    go (PBin op a b) =
      let x = go a
          y = go b
      in case op of
        "%"  -> if y == 0 then 0 else x `mod` y
        "<"  -> fromBool (x < y)
        "<=" -> fromBool (x <= y)
        ">"  -> fromBool (x > y)
        ">=" -> fromBool (x >= y)
        "==" -> fromBool (x == y)
        "!=" -> fromBool (x /= y)
        "&&" -> fromBool (x /= 0 && y /= 0)
        "||" -> fromBool (x /= 0 || y /= 0)
        _    -> 0
    fromBool b = if b then 1 else 0

pluralExpr :: PoParser PExpr
pluralExpr = do
  c <- binaryExpr
  (do _ <- sym "?"
      a <- pluralExpr
      _ <- sym ":"
      b <- pluralExpr
      return (PCond c a b))
    <|> return c
  where
    sym = L.symbol space
    binaryExpr = makeExprParser term table
    table =
      [ [Prefix (PNot <$ L.lexeme space (try (char '!' <* notFollowedBy (char '='))))]
      , [binary "%"]
      , [binary "<=", binary ">=", binary "<", binary ">"]
      , [binary "==", binary "!="]
      , [binary "&&"]
      , [binary "||"]
      ]
    binary op = InfixL (PBin op <$ sym op)
    term = choice
      [ PN <$ L.lexeme space (try (char 'n' <* notFollowedBy alphaNumChar))
      , PLit <$> L.lexeme space L.decimal
      , between (sym "(") (sym ")") pluralExpr
      ]

-- * Language tags

-- | Is this a well-formed language tag, safe to use in a cookie ? Two or three letters, then optional subtags of one to eight
-- letters or digits, separated by hyphens.
isValidLangTag :: Text -> Bool
isValidLangTag t = case T.splitOn "-" t of
  (l : subs) -> T.length l `elem` [2, 3] && T.all isAsciiAlpha l && all okSub subs && T.length t <= 35
  _ -> False
  where
    okSub s = not (T.null s) && T.length s <= 8 && T.all (\c -> isAscii c && isAlphaNum c) s
    isAsciiAlpha c = isAscii c && isAlpha c

-- | Convert a language tag as found in the environment or an HTTP header
-- to canonical form, or Nothing if it does not name a language.
--
-- Handles POSIX locale names (de_DE.UTF-8\@euro becomes de-DE; C, POSIX
-- and an empty value become Nothing), Accept-Language quality suffixes,
-- and letter case (pt-br becomes pt-BR). Chinese region tags map to the
-- script tags zh-Hans and zh-Hant, and Norwegian's no to nb.
normalizeLangTag :: Text -> Maybe Text
normalizeLangTag raw
  | T.null base || isC = Nothing
  | otherwise = do
      let parts = filter (not . T.null) $ T.splitOn "-" $ T.replace "_" "-" base
      tag <- case parts of
        (l : rest) | T.length l `elem` [2, 3] && T.all isAlpha l ->
          Just $ T.intercalate "-" (T.toLower l : modifierSubtag ++ map canonSub rest)
        _ -> Nothing
      let tag' = alias tag
      if isValidLangTag tag' then Just tag' else Nothing
  where
    value = T.strip $ T.takeWhile (/= ';') raw
    (base, suffix) = T.break (\c -> c == '.' || c == '@') value
    modifier = T.drop 1 $ T.dropWhile (/= '@') suffix
    modifierSubtag = case T.toLower modifier of
      "latin"    -> ["Latn"]
      "cyrillic" -> ["Cyrl"]
      _          -> []
    isC = T.toLower base `elem` ["c", "posix"]
    canonSub s
      | T.length s == 4 && T.all isAlpha s = T.toTitle s  -- script
      | T.length s == 2 && T.all isAlpha s = T.toUpper s  -- region
      | otherwise = s
    alias t = case T.toLower t of
      "zh"      -> "zh-Hans"
      "zh-cn"   -> "zh-Hans"
      "zh-sg"   -> "zh-Hans"
      "zh-hans" -> "zh-Hans"
      "zh-tw"   -> "zh-Hant"
      "zh-hk"   -> "zh-Hant"
      "zh-mo"   -> "zh-Hant"
      "zh-hant" -> "zh-Hant"
      "no"      -> "nb"
      "no-no"   -> "nb"
      _         -> t

-- | The tags to try for a language tag, most specific first:
-- the tag itself, then with subtags dropped from the right.
langTagCandidates :: Text -> [Text]
langTagCandidates t = map (T.intercalate "-") $ reverse $ drop 1 $ inits $ T.splitOn "-" t

-- | Given the available language tags and a list of preferred tags in
-- order of preference (raw, as from the environment or a browser),
-- choose the first available one. Each preference is tried with its
-- subtags dropped from the right before moving on to the next, so that
-- de-CH followed by en chooses de over en when only de is available.
resolveLang :: [Text] -> [Text] -> Maybe Text
resolveLang available prefs = listToMaybe
  [ a
  | p <- mapMaybe normalizeLangTag prefs
  , c <- langTagCandidates p
  , a <- available
  , T.toLower a == T.toLower c
  ]

-- | The languages a user prefers, in order, according to these
-- environment variables, following gettext: the effective locale is
-- LC_ALL, else LC_MESSAGES, else LANG; if that is unset or C/POSIX the
-- result is empty (English) and LANGUAGE is ignored; otherwise the
-- colon-separated LANGUAGE list is consulted first, then the locale.
langPrefsFromEnv :: [(String, String)] -> [Text]
langPrefsFromEnv env = case effective of
  Nothing -> []
  Just loc
    | isNothing (normalizeLangTag loc) -> []
    | otherwise -> mapMaybe normalizeLangTag (languageList ++ [loc])
  where
    get k = case lookup k env of
      Just v | not (null v) -> Just (T.pack v)
      _ -> Nothing
    effective = get "LC_ALL" <|> get "LC_MESSAGES" <|> get "LANG"
    languageList = maybe [] (T.splitOn ":") (get "LANGUAGE")

-- * Tests

-- i18n-extract: off

tests_I18n :: TestTree
tests_I18n = testGroup "I18n" [
   testCase "substitutePlaceholders" $ do
     substitutePlaceholders [("a", "1")] "x {a} y" @?= "x 1 y"
     substitutePlaceholders [("a", "{b}"), ("b", "2")] "{a}{b}" @?= "{b}2"
     substitutePlaceholders [] "{unknown} { }" @?= "{unknown} { }"
     substitutePlaceholders [("a", "1")] "{a}{a}" @?= "11"

  ,testCase "placeholders" $ do
     placeholders "a {x} {y_1} {bad name} { {z}" @?= S.fromList ["x", "y_1", "z"]
     placeholders "" @?= S.empty

  ,testCase "parsePo" $ do
     t <- either assertFailure return $ parsePo "sample" "de" samplePo
     trLang t @?= "de"
     tr t "Balance Sheet" @?= "Bilanz"
     tr t "Untranslated" @?= "Untranslated"
     tr t "Empty" @?= "Empty"
     tr t "Fuzzy" @?= "Fuzzy"
     tr t "Obsolete" @?= "Obsolete"
     trc t "column heading" "Total" @?= "Summe"
     tr t "Total" @?= "Total"
     tr t "Multi" @?= "line one\nline two \"quoted\" \\ \252 A"
     trn t 1 "{n} day" "{n} days" @?= "1 Tag"
     trn t 2 "{n} day" "{n} days" @?= "2 Tage"
     trn t 0 "{n} day" "{n} days" @?= "0 Tage"
     tr t "{n} day" @?= "{n} Tag"
     trf t "Balance changes in {period}:" [("period", "2024")] @?= "Saldo\228nderungen in 2024:"
     maybe (-1) pfCount (trPluralForms t) @?= 2

  ,testCase "parsePo errors" $ do
     let bad = assertBool "expected a parse failure" . isLeft . parsePo "t" "de"
     bad "msgid \"a\"\nmsgstr \"b\"\nmsgid \"a\"\nmsgstr \"c\"\n"
     bad "garbage\n"
     bad "msgid \"a\"\nmsgstr \"b\n"
     bad "msgid \"\"\nmsgstr \"Content-Type: text/plain; charset=ISO-8859-1\\n\"\n"
     bad "msgid \"\"\nmsgstr \"Plural-Forms: nplurals=2; plural=(n +);\\n\"\n"

  ,testCase "parsePo tolerates" $ do
     let ok = assertBool "expected a successful parse" . not . isLeft . parsePo "t" "de"
     ok ""
     ok "# just a comment\n"
     ok "\xFEFFmsgid \"a\"\r\nmsgstr \"b\"\r\n"
     ok "#~ msgid \"old\"\n#~ msgstr \"alt\"\n"
     ok "msgid \"\"\nmsgstr \"Content-Type: text/plain; charset=CHARSET\\n\"\n"

  ,testCase "plural rules" $ do
     let rule s = maybe (const (-1)) pfRule (parsePluralForms s)
         en = rule "nplurals=2; plural=(n != 1);"
         fr = rule "nplurals=2; plural=(n > 1);"
         ru = rule "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);"
         zh = rule "nplurals=1; plural=0;"
         ar = rule "nplurals=6; plural=(n==0 ? 0 : n==1 ? 1 : n==2 ? 2 : n%100>=3 && n%100<=10 ? 3 : n%100>=11 ? 4 : 5);"
         pl = rule "nplurals=3; plural=(n==1 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);"
     map en [0, 1, 2] @?= [1, 0, 1]
     map fr [0, 1, 2] @?= [0, 0, 1]
     map ru [1, 2, 5, 11, 21, 22, 25] @?= [0, 1, 2, 2, 0, 1, 2]
     map zh [0, 1, 5] @?= [0, 0, 0]
     map ar [0, 1, 2, 3, 11, 100] @?= [0, 1, 2, 3, 4, 5]
     map pl [1, 2, 5, 12, 22] @?= [0, 1, 2, 2, 1]
     maybe 0 pfCount (parsePluralForms "nplurals=6; plural=0;") @?= 6

  ,testCase "normalizeLangTag" $ do
     normalizeLangTag "de_DE.UTF-8@euro" @?= Just "de-DE"
     normalizeLangTag "de" @?= Just "de"
     normalizeLangTag "C" @?= Nothing
     normalizeLangTag "POSIX" @?= Nothing
     normalizeLangTag "C.UTF-8" @?= Nothing
     normalizeLangTag "" @?= Nothing
     normalizeLangTag "zh_CN" @?= Just "zh-Hans"
     normalizeLangTag "zh-TW" @?= Just "zh-Hant"
     normalizeLangTag "zh-hant-tw" @?= Just "zh-Hant-TW"
     normalizeLangTag "sr_RS@latin" @?= Just "sr-Latn-RS"
     normalizeLangTag "pt-br" @?= Just "pt-BR"
     normalizeLangTag "no_NO" @?= Just "nb"
     normalizeLangTag "en-US;q=0.8" @?= Just "en-US"
     normalizeLangTag "ast" @?= Just "ast"
     normalizeLangTag "../x" @?= Nothing
     normalizeLangTag "de/../x" @?= Nothing

  ,testCase "isValidLangTag" $ do
     isValidLangTag "de" @?= True
     isValidLangTag "zh-Hant-TW" @?= True
     isValidLangTag "d" @?= False
     isValidLangTag "de-" @?= False
     isValidLangTag "../de" @?= False
     isValidLangTag "de.po" @?= False

  ,testCase "langTagCandidates" $
     langTagCandidates "zh-Hant-TW" @?= ["zh-Hant-TW", "zh-Hant", "zh"]

  ,testCase "resolveLang" $ do
     resolveLang ["en", "de"] ["de-CH", "en", "de"] @?= Just "de"
     resolveLang ["en", "de"] ["fr", "en-GB"] @?= Just "en"
     resolveLang ["en", "de"] ["fr"] @?= Nothing
     resolveLang ["en", "de"] ["../etc"] @?= Nothing
     resolveLang ["en", "de"] ["DE"] @?= Just "de"
     resolveLang ["en", "zh-Hans"] ["zh_CN"] @?= Just "zh-Hans"

  ,testCase "langPrefsFromEnv" $ do
     langPrefsFromEnv [("LANG", "de_DE.UTF-8")] @?= ["de-DE"]
     langPrefsFromEnv [("LC_ALL", "C"), ("LANGUAGE", "de"), ("LANG", "de_DE.UTF-8")] @?= []
     langPrefsFromEnv [("LANGUAGE", "fr:de"), ("LANG", "en_US.UTF-8")] @?= ["fr", "de", "en-US"]
     langPrefsFromEnv [("LC_MESSAGES", "de_AT"), ("LANG", "C")] @?= ["de-AT"]
     langPrefsFromEnv [("LC_ALL", ""), ("LANG", "de")] @?= ["de"]
     langPrefsFromEnv [] @?= []

  ,testCase "built-in catalogs" $
     mapM_ checkBuiltin builtinCatalogSources
  ]
  where
    checkBuiltin (lang, bs) = do
      s <- either (\e -> assertFailure $ T.unpack lang ++ ": not UTF-8: " ++ show e) return $ TE.decodeUtf8' bs
      t <- either assertFailure return $ parsePo (T.unpack lang) lang s
      let msgid k = T.takeWhileEnd (/= '\x04') k
      mapM_ (\(k, v) -> assertEqual ("placeholders differ in " ++ T.unpack lang ++ " translation of " ++ show (msgid k))
                          (placeholders (msgid k)) (placeholders v))
            (M.toList (trMessages t))
      mapM_ (\(k, vs) -> mapM_ (\v -> assertBool ("unknown placeholder in " ++ T.unpack lang ++ " plural of " ++ show (msgid k))
                                       (placeholders v `S.isSubsetOf` S.insert "n" (placeholders (msgid k)))) vs)
            (M.toList (trPlurals t))

samplePo :: Text
samplePo = T.unlines
  [ "# German translations for the tests."
  , "#, fuzzy"
  , "msgid \"\""
  , "msgstr \"\""
  , "\"Project-Id-Version: hledger\\n\""
  , "\"Language: de\\n\""
  , "\"Content-Type: text/plain; charset=UTF-8\\n\""
  , "\"Plural-Forms: nplurals=2; plural=(n != 1);\\n\""
  , ""
  , "#. Report title."
  , "#: hledger/Hledger/Cli/Commands/Balancesheet.hs:23"
  , "#, python-brace-format"
  , "msgid \"Balance Sheet\""
  , "msgstr \"Bilanz\""
  , ""
  , "msgid \"Untranslated\""
  , "msgstr \"\""
  , ""
  , "msgid \"Empty\""
  , "msgstr \"\""
  , ""
  , "#, fuzzy, python-brace-format"
  , "#| msgid \"Fuzy\""
  , "msgid \"Fuzzy\""
  , "msgstr \"Unscharf\""
  , ""
  , "msgctxt \"column heading\""
  , "msgid \"Total\""
  , "msgstr \"Summe\""
  , ""
  , "msgid \"Multi\""
  , "msgstr \"\""
  , "  \"line one\\n\""
  , "  \"line two \\\"quoted\\\" \\\\ \\374 \\x41\""
  , ""
  , "msgid \"{n} day\""
  , "msgid_plural \"{n} days\""
  , "msgstr[0] \"{n} Tag\""
  , "msgstr[1] \"{n} Tage\""
  , ""
  , "msgid \"Balance changes in {period}:\""
  , "msgstr \"Saldo\228nderungen in {period}:\""
  , ""
  , "#~ msgid \"Obsolete\""
  , "#~ msgstr \"Veraltet\""
  ]
