#!/usr/bin/env stack
{- stack script --resolver nightly-2026-06-01 --compile
   --extra-include-dirs /Library/Developer/CommandLineTools/SDKs/MacOSX12.1.sdk/usr/include/ffi
   --extra-dep shake-0.19.9
   --package base-prelude
   --package directory
   --package extra
   --package process
   --package regex
   --package safe
   --package shake
   --package time
-}
{-
-- add this to see packages being installed instead of a long silence:
   --verbosity=info

Heavy project scripts, with file dependencies, using https://shakebuild.com.
See also justfile, Makefile.
Also uses tools like:
- hpack (same version that's in current stack release)
- GNU date (on mac, get it with brew install coreutils)
- pandoc, groff, m4, makeinfo, sed, mv, cat, rm

Some things that may be useful when working on this:
- https://docs.haskellstack.org/en/stable/topics/scripts
- watch Shake.hs for compile errors: make ghcid-shake
- load Shake.hs in GHCI: make ghci-shake
- rebuild things when files change with entr (file watcher), eg:
   find hledger-lib hledger | entr ./Shake manuals
- view rule dependency graph:
   ./Shake --report, open report.html?mode=rule-graph&query=!name(/(doc%7Cimages%7Cjs%7Ccss%7Cfonts%7Ctime%7Capi%7Cui%7Ccsv)/)

-}

{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE PackageImports #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE ScopedTypeVariables #-}

import                Prelude ()
import "base-prelude" BasePrelude
import "base"         Control.Exception as C
-- required packages, keep synced with Makefile -> SHAKEDEPS:
import "directory"    System.Directory as S (getDirectoryContents)
import "extra"        Data.List.Extra hiding (headDef, lastDef)
import "regex"        Text.RE.TDFA.String
import "regex"        Text.RE.Replace
import "safe"         Safe
import "shake"        Development.Shake
import "shake"        Development.Shake.FilePath
import "time"         Data.Time
-- import Debug.Trace
-- import "hledger-lib"  Hledger.Utils.Debug

usage =
  let scriptname = "Shake" in replaceRe [re|/Shake|] ('/':scriptname) $
  unlines
    ---------------------------------------79--------------------------------------
  ["Shake: for heavier project scripting. See also Justfile"
  ,"Usage:"
  ,"./Shake.hs [CMD [ARGS]]  run CMD, compiling this script first if needed"
  ,"./Shake    [CMD [ARGS]]  run CMD, using the compiled version of this script"
  ,"./Shake [help]           show this help"
  ,"./Shake cabalfiles [-c]  update */*.cabal files from */package.yaml"
  ,"./Shake setversion [VER] [PKGS] [-c]"
  ,"                         update versions in source files to */.version or VER"
  ,"                         and update */*.cabal files"
  ,"./Shake hledger-install-version    update some version strs in hledger-install"
  ,"./Shake cmddocs [-c]     update all hledger's COMMAND.md and COMMAND.txt files,"
  ,"                         used for --help, manuals etc. (run after changing"
  ,"                         COMMAND.md or command options or general options)"
  ,"./Shake manuals [-c]     update the packages' embedded info/man/txt manuals"
  ,"./Shake changelogs [-c] [-n/--dry-run]"
  ,"./Shake changelogs-check check changelogs for stale resume point, bad issue"
  ,"                         links, leftover draft markers"
  ,"                         update CHANGES.md files, adding new commits & headings"
  ,"./Shake docs [-c]        update all program docs (CLI help, manuals, changelogs)"
  ,"./Shake site             update (render) the website, in ./site"
  ,"./Shake build [PKGS]     build hledger packages and their embedded docs"
  ,"./Shake clean            remove generated texts, manuals"
  ,"./Shake Clean            also remove object files, Shake's cache"
  ,"./Shake FILE             build any individual file"
  ,"./Shake --help           list shake build options (--color, --rebuild, etc."
  ,"                         Keep shake option arguments adjacent to their flag.)"
  ,""
  ,"See comments in Shake.hs for more detailed descriptions."
  ,"Add -c/--commit to have commands commit their changes."
  ,"Add -B (on its own) to force rebuilding."
  ,"Add -V/-VV/-VVV/-VVVV to see more verbose output."
  ,"Add --skip-commands to try to avoid running external commands"
  ,"(not a true dry run; some cmd calls may still run, code may do IO, etc)."
  ]
-- TODO
--  ,"./Shake releasebranch      create a new release branch, bump main to next dev version (.99)" 
--  ,"./Shake majorversion       bump to the next major version project-wide, update affected files"
--  ,"./Shake minorversion PKGS  bump one or more packages to their next minor version project-wide, update affected files"
--  ,"./Shake relnotes           create draft release notes"

-- groff    = "groff -c" ++ " -Wall"  -- see "groff" below
m4 = "m4 -P"
makeinfo = "makeinfo -cASCII_PUNCTUATION=1 --no-split --force --no-warn --no-validate"  -- silence makeinfo warnings, comment these to see them
pandoc   = "pandoc --strip-comments"

-- We should work with both BSD and GNU sed. Tips:
-- use [a-z] [0-9] instead of \w \d etc.
-- backslash-escape things like: { &
sed = "sed -E"

-- We should work with both BSD and GNU grep.
grep = "grep -E"

-- The kind of markdown used in our doc source files.
-- Note: without +hard_line_breaks here, paragraphs get refilled,
-- which is good for nice rendered info/man/text output, but so do
-- multiline arguments to m4 macros, which is bad eg when using
-- _info_ to add Info directives (cf #806). For such situations we
-- work around by calling the macro for each line of text, it
-- would be nice to find a way to avoid this.
fromsrcmd = "-f markdown-smart-tex_math_dollars"

-- The kind of org markup used in any org source files.
-- In pandoc 2.14, org reader enables smart dashes by default;
-- use #+OPTIONS: -:nil in the org file to disable it (-smart here has no effect).
-- We also write to markdown+strict, which would undo any smart dashes or quotes).
fromorg = "-f org-smart"

-- The kind of markdown we like to generate for the website.
--
-- This was configured for sphinx+recommonmark+sphinx-markdown-tables; it could be reviewed now that we use mdbook.
-- Trying to force the use of pipe_tables here, but sometimes it uses html instead.
--
-- --markdown-headings=atx requires pandoc 2.11.2+; with older pandoc use --atx-headers instead.
--
-- In pandoc 2.14, "If you are writing Markdown, then the smart extension has the 
-- reverse effect: what would have been curly quotes comes out straight.".
-- So +smart here can fix unwanted smart typography that may have crept in,
-- eg from org docs (see above).
--
towebmd = "-t markdown+smart-fenced_divs-fenced_code_attributes-simple_tables-multiline_tables-grid_tables-raw_attribute --markdown-headings=atx"


main = do

  -- Gather some IO values used by rules.

  -- hledger manual also includes the markdown files from here:
  let commandsdir = "hledger/Hledger/Cli/Commands"
  commandmds <-
    sort . filter (not . ("README." `isPrefixOf`) . takeFileName) . filter (".md" `isSuffixOf`) . map (commandsdir </>)
    <$> S.getDirectoryContents commandsdir
  let
    commandmdsnew = map (<.> "new") commandmds
    commandtxts = map (-<.> "txt") commandmds

  -- Run the shake rule selected by the first command line argument.
  -- Other arguments and some custom flags are set aside for the rule
  -- to use if it wants.

  -- Option arguments should be kept adjacent to their flag or this will go wrong.
  (opts, args) <- partition ("-" `isPrefixOf`) <$> getArgs
  let
    ruleoptnames = [
       "--commit", "-c"
      ,"--dry-run", "--dry", "-n"
      ]
    (ruleopts, shakeopts) = partition (`elem` ruleoptnames) opts
    commit = any (`elem` ruleopts) ["--commit", "-c"]
    dryrun = any (`elem` ruleopts) ["--dry-run", "--dry", "-n"]
    (shakearg, ruleargs) = splitAt 1 args
    shakeargs = shakeopts ++ shakearg
  -- print (opts,args,shakeopts,shakearg,shakeargs,ruleopts,ruleargs)

  withArgs shakeargs $ shakeArgs shakeOptions{
    shakeVerbosity=Quiet
    -- ,shakeReport=[".shake.html"]
    }
    $ do
   
  -- The rules.
  
      want ["help"]

      phony "help" $ liftIO $ putStr usage

      -- NAMES, FILES, URIS, HELPERS

      let
        -- main package names, in standard build order
        packages = [
           "hledger-lib"
          ,"hledger"
          ,"hledger-ui"
          ,"hledger-web"
          ]
        pkgdirs = packages
        pkgandprojdirs = "" : pkgdirs
        cabalfiles = [p </> p <.> "cabal" | p <- packages]
        changelogs = map (</> "CHANGES.md") pkgdirs ++ ["doc/CHANGES.md"]
        packagemanversionm4s = [p </> ".version.m4" | p <- packages]
        packagemandatem4s = [p </> ".date.m4" | p <- packages]

        -- doc files (or related targets) that should be generated
        -- before building hledger packages.
        -- [(PKG, [TARGETS])]
        embeddedFiles = [
           -- hledger embeds the plain text command help files and all packages' text/nroff/info manuals
           ("hledger", commandtxts ++ ["manuals"])
           -- hledger-ui imports the hledger-ui manuals from hledger
          ,("hledger-ui", ["hledger"])
          ]

        -- man page names (manual names plus a man section number), in suggested reading order
        manpageNames = [
           "hledger.1"
          ,"hledger-ui.1"
          ,"hledger-web.1"
          ]

        -- basic manual names, without numbers
        manualNames = map manpageNameToManualName manpageNames

        -- main markdown+m4 source files for manuals (hledger/hledger.m4.md)
        -- These may include additional files using m4.
        m4manuals = [manualDir m </> m <.> "m4.md" | m <- manualNames]

        -- manuals as plain text, ready for embedding as CLI help (hledger/hledger.txt)
        txtmanuals = [manualDir m </> m <.> "txt" | m <- manualNames]

        -- manuals as nroff, ready for man (hledger/hledger.1)
        nroffmanuals = [manpageDir m </> m | m <- manpageNames]

        -- manuals as info, ready for info (hledger/hledger.info)
        infomanuals = [manualDir m </> m <.> "info" | m <- manualNames]
        -- an Info directory entry for each package's info manual (hledger/dir-entry.texi)
        infodirentries = [manualDir m </> "dir-entry.texi" | m <- manualNames]
        -- a generated Info directory file for easily accessing/linking the dev version of all the info manuals
        -- infodir = "dir"

        -- manuals as sphinx-ready markdown, to be rendered as part of the website (hledger/hledger.md)
        webmanuals = [manualDir m </> m <.> "md" | m <- manualNames]

        -- -- old versions of the manuals rendered to html (site/_site/doc/1.14/hledger.html)
        -- oldhtmlmanuals = map (normalise . ("site/_site/doc" </>) . (<.> "html")) $
        --   [ v </> manpageNameToWebManualName p | v <- docversions, v>="1.0", p <- manpageNames ++ ["manual"] ] ++
        --   [ v </> "manual"           | v <- docversions, v <"1.0" ]  -- before 1.0 there was only the combined manual

        -- The directory in which to find this man page.
        -- hledger.1 -> hledger/doc, hledger_journal.5 -> hledger-lib/doc
        manpageDir m
          | '_' `elem` m = "hledger-lib"
          | otherwise    = dropExtension m

        -- The directory in which to find this manual.
        -- hledger -> hledger, hledger_journal -> hledger-lib
        manualDir m
          | '_' `elem` m = "hledger-lib"
          | otherwise    = m

        -- The web manual name (& URI "slug") corresponding to this man page.
        -- hledger.1 -> hledger, hledger_journal.5 -> journal
        manpageNameToWebManualName m | "hledger_" `isPrefixOf` m = dropExtension $ drop 8 m
                                     | otherwise                 = dropExtension m

        -- The man page corresponding to this web manual name.
        -- hledger -> hledger.1, journal -> hledger_journal.5
        webManualNameToManpageName u | "hledger" `isPrefixOf` u = u <.> "1"
                                     | otherwise                = "hledger_" ++ u <.> "5"

      -- VERSION NUMBERS

      -- Regenerate .cabal files from package.yaml files.
      -- (used by "cabalfiles" and "setversion")
      -- XXX should remove old cabal files first, otherwise fails if they were generated with newer hpack
      let gencabalfiles = do

            -- Update cabal files with stack build.
            -- stack 1.7+ no longer updates cabal files with --dry-run, we must do a full build.
            -- stack can return zero exit code while failing to update cabal files so
            -- we need to check for the error message (specifically) on stderr.
            -- out <- fromStdouterr <$>  -- (getting both stdout and stderr here just as an example)
            --   (cmd (EchoStdout True) (EchoStderr True) Shell "stack build" :: Action (Stdouterr String))
            -- when ("was generated with a newer version of hpack" `isInfixOf` out) $
            --   liftIO $ putStr out >> exitFailure

            -- Or update them with hpack directly.
            -- It should be the same hpack version that's in current stack, to avoid commit conflicts.
            forM_ pkgdirs $ \d -> cmd_ (Cwd d) Shell "hpack --no-hash"

            when commit $ commitIfChanged ";cabal: update cabal files" cabalfiles

      -- setversion [VER] [PKGS] [-c]
      -- Update version strings in all packages, or just the ones specified.
      -- If a version number is provided as first argument, save that in .version files first.
      -- Then update various source files to match what's in their nearby .version file, such as:
      -- package.yaml files, .cabal files (regenerating from package.yaml), .version.m4 files.
      -- With -c, also commit the changes.
      -- See also CONTRIBUTING.md > Version numbers.
      phony "setversion" $ do
        let
          (mver, dirargs) = (headMay ver', drop 1 ver' ++ dirs')
            where (ver',dirs') = span isVersion ruleargs
          (specifieddirs, specifiedpkgs) =
            case dirargs of [] -> (pkgandprojdirs, pkgdirs)
                            ds -> (ds, ds)
        -- if a version was provided, update .version files in the specified directories
        let specifiedversionfiles = map (</> ".version") specifieddirs
        case mver of
          Just v  -> liftIO $ forM_ specifiedversionfiles $ flip maybeWriteFile (v++"\n")
          Nothing -> return ()

        -- update source files depending on .version in the specified packages
        let dependents = map (</> ".version.m4")  specifiedpkgs
                      ++ map (</> "package.yaml") specifiedpkgs
        need dependents

        -- and maybe commit them
        when commit $ do
          let msg = unwords [
                 ";pkg: set"
                ,case dirargs of
                   [] -> "version"
                   ds -> intercalate ", " ds ++ " version"
                ,case mver of
                   Nothing -> ""
                   Just v  -> "to " ++ v
                ]
          commitIfChanged msg $ specifiedversionfiles ++ dependents

        gencabalfiles

      -- Update some of the version strings in hledger-install/hledger-install.sh. Manual fixup will be needed.
      -- Not done by setversion since that is used on main, where the production hledger-install is.
      phony "hledger-install-version" $ do
        let versionfile = ".version"
        let out = "hledger-install/hledger-install.sh"
        version <- ((headDef (error $ "failed to read " <> versionfile) . words) <$>) $ liftIO $ readFile versionfile
        cmd_ Shell sed "-i -e" ("'s/(^HLEDGER_INSTALL_VERSION)=.*/\\1='`date +%Y%m%d`'/'") out
        cmd_ Shell sed "-i -e" ("'s/(^HLEDGER(|_LIB|_UI|_WEB)_VERSION)=.*/\\1="++version++"/'") out

      -- PKG/.version.m4 <- PKG/.version, just updates the _version_ macro
      "hledger*/.version.m4" %> \out -> do
        let versionfile = takeDirectory out </> ".version"
        need [versionfile]
        version <- ((headDef (error $ "failed to read " <> versionfile) . words) <$>) $ liftIO $ readFile versionfile
        cmd_ Shell sed "-i -e" ("'s/(_version_}}, *)\\{\\{[^}]+/\\1{{"++version++"/;'") out

      -- PKG/package.yaml <- PKG/.version, just updates version strings
      "hledger*/package.yaml" %> \out -> do
        let versionfile = takeDirectory out </> ".version"
        need [versionfile]
        version <- ((headDef (error $ "failed to read " <> versionfile) . words) <$>) $ liftIO $ readFile versionfile
        let ma:jor:_ = splitOn "." version
            nextmajorversion = intercalate "." [ma, show $ read jor+1]

        -- One simple task: update some strings in a small text file.
        -- Several ugly solutions:
        --
        -- 1. use haskell list utils. Tedious.
        -- old <- liftIO $ readFileStrictly out
        -- let isversionline s = "version" `isPrefixOf` (dropWhile isSpace $ takeWhile (not.(`elem` " :")) s)
        --     (before, _:after) = break isversionline $ lines old
        --     -- oldversion = words versionline !! 1
        --     new = unlines $ before ++ ["version: "++version] ++ after
        -- liftIO $ writeFile out new
        --
        -- 2. use regular expressions in haskell. Haskell has no portable,
        -- featureful, replacing, backreference-supporting regex lib yet.
        --
        -- 3. use sed. Have to assume non-GNU sed, eg on mac.

        -- Things to update in package.yaml:
        --
        --  version: VER
        cmd_ Shell sed "-i -e" ("'s/(^version *:).*/\\1 "++version++"/'") out
        --
        --  -DVERSION="VER"
        cmd_ Shell sed "-i -e" ("'s/(-DVERSION=)\"[^\"]+/\\1\""++version++"/'") out
        --
        --  this package's dependencies on other hledger packages (typically hledger-lib, hledger)
        --
        --  This one is a bit tricky, and we do it with these limitations:
        --  a. We handle bounds in one of these forms (allowing extra whitespace):
        --     ==A
        --     >A
        --     >=A
        --     >A && <B
        --     >=A && <B
        --  b. We set
        --     the new lower bound to:         this package's new version, V
        --     the new upper bound if any, to: the next major version after V
        --     both of which may not be what's desired.
        --  c. We convert > bounds to >= bounds.
        --
        --  hledger[-PKG] ==LOWER
        let versionre = "([0-9]+\\.)*[0-9]+"  -- 2 or 3 part version number regexp
        cmd_ Shell sed "-i -e" ("'s/(hledger(-[a-z]+)?) *== *"++versionre++" *$/\\1 == "++version++"/'") out
        --
        --  hledger[-PKG] >[=]LOWER
        cmd_ Shell sed "-i -e" ("'s/(hledger(-[a-z]+)?) *>=? *"++versionre++" *$/\\1 >= "++version++"/'") out
        --
        --  hledger[-PKG] >[=]LOWER && <UPPER
        let
          pat = "(hledger(-[a-z]+)?) *>=? *"++versionre++" *&& *< *"++versionre++" *$"
          rpl = "\\1 >="++version++" \\&\\& <"++nextmajorversion -- This was a beast. These ampersands must be backslash-escaped.
          arg = "'s/"++pat++"/"++rpl++"/'"
        cmd_ Shell sed "-i -e" arg out

        let pkg = takeDirectory out
        when (pkg /= "hledger-lib") $ liftIO $ do
          putStrLn $ out++": hledger bounds are (improve if needed):"
          cmd_ Shell grep "'^ *- +hledger.*[<>=]'" out 
            " || [[ $? == 1 ]]"  -- ignore no matches, https://unix.stackexchange.com/a/427598

      phony "cabalfiles" $ gencabalfiles

      -- MANUALS

      -- Generate the manuals in plain text, nroff, info, and markdown formats.
      -- NB you should run "Shake cmddocs" before this, it's not automatic (?)
      phony "manuals" $ do
        need $ concat [
               ["mandates"]
              ,nroffmanuals
              ,infomanuals
              -- ,[infodir]
              ,txtmanuals
              ,webmanuals
              ]
        when commit $
          commitIfChanged ";doc: update embedded manuals" $
            concat [commandmds, packagemandatem4s, nroffmanuals, infomanuals, infodirentries, txtmanuals]  -- infodir

      -- Update the dates to show in man pages, to the current month and year.
      -- Dates are stored in PKG/.date.m4, and are committed along with manuals by Shake manuals -c.
      phony "mandates" $ do
        date <- chomp . fromStdout <$> (cmd Shell "date +'%B %Y'" :: Action (Stdout String))
        forM_ packagemandatem4s $ \f -> do
          cmd_ Shell ["perl","-pi","-e","'s/(.*)\\{\\{.*}}(.*)$/\\1\\{\\{"++date++"}}\\2/'",f]

      -- Generate nroff man pages suitable for man output, from the .m4.md source.
      -- Also updates the _monthyear_ macro to current month and year in hledger*/.date.m4.
      phony "nroffmanuals" $ need nroffmanuals
      nroffmanuals |%> \out -> do -- hledger/hledger.1
        let src       = manpageNameToManualName out <.> "m4.md"
            commonm4  = "doc/common.m4"
            commandsm4 = "hledger/Hledger/Cli/Commands/commands.m4"
            dir       = takeDirectory out
            pkg       = dir
            packagemanversionm4 = dir </> ".version.m4"
            packagemandatem4 = dir </> ".date.m4"
            tmpl      = "doc/manpage.nroff"
        pkgversion <- liftIO $ readFile $ dir </> ".version"
        -- mandate <- formatTime defaultTimeLocale "%B %Y" <$> liftIO getCurrentDay  -- XXX not using this.. compare with .date.m4
        -- assume any other .m4.md files in dir are included by this one XXX not true in hledger-lib
        subfiles <- liftIO $ filter (/= src) . filter (".m4.md" `isSuffixOf`) . map (dir </>) <$> S.getDirectoryContents dir
        need $ [src, commonm4, commandsm4, packagemanversionm4, packagemandatem4, tmpl] ++ subfiles
        when (dir=="hledger") $ need commandmds
        cmd Shell
          m4 "-DMANFORMAT -I" dir commonm4 commandsm4 packagemanversionm4 packagemandatem4 src "|"
          pandoc fromsrcmd "-s" "--template" tmpl
          ("-V footer='"++pkg++"-"++pkgversion++"'")
          "--lua-filter tools/pandoc-drop-html-blocks.lua"
          "--lua-filter tools/pandoc-drop-html-inlines.lua"
          "--lua-filter tools/pandoc-drop-links.lua"
          "-o" out

      -- Generate plain text manuals suitable for embedding in
      -- executables and viewing with a pager, from the man pages.
      -- (Depends on the nroffmanuals.)
      phony "txtmanuals" $ need txtmanuals
      txtmanuals |%> \out -> do  -- hledger/hledger.txt
        let src = manualNameToManpageName $ dropExtension out
        need [src]
        -- cmd Shell groff "-t -e -mandoc -Tascii" src  "| col -b >" out -- http://www.tldp.org/HOWTO/Man-Page/q10.html
        -- Workaround: groff 1.22.4 always calls grotty in a way that adds ANSI/SGR escape codes.
        -- (groff -c is supposed to switch those to backspaces, which we could
        -- remove with col -b, but it doesn't as can be seen with groff -V.)
        -- To get plain text, we run groff's lower-level commands (from -V) and add -cbuo.
        -- -Wall silences most troff warnings, remove to see them
        -- XXX eqn complains on nonascii chars, not needed ?
        -- cmd Shell "tbl" src "| eqn -Tascii | troff -Wall -mandoc -Tascii | grotty -cbuo >" out
        -- XXX how to silence wide table warnings (generated by tbl, reported by troff) ?
        cmd Shell "tbl" src "| troff -Wall -mandoc -Tascii | grotty -cbuo >" out

      -- Generate Info manuals suitable for viewing with info, from the .m4.md source.
      infomanuals |%> \out -> do -- hledger/hledger.info
        let src       = out -<.> "m4.md"
            commonm4  = "doc/common.m4"
            commandsm4 = "hledger/Hledger/Cli/Commands/commands.m4"
            dir       = takeDirectory out
            packagemanversionm4 = dir </> ".version.m4"
            packagemandatem4 = dir </> ".date.m4"
            direntry = dir </> "dir-entry.texi"
        -- assume any other .m4.md files in dir are included by this one XXX not true in hledger-lib
        subfiles <- liftIO $ filter (/= src) . filter (".m4.md" `isSuffixOf`) . map (dir </>) <$> S.getDirectoryContents dir
        need $ [src, commonm4, commandsm4, packagemanversionm4, packagemandatem4, direntry] ++ subfiles
        when (dir=="hledger") $ need commandmds
        cmd_ Shell
          "( cat" direntry ";"
          m4 "-DINFOFORMAT -I" dir commonm4 commandsm4 packagemanversionm4 packagemandatem4 src "|"
          -- sed "-e 's/^#(#+)/\\1/'" "|"
          pandoc fromsrcmd
          "--lua-filter tools/pandoc-drop-html-blocks.lua"
          "--lua-filter tools/pandoc-drop-html-inlines.lua"
          "--lua-filter tools/pandoc-drop-links.lua"
          -- add "standalone" headers ? sounds good for setting text encoding,
          -- but messes up quotes ('a' becomes ^Xa^Y)
          -- "-s"
          "-t texinfo ) |"
          makeinfo "-o" out

      -- XXX This generates ./dir, for previewing latest dev manuals in Info's directory.
      -- For that we need subdirectory paths like "hledger: (hledger/hledger)",
      -- but this generates "hledger: (hledger)". Don't regenerate dir for now.
      --
      -- Generate an Info dir file which can be included with info -d
      -- or INFOPATH to add hledger menu items in Info's Directory.
      -- infodir %> \out -> do
      --   need infomanuals
      --   forM_ infomanuals $ \info -> cmd_ Shell "install-info" info out

      phony "infomanuals" $ need $ infomanuals  -- ++ [infodir]

      -- WEBSITE MARKDOWN SOURCE

      -- Generate the individual web manuals' markdown source, using m4
      -- and pandoc to tweak content.
      phony "webmanuals" $ need webmanuals
      webmanuals |%> \out -> do -- hledger/hledger.md, hledger/hledger-ui.md ..
        let 
            dir       = takeDirectory out -- hledger, hledger-lib
            manpage   = webManualNameToManpageName $ dropExtension $ dropExtension $ takeFileName out -- hledger, journal
            manual    = manpageNameToManualName manpage -- hledger, hledger_journal
            src       = dir </> manual <.> "m4.md"
            commonm4  = "doc/common.m4"
            commandsm4 = "hledger/Hledger/Cli/Commands/commands.m4"
            packageversionm4 = dir </> ".version.m4"
            packagemandatem4 = dir </> ".date.m4"
            heading   = let h = manual
                        in if "hledger_" `isPrefixOf` h
                           then drop 8 h ++ " format"
                           else h
        -- assume any other .m4.md files in dir are included by this one XXX not true in hledger-lib
        subfiles <- liftIO $ filter (/= src) . filter (".m4.md" `isSuffixOf`) . map (dir </>) <$> S.getDirectoryContents dir
        let deps = [src, commonm4, packageversionm4, packagemandatem4] ++ subfiles
        need deps
        when (manual=="hledger") $ need $ commandsm4 : commandmds
        -- add the web page's heading.
        -- XXX Might be nice to do this atomically with the below, so
        -- make avoid any double refresh when watch docs with entr/livereload.
        -- But cmd Shell doesn't handle arguments containing spaces properly.
        let
          aboutmsg =
            ["<!-------------------------------------------------------------------------"
            ,"Don't edit this file directly."
            ,"Instead, in the hledger repo's main branch edit the source file, one of:"
            ] <>
            [" hledger/Hledger/Cli/Commands/commands.m4" | manual=="hledger"] <>
            [" hledger/Hledger/Cli/Commands/*.md"        | manual=="hledger"] <>
            [" " <> intercalate "\n " deps
            ,""
            ,"If the change needs to be applied to past releases' manuals on hledger.org,"
            ,"see https://hledger.org/DOCS.html, or ask the maintainer to help."
            ,"-------------------------------------------------------------------------->"
            ]
        liftIO $ writeFile out $ unlines $
          aboutmsg <>
          [""
          ,"<div class=\"docversions\"></div>"
          ,""
          ,"# " ++ heading
          ,""
          ]
        cmd Shell
          m4 "-DWEBFORMAT -I" dir commonm4 commandsm4 packageversionm4 packagemandatem4 src "|"
          pandoc fromsrcmd towebmd
          "--lua-filter tools/pandoc-demote-headers.lua"
          ">>" out

      -- This rule, for updating the live hledger.org site, gets called by:
      -- 1. github-post-receive (github webhook handler), when something is pushed
      --    to the main repo on Github. Config:
      --     /etc/supervisord.conf -> [program:github-post-receive]
      --     /etc/github-post-receive.conf
      -- 2. cron, nightly. Config: /etc/crontab
      -- 3. manually (make site).
      -- phony "hledgerorg" $ do
      --   -- XXX ideally we would ensure here that output is logged in site.log,
      --   -- but I don't know how to do that for the Shake rules.
      --   -- Instead we'll do the logging in "make site".
      --   cmd_ Shell
      --
      --     -- print timestamp. On mac, use brew-installed GNU date.
      --     "PATH=\"/usr/local/opt/coreutils/libexec/gnubin:$PATH\" date --rfc-3339=seconds"
      --     -- pull latest code and site repos - sometimes already done by webhook, not always
      --     "&& printf 'code repo: ' && git pull"
      --     "&& printf 'site repo: ' && git -C site pull"
      --
      --   -- Shake.hs might have been updated, but we won't execute the
      --   -- new one, too insecure. Continue with this one.
      --
      -- Help:
      -- ,"./Shake hledgerorg       update the hledger.org website (when run on prod)"

      -- HLEDGER PACKAGES/EXECUTABLES

      -- build [PKGS]
      -- Build some or all hledger packages, after generating any doc
      -- files they embed or import.
      -- This may also update .cabal files from package.yaml files, and/or install haskell deps.
      phony "build" $ do
        let
          args' = drop 1 args
          pkgs | null args' = packages
               | otherwise = args'
        sequence_ [ do
          need $ fromMaybe [] $ lookup pkg embeddedFiles
          cmd Shell "stack build " pkg :: Action ()
          | pkg <- pkgs
          ]

      -- Using the current hledger build, run all commands to update their options help in COMMAND.md,
      -- then regenerate all the COMMAND.txt from COMMAND.md.
      -- With -c, also commit any changes in the .md and .txt files.
      -- The hledger build should up to date when running this. XXX how to check ? need ["build"] is circular
      phony "cmddocs" $ do
        liftIO $ putStrLn "please ensure the hledger build is up to date. Running all commands..."
        need commandtxts
        when commit $ commitIfChanged ";doc: update command docs" $ commandmds <> commandtxts

      -- Regenerate Hledger/Cli/Commands/*.txt from the corresponding .md files,
      -- after first updating the options help within those.
      commandtxts |%> \out -> do
        let src = out -<.> "md"
        liftIO $ putStrLn ("generating " <> out)
        need [src <.> "new"]  -- 1. depend on phony target that updates the options help in src
        need [src]            -- 2. depend on the now updated src
        cmd Shell
          pandoc fromsrcmd src "--lua-filter" "tools/pandoc-dedent-code-blocks.lua" "-t plain" ">" out

      -- -- Update each Hledger/Cli/Commands/*.md, replacing the ```flags block with latest --help output,
      -- -- or a placeholder if there are no command-specific flags.
      -- -- For hledger manual and also for cmddocs below.
      -- -- NB hledger executables should be up to date, see cmddocs
      -- phony "optdocs" $ do
      --   need commandmdsnew
      --   when commit $ commitIfChanged ";doc: update command flag docs" commandmds

      -- hledger/Hledger/Cli/Commands/CMD.md.new: a phony target that updates the ```flags block
      -- within hledger/Hledger/Cli/Commands/CMD.md with the output of "stack run -- hledger CMD --help".
      -- If that fails, a warning is printed and it carries on, keeping the old options help.
      -- NB this needs the hledger build to be up to date, see cmddocs.
      phonys $ \out ->
        if not $ "hledger/Hledger/Cli/Commands/" `isPrefixOf` out && ".md.new" `isSuffixOf` out
        then Nothing
        else Just $ do
          let src = dropExtension out
          need [src]
          srcls <- fmap lines $ liftIO $ readFileStrictly src
          let
            (pre,rest) = break (=="```flags") srcls
            (_,post)   = span  (/="```")     rest
          let cmdname = map toLower $ takeBaseName src
          do
            let shellcmd = "stack exec -- hledger -h " <> cmdname
            -- liftIO $ putStrLn $ "running " <> shellcmd <> " to get options help"
            cmdhelp <- lines . fromStdout <$> (cmd Shell shellcmd :: Action (Stdout String))
            let
              cmdflagshelp = takeWhile (not.null) $ dropWhile (/="Flags:") cmdhelp
              cmdflagshelp'
                | null cmdflagshelp = ["Flags:","no command-specific flags"]
                | otherwise         = cmdflagshelp
            liftIO $ writeFile src $ unlines $ concat [pre, ["```flags"], cmdflagshelp', post]
          -- This is supposed to print the error but otherwise ignore it, making this action a no-op,
          -- in case hledger is not yet built/runnable.
          `actionCatch` \(e::C.IOException) -> return ()
          -- XXX should somehow control the output and elide the verbose "not found on path" errors
            -- let elide err
            --       | "path: [" `isInfixOf` err = takeWhile (/='[') err <> "..."
            --       | otherwise = err
            -- in \(e::C.IOException) -> liftIO $ hPutStrLn stderr $ elide $ show e  -- not used

      -- CHANGELOGS

      -- update all changelogs with latest commits
      phony "changelogs" $ do
        need changelogs
        when commit $ commitIfChanged ";doc: update changelogs" changelogs

      -- [PKG/]CHANGES.md [-n|--dry-run]
      -- Add any new commit messages to the specified changelog, idempotently.
      -- Or with -n/--dry-run, just print the new content to stdout.
      -- Assumptions/requirements:
      -- 1. All releases nowadays are full releases (including all four packages).
      -- 2. The changelog's topmost markdown heading text is a release heading like "1.18.1 2020-06-21", or a more recent commit id like "4fffe6e7".
      -- 3. When a release heading is added to a changelog, a corresponding release tag is also created.
      phonys (\out -> if out `notElem` changelogs
        then Nothing
        else Just $ do
          let
            -- shell command to run git log showing short commit hashes.
            -- In 2024 git is showing 9 digits, 1 more than jj - show 8 for easier interop
            gitlog = "git log --abbrev=8"

            -- a git log format suitable for changelogs/release notes
            -- %s=subject, %an=author name, %n=newline if needed, %w=width/indent1/indent2, %b=body, %h=hash
            changelogGitFormat = "--pretty=format:'- %s (%an)%n%w(0,2,2)%b\n'"
            -- changelogVerboseGitFormat = "--pretty=format:'- %s (%an)%n%w(0,2,2)%b%h' --stat"

            -- shell command to format a git log message with the above format, as a changelog item
            commitMessageToChangelogItemCmd = unwords [
              sed
              ,"-e 's/^( )*\\* /\1- /'"        --  ensure bullet lists in descriptions use hyphens not stars
              ,"-e 's/ \\(Simon Michael\\)//'" --  strip maintainer's author name
              ,"-e 's/^- (doc: *)?(updated? *)?changelogs?( *updates?)?$//'"  --  strip some variants of "updated changelog"
              ,"-e 's/^ +\\[ci skip\\] *$//'"  --  strip [ci skip] lines
              ,"-e 's/^ +$//'"                 --  replace lines containing only spaces with empty lines
              -- ,"-e 's/\r//'"                   --  strip windows carriage returns (XXX \r untested. IDEA doesn't like a real ^M here)
              ,"-e '/./,/^$/!d'"               --  replace consecutive newlines with one
              ]

            -- Commit subjects (lowercased, after any ";" prefix) beginning
            -- with one of these are routine bookkeeping, never announced in
            -- release notes; their draft changelog items are dropped.
            routineCommitPrefixes = [
               "doc: changelog"           -- changelog drafting/editing/finalising
              ,"doc: update changelog"
              ,"doc: update command docs"
              ,"doc: update embedded manuals"
              ,"doc: update manuals"
              ,"doc: ai usage"
              ,"cabal:"                   -- regenerated cabal files
              ,"pkg: update tested-with"
              ]

            -- Remove never-announced routine content from draft changelog
            -- items: whole items generated from routine bookkeeping commits
            -- (see routineCommitPrefixes), and "AI usage:"/"AI assistance:"
            -- trailer lines (AI usage is reported separately, eg by
            -- just ai-commits). Runs before capitaliseAndPunctuateFirstLines.
            dropRoutineContent s
              | null s    = s
              | otherwise = unlines $ squeezeBlankLines $ go False $ lines s
              where
                -- An item is a "- " line plus any following lines up to the
                -- next "- " line (bodies are indented, so only items start
                -- at column 0 with "- ").
                go _ [] = []
                go dropping (l:ls)
                  | "- " `isPrefixOf` l = if isroutine l then go True ls else l : go False ls
                  | dropping            = go True ls
                  | isaiusage l         = go False ls
                  | otherwise           = l : go False ls
                isroutine l = any (`isPrefixOf` subject) routineCommitPrefixes
                  where subject = map toLower $ dropWhile (`elem` ("; "::String)) $ drop 2 l
                isaiusage l = any (`isPrefixOf` t) ["ai usage:", "ai assistance:"]
                  where t = map toLower $ dropWhile isSpace l
                squeezeBlankLines (l1:ls@(l2:_)) | null l1 && null l2 = squeezeBlankLines ls
                                                 | otherwise = l1 : squeezeBlankLines ls
                squeezeBlankLines ls = ls

            -- Capitalise and add a trailing period to the first line of each
            -- changelog item that has additional (indented) body lines, so it
            -- reads as a complete sentence and doesn't run into the body.
            -- An item with no body (a single "- ..." line, typically a terse
            -- doc/tooling note) is left exactly as written.
            capitaliseAndPunctuateFirstLines s
              | null s    = s  -- lines/unlines isn't a safe round trip for ""
              | otherwise = unlines $ concatMap fixblock $ blocks $ lines s
              where
                -- split into blank-line separators and the contiguous, non-blank
                -- line groups (each one changelog item) between them
                blocks [] = []
                blocks (l:ls)
                  | null l    = [l] : blocks ls
                  | otherwise = let (item, rest) = break null (l:ls) in item : blocks rest
                fixblock []        = []
                fixblock [oneline] = [oneline]  -- no body lines: leave the item as written
                fixblock (first:rest) = fixline first : rest
                fixline l = case stripPrefix "- " l of
                  Nothing   -> l
                  Just rest ->
                    let capitalised = capitalise rest
                        (main, annotations) = peelTrailingAnnotations capitalised
                    in "- " ++ if null annotations
                       then addPeriod capitalised
                       -- a trailing issue ref/author name sits outside the
                       -- sentence; normalise to a single period after it,
                       -- dropping any that ended up before it
                       else stripTrailingPeriod main ++ annotations ++ "."
                capitalise (c:cs) | isLower c = toUpper c : cs
                capitalise cs' = cs'
                addPeriod t
                  | endsInPunctuation trimmed = t
                  | otherwise = t ++ "."
                  where trimmed = dropWhileEnd isSpace t
                stripTrailingPeriod t = case reverse (dropWhileEnd isSpace t) of
                  ('.':cs) -> reverse cs
                  _        -> t
                endsInPunctuation t = case reverse t of
                  (c:_) -> c `elem` (".!?:" :: String)
                  []    -> True

                -- Peel zero or more trailing " [...]"/" (...)" annotation groups
                -- (eg an issue ref like "[#1941]", or an author-name attribution
                -- like "(Henning Thielemann)") off the end of a line. Assumes no
                -- nested brackets within a group.
                peelTrailingAnnotations t = case stripOneGroup t of
                  Just (t', grp) | isAnnotationGroup grp ->
                    let (t'', grps) = peelTrailingAnnotations t' in (t'', grps ++ grp)
                  _ -> (t, "")
                  where
                    -- everything but the last character of s, without using init/last
                    dropLastChar s = case reverse s of
                      (_:cs) -> reverse cs
                      []     -> ""
                    stripOneGroup s = case reverse trimmed of
                      (')':_) -> strip '('
                      (']':_) -> strip '['
                      _       -> Nothing
                      where
                        trimmed = dropWhileEnd isSpace s
                        strip open = case reverse (elemIndices open (dropLastChar trimmed)) of
                          (i:_) -> Just (dropWhileEnd isSpace (take i trimmed), " " ++ drop i trimmed)
                          []    -> Nothing

                -- A group is an annotation - an issue ref like "[#1941]", an
                -- author-name attribution like "(Henning Thielemann)", or a
                -- mix like "(Arthur Cinader, Simon Michael, #2698)" - if
                -- every word in it is either a "#digits" token or starts with
                -- a capital letter. Issue refs are conventionally bracketed
                -- and author names parenthesised, but recognise either form
                -- for either kind rather than assuming. Anything else is
                -- presumed to be a substantive part of the sentence, not an
                -- annotation.
                isAnnotationGroup grp = case dropWhile isSpace grp of
                  (opener:inner) | opener `elem` ("[(" :: String) -> case reverse inner of
                    (closer:revcontent) | closer `elem` (")]" :: String) ->
                      let ws = words (reverse revcontent)
                      in not (null ws) && all (\w -> looksLikeIssueRef w || startsUpper w) ws
                    _ -> False
                  _ -> False
                looksLikeIssueRef ('#':ds) = not (null ds) && all isDigit ds
                looksLikeIssueRef _        = False
                startsUpper (c:_) = isUpper c
                startsUpper []    = False

            -- Directories to exclude when doing git log for the project changelog.
            -- https://git-scm.com/docs/gitglossary.html#gitglossary-aiddefpathspecapathspec
            projectChangelogExcludes = unwords [
              ":!hledger-lib"
              ,":!hledger"
              ,":!hledger-ui"
              ,":!hledger-web"
              ,":!tests"
              ]

            mpkg = if dir=="doc" then Nothing else Just dir where dir = takeDirectory out

            -- In package changelog drafts, move any breaking changes (a "!"
            -- in the item's category prefix, eg "imp!:...") to the top,
            -- under a "Breaking changes" heading, with the rest under
            -- "Other changes". Further headings are chosen while polishing:
            -- topic headings for a long changelog like hledger's, or a
            -- suitable generic heading otherwise. (The project changelog
            -- has its own sections and is left alone.)
            liftBreakingItems s
              | null breakingitems = s
              | otherwise = unlines $ intercalate [""] $ concat [
                   [["Breaking changes"]]
                  ,breakingitems
                  ,if null otheritems then [] else [["Other changes"]]
                  ,otheritems
                  ]
              where
                (breakingitems, otheritems) = partition isbreaking items
                -- each item is a "- " line plus its continuation lines, sans trailing blanks
                items = splititems $ lines s
                  where
                    splititems [] = []
                    splititems (l:ls)
                      | "- " `isPrefixOf` l = let (body, rest) = break ("- " `isPrefixOf`) ls
                                              in dropWhileEnd null (l:body) : splititems rest
                      | otherwise = splititems ls
                isbreaking item = case item of
                  (first:_) -> case break (==':') $ dropWhile (==';') $ drop 2 first of
                    (cat, ':':_) -> '!' `elem` cat
                    _            -> False
                  [] -> False

          -- Parse the changelog.
          oldlines <- liftIO $ lines <$> readFileStrictly out
          let
            (preamble, oldheading:rest) = span isnotheading oldlines where isnotheading = not . ("# " `isPrefixOf`)
            oldversion = headDef err $ drop 1 $ words oldheading
              where err = error $ "could not parse changelog heading: "++oldheading

          -- Find the latest commit that has been scanned for this changelog, as a commit id or tag name.
            lastscannedrev
              | isCommitHash oldversion = oldversion
              | otherwise = maybe oldversion (++("-"++oldversion)) mpkg

          -- Issue numbers already mentioned in this changelog's unreleased
          -- section or most recent release section. A drafted item mentioning
          -- one of these may be a change that was already announced (eg
          -- merged from another branch, or added to the changelog by hand).
            recentissuerefs = nubSort $ concatMap issuerefs recentlines
              where
                recentlines = go (0::Int) (oldheading:rest)
                  where
                    go _ [] = []
                    go n (l:ls)
                      | "# " `isPrefixOf` l = if n >= 2 then [] else l : go (n+1) ls
                      | otherwise           = l : go n ls
            issuerefs ('#':cs) | not (null ds) = ds : issuerefs cs' where (ds,cs') = span isDigit cs
            issuerefs (_:cs) = issuerefs cs
            issuerefs [] = []

          -- Add a warning line to draft items which look like they may
          -- duplicate an already-announced change: ones mentioning an issue
          -- number in recentissuerefs, and cherry-picked commits (often
          -- already announced in another branch's changelog).
            flagPossibleDuplicates s
              | null s    = s
              | otherwise = unlines $ go $ lines s
              where
                go [] = []
                go (l:ls)
                  | "- " `isPrefixOf` l =
                      let
                        (body, rest') = break ("- " `isPrefixOf`) ls
                        dupes  = nubSort $ filter (`elem` recentissuerefs) $ concatMap issuerefs (l:body)
                        cherry = any (isInfixOf "cherry picked from" . map toLower) (l:body)
                        notes  =
                             ["  DUPLICATE? #" ++ intercalate ", #" dupes ++ " already mentioned in this changelog." | not (null dupes)]
                          ++ ["  CHERRYPICK? may already be announced in another branch's changelog." | cherry]
                      in l : notes ++ body ++ go rest'
                  | otherwise = l : go ls

          -- Find the latest commit (HEAD).
          latestrev <- unwords . words . fromStdout <$> (cmd Shell gitlog "-1 --pretty=%h" :: Action (Stdout String))

          -- If it's newer,
          when (lastscannedrev /= latestrev) $ do

            -- Check the resume point is still an ancestor of HEAD.
            -- A rebase or amend can leave the heading pointing to a rewritten
            -- commit; drafting from there would re-list the rebased commits
            -- as duplicates. In that case, find the commit's equivalent in
            -- the current history and resume from that instead; or if that
            -- fails, stop with a helpful message.
            Exit ancestorcheck <- cmd Shell "git merge-base --is-ancestor" lastscannedrev "HEAD 2>/dev/null"
            resumerev <-
              if ancestorcheck == ExitSuccess
              then return lastscannedrev
              else do
                mequiv <- relocateResumePoint lastscannedrev
                case mequiv of
                  Just equiv -> do
                    liftIO $ putStrLn $ out ++ ": resume point " ++ lastscannedrev ++ " was rewritten; resuming from its equivalent " ++ equiv
                    return equiv
                  Nothing -> do
                    lasttouch <- unwords . words . fromStdout <$> (cmd Shell gitlog "-1 --pretty=%h --" out :: Action (Stdout String))
                    error $ unlines [
                       out ++ ": the resume point '" ++ lastscannedrev ++ "' (from the topmost heading) is not an ancestor of HEAD."
                      ,"It was probably rewritten by a rebase or amend, and no equivalent commit was found in the current history."
                      ,"To fix, change that heading to a suitable current commit hash"
                      ,"(eg with: just changelogs-catchup COMMIT);"
                      ,"eg the last commit touching this file: " ++ lasttouch
                      ]

            -- Find the new commit messages relevant to this changelog, and clean them.
            let scanpath = fromMaybe projectChangelogExcludes mpkg
            newitems <- (if isJust mpkg then liftBreakingItems else id)
              . flagPossibleDuplicates . capitaliseAndPunctuateFirstLines . dropRoutineContent . fromStdout <$> (cmd Shell
              "set -o pipefail;"  -- so git log failure will cause this action to fail
              gitlog changelogGitFormat (resumerev++"..") "--" scanpath
              "|" commitMessageToChangelogItemCmd
              :: Action (Stdout String))

            -- Add the new heading and change items to the changelog, or print them.
            let newcontent = "# " ++ latestrev ++ "\n\n" ++ newitems ++ "\n"
            liftIO $ if dryrun
              then putStr $ out ++ ":\n" ++ newcontent
              else do
                writeFile out $ concat [
                  unlines preamble
                  ,newcontent
                  ,"\n"
                  ,if isCommitHash oldversion then "" else oldheading
                  ,"\n"
                  ,unlines rest
                  ]
                putStrLn (out ++ ": updated to " ++ latestrev)

          )

      -- Check the changelogs for common problems: a stale resume point,
      -- issue references without a matching link definition (and vice versa),
      -- and leftover draft markers. Checks each changelog's topmost section
      -- only (the one being edited). Exits nonzero if problems are found.
      phony "changelogs-check" $ do
        problems <- fmap concat $ forM changelogs $ \f -> do
          ls <- liftIO $ lines <$> readFileStrictly f
          case break ("# " `isPrefixOf`) ls of
            (_, []) -> return [f ++ ": no release heading found"]
            (_, heading:rest) -> do
              let
                version = headDef "" $ drop 1 $ words heading
                section = takeWhile (not . ("# " `isPrefixOf`)) rest
                defs    = nubSort $ mapMaybe issueRefDefinition section
                uses    = nubSort $ concatMap bracketedIssueRefs $ filter (isNothing . issueRefDefinition) section
                markers = [f ++ ": leftover draft marker: " ++ dropWhile isSpace l
                          | l <- section, any (`isInfixOf` l) ["DUPLICATE?","CHERRYPICK?"]]
              stale <-
                if isCommitHash version
                then do
                  Exit ok <- cmd Shell "git merge-base --is-ancestor" version "HEAD 2>/dev/null"
                  if ok == ExitSuccess
                  then return []
                  else do
                    mequiv <- relocateResumePoint version
                    return $ case mequiv of
                      Just equiv -> [f ++ ": heading commit " ++ version ++ " was rewritten; just changelogs will resume from its equivalent " ++ equiv]
                      Nothing    -> [f ++ ": heading commit " ++ version ++ " is not an ancestor of HEAD (fix with just changelogs-catchup COMMIT)"]
                else return []
              return $ concat [
                 stale
                ,[f ++ ": [#" ++ r ++ "] is used but has no link definition in the topmost section" | r <- uses \\ defs]
                ,[f ++ ": [#" ++ r ++ "] is defined but unused in the topmost section" | r <- defs \\ uses]
                ,markers
                ]
        liftIO $ mapM_ putStrLn problems
        if null problems
        then liftIO $ putStrLn "changelogs look ok"
        else error "changelogs-check found problems"

      -- Update all program-specific docs, eg after setversion.
      phony "docs" $ need [
         "cmddocs"
        ,"manuals"
        ,"changelogs"
        ]

      -- Update (render) the website, which should be checked out as ./site
      phony "site" $ do
        need [
           "webmanuals"
          ]
        cmd_ "make -C site build"

      -- Markdown generated from org files, for the website.
      -- [ -- "doc/BACKLOG.md"
      --  ] |%> \out -> do
      --   let src = out -<.> "org"
      --   need [src]
      --   -- replace the generated top heading with our own so we can insert the TOC after it
      --   let heading = dropExtension out
      --   mdlines <- drop 1 . lines . fromStdout <$> (cmd Shell pandoc fromorg towebmd src :: Action (Stdout String))
      --   liftIO $ writeFile out $ unlines $ [
      --      "<!-- " ++ "Generated by \"Shake " ++ out ++ " from " ++ src ++ " -->"
      --     ,""
      --     ,"# " ++ heading
      --     ,""
      --     ] ++ mdlines

-- XXX try to style backlog items as unnumbered or nested-numbered list items
{-
<style>
main>ol {
  list-style: none;
  padding-inline-start: 1em;
  counter-reset: item;
}
/* XXX when there are subitems, pandoc wraps all in a <p>,
 * which forces a line break after the :before text
 */
main>ol>li:before {
  content: counters(item, ".") ". ";
  counter-increment: item;
}
*/
main>ol>li {
}
</style>
-}

      -- MISC

      -- Generate the web manuals based on the current checkout and save
      -- them as the specified versioned snapshot in site/doc/VER/ .
      -- .snapshot is a dummy file.
      -- "site/doc/*/.snapshot" %> \out -> do
      --   need webmanuals
      --   let snapshot = takeDirectory out
      --   cmd_ Shell "mkdir -p" snapshot
      --   forM_ webmanuals $ \f -> -- site/hledger.md, site/journal.md
      --     cmd_ Shell "cp" f (snapshot </> takeFileName f)
      --   cmd_ Shell "cp -r site/images" snapshot
      --   cmd_ Shell "touch" out
      -- Help:
      -- ,"./Shake site/doc/VERSION/.snapshot  save current web manuals as this snapshot"

      -- Cleanup.

      phony "clean" $ do
        putNormal "Cleaning object files in tools"
        removeFilesAfter "tools"  ["*.o","*.p_o","*.hi"]

      phony "Clean" $ do
        need ["clean"]
        putNormal "Cleaning shake build cache"
        removeFilesAfter ".shake" ["//*"]

-- Git commit the given files with the given message if they have changes,
-- otherwise print a no change message and continue.
commitIfChanged msg files = do
  diffs <- (/=ExitSuccess) . fromExit <$> cmd Shell "git diff --no-ext-diff --quiet --exit-code --" files
  if diffs
  then cmd Shell ("git commit -m '"++msg++"' --") files
  else liftIO $ putStrLn $ "nothing to commit for \"" ++ msg ++ "\""

-- Convert numbered man page names to manual names.
-- hledger.1 -> hledger, hledger_journal.5 -> hledger_journal
manpageNameToManualName = dropNumericSuffix
  where
    dropNumericSuffix s = reverse $
      case reverse s of
        c : '.' : cs | isDigit c -> cs
        cs                       -> cs

-- Convert manual names to numbered man page names.
-- hledger -> hledger.1, hledger_journal -> hledger_journal.5
manualNameToManpageName s
  | '_' `elem` s = s <.> "5"
  | otherwise    = s <.> "1"

dropDirectory2 = dropDirectory1 . dropDirectory1

readFileStrictly :: FilePath -> IO String
readFileStrictly f = readFile f >>= \s -> C.evaluate (length s) >> return s

-- Write new content to a file, only if it's different.
maybeWriteFile :: FilePath -> String -> IO ()
maybeWriteFile f new = do
  old <- readFileStrictly f
  when (old /= new) $ writeFile f new

-- | Get the current local date.
getCurrentDay :: IO Day
getCurrentDay = localDay . zonedTimeToLocalTime <$> getZonedTime

-- | Replace each occurrence of a regular expression by this string.
replaceRe :: RE -> String -> String -> String
replaceRe re repl = replaceBy re (\_ _ _ -> Just repl)

-- | Replace each occurrence of a regular expression, by transforming
-- each matched text with the given function.
replaceBy :: RE -> (Match String -> RELocation -> Capture String -> Maybe String) -> String -> String
replaceBy re f src = replaceAllCaptures TOP f $ src *=~ re

-- | Does this string look like a valid cabal package version ?
isVersion s = not (null s) && all (`elem` "0123456789.") s && '.' `elem` s

-- | Does this string look like a hledger development version ?
-- Ie a version where the first two digits of the last part are the
-- special values 97, 98 or 99, indicating alpha/beta/rc or whatever.
isDevVersion s = isVersion s && lastpart >= "97"
  where lastpart = lastDef "" $ splitOn "." s

-- | Does this string look like a hledger release version ?
-- Ie a cabal package version that's not a hledger development version.
isReleaseVersion s = isVersion s && not (isDevVersion s)

-- | Does this string look like a git commit hash ?
-- Ie a sequence of 7 or more numbers or letters.
isCommitHash s = length s > 6 && all isAlphaNum s

-- | Extract the numbers of well-formed bracketed issue references,
-- like "[#1234]", from a string.
bracketedIssueRefs :: String -> [String]
bracketedIssueRefs s = case s of
  ('[':'#':cs) -> let (ds,rest) = span isDigit cs
                  in case rest of
                       (']':rest') | not (null ds) -> ds : bracketedIssueRefs rest'
                       _ -> bracketedIssueRefs cs
  (_:cs) -> bracketedIssueRefs cs
  []     -> []

-- | If this line is a markdown link reference definition for a
-- bracketed issue reference, like "[#1234]: URL", return the issue number.
issueRefDefinition :: String -> Maybe String
issueRefDefinition l = case l of
  ('[':'#':cs) -> let (ds,rest) = span isDigit cs
                  in case rest of
                       (']':':':_) | not (null ds) -> Just ds
                       _ -> Nothing
  _ -> Nothing

-- | Given a commit hash which is no longer an ancestor of HEAD (it was
-- probably rewritten by a rebase or amend), try to find its equivalent
-- commit in the current history, by matching author date and author email
-- (and the commit subject, as a tiebreaker if needed; a rewrite preserves
-- the author date and author, though it may change the hash and subject).
-- Returns Nothing if the old commit's metadata can't be read (eg it has
-- been garbage collected) or if no unique match is found.
relocateResumePoint :: String -> Action (Maybe String)
relocateResumePoint oldhash = do
  (Exit code, Stdout oldmeta) <- cmd Shell "git log -1 --pretty=%aI%x09%ae%x09%s" oldhash "-- 2>/dev/null"
  case (code, parsemeta (chomp oldmeta)) of
    (ExitSuccess, Just (date, email, subject)) -> do
      Stdout candidates <- cmd Shell "git log --abbrev=8 --pretty=%h%x09%aI%x09%ae%x09%s -10000"
      let
        parsed = mapMaybe parsehashmeta $ lines candidates
        datematches = [(h,s) | (h,d,e,s) <- parsed, d == date, e == email]
        matches = case datematches of
          [m] -> [m]
          ms  -> filter ((== subject) . snd) ms
      return $ case matches of
        [(h,_)] -> Just h
        _       -> Nothing
    _ -> return Nothing
  where
    parsemeta l = case splitOn "\t" l of
      (d:e:rest@(_:_)) -> Just (d, e, intercalate "\t" rest)
      _ -> Nothing
    parsehashmeta l = case splitOn "\t" l of
      (h:d:e:rest@(_:_)) -> Just (h, d, e, intercalate "\t" rest)
      _ -> Nothing

-- | Remove all trailing newlines/carriage returns.
chomp :: String -> String
chomp = reverse . dropWhile (`elem` "\r\n") . reverse

