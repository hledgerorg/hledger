# Converting Open Collective CSV

Here are notes on Open Collective's CSV (as of 2025-12, based on hledger's open collective).

On the Transactions screen, first remove any filters so that all transactions will be exported, including:

- Contribution (incoming or outgoing)
- Expense
- Host fee
- Payment processor cover
- Payment processor fee

Eg: <https://opencollective.com/hledger/transactions?kind=ALL>

When you click the Export CSV button, two CSV formats are offered:

- Legacy Platform Default (Pre-2024)  (we'll call it Legacy)
- Platform Default                    (we'll call it Default)

Each has three options:

- Selected fields for export - about 25 reorderable fields; we'll assume the default order.
  (It says "out of 85", suggesting there might be more available, but if so they're not accessible to a normal collective admin.)
- Use field IDs as column headers instead of field names - normally on for Legacy and off for Default.
- Export taxes and payment processor fees as columns - ditto.

Additionally, the data available varies by era:

- Host fee records start in 2021-06.
- With the "as columns" option on, payment processor fees are available for all eras. Otherwise, processor fee records start in 2024-01.
- Payment processor cover records start in 2024-01.

In eras where fees are not available, contribution amounts can be under-reported.
Eg, a $10 contribution with a $1 host fee and $0.59 payment processor fee might be reported as just a $8.41 contribution.

Here are the formats we provide rules for, and their limitations:

| format                    | accurate contribution amounts?      | host fees?                            | processor fees? | processor covers? | balances?           | notes                                       | rules file                   |
|---------------------------|-------------------------------------|---------------------------------------|-----------------|-------------------|---------------------|---------------------------------------------|------------------------------|
| Legacy                    | yes                                 | from 2021/06 (inferrable before then) | yes             | from 2024         | yes; some are wrong | provides the most data across all eras      | opencollective-legacy.rules  |
| Default + fees as columns | from 2024 (inferrable from 2021/06) | from 2021/06                          | yes             | from 2024         | no                  | simplest if you have no data before 2021-06 | opencollective-columns.rules |
| Default                   | from 2024                           | from 2021/06                          | from 2024       | from 2024         | no                  | simplest if you have no data before 2024    | opencollective-default.rules |

Note to get accurate pre-2024 contributions and fees, or balance information, the Legacy format is needed.
opencollective-legacy.rules is the best-tested of these rules files.

## How to test your conversion

### CSV balance column

If you are using the legacy format, you can use the balance column to generate hledger balance assertions.
Though in some record types (eg contributions after 2021-06, and expenses) the balance values may be out of sequence; those should be ignored.

Then, hledger should agree with Open Collective's balances; check with `hledger check assertions` or `hledger check -s`.

### Budget stats

In the Budget section on the collective's page (eg <https://opencollective.com/hledger#category-BUDGET>),
you can see some calculated values (and a few more if you mouse over), listed below.
Some of these can be reproduced by the hledger reports shown.
(If you have used the legacy format and the provided rules; or if your data begins in 2024 or later.
Tested with the hledger collective.)
  
#### Today's balance

`hledger bs`

#### Total consolidated including Projects and Events

#### Total raised

`hledger is not:disbursed` *? not reproduced yet*

#### Total contributed before fees

`hledger is revenues`

#### Total disbursed

`hledger is disbursed` *? not reproduced yet*

#### Estimated annual budget

#### Monthly recurring

#### Total received in the last 12 months

`hledger is revenues -b $(date -I -d '-12 months')`
