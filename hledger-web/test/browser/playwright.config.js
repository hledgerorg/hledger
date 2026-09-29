// Playwright config for hledger-web browser tests.
// The web server is started per-run by global-setup.js (see there for
// how the hledger-web binary is located and the test journal prepared).
const { defineConfig } = require('@playwright/test');

module.exports = defineConfig({
  testDir: '.',
  globalSetup: './global-setup.js',
  globalTeardown: './global-teardown.js',
  timeout: 30000,
  // hledger-web mutates one shared journal file; keep tests serial.
  workers: 1,
  use: {
    baseURL: process.env.HLEDGER_WEB_URL || 'http://127.0.0.1:5099',
  },
  reporter: [['list']],
});
