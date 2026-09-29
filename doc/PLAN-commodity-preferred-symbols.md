# Plan: detecting and showing preferred commodity symbols, 2026-05

## Context

Since the recent cur:/sym: work, hledger's `commodity` directives form
*alias groups*: any symbols that share membership in someone's `alias:` tag,
or that are reachable transitively, are merged into one undirected group
([`journalCommodityAliasGroups`](../hledger-lib/Hledger/Data/Journal.hs#L1240)).
A typical setup has multiple directives for symbols in the same group — e.g.
`commodity USD…` to declare the canonical with its aliases, plus `commodity
$…` to control `$`'s own display style. The group is symmetric, but nothing
in the data currently records *which* symbol the user thinks of as the
preferred name.

We want to:

1. **Phase 1** — record the preferred symbol of each alias group, by tracking
   `commodity` directive declaration order. The preferred symbol is the
   group member whose `commodity` directive comes first in parse order.
   (User-controllable simply by putting that directive first; no new syntax.)

2. **Phase 2** — use the preferred symbol at report-render time:
   automatically render alias-group amounts in the preferred symbol (and its
   display style). Print and print-like reports are exempted; their output
   must remain faithful to the as-written commodities for round-tripping.

The two phases can ship independently: phase 1 is pure data plumbing with
no behaviour change; phase 2 is the user-facing feature.

---

## Phase 1: Track commodity declaration order

### Design

Mirror the existing `jdeclaredaccounts` + `adideclarationorder` pattern.
Three pieces:

1. **Parallel parse-order list** — new field on `Journal`:
   `jdeclaredcommodityorder :: [CommoditySymbol]`, populated during
   parsing alongside `jdeclaredcommodities`. Symbols only; the full
   `Commodity` lives in the existing map.
2. **Rank field on each `Commodity`** — new field
   `cdeclarationorder :: Int` (default 0 in unfinalised journals;
   assigned globally at finalise).
3. **Finalise step** — new `journalRenumberCommodityDeclarations`:
   walks `jdeclaredcommodityorder`, looks each symbol up in
   `jdeclaredcommodities`, writes back the same `Commodity` with its
   `cdeclarationorder` set to its 1-based position. Called from
   `journalFinalise` next to the existing
   `journalRenumberAccountDeclarations`.

Multi-file journals: `jdeclaredcommodityorder` concatenates via `<>` in
`journalConcat`, just like `jdeclaredaccounts` does. The
`jdeclaredcommodities` map keeps its existing `M.union` semantics
(j2 overrides j1 for same-symbol duplicates). After concatenation,
`journalRenumberCommodityDeclarations` produces globally consistent ranks.

A small helper exposes the preferred symbol per group:

```haskell
journalCommodityPreferredSymbol :: Journal -> CommoditySymbol -> CommoditySymbol
```

It looks up the alias group of the given symbol (existing
`journalCommodityAliasGroup`), then picks the group member with the lowest
`cdeclarationorder`. Symbols that appear only as alias values (no
`commodity` directive of their own) have no rank — they sort after all
directive-declared symbols (`maxBound` sentinel).

### Files to modify

- **[hledger-lib/Hledger/Data/Types.hs](../hledger-lib/Hledger/Data/Types.hs)**
  - `Commodity` record (line 321): add `cdeclarationorder :: Int`.
  - `Journal` record (line 684 area): add `jdeclaredcommodityorder :: [CommoditySymbol]`.

- **[hledger-lib/Hledger/Data/Journal.hs](../hledger-lib/Hledger/Data/Journal.hs)**
  - `nulljournal` (~line 369): initialise `jdeclaredcommodityorder = []`.
  - `journalConcat`/Semigroup (line 308 area): concat
    `jdeclaredcommodityorder` with `<>`, mirroring line 287 for accounts.
  - Add `journalRenumberCommodityDeclarations :: Journal -> Journal` near
    `journalRenumberAccountDeclarations` (line 331). Defensively, when the
    order list contains a symbol multiple times (multi-file or duplicate
    directives), use the first occurrence's index — matches "first declared".
  - Add `journalCommodityPreferredSymbol :: Journal -> CommoditySymbol -> CommoditySymbol`.
  - Export both.

- **[hledger-lib/Hledger/Read/JournalReader.hs](../hledger-lib/Hledger/Read/JournalReader.hs)**
  - `commoditydirectiveonelinep` (~line 629) and `commoditydirectivemultilinep`
    (~line 661): in addition to inserting into `jdeclaredcommodities`,
    append the symbol to `jdeclaredcommodityorder` in the same `modify'`.

- **[hledger-lib/Hledger/Read/Common.hs](../hledger-lib/Hledger/Read/Common.hs)**
  - `journalFinalise` (~line 394): add `<&> journalRenumberCommodityDeclarations`
    adjacent to the existing `<&> journalRenumberAccountDeclarations`.

### Verification

Unit tests against constructed journals:

1. `commodity USD…` + `commodity $… ; alias: USD` →
   `journalCommodityPreferredSymbol j "$"` = `"USD"` (USD comes first).
2. Reverse the directive order → returns `"$"`.
3. Chain `commodity USD ; alias: $` + `commodity $ ; alias: USDOLLAR` →
   preferred is `"USD"` (first declared in the chain).
4. Symbol with no group → returned unchanged.
5. Multi-file: include order determines rank, both directions.

Existing functional tests (commodity-aliases.test) are unaffected: phase 1
adds no user-visible behaviour change.

### Code impact estimate

~100 LOC across ~4 files. Pure data plumbing.

---

## Phase 2: Render alias-group amounts in their preferred symbol

### Design

A pure transform applied at the rendering boundary of non-print reports:
each `Amount` has its `acommodity` swapped to the preferred symbol of its
alias group, and its `astyle` swapped to that symbol's `cformat`. No
quantity change (aliases are by definition 1:1); no valuation involved.

Three new pieces:

1. **Per-amount transform**:
   ```haskell
   journalNormalizeAmount :: Journal -> Amount -> Amount
   journalNormalizeAmount j a =
     let pref     = journalCommodityPreferredSymbol j (acommodity a)
         prefStyl = maybe (astyle a) cformat $ M.lookup pref (jdeclaredcommodities j)
     in a { acommodity = pref, astyle = prefStyl,
            acost      = fmap (normalizeCost j) (acost a) }
   ```
   Likewise for cost amounts.

2. **MixedAmount re-keying** — `MixedAmount` is internally keyed by
   `(CommoditySymbol, Maybe AmountCost)`. Re-keying produces collisions
   (e.g. `USD10` + `$10` both becoming `USD15` after merging). Must use
   `maAddAmount`/`maSum` to *add* on collision, not silently drop.

3. **Render-time hook**, applied next to the existing
   `styleAmounts (journalCommodityStyles j)` calls in each report
   command's rendering boundary. Skip in print and print-like reports.

### Files to modify

- **Core transform**: new helper(s) in
  `hledger-lib/Hledger/Data/Journal.hs` (or a small dedicated module).
- **Rendering sites** — every report command's render path. The existing
  `styleAmounts` calls are good anchor points; the new transform either
  runs before, after, or alongside them. Roughly 15–20 sites across
  hledger (Balance, Register, Aregister, Prices, Stats, compound balance
  commands), hledger-ui (each screen), and hledger-web (each page).
- **Skip list** — print and print-like commands explicitly opt out. To
  enumerate (review needed):
  - `print` (obvious)
  - `register --output-format=csv` / similar dump-like outputs
  - `aregister`, `accounts --used`, `tags`, `payees`, `commodities --used` —
    these render commodity symbols but mostly as data, not styled amounts;
    likely fine either way
  - hledger-web's transaction-detail page
  - hledger-ui's transaction screen
- **Off-switch** — new general flag, tentatively `--no-normalize-commodities`
  (or whatever the standard reverse-of-default form is). Stored in
  `ReportOpts` or `InputOpts`.
- **Manual** — `hledger.m4.md` section describing the behaviour and opt-out.
- **Tests** — many existing tests that rely on side-by-side rendering of
  alias-group symbols will need expected-output updates. In particular,
  `commodity-aliases.test` tests 9–20 currently *demonstrate* that
  `USD10`/`$-10` postings can coexist in one report; with normalization,
  those would all become the preferred symbol. Either:
  - update those tests to expect the normalized output, OR
  - have them set `--no-normalize-commodities` to preserve their current
    intent (matching/filtering, not display).

### Reload correctness

Same shape as the cur: expansion. Preferred symbols depend on the
(potentially reloaded) journal. The normalization map can be re-derived
from the journal each time `styleAmounts` would be re-derived — the
existing journal-attach hooks (`reportSpecExpandCurQueries`-equivalent
sites) already cover this.

### Code impact estimate

~250–350 LOC across ~15–20 files. Roughly 60% mechanical (per-site
plumbing, tests, docs), 40% genuine design (where exactly to hook, what
counts as "print-like", aggregation semantics in MixedAmount).

### Risks

1. **Aggregation surprise** — `USD10` and `$10` in one account, currently
   shown as two lines, would collapse into one. That's the point, but
   users who relied on side-by-side display will be surprised. The
   off-switch matters.
2. **Cost rendering** — `2 USD @ 1.50 EUR` becomes `2 $ @ 1.50 €` (literal
   symbol swap). Fine in theory; changes the look of derived output.
3. **Enumerating "print-like" reports** — getting this wrong is the easiest
   way to break round-tripping. Audit each output format before shipping.
4. **Default vs opt-in** — should normalization be on by default or
   require a flag? "On by default with opt-out" matches the user-facing
   intent (the user *wants* this when they set up aliases) but is the more
   disruptive change. "Opt-in" is safer but means most users never see
   the benefit. Decision deferred.

---

## Open questions to resolve before implementing Phase 2

- On by default, or opt-in with a flag? (lean: on by default, with opt-out.)
- Cost amounts: normalize the cost-side commodity too, or only the
  posting-amount-side? (lean: yes, normalize both, for consistency within
  a report.)
- What about `register`'s historical-balance column — does the running
  balance also normalize? (yes, it should, since it's a balance display.)
- hledger-ui's running balance + per-screen reload: any extra hook needed
  beyond the existing `regenerateScreens` funnel? (probably not, but
  verify before shipping.)
- A future explicit `preferred:` tag on commodity directives, overriding
  the positional rule? (not needed for either phase; a clean later
  addition if a real use case arises.)
