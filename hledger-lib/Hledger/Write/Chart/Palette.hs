{- |
The exact colours of chart series, shared by the chart renderers (SVG, and text in terminals with 24-bit colour),
so that charts look the same everywhere.

The categorical palette and chart colours are the dataviz skill's validated reference palette (8 slots, light and dark variants);
the account type colours were chosen from it and validated on the pairs that appear together (assets-liabilities-equity, revenues-expenses).
-}

{-# LANGUAGE OverloadedStrings #-}

module Hledger.Write.Chart.Palette (
  colourHex,
  tint,
  tests_Hledger_Write_Chart_Palette,
) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Numeric (readHex)
import Safe (atMay)
import Text.Printf (printf)

import Hledger.Data.Types (AccountType(..))
import Hledger.Utils.Test
import Hledger.Write.Chart (Colour(..), mainAccountType, maxTints)


-- | A chart colour as #rrggbb, in its light variant (for light backgrounds) or its dark variant (for dark backgrounds).
colourHex :: Bool -> Colour -> Text
colourHex dark c = case c of
  TypeColour at k -> tint (tintFraction k) $ pick $ typeColour $ mainAccountType at
  IndexColour k   -> pick $ fromMaybe ("#2a78d6", "#3987e5") $ categorical `atMay` (k `mod` length categorical)
  OtherColour     -> "#898781"
  LoneColour      -> pick ("#1597b0", "#22a6be")  -- cyan
  NeutralColour   -> pick ("#52514e", "#c3c2b7")
  TotalColour     -> pick ("#0b0b0b", "#ffffff")
  where
    pick (light, darkc) = if dark then darkc else light

-- | Conventional colours for the main account types (light, dark).
typeColour :: AccountType -> (Text, Text)
typeColour at = case at of
  Asset     -> ("#2a78d6", "#3987e5")  -- blue
  Liability -> ("#eda100", "#c98500")  -- amber
  Equity    -> ("#4a3aa7", "#9085e9")  -- violet
  Revenue   -> ("#008300", "#008300")  -- green
  Expense   -> ("#e34948", "#e66767")  -- red
  _         -> ("#4a3aa7", "#9085e9")

-- | The categorical palette (light, dark), in its validated order.
categorical :: [(Text, Text)]
categorical =
  [ ("#2a78d6", "#3987e5"), ("#eb6834", "#d95926"), ("#1baf7a", "#199e70"), ("#eda100", "#c98500")
  , ("#e87ba4", "#d55181"), ("#008300", "#008300"), ("#4a3aa7", "#9085e9"), ("#e34948", "#e66767") ]

-- | How the Nth tint of a type's colour differs from it ('maxTints' of them, repeating):
-- the colour itself, then lighter, darker, and lighter still (the fraction to mix with white (positive) or black (negative)).
tintFraction :: Int -> Double
tintFraction k = fromMaybe 0 $ take maxTints [0, 0.4, -0.3, 0.65] `atMay` (k `mod` maxTints)

-- | Mix a #rrggbb colour with white (by a positive fraction) or black (by a negative fraction).
tint :: Double -> Text -> Text
tint f hex = case mapM channel [T.take 2 $ T.drop i digits | i <- [0, 2, 4]] of
    Just cs | T.length digits == 6 -> "#" <> T.concat (map (T.pack . printf "%02x" . mix) cs)
    _ -> hex
  where
    digits = T.drop 1 hex
    channel t = case readHex (T.unpack t) of [(n, "")] -> Just (n :: Int); _ -> Nothing
    mix :: Int -> Int
    mix ch = round $ if f >= 0 then fromIntegral ch + (255 - fromIntegral ch) * f else fromIntegral ch * (1 + f)

tests_Hledger_Write_Chart_Palette :: TestTree
tests_Hledger_Write_Chart_Palette = testGroup "Write.Chart.Palette" [
   testCase "colourHex" $ do
     colourHex False (TypeColour Revenue 0) @?= "#008300"
     colourHex True (TypeColour Expense 0) @?= "#e66767"
     colourHex False (TypeColour Cash 0) @?= "#2a78d6"  -- a subtype gets its main type's colour
     colourHex False (TypeColour Expense maxTints) @?= colourHex False (TypeColour Expense 0)  -- tints repeat
  ,testCase "tint" $ do
     tint 0.5 "#000000" @?= "#808080"
     tint (-0.5) "#ffffff" @?= "#808080"
     tint 0.5 "not a colour" @?= "not a colour"
  ]
