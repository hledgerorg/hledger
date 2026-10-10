#!/usr/bin/env python3
"""Show the text of hledger-web's pages in a language, for checking a translation.

Usage:
  tools/i18n-web.py LANG [JOURNAL] [--port N]

Starts hledger-web on JOURNAL (default: examples/sample.journal), requests
its main pages as a browser preferring LANG would (Accept-Language: LANG),
prints the visible text and tooltips of each page, then stops hledger-web.
Each string is printed once, under the first page it appears on, so later
pages show only what is new. Some strings are journal data (account names,
descriptions), which are never translated.

The pages include the file management pages, and the add form after a
deliberately invalid submission, so that its validation messages appear.

Your own catalogs in hledger's config directory (eg
~/.config/hledger/locale/LANG.po) are used, so you can check a translation
in progress. hledger-web reads catalogs when it starts, and this starts it
afresh each time.

To find text that is still in English: `just i18n-pseudo` writes a
pseudo-locale catalog that brackets every translated string; then
`just i18n-web xx` shows any text without brackets.

hledger-web is run with `stack exec -- hledger-web` when stack is installed,
otherwise as `hledger-web` from PATH; set HLEDGER_WEB to another command to
override that.
"""

import argparse
import html.parser
import json
import os
import shlex
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class PageText(html.parser.HTMLParser):
    """Collects a page's visible text, its tooltips and other user-facing
    attributes, its html lang attribute, and its links."""

    # code: search syntax and keys, never translated; textarea: the journal being edited
    SKIP = {'script', 'style', 'code', 'textarea'}
    ATTRS = ('title', 'placeholder', 'aria-label', 'alt')

    def __init__(self):
        super().__init__()
        self.strings = []
        self.links = []
        self.lang = None
        self.skipping = 0

    def add(self, s):
        s = ' '.join(s.split())
        if any(c.isalpha() for c in s):
            self.strings.append(s)

    def handle_starttag(self, tag, attrs):
        a = {k: v or '' for k, v in attrs}
        if tag == 'html':
            self.lang = a.get('lang')
        if tag in self.SKIP:
            self.skipping += 1
        if tag == 'a' and a.get('href'):
            self.links.append(a['href'])
        for k in self.ATTRS:
            self.add(a.get(k, ''))
        for k, v in a.items():
            if k.startswith('data-') and k.endswith('-placeholder'):
                self.add(v)
        if tag == 'input' and a.get('type') in ('submit', 'button'):
            self.add(a.get('value', ''))

    def handle_endtag(self, tag):
        if tag in self.SKIP and self.skipping:
            self.skipping -= 1

    def handle_data(self, data):
        if not self.skipping:
            self.add(data)


def hledger_web_command():
    if os.environ.get('HLEDGER_WEB'):
        return shlex.split(os.environ['HLEDGER_WEB'])
    if shutil.which('stack') and os.path.exists(os.path.join(REPO, 'stack.yaml')):
        return ['stack', 'exec', '--', 'hledger-web']
    return ['hledger-web']


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('lang', help='a language tag, as a browser would send it, eg es or pt-BR')
    ap.add_argument('journal', nargs='?', default=os.path.join(REPO, 'examples', 'sample.journal'))
    ap.add_argument('--port', type=int, default=5917)
    args = ap.parse_args()

    base = 'http://127.0.0.1:%d' % args.port
    cmd = hledger_web_command() + ['--serve', '--port', str(args.port), '--allow=edit',
                                   '-f', os.path.abspath(args.journal)]
    # its own process group, so that stopping it also stops a stack wrapper's child
    server = subprocess.Popen(cmd, cwd=REPO, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                              start_new_session=True)
    try:
        wait_until_serving(server, base)
        show_pages(base, args.lang)
    finally:
        try:
            os.killpg(server.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        server.wait()


def wait_until_serving(server, base):
    for _ in range(120):
        if server.poll() is not None:
            sys.exit("hledger-web exited:\n" + server.stderr.read().decode(errors='replace'))
        try:
            urllib.request.urlopen(base + '/version', timeout=2).read()
            return
        except (urllib.error.URLError, ConnectionError, TimeoutError):
            time.sleep(0.5)
    sys.exit("hledger-web did not start serving within a minute")


def fetch(base, path, lang, data=None):
    req = urllib.request.Request(base + path, data=data, headers={'Accept-Language': lang})
    try:
        body = urllib.request.urlopen(req, timeout=30).read()
    except urllib.error.HTTPError as e:  # eg a form re-shown with a 400 status
        body = e.read()
    p = PageText()
    p.feed(body.decode('utf-8', errors='replace'))
    return p


def show_pages(base, lang):
    accounts = json.loads(urllib.request.urlopen(base + '/accountnames', timeout=30).read())
    account = next((a for a in accounts if ':' in a), accounts[0] if accounts else '')
    pages = [
        ('journal, with the help dialog and add form', '/journal'),
        ('register', '/register?' + urllib.parse.urlencode({'q': 'inacct:' + account})),
        ('balance', '/balance'),
        ('balance, monthly', '/balance?period=monthly'),
        ('balance sheet', '/balancesheet'),
        ('balance sheet with equity', '/balancesheetequity'),
        ('income statement', '/incomestatement'),
        ('cashflow statement', '/cashflow'),
        ('file management', '/manage'),
    ]
    seen = set()
    first = True
    for name, path in pages:
        p = fetch(base, path, lang)
        if first:
            print("Page language: %s (requested: %s)" % (p.lang, lang))
            if p.lang and p.lang.split('-')[0].lower() != lang.replace('_', '-').split('-')[0].lower():
                print("  hledger-web has no catalog for %s, so these pages are in %s." % (lang, p.lang))
            first = False
        show(name, path, p, seen)
        if path == '/manage':
            # the file pages' links are relative
            paths = [urllib.parse.urlsplit(urllib.parse.urljoin(base + path, l)) for l in p.links]
            for prefix in ('/edit/', '/upload/'):
                link = next((u.path for u in paths if u.path.startswith(prefix)), None)
                if link:
                    show(prefix.strip('/') + ' page', link, fetch(base, link, lang), seen)
    # two postings with no amounts, and a bad date, so the form shows its error messages
    form = urllib.parse.urlencode([('_formid', 'identify-add'), ('date', 'not a date'), ('description', 'x'),
                                   ('account', 'a'), ('amount', ''), ('account', 'b'), ('amount', '')]).encode()
    show('add form, after an invalid submission', '/add (POST)', fetch(base, '/add', lang, form), seen)


def show(name, path, page, seen):
    new = [s for s in dict.fromkeys(page.strings) if s not in seen]
    seen.update(new)
    print("\n== %s: %s" % (name, path))
    for s in new:
        print("  " + s)
    if not new:
        print("  (nothing new)")


if __name__ == '__main__':
    main()
