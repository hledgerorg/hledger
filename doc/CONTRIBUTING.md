# Contributor Quick Start

New contributors of all kinds are always welcome in the hledger project. 
We invite you to jump in, and thank you!

There are many ways to help. Browse the ideas below,
and/or say hello in the [chat](support.md) and we'll help find you a useful job.

## Developer quick start

Install these prerequisites:

- [git](https://git-scm.com)
- [stack](https://haskellstack.org) (or [cabal](https://www.haskell.org/cabal/), but project scripts use stack)
- [just](https://just.systems), which runs our project scripts
- bash, used by the project scripts (on mac, a newer one than /bin/bash: `brew install bash`)
- [shelltestrunner](https://hackage.haskell.org/package/shelltestrunner), which runs our functional tests: `stack install shelltestrunner`

Get and build the code (for more details and help with build problems, see [Build from source](install.md#build-from-source)):

    git clone https://github.com/hledgerorg/hledger
    cd hledger
    stack build hledger    # or hledger-ui, hledger-web, or no argument to build all

Run the executable you just built:

    stack exec -- hledger    # ARGS...

Run the tests:

    just functest    # unit and functional tests; add --hide for less output
    just test        # all tests; slower, requires a second build for doctests

For more workflows (GHCI, ghcid, benchmarks, docs generation..) see [Developer workflows](DEVWORKFLOWS.md),
and for more project scripts run `just` in the main repo.

## Visitor / passer-by ?

- Give feedback on the site and your impressions of the project, small or large, good or bad. This is valuable.

## New user ?

- Report your new user experiences, small or large, good or bad. This is valuable.

## Tech supporter ?

- Share what you've learned so far to help others. This is a quadruple win -
  it helps them, improves your own understanding, builds community, and frees up maintainer time!
- Add translation to your language. Starting with the [tldr](https://github.com/hledgerorg/hledger/tree/main/doc/tldr) has high value. Or if you want to spend minimal effort, then just translate the [top level account names](https://github.com/hledgerorg/hledger/tree/main/examples/i18n). To translate hledger's own report headings and interfaces, see [TRANSLATING](TRANSLATING.md); no programming needed.

## Funder ?

- Become a financial backer: [Sponsor hledger](sponsor.md)
- Contribute or pledge bounties on issues you care about
- Ask your organization to contribute
- Work on project [finance](FINANCE.md) - accounting, fundraising, sustainability..

## Tester ?

- Test installation on platforms you have access to
- Test examples, advice, and links in the docs
- Run the latest release or developer build in daily use
- Run [tests](DEVWORKFLOWS.md#run-package-tests)
- Run [benchmarks](DEVWORKFLOWS.md#run-benchmarks)
- Report packaging, documentation, UX, functional, performance issues (<https://bugs.hledger.org/new>)
- Test new releases, report regressions and collect regression finder bounties
- Discuss and help analyse problems via chat/mail list/issue tracker

## Bug wrangler ?

- Respond to issue reports when needed, especially if they are from new reporters
- Add appropriate labels to issues to categorise them
- Follow up on inactive/stalled issues, help move things forward
- Link/merge related issues
- Keep an overview of the issue tracker, report stats & trends
- Improve issues urls & dashboard(s)
- Help ensure a consistently good bug-reporting and PR-contributing experience

## Bug fixer ?

- Get familiar with issue tracker, issue labels, shortcut urls, issue dashboards..
- Review open bug reports
- Try to fix or help fix some
- Fix regressions and collect regression fixer bounties

## Developer ?

- See the [Developer quick start](#developer-quick-start) above
- Give feedback on your experience using the hledger packages
- Suggest API improvements
- See the [Developer FAQ](DEVFAQ.md) and other [Developer docs](dev.md).

## Technical writer ?

- Get familiar with the documentation, website and online presence; review and test
- Get familiar with the doc/site source files and generation process (see [DOCS](DOCS.md) and [DEVWORKFLOWS](DEVWORKFLOWS.md#work-on-docs))
- Help improve user, contributor, process docs, translation

## Web designer / webmaster ?

- Review and help improve our web presence

## Graphic designer ?

- Review and improve logos, graphics, design language
- Contribute illustrations, diagrams, cartoons, mockups

## Packager ?

- Start/test/improve hledger's packaging on various platforms
- Find/assist/take over from existing packagers
- Improve packaging-related docs/links
- Develop mac or windows installers

## Marketer / communicator ?

- Clarify project goals, value proposition, brand, mission, story
- Monitor product-market fit
- Identify new opportunities
- Influence developer priorities
- Spread the word!

## Product designer ?

- Contribute design input to discussions in issue tracker and elsewhere
- Develop your whole-system view of the hledger "product" (user software, docs, online presence, new user experience etc.)

## Community builder/moderator ?

- Participate in [support](support.md) channels
- As a regular member or moderator, help to resolve/report incidents
- Help uphold and improve our community structures and dynamics

## Project manager ?

- Monitor, report on project progress and performance
- Research, compare and report on successful projects, related projects
- Identify collaboration opportunities
- Assist with marketing, communication, outreach
- Assist with maintainer tasks

## Maintainer / co-maintainer ?

- Manage and ship releases
- Manage the project roadmap
- Clarify/update goals and principles
- Resolve issues
- Serve the community
