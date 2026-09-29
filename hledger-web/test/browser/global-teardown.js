const fs = require('fs');
const os = require('os');
const path = require('path');

module.exports = async () => {
  const pidFile = path.join(os.tmpdir(), 'hledger-web-browser.pid');
  try {
    const pid = parseInt(fs.readFileSync(pidFile, 'utf8'), 10);
    if (pid) process.kill(pid);
    fs.unlinkSync(pidFile);
  } catch (e) { /* already gone */ }
  try {
    if (process.env.BROWSER_JOURNAL) fs.unlinkSync(process.env.BROWSER_JOURNAL);
  } catch (e) { /* already gone */ }
};
