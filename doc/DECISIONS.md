# Decisions

A partial list of notable development decisions / design choices..

## 2022

### Replace "transaction price" terminology with "cost"

"Transaction price" never quite stuck. "Cost" is simpler, shorter, more intuitive, consistent with `--cost` and "cost reporting", and more distinct from "market price".

There is an (acceptable) ambiguity: "cost" could mean the `@ UNITCOST` price attached to the amount, or the total cost when the amount is converted (`QUANTITY * UNITCOST`).

Status: as of 2023Q1 this has been done in the manuals and is slowly ongoing in the code.

## 2023

### Plugin types

We will document and support where feasible several distinct kinds of plugin, written in haskell or other languages,
such as reader, processor, writer, formatter, command. See <https://hledger.org/scripting.html#plugin-types>.

## 2025

I think the keyword-first style for directives is right for us (`open 2025-01-01 ...`, not `2025-01-01 open ...`).
It avoids polluting/breaking transaction descriptions, it's similar to P, 
it keeps directives and transactions visually distinct,
and consistently beginning with letters and numbers respectively.

Yes we should support declaring aliases with alias: tags on account directives.

## 2026

### Release hledger 2.0 this year, with two main themes: lots and AI-assisted development

hledger 2 will explore ethical AI-assisted development, 
and will leverage that to ship automated lots and gains tracking.
There will be a substantial period for preview releases, discussion and testing before the 2.0 release.

### Shift "cost" terminology to "transacted cost" or "transacted price"

To distinguish transacted costs (@) from cost basis ({}).

### Compute realised gain from the disposal postings only

The generated gain posting is sized from `Σ aquantity × (B − T)`
over non-acquire postings with both basis and transacted cost — not from
the entry's full cost-basis residual. This isolates real capital gain
from acquire-side bookkeeping mistakes (eg a typo'd `{B}` or a fee being
double-counted into basis).

### Disposals balance at cost basis (historical cost accounting)

2026-09, #2731. Disposal entries get a single realised gain posting, and are
understood to balance at cost basis: the disposed units count as `q × B`,
the gain posting supplies `q × (T − B)`, and the proceeds are `q × T`.
Previously an `equity:unrealised-gain` counter posting was also generated so
that disposals balanced at transacted cost; but with no revaluation postings
ever crediting that account, it accumulated a phantom balance equal to minus
the cumulative realised gains, so `bse` failed to balance even after
everything was sold. The alternative, mark-to-market accounting (keeping the
counter posting and generating revaluation postings as prices change), is
legitimate but more complex, and historical cost is what hledger 1 users
already do. Implementation: the balancer sets aside postings tagged
`_ptype:gain` (equivalent to basis balancing, since `q×B + q×(T−B) = q×T`,
and checkable before lot matching); the gain amount is verified after lot
matching. `-B`/`--value=cost` still converts at transacted cost (a possible
follow-up). Revaluation postings could be added later as an optional layer.

### Don't enforce basis = transacted cost in acquisitions by default

Acquires with `{B} @ T` where `B ≠ T`, are accepted by default, for better compatibility
with other apps (hledger 1, Ledger, Beancount, rustledger, acc, etc.). 
Docs recommend users to always keep `B = T`, and to use the `basis` check to check this,
with reasons provided (prevent wrong gain caused by basis typos).
The new check might be moved into strict mode some day, but not yet.

### Amount keys are commodity plus transacted cost only

`MixedAmountKey`, which decides which amounts combine in `MixedAmount` arithmetic and aggregated reports,
was simplified to commodity plus transacted cost.
Cost basis was removed from it, since in `--lots` mode lot identity is carried by lot subaccounts,
and no report aggregates by cost basis.
Transacted cost stays, because balance assignments and balance inference rely on keeping
same-commodity, different-cost amounts separate.
(Background: doc/NOTE-amount-keys.md in git history, removed 2026-09.)

### hledger-web is read only by default on a public address

When listening on a non-local address, hledger-web now defaults to read-only;
allowing writes requires saying so explicitly.
The safe default matters more than the convenience of the permissive one.

### Journal-adjacent data directories

CSV `source` and `archive` rules, and `import`, now work relative to the journal's data directory
rather than the rules file's directory, establishing a convention of journal-adjacent
`data/`, `data/archive/`, `rules/` and `prices/` directories.
Rationale: a journal plus its inputs, rules and fetched data should be one relocatable unit.

### Config files can no longer specify which command to run

Config files can no longer provide the first argument to specify which command to run -
that was confusing and made the CLI's argument parsing hard to reason about.
For similar reasons, `--conf`/`--no-conf` written inside a config file are also ignored.

### Consolidate documentation under the `help` command

`help` becomes the single entry point for hledger's docs:
it shows an overview by default,
the `commands` command is replaced by `help commands`,
--help is available via `help usage`,
it can open key website pages, etc.

### Detach from the tldr-pages project

Letting the tldr-pages project control part of our docs, and keeping in sync,
limited our content quite a lot (commands only, specific formatting rules)
and added lots of overhead. We'll leave the existing hledger docs in the tldr-pages repo,
for others to maintain. It's not essential that they be there, as having docs built in
to the program itself is more useful and efficient. But we'll keep using the format
for inspiration.
`--tldr` is renamed `--examples` and `help examples`.
Our local copy of the tldr pages, in `doc/tldr/`, will be moved under `examples/`,
which will become more integrated with `help examples`.

### Drop the `demo` command

The demos were too few, too costly to create and update,
and won't provide enough benefit over docs and examples.

### Syntax and parsing relaxations

### A single tab is not accepted as the "two space delimiter"

This was added in 1.99.4 for Ledger compatibility, then reverted in 2026-09,
because it added a source of incompatibility between hledger 1 and hledger 2.

### Apostrophe and underscore are accepted as digit group marks.

For Switzerland and for programmers.

### Inferred amounts no longer affect a commodity's display precision.

Amounts inferred to balance an entry no longer influence global display precisions,
or the entry's local balancing precision. Only explicitly-written amounts
(and those inferred from balance assignments) do.
This changes behaviour for the better, avoiding unexpected/unwanted increases in display precision.

### Autodetect the base currency

hledger guesses a journal's base currency, eg for fetching prices, and shows it in `stats`.

### Keep Open Collective, but steer small donations elsewhere

([#2660](https://github.com/hledgerorg/hledger/issues/2660))
Open Source Collective, our fiscal host, charges 10% on every donation, holds the funds
(they are legally owned by OSC, not by the project or by Simon), pays no interest,
and can add friction to routine reimbursements.
Now,

- Small donors are steered towards Github Sponsors / Liberapay / Paypal, avoiding the 10% fee.
- OC/OSC is kept for larger donors,
  where the 10% and the friction are the price of receiving funds via a 501(c)(6) nonprofit
  with corporate-friendly procedures and oversight.
- Docs and bookkeeping now make clear that funds in the hledger open collective are owned and disbursed by OSC.
- The balance held with OSC will be reduced and kept low (eg 1-2k), limiting investment losses
  and exposure to host wind-down, policy changes or disputes.

### Policies for AI usage

These are tracked in AI.md. Eg,

- Significant AI usage must be disclosed
- AI assistance is not allowed in PRs from first-time contributors.
- AI assistance using OpenAI tools is not allowed.
- Significant AI usage must be tracked, approximately, one way or another.
  Eg logged in commit messages, or when that's not appropriate, logged in `doc/ai/ai.journal`.

### RULES.md

Repo policies in general, including AI policies, are gathered in doc/RULES.md.

### Discontinue the regression bounties

They are now a magnet for AI slop.

### Formalise core developers

Core developers will be nominated and documented, and the higher levels of repo access will be restricted to them.

### Pay for review work

PR review work, especially now with AI, is costly and unrewarding. 
We will start paying a small reviewer stipend ($50/hr initially, via opencollective) to any core developer who does it.
Core developers can also nominate other contributors on a PR for the reviewer stipend.

### Move the repos to a Github organisation

To get more fine-grained access control, supporting more governance and funding structure in the project.
And for more future-proofing.
It seems likely we'll use `hledgerorg`, because the `hledger` username is taken and unreachable.
