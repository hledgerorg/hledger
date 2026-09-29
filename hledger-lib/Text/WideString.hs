-- | Calculate the width of String and Text, being aware of wide characters.

module Text.WideString (
  -- * Text Builders which keep track of length
  WideBuilder(..),
  wbUnpack,
  wbToText,
  wbFromText
  ) where

import Data.Text (Text)
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Builder qualified as TB
import Text.DocLayout (realLength)


-- | Helper for constructing Builders while keeping track of text width.
data WideBuilder = WideBuilder
  { wbBuilder :: !TB.Builder
  , wbWidth   :: !Int
  } deriving (Show)

instance Semigroup WideBuilder where
  WideBuilder x i <> WideBuilder y j = WideBuilder (x <> y) (i + j)

instance Monoid WideBuilder where
  mempty = WideBuilder mempty 0

-- | Convert a WideBuilder to a strict Text.
wbToText :: WideBuilder -> Text
wbToText = TL.toStrict . TB.toLazyText . wbBuilder

-- | Convert a strict Text to a WideBuilder.
wbFromText :: Text -> WideBuilder
wbFromText t = WideBuilder (TB.fromText t) (realLength t)

-- | Convert a WideBuilder to a String.
wbUnpack :: WideBuilder -> String
wbUnpack = TL.unpack . TB.toLazyText . wbBuilder
