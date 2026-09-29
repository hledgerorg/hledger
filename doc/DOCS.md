# DOCS

An overview of hledger's documentation structure and maintenance procedures, for developers and maintainers.
(For user documentation, see [Docs](doc.md).
For all developer documentation, see [Developer docs](dev.md).)

## Documentation structure

<div style="margin:1em 2em; font-style:italic;">
"There is a secret that needs to be understood in order to write good
software documentation: there isn’t one thing called documentation,
there are four. They are: tutorials, how-to guides, explanation and
technical reference. They represent four different purposes or
functions, and require four different approaches to their creation."
--[Daniele Procida] (https://news.ycombinator.com/item?id=21289832)
</div>

hledger's documentation lives in these places:

1. **The hledger.org website**: home page, install guide, docs hub, hledger by example,
   cookbook pages, developer docs, and current and past versions of the manuals.
   Its source is the `hledger_site` repo, usually cloned as `site/` in the hledger working copy,
   and rendered with [mdbook](https://rust-lang.github.io/mdBook/).
   `site/src/SUMMARY.md` defines the pages and the sidebar.
2. **The reference manuals** for hledger, hledger-ui and hledger-web.
   Their source is markdown with m4 macros, in the main repo:
   `hledger/hledger.m4.md` (which includes the command docs from `hledger/Hledger/Cli/Commands/*.md`),
   `hledger-ui/hledger-ui.m4.md` and `hledger-web/hledger-web.m4.md`.
   They are rendered as web pages, man pages, info manuals and plain text,
   and embedded in the hledger executables (see `hledger help`).
3. **Developer docs** in `doc/` of the main repo, such as this one.
   Most are symlinked into `site/src/` and published on the website.
4. **Per-package files**: `package.yaml` descriptions, `README.md` and `CHANGES.md` in each package directory,
   shown on Hackage.
5. **Code docs**: haddock comments and doctests in the Haskell source.
6. **Examples**: `examples/` (sample journals, the CSV rules library),
   the built-in command examples (`hledger help examples`, source in `doc/tldr/`),
   and the built-in demos (`hledger demo`).
7. **Other**: HCAR entries (`doc/hcar/`), announcements (`doc/ANNOUNCE*`), mockups (`doc/mockups/`),
   and project notes and specs (`doc/NOTE-*`, `doc/PLAN-*`, `doc/SPEC-*`; some of these are published).

### Conventions

- The manuals' top-level structure is deliberately flat: the PART headings and the sections within
  each part are all level-1 headings. This limits heading depth (info manuals support four levels,
  man pages two), and keeps the website sidebar simple. The built-in help command shows parts as
  containers by treating all-caps headings as one level up.
- "Since 1.x" notes in the manuals are kept only for the last few releases, then removed.
- Website pages (including published dev docs) which haven't been substantively updated in over a year
  carry a `Last updated: YEAR` line under their title. Hub and index pages don't.
- Internal links in the manuals are checked by `just anchortest`.

## Workflows

Last updated: 2025-09
<!-- keep synced with Justfile, Shake.hs -->

### Compile the Shake script

`Shake.hs` automates some doc maintenance tasks (complementing `Justfile)`.
Most contributors don't need to use it, but if you do, compile it like so:
in the hledger repo, run:
```
$ ./Shake.hs
```

### Update options help

Edit general options definitions in `hledger/Hledger/Cli/CliOptions.hs`
and  command options definitions in `hledger/Hledger/Cli/Commands/*.hs`.

### Update manuals' content

Updates and fixes for the manuals' content are welcome and encouraged!
They can be committed together with related code changes, or separately.

The manuals have (a) source files, kept in the hledger repo and (b) generated files derived from those.
Don't edit the generated files, such as:
- `hledger/hledger.md` or `hledger-ui/hledger-ui.md` in the hledger repo
- `site/src/1.50/hledger*.md` or `site/src/dev/hledger*.md` in the hledger_site repo

Instead, edit the source files:
- `hledger/hledger.m4.md` or `hledger/Hledger/Cli/Commands/*.md` for the hledger manual
- `hledger-ui/hledger-ui.m4.md` for the hledger-ui manual
- `hledger-web/hledger-web.m4.md` for the hledger-web manual.

(There are a few more source files which change less often;
if you click "edit this page" on a recent release manual on the website, you'll see all source files listed.)

### Update manuals' generated files

Contributors don't need to do this; usually it's done periodically by the maintainer.
It requires unix tools such as m4, makeinfo and pandoc.

In the hledger repo: first, set current year and month for the man pages:
```
$ just mandates
```

Then update the lists of command line options in the manuals' source files (only as needed, if command line options or option help have changed):
```
$ stack build && ./Shake cmddocs -c
```

Then regenerate the text, man, info, and markdown manuals in hledger*/ from their source files:

```
$ ./Shake manuals -c
```

### Update dev manuals on the website

When updates to manuals' generated files land in the main branch of the hledger repo on github,
the dev manuals on hledger.org will update automatically.

(The manuals on the website are rendered from `site/src/VERSION/*.md` in the hledger_site repo,
which are symlinked copies of `hledger/hledger.md`, `hledger-ui/hledger-ui.md` and `hledger-web/hledger-web.md` in the hledger repo.)

### Update release manuals on the website

Contributors can do this, but doing it the right way is a little complicated; you can also ask the maintainer to do it.

The release manuals on the website are rendered from `site/src/1.50/*.md`, `site/src/1.43/*.md`, etc.
These are generated as follows:

In the hledger repo, with the hledger_site repo symlinked as `./site`;\
for each major release REL that needs updating:

1. Cherry pick the manuals' content updates for REL (not generated files updates) from `main` to `REL-branch`
2. In main, run `just site-manuals-snapshot REL` to update the release manuals in the site repo.

When these commits land in the hledger_site repo on github,
the release manuals on hledger.org will update automatically.

### Add new release manuals to the website

A few extra steps are needed the first time new release's manuals are added to the site,
to update redirects and the version links shown at the top of manuals:

1. In the site repo, update and push version numbers in Makefile, site.js, hledger.org.caddy
2. On hledger.org, restart the web server
3. On cloudflare, purge hledger.org/site.js from the cache

### Update hledger binaries with latest docs

This ensures the hledger dev executables are embedding the latest manuals' generated files, affecting:
- options help displayed by `--help`
- command docs displayed by `CMD --help`
- manuals displayed by `help`, `--info`, and `--man`.

Update the options help, manuals' content and manuals' generated files as above, then rebuild:
```
$ stack build
```

### Update change logs

Changelogs are in `**/CHANGES.md` (one in each package, and one at top level for the project).
They should ideally be updated continually (at least weekly), in main, taking advantage of fresh memory and context.
At release time they get some extra polish, and are propagated to the release branch.

To update changelogs, in main or in a release branch:

1. Add new draft change notes to all changelogs (based on commit messages since the release or commit id mentioned in their first heading):
   ```
   $ just changelogs
   ```
2. Edit and polish the new change notes.
3. Add issue number links, eg with `md-issue-refs` macro.
4. Commit, eg with `just changelogs -c`

Note once the release branch is created, extra care is needed to keep changelogs synced between branches, considering:
- edits to existing change notes
- new change notes, corresponding to code changes cherry picked from main or created in the release branch.

At such times it may be useful to follow this sequence:
1. Add/sync code changes to the release branch.
2. Update change logs in release branch, based on latest commits there.
3. Cherry pick change log updates from the release branch to (that release's section in) the changelogs in main.
4. Update change logs in main, to add any more unreleased commits at the top (assisted by manual cleanup).

### Finalise change logs for a release

In the release branch, on the day of release, run this to add release headings and commit:
```
$ just changelogs-finalise
```

### Update release notes

Release notes are in `doc/relnotes.md` in the hledger repo (and symlinked as `site/src/relnotes.md` in the site repo).
They are generated at release time, from the finalised change logs.
Note once the release notes are generated, they should be kept in sync with any late updates to the changelogs (by regenerating them).

To update release notes:

1. In the release branch, with change logs finalised, run
   ```
   $ just relnotes
   ```
2. Review the new release notes. When changes are needed, change the changelogs, then regenerate the release notes as above.
3. Add release contributors and github nicks at the bottom.
4. Add release highlights at the top.
5. Commit.

### Update release notes on github

Release notes are uploaded to each github release, with some additional github-specific release docs.

In the release branch, once the corresponding github release is created, after updating release notes:

1. If needed, update github release docs in `doc/ghrelnotes`.
2. Push this and the latest release notes to the github release:
   ```
   $ just ghrel-notes
   ```

### Update release notes on the website

1. Cherry pick the latest release notes (`doc/relnotes.md`) from the release branch to main.
2. Push to the main branch on github. The website's "Release notes" page will update automatically.

### Diagrams

(approximate)
[![doc update diagrams](doc-update.png)](doc-update.png)
