% hledger-web(1)
% _author_
% _monthyear_

_notinfo_({{
# NAME
}})

hledger-web - web interface and API for `hledger`, a robust, friendly plain text accounting app.

_notinfo_({{
# SYNOPSIS
}})

`hledger-web [OPTS] [QUERY]`\
or\
`hledger web [OPTS] [QUERY]`

_notinfo_({{
# DESCRIPTION
}})

This manual is for hledger's web interface, version _version_.
See also the hledger manual for common concepts and file formats.

_hledgerdescription_

_web_({{
<div class="screenshots-right">
<a href="/images/hledger-web/normal/register.png" class="highslide" onclick="return hs.expand(this)"><img src="/images/hledger-web/normal/register.png" title="Account register view with accounts sidebar" height="180" /></a>
<a href="/images/hledger-web/normal/journal.png" class="highslide" onclick="return hs.expand(this)"><img src="/images/hledger-web/normal/journal.png" title="Journal view" height="180" /></a>
<a href="/images/hledger-web/normal/help.png" class="highslide" onclick="return hs.expand(this)"><img src="/images/hledger-web/normal/help.png" title="Help dialog" height="180" /></a>
<a href="/images/hledger-web/normal/add.png" class="highslide" onclick="return hs.expand(this)"><img src="/images/hledger-web/normal/add.png" title="Add form" height="180" /></a>
</div>
}})

hledger-web is a simple web application for browsing and adding transactions.
It provides a more user-friendly UI than the hledger CLI or
hledger-ui TUI, showing more at once (accounts, the current account register,
balance charts) and allowing history-aware data entry, interactive searching,
and bookmarking.

hledger-web also lets you share a journal with multiple users, or even the public web.
There is no user authentication, so if you need that you should put it
behind a suitable web proxy.  As a small protection against data loss
when running an unprotected instance, it writes a numbered backup of
the main journal file (only) on every edit.

Like hledger, it _inputfileswithptr_

hledger-web can be run in three modes:

- `--serve-browse` mode (the default):
  the app serves the web UI and JSON API,
  and opens your default web browser to show the app if possible,
  and exits automatically once no browser window has shown it for fifteen minutes.

- `--serve`: the app just serves the web UI and JSON API.

- `--serve-api`: the app just serves the JSON API.

In all cases hledger-web runs as a foreground process, logging requests to stdout.

# OPTIONS

hledger-web provides the following options:

```
Flags:
     --serve --server       serve and log requests, don't browse or auto-exit
     --serve-api            like --serve, but serve only the JSON web API,
                            not the web UI
     --allow=view|add|edit  set the user's access level for changing data
                            (default: `add` on a local-only address, `view`
                            otherwise). It also accepts `sandstorm` for that
                            platform (reads from the `X-Sandstorm-Permissions`
                            request header).
     --cors=ORIGIN          allow cross-origin requests from the specified
                            origin; setting ORIGIN to "*" allows requests from
                            any origin
     --host=IPADDR          listen on this IP address (default: 127.0.0.1)
     --port=PORT            listen on this TCP port (default: 5000); 0 means
                            a free port chosen by the OS
     --socket=SOCKET        listen on the given unix socket instead of an IP
                            address and port (unix only; implies --serve)
     --base-url=BASEURL     set the base url (default: http://IPADDR:PORT)
     --lang=LANG            show the web UI in this language (en, de, zh); or
                            with auto, use each viewer's browser language if
                            available, otherwise the server's. (Default: the
                            browser's language if available, otherwise en.)
```

By default hledger-web listens only on IP address `127.0.0.1`,
which can be accessed only from the local machine.

To allow access from elsewhere, use `--host` to specify an externally accessible address configured on this machine.
The special address `0.0.0.0` causes it to listen on all of this machine's addresses.

Similarly, you can use `--port` to listen on a TCP port other than 5000.
This is useful if you want to run multiple hledger-web instances on a machine.
`--port 0` makes the operating system choose a free port, which is reported
in the startup message and in the default base url, and is where the browser
is opened in `--serve-browse` mode. This can be useful eg when scripting.

When `--socket` is used, hledger-web creates and communicates via a socket file instead of a TCP port.
This can be more secure, respects unix file permissions, and makes certain use cases easier,
such as running per-user instances behind an nginx reverse proxy. (Eg:
`proxy_pass http://unix:/tmp/hledger/${remote_user}.socket;`.)

You can use `--base-url` to change the protocol, hostname, port and path that appear in
hledger-web's hyperlinks. This is useful eg when integrating hledger-web within a larger website.
The default is `http://HOST:PORT/` using the server's configured host address and TCP port
(or `http://HOST` if PORT is 80).
Note this affects url generation but not route parsing.

<!--  #2139
`--file-url=URL`
: set a different base url for static files (default: `BASEURL/static/`)

hledger-web normally serves static files itself,
but if you wanted to serve them from another server,
eg for better caching or cookie-less serving on high performance websites,
you can customise their urls with this.
-->

hledger-web also supports many of hledger's [general options](hledger.md#options):

_webgeneraloptions_

hledger-web shows accounts with zero balances by default (like `hledger-ui`, and unlike `hledger`).
Using the `-E/--empty` flag will reverse this behaviour.
If you see accounts which appear to have a zero balance, but cannot be hidden with `-E`,
it's because they have a mixed-cost balance, which looks like zero when costs are hidden.
(hledger-web does not show costs.)

Report options and query arguments given at startup become url state:
hledger-web translates them into the url that browse mode opens, and
that `--serve` prints, eg `hledger-web -V -M` opens
`/journal?interval=monthly&value=end`, and `hledger-web --cleared -3 assets`
opens `/journal?q=assets status:*&depth=3` (url-encoded). The server
itself keeps the defaults, so every view is fully described by its
url: a bare url shows the default view, and editing the url (or the
search and the links above each page) changes the view. Report options
the web UI has no equivalent for are ignored; options that map to
page-local state, like `--historical`, shape the opening page only.

This means a startup query is a starting search, not a restriction: a
viewer can edit or clear it, and the JSON API serves the whole journal
regardless. To actually restrict what hledger-web serves, give it a
file holding only the entries to serve (eg one written by `hledger
print QUERY`).

If you use the bash shell, you can auto-complete flags by pressing TAB in the command line.
If this is not working see [Install > Shell completions](install.html#shell-completions).

# WEB UI

hledger-web's main views are:

- the **journal view** (the home page), showing journal entries, newest first, with their postings;
- the **register view**, showing the transactions affecting one account (and its subaccounts),
  with a running balance and a balance chart, the account named by an `account` parameter,
  eg `/register?account=assets:bank` (with `subs=0`, excluding its subaccounts), which the
  register's links and search keep; and
- the **report views**, described [below](#reports): the balance sheet, income statement,
  and cashflow statement (and holdings, for journals using lots), also linked from the sidebar,
  and the All accounts report and the balance sheet with equity.

The register's chart shows the running balance over the page's transactions, across the page.
With several commodities, a legend chooses the one charted, each on its own scale,
starting with the one with the most transactions.
Clicking a point goes to its transaction, and dragging across the chart
shows the transactions of the dates dragged across.

A row of links at the top of every page leads to the journal and report views.
Below it are the search form, the options, and then the view's heading and content.
The options are hidden until opened (click them, or press `o`); while hidden, they list
the ones in effect, eg "Monthly · Depth 2 · Tree", so a view's shape is always visible.

The journal and register views show the newest 1000 matching transactions, with links to the older
and newer pages and to pages by number, so that a page stays a reasonable size
however large the journal is (a `page` parameter in the URL names the page).
When the matching transactions span more than one year, a row of years among the
controls links to the view narrowed to each year; "All" widens it again, and shift-clicking
a year selects a range of years (a `date:FIRST..END` search term, whose years the row marks).
When they span more than twenty years, the years are shown one row per decade.

The **sidebar** lists accounts and their balances (parent balances include subaccounts,
and multiple commodities are shown one above the other).
When a report shows its accounts as a tree (the Accounts row), the sidebar does too,
with carets that fold and open each group in place. Folds are remembered in the browser,
as choices laid over each page's baseline: a page with a depth limit starts folded
to it, one without starts fully open, and either way the groups you have opened or
closed by hand stay as you left them. A caret clicked back to its page's baseline
is forgotten.
Click an account name to see its register, or an amount to see the transactions it is
made of. In the journal and register views, click a date to see that day's journal entries.

The **search form** filters every view with hledger's [query](hledger.md#queries) syntax,
eg `expenses date:thismonth`; the help dialog summarises the query types.
The current view and search are reflected in the URL, so views can be bookmarked and shared.

The **add form** (press `a`, or click "Add a transaction" in the journal view)
adds a transaction to the main journal file, if the [access level](#permissions) allows it.
It autocompletes account names and descriptions from your existing entries.

The **help dialog** (press `?`, or click the question mark button) lists these keyboard shortcuts,
which work when you are not typing in a field:

- `h` or `?` - show or hide the help dialog
- `.` - show or hide key hints: a small badge on each control, naming its key
  (remembered in this browser; not shown on touch screens)
- `g` - go to another page: shows a menu of the pages, each with its key;
  then `j` journal, `b` balance sheet, `i` income statement, `c` cashflow statement,
  `h` holdings (for journals using lots), `a` all accounts, `e` balance sheet with equity,
  or `n` / `p` the next / previous page in that order, wrapping round (escape to cancel)
- `a` or `n` - add a transaction (escape to cancel)
- `s` - show or hide the sidebar
- `o` - show or hide the report options
- `f` - full window: show only the report's heading and data, or everything (`s`, `o` and `/` leave it, showing what they ask for)
- `z` - show or hide accounts with zero balances
- `t` - show accounts as a tree, or a list
- `H` - show ending balances, or balance changes
- `L` - show or hide lot detail
- `V` - show amounts at market value, or as recorded
- `B` - show amounts at cost, or as recorded
- `R` - show only real postings, or all
- `U`, `P`, `C` - show only unmarked, pending, or cleared transactions, or all
- `S` - sort by amount, or by account
- `T`, `A` - add or remove the row total and average columns (multi-period reports)
- `D`, `W`, `M`, `Q`, `Y` - set the report interval (daily, weekly, monthly, quarterly, yearly); pressed again, remove it
- `0`-`9`, `-`, `+` - set or adjust the account depth limit (`-` and `+` step between 0 and the deepest)
- `/` - focus the search form, ready to add a term (escape to leave it)

The pages are light or dark, following your OS or browser's color scheme setting,
and switch when it changes.

Editing, uploading and downloading journal files is described [below](#editing-uploading-downloading).

# PERMISSIONS

You can restrict who can access hledger-web by

- setting the IP address it listens on (see `--host` above).
  By default it listens on 127.0.0.1, accessible to users on the local machine only.
- or by putting it behind an authenticating proxy, such as caddy or apache
- or by putting it behind a firewall.

And you can restrict what the users reaching it can do,
by specifying the `--allow=ACCESSLEVEL` option at startup.
ACCESSLEVEL is one of:

- `view` - allows viewing the journal file(s)
- `add`  - also allows adding new transactions to the main journal file
- `edit` - also allows editing, uploading or downloading the journal file(s)
- `sandstorm` - (for the hledger-web Sandstorm app:) allows whichever of `view`, `add`, or `edit` are specified in the `X-Sandstorm-Permissions` HTTP header

The default access level is `add` when listening on a local-only address
(`127.0.0.1`, `::1`, `localhost`, or a unix socket), and `view` otherwise.
To allow more than the default access, start it with an explicit `--allow=add` or `--allow=edit` option.

# EDITING, UPLOADING, DOWNLOADING

If you start hledger-web with `--allow=edit`,
you'll see a new "spanner" button to the right of the search form.
Clicking this will let you edit, upload, or download the journal
file or any files it includes.

Note, unlike any other hledger command, in this mode you (or any visitor)
can alter or wipe the data files.
Normally when hledger-web changes any data, it will save a numbered backup of the file
(assuming file permissions allow it, the disk is not full, etc.)
hledger-web is not aware of version control systems, currently; if you use one,
you'll have to arrange to commit the changes yourself.

Changes which would leave the journal file(s) unparseable or invalid
(eg with failing balance assertions) are prevented.

# REPORTS

Besides the journal and account registers, hledger-web can show the
reports of the command line's
[balancesheet](hledger.md#balancesheet),
[balancesheetequity](hledger.md#balancesheetequity),
[incomestatement](hledger.md#incomestatement), and
[cashflow](hledger.md#cashflow) commands, at `/balancesheet`,
`/balancesheetequity`, `/incomestatement`, and `/cashflow`, and the
general [balance report](hledger.md#balance), named All accounts (as in hledger-ui), at `/balance`.
The sidebar links to the balance sheet, income statement, and cashflow
statement, and the row of links at the top of every page links to them
all: the journal and the named reports first, as in the sidebar, then the
general ones (All accounts, and the balance sheet with equity).

For journals that use [lots](hledger.md#lots-and-capital-gains), the
[holdings](hledger.md#holdings) report is at `/holdings`, and appears
in the sidebar and the report links. It shows one row per account and
held commodity by default; its links can show each individual lot (a
`lots=1` parameter), fully disposed positions (a `closed=1` parameter;
`empty` keeps meaning zero-balance accounts, as on the other pages),
accounts as a tree (positions grouped under account headings that
subtotal the dollar columns, with each position's lots folding into
it, opened in place by a caret), values converted to the market
valuation commodity (`value=end`, like `-V`), and rows sorted by
value. On such journals
every page also gains a Lots link, showing lot subaccounts and per-lot
postings everywhere with the same `lots` parameter.

The search box filters the reports like the other pages, its `date:`
terms setting the report's dates. An `interval` parameter, like the
command line's `-D`/`-W`/`-M`/`-Q`/`-Y` or the interval part of
`-p/--period`, divides them into columns, eg `/balancesheet?interval=monthly`
or `/incomestatement?q=date:2025&interval=quarterly`; the links above each
report offer the usual intervals, and column headings link to the
report for that column's dates.
A `date:` term typed with an interval, as on the command line
(`date:monthly`, or `"date:quarterly in 2025"`), moves its interval to
the `interval` parameter (the page reloads), leaving its dates in the
search.

A `depth` parameter, like `--depth`, limits the account depth, eg
`/balancesheet?depth=2`; the Depth links and the digit keys set it, and
the pages' links carry it. Depth 0 shows only the total, as one row of
all accounts. A `depth:N` term typed in the search moves
there too (the page reloads with it as the `depth` parameter), so the
search holds only the terms selecting data.
In tree mode, the reports and the sidebar show the accounts below this
limit folded, with carets that open them in place; folded, they show
the same rows as `--depth`. The holdings report is clipped to the
limit instead, as on the command line, merging the clipped accounts'
positions by commodity.
A per-account depth limit, like `depth:assets=3`, stays in the search,
and clips its accounts as on the command line, in tree mode too.

The links above each report also set how amounts are shown, as recorded, at
cost (like `-B`), or at market value at the end of each period (like
`-V`), with a `value` parameter (`none`, `cost`, `then`, `end`, `now`,
or a date; all but `cost` take an optional commodity, as
`--value WHEN[,COMM]`) that is carried to the other reports; and
whether accounts with zero balances are shown, with an `empty`
parameter that the `z` key toggles and the pages' links carry.
Other rows filter what every page shows, each rewriting its own search
term: transaction status, posting realness, account type, and
commodity, the last two selecting several at once with shift-click.

Every page shows and preserves the report state its url carries: a
link changes only the control it names, and controls that take effect
on another page (the report-shaping rows, on the journal and register)
show muted labels, their state marked all the same. Only the
accumulation mode and the register's costs toggle are page-local:
each report accumulates its own way, and following a link returns
to the target page's own default.

The balance sheets show ending balances and the income statement and
cashflow statement show changes, as their commands do; an `accum`
parameter (`historical` or `change`) overrides that, and the heading
then says so, as the commands' does. The All accounts report shows changes,
or with `accum=historical`, which its "Ending balances" link sets,
each account's balance at the end of each period.
Like the commands, the statements show all balances as positive
amounts, so liabilities, equity, and revenues appear with the opposite
sign to the register's; the link on such a figure says so.

Every figure links to the register it is derived from: the account's
transactions in that period, whose final balance is the figure, or its
negation in the sections shown with the opposite sign. (The two can
differ when a transaction's postings have dates of their own: the
report counts such a posting in its own period, while the register
shows its whole transaction.) A section's total links to the register
of the section's account types.
An ending balance's register runs in historical mode (its own
`accum=historical`): its running balance starts from the balance
brought forward from before the period, shown as its oldest row, and
its balance column's heading switches between the two modes.
A figure at cost or at market value links to a register showing its
amounts the same way (with the same `value` parameter).

# RELOADING

hledger-web detects changes made to the files by other means (eg if you edit
it directly, outside of hledger-web), and it will show the new data
when you reload the page or navigate to a new page.
If a change makes a file unparseable,
hledger-web will display an error message until the file has been fixed.

(If you are viewing files mounted from another machine, make sure that
both machines have roughly the same idea of what time it is.)

# JSON API

In addition to the web UI, hledger-web also serves a JSON API that can be
used to get data or add new transactions.
If you want the JSON API only, you can use the `--serve-api` flag. Eg:

```cli
$ hledger-web -f examples/sample.journal --serve-api
...
```

You can get JSON data from these routes:

```
/version
/accountnames
/transactions
/prices
/commodities
/accounts
/accounttransactions/ACCOUNTNAME
/openapi.json
```

Eg, all account names in the journal (similar to the [accounts](hledger.md#accounts) command).
(hledger-web's JSON does not include newlines, here we use python to prettify it):

```cli
$ curl -s http://127.0.0.1:5000/accountnames | python3 -m json.tool
[
    "assets",
    "assets:bank",
    "assets:bank:checking",
    "assets:bank:saving",
    "assets:cash",
    "expenses",
    "expenses:food",
    "expenses:supplies",
    "income",
    "income:gifts",
    "income:salary",
    "liabilities",
    "liabilities:debts"
]
```

Or all transactions:

```cli
$ curl -s http://127.0.0.1:5000/transactions | python3 -m json.tool
[
    {
        "tcode": "",
        "tcomment": "",
        "tdate": "2008-01-01",
        "tdate2": null,
        "tdescription": "income",
        "tindex": 1,
        "tpostings": [
            {
                "paccount": "assets:bank:checking",
                "pamount": [
                    {
                        "acommodity": "$",
                        "aismultiplier": false,
                        "aprice": null,
...
```

Most of the JSON corresponds to hledger's data types; for details of what the fields mean, see the
[Hledger.Data.Json haddock docs](https://hackage.haskell.org/package/hledger-lib/docs/Hledger-Data-Json.html)
and click on the various data types, eg
[Transaction](https://hackage.haskell.org/package/hledger-lib/docs/Hledger-Data-Types.html#t:Transaction).
And for a higher level understanding, see the [journal docs](hledger.md#journal).
There is also a basic [OpenAPI specification][openapi.yaml], also served at `/openapi.json`.

[openapi.yaml]: https://github.com/hledgerorg/hledger/blob/main/hledger-web/config/openapi.yaml

Some routes return a report type wrapping the data; eg `/accounttransactions` returns an
[AccountTransactionsReport](https://hackage.haskell.org/package/hledger-lib/docs/Hledger-Reports-AccountTransactionsReport.html#t:AccountTransactionsReport),
a report title and a list of items.
The handlers in [Hledger.Web.Handler.MiscR](https://hackage.haskell.org/package/hledger-web/docs/Hledger-Web-Handler-MiscR.html) show what each route returns.

You can add a new transaction to the journal with a PUT request to `/add`,
if hledger-web was started with `--allow=add` (the default when listening on a local-only address).
The payload must be the full, exact JSON representation of a hledger transaction
(partial data won't do).
You can get sample JSON from hledger-web's `/transactions` or `/accounttransactions`,
or from hledger's print command. Eg, this saves the first transaction of the sample journal to `txn.json`:

```cli
$ hledger -f examples/sample.journal print -O json | python3 -c 'import json,sys; json.dump(json.load(sys.stdin)[0], sys.stdout, indent=4)' > txn.json
```

Here's how it looks
(remember, this JSON corresponds to hledger's
[Transaction](https://hackage.haskell.org/package/hledger-lib/docs/Hledger-Data-Types.html#t:Transaction)
and related data types):

```json
{
    "tcode": "",
    "tcomment": "",
    "tdate": "2008-01-01",
    "tdate2": null,
    "tdescription": "income",
    "tindex": 1,
    "tpostings": [
        {
            "paccount": "assets:bank:checking",
            "pamount": [
                {
                    "acommodity": "$",
                    "acost": null,
                    "acostbasis": null,
                    "aquantity": {
                        "decimalMantissa": 1,
                        "decimalPlaces": 0,
                        "floatingPoint": 1
                    },
                    "astyle": {
                        "ascommodityside": "L",
                        "ascommodityspaced": false,
                        "asdecimalmark": ".",
                        "asdigitgroups": null,
                        "asprecision": 0,
                        "asrounding": "NoRounding"
                    }
                }
            ],
            "pbalanceassertion": null,
            "pcomment": "",
            "pdate": null,
            "pdate2": null,
            "poriginal": null,
            "preal": "RealPosting",
            "pstatus": "Unmarked",
            "ptags": [],
            "ptransaction_": "1"
        },
        {
            "paccount": "income:salary",
            "pamount": [
                {
                    "acommodity": "$",
                    "acost": null,
                    "acostbasis": null,
                    "aquantity": {
                        "decimalMantissa": -1,
                        "decimalPlaces": 0,
                        "floatingPoint": -1
                    },
                    "astyle": {
                        "ascommodityside": "L",
                        "ascommodityspaced": false,
                        "asdecimalmark": ".",
                        "asdigitgroups": null,
                        "asprecision": 0,
                        "asrounding": "NoRounding"
                    }
                }
            ],
            "pbalanceassertion": null,
            "pcomment": "",
            "pdate": null,
            "pdate2": null,
            "poriginal": null,
            "preal": "RealPosting",
            "pstatus": "Unmarked",
            "ptags": [],
            "ptransaction_": "1"
        }
    ],
    "tprecedingcomment": "",
    "tsourcepos": [
        {
            "sourceColumn": 1,
            "sourceLine": 31,
            "sourceName": "/home/user/hledger/examples/sample.journal"
        },
        {
            "sourceColumn": 1,
            "sourceLine": 34,
            "sourceName": "/home/user/hledger/examples/sample.journal"
        }
    ],
    "tstatus": "Unmarked",
    "ttags": []
}
```

And here's how to add it with curl. This should append a new entry to your journal file:

```cli
$ curl http://127.0.0.1:5000/add -X PUT -H 'Content-Type: application/json' --data-binary @txn.json
```

# DEBUG OUTPUT

You can add `--debug[=N]` to the command line to log debug output.
N ranges from 1 (least output, the default) to 9 (maximum output).
Typically you would start with 1 and increase until you are seeing enough.
Debug output goes to stderr, interleaved with the requests logged on stdout.
To capture debug output in a log file instead, you can usually redirect stderr, eg:\
`hledger-web --debug=3 2>hledger-web.log`.

# LANGUAGE

hledger-web's pages can be shown in another language when a translation catalog is available
(see [Languages](hledger.md#languages) in the hledger manual).

When hledger-web is started with `--lang LANG`, eg `--lang de`, every page is in that language,
whatever the browser asks for.
So you can use hledger-web in a language other than your browser's,
or give every user of a shared server the same language.

Otherwise the language is chosen per request, and the first of these naming an available translation wins:

1. a `_LANG` query parameter, eg `?_LANG=de`. This choice is remembered in a `_LANG` cookie.
2. the `_LANG` cookie
3. the browser's `Accept-Language` header, ie the browser's or system's language settings

If none does, pages are in English, or with `--lang auto`, in the language of hledger-web's environment.
So viewers usually get their browser's language automatically, if hledger-web has it.
Catalogs, including any in the config directory, are loaded when hledger-web starts.

# ENVIRONMENT

**LEDGER_FILE**
The main journal file to use when not specified with `-f/--file`.
Default: `$HOME/.hledger.journal`.

# BUGS

_reportbugs_

Some known issues:

Does not work well on small screens, or in text-mode browsers.
