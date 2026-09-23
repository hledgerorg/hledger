m4_dnl m4 helpers and common text used in hledger docs (the manuals, mainly).
m4_dnl When Shake.hs docs scripts use m4, they always load this file first.
m4_dnl
m4_dnl `m4_dnl` ignores the rest of the line, including the newline.
m4_dnl Avoid blank lines or stray newlines in this file, unless inside a macro.
m4_dnl Add single quotes where needed to help vscode's highlighting. '
m4_dnl
m4_dnl
m4_dnl Set {{ }} as our m4 quoting delimiters:
m4_dnl
m4_changequote({{,}})m4_dnl
m4_dnl
m4_dnl
m4_dnl Easier macros for including/excluding content based on output format:
m4_dnl
m4_define({{_man_}},         m4_ifdef({{MANFORMAT}},{{$1}})    )m4_dnl
m4_define({{_notman_}},      m4_ifdef({{MANFORMAT}},,{{$1}})   )m4_dnl
m4_define({{_info_}},        m4_ifdef({{INFOFORMAT}},{{$1}})   )m4_dnl
m4_define({{_notinfo_}},     m4_ifdef({{INFOFORMAT}},,{{$1}})  )m4_dnl
m4_define({{_web_}},         m4_ifdef({{WEBFORMAT}},{{$1}})    )m4_dnl
m4_define({{_notweb_}},      m4_ifdef({{WEBFORMAT}},,{{$1}})   )m4_dnl
m4_dnl
m4_dnl
m4_dnl Author name for pandoc metadata in manuals, affecting man pages. Currently left blank.
m4_dnl
m4_define({{_author_}}, {{}})m4_dnl
m4_dnl
m4_dnl
m4_dnl A general hledger description used at the start of the manuals.
m4_dnl
m4_define({{_hledgerdescription_}}, {{
hledger is a robust, user-friendly, cross-platform set of programs
for tracking money, time, or any other commodity,
using double-entry accounting and a simple, editable file format.
hledger is inspired by and largely compatible with ledger(1),
and largely interconvertible with beancount(1). }} )m4_dnl
m4_dnl
m4_dnl
m4_dnl A short description of hledger's input files, used in the manuals. '
m4_dnl
m4_define({{_inputfiles_}},
{{reads from (and appends to) a journal file specified by the `LEDGER_FILE` environment variable
(defaulting to `$HOME/.hledger.journal`); or you can specify files with `-f` options.
It can also read timeclock files, timedot files, or any CSV/SSV/TSV file with a date field.}} )m4_dnl
m4_dnl
m4_dnl
m4_dnl The above text plus a pointer to the more detailed hledger manual section.
m4_dnl Used in the ui/web manuals.
m4_dnl
m4_define({{_inputfileswithptr_}},
{{_inputfiles_
(See hledger(1) -> Input for details.)}} )m4_dnl
m4_dnl
m4_dnl
m4_dnl Bug reporting info for the manuals' BUGS sections. '
m4_dnl
m4_define({{_reportbugs_}},
{{We welcome bug reports in the hledger issue tracker (<https://bugs.hledger.org>),
or on the hledger chat or mail list (<https://hledger.org/support>).}} )m4_dnl
m4_dnl
m4_dnl
m4_dnl A copy of the general options help shown by `hledger --help`. Used in the three manuals.
m4_dnl To make changes: update the flag definitions at top of CliOptions.hs,
m4_dnl then run `just generaloptionshelp` to regenerate this from the build's --help output. '
m4_dnl Do this always before release, and more often if needed to update
m4_dnl the manual within dev builds and at https://hledger.org/dev/hledger.html#options.
m4_dnl
m4_define({{_generaloptions_}}, {{
```
General input flags:
  -f --file=[FMT:]FILE      Use this as the journal file (- means stdin). If
                            not specified, $LEDGER_FILE or ~/.hledger.journal
                            will be used. If specified more than once, the
                            files will be read in order. Each file's format
                            (journal, csv, timeclock, timedot, rules..) is
                            inferred from the file extension or a FMT: prefix.
                            Some commands (add, import) write to the (first)
                            file, and expect it to be in journal format.
     --rules=RULESFILE      Use rules defined in this rules file for
                            converting subsequent CSV/SSV/TSV files. If not
                            specified, uses FILE.csv.rules for each FILE.csv.
     --alias=A=B|/RGX/=RPL  transform account names from A to B, or by
                            replacing regular expression matches
     --auto                 generate extra postings by applying auto posting
                            rules ("=") to all transactions
     --forecast[=PERIOD]    Generate extra transactions from periodic rules
                            ("~"), from after the latest ordinary transaction
                            until 6 months from now. Or, during the specified
                            PERIOD (the equals is required). Auto posting rules
                            will also be applied to these transactions. In
                            hledger-ui, also make future-dated transactions
                            visible at startup.
     --ignore-assertions    don't check balance assertions by default
     --ignore-lots          don't do lot tracking or checking by default
  -I                        shortcut for --ignore-assertions --ignore-lots
     --txn-balancing=...    how to check that transactions are balanced:
                            'old':   - use global display precision
                            'exact': - use transaction precision (default)
     --infer-costs          infer costs from conversion equity postings
     --infer-equity         infer conversion equity postings from costs
     --infer-market-prices  infer market prices from costs
     --pivot=TAGNAME        use a different field or tag as account names
  -s --strict               do extra error checks (and override -I)

General output flags (affecting some commands):
  -b --begin=DATE           include postings/transactions on/after this date
  -e --end=DATE             include postings/transactions before this date
                            (with a report interval, will be adjusted to
                            following subperiod end)
  -D --daily                set report interval: 1 day
  -W --weekly               set report interval: 1 week
  -M --monthly              set report interval: 1 month
  -Q --quarterly            set report interval: 1 quarter
  -Y --yearly               set report interval: 1 year
  -p --period=PERIODEXP     set begin date, end date, and/or report interval,
                            with more flexibility
     --today=DATE           override today's date (affects relative dates)
     --date2                match/use secondary dates instead (deprecated)
  -U --unmarked             include only unmarked postings/transactions
  -P --pending              include only pending postings/transactions
  -C --cleared              include only cleared postings/transactions
                            (-U/-P/-C can be combined)
  -R --real                 include only non-virtual postings
  -E --empty                Show zero items, which are normally hidden.
                            In hledger-ui & hledger-web, do the opposite.
     --depth=DEPTHEXP       if a number (or -NUM): show only top NUM levels
                            of accounts. If REGEXP=NUM, only apply limiting to
                            accounts matching the regular expression.
  -B --cost                 convert amounts to their cost/sale amount (@/@@)
  -V --market               valuation mode: show amounts converted to market
                            value at period end(s) in their default valuation
                            commodity. Short for --value=end.
  -X --exchange=COMM        valuation mode: show amounts converted to market
                            value at period end(s) in the specified commodity.
                            Short for --value=end,COMM.
     --value=WHEN[,COMM]    valuation mode: show amounts converted to market
                            value on the specified date(s) in their default
                            valuation commodity or a specified commodity. WHEN
                            can be:
                            'then':     value on transaction dates
                            'end':      value at period end(s)
                            'now':      value today
                            YYYY-MM-DD: value on given date
     --lots                 show lot subaccounts and other lot details
  -c --commodity-style=S    Override a commodity's display style.
                            Eg: -c '$1000.' or -c '1.000,00 EUR'
     --pretty[=YN]          Use box-drawing characters in text output? The
                            optional 'y'/'yes' or 'n'/'no' arg requires =.
     --title=T              set or customise a report title
     --subreport-titles=TS  customise subreport headings in compound reports
                            (|-separated)
     --period-titles=OPT    customise headings in periodic reports:
                            'compact': readable period names when possible
                            'dates':   exact dates/date ranges always

General help flags:
  -?                        show the hledger quick reference
  -h --help                 show this command's usage help
     --info                 show this command's manual with info
     --man                  show this command's manual with man
     --webman               show this command's manual on the web
     --examples             show examples for this command
     --version              show version information
     --debug=[1-9]          show this much debug output (default: 1)
     --pager=YN             use a pager when needed ? y/yes (default) or n/no
     --color=YNA --colour   use ANSI color ? y/yes, n/no, or auto (default)
     --lang=LANG            language for report titles and headings: a
                            language tag like de, auto (from the environment),
                            or en (default)
```
}} )m4_dnl '
