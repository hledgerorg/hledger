# Export Lots workflow

In latest hledger (master), Ledger lot syntax is preserved in print's txt and beancount output.
This lets us export to other apps for lot and gains reports that hledger doesn't support yet.
Here are some notes on the process.

## hledger

### Export

Export just some investment transactions to report on. Eg:

    hledger print -x :vceb > vceb.j

Disable any balance assertions. Reason:
some unimportant opening balances may be missing,
also Ledger doesn't allow costs in balance assertions.

    sed -i -E -e 's/ =/  ;=/' vceb.j

Add an amountless rounding posting to each transaction. Reason:
all PTA apps have slightly different transaction balancing behaviour (alas),
this workaround allows them to agree that the transactions are balanced.
Because of -x above the resulting entries should be valid.

    awk '/^[0-9]/,/^$/{if(/^$/)print "    expenses:rounding"}1' vceb.j > vceb-tmp.j && mv vceb-tmp.j vceb.j

Make a copy without lot subaccounts, for comparison.

    hledger print --alias '/:2.*/=' > vceb-lotless.j

Make copies in beancount format.

    hledger -f vceb.j         print --alias revenues=Income -o vceb.beancount
    hledger -f vceb-lotless.j print --alias revenues=Income -o vceb-lotless.beancount

In the beancount files, convert @ COST to {LOTCOST} notation where appropriate.
Here we assume all costs are lot costs.

    sed -i -Ee 's/^ (.+) @ ([^;]+)/ \1 {\2}/'      vceb*.beancount
    sed -i -Ee 's/^ (.+) @@ ([^;]+)/ \1 \{\{\2}}/' vceb*.beancount

2. Add some market prices to both beancount files.


Or: use the Justfile in this directory, which combines the above commands.

    just export


### Reports

#### Lots

hledger can show lots if they are tracked with explicit accounts.
Eg this shows the current balance in each lot account
(and its cost if you append that to the account names):

    hledger -f vceb.j bs :2

#### Unrealised gain

    hledger -f vceb.j bal --gain

Shows unrealised gains, per account.
Accounts with zero gains will be hidden unless you add -E.

## Ledger

### Reports

#### Lots

    ledger -f vceb.j bal --lots --flat --no-total

Shows lotful balances as one or more lots, one per line, with their cost basis.
Ledger treats all balances transacted with a @ cost as lotful, so limit the report to lotful asset accounts.

    ledger -f vceb.j bal --lots --flat --no-total vg:vceb and not desc dividend
    ledger -f vceb.j bal --lots --flat --no-total vg:vceb and desc dividend

#### Unrealised gain

    ledger -f vceb.j bal --gain

Like hledger.
Gains from multiple lots within an account are shown as a single sum.

## Beancount

### Install

Using beancount 2 here for its bean-report command.

    pip install beancount==2.3.6

### Reports

#### Lots

    bean-report vceb.beancount balances

Shows balance change in each account.

    bean-report vceb.beancount holdings

Shows balance change, average cost, current market price, total cost and market value in each account.

    bean-report vceb-lotless.beancount holdings

Shows the same lots, still separate but now within one account, and probably in a different order.
"Average cost" seems to be just "lot cost".

## rustledger

### Install

    eget --all rustledger/rustledger --to /usr/local/bin

rustledger provides both `rledger-*` and `bean-*` executables.
I recommend renaming the latter to `rbean-*` to coexist with beancount.

Last tested: rustledger 0.4.0.

### Reports

#### Lots

    rbean-report vceb.beancount balances

Like beancount.

    rbean-report vceb.beancount holdings

Like beancount, but with more decimals, and does not show average cost, market price, market value.

    rbean-report vceb-lotless.beancount holdings

Shows the total units and total cost of the lots in each account.
