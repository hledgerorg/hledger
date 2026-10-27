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

// Hover an element, then nudge the pointer one pixel. hover() may scroll the
// element into view, and the scroll event, delivered on the next frame, hides
// the entry tooltip and cancels its pending show; the nudge is the small
// pointer movement a real hand always makes, which re-arms it.
async function hoverSettled(page, locator) {
  await locator.hover();
  const box = await locator.boundingBox();
  await page.mouse.move(box.x + box.width / 2 + 1, box.y + box.height / 2);
}

test.describe('page initialization', () => {

  test('journal page loads and starts up without javascript errors', async ({ page }) => {
    await page.goto('/journal');
    await openAddForm(page);
    // startup ran to completion: the add form was pre-filled with today's date
    await expect(page.locator('#addform input[name=date]')).not.toHaveValue('');
    expect(pageErrors).toEqual([]);
  });

  // A url hash can be anything, eg an old bookmark's numeric row id, and
  // '#3' is not a valid CSS selector, so any code passing location.hash to
  // querySelector must guard it. A failure here leaves the page
  // half-initialized: no date picker, no keyboard shortcuts, no sidebar handlers.
  test('register url with a numeric transaction hash initializes fully', async ({ page }) => {
    await page.goto('/register?account=assets:bank:checking#3');
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

  test('"a" opens it on the report pages too', async ({ page }) => {
    for (const url of ['/balancesheet', '/balance']) {
      await page.goto(url);
      await page.locator('body').press('a');
      await expect(page.locator('#addmodal')).toBeVisible();
    }
    expect(pageErrors).toEqual([]);
  });

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
    // the server reads the showsidebar cookie (named for its port), so a fresh page load keeps it hidden
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

  test('"h" and "?" toggle the help dialog', async ({ page }) => {
    await page.goto('/journal');
    await page.locator('body').press('h');
    await expect(page.locator('#helpmodal')).toBeVisible();
    await page.locator('body').press('h');
    await expect(page.locator('#helpmodal')).toBeHidden();
    await page.locator('body').press('?');
    await expect(page.locator('#helpmodal')).toBeVisible();
    await page.locator('body').press('?');
    await expect(page.locator('#helpmodal')).toBeHidden();
    expect(pageErrors).toEqual([]);
  });

  test('"/" focuses the search ready for another term, after a space', async ({ page }) => {
    await page.goto('/journal?q=assets');
    const search = page.locator('#searchform input[name=q]');
    await page.locator('body').press('/');
    await expect(search).toBeFocused();
    await expect(search).toHaveValue('assets ');
    // the cursor is at the end, nothing selected, so typing adds a term
    await page.keyboard.type('date:2025');
    await expect(search).toHaveValue('assets date:2025');
    // an empty search gets no space
    await page.goto('/journal');
    await page.locator('body').press('/');
    await expect(search).toBeFocused();
    await expect(search).toHaveValue('');
    expect(pageErrors).toEqual([]);
  });

  test('escape leaves the search field, keeping its text, and the shortcuts work again', async ({ page }) => {
    await page.goto('/journal?q=assets');
    const search = page.locator('#searchform input[name=q]');
    await page.locator('body').press('/');
    await page.keyboard.type('date:2025');
    await page.keyboard.press('Escape');
    await expect(page.locator('#main-content')).toBeFocused();
    await expect(search).toHaveValue('assets date:2025');
    await page.locator('body').press('g');
    await expect(page.locator('#gomenu')).toBeVisible();
    expect(pageErrors).toEqual([]);
  });

  test('"f" toggles full window mode, which survives navigation; escape or its button leave it', async ({ page }) => {
    await page.goto('/balance');
    const sidebar = page.locator('#sidebar-menu');
    const search = page.locator('#searchform');
    const heading = page.locator('#main-content h2').first();
    const table = page.locator('#main-content .report-table');
    const exit = page.locator('#fullwindow-exit');
    await expect(exit).toBeHidden();
    await page.locator('body').press('f');
    await expect(sidebar).toBeHidden();
    await expect(search).toBeHidden();
    await expect(page.locator('#main-content details.report-controls')).toBeHidden();
    await expect(heading).toBeVisible();
    await expect(table).toBeVisible();
    await expect(exit).toBeVisible();
    // pressed again, it leaves
    await page.locator('body').press('f');
    await expect(sidebar).toBeVisible();
    await expect(search).toBeVisible();
    // it's remembered for the tab, so a key that reloads the page keeps it
    await page.locator('body').press('f');
    await page.locator('body').press('M');
    await expect(page).toHaveURL(/interval=monthly/);
    await expect(search).toBeHidden();
    // escape closes the g menu first, then leaves full window mode
    await page.locator('body').press('g');
    await page.locator('body').press('Escape');
    await expect(page.locator('#gomenu')).toBeHidden();
    await expect(search).toBeHidden();
    await page.locator('body').press('Escape');
    await expect(search).toBeVisible();
    await expect(exit).toBeHidden();
    // and the button leaves it
    await page.locator('body').press('f');
    await exit.click();
    await expect(search).toBeVisible();
    expect(pageErrors).toEqual([]);
  });

  test('in full window mode, "s", "o" and "/" leave it, showing what they ask for', async ({ page }) => {
    await page.goto('/balance');
    const sidebar = page.locator('#sidebar-menu');
    const controls = page.locator('#main-content details.report-controls');
    const search = page.locator('#searchform input[name=q]');
    // s shows the sidebar, even one hidden before full window mode
    await page.locator('body').press('s');
    await expect(sidebar).toBeHidden();
    await page.locator('body').press('f');
    await page.locator('body').press('s');
    await expect(search).toBeVisible();
    await expect(sidebar).toBeVisible();
    // o opens the options
    await expect(controls).toHaveJSProperty('open', false);
    await page.locator('body').press('f');
    await page.locator('body').press('o');
    await expect(search).toBeVisible();
    await expect(controls).toHaveJSProperty('open', true);
    // / focuses the search
    await page.locator('body').press('f');
    await page.locator('body').press('/');
    await expect(search).toBeVisible();
    await expect(search).toBeFocused();
    expect(pageErrors).toEqual([]);
  });

  // On wider screens the main content scrolls by itself, not the window, so
  // it must have focus for the keyboard to scroll it.
  test('a page loads ready to scroll from the keyboard', async ({ page }) => {
    await page.setViewportSize({ width: 1200, height: 300 });
    await page.goto('/journal');
    const main = page.locator('#main-content');
    await expect(main).toBeFocused();
    test.skip(await main.evaluate(el => el.scrollHeight <= el.clientHeight), 'main content does not scroll at this viewport');
    await page.keyboard.press('PageDown');
    await expect.poll(() => main.evaluate(el => el.scrollTop)).toBeGreaterThan(0);
    expect(pageErrors).toEqual([]);
  });

  test('"g" shows the pages menu, and a page\'s key goes there', async ({ page }) => {
    await page.goto('/journal');
    const menu = page.locator('#gomenu');
    await expect(menu).toBeHidden();
    await page.locator('body').press('g');
    await expect(menu).toBeVisible();
    await expect(menu.locator('a[data-gokey="i"]')).toContainText('Income statement');
    await page.locator('body').press('i');
    await expect(page).toHaveURL(/\/incomestatement/);
    // n and p go to the next and previous pages
    await page.locator('body').press('g');
    await page.locator('body').press('n');
    await expect(page).toHaveURL(/\/cashflow/);
    await page.locator('body').press('g');
    await page.locator('body').press('p');
    await expect(page).toHaveURL(/\/incomestatement/);
    // escape closes the menu without going anywhere
    await page.locator('body').press('g');
    await expect(page.locator('#gomenu')).toBeVisible();
    await page.locator('body').press('Escape');
    await expect(page.locator('#gomenu')).toBeHidden();
    await expect(page).toHaveURL(/\/incomestatement/);
    // after g, "a" goes to All accounts rather than opening the add form
    await page.locator('body').press('g');
    await page.locator('body').press('a');
    await expect(page).toHaveURL(/\/balance/);
    await expect(page.locator('#main-content h2').first()).toHaveText('All accounts');
    expect(pageErrors).toEqual([]);
  });

  test('"o" toggles the report options, like clicking their summary', async ({ page }) => {
    await page.goto('/journal');
    const details = page.locator('#main-content details.report-controls');
    await expect(details.locator('p.report-links').first()).toBeHidden();
    await page.locator('body').press('o');
    await expect(details.locator('p.report-links').first()).toBeVisible();
    // the choice is saved like a click's, from the toggle event
    await page.waitForFunction(() => /showcontrols_\d+=1/.test(document.cookie));
    await page.locator('body').press('o');
    await expect(details.locator('p.report-links').first()).toBeHidden();
    await page.waitForFunction(() => /showcontrols_\d+=0/.test(document.cookie));
    expect(pageErrors).toEqual([]);
  });

  test('a depth typed in the search moves to the Depth row', async ({ page }) => {
    await page.goto('/balance');
    const search = page.locator('#searchform input[name=q]');
    await search.fill('assets depth:1');
    await search.press('Enter');
    await expect(page).toHaveURL(/q=assets&depth=1$/);
    await expect(search).toHaveValue('assets');
    await expect(page.locator('#main-content .depth .current')).toHaveText('1');
    expect(pageErrors).toEqual([]);
  });

  test('the report keys follow control links: digits set depth, "V" value, "t" tree, "M" monthly', async ({ page }) => {
    await page.goto('/balance');
    await page.locator('body').press('3');
    await expect(page).toHaveURL(/depth=3/);
    await page.locator('body').press('V');
    await expect(page).toHaveURL(/value=end/);
    await page.locator('body').press('t');
    await expect(page).toHaveURL(/list=tree/);
    await page.locator('body').press('M');
    await expect(page).toHaveURL(/interval=monthly/);
    // the keys are cased as hledger-ui's: lowercase v is not a key
    await page.locator('body').press('v');
    await expect(page).toHaveURL(/value=end/);
    expect(pageErrors).toEqual([]);
  });

  test('"+" and "-" step the depth limit through the Depth links, stopping at the ends', async ({ page }) => {
    // the fixture's deepest accounts are at depth 4, whose link removes the limit
    await page.goto('/balance?depth=3');
    await page.locator('body').press('+');
    await expect(page).not.toHaveURL(/depth=/);
    // at the deepest, + does nothing, so - goes to the one before it
    await page.locator('body').press('+');
    await page.locator('body').press('-');
    await expect(page).toHaveURL(/depth=3/);
    // 0 shows only the total; there, - does nothing, so + goes to 1
    await page.locator('body').press('0');
    await expect(page).toHaveURL(/depth=0/);
    await page.locator('body').press('-');
    await page.locator('body').press('+');
    await expect(page).toHaveURL(/depth=1/);
    expect(pageErrors).toEqual([]);
  });

  // The rows of report controls sit behind a disclosure, closed by default;
  // opening it is remembered in a cookie the server reads, so the next
  // page renders it already open.
  test('the controls disclosure starts closed, and stays open across pages', async ({ page }) => {
    await page.goto('/balance');
    const details = page.locator('#main-content details.report-controls');
    await expect(details.locator('p.report-links').first()).toBeHidden();
    await details.locator('> summary').click();
    await expect(details.locator('p.report-links').first()).toBeVisible();
    // the cookie is saved from the toggle event, which fires
    // asynchronously; wait for it before navigating away
    await page.waitForFunction(() => /showcontrols_\d+=1/.test(document.cookie));
    await page.goto('/journal');
    await expect(page.locator('#main-content details.report-controls p.report-links').first()).toBeVisible();
    expect(pageErrors).toEqual([]);
  });

  // Shift-clicking account types composes a type:AL.. search term; the
  // row marks each selected type.
  test('shift-clicking account types selects several', async ({ page }) => {
    await page.goto('/journal');
    await page.locator('#main-content details.report-controls > summary').click();
    const types = page.locator('#main-content div.types');
    await types.locator('a', { hasText: 'Asset' }).click();
    await expect(page).toHaveURL(/type%3AA/);
    await types.locator('a', { hasText: 'Liability' }).click({ modifiers: ['Shift'] });
    await expect(page).toHaveURL(/type%3AAL/);
    await expect(types.locator('a.current')).toHaveText(['Asset', 'Liability']);
    // a hand-typed search may hold several type: terms; composing
    // replaces them all with the one term (the controls stay open
    // here, via the cookie saved above)
    await page.goto('/journal?q=type%3AA%20type%3AL');
    await types.locator('a', { hasText: 'Equity' }).click({ modifiers: ['Shift'] });
    await expect(page).toHaveURL(/type%3AAEL/);
    expect(page.url().match(/type%3A/g).length).toBe(1);
    expect(pageErrors).toEqual([]);
  });

  // Many commodities collapse to a line showing the selection; opening
  // the list is remembered across pages. Shift-clicking composes a
  // cur:A|B search term from the links' data attributes, and the row
  // marks each selected one.
  test('the commodity list opens, stays open, and shift-click selects several', async ({ page }) => {
    await page.goto('/journal');
    await page.locator('#main-content details.report-controls > summary').click();
    const box = page.locator('#main-content div.commodities');
    await expect(box.locator('summary .sel')).toHaveText('All');
    await box.locator('summary').click();
    // its cookie too is saved from the asynchronous toggle event
    await page.waitForFunction(() => /showcommodities_\d+=1/.test(document.cookie));
    await box.locator('a', { hasText: 'USD' }).click();
    await expect(page).toHaveURL(/cur%3AUSD/);
    // the selection reads back, and the opened list is remembered
    // (the server renders it open, from the cookie)
    await expect(box.locator('summary .sel')).toHaveText('USD');
    await expect(box.locator('details')).toHaveAttribute('open', 'open');
    await box.locator('a', { hasText: '$' }).click({ modifiers: ['Shift'] });
    await expect(page).toHaveURL(/cur%3AUSD%7C%5C%24/);
    await expect(box.locator('a.current')).toHaveText(['$', 'USD']);
    expect(pageErrors).toEqual([]);
  });

  // Zero balances state is the empty parameter; the row's links set it,
  // and the "e" key presses the row's other link.
  test('"z" and the Zero balances links switch a page between showing and hiding zero balances', async ({ page }) => {
    await page.goto('/balance');
    const current = page.locator('#main-content .zero-balances a.current');
    await expect(current).toHaveText('Shown');
    await page.locator('#main-content details.report-controls > summary').click();
    await page.locator('#main-content .zero-balances a', { hasText: 'Hidden' }).click();
    await expect(page).toHaveURL(/empty=0/);
    await expect(current).toHaveText('Hidden');
    await page.locator('body').press('z');
    await expect(page).not.toHaveURL(/empty=/);
    await expect(current).toHaveText('Shown');
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
    await page.locator('body').press('g');   // would open the pages menu
    await page.locator('body').press('a');   // would open the add form
    await expect(page).toHaveURL(/register/);
    await expect(page.locator('#helpmodal')).toBeVisible();
    await expect(page.locator('#addmodal')).toBeHidden();
    await expect(page.locator('#gomenu')).toBeHidden();
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

  // Escape closes a dialog, even from one of its fields, marking the key
  // handled, which keeps Safari in full screen.
  test('escape closes a dialog, as a handled key', async ({ page }) => {
    await page.goto('/journal');
    await page.evaluate(() => {
      window.addEventListener('keydown', e => { window.lastKeyHandled = e.defaultPrevented; });
    });
    await page.locator('body').press('h');
    await expect(page.locator('#helpmodal')).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.locator('#helpmodal')).toBeHidden();
    expect(await page.evaluate(() => window.lastKeyHandled)).toBe(true);
    await page.locator('body').press('a');
    await expect(page.locator('#addmodal')).toBeVisible();
    await page.locator('#addform input[name=description]').focus();
    await page.keyboard.press('Escape');
    await expect(page.locator('#addmodal')).toBeHidden();
    expect(await page.evaluate(() => window.lastKeyHandled)).toBe(true);
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

  test('"z" hides empty accounts, as the empty parameter', async ({ page }) => {
    await page.goto('/journal');
    await page.locator('body').press('z');
    await expect(page).toHaveURL(/\/journal\?empty=0/);
    await page.locator('body').press('z');
    await expect(page).not.toHaveURL(/empty=/);
    expect(pageErrors).toEqual([]);
  });

  test('links to the financial statements, marking the one shown', async ({ page }) => {
    // at a laptop width the sidebar is narrow; the report labels must still fit
    await page.setViewportSize({ width: 1000, height: 800 });
    await page.goto('/journal');
    const clipped = await page.locator('#sidebar-menu td.top').evaluateAll(
      tds => tds.filter(td => td.scrollWidth > td.clientWidth).map(td => td.textContent.trim()));
    expect(clipped).toEqual([]);
    await page.locator('#sidebar-menu a', { hasText: 'Income statement' }).click();
    await expect(page).toHaveURL(/\/incomestatement$/);
    await expect(page.locator('#main-content h2')).toContainText('Income Statement');
    await expect(page.locator('#sidebar-menu tr.inacct a')).toHaveText('Income statement');
    // from a report, the other reports are one click away in the Report row
    await page.locator('#main-content .report-links a', { hasText: 'All accounts' }).click();
    await expect(page).toHaveURL(/\/balance$/);
    expect(pageErrors).toEqual([]);
  });

  // The balance sheet with equity is the balance sheet with its Equity
  // row's Shown link, a choice remembered; its old page's url leads there.
  test('the balance sheet\'s Equity row shows or hides the equity section, and is remembered', async ({ page }) => {
    await page.goto('/balancesheet');
    const heading = page.locator('#main-content h2').first();
    const sidebarlink = page.locator('#sidebar-menu a', { hasText: 'Balance sheet' });
    await expect(heading).not.toContainText('With Equity');
    await page.locator('#main-content details.report-controls > summary').click();
    await page.locator('#main-content .equity a', { hasText: 'Shown' }).click();
    await expect(page).toHaveURL(/\/balancesheet\?equity=1$/);
    await expect(heading).toContainText('Balance Sheet With Equity');
    await sidebarlink.click();
    await expect(page).toHaveURL(/\/balancesheet$/);
    await expect(heading).toContainText('Balance Sheet With Equity');
    await page.locator('#main-content .equity a', { hasText: 'Hidden' }).click();
    await expect(page).toHaveURL(/\/balancesheet\?equity=0$/);
    await expect(heading).not.toContainText('With Equity');
    await sidebarlink.click();
    await expect(heading).not.toContainText('With Equity');
    await page.goto('/balancesheetequity');
    await expect(page).toHaveURL(/\/balancesheet\?equity=1$/);
    expect(pageErrors).toEqual([]);
  });

  // The fixture's ZZZ balances are too wide to fit beside their account
  // names at a laptop width, and go below them; at a desktop width every
  // balance fits beside its name.
  test('every balance is shown whole, clear of its account name', async ({ page }) => {
    for (const [width, beside] of [[1400, true], [900, false]]) {
      await page.setViewportSize({ width, height: 800 });
      await page.goto('/journal');
      const problems = await page.locator('#sidebar-menu').evaluate((sidebar, beside) => {
        const s = sidebar.getBoundingClientRect();
        const found = [];
        for (const tr of sidebar.querySelectorAll('tr[data-indent], tr.total')) {
          const spans = [...tr.querySelectorAll('td.amount span.amount')].map(e => e.getBoundingClientRect());
          if (!tr.getClientRects().length || !spans.length) continue;
          const row = tr.getAttribute('data-acct') || 'total';
          const name = tr.querySelector('td.acct, td.total-label').getBoundingClientRect();
          const left = Math.min(...spans.map(r => r.left)), right = Math.max(...spans.map(r => r.right));
          const top = Math.min(...spans.map(r => r.top));
          if (left < s.left || right > s.right) found.push(`${row}: cut off`);
          if (left < name.right && top < name.bottom) found.push(`${row}: over its name`);
          if (name.width <= s.width / 4) found.push(`${row}: name squeezed`);
          if (beside && top >= name.bottom) found.push(`${row}: below its name`);
        }
        return found;
      }, beside);
      expect(problems, `at ${width}px`).toEqual([]);
    }
  });

});

test.describe('report tree folding', () => {

  // A tree-mode report serves every depth and folds to the depth limit;
  // the carets open and close groups in place, without changing the URL.
  test('folds to the depth limit, and carets unfold groups in place', async ({ page }) => {
    await page.goto('/balance?list=tree&depth=1');
    // expenses is a group, whose subaccounts are folded at depth 1
    const top = page.locator('td.account.indent-0', { hasText: 'expenses' });
    const deep = page.locator('td.account.indent-1', { hasText: 'food' });
    await expect(top).toBeVisible();
    await expect(deep).toBeHidden();
    // a boring parent at the fold depth keeps its own row, as with --depth 1
    await expect(page.locator('td.account.indent-0').getByText('assets', { exact: true })).toBeVisible();
    await expect(page.locator('td.account.indent-1').getByText('bank:checking', { exact: true })).toBeHidden();
    await top.locator('.tree-caret').click();
    await expect(deep).toBeVisible();
    await expect(page).toHaveURL('/balance?list=tree&depth=1');
    await top.locator('.tree-caret').click();
    await expect(deep).toBeHidden();
    expect(pageErrors).toEqual([]);
  });

  // The sidebar's accounts fold too, and the fold is remembered in
  // this browser, so the sidebar stays as you left it between pages.
  test('in tree mode the sidebar folds, and stays folded across navigation', async ({ page }) => {
    await page.goto('/journal?list=tree');
    const deep = () => page.locator('#sidebar-menu tr[data-acct="expenses:food:groceries"]');
    await expect(deep()).toBeVisible();
    await page.locator('#sidebar-menu tr[data-acct="expenses"] .tree-caret').click();
    await expect(deep()).toBeHidden();
    await page.goto('/balance?list=tree');
    await expect(deep()).toBeHidden();
    await page.locator('#sidebar-menu tr[data-acct="expenses"] .tree-caret').click();
    await expect(deep()).toBeVisible();
    expect(pageErrors).toEqual([]);
  });

  // A depth limit is each page's baseline: the sidebar starts folded to
  // it, groups opened or closed by hand are remembered over it, and a
  // caret clicked back to its page's baseline is forgotten.
  test('a depth limit folds the sidebar, and caret choices are remembered over it', async ({ page }) => {
    await page.goto('/journal?list=tree&depth=2');
    const food = () => page.locator('#sidebar-menu tr[data-acct="expenses:food"]');
    const groceries = () => page.locator('#sidebar-menu tr[data-acct="expenses:food:groceries"]');
    await expect(food()).toBeVisible();
    await expect(groceries()).toBeHidden();
    // opening past the limit is remembered on the next page
    await food().locator('.tree-caret').click();
    await expect(groceries()).toBeVisible();
    await page.goto('/balance?list=tree&depth=2');
    await expect(groceries()).toBeVisible();
    // closing it again returns it to the baseline, so a page without a
    // depth limit, whose baseline is fully open, shows it open
    await food().locator('.tree-caret').click();
    await expect(groceries()).toBeHidden();
    await page.goto('/journal?list=tree');
    await expect(groceries()).toBeVisible();
    expect(pageErrors).toEqual([]);
  });

  // The other direction: a group folded by hand stays folded on a page
  // whose depth limit would open it.
  test('a fold made by hand holds against a depth limit', async ({ page }) => {
    await page.goto('/journal?list=tree');
    const food = () => page.locator('#sidebar-menu tr[data-acct="expenses:food"]');
    await page.locator('#sidebar-menu tr[data-acct="expenses"] .tree-caret').click();
    await expect(food()).toBeHidden();
    await page.goto('/journal?list=tree&depth=3');
    await expect(food()).toBeHidden();
    expect(pageErrors).toEqual([]);
  });

  // Without a depth, the tree starts fully open and can be folded.
  test('an unfolded tree collapses from any group', async ({ page }) => {
    await page.goto('/balance?list=tree');
    const deep = page.locator('td.account.indent-1').first();
    await expect(deep).toBeVisible();
    await page.locator('td.account.indent-0', { hasText: 'expenses' }).locator('.tree-caret').click();
    await expect(deep).toBeHidden();
    expect(pageErrors).toEqual([]);
  });

});

// Hovering a transaction shows its journal entry in a tooltip drawn by
// hledger.js, in a fixed-width font (#2716). It behaves like a browser's own
// tooltip: it appears after a pause, and goes when the pointer leaves or clicks.
test.describe('entry tooltip', () => {

  test('hovering a journal entry shows it, until the pointer leaves or clicks', async ({ page }) => {
    await page.goto('/journal');
    const tip = page.locator('.entry-tooltip');
    const row = page.locator('#main-content tr.title', { hasText: 'Cafe Luna' });
    const description = row.locator('td').nth(1);
    // the row has no title of its own, so no browser tooltip shows as well
    await expect(row).not.toHaveAttribute('title');
    await hoverSettled(page, description);
    await expect(tip).toBeVisible();
    await expect(tip).toContainText('Cafe Luna');
    await expect(tip).toContainText('expenses:food:dining');
    await page.locator('#main-content h2').hover();
    await expect(tip).toBeHidden();
    // after a click it stays away while the pointer is still on the row
    await description.hover();
    await expect(tip).toBeVisible();
    await page.mouse.down();
    await page.mouse.up();
    await expect(tip).toBeHidden();
    await row.locator('td.date').hover();
    await page.waitForTimeout(800);
    await expect(tip).toBeHidden();
    expect(pageErrors).toEqual([]);
  });

  test('a register row shows its entry too, but over an account link the link\'s title applies', async ({ page }) => {
    await page.goto('/register?account=assets:bank:checking');
    const tip = page.locator('.entry-tooltip');
    const row = page.locator('#main-content tbody tr', { hasText: 'Cafe Luna' });
    await hoverSettled(page, row.locator('td.description'));
    await expect(tip).toBeVisible();
    await expect(tip).toContainText('Cafe Luna');
    const link = row.locator('td.account a');
    await expect(link).toHaveAttribute('title', 'expenses:food:dining');
    await link.hover();
    await expect(tip).toBeHidden();
    await page.waitForTimeout(800);
    await expect(tip).toBeHidden();
    expect(pageErrors).toEqual([]);
  });

});

test.describe('register chart', () => {

  // Its plots carry their date scales, from which hledger.js reads the dates
  // dragged across.
  test('dragging across a plot shows the register for those dates', async ({ page }) => {
    await page.goto('/register?account=assets:bank:checking');
    const before = await page.locator('#main-content tbody td.date').count();
    // from just before the second point to just after the next to last,
    // leaving out the first and the last, whatever other specs add
    const points = page.locator('.register-chart .hit');
    const n = await points.count();
    const a = await points.nth(1).boundingBox(), b = await points.nth(n - 2).boundingBox();
    const plot = await page.locator('.register-chart rect.plot').first().boundingBox();
    const y = plot.y + plot.height / 2;
    await page.mouse.move(a.x + a.width / 2 - 2, y);
    await page.mouse.down();
    await page.mouse.move(b.x + b.width / 2, y);
    await page.mouse.move(b.x + b.width / 2 + 2, y);
    await page.mouse.up();
    await expect(page).toHaveURL(/date(:|%3A)\d{4}-\d\d-\d\d\.\.\d{4}-\d\d-\d\d/);
    const [, from, to] = new URL(page.url()).searchParams.get('q').match(/date:(\S+)\.\.(\S+)/);
    const dates = (await page.locator('#main-content tbody td.date').allTextContents()).map(d => d.trim());
    expect(dates.length).toBeGreaterThan(0);
    expect(dates.length).toBeLessThan(before);
    expect(dates.filter(d => d < from || d >= to)).toEqual([]);
  });

  // With several commodities, its legend chooses the one charted, each on
  // its own scale. The entries are radio buttons' labels: clicks and the
  // arrow keys both work, with no javascript involved.
  test('the legend chooses the commodity charted', async ({ page }) => {
    await page.goto('/register?account=equity:opening');
    const shown = page.locator('.register-chart svg:visible');
    await expect(page.locator('.register-chart > label')).toHaveText(['no symbol', 'ZZZ']);
    await expect(shown).toHaveCount(1);
    await expect(shown).toHaveAttribute('aria-label', 'Period Total');
    await page.locator('.register-chart > label', { hasText: 'ZZZ' }).click();
    await expect(shown).toHaveAttribute('aria-label', 'Period Total: ZZZ');
    await page.keyboard.press('ArrowLeft');
    await expect(shown).toHaveAttribute('aria-label', 'Period Total');
  });

  // The server draws it as wide as the browser last measured the page's
  // main column, so that it fills the column without being scaled, its
  // text included. Full window mode widens the column, and the next page
  // draws the chart that wide.
  test('is drawn as wide as it is shown', async ({ page }) => {
    await page.goto('/journal');
    await page.goto('/register?account=assets:bank:checking');
    const chart = page.locator('.register-chart svg').first();
    const drawn = Number(await chart.getAttribute('width'));
    const shown = await chart.evaluate(svg => svg.getBoundingClientRect().width);
    expect(drawn).not.toBe(880);
    expect(Math.abs(shown - drawn)).toBeLessThan(1);
    await page.locator('body').press('f');
    await page.reload();
    const wide = Number(await chart.getAttribute('width'));
    const wideshown = await chart.evaluate(svg => svg.getBoundingClientRect().width);
    expect(wide).toBeGreaterThan(drawn);
    expect(Math.abs(wideshown - wide)).toBeLessThan(1);
  });
});
