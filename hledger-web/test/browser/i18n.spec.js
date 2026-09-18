// Browser end-to-end tests for hledger-web's translations: the parts that
// only exist once javascript runs (the add form's placeholders on rows the
// page adds itself), and the language cookie surviving navigation.
//
// The browser is configured with a German locale, so it sends
// Accept-Language: de-DE,de and gets the built-in German catalog.
const { test, expect } = require('@playwright/test');

test.use({ locale: 'de-DE' });

test.describe('translations', () => {

  test('a German browser gets German pages', async ({ page }) => {
    await page.goto('/journal');
    await expect(page.locator('html')).toHaveAttribute('lang', 'de');
    await expect(page.locator('#addformlink')).toHaveText(/Buchung hinzufügen/);
    await expect(page).toHaveTitle('Journal - hledger-web');
    await expect(page.locator('#searchform input[name=q]')).toHaveAttribute('placeholder', 'Suchen');
    await page.goto('/register');
    await expect(page.locator('#main-content h2')).toHaveText(/alle Konten/);
    await expect(page).toHaveTitle('Buchungen - hledger-web');
  });

  test('rows the add form adds itself get translated placeholders', async ({ page }) => {
    await page.goto('/journal');
    await page.locator('body').press('a');
    await expect(page.locator('#addmodal')).toBeVisible();
    const accounts = page.locator('#addform input[name=account]');
    await expect(accounts.first()).toHaveAttribute('placeholder', 'Konto 1');
    await expect(accounts.nth(3)).toHaveAttribute('placeholder', 'Konto 4');
    // a keypress in the last amount field makes the page add a fifth row
    await page.locator('#addform input[name=amount]').nth(3).press('1');
    await expect(accounts).toHaveCount(5);
    await expect(accounts.nth(4)).toHaveAttribute('placeholder', 'Konto 5');
    await expect(page.locator('#addform input[name=amount]').nth(4)).toHaveAttribute('placeholder', 'Betrag 5');
  });

  test('an explicit _LANG choice overrides the browser language and is remembered', async ({ page }) => {
    await page.goto('/journal?_LANG=en');
    await expect(page.locator('html')).toHaveAttribute('lang', 'en');
    await expect(page.locator('#addformlink')).toHaveText(/Add a transaction/);
    // the choice was stored in a cookie, so a plain navigation keeps it
    await page.goto('/journal');
    await expect(page.locator('html')).toHaveAttribute('lang', 'en');
    await page.context().clearCookies();
    await page.goto('/journal');
    await expect(page.locator('html')).toHaveAttribute('lang', 'de');
  });

});
