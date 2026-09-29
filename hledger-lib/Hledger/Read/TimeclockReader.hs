--- * -*- outline-regexp:"--- \\*"; -*-
--- ** doc
-- In Emacs, use TAB on lines beginning with "-- *" to collapse/expand sections.

-- Keep relevant parts synced with manual:
{-|

A reader for the timeclock file format.

What exactly is this format ? It was introduced in timeclock.el (<http://www.emacswiki.org/emacs/TimeClock>).
The old specification in timeclock.el 2.6 was:

@
A timeclock contains data in the form of a single entry per line.
Each entry has the form:

  CODE YYYY/MM/DD HH:MM:SS [COMMENT]

CODE is one of: b, h, i, o or O.  COMMENT is optional when the code is
i, o or O.  The meanings of the codes are:

  b  Set the current time balance, or \"time debt\".  Useful when
     archiving old log data, when a debt must be carried forward.
     The COMMENT here is the number of seconds of debt.

  h  Set the required working time for the given day.  This must
     be the first entry for that day.  The COMMENT in this case is
     the number of hours in this workday.  Floating point amounts
     are allowed.

  i  Clock in.  The COMMENT in this case should be the name of the
     project worked on.

  o  Clock out.  COMMENT is unnecessary, but can be used to provide
     a description of how the period went, for example.

  O  Final clock out.  Whatever project was being worked on, it is
     now finished.  Useful for creating summary reports.
@

Ledger's timeclock format is different, and hledger's timeclock format is different again.
For example: in a clock-in entry, after the time,

- timeclock.el's timeclock has 0-1 fields: [COMMENT]
- Ledger's timeclock has 0-2 fields:       [ACCOUNT[  PAYEE]]
- hledger's timeclock has 1-3 fields:      ACCOUNT[  DESCRIPTION[;COMMENT]]

hledger's timeclock format is:

@
# Comment lines like these, and blank lines, are ignored:
# comment line
; comment line
* comment line

# Lines beginning with b, h, or capital O are also ignored, for compatibility:
b SIMPLEDATE HH:MM[:SS][+-ZZZZ][ TEXT]
h SIMPLEDATE HH:MM[:SS][+-ZZZZ][ TEXT]
O SIMPLEDATE HH:MM[:SS][+-ZZZZ][ TEXT]

# Lines beginning with i or o are are clock-in / clock-out entries:
i SIMPLEDATE HH:MM[:SS][+-ZZZZ] ACCOUNT[  DESCRIPTION][;COMMENT]]
o SIMPLEDATE HH:MM[:SS][+-ZZZZ][ ACCOUNT][;COMMENT]
@

The date is a hledger [simple date](#simple-dates) (YYYY-MM-DD or similar).
The time parts must use two digits.
The seconds are optional.
A + or - four-digit time zone is accepted for compatibility, but currently ignored; times are always interpreted as a local time.

In clock-in entries (`i`), the account name is required.
A transaction description, separated from the account name by 2+ spaces, is optional.
A transaction comment, beginning with `;`, is also optional.

In clock-out entries (`o`) have no description, but can have a comment if you wish.
A clock-in and clock-out pair form a "transaction" posting some number of hours to an account - also known as a session.
Eg:

```timeclock
i 2015/03/30 09:00:00 session1
o 2015/03/30 10:00:00
```

```cli
$ hledger -f a.timeclock print
2015-03-30 * 09:00-10:00
    (session1)           1.00h
```

Clock-ins and clock-outs are matched by their account/session name.
If a clock-outs does not specify a name, the most recent unclosed clock-in is closed.
Also, sessions spanning more than one day are automatically split at day boundaries.
Eg, the following time log:

```timeclock
i 2015/03/30 09:00:00 some account  optional description after 2 spaces ; optional comment, tags:
o 2015/03/30 09:20:00
i 2015/03/31 22:21:45 another:account
o 2015/04/01 02:00:34
i 2015/04/02 12:00:00 another:account  ; this demonstrates multple sessions being clocked in
i 2015/04/02 13:00:00 some account
o 2015/04/02 14:00:00
o 2015/04/02 15:00:00 another:account
```

generates these transactions:

```cli
$ hledger -f t.timeclock print
2015-03-30 * optional description after 2 spaces   ; optional comment, tags:
    (some account)           0.33h

2015-03-31 * 22:21-23:59
    (another:account)           1.64h

2015-04-01 * 00:00-02:00
    (another:account)           2.01h

2015-04-02 * 12:00-15:00  ; this demonstrates multiple sessions being clocked in
    (another:account)           3.00h

2015-04-02 * 13:00-14:00
    (some account)           1.00h

```

-}

--- ** language
{-# LANGUAGE OverloadedStrings #-}

--- ** exports
module Hledger.Read.TimeclockReader (
  -- * Reader
  reader,
  -- * Misc other exports
  timeclockfilep,
)
where

--- ** imports
import           Control.Monad
import           Control.Monad.Except (ExceptT, liftEither)
import           Control.Monad.State.Strict
import           Data.Maybe (fromMaybe)
import           Data.Text (Text)
import           Text.Megaparsec hiding (parse)

import           Hledger.Data
-- XXX too much reuse ?
import           Hledger.Read.Common
import           Hledger.Utils
import Data.Text as T (strip)
import Data.Functor ((<&>))

--- ** doctest setup
-- $setup
-- >>> :set -XOverloadedStrings

--- ** reader

reader :: MonadIO m => Reader m
reader = Reader
  {rFormat     = Timeclock
  ,rExtensions = ["timeclock"]
  ,rReadFn     = handleReadFnToTextReadFn parse
  ,rParser     = timeclockfilep
  }

-- | Parse and post-process a "Journal" from timeclock.el's timeclock
-- format, saving the provided file path and the current time, or give an
-- error.
parse :: InputOpts -> FilePath -> Text -> ExceptT String IO Journal
parse iopts fp t = initialiseAndParseJournal (timeclockfilep iopts) iopts fp t
                   >>= liftEither . journalApplyAliases (aliasesFromOpts iopts)
                   >>= journalFinalise iopts fp t

--- ** parsers

-- timeclockfilepspecial :: InputOpts -> JournalParser m ParsedJournal
-- timeclockfilepspecial args = 
-- timeclockfilep args

timeclockfilep :: MonadIO m => InputOpts -> JournalParser m ParsedJournal
timeclockfilep iopts = do
  many timeclockitemp
  eof
  j@Journal{jparsetimeclockentries=es} <- get
  -- Convert timeclock entries in this journal to transactions, closing any unfinished sessions.
  -- Doing this here rather than in journalFinalise means timeclock sessions can't span file boundaries,
  -- but it simplifies code above.
  now <- liftIO getCurrentLocalTime
  -- journalFinalise expects the transactions in reverse order, so reverse the output in either case
  let
    j' = if _oldtimeclock iopts
      then
        -- timeclockToTransactionsOld expects the entries to be in normal order, 
        -- but they have been parsed in reverse order, so reverse them before calling
        j{jtxns = reverse $ timeclockToTransactionsOld now $ reverse es, jparsetimeclockentries = []}
      else
        -- We don't need to reverse these transactions 
        -- since they are sorted inside of timeclockToTransactions
        j{jtxns = reverse $ timeclockToTransactions now es, jparsetimeclockentries = []}
  return j'
  where
    -- As all ledger line types can be distinguished by the first
    -- character, excepting transactions versus empty (blank or
    -- comment-only) lines, can use choice w/o try
    timeclockitemp = choice [
       void (lift emptyorcommentlinep)
      ,entryp >>= \e -> modify' (\j -> j{jparsetimeclockentries = e : jparsetimeclockentries j})
      ] <?> "timeclock entry, comment line, or empty line"
      where entryp = if _oldtimeclock iopts then oldtimeclockentryp else timeclockentryp

-- | Parse a timeclock entry (loose pre-1.50 format).
oldtimeclockentryp :: JournalParser m TimeclockEntry
oldtimeclockentryp = do
  pos <- getSourcePos
  code <- oneOf ("bhioO" :: [Char])
  lift skipNonNewlineSpaces1
  datetime <- datetimep
  account     <- fmap (fromMaybe "") $ optional $ lift skipNonNewlineSpaces1 >> modifiedaccountnamep True
  description <- fmap (maybe "" T.strip) $ optional $ lift $ skipNonNewlineSpaces1 >> descriptionp
  (comment, tags) <- lift transactioncommentp
  return $ TimeclockEntry pos (read [code]) datetime account description comment tags

-- | Parse a timeclock entry (more robust post-1.50 format).
timeclockentryp :: JournalParser m TimeclockEntry
timeclockentryp = do
  pos <- getSourcePos
  code <- oneOf ("iobhO" :: [Char])
  lift skipNonNewlineSpaces1
  datetime <- datetimep
  (account, description) <- case code of
    'i' -> do
      lift skipNonNewlineSpaces1
      a <- modifiedaccountnamep False
      d <- optional (lift $ skipNonNewlineSpaces1 >> descriptionp) <&> maybe "" T.strip
      return (a, d)
    'o' -> do
      -- Notice the try needed here to avoid a parse error if there's trailing spaces.
      -- Unlike descriptionp above, modifiedaccountnamep requires nonempty text.
      -- And when a parser in an optional fails after consuming input, optional doesn't backtrack,
      -- it propagates the failure.
      a <- optional (try $ lift skipNonNewlineSpaces1 >> modifiedaccountnamep False) <&> fromMaybe ""
      return (a, "")
    _ -> return ("", "")
  lift skipNonNewlineSpaces
  (comment, tags) <- lift $ optional transactioncommentp <&> fromMaybe ("",[])
  return $ TimeclockEntry pos (read [code]) datetime account description comment tags
