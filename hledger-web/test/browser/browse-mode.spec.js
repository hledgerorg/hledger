// The default mode, with no --serve flag, opens a browser on hledger-web and
// exits the server once no browser window has shown it for two minutes. The
// page tells the server it is open by pinging /_ping, from hledger.js, on
// load and then periodically (serveAndBrowse in Main.hs). This spec checks
// that the page is marked for the ping in this mode, that the ping goes out
// and is answered, and that it does so without any policy violation.
//
// It starts its own hledger-web, on port 5089 (HLEDGER_WEB_BROWSE_PORT), with
// the browser launcher stubbed out: hledger opens the browser with `open` on
// macOS and `xdg-open` elsewhere, found on PATH. On Windows it runs rundll32,
// which cannot be stubbed that way, so the spec is skipped there.
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

test('in browse mode, the page pings the server so that it keeps serving', async ({ page }) => {
  const violations = await watchViolations(page);
  const pageErrors = watchPageErrors(page);
  const ping = page.waitForRequest(req => req.url().startsWith(URL + '/_ping'));

  const response = await page.goto(URL + '/journal');
  expect(response.headers()['content-security-policy']).not.toContain('sha256-');
  await expect(page.locator('body')).toHaveAttribute('data-browse-mode');
  expect((await (await ping).response()).status()).toBe(204);
  await expectNoViolations(page, violations);
  expect(pageErrors).toEqual([]);
});
