{-|

Instances for obfuscating sensitive data (mainly text, not numbers) in various types.

Currently this is deterministic and does not provide much privacy.
It has been moved to a hidden --obfuscate flag, with the old --anon flag
now raising an error. See https://github.com/hledgerorg/hledger/issues/2133 .

-}

module Hledger.Cli.Anon
    ( Anon(..)
    , anonAccount
    )
where

import Control.Arrow (first)
import Data.Hashable (hash)
import Data.Word (Word32)
import Numeric (showHex)
import Data.Text qualified as T

import Hledger.Data
import Data.Map (mapKeys)

class Anon a where
    -- | Consistent converter to structure with sensitive data anonymized
    anon :: a -> a

instance Anon Journal where
    -- Apply the anonymisation transformation on a journal after finalisation
    anon j = j { jtxns = map anon . jtxns $ j
               , jitems = []  -- verbatim source text, may contain anything
               , jparseparentaccounts  = map anonAccount $ jparseparentaccounts j
               , jparsealiases         = []  -- already applied
               , jdeclaredaccounts     = map (first anon) $ jdeclaredaccounts j
               , jdeclaredaccounttags  = mapKeys anon $ jdeclaredaccounttags j
               , jdeclaredaccounttypes = (map anon) <$> jdeclaredaccounttypes j
               }

instance Anon Posting where
    anon p = p { paccount = anonAccount . paccount $ p
               , pcomment = T.empty
               , ptransaction = fmap anon . ptransaction $ p  -- Note that this will be overridden
               , poriginal = anon <$> poriginal p
               }

instance Anon Transaction where
    anon txn = txnTieKnot $ txn { tpostings = map anon . tpostings $ txn
                                , tdescription = anon . tdescription $ txn
                                , tcode = anon . tcode $ txn
                                , tcomment = T.empty
                                , tprecedingcomment = T.empty
                                }

-- | Anonymize account name preserving hierarchy
anonAccount :: AccountName -> AccountName
anonAccount = T.intercalate (T.pack ":") . map anon . T.splitOn (T.pack ":")

instance Anon T.Text where anon = T.pack . flip showHex "" . (fromIntegral :: Int -> Word32) . hash
