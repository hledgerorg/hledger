# Translating hledger

hledger can show the structural text of its output in your language:
report titles and section headings, column headings, month names, the
names of hledger-ui's screens, and hledger-web's pages and forms. This
guide is for anyone who would like to add or improve a language. You do
not need to be a programmer or a professional translator, and you do not
need to build hledger: you can work with an installed release and see
your translation in action within minutes.

Things that are never translated, so you do not have to look for them:
your own data (account names, descriptions, amounts), dates (always
`2026-01-31`), number formats (these come from your journal's commodity
settings), error messages, the command line help, the manuals, and the
column headings of CSV, TSV and JSON output, which other programs read.
Translating the manuals is a separate, larger project.

A translation is one text file per language, in the "PO" format that
translation tools everywhere understand. hledger's built-in catalogs
live in the source tree at `hledger-lib/locale/`, one `LANG.po` per
language, next to the template `hledger.pot` that lists every
translatable string.

## What you need

- hledger with the `--lang` option (check with `hledger --help | grep lang`).
- The template, `hledger.pot`. Download it from
  <https://raw.githubusercontent.com/hledgerorg/hledger/main/hledger-lib/locale/hledger.pot>
  or take it from a source checkout.
- Either [Poedit](https://poedit.net) (free, runs on Windows, macOS and
  Linux, recommended if PO files are new to you), or any plain text
  editor. Weblate and Lokalize work too.
- A small journal to try things on. The one used below is
  `examples/sample.journal` in the hledger source, or paste this into a
  file called `sample.journal`:

```journal
2026-01-01 opening balance
    assets:bank:checking    100 EUR
    equity:opening

2026-02-14 groceries
    expenses:food            25 EUR
    assets:bank:checking
```

## The workflow in short

1. Create `LANG.po` from `hledger.pot`.
2. Translate the entries.
3. Put the file in hledger's config directory and run hledger with `--lang LANG`.
4. Repeat 2 and 3 until you are happy.
5. Send the file in.

The rest of this guide goes through each step with French as the example.

## Step 1: create your language's file

Language files are named by their language tag: `de.po` for German,
`fr.po` for French, `pt-BR.po` for Brazilian Portuguese, `zh-Hans.po`
for Simplified Chinese. A plain two-letter tag is usually right; add a
region or script only when the language really differs by it.

**With Poedit:** File > New From POT/PO File, choose `hledger.pot`, pick
your language when asked, and save as `fr.po`. Poedit fills in the file
header, including the plural rule for your language.

**With a text editor:** copy `hledger.pot` to `fr.po` and edit the block
at the top:

```po
msgid ""
msgstr ""
"Project-Id-Version: hledger\n"
"Language: fr\n"
"MIME-Version: 1.0\n"
"Content-Type: text/plain; charset=UTF-8\n"
"Content-Transfer-Encoding: 8bit\n"
"Plural-Forms: nplurals=2; plural=(n > 1);\n"
```

Set `Language` to your tag, keep the charset as UTF-8, and set
`Plural-Forms` to your language's rule. Common ones:

| Languages | Plural-Forms |
|---|---|
| English, German, Dutch, Spanish, Italian, Swedish, Turkish | `nplurals=2; plural=(n != 1);` |
| French, Portuguese (Brazil) | `nplurals=2; plural=(n > 1);` |
| Chinese, Japanese, Korean, Vietnamese, Thai | `nplurals=1; plural=0;` |
| Russian, Ukrainian, Polish, Czech | see the [GNU gettext list](https://www.gnu.org/software/gettext/manual/html_node/Plural-forms.html) |

Also remove the `#, fuzzy` line above the header if it is there: it
marks the whole file as a draft.

## Step 2: translate the entries

Each string is one entry. Here is one from the template:

```po
#. the report title, eg "Monthly Balance Sheet 2024 (Historical Ending Balances), valued at period ends". {clarification} brings its own leading space when present.
#: hledger/Hledger/Cli/CompoundBalanceCommand.hs:151
#, python-brace-format
msgid "{report} {dates}{clarification}{valuation}"
msgstr ""
```

- `msgid` is the English text. Never change it.
- `msgstr` is where your translation goes. Leave it empty for anything
  you are not sure about: an empty translation shows the English text
  (or, for a language hledger already ships, the built-in translation),
  so a partly translated file is fine and useful.
- `#.` lines are notes from the developers about where and how the text
  is used. Read them; they say things like "this precedes a report
  title" or "stand-alone month name, used as a column heading".
- `#:` lines say where in the source the text comes from. You can ignore them.
- `#, python-brace-format` means the text contains placeholders.

In Poedit the same entry appears as a row; the notes show in the right
hand panel.

### Placeholders

`{report}`, `{dates}`, `{account}` and similar are placeholders that
hledger fills in when it runs. Keep each one exactly as it is, but put
it where your language needs it. For example, "Transactions in
{account}" becomes "Buchungen in {account}" in German, and a language
that puts the date first can write "{dates} {report}" for the
title template. Do not translate the word inside the braces. Poedit
warns you if a placeholder goes missing.

### Contexts

A few short words appear in more than one place with different
meanings, so they carry a context line:

```po
msgctxt "column heading"
msgid "Total"
msgstr "Gesamt"
```

Translate each context separately; the same English word may want
different translations. Poedit shows the context next to the entry.

### Spaces, punctuation and capitals

Some entries deliberately start with a comma and a space, like
`", valued at {date}"`, or end with a colon, like `"Net:"`, because
they are appended to other text. Keep that shape. Keep the capitalization
style of the English too: headings are capitalized, hledger-ui screen
names are not.

### Whole phrases

A report title with a reporting interval, like "Monthly Balance Sheet",
is one entry, not "Monthly" and "Balance Sheet" joined together. That
makes for more entries (each report has one per interval), but each is
a complete phrase, so you can inflect, reorder or join the words however
your language needs: "Monatliche Bilanz", "Bilan mensuel", "月次貸借対照表".

### Month names

There are two sets, with contexts `month` (January) and `month abbrev`
(Jan). Use the stand-alone, nominative form, since they are used as
column headings, not inside dates. Short forms of three or four
characters keep the columns narrow, but longer ones work.

### Never markup

Translations are always shown as plain text, including on web pages, so
`<b>` or `&amp;` in a translation will appear literally.

## Step 3: try it out

hledger looks for translations in the `locale` folder of its config
directory, and uses one found there in preference to the built-in
catalog for the same language. So you can test without rebuilding
anything:

| System | Put your file at |
|---|---|
| Linux, macOS | `~/.config/hledger/locale/fr.po` |
| Windows | `%APPDATA%\hledger\locale\fr.po` |

Then, once a few entries are translated, run some reports with `--lang fr`
(this is what a French file translating the balance sheet's four strings gives):

```
$ hledger -f sample.journal balancesheet --lang fr
Bilan 2026-02-14

                      || 2026-02-14 
======================++============
 Actifs               ||            
----------------------++------------
 assets:bank:checking ||     75 EUR 
----------------------++------------
                      ||     75 EUR 
======================++============
 Passifs              ||            
----------------------++------------
----------------------++------------
                      ||          0 
======================++============
 Solde:               ||     75 EUR 
```

Commands that between them show most of the translatable text:

```
hledger -f sample.journal balancesheet --lang fr
hledger -f sample.journal incomestatement --lang fr -M -T -A
hledger -f sample.journal cashflow --lang fr
hledger -f sample.journal balance --lang fr -M
hledger -f sample.journal balance --lang fr -Q --value=then
hledger -f sample.journal balance --lang fr --budget -M
hledger-ui -f sample.journal --lang fr
hledger-web -f sample.journal --lang fr
```

For hledger-web you can also leave `--lang` off and open
`http://127.0.0.1:5000/?_LANG=fr` in your browser, or set your browser's
preferred language to French; the choice is remembered in a cookie. The
add form (press `a`), its validation messages (submit it empty), the
help dialog (press `h`) and the file management pages (the wrench icon,
with `--allow=edit`) each have their own strings. hledger-web reads the
catalogs when it starts, so restart it after editing your file; hledger
itself reads the file on every run.

If hledger prints a warning that it is ignoring your catalog, the file
has a syntax problem, usually an unclosed quote or a stray line; the
warning names the line. Poedit will not save an invalid file, so this
mostly happens with hand-edited ones.

To find what is still in English, compare with the same commands run
without `--lang`, or look at Poedit's counter of untranslated entries.

## Step 4: send it in

When you are happy with it, contribute the file:

- If you use GitHub: add it as `hledger-lib/locale/fr.po` and open a pull
  request. Two one-line changes are also needed to build it into hledger,
  and a maintainer will add them if you would rather not: list the file
  under `extra-source-files` in `hledger-lib/package.yaml`, and add
  `("fr", $(embedFileRelativeBytes "locale/fr.po"))` to
  `builtinCatalogSources` in `hledger-lib/Hledger/Utils/I18n.hs`.
- Otherwise, attach the file to an issue or a message on the
  [mail list](https://hledger.org/support.html), and someone will add it.

Please say in the pull request or message which terminology you chose
for the accounting terms (assets, liabilities, equity, revenues,
expenses), and why, especially where the everyday word differs from the
term accountants use in your country. The German catalog's choices are
explained in `hledger-lib/locale/README.md` as an example. Having a
second speaker, ideally someone who reads financial statements, look
over the file before it ships is worth a lot; hledger's maintainers
usually can not check a language themselves.

## Keeping a translation up to date

When hledger's English text changes, the template changes with it. To
refresh your file:

- In Poedit: Translation > Update from POT File, choosing the new
  `hledger.pot`. New entries appear untranslated; entries whose English
  changed are marked "needs work" (fuzzy) with your old translation kept
  for reference. Fix those, since fuzzy entries are not used until you
  clear the flag (the English text, or the built-in translation, shows
  instead).
- With the gettext tools: `msgmerge --update --previous fr.po hledger.pot`
  does the same.

In the hledger repository, `just i18n-merge` refreshes every built-in
catalog this way and `just i18n-check` lists stale entries and counts
untranslated ones, so a maintainer can tell you what a language needs.

## For developers

How strings become translatable, and the rules that keep them
translatable:

- `tr trs "Text"` translates a literal; `trc trs "context" "Text"`
  adds a context for a short word used in several senses; `trf trs
  "Text with {name}" [("name", value)]` fills placeholders after
  translation; `trn trs n "{n} day" "{n} days"` picks a plural form.
  `i18n "Text"` and `i18nc "context" "Text"` mark a literal that is
  stored now and translated later. In hledger-web templates, use
  `_{HMsg "Text"}` and `_{HMsgc "context" "Text"}`. The `trs` value
  comes from `translations_` in `ReportOpts`, or from `getViewData` in
  hledger-web. See `Hledger.Utils.I18n`.
- Write each call on one line, so the extraction tool finds it, and put
  a `-- TRANSLATORS: ...` comment on the line above when a translator
  would need context.
- One entry per sentence. Do not build sentences from translated
  fragments, since word order differs between languages; use one
  template with placeholders instead.
- Placeholders are `{name}` and are substituted after translation. Never
  pass a translation to `printf`.
- Keep the English string byte for byte as it was, including trailing
  colons, so that English output is unchanged.
- Never translate: journal-format output, csv/tsv/json headings, error
  messages, anything a program parses. Never insert a translation into
  HTML unescaped.
- Tooling: `just i18n-pot` regenerates `hledger-lib/locale/hledger.pot`
  from the sources with `tools/i18n-extract.py`; `just i18n-check`
  compares the catalogs with it; `just i18n-merge` runs msgmerge on them;
  `just i18n-pseudo` writes a catalog that brackets every string, so
  `hledger ... --lang xx` shows any output that is still hard-coded.
- The unit tests parse every built-in catalog and check that
  translations keep their placeholders; `hledger/test/i18n.test`,
  the yesod tests and `hledger-web/test/browser/i18n.spec.js` cover the
  German output end to end.
