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
  and exits automatically once no browser window has shown it for two minutes.

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
     --test                 run hledger-web's tests and exit. hspec test
                            runner args may follow a --, eg: hledger-web --test
                            --help
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

_generaloptions_

hledger-web shows accounts with zero balances by default (like `hledger-ui`, and unlike `hledger`).
Using the `-E/--empty` flag will reverse this behaviour.
If you see accounts which appear to have a zero balance, but cannot be hidden with `-E`,
it's because they have a mixed-cost balance, which looks like zero when costs are hidden.
(hledger-web does not show costs.)

Reporting options and/or query arguments can be used to set an initial query,
which although not shown in the UI, will restrict the data shown
(in addition to any search query entered in the UI).

If you use the bash shell, you can auto-complete flags by pressing TAB in the command line.
If this is not working see [Install > Shell completions](install.html#shell-completions).

# WEB UI

hledger-web's main views are:

- the **journal view** (the home page), showing journal entries, newest first, with their postings;
- the **register view**, showing the transactions affecting one account (and its subaccounts),
  with a running balance and a balance chart; and
- the **report views**, described [below](#reports): the balance sheet, income statement,
  and cashflow statement, linked from the sidebar, and the balance sheet with equity and
  the general balance report, linked from those.

The **sidebar** lists accounts and their balances (parent balances include subaccounts,
and multiple commodities are shown one above the other).
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
- `j` - go to the journal view
- `a` or `n` - add a transaction (escape to cancel)
- `s` - show or hide the sidebar
- `e` - show or hide empty accounts in the sidebar
- `f` - focus the search form

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
general [balance report](hledger.md#balance) at `/balance`.
The sidebar links to the balance sheet, income statement, and cashflow
statement, and each report page links to all five.

A `period` parameter, like the command line's `-p/--period`, selects
the interval and/or the period, eg `/balancesheet?period=monthly` or
`/incomestatement?period=quarterly in 2025`; the links above each
report offer the usual intervals, and column headings link to the
report for that period.
The search box filters the reports like the other pages, including
`depth:` terms, and the general report options given at startup, such
as `--depth`, `-B`, or `-V`, apply. A `date:` term can set the interval
too, as on the command line (`date:monthly`, or
`"date:quarterly in 2025"`), and wins over the `period` parameter.

The balance sheets show ending balances and the income statement and
cashflow statement show changes, as their commands do; an `accum`
parameter (`historical` or `change`) overrides that, and the heading
then says so, as the commands' does. The balance report shows changes,
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

# ENVIRONMENT

**LEDGER_FILE**
The main journal file to use when not specified with `-f/--file`.
Default: `$HOME/.hledger.journal`.

# BUGS

_reportbugs_

Some known issues:

Does not work well on small screens, or in text-mode browsers.
