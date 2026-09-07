// Security regression tests for the hledger-web UI.
//
// hledger-web is meant to be run locally, but journal data is not always
// trusted (imported CSV, shared files), and the browser is a hostile place to
// interpolate text. Yesod escapes template output by default; these tests
// exist so that a future refactor cannot quietly opt out of it.
//
// Run with: npx playwright test security  (see README.md)
const { test, expect } = require('@playwright/test');

// A payload that executes if it is ever inserted as markup rather than text.
// Tests assert window.__xss stays undefined and the text is shown literally.
const PAYLOAD = '<img src=x onerror="window.__xss=1">';

let pageErrors;
test.beforeEach(({ page }) => {
  pageErrors = [];
  page.on('pageerror', err => pageErrors.push(String(err)));
});

async function xssFired(page) {
  return page.evaluate(() => window.__xss !== undefined);
}

test.describe('journal data is rendered as text, not markup', () => {

  // fixture.journal carries the payload in a description, an account name and
  // a comment, so every view that renders them is covered.
  test('the journal view escapes a payload in a description', async ({ page }) => {
    await page.goto('/journal');
    expect(await xssFired(page)).toBe(false);
    await expect(page.locator('#main-content')).toContainText(PAYLOAD);
    expect(await page.locator('#main-content img[src="x"]').count()).toBe(0);
  });

  test('the register view escapes a payload in a description', async ({ page }) => {
    await page.goto('/register?q=inacct:expenses:food:dining');
    expect(await xssFired(page)).toBe(false);
    expect(await page.locator('#main-content img[src="x"]').count()).toBe(0);
  });

  test('the sidebar escapes a payload in an account name', async ({ page }) => {
    await page.goto('/journal');
    await expect(page.locator('#sidebar-menu')).toContainText('xss<script>');
    expect(await page.locator('#sidebar-menu script').count()).toBe(0);
    expect(await xssFired(page)).toBe(false);
  });

  // Completion data is <option> markup, so the payload must arrive as an
  // attribute value and nothing else: no element created, nothing executed.
  test('autocomplete options carry a payload inertly', async ({ page }) => {
    await page.goto('/journal');
    await page.locator('body').press('a');
    await expect(page.locator('#addmodal')).toBeVisible();
    expect(pageErrors).toEqual([]);
    expect(await xssFired(page)).toBe(false);
    // the payload is offered as a completion, as a value rather than markup
    expect(await page.locator('#descriptionnames option[value*="onerror"]').count())
      .toBeGreaterThan(0);
    expect(await page.locator('#descriptionnames img, #accountnames img').count()).toBe(0);
    expect(await page.locator('#descriptionnames script, #accountnames script').count()).toBe(0);
    expect(await xssFired(page)).toBe(false);
  });

  test('a payload typed into the search box is not executed', async ({ page }) => {
    await page.goto('/journal');
    await page.locator('#searchform input[name=q]').fill(PAYLOAD);
    await page.locator('#searchform input[name=q]').press('Enter');
    expect(await xssFired(page)).toBe(false);
    expect(await page.locator('#main-content img[src="x"]').count()).toBe(0);
  });

  // The upload form names the file you picked. A filename is text the user
  // supplies and can contain markup, so it is shown rather than parsed.
  test('the upload form names the chosen file as text', async ({ page }) => {
    const fs = require('fs'), os = require('os'), path = require('path');
    const name = 'x<img src=x onerror="window.__upxss=1">.journal';
    const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hw-upload-')), name);
    fs.writeFileSync(file, '2025-01-01 x\n    a  1\n    b\n');

    await page.goto('/manage');
    await page.locator('a.btn', { hasText: 'Upload' }).first().click();
    await page.locator('#file').setInputFiles(file);

    await expect(page.locator('#file-info')).toHaveText(name);
    expect(await page.locator('#file-info img').count()).toBe(0);
    expect(await xssFired(page)).toBe(false);
    expect(await page.evaluate(() => window.__upxss)).toBeUndefined();
  });

  test('the edit form shows journal text as text', async ({ page }) => {
    await page.goto('/manage');
    await page.locator('a.btn', { hasText: 'Edit' }).first().click();
    expect(await page.locator('textarea').inputValue()).toContain(PAYLOAD);
    expect(await xssFired(page)).toBe(false);
  });

});

// The Content-Security-Policy (#2703): scripts and styles from our origin
// only, and no inline script without the response's nonce. A violation is
// not a page error, so these tests listen for the browser's own report of
// one, installed before any page script runs.
test.describe('the content security policy', () => {

  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => {
      window.__cspViolations = [];
      document.addEventListener('securitypolicyviolation', e => {
        window.__cspViolations.push(e.violatedDirective + ' ' + e.blockedURI);
      });
    });
  });

  const violations = page => page.evaluate(() => window.__cspViolations);

  // The pixel position of a point on the register chart, so the mouse can
  // reach what flot drew on its canvas.
  async function chartPoint(page, series, index) {
    return page.evaluate(([s, i]) => {
      const $chart = $('#register-chart'), plot = $chart.data('plot');
      const rect = $chart[0].getBoundingClientRect();
      const p = plot.getData()[s].data[i], o = plot.pointOffset({ x: p[0], y: p[1] });
      return { x: rect.left + o.left, y: rect.top + o.top, rect };
    }, [series, index]);
  }

  test('is sent with every page, with a fresh nonce on its inline scripts', async ({ page }) => {
    const first = await page.goto('/journal');
    const csp = first.headers()['content-security-policy'];
    expect(csp).toMatch(/^default-src 'self'; script-src 'self' 'nonce-[A-Za-z0-9+/]{22}=='/);
    const nonce = csp.match(/'nonce-([^']+)'/)[1];
    // every inline script carries it; the rest load from our origin
    const inline = await page.evaluate(() => Array.from(document.scripts).filter(s => !s.src).map(s => s.nonce));
    expect(inline.length).toBeGreaterThan(0);
    expect(inline.every(n => n === nonce)).toBe(true);
    const second = await page.goto('/journal');
    expect(second.headers()['content-security-policy']).not.toContain(nonce);
    const notFound = await page.goto('/nosuchpage');
    expect(notFound.status()).toBe(404);
    expect(notFound.headers()['content-security-policy']).toContain("script-src 'self' 'nonce-");
  });

  test('is not violated by any page or interaction', async ({ page }) => {
    await page.goto('/journal');
    await page.locator('body').press('h');
    await expect(page.locator('#helpmodal')).toBeVisible();
    await page.locator('body').press('Escape');
    await page.locator('body').press('a');
    await expect(page.locator('#addmodal')).toBeVisible();
    // a rejected submission re-renders the form on a page of its own
    await page.locator('#addform input[name=description]').fill('CspUnbalanced');
    await page.locator('#addform input[name=account]').nth(0).fill('expenses:food:dining');
    await page.locator('#addform input[name=amount]').nth(0).fill('10.00');
    await page.locator('#addform input[name=account]').nth(1).fill('assets:bank:checking');
    await page.locator('#addform input[name=amount]').nth(1).fill('99.00');
    await page.locator('#addform button[type=submit]').click();
    await expect(page.locator('#message')).toBeVisible();
    expect(await violations(page)).toEqual([]);

    // the register chart: flot draws with the CSSOM, which the policy allows
    await page.goto('/register?q=inacct:assets:bank:checking');
    const point = await chartPoint(page, 1, 0);
    await page.mouse.move(point.x - 30, point.y - 30);
    await page.mouse.move(point.x, point.y);
    await expect(page.locator('#flotTip')).toBeVisible();
    await page.mouse.click(point.x, point.y);
    const { rect } = point, y = rect.top + rect.height / 2;
    await page.mouse.move(rect.left + rect.width * 0.3, y);
    await page.mouse.down();
    await page.mouse.move(rect.left + rect.width * 0.4, y);
    await page.mouse.move(rect.left + rect.width * 0.7, y);
    await page.mouse.up();
    await expect(page).toHaveURL(/date:/);
    expect(await violations(page)).toEqual([]);

    for (const url of ['/manage', '/nosuchpage']) {
      await page.goto(url);
      expect(await violations(page)).toEqual([]);
    }
    await page.goto('/manage');
    await page.locator('a.btn', { hasText: 'Edit' }).first().click();
    await expect(page.locator('textarea')).toBeVisible();
    expect(await violations(page)).toEqual([]);
    await page.goto('/manage');
    await page.locator('a.btn', { hasText: 'Upload' }).first().click();
    await expect(page.locator('#file')).toBeAttached();
    expect(await violations(page)).toEqual([]);
    expect(pageErrors).toEqual([]);
  });

  // The control: without this, the tests above could pass because the policy
  // is absent or ignored, rather than because nothing violates it.
  test('blocks an inline script that lacks the nonce', async ({ page }) => {
    await page.goto('/journal');
    const ran = await page.evaluate(async () => {
      window.__canary = false;
      const s = document.createElement('script');
      s.textContent = 'window.__canary = true;';
      document.body.appendChild(s);
      await new Promise(resolve => setTimeout(resolve, 100));
      return window.__canary;
    });
    expect(ran).toBe(false);
    expect(await violations(page)).toEqual(['script-src-elem inline']);
  });

});
