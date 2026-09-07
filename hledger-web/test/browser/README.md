# hledger-web browser tests

End-to-end tests for the hledger-web UI, using [Playwright](https://playwright.dev).
Unlike the yesod-test suite (`Hledger/Web/Test.hs`), these run a real browser, so
they cover the parts of hledger-web that only exist once javascript runs: the add
form, autocomplete, the date picker, keyboard shortcuts, sidebar state, and hash
highlighting.

- `webui.spec.js` — the UI's current behavior, so that changes to it are deliberate.
- `security.spec.js` — journal data is rendered as text and not markup, including the
  data handed to the autocomplete's javascript. `fixture.journal` deliberately
  contains html/javascript payloads for this. Also the Content-Security-Policy: it is
  sent, nothing on any page violates it, and a script without the nonce is blocked.
- `browse-mode.spec.js` — the default mode (no `--serve`), where the browser launcher
  inserts a ping script into every page: the policy allows it. This spec starts a
  second hledger-web on port 5089 (`HLEDGER_WEB_BROWSE_PORT`) with the launcher
  stubbed; it is skipped on Windows, where the launch cannot be intercepted.

Nothing here is part of `stack build` or `stack test`; the suite is opt-in and needs
node only to run it.

Each run starts its own hledger-web on port 5099 (override with `HLEDGER_WEB_PORT`)
against a scratch copy of `fixture.journal`, and stops it afterwards. The tests add
and edit transactions, so they need `--allow=edit`, which the setup passes.

## Setup (once)

Note: running these tests means installing and running javascript tooling from
the npm registry, and a browser it downloads. That is more exposure than the
rest of hledger's test suites carry, and the npm ecosystem has a history of
compromised packages. The settings below reduce the risk but do not remove it;
if that is not a trade you want to make on a machine you care about, run these
tests in a container or a throwaway environment, or not at all. The Haskell
suites (`stack test`) need none of this.

Uses [pnpm](https://pnpm.io) (>= 10). Config is in `pnpm-workspace.yaml`:
- `onlyBuiltDependencies: []` (no dependency build scripts run) and
- `minimumReleaseAge: 1440` (nothing published in the last 24h).
- `pnpm-lock.yaml` is committed. The one dependency is `@playwright/test`.

```sh
corepack enable                        # use the pnpm version pinned in package.json
cd hledger-web/test/browser
pnpm install --frozen-lockfile         # install exactly what pnpm-lock.yaml pins
pnpm exec playwright install chromium  # download the test browser
```

## Run

    # using a hledger-web binary on $PATH:
    pnpm test

    # or say how to run hledger-web (eg to test your working copy):
    HLEDGER_WEB="stack exec -- hledger-web" pnpm test

    # just the security tests:
    pnpm test security

    # watch the browser while it runs:
    pnpm test:headed

    # run one test:
    pnpm exec playwright test -g "adds a transaction"
