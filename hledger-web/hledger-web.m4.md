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
There is no access control, so if you need that you should put it
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
which be accessed only from the local machine.

To allow access from elsewhere, use `--host` to specify an externally accessible address configured on this machine,
The special address `0.0.0.0` causes it to listen on all of this machine's addresses.

Similarly, you can use `--port` to listen on a TCP port other than 5000.
This is useful if you want to run multiple hledger-web instances on a machine.
`--port 0` makes the operating system choose a free port, which is reported
in the startup message and in the default base url. This can be useful eg
when scripting; it is supported with `--serve` and `--serve-api`, but not
with `--serve-browse`.

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

If you enable the `manage` capability mentioned above,
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
```

Eg, all account names in the journal (similar to the [accounts](hledger.html#accounts) command).
(hledger-web's JSON does not include newlines, here we use python to prettify it):

```cli
$ curl -s http://127.0.0.1:5000/accountnames | python -m json.tool
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
$ curl -s http://127.0.0.1:5000/transactions | python -m json.tool
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
[Hledger.Data.Json haddock docs](https://hackage.haskell.org/package/hledger-lib-1.17.1/docs/Hledger-Data-Json.html)
and click on the various data types, eg 
[Transaction](https://hackage.haskell.org/package/hledger-lib-1.17.1/docs/Hledger-Data-Types.html#t:Transaction).
And for a higher level understanding, see the [journal docs](hledger.html#journal).
There is also a basic [OpenAPI specification][openapi.yaml].

[openapi.yaml]: https://github.com/plaintextaccounting/hledger/blob/main/hledger-web/config/openapi.yaml

In some cases there is outer JSON corresponding to a "Report" type.
To understand that, go to the
[Hledger.Web.Handler.MiscR haddock](https://hackage.haskell.org/package/hledger-web-1.17.1/docs/Hledger-Web-Handler-MiscR.html)
and look at the source for the appropriate handler to see what it returns.
Eg for `/accounttransactions` it's
[getAccounttransactionsR](https://hackage.haskell.org/package/hledger-web-1.17.1/docs/src/Hledger.Web.Handler.MiscR.html#getAccounttransactionsR),
returning a "`accountTransactionsReport ...`".
[Looking up](https://hoogle.haskell.org/?hoogle=accountTransactionsReport) the haddock for that
we can see that /accounttransactions returns an 
[AccountTransactionsReport](https://hackage.haskell.org/package/hledger-lib-1.17.1/docs/Hledger-Reports-AccountTransactionsReport.html#t:AccountTransactionsReport),
which consists of a report title and a list of AccountTransactionsReportItem (etc).

You can add a new transaction to the journal with a PUT request to `/add`,
if hledger-web was started with the `add` capability (enabled by default).
The payload must be the full, exact JSON representation of a hledger transaction
(partial data won't do).
You can get sample JSON from hledger-web's `/transactions` or `/accounttransactions`,
or you can export it with hledger-lib, eg like so:

```cli
.../hledger$ stack ghci hledger-lib
>>> writeJsonFile "txn.json" (head $ jtxns samplejournal)
>>> :q
```

Here's how it looks as of hledger-1.17
(remember, this JSON corresponds to hledger's 
[Transaction](http://hackage.haskell.org/package/hledger-lib-1.17.1/docs/Hledger-Data-Types.html#t:Transaction)
and related data types):

```json
{
    "tcomment": "",
    "tpostings": [
        {
            "pbalanceassertion": null,
            "pstatus": "Unmarked",
            "pamount": [
                {
                    "aprice": null,
                    "acommodity": "$",
                    "aquantity": {
                        "floatingPoint": 1,
                        "decimalPlaces": 10,
                        "decimalMantissa": 10000000000
                    },
                    "aismultiplier": false,
                    "astyle": {
                        "ascommodityside": "L",
                        "asdigitgroups": null,
                        "ascommodityspaced": false,
                        "asprecision": 2,
                        "asdecimalpoint": "."
                    }
                }
            ],
            "ptransaction_": "1",
            "paccount": "assets:bank:checking",
            "pdate": null,
            "ptype": "RegularPosting",
            "pcomment": "",
            "pdate2": null,
            "ptags": [],
            "poriginal": null
        },
        {
            "pbalanceassertion": null,
            "pstatus": "Unmarked",
            "pamount": [
                {
                    "aprice": null,
                    "acommodity": "$",
                    "aquantity": {
                        "floatingPoint": -1,
                        "decimalPlaces": 10,
                        "decimalMantissa": -10000000000
                    },
                    "aismultiplier": false,
                    "astyle": {
                        "ascommodityside": "L",
                        "asdigitgroups": null,
                        "ascommodityspaced": false,
                        "asprecision": 2,
                        "asdecimalpoint": "."
                    }
                }
            ],
            "ptransaction_": "1",
            "paccount": "income:salary",
            "pdate": null,
            "ptype": "RegularPosting",
            "pcomment": "",
            "pdate2": null,
            "ptags": [],
            "poriginal": null
        }
    ],
    "ttags": [],
    "tsourcepos": {
        "tag": "JournalSourcePos",
        "contents": [
            "",
            [
                1,
                1
            ]
        ]
    },
    "tdate": "2008-01-01",
    "tcode": "",
    "tindex": 1,
    "tprecedingcomment": "",
    "tdate2": null,
    "tdescription": "income",
    "tstatus": "Unmarked"
}
```

And here's how to test adding it with curl. This should add a new entry to your journal:

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
