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

## Translators

People to ping when a language needs updating, eg in a pre-release
translation sprint (see doc/RELEASING.md), and to credit. Anyone who
sends translations or corrections for a language joins its list. Their
email addresses are in the git log: a translation sent by mail is
committed with the translator as its author (name and email address)
and the maintainer as committer, with the commit message saying how it arrived.

| Language | Translators | Status |
|---|---|---|
| [de](#german) | Arthur Cinader (@acinader), Henning Thielemann (@thielema) | some entries machine-made; these are marked |
| [es](#spanish) | | machine-made, not yet checked by a native speaker |
| [fr](#french) | | machine-made, not yet checked by a native speaker |
| [ga](#irish) | | machine-made, not yet checked by a native speaker |
| [haw](#hawaiian) | | machine-made, not yet checked by a native speaker |
| [it](#italian) | Diego Depaoli | a draft, completed by machine; machine-made entries are marked |
| [ja](#japanese) | | machine-made, not yet checked by a native speaker |
| [pt-BR](#brazilian-portuguese) | | machine-made, not yet checked by a native speaker |
| [ru](#russian) | Daniil Iaitskov (@yaitskov) | some entries machine-made; these are marked |
| [zh-Hans](#simplified-chinese) | Chunhui Ouyang (@jack9603301) | some entries machine-made; these are marked |

Also interested in hledger's i18n: Arthur Cinader (@acinader), who built
it (#2736), and @mildred, @alerque (#1025) and @weakish (#231), who asked
for it.

## Translating

The step-by-step guide for translators, and the developer notes on
marking strings and the `just i18n-*` tooling, are in
[doc/TRANSLATING.md](../../doc/TRANSLATING.md).

## German

Translators: Arthur Cinader, Henning Thielemann.

The report vocabulary follows Henning Thielemann's choices in PR #2735,
so that the two catalogs agree: everyday, cash-basis terms (Einnahmen,
Ausgaben, Einnahmenüberschussrechnung), which fit hledger's typical
personal and small-business use better than the accrual terms of the
German commercial code (Erträge, Aufwendungen, Gewinn- und
Verlustrechnung, Vermögenswerte). Anyone keeping books under HGB can put
those in `~/.config/hledger/locale/de.po`, which overrides the built-in
catalog entry by entry.

Some entries were made by machine (Claude Opus 5.5), most of them, at
Henning's request, the hledger-web text still untranslated at the end
of October 2026; each is marked `# machine-translated, please review`.

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
| Commodity | Einheit (in hledger-web: Einheit oder Währung) |
| Account | Konto |
| transaction / posting | Buchung / Buchungszeile |
| Lot | Tranche |
| Hidden / Shown | Ausgeblendet / Angezeigt |
| Cost, as an asset's cost basis (holdings, --gain) | Anschaffungskosten |
| Cost, as the price recorded in a transaction (-B, "at cost", @ prices) | Transaktionspreis |
| Balance changes | Saldoänderungen |
| Ending balances (historical) | Endsalden (historisch) |
| Budget performance | Soll-Ist-Vergleich |

Choices to check (as of 2026-10):

- Tranche for lot, the usual finance term for a purchase lot (Lose seemed
  wrong).
- The holdings gain columns, abbreviated as headings: Unreal. Gew.,
  Unreal. Gew. %, Real. Gew.; XIRR kept as is.
- Account types: Umrechnung for Conversion, Kursgewinne for Gain,
  Differenzen for Imbalance.
- In Anschaffungswährung for "Per cost commodity" (holdings values), and
  Zweitdaten for secondary dates.
- "Equity:", the label before the balance sheet's links that hide or show
  equity, reads Vermögen:, which elsewhere means assets; Eigenkapital:?
- "Total value", a holdings column, reads Gesamtsumme; Gesamtwert?

Known inconsistency: `examples/i18n/de.journal` names its accounts
aktiva, passiva, erträge and aufwendungen.

Not yet translatable: the `W` prefix of the week headings in weekly
reports (`W23`), which is hard-coded in the period rendering; German
would want `KW23`. Interval words precede a report title ("Monatliche
Bilanz") and are inflected for the feminine, which all four report titles
happen to share.

## Spanish

Machine-made (Claude Opus 5.5), not yet checked by a native speaker;
corrections are welcome. It aims at neutral Spanish, readable in
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

## Russian

Translators: Daniil Iaitskov (#2773).
Regional tags like `ru-RU` or `ru_RU` select it too.

| English | Russian |
|---|---|
| Balance Sheet / With Equity | Баланс / Баланс с капиталом |
| Income Statement | Отчёт о прибылях и убытках |
| Cashflow Statement | Отчёт о движении денежных средств |
| Assets / Liabilities / Equity | Активы / Обязательства / Капитал |
| Revenues / Expenses | Доходы / Расходы |
| Net: | Чистый итог: |
| Total / Average | Итого / Среднее |
| Cash flows | Движение денежных средств |
| Commodity | Единица учёта |
| Net worth | Чистые активы |
| converted to cost / current value | в ценах сделки / по текущей стоимости |
| Account / Amount | Счёт / Сумма |
| Journal (hledger-web's view) | Журнал |
| Balance changes / Ending balances | Изменения сальдо / Конечные сальдо |
| Budget performance | Исполнение бюджета |

## Simplified Chinese

Translators: Chunhui Ouyang. Contributed as `zh_CN.po`; renamed to `zh-Hans.po`,
the tag that `zh`, `zh_CN` and `zh-CN` all resolve to. It was later
brought up to date with the current template by its contributor.

The terms it uses, which machine-filled entries should follow:

| English | Simplified Chinese |
|---|---|
| Balance Sheet / With Equity | 资产负债表 / 包含权益的资产负债表 |
| Income Statement | 损益表 |
| Cashflow Statement | 现金流量表 |
| Assets / Liabilities / Equity | 资产 / 负债 / 权益 |
| Revenues / Expenses | 收入 / 支出 |
| Net: | 净额： |
| Total / Average | 总计 / 平均 |
| Account / Amount / Commodity | 账户 / 金额 / 商品 |
| Journal (hledger-web's view) / General Journal | 日记账 / 通用日记账 |
| Register (`register`'s spreadsheet sheet, hledger-web's register page) | 明细账 |
| Balance changes / Ending balances | 余额变动 / 期末余额 |
| Balance brought forward | 上期结转余额 |
| Daily / Monthly | 每日 / 每月度 (eg 月度资产负债表) |

Decided with the translator (2026-10): "Balance changes" is 余额变动
(was 平衡性调整, "balancing adjustments"), and the Register sheet is 明细账
(was 日记账, the Journal view's name). For "Net:" the translator kept 净值,
then suggested 总计; it is now 净额 ("net amount"), since the row is a
difference rather than a total (assets minus liabilities, revenues minus
expenses), 总计 is the Total column, and 净值 reads as net worth, which
suits only the balance sheet. hledger-web's register page then took 明细账 too
(was 登记册), so that both programs name the register alike.

## Japanese

Machine-made (Claude Opus 5.5), not yet checked by a native speaker;
corrections are welcome. The statement names follow Japanese
GAAP usage, and the account words match `examples/i18n/ja.journal`.
Regional tags like `ja-JP` or `ja_JP` select it too.

| English | Japanese |
|---|---|
| Balance Sheet / With Equity | 貸借対照表 / 純資産を含む貸借対照表 |
| Income Statement | 損益計算書 |
| Cashflow Statement | キャッシュ・フロー計算書 |
| Assets / Liabilities / Equity | 資産 / 負債 / 純資産 |
| Revenues / Expenses | 収益 / 費用 |
| Net: | 純額: |
| Account / Amount / Commodity | 勘定科目 / 金額 / 単位 |
| transaction / posting / journal entry | 取引 / 転記 / 仕訳 |
| Journal (hledger-web's view) / Register / Holdings | 仕訳帳 / 元帳 / 保有資産 |
| Cumulative / Historical | 累計 / 繰越込み |
| Balance brought forward | 前期繰越 |
| Daily ... Periodic | 日次, 週次, 隔週, 月次, 隔月, 四半期, 半期, 年次, 隔年, 期間別 (eg 月次貸借対照表) |

Choices to check:

- 単位 for Commodity, since it covers both currencies and securities;
  it may read oddly.
- 転記 for posting, bookkeeping's word for posting to the ledger.
- Parentheses and colons are ASCII rather than full-width, to match
  hledger's layout.
- Japanese has no plural forms, so the plural rule is `nplurals=1`.

## Irish

Machine-made (Claude Opus 5.5), not yet checked by a native speaker;
corrections are welcome. Regional tags like `ga-IE` or `ga_IE`
select it too.

| English | Irish |
|---|---|
| Balance Sheet / With Equity | Clár Comhardaithe / Clár Comhardaithe le Cothromas |
| Income Statement | Ráiteas Ioncaim |
| Cashflow Statement | Ráiteas Sreabhadh Airgid |
| Assets / Liabilities / Equity | Sócmhainní / Dliteanais / Cothromas |
| Revenues / Expenses | Ioncam / Speansais |
| Net: | Glan: |
| Account / Amount / Commodity | Cuntas / Méid / Aonad |
| transaction / posting / journal | idirbheart / postáil / dialann |
| Register / Holdings | Clár / Sealúchais |
| Monthly Balance Sheet | Clár Comhardaithe Míosúil |
| Months | Eanáir ... Nollaig; short forms Ean, Feabh ... Noll, as in CLDR |

Choices to check:

- Speansais for Expenses, not Costais, which would look the same as the
  options' "Costs" (Costais).
- Interval words follow the statement name, unlenited, so that they
  describe the statement (Clár), not the genitive (Comhardaithe).
- Counts are written "cuntais: {n}" rather than "{n} cuntas", since the
  mutation after a numeral depends on the number.
- The least certain: mutations in phrases like "cuntais shócmhainne",
  the long help texts, and the shortened holdings column headings
  (Gnóth. neamhr., Gnóth. réad.).

## Hawaiian

Machine-made (Claude Opus 5.5), not yet checked by a native speaker;
corrections are welcome. Hawaiian has little established
accounting vocabulary, so many terms are descriptive phrases, and this
is the least certain of the machine-made catalogs. Regional tags like
`haw-US` select it too.

| English | Hawaiian |
|---|---|
| Balance Sheet / With Equity | Pepa Kaulike / Pepa Kaulike me ke Kumu Waiwai |
| Income Statement | Hōʻike Loaʻa a me Hoʻolilo |
| Cashflow Statement | Hōʻike Kahe Kālā |
| Assets / Liabilities / Equity | Nā Waiwai / Nā ʻAiʻē / Kumu Waiwai |
| Revenues / Expenses | Loaʻa / Hoʻolilo |
| Net: | Maʻemaʻe: |
| Total / Average | Huina / Awelika |
| Account / Amount / Commodity | Moʻokālā / Ka nui / Ana |
| transaction / posting / journal | hana kālā / laina / puke moʻolelo |
| Register / Holdings | Papa Helu / Nā Waiwai Paʻa |
| Balance | Koena |
| Cost / Market value | Kumukūʻai / Kumukūʻai mākeke |
| Gain / Loss | Puka / Poho |
| Monthly Balance Sheet | Pepa Kaulike o ka Mahina |
| Months | Ianuali ... Kekemapa; short forms Ian. ... Kek., as in CLDR |

Choices to check:

- Ana ("measure, unit") for Commodity, and laina ("line") for posting.
- Kumu Waiwai for Equity, and waiwai maʻemaʻe for net worth.
- Maʻemaʻe ("clean") for Net, by analogy with net weight.
- The interval links are "I ka lā", "I ka mahina" ("per day", "per
  month"), so that the daily link is not "Lā", which is the Date column.
- Hōʻike is both "show" (in the tooltips) and "report" (in titles).
- The shortened holdings column headings (Puka L.ʻO., Puka L.) are
  guesses.

## French

Machine-made (Claude Opus 5.5), not yet checked by a native speaker;
corrections are welcome. The statement names are those of France's plan
comptable général (Bilan, Compte de résultat, Tableau des flux de
trésorerie), and the account words match `examples/i18n/fr.journal`.
Regional tags like `fr-CA`, `fr-BE` or `fr_FR` select it too. Viewers are
addressed formally (vous), and actions are infinitives (Afficher,
Masquer), as is usual in French software.

| English | French |
|---|---|
| Balance Sheet / With Equity | Bilan / Bilan avec capitaux propres |
| Income Statement | Compte de résultat |
| Cashflow Statement | Tableau des flux de trésorerie |
| Assets / Liabilities / Equity | Actifs / Passifs / Capitaux propres |
| Revenues / Expenses | Revenus / Dépenses |
| Net: | Net : |
| Total / Average | Total / Moyenne |
| Account / Amount / Commodity | Compte / Montant / Unité |
| transaction / posting / journal entry | opération / mouvement / écriture |
| Register / Holdings | Registre / Portefeuille |
| Balance changes / Ending balances | Variations de solde / Soldes de clôture |
| Cost / Value | Coût / Valeur (de marché) |
| Unrealized gain / loss | Plus-value / Moins-value latente |
| Cleared / Pending / Unmarked | Rapprochées / En attente / Non marquées |
| Balance brought forward | Solde reporté |

Choices to check:

- Revenus / Dépenses, everyday terms suited to personal and small-business
  use, rather than the PCG's Produits / Charges, which pair with "Compte
  de résultat". Anyone keeping books under the PCG can override them in
  `~/.config/hledger/locale/fr.po`.
- "Net :" and the other labels have a space before the colon, as French
  typography wants (an ordinary space, not a non-breaking one).
- Biweekly is "par quinzaine" (Bilan par quinzaine), avoiding the
  ambiguous "bimensuel"; bimonthly is "bimestriel".
- Appended fragments avoid agreement: ", au coût", ", à la valeur de
  marché en fin de chaque période", "{title}, avec filtre".

## Brazilian Portuguese

Machine-made (Claude Opus 5.5), not yet checked by a native speaker;
corrections are welcome. The statement names are the ones used in Brazil
(Balanço Patrimonial, Demonstração do Resultado, Demonstração dos Fluxos
de Caixa). It is selected by `pt-BR` or `pt_BR`; plain `pt`, Portugal's
Portuguese, is a different language tag and does not select it.

| English | Brazilian Portuguese |
|---|---|
| Balance Sheet / With Equity | Balanço Patrimonial / Balanço Patrimonial com Patrimônio Líquido |
| Income Statement | Demonstração do Resultado |
| Cashflow Statement | Demonstração dos Fluxos de Caixa |
| Assets / Liabilities / Equity | Ativos / Passivos / Patrimônio Líquido |
| Revenues / Expenses | Receitas / Despesas |
| Net: | Líquido: |
| Total / Average | Total / Média |
| Account / Amount / Commodity | Conta / Valor / Unidade |
| transaction / posting / journal entry | transação / partida / lançamento |
| Journal (hledger-web's view) / Register / Holdings | Livro diário / Extrato / Carteira |
| Balance changes / Ending balances | Variações de saldo / Saldos finais |
| Cost / Value | Custo / Valor de mercado |
| Unrealized gain / loss | Ganho / Perda não realizada |
| Cleared / Pending / Unmarked | Conciliadas / Pendentes / Não marcadas |
| Balance brought forward | Saldo anterior |

Choices to check:

- Valor for Amount, as Brazilian banking software uses it, so Value is
  always "Valor de mercado" (including the holdings page's column), to
  keep the two apart.
- Patrimônio Líquido for Equity, rather than `examples/i18n/pt.journal`'s
  European "capital próprio"; it also serves for net worth.
- hledger-web's Journal view is "Livro diário", since "Diário" alone is
  its Daily interval link; the journal file is "o diário".
- Register is "Extrato", like a bank statement, and posting is "partida"
  (as in partidas dobradas), leaving "lançamento" for journal entries.

## Italian

Translators: Diego Depaoli, whose untested draft (October 2026) covered
about 200 of the entries. The rest were filled in by machine (Claude Opus
5.5), which also fixed some errors in the draft (eg "quadrimestrale" for
quarterly, balances translated as gains); every entry added or changed
that way is marked `# machine-translated, please review`. Regional tags
like `it-CH` or `it_IT` select it too. Viewers are addressed informally
(tu), as in the draft.

| English | Italian |
|---|---|
| Balance Sheet / With Equity | Bilancio / Bilancio con patrimonio netto |
| Income Statement | Conto economico |
| Cashflow Statement | Rendiconto finanziario |
| Assets / Liabilities / Equity | Attività / Passività / Patrimonio netto |
| Revenues / Expenses | Entrate / Uscite |
| Net: | Netto: |
| Total / Average | Totale / Media |
| Account / Amount / Commodity | Conto / Importo / Unità di conto |
| transaction / posting | registrazione / movimento |
| Journal / Register / Holdings | Giornale / Registro / Portafoglio |
| Balance / Balance changes / Ending balances | Saldo / Variazioni di saldo / Saldi finali |
| Cost / Value | Costo / Valore |
| Unrealized gain / loss | Plusvalenza / Minusvalenza latente |
| Cleared / Pending / Unmarked | Riconciliate / In sospeso / Non contrassegnate |
| Quarterly / Biweekly | Trimestrale / Quindicinale |

Choices to check:

- Bilancio for Balance Sheet, as in the draft; strictly the bilancio is
  the whole set of statements, and the balance sheet is the stato
  patrimoniale.
- Movimento for posting, so that "registrazione" means only a
  transaction (the draft used it for both).
- The links that show or hide something (zero balances, equity, costs,
  lots, closed positions) read Mostra / Nascondi, avoiding agreement with
  nouns of different genders.
