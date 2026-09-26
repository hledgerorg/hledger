-- | Paging for the journal and register pages, which show the newest
-- transactions first, a page at a time, however large the journal is;
-- and the row of years a search matches, for moving through history.

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TemplateHaskell   #-}

module Hledger.Web.Paging
  ( pageSize
  , Page(..)
  , PageRequest(..)
  , pageRequest
  , pageOf
  , pageNumbers
  , pagingLinks
  , datelessQuery
  , yearsRow
  ) where

import Data.Function (on)
import Data.List (findIndex, groupBy, intercalate)
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (Day, toGregorian)
import Text.Hamlet (hamletFile)
import Text.Read (readMaybe)
import Yesod (HtmlUrl, MonadHandler, lookupGetParam)

import Hledger
import Hledger.Query qualified as Query
import Hledger.Web.Widget.Common (removeDates)

-- | How many transactions a journal or register page shows: the newest
-- this many, with links to the older pages. It keeps a page to a megabyte
-- or two and a few thousand table rows, which browsers render promptly,
-- where a whole journal of tens of thousands of rows stalls some (#586).
pageSize :: Int
pageSize = 1000

-- | Which page of a list is shown, and where it sits in the list.
data Page = Page
  { pgNumber :: Int  -- ^ this page's number, from 1
  , pgCount  :: Int  -- ^ how many pages there are, at least 1
  , pgFirst  :: Int  -- ^ the position of this page's first item, from 1; 0 when there are none
  , pgLast   :: Int  -- ^ the position of this page's last item
  , pgTotal  :: Int  -- ^ how many items there are in all
  } deriving (Eq, Show)

-- | Which page a request asks for: a page by number, or the page holding
-- a transaction named by its index (a link from one view to a transaction
-- in the other says which), or else the first.
data PageRequest = PageNumber Int | PageOfTransaction Integer | FirstPage
  deriving (Eq, Show)

-- | The page the page and txn query parameters ask for. A page number
-- that is not a positive integer is ignored; a number past the last page
-- is brought back to it by 'pageOf'.
pageRequest :: MonadHandler m => m PageRequest
pageRequest = do
  mpage <- (>>= readMaybe . T.unpack) <$> lookupGetParam "page"
  mtxn  <- (>>= readMaybe . T.unpack) <$> lookupGetParam "txn"
  return $ case (mpage, mtxn) of
    (Just n, _)       -> PageNumber (clamp n)
    (Nothing, Just i) -> PageOfTransaction i
    _                 -> FirstPage
  where
    -- read as an Integer, so that a huge number stays past the end
    -- rather than wrapping around
    clamp :: Integer -> Int
    clamp = fromInteger . max 1 . min (toInteger (maxBound :: Int))

-- | The requested page of a list, and where it sits: the first page is the
-- first 'pageSize' items, and a page number past the end gives the last
-- page. The second argument gives an item's transaction index, for finding
-- the page holding a transaction; an index not in the list gives the first
-- page.
pageOf :: PageRequest -> (a -> Integer) -> [a] -> (Page, [a])
pageOf req indexOf xs = (Page{..}, items)
  where
    pgTotal  = length xs
    pgCount  = max 1 $ (pgTotal + pageSize - 1) `div` pageSize
    pgNumber = max 1 $ min pgCount $ case req of
      PageNumber n        -> n
      PageOfTransaction i -> maybe 1 (\k -> k `div` pageSize + 1) $ findIndex ((== i) . indexOf) xs
      FirstPage           -> 1
    items    = take pageSize $ drop ((pgNumber - 1) * pageSize) xs
    pgFirst  = if pgTotal == 0 then 0 else (pgNumber - 1) * pageSize + 1
    pgLast   = min pgTotal (pgNumber * pageSize)

-- | The page numbers a pager shows: up to ten, in a window that slides
-- along with the current page, as web pagers usually do.
pageNumbers :: Int -> Int -> [Int]
pageNumbers current count = [start .. min count (start + 9)]
  where start = max 1 $ min (current - 4) (count - 9)

-- | The line saying which of the matching transactions this page shows,
-- and under it the row of pages: links to the newer and older pages and
-- to the pages by number, the current one marked. Nothing when they all
-- fit on one page. The links keep the search.
pagingLinks :: r -> Text -> Page -> HtmlUrl r
pagingLinks here qparam Page{..} = $(hamletFile "templates/paging.hamlet")
  where
    link n = (here, [("q", qparam) | not (T.null qparam)] ++ [("page", T.pack (show n)) | n > 1])
    mnewer = if pgNumber > 1       then Just (pgNumber - 1) else Nothing
    molder = if pgNumber < pgCount then Just (pgNumber + 1) else Nothing
    numbers = pageNumbers pgNumber pgCount

-- | The search without its date terms, parsed as the year links' searches
-- will be; or Nothing when it has none, or when what is left does not
-- parse. The years row counts what a search matches in any year by the
-- same report the page shows, so a handler runs its report again on this,
-- and the counts are what each year link's page shows.
datelessQuery :: Day -> Journal -> Text -> Maybe Query
datelessQuery today j qparam
  | length rest == length terms = Nothing
  | otherwise = case parseQuery today (T.unwords rest) of
      Right (q, _) -> Just . simplifyQuery $ queryExpandCurAliases j q
      Left _       -> Nothing
  where
    terms = filter (not . T.null) $ Query.words'' queryprefixes qparam
    rest = removeDates qparam

-- | The years in which a search matches transactions, each a link to the
-- search narrowed to that year, after an All link that widens it again.
-- Nothing when there is only one year, which has nowhere to go. More than
-- twenty years are grouped by decade, a row each.
yearsRow :: r -> Text -> [Day] -> HtmlUrl r
yearsRow here qparam days = $(hamletFile "templates/years.hamlet")
  where
    years :: [Integer]
    years = S.toAscList $ S.fromList [y | d <- days, let (y, _, _) = toGregorian d]
    manyYears = length years > 1
    byDecade = if length years > 20 then map decadeRow $ groupBy ((==) `on` decade) years else []
    decadeRow ys@(y:_) = (show (decade y * 10) ++ "s", ys)
    decadeRow [] = ("", [])
    decade y = y `div` 10
    terms = filter (not . T.null) $ Query.words'' queryprefixes qparam
    isDateTerm t = any (`T.isPrefixOf` t) ["date:", "date2:"]
    -- the search without its date terms, which each year link replaces
    rest = removeDates qparam
    -- A year is current when the search names it as a whole, in the form
    -- the year links use; a year written another way is not recognized.
    isCurrent y = ("date:" <> T.pack (show y)) `elem` terms
    allCurrent = not $ any isDateTerm terms
    yearlink y = (here, [("q", T.unwords $ ("date:" <> T.pack (show y)) : rest)])
    alllink = (here, [("q", T.unwords rest) | not (null rest)])

-- | A count with thousands separators, as English prose has it: 1,234.
withCommas :: Int -> Text
withCommas n
  | n < 0 = "-" <> withCommas (negate n)
  | otherwise = T.pack . reverse . intercalate "," . chunks . reverse $ show n
  where
    chunks [] = []
    chunks s = let (a, b) = splitAt 3 s in a : chunks b
