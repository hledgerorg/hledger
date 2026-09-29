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
// child process and the base url from its startup banner, once it answers
// there. With --port 0 that url carries the port the OS chose. `env` adds to
// or overrides the environment it runs in.
async function startServer(args, env) {
  const [cmd, ...cmdargs] = serverCommand();
  const child = spawn(cmd, [...cmdargs, ...args],
    { stdio: ['ignore', 'pipe', 'pipe'], detached: true, env: { ...process.env, ...(env || {}) } });
  child.unref();
  const url = await new Promise((resolve, reject) => {
    let out = '';
    const done = (fn) => (arg) => {
      clearTimeout(timer);
      child.stdout.off('data', onData); child.stderr.off('data', onData); child.off('exit', onExit);
      fn(arg);
    };
    const succeed = done(resolve), fail = done(reject);
    const timer = setTimeout(() => fail(new Error('hledger-web did not report its base url:\n' + out)), 60000);
    const onData = chunk => {
      out += chunk;
      const m = out.match(/^with base url (\S+)\n/m);
      if (m) succeed(m[1]);
    };
    const onExit = code => fail(new Error(`hledger-web exited with ${code}:\n` + out));
    child.stdout.on('data', onData); child.stderr.on('data', onData); child.on('exit', onExit);
  });
  // keep draining its output, or it would block once the pipes fill up
  child.stdout.resume(); child.stderr.resume();
  try {
    await waitForServer(url, 60000);
  } catch (e) {
    try { process.kill(child.pid); } catch (_) { /* already gone */ }
    throw e;
  }
  return { child, url };
}

module.exports = { startServer };
