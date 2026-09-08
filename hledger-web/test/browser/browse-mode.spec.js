// The default mode, with no --serve flag, runs hledger-web through
// wai-handler-launch: it opens a browser, inserts a ping script into every
// page, and exits the server when the pings stop. The Content-Security-Policy
// allows that script by its hash (cspHeader in App.hs). If a new version of
// the library changed the script's text, the hash would no longer match, the
// browser would block the script, and hledger-web would exit about two
// minutes into every session. This spec is the only automated check of that.
//
// It starts its own hledger-web, on port 5089 (HLEDGER_WEB_BROWSE_PORT), with
// the browser launcher stubbed out: the library runs `open` on macOS and
// `xdg-open` elsewhere, found on PATH. On Windows it calls ShellExecute
// directly, which cannot be intercepted, so the spec is skipped there.
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { startServer } = require('./server');
const { watchViolations, watchPageErrors, expectNoViolations } = require('./helpers');

const PORT = process.env.HLEDGER_WEB_BROWSE_PORT || '5089';
const URL = `http://127.0.0.1:${PORT}`;

test.skip(process.platform === 'win32', 'the browser launch cannot be stubbed on Windows');

let server, tmpdir;

test.beforeAll(async () => {
  // starting the server can take longer than the 30s hook timeout, eg on a cold stack
  test.setTimeout(120000);
  tmpdir = fs.mkdtempSync(path.join(os.tmpdir(), 'hledger-web-browse-'));
  for (const name of ['open', 'xdg-open']) {
    const stub = path.join(tmpdir, name);
    fs.writeFileSync(stub, '#!/bin/sh\nexit 0\n');
    fs.chmodSync(stub, 0o755);
  }
  const journal = path.join(tmpdir, 'browse.journal');
  fs.copyFileSync(path.join(__dirname, 'fixture.journal'), journal);
  server = await startServer(URL, ['-f', journal, '--host', '127.0.0.1', '--port', PORT],
    { PATH: tmpdir + path.delimiter + process.env.PATH });
});

test.afterAll(() => {
  try { if (server) process.kill(server.pid); } catch (e) { /* already gone */ }
  try { fs.rmSync(tmpdir, { recursive: true, force: true }); } catch (e) { /* fine */ }
});

test('in browse mode, the launcher\'s ping script is allowed by the policy and runs', async ({ page }) => {
  const violations = await watchViolations(page);
  const pageErrors = watchPageErrors(page);

  const response = await page.goto(URL + '/journal');
  expect(response.headers()['content-security-policy'])
    .toMatch(/script-src 'self' 'nonce-[^']+' 'sha256-[A-Za-z0-9+/]{43}='/);
  // the library's script is in the page, without a nonce, and was not blocked
  const pingScripts = await page.evaluate(() =>
    Array.from(document.scripts).filter(s => !s.src && s.textContent.includes('/_ping')).length);
  expect(pingScripts).toBe(1);
  await expectNoViolations(page, violations);
  expect(pageErrors).toEqual([]);
  // and the endpoint it pings is in place
  expect((await page.request.get(URL + '/_ping?' + Date.now())).status()).toBe(200);
});
