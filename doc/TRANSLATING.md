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

- hledger 1.99.6 or newer, which can write out the file to translate
  (check with `hledger --help | grep write-lang`). With an older
  hledger that has the `--lang` option, see
  [Without --write-lang](#without---write-lang).
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

1. Run `hledger --write-lang=LANG`. This puts your language's file,
   `LANG.po`, in hledger's config directory: a copy of hledger's
   translation if it has one, otherwise a new, untranslated file.
2. Translate the entries, or improve the existing translations.
3. Run hledger with `--lang LANG` to see them.
4. Repeat 2 and 3 until you are happy.
5. Send the file in (by mail is fine).

The rest of this guide goes through each step with Esperanto as the example.

## Step 1: get your language's file

Run hledger with `--write-lang` and your language's tag:

```
$ hledger --write-lang=eo
Wrote a new, untranslated eo catalog to /home/you/.config/hledger/locale/eo.po.
Edit it with Poedit or a text editor; hledger --lang eo uses it from now on.
To share your translation, see https://hledger.org/TRANSLATING.html.
```

For a language hledger already has, like `de`, it writes a copy of
hledger's own translation, to complete or improve. For a new language,
it writes a file with every entry untranslated. Either way the file
matches your hledger's version, so everything you translate shows up
when you try it. If a file for that language is there already, it is
left alone.

Entries marked with a `# machine-translated, please review` comment were
filled in by a machine translation before a release, so they are a good
place to start reviewing. In Poedit, search for `machine-translated`.
Once you have checked or corrected one, delete that comment line.

If you have only a few minutes, check the entries marked "Key term"
first. They are the seventy or so whose
mistranslation would mislead about money or data: the statement and
section names (Assets, Equity, ...), what a total means, balances vs
changes, cost vs value, gains, transaction status, and the warning before
overwriting a journal. For the accounting terms, your country's standard
ones are best, eg from official IFRS translations or national accounting
rules.

For a new language, check the file's `Plural-Forms` header (see
[Plural forms](#plural-forms)): hledger fills in the rule for many
languages, but for others, the most common rule, which may be wrong.

### Language tags

Language files are named by their language tag: `de.po` for German,
`fr.po` for French, `pt-BR.po` for Brazilian Portuguese, `zh-Hans.po`
for Simplified Chinese. A plain two-letter tag is usually right; add a
region or script only when the language really differs by it.
`--write-lang` puts the tag in hledger's form (`zh_CN` gives
`zh-Hans`), and finds a built-in catalog as `--lang` does (`de-AT`
gives `de`).

The name matters: the file's name is the tag that `--lang` selects it
by. A file named `fr_FR.po` is selected by `--lang fr-FR`, but not by
`--lang fr`. If you name or rename a file yourself, translation tools
often suggest names in the style of locale codes, like `zh_CN.po` or
`pt_BR.po`; use hledger's form instead:

| Tools may suggest | Name the file |
|---|---|
| `fr_FR.po`, `de_DE.po`, ... | `fr.po`, `de.po`, ... |
| `pt_BR.po` | `pt-BR.po` |
| `zh_CN.po` | `zh-Hans.po` |
| `zh_TW.po` | `zh-Hant.po` |
| `no.po`, `nb_NO.po` | `nb.po` |

### Plural forms

A file's header, the block at the top, says how plurals work in its
language:

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

`--write-lang` fills in a new file's header with the language's tag
and plural rule. It knows the rules in the table below; for other
languages it uses `nplurals=2; plural=(n != 1);`. If your language's
rule is different, change the `Plural-Forms` line (in Poedit,
Translation > Properties). Keep the charset as UTF-8. Common rules:

| Languages | Plural-Forms |
|---|---|
| English, German, Dutch, Spanish, Italian, Swedish, Turkish | `nplurals=2; plural=(n != 1);` |
| French, Portuguese (Brazil) | `nplurals=2; plural=(n > 1);` |
| Chinese, Japanese, Korean, Vietnamese, Thai, Indonesian | `nplurals=1; plural=0;` |
| Russian, Ukrainian, Belarusian, Serbian, Croatian, Bosnian, Polish, Czech, Slovak, Slovenian, Lithuanian, Latvian, Romanian, Irish, Arabic | three or more forms: see the [GNU gettext list](https://www.gnu.org/software/gettext/manual/html_node/Plural-forms.html) |

### Without --write-lang

With a hledger older than 1.99.6, start from the template that lists
every translatable string, `hledger.pot`, for your version: download
`https://raw.githubusercontent.com/hledgerorg/hledger/VERSION/hledger-lib/locale/hledger.pot`,
with VERSION replaced by your hledger's version number, eg `1.99.5`.
(To improve a language hledger already has, download `LANG.po` from
the same place instead.) Then:

- **With Poedit:** File > New From POT/PO File, choose `hledger.pot`, pick
  your language when asked, and save as `eo.po` (changing the name Poedit
  suggests, if needed). Poedit fills in the file header, including the
  plural rule for your language. The header's `Language:` line can stay
  as Poedit writes it; hledger goes by the file name.
- **With a text editor:** copy `hledger.pot` to `eo.po`, set `Language`
  and `Plural-Forms` in its header as above, and remove the `#, fuzzy`
  line above the header: it marks the whole file as a draft.

Put the file in hledger's config directory (see step 3).

## Step 2: translate the entries

Each string is one entry. Here is one from the template:

```po
#. the report title, eg "Monthly Balance Sheet 2024 (Historical Ending Balances), valued at period ends". {clarification} brings its own leading space when present.
#: hledger/Hledger/Cli/CompoundBalanceCommand.hs
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
- `#:` lines name the source files the text comes from. You can mostly ignore them.
- `#, python-brace-format` means the text contains placeholders.

In Poedit the same entry appears as a row; the notes show in the right
hand panel.

The entries are grouped by program, and a note on each group's first
entry says which it is: first those for the hledger command line
(some of which, like month names, the other programs show too), then
hledger-ui's, then hledger-web's, which are most of them. Untranslated
entries show in English, so you can translate just the groups for the
programs you use: the first group gives a translated command line, and
the first two cover most of hledger-ui.

### Placeholders

`{report}`, `{dates}`, `{account}` and similar are placeholders that
hledger fills in when it runs. Keep each one exactly as it is, but put
it where your language needs it. For example, "Transactions in
{account}" becomes "Buchungen in {account}" in German, and a language
that puts the date first can write "{dates} {report}" for the
title template. Do not translate the word inside the braces. Poedit
warns you if a placeholder goes missing, and so does hledger: a
translation that does not have exactly the English text's placeholders
is not used (the English text is shown instead), and hledger prints a
warning naming it.

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
directory, where `--write-lang` puts your file, and uses one found
there in preference to the built-in catalog for the same language. So
you can test without rebuilding anything:

| System | Your file is at |
|---|---|
| Linux, macOS | `~/.config/hledger/locale/eo.po` |
| Windows | `%APPDATA%\hledger\locale\eo.po` |

Then, once a few entries are translated, run some reports with `--lang eo`
(this is what an Esperanto file translating the balance sheet's four strings gives):

```
$ hledger -f sample.journal balancesheet --lang eo
Bilanco 2026-02-14

                      || 2026-02-14 
======================++============
 Aktivoj              ||            
----------------------++------------
 assets:bank:checking ||     75 EUR 
----------------------++------------
                      ||     75 EUR 
======================++============
 Pasivoj              ||            
----------------------++------------
----------------------++------------
                      ||          0 
======================++============
 Neto:                ||     75 EUR 
```

Commands that between them show most of the translatable text:

```
hledger -f sample.journal balancesheet --lang eo
hledger -f sample.journal incomestatement --lang eo -M -T -A
hledger -f sample.journal cashflow --lang eo
hledger -f sample.journal balance --lang eo -M
hledger -f sample.journal balance --lang eo -Q --value=then
hledger -f sample.journal balance --lang eo --budget -M
hledger-ui -f sample.journal --lang eo
hledger-web -f sample.journal --lang eo
```

For hledger-web you can also leave `--lang` off and open
`http://127.0.0.1:5000/?_LANG=eo` in your browser, or set your browser's
preferred language to Esperanto; the choice is remembered in a cookie. The
add form (press `a`), its validation messages (submit it empty), the
help dialog (press `h`) and the file management pages (the wrench icon,
with `--allow=edit`) each have their own strings. hledger-web reads the
catalogs when it starts, so restart it after editing your file; hledger
itself reads the file on every run.

If you have hledger's source code, `just i18n-web eo` shows all of
hledger-web's pages in one go, as text: it starts hledger-web, requests
each page as an Esperanto-preferring browser would (including the file pages
and the add form's validation messages), and prints the text and
tooltips of each, using your file.

If hledger prints a warning that it is ignoring your catalog, the file
has a syntax problem, usually an unclosed quote or a stray line; the
warning names the line. Poedit will not save an invalid file, so this
mostly happens with hand-edited ones. If instead it warns that it is
ignoring some translations, those have missing, extra or misspelled
placeholders (see Placeholders above); the rest of the catalog is used.

To find what is still in English, compare with the same commands run
without `--lang`, or look at Poedit's counter of untranslated entries.

## Step 4: send it in

When you are happy with it, or have done as much as you want to,
contribute the file. It needn't match the latest hledger: if hledger's
text has changed since you started, the maintainers will fit your file
to it.

- By mail: attach the file to a message on the
  [mail list](https://hledger.org/support.html), and someone will add it.
  It is committed with you as its author, so your name and email
  address appear in hledger's public git history, as for any contributor.
- If you use GitHub: add it as `hledger-lib/locale/eo.po` and open a pull
  request. Two one-line changes are also needed to build it into hledger,
  and a maintainer will add them if you would rather not: list the file
  under `extra-source-files` in `hledger-lib/package.yaml`, and add
  `("eo", $(embedFileRelativeBytes "locale/eo.po"))` to
  `builtinCatalogSources` in `hledger-lib/Hledger/Utils/I18n.hs`.
  The file name and the tag given there must both be the language's tag
  in hledger's form (see step 1), or `--lang` can not select it.
  `just i18n-check` reports a catalog that is not registered, and one
  that is not up to date; the unit tests check the tag.

Please say in the pull request or message which terminology you chose
for the accounting terms (assets, liabilities, equity, revenues,
expenses), and why, especially where the everyday word differs from the
term accountants use in your country. The German catalog's choices are
explained in `hledger-lib/locale/README.md` as an example. Having a
second speaker, ideally someone who reads financial statements, look
over the file before it ships is worth a lot; hledger's maintainers
usually can not check a language themselves.

Your file keeps taking precedence over hledger's built-in translation,
entry by entry. Once your work is in a release, delete your file or move
it aside, so that later improvements to the built-in translation show.

## Keeping a translation up to date

When hledger's English text changes, the template changes with it, and
a file made for an older version lacks the new entries. To keep working
on your file after upgrading hledger, refresh it from the new version's
template, as below (for where to download it, see
[Without --write-lang](#without---write-lang)).

If you work from hledger's source: the built-in catalogs on main are
refreshed only before a release, so between releases refresh your file
from main's template. Before each major or preview release there is a
short message freeze, when the English text stops changing and the
catalogs are refreshed, and a translation sprint; that is the best time
to update a translation. After it, any entries still untranslated are
filled in by machine translation, marked for review as described in
step 1, so every release ships complete catalogs.

To refresh your file:

- With the gettext tools: `msgmerge --update --no-fuzzy-matching --no-wrap eo.po hledger.pot`.
  New entries, and entries whose English changed, appear untranslated.
  An entry whose English changed keeps its old translation at the end of
  the file, as an obsolete `#~` entry, for reference.
- In Poedit: Translation > Update from POT File, choosing the new
  `hledger.pot`. Poedit also guesses translations for new and changed
  entries, from similar-looking ones, marking them "needs work" (fuzzy).
  These guesses are often translations of unrelated text, so check each
  one carefully, or clear it and translate afresh. Fuzzy entries are not
  used until you clear the flag (the English text, or the built-in
  translation, shows instead).

In the hledger repository, `just i18n-merge` refreshes every built-in
catalog this way. `just i18n-check` checks that the template is up to
date, and for each catalog lists stale entries, counts untranslated
ones, and reports it if it is not built in, so a maintainer can tell you
what a language needs.

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
- When you add, change or remove a translatable string, or its
  `TRANSLATORS:` comment, run `just i18n-pot` and commit the regenerated
  template with the change. Translators work from the template on main,
  so one left behind gives them an incomplete list. Don't run
  `just i18n-merge` or commit catalog changes with it: the catalogs are
  refreshed during the message freeze before a release, which keeps
  their empty new entries out of every pull request.
- Tooling: `just i18n-pot` regenerates `hledger-lib/locale/hledger.pot`
  from the sources with `tools/i18n-extract.py`, keeping existing
  entries in their order so that moving code between files doesn't
  reorder the template and catalogs (`--reorder` re-sorts them in source
  order); `just i18n-check`
  fails if the template differs from what `i18n-pot` would write, if a
  catalog has stale entries, or if a catalog file is not built in, and
  counts untranslated entries; `just i18n-merge` runs msgmerge on the
  catalogs; `just i18n-pseudo` writes a catalog that brackets every
  string, so `hledger ... --lang xx` (and `just i18n-web xx`, for
  hledger-web's pages) shows any output that is still hard-coded;
  `just i18n-web LANG` prints hledger-web's pages as a browser preferring
  LANG sees them.
- AI assistants (Claude Code and similar) can follow
  `.claude/skills/translations/SKILL.md`, which covers checking the AI
  policy, creating and updating catalogs, a translation checklist, and
  checking the CLI, hledger-ui and hledger-web.
- The unit tests parse every built-in catalog and check that its tag is
  in hledger's normalized form and that translations keep their
  placeholders; `hledger/test/i18n.test`, the yesod tests and
  `hledger-web/test/browser/i18n.spec.js` cover the German output end to
  end, and `i18n.test` checks that Chinese, Spanish and Russian are selectable.
