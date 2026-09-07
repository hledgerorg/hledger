// Start hledger-web for the browser test run, on a scratch copy of fixture.journal
// (tests add and edit transactions, so the journal must be disposable).
// How the binary is located is described in server.js.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { startServer } = require('./server');

const PORT = process.env.HLEDGER_WEB_PORT || '5099';
const URL = process.env.HLEDGER_WEB_URL || `http://127.0.0.1:${PORT}`;

module.exports = async () => {
  const journal = path.join(os.tmpdir(), `hledger-web-browser-${process.pid}.journal`);
  fs.copyFileSync(path.join(__dirname, 'fixture.journal'), journal);
  process.env.BROWSER_JOURNAL = journal;

  const child = await startServer(URL, [
    '-f', journal, '--serve', '--host', '127.0.0.1', '--port', PORT, '--allow=edit',
  ]);
  fs.writeFileSync(path.join(os.tmpdir(), 'hledger-web-browser.pid'), String(child.pid));
};
