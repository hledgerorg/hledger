-- | String formatting helpers, starting to get a bit out of control.

module Hledger.Utils.String (
 takeEnd,
 -- * misc
 capitalise,
 lowercase,
 uppercase,
 underline,
 stripbrackets,
 -- quoting
 quoteIfNeeded,
 singleQuoteIfNeeded,
 shellQuoteIfNeeded,
 quoteForCommandLine,
 -- quotechars,
 -- whitespacechars,
 words',
 wordsmay,
 wordsEither,
 stripQuotes,
 isSingleQuoted,
 isDoubleQuoted,
 stripAnsi,
 -- * single-line layout
 strip,
 lstrip,
 rstrip,
 strip1Char,
 stripBy,
 strip1By,
 chomp,
 chomp1,
 singleline,
 elideLeft,
 elideRight,
 formatString,
 -- * wide-character-aware layout
 charWidth,
 strWidth,
 strWidthAnsi,
 takeWidth,
 ) where


import Data.Char (isSpace, toLower, toUpper)
import Data.List (intercalate, dropWhileEnd)
import Data.Text qualified as T
import System.Info (os)
import Safe (headErr, tailErr)
import Text.Megaparsec (between, choice, errorBundlePretty, many, noneOf, sepBy, some)
import Text.Megaparsec.Char (char)
import Text.Printf (printf)

import Hledger.Utils.Parse
import Hledger.Utils.Regex (toRegex', regexReplace)
import Text.DocLayout (charWidth, realLength)


-- | Take elements from the end of a list.
takeEnd n l = go (drop n l) l
  where
    go (_:xs) (_:ys) = go xs ys
    go []     r      = r
    go _      []     = []

capitalise :: String -> String
capitalise (c:cs) = toUpper c : cs
capitalise s = s

lowercase, uppercase :: String -> String
lowercase = map toLower
uppercase = map toUpper

-- | Remove leading and trailing whitespace.
strip :: String -> String
strip = lstrip . rstrip

-- | Remove leading whitespace.
lstrip :: String -> String
lstrip = dropWhile isSpace

-- | Remove trailing whitespace.
rstrip :: String -> String
rstrip = reverse . lstrip . reverse

-- | Strip the given starting and ending character
-- from the start and end of a string if both are present.
strip1Char :: Char -> Char -> String -> String
strip1Char b e s = case s of
  (c:cs) | c==b, not $ null cs, last cs==e -> init cs
  _ -> s

-- | Strip a run of zero or more characters matching the predicate
-- from the start and end of a string.
stripBy :: (Char -> Bool) -> String -> String
stripBy f = dropWhileEnd f . dropWhile f

-- | Strip a single balanced enclosing pair of a character matching the predicate
-- from the start and end of a string.
strip1By :: (Char -> Bool) -> String -> String
strip1By f s = case s of
  (c:cs) | f c, not $ null cs, last cs==c -> init cs
  _ -> s

-- | Remove all trailing newlines/carriage returns.
chomp :: String -> String
chomp = reverse . dropWhile (`elem` "\r\n") . reverse

-- | Remove all trailing newline/carriage returns, leaving just one trailing newline.
chomp1 :: String -> String
chomp1 = (++"\n") . chomp

-- | Remove consecutive line breaks, replacing them with single space
singleline :: String -> String
singleline = unwords . filter (/="") . (map strip) . lines

stripbrackets :: String -> String
stripbrackets = dropWhile (`elem` "([") . reverse . dropWhile (`elem` "])") . reverse :: String -> String

elideLeft :: Int -> String -> String
elideLeft width s =
    if length s > width then ".." ++ takeEnd (width - 2) s else s

elideRight :: Int -> String -> String
elideRight width s =
    if length s > width then take (width - 2) s ++ ".." else s

-- | Clip and pad a string to a minimum & maximum width, and/or left/right justify it.
-- Works on multi-line strings too (but will rewrite non-unix line endings).
formatString :: Bool -> Maybe Int -> Maybe Int -> String -> String
formatString leftJustified minwidth maxwidth s = intercalate "\n" $ map (printf fmt) $ lines s
    where
      justify = if leftJustified then "-" else ""
      minwidth' = maybe "" show minwidth
      maxwidth' = maybe "" (("."++).show) maxwidth
      fmt = "%" ++ justify ++ minwidth' ++ maxwidth' ++ "s"

underline :: String -> String
underline s = s' ++ replicate (length s) '-' ++ "\n"
    where s'
            | last s == '\n' = s
            | otherwise = s ++ "\n"

-- | Double-quote this string if it contains whitespace, single quotes
-- or double-quotes, escaping the quotes as needed.
quoteIfNeeded :: String -> String
quoteIfNeeded s | any (`elem` s) (quotechars++whitespacechars++redirectchars) = showChar '"' $ escapeQuotes s "\""
                | otherwise = s
  where
    escapeQuotes []       x = x
    escapeQuotes ('"':cs) x = showString "\\\"" $ escapeQuotes cs x
    escapeQuotes (c:cs)   x = showChar c        $ escapeQuotes cs x

-- | Single-quote this string if it contains whitespace or double-quotes.
-- Does not work for strings containing single quotes.
singleQuoteIfNeeded :: String -> String
singleQuoteIfNeeded s | any (`elem` s) (quotechars++whitespacechars) = singleQuote s
                      | otherwise = s

-- | Prepend and append single quotes to a string.
singleQuote :: String -> String
singleQuote s = "'"++s++"'"

-- | Quote a string if needed for use as one argument in a shell command line
-- on the current platform. Uses double-quote escaping on Windows (cmd.exe does
-- not recognise single quotes as a quoting character); elsewhere uses single
-- quotes, which are literal in POSIX shells. Use this whenever interpolating
-- a path or other string into a command that will be passed to
-- 'System.Process.runCommand', 'System.Process.callCommand', or
-- 'System.Process.shell'.
shellQuoteIfNeeded :: String -> String
shellQuoteIfNeeded
  | os == "mingw32" = quoteIfNeeded
  | otherwise       = singleQuoteIfNeeded

-- | Try to single- and backslash-quote a string as needed to make it usable
-- as an argument on a (sh/bash) shell command line. At least, well enough 
-- to handle common currency symbols, like $. Probably broken in many ways.
--
-- >>> quoteForCommandLine "a"
-- "a"
-- >>> quoteForCommandLine "\""
-- "'\"'"
-- >>> quoteForCommandLine "$"
-- "'$'"
-- >>> quoteForCommandLine "it's"
-- "'it'\\''s'"
--
quoteForCommandLine :: String -> String
quoteForCommandLine s
  | null s = "''"  -- an empty argument must be quoted, or it vanishes from the command line
  | any (`elem` s) (quotechars++whitespacechars++shellchars) = singleQuote $ escapeSingleQuotes s
  | otherwise = s

-- | Escape single quotes appearing in a string we're protecting by wrapping in single quotes.
-- A backslash is not an escape inside single quotes in POSIX sh, so the quote has to be
-- closed, the apostrophe emitted separately, and the quote reopened: 'it'\\''s'.
escapeSingleQuotes :: String -> String
escapeSingleQuotes = concatMap escapeSingleQuote
  where
    escapeSingleQuote c | c `elem` "'" = "'\\''"
    escapeSingleQuote c = [c]

quotechars, whitespacechars, redirectchars, shellchars :: [Char]
quotechars      = "'\""
whitespacechars = " \t\n\r"
redirectchars   = "<>"
shellchars      = "<>(){}[]$&?#!~`*+\\"

-- | Quote-aware version of words, splitting a string into words like the
-- shell does: spaces inside single or double quotes don't split, quotes enclosing
-- a word are removed, and a word can mix unquoted and quoted parts
-- (so date:'1 to 15' is the single word date:1 to 15).
-- Can raise an error if parsing fails (eg if there's an unclosed quote);
-- wordsmay and wordsEither are total versions.
--
-- >>> words' "a b"
-- ["a","b"]
-- >>> words' "'a b' c"
-- ["a b","c"]
-- >>> words' "date:'1 to 15' x"
-- ["date:1 to 15","x"]
-- >>> words' "\"it's\""
-- ["it's"]
-- >>> words' "a '' b"
-- ["a","","b"]
-- >>> wordsmay "an unclosed 'quote"
-- Nothing
words' :: String -> [String]
words' "" = []
words' s  = fromparse $ parsewithString wordsp s  -- PARTIAL

-- | Like words', but return Nothing if parsing fails
-- (eg because of an unclosed quote), rather than raising an error.
wordsmay :: String -> Maybe [String]
wordsmay = either (const Nothing) Just . wordsEither

-- | Like words', but on failure (eg because of an unclosed quote) return
-- a pretty error message, showing the position and the problem, instead of
-- raising an error.
wordsEither :: String -> Either String [String]
wordsEither "" = Right []
wordsEither s  = either (Left . errorBundlePretty) Right $ parsewithString wordsp s

wordsp :: SimpleStringParser [String]
wordsp = wordp `sepBy` skipNonNewlineSpaces1
    -- eof
    where
      wordp = concat <$> many segmentp
      segmentp = choice
        [ between (char '\'') (char '\'') (many $ noneOf "'")
        , between (char '"') (char '"') (many $ noneOf "\"")
        , some $ noneOf $ quotechars <> whitespacechars
        ]

-- | Strip one matching pair of single or double quotes on the ends of a string.
stripQuotes :: String -> String
stripQuotes s = if isSingleQuoted s || isDoubleQuoted s then init $ tailErr s else s  -- PARTIAL tailErr won't fail because isDoubleQuoted

isSingleQuoted :: String -> Bool
isSingleQuoted s@(_:_:_) = headErr s == '\'' && last s == '\''  -- PARTIAL headErr, last will succeed because of pattern
isSingleQuoted _ = False

isDoubleQuoted :: String -> Bool
isDoubleQuoted s@(_:_:_) = headErr s == '"' && last s == '"'  -- PARTIAL headErr, last will succeed because of pattern
isDoubleQuoted _ = False

-- Functions below treat wide (eg CJK) characters as double-width.

-- | Double-width-character-aware string truncation. Take as many
-- characters as possible from a string without exceeding the
-- specified width. Eg takeWidth 3 "りんご" = "り".
takeWidth :: Int -> String -> String
takeWidth _ ""     = ""
takeWidth 0 _      = ""
takeWidth w (c:cs) | cw <= w   = c:takeWidth (w-cw) cs
                   | otherwise = ""
  where cw = charWidth c

-- | Like strWidth, but also strips ANSI escape sequences before
-- calculating the width.
--
-- This is no longer used in code, as widths are calculated before
-- adding ANSI escape sequences, but is being kept around for now.
strWidthAnsi :: String -> Int
strWidthAnsi = strWidth . stripAnsi

-- | Alias for 'realLength'.
strWidth :: String -> Int
strWidth = realLength

-- | Strip ANSI escape sequences from a string.
--
-- >>> stripAnsi "\ESC[31m-1\ESC[m"
-- "-1"
stripAnsi :: String -> String
stripAnsi s = either err id $ regexReplace ansire "" s
 where
   err    = errorWithoutStackTrace "stripAnsi: invalid replacement pattern"      -- PARTIAL, shouldn't happen
   ansire = toRegex' $ T.pack "\ESC\\[([0-9]+;)*([0-9]+)?[ABCDHJKfmsu]"  -- PARTIAL, should succeed
