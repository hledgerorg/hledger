#!/usr/bin/env python3
"""Collect hledger's translatable strings into a gettext .pot template.

Usage:
  tools/i18n-extract.py [-o FILE] [--reorder] [DIR|FILE ...]
  tools/i18n-extract.py --pseudo [-o FILE] [DIR|FILE ...]
  tools/i18n-extract.py --check PO... [-- DIR|FILE ...]

By default the four packages' source trees are scanned. The recognized
forms, which must each be written on one line, are:

  Haskell:  tr T "TEXT"          trc T "CTX" "TEXT"     trf T "TEXT" ...
            trn T N "ONE" "MANY" i18n "TEXT"            i18nc "CTX" "TEXT"
            (T, the Translations argument, may be omitted when the module binds
            a local helper such as `tr = I18n.tr translations_`)
            HMsg "TEXT"          HMsgc "CTX" "TEXT"     (hledger-web, also in hamlet's _{...})

A comment starting with "TRANSLATORS:" (after "--" in Haskell, "$#" in
hamlet) becomes the extracted comment of the matches on the lines directly
below it, up to the next blank line; so one comment above a function or a
list covers every string in it. Lines between "i18n-extract: off" and "i18n-extract: on" comments
are skipped. Entries whose text has {placeholders} get the
python-brace-format flag, which makes Poedit and Weblate check that a
translation keeps them. Each entry's #: line names the source files the
text appears in, without line numbers (like xgettext --add-location=file),
so that the template changes only when strings are added, removed, or move
to another file, and branches that regenerate it rarely conflict.

Entries keep their order in the existing template (FILE, or else
hledger-lib/locale/hledger.pot), and a new entry goes after the entry
that precedes it in the sources. So moving code between files changes
only the #: lines, not the order of the template and of the catalogs,
which msgmerge orders like the template. --reorder ignores the existing
order and writes the entries in source order. Either way they are grouped
by program (the command line's, with hledger-lib's, then hledger-ui's and
hledger-web's), and the first entry of each group gets an extracted comment
saying which group it starts.

--pseudo writes a pseudo-locale catalog instead, translating every entry
to "[TEXT]"; running hledger with it shows which output is still English.

--check compares the given .po files with the extracted entries and
reports entries that no longer exist in the source (which msgmerge would
mark obsolete) and how many are untranslated. For catalogs in
hledger-lib/locale, it also checks that each is built in (registered in
package.yaml and I18n.hs). A .pot file given to --check must be exactly
what extraction writes now, so a template that was not regenerated after
a string changed is caught. It exits 1 if any entries are stale, any
catalog is not built in, or the template is out of date.
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

# The Translations argument is optional: renderers commonly bind a local
# `tr = I18n.tr translations_` and then write `tr "text"`.
TRS = r'(?:' + EXPR + WS + r')?'

PATTERNS = [
    # (regex, kind) where kind names the captured groups
    (re.compile(r'\btr' + WS + TRS + STR), "msgid"),
    (re.compile(r'\btrc' + WS + TRS + STR + WS + STR), "ctx msgid"),
    (re.compile(r'\btrf' + WS + TRS + STR), "msgid"),
    (re.compile(r'\btrn' + WS + TRS + EXPR + WS + STR + WS + STR), "msgid plural"),
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
                if path not in e.refs:
                    e.refs.append(path)
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


def keep_order(entries, previous):
    """Order entries (given in source order) as in previous, a list of an
    existing template's keys; each new entry goes after the entry that
    precedes it in source order, or first if none does."""
    by_key_ = {(e.ctx, e.msgid): e for e in entries}
    keys = [k for k in previous if k in by_key_]
    placed = set(keys)
    before = None
    for e in entries:
        k = (e.ctx, e.msgid)
        if k not in placed:
            keys.insert(keys.index(before) + 1 if before else 0, k)
            placed.add(k)
        before = k
    return [by_key_[k] for k in keys]


def template_keys(path):
    """The keys of the template at path, in order, or [] if there is none."""
    return list(read_po_keys(path)) if path and os.path.isfile(path) else []


HEADER = '''# Translation template for hledger.
# This file is distributed under the same license as hledger.
# "Key term" marks an entry whose mistranslation would mislead about money or data:
# use your country's standard accounting term, and review these first.
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


# Notes heading each group of entries, by the package whose sources they
# first appear in. hledger-lib's go with the command line's, though some,
# like month names, are shown by the other programs too.
GROUP_NOTES = {
    'hledger': '---- Entries for the hledger command line (some, like month names, '
               'also shown by hledger-ui and hledger-web). ----',
    'hledger-ui': '---- Entries for hledger-ui. ----',
    'hledger-web': '---- Entries for hledger-web. ----',
}


def group_of(e):
    package = e.refs[0].split('/')[0]
    return 'hledger' if package == 'hledger-lib' else package


# Entries whose mistranslation would mislead about money or data, not just
# read oddly: statement and section names, what a total means, stock vs
# flow, valuation, gains, status, posting kinds, and destructive actions;
# one representative of each concept. Each gets KEY_TERM_NOTE, so translators take care with them and
# reviewers check them first. As (msgctxt, msgid); --check fails if one no
# longer exists.
KEY_TERM_NOTE = 'Key term'
# Defines the mark, once, in a note on the first entry (and in the template's header comment),
# so that every catalog carries the definition without repeating it on each key term.
KEY_TERM_DEF = ('"Key term" marks an entry whose mistranslation would mislead about money or data: '
                'use your country\'s standard accounting term (eg from official IFRS translations), '
                'and review these first.')
KEY_TERMS = {(None, m) for m in [
    # one representative of each concept; translators will translate its variants the same way
    # statements and their sections
    "Balance Sheet", "Balance Sheet With Equity", "Income Statement", "Cashflow Statement",
    "Assets", "Liabilities", "Equity", "Revenues", "Expenses", "Net:",
    # stock vs flow
    "Balance changes", "Ending balances",
    # valuation
    "Cost", "Value", "At cost", "At market value",
    # gains
    "Unrealised gain", "Gain",
    # status, and kinds of posting
    "Cleared", "Pending", "Unmarked", "Real", "Virtual",
    # destructive actions
    "Are you sure? This will overwrite your journal!",
]}


def render(entries, pseudo=False):
    out = [PSEUDO_HEADER if pseudo else HEADER]
    group = None
    for e in entries:
        block = []
        if group_of(e) != group:
            first = group is None
            group = group_of(e)
            if group in GROUP_NOTES:
                block.append('#. ' + GROUP_NOTES[group])
            if first:
                block.append('#. ' + KEY_TERM_DEF)
        if (e.ctx, e.msgid) in KEY_TERMS:
            block.append('#. ' + KEY_TERM_NOTE)
        for c in e.comments:
            block.append('#. ' + c)
        block.append('#: ' + ' '.join(e.refs))
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


def by_key(k):
    return (k[0] or '', k[1])


def check(po_paths, source_paths):
    entries = extract(source_paths)
    wanted = {(e.ctx, e.msgid) for e in entries}
    status = 0
    for k in sorted(KEY_TERMS - wanted, key=by_key):
        print("KEY_TERMS in tools/i18n-extract.py lists an entry that no longer exists: %r" % (k,))
        status = 1
    for po in po_paths:
        if po.endswith('.pot'):
            status = max(status, check_template(po, entries, wanted))
            continue
        have = read_po_keys(po)
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
        for problem in registration_problems(po):
            print("  " + problem)
            status = 1
    return status


def check_template(pot, entries, wanted):
    """Check that a template is exactly what extraction would write now,
    reporting the entries it lacks or should no longer have. Returns 1 if
    it is out of date."""
    with open(pot, encoding='utf-8') as f:
        if f.read() == render(keep_order(entries, template_keys(pot))):
            print("%s: up to date" % pot)
            return 0
    have = set(read_po_keys(pot))
    missing = sorted(wanted - have, key=by_key)
    stale = sorted(have - wanted, key=by_key)
    print("%s: out of date with the sources, run just i18n-pot "
          "(%d entries missing, %d stale)" % (pot, len(missing), len(stale)))
    for k in missing:
        print("  missing: %s" % format_key(k))
    for k in stale:
        print("  stale: %s" % format_key(k))
    if not missing and not stale:
        print("  (the entries are the same, but their comments or source references changed)")
    return 1


REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALE_DIR = os.path.join(REPO, 'hledger-lib', 'locale')
TEMPLATE = os.path.join(LOCALE_DIR, 'hledger.pot')


def registration_problems(po):
    """For a catalog in hledger-lib/locale, the ways it is not built in:
    each must be listed, by its file name, in package.yaml's
    extra-source-files and in builtinCatalogSources in I18n.hs, with a tag
    equal to its file name. (The unit tests check that the tag is normalized.)"""
    if os.path.dirname(os.path.abspath(po)) != LOCALE_DIR:
        return []
    name = os.path.basename(po)
    tag = name[:-len('.po')]
    with open(os.path.join(REPO, 'hledger-lib', 'package.yaml'), encoding='utf-8') as f:
        packageyaml = f.read()
    with open(os.path.join(REPO, 'hledger-lib', 'Hledger', 'Utils', 'I18n.hs'), encoding='utf-8') as f:
        i18nhs = f.read()
    problems = []
    if not re.search(r'^- locale/' + re.escape(name) + r'\s*$', packageyaml, re.M):
        problems.append("not built in: add - locale/%s to extra-source-files in hledger-lib/package.yaml" % name)
    if not re.search(r'\("' + re.escape(tag) + r'",\s*\$\(embedFileRelativeBytes "locale/' + re.escape(name) + r'"\)\)', i18nhs):
        problems.append('not built in: add ("%s", $(embedFileRelativeBytes "locale/%s")) to builtinCatalogSources in hledger-lib/Hledger/Utils/I18n.hs' % (tag, name))
    return problems


def format_key(k):
    ctx, msgid = k
    return ('[%s] ' % ctx if ctx is not None else '') + repr(msgid)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('-o', '--output', help='write here instead of stdout')
    ap.add_argument('--pseudo', action='store_true', help='write a pseudo-locale catalog (xx) instead of a template')
    ap.add_argument('--check', nargs='+', metavar='PO', help='check these catalogs against the sources')
    ap.add_argument('--reorder', action='store_true', help="write entries in source order, not the existing template's order")
    ap.add_argument('paths', nargs='*', help='directories or files to scan (default: the four packages)')
    args = ap.parse_args()
    paths = args.paths or DEFAULT_DIRS
    if args.check:
        sys.exit(check(args.check, paths))
    entries = extract(paths)
    if not args.reorder:
        previous = args.output if args.output and os.path.isfile(args.output) and not args.pseudo else TEMPLATE
        entries = keep_order(entries, template_keys(previous))
    text = render(entries, pseudo=args.pseudo)
    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(text)
    else:
        sys.stdout.write(text)


if __name__ == '__main__':
    main()
