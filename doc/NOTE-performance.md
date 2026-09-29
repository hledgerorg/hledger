# Performance: remaining ideas

Working notes: the ranked list of performance ideas not yet tried, kept between sessions.
Measurements, lessons learned and how to measure are in [PERFORMANCE](PERFORMANCE.md);
the September 2026 optimisation commits are listed by `git log --grep='^perf:'`.
Numbers below are for `hledger balance` on examples/100ktxns-1kaccts.journal (about 1.4s on a
MacBook Pro M5 Pro in late 2026-09, with about 150 MB of live data).
A lot-using variant for idea 3 can be generated with tools/_100k-lots-journal.py (local, untracked).

Done in 2026-09: the megaparsec regression (fixed upstream in megaparsec 9.8.3, via our
[megaparsec#613](https://github.com/mrkkrp/megaparsec/pull/613); pinned in all stack configs);
the residency reductions (strict parser accumulators, shared amount styles, account names and
commodity symbols: 2.6 -> 1.5 KB per transaction); cheaper cost annotation parsing; and the
parser fast path for simple transactions and prices (parse 0.92 -> 0.63s, allocation halved),
later extended to codes, secondary and partial dates, posting status marks, times of day in
price directives, comments and tags (a real 21k-transaction journal went from 40% to 85% of
entries on the fast path; `--debug=1` reports the share and the reasons for the rest);
and, prompted by that journal, where finalising was 40% of the run, a one-pass account tree
builder, cheaper account type inference, and tag propagation that leaves untagged postings alone.
Also the scan of PATH for add-on commands, 11 ms of every run with a long PATH, now happens only
when the command is not a builtin one (startup 14 -> 2.5 ms; `hledger --version` 32 -> 23 ms).

## Parser allocation: tried and dropped (2026-09-28)

After the fast path work, the parser still allocates about 27 KB per transaction and price pair
(against 1.5 KB retained). A plan to trim that (cheaper source positions, interning through the
pure scanner, lazy comment fields, offset-based scanners, a blank-line fast path) was started and
dropped: the first step, computing end positions by arithmetic and recording the position anchor
once per entry, gained 3% of parse time (0.63 -> 0.61s on the 100k `check`) for 36 lines, and a
stub with no position work at all gained only 1% more. The other steps can be expected to gain a
few percent of parse time each, less of a run. What the measurements showed instead is in
PERFORMANCE: allocation is a poor proxy for time (Tips), garbage collection is 35-40% of a run and
scales with the live data (Memory and garbage collection), the parser has no hot spot (Parsing),
and a profile's story must be confirmed by stub experiments (Profiling).

## Remaining ideas, ranked

Expected gains are for the 100k balance run; "general" means every command pays it.

1. Report side, per command: the balance command is 0.24s (17%), mostly building the account tree
   (HashMap update and period data insertion per posting), and it computes amount widths more than
   once. print's own rendering is about 0.9s at 100k, and is shared by exports, hledger-ui and
   hledger-web: profile it.
2. Parser fast path, balance assertions: the one common syntax it still declines (14% of entries
   in the real journal above; everything in a journal that asserts every posting). Decided not
   worth the code for now (2026-09-26); it would matter for assertion-heavy journals, where an
   assertion costs about 3us in the general parser against 0.5us for a fast-path amount, so up to
   20% of a run. About forty lines: mirror balanceassertionp (=, ==, =*, then the existing
   amount-with-cost scanner), compute the = character's source position for the BalanceAssertion
   (line offset within the entry plus column; decline when a tab precedes it, to avoid
   megaparsec's tab-stop rule), and intern the asserted amount. Check mode covers the positions.
   Also still declined: bracketed dates in posting comments, symbol-less amounts under a D directive.
3. Remaining lot overhead on lot journals, ~0.36s: calculateLots still sorts, rebuilds and re-ties
   every transaction (0.135s); basis-from-account-name and transacted-cost inference search every
   account name (0.07s); commodity tags, method coherence.
4. Small finalise stages, ~1-2% each: style inference (0.04s), cost tagging; the account types
   stage is now mostly journalAccountNamesUsed (a set of 200k posting account names), which
   several stages compute separately and could share.
5. Remaining memory, now also the main time lever for large journals (see above: GC copies the
   live data, twice over): the steady state is mostly postings, amounts and their maps,
   transactions, and descriptions (slices of the input text, which keep it alive). Candidates:
   a single-amount case for MixedAmount (a singleton Map per posting today), an unboxed Decimal;
   both report-side and riskier. (The compacting collector,
   `+RTS -c`, was measured: 20-40% less memory for 40-60% more time; see PERFORMANCE. It's now
   suggested in the manual for users short of memory.)
6. Order of magnitude, not incremental: an on-disk cache of the finalised journal keyed by file
   contents and finalising options, skipping most of the run on unchanged journals; big feature
   with invalidation risks (includes, config, -I and friends, CSV/timeclock inputs). Parallel
   parsing of included files would help multi-file setups only.

Not worth retrying: nursery sizes; memory-doubling GC flags (unless the trade-off is reconsidered);
aggressive specialisation flags; deepseq in postingphelper; a dedicated `--timing` flag (`--debug=1`
was chosen); tying lot checks to `--lots`/holdings; removing parser labels; applying display styles
at render time instead of storing them per amount (7% of the run, but every report would need to
get it right); re-pointing postings during posting transforms, and releasing the balancer's input
journal early (both addressed short-lived peaks only); moving the finalised journal into a GHC compact
region (ghc-compact) so the GC stops copying it: `compactWithSharing` is needed (the journal is cyclic,
and its texts are slices of the input) and takes 1.3s for the 100k journal, three times what the GC
copying costs, and it comes after the memory peak. It might still suit hledger-web and hledger-ui,
which keep a journal loaded through many collections.
Also: recording journal items (jitems, for print --export) only on request. Measured with a
keep_items_ input option: the items cost about 60 bytes per transaction plus 70 per top-level
comment or directive line, so skipping them saved 5% of live data on the 100k journal (which has a
P directive per transaction) but only 2% without those directives; not worth a new option.
