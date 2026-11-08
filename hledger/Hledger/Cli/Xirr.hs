{-|

Calculation of the internal rate of return of some dated cash flows, shared by the @roi@ and @holdings@ commands.

-}

module Hledger.Cli.Xirr (
  IrrError(..)
  , xirr
) where

import Data.Time.Calendar (Day, diffDays)
import Numeric.RootFinding (RiddersParam(..), Root(..), Tolerance(..), ridders)

import Hledger (Quantity)

-- | Why an internal rate of return could not be computed.
data IrrError
  = IrrNothingPutIn     -- ^ money only came out (or is still in at the end), and none was put in: the rate is infinite
  | IrrAllOnOneDay Day  -- ^ all the cash flows fall on this day, so no time passes, but they don't add up to zero
  | IrrNotBracketed     -- ^ no solution between -100% and the largest rate searched (1000000%)
  | IrrSearchFailed     -- ^ the search for a solution did not converge
  deriving (Eq, Show)

-- | The annualised internal rate of return of some dated cash flows, as a percentage, like Excel's XIRR.
-- What is put in is negative; what is taken out, or is still held at the end, is positive.
-- Each flow is compounded from its date to the reference day (usually the date of the last one).
--
-- Some cases have no solution, or one the search can't find:
--
-- - no cash flows: 0%
-- - money is put in, but nothing comes out or is left: -100% (all of it was lost)
-- - money comes out or is left, but nothing is put in: an infinite rate, so an error
-- - all on one day: 0% if they add up to zero (nothing was gained or lost), otherwise an error, as no time passes for
--   the gain or loss to happen in.
--
-- So on one day, a total loss is -100% but a partial loss is an error. That's because a total loss solves
-- (1+r)^t = 0, which gives -100% however long the money was in. A partial loss (eg (1+r)^t = 0.5) depends on t, and has
-- no solution when no time passes.
-- (Also, cash flows which net to zero are not passed in, so a total loss's date is not known here.)
xirr :: Day -> [(Day, Quantity)] -> Either IrrError Double
xirr referenceDay cf0 = case cf of
  [] -> Right 0
  _ | all ((< 0) . snd) cf -> Right (-100)
    | all ((> 0) . snd) cf -> Left IrrNothingPutIn
  (d, _) : _ | all ((== d) . fst) cf ->
    -- (valued amounts can leave a tiny remainder, so allow for that)
    if abs (sum qs) <= maximum (map abs qs) / 10^(10::Int) then Right 0 else Left (IrrAllOnOneDay d)
    where qs = map snd cf
  _ -> case ridders (RiddersParam 100 (AbsTol 0.00001)) (0.000000000001, 10000) npv of
         Root rate    -> Right $ (rate - 1) * 100
         NotBracketed -> Left IrrNotBracketed
         SearchFailed -> Left IrrSearchFailed
  where
    cf = filter ((/= 0) . snd) cf0
    -- the cash flows' net value on the reference day, at this rate (1 + the annual rate of return)
    npv rate = sum [ realToFrac q * rate ** (fromIntegral (diffDays referenceDay t) / 365.25) | (t, q) <- cf ]
