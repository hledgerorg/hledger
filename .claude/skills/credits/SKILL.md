---
name: credits
description: Update the commit-authors table in doc/CREDITS.md from the latest git history. Run `just authors`, merge the new counts into the table, refresh notes for authors whose commit count grew significantly, and move them into the correct digit-section. Use for the periodic (e.g. year-end) CREDITS refresh.
---

# Updating the CREDITS.md commit-authors table

`doc/CREDITS.md` holds a table of everyone who has committed to hledger, with a
short note summarising each person's contributions. `site/src/CREDITS.md` is a
**symlink** to it, so only edit `doc/CREDITS.md`.

The task: bring the table in sync with current git history — update counts, add
new contributors with notes, refresh notes for people whose contribution grew,
and keep everyone in the right section.

## Table structure

The table is authored in Markdown with embedded HTML, rendered by mdbook:

```
| Author                     | Notes                        |
|----------------------------|------------------------------|
| <h3><a name=five-digits href="#five-digits">5 digits</a></h3>  |
| <!-- 13594 -->  Simon Michael  | founder, project leader, lead developer |
| <h3><a name=four-digits ...>4 digits</a></h3>  |
| <h3><a name=three-digits ...>3 digits</a></h3>  |
| <!-- 477 -->    Stephen Morgan  | performance, code cleanup, ... |
...
```

Key points:
- **Authors are grouped into digit-sections** by commit count: `5 digits`
  (10000+), `4 digits` (1000+), `3 digits` (100+), `2 digits` (10+),
  `1 digit` (1-9). Each section starts with an `<h3>` anchor row. A section can
  be empty (just its header, e.g. `4 digits`).
- **The commit count lives in an HTML comment** `<!-- N -->` at the start of the
  first column, so it is hidden in the rendered page but still visible/editable
  in source. The visible cell is just the name (right-aligned by the `<style>`
  block above the table).
- **Within a section, rows are sorted by count descending.**
- An inline `<style>` block just before the table right-aligns the Author
  column, left-aligns Notes, and removes link underlines. Leave it in place.
- Below the table is a `contrib.rocks` avatar image.

## Workflow

### 1. Get the current author counts

```sh
git shortlog -sn main
```

Also useful:
```sh
git shortlog -sn main | wc -l                 # number of people
git shortlog -sn main | awk '{s+=$1} END{print s}'   # total commits
git log main --reverse --format=%as | head -1      # first commit date (for "N years")
```

### 2. Reconcile the latest author names the table

Names are canonicalised by `.mailmap`, but new contributors, renames,
and alias/case duplicates still need handling. Diff the shortlog names against
the table's names and investigate each difference:

```sh
git shortlog -sn main | sed -E 's/^ *[0-9]+\t//' | sort > /tmp/shortlog.txt
# extract current table names (strip the <!-- N --> prefix), sort, diff vs shortlog
```

For any name that appears/disappears, check the underlying identity before
deciding it's a new person:

```sh
git log main --format='%an <%ae>' | grep -i NAME | sort -u   # emails behind a name
grep -i NAME .mailmap                                         # existing mappings
```

Common cases:
- **Case/alias duplicates** (e.g. `ooker`/`Ooker`, `ob` for a real name) — same
  person, git counts them separately. Fix by adding a `.mailmap` entry, then
  **re-run the shortlog** so counts merge, before updating the table.
- **Misattributed commits** (e.g. `root <root@localhost>`) — usually a
  maintainer's commit from a misconfigured machine. Map to the real person in
  `.mailmap` (`Real Name <email> <bad@host>`), re-run shortlog, and drop the row.
- **Genuinely new contributors** — add a new row (see step 4).

`.mailmap` format is `Proper Name <canonical-email>` (canonicalise a name) or
`Proper Name <canonical-email> <alias-email>` (merge an alias). It's sorted
case-insensitively.

**Ask the user about anything ambiguous** — which of two spellings to display,
whether two identities are really one person, whether to include a junk row.

### 3. Update counts and re-section

For each existing author, update the `<!-- N -->` count. If a new count crosses
a digit boundary (e.g. 9 → 12, or 99 → 100+), **move the row into the correct
digit-section** and re-sort it within that section by descending count. Keep
the section header rows; a section may become empty or newly non-empty.

Update the stats line and Simon Michael's count at the top:

```
Stats as of YYYY-MM-DD: **NNNNN commits in NN years by NNN people**
```

### 4. Write notes for new authors

Every author should have a brief note. For a contributor with no note, read
their commit subjects and summarise in the existing style — lowercase-ish,
phrases separated by `;`, naming the command/feature/area (e.g.
`csv encoding rule; html export fix`, `tsv output format`,
`hledger-ui Windows support`). One short clause is fine for a single commit.

```sh
# deduped subjects for one author (skip merges)
git log main --author="NAME" --format='%s' | grep -v '^Merge ' | awk '!seen[$0]++'
```

Match the tone and brevity of the surrounding notes.

### 5. Refresh notes for authors whose count grew significantly

Identify authors whose count rose a lot since the last update (compare the old
table counts from git against the new shortlog; a threshold like +5, or a digit
boundary crossing, works well):

```sh
git show main:doc/CREDITS.md   # old counts, to diff against current shortlog
```

For each significant grower, look at their **recent** commits and fold the new
work into their note (and move them up / into the higher section if warranted).
Filter out noise (`dev`/`doc`/`cln`/`test`/merges) to find the substantive work:

```sh
git log main --author="NAME" --since=LAST_UPDATE_DATE --format='%s' \
  | grep -viE '^;?(dev|doc|cln|test|ref|Merge)' | sort -u
```

Keep the existing note's good content; append or integrate the new areas rather
than rewriting from scratch. Prefer concise phrasing over an exhaustive list.

### 6. Verify

- No author row left with an empty note.
- Every author is under the correct digit-section, sorted by count within it.
- Column alignment/padding is consistent with neighbouring rows (match the
  existing whitespace; the note column is padded to a fixed width).
- Stats line, Simon's count, and people/commit totals all agree with the
  shortlog.
- `git diff .mailmap doc/CREDITS.md` reads cleanly.

## Notes

- Do **not** hand-edit `site/src/CREDITS.md` — it's a symlink to `doc/CREDITS.md`.
- Doing the bulk merge/re-padding with a small script (Python) is far more
  reliable than editing ~200 rows by hand; verify alignment afterwards.
- When merging identities via `.mailmap`, always re-run `git shortlog -sn main`
  before touching the table so the counts already reflect the merge.
