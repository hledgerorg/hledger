// Browser tests for the /holdings page: in tree mode positions group
// under account heading rows that subtotal the dollar columns, and with
// lots=1 each position's lots start folded into it (data-fold-lots +
// reportTreeInit) and the caret opens them in place; a lot row's account
// link reaches that lot's register, quoting the lot subaccount name -
// including its auto label's double quotes - so the query round-trips;
// and the flat view shows the account names' shared prefix once, as a
// group heading, dimming each row's remaining parent path.
//
// Starts its own hledger-web on a lot-tracking journal, since the shared
// fixture journal has no lots.
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
  tmpdir = fs.mkdtempSync(path.join(os.tmpdir(), 'hledger-web-holdings-'));
  const journal = path.join(tmpdir, 'lots.journal');
  // two same-date buys, so the lots get automatic "0001"/"0002" labels,
  // and a second, deeper position, so the flat view has a path to dim
  fs.writeFileSync(journal, [
    'commodity AAA  ; lots:',
    'commodity BBB  ; lots:',
    'P 2026-02-01 AAA $12.00',
    '',
    '2026-01-01 buy one',
    '    assets:broker    2 AAA @ $10.00',
    '    assets:cash    $-20.00',
    '',
    '2026-01-01 buy two',
    '    assets:broker    3 AAA @ $11.00',
    '    assets:cash    $-33.00',
    '',
    '2026-01-02 buy bbb',
    '    assets:other:broker2    1 BBB @ $2.00',
    '    assets:cash    $-2.00',
    '',
  ].join('\n'));
  ({ child: server, url: URL } = await startServer(
    ['-f', journal, '--host', '127.0.0.1', '--port', '0', '--serve', '--allow=view']));
});

test.afterAll(() => {
  try { if (server) process.kill(server.pid); } catch (e) { /* already gone */ }
  if (tmpdir) fs.rmSync(tmpdir, { recursive: true, force: true });
});

test.describe('holdings page', () => {

  test('tree mode folds lots into their position, and the caret opens them', async ({ page }) => {
    const violations = await watchViolations(page);
    const errors = watchPageErrors(page);
    await page.goto(URL + '/holdings?list=tree&lots=1');
    const lotRows = page.locator('.report-table tr', { has: page.locator('td.account.lot'), hasText: 'AAA' });
    await expect(lotRows).toHaveCount(2);
    // the same-date lots were auto-labeled
    await expect(lotRows.first()).toContainText('"0001"');
    // the lots start folded into the position row...
    await expect(lotRows.first()).toBeHidden();
    await expect(lotRows.last()).toBeHidden();
    // ...whose caret shows it is closed, and opens them in place
    const broker = page.locator('.report-table tr', { has: page.locator('td.account.depth-1 a', { hasText: /^broker$/ }) });
    // the boring parent is squashed into its child, as on the command line
    await expect(page.locator('td.account.depth-1 a', { hasText: 'other:broker2' })).toBeVisible();
    await expect(broker.locator('.tree-caret')).toHaveText('▸');
    await broker.locator('.tree-caret').click();
    await expect(lotRows.first()).toBeVisible();
    await expect(lotRows.last()).toBeVisible();
    // the position row's units are its lots' sum, so the fold reconciles
    await expect(broker).toContainText('5 AAA');
    await expect(lotRows.first()).toContainText('2 AAA');
    await expect(lotRows.last()).toContainText('3 AAA');
    expect(errors).toEqual([]);
    await expectNoViolations(page, violations);
  });

  test('flat view shows the shared account prefix once and dims each parent path', async ({ page }) => {
    const violations = await watchViolations(page);
    const errors = watchPageErrors(page);
    await page.goto(URL + '/holdings');
    // the account names' shared prefix is shown once, over the table
    await expect(page.locator('.report-table tr.section th')).toHaveText('assets');
    // rows show the rest: the leaf name, and any dimmed path before it
    await expect(page.locator('td.account .acct-path')).toHaveText('other');
    // the register link still carries the full account name
    await page.locator('td.account a', { hasText: 'broker2' }).click();
    await expect(page).toHaveURL(/register/);
    await expect(page.locator('h2')).toContainText('assets:other:broker2');
    expect(errors).toEqual([]);
    await expectNoViolations(page, violations);
  });

  test('tree mode shows account headings with dollar subtotals', async ({ page }) => {
    const violations = await watchViolations(page);
    const errors = watchPageErrors(page);
    await page.goto(URL + '/holdings?list=tree');
    // the root account heading subtotals its subtree's costs ($53 AAA + $2 BBB)
    const heading = page.locator('.report-table tr', { has: page.locator('td.account.acctheading') });
    await expect(heading).toHaveCount(1);
    await expect(heading).toContainText('assets');
    await expect(heading).toContainText('$55.00');
    // a single-commodity account is one combined row carrying its figures
    const broker = page.locator('.report-table tr', { has: page.locator('td.account.depth-1 a', { hasText: /^broker$/ }) });
    await expect(broker).toContainText('5 AAA');
    await expect(broker).toContainText('$60.00'); // 5 AAA at the $12 market price
    // the heading's caret folds the whole group
    await heading.locator('.tree-caret').click();
    await expect(broker).toBeHidden();
    expect(errors).toEqual([]);
    await expectNoViolations(page, violations);
  });

  test("a lot row's register link round-trips its quoted name", async ({ page }) => {
    await page.goto(URL + '/holdings?list=tree&lots=1');
    // open the folded lots, then follow the labeled lot's register link
    await page.locator('td.account.depth-1', { has: page.locator('a', { hasText: /^broker$/ }) }).locator('.tree-caret').click();
    await page.locator('td.account.lot a', { hasText: '"0001"' }).click();
    await expect(page).toHaveURL(/register/);
    await expect(page.locator('h2')).toContainText('{2026-01-01, "0001", $10.00}');
    // its register shows the lot's one posting
    await expect(page.locator('td.description')).toHaveCount(1);
  });
});
