// Browser tests for the light and dark color schemes (#2706).
//
// The pages follow the browser's prefers-color-scheme with css alone, except
// for the register chart, which flot draws on a canvas and hledger.js draws
// again when the scheme changes. These tests catch what a reader in the dark
// scheme would notice: something left light, text too dim to read, or a chart
// in the other scheme's colors.
//
// Run with: npx playwright test color-scheme  (see README.md)
const { test, expect } = require('@playwright/test');
const { watchPageErrors } = require('./helpers');

// In the page: the visible elements that stand out as light on a dark page,
// ie with a background or border brighter than mid-gray, or with text under
// the WCAG AA minimum of 4.5:1 contrast against what is behind it. Legend
// swatches take the chart's line colors, and bootstrap's close button is
// faint on purpose; both look the same in either scheme.
function lightOnDark() {
  const parse = s => {
    const [r, g, b, a = 1] = s.match(/[\d.]+/g).map(Number);
    return { r, g, b, a };
  };
  const over = (top, under) => ({
    r: top.r * top.a + under.r * (1 - top.a),
    g: top.g * top.a + under.g * (1 - top.a),
    b: top.b * top.a + under.b * (1 - top.a),
    a: 1,
  });
  const channel = v => (v /= 255) <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  const luminance = c => 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  const contrast = (a, b) => {
    const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
    return (hi + 0.05) / (lo + 0.05);
  };
  // What an element is drawn on: its background and its ancestors', down to
  // the first opaque one.
  const behind = el => {
    const layers = [];
    for (let e = el; e; e = e.parentElement) {
      const c = parse(getComputedStyle(e).backgroundColor);
      if (c.a > 0) layers.unshift(c);
      if (c.a === 1) break;
    }
    return layers.reduce((under, top) => over(top, under), { r: 255, g: 255, b: 255, a: 1 });
  };
  const found = [];
  for (const el of [document.body, ...document.body.querySelectorAll('*')]) {
    const style = getComputedStyle(el);
    if (!el.getClientRects().length || style.visibility !== 'visible') continue;
    if (el.closest('.legend-swatch, .close')) continue;
    const name = el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') +
      [...el.classList].map(c => '.' + c).join('');
    const bg = behind(el);
    if (parse(style.backgroundColor).a > 0 && luminance(bg) > 0.5)
      found.push(`${name}: light background`);
    const lightBorder = ['Top', 'Right', 'Bottom', 'Left'].some(side =>
      parseFloat(style[`border${side}Width`]) > 0 && style[`border${side}Style`] !== 'none' &&
      luminance(over(parse(style[`border${side}Color`]), bg)) > 0.5);
    if (lightBorder) found.push(`${name}: light border`);
    if ([...el.childNodes].some(n => n.nodeType === Node.TEXT_NODE && n.textContent.trim())) {
      let opacity = 1;
      for (let e = el; e; e = e.parentElement) opacity *= getComputedStyle(e).opacity;
      const fg = parse(style.color);
      const ratio = contrast(over({ ...fg, a: fg.a * opacity }, bg), bg);
      if (ratio < 4.5) found.push(`${name}: text contrast ${ratio.toFixed(2)}`);
    }
  }
  return found;
}

// The pages and dialogs checked, each opened from scratch.
const views = {
  'journal': page => page.goto('/journal'),
  'help dialog': async page => {
    await page.goto('/journal');
    await page.locator('body').press('h');
    await expect(page.locator('#helpmodal')).toBeVisible();
  },
  'add dialog': async page => {
    await page.goto('/journal');
    await page.locator('body').press('a');
    await expect(page.locator('#addmodal')).toBeVisible();
  },
  // a rejected submission shows the form, with its errors, on a page of its own
  'rejected add': async page => {
    await views['add dialog'](page);
    await page.locator('#addform input[name=date]').fill('nonsense');
    await page.locator('#addform input[name=account]').nth(0).fill('expenses:food:dining');
    await page.locator('#addform input[name=amount]').nth(0).fill('10.00');
    await page.locator('#addform input[name=account]').nth(1).fill('assets:bank:checking');
    await page.locator('#addform button[type=submit]').click();
    await expect(page.locator('#addform .has-error')).toBeVisible();
  },
  // hledger.js draws it only while the pointer rests on an entry
  'entry tooltip': async page => {
    await page.goto('/journal');
    await page.locator('#main-content tr.title td').nth(1).hover();
    await expect(page.locator('.entry-tooltip')).toBeVisible();
  },
  'register': page => page.goto('/register?q=inacct:assets:bank:checking'),
  'balance report': page => page.goto('/balance?period=monthly'),
  'balance report error': page => page.goto('/balance?period=nonsense'),
  'manage': page => page.goto('/manage'),
  'edit form': async page => {
    await page.goto('/manage');
    await page.locator('a.btn', { hasText: 'Edit' }).first().click();
    await expect(page.locator('textarea')).toBeVisible();
  },
};

test('in the dark scheme, nothing on any page is left light', async ({ page }) => {
  const errors = watchPageErrors(page);
  // The control: the check does find the light scheme's page light.
  await views['journal'](page);
  expect(await page.evaluate(lightOnDark)).toContain('body: light background');

  await page.emulateMedia({ colorScheme: 'dark' });
  const found = [];
  for (const [view, open] of Object.entries(views)) {
    await open(page);
    found.push(...(await page.evaluate(lightOnDark)).map(f => `${view}: ${f}`));
  }
  expect(found).toEqual([]);
  expect(errors).toEqual([]);
});

test('the register chart is drawn again for a change of scheme, and in the light one for printing', async ({ page }) => {
  const errors = watchPageErrors(page);
  await page.goto('/register?q=inacct:assets:bank:checking');
  const chart = () => page.locator('#register-chart canvas.flot-base').evaluate(c => c.toDataURL());
  const light = await chart();
  await page.emulateMedia({ colorScheme: 'dark' });
  await expect.poll(chart).not.toEqual(light);
  const dark = await chart();
  await page.emulateMedia({ media: 'print' });
  await expect.poll(chart).toEqual(light);
  await page.emulateMedia({ media: 'screen' });
  await expect.poll(chart).toEqual(dark);
  // each drawing replaces the legend rather than adding to it
  await expect(page.locator('#register-chart-label .legend-item')).toHaveCount(1);
  expect(errors).toEqual([]);
});
