---
name: translations
description: Add, update, check or review a translation of hledger's own text (a gettext PO catalog, in hledger-lib/locale/ or a user's config directory), for a maintainer or a translator. Covers the AI policy check, starting from the current template, a translation checklist, checking the result in the CLI, hledger-ui and hledger-web, and making a language built in. Use when asked to translate hledger into a language, complete or update a catalog after the English text changed, review a translation, or find text that is not yet translatable.
---

# Translations

This skill is for anyone working on a translation of hledger's own text
(report titles and headings, month names, hledger-ui's screens,
hledger-web's pages): maintainers, and translators, including first-time
contributors and people translating only for their own use.

Read these first; this skill adds an agent's workflow and checklists to them:

- `doc/TRANSLATING.md`: the guide for translators (file naming, PO format,
  placeholders, contexts, trying it out, sending it in, updating).
- `hledger-lib/locale/README.md`: the terminology and grammar choices made
  for each built-in language. Read the section for the language at hand.
- `hledger-lib/Hledger/Utils/I18n.hs`: the machinery, if needed.

## 0. Policy and situation

Before producing anything meant to be contributed, read the current
`doc/AI.md` and `.github/pull_request_template.md`. As of 2026-10:

- First-time hledger contributors must not use AI-generated code, tests or
  docs in their first merged pull request. Treat a catalog like docs. If the
  person you are helping has not yet had a pull request merged, tell them
  this before doing translation work for a contribution. The policy may
  have changed, so quote what it currently says.
- Translating for personal use (a catalog in their config directory, never
  submitted) is not a contribution, and the policy does not restrict it.
- Non-trivial AI usage must be disclosed in the commit, in the format
  `doc/AI.md` gives.

Establish, asking if it isn't clear:

- the language, and whether a regional or script variant is meant;
- whether this is a new language, or an update or review of an existing one;
- whether the person speaks the language natively, and knows its
  accounting vocabulary; this decides how the result is labelled (step 6);
- whether it is for personal use (`~/.config/hledger/locale/TAG.po`, used
  without rebuilding) or for contributing (`hledger-lib/locale/TAG.po`).

## 1. Start from the current template

In a source checkout, run `just i18n-check`. It fails if
`hledger-lib/locale/hledger.pot` is out of date with the sources; then run
`just i18n-pot` first (a maintainer commits the regenerated template).
Without a checkout, download the template from the URL in
`doc/TRANSLATING.md`, which is only as current as main.

## 2. Create or update the catalog

**New language.** Name the file by the language's tag in hledger's
normalized form, as the table in `doc/TRANSLATING.md` step 1 shows (`es`,
`pt-BR`, `zh-Hans`; not `es_ES` or `zh_CN`). Prefer the bare language tag
unless the language really differs by region or script. Create it from the
template with gettext's msginit, eg
`msginit --no-translator --locale=pt_BR -i hledger-lib/locale/hledger.pot -o hledger-lib/locale/pt-BR.po`,
which fills in `Plural-Forms` and removes the header's `#, fuzzy`. msginit
wants a POSIX-style locale name (`pt_BR`, `zh_CN`) even though the file is
named by hledger's tag. Or copy the template and edit the header as the
guide shows: set `Plural-Forms`, keep `charset=UTF-8`, remove `#, fuzzy`.
Keep the template's `#.` comments and `#:` references. Never change a
`msgid` or `msgctxt`.

**Existing language.** Run `just i18n-merge` (every built-in catalog) or
`msgmerge --update --previous FILE hledger-lib/locale/hledger.pot`. New
entries arrive empty. Entries whose English changed arrive marked fuzzy,
with the previous English in `#|` lines. For each fuzzy entry, compare the
old and new English and revise the translation, then remove the fuzzy flag
and the `#|` lines. Never just clear the flag: msgmerge's guess is often a
translation of a different string. Fuzzy entries are not used until cleared.

## 3. Translate: checklist

When an entry is unclear, read its `#.` comment, and look at how the `#:`
files use it.

- **Placeholders.** Keep every `{name}` exactly, moving it where the
  language needs it; add none. hledger ignores a translation whose
  placeholders differ (with a warning, for a user catalog), and the unit
  tests fail for a built-in one.
- **Shape.** Keep leading `", "` and trailing `":"`, parentheses around
  clarifications like `"(Historical Ending Balances)"`, and the trailing
  space of the one msgid that has it. These are appended to other text.
- **Whole phrases.** Each report title with an interval is its own entry,
  so order and inflect each as a whole. Check that the interval word can't
  be read as describing the wrong noun (Spanish: "Balance general anual con
  patrimonio", not "... con patrimonio anual").
- **Appended fragments.** `", valued at ..."`, `"{title}, filtered"` and
  the like follow titles of any gender, number or case. Phrase them so that
  they need no agreement (Spanish: ", con valoración al ...", "{title}, con
  filtro").
- **Collisions.** Different English strings that appear on the same page
  must not become the same word (Spanish: both "Daily" and "Journal" would
  be "Diario"; the Journal view became "Libro diario").
- **Contexts.** The same English word under different `msgctxt` may need
  different translations ("Search" in the search box and as a heading).
- **Terminology.** Decide the accounting terms first: the four statement
  names, assets, liabilities, equity, revenues, expenses, net. Keep them
  consistent with `examples/i18n/TAG.journal` if it exists, and say which
  accounting convention they follow.
- **Consistency.** One form of address (formal or informal) throughout.
  Headings capitalized as the language capitalizes headings; hledger-ui
  screen names lower case, as in English.
- **Months.** Stand-alone (nominative) forms. Keep abbreviations short,
  ideally three or four characters, since they are column headings.
- **Leave alone.** hledger query syntax, option names, file names, product
  names like hledger-web. No markup: translations are shown as plain text.

## 4. Check the result

- `msgfmt --check --statistics -o /dev/null FILE`. Warnings about missing
  `PO-Revision-Date`, `Last-Translator` or `Language-Team` header fields
  are harmless.
- In a checkout: `just i18n-check`, and for a built-in catalog the unit
  tests (`stack exec -- hledger test`), which check placeholders and tags.
- Built-in catalogs are embedded at build time: rebuild hledger,
  hledger-ui and hledger-web (`stack build`) before looking at them. A user
  catalog is read at run time, with no rebuild.
- **CLI.** Run the commands listed in `doc/TRANSLATING.md` step 3 with
  `--lang TAG`, and read the output as a user would: titles, column
  headings and alignment, the totals row.
- **hledger-web.** `just i18n-web TAG` starts hledger-web on the sample
  journal, requests every main page as a browser preferring TAG would, and
  prints each page's text and tooltips (including the file pages and the
  add form's validation messages), then stops it. A user catalog applies.
  Account names, descriptions and the version are journal data, not
  untranslated text.
- **hledger-ui.** Drive it with tmux, eg:

  ```
  tmux new-session -d -s i18nui -x 90 -y 16 "stack exec -- hledger-ui -f examples/sample.journal --lang TAG"
  sleep 4; tmux capture-pane -t i18nui -p
  tmux send-keys -t i18nui Down; tmux send-keys -t i18nui Right; sleep 1.5; tmux capture-pane -t i18nui -p
  tmux kill-session -t i18nui
  ```

  The menu, and each accounts screen's name in the top border, are
  translated. Use `kill-session`, never `kill-server`, which would end the
  person's other tmux sessions.
- **Text that is not translatable yet.** `just i18n-pseudo` writes a
  pseudo-locale catalog, `~/.config/hledger/locale/xx.po`, that brackets
  every translatable string. Then `hledger ... --lang xx` and
  `just i18n-web xx` show, without brackets, any English text that the
  sources don't yet mark for translation. That is a code change (wrapping
  the text in `tr` or `HMsg`, then `just i18n-pot`), not something a
  catalog can fix: report it rather than working around it. Delete `xx.po`
  afterwards, since it applies to every run with `--lang xx`.
- To test a built-in catalog's output in scripts or tests, set
  `XDG_CONFIG_HOME=/nonexistent` so that the person's own catalogs don't
  apply. `-n` is not enough: it skips only the config file.

## 5. Make a language built in

For a contribution, or a maintainer adding a language:

- Put the catalog at `hledger-lib/locale/TAG.po`.
- Register it in `builtinCatalogSources` in
  `hledger-lib/Hledger/Utils/I18n.hs` and in `extra-source-files` in
  `hledger-lib/package.yaml`, with the normalized tag (the unit tests check
  it; `just i18n-check` reports a catalog that isn't registered).
- In `hledger/hledger.m4.md`, add it to the sentence listing the built-in
  catalogs, giving the short spelling users type (`zh`, not `zh-Hans`).
  Edit only the `.m4.md`; the generated manuals are updated separately.
- In `hledger-lib/locale/README.md`, add a section for the language: who
  made it, its review status, a terminology table, and notes on the
  choices made (see the German and Spanish sections).
- In `hledger/test/i18n.test`, add a test that the language is selected by
  its tag and any usual alternative spellings, using
  `XDG_CONFIG_HOME=/nonexistent`. Don't assert the whole list of available
  languages, which changes whenever one is added.
- Run `just i18n-check`, the unit tests and `hledger/test/i18n.test`.

## 6. Labelling, review and commits

- A catalog that is machine-made, or not reviewed by a native speaker, says
  so: in a comment at the top of the catalog, and in its README section.
  Ask for review by a second speaker, ideally one who reads financial
  statements. hledger's maintainers usually can't check a language.
- Commit messages follow `doc/COMMITS.md` (or the repo's CLAUDE.md), eg
  `imp: i18n: Spanish translation (--lang es)` or
  `imp: i18n: update the German translation`, with the user-visible effect
  in the first paragraph, and the AI usage line when AI was used.
- Don't push, comment publicly, or open a pull request without the
  person's go-ahead.

## Problems seen so far

- A catalog was merged without being registered, so `--lang` couldn't
  select it (zh, 2026-09). `just i18n-check` now reports this.
- A catalog registered under a non-normalized tag (`zh_CN`) can never be
  selected. The unit tests now catch this.
- A catalog made from an old template lacked newer strings. Merge the
  current template before submitting.
- The committed template lagged behind the sources, so translators
  downloading it got an incomplete list. `just i18n-check` now fails on
  this; regenerate it whenever translatable text changes.
- Some hledger-web text isn't marked translatable yet (as of 2026-10: the
  statement pages' section titles and Net:, the balance page's column
  headings and Total:, the amount cells' tooltips, and the add form page's
  title). `just i18n-web` with a pseudo-locale shows it.
