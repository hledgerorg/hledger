{-|
A convenient module to import in hledger scripts, 
aiming to provide the most useful imports and reduce boilerplate.
|-}

{-# LANGUAGE CPP #-}
{-# LANGUAGE PackageImports #-}

module Hledger.Cli.Script 
( module M
) 
where

import Control.Applicative as M
import Control.Concurrent as M
import Control.Monad as M
import Data.Char as M
import Data.Either as M

import Data.Functor as M
#if MIN_VERSION_base(4,19,0)
  hiding (unzip)
#endif
-- import Data.Functor as M (Functor, fmap, (<$), ($>), (<$>), (<&>))  -- or without CPP ? redundant import warning

import Data.List as M
import Data.Maybe as M
import Data.Ord as M
-- import Data.String.QQ (s)  -- https://github.com/audreyt/string-qq/pull/3
import Data.Time as M
import Text.Printf as M hiding (formatString)
import "text" Data.Text as M (Text, pack, unpack)
  -- can't re-export much of Data.Text & Data.Text.IO, they need to be qualified
import Safe as M hiding (at)
-- import System.Console.CmdArgs.Explicit qualified as M
import System.Directory as M
import System.Environment as M
import System.Exit as M
import System.FilePath as M
import System.IO as M
import System.IO.Error as M
import System.Process as M

-- import Hledger.Cli as M hiding (main)
import Hledger.Cli as M (argsToCliOpts)
import Hledger.Cli.CliOptions as M
import Hledger.Cli.Commands as M
import Hledger.Cli.DocFiles as M
import Hledger.Cli.Utils as M
import Hledger.Cli.Version as M
import Hledger.Cli.CompoundBalanceCommand as M

import Hledger as M
import System.Console.CmdArgs.Explicit as M

-- import Hledger.Cli as M (argsToCliOpts)
