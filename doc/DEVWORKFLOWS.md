# Developer workflows

## Get developer tools

Ensure [`git`](https://git-scm.com) is installed. On Windows, it comes with stack.

Ensure [`stack`](https://haskellstack.org) is installed
(or if you're a [cabal](https://www.haskell.org/cabal/) expert, feel free to use that.)

Ensure [`just`](https://just.systems) and a recent bash are installed.
Most project automation tasks are just scripts; run `just` in the main repo to list them,
or `just h REGEX` to list the ones matching REGEX.
(On mac, /bin/bash is too old; install a newer one, eg with `brew install bash`.)

Here are some more tools used by some tasks:

- [`shelltestrunner`](https://hackage.haskell.org/package/shelltestrunner) runs hledger's functional tests (needed for `just functest`).
- [`ghcid`](https://hackage.haskell.org/package/ghcid) gives real-time GHC feedback as you make code changes (needed for `just ghcid`).
- [`watchexec`](https://watchexec.github.io) re-runs commands when files change.
- [`quickbench`](https://github.com/simonmichael/quickbench) measures and reports time taken by commands (needed for `just bench`).
- [`hasktags`](https://hackage.haskell.org/package/hasktags) generates tag files for quick code navigation in editors like Emacs and vim.
- [`profiterole`](https://hackage.haskell.org/package/profiterole) and [`profiteur`](https://hackage.haskell.org/package/profiteur) summarise and render GHC profiles.
- For browsing and editing Haskell code, popular tools include: Emacs, Vim, VS Code, IDEA..

Eg:

    stack install shelltestrunner ghcid hasktags
    git clone https://github.com/simonmichael/quickbench; cd quickbench; stack install  # must run in source dir

## Project scripts: just and Shake

`Justfile` in the main repo's top directory is the starting point for scripts automating hledger project tasks,
using [just](https://just.systems). Run `just` to list them, or `just h REGEX` to list those matching REGEX.
A short alias such as `j` is handy.

`Shake.hs` complements the Justfile: tasks needing file dependencies or more complex code,
such as building the manuals and website docs, are scripted there, often with a corresponding `just` alias.
Run `./Shake.hs` once to compile it (or `just Shake`), then `./Shake` to list its scripts.
`just -n RECIPE` shows the commands a just recipe would run.

Makefiles are still used in a few subdirectories, like `site/` and `finance/`.
Additional helper scripts and tools are kept in `tools/`.

## Get the code

    git clone https://github.com/hledgerorg/hledger
    cd hledger

## Review code

- review and discuss new [pull requests](http://prs.hledger.org) and commits on github
- build hledger and test the latest changes in your own repo
- read the existing code docs and source (see [CODE](CODE.md))
- send feedback or discuss via [chat or mail list](support.md)

## Build in place

[Install > Build from source](install.md#build-from-source) has the maintained build instructions,
including required C libraries and troubleshooting; see there first. In short:

    stack build hledger    # just the CLI (and hledger-lib); or hledger-ui, hledger-web, or no argument for all

This fetches the required GHC version and haskell dependencies from the stackage snapshot configured in `stack.yaml`,
then builds the hledger package(s). This can take a while the first time!

To build with a different GHC version, use one of the other stack-*.yaml files, eg:

    stack --stack-yaml stack910.yaml build hledger

## Type-check quickly

A full `stack build hledger` is slow (about 11s) after touching a core module like `Types.hs`,
because of cascading recompilation. To just type-check a module, without generating code, in about 2s:

```
stack exec -- ghc -fno-code -fforce-recomp \
  -Wall -Wno-incomplete-uni-patterns -Wno-missing-signatures -Wno-orphans -Wno-type-defaults -Wno-unused-do-bind \
  -DDEVELOPMENT -DVERSION="\"VER\"" \
  -ihledger-lib -ihledger \
  MODULE.hs
```

where VER is the current version in `hledger/package.yaml`, and MODULE.hs is the module you changed
(eg `hledger-lib/Hledger/Data/Lots.hs`).
Then build with stack when you need the binary, eg before running functional tests.
`just ghcid` (below) is an alternative that keeps a GHCI session loaded.

## Run in place

    stack exec -- hledger     # ARGS...
    stack exec -- hledger-ui  # ARGS...
    stack exec -- which hledger

## Build and install

This builds and also copies the hledger executables to `~/.local/bin` or the Windows equivalent
(which you should [add to your `$PATH`](install.md#path)).

    stack install    # hledger hledger-ui ...

## Run package tests

Runs the test suites defined by each hledger package (unit tests, doctests).

    stack test    # PKG...

## Run benchmarks

Times the end-user commands in `bench/bench.sh` using quickbench:

    just bench

See [PERFORMANCE](PERFORMANCE.md) for this and the other ways to measure performance.

## Run functional tests

Builds hledger and runs the unit tests and the shelltestrunner tests defined in hledger/test/ and bin/.
Requires [shelltestrunner](https://hackage.haskell.org/package/shelltestrunner) (`stack install shelltestrunner`).

    just functest

## Run doctests

Runs the unit tests embedded in haddock documentation. Slow, requiring its own build of hledger-lib.

    just doctest

## Run haddock tests

Checks for anything that would break haddock doc generation.

    just haddocktest

## Run most tests

Runs embedded-file checks, functional tests (including unit tests), and doctests.

    just test

See more test-related scripts with `just h test`.

## Use GHCI

GHCI is GHC's [REPL](https://en.wikipedia.org/wiki/Read%E2%80%93eval%E2%80%93print_loop),
useful for exploring and calling code interactively.

If you try to run GHCI (or things based on it, like ghcid)
right after cloning the hledger repo, you might see an error about CPP macros, eg like
[on #961](https://github.com/hledgerorg/hledger/issues/961#issuecomment-459283412).
To fix this, build the hledger packages once, eg `stack build hledger`.

Get a GHCI prompt for the hledger CLI (and hledger-lib):

    just ghci

Get a GHCI prompt for hledger-ui or hledger-web:

    just ghci-ui
    just ghci-web

See more GHCI-related scripts with `just h ghci`.
Or use stack directly, eg:

    cd hledger; stack ghci hledger

hledger-web also needs to find some things in its current directory (like the static/ directory).
This normally just works, if not please [send details](https://github.com/hledgerorg/hledger/issues/274).

## Run hledger-web in development

Some ways to run hledger-web while working on it:

- `yesod devel`: runs in developer mode, rebuilds automatically when config, template, static or haskell files change
(but only files in the hledger-web package):
```cli
$ (cd hledger-web; yesod devel)
```

- [yesod-fast-devel](https://hackage.haskell.org/package/yesod-fast-devel)
  may be a good alternative, also reloads the browser page

- `stack ghci`: runs the server in developer mode from GHCI.
Changes to static files like hledger.js will be visible on page reload;
to see other changes, restart it as shown.
```cli
$ (cd hledger-web; stack ghci hledger-web)
hledger-web> :main --serve   # restart: ctrl-c, :r, enter, ctrl-p, ctrl-p, enter
```

- `just ghci-web`: runs the server in developer mode from GHCI, also
interpreting the hledger-lib and hledger packages so that :reload picks
up changes in those packages too:
```cli
$ just ghci-web
ghci> :main --serve
```

See also [Use GHCI](#use-ghci) above.

## Use ghcid for watching GHC/GHCI

[ghcid](https://hackage.haskell.org/package/ghcid) is the most reliable and fastest way to see GHC's feedback,
and optionally run tests or a GHCI command, as you edit.
We run it via just, for convenience and to watch multiple packages rather than just one.
Run `just h ghcid` to list related scripts.

Watch for compile errors in hledger-lib and hledger:

    just ghcid

Watch compile errors and the output of some hledger command:

    ghcid -c 'just ghci' -T ':main -f a.j bal --budget -N'

## Use --file-watch for watching stack

stack's --file-watch flag will re-run build/test/bench when source files or package.yaml/cabal files change. Eg:

    stack test hledger --file-watch

Rerun a single functional test as you change it:

    watchexec -w hledger/test/journal/assertions.test just functest -i budget.*19

## Add a test

- identify what to test
- choose the test type: unit ? functional ? benchmark ? (see [TESTS](TESTS.md))
- currently expected to pass or fail ?
- figure out where it goes
- write test, verify expected result
- get it committed

## Fix a bug or add a feature

- research, discuss, validate the issue/feature on chat/list/bug tracker
- look for related tests, run the tests and check they are passing
- add a test ?
- develop a patch
- include any related issue numbers in the patch name, eg: "fix for blah blah (#NNN)"
- get it committed

## Get your changes accepted

Follow the usual github workflow:

- fork the main hledger repo on github,
- git clone it to your local machine,
- git commit, after (?) pulling and merging the latest upstream changes
- git push back to github,
- open a pull request on github,
- follow up on any discussion there.

If you're new to this process, [docs.github.com](https://docs.github.com) may be useful.

## Add yourself to the contributor list

- after getting something into the main branch, read and sign the [contributor list & agreement](https://hledger.org/contributors.html). Or, [ask](support.md) to be added.
- give yourself a high five!

## Work on docs

The manuals and some other docs are generated by [Shake](#project-scripts-just-and-shake):

    ./Shake            # list Shake rules
    ./Shake manuals    # regenerate the man/info/txt/web manuals (then stack build to embed them)
    ./Shake cmddocs    # regenerate the CLI commands' help texts
    ./Shake Clean      # remove all files generated by Shake

The hledger.org website is built from the [hledger_site](https://github.com/hledgerorg/hledger_site) repo;
see [DOCS](DOCS.md) for more about the documentation system.
