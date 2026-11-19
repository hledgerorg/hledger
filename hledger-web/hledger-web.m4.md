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

hledger-web is hledger's web interface. In a web browser, it shows the journal,
account registers, and the main financial reports with their charts, and lets you
search them, add transactions, and (if allowed) edit the journal files.
It shows more at once than the hledger CLI or hledger-ui
(eg the accounts beside a register, or a report's chart above its table),
and every view has its own url, so it can be bookmarked or shared.

hledger-web also lets you share a journal with multiple users, or even the public web.
There is no user authentication, so if you need that you should put it
behind a suitable web proxy (see [Permissions](#permissions)).

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

hledger-web provides the following command line options:

```
Flags:
     --serve-browse         server mode: serve the web UI and JSON API, and
                            open a browser, and exit if inactive for 15m
                            (default)
     --serve                server mode: just serve the web UI and JSON API
     --serve-api            server mode: just serve the JSON API
     --allow=view|add|edit  set the user's access level for changing data
                            (default: `add` on a local-only address, `view`
                            otherwise). It also accepts `sandstorm` for that
                            platform (reading from the
                            `X-Sandstorm-Permissions` request header).
     --cors=ORIGIN          allow cross-origin requests from the specified
                            origin; setting ORIGIN to "*" allows requests from
                            any origin
     --host=IPADDR          listen on this IP address (default: 127.0.0.1)
     --port=PORT            listen on this TCP port (default: 5000); 0 means
                            a free port chosen by the OS
     --socket=SOCKET        listen on the given unix socket instead of an IP
                            address and port (only on unix)
     --base-url=BASEURL     set the base url (default: http://IPADDR:PORT)
     --lang=LANG            show the web UI in this language (en, de, es, ru,
                            zh); or with auto, use each viewer's browser
                            language if available, otherwise the server's.
                            (Default: the browser's language if available,
                            otherwise en.)
     --commit               record the changed files in the journal's jj or
                            git repository
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

Some of these can be adjusted while hledger-web is running, in the web UI's Options panel.

hledger-web shows accounts with zero balances by default (like `hledger-ui`, and unlike `hledger`);
`-E/--empty` starts it with them hidden instead. In the web UI, the Zero balances option
or the `z` key shows or hides them.

Report options and a query given at startup set the view hledger-web opens with,
by putting them in its url (see [URL parameters](#url-parameters)).
Eg `hledger-web -V -M` opens `/journal?interval=monthly&value=end`,
and `hledger-web --cleared -3 assets` opens `/journal?q=assets status:*&depth=3`.
They are only a starting point: they can be changed in the web UI,
and they don't affect other urls or the JSON API.
Report options that hledger-web has no equivalent for are ignored.

Note, a startup query doesn't restrict what hledger-web serves;
to do that, give it a file holding only the entries to serve (eg one written by `hledger print QUERY`).

If you use the bash shell, you can auto-complete flags by pressing TAB in the command line.
If this is not working see [Install > Shell completions](install.html#shell-completions).

# WEB UI

hledger-web's main views are:

- the **journal view**, showing journal entries, newest first, with their postings
- the **report views**, described [below](#reports): the balance sheet, income statement,
  cashflow statement (and holdings, for journals using lots), and All accounts report
- a **register view** for each account, reached by clicking an account name,
  showing the transactions affecting that account (and its subaccounts),
  with a running balance and a balance chart.

Every page has, from the top: links to the journal and the reports,
the search form, the options, and then the view itself.
The options are hidden until you open them (click Options, or press `o`);
while hidden, they list the ones in effect, eg "Monthly · Depth 2 · Tree".

The journal and register show the newest 1000 matching transactions,
with links to older and newer pages.
When the transactions span more than one year, the options include a row of years,
to narrow the view to one year; shift-click a second year to select a range of years.

The register's chart shows the running balance over the page's transactions.
With several commodities, use the legend, or the `[` and `]` keys, to choose the one charted.
Click a point to go to its transaction, or drag across the chart to see the transactions of those dates.
The register's Costs option shows the costs recorded with its amounts.

The **sidebar** lists accounts and their balances (parent balances include subaccounts).
When the Accounts option is Tree, the sidebar is a tree too, with carets that fold and open
each group. It starts folded to the depth limit, if there is one, and the browser remembers
the groups you open or close.

Click an account name to see its register, or an amount to see the transactions it is made of.
In the journal and register, click a date to see that day's journal entries.

The **search form** filters every view with hledger's [query](hledger.md#queries) syntax,
eg `expenses date:thismonth`; the help dialog summarises the query types.
The search and the options are part of the page's url (see [URL parameters](#url-parameters)).

The **add form** (press `a`, or click "Add a transaction" in the journal view)
adds a transaction to the main journal file, if the [access level](#permissions) allows it.
It autocompletes account names and descriptions from your existing entries.

The **help dialog** (press `?`, or click the question mark button) lists these keyboard shortcuts,
which work when you are not typing in a field:

- `h` or `?` - show or hide the help dialog
- `g` - go to another page: shows a menu of the pages, each with its key;
  then `j` journal, `b` balance sheet, `i` income statement, `c` cashflow statement,
  `h` holdings (for journals using lots), `a` all accounts,
  or `n` / `p` the next / previous page in that order, wrapping round (escape to cancel)
- `a` or `n` - add a transaction (escape to cancel)
- `s` - show or hide the sidebar
- `o` - show or hide the report options
- `c` - show or hide the report's chart (on pages with one)
- `[` / `]` - chart the previous / next commodity (on pages whose chart has several, wrapping round)
- `d` - show or hide the report's data, its table (on pages with a chart)
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
Before saving an edited or uploaded file, hledger-web saves a numbered backup of it
(eg `main.journal.1`, then `main.journal.2`); if the backup can't be written, the file is not changed.
(Adding a transaction appends it to the main journal file without making a backup.)

If your files are in a jj or git repository, you can start hledger-web with `--commit`,
and it will commit each change (each added transaction, and each edited or uploaded file),
with a descriptive message. It checks at startup that there is a repository.
If a commit fails, the change is still saved, and the error is shown.
See [Version control](hledger.html#version-control) in the hledger manual.

Changes which would leave the journal file(s) unparseable or invalid
(eg with failing balance assertions) are prevented.

# REPORTS

Besides the journal and the account registers, hledger-web shows these
reports. The sidebar and the links at the top of every page lead to each
of them, and so does the `g` key followed by the first letter of the report's name:

- **Balance sheet** (`b`, `/balancesheet`): assets, liabilities and net worth, like the
  [balancesheet](hledger.md#balancesheet) command.
  Its Equity option adds an equity section, like [balancesheetequity](hledger.md#balancesheetequity).
- **Income statement** (`i`, `/incomestatement`): revenues, expenses and net income, like
  [incomestatement](hledger.md#incomestatement).
- **Cashflow** (`c`, `/cashflow`): changes in cash accounts, like [cashflow](hledger.md#cashflow).
- **Holdings** (`h`, `/holdings`): investments and their performance, like [holdings](hledger.md#holdings).
  Shown only for journals that use [lots](hledger.md#lots-and-capital-gains); see [below](#holdings).
- **All accounts** (`a`, `/balance`): all accounts, or those you search for, like [balance](hledger.md#balance).

Each report shows a chart and then a table (by default; both can be toggled).
Click any amount to see the transactions it is made of.

## Options

A report's options (click Options, or press `o`) change what it shows.
These are similar to hledger's command-line [options](hledger.md#options) 
and [hledger-ui's keys](hledger-ui.md#keys).
The main ones, with their keyboard shortcuts:

- **Interval** (`D`, `W`, `M`, `Q`, `Y`): one column for the whole period,
  or one per day, week, month, quarter or year
  (see [Report intervals](hledger.md#report-intervals)).
  Click a column's heading to see the report for just its dates.
- **Show** (`H`): balance changes in each period, or ending balances
  (which include everything before the period).
  The balance sheet shows ending balances by default and the other reports show changes,
  as their commands do; the report's heading says which it is showing.
- **Depth** (`0`-`9`, `-`, `+`): how many levels of accounts to show
  (see [Depth](hledger.md#depth)). Depth 0 shows only the totals.
- **Accounts** (`t`): a list, or a tree with subtotals. In a tree, the accounts
  below the depth limit are folded, and their carets open them in place.
- **Amounts** (`B`, `V`): as recorded, at cost, or at market value at the end of each period
  (see [Cost reporting](hledger.md#cost-reporting) and [Value reporting](hledger.md#value-reporting)).
- **Zero balances** (`z`): hide or show accounts whose balance is zero.
- **Equity** (balance sheet only): hide or show the equity section.
  The browser remembers this choice for each hledger-web server.
- **Status** (`U`, `P`, `C`), **Postings** (`R`), account types, and commodities:
  show only transactions with that [status](hledger.md#status), only real postings,
  or only some [account types](hledger.md#account-types) or commodities.
  These rows edit the search, adding a term like `status:*` or `type:A`.
  Shift-click selects several types or commodities.

The options you choose stay in effect as you move to other pages, except Show,
which each report sets to its own default.
On the journal and register, the report options are shown muted, but are kept.

The search form filters reports as it does the other pages, and its `date:` terms set the report's dates.
An interval or depth typed in the search, like `date:monthly` or `depth:2`,
moves into the options when the page reloads.
A depth limit for some accounts only, like `depth:assets=3`, stays in the search.

The options are also [URL parameters](#url-parameters), so you can bookmark a report with them.

(For more detail, see the hledger manual, eg [CONCEPTS](hledger.md#part-4-concepts).)

## Charts

A report's chart is the one its command draws with [`--chart`](hledger.md#charts):
eg a bar per account, or with an interval, each account over time,
and for the statements, each section and the net total.
In tree mode it shows the accounts down to the depth limit.
With several commodities, use the legend, or the `[` and `]` keys, to choose the one charted.

The `c` key hides or shows the chart, and `d` the table.
The browser remembers this for each hledger-web server.

## From a report to its transactions

Click an amount to see its account's register for that period:
the transactions the amount is made of.
An ending balance's register starts with the balance brought forward,
so its final running balance is that amount.
A section's total shows the register of all the section's accounts.
An amount shown at cost or market value leads to a register showing its amounts the same way.

Some things can make the register look different from the report:

- The statements show liabilities, equity and revenues as positive amounts,
  as their commands do, so their registers show the same amounts negated.
  The amount's tooltip says so.
- When a posting has a date of its own, the report counts it on that date,
  but the register lists its whole transaction, on the transaction's date.

## Holdings

The holdings report shows one row for each commodity held in each account,
with its cost basis, value and gains. Its chart has a bar for each one,
showing its cost basis and unrealised gain or loss.
Its own options can show:

- each lot separately (**Lots**, `L`),
- fully disposed positions and their realised gains (**Closed positions**),
- all values in the market valuation commodity (**Values**).

Its depth limit doesn't fold accounts: as on the command line, it merges
the deeper accounts' positions, by commodity, into the accounts at the limit.

On journals that use lots, every page also has a Lots option, showing
lot subaccounts and per-lot postings.

# URL PARAMETERS

A page's url includes its search and options, so a bookmark or a shared link
shows the same view. You can also write these urls yourself, eg
`/balancesheet?interval=monthly&depth=2` or `/register?account=assets:bank`.
These are the parameters, most corresponding to hledger options:

- `q` - the search
- `account` - the account whose register to show (with its subaccounts, unless `subs=0`)
- `page` - which page of transactions to show, in the journal and register (1 is the newest)
- `interval` - `daily`, `weekly`, `monthly`, `quarterly` or `yearly` (like `-D`, `-W`, `-M`, `-Q`, `-Y`)
- `depth` - a number (like `--depth`)
- `accum` - `change`, `historical` or `cumulative` (like `--change`, `-H`, `--cumulative`)
- `value` - `none`, `cost`, or `then`, `end`, `now` or a date, optionally followed by `,COMMODITY` (like `--value`)
- `infer` - `1` to infer market prices from transaction costs too (like `--infer-market-prices`)
- `empty` - `1` to show zero balances, `0` to hide them (like `-E`)
- `list` - `tree` or `flat` (like `--tree`, `--flat`)
- `sort` - `amount` (like `-S`)
- `total`, `avg`, `pct` - `1` to add totals, averages, or show percentages (like `-T`, `-A`, `-%`)
- `calc` - `valuechange`, `gain` or `count` (like `--valuechange`, `--gain`, `--count`)
- `date2` - `1` to use secondary dates (like `--date2`)
- `costs` - `1` to show costs, in the register
- `equity` - `1` or `0`, on the balance sheet (the old `/balancesheetequity` address leads to `equity=1`)
- `lots` - `1` to show lots (like `--lots`)
- `closed` - `1`, on the holdings page, to show closed positions

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
                        "acost": null,
                        "acostbasis": null,
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

Without JavaScript (eg in text-mode browsers), pages can be viewed and their links followed,
but the add form, help dialog, keyboard shortcuts, sidebar toggle and folding don't work.
