{-# LANGUAGE CPP             #-}
{-
Version number-related utilities. See also the Makefile.
-}

module Hledger.Cli.Version (
  PackageVersionString,
  Version,
  nullversion,
  toVersion,
  showVersion,
  isReleaseVersion,
  HledgerVersionString,
  HledgerBinaryInfo(..),
  nullbinaryinfo,
  ProgramName,
  GitHash,
  ArchName,
  parseHledgerVersion,
  packageversion,
  packagemajorversion,
  docVersion,
  webManualUrl,
  versionStringWith,
)
where

import GitHash (GitInfo, giHash, giCommitDate)  -- giDirty
import System.Info (os, arch)
import Data.Char (toLower)
import Data.List (intercalate)
import Data.List.NonEmpty (NonEmpty ((:|)), nonEmpty, toList)
import Data.List.Split (splitOn)
import Data.Maybe
import Text.Read (readMaybe)

import Hledger.Utils (ghcDebugSupportedInLib, splitAtElement, rstrip)
import Data.Time (Day)
import Text.Megaparsec
import Data.Void (Void)
import Text.Megaparsec.Char
import Text.Megaparsec.Char.Lexer qualified as L
import Hledger.Data.Dates (parsedate)
import Data.Bifunctor
import Data.List.NonEmpty qualified as NE


-- | A Cabal/Hackage-compatible package version string: one or more dot-separated integers.
type PackageVersionString = String

-- | The number parts parsed from a PackageVersionString.
type Version = NonEmpty Int

nullversion = NE.fromList [0]

showVersion :: Version -> String
showVersion = intercalate "." . map show . toList

-- | Parse a valid Cabal/Hackage-compatible package version.
toVersion :: PackageVersionString -> Maybe Version
toVersion s =
  let parts = map readMaybe $ splitOn "." s :: [Maybe Int]
  in
    if null parts || any isNothing parts
    then Nothing
    else nonEmpty $ catMaybes parts

isReleaseVersion :: Version -> Bool
isReleaseVersion v = NE.last v < 98   -- .99 and possibly .98 are dev

-- | A hledger version string, as shown by hledger --version.
-- This can vary; some examples:
--
-- * dev builds:     hledger 1.42.99-g2288f5193-20250422, mac-aarch64
--
-- * release builds: hledger 1.42.1, mac-aarch64
--
-- * older versions: hledger 1.21
type HledgerVersionString = String

-- | The program name from a hledger version string: hledger, hledger-ui, hledger-web..
type ProgramName = String

-- | The operating system name from a hledger version string.
-- This the value of @System.Info.os@ modified for readability:
-- mac, windows, linux, linux-android, freebsd, netbsd, openbsd..
type OsName = String

-- | The machine architecture from a hledger version string.
-- This is the value of @System.Info.arch@, eg:
-- aarch64, alpha, arm, hppa, hppa1_1, i386, ia64, loongarch32, loongarch64, m68k,
-- mips, mipseb, mipsel, nios2, powerpc, powerpc64, powerpc64le, riscv32, riscv64,
-- rs6000, s390, s390x, sh4, sparc, sparc64, vax, x86_64..
type ArchName = String

-- | The git hash from a hledger version string, excluding the g prefix.
type GitHash = String

-- | The name and package version of a hledger binary,
-- and the build's git hash, the release date, and the binary's 
-- intended operating machine and machine architecture, if we can detect these.
-- Also, a copy of the --version output from which it was parsed.
data HledgerBinaryInfo = HledgerBinaryInfo {
    hbinVersionOutput     :: String
  , hbinProgramName       :: ProgramName
  , hbinPackageVersion    :: Version 
  , hbinPackageVersionStr :: String
  , hbinGitHash           :: Maybe GitHash
  , hbinReleaseDate       :: Maybe Day
  , hbinOs                :: Maybe OsName
  , hbinArch              :: Maybe ArchName
} deriving (Show, Eq)

nullbinaryinfo = HledgerBinaryInfo {
    hbinVersionOutput     = ""
  , hbinProgramName       = ""
  , hbinPackageVersion    = nullversion
  , hbinPackageVersionStr = ""
  , hbinGitHash           = Nothing
  , hbinReleaseDate       = Nothing
  , hbinOs                = Nothing
  , hbinArch              = Nothing
}

type Parser = Parsec Void String

-- | Parse hledger's --version output.
--
-- >>> isRight $ parseHledgerVersion "hledger 1.21"
-- True
-- >>> isRight $ parseHledgerVersion "hledger 1.42.1, mac-aarch64"
-- True
-- >>> isRight $ parseHledgerVersion "hledger 1.42.99-g2288f5193-20250422, mac-aarch64"
-- True
--
parseHledgerVersion :: HledgerVersionString -> Either String HledgerBinaryInfo
parseHledgerVersion s = 
  case parse hledgerversionp "" s of
  Left err -> Left $ errorBundlePretty err
  Right v  -> Right v{hbinVersionOutput=rstrip s}

-- Parser for hledger --version output: a program name beginning with "hledger" and a package version;
-- possibly followed by a git hash and release date;
-- possibly followed by the binary's intended operating system and architecture
-- (see HledgerVersionString and versionStringWith).
-- The hbinVersionOutput field is left blank here; parseHledgerVersion sets it.
hledgerversionp :: Parser HledgerBinaryInfo
hledgerversionp = do
  progName <- (<>) <$> string "hledger" <*> many (letterChar <|> char '-')
  some $ char ' '
  pkgversion <- packageversionp
  mgithash <- optional $ try $ string "-g" *> some hexDigitChar
  mreldate <- optional $ do
    string "-"
    datestr <- (:) <$> digitChar <*> some (digitChar <|> char '-')
    maybe (fail "invalid date") pure $ parsedate $ datestr
  -- Oh oh. hledger --version prints OS-ARCH, but it turns out OS can contain hyphens (eg linux-android).
  -- Based on the "common values" in System.Info docs, it seems ARCH typically does not contain hyphens;
  -- we'll assume that here, and split at the rightmost hyphen.
  mosarch <- optional $ do
    string ","
    some (char ' ')
    some (letterChar <|> digitChar <|> char '-' <|> char '_')
  let
    (march, mos) = case mosarch of
      Nothing -> (Nothing, Nothing)
      Just osarch -> bimap (Just . reverse) (Just . reverse) $ second (drop 1) $ break (== '-') $ reverse osarch
  many spaceChar
  eof
  return $ HledgerBinaryInfo
    { hbinVersionOutput = ""
    , hbinProgramName = progName
    , hbinPackageVersion = pkgversion
    , hbinPackageVersionStr = showVersion pkgversion
    , hbinGitHash = mgithash
    , hbinReleaseDate = mreldate
    , hbinOs = mos
    , hbinArch = march
    }

-- | Parser for Cabal package version numbers, one or more dot-separated integers. Eg "1.42.1".
packageversionp :: Parser Version
packageversionp = do
  firstNum <- L.decimal
  rest <- many (char '.' *> L.decimal)
  return $ firstNum :| rest

-- | The VERSION string defined with -D in this package's package.yaml/.cabal file 
-- (by Shake setversion), if any. Normally a dotted number string with 1-3 components.
packageversion :: PackageVersionString
packageversion =
#ifdef VERSION
  VERSION
#else
  ""
#endif

-- | Just the first 1-2 components of packageversion.
packagemajorversion :: PackageVersionString
packagemajorversion = intercalate "." $ take 2 $ splitAtElement '.' packageversion

-- | The hledger.org path segment for this build's online manuals:
-- the major.minor version for a release build, or "dev" for a dev build
-- (one whose package version is newer than the latest release, ie ends in .98/.99).
docVersion :: String
docVersion = case toVersion packageversion of
  Just v | isReleaseVersion v -> packagemajorversion
  _                           -> "dev"

-- | The URL of the given hledger tool's manual on hledger.org, for this build's
-- version (see 'docVersion'), optionally at a section anchor derived from a
-- heading (lower-cased, with spaces replaced by hyphens).
-- The program name should be hledger, hledger-ui or hledger-web.
webManualUrl :: ProgramName -> Maybe String -> String
webManualUrl prog mheading =
  "https://hledger.org/" <> docVersion <> "/" <> prog <> ".html"
    <> maybe "" (("#"<>) . headingAnchor) mheading
  where headingAnchor = map (\c -> if c==' ' then '-' else toLower c)

-- | Given possible git state info from the build directory (or a git error, which is ignored),
-- and the debug build flag, executable name and package version for the package being built,
-- make the best version string we can. Here is the logic:
-- 
-- * Program name, OS and architecture are always shown.
-- * The package version is always shown.
-- * If there is git info at build time, the latest commit hash and commit date are shown,
--   and (TODO, requires githash to use -uno for giDirty):
--   if the working copy has uncommitted changes a + sign is appended.
-- * (TODO, requires adding --match support to githash:
--   If there are tags matching THISPKG-[0-9]*, the latest one is used to calculate patch level
--   (number of commits since tag), and if non-zero, it and the branch name are shown.)
-- * If the debug build flag was enabled for the package being built, and for hledger-lib (both are needed),
--   "ghc-debug support" is shown.
--
-- Some example outputs:
--
-- * A homebrew binary, not built in git repo:             hledger-ui 1.24, mac-aarch64
-- * A CI release build, built in git repo at release tag: hledger-ui 1.24.1-g455b35293-20211210, mac-x86_64
-- * (TODO) A dev build, built in git repo:                hledger-ui 1.24.1+1-g4abd8ef10-20211210 (1.24-branch), mac-x86_64
--
-- This function requires git log to show the default (rfc2822-style) date format,
-- so that must not be overridden by a log.date git config variable.
--
-- The GitInfo if any, fetched by template haskell, is passed down from
-- a top-level module, reducing wasteful recompilation.
-- The status of the debug build flag is also passed down, since it is
-- specific to each hledger package.
--
-- This is used indirectly by at least hledger, hledger-ui, and hledger-web,
-- so output should be suitable for all of those.
--
versionStringWith :: Either String GitInfo -> Bool -> ProgramName -> PackageVersionString -> HledgerVersionString
versionStringWith egitinfo ghcDebugSupportedInThisPackage progname packagever =
  concat $
    [ progname , " " , version , ", " , os' , "-" , arch ]
    ++ [ " with ghc-debug support" | ghcDebugSupportedInThisPackage && ghcDebugSupportedInLib ]
  where
    os' | os == "darwin"  = "mac"
        | os == "mingw32" = "windows"
        | otherwise       = os
    version = case egitinfo of
      Left _err     -> packagever
      Right gitinfo -> 
        case words $ giCommitDate gitinfo of
          -- git log's date format is normally --date=default ("similar to --date=rfc2822")
          _weekday:mon:day:_localtime:year:_offset:_ ->
            intercalate "-" $ [packagever, hash, date]
              -- ++ ["+" | giDirty gitinfo]
              --   XXX giDirty is wrong when repo shows untracked files by default, skip it for now
              where
                hash = 'g' : take 9 (giHash gitinfo)  -- like git describe
                date = concat [year,mm,dd]
                  where 
                    mm = fromMaybe mon $ lookup mon $ [
                      ("Jan","01")
                      ,("Feb","02")
                      ,("Mar","03")
                      ,("Apr","04")
                      ,("May","05")
                      ,("Jun","06")
                      ,("Jul","07")
                      ,("Aug","08")
                      ,("Sep","09")
                      ,("Oct","10")
                      ,("Nov","11")
                      ,("Dec","12")
                      ]
                    dd = (if length day < 2 then ('0':) else id) day
          -- but could be overridden by a log.date config variable in repo or user git config
          _ -> packageversion
