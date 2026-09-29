-- the hledger command-line executable; see Hledger/Cli.hs

module Main (main)
where
import Control.Monad (when)
import System.IO (hClose, hIsSeekable, stdout)
import Hledger.Cli qualified (main)

-- Have to write this explicitly for GHC 9.0.1a for some reason:
main :: IO ()
main = do
  Hledger.Cli.main
  -- When output is redirected to a file, close it explicitly rather than leaving that to process exit.
  -- On some network filesystems (seen with Linux CIFS), the implicit close at exit
  -- of a multithreaded program can be interrupted, losing the unflushed part of the output.
  tofile <- hIsSeekable stdout
  when tofile $ hClose stdout
