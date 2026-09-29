--- * -*- outline-regexp:"--- \\*"; -*-
--- ** doc
-- In Emacs, use TAB on lines beginning with "-- *" to collapse/expand sections.
{-|

A reader for the "timedot" file format.
Example:

@
;DATE
;ACCT  DOTS  # Each dot represents 15m, spaces are ignored
;ACCT  8    # numbers with or without a following h represent hours
;ACCT  5m   # numbers followed by m represent minutes

; on 2/1, 1h was spent on FOSS haskell work, 0.25h on research, etc.
2/1
fos.haskell   .... ..
biz.research  .
inc.client1   .... .... .... .... .... ....

2/2
biz.research  .
inc.client1   .... .... ..

@

-}

--- ** language
{-# LANGUAGE OverloadedStrings #-}

--- ** exports
module Hledger.Read.TimedotReader (
  -- * Reader
  reader,
  -- * Misc other exports
  timedotfilep,
)
where

--- ** imports
import Control.Monad
import Control.Monad.Except (ExceptT, liftEither)
import Control.Monad.State.Strict
import Data.Char (isSpace)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (Day)
import Text.Megaparsec hiding (parse)
import Text.Megaparsec.Char

import Hledger.Data
import Hledger.Read.Common
import Hledger.Utils
import Data.Decimal (roundTo)
import Data.Functor ((<&>))
import Data.List (sort)
import Data.List (group)
-- import Text.Megaparsec.Debug (dbg)

--- ** doctest setup
-- $setup
-- >>> :set -XOverloadedStrings

--- ** reader

reader :: MonadIO m => Reader m
reader = Reader
  {rFormat     = Timedot
  ,rExtensions = ["timedot"]
  ,rReadFn     = handleReadFnToTextReadFn parse
  ,rParser    = timedotp
  }

-- | Parse and post-process a "Journal" from the timedot format, or give an error.
parse :: InputOpts -> FilePath -> Text -> ExceptT String IO Journal
parse iopts fp t = initialiseAndParseJournal (timedotp iopts) iopts fp t
                   >>= liftEither . journalApplyAliases (aliasesFromOpts iopts)
                   >>= journalFinalise iopts fp t

--- ** utilities

-- Trace parser state above a certain --debug level ?
tracelevel = 9
dp :: String -> JournalParser m ()
dp = if tracelevel >= 0 then lift . dbgparse tracelevel else const $ return ()

--- ** parsers
{-
Rough grammar for timedot format:

timedot:           preamble day*
preamble:          (emptyline | commentline | orgheading)*
orgheading:        orgheadingprefix restofline
day:               dateline entry* (emptyline | commentline)*
dateline:          orgheadingprefix? date description?
orgheadingprefix:  star+ space+
description:       restofline  ; till semicolon?
entry:          orgheadingprefix? space* singlespaced (doublespace quantity?)?
doublespace:       space space+
quantity:          (dot (dot | space)* | number | number unit)

Date lines and item lines can begin with an org heading prefix, which is ignored.
Org headings before the first date line are ignored, regardless of content.
-}

timedotfilep = timedotp -- XXX rename export above

timedotp :: InputOpts -> JournalParser m ParsedJournal
timedotp _ = preamblep >> many dayp >> eof >> get

-- | A lookahead that succeeds when the current line looks like a date line attempt:
-- either a valid date line (full or partial date, with optional org heading prefix),
-- or three groups of digits separated by '-', '/', or '.' (catches malformed full dates,
-- so they error clearly via datep rather than being silently treated as a comment or entry).
-- Does not consume input.
datelineattemptp :: JournalParser m ()
datelineattemptp = lift datelikep <|> void datelinep
  where
    datelikep = try . lookAhead $ do
      optional . try $ skipSome (char '*') >> skipNonNewlineSpaces1
      void $ some digitChar
      void datesepchar
      void $ some digitChar
      void datesepchar
      void $ some digitChar

preamblep :: JournalParser m ()
preamblep = do
  dp "preamblep"
  void $ many $ do
    notFollowedBy datelineattemptp
    lift $ emptyorcommentlinep2 "#;*"

-- | Parse timedot day entries to multi-posting time transactions for that day.
-- @
-- 2020/2/1 optional day description
-- fos.haskell  .... ..
-- biz.research .
-- inc.client1  .... .... .... .... .... ....
-- @
dayp :: JournalParser m ()
dayp = label "timedot day entry" $ do
  dp "dayp"
  pos <- getSourcePos
  (date,desc,comment,tags) <- datelinep
  dp "dayp1"
  commentlinesp
  dp "dayp2"
  ps <- (many $ dp "dayp3" >> timedotentryp <* commentlinesp) <&> concat
  endpos <- getSourcePos
  let t = txnTieKnot $ nulltransaction{
    tsourcepos   = (pos, endpos),
    tdate        = date,
    tstatus      = Cleared,
    tdescription = desc,
    tcomment     = comment,
    ttags        = tags,
    tpostings    = ps
    }
  modify' $ addTransaction t

datelinep :: JournalParser m (Day,Text,Text,[Tag])
datelinep = do
  dp "datelinep"
  lift $ optional orgheadingprefixp
  date <- datep
  desc <- T.strip <$> lift descriptionp
  (comment, tags) <- lift transactioncommentp
  return (date, desc, comment, tags)

-- | Zero or more empty lines or hash/semicolon comment lines
-- or org headlines which do not start a new day.
commentlinesp :: JournalParser m ()
commentlinesp = do
  dp "commentlinesp"
  void $ many $ try $ lift $ emptyorcommentlinep2 "#;"

-- orgnondatelinep :: JournalParser m ()
-- orgnondatelinep = do
--   dp "orgnondatelinep"
--   lift orgheadingprefixp
--   notFollowedBy datelinep
--   void $ lift restofline

orgheadingprefixp = skipSome (char '*') >> skipNonNewlineSpaces1

-- | Parse a single timedot data line as one or more postings.
-- (Multiple postings can arise if timedot letter syntax is used.)
-- @
-- fos.haskell  .... ..
-- @
timedotentryp :: JournalParser m [Posting]
timedotentryp = do
  dp "timedotentryp"
  notFollowedBy datelineattemptp
  lift $ optional $ choice [orgheadingprefixp, skipNonNewlineSpaces1]
  a <- modifiedaccountnamep False
  lift skipNonNewlineSpaces
  taggedhours <- lift durationsp
  (comment0, tags0) <-
         lift transactioncommentp    -- not postingp, don't bother with date: tags here
     <|> (newline >> return ("",[]))
  mcs <- getDefaultCommodityAndStyle
  let 
    (c,s) = case mcs of
      Just (defc,defs) -> (defc, defs{asprecision=max (asprecision defs) (Precision 2)})
      _ -> ("", amountstyle{asprecision=Precision 2})
    ps = [
      nullposting{paccount=a
                ,pamount=mixedAmount $ nullamt{acommodity=c, aquantity=hours, astyle=s}
                ,preal=VirtualPosting
                ,pcomment=comment
                ,ptags=tags
                }
      | (hours,tagval) <- taggedhours
      , let tag = ("t",tagval)
      , let tags    = if T.null tagval then tags0    else tags0 ++ [tag]
      , let comment = if T.null tagval then comment0 else comment0 `commentAddTagUnspaced` tag
      ]
  return ps

type Hours = Quantity

-- | Parse one or more durations in hours, each with an optional tag value
-- (or empty string for none).
durationsp :: TextParser m [(Hours,TagValue)]
durationsp =
      (try numericquantityp <&> \h -> [(h,"")])  -- try needed because numbers can begin with .
  <|> (dotquantityp     <&> \h -> [(h,"")])
  <|> letterquantitiesp
  <|> pure [(0,"")]

-- | Parse a duration of seconds, minutes, hours, days, weeks, months or years,
-- written as a decimal number followed by s, m, h, d, w, mo or y, assuming h
-- if there is no unit. Returns the duration as hours, assuming
-- 1m = 60s, 1h = 60m, 1d = 24h, 1w = 7d, 1mo = 30d, 1y=365d.
-- @
-- 1.5
-- 1.5h
-- 90m
-- @
numericquantityp :: TextParser m Hours
numericquantityp = do
  -- dp "numericquantityp"
  (q, _, _, _) <- numberp Nothing
  msymbol <- optional $ choice $ map (string . fst) timeUnits
  skipNonNewlineSpaces
  let q' =
        case msymbol of
          Nothing  -> q
          Just sym -> roundTo 2 $
            case lookup sym timeUnits of
              Just mult -> q * mult
              Nothing   -> q  -- shouldn't happen.. ignore
  return q'

-- (symbol, equivalent in hours).
timeUnits =
  [("s",2.777777777777778e-4)
  ,("mo",5040) -- before "m"
  ,("m",1.6666666666666666e-2)
  ,("h",1)
  ,("d",24)
  ,("w",168)
  ,("y",61320)
  ]

-- | Parse a quantity written as a line of one or more dots,
-- each representing 0.25, ignoring any interspersed spaces
-- after the first dot.
-- @
-- .... ..
-- @
dotquantityp :: TextParser m Hours
dotquantityp = do
  -- dp "dotquantityp"
  char '.'
  dots <- many (oneOf ['.', ' ']) <&> filter (not.isSpace)
  return $ fromIntegral (1 + length dots) / 4

-- | Parse a quantity written as a line of one or more letters,
-- each representing 0.25 with a tag "t" whose value is the letter,
-- ignoring any interspersed spaces after the first letter.
letterquantitiesp :: TextParser m [(Hours, TagValue)]
letterquantitiesp =
  -- dp "letterquantitiesp"
  do
    letter1 <- letterChar
    letters <- many (letterChar <|> spacenonewline) <&> filter (not.isSpace)
    let groups =
          [ (fromIntegral (length t) / 4, T.singleton c)
          | t@(c:_) <- group $ sort $ letter1:letters
          ]
    return groups
