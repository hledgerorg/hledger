#!/usr/bin/env stack
{- stack --resolver=nightly-2026-06-01 script --compile --verbosity=error
   --package "bytestring cassava gogol gogol-core gogol-sheets lens pretty-show text"
-}
-- or
#!/usr/bin/env cabal
{- cabal:
build-depends: aeson<1.6, bytestring, cassava, gogol, gogol-core, gogol-sheets, lens, pretty-show, text
-}

-- In 2023-02, this is hard to build; gogol is unmaintained and requires old aeson < 1.6,
-- which requires old bytestring which requires old GHC (8.10 or 9.0).
-- On modern macs these GHCs are difficult to run. This build most deps for me:
-- brew install llvm@12
-- ghcup set ghc 9.0.2
-- PATH=/opt/homebrew/opt/llvm@12/bin:$PATH CPATH=/Library/Developer/CommandLineTools/SDKs/MacOSX13.1.sdk/usr/include/ffi cabal build gsheet-csv.hs
-- but failed on cryptonite with  "error: instruction requires: sha3", an llvm 12 on arm bug

{-
gsheet-csv - download the CSV of a Google Sheet you have access to

INSTALL:
Get stack if needed, eg from https://haskell-lang.org/get-started
Run "./gsheet-csv.hs" once to compile. On Windows, run "stack gsheet-csv.hs".

SETUP:
Set up an account at https://console.developers.google.com/iam-admin/serviceaccounts, selecting or creating a project
Save the service account's email address
Create a key and download as json to ~/.config/gcloud/KEYFILE.json
Symlink this to ~/.config/gcloud/application_default_credentials.json
Share spreadsheets with the service account's email address

USAGE:
gsheet-csv SPREADSHEETID SHEETNAME  - print specified sheet as CSV

-}

{-# LANGUAGE PackageImports #-}

module Main
where
import "lens" Control.Lens
import "bytestring" qualified Data.ByteString.Lazy as B
import "cassava" Data.Csv
import "text" qualified Data.Text as T
import "gogol" Network.Google
import "gogol-sheets" Network.Google.Sheets
import "base" System.Environment
import "base" System.IO
-- import "base" Debug.Trace
-- import "pretty-show" Text.Show.Pretty  (pPrint, ppShow)

main = do
  [spreadsheetId, sheetName] <- map T.pack <$> getArgs
  let range = sheetName -- ++"!A1:J10"
  lgr <- newLogger Info stdout
  env <- newEnv <&> (envLogger .~ lgr) . (envScopes .~ spreadsheetsReadOnlyScope)
  values <- view vrValues <$> (runResourceT . runGoogle env $ send  (spreadsheetsValuesGet spreadsheetId range))
  B.putStr $ Data.Csv.encode $ map (map bs) values
    where bs = drop 8 . init . show -- no more time for hilariously craptastic haskell libs


------------------------------
-- notes

-- import Data.Aeson
-- import Data.Text (Text)
-- import Network.Google.Data.JSON
-- import Network.Google.Resource.Sheets.Spreadsheets.Get


{-
TODO:
gsheet-csv [-h]                          - show help
gsheet-csv SPREADSHEETID                 - get first sheet
gsheet-csv SPREADSHEETID SHEETNAME RANGE - get just the specified cells

-}

{-
Notes for developers of stack (1.9.1) scripts:

1. In the stack header above, flags' position and style are critical.
Minor variations cause very different behaviour.

2. For different run actions, adjust the stack command:
script --optimize  - run compiled, after compiling if needed
script --compile   - run compiled, after compiling if needed (without optimisation)
script             - run interpreted (slower)
exec runghc        - run interpreted using ambient GHC package db
exec ghc           - compile
exec ghci          - load in GHCI
exec ghcid         - watch for compile errors

3. To silence "Using resolver:" output (but also deps install output), change --verbosity to warn

4. Declare which package each import is from, keep synced with --package; might as well be clear

5. Doc: https://docs.haskellstack.org/en/stable/topics/scripts

-}
