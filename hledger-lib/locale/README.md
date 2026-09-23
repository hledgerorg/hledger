# Translations

This directory holds hledger's localization (l10n) files: one gettext PO
catalog per language, translating the structural text of hledger's own
output (report titles, headings, month names, the hledger-ui and
hledger-web interfaces). The machinery that makes hledger translatable,
its internationalization (i18n) support, is `Hledger.Utils.I18n`; the
`--lang` option selects a catalog. Localization here means the language
of hledger's text only: number and date formats are not localized, since
hledger takes number styles from the journal and keeps ISO dates.

- `hledger.pot` is the template, generated from the sources by
  `tools/i18n-extract.py` (`just i18n-pot`). Do not edit it by hand.
- `LANG.po` is a language's catalog, named by its tag (`de`, `pt-BR`,
  `zh-Hans`). A catalog is built into the executables when it is listed
  both in package.yaml's extra-source-files and in `builtinCatalogSources`
  in `Hledger/Utils/I18n.hs` (see doc/TRANSLATING.md, step 4).

## Translating

The step-by-step guide for translators, and the developer notes on
marking strings and the `just i18n-*` tooling, are in
[doc/TRANSLATING.md](../../doc/TRANSLATING.md).

## German

The report vocabulary follows Henning Thielemann's choices in PR #2735,
so that the two catalogs agree: everyday, cash-basis terms (Einnahmen,
Ausgaben, Einnahmenüberschussrechnung), which fit hledger's typical
personal and small-business use better than the accrual terms of the
German commercial code (Erträge, Aufwendungen, Gewinn- und
Verlustrechnung, Vermögenswerte). Anyone keeping books under HGB can put
those in `~/.config/hledger/locale/de.po`, which overrides the built-in
catalog entry by entry.

| English | German |
|---|---|
| Balance Sheet / With Equity | Bilanz / Bilanz mit Eigenkapital |
| Income Statement | Einnahmenüberschussrechnung |
| Cashflow Statement | Kapitalflussrechnung |
| Assets | Vermögen |
| Liabilities | Verbindlichkeiten |
| Equity | Eigenkapital |
| Revenues | Einnahmen |
| Expenses | Ausgaben |
| Cash flows | Kapitalflüsse |
| Net: | Überschuss: |
| Total / Average | Gesamt / Durchschnitt |
| Commodity | Einheit |
| Account | Konto |
| Balance changes | Saldoänderungen |
| Ending balances (historical) | Endsalden (historisch) |
| Budget performance | Soll-Ist-Vergleich |

Known inconsistency: `examples/i18n/de.journal` names its accounts
aktiva, passiva, erträge and aufwendungen.

Not yet translatable: the `W` prefix of the week headings in weekly
reports (`W23`), which is hard-coded in the period rendering; German
would want `KW23`. Interval words precede a report title ("Monatliche
Bilanz") and are inflected for the feminine, which all four report titles
happen to share.
