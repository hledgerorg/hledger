#!/usr/bin/env just
# * Project scripts
# using https://github.com/casey/just, doc: https://just.systems/man/en
# Usage: alias j=just, run j to list available scripts.
#
# Maintainable robust project automation is essential.
# We rely on just for project automation scripts,
# even though it's less likely to be installed by default than make.
# After many years with make and plain shell and haskell for scripting,
# just is better enough that it's worthwhile.
# The big current limitation of just is the lack of file dependencies.
# When that is needed, or when more powerful scripting is needed,
# call out to Shake.hs, which handles both of those well.
#
# Reference:
# https://docs.rs/regex/1.5.4/regex/#syntax Regexps
# https://just.systems/man/en/chapter_31.html Functions
# https://cheatography.com/linux-china/cheat-sheets/justfile Cheatsheet
# https://github.com/casey/just/discussions
#
# Here are other tools required by some of the scripts below:
# - bash            - (not the old /bin/bash on mac)
# - ghc             - a haskell compiler in PATH (installing with ghcup is recommended)
# - ghcid           - recompiles and optionally runs tests on file change
# - stack           - installs haskell libs, runs ghc
# - shelltestrunner - runs functional tests
# - quickbench      - runs benchmarks
# - hasktags        - generates tag files for code navigation
# - profiterole     - simplifies profiles
# - profiteur       - renders profiles as html
# - dateround       - from dateutils
#
# Lines beginning with "# * ", "# ** " in this file are emacs outshine-mode headings, foldable with TAB.
# You could add emacs highlighting like so, if needed:
# (add-hook 'just-mode-hook (lambda ()
#   (highlight-lines-matching-regexp "^# \\*\\*? " 'hi-yellow)  ; level 1-2 outshine headings
#   (highlight-lines-matching-regexp "^@?\\w.*\\w:$" 'hi-pink) ; recipe headings (misses recipes with dependencies)
#   ))

# ** just config ------------------------------------------------------------

################################################################################
# prelude.just - Standard definitions for justfiles.

#set allow-duplicate-recipes
set allow-duplicate-variables

set export := true
set positional-arguments := true

just := 'just -f ' + justfile()

# list recipes, optionally filtered by REGEX. Useful when there's many, but slower than just -ul.
_help *REGEX:
    #!/usr/bin/env bash
    if [[ '{{ REGEX }}' == '' ]]
    then just -f {{ justfile() }} -ul | sed -E 's/(^ +[A-Z_-]+ )/\n\1/'; echo
    else just -f {{ justfile() }} -ul | rg --pcre2 -i '{{ REGEX }}'; true
    fi

alias h := _help

# check this justfile for errors and non-standard format
@_chk:
    just --fmt --unstable --check

# if this justfile is error free but in non-standard format, reformat and commit it
@_fmt:
    just -q check || just --fmt --unstable && git commit -m 'just: fmt' -- {{ justfile() }}

WATCHEXEC := 'watchexec'

# rerun RECIPE when any watched-by-default file changes
@_watch RECIPE *JOPTS:
    $WATCHEXEC -r -- just $RECIPE {{ JOPTS }}
################################################################################

# Ensure a predictable default shell. bash will need to be installed to use this justfile.
set shell := ["bash", "-uc"]

# ** Constants ------------------------------------------------------------

# Open a web browser
OPEN := 'open -a safari'

# grep-like rg
#RG_ := 'rg --sort=path --no-heading -i'
#TODAY := `date +%Y-%m-%d`
# just := "just -f " + justfile()
# Use this justfile from within its directory, otherwise we must write {{ just }} everywhere.

BROWSE := 'open'

# XXX These often don't work well interpolated as $CMD or {{ CMD }}, not sure why
# find GNU tools, eg on mac

GDATE := `type -P gdate || echo date`
GTAR := `type -P gtar || echo tar`

#GNUTAR := `which gtar >/dev/null && echo gtar || echo tar`
# make ghc usable for scripting with -e

GHC := 'ghc -package-env - -ignore-dot-ghci -Wno-x-partial'
GHCI := 'ghci'

# GHCPKG := 'ghc-pkg'
# HADDOCK := 'haddock'
# CABAL := 'cabal'
# CABALINSTALL := 'cabal install -w {{ GHC }}'
# GHC-compiled executables require a locale (and not just C) or they
# will die on encountering non-ascii data. Set LANG to something if not already set.
# export LANG? := 'en_US.UTF-8'
# command to run during profiling (time and heap)
# command to run when profiling

PROFCMD := 'bin/hledgerprof balance -f examples/10ktxns-1kaccts.journal >/dev/null'
PROFRTSFLAGS := '-P'

# # command to run when checking test coverage
# COVCMD := 'test'
# COVCMD := '-f test-wf.csv print'
# Which stack command (and in particular, stack yaml/GHC version) to use for building etc. ?

STACK := 'stack'
#STACK := 'stack --stack-yaml=stack912.yaml'

PACKAGES := '
    hledger-lib
    hledger
    hledger-ui
    hledger-web
    '

INCLUDEPATHS := '
    -ihledger-lib
    -ihledger
    -ihledger-ui
    -ihledger-web
    -ihledger-web/app
    '
MAIN := 'hledger/app/hledger-cli.hs'

# All source files in the project (plus a few strays like Setup.hs & hlint.hs).
# Used eg for building tags. Doesn't reliably catch all source files.

SOURCEFILES := '
    hledger/*hs
    hledger/app/*hs
    hledger/bench/*hs
    hledger/test/*hs
    hledger/Hledger/*hs
    hledger/Hledger/*/*hs
    hledger/Hledger/*/*/*hs
    hledger-*/*hs
    hledger-*/app/*hs
    hledger-*/test/*hs
    hledger-*/Hledger/*hs
    hledger-*/Hledger/*/*hs
    hledger-*/Hledger/*/*/*hs
    hledger-lib/Text/*/*hs
    '
HPACKFILES := '
    hledger/*package.yaml
    hledger-*/*package.yaml
    '
CABALFILES := '
    hledger/hledger.cabal
    hledger-*/*.cabal
    '
MANUALSOURCEFILES := '
    doc/common.m4
    */*.m4.md
    '

# MANUALGENFILES := '
#     hledger*/hledger*.{1,5,info,txt}
#     '

COMMANDHELPFILES := '
    hledger/Hledger/Cli/Commands/*.md
    '
WEBTEMPLATEFILES := '
    hledger-web/templates/*
    '
WEBCODEFILES := '
    hledger-web/static/*.js
    hledger-web/static/*.css
    '
DOCSOURCEFILES := '
    README.md
    CONTRIBUTING.md
    ' + MANUALSOURCEFILES + COMMANDHELPFILES
TESTFILES := `fd '\.test$' --exclude ledger-compat`

# XXX it's fd-find on gnu/linux ?
# # file(s) which require recompilation for a build to have an up-to-date version string
# VERSIONSOURCEFILE := 'hledger/Hledger/Cli/Version.hs'
# Two or three-part version string, set as program version in builds made by this makefile.
# We use hledger CLI's current version (XXX for all packages, which isn't quite right).

export VERSION := `cat hledger/.version`

# Flags for ghc builds.

# Warnings to see during dev tasks like make ghci*. XXX redundant with package.yamls ?
WARNINGS := '
    -Wall
    -Wno-incomplete-uni-patterns
    -Wno-missing-signatures
    -Wno-orphans
    -Wno-type-defaults
    -Wno-unused-do-bind
    '

# if you have need to try building in less memory
GHCLOWMEMFLAGS := ''
#GHCLOWMEMFLAGS := '+RTS +M2g -RTS'

# ghc-only builds need the macro definitions generated by cabal
# from cabal's dist dir, hopefully there's just one:
#CABALMACROSFLAGS := '-optP-include -optP hledger/dist*/build/autogen/cabal_macros.h'
# or from stack's dist dir:
#CABALMACROSFLAGS := '-optP-include -optP hledger/.stack-work/dist/*/*/build/autogen/cabal_macros.h'
CABALMACROSFLAGS := ''

BUILDFLAGS := '-rtsopts ' + WARNINGS + GHCLOWMEMFLAGS + CABALMACROSFLAGS + ' -DDEVELOPMENT' + ' -DVERSION="' + VERSION + '"' + INCLUDEPATHS

#    -fplugin Debug.Breakpoint \
#    -fhide-source-paths \
# PROFBUILDFLAGS := '-prof -fprof-auto -osuf hs_p'

# ** Building ------------------------------------------------------------
BUILDING:

# build the hledger package showing ghc codegen times/allocations
@buildtimes:
    time ($STACK build hledger --force-dirty --ghc-options='-fforce-recomp -ddump-timings' 2>&1 | grep -E '\bCodeGen \[.*time=')

# # build an unoptimised hledger at bin/hledger.EXT.unopt (default: git describe)
# build-unopt *EXT:
#     #!/usr/bin/env bash
#     ext={{ if EXT == '' { `git describe --tags` } else { EXT } }}
#     exe="bin/hledger.$ext.unopt"
#     $STACK --verbosity=error install --ghc-options=-O0 hledger --local-bin-path=bin
#     mv bin/hledger "$exe"
#     echo "$exe"

# build hledger with profiling enabled at bin/hledgerprof (using stack-prof.yaml and its own work dir, see its header)
hledgerprof:
    @echo "building bin/hledgerprof..."
    stack --stack-yaml stack-prof.yaml --work-dir .stack-prof install --library-profiling --executable-profiling --local-bin-path bin hledger
    mv bin/hledger bin/hledgerprof
    @echo "to profile, run: bin/hledgerprof CMD +RTS -p -RTS  (writes hledgerprof.prof), or use just quickprof"

# # build "bin/hledgercov" for coverage reports (with ghc)
# hledgercov:
#     $STACK ghc {{ MAIN }} -fhpc -o bin/hledgercov -outputdir .hledgercovobjs $BUILDFLAGS

# run ghcid on hledger-lib + hledger
@ghcid:
    ghcid -c 'just ghci'

# run ghcid autobuilder on hledger-lib + hledger + hledger-ui
@ghcid-ui:
    ghcid -c 'just ghci-ui'

# run ghcid autobuilder on hledger-lib + hledger + hledger-web
@ghcid-web:
    ghcid -c 'just ghci-web'

# run ghcid autobuilding and running hledger-web with sample journal on port 5001
@ghcid-web-run:
    ghcid -c 'just ghci-web' --test ':main -f examples/sample.journal --port 5001 --serve'

# # run ghcid autobuilding and running the test command
# ghcid-test:
#     ghcid -c 'just ghci' --test ':main test -- --color=always'
# # run ghcid autobuilding and running the test command with this TESTPATTERN
# ghcid-test-%:
#     ghcid -c 'just ghci' --test ':main test -- --color=always -p$*'

# run ghcid autobuilding and running hledger-lib doctests
@ghcid-doctest:
    ghcid -c 'cd hledger-lib; $STACK ghci hledger-lib:test:doctest' --test ':main' --reload hledger-lib

GHCIDRESTART := '--restart Makefile --restart Makefile.local'
GHCIDRELOAD := '--reload t.j --reload t.timedot'
GHCIDCMD := ':main -f t.j bal date:today -S'

# # run ghcid autobuilding and running a custom GHCI command with reload/restart on certain files - customise this
# ghcid-watch watch:
#     ghcid -c 'just ghci' --test '{{ GHCIDCMD }}' {{ GHCIDRELOAD }} {{ GHCIDRESTART }}
# keep synced with Shake.hs header

SHAKEDEPS := '\
    --package base-prelude \
    --package directory \
    --package extra \
    --package process \
    --package regex \
    --package safe \
    --package shake \
    --package time \
    '

#    --package hledger-lib \  # for Hledger.Utils.Debug

# run ghcid autobuilder on Shake.hs
ghcid-shake:
    stack exec {{ SHAKEDEPS }} -- ghcid Shake.hs

# ** Testing ------------------------------------------------------------
TESTING:

# run ghci on hledger-lib + hledger
@ghci *GHCIARGS:
    $STACK exec -- $GHCI $BUILDFLAGS {{ GHCIARGS }} hledger/Hledger/Cli.hs

# echo the full command that just ghci would run
@ghci-echo *GHCIARGS:
    echo $STACK exec -- $GHCI $BUILDFLAGS {{ GHCIARGS }} hledger/Hledger/Cli.hs

# run ghci on hledger-lib + hledger with profiling/call stack information
@ghci-prof *GHCIARGS:
    stack build --profile hledger --only-dependencies
    $STACK exec -- $GHCI $BUILDFLAGS -fexternal-interpreter -prof -fprof-auto {{ GHCIARGS }} hledger/Hledger/Cli.hs

# run ghcitui on hledger-lib + hledger
@ghcitui *GHCITUIARGS:
    ghcitui --cmd "just ghci"

# run ghci on hledger-lib + hledger + hledger-ui
@ghci-ui *GHCIARGS:
    $STACK exec -- $GHCI $BUILDFLAGS {{ GHCIARGS }} hledger-ui/app/hledger-ui.hs

# run ghci on hledger-lib + hledger + hledger-web
@ghci-web *GHCIARGS:
    $STACK exec -- $GHCI $BUILDFLAGS {{ GHCIARGS }} hledger-web/app/main.hs

# run ghci on hledger-lib + hledger + hledger-web + hledger-web test suite
@ghci-web-test *GHCIARGS:
    $STACK exec -- $GHCI $BUILDFLAGS {{ GHCIARGS }} hledger-web/test/test.hs

# # better than stack exec ?
# # XXX does not see changes to files
# # run ghci on hledger-lib + test runner
# ghci-lib-test:
#     $STACK ghci --ghc-options="\'-rtsopts {{ WARNINGS }} -ihledger-lib  -DDEVELOPMENT -DVERSION=\"1.26.99\"\'" hledger-lib/test/unittest.hs
# run ghci on all the hledger
# ghci-all:
#     $STACK exec -- $GHCI $BUILDFLAGS \
#         hledger-ui/Hledger/UI/Main.hs \
#         hledger-web/app/main.hs \

# run ghci on hledger-lib doctests
@ghci-doctest:
    cd hledger-lib; $STACK ghci hledger-lib:test:doctest

# run ghci on Shake.hs
@ghci-shake:
    $STACK exec {{ SHAKEDEPS }} -- ghci Shake.hs

# run most tests (files, unit, doc, functional). doctest is slow, requiring its own build.
test:
    @echo
    just embedtest
    @echo
    just functest --hide
    @echo
    just doctest
    @echo

# For quieter tests add --silent. It may hide troubleshooting info.
# For very verbose tests add --verbosity=debug. It seems hard to get something in between.

STACKTEST := STACK + ' test --fast'

# # When doing build testing, save a little time and output noise by not
# # running tests & benchmarks. Comment this out if you want to run them.
# SKIPTESTSBENCHS := '--no-run-tests --no-run-benchmarks'

# check all files embedded with file-embed are declared in extra-source-files
@embedtest:
    tools/checkembeddedfiles

# check that internal links in the manuals' source files point to existing headings
@anchortest:
    tools/checkanchors

# # stack build --dry-run all hledger packages ensuring an install plan with default snapshot)
# buildplantest:
#     buildplantest-stack.yaml
# # stack build --dry-run all hledger packages ensuring an install plan with each ghc version/stackage snapshot
# buildplantest-all:
#     for F in stack*.yaml; do make --no-print-directory buildplantest-$F; done
# # stack build --dry-run all hledger packages ensuring an install plan with the given stack yaml file; eg make buildplantest-stack8.2.yaml
# buildplantest-%:
#     $STACK build --dry-run --test --bench --stack-yaml=$*
# # force-rebuild all hledger packages/modules quickly ensuring no warnings with default snapshot)
# buildtest:
#     buildtest-stack.yaml
# # force-rebuild all hledger packages/modules quickly ensuring no warnings with each ghc version/stackage snapshot
# buildtest-all:
#     for F in stack*.yaml; do make --no-print-directory buildtest-$F; done
# # force-rebuild all hledger packages/modules quickly ensuring no warnings with the given stack yaml file; eg make buildtest-stack8.2.yaml
# buildtest-%:
#     $STACK build --test --bench {{ SKIPTESTSBENCHS }} --fast --force-dirty --ghc-options=-fforce-recomp --ghc-options=-Werror --stack-yaml=$*
# # build any outdated hledger packages/modules quickly ensuring no warnings with default snapshot. Wont detect warnings in up-to-date modules.)
# incr-buildtest:
#     incr-buildtest-stack.yaml
# # build any outdated hledger packages/modules quickly ensuring no warnings with each ghc version/stackage snapshot. Wont detect warnings in up-to-date modules.
# incr-buildtest-all:
#     for F in stack*.yaml; do make --no-print-directory incr-buildtest-$F; done
# # build any outdated hledger packages/modules quickly ensuring no warnings with the stack yaml file; eg make buildtest-stack8.2.yaml. Wont detect warnings in up-to-date modules.
# incr-buildtest-%:
#     $STACK build --test --bench {{ SKIPTESTSBENCHS }} --fast --ghc-options=-Werror --stack-yaml=$*
# # do a stack clean --full with all ghc versions for paranoia/troubleshooting
# stack-clean-all:
#     for F in stack*.yaml; do $STACK clean --full --stack-yaml=$F; done

# run all test suites in the hledger packages
@pkgtest:
    ($STACKTEST && echo $@ PASSED) || (echo $@ FAILED; false)

# doctest with ghc 8.4 on mac requires a workaround, see hledger-lib/package.yaml.
# Or, could run it with ghc 8.2:
#    @($STACKTEST --stack-yaml stack8.2.yaml hledger-lib:test:doctest && echo $@ PASSED) || (echo $@ FAILED; false)

# run the doctests in hledger-lib module/function docs. DOCTESTARGS is passed through but seems not too useful.
@doctest *DOCTESTARGS:
    ({{ STACK }} test --test-arguments="$DOCTESTARGS" hledger-lib:test:doctest && echo $@ PASSED) || (echo $@ FAILED; false)

# # run the unit tests in hledger-lib
# unittest:
#     @($STACKTEST hledger-lib:test:unittest && echo $@ PASSED) || (echo $@ FAILED; false)

# run hledger & hledger-lib unit tests (do a stack build hledger first).
@unittest:
    ($STACK exec hledger test && echo $@ PASSED) || (echo $@ FAILED; false)

SHELLTEST := STACK + ' exec -- shelltest --execdir --threads=40'

#  --hide-successes

# build hledger warning-free and run functional tests, with any shelltest OPTS.
@functest *STOPTS:
    {{ STACK }} build --ghc-options=-Werror --test --no-run-tests hledger
    time (({{ SHELLTEST }} --exclude=/_ --hide {{ if STOPTS == '' { '' } else { STOPTS } }} \
        hledger/test/ bin/ \
        -x hledger/test/perf.test \
        -x ledger-compat/ledger-baseline -x ledger-compat/ledger-regress -x ledger-compat/ledger-extra \
        && echo $@ PASSED) || (echo $@ FAILED; false))
# --test so that subsequent `stack test` won't recompile everything
# --no-run-tests to avoid running the slow doctest suite every time

# run hledger-web's browser tests against the current build, with any playwright OPTS (needs setup, see hledger-web/test/browser/README.md)
@browsertest *PWOPTS:
    {{ STACK }} build hledger-web
    cd hledger-web/test/browser && \
        HLEDGER_WEB="{{ STACK }} exec -- hledger-web" pnpm test {{ PWOPTS }}

# too fragile:
#    echo
#    just perftest {{ STOPTS }}

# remind how to test performance
@perfhelp:
    echo "Some ways to compare performance of two installed hledger versions:"
    echo "just installas new"
    echo "just perftest"
    echo "just bench -w hledger,hledger-new -n2 -N2"
    echo "just bench-throughput hledger; just bench-throughput hledger-new"

# run performance tests with the hledger in PATH, logging to perf.log and expecting a certain txns/s. Accepts shelltest OPTS.
@perftest *STOPTS:
    echo "Running performance tests..."
    time (({{ SHELLTEST }} {{ if STOPTS == '' { '' } else { STOPTS } }} hledger/test/_perf.test \
        && echo $@ PASSED) || (echo $@ FAILED; false))
    echo "Now eyeball the recent perf.log for changes:"
    tail -50 perf.log

# compare hledger's and ledger's balance report
compare-balance:
    #!/usr/bin/env bash
    for f in examples/1txns-1accts.journal \
            examples/10txns-10accts.journal \
            ; do \
        (export f=$f; \
        printf "\n-------------------------------------------------------------------------------\n"; \
        echo "comparing hledger -f $f balance and ledger -f $f balance --flat"; \
        difft --color=always --display side-by-side-show-both <(hledger -f $f balance) <(ledger -f $f balance --flat) ) | tail +2; \
        done

# generate a hlint report
hlinttest hlint:
    hlint --hint=hlint --report=hlint.html {{ SOURCEFILES }}

# check that haddock can generate docs without dying
@haddocktest:
    (just -q haddock && echo haddocktest PASSED) || (echo haddocktest FAILED; false)

# check cabal files' syntax
@cabalfilestest:
    (for p in $PACKAGES; do (cd $p && printf "\nchecking $p.cabal:\n" && cabal check); done \
      && echo $@ PASSED) || (echo $@ FAILED; false)

# test-stack%yaml:
#     $STACK --stack-yaml stack$*yaml clean
#     $STACK --stack-yaml stack$*yaml build --ghc-options="{{ WARNINGS }} -Werror" --test --bench --haddock --no-haddock-deps
#
# releasetest: Clean unittest functest fullcabaltest haddocktest #buildtest doctest \
#     {{ call def-help,releasetest,pre-release tests }}

# run hledger-install.sh not from inside a haskell project
installtest:
    cd; {{ justfile_directory() }}/hledger-install/hledger-install.sh

# ** Benchmarking ------------------------------------------------------------
BENCHMARKING:

# generate standard sample journals in examples/. Run just tools first.
samplejournals:
    # small journals
    tools/generatejournal 3 5 5            > examples/ascii.journal
    tools/generatejournal 3 5 5 --mixed    > examples/mixed.journal
    tools/generatejournal 1 1 10           > examples/1txns-1accts.journal
    tools/generatejournal 10 10 10         > examples/10txns-10accts.journal
    tools/generatejournal 100 100 10       > examples/100txns-100accts.journal
    # many transactions
    tools/generatejournal 1000    1000 10  > examples/1ktxns-1kaccts.journal
    tools/generatejournal 2000    1000 10  > examples/2ktxns-1kaccts.journal
    tools/generatejournal 3000    1000 10  > examples/3ktxns-1kaccts.journal
    tools/generatejournal 4000    1000 10  > examples/4ktxns-1kaccts.journal
    tools/generatejournal 5000    1000 10  > examples/5ktxns-1kaccts.journal
    tools/generatejournal 6000    1000 10  > examples/6ktxns-1kaccts.journal
    tools/generatejournal 7000    1000 10  > examples/7ktxns-1kaccts.journal
    tools/generatejournal 8000    1000 10  > examples/8ktxns-1kaccts.journal
    tools/generatejournal 9000    1000 10  > examples/9ktxns-1kaccts.journal
    tools/generatejournal 10000   1000 10  > examples/10ktxns-1kaccts.journal
    tools/generatejournal 20000   1000 10  > examples/20ktxns-1kaccts.journal
    tools/generatejournal 30000   1000 10  > examples/30ktxns-1kaccts.journal
    tools/generatejournal 40000   1000 10  > examples/40ktxns-1kaccts.journal
    tools/generatejournal 50000   1000 10  > examples/50ktxns-1kaccts.journal
    tools/generatejournal 60000   1000 10  > examples/60ktxns-1kaccts.journal
    tools/generatejournal 70000   1000 10  > examples/70ktxns-1kaccts.journal
    tools/generatejournal 80000   1000 10  > examples/80ktxns-1kaccts.journal
    tools/generatejournal 90000   1000 10  > examples/90ktxns-1kaccts.journal
    tools/generatejournal 100000  1000 10  > examples/100ktxns-1kaccts.journal
    tools/generatejournal 1000000 1000 10  > examples/1Mtxns-1kaccts.journal
    # many accounts
    tools/generatejournal 1000 1 10        > examples/1ktxns-1accts.journal
    tools/generatejournal 1000 10 10       > examples/1ktxns-10accts.journal
    tools/generatejournal 1000 100 10      > examples/1ktxns-100accts.journal
    #tools/generatejournal 1000 1000 10    > examples/1ktxns-1kaccts.journal
    tools/generatejournal 1000 10000 10    > examples/1ktxns-10kaccts.journal
    tools/generatejournal 1000 100000 10   > examples/1ktxns-100kaccts.journal
    tools/generatejournal 1000 1000000 10  > examples/1ktxns-1maccts.journal
    tools/generatejournal 10000 1 10       > examples/10ktxns-1accts.journal
    tools/generatejournal 10000 10 10      > examples/10ktxns-10accts.journal
    tools/generatejournal 10000 100 10     > examples/10ktxns-100accts.journal
    #tools/generatejournal 10000 1000 10   > examples/10ktxns-1kaccts.journal
    tools/generatejournal 10000 10000 10   > examples/10ktxns-10kaccts.journal
    tools/generatejournal 10000 20000 10   > examples/10ktxns-20kaccts.journal
    tools/generatejournal 10000 30000 10   > examples/10ktxns-30kaccts.journal
    tools/generatejournal 10000 40000 10   > examples/10ktxns-40kaccts.journal
    tools/generatejournal 10000 50000 10   > examples/10ktxns-50kaccts.journal
    tools/generatejournal 10000 60000 10   > examples/10ktxns-60kaccts.journal
    tools/generatejournal 10000 70000 10   > examples/10ktxns-70kaccts.journal
    tools/generatejournal 10000 80000 10   > examples/10ktxns-80kaccts.journal
    tools/generatejournal 10000 90000 10   > examples/10ktxns-90kaccts.journal
    tools/generatejournal 10000 100000 10  > examples/10ktxns-100kaccts.journal
    tools/generatejournal 10000 1000000 10 > examples/10ktxns-1maccts.journal
    # for hledger-web's paging: a sparse century, ten transactions a year, and a dense year
    tools/generatejournal 1000 20 3    --start=1926-01-01 --days=36500 > examples/century-sparse.journal
    tools/generatejournal 6000 100 4   --start=2026-01-01 --days=365   > examples/dense-year.journal

#    tools/generatejournal.hs 3 5 5 --chinese > examples/chinese.journal  # don't regenerate, keep the simple version
# $ just --set BENCHEXES ledger,hledger  bench

# run the benchmark commands in bench/bench.sh (or another -f file) with quickbench. Eg: just bench -h; just bench -f bench/bench10k.sh -w hledger-1.30,hledger-1.31,hledger-1.32 -n2 -N2
@bench *ARGS:
    printf "Running quick benchmarks (times are approximate, can be skewed):\n"
    which quickbench >/dev/null && quickbench {{ if ARGS =~ '(^| )(-f|--file)' { ARGS } else { "-f bench/bench.sh " + ARGS } }} || echo "quickbench not installed (see bench/bench.sh), skipping"

# @bench-gtime:
#     for args in '-f examples/10ktxns-1kaccts.journal print' '-f examples/100ktxns-1kaccts.journal register' '-f examples/100ktxns-1kaccts.journal balance'; do \
#     echo; \
#     for app in hledger-1.26 hledger-21ad ledger; do \
#     echo; echo $app $args:; \
#     gtime $app $args >/dev/null; \
#     done; \
#     done

# show throughput at various data sizes with the given hledger executable (requires samplejournals)
@bench-throughput EXE:
    echo date:       `date`
    echo system:     `uname -a`
    echo executable: {{ EXE }}
    echo version:    `{{ EXE }} --version`
    for n in 1 2 3 4 5 6 7 8 9 10 100 ; do \
        printf "%3dk txns: " $n; {{ EXE }} stats -f examples/${n}ktxns-1kaccts.journal | tail -1; \
    done
    date

# show throughput at various data sizes with the latest hledger dev build, optimised or not (requires samplejournals)
@bench-throughput-dev:
    stack build hledger
    stack exec -- just bench-throughput hledger

# show throughput of recent hledger versions (requires samplejournals)
@bench-throughput-recent:
    for v in 1.25 1.40 1.52 1.99.4; do printf "\nhledger-$v:\n"; for i in `seq 1 3`; do hledger-$v -f examples/10ktxns-10kaccts.journal stats | grep ^Run; done; done

# @bench-balance-many-accts:
#     quickbench -w hledger-1.26,hledger-21ad,ledger -f bench/bench-many-accts.sh -N2
#     #quickbench -w hledger-1.25,hledger-1.28,hledger-1.29,hledger-1.30,hledger-1.31,hledger-1.32,hledger-21ad,ledger -f bench/bench-many-accts.sh -N2
# @bench-balance-many-txns:
#     quickbench -w hledger-21ad,ledger -f bench/bench-many-txns.sh -N2
# samplejournals bench/bench.sh
# bench: samplejournals tests/bench.tests tools/simplebench \
#   $(call def-help,bench,\
# 	run simple performance benchmarks and archive results\
# 	Requires some commands defined in tests/bench.tests and some BENCHEXES defined above.\
# 	)
# 	tools/simplebench -v -ftests/bench.tests $(BENCHEXES) | tee doc/profs/$(TIME).bench
# 	@rm -f benchresults.*
# 	@(cd doc/profs; rm -f latest.bench; ln -s $(TIME).bench latest.bench)
# criterionbench: samplejournals tools/criterionbench \
# 	$(call def-help,criterionbench,\
# 	run criterion benchmark tests and save graphical results\
# 	)
# 	tools/criterionbench -t png -k png
# progressionbench: samplejournals tools/progressionbench \
# 	$(call def-help,progressionbench,\
# 	run progression benchmark tests and save graphical results\
# 	)
# 	tools/progressionbench -- -t png -k png
# prof: samplejournals \
# 	$(call def-help,prof,\
# 	generate and archive an execution profile\
# 	) #bin/hledgerprof
# 	@echo "Profiling: $(PROFCMD)"
# 	-$(PROFCMD) +RTS $(PROFRTSFLAGS) -RTS
# 	mv hledgerprof.prof doc/profs/$(TIME).prof
# 	(cd doc/profs; rm -f latest*.prof; ln -s $(TIME).prof latest.prof)
# viewprof: prof \
# 	$(call def-help,viewprof,\
# 	generate, archive, simplify and display an execution profile\
# 	)
# 	tools/simplifyprof.hs doc/profs/latest.prof

#{{ STACK }} exec --profile -- hledger +RTS {{ PROFRTSFLAGS }} -RTS -f examples/1000x1000x10.journal {{ CMD }} #>/dev/null
# run a hledger CMD against a sample journal and display the execution profile (build hledgerprof first)
quickprof CMD: #hledgerprof #samplejournals
    bin/hledgerprof +RTS {{ PROFRTSFLAGS }} -RTS -f examples/10ktxns-1kaccts.journal {{ CMD }} #>/dev/null
    @profiterole hledgerprof.prof
    @echo
    @head -20 hledgerprof.prof
    @echo ...
    @echo
    @head -20 hledgerprof.profiterole.txt
    @echo ...
    @echo
    @echo "See hledgerprof.prof, hledgerprof.profiterole.txt, hledgerprof.profiterole.html for more."

# generate and archive a graphical heap profile
@heap: hledgerprof #samplejournals
    echo "Profiling heap with: $PROFCMD"
    {{ PROFCMD }} +RTS -hc -RTS
    t=$(date +%Y%m%d%H%M); mv hledgerprof.hp doc/profs/$t.hp; cd doc/profs; \
        rm -f latest.hp; ln -s $t.hp latest.hp; \
        hp2ps $t.hp; rm -f latest.ps; ln -s $t.ps latest.ps; rm -f *.aux

# viewheap: heap \
# 	$(call def-help,viewheap,\
# 	\
# 	)
# 	$(VIEWPS) doc/profs/latest.ps
# quickheap-%: hledgerprof samplejournals \
# 		$(call def-help,quickheap-"CMD", run some command against a sample journal and display the heap profile )
# 	$(STACK) exec -- hledgerprof +RTS -hc -RTS $* -f examples/10000x1000x10.journal >/dev/null
# 	hp2ps hledgerprof.hp
# 	@echo generated hledgerprof.ps
# 	$(VIEWPS) hledgerprof.ps

# quickcoverage: hledgercov \
# 	$(call def-help,quickcoverage,\
# 	display a code coverage text report from running hledger COVCMD\
# 	)
# 	@echo "Generating code coverage text report for hledger command: $(COVCMD)"
# 	tools/runhledgercov "report" $(COVCMD)
# coverage: samplejournals hledgercov \
# 	$(call def-help,coverage,\
# 	generate a code coverage html report from running hledger COVCMD\
# 	)
# 	@echo "Generating code coverage html report for hledger command: $(COVCMD)"
# 	tools/runhledgercov "markup --destdir=doc/profs/coverage" $(COVCMD)
# 	cd doc/profs/coverage; rm -f index.html; ln -s hpc_index.html index.html
# viewcoverage: \
# 	$(call def-help,viewcoverage,\
# 	view the last html code coverage report\
# 	)
# 	$(VIEWHTML) doc/profs/coverage/index.html

# ** Documenting ------------------------------------------------------------
DOCUMENTING:

# Update manuals - build hledger, regenerate flag docs, regenerate manuals
manuals:
    $STACK build hledger
    ./Shake cmddocs -c
    ./Shake manuals -c

# Update the site's snapshot of the manuals for this branch's major release version.
manuals-site: manuals
    make -C site snapshot-$(just majorver)

# Update the general options help shown in the manuals (doc/common.m4) from hledger's --help output.
generaloptionshelp:
    $STACK build hledger
    tools/generaloptionshelp

# Add latest commit messages to the changelogs. (Runs ./Shake changelogs [OPTS])
changelogs *OPTS:
    ./Shake changelogs {{ OPTS }}

# Check the changelogs for stale resume points, bad issue links, leftover draft markers. (Runs ./Shake changelogs-check)
changelogs-check:
    ./Shake changelogs-check

# Drop any uncommitted changes to the project and package changelogs.
changelogs-reset:
    git checkout */CHANGES.md

# Set changelog headings to the specified commit, or HEAD. Rarely needed now (changelogs auto-relocates rewritten resume points). Run on release branch.
changelogs-catchup *COMMIT:
    #!/usr/bin/env bash
    set -euo pipefail
    just _on-release-branch
    C={{ if COMMIT == '' { `git log -1 --pretty=%h --abbrev=8` } else { COMMIT } }}
    for p in $PACKAGES; do \
      sed -i "0,/^# /s/^# .*$/# $C/" $p/CHANGES.md; \
    done
    sed -i "0,/^# /s/^# .*$/# $C/" doc/CHANGES.md
    echo "Changelog headings have been set to $C"

# Set changelog headings for a full release today. Run on release branch.
changelogs-finalise:
    #!/usr/bin/env bash
    set -euo pipefail
    just _on-release-branch
    date=`gdate -I`
    for p in $PACKAGES; do \
      sed -i "0,/^# /s/^# .*$/# `cat $p/.version` $date/" $p/CHANGES.md; \
    done
    sed -i "0,/^# /s/^# .*$/# `cat .version` $date/" doc/CHANGES.md
    git commit -m ";doc: finalise changelogs for `cat .version` on $date" */CHANGES.md

# see also Shake.hs
# http://www.haskell.org/haddock/doc/html/invoking.html

# update the website (the live one if run on hledger.org)
site: #Shake
    ./Shake -V site 2>&1 | tee -a site.log

# Use the existing Shake executable without recompiling it, so as not to automatially run unreviewed code by hook ? I think this no longer applies.
# site: $(call def-help,site-build, update the hledger.org website (run this on hledger.org, or run "make hledgerorg" elsewhere) )
#     @[ ! -x Shake ] \
#         && echo 'Please run "make Shake" first (manual compilation required for safety)' \
#         || ( \
#             echo; \
#             ./Shake -V site; \
#         ) 2>&1 | tee -a site.log

BROWSEDELAY := '5'
LOCALSITEURL := 'http://localhost:3000/index.html'

# open a browser on the website (in ./site) and rerender when docs or web pages change
@site-watch: #Shake
    (printf "\nbrowser will open in {{ BROWSEDELAY }}s (adjust BROWSE if needed)...\n\n"; sleep $BROWSEDELAY; $BROWSE "$LOCALSITEURL" ) &
    $WATCHEXEC --no-vcs-ignore -e md,m4 -i hledger.md -i hledger-ui.md -i hledger-web.md -r './Shake webmanuals && make -sC site serve'
# --no-vcs-ignore to include site/src/*.md

# restart hledger.org's caddy server, after config changes
site-restart:
    osh -i -c 'hledgerorgssh systemctl restart caddy'

STACKHADDOCK := 'time ' + STACK + ' --verbosity=error haddock --fast --no-keep-going \
    --only-locals --no-haddock-deps --no-haddock-hyperlink-source \
    --haddock-arguments="--no-warnings" \
    '
# workaround for haddock "Module defined in multiple files" trac.haskell.org/haddock/ticket/284
# -ghc-options='-optP-P'

HADDOCKPKGS := 'hledger-lib'

# regenerate haddock docs for the hledger packages
haddock:
    {{ STACKHADDOCK }} {{ HADDOCKPKGS }}

# regenerate haddock docs for the hledger packages and open them
@haddock-and-open:
    just haddock
    just haddock-open

# open the haddock packages contents page in a browser
haddock-open:
    {{ BROWSE }} `$STACK path --local-install-root`/doc/index.html

# # Rerenders all hledger packages. Run make haddock-open to open contents page.
# haddock-watch1: \
#     $(call def-help,haddock-watch, regenerate haddock docs when files change )
#     $(STACKHADDOCK) $(HADDOCK_PKGS) --file-watch --exec='echo done'
# # Rerenders hledger-lib modules, opens hledger-lib contents page.
# haddock-watch2: \
#     $(call def-help,haddock-watch2, regenerate hledger-lib haddock docs when files change )
#     watchexec -r -e yaml,cabal,hs --print-events -- \
#     $(STACKHADDOCK) --verbosity=info $(HADDOCK_PKGS) --exec="'echo done'" hledger-lib --open
# # Rerenders/reopens the Hledger module, without submodules. (Fastest)
# haddock-watch: \
#     $(call def-help,haddock-watch3, quickly regenerate & reload Hledger.hs haddock when files change )
#     watchexec -r -e yaml,cabal,hs --print-events --shell=none -- bash -c 'mkdir -p tmp && rm -f tmp/Hledger.html && haddock -h -o tmp hledger-lib/Hledger.hs --no-warnings --no-print-missing-docs 2>&1 | grep -v "Could not find documentation" && open tmp/Hledger.html'

# hoogle-setup: $(call def-help,hoogle-setup, install hoogle then build haddocks and a hoogle db for the project and all deps )
#     stack hoogle --rebuild
# HOOGLEBROWSER="/Applications/Firefox Dev.app/Contents/MacOS/firefox"   # safari not supported
# hoogle-serve: $(call def-help,hoogle-serve, run hoogle web app and open in browser after doing setup if needed )
#     $(HOOGLEBROWSER) http://localhost:8080 &
#     stack --verbosity=warn hoogle --server
# sourcegraph: \
#     $(call def-help,sourcegraph,\
#     \
#     )
#     for p in $(PACKAGES); do (cd $$p; SourceGraph $$p.cabal); done
# manuals-watch: Shake \
#         $(call def-help,manuals-watch, rerender manuals when their source files change  )
#     ls $(DOCSOURCEFILES) | entr ./Shake -VV manuals
# man-watch: man-watch-hledger \
#         $(call def-help,man-watch, run man on the hledger man page when its source file changes )
# man-watch-%: Shake \
#         $(call def-help,man-watch-PROG, run man on the given man page when its source file changes. Eg make man-watch-hledger-web )
#     $(WATCHEXEC) -r -w $*/$*.m4.md './Shake $*/$*.1 && man $*/$*.1'
# shakehelp-watch: \
#         $(call def-help,shakehelp-watch, rerender Shake.hs's help when it changes)
#     ls Shake.hs | entr -c ./Shake.hs
# The following rule, for updating the website, gets called on hledger.org by:
# 1. github-post-receive (github webhook handler), when something is pushed
#    to the main or wiki repos on Github. Config:
#     /etc/supervisord.conf -> [program:github-post-receive]
#     /etc/github-post-receive.conf
# 2. cron, nightly. Config: /etc/crontab
# 3. manually: "make site" on hledger.org, or "make hledgerorg" elsewhere (cf Makefile.local).

# Generate packages diagrams for the hledger packages.
@packagediags:
    # just packagediag hledger-lib
    # just packagediag hledger
    # just packagediag hledger-ui
    # just packagediag hledger-web
    stack exec -- ghc-pkg dot | tred | dot -Tsvg >packages.svg

# View the packages diagrams.
@packagediags-view:
    # $OPEN hledger-lib/packages.svg
    # $OPEN hledger/packages.svg
    # $OPEN hledger-ui/packages.svg
    # $OPEN hledger-web/packages.svg
    $OPEN packages.svg

# # Generate a packages diagram for a hledger package.
# @packagediag PKG:
#     cd  && stack exec -- ghc-pkg dot | tred | dot -Tsvg >packages.svg

# Generate modules diagrams for the hledger packages.
@modulediags:
    just modulediag hledger-lib
    just modulediag hledger
    just modulediag hledger-ui
    just modulediag hledger-web
    cd hledger && stack exec -- graphmod -q -c Hledger.Cli.Commands | tred | dot -Tsvg >modules-collapsed.svg

# View the modules diagrams.
@modulediags-view:
    $OPEN hledger-lib/modules.svg
    $OPEN hledger/modules.svg
    $OPEN hledger-ui/modules.svg
    $OPEN hledger-web/modules.svg

# Generate a modules diagram for a hledger package.
@modulediag PKG:
    cd {{ PKG }} && stack exec -- graphmod -q | tred | dot -Tsvg >modules.svg

# optimise and commit RELEASING.png diagram after export from obsidian
@releasediag:
    pngquant doc/RELEASING.png -f -o doc/RELEASING.png
    git add doc/RELEASING.png
    git commit -m ';doc:RELEASING.png: update' -- doc/RELEASING.png

# optimise and commit doc-update.png diagram after export from obsidian
@docupdatediag:
    pngquant doc/doc-update.png -f -o doc/doc-update.png
    git add doc/doc-update.png
    git commit -m ';doc:doc-update.png: update' -- doc/doc-update.png

CHANGELOGS := 'CHANGES.md hledger/CHANGES.md hledger-ui/CHANGES.md hledger-web/CHANGES.md hledger-lib/CHANGES.md'

# Show changes since last release in the given CHANGES.md file or all of them. (Run after ./Shake changelogs.)
unreleased *CHANGELOG:
    #!/usr/bin/env osh
    if [[ -z $CHANGELOG ]]; then
        for CHANGELOG in $CHANGELOGS; do
            printf "** $CHANGELOG\n\n"
            just unreleased $CHANGELOG
            echo
        done
    else
        awk '/^#+ /{p=1};/^#+ +[0-9]+\.[0-9].*([0-9]{4}-[0-9]{2}-[0-9]{2})/{exit};p' $CHANGELOG
    fi

# Commit and push FAQ edits.
pushfaq:
    (cd ~/src/hledger/site; git commit -m 'faq' src/faq.md; git push)

# Show diffs between upstream hledger tldr pages and the local copies in this repo.
tldr-diff:
    # XXX JUSTFILEDIR
    diff doc/tldr/upstream doc/tldr | grep hledger

# Save a copy of the full jj log showing all commits and branches.
log-save:
    jj log -r:: >doc/log.txt
    jj log -r:: --color=always >doc/log.color.txt

# log-headtail [y] - show the start and end of the saved log, optionally in color.
log-headtail *COLOR:
    #/usr/bin/env osh
    set -euo pipefail
    LOG=doc/log{{ if COLOR == 'y' { ".color" } else { "" } }}.txt; \
    head $LOG; echo ...; tail $LOG

# Upload a copy of the log to the website, on the side since it's large.
log-push:
    scp -v doc/log*.txt 173.255.213.235:/opt/hledger/site/out

# Update the short version of the hledger script example (by removing docs).
bin-short:
    awk '/^----/ { b=!b; next } !b' bin/hledger-script-example.hs | rg -v '^ *-- \w' > bin/hledger-script-example-short.hs

@site-caching-open:
    $OPEN https://dash.cloudflare.com/f629035917dd3b99b1e37ae20c15ff09/hledger.org/caching/configuration

# ** Releasing ------------------------------------------------------------
RELEASING:

# These are roughly in the order they should be done during release.

# Create or switch to this release branch, and set the version string in various places.
relbranch VER:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ -z {{ VER }} ]] && usage
    BRANCH=$(just _versionReleaseBranch {{ VER }})
    echo "Switching to $BRANCH, auto-creating it if needed"
    just _gitSwitchAutoCreate "$BRANCH"
    echo "Setting {{ VER }} in package.yamls and .version.m4 macros"
    ./Shake setversion {{ VER }} -c
# Too much at once, allow smaller steps.
#    echo "Updating all command help texts for embedding..."
#    ./Shake cmddocs -c
#    echo "Generating all the manuals in all formats...."
#    ./Shake manuals -c
#    # echo "Updating CHANGES.md files with latest commits..."
#    # ./Shake changelogs $COMMIT

# update shell completions in hledger package
@completions:
    make -C hledger/shell-completion/
    echo "now please commit any changes in hledger/shell-completion/"

# Update the release version on the hledger.org Install page (site/src/install.md). NEWVER defaults to ./.version.
installpage *NEWVER:
    tools/installpage {{ NEWVER }}

# Make draft release notes from changelogs. Run on release branch. Run just tools first.
@relnotes:
    just _on-release-branch
    tools/relnotes

# Upload all packages to hackage (run from release branch).
@hackageupload:
    tools/hackageupload $PACKAGES

@hackagerevise:
    $OPEN https://hackage.haskell.org/package/hledger-lib/hledger-lib.cabal/edit
    $OPEN https://hackage.haskell.org/package/hledger/hledger.cabal/edit
    $OPEN https://hackage.haskell.org/package/hledger-ui/hledger-ui.cabal/edit
    $OPEN https://hackage.haskell.org/package/hledger-web/hledger-web.cabal/edit

# Make git tags for a full release today, but don't push them yet. Run on release branch.
reltags:
    #!/usr/bin/env bash
    set -euo pipefail
    just _on-release-branch
    for p in $PACKAGES; do \
      git tag --force --sign $p-`cat $p/.version` -m "Release $p-`cat $p/.version`"; \
    done
    git tag --force --sign `cat .version` -m "Release `cat .version`"
    echo "Release has been tagged!"

# Push the current HEAD to github oldest branch, testing the build with oldest supported GHC.
@oldest:
    git push -f origin HEAD:oldest

# Push the current HEAD to github binaries branch, generating platform binaries.
@ghbin:
    # assumes the github remote is named "origin"
    git push -f origin HEAD:binaries

# Browse the latest run of the platform binaries workflows.
@ghbin-open:
    just ghrun-open binaries-linux-x64
    just ghrun-open binaries-mac-arm64
    just ghrun-open binaries-mac-x64
    just ghrun-open binaries-windows-x64

# Push the current release's tags (made by reltags, named per */.version) to github. Do this after building release binaries and before creating the github release.
reltags-push:
    #!/usr/bin/env bash
    set -euo pipefail
    just _on-release-branch
    TAGS="`cat .version`"
    for p in $PACKAGES; do TAGS="$TAGS $p-`cat $p/.version`"; done
    git push origin $TAGS

# The github release is normally assembled by the release.yml workflow (via just ghrel),
# entirely on github's servers. ghbin-download and ghrel-upload below support ghrel-local,
# the older flow which routes the binaries through the local machine; kept as a fallback
# for release branches that don't have release.yml.

# Download new binaries from the latest runs of the platform binaries workflows, and recompress them.
# If a release tag matching ./.version exists, each run is checked to be built from that tag's commit.
ghbin-download:
    #!/usr/bin/env bash
    set -euo pipefail
    VER=$(just ver)
    TAGCOMMIT=$(git rev-parse -q --verify "refs/tags/$VER^{commit}" || true)
    [[ -n $TAGCOMMIT ]] || echo "note: no $VER tag found, not checking the runs' build commits"
    mkdir -p tmp
    cd tmp
    rm -rf hledger-*64
    for w in binaries-linux-x64 binaries-mac-arm64 binaries-mac-x64 binaries-windows-x64; do
      read -r id sha < <(gh run list --workflow $w --json databaseId,headSha --jq '.[0] | "\(.databaseId) \(.headSha)"')
      if [[ -n $TAGCOMMIT && $sha != "$TAGCOMMIT" ]]; then
        echo "error: latest $w run ($id) was built from commit $sha," >&2
        echo "not the $VER tag's commit $TAGCOMMIT; not downloading" >&2
        exit 1
      fi
      gh run download "$id"
    done
    mv */*.tar .
    gzip -f *.tar
    zip -j hledger-windows-x64.zip hledger-windows-x64/*
    rm -rf hledger-*64

# Create or update a draft github release for the current version, with release notes and
# binaries attached, using the release.yml workflow - the binaries stay on github's servers.
# Run on release branch, after reltags-push, once the binaries-* workflows have succeeded
# for the tagged commit. Safe to re-run.
ghrel:
    #!/usr/bin/env bash
    set -euo pipefail
    just _on-release-branch
    VER=$(just ver)
    BRANCH=$(git branch --show-current)
    gh workflow run release.yml --ref "$BRANCH" -f version="$VER"
    echo "Waiting for the release workflow to start.."
    sleep 5
    RUN=$(gh run list --workflow release.yml -b "$BRANCH" --json databaseId --jq '.[0].databaseId')
    gh run watch "$RUN" --exit-status
    echo "Draft release $VER is ready. Review it (just ghrel-open), then make it public with: just ghrel-publish"

# Like ghrel, but assembling the release locally: create/update the draft release,
# then download the binaries (ghbin-download) and upload them to it (ghrel-upload).
# A fallback for release branches that don't have the release.yml workflow.
ghrel-local:
    #!/usr/bin/env bash
    set -euo pipefail
    just _on-release-branch
    VER=$(just ver)
    if gh release view "$VER" >/dev/null 2>&1; then
      echo "Updating github release $VER's notes"
      doc/ghrelnotes "$VER" | gh release edit "$VER" -F-
    else
      PRERELEASE=$([[ $(just _versionIsPreview "$VER") == y ]] && echo --prerelease || true)
      echo "Creating draft github release $VER"
      doc/ghrelnotes "$VER" | gh release create "$VER" --draft --verify-tag $PRERELEASE --title "$VER" -F-
    fi
    just ghbin-download
    just ghrel-upload
    echo "Draft release $VER is ready. Review it (just ghrel-open), then make it public with: just ghrel-publish"

# Publish the current version's draft github release, making it visible to the world. ⚠
ghrel-publish:
    #!/usr/bin/env bash
    set -euo pipefail
    just _on-release-branch
    VER=$(just ver)
    gh release view "$VER"
    read -p "Publish github release $VER, for all the world to see ? Enter to proceed, ctrl-c to cancel: "
    gh release edit "$VER" --draft=false
    gh release view "$VER" --json url --jq .url

# Browse the latest github release.
@ghrel-open:
    gh release view -w

# Upload release notes to the configured github release.
@ghrel-notes:
    just _on-release-branch
    doc/ghrelnotes `cat .version` | gh release edit `cat .version` -F-

# After ghbin-download: upload the downloaded binaries to the current release branch's github release.
ghrel-upload:
    #!/usr/bin/env bash
    set -euo pipefail
    just _on-release-branch
    VER=$(just ver)
    if [[ $(gh release view "$VER" --json isDraft --jq .isDraft) != true ]]; then
      read -p "Warning! uploading binaries to the published release $VER, are you sure ? Enter to proceed: "
    fi
    gh release upload --clobber "$VER" tmp/hledger-linux-x64.tar.gz
    gh release upload --clobber "$VER" tmp/hledger-mac-arm64.tar.gz
    gh release upload --clobber "$VER" tmp/hledger-mac-x64.tar.gz
    gh release upload --clobber "$VER" tmp/hledger-windows-x64.zip

# After major release: in main, bump versions for a new dev cycle ("OLDVER.99")
@devver:
    #!/usr/bin/env bash
    set -euo pipefail
    RELVER=$(just majorver)
    DEVVER=$RELVER.99
    just _on-main-branch
    echo "Setting versions to $DEVVER.."
    ./Shake setversion "$DEVVER" -c

# ** Installing ------------------------------------------------------------
INSTALLING:

# # copy the current ~/.local/bin/hledger to bin/old/hledger-VER
# @copy-as VER:
#     cp ~/.local/bin/hledger bin/old/hledger-{{ VER }}; echo "bin/hledger-{{ VER }}"

# install hledger binaries as bin/old/hledger*-VER
@installas VER:
    for e in hledger     ; do $STACK install --local-bin-path bin/old $e; mv bin/old/$e bin/old/$e-{{ VER }}; echo "bin/old/$e-{{ VER }}"; done
    for e in hledger-ui  ; do $STACK install --local-bin-path bin/old $e; mv bin/old/$e bin/old/$e-{{ VER }}; echo "bin/old/$e-{{ VER }}"; done
    for e in hledger-web ; do $STACK install --local-bin-path bin/old $e; mv bin/old/$e bin/old/$e-{{ VER }}; echo "bin/old/$e-{{ VER }}"; done

# install all hledger executables as bin/old/hledger*-VER
@installallas VER:
    $STACK install --local-bin-path bin/old
    for e in hledger hledger-ui hledger-web ; do mv bin/old/$e bin/old/$e-{{ VER }}; echo "bin/old/$e-{{ VER }}"; done

# install hledger with stack traces and ghc-debug support enabled, as bin/hledger*-dbg
@installasdbg *STACKARGS:
    $STACK install --local-bin-path bin --flag '*:debug' {{ STACKARGS }} hledger
    for e in hledger ; do mv bin/$e bin/$e-dbg; echo "bin/$e-dbg"; done

# install all hledger executables with stack traces and ghc-debug support enabled, as bin/hledger*-dbg
@installallasdbg *STACKARGS:
    $STACK install --local-bin-path bin --flag '*:debug' {{ STACKARGS }}
    for e in hledger hledger-ui hledger-web ; do mv bin/$e bin/$e-dbg; echo "bin/$e-dbg"; done

# On gnu/linux: can't interpolate GTAR here for some reason, and need the shebang line.
# linux / mac only for now, does not handle the windows zip file.
# download the specified version of github release binaries, for the current OS and ARCH, to bin/old/hledger*-VER
installrel VER:
    #!/usr/bin/env bash

    # The current OS name, in the form used for hledger release binaries: linux, mac, windows or other.
    # can't use $GHC or {{GHC}} here for some reason
    OS=$(ghc -ignore-dot-ghci -package-env - -e 'import System.Info' -e 'putStrLn $ case os of "darwin"->"mac"; "mingw32"->"windows"; "linux"->"linux"; _->"other"')

    # The current architecture, in the form used for hledger release binaries: x64, arm64 or other.
    ARCH=$(ghc -ignore-dot-ghci -package-env - -e 'import System.Info' -e 'putStrLn $ case arch of "x86_64"->"x64"; "aarch64"->"arm64"; "arm"->"arm64"; _->"other"')

    # if [[ "$OS" == "windows" ]]; then
    #   cd bin/old && curl -L https://github.com/hledgerorg/hledger/releases/download/$VER/hledger-$OS-$ARCH.zip | funzip | `type -P gtar || echo tar` xf - --transform "s/$/-$VER/"
    # else
    # fi

    cd bin/old && curl -L https://github.com/hledgerorg/hledger/releases/download/$VER/hledger-$OS-$ARCH.tar.gz | `type -P gtar || echo tar` xzf - --transform "s/\$/-$VER/"

# # download recent versions of the hledger executables from github to bin/hledger*-VER
# get-recent-binaries:
#     for V in 1.32.2 1.31 1.30 1.29.2 1.28 1.27.1; do just get-binaries $OS x64 $V; done
#     just symlink-binaries

# # add easier symlinks for all the minor hledger releases downloaded by get-binaries.
# symlink-binaries:
#     just symlink-binary 1.32.2
#     just symlink-binary 1.29.2
#     just symlink-binary 1.27.1

# add an easier symlink for this minor hledger release (hledger-1.29 -> hledger-1.29.2, etc.)
@symlink-binary MINORVER:
    cd bin && ln -sf hledger-$MINORVER hledger-`echo $MINORVER | sed -E 's/\.[0-9]+$//'`

# ** Info ------------------------------------------------------------
INFO:

# List git tags approximately most recent first (grouped by package). The available fields vary over time.
tags:
    git tag -l --sort=-tag --format='%(refname:short) taggerdate:%(taggerdate:iso8601) committerdate:%(committerdate:iso8601)}'

# Show the last release date and version (of the hledger package).
@rel:
    just rels | head -1

# Show last release date (of the hledger package).
@reldate:
    awk '/^#+ +[0-9]+\.[0-9].*([0-9]{4}-[0-9]{2}-[0-9]{2})/{print $3;exit}' hledger/CHANGES.md

# Show the last release version (of the hledger package).
@relver:
    just rel | awk '{print $2}'

# show commit author names since last release
@relauthors:
    echo "Commit authors since last release:"
    git shortlog -sn `git tag --sort=-creatordate -l '[0-9]*' | head -1`..

# show contributor commits and names in main and site repos since DATE
@contribs YYYY-MM-DD:
    printf "==========\nmain:\n\n"; just contribs-main {{ YYYY-MM-DD }}
    printf "==========\nsite:\n\n"; just contribs-site {{ YYYY-MM-DD }}
    printf "==========\nfinance:\n\n"; just contribs-finance {{ YYYY-MM-DD }}

# show contributor commits and names in the main repo since DATE
@contribs-main YYYY-MM-DD:
    git shortlog -n --perl-regexp --author='^(?!(Simon Michael))' --since {{ YYYY-MM-DD }}

# show contributor commits and names in the site repo since DATE
@contribs-site YYYY-MM-DD:
    git -C site shortlog -n --perl-regexp --author='^(?!(Simon Michael))' --since {{ YYYY-MM-DD }}

# show contributor commits and names in the finance repo since DATE
@contribs-finance YYYY-MM-DD:
    git -C finance shortlog -n --perl-regexp --author='^(?!(Simon Michael))' --since {{ YYYY-MM-DD }}

# Show all release dates and versions (of the hledger package).
@rels:
    awk '/^#+ +[0-9]+\.[0-9].*([0-9]{4}-[0-9]{2}-[0-9]{2})/{printf "%s %s\n",$3,$2}' hledger/CHANGES.md

# Show major release dates and versions (of the hledger package).
@rels-major:
    awk '/^#+ +[0-9]+\.[0-9]+ .*([0-9]{4}-[0-9]{2}-[0-9]{2})/{printf "%s %s\n",$3,$2}' hledger/CHANGES.md

# Show the release notes for VERSION.
@showrelnotes VER:
    awk "/^## .*-${VER//./\\.}$/ {p=1;print;next}; /^## / {p=0}; p" doc/relnotes.md

SCC := 'scc -z --cocomo-project-type semi-detached -f wide -s code'

# count lines of code with scc
scc:
    echo "Lines of code including tests:"
    {{ SCC }} -i hs,sh,m4,hamlet

# count lines of code with scc, showing all files
sccv:
    echo "Lines of code including tests:"
    {{ SCC }} -i hs,sh,m4,hamlet --by-file

# showreleasestats stats: \
#     showreleasedays \
#     showunreleasedchangecount \
#     showloc \
#     showtestcount \
#     showunittestcoverage \
#     showreleaseauthors \
#     showunreleasedcodechanges \
#     showunpushedchanges \
#     $(call def-help,showreleasestats stats,\
#     show project stats useful for release notes\
#     )
# #    showerrors
# FROMTAG=.
# showreleasedays: \
#     $(call def-help,showreleasedays,\
#     \
#     )
#     @echo Days since last release:
#     @tools/dayssincetag.hs $(FROMTAG) | head -1 | cut -d' ' -f-1
#     @echo
# # XXX
# showunreleasedchangecount: \
#     $(call def-help,showunreleasedchangecount,\
#     \
#     )
#     @echo Commits since last release:
#     @darcs changes --from-tag $(FROMTAG) --count
#     @echo

# `ls $(SOURCEFILES)`
# sloc: \
#     $(call def-help,sloc,\
#     \
#     )
#     @sloccount hledger-lib hledger hledger-web
# cloc: \
#     $(call def-help,cloc,\
#     \
#     )
#     @echo
#     @echo "Lines of code as of `date`:"
#     @echo
#     @echo "hledger-lib, hledger"
#     @cloc -q hledger-lib hledger             2>&1 | grep -v 'defined('
#     @echo
#     @echo "hledger-web"
#     @cloc -q hledger-web                     2>&1 | grep -v 'defined('
#     @echo
#     @echo "hledger-lib, hledger, hledger-web"
#     @cloc -q hledger-lib hledger hledger-web 2>&1 | grep -v 'defined('
# showtestcount: \
#     $(call def-help,showtestcount,\
#     \
#     )
#     @echo "Unit tests:"
#     @hledger test 2>&1 | cut -d' ' -f2
#     @echo "Functional tests:"
#     @make --no-print functest | egrep '^ Total' | awk '{print $$2}'
#     @echo
# showunittestcoverage: \
#     $(call def-help,showunittestcoverage,\
#     \
#     )
#     @echo Unit test coverage:
#     @make --no-print quickcoverage | grep 'expressions'
#     @echo
# # showerrors:
# #     @echo Known errors:
# #     @awk '/^** errors/, /^** / && !/^** errors/' NOTES.org | grep '^\*\*\* ' | tail +1
# #     @echo
# # XXX
# showunpushedchanges showunpushed: \
#     $(call def-help,showunpushedchanges showunpushed,\
#     \
#     )
#     @echo "Changes not yet pushed upstream (to `darcs show repo | grep 'Default Remote' | cut -c 17-`):"
#     @-darcs push simon@joyful.com:/repos/hledger --dry-run | grep '*' | tac
#     @echo
# # XXX
# showunreleasedcodechanges showunreleased showchanges: \
#     $(call def-help,showunreleasedcodechanges showunreleased showchanges,\
#     \
#     )
#     @echo "hledger code changes since last release:"
#     @darcs changes --from-tag $(FROMTAG) --matches "not (name docs: or name doc: or name site: or name tools:)" | grep '*'
#     @echo
# # XXX
# showcodechanges: \
#     $(call def-help,showcodechanges,\
#     \
#     )
#     @echo "hledger code changes:"
#     @darcs changes --matches "not (name docs: or name site: or name tools:)" | egrep '^ +(\*|tagged)'
#     @echo
# nix-hledger-version: $(call def-help,nix-hledger-version, show which version of hledger has reached nixpkgs)
#     @curl -s https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/development/haskell-modules/hackage-packages.nix | grep -A1 'pname = "hledger"'
# nix-hledger-versions: $(call def-help,nix-hledger-versions, show versions of all hledger packages in nixpkgs)
#     @curl -s https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/development/haskell-modules/hackage-packages.nix | grep -A1 'pname = "hledger'
# nix-view-commits: $(call def-help,nix-view-commits, show recent haskell commits in nixpkgs)
#     @open 'https://github.com/NixOS/nixpkgs/commits/master/pkgs/development/haskell-modules/hackage-packages.nix'
# list-commits: $(call def-help,list-commits, list all commits chronologically and numbered)
#     @git log --format='%ad %h %s (%an)' --date=short --reverse | cat -n

# show upcoming planned dated tasks
schedule *PERIOD:
    #!/usr/bin/env osh
    P={{ if PERIOD == '' { 'today..30days' } else { PERIOD } }}
    hledger -f doc/SCHEDULE print --forecast=$P

# show recent branches summary with jj
@branches:
    echo "Recent branches:"
    bash -ic 'jjb | head -20'

# show recent branches detail with jj
@branchesv:
    echo "Recent branches (commits):"
    jj log -n 40 -r 'log_default ~ @'

# Show activity over the last N days (eg 7), for This Week In Hledger.
@_lastweek DAYS:
    echo "hledger time last $DAYS days including today (this should be run on a Friday):"
    tt bal hledger -DTS -b "$DAYS days ago" --drop 2
    echo
    echo "By activity type, percentage:"
    tt bal hledger -DTS -b "$DAYS days ago" --pivot t -% -c 1% | tail +1
    echo
    echo "Time log details:"
    tt print hledger -b "$DAYS days ago" | grep -E '^[^ ]|hledger'
    echo
    echo "main repo:"
    git log --format='%C(yellow)%cd %ad %Cred%h%Creset %s %Cgreen(%an)%Creset%C(bold blue)%d%Creset' --date=short --since="$DAYS days ago" --reverse
    echo
    echo "site repo:"
    git -C site log --format='%C(yellow)%cd %ad %Cred%h%Creset %s %Cgreen(%an)%Creset%C(bold blue)%d%Creset' --date=short --since="$DAYS days ago" --reverse
    echo
    echo "finance repo:"
    git -C finance log --format='%C(yellow)%cd %ad %Cred%h%Creset %s %Cgreen(%an)%Creset%C(bold blue)%d%Creset' --date=short --since="$DAYS days ago" --reverse
    echo

# show the sorted, unique files matched by SOURCEFILES
@_listsourcefiles:
    for f in $SOURCEFILES; do echo $f; done | sort | uniq

# show the sorted, unique subdirectories containing hs files
@_listsourcedirs:
    find . -name '*hs' | sed -e 's%[^/]*hs$%%' | sort | uniq

# show the ghc versions used by all stack files
@_listghcversions:
    for F in stack*.yaml; do $STACK --stack-yaml=$F --no-install-ghc exec -- ghc --version; done 2>&1 | grep -v 'To install the correct GHC'

# Show a bunch of debug messages.
@_dbgmsgs:
    rg --sort path -t hs 'dbg.*?(".*")' -r '$1' -o

# # Extract Hledger.hs examples to jargon.j.
# @_jargon:
#   rg '^ *> (.*)' -or '$1' hledger-lib/Hledger.hs > jargon.j
#   echo "wrote jargon.j"

# Extract ledger/hledger/beancount commit stats to project-commits.j.
@_projectcommits:
    # https://hledger.org/reporting-version-control-stats.html
    printf "account ledger\naccount hledger\naccount beancount\n\n" >project-commits.j
    for p in ledger hledger beancount; do git -C ../$p log --format="%cd (%h) %s%n  ($p)  1%n" --date=short --reverse >> project-commits.j; done
    echo "wrote project-commits.j"

# show some big directory sizes
@usage:
    -du -sh .git bin data doc extra `find . -name '.stack*' -prune -o -name 'dist' -prune -o -name 'dist-newstyle' -prune` 2>/dev/null | sort -hr

# hledger time report
time *ARGS:
    hledger -n -f $TIMEDIR/time-all.journal bal hledger -YTA --transpose -0 {{ ARGS }}

# open google search console report for hledger.org
@google-search-console:
    $OPEN 'https://search.google.com/search-console/performance/search-analytics?resource_id=sc-domain%3Ahledger.org&breakdown=page&metrics=CLICKS&hl=en&time_granularity=MONTH&num_of_months=16'

# *** hledger version number helpers
# (as hidden recipes, since just doesn't support global custom functions)
# See doc/RELEASING.md > Glossary.

# First 0-2 parts of a dotted version number.
@_versionMajorPart VER:
    echo {{ replace_regex(VER, '(\d+(\.\d+)?).*', '$1') }}

# Third part of a dotted version number, if any.
@_versionMinorPart VER:
    echo {{ if VER =~ '\d+(\.\d+){2,}' { replace_regex(VER, '\d+\.\d+\.(\d+).*', '$1') } else { '' } }}

# Fourth part of a dotted version number, if any.
@_versionFourthPart VER:
    echo {{ if VER =~ '\d+(\.\d+){3,}' { replace_regex(VER, '\d+(\.\d+){2}\.(\d+).*', '$2') } else { '' } }}

# Is this a dev version number (ending in .99) ? Eg: 1.99, 1.52.99.
@_versionIsDev VER:
    echo {{ if VER =~ '^\d+\.(\d+\.)?99$' { 'y' } else { '' } }}

# Is this a preview version number (a .99 part followed by one more part) ? Eg: 1.99.3, 1.52.99.1.
@_versionIsPreview VER:
    echo {{ if VER =~ '^\d+\.(\d+\.)?99\.\d+$' { 'y' } else { '' } }}

# Show the hledger version number that's configured for the current branch.
@ver:
    cat .version

# Show the hledger major version number that's configured for the current branch.
@majorver:
    just _versionMajorPart $(cat .version)

# Increment a major version number to the next.
# @majorVersionIncrement MAJORVER:
#     python3 -c "print({{MAJORVER}} + 0.01)"

# Appropriate release branch name for the given version number:
# "MAJOR-branch", or "VER-branch" for preview releases.
_versionReleaseBranch VER:
    #!/usr/bin/env bash
    MAJOR=$(just _versionMajorPart {{ VER }})
    if [[ $(just _versionIsDev {{ VER }}) == y ]]; then
      echo "{{ VER }} is not a releasable version" >&2
      exit 1
    elif [[ $(just _versionIsPreview {{ VER }}) == y ]]; then
      echo "{{ VER }}-branch"
    else
      echo "$MAJOR-branch"
    fi

# *** git helpers

# Does the named branch exist in this git repo ?
@_gitBranchExists BRANCH:
    git branch -l {{ BRANCH }} | grep -q {{ BRANCH }}

# Switch to the named git branch, creating it if it doesn't exist.
_gitSwitchAutoCreate BRANCH:
    #!/usr/bin/env bash
    if just _gitBranchExists {{ BRANCH }}; then
      git switch {{ BRANCH }}
    else
      git switch -c {{ BRANCH }}
    fi

# show a precise git-describe version string
@describe:
    git describe --tags --match 'hledger-[0-9]*' --dirty

# show all commit author names
@authors:
    echo "Commit authors ($(git shortlog -sn | wc -l | awk '{print $1}'))":
    git shortlog -sn

# show all commit author names and emails
@authorsv:
    echo "Commit authors ($(git shortlog -sn | wc -l | awk '{print $1}'))":
    git shortlog -sne

# Check that we're on a release branch. (Hopefully the latest.)
_on-release-branch:
    #!/usr/bin/env bash
    set -euo pipefail
    BRANCH=$(git branch --show-current)
    if [[ ! $BRANCH =~ ^[0-9].*-branch ]]; then
        echo "You are currently on $BRANCH branch. Please switch to the latest release branch."
        exit 1
    fi

# Check that we're on the main branch.
_on-main-branch:
    #!/usr/bin/env bash
    set -euo pipefail
    BRANCH=$(git branch --show-current)
    if [[ ! $BRANCH =~ main ]]; then
        echo "You are currently on $BRANCH branch. Please switch to the main branch."
        exit 1
    fi

# ** News ------------------------------------------------------------
NEWS:

# # Convert DATEARG to an ISO date. It can be an ISO date, number of recent days, or nothing (meaning last release date).
# @_datearg *DATEARG:
#     echo {{ if DATEARG == '' { `just reldate` } else { if DATEARG =~ '^\d+$' { `dateadd $(date +%Y-%m-%d) -$DATEARG` } else { DATEARG } } }}

#dateround := 'dateround -n'
dateround := 'dateround'

# If DATE is provided, return it, otherwise the date two fridays ago.
@_dateorsecondlatestfriday *DATE:
    echo {{ if DATE == '' { `gdate -I -d "$($dateround today -- -fri) - 1 week"` } else { DATE } }}

# If DATE is provided, return today's date, otherwise the most recent friday's (possibly today).
@_todayorlatestfriday *DATE:
    echo {{ if DATE == '' { `$dateround today -- -fri` } else { `$GDATE -I` } }}

# If DATE is provided, return tomorrow's date, otherwise last friday's.
@_tomorroworlatestfriday *DATE:
    echo {{ if DATE == '' { `$dateround today -- -fri` } else { `$GDATE -I -d tomorrow` } }}

# Show a draft This Week In Hledger post, with activity between the last two fridays (by default)
twih:  # *DATE:
    #!/usr/bin/env osh
    #BEG=`just _dateorsecondlatestfriday  $DATE`
    END=`just _todayorlatestfriday $DATE`
    cat <<EOS:  # the colon helps the vscode just highlighter
    == TWIH notes: ========================================

    last release: `just rel`
    
    `gcal`
    `just timelog $DATE`

    `just worklog $DATE`

    recent issue activity:
    https://github.com/hledgerorg/hledger/issues?q=sort:updated-desc


    == TWIH draft (in clipboard) : ========================

    EOS:
    (cat <<EOS:
    ---

    ## This Week In Hledger $END
    
    **sm**
    `just commitlog $DATE`
    
    **Misc**
    recent discussions: <https://hledger.org/support.html>
    
    **Quotes**
    
    - **
    
    - **
    
    <https://hledger.org/news.html#this-week-in-hledger-$END>

    
    EOS:
    ) | tee /dev/tty | pbcopy

GITSHORTFMT := "--format='%ad %s' --date=short"

# Show commits briefly in the three hledger repos between the last two fridays or since this date
commitlog *DATE:
    #!/usr/bin/env osh
    BEG=`just _dateorsecondlatestfriday $DATE`
    END=`just _todayorlatestfriday $DATE`
    printf "** commits in $BEG..$END\n"
    printf "** hledger\n"
    git log {{ GITSHORTFMT }} --since $BEG --until $END --reverse | sed -E -e 's/ ;/ /'
    printf "** site\n"
    git -C site log {{ GITSHORTFMT }} --since $BEG --until $END --reverse | sed -E -e 's/ ;/ /'
    printf "** finance\n"
    git -C finance log {{ GITSHORTFMT }} --since $BEG --until $END --reverse | sed -E -e 's/ ;/ /'
    printf "** plaintextaccounting.org\n"
    git -C ../plaintextaccounting.org log {{ GITSHORTFMT }} --since $BEG --until $END --reverse | sed -E -e 's/ ;/ /'
    echo

WORKLOG := "../../notes/CLOUD/hledger.md"

# Show dates logged in hledger work log.
@worklogdates:
    rg '^#+ (\d{4}-\d{2}-\d{2})' -or '$1' "$WORKLOG"

# Show hledger work logged since this date or days ago or last release
worklog *DATE:
    #!/usr/bin/env osh
    BEG=`just _dateorsecondlatestfriday  $DATE`
    END=`just _todayorlatestfriday $DATE`
    # LOGGEDDATES=`just worklogdates`
    BEGLOGGED=`just worklogdates | $GHC -e "getContents >>= putStrLn . head . dropWhile (< \"$BEG\") . (++[\"9999-99-99\"]) . lines"`
    # ENDLOGGED=`just worklogdates | $GHC -e "getContents >>= putStrLn . head . takeWhile (< \"$END\") . (++[\"9999-99-99\"]) . dropWhile (< \"$BEG\") . (++[\"9999-99-99\"]) . lines"`
    printf "hledger work log in $BEG..:\n"
    # printf "hledger work log in $BEGLOGGED..$ENDLOGGED:\n"
    awk "/^#### $BEGLOGGED/{p=1;print;next}; /^## /{p=0}; p" "$WORKLOG"
    # awk "/^#### $BEGLOGGED/{p=1;print;next}; /#### $ENDLOGGED/{p=0}; /^## /{p=0}; p" "$WORKLOG"
    echo

# Show hledger-related time logged between the last two fridays or since this date
timelog *DATE:
    #!/usr/bin/env osh
    BEG=`just _dateorsecondlatestfriday  $DATE`
    END=`just _todayorlatestfriday $DATE`
    END1=`just _tomorroworlatestfriday $DATE`
    printf "hledger time logged in $BEG..$END:\n\n"
    hledger -f $TIMELOG bal -S --format '%-20(account) %12(total)' hledger -b $BEG -e $END1
    echo
    hledger -f $TIMELOG print hledger -b $BEG -e $END1 | rg '^2|hledger'
    echo

# Copy some text to the system clipboard if possible
@_clip TEXT:
    type -P pbcopy >/dev/null && (printf "$TEXT" | pbcopy)

# Show matrix chat since this date or days ago or last release
chatlog *DATE:
    #!/usr/bin/env osh
    DATE=`just _dateorsecondlatestfriday $DATE`
    JUMP="/jumptodate $DATE"
    just _clip "$JUMP"
    echo "** matrix:    https://matrix.hledger.org, $JUMP"
    echo

# Show mail list discussion since this date or days ago or last release
maillog *DATE:
    #!/usr/bin/env osh
    DATE=`just _dateorsecondlatestfriday $DATE`
    DATE2=`$GDATE -d $DATE +"%b %-d"`
    echo "** mail list: https://list.hledger.org, since $DATE2 ($DATE)"
    echo

# Show /r/plaintextaccounting posts since this date or days ago or last release
redditlog *DATE:
    #!/usr/bin/env osh
    DATE=`just _dateorsecondlatestfriday $DATE`
    DAYS=`datediff $DATE now`
    echo "** reddit:    https://www.reddit.com/r/plaintextaccounting/new, since $DAYS days ago ($DATE)"
    echo

# Show #hledger-tagged mastodon toots since this date or days ago or last release
tootlog *DATE:
    #!/usr/bin/env osh
    DATE=`just _dateorsecondlatestfriday $DATE`
    just _clip "#hledger after:$DATE"
    echo "** mastodon:  https://fosstodon.org/search, #hledger after:$DATE , #plaintextaccounting after:$DATE"
    echo

# Show recent PTA blog posts added on plaintextaccounting.org
bloglog:
    #!/usr/bin/env osh
    echo "** pta.o:  https://plaintextaccounting.org/#`date +%Y`"
    echo

# Some evil works against this..
#     echo "open https://www.reddit.com/r/plaintextaccounting/new, copy links since $DAYS days ago ($DATE), paste into obsidian, select, cut, and paste here for cleaning (in emacs shell use C-c C-d, C-c C-r)"
#     just redditclean > $$.tmp
#     printf "\n\n\n\n\n"
#     cat $$.tmp
#     rm -f $$.tmp
#
# Clean links copied from old.reddit.com.
# @redditclean:
#     rg '^(\[.*?]\([^\)]+\)).*self.plaintextaccounting' -or '- $1\n' -

# ** AI ------------------------------------------------------------
AI:

ai-help:
    #!/bin/bash
    cat <<EOS
    AI usage scripts.
    These are in groups, corresponding to various data sources:
    1. ccusage         - prints reports from this machine's recent claude code logs
    2. ccusage.journal - a cached snapshot of the above as a hledger journal
    3. aicommits.csv   - a snapshot of the "AI usage:" disclosure lines in commit messages
    4. ai.journal      - a permanent journal of project's monthly ai usage, with entries imported from the above and added manually
    Notes:
    - ccusage.journal's numbers drop over time (when regenerated) as old logs get purged.
      Eg compare just ai-ccusagej-monthly -Xkt -c1.kt; j ai-aij-monthly -Xkt -c1.kt
    - in recent period, ccusage.journal should be similar to the usage recorded in SM commits.
    - ai.journal should be >= the usage recorded in all commits. (It may record additional AI usage not tied to commits.)

    EOS
    just h ai-

# Show today's logged local-machine claude code usage. Accepts ccusage options, like -b.
@ai-ccusage-today *CCUSAGEOPTS:
    ccusage -O daily -s `date +%Y%m%d` {{ CCUSAGEOPTS }}

# Watch today's logged local-machine claude code usage. Accepts ccusage options, like -b.
@ai-ccusage-watch *CCUSAGEOPTS:
    watch -n10 -c -d 'ccusage -O daily -s `date +%Y%m%d` {{ CCUSAGEOPTS }}| tail +8'

# Export ccusage's local-machine claude code usage data as CSV.
@ai-ccusage-csv CCUSAGECMD='monthly' *CCUSAGEOPTS:
    ccusage -O {{ CCUSAGECMD }} {{ CCUSAGEOPTS }} -j | jq -r ' \
      first(.. | arrays | select(length > 0 and (.[0] | type == "object"))) \
      | [.[] | with_entries(select(.value | type != "array" and type != "object"))] \
      | (.[0] | keys_unsorted) as $k \
      | ($k | @csv), (.[] | [.[$k[]]] | @csv) \
    '

AIDIR := 'doc/ai'

# Regenerate ccusage.journal from ccusage's data, and add lots of unit conversions.
ai-ccusagej-regen:
    #!/usr/bin/env bash
    {
    cat <<'EOS'
    # Local user's claude code usage based on available chat logs.
    include commodities.journal
    account ai
    EOS
    just ai-ccusage-csv daily | hledger -f csv:- --rules {{ AIDIR }}/ccusage.rules print -c '1,000,000 t'
    } > {{ AIDIR }}/ccusage.journal

# Run a hledger command on ccusage.journal. If you need it to be up to date, run just ai-ccusagej-regen first.
@ai-ccusagej *HLEDGERARGS:
    hledger -f {{ AIDIR }}/ccusage.journal {{ HLEDGERARGS }}

# Show a claude code usage balance report, vertically.
@ai-ccusagej-bal *BALARGS:
    just ai-ccusagej bal --transpose -N --layout=bare {{ BALARGS }}

# Show claude code monthly usage.
@ai-ccusagej-monthly *BALARGS:
    just ai-ccusagej-bal -M -b 2026 {{ BALARGS }}

# Show claude code daily usage this month.
@ai-ccusagej-daily *BALARGS:
    just ai-ccusagej-bal -D -p1..tomorrow {{ BALARGS }}

# Regen ccusage.journal, then show recent daily usage.
ai-ccusagej-recent *BALARGS:
    #!/bin/bash
    just ai-ccusagej-regen
    just ai-ccusagej-bal -DE -p-7days..tomorrow -Xkt --title "Latest_AI_usage,_$(date | sed 's/ /_/g')" {{ BALARGS }}

# Run ai-ccusagej-recent repeatedly.
@ai-ccusagej-recent-watch *BALARGS:
    while true; do just ai-ccusagej-recent -c1.kt {{ BALARGS }}; echo; read -p "press enter to update.."; done

CCPROJECTS := '~/.claude/projects'

# jq program summing output tokens in claude code transcripts, between epoch times $from and $to.
# Deduplicates by message and request id, since a response is often logged on several lines (ccusage session --id doesn't do this).
AI_OUTPUT_JQ := '[.[] | select(.message.usage) | select((.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdate) as $t | $t >= $from and $t < $to)] | unique_by([.message.id, .requestId]) | [.[].message.usage.output_tokens] | add // 0'

# Show one claude code session's output tokens (kt), including its subagents; optionally only those since a time (gdate syntax). Unlike the daily numbers, not affected by other concurrent sessions.
ai-session SESSIONID SINCE='1970-01-01':
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    files=({{ CCPROJECTS }}/*/{{ SESSIONID }}*.jsonl)
    if [[ ${#files[@]} -ne 1 ]]; then echo "expected one transcript matching {{ SESSIONID }}, found ${#files[@]}" >&2; exit 1; fi
    main=${files[0]}
    from=$(gdate -d '{{ SINCE }}' +%s)
    cat "$main" "${main%.jsonl}"/subagents/*.jsonl \
      | jq -s -r --argjson from "$from" --argjson to 9999999999 '({{ AI_OUTPUT_JQ }}) / 1000 | "\(.) kt"'

# List the claude code sessions active on a day (default today), with their output tokens (kt) that day, and the total.
ai-sessions DATE='today':
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    day=$(gdate -d '{{ DATE }}' +%F)
    from=$(gdate -d "$day" +%s)
    to=$(gdate -d "$day +1 day" +%s)
    for main in $(find {{ CCPROJECTS }}/ -mindepth 2 -maxdepth 2 -name '*.jsonl' -newermt "$(gdate -d @$from "+%F %T")"); do
      kt=$(cat "$main" "${main%.jsonl}"/subagents/*.jsonl | jq -s --argjson from "$from" --argjson to "$to" '({{ AI_OUTPUT_JQ }}) / 1000')
      [[ $kt == 0 ]] || printf "%8.1f kt  %s  %s\n" "$kt" "$(basename "$main" .jsonl)" "$(basename "$(dirname "$main")")"
    done | sort -rn | awk '{print} {t+=$1} END {printf "%8.1f kt  total\n", t}'

# Extract the "AI usage:" disclosure lines from commit messages to aicommits.csv.
@ai-commits-csv:
    tools/aicommits > {{ AIDIR }}/aicommits.csv
    echo "wrote {{ AIDIR }}/aicommits.csv"

# Run a hledger command on aicommits.csv. If you need it to be up to date, run just ai-commits-csv first.
@ai-commits *HLEDGERARGS:
    hledger -f {{ AIDIR }}/aicommits.csv {{ HLEDGERARGS }}

# Regen ccusage.journal, then import any new summarised month entries from there to ai.journal.
@ai-aij-import *IMPORTARGS:
    just ai-ccusagej-regen
    cd {{ AIDIR }} \
    ; hledger -f ccusage.journal reg ai -ME -e thismonth -O csv \
    | hledger -f ai.journal import csv:- --rules ai.rules {{ IMPORTARGS }}

# Run a hledger command on ai.journal.
@ai-aij *HLEDGERARGS:
    hledger -f {{ AIDIR }}/ai.journal {{ HLEDGERARGS }}

# Show a project ai usage balance report.
@ai-aij-bal *BALARGS:
    just ai-aij bal --transpose -N --layout=bare {{ BALARGS }}

# Show project monthly usage.
@ai-aij-monthly *BALARGS:
    just ai-aij-bal -M {{ BALARGS }}


# ** Misc ------------------------------------------------------------
MISC:

# ensure the Shake script is compiled
Shake: # Shake.hs
    ./Shake.hs

# ensure the tools/*.hs scripts are compiled
tools:
    tools/compile.sh

# Files to include in emacs TAGS file:
# 1. haskell source files with hasktags -e (or ctags -aeR)
# 2. other source files recognised by (exuberant) ctags and not excluded by .ctags. Keep .ctags up to date.
# 3. some extra files missed by the above, as just their file names (for tags-search, tags-query-replace etc.)

TAGFILES := WEBTEMPLATEFILES + DOCSOURCEFILES + TESTFILES + HPACKFILES + CABALFILES + 'Shake.hs'

# generate emacs TAGS file for haskell source and other project files, and list the tagged files in TAGS.files
@etags:
    hasktags -e $SOURCEFILES
    for f in $TAGFILES; do printf "\f\n$f,1\n" >>TAGS; done

# list the files tagged in TAGS
@etags-ls:
    rg -v '[\f\x7f ]' TAGS | rg -r '$1' '^(.*?([0-9]+)?),[0-9,]+*'

# remove TAGS files
@etags-clean:
    rm -f TAGS

# run some tests to validate the development environment
# check-setup:
#     run some tests to validate the development environment\
#     )
#     @echo sanity-checking developer environment:
#     @({{ SHELLTEST }} --exclude=/_ checks \
#         && echo $@ PASSED) || echo $@ FAILED

# sym-link some directories required by hledger-web dev builds
symlink-web-dirs:
    echo "#ln -sf hledger-web/config  # disabled, causes makeinfo warnings"
    ln -sf hledger-web/messages
    ln -sf hledger-web/static
    ln -sf hledger-web/templates

# symlink tools/commitlint as .git/hooks/commit-msg
installcommithook:
    ln -s ../../tools/commitlint .git/hooks/commit-msg

# run tests locally, push main to github ci, wait for tests to pass there, refreshing every INTERVAL (default:10s), then push to github main.
@push *INTERVAL:
    just functest --hide && tools/push {{ INTERVAL }}

# Browse the All workflows status page on github.
@ghworkflows-open:
    $OPEN https://ci.hledger.org

# Browse the latest run of the named workflow.
@ghrun-open WORKFLOW:
    gh run view --web $(just _ghrun-id {{ WORKFLOW }})

# Get the id of the latest run of the named workflow.
@_ghrun-id WORKFLOW:
    gh run list --workflow {{ WORKFLOW }} --json databaseId --jq '.[0].databaseId'

# stackclean: \
#     $(call def-help-hide,stackclean, remove .stack-work/ dirs )
#     $(STACK) purge
# cleanghco: \
#     $(call def-help-hide,cleanghc, remove ghc build leftovers )
#     rm -rf `find . -name "*.o" -o -name "*.hi" -o -name "*.dyn_o" -o -name "*.dyn_hi" -o -name "*~" | grep -vE '\.(stack-work|cabal-sandbox|virthualenv)'`
# #rm -f `fd -I '\.(hi|o|dyn_hi|dyn_o)$'`
# clean: cleanghco \
#     $(call def-help,clean, default cleanup (ghc build leftovers) )
# Clean: stackclean cleanghco cleantags \
#     $(call def-help,Clean, thorough cleanup (stack/ghc leftovers/tags) )
# # reverse = $(if $(wordlist 2,2,$(1)),$(call reverse,$(wordlist 2,$(words $(1)),$(1))) $(firstword $(1)),$(1))

# Show a beancount sample holdings report.
@holdings-beancount *ARGS:
    bean-report examples/example.beancount holdings {{ ARGS }}

# Show a rledger sample holdings report.
@holdings-rledger *ARGS:
    rledger report examples/example.beancount holdings {{ ARGS }}

# Show a hledger sample holdings report.
@holdings-hledger *ARGS:
    hledger -f examples/lots/lots.journal holdings {{ ARGS }}

# Show several holdings report examples.
holdings-examples:
    just holdings-beancount
    just holdings-beancount --by root-account
    just holdings-beancount --by account
    just holdings-beancount --by commodity
    just holdings-beancount --by currency
    just holdings-rledger
    just holdings-hledger

