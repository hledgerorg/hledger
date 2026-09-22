## check

Check for various kinds of errors in your data. 

```flags
Flags:
no command-specific flags
```

hledger provides a number of built-in correctness checks to help validate your data and prevent errors.
Some are run automatically, some when you enable `--strict` mode;
or you can run any of them on demand by providing them as arguments to the `check` command.
`check` produces no output and a zero exit code if all is well.
Eg:

```cli
hledger check                      # run default checks
hledger check -s                   # run default and strict checks
hledger check ordereddates payees  # run default checks and two others
```

If you are an Emacs user, you can also configure flycheck-hledger to run these checks,
providing instant feedback as you edit the journal.

Here are the checks currently available.
They are generally checked in the order they are shown here, and only the first failure will be reported.

### Default checks

These important checks are performed by default, by almost all hledger commands:

- **parseable** - data files are in a supported [format](#data-formats),
  with no syntax errors and no invalid include directives.
  This ensures that all files exist and are readable.

- **autobalanced** - all transactions are [balanced](#postings),
  after automatically inferring missing amounts and conversion rates
  and then converting  amounts to cost.
  This ensures that each transaction's journal entry is well formed.

- **assertions** - all balance assertions in the journal are passing.
  [Balance assertions] are a strong defense against errors, catching many problems.
  This check is on by default, but if it gets in your way, you can disable it temporarily
  with `-I` or `--ignore-assertions`, or as a default by adding that flag to your config file.
  If you put it in your config file, you can override that with `-s`/`--strict` or `hledger check lots`.
  When a journal has both kinds of problem, lot errors are reported before assertion failures.

- **lots** - all [lot](#lot-reporting) entries are valid.
  Checks lot posting classifications, lot movements, and that any user-written
  realised gain amount on a disposal matches the calculated gain.
  This check can be disabled by `-I` or `--ignore-lots`.
  If you put it in your config file, you can override that with `-s`/`--strict` or `hledger check lots`.

### Strict checks

When the `-s`/`--strict` flag is used (AKA [strict mode]), all commands will perform the following additional checks.
These provide extra error-catching power to help you keep your data clean and correct:

- **balanced** - like `autobalanced`, but implicit conversions between commodities are not allowed;
  all conversion transactions must use [cost notation](#recording-costs) or [equity postings](#equity-conversion-postings).
  This prevents wrong conversions caused by typos.

- **commodities** - all commodity symbols used must be [declared](#commodity-error-checking).
  This guards against mistyping or omitting commodity symbols.

- **accounts** - all account names used must be [declared](#account-error-checking).
  This prevents the use of mis-spelled or outdated account names.
  (Except lot subaccounts, like `:{2026-01-15, $50}`, which are automatically exempt;
  only their base account needs to be declared.)

Also, strict mode ensures that the `assertions` and `lots` checks run (overriding their ignore flags).

### Other checks

These are not wanted by everyone, but can be run using the `check` command:

- **tags** - all tags used must be [declared](#tag-directive).
  This prevents mis-spelled tag names.
  Note hledger fairly often finds unintended tags in comments.

- **payees** - all payees used in transactions must be [declared](#payee-directive).
  This will force you to declare any new payee name before using it.
  Most people will probably find this a bit too strict.

- **ordereddates** - within each file, transactions must be ordered by date.
  This is a simple and effective error catcher. It's not included in strict mode,
  but you can add it by running `hledger check -s ordereddates`.
  If enabled, this check is performed before balance assertions.

- **recentassertions** - all accounts with balance assertions must have one that's
  within the 7 days before their latest posting.
  This will encourage adding balance assertions for your active asset/liability accounts,
  which in turn should encourage you to reconcile regularly with those real world balances -
  another strong defense against errors.
  ([`hledger close --assert >>$LEDGER_FILE`](#close---assert) is a convenient way to add new balance assertions.
  Later these become quite redundant, and you might choose to remove them to reduce clutter.)

- **uniqueleafnames** - no two accounts may have the same last account name part
  (eg the `checking` in `assets:bank:checking`).
  This ensures each account can be matched by a unique short name, easier to remember and to type.

- **basis** - all lot acquisitions set a per-unit basis equal to the per-unit transacted cost.
  This guards against typos in cost basis amounts causing wrong capital gain calculation at disposal time.
  It also enforces hledger's preferred style of "basis cost = transacted cost, with any real difference (as in gifts, NSO, RSU, etc) funded by a separate posting",
  rather than expressing the difference as a {B} @ T mismatch.

### Custom checks

You can build your own custom checks with [add-on command scripts].
See also [Cookbook > Scripting](scripting.html).
Here are some examples from [hledger/bin/](https://github.com/hledgerorg/hledger/tree/main/bin):

- **hledger-check-tagfiles** - all tag values containing `/` exist as file paths

- **hledger-check-fancyassertions** - more complex balance assertions are passing


[add-on command scripts]:    #add-on-commands
[balance assertions]: #balance-assertions
[strict mode]:        #strict-mode
[costs]: #costs
