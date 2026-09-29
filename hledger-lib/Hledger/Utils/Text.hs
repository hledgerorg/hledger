-- | Text formatting helpers, ported from String as needed.
-- There may be better alternatives out there.

{-# LANGUAGE OverloadedStrings #-}

module Hledger.Utils.Text
  (
  -- * misc
  textCapitalise,
  -- underline,
  -- stripbrackets,
  textUnbracket,
  wrap,
  textChomp,
  -- quoting
  quoteIfSpaced,
  textQuoteIfNeeded,
  -- singleQuoteIfNeeded,
  -- quotechars,
  -- whitespacechars,
  escapeDoubleQuotes,
  escapeBackslash,
  -- escapeSingleQuotes,
  -- escapeQuotes,
  -- words',
  textStripQuotes,
  -- textIsSingleQuoted,
  -- textIsDoubleQuoted,
  -- * single-line layout
  -- elideLeft,
  textElideRight,
  formatText,
  -- * multi-line layout
  textConcatTopPadded,
  textConcatBottomPadded,
  fitText,
  linesPrepend,
  linesPrepend2,
  unlinesB,
  -- * wide-character-aware layout
  WideBuilder(..),
  wbToText,
  wbFromText,
  wbUnpack,
  textTakeWidth,
  -- * Reading
  readDecimal,
  -- * tests
  tests_Text
  )
where

import Data.Char (digitToInt)
import Data.Default (def)
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Builder qualified as TB
import Text.DocLayout (charWidth, realLength)

import Test.Tasty (testGroup)
import Test.Tasty.HUnit ((@?=), testCase)
import Text.Tabular.AsciiWide
  (Align(..), Header(..), Properties(..), TableOpts(..), renderRow, textCell)
import Text.WideString (WideBuilder(..), wbToText, wbFromText, wbUnpack)


textCapitalise :: Text -> Text
textCapitalise t = T.toTitle c <> cs where (c,cs) = T.splitAt 1 t

-- stripbrackets :: String -> String
-- stripbrackets = dropWhile (`elem` "([") . reverse . dropWhile (`elem` "])") . reverse :: String -> String

-- elideLeft :: Int -> String -> String
-- elideLeft width s =
--     if length s > width then ".." ++ reverse (take (width - 2) $ reverse s) else s

textElideRight :: Int -> Text -> Text
textElideRight width t =
    if T.length t > width then T.take (width - 2) t <> ".." else t

-- | Wrap a Text with the surrounding Text.
wrap :: Text -> Text -> Text -> Text
wrap start end x = start <> x <> end

-- | Remove trailing newlines/carriage returns.
textChomp :: Text -> Text
textChomp = T.dropWhileEnd (`elem` ['\r', '\n'])

-- | Clip and pad a string to a minimum & maximum width, and/or left/right justify it.
-- Works on multi-line strings too (but will rewrite non-unix line endings).
formatText :: Bool -> Maybe Int -> Maybe Int -> Text -> Text
formatText leftJustified minwidth maxwidth t =
    T.intercalate "\n" . map (pad . clip) $ if T.null t then [""] else T.lines t
  where
    pad  = maybe id justify minwidth
    clip = maybe id T.take maxwidth
    justify n = if leftJustified then T.justifyLeft n ' ' else T.justifyRight n ' '

-- underline :: String -> String
-- underline s = s' ++ replicate (length s) '-' ++ "\n"
--     where s'
--             | last s == '\n' = s
--             | otherwise = s ++ "\n"

-- | Wrap a string in double quotes, and \-prefix any embedded single
-- quotes, if it contains whitespace and is not already single- or
-- double-quoted.
quoteIfSpaced :: T.Text -> T.Text
quoteIfSpaced s | textIsSingleQuoted s || textIsDoubleQuoted s = s
                | not $ any (\c -> T.any (==c) s) whitespacechars = s
                | otherwise = textQuoteIfNeeded s

-- -- | Wrap a string in double quotes, and \-prefix any embedded single
-- -- quotes, if it contains whitespace and is not already single- or
-- -- double-quoted.
-- quoteIfSpaced :: String -> String
-- quoteIfSpaced s | textIsSingleQuoted s || textIsDoubleQuoted s = s
--                 | not $ any (`elem` s) whitespacechars = s
--                 | otherwise = "'"++escapeSingleQuotes s++"'"

-- -- | Double-quote this string if it contains whitespace, single quotes
-- -- or double-quotes, escaping the quotes as needed.
textQuoteIfNeeded :: T.Text -> T.Text
textQuoteIfNeeded s | any (\c -> T.any (==c) s) (quotechars++whitespacechars) = "\"" <> escapeDoubleQuotes s <> "\""
                    | otherwise = s

-- -- | Single-quote this string if it contains whitespace or double-quotes.
-- -- No good for strings containing single quotes.
-- singleQuoteIfNeeded :: String -> String
-- singleQuoteIfNeeded s | any (`elem` s) whitespacechars = "'"++s++"'"
--                       | otherwise = s

quotechars, whitespacechars :: [Char]
quotechars      = "'\""
whitespacechars = " \t\n\r"

escapeDoubleQuotes :: T.Text -> T.Text
escapeDoubleQuotes = T.replace "\"" "\\\""

escapeBackslash :: T.Text -> T.Text
escapeBackslash = T.replace "\\" "\\\\"

-- escapeSingleQuotes :: T.Text -> T.Text
-- escapeSingleQuotes = T.replace "'" "\'"

-- escapeQuotes :: String -> String
-- escapeQuotes = regexReplace "([\"'])" "\\1"

-- -- | Quote-aware version of words - don't split on spaces which are inside quotes.
-- -- NB correctly handles "a'b" but not "''a''". Can raise an error if parsing fails.
-- words' :: String -> [String]
-- words' "" = []
-- words' s  = map textStripQuotes $ fromparse $ parsewith p s
--     where
--       p = do ss <- (singleQuotedPattern <|> doubleQuotedPattern <|> pattern) `sepBy` many1 spacenonewline
--              -- eof
--              return ss
--       pattern = many (noneOf whitespacechars)
--       singleQuotedPattern = between (char '\'') (char '\'') (many $ noneOf "'")
--       doubleQuotedPattern = between (char '"') (char '"') (many $ noneOf "\"")

-- | Strip one matching pair of single or double quotes on the ends of a string.
textStripQuotes :: Text -> Text
textStripQuotes s = if textIsSingleQuoted s || textIsDoubleQuoted s then T.init $ T.tail s else s

textIsSingleQuoted :: Text -> Bool
textIsSingleQuoted s =
  T.length s >= 2 && T.head s == '\'' && T.last s == '\''

textIsDoubleQuoted :: Text -> Bool
textIsDoubleQuoted s =
  T.length s >= 2 && T.head s == '"' && T.last s == '"'

-- | Remove all matching pairs of square brackets and parentheses from the text.
textUnbracket :: Text -> Text
textUnbracket s = T.drop stripN $ T.dropEnd stripN s
  where
    matchBracket :: Char -> Maybe Char
    matchBracket '(' = Just ')'
    matchBracket '[' = Just ']'
    matchBracket _ = Nothing

    expectedClosingBrackets = catMaybes $ takeWhile (/= Nothing) $ matchBracket <$> T.unpack s
    stripN = length $ takeWhile (uncurry (==)) $ zip expectedClosingBrackets $ reverse $ T.unpack s

-- | Join several multi-line strings as side-by-side rectangular strings of the same height, top-padded.
-- Treats wide characters as double width.
textConcatTopPadded :: [Text] -> Text
textConcatTopPadded = TL.toStrict . renderRow def{tableBorders=False, borderSpaces=False}
                    . Group NoLine . map (Header . textCell BottomLeft)

-- | Join several multi-line strings as side-by-side rectangular strings of the same height, bottom-padded.
-- Treats wide characters as double width.
textConcatBottomPadded :: [Text] -> Text
textConcatBottomPadded = TL.toStrict . renderRow def{tableBorders=False, borderSpaces=False}
                       . Group NoLine . map (Header . textCell TopLeft)

-- -- Functions below treat wide (eg CJK) characters as double-width.

-- | General-purpose wide-char-aware single-line text layout function.
-- It can left- or right-pad a short string to a minimum width.
-- It can left- or right-clip a long string to a maximum width, optionally inserting an ellipsis (the third argument).
-- It clips and pads on the right when the fourth argument is true, otherwise on the left.
-- It treats wide characters as double width.
fitText :: Maybe Int -> Maybe Int -> Bool -> Bool -> Text -> Text
fitText mminwidth mmaxwidth ellipsify rightside = clip . pad
  where
    clip :: Text -> Text
    clip s =
      case mmaxwidth of
        Just w
          | realLength s > max 0 w ->
            if rightside
              then textTakeWidth (w - T.length ellipsis) s <> ellipsis
              else ellipsis <> T.reverse (textTakeWidth (w - T.length ellipsis) $ T.reverse s)
          | otherwise -> s
          where
            ellipsis = if ellipsify then ".." else ""
        Nothing -> s
    pad :: Text -> Text
    pad s =
      case mminwidth of
        Just w
          | sw < w ->
            if rightside
              then s <> T.replicate (w - sw) " "
              else T.replicate (w - sw) " " <> s
          | otherwise -> s
        Nothing -> s
      where sw = realLength s

-- | Double-width-character-aware string truncation. Take as many
-- characters as possible from a string without exceeding the
-- specified width. Eg textTakeWidth 3 "りんご" = "り".
textTakeWidth :: Int -> Text -> Text
textTakeWidth _ ""     = ""
textTakeWidth 0 _      = ""
textTakeWidth w t | not (T.null t),
                let c = T.head t,
                let cw = charWidth c,
                cw <= w
                = T.cons c $ textTakeWidth (w-cw) (T.tail t)
              | otherwise = ""

-- | Add a prefix to each line of a string.
linesPrepend :: Text -> Text -> Text
linesPrepend prefix = T.unlines . map (prefix<>) . T.lines

-- | Add a prefix to the first line of a string, 
-- and a different prefix to the remaining lines.
linesPrepend2 :: Text -> Text -> Text -> Text
linesPrepend2 prefix1 prefix2 s = T.unlines $ case T.lines s of
    []   -> []
    l:ls -> (prefix1<>l) : map (prefix2<>) ls

-- | Join a list of Text Builders with a newline after each item.
unlinesB :: [TB.Builder] -> TB.Builder
unlinesB = foldMap (<> TB.singleton '\n')

-- | Read a decimal number from a Text. Assumes the input consists only of digit
-- characters.
readDecimal :: Text -> Integer
readDecimal = T.foldl' step 0
  where step a c = a * 10 + toInteger (digitToInt c)


tests_Text = testGroup "Text" [
   testCase "quoteIfSpaced" $ do
     quoteIfSpaced "a'a" @?= "a'a"
     quoteIfSpaced "a\"a" @?= "a\"a"
     quoteIfSpaced "a a" @?= "\"a a\""
     quoteIfSpaced "mimi's cafe" @?= "\"mimi's cafe\""
     quoteIfSpaced "\"alex\" cafe" @?= "\"\\\"alex\\\" cafe\""
     quoteIfSpaced "le'shan's cafe" @?= "\"le'shan's cafe\""
     quoteIfSpaced "\"be'any's\" cafe" @?= "\"\\\"be'any's\\\" cafe\"",
   testCase "textUnbracket" $ do
     textUnbracket "()" @?= ""
     textUnbracket "(a)" @?= "a"
     textUnbracket "(ab)" @?= "ab"
     textUnbracket "[ab]" @?= "ab"
     textUnbracket "([ab])" @?= "ab"
     textUnbracket "(()b)" @?= "()b"
     textUnbracket "[[]b]" @?= "[]b"
     textUnbracket "[()b]" @?= "()b"
     textUnbracket "[([]())]" @?= "[]()"
     textUnbracket "[([[[()]]])]" @?= ""
     textUnbracket "[([[[(]]])]" @?= "("
     textUnbracket "[([[[)]]])]" @?= ")",
   testCase "fitText" $ do
     fitText Nothing (Just (-2)) True True "" @?= ""
     fitText Nothing (Just 0) True True "" @?= ""
     fitText Nothing (Just 6) True True "Test Text" @?= "Test.."
  ]
