{-|

Various options to use when reading journal files.
Similar to CliOptions.inputflags, simplifies the journal-reading functions.

-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Read.InputOptions (
-- * Types and helpers for input options
  InputOpts(..)
, HasInputOpts(..)
, definputopts
, inputOptsSetJournalDir
, forecastPeriod
) where

import Control.Applicative ((<|>))
import Data.Time (Day, addDays)
import System.FilePath (takeDirectory)

import Hledger.Data.Types
import Hledger.Data.Journal (journalEndDate, journalFilePath)
import Hledger.Data.Dates (nulldate, nulldatespan)
import Hledger.Data.Balancing (BalancingOpts(..), HasBalancingOpts(..), defbalancingopts)
import Hledger.Utils (dbg2, makeHledgerClassyLenses)

data InputOpts = InputOpts {
     -- files_             :: [FilePath]
     mformat_           :: Maybe StorageFormat  -- ^ a file/storage format to try, unless overridden
                                                --   by a filename prefix. Nothing means try all.
    ,mrules_file_       :: Maybe FilePath       -- ^ a conversion rules file to use (when reading CSV)
    ,aliases_           :: [String]             -- ^ account name aliases to apply
    ,anon_              :: Bool                 -- ^ do light obfuscation of the data ? Now corresponds to --obfuscate, not the old --anon flag.
    ,new_               :: Bool                 -- ^ read only new transactions since this file was last read ?
    ,new_save_          :: Bool                 -- ^ save latest new transactions state for next time ?
    ,pivot_             :: String               -- ^ use the given field's value as the account name
    ,forecast_          :: Maybe DateSpan       -- ^ span in which to generate forecast transactions
    ,verbose_tags_      :: Bool                 -- ^ add user-visible tags when generating/modifying transactions & postings ?
    ,reportspan_        :: DateSpan             -- ^ a dirty hack keeping the query dates in InputOpts. This rightfully lives in ReportSpec, but is duplicated here.
    ,auto_              :: Bool                 -- ^ generate extra postings according to auto posting rules ?
    ,infer_equity_      :: Bool                 -- ^ infer equity conversion postings from costs ?
    ,infer_costs_       :: Bool                 -- ^ infer costs from equity conversion postings ? distinct from BalancingOpts{infer_balancing_costs_}
    ,ignore_lots_       :: Bool                 -- ^ skip lot tracking and its checks, silencing lot errors ? (basic lot inference still runs, leniently, so lot entries balance)
    ,balancingopts_     :: BalancingOpts        -- ^ options for transaction balancing
    ,strict_            :: Bool                 -- ^ do extra correctness checks ?
    ,_defer             :: Bool                 -- ^ internal flag: postpone checks, because we are processing multiple files ?
    ,_importing         :: Bool                 -- ^ internal flag: is this the @import@ command reading its data files ?
                                                --   Enables the CSV rules reader's import-specific behaviour: preferring the
                                                --   oldest file matched by a @source@ glob, and honouring the @archive@ rule.
                                                --   Set by 'importcmd'; other reads should leave it off.
    ,_dryrun            :: Bool                 -- ^ internal flag: is this a @import --dry-run@ command ?
                                                --   If set, the CSV rules reader will never archive or remove a data file.
    ,_ioDay             :: Day                  -- ^ today's date, for use with forecast transactions  XXX this duplicates _rsDay, and should eventually be removed when it's not needed anymore.
    ,_oldtimeclock      :: Bool                 -- ^ parse with the old timeclock pairing rules?
    ,_journaldir        :: Maybe FilePath       -- ^ The main journal file's directory. Used eg by the CSV rules reader to locate the
                                                --   journal's @data/@ directory. Set by the CLI entry points 'withJournal',
                                                --   'withPossibleJournal', and 'journalReload'.
                                                --   If you do a further 'readJournalFile' / 'readJournalFiles' call after a
                                                --   journal has been loaded (eg as @import@ does), apply 'inputOptsSetJournalDir'
                                                --   to its 'InputOpts' so the CSV rules reader can find the right @data/@.
                                                --   Otherwise, the CSV rules reader falls back to the rules file's own directory.
 } deriving (Eq, Ord, Show)

definputopts :: InputOpts
definputopts = InputOpts
    { mformat_           = Nothing
    , mrules_file_       = Nothing
    , aliases_           = []
    , anon_              = False
    , new_               = False
    , new_save_          = True
    , pivot_             = ""
    , forecast_          = Nothing
    , verbose_tags_      = False
    , reportspan_        = nulldatespan
    , auto_              = False
    , infer_equity_      = False
    , infer_costs_       = False
    , ignore_lots_       = False
    , balancingopts_     = defbalancingopts
    , strict_            = False
    , _defer             = False
    , _importing         = False
    , _dryrun            = False
    , _ioDay             = nulldate
    , _oldtimeclock      = False
    , _journaldir        = Nothing
    }

-- | Set 'InputOpts._journaldir' from a parsed 'Journal' (using @takeDirectory . journalFilePath@).
--
-- Use this when you want to do a further @readJournalFile@ / @readJournalFiles@ call
-- after a journal has been loaded — eg the @hledger import@ command reads the user's rules
-- files in a second pass — so the CSV rules reader can find the journal's @data/@ directory
-- for @source@ lookups and @archive@ saves. Otherwise it will fall back to using the rules
-- file's own directory, which is no longer the preferred place.
--
-- Usage:
--
-- @
-- iopts' = inputOptsSetJournalDir j $ iopts { ...other tweaks... }
-- @
inputOptsSetJournalDir :: Journal -> InputOpts -> InputOpts
inputOptsSetJournalDir j iopts = iopts{_journaldir = Just (takeDirectory (journalFilePath j))}

-- | Get the Maybe the DateSpan to generate forecast options from.
-- This begins on:
-- - the start date supplied to the `--forecast` argument, if present
-- - otherwise, the later of
--   - the report start date if specified with -b/-p/date:
--   - the day after the latest normal (non-periodic) transaction in the journal, if any
-- - otherwise today.
-- It ends on:
-- - the end date supplied to the `--forecast` argument, if present
-- - otherwise the report end date if specified with -e/-p/date:
-- - otherwise 180 days (6 months) from today.
forecastPeriod :: InputOpts -> Journal -> Maybe DateSpan
forecastPeriod iopts j = do
    DateSpan requestedStart requestedEnd <- forecast_ iopts
    let forecastStart = fromEFDay <$> requestedStart <|> max mjournalend (fromEFDay <$> reportStart) <|> Just (_ioDay iopts)
        forecastEnd   = fromEFDay <$> requestedEnd <|> fromEFDay <$> reportEnd <|> (Just $ addDays 180 $ _ioDay iopts)
        mjournalend   = dbg2 "journalEndDate" $ journalEndDate False j  -- ignore secondary dates
        DateSpan reportStart reportEnd = reportspan_ iopts
    return . dbg2 "forecastspan" $ DateSpan (Exact <$> forecastStart) (Exact <$> forecastEnd)

-- ** Lenses

makeHledgerClassyLenses ''InputOpts

instance HasBalancingOpts InputOpts where
    balancingOpts = balancingopts
