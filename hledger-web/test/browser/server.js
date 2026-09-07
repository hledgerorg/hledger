// Starting hledger-web for the browser tests: used by global-setup.js for the
// main server, and by specs that need a server started differently.
const { spawn } = require('child_process');
const fs = require('fs');
const http = require('http');
const path = require('path');

// The hledger-web binary is located by, in order:
//   1. $HLEDGER_WEB (a command, may contain spaces, e.g. "stack exec -- hledger-web")
//   2. `stack exec -- hledger-web` if a stack project is detected three dirs up
//   3. plain `hledger-web` from $PATH
function serverCommand() {
  if (process.env.HLEDGER_WEB) return process.env.HLEDGER_WEB.split(/\s+/);
  const repoRoot = path.resolve(__dirname, '..', '..', '..');
  if (fs.existsSync(path.join(repoRoot, 'stack.yaml')))
    return ['stack', 'exec', '--', 'hledger-web'];
  return ['hledger-web'];
}

function waitForServer(url, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  return new Promise((resolve, reject) => {
    (function poll() {
      http.get(url + '/journal', res => {
        res.resume();
        res.statusCode < 500 ? resolve() : retry();
      }).on('error', retry);
      function retry() {
        if (Date.now() > deadline) return reject(new Error(`hledger-web did not start at ${url}`));
        setTimeout(poll, 300);
      }
    })();
  });
}

// Start hledger-web with the given arguments, detached, and resolve with the
// child process once it answers at url. `env` adds to or overrides the
// environment it runs in.
async function startServer(url, args, env) {
  const [cmd, ...cmdargs] = serverCommand();
  const child = spawn(cmd, [...cmdargs, ...args],
    { stdio: 'ignore', detached: true, env: { ...process.env, ...(env || {}) } });
  child.unref();
  try {
    await waitForServer(url, 60000);
  } catch (e) {
    try { process.kill(child.pid); } catch (_) { /* already gone */ }
    throw e;
  }
  return child;
}

module.exports = { serverCommand, waitForServer, startServer };
