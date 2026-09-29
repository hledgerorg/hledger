# Developer FAQ

<!-- toc -->

<!-- ## Developing hledger -->

## How do I get/build the hledger source ?

```cli
$ git clone https://github.com/hledgerorg/hledger
$ cd hledger
$ stack build hledger    # or hledger-ui, hledger-web, or no argument to build all
```
[Install > Build from source](install.md#build-from-source) has the maintained build instructions,
including required C libraries, other build methods, and troubleshooting.

## What other repos are there ?

There are three official repos:
- <https://github.com/hledgerorg/hledger> - the main hledger repo, for hledger, hledger-ui and hledger-web. Shortcut url: <https://code.hledger.org>
- <https://github.com/hledgerorg/hledger_site> - the hledger.org website
- <https://github.com/hledgerorg/hledger_finance> - the hledger project's financial ledger

And third-party add-ons and tools (hledger-iadd, hledger-utils, full fledged hledger, hledger-flow, etc.) have their own repos.

## How do I run a build in place ?

After building with stack,
```cli
$ stack exec -- hledger [ARGS]    # or hledger-ui, hledger-web
```

Or after building with cabal,
```cli
$ cabal exec -- hledger [ARGS]
```

## How do I install a build in PATH ?

```cli
$ stack install
```
This installs the hledger executables to `~/.local/bin`. You should have this directory configured in $PATH.
Or you can install to another directory with `--local-bin-path`.
It builds the executables first if needed.
You can specify `hledger`, `hledger-ui` or `hledger-web` as an argument to build/install just that executable.

If you use cabal, it has a similar command; the argument is required.
It will install executables to `~/.cabal/bin`:
```cli
$ cabal install all:exes
```

## How do I build/run with ghc-debug support ?

You might need to stop background builders like HLS, to avoid a fight over the build flag
(in VS Code, run the command "Haskell: Stop Haskell LSP server").

Then build lib and executable(s) with the `ghcdebug` flag:
```cli
$ stack build --flag='*:ghcdebug'
```

When the build is right, --version should mention ghc-debug:
```
$ stack exec -- hledger --version
... with ghc debug support
```

And when you run at debug level -1, -2 or -3 the output should mention ghc-debug:
```cli
$ hledger CMD --debug=-1    # run normally, and listen for ghc-debug commands
$ hledger CMD --debug=-2    # pause for ghc-debug commands at program start (doesn't work)
$ hledger CMD --debug=-3    # pause for ghc-debug commands at program end (doesn't work)
Starting ghc-debug on socket: ...
```

Now in another window, you can run [ghc-debug-brick](https://hackage.haskell.org/package/ghc-debug-brick) and it will show the hledger process (until it ends). Press enter to connect. If it fails,
- you might need to clear out stale sockets: `rm -f ~/.local/share/ghc-debug/debuggee/sockets/*`
- you might need to kill stale hledger processes: `pkill -fl hledger`
- with --debug=-2 or -3 it fails with `rts_resume: called from a different OS thread than rts_pause`, 
  so use --debug=-1 instead. This works best with the long-running hledger-ui or hledger-web;
  with hledger, you'll need a big enough data file so that you have time to connect before it finishes.
  Once connected, press `p` to pause the program.

At this point, you can explore memory/profile information, save snapshots, resume execution, etc.

Or, instead of ghc-debug-brick you can write a [ghc-debug-client](https://hackage.haskell.org/package/ghc-debug-client) script to extract specific information.

## How do I write a parser for hledger journals ? Should I ?

A few things that might help:

- [hledger manual: Amounts](dev/hledger.md#amounts) (the manual is a kind of spec)
- [SPEC-journal](SPEC-journal.md)
- [CODE](CODE.md)
- the parsers in Hledger.Read.JournalReader and Hledger.Read.Common

But: "it is not easy to get all the edge cases right"

Agreed, and that is a massive understatement :-)
It's not impossible to provide a near-equivalent reimplementation, but a ton of work, even with AI assistance.
See rustledger for a project that's doing this with Beancount (and hledger-macos for a project that's doing a bit of this with hledger).

If you're doing this, it's important to define your scope -

- Just surface parsing, to get what's explicit in the journal; or also apply hledger semantics to fill in the implicit parts ?
- Parse a simpler subset of journal format, enough for my own journals; or full journal format, required to parse other people's journals ?
- A pure new implementation; or am I allowed to run hledger (or link with it) ?

If you can run the hledger command line tool, you could let it do the hard parsing and inferring,
and get the data out with something like `hledger print -O json`.

Or if you're using haskell (or some language that can link with a haskell library),
you could link with the hledger or hledger-lib packages and call hledger's routines directly.
