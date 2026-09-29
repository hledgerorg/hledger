{-|

The quick reference card: a compact overview of hledger's most useful
commands, flags, and concepts, shown by @hledger help quickref@.

-}

{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Quickref (
  showQuickref
) where

import Data.List (dropWhileEnd)
import System.Console.ANSI (setSGRCode, SGR(..), Underlining(..))

import Hledger
import Hledger.Cli.CliOptions (prognameandversionnoarch)

-- | The quick reference card, from quickref.txt in the hledger package directory.
quickrefcontent :: String
quickrefcontent = $(embedFileRelative "quickref.txt")

-- | Print the quick reference card, styling it a little when color is enabled.
showQuickref :: IO ()
showQuickref = do
  usecolor <- useColorOnStdout
  runPager $ styleQuickref usecolor quickrefcontent

-- | Render the card. The program name and version are added right-aligned on
-- the title line. When color is enabled: the title line gets hledger's usual
-- bold colour gradient (and the version a faint gradient), section headings (lines with
-- nothing beyond the label margin) are faint and underlined, other labels in
-- the margin (the first 16 columns) are faint, and the commands, flags etc.
-- beyond them are left normal, except parentheses, which are faint.
styleQuickref :: Bool -> String -> String
styleQuickref usecolor s = unlines $ case lines s of
  []         -> []
  title:rest -> titleline title : map styleline rest
  where
    version = prognameandversionnoarch
    -- align the version's right edge with the widest line of the card
    cardwidth = maximum $ map length $ lines s
    titleline t = titleAndVersionLine cardwidth t version
    labelwidth = 16
    -- Top-level labels that share their line with content but should still
    -- render as underlined headings (underlining only the text, not the padding).
    underlinedlabels = ["Input formats", "Default checks"]
    styleheading = faint'
    styleline l
      | not usecolor      = l
      | all (==' ') label = label <> dimparens content
      | null content      = underline' $ styleheading l
      | otherwise         = styledlabel <> dimparens content
      where
        (label, content) = splitAt labelwidth l
        labeltext = dropWhileEnd (==' ') label
        labelpad  = drop (length labeltext) label
        styledlabel
          | labeltext `elem` underlinedlabels = underline' (styleheading labeltext) <> styleheading labelpad
          | otherwise                         = styleheading label
    dimparens = concatMap (\c -> if c `elem` "()" then styleheading [c] else [c])

-- | Wrap a string in ANSI codes to switch single underlining on and off.
underline' :: String -> String
underline' s = setSGRCode [SetUnderlining SingleUnderline] <> s <> setSGRCode [SetUnderlining NoUnderline]
