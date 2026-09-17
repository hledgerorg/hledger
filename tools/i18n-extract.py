#!/usr/bin/env python3
"""Collect hledger's translatable strings into a gettext .pot template.

Usage:
  tools/i18n-extract.py [-o FILE] [DIR|FILE ...]
  tools/i18n-extract.py --pseudo [-o FILE] [DIR|FILE ...]
  tools/i18n-extract.py --check PO... [-- DIR|FILE ...]

By default the four packages' source trees are scanned. The recognized
forms, which must each be written on one line, are:

  Haskell:  tr T "TEXT"          trc T "CTX" "TEXT"     trf T "TEXT" ...
            trn T N "ONE" "MANY" i18n "TEXT"            i18nc "CTX" "TEXT"
            HMsg "TEXT"          HMsgc "CTX" "TEXT"     (hledger-web, also in hamlet's _{...})

A comment starting with "TRANSLATORS:" (after "--" in Haskell, "$#" in
hamlet) becomes the extracted comment of the matches on the lines directly
below it, up to the next blank line; so one comment above a function or a
list covers every string in it. Lines between "i18n-extract: off" and "i18n-extract: on" comments
are skipped. Entries whose text has {placeholders} get the
python-brace-format flag, which makes Poedit and Weblate check that a
translation keeps them.

--pseudo writes a pseudo-locale catalog instead, translating every entry
to "[TEXT]"; running hledger with it shows which output is still English.

--check compares the given .po files with the extracted entries and
reports entries that no longer exist in the source (which msgmerge would
mark obsolete) and how many are untranslated; it exits 1 if any are
stale.
"""

import argparse
import os
import re
import sys

DEFAULT_DIRS = ["hledger-lib", "hledger", "hledger-ui", "hledger-web"]
SKIP_DIRS = {".stack-work", "dist-newstyle", "node_modules", ".git"}

STR = r'"((?:[^"\\\n]|\\.)*)"'
EXPR = r'(?:[\w\'.]+|\((?:[^()"]|\([^()"]*\))*\))'
WS = r'\s+'

PATTERNS = [
    # (regex, kind) where kind names the captured groups
    (re.compile(r'\btr' + WS + EXPR + WS + STR), "msgid"),
    (re.compile(r'\btrc' + WS + EXPR + WS + STR + WS + STR), "ctx msgid"),
    (re.compile(r'\btrf' + WS + EXPR + WS + STR), "msgid"),
    (re.compile(r'\btrn' + WS + EXPR + WS + EXPR + WS + STR + WS + STR), "msgid plural"),
    (re.compile(r'\bi18n' + WS + STR), "msgid"),
    (re.compile(r'\bi18nc' + WS + STR + WS + STR), "ctx msgid"),
    # hledger-web's message types, in Haskell code and in hamlet's _{HMsg "..."}
    (re.compile(r'\bHMsg' + WS + STR), "msgid"),
    (re.compile(r'\bHMsgc' + WS + STR + WS + STR), "ctx msgid"),
]

COMMENT_LINE = re.compile(r'^\s*(?:--|\$#)\s?(.*)$')
COMMENT_ONLY = re.compile(r'^\s*(?:--|\$#)')
PLACEHOLDER = re.compile(r'\{[A-Za-z0-9_]+\}')

SIMPLE_ESCAPES = {
    'n': '\n', 't': '\t', 'r': '\r', '\\': '\\', '"': '"', "'": "'",
    'a': '\a', 'b': '\b', 'f': '\f', 'v': '\v', '0': '\0',
}


def unescape_haskell(s):
    """Decode the escapes of a Haskell string literal's body."""
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c != '\\':
            out.append(c)
            i += 1
            continue
        i += 1
        if i >= len(s):
            break
        c = s[i]
        if c in SIMPLE_ESCAPES:
            out.append(SIMPLE_ESCAPES[c])
            i += 1
        elif c == '&':  # empty escape
            i += 1
        elif c.isspace():  # string gap: backslash, whitespace, backslash
            while i < len(s) and s[i] != '\\':
                i += 1
            i += 1
        elif c == 'x':
            m = re.match(r'[0-9A-Fa-f]+', s[i + 1:])
            out.append(chr(int(m.group(0), 16)))
            i += 1 + len(m.group(0))
        elif c == 'o':
            m = re.match(r'[0-7]+', s[i + 1:])
            out.append(chr(int(m.group(0), 8)))
            i += 1 + len(m.group(0))
        elif c.isdigit():
            m = re.match(r'[0-9]+', s[i:])
            out.append(chr(int(m.group(0))))
            i += len(m.group(0))
        else:  # unknown escape: keep it
            out.append(c)
            i += 1
    return ''.join(out)


def po_string(s):
    """Render text as a PO string literal (possibly several lines)."""
    s = s.replace('\\', '\\\\').replace('"', '\\"').replace('\t', '\\t').replace('\r', '\\r')
    if '\n' not in s:
        return '"%s"' % s
    parts = s.split('\n')
    lines = ['""']
    for k, p in enumerate(parts):
        if k < len(parts) - 1:
            lines.append('"%s\\n"' % p)
        elif p:
            lines.append('"%s"' % p)
    return '\n'.join(lines)


class Entry:
    def __init__(self, ctx, msgid, plural):
        self.ctx = ctx
        self.msgid = msgid
        self.plural = plural
        self.refs = []
        self.comments = []


def translator_comment(lines, i):
    """The text of the TRANSLATORS: comment starting on line i, which may
    continue on the comment lines directly below it."""
    block = []
    j = i
    while j < len(lines):
        m = COMMENT_LINE.match(lines[j])
        if not m:
            break
        block.append(m.group(1).strip())
        j += 1
    text = ' '.join(block)
    k = text.find("TRANSLATORS:")
    return text[k + len("TRANSLATORS:"):].strip() if k >= 0 else None


def scan_file(path, entries, order):
    with open(path, encoding='utf-8') as f:
        lines = f.read().split('\n')
    active = True
    note = None      # the TRANSLATORS comment governing the current block, if any
    for i, line in enumerate(lines):
        if 'i18n-extract: off' in line:
            active = False
            continue
        if 'i18n-extract: on' in line:
            active = True
            continue
        if not line.strip():
            note = None
            continue
        if COMMENT_ONLY.match(line):
            if 'TRANSLATORS:' in line:
                note = translator_comment(lines, i)
            continue
        if not active:
            continue
        for rx, kind in PATTERNS:
            for m in rx.finditer(line):
                groups = [unescape_haskell(g) for g in m.groups()]
                names = kind.split()
                fields = dict(zip(names, groups))
                ctx = fields.get('ctx')
                msgid = fields['msgid']
                plural = fields.get('plural')
                key = (ctx, msgid)
                e = entries.get(key)
                if e is None:
                    e = entries[key] = Entry(ctx, msgid, plural)
                    order.append(key)
                elif plural and e.plural and e.plural != plural:
                    sys.stderr.write("%s:%d: warning: %r has two different plural forms\n" % (path, i + 1, msgid))
                elif plural and not e.plural:
                    e.plural = plural
                e.refs.append((path, i + 1))
                c = note
                if c and c not in e.comments:
                    e.comments.append(c)


def source_files(args):
    for a in args:
        if os.path.isfile(a):
            yield a
            continue
        for root, dirs, files in os.walk(a):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
            for fn in sorted(files):
                if fn.endswith('.hs') or fn.endswith('.hamlet'):
                    yield os.path.join(root, fn)


def extract(paths):
    entries = {}
    order = []
    for p in source_files(paths):
        scan_file(p, entries, order)
    return [entries[k] for k in order]


HEADER = '''# Translation template for hledger.
# This file is distributed under the same license as hledger.
#
#, fuzzy
msgid ""
msgstr ""
"Project-Id-Version: hledger\\n"
"Report-Msgid-Bugs-To: https://github.com/simonmichael/hledger/issues\\n"
"Language: \\n"
"MIME-Version: 1.0\\n"
"Content-Type: text/plain; charset=UTF-8\\n"
"Content-Transfer-Encoding: 8bit\\n"
"Plural-Forms: nplurals=INTEGER; plural=EXPRESSION;\\n"
'''

PSEUDO_HEADER = HEADER.replace('#, fuzzy\n', '').replace('"Language: \\n"', '"Language: xx\\n"') \
    .replace('nplurals=INTEGER; plural=EXPRESSION;', 'nplurals=2; plural=(n != 1);')


def render(entries, pseudo=False):
    out = [PSEUDO_HEADER if pseudo else HEADER]
    for e in entries:
        block = []
        for c in e.comments:
            block.append('#. ' + c)
        block.append('#: ' + ' '.join('%s:%d' % r for r in e.refs))
        if PLACEHOLDER.search(e.msgid) or (e.plural and PLACEHOLDER.search(e.plural)):
            block.append('#, python-brace-format')
        if e.ctx is not None:
            block.append('msgctxt ' + po_string(e.ctx))
        block.append('msgid ' + po_string(e.msgid))
        if e.plural:
            block.append('msgid_plural ' + po_string(e.plural))
            if pseudo:
                block.append('msgstr[0] ' + po_string('[' + e.msgid + ']'))
                block.append('msgstr[1] ' + po_string('[' + e.plural + ']'))
            else:
                block.append('msgstr[0] ""')
                block.append('msgstr[1] ""')
        else:
            block.append('msgstr ' + (po_string('[' + e.msgid + ']') if pseudo else '""'))
        out.append('\n'.join(block) + '\n')
    return '\n'.join(out)


def unescape_po(s):
    """Decode the C-style escapes of a PO string literal's body."""
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c != '\\' or i + 1 >= len(s):
            out.append(c)
            i += 1
            continue
        c = s[i + 1]
        i += 2
        if c in SIMPLE_ESCAPES:
            out.append(SIMPLE_ESCAPES[c])
        elif c == 'x':
            m = re.match(r'[0-9A-Fa-f]+', s[i:])
            out.append(chr(int(m.group(0), 16)))
            i += len(m.group(0))
        elif c in '01234567':
            m = re.match(r'[0-7]{1,3}', s[i - 1:])
            out.append(chr(int(m.group(0), 8)))
            i += len(m.group(0)) - 1
        else:
            out.append(c)
    return ''.join(out)


def read_po_keys(path):
    """The (ctx, msgid) keys in a PO file, each mapped to whether it is
    translated (a non-empty, non-fuzzy translation). A small reader, enough
    for catalogs written by hledger's tools, msgmerge or Poedit."""
    keys = {}
    cur = None
    field = None
    pending_fuzzy = False
    field_rx = re.compile(r'(msgctxt|msgid_plural|msgid|msgstr(?:\[\d+\])?)\s+(".*")$')

    def flush():
        nonlocal cur
        if cur and cur['msgid'] is not None:
            translated = any(s.strip() for s in cur['strs']) and not cur['fuzzy']
            keys[(cur['ctx'], cur['msgid'])] = translated
        cur = None

    with open(path, encoding='utf-8') as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            if line.startswith('#'):
                if line.startswith('#,') and 'fuzzy' in line:
                    pending_fuzzy = True
                if line.startswith('#~'):  # obsolete entry: ignore it
                    field = None
                continue
            m = field_rx.match(line)
            if m:
                name, val = m.group(1), m.group(2)[1:-1]
                starts = name == 'msgctxt' or (name == 'msgid' and (cur is None or cur['msgid'] is not None))
                if starts:
                    flush()
                    cur = {'ctx': None, 'msgid': None, 'strs': [], 'fuzzy': pending_fuzzy}
                    pending_fuzzy = False
                if cur is None:
                    continue
                field = name
                if name == 'msgctxt':
                    cur['ctx'] = ''
                elif name == 'msgid':
                    cur['msgid'] = ''
                elif name.startswith('msgstr'):
                    cur['strs'].append('')
            elif line.startswith('"') and field and cur is not None:
                val = line[1:-1]
            else:
                continue
            val = unescape_po(val)
            if field == 'msgctxt':
                cur['ctx'] += val
            elif field == 'msgid':
                cur['msgid'] += val
            elif field.startswith('msgstr'):
                cur['strs'][-1] += val
        flush()
    keys.pop((None, ''), None)  # the header
    return keys


def check(po_paths, source_paths):
    wanted = {(e.ctx, e.msgid) for e in extract(source_paths)}
    status = 0
    for po in po_paths:
        have = read_po_keys(po)
        by_key = lambda k: (k[0] or '', k[1])
        stale = sorted((k for k in have if k not in wanted), key=by_key)
        missing = sorted((k for k in wanted if k not in have), key=by_key)
        untranslated = sorted((k for k, ok in have.items() if not ok and k in wanted), key=by_key)
        print("%s: %d entries, %d untranslated, %d missing from catalog, %d stale" %
              (po, len(have), len(untranslated), len(missing), len(stale)))
        for k in stale:
            print("  stale: %s" % format_key(k))
            status = 1
        for k in missing:
            print("  missing: %s" % format_key(k))
    return status


def format_key(k):
    ctx, msgid = k
    return ('[%s] ' % ctx if ctx is not None else '') + repr(msgid)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('-o', '--output', help='write here instead of stdout')
    ap.add_argument('--pseudo', action='store_true', help='write a pseudo-locale catalog (xx) instead of a template')
    ap.add_argument('--check', nargs='+', metavar='PO', help='check these catalogs against the sources')
    ap.add_argument('paths', nargs='*', help='directories or files to scan (default: the four packages)')
    args = ap.parse_args()
    paths = args.paths or DEFAULT_DIRS
    if args.check:
        sys.exit(check(args.check, paths))
    text = render(extract(paths), pseudo=args.pseudo)
    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(text)
    else:
        sys.stdout.write(text)


if __name__ == '__main__':
    main()
