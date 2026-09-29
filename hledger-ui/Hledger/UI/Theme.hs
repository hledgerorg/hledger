-- | The all-important theming engine!
--
-- Cf
-- https://hackage.haskell.org/package/vty/docs/Graphics-Vty-Attributes.html
-- http://hackage.haskell.org/package/brick/docs/Brick-AttrMap.html
-- http://hackage.haskell.org/package/brick-0.1/docs/Brick-Util.html
-- http://hackage.haskell.org/package/brick-0.1/docs/Brick-Widgets-Core.html#g:5
-- http://hackage.haskell.org/package/brick-0.1/docs/Brick-Widgets-Border.html

{-# LANGUAGE OverloadedStrings #-}

module Hledger.UI.Theme (
   defaultTheme
  ,getTheme
  ,themes
  ,themeNames
)
where

import Data.Map qualified as M
import Data.Maybe
import Graphics.Vty
import Brick
import Safe (headErr)

defaultTheme :: AttrMap
defaultTheme = fromMaybe (snd $ headErr themesList) $ getTheme "light"  -- PARTIAL headErr succeeds because themesList is non-null
  -- the theme named here should exist;
  -- otherwise it will take the first one from the list,
  -- which must be non-empty.

-- | Look up the named theme, if it exists.
getTheme :: String -> Maybe AttrMap
getTheme name = M.lookup name themes

-- | A selection of named themes specifying terminal colours and styles.
-- One of these is active at a time.
--
-- A hledger-ui theme is a vty/brick AttrMap.  Each theme specifies a
-- default style (Attr), plus extra styles which are applied when
-- their (hierarchical) name matches the widget rendering context.
-- "More specific styles, if present, are used and only fall back to
-- more general ones when the more specific ones are absent, but also
-- these styles get merged, so that if a more specific style only
-- provides the foreground color, its more general parent style can
-- set the background color, too."
-- For example: rendering a widget named "b" inside a widget named "a",
-- - if a style named "a" <> "b" exists, it will be used. Anything it
--   does not specify will be taken from a style named "a" if that
--   exists, otherwise from the default style.
-- - otherwise if a style named "a" exists, it will be used, and
--   anything it does not specify will be taken from the default style.
-- - otherwise (you guessed it) the default style is used.
--
themes :: M.Map String AttrMap
themes = M.fromList themesList

themeNames :: [String]
themeNames = map fst themesList

(&) = withStyle
active = fg brightWhite & bold
selectbg = cyan
select = black `on` selectbg

themesList :: [(String, AttrMap)]
themesList = [
   ("light", attrMap (black `on` white) [
     (attrName "border"                                        , white `on` black & dim)
    ,(attrName "border" <> attrName "bold"                              , currentAttr & bold)
    ,(attrName "border" <> attrName "depth"                             , active)
    ,(attrName "border" <> attrName "filename"                          , currentAttr)
    ,(attrName "border" <> attrName "key"                               , active)
    ,(attrName "border" <> attrName "minibuffer"                        , white `on` black & bold)
    ,(attrName "border" <> attrName "query"                             , active)
    ,(attrName "border" <> attrName "selected"                          , active)
    ,(attrName "error"                                         , fg red)
    ,(attrName "warning"                                       , fg brightYellow & bold)  -- like the CLI's warning colour (ansiFormatWarning)
    ,(attrName "help"                                          , white `on` black & dim)
    ,(attrName "help" <> attrName "heading"                             , fg yellow)
    ,(attrName "help" <> attrName "key"                                 , active)
    -- ,(attrName "list"                                          , black `on` white)
    -- ,(attrName "list" <> attrName "amount"                              , currentAttr)
    ,(attrName "list" <> attrName "amount" <> attrName "decrease"                , fg red)
    -- ,(attrName "list" <> attrName "amount" <> attrName "increase"                , fg green)
    ,(attrName "list" <> attrName "amount" <> attrName "decrease" <> attrName "selected"  , red `on` selectbg & bold)
    -- ,(attrName "list" <> attrName "amount" <> attrName "increase" <> attrName "selected"  , green `on` selectbg & bold)
    ,(attrName "list" <> attrName "balance"                             , currentAttr & bold)
    ,(attrName "list" <> attrName "balance" <> attrName "negative"               , fg red)
    ,(attrName "list" <> attrName "balance" <> attrName "positive"               , fg black)
    ,(attrName "list" <> attrName "balance" <> attrName "negative" <> attrName "selected" , red `on` selectbg & bold)
    ,(attrName "list" <> attrName "balance" <> attrName "positive" <> attrName "selected" , select & bold)
    ,(attrName "list" <> attrName "selected"                            , select)
    -- ,(attrName "list" <> attrName "accounts"                         , white `on` brightGreen)
    -- ,(attrName "list" <> attrName "selected"                         , black `on` brightYellow)
  ])

  ,("dark", attrMap (white `on` black & dim) [
      (attrName "border"                                                                   , white `on` black)
    , (attrName "border" <> attrName "bold"                                                , currentAttr & bold)
    , (attrName "border" <> attrName "depth"                                               , active)
    , (attrName "border" <> attrName "filename"                                            , currentAttr)
    , (attrName "border" <> attrName "key"                                                 , active)
    , (attrName "border" <> attrName "minibuffer"                                          , white `on` black & bold)
    , (attrName "border" <> attrName "query"                                               , active)
    , (attrName "border" <> attrName "selected"                                            , active)
    , (attrName "error"                                                                    , fg red)
    , (attrName "warning"                                                                  , fg brightYellow & bold)  -- like the CLI's warning colour (ansiFormatWarning)
    , (attrName "help"                                                                     , currentAttr & bold)
    , (attrName "help" <> attrName "heading"                                               , fg blue)
    , (attrName "help" <> attrName "key"                                                   , active)
    , (attrName "list" <> attrName "amount" <> attrName "decrease"                         , fg red)
    , (attrName "list" <> attrName "amount" <> attrName "decrease" <> attrName "selected"  , red `on` black & bold)
    , (attrName "list" <> attrName "balance"                                               , currentAttr)
    , (attrName "list" <> attrName "balance" <> attrName "negative"                        , fg red)
    , (attrName "list" <> attrName "balance" <> attrName "positive"                        , fg white)
    , (attrName "list" <> attrName "balance" <> attrName "negative" <> attrName "selected" , red `on` black    & bold)
    , (attrName "list" <> attrName "balance" <> attrName "positive" <> attrName "selected" , cyan `on` black & bold)
    , (attrName "list" <> attrName "selected"                                              , cyan `on` black & bold)
  ])

  ,("terminal", attrMap defAttr [
    (attrName "border"                                         , white `on` black),
    (attrName "list"                                           , defAttr),
    (attrName "list" <> attrName "selected"                             , defAttr & reverseVideo)
  ])

  ,("greenterm", attrMap (green `on` black) [
    (attrName "list" <> attrName "selected"                             , black `on` green)
  ])

  ]

-- halfbrightattr = defAttr & dim
-- reverseattr = defAttr & reverseVideo
-- redattr = defAttr `withForeColor` red
-- greenattr = defAttr `withForeColor` green
-- reverseredattr = defAttr & reverseVideo `withForeColor` red
-- reversegreenattr= defAttr & reverseVideo `withForeColor` green
