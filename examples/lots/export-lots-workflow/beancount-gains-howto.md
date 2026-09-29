# How to Report Realized Gains with Beancount

Generated: 2026-01-18, Claude

Beancount handles realized gains through explicit postings using booking methods and lot selection. Here are the main approaches:

## Method 1: Explicit Gains/Losses Postings (Manual)

```beancount
; Purchase
2024-01-01 * "Buy stock"
  Assets:Brokerage:Stock    10 AAPL {150.00 USD}
  Assets:Brokerage:Cash    -1500.00 USD

; Sale with explicit gain
2024-06-01 * "Sell stock"
  Assets:Brokerage:Stock    -10 AAPL {150.00 USD}  ; Original cost basis
  Assets:Brokerage:Cash      1700.00 USD            ; Sale proceeds
  Income:CapitalGains:LongTerm  -200.00 USD        ; Realized gain
```

The gain posting is calculated as: Sale proceeds - Cost basis = $1700 - $1500 = $200

## Method 2: Using Price Conversions (Automatic)

Beancount can automatically calculate gains when you sell at a different price:

```beancount
; Purchase with cost basis
2024-01-01 * "Buy stock"
  Assets:Brokerage:Stock    10 AAPL {150.00 USD}
  Assets:Brokerage:Cash

; Sale - Beancount infers the gain
2024-06-01 * "Sell stock"
  Assets:Brokerage:Stock    -10 AAPL {150.00 USD} @ 170.00 USD
  Income:CapitalGains:LongTerm
  Assets:Brokerage:Cash      1700.00 USD
```

The `@ 170.00 USD` indicates the sale price, and Beancount calculates the gain.

## Method 3: Plugin for Automatic Gains Booking

Beancount has plugins to automatically book capital gains. Add to your main file:

```beancount
plugin "beancount.plugins.implicit_prices"
plugin "beancount.plugins.unrealized"
```

Or use the `booking` module:

```beancount
option "booking_method" "FIFO"  ; or "LIFO", "AVERAGE", "STRICT"
```

Then your transactions can be simpler:

```beancount
2024-01-01 * "Buy"
  Assets:Brokerage:Stock    10 AAPL {150.00 USD}
  Assets:Brokerage:Cash

2024-06-01 * "Sell"
  Assets:Brokerage:Stock    -10 AAPL {} @ 170.00 USD
  Assets:Brokerage:Cash      1700.00 USD
  Income:CapitalGains       ; Amount calculated automatically
```

The `{}` means "use automatic lot selection based on booking method".

## Method 4: Explicit Lot Selection

For specific lot selection (not FIFO):

```beancount
; Buy two lots
2024-01-01 * "Buy lot 1"
  Assets:Brokerage:Stock    10 AAPL {150.00 USD, 2024-01-01}
  Assets:Brokerage:Cash

2024-02-01 * "Buy lot 2"
  Assets:Brokerage:Stock    10 AAPL {160.00 USD, 2024-02-01}
  Assets:Brokerage:Cash

; Sell specific lot (lot 1)
2024-06-01 * "Sell from lot 1"
  Assets:Brokerage:Stock    -10 AAPL {150.00 USD, 2024-01-01} @ 170.00 USD
  Assets:Brokerage:Cash      1700.00 USD
  Income:CapitalGains:LongTerm  -200.00 USD
```

## Reporting Realized Gains

### Using bean-query

```bash
# Show all realized gains
bean-query myfile.beancount "
  SELECT account, sum(position)
  WHERE account ~ 'Income:CapitalGains'
  GROUP BY account
"

# Show gains by year
bean-query myfile.beancount "
  SELECT year(date) as year, sum(position)
  WHERE account ~ 'Income:CapitalGains'
  GROUP BY year
"

# Show specific lot sales
bean-query myfile.beancount "
  SELECT date, narration, position
  WHERE account ~ 'Income:CapitalGains'
  ORDER BY date
"
```

### Using bean-report

```bash
# Income statement (includes capital gains)
bean-report myfile.beancount income

# Journal entries for capital gains
bean-report myfile.beancount journal -a Income:CapitalGains

# Balance of capital gains account
bean-report myfile.beancount balances -a Income:CapitalGains
```

### Using fava (web interface)

```bash
# Install fava
pip install fava

# Run web interface
fava myfile.beancount

# Navigate to:
# - Income Statement -> See Capital Gains
# - Account -> Income:CapitalGains -> See all transactions
```

## Account Structure for Gains

```beancount
; Open accounts for different gain types
2020-01-01 open Income:CapitalGains:ShortTerm  USD
2020-01-01 open Income:CapitalGains:LongTerm   USD
2020-01-01 open Income:CapitalGains:Crypto     USD

; Or simpler
2020-01-01 open Income:CapitalGains  USD
```

## Complete Example with Multiple Lots

```beancount
option "operating_currency" "USD"
option "booking_method" "FIFO"

2020-01-01 open Assets:Brokerage:Cash         USD
2020-01-01 open Assets:Brokerage:Stock        AAPL
2020-01-01 open Income:CapitalGains:LongTerm  USD
2020-01-01 open Income:CapitalGains:ShortTerm USD

; Buy lots
2023-01-15 * "Buy AAPL lot 1"
  Assets:Brokerage:Stock    10 AAPL {150.00 USD}
  Assets:Brokerage:Cash     -1500.00 USD

2023-06-01 * "Buy AAPL lot 2"
  Assets:Brokerage:Stock    5 AAPL {160.00 USD}
  Assets:Brokerage:Cash     -800.00 USD

; Sell - FIFO means lot 1 is sold first
2024-03-01 * "Sell AAPL (short-term gain)"
  Assets:Brokerage:Stock    -10 AAPL {150.00 USD} @ 170.00 USD
  Assets:Brokerage:Cash      1700.00 USD
  Income:CapitalGains:ShortTerm  -200.00 USD

; Check remaining position
2024-03-01 balance Assets:Brokerage:Stock  5 AAPL
```

## Using unrealized gains plugin

To see unrealized gains (for reporting, not for tax):

```beancount
plugin "beancount.plugins.unrealized" "Unrealized"

; This creates virtual entries showing unrealized gains
; based on current market prices
```

## Query Examples

```bash
# Total realized gains this year
bean-query file.beancount "
  SELECT sum(position)
  WHERE account ~ 'Income:CapitalGains'
    AND year = 2024
"

# Gains by security
bean-query file.beancount "
  SELECT currency, sum(convert(position, 'USD')) as gain
  WHERE account ~ 'CapitalGains'
  GROUP BY currency
  ORDER BY gain DESC
"

# Long-term vs short-term
bean-query file.beancount "
  SELECT account, sum(position)
  WHERE account ~ 'Income:CapitalGains'
  GROUP BY account
"
```

## Export for Tax Reporting

```bash
# Export to CSV for tax software
bean-query file.beancount "
  SELECT date, narration, position
  WHERE account = 'Income:CapitalGains:LongTerm'
    AND year = 2024
  ORDER BY date
" --output-format csv > gains_2024.csv
```

## Summary

**Best practices:**
1. **Always specify cost basis** with `{cost}` on purchases
2. **Use explicit lot selection** or set a `booking_method`
3. **Separate long-term and short-term** gains for tax purposes
4. **Use bean-query** for flexible reporting
5. **Consider using fava** for visual reporting
6. **Track lots with dates** for wash sale and holding period tracking

The key difference from hledger: Beancount requires **explicit cost basis** tracking with `{}` syntax and calculates gains automatically when you sell at a different price with `@`.
