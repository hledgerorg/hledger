---
name: changelogs
description: Update hledger's changelogs (*/CHANGES.md, one per package plus the project one in doc/). Run `just changelogs` to draft entries from git log since the last recorded commit, then polish them in phases (cleanup, wording, finalise). Use when asked to draft, update, polish or finalise changelogs.
---

# Changelogs

This skill describes how to update hledger changelogs, which are in */CHANGES.md.
There is one for each hledger package and one for the overall project (in doc/).

## Drafting changelogs

`just changelogs` adds draft changelog entries to the changelogs.
For each package in the source tree, it lists git log messages since the commit hash saved in the topmost level 1 heading, 
and inserts them below that heading (and then replaces that heading with the latest commit hash).

The drafts come partly pre-cleaned:
- items for routine bookkeeping commits (changelog updates, regenerated cabal files, etc) are dropped
- "AI usage:" trailer lines are stripped (AI usage is reported separately, by `just ai-commits`)
- in package changelogs, breaking changes (a "!" in the commit's category prefix) are moved to the top under a "Breaking changes" heading, with the rest under "Other changes"
- items that may duplicate an already-announced change are flagged with a "DUPLICATE?" or "CHERRYPICK?" note line.

If drafting fails with "resume point ... is not an ancestor of HEAD", the heading's commit
was rewritten by a rebase or amend; fix the headings with `just changelogs-catchup COMMIT`.

## Polishing changelogs

Here is how to polish a draft changelog. By default, you should 
- work on one package at a time, in this order: hledger-web, hledger-ui, hledger, hledger-lib, project.
- and one phase at a time, usually doing phase 1 for all of the packages first
- and ask for review of each changed item or group of items.

### Polish phase 1: cleanup
- focus on the new release changelog, which is all the items between the first two level 1 markdown headings. These are the draft entries to be polished. No changes should be made elsewhere.
- items towards the bottom of the new release changelog may have already been polished. These should be kept mostly as they are. For the rest,
- remove the semicolon prefix from change items.
- remove routine/boring/non-user-visible change items. But first, show them as a grouped and numbered list and ask for confirmation. Also save this list as a temp file for later review.
  Standard removal categories (confirmed conventions):
  - test-only or dev-only changes (a notable one may instead be summarised in the project changelog's Tools/infrastructure)
  - fixes for regressions introduced earlier in the same unreleased cycle (the regression was never released)
  - changes made and then reverted or superseded within the cycle: announce only the net change relative to the last release (eg merge successive dependency bound changes into one item stating the final bound)
  - refinements of a change made earlier in the same cycle: fold them into the parent item rather than listing separately
- remove duplicated/previously announced items. Act on the draft's DUPLICATE?/CHERRYPICK? flags, but also watch for duplicates without issue numbers, which can't be auto-flagged; already-announced items may use different wording. List removals, showing where they were previously announced.
- items backported from another branch may note their origin, eg "(Cherry picked from an AI-assisted change in hledger 2.x.)"
- items that mention "cli:" are user-visible CLI changes shared by all hledger tools (hledger, hledger-ui, hledger-web), and should be kept in each package's changelog.
- otherwise, package-specific items belong in exactly one changelog (eg web items only in hledger-web/CHANGES.md, not also in doc/).
- changes visible only to API users belong in the hledger-lib changelog.
- section headings, in package changelogs: "Breaking changes" comes first, when there are any (the draft provides it). After that, use topic headings for a long section (as in hledger's recent releases: ## Lot tracking, ## Reports, ## Data import etc), or a suitable generic heading or two otherwise (eg Fixes, Improvements) - or none, for a very short section. Don't use the old fixed six-heading template, and never leave empty headings.
- the category prefixes can be removed once items are in place; they can help choose headings first (eg "fix:" items under Fixes, and grouping "doc:" items compactly together).
- follow the layout of the (recent) previous releases' changelogs, below.
- The hledger-lib changelog is likely to have some end-user-visible items; these should be moved to the appropriate tool changelog (usually hledger/CHANGES.md).
  Only API-user-visible changes should remain in the hledger-lib changelog.
- In the project changelog (which keeps its own sections, listed in its header comment):
  Tools/process/infrastructure/justfile items should be summarised compactly in "Infrastructure/Misc".
  Project-level doc items (these often have upper-case filenames) should be summarised compactly in "Doc updates".
  Examples and scripts/addons/"bin:" items from the project changelog should be moved to the hledger changelog's "Examples" and "Scripts/addons" sections respectively.

### Polish phase 2: edits
- improve the spelling (british preferred), capitalisation, grammar, flow, and clarity of each item.
  They don't have to be perfect, but follow the style and tone of the older changelogs below.
- simple clear english is preferred.
- sometimes a commit message is too brief, unclear, or not in the usual style.
  When necessary we can find out more by inspecting the corresponding commit(s), looking for issue number or text matches.
- author(s) and issue numbers usually appear on their own line at the end of each item.
- we prefer real author names if available. Sometimes we can convert a commit author's nickname to a real name by looking up their github user page.

### Polish phase 3: links
- each issue number should be enclosed in square brackets (its own brackets - "[#1], [#2]", not "[#1, #2]")
- and at the end of the draft entries, markdown urls should be inserted for each issue, for hyperlinking.
  These look like:
  [#NNNN]: https://github.com/plaintextaccounting/hledger/issues/NNNN
- finally, run `just changelogs-check`, which verifies the resume points, the issue links, and that no DUPLICATE?/CHERRYPICK? markers remain; fix anything it reports.

## Finalising changelogs

On release day, when changelogs are polished and reviewed, run `just changelogs-check` once more,
then use `just changelogs-finalise` to replace the headings with the release version and date, and commit.
