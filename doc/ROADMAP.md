# ROADMAP

Ideas of where the hledger project should be going next.
Being listed here suggests a bit of commitment, perhaps even a schedule.

See also: [ACHIEVEMENTS](ACHIEVEMENTS.md)

## 2026

**Goals** (SM, 2026-02):

Some goals for 2.x:

- continue and improve 1.x's reliability
- excellent lots/capital gains tracking
- more interoperability/convertibility
- more speed
- more customisation paths

and:

- more use of AI as a dev tool; clarify policies
- more use of jj to simplify version management
- more aggressive cleanup and simplification of code/doc/process/finance..
- easier contribution

and for 1.x:

- continued installability/usability
- preserve the stable/known hledger 1.x feature set
- preserve the non-AI-assisted codebase; draw a line between pre and post-AI eras

**2.0 strategy**

Summary of discussion [Thoughts on hledger 2 #2547](https://github.com/hledgerorg/hledger/issues/2547):

**Positions**

**Simon's motivations**: drop costly cruft, marketing power of "2.0", lot tracking as flagship feature, AI-era demarcation, decouple from the 3-month release cycle.

**New users (rickles42, Daniii44)**: Beancount's v2->v3 transition was a cautionary tale -- intermingled docs, broken companion tools, unclear what works with which version. Don't repeat that.

**adept (collaborator)**: don't break compatibility without a clear goal that requires it. History is full of needless rewrites that killed projects.

**Recommended: "Boring 2.0"**

Stay on master, release 2.0 when ready. Don't maintain parallel long-lived branches.

1. **Linear release path**: 1.52 -> 1.99.1 (preview) -> 1.99.2 -> ... -> 2.0. Avoids the cost of maintaining two diverging trunks.

2. **Minimise breaking changes; make them opt-in first**: new behaviours behind flags (like `--lots`), old behaviours deprecated with warnings for a release or two, then removed. Proven pattern (Rust editions, Python `__future__`, GHC extensions).

3. **Lot tracking alone justifies 2.0**: it's a large, data-model-impacting feature. Combined with accumulated improvements, it's enough. Bundling too many breaking cleanups risks the Beancount trap.

4. **Keep docs unified**: a single docset with "New in 2.0" / "Changed in 2.0" callouts, not two divergent doc trees.

5. **AI demarcation is worth noting but shouldn't drive versioning**: it's a process change, not user-facing. Mention in release notes, not a reason to break compatibility.

**Key Principle**

Take the marketing win (call it 2.0) but keep the technical disruption minimal.

**Current most likely plan:**

- Keep using one master branch.
- On next release day (march 1st), release both 1.52 (minor updates) and 1.99.1 (2.0 preview 1, with lot tracking).
- Don't intentionally break anything, except in the usual way (as rarely as possible, with easy workarounds and deprecation periods).

## 2025

- progress on automated lot tracking
- fix hledger-ui --watch memory leak
- up-to-date, effective project finance reports
- easier file/script management when importing
- easier setup & get started process

## 2024

**Targets:**
- hledger 1.41, december
- hledger 1.40, september
- hledger 1.34, june
- hledger 1.33, april

## 2023

**Targets:**
- hledger 1.32, december
- hledger 1.31, september
- hledger 1.30, june
  - demos: built in asciinema demos and maintenance process *done, 4 simple demos*
  - ghc 9.6 support *partly done, hledger-web is blocked on deps*
  - process/tools improvement *done*
  - docs improvement *done: 115 doc commits + 112 site commits, manual cleanups & rewrites*
- hledger 1.29, march

**Goals:**
  - CSV extensibility: workflows to obtain, use, develop, share, contribute ready-to-use CSV rules
  - Scripts extensibility: workflows to obtain, use, develop, share, contribute ready-to-use scripts
  - Interop: clear ledger & beancount import/export how-tos documenting issues & workarounds
  - Better installer: more robust, binary-installing
  - Bar charts: simple built in bar charts
  - Investment: clear updated how-to documenting available tools & best practices for common needs (price fetching, lot reducing, lot reporting, cost reporting, gains reporting)

**Priorities:**
- newcomer/learner experience: docs, installers, demos
- customiser/contributor experience: easy csv rules install/contrib, scripts install/contrib
- maintainer experience: reduce tech/doc/process/issue debt, increase velocity
- marketing/community: news updates, mastodon presence
- interop: solve Ledger/Beancount reading/writing/conversion
- features: charts, investment

**Mission:**
1. Make plain text accounting more usable and useful for all
2. Bring relief to people experiencing financial and financial technology stress
3. Help people and communities in all countries increase their financial mastery and freedom
4. Help grow a shared global culture of accountability and sustainability
5. Starting with this project and ourselves.
<!-- see also: sponsor.md, faq.md -->

## 2020

**Targets:**

- hledger 1.19, september
  - account transactions register, stricter/more correct handling of
    unbalanced multicommodity transactions (#1177), Track & show
    deposited lots (#1022), Report unrealized capital gains/losses
    (#1029)
- hledger 1.18, june
  - more effective CI setup, updated home page, quickstart, tutorials
    etc., negative matching in CSV rules,
- hledger 1.17, march
  - field matching in CSV rules, reduce install hassles with terminfo C
    lib (?), more import/export options, simple console charts,
    refreshed home page, faq, tutorials, manuals,

**Priorities:**
- Documentation: Improve the docs.
- Effectiveness: Improve getting-started experience, just-works quality, practicality,
real-world usefulness.
- Investment: Improve suitability for investment tracking
([#1015](https://github.com/hledgerorg/hledger/issues/1015))
- Charts: Add charts and more visual appeal.
- Correctness: More support for enforcing correctness & accounting rules.

## 2019
**Targets:**
- hledger 1.16, december
  - ghc 8.8 support, more powerful CSV conversion, updated home page,
    faq, manuals, reduce install hassles with terminfo C lib
