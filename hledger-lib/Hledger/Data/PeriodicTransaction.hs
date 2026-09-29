{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-|

A 'PeriodicTransaction' is a rule describing recurring transactions.

-}
module Hledger.Data.PeriodicTransaction (
    runPeriodicTransaction
  , periodicTransactionDates
  , checkPeriodicTransactionStartDate
)
where

import Data.Function ((&))
import Data.Maybe (isNothing)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import Data.Time (Day)
import Text.Printf

import Hledger.Data.Types
import Hledger.Data.Dates
import Hledger.Data.DayPartition
import Hledger.Data.Amount
import Hledger.Data.Posting (post, generatedTransactionTagName)
import Hledger.Data.Transaction

-- $setup
-- >>> :set -XOverloadedStrings
-- >>> import Hledger.Data.Posting
-- >>> import Hledger.Data.Journal

-- doctest helper, too much hassle to define in the comment
-- XXX duplicates some logic in periodictransactionp
_ptgen str = do
  let
    t = T.pack str
    (i,s) = parsePeriodExpr' nulldate t
  mapM_ (T.putStr . showTransaction) $
    runPeriodicTransaction True
      nullperiodictransaction{ ptperiodexpr=t , ptspan=s, ptinterval=i, ptpostings=["a" `post` usd 1] }
      nulldatespan

_ptgenspan str spn = do
  let
    t = T.pack str
    (i,s) = parsePeriodExpr' nulldate t
  mapM_ (T.putStr . showTransaction) $
    runPeriodicTransaction True
      nullperiodictransaction{ ptperiodexpr=t , ptspan=s, ptinterval=i, ptpostings=["a" `post` usd 1] }
      spn

--deriving instance Show PeriodicTransaction
-- for better pretty-printing:
instance Show PeriodicTransaction where
  show PeriodicTransaction{..} =
    printf "PeriodicTransactionPP {%s, %s, %s, %s, %s, %s, %s, %s, %s, %s}"
      -- Warning, be careful to keep these synced ^ v
      ("ptperiodexpr=" ++ show ptperiodexpr)
      ("ptinterval=" ++ show ptinterval)
      ("ptspan=" ++ show (show ptspan))
      ("ptsourcepos=" ++ show ptsourcepos)
      ("ptstatus=" ++ show (show ptstatus))
      ("ptcode=" ++ show ptcode)
      ("ptdescription=" ++ show ptdescription)
      ("ptcomment=" ++ show ptcomment)
      ("pttags=" ++ show pttags)
      ("ptpostings=" ++ show ptpostings)

-- A basic human-readable rendering.
--showPeriodicTransaction t = "~ " ++ T.unpack (ptperiodexpr t) ++ "\n" ++ unlines (map show (ptpostings t))

--nullperiodictransaction is defined in Types.hs

-- | Generate transactions from 'PeriodicTransaction' within a 'DateSpan'.
-- This should be a closed span with both start and end dates specified;
-- an open ended span will generate no transactions.
--
-- Note that new transactions require 'txnTieKnot' post-processing.
-- The new transactions will have three tags added: 
-- - a recur:PERIODICEXPR tag whose value is the generating periodic expression
-- - a generated-transaction: tag
-- - a hidden _generated-transaction: tag which does not appear in the comment. 
--
-- >>> import Data.Time (fromGregorian)
-- >>> _ptgen "monthly from 2017/1 to 2017/4"
-- 2017-01-01
--     ; generated-transaction: ~ monthly from 2017/1 to 2017/4
--     a                                             $1.00
-- <BLANKLINE>
-- 2017-02-01
--     ; generated-transaction: ~ monthly from 2017/1 to 2017/4
--     a                                             $1.00
-- <BLANKLINE>
-- 2017-03-01
--     ; generated-transaction: ~ monthly from 2017/1 to 2017/4
--     a                                             $1.00
-- <BLANKLINE>
--
-- >>> _ptgen "monthly from 2017/1 to 2017/5"
-- 2017-01-01
--     ; generated-transaction: ~ monthly from 2017/1 to 2017/5
--     a                                             $1.00
-- <BLANKLINE>
-- 2017-02-01
--     ; generated-transaction: ~ monthly from 2017/1 to 2017/5
--     a                                             $1.00
-- <BLANKLINE>
-- 2017-03-01
--     ; generated-transaction: ~ monthly from 2017/1 to 2017/5
--     a                                             $1.00
-- <BLANKLINE>
-- 2017-04-01
--     ; generated-transaction: ~ monthly from 2017/1 to 2017/5
--     a                                             $1.00
-- <BLANKLINE>
--
-- >>> _ptgen "every 2nd day of month from 2017/02 to 2017/04"
-- 2017-02-02
--     ; generated-transaction: ~ every 2nd day of month from 2017/02 to 2017/04
--     a                                             $1.00
-- <BLANKLINE>
-- 2017-03-02
--     ; generated-transaction: ~ every 2nd day of month from 2017/02 to 2017/04
--     a                                             $1.00
-- <BLANKLINE>
--
-- >>> _ptgen "every 30th day of month from 2017/1 to 2017/5"
-- 2017-01-30
--     ; generated-transaction: ~ every 30th day of month from 2017/1 to 2017/5
--     a                                             $1.00
-- <BLANKLINE>
-- 2017-02-28
--     ; generated-transaction: ~ every 30th day of month from 2017/1 to 2017/5
--     a                                             $1.00
-- <BLANKLINE>
-- 2017-03-30
--     ; generated-transaction: ~ every 30th day of month from 2017/1 to 2017/5
--     a                                             $1.00
-- <BLANKLINE>
-- 2017-04-30
--     ; generated-transaction: ~ every 30th day of month from 2017/1 to 2017/5
--     a                                             $1.00
-- <BLANKLINE>
--
-- >>> _ptgen "every 2nd Thursday of month from 2017/1 to 2017/4"
-- 2017-01-12
--     ; generated-transaction: ~ every 2nd Thursday of month from 2017/1 to 2017/4
--     a                                             $1.00
-- <BLANKLINE>
-- 2017-02-09
--     ; generated-transaction: ~ every 2nd Thursday of month from 2017/1 to 2017/4
--     a                                             $1.00
-- <BLANKLINE>
-- 2017-03-09
--     ; generated-transaction: ~ every 2nd Thursday of month from 2017/1 to 2017/4
--     a                                             $1.00
-- <BLANKLINE>
--
-- >>> _ptgen "every nov 29th from 2017 to 2019"
-- 2017-11-29
--     ; generated-transaction: ~ every nov 29th from 2017 to 2019
--     a                                             $1.00
-- <BLANKLINE>
-- 2018-11-29
--     ; generated-transaction: ~ every nov 29th from 2017 to 2019
--     a                                             $1.00
-- <BLANKLINE>
--
-- >>> _ptgen "2017/1"
-- 2017-01-01
--     ; generated-transaction: ~ 2017/1
--     a                                             $1.00
-- <BLANKLINE>
--
-- >>> let reportperiod="daily from 2018/01/03" in let (i,s) = parsePeriodExpr' nulldate reportperiod in runPeriodicTransaction True (nullperiodictransaction{ptperiodexpr=reportperiod, ptspan=s, ptinterval=i, ptpostings=["a" `post` usd 1]}) (DateSpan (Just $ Flex $ fromGregorian 2018 01 01) (Just $ Flex $ fromGregorian 2018 01 03))
-- []
--
-- >>> _ptgenspan "every 3 months from 2019-05" (DateSpan (Just $ Flex $ fromGregorian 2020 01 01) (Just $ Flex $ fromGregorian 2020 02 01))
--
-- >>> _ptgenspan "every 3 months from 2019-05" (DateSpan (Just $ Flex $ fromGregorian 2020 02 01) (Just $ Flex $ fromGregorian 2020 03 01))
-- 2020-02-01
--     ; generated-transaction: ~ every 3 months from 2019-05
--     a                                             $1.00
-- <BLANKLINE>
-- >>> _ptgenspan "every 3 days from 2018" (DateSpan (Just $ Flex $ fromGregorian 2018 01 01) (Just $ Flex $ fromGregorian 2018 01 05))
-- 2018-01-01
--     ; generated-transaction: ~ every 3 days from 2018
--     a                                             $1.00
-- <BLANKLINE>
-- 2018-01-04
--     ; generated-transaction: ~ every 3 days from 2018
--     a                                             $1.00
-- <BLANKLINE>
-- >>> _ptgenspan "every 3 days from 2018" (DateSpan (Just $ Flex $ fromGregorian 2018 01 02) (Just $ Flex $ fromGregorian 2018 01 05))
-- 2018-01-04
--     ; generated-transaction: ~ every 3 days from 2018
--     a                                             $1.00
-- <BLANKLINE>

runPeriodicTransaction :: Bool -> PeriodicTransaction -> DateSpan -> [Transaction]
runPeriodicTransaction verbosetags pt@PeriodicTransaction{..} requestedspan =
    [ t{tdate=d} | d <- periodicTransactionDates pt requestedspan ]
  where
    t = nulltransaction{
           tsourcepos   = ptsourcepos
          ,tstatus      = ptstatus
          ,tcode        = ptcode
          ,tdescription = ptdescription
          ,tcomment     = ptcomment
          ,ttags        = pttags
          ,tpostings    = ptpostings
          }
        & transactionAddHiddenAndMaybeVisibleTag verbosetags (generatedTransactionTagName, period)
    period = "~ " <> ptperiodexpr

-- | The dates on which this periodic transaction rule generates a transaction within the
-- given span, as a lazily generated list (so counting or consuming them once uses constant
-- memory however many there are, cf #1683).
periodicTransactionDates :: PeriodicTransaction -> DateSpan -> [Day]
periodicTransactionDates PeriodicTransaction{ptspan, ptinterval} requestedspan =
    [ d | Just d <- map spanStart alltxnspans, spanContainsDate requestedspan d ]
  where
    -- All the date spans described by this periodic transaction rule.
    alltxnspans = splitSpanToDateSpans adjust ptinterval span'
      where
        -- If the PT does not specify  start or end dates, we take them from the requestedspan.
        span' = ptspan `spanValidDefaultsFrom` requestedspan
        -- Unless the PT specified a start date explicitly, we will adjust the start date to the previous interval boundary.
        adjust = isNothing $ spanStart span'

-- | Check that this date span begins at a boundary of this interval,
-- or return an explanatory error message including the provided period expression
-- (from which the span and interval are derived).
checkPeriodicTransactionStartDate :: Interval -> DateSpan -> T.Text -> Maybe String
checkPeriodicTransactionStartDate i s periodexpr =
  case (i, spanStart s) of
    (Weeks _,    Just d) -> checkStart d Week
    (Months _,   Just d) -> checkStart d Month
    (Quarters _, Just d) -> checkStart d Quarter
    (Years _,    Just d) -> checkStart d Year
    _                    -> Nothing
    where
      checkStart d x =
        let firstDate = fromEFDay $ fixSmartDate d $ SmartRelative 0 x
        in
         if d == firstDate
         then Nothing
         else Just $
          "Unable to generate transactions according to "++show (T.unpack periodexpr)
          ++" because "++show d++" is not a first day of the "++show x

---- | What is the interval of this 'PeriodicTransaction's period expression, if it can be parsed ?
--periodTransactionInterval :: PeriodicTransaction -> Maybe Interval
--periodTransactionInterval pt =
--  let
--    expr = ptperiodexpr pt
--    err  = error' $ "Current date cannot be referenced in " ++ show (T.unpack expr)
--  in
--    case parsePeriodExpr err expr of
--      Left _      -> Nothing
--      Right (i,_) -> Just i
