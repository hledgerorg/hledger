{-|
The report pages' rows of links, and their multiple-choice URL
parameters, such as calc: each one's name, modes, URL words, and labels,
written once, from which its parser, its row of links, the parameters
that carry it, and its name in the options summary are made.
-}

{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

module Hledger.Web.Param
  ( linksRow
  , linksRowClass
  , linksRowGroups
  , Param(..)
  , parseParam
  , lookupParam
  , paramSetting
  , paramSettings
  , paramLinks
  , paramPhrase
  , calcParam
  ) where

import Control.Monad (unless)
import Data.Foldable (find, for_)
import Data.Text (Text)
import Data.Text qualified as T
import Text.Blaze ((!), (!?))
import Text.Blaze.Html5 qualified as H
import Text.Blaze.Html5.Attributes qualified as A
import Yesod (HtmlUrl, MonadHandler, lookupGetParam)

import Hledger
import Hledger.Utils.I18n (Translations, tr, trc)

-- | A row of links above a report: a label, then each link's label,
-- title, target, and whether it is the one being shown.
-- Each label and title is a whole phrase, not a word slotted into a
-- sentence: an adjective that fits one language's sentence does not fit
-- another's, so a translation cannot be assembled from parts.
linksRow :: Text -> [(Text, Text, (r, [(Text, Text)]), Bool)] -> HtmlUrl r
linksRow = linksRowClass ""

-- | 'linksRow' with an extra class on the row: a hook for hledger.js's
-- keyboard shortcuts.
linksRowClass :: Text -> Text -> [(Text, Text, (r, [(Text, Text)]), Bool)] -> HtmlUrl r
linksRowClass cls rowlabel items = linksRowGroups cls rowlabel [items]

-- | 'linksRowClass' with the links in groups, shown a little apart.
linksRowGroups :: Text -> Text -> [[(Text, Text, (r, [(Text, Text)]), Bool)]] -> HtmlUrl r
linksRowGroups cls rowlabel groups renderUrl =
    H.p ! A.class_ (H.toValue $ T.unwords $ "report-links" : [cls | not (T.null cls)]) $ do
      unless (T.null rowlabel) $ H.span ! A.class_ "row-label" $ H.toHtml rowlabel
      for_ (zip [0 :: Int ..] groups) $ \(g, items) ->
        for_ (zip [0 :: Int ..] items) $ \(i, (label, title, link, current)) ->
          let classes = ["current" | current] ++ ["group-start" | g > 0, i == 0]
          in H.a !? (not (null classes), A.class_ (H.toValue $ T.unwords classes))
                 ! A.href (H.toValue $ uncurry renderUrl link)
                 ! A.title (H.toValue title) $
               H.toHtml label

-- | A multiple-choice URL parameter, and its row of links.
-- Where the parameter offers every constructor of its type, write
-- 'paramWord' and 'paramLabel' as case expressions naming every
-- constructor, with no catch-all case: then a constructor added to the
-- type gives a missing-case warning until it has a word and a label.
data Param a = Param
  { paramName     :: Text
    -- ^ The URL parameter's name, eg "calc". Also the class of its row
    -- of links, which hledger.js's keyboard shortcuts look for.
  , paramModes    :: [a]
    -- ^ The modes the page offers, in the order of the row's links.
    -- Can be a subset of the type's constructors.
  , paramWord     :: a -> Text
    -- ^ The URL word naming a mode, eg "gain". Each mode's must differ.
  , paramRowLabel :: Translations -> Text
    -- ^ The label before the row of links, eg "Calculate:".
  , paramLabel    :: Translations -> a -> (Text, Text)
    -- ^ A mode's link text and tooltip. The link text is also how the
    -- closed options disclosure names the mode.
  }

-- | Read a parameter's value: one of its modes' words, or, when it is
-- empty or absent, Nothing, for the page's default. An unknown word is
-- returned on the Left.
parseParam :: Param a -> Maybe Text -> Either Text (Maybe a)
parseParam p = \case
  Nothing -> Right Nothing
  Just "" -> Right Nothing
  Just w  -> maybe (Left w) (Right . Just) $ find ((== w) . paramWord p) (paramModes p)

-- | A parameter's value in the request, if it names one of its modes.
-- For pages that ignore an unknown value rather than report it.
lookupParam :: MonadHandler m => Param a -> m (Maybe a)
lookupParam p = either (const Nothing) id . parseParam p <$> lookupGetParam (paramName p)

-- | The URL parameter selecting a mode.
paramSetting :: Param a -> a -> (Text, Text)
paramSetting p a = (paramName p, paramWord p a)

-- | The URL parameter selecting a mode, if needed: not for the page's
-- default mode, or a mode the parameter does not offer.
paramSettings :: Eq a => Param a -> a -> a -> [(Text, Text)]
paramSettings p dflt a = [paramSetting p a | a /= dflt, a `elem` paramModes p]

-- | A parameter's row of links, one per mode, each replacing the
-- parameter among the given ones; the page's default mode needs none.
-- The mode being shown is marked. The row's class is the parameter's
-- name, a hook for hledger.js's keyboard shortcuts.
paramLinks :: Eq a => Param a -> Translations -> r -> [(Text, Text)] -> a -> a -> HtmlUrl r
paramLinks p trs route kept dflt current =
  linksRowClass (paramName p) (paramRowLabel p trs)
    [ (label, title, (route, kept' ++ paramSettings p dflt a), a == current)
    | a <- paramModes p, let (label, title) = paramLabel p trs a ]
  where kept' = filter ((/= paramName p) . fst) kept

-- | The link text of the mode a URL word names, if it names one: how
-- the closed options disclosure lists it.
paramPhrase :: Param a -> Translations -> Text -> Maybe Text
paramPhrase p trs w = fst . paramLabel p trs <$> find ((== w) . paramWord p) (paramModes p)

-- | The calc parameter: what a report's cells calculate, as the balance
-- commands' --valuechange, --gain, and --count flags choose.
calcParam :: Param BalanceCalculation
calcParam = Param
  { paramName  = "calc"
  , paramModes = [CalcChange, CalcValueChange, CalcGain, CalcPostingsCount]
  , paramWord  = \case
      CalcChange        -> "change"
      CalcValueChange   -> "valuechange"
      CalcGain          -> "gain"
      CalcPostingsCount -> "count"
      -- Not offered (not in paramModes), so never in a url.
      _                 -> ""
  -- TRANSLATORS: the label before a report's calculation links, and the links' text and tooltips.
  , paramRowLabel = \trs -> tr trs "Calculate:"
  , paramLabel = \trs -> \case
      CalcChange        -> (trc trs "calculation" "Sums", tr trs "Show sums of postings")
      CalcValueChange   -> (tr trs "Value change", tr trs "Show how period-end market values changed (--valuechange)")
      CalcGain          -> (tr trs "Unrealized gain", tr trs "Show unrealized capital gains: market value minus cost (--gain)")
      CalcPostingsCount -> (tr trs "Posting counts", tr trs "Count the postings instead of summing them (--count)")
      _                 -> ("", "")
  }
