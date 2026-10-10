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

## Spanish

Machine-made (by Claude Opus 5.5) and not yet reviewed by a native
speaker; corrections are welcome. It aims at neutral Spanish, readable in
Spain and Latin America, so regional tags like `es-MX` or `es_ES` select
it too. Viewers are addressed formally (usted).

The statement names are the IFRS-style ones used across Latin America
and in Spanish IFRS texts. Spain's PGC names differ (Balance de
situación, Cuenta de pérdidas y ganancias); anyone who prefers them can
override those entries in `~/.config/hledger/locale/es.po`. The account
words match `examples/i18n/es.journal`.

| English | Spanish |
|---|---|
| Balance Sheet / With Equity | Balance general / Balance general con patrimonio |
| Income Statement | Estado de resultados |
| Cashflow Statement | Estado de flujos de efectivo |
| Assets / Liabilities / Equity | Activos / Pasivos / Patrimonio |
| Revenues / Expenses | Ingresos / Gastos |
| Net: | Neto: |
| Total / Average | Total / Promedio |
| Commodity | Unidad |
| Account / Amount | Cuenta / Importe |
| transaction / posting / journal entry | transacción / movimiento / asiento |
| Journal (hledger-web's view) | Libro diario |
| Balance changes / Ending balances | Cambios de saldo / Saldos finales |
| Budget performance | Ejecución del presupuesto |

Notes on the choices:

- Spanish adjectives agree with their noun, so text that is appended to
  titles of any gender and number is phrased to need no agreement:
  ", con valoración al cierre de cada período" rather than ", valorado
  ...", and "{title}, con filtro" rather than "..., filtrado".
- All four statement names are masculine, so the interval words are too
  ("Balance general mensual"). Where an interval word could be read as
  describing the last noun, it moves: "Balance general anual con
  patrimonio", "Estado mensual de flujos de efectivo".
- hledger-web's Journal view is "Libro diario" everywhere, since "Diario"
  alone is also its Daily interval link.
- Month names are capitalized, as column headings, though Spanish writes
  them in lower case in running text.

## Simplified Chinese

Contributed by Chunhui Ouyang, as `zh_CN.po`; renamed to `zh-Hans.po`,
the tag that `zh`, `zh_CN` and `zh-CN` all resolve to. It was later
brought up to date with the current template by its contributor.
