# Developer docs

Contributor, developer, and maintainer docs.
These aim to describe and communicate the structure, processes and
workflows of the hledger project - "the machine that makes the machine".

These mostly are kept in doc/ in the main hledger repo,
and then symlinked into the hledger_site repo for rendering on hledger.org.

**Start here**

- [CONTRIBUTING](CONTRIBUTING.md) - ways to help, by role
- [DEVFAQ](DEVFAQ.md) - developer FAQ
- [DEVWORKFLOWS](DEVWORKFLOWS.md) - tools, building, testing, GHCI, working on docs
- [RULES](RULES.md) - the repo's policies, on one page
- [AI](AI.md) - AI usage policy
- [README](dev-README.md) - the project README

**Code and tests**

- [CODE](CODE.md) - architecture and package overview
- [FILES](FILES.md) - repo and working copy layout
- [TESTS](TESTS.md) - test suites and how to run them
- [ERRORS](ERRORS.md) - error message standards and examples
- [BENCHMARKS](BENCHMARKS.md) - performance measurement

**Specs**

- [SPEC-journal](SPEC-journal.md) - journal syntax
- [SPEC-finalising](SPEC-finalising.md) - the journal finalisation pipeline
- [SPEC-special-postings](SPEC-special-postings.md) - inferred postings and their rules
- [SPEC-lots](SPEC-lots.md) - lot tracking
- [SPEC-holdings](SPEC-holdings.md) - the holdings command
- [SPEC-print](SPEC-print.md) - print behaviour

**Process**

- [COMMITS](COMMITS.md) - commit message conventions
- [PULLREQUESTS](PULLREQUESTS.md) - pull request guidelines
- [ISSUES](ISSUES.md) - issue tracker conventions and views
- [REGRESSIONS](REGRESSIONS.md) - regression tracking
- [RELEASING](RELEASING.md) - release process
- [VERSIONNUMBERS](VERSIONNUMBERS.md) - version numbering policy
- [DOCS](DOCS.md) - documentation structure and maintenance
- [TRANSLATING](TRANSLATING.md) - contributing a language

**Project**

- [ROADMAP](ROADMAP.md) - where the project is going
- [DECISIONS](DECISIONS.md) - notable design decisions
- [ACHIEVEMENTS](ACHIEVEMENTS.md) - achievements to unlock
- [IMPACT](IMPACT.md) - the project's intended impact
- [CLIMATE](CLIMATE.md) - environmental cost and benefit
- [FINANCE](FINANCE.md) - project finances
- [CREDITS](CREDITS.md) - contributors
- [This Week In Hledger 2023-2024](news.md) - a weekly project news digest, archived

See also:

- <https://deepwiki.com/hledgerorg/hledger> - an AI-generated presentation of hledger's user and dev docs.
  Use with caution, but they look rather useful, as an alternate overview / map.
  Also you can ask it questions.

Dev notes on joyful.com:

- <https://joyful.com/hledger>
- <https://joyful.com/PTA+transaction+balancing>
- <https://joyful.com/PTA+lot+tracking>
- <https://joyful.com/hledger+lot+tracking>
- <https://joyful.com/hledger+workflow+2025>
- <https://joyful.com/hledger+project+report+2024>

## Links

**Discussion:**
<https://hledger.org/support>\
\
**Github:**\
main repo: <https://code.hledger.org>

[commits](https://github.com/hledgerorg/hledger/commits),
<https://ci.hledger.org>,
<https://nightly.hledger.org>,
<https://release.hledger.org>

<https://bugs.hledger.org>,
<https://wishes.hledger.org>,
<https://regressions.hledger.org>,
[ISSUES](ISSUES.md)

<https://prs.hledger.org>,
<https://draftprs.hledger.org>,
<https://readyprs.hledger.org>,
<https://assignedprs.hledger.org>,
<https://unassignedprs.hledger.org>,
[PULLREQUESTS](PULLREQUESTS.md)

site repo: <https://site.hledger.org>

finance repo: <https://finance.hledger.org>

related repos:\
[![Github topic: #hledger](https://img.shields.io/badge/Github_topic-%23hledger-green)](https://github.com/topics/hledger?o=desc&s=updated)\
[![Github topic: #plaintext-accounting](https://img.shields.io/badge/Github_topic-%23plaintext--accounting-green)](https://github.com/topics/plaintext-accounting?o=desc&s=updated)\
[![Github topics: *accounting*](https://img.shields.io/badge/Github_topics-%2Aaccounting%2A-green)](https://github.com/search?type=topics&q=accounting)\
\
**Hackage:**\
packages:
[hledger-lib](https://hackage.haskell.org/package/hledger-lib),
[hledger](https://hackage.haskell.org/package/hledger),
[hledger-ui](https://hackage.haskell.org/package/hledger-ui),
[hledger-web](https://hackage.haskell.org/package/hledger-web),
[hledger-diff](https://hackage.haskell.org/package/hledger-diff),
[hledger-iadd](https://hackage.haskell.org/package/hledger-iadd),
[hledger-interest](https://hackage.haskell.org/package/hledger-interest),
[hledger-irr](https://hackage.haskell.org/package/hledger-irr),
[\*hledger\*](https://hackage.haskell.org/packages/search?terms=hledger)\
reverse deps:
[hledger-lib](https://packdeps.haskellers.com/reverse/hledger-lib),
[hledger](https://packdeps.haskellers.com/reverse/hledger),
[hledger-ui](https://packdeps.haskellers.com/reverse/hledger-ui),
[hledger-web](https://packdeps.haskellers.com/reverse/hledger-web)\
[![Hackage](https://img.shields.io/hackage/v/hledger.svg?logo=Haskell&label=Hackage&colorB=brightgreen)](https://hackage.haskell.org/package/hledger)\
\
**Stackage:**\
[build-constraints.yaml](https://github.com/fpco/stackage/blob/master/build-constraints.yaml)\
[open hledger-related issues](https://github.com/fpco/stackage/search?q=hledger+is%3Aopen&type=Issues)\
packages:
[hledger-lib](https://www.stackage.org/package/hledger-lib),
[hledger](https://www.stackage.org/package/hledger),
[hledger-ui](https://www.stackage.org/package/hledger-ui),
[hledger-web](https://www.stackage.org/package/hledger-web)\
versions:
[hledger-lib](https://www.stackage.org/package/hledger-lib/snapshots),
[hledger](https://www.stackage.org/package/hledger/snapshots),
[hledger-ui](https://www.stackage.org/package/hledger-ui/snapshots),
[hledger-web](https://www.stackage.org/package/hledger-web/snapshots)\
[![Stackage LTS](https://repology.org/badge/version-for-repo/stackage_lts/hledger.svg?header=Stackage+LTS)](https://www.stackage.org/lts/package/hledger)
[![Stackage LTS](https://repology.org/badge/version-for-repo/stackage_nighly/hledger.svg?header=Stackage+Nightly)](https://www.stackage.org/lts/package/hledger)\
\
**Repology:**\
[quick hledger packaging status](https://repology.org/metapackage/hledger/badges),
[detailed hledger packaging status](https://repology.org/project/hledger/versions),
[information for hledger](https://repology.org/project/hledger/information),
[all \*hledger\* packages](https://repology.org/metapackages/?search=hledger)\
\
**Homebrew:**\
[hledger](https://formulae.brew.sh/formula/hledger)\
our [homebrew requested installs in last 365 days](https://formulae.brew.sh/analytics/install-on-request/365d):\
2025: #1632 of 28k, top 6%\
2023: #1821 of 24k, top 8%\
2020: #1520 of 10k, top 15%
<!--
2025-02-18: 2681
-->
\
**Debian:**\
source packages:
[haskell-hledger-lib](https://tracker.debian.org/pkg/haskell-hledger-lib),
[bugs](https://bugs.debian.org/cgi-bin/pkgreport.cgi?package=haskell-hledger-lib),
[haskell-hledger](https://tracker.debian.org/pkg/haskell-hledger),
[bugs](https://bugs.debian.org/cgi-bin/pkgreport.cgi?package=haskell-hledger),
[haskell-hledger-ui](https://tracker.debian.org/pkg/haskell-hledger-ui),
[bugs](https://bugs.debian.org/cgi-bin/pkgreport.cgi?package=haskell-hledger-ui),
[haskell-hledger-web](https://tracker.debian.org/pkg/haskell-hledger-web),
[bugs](https://bugs.debian.org/cgi-bin/pkgreport.cgi?package=haskell-hledger-web)\
stable:
[hledger](https://packages.debian.org/stable/hledger),
[bugs](https://bugs.debian.org/cgi-bin/pkgreport.cgi?package=hledger;dist=stable),
[hledger-ui](https://packages.debian.org/stable/hledger-ui),
[bugs](https://bugs.debian.org/cgi-bin/pkgreport.cgi?package=hledger-ui;dist=stable),
[hledger-web](https://packages.debian.org/stable/hledger-web),
[bugs](https://bugs.debian.org/cgi-bin/pkgreport.cgi?package=hledger-web;dist=stable)\
testing:
[hledger](https://packages.debian.org/testing/hledger),
[bugs](https://bugs.debian.org/cgi-bin/pkgreport.cgi?package=hledger;dist=testing),
[hledger-ui](https://packages.debian.org/testing/hledger-ui),
[bugs](https://bugs.debian.org/cgi-bin/pkgreport.cgi?package=hledger-ui;dist=testing),
[hledger-web](https://packages.debian.org/testing/hledger-web),
[bugs](https://bugs.debian.org/cgi-bin/pkgreport.cgi?package=hledger-web;dist=testing)\
unstable:
[hledger](https://packages.debian.org/unstable/hledger),
[bugs](https://bugs.debian.org/cgi-bin/pkgreport.cgi?package=hledger;dist=unstable),
[hledger-ui](https://packages.debian.org/unstable/hledger-ui),
[bugs](https://bugs.debian.org/cgi-bin/pkgreport.cgi?package=hledger-ui;dist=unstable),
[hledger-web](https://packages.debian.org/unstable/hledger-web),
[bugs](https://bugs.debian.org/cgi-bin/pkgreport.cgi?package=hledger-web;dist=unstable)\
all:
[\*hledger\*](https://packages.debian.org/search?searchon=names&keywords=hledger)\
Popularity contest install stats:
[hledger](https://qa.debian.org/popcon-graph.php?packages=hledger),
[hledger-ui](https://qa.debian.org/popcon-graph.php?packages=hledger-ui),
[hledger-web](https://qa.debian.org/popcon-graph.php?packages=hledger-web)\
\
**Ubuntu:**\
source packages:
[haskell-hledger-lib](https://launchpad.net/ubuntu/+source/haskell-hledger-lib),
[bugs](https://bugs.launchpad.net/ubuntu/+source/haskell-hledger-lib),
[haskell-hledger](https://launchpad.net/ubuntu/+source/haskell-hledger),
[bugs](https://bugs.launchpad.net/ubuntu/+source/haskell-hledger),
[haskell-hledger-ui](https://launchpad.net/ubuntu/+source/haskell-hledger-ui),
[bugs](https://bugs.launchpad.net/ubuntu/+source/haskell-hledger-ui),
[haskell-hledger-web](https://launchpad.net/ubuntu/+source/haskell-hledger-web),
[bugs](https://bugs.launchpad.net/ubuntu/+source/haskell-hledger-web)\
binary packages:
[\*hledger\*](https://packages.ubuntu.com/search?suite=all&searchon=names&keywords=hledger)\
\
**Gentoo:**
[\*hledger\*](https://packages.gentoo.org/packages/search?q=hledger),
[\*hledger\* overlays](https://gpo.zugaina.org/Search?search=hledger)\
\
**Fedora:**
[hledger](https://packages.fedoraproject.org/pkgs/hledger/hledger/),
[\*hledger\*](https://packages.fedoraproject.org/search?query=hledger),
[Haskell SIG](https://fedoraproject.org/wiki/Haskell_SIG)\
\
**Void Linux:** [package search](https://voidlinux.org/packages/)->hledger\
\
**Nix:** [\*hledger\*](https://hydra.nixos.org/search?query=hledger)\
\
**Sandstorm:**
[hledger web app & reviews](https://apps.sandstorm.io/app/8x12h6p0x0nrzk73hfq6zh2jxtgyzzcty7qsatkg7jfg2mzw5n90),
[issues](https://github.com/hledgerorg/hledger/issues?utf8=✓&q=label%3A%22platform%3A%20sandstorm%22%20)\
\
**Reference:** [fosskers GHC compatibility chart](https://www.fosskers.ca/en/blog/base)\
\
**Old trello planning board:** <https://trello.hledger.org>\
\
**hledger-web demo:** <https://demo.hledger.org>\
**hledger GHCJS demo:** <https://hledger.fiatjaf.com>, <https://github.com/fiatjaf/hledger-web> \

<!--
hledger-api demo
[api-demo.hledger.org/api/v1/accounts](https://api-demo.hledger.org/api/v1/accounts),
[api-demo.hledger.org/swagger.json](https://api-demo.hledger.org/swagger.json),
[in swagger editor](https://editor2.swagger.io/#/?import=api-demo.hledger.org/swagger.json&no-proxy)\
[unfinished angular sample app](https://api-demo.hledger.org) ([code](https://github.com/hledgerorg/hledger/tree/main/hledger-api/examples/angular))
-->

<!-- The Debian packages:
3 source:
haskell-hledger-lib
haskell-hledger
haskell-hledger-web
8 binary:
hledger
hledger-web
libghc-hledger-dev
libghc-hledger-doc
libghc-hledger-prof
libghc-hledger-lib-dev
libghc-hledger-lib-doc
libghc-hledger-lib-prof
-->
