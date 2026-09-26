// The journal and register views show the newest 1000 matching transactions
// and link to the older pages, so that a page stays small however large the
// journal is (#586). The server-rendered contracts (which rows a page holds,
// the links, the years row, the running balance) are covered by the
// yesod-test cases in Hledger/Web/Test.hs; this spec covers what only a
// browser shows. It starts its own hledger-web on a generated journal of 2300
// transactions, one a day from 2023-01-01, each moving 1 into assets:cash.
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { startServer } = require('./server');
const { watchViolations, watchPageErrors, expectNoViolations } = require('./helpers');

let server, URL, tmpdir;

test.beforeAll(async () => {
  // starting the server can take longer than the 30s hook timeout, eg on a cold stack
  test.setTimeout(120000);
  tmpdir = fs.mkdtempSync(path.join(os.tmpdir(), 'hledger-web-paging-'));
  const journal = path.join(tmpdir, 'paging.journal');
  const entries = [];
  const day = new Date(Date.UTC(2023, 0, 1));
  for (let i = 1; i <= 2300; i++) {
    entries.push(`${day.toISOString().slice(0, 10)} txn ${i}\n    assets:cash    1\n    income\n`);
    day.setUTCDate(day.getUTCDate() + 1);
  }
  fs.writeFileSync(journal, entries.join('\n'));
  ({ child: server, url: URL } = await startServer(['-f', journal, '--serve', '--host', '127.0.0.1', '--port', '0']));
});

test.afterAll(() => {
  try { if (server) process.kill(server.pid); } catch (e) { /* already gone */ }
  try { fs.rmSync(tmpdir, { recursive: true, force: true }); } catch (e) { /* fine */ }
});

test('a paged journal loads and pages without policy violations or errors', async ({ page }) => {
  const violations = await watchViolations(page);
  const pageErrors = watchPageErrors(page);

  await page.goto(URL + '/journal');
  await expect(page.locator('tr.title')).toHaveCount(1000);
  await page.locator('p.paging-nav a', { hasText: 'Older' }).first().click();
  await expect(page).toHaveURL(/\/journal\?page=2$/);
  await expect(page.locator('p.paging').first()).toContainText('Showing 1,001 to 2,000 of 2,300 transactions');

  await expectNoViolations(page, violations);
  expect(pageErrors).toEqual([]);
});

test('the register chart is drawn from the rows on the page', async ({ page }) => {
  const pageErrors = watchPageErrors(page);
  await page.goto(URL + '/register?q=inacct:assets:cash&page=2');
  const chart = page.locator('#register-chart');
  // the chart's data carries the transaction texts of this page's rows only
  await expect(chart).toHaveAttribute('data-series', /txn 1300\\n/);
  await expect(chart).not.toHaveAttribute('data-series', /txn 1301\\n/);
  await expect(chart.locator('canvas').first()).toBeVisible();
  expect(pageErrors).toEqual([]);
});

test('a link to a transaction on another page opens that page and scrolls to it', async ({ page }) => {
  await page.goto(URL + '/register?q=inacct:assets:cash&page=2');
  // the last row here is the oldest on the page, and its journal entry is at
  // the bottom of the journal's page 2, three thousand rows down
  const row = page.locator('#main-content .table-responsive tbody tr').last();
  await expect(row).toContainText('txn 301');
  await row.locator('td.date a').click();
  await expect(page).toHaveURL(/\/journal\?txn=301#transaction-1-301$/);
  await expect(page.locator('p.paging').first()).toContainText('Showing 1,001 to 2,000 of 2,300 transactions');
  await expect(page.locator('#transaction-1-301')).toBeInViewport();
});
