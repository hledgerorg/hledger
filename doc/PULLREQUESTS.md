# Pull requests

Last updated: 2026-07

## Guidelines

<!-- keep synced -->
From <https://github.com/hledgerorg/hledger/blob/main/.github/pull_request_template.md?plain=1>:

We welcome help, but we must also balance the cost and benefit of pull requests,
with available maintainer/reviewer time, and with our [AI policy](https://hledger.org/AI.html).
Thanks for your understanding! Here are the current hledger PR guidelines:

1. PRs are processed only when a maintainer/reviewer has the time and motivation.
   Submitting a pull request does not guarantee a review or a response.

2. PRs that minimise work for maintainers/reviewers get processed more quickly.
   Eg, PRs that are small, clear, high quality, following guidelines, passing tests,
   non-conflicting, well researched, mindful of impact, responsive to feedback.

3. You can have one hledger PR open at a time (unless you have collaborator access).

4. First-time hledger contributors must not use AI to generate PRs.
   New-contributor PRs that seem AI-generated will be closed.

5. Code intended for the legacy hledger1 branch (hledger 1.x) must not use AI.
   (Maintainers may make rare exceptions, for security fixes.)

6. You must not use OpenAI's models (GPT series, o-series, etc).

7. Otherwise, you can use AI assistance. For any non-trivial use,
   you must disclose the provider, model(s), and a rough estimate of output tokens used.
   Eg, in your main commit: "AI usage: Claude Opus 4.8, ~50k output tokens."

8. Review your work before submitting it.

9. Begin commit messages with one of our standard prefixes.
   (And optionally a semicolon to mark commits that don't need costly CI tests.)
   Examples:
 
   - feat: a user-visible new feature
   - imp: a user-visible improvement to existing features
   - fix: a user-visible bugfix
   - dev: a less visible/internal improvement
   - ;doc: a documentation update
   - ;pkg: stack: something relating to packaging/dependencies and stack
   - ;tools: bin/bashrc: updates to our bash scripts

See also:
- <https://hledger.org/AI.html>
- <https://hledger.org/COMMITS.html>
- <https://hledger.org/PULLREQUESTS.html>


## Code review is important

We aim to improve and sustain hledger's quality and maintainability over the long term.

Ideally, we like to merge PRs quickly.
But some PRs can require substantial review, discussion, changes, or re-submission. 
Sometimes this is much more work than the coding.
Much valuable design, quality control, and knowledge sharing happens at this time. 
Some PRs ultimately get rejected, but their discussion and exploration can still be a useful contribution.
We want to avoid wasted work, but it occasionally happens. 
All of this is a normal part of software development.
We hope you'll see it as an opportunity to collaborate,
share and receive knowledge, refine your design/documentation/code,
and practice real-world development and communication skills.
Patience and persistence will pay off.

## The pull request

A PR should have a clear purpose, documented in its description. Mention any #ISSUENOs addressed.

Don't tackle too much at once. 
Smaller/more focussed PRs can be reviewed quicker and accepted (or rejected) quicker.

Consider showing a draft of documentation first (more on this below).

If you are not ready for the PR to be merged, please make it a Draft PR.
(But don't write "WIP:" or "Draft:" in the title, just use a normal title.)


## The commit(s)

Commits should be easy to review.
Ideally each commit is complete, and has a single clear purpose,
which should be documented in the summary (and long description, if needed).
\#ISSUENOs can be mentioned in summary/description too when appropriate.
If these constraints are satisfied, then fewer, larger commits are preferred.

Commit messages are valuable documentation for future developers and troubleshooters.
They are also the starting point for package changelogs and hledger release notes.
High-quality commit messages makes the release process quicker, and the resulting docs better. 

User-impacting commits should mention the user-visible changes, and be described in user-relevant language.
Library-user-impacting commits, eg API changes, ideally will also be called out, and can described in more technical language.
Commits affecting hledger internals are less important, but you may notice some adhoc conventions if you browse the history.
In particular, you can optionally prefix the summary with short component codes (cf [Issues](#issues))
to facilitate history reading and changelog/release note production.

Rewrite and force-push your commits freely (rebase -i, push -f) to clean them up. 
Unless we decide to squash the PR into one commit, 
your commits will become part of hledger's history "for all time", 
so think about future developers trying to understand them, git bisect, etc.   

Rebase your commits against latest main for easiest review. Especially if they start to conflict.

We like to use some conventions in commit messages when it makes sense. These aren't mandatory, but appreciated:

- prepend a [topic label](ISSUES.md#labels) prefix, eg `cli: ` or `journal: `, for clarity and to help with changelog production
- prepend a semicolon (`;`) to indicate commits that 
  - need not trigger a CI workflows, reducing wasteful carbon emissions
  - and probably need not be mentioned in changelogs/release notes

More detail: [COMMITS](COMMITS.md)

## The docs

PRs should include appropriate updates to reference documentation, unless otherwise agreed.
Typically this means the manual source files (hledger*/hledger*.m4.md).
It can also involve
command line option names and descriptions,
other --help output,
hledger's commands list,
hledger-ui's help dialog,
hledger-web's help dialog,
etc.
Sometimes it means the developer docs, at least the ones in the main repo (READMEs).

Reviewers can understand your PR more efficiently once proposed doc changes are provided, and may postpone it otherwise.
We are happy to help with the docs if needed - just ask.

Updating rendered manuals (hledger.{1,info,txt,md,html}) is not required, and probably best avoided to reduce conflicts.
Updating other docs such as tutorials, how-tos, examples, or screenshots is not required,
though it's welcome (may be in a different repo).

## Documentation-driven development

hledger follows documentation-driven design. 
It is highly effective, and recommended, to write a draft of new docs or doc changes
(in help text, user manual, haddocks, READMEs, ..) before writing any code.

Sharing a rough draft in the chat room, in an issue comment, or in a draft PR will speed up the discussion.
This is often the quickest road to getting something merged into hledger.
hledger's many parts interact in surprisingly complex ways.
The documentation-driven working style lets us discuss, clarify and reach a good-enough consensus more quickly.

## Shortcut urls

- <https://prs.hledger.org>
- <https://draftprs.hledger.org>
- <https://readyprs.hledger.org>
- <https://assignedprs.hledger.org>
- <https://unassignedprs.hledger.org>

