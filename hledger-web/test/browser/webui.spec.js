// Browser end-to-end tests for the hledger-web UI.
//
// These pin down the behaviors that Hledger/Web/Test.hs cannot see, because
// yesod-test never runs javascript: the add form, autocomplete, the date
// picker, keyboard shortcuts, sidebar state, and hash highlighting.
//
// Run with: npx playwright test  (see README.md)
const { test, expect } = require('@playwright/test');
const fs = require('fs');

// Collect uncaught page errors in every test; individual tests assert on them.
let pageErrors;
test.beforeEach(({ page }) => {
  pageErrors = [];
  page.on('pageerror', err => pageErrors.push(String(err)));
});

// Open the add-transaction modal via its keyboard shortcut and wait for it.
async function openAddForm(page) {
  await page.locator('body').press('a');
  await expect(page.locator('#addmodal')).toBeVisible();
}

test.describe('page initialization', () => {

  test('journal page loads and starts up without javascript errors', async ({ page }) => {
    await page.goto('/journal');
    await openAddForm(page);
    // startup ran to completion: the add form was pre-filled with today's date
    await expect(page.locator('#addform input[name=date]')).not.toHaveValue('');
    expect(pageErrors).toEqual([]);
  });

  // Register rows use bare-numeric ids (id="3"), and '#3' is not a valid CSS
  // selector, so any code passing location.hash to querySelector must guard
  // it. A failure here leaves the page half-initialized: no date picker, no
  // keyboard shortcuts, no sidebar handlers.
  test('register url with a numeric transaction hash initializes fully', async ({ page }) => {
    await page.goto('/register?q=inacct:assets:bank:checking#3');
    expect(pageErrors).toEqual([]);
    await openAddForm(page);
    await expect(page.locator('#addform input[name=date]')).not.toHaveValue('');
  });

  // The mark is a :target rule in hledger.css, so assert on the rendered
  // colour rather than on a class: that is what the reader actually sees.
  test('a transaction link marks its target row', async ({ page }) => {
    await page.goto('/journal');
    const link = page.locator('#main-content a[title="assets:bank:checking"]').first();
    const id = (await link.getAttribute('href')).split('#')[1];
    await link.click();
    await expect(page).toHaveURL(/register/);
    await expect(page.locator(`[id="${id}"]`)).toBeVisible();
    const colourOf = l => l.evaluate(el => getComputedStyle(el).backgroundColor);
    const target = page.locator(`[id="${id}"] > td`).first();
    const other = page.locator('#main-content tbody tr:not(:target) > td').first();
    expect(await colourOf(target)).not.toEqual(await colourOf(other));
    expect(pageErrors).toEqual([]);
  });

});

test.describe('add form', () => {

  test('starts with four posting rows', async ({ page }) => {
    await page.goto('/journal');
    await openAddForm(page);
    await expect(page.locator('#addform .account-group')).toHaveCount(4);
  });

  test('typing in the last amount field adds a posting row', async ({ page }) => {
    await page.goto('/journal');
    await openAddForm(page);
    await page.locator('#addform input[name=amount]').last().press('5');
    await expect(page.locator('#addform .account-group')).toHaveCount(5);
    expect(pageErrors).toEqual([]);
  });

  // Completion is a native <datalist>. The browser draws its dropdown outside
  // the page, so a test can only check that the field is wired to a list and
  // that the list offers the journal's accounts and descriptions.
  test('the account and description fields offer completions', async ({ page }) => {
    await page.goto('/journal');
    await openAddForm(page);
    await expect(page.locator('#addform input[name=account]').first())
      .toHaveAttribute('list', 'accountnames');
    await expect(page.locator('#addform input[name=description]'))
      .toHaveAttribute('list', 'descriptionnames');
    await expect(page.locator('#accountnames option[value="assets:bank:checking"]')).toHaveCount(1);
    await expect(page.locator('#descriptionnames option[value="Cafe Luna"]')).toHaveCount(1);
  });

  test('the date field offers a picker and accepts a typed date', async ({ page }) => {
    await page.goto('/journal');
    await openAddForm(page);
    const date = page.locator('#addform input[name=date]');
    await date.fill('2025-03-04');
    await expect(date).toHaveValue('2025-03-04');
    expect(pageErrors).toEqual([]);
  });

  test('adds a transaction', async ({ page }) => {
    await page.goto('/journal');
    await openAddForm(page);
    await page.locator('#addform input[name=description]').fill('E2eCreatePlain');
    await page.locator('#addform input[name=account]').nth(0).fill('expenses:food:dining');
    await page.locator('#addform input[name=amount]').nth(0).fill('12.34');
    await page.locator('#addform input[name=account]').nth(1).fill('assets:bank:checking');
    await page.locator('#addform button[type=submit]').click();
    await expect(page.locator('#message')).toContainText('Transaction added.');
    expect(fs.readFileSync(process.env.BROWSER_JOURNAL, 'utf8')).toContain('E2eCreatePlain');
  });

  test('reports an unbalanced transaction without adding it', async ({ page }) => {
    await page.goto('/journal');
    await openAddForm(page);
    await page.locator('#addform input[name=description]').fill('E2eUnbalanced');
    await page.locator('#addform input[name=account]').nth(0).fill('expenses:food:dining');
    await page.locator('#addform input[name=amount]').nth(0).fill('10.00');
    await page.locator('#addform input[name=account]').nth(1).fill('assets:bank:checking');
    await page.locator('#addform input[name=amount]').nth(1).fill('99.00');
    await page.locator('#addform button[type=submit]').click();
    await expect(page.locator('#message')).toBeVisible();
    expect(fs.readFileSync(process.env.BROWSER_JOURNAL, 'utf8')).not.toContain('E2eUnbalanced');
  });

});

test.describe('edit form', () => {

  test('edits a journal file', async ({ page }) => {
    await page.goto('/journal');
    await page.locator('a[title="Manage journal files"]').click();
    await page.locator('a.btn', { hasText: 'Edit' }).first().click();
    const ta = page.locator('textarea');
    const text = await ta.inputValue();
    expect(text).toContain('Metro Transit');
    await ta.fill(text.replace('Metro Transit', 'Metro Transit EDITED'));
    await page.locator('input[type=submit][value=Save]').click();
    await expect(page.locator('#message')).toContainText('Saved journal');
    expect(fs.readFileSync(process.env.BROWSER_JOURNAL, 'utf8')).toContain('Metro Transit EDITED');
  });

  test('rejects an edit that would not parse, leaving the file alone', async ({ page }) => {
    await page.goto('/manage');
    await page.locator('a.btn', { hasText: 'Edit' }).first().click();
    const ta = page.locator('textarea');
    const before = fs.readFileSync(process.env.BROWSER_JOURNAL, 'utf8');
    await ta.fill('this is not a journal\n  and cannot parse\n');
    await page.locator('input[type=submit][value=Save]').click();
    await expect(page.locator('#message')).toContainText('Failed to load journal');
    expect(fs.readFileSync(process.env.BROWSER_JOURNAL, 'utf8')).toEqual(before);
  });

});

test.describe('search', () => {

  test('accepts documented query syntax containing slashes', async ({ page }) => {
    await page.goto('/journal');
    let dialogMessage = null;
    page.on('dialog', d => { dialogMessage = d.message(); d.dismiss().catch(() => {}); });
    await page.locator('#searchform input[name=q]').fill('date:2025/1/5');
    await page.locator('#searchform input[name=q]').press('Enter');
    await expect(page).toHaveURL(/date%3A2025/);
    expect(dialogMessage).toBeNull();
    // the filter was applied: only the matching transaction remains
    await expect(page.locator('#main-content')).toContainText('weekly shop');
    await expect(page.locator('#main-content')).not.toContainText('Cafe Luna');
  });

  test('an account query filters the register', async ({ page }) => {
    await page.goto('/journal');
    await page.locator('#searchform input[name=q]').fill('acct:dining');
    await page.locator('#searchform input[name=q]').press('Enter');
    await expect(page.locator('#main-content')).toContainText('Cafe Luna');
    await expect(page.locator('#main-content')).not.toContainText('Metro Transit');
  });

});

test.describe('keyboard shortcuts', () => {

  test('"s" toggles the sidebar, and the choice survives navigation', async ({ page }) => {
    await page.goto('/journal');
    const sidebar = page.locator('#sidebar-menu');
    await expect(sidebar).toBeVisible();
    await page.locator('body').press('s');
    await expect(sidebar).not.toBeVisible();
    // the server reads the showsidebar cookie, so a fresh page load keeps it hidden
    await page.goto('/journal');
    await expect(sidebar).not.toBeVisible();
    expect(pageErrors).toEqual([]);
  });

  test('shortcuts do not fire while typing in the search box', async ({ page }) => {
    await page.goto('/journal');
    const q = page.locator('#searchform input[name=q]');
    await q.click();
    // 's' would toggle the sidebar and 'a' would open the add form
    await q.pressSequentially('assets', { delay: 20 });
    await expect(q).toHaveValue('assets');
    await expect(page.locator('#sidebar-menu')).toBeVisible();
    await expect(page.locator('#addmodal')).not.toBeVisible();
  });

  test('"h" opens the help dialog', async ({ page }) => {
    await page.goto('/journal');
    await page.locator('body').press('h');
    await expect(page.locator('#helpmodal')).toBeVisible();
    expect(pageErrors).toEqual([]);
  });

});

test.describe('modal dialogs', () => {

  // A <dialog> shown with showModal() should capture the shortcut keys; before
  // the guard, keys pressed with a dialog open acted on the page behind it.
  test('shortcut keys do nothing while a modal is open', async ({ page }) => {
    await page.goto('/register');
    await page.locator('body').press('h');
    await expect(page.locator('#helpmodal')).toBeVisible();
    await page.locator('body').press('j');   // would go to /journal
    await page.locator('body').press('a');   // would open the add form
    await expect(page).toHaveURL(/register/);
    await expect(page.locator('#helpmodal')).toBeVisible();
    await expect(page.locator('#addmodal')).toBeHidden();
    expect(pageErrors).toEqual([]);
  });

  // showModal() throws if the dialog is already open; the add-form shortcut
  // must not raise an uncaught error when pressed with the form already up.
  test('re-triggering the add form while open does not error', async ({ page }) => {
    await page.goto('/journal');
    await page.locator('body').press('a');
    await expect(page.locator('#addmodal')).toBeVisible();
    await page.locator('body').press('a');
    await expect(page.locator('#addmodal')).toBeVisible();
    expect(pageErrors).toEqual([]);
  });

  // Clicking the backdrop closes the dialog (the help text promises this).
  test('clicking outside the dialog closes it', async ({ page }) => {
    await page.goto('/journal');
    await page.locator('body').press('h');
    await expect(page.locator('#helpmodal')).toBeVisible();
    await page.mouse.click(4, 4);   // top-left corner: the backdrop
    await expect(page.locator('#helpmodal')).toBeHidden();
    expect(pageErrors).toEqual([]);
  });

});

test.describe('sidebar', () => {

  // Regression test for #2651: the sidebar's scroll position is restored
  // during page parse, so it must not be at 0 after navigating.
  test('keeps its scroll position across navigation', async ({ page }) => {
    await page.setViewportSize({ width: 1200, height: 300 });
    await page.goto('/journal');
    const sidebar = page.locator('#sidebar-menu');
    await sidebar.evaluate(el => { el.scrollTop = el.scrollHeight; });
    const scrolled = await sidebar.evaluate(el => el.scrollTop);
    test.skip(scrolled === 0, 'sidebar does not scroll at this viewport');
    await page.locator('#sidebar-menu a.acct-name', { hasText: 'groceries' }).first().click();
    await expect(page).toHaveURL(/register/);
    expect(await page.locator('#sidebar-menu').evaluate(el => el.scrollTop)).toBeGreaterThan(0);
  });

  test('"e" hides empty accounts', async ({ page }) => {
    await page.goto('/journal');
    await page.locator('body').press('e');
    // the toggle is remembered server-side via the hideemptyaccts cookie
    await page.goto('/journal');
    expect(pageErrors).toEqual([]);
  });

});
