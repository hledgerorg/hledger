# AI policy

Last updated: 2026-09-21

The productivity benefits from AI-assisted software development are becoming obvious.
And the disruptions, costs and risks of AI will keep becoming clearer.

From 2026, in the hledger 2.x series, we are exploring ethical and effective use of AI to assist hledger development.

If you are a hledger user who objects to any use of AI, for one reason or another: I can understand.
The AI-free hledger 1.x still exists, will continue to receive regression fixes, and can be revived or forked at any time.

## Justification for AI use in this project

- I needed it to fully design and implement robust tax lot tracking in hledger.
  This is a feature that I have been wanting for many years, but it was just too big/intricate to tackle.
  Use of AI tools made it possible. I think it's unlikely hledger would have ever got this feature without them.

- Although lot tracking features exist in other free software (Beancount/Ledger/rustledger/BittyTax/rotki/RP2/..),
  I believe this new implementation provides flexibility currently not available elsewhere
  (privately and precisely modelling real world lot movements as required for tax reporting in the US,
  including pre- and post-2025 US booking methods).  This will (I hope) provide value to many.

- I imagine it is overall more efficient in resources and human energy,
  for developers to use AI to develop efficient deterministic software,
  than to have everyone using AI individually to try and do the same tasks less efficiently and less reliably.
  Ie, let's move the AI use upstream as far as possible - use it briefly at design/implementation time,
  not repeatedly at usage time.

- The "bitter lesson" says that general computation always eventually wins over special-purpose systems -
  suggesting that the lifetime and value of specialised tools like hledger will decrease.
  However, there is at least a time lag, and for some time yet there will be a gap in efficiency, cost, reliability,
  and so on, making this work worthwhile.

- We are making mindful limited use of unsustainable technologies for a short time, 
  in preparation for more sustainable versions (local LLMs, ASIC LLMs) coming soon.

- It is a learning experiment that can be discontinued or even rolled back at any time.

## Rules of engagement

Here are our current policies for AI use in hledger.

1. hledger does not use AI at runtime.

2. hledger 1.x (2007..2025) was developed without AI assistance.
   New commits intended for the legacy hledger1 branch may not use AI,
   except rarely, at maintainer's discretion, for security-related fixes
   (disclosure is still required).

3. hledger 2.x (2026..) is developed with careful AI assistance,
   in ways that increase quality and human maintainability.
   At any time we can stop using AI and keep moving forward.

4. We require disclosure of non-trivial AI usage, including
   the provider, model, and a rough estimate of output tokens used.
   Eg, in your main commit: "AI usage: Claude Opus 4.8, ~10k output tokens."
   See also "Measuring usage" below.

5. We try to use the more principled/trustworthy tools and providers,
   such as local LLMs, Ecosia, Anthropic.
   We don't use OpenAI models (GPT series, o-series, etc).

6. First-time hledger contributors must not use any AI-generated code, tests or docs in their first merged pull request.
   Human-generated commit messages and discussion are also encouraged.
  (We understand that some contributors are non-english speakers, who may want to use AI tools for translation.
   We are happy to see human communication, even with imperfections.)

7. The human committer is responsible for everything in their commits.
   Review your work before submitting it.

8. PRs require review by maintainers; if they are hard to review, they don't get merged, as always.

9. We track, optimise, and limit our AI resource usage as a project.
   We monitor the impacts of AI usage, and make adjustments when needed.

## More discussion / thoughts

### Can engaging with the AI phenomenon be ethical ?

- Choosing to avoid AI use entirely will become increasingly hard if not impossible.
But it's one possible stance, requiring Amish- or Stallman-like discipline.
My gut feeling is that absolute non-engagement isn't the right course for most of us.
It's possible that could change.

- It is here and will continue to unfold and impact us all for at least the next N years.
It shouldn't be left only to the boosters and zealots.

### Generating code with AI violates copyright of the training sources ?

- First, I'll note that the topic of copyright comes up only when using AI to generate code (docs, content..)
that is to be published. Much of the discussion here focusses on generated code, but let's keep in mind
that is just one of many ways AI can be used. Allowing AI use but writing all code by hand is a possible policy.
- Both in manual and automated coding, there's much grey area between clear plagiarism/theft, and fair use/independent invention.
- At some point, code is like science or mathematics: not ownable, belonging to all.
- "Copyright" is not a law of nature, not a consistent human law around the world, and not consistently applied,
eg to individuals and to large corporations. It's a mechanism, that was invented to achieve certain goals in a certain context.
The deeper goals we really care about are fairness, rule of law, innovation, stability, healthy society, etc.

### AI-generated code has unclear copyright / license ?

Remarks from gecko, summarised:
US courts have not recognised copyright in works that lack a human author, including works generated autonomously by AI.
In March 2025 the U.S. Court of Appeals for the D.C. Circuit affirmed, in Thaler v. Perlmutter,
that the Copyright Act "requires all eligible work to be authored in the first instance by a human being".
The Congressional Research Service's [LSB10922](https://www.congress.gov/crs-product/LSB10922) adds that
"human authorship is an essential part of a valid copyright claim", and that
"what matters is the extent to which the human had creative control over the work's expression".
Other jurisdictions, such as Europe, have their own rules.
So if fully AI-generated code were added to hledger, it might not be copyrightable,
could not then be licensed under the GPL, and the project could end up holding unlicensed code.

My (SM's) position: I'm assuming AI-assisted code is equivalent to code written by the human committer, until we hear otherwise.
I don't see how anything else is practical at present.
The lots work is essentially human-authored, using powerful tools -
similar in principle to how compiled machine code is human-authored, using a compiler to generate it.
Of course it's a spectrum, and we'll find out what the various courts decide.

### Is AI-generated code a copyright time bomb ?

I think hledger has less to lose there than a large business; we are a GPLv3+ project,
which means in practice nothing depends on us except similar projects.
Worst case, we roll back to hledger 1.x and rewrite things by hand.

### AI-generated code should be explicitly tagged ?

- That's a policy that might make sense in some cases. (I have annotated the merge of the recent lots branch this way, eg.)
But there's a spectrum of AI involvement which would complicate this,
and in the most general case I don't think it's enforceable or scalable.
I think it's more practical to keep associating authorship and responsibility with the human committer.

### AI's environmental impact ?

- It's bad of course, probably worse than we can see, and will remain so until we require it not to be.
It will continue to become more efficient and less costly in resources, possibly more quickly than we might expect.
Smaller AIs running on local devices powered by solar energy, eg.
Offsetting costly AI use with compensating actions could be helpful. (As eg Ecosia does.)
- We live in a time of collapse. Are current AI use and trends sustainable ?
Will widespread reliable energy, resources, infrastructure, stability, etc. continue to allow it ?
No, at least not in the ways we're used to. But AI is going to remain "cheap" and widely used for a while yet.
- Are the true costs of AI (capitalism+AI, really) being hidden from users ? Of course, as usual.
We should strive for more complete accounting, transparency, and truthful discourse
that includes all impacts on society and the planet.

### After 18 years of development, what was the sudden shortcoming?
Was it a shortage of time/labor or a technical problem that humans couldn't solve alone?

- Lots tracking in hledger was unimplemented for many years,
because the cost of designing and building it outweighed the need and the available resources
(part-time FOSS developer + occasional contributors). Lately,
    - The need has intensified. US tax reporting has become more strict and more complex,
    requiring the aid of software tools, and in the cryptocurrency era most of those are a security risk.
    - The latest AI tools (opus 4.6, claude code..) have dramatically lowered the cost.
    - As a lifelong programmer, once you have experienced the labour saving of a good AI setup,
    it becomes very hard to keep forcing your mind to jump through those hoops which are better suited to a machine.
    It feels like a waste of human spirit and energy.
    - Given the times, this was a good project to motivate exploring the new tech and surrounding issues,
    and how to use it or to respond to others using it.

## Measuring usage

The hledger project's estimated AI usage is tracked in [ai.journal](https://github.com/hledgerorg/hledger/blob/main/doc/ai/ai.journal).

Some notes on tracking AI usage:

### Anthropic API

For the initial lots work in the first 2.0 preview release (1.99.1),
here's my (SM's) estimated claude input+output tokens and costs,
from <https://platform.claude.com/usage>:

- 2026-01: 133 Mt,   $85
- 2026-02: 598 Mt,  $551
- 2026-03: 299 Mt,  $256
- Total:    ~1 Gt, ~$900

Estimated human dev time: ~150h, market value ~$10k-30k

### Anthropic monthly plan

From 2026-04-01, I'm using Anthropic's 6-month FOSS Claude Max plan (worth about $1200),
which I applied for and received after writing this policy.
It is helping recover the costs of the initial experimentation above.

[ccusage](https://ccusage.com) shows data from the claude code chat logs on your machine,
for both API and monthly plan usage.
It sees only the chat logs still present on the machine, so it can undercount;
for me it shows numbers much lower than the ones from platform.claude.com above.

`just h ai-` shows some related Justfile scripts.
Each month I import my estimated claude code usage data, summarised, to the project's ai.journal.
Other contributors' usage estimates can be added here too.

## Related

### Discussions
- in the hledger community
  - [mastodon](https://fosstodon.org/@happyborg/116312844334306281)
  - [mail list](https://groups.google.com/g/hledger/c/S7wCGw562yE)
  - [matrix](https://matrix.to/#/!6BCfAOV-btRKuqChph9Z_ppkIj8KttMoIL_rB4eU0Os/$Lu9jFe8JV5-uR8Mu0E9w4kv0moO2P48o64dmeO1InPs?via=asgard.chat&via=matrix.org&via=tchncs.de)
  - [Non-AI Tools? (/r/plaintextaccounting)](https://www.reddit.com/r/plaintextaccounting/comments/1sd1iar/nonai_tools)
- in the Haskell community
  - <https://discourse.haskell.org/search?q=LLM>
  - <https://www.reddit.com/r/haskell/search?q=ai+OR+llm&restrict_sr=on&sort=new&t=all>
- elsewhere
  - [The Closing of the Frontier](https://tanyaverma.sh/2026/04/10/closing-of-the-frontier.html) ([discussion](https://news.ycombinator.com/item?id=47742790))
  - [The Wonders of AI: We Are Retiring Our Bug Bounty Program](https://turso.tech/blog/the-wonders-of-ai) ([discussion](https://news.ycombinator.com/item?id=48148391))
  - <https://news.ycombinator.com/item?id=48142553> Have a Coherent AI Policy
  - <https://github.com/rust-lang/rust-forge/pull/1040> Add an LLM policy for rust-lang/rust

### Software Practitioners
- Donald Knuth: <https://cs.stanford.edu/~knuth/papers/claude-cycles.pdf>
- Kent Beck: <https://tidyfirst.substack.com/t/genies>,\
  <https://www.youtube.com/watch?v=5htJ2ML7BKU> 
- Martin Fowler: <https://martinfowler.com/fragments/2026-04-02.html>
- <https://news.ycombinator.com/item?id=47648828> Eight years of wanting, three months of building with AI
- Raffael Schneider: <https://raskell.io/articles/looking-back-on-2025>
- Bryan Cantrill: <https://bcantrill.dtrace.org/2026/09/05/the-revolt-of-the-reader/> on AI-assisted writing
- Andy Balaam: <https://artificialworlds.net/blog/2025/12/16/why-i-dont-use-ai/>, <https://artificialworlds.net/blog/2026/09/11/feeling-sad-about-ai/>

### Policies
- [Pope Leo XIV: Magnifica Humanitas: On Safeguarding The Human Person In The Time Of Artificial Intelligence](https://www.vatican.va/content/leo-xiv/en/encyclicals/documents/20260515-magnifica-humanitas.html)
  ([summary](https://www.theregister.com/ai-ml/2026/05/26/pope-leo-warns-ai-boom-can-give-big-tech-and-the-people-who-run-it-too-much-power/5245883))
- <https://sfconservancy.org/llm-gen-ai/llm-backed-generative-ai-recommendations.html>
- <https://docs.fedoraproject.org/en-US/council/policy/ai-contribution-policy>
- <https://github.com/stanford-cs336/assignment1-basics/blob/main/CLAUDE.md>
- <https://ladybird.org/posts/changing-how-we-develop-ladybird/> ([discussion](https://news.ycombinator.com/item?id=48409191))
- <https://blog.rust-lang.org/inside-rust/2026/08/05/rust-langrust-is-adopting-an-llm-policy> ([discussion](https://news.ycombinator.com/item?id=49179039))
- <https://dbushell.com/ai/> ([discussion](https://news.ycombinator.com/item?id=49537900))
- <https://www.visidata.org/blog/2026/ai/#self-assessed-ai-level-for-contributions>
- <https://rfd.shared.oxide.computer/rfd/0576>

### Research
- [AI 2027](https://ai-2027.com), [AI 2040](https://ai-2040.com)
- Jaron Lanier: <https://www.newyorker.com/science/annals-of-artificial-intelligence/there-is-no-ai>
- Margaret-Anne Storey: [From Technical Debt to Cognitive and Intent Debt: Rethinking Software Health in the Age of AI](https://arxiv.org/pdf/2603.22106)

### Law
- <https://www.congress.gov/crs-product/LSB10922>
- <https://legallayer.substack.com/p/who-owns-the-claude-code-wrote> ([discussion](https://news.ycombinator.com/item?id=47932937))

### Risks
- <https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/> (one of many)

### Tools
- <https://ccusage.com>
- <https://github.com/ratherlegit/environmental-impact-tracker>
- <https://www.pangram.com>
- <https://isaiprofitable.com>
