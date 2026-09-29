// Helpers shared by the specs.
const { expect } = require('@playwright/test');

// Collect the browser's own reports of Content-Security-Policy violations on
// this page. The listener has to be installed before any page script runs,
// and the list has to live here rather than in the page, where a navigation
// would reset it. Returns the array, which fills in as reports arrive.
async function watchViolations(page) {
  const violations = [];
  await page.exposeFunction('__reportCspViolation', v => { violations.push(v); });
  await page.addInitScript(() => {
    document.addEventListener('securitypolicyviolation', e => {
      window.__reportCspViolation(e.violatedDirective + ' ' + e.blockedURI);
    });
  });
  return violations;
}

// Collect uncaught errors thrown by the page's scripts.
function watchPageErrors(page) {
  const errors = [];
  page.on('pageerror', err => errors.push(String(err)));
  return errors;
}

// Reports cross from the page asynchronously; let any in flight land first.
async function expectNoViolations(page, violations) {
  await page.waitForTimeout(100);
  expect(violations).toEqual([]);
}

module.exports = { watchViolations, watchPageErrors, expectNoViolations };
