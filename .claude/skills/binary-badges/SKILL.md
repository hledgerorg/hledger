---
name: binary-badges
description: Check and refresh the version badges under "Packaged binaries" in site/src/install.md — update stale version numbers and set badge colour (green if current, red if outdated) by checking each package's actual page. Use when asked to update packaged/distro versions, refresh install.md badges, or similar.
---

# Updating packaged-binary version badges

`site/src/install.md` has a **Packaged binaries** section listing ~20 ways to
install hledger via OS/distro package managers, each with a version badge.

**`site/` is a separate git repo** (gitignored by the main hledger repo, with
its own remotes `origin` → `hledger_site.git` and `hledgerorg`). Commit
changes to `install.md` there — `cd site && git add src/install.md && git
commit ...` — not in the main repo. That repo's commit messages are plain
(no `;category:` prefix, no AI-disclosure line); match its existing log
style, e.g. `install: update packaged-binary version badges`.

## Temporary state since 2026-09-20: repology badges are static

repology.org has been offline since 2026-09-13 (domain on registrar hold; see
https://github.com/repology/repology-rs/issues/560). Until it returns, every
repology badge line in install.md carries a static shields.io badge instead,
with the original repology URL kept on the same line in an HTML comment:
`<!-- repology: https://repology.org/badge/version-for-repo/REPO/hledger.svg -->`.
While this lasts, treat those lines like the static badges below (check and
update their versions), and update the date in the "**Note:**" paragraph at
the top of the Packaged binaries section. When repology is back: swap each
shields URL back for the URL in its comment, drop the comments and the note,
and delete this section.

## Two kinds of badge — only one needs checking

1. **repology badges** — `https://repology.org/badge/version-for-repo/REPO/hledger.svg`.
   These are live images that repology itself keeps up to date. **Never
   "check" or edit these** — no version/colour is embedded in the URL to
   update.
2. **Static shields.io badges** — `https://img.shields.io/badge/LABEL-VERSION-COLOR.svg`.
   These are hand-authored and go stale. **These are the ones this skill
   updates.** Where a distro has multiple packaged releases listed (e.g.
   Fedora 45/44/43/42, Debian testing/stable/oldstable), check **every**
   one, not just the newest — each track's actual version can change
   independently between updates (a track can even jump past where it
   was, as distros rebase testing/stable/oldstable onto newer releases).

Grep for `img.shields.io/badge` within the `## Packaged binaries` section
(stop at `## Build from source`) to enumerate exactly which lines to work on.
Don't touch shields.io badges elsewhere on the page (e.g. the "Official
binaries" section's release-binaries badge follows the same format but is
assumed to be always up to date).

## Reference version

Read the current stable version from the top of the file:

    The current stable hledger release is **X.Y.Z**.

This is the target to compare each package's version against.

## Per-badge workflow

For each static shields.io badge line:

1. **Find the real current version.** Follow the badge's hyperlink (the
   `](URL)` the image is wrapped in):
   - If it goes straight to the package's page (Docker Hub image, a specific
     Fedora/Debian/Gentoo package page, etc.), fetch it and read off the
     published version.
   - If it goes to a repo/search page (e.g. a "search for hledger" URL),
     fetch it and locate the hledger entry to read its version.
   - Some sites are JS-heavy and won't render via fetch. Per project
     convention, don't fight this — show a clickable URL and ask the user
     to check the version there.
2. **Update the version number** in the badge URL to match exactly what the
   package page reports (don't normalize it to X.Y.Z — match upstream's own
   string, e.g. Debian may genuinely be on just "1.25", Fedora on "1.40").
3. **Set the colour**:
   - `brightgreen` if the package version equals the current stable version
     from the top of the page.
   - `e05d44` (hex, no `#`) otherwise, matching the red used by repology
     for outdated packages.
4. **Sanity-check the label** while you're in there: shields.io labels use
   `_` for spaces, and the visible alt text (`![Alt]`) should describe the
   same thing the label encodes (e.g. `![Fedora_45]` next to a label reading
   `Fedora_44_package` is a mismatch — fix the label, not the alt text, once
   you've established which Fedora version that row is actually for). Check
   this kind of alt-text/label/version alignment for every row you touch.

## Known frozen distro releases — skip these

Once a specific distro *release* (not the distro in general) reaches its own
end-of-life, its package version is permanently frozen — it will never gain a
newer hledger, so there's no need to re-check it on future runs. Skip these:

- **Fedora 42** — EOL 2026-05-13, frozen at hledger 1.32.3.
- **Sandstorm** — the app is no longer updated; frozen at hledger 1.31. (Not a distro release, but the same rule applies.)

When you confirm a release has newly reached EOL (e.g. its packages page
disappears from Fedora's active-releases table, or endoflife.date shows a
past EOL date), add it here with its frozen version so later runs skip it
straight away. If a listed EOL date is more than a year or two old, it's
worth a quick sanity check that the entry is still right.

## Check for new major distro releases not yet listed

For the distros with a run of version-specific rows — **Alpine, Debian,
Fedora, Ubuntu** — also check whether a newer major release now exists
upstream that isn't listed on the page yet:

- **Alpine**: check current stable branches (e.g. via
  https://alpinelinux.org/releases/ or the repology page) for one newer than
  the newest `alpine_X_Y` row here. If found, add a new repology-badge row
  above the current newest, in the same style (`![Alpine 3.NN](.../badge/version-for-repo/alpine_3_NN/hledger.svg)`).
- **Fedora**: check currently supported releases (e.g.
  https://fedoraproject.org/wiki/Releases or endoflife.date/fedora) for one
  newer than the newest `Fedora_NN` row. If found, add a new shields.io badge
  row above the current newest and check its real version per the per-badge
  workflow above.
- **Ubuntu**: check for a newer release (LTS or interim) than the newest
  `ubuntu_YY_MM` row, e.g. via https://wiki.ubuntu.com/Releases. If found,
  add a new repology-badge row above the current newest.
- **Debian** doesn't need this: its three rows (testing/stable/oldstable) are
  relative labels, not fixed version numbers, so they automatically track
  Debian's current release ladder without adding rows.

When a new row pushes the visible list past its usual length (these sections
currently show ~4 visible rows each), move the row that falls off the bottom
into an HTML comment rather than deleting it, matching the existing retired
rows (e.g. `<!-- [![ubuntu_18_04]... -->`, `<!-- ![Fedora_38]... -->`). Match
the exact formatting of its neighbours (backslash continuations, alt text
pattern, whether the row carries an install command).

## Judgment calls

- If a package's fetched version can't be pinned down confidently (ambiguous
  search results, page didn't load, version format is unclear), leave that
  line unchanged and flag it to the user rather than guessing.
- Preserve the line-continuation backslashes, HTML comments (commented-out
  older distro rows like `<!-- [![ubuntu_18_04]... -->`), and surrounding
  formatting exactly — this is a diff people will skim, so keep it minimal
  and mechanical.

## Verify

- `git diff site/src/install.md` — confirm only version numbers, colours,
  and (where fixed) mismatched labels changed; no accidental reformatting.
- Every repology-badge line is untouched.
- Every static badge's colour agrees with whether its version equals the
  current stable release stated at the top of the page.
