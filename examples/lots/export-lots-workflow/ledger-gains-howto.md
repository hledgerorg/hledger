# How to Report Realized Gains with Ledger

Generated: 2026-01-18, Claude

Ledger CLI handles realized gains through lot tracking and automatic gain/loss calculations. Here are the main approaches:

## Method 1: Automatic Lot Tracking (Recommended)

Ledger automatically tracks lots and calculates gains when you use lot prices:

```ledger
; Purchase with lot price
2024-01-01 Buy stock
    Assets:Brokerage:Stock         10 AAPL {$150.00}
    Assets:Brokerage:Cash         $-1500.00

; Sale - Ledger calculates gain automatically
2024-06-01 Sell stock
    Assets:Brokerage:Stock        -10 AAPL {$150.00} @ $170.00
    Assets:Brokerage:Cash          $1700.00
    Income:CapitalGains           ; Automatically calculated: -$200.00
```

The `{$150.00}` is the cost basis (lot price), and `@ $170.00` is the sale price.

## Method 2: Manual Gains Posting

You can explicitly record the gain:

```ledger
2024-06-01 Sell stock
    Assets:Brokerage:Stock        -10 AAPL {$150.00}
    Assets:Brokerage:Cash          $1700.00
    Income:CapitalGains:LongTerm   $-200.00
```

## Method 3: Using --lot-prices Flag

Enable lot tracking globally:

```bash
# Show all lots with their prices
ledger bal Assets:Brokerage:Stock --lot-prices

# Show gains/losses
ledger bal Income:CapitalGains
```

## Method 4: Specific Lot Selection

When you have multiple lots, specify which to sell:

```ledger
; Buy two lots
2024-01-01 Buy lot 1
    Assets:Brokerage:Stock         10 AAPL {$150.00}
    Assets:Brokerage:Cash

2024-02-01 Buy lot 2
    Assets:Brokerage:Stock         10 AAPL {$160.00}
    Assets:Brokerage:Cash

; Sell specific lot (lot 1)
2024-06-01 Sell from lot 1
    Assets:Brokerage:Stock        -10 AAPL {$150.00} @ $170.00
    Assets:Brokerage:Cash          $1700.00
    Income:CapitalGains:LongTerm

; Remaining balance shows only lot 2
```

## Method 5: Lot Notes/Tags for Tracking

Add lot metadata for better tracking:

```ledger
; Purchase with lot note
2024-01-01 Buy stock
    ; Purchase date: 2024-01-01
    ; Type: Long-term hold
    Assets:Brokerage:Stock         10 AAPL {$150.00}
    Assets:Brokerage:Cash

2024-06-01 Sell stock
    ; Holding period: 5 months (short-term)
    Assets:Brokerage:Stock        -10 AAPL {$150.00} @ $170.00
    Assets:Brokerage:Cash          $1700.00
    Income:CapitalGains:ShortTerm
```

## Reporting Realized Gains

### Basic Balance Report

```bash
# Show all capital gains
ledger bal Income:CapitalGains

# Show gains with subaccounts
ledger bal Income:CapitalGains --flat
```

### Register Report (Transaction Detail)

```bash
# Show all capital gains transactions
ledger reg Income:CapitalGains

# Show gains for specific year
ledger reg Income:CapitalGains --begin 2024/01/01 --end 2024/12/31

# Show with running total
ledger reg Income:CapitalGains --subtotal
```

### Gains by Period

```bash
# Monthly gains
ledger reg Income:CapitalGains --monthly

# Quarterly gains
ledger reg Income:CapitalGains --quarterly

# Yearly gains
ledger reg Income:CapitalGains --yearly
```

### Show Lot Details

```bash
# Show current lots with their cost basis
ledger bal Assets:Brokerage:Stock --lot-prices --lots

# Show lot dates
ledger bal Assets:Brokerage:Stock --lot-dates

# Show both
ledger bal Assets:Brokerage:Stock --lot-prices --lot-dates --lots
```

### Gains by Security

```bash
# Filter by commodity
ledger reg Income:CapitalGains and @AAPL

# Show multiple securities
ledger bal Income:CapitalGains --group-by commodity
```

## Account Structure for Gains

```ledger
; Account declarations (optional but recommended)
account Income:CapitalGains:ShortTerm
account Income:CapitalGains:LongTerm
account Income:CapitalGains:Crypto

; Or use automated postings to categorize
= expr account =~ /Income:CapitalGains/ and commodity =~ /AAPL/
    ; Tag: stock=AAPL
```

## Complete Example with Multiple Lots

```ledger
; Account setup
2020-01-01 * Opening balances
    Assets:Brokerage:Cash         $10000.00
    Equity:OpeningBalances

; Buy lots
2023-01-15 * Buy AAPL lot 1
    Assets:Brokerage:Stock         10 AAPL {$150.00}
    Assets:Brokerage:Cash

2023-06-01 * Buy AAPL lot 2
    Assets:Brokerage:Stock          5 AAPL {$160.00}
    Assets:Brokerage:Cash

; Sell specific lot
2024-03-01 * Sell AAPL (short-term gain)
    ; Holding period: < 1 year
    Assets:Brokerage:Stock        -10 AAPL {$150.00} @ $170.00
    Assets:Brokerage:Cash          $1700.00
    Income:CapitalGains:ShortTerm

; Check remaining position
; Should show: 5 AAPL {$160.00}
```

## Using Automated Postings for Categorization

```ledger
; Automatically categorize short-term vs long-term
; (requires manual tagging in transactions)

= expr tag("holding") =~ /short/
    Income:CapitalGains:ShortTerm

= expr tag("holding") =~ /long/
    Income:CapitalGains:LongTerm
```

Then in transactions:

```ledger
2024-06-01 * Sell stock
    ; holding: short
    Assets:Brokerage:Stock        -10 AAPL {$150.00} @ $170.00
    Assets:Brokerage:Cash
    Income:CapitalGains
```

## Advanced: Using --gain Flag

Ledger has a `--gain` flag to show only capital gains:

```bash
# Show only the gain/loss portion of transactions
ledger reg --gain Assets:Brokerage:Stock

# Show unrealized gains (current market value vs cost basis)
ledger bal Assets:Brokerage:Stock --market --gain
```

## Exporting Gains for Tax Reporting

### CSV Export

```bash
# Export capital gains to CSV
ledger csv Income:CapitalGains --begin 2024 --end 2025 > gains_2024.csv
```

### Custom Format

```bash
# Custom format for tax software
ledger reg Income:CapitalGains \
  --begin 2024 --end 2025 \
  --format '%(format_date(date, "%Y-%m-%d")),%(payee),%(display_amount)\n' \
  > gains_2024.txt
```

### Summary Report

```bash
# Summary by type
ledger bal Income:CapitalGains:ShortTerm Income:CapitalGains:LongTerm \
  --begin 2024 --end 2025 \
  --format '%(account) %(total)\n'
```

## Unrealized Gains

Show unrealized gains (current market value vs cost basis):

```bash
# Add current market prices first
P 2024-12-31 AAPL $180.00

# Show unrealized gains
ledger bal Assets:Brokerage:Stock --market --gain --now 2024-12-31

# Or use --unrealized flag
ledger bal Assets:Brokerage:Stock --unrealized
```

## Ledger Configuration for Gains Tracking

Add to `~/.ledgerrc`:

```ledger
; Always show lot prices for investment accounts
--lot-prices

; Show lot dates
--lot-dates

; Use FIFO by default
--lot-price FIFO

; Or specify lot selection method
; --lot-price LIFO
; --lot-price AVERAGE
```

## Query Examples

```bash
# Total realized gains for year
ledger bal Income:CapitalGains --begin 2024 --end 2025

# Gains by security
ledger reg Income:CapitalGains --group-by commodity

# Gains by month
ledger reg Income:CapitalGains --monthly --begin 2024

# Show transactions with gains over $1000
ledger reg Income:CapitalGains 'expr amount > 1000'

# Show only long-term gains
ledger bal Income:CapitalGains:LongTerm

# Compare short-term vs long-term
ledger bal Income:CapitalGains --depth 2
```

## Lot Selection Methods

Ledger supports different lot selection methods:

```bash
# FIFO (First In, First Out) - default
ledger bal Assets:Brokerage:Stock --lot-price FIFO

# LIFO (Last In, First Out)
ledger bal Assets:Brokerage:Stock --lot-price LIFO

# By specific lot price (must match exactly)
# Specified in the transaction itself with {$price}
```

## Wash Sale Tracking

Track wash sales with tags:

```ledger
2024-03-01 * Sell AAPL at loss
    ; wash-sale-candidate: yes
    Assets:Brokerage:Stock        -10 AAPL {$170.00} @ $150.00
    Assets:Brokerage:Cash          $1500.00
    Income:CapitalGains:Loss       $200.00

2024-03-15 * Buy AAPL within 30 days
    ; wash-sale: yes, disallowed-loss: $200.00
    Assets:Brokerage:Stock         10 AAPL {$155.00}
    Assets:Brokerage:Cash
```

Query wash sales:

```bash
ledger reg tag wash-sale
```

## Summary

**Best practices:**
1. **Always use lot prices** with `{$price}` on purchases
2. **Specify sale price** with `@ $price` on sales
3. **Let Ledger calculate gains** automatically (leave posting blank)
4. **Separate short-term and long-term** gains for tax purposes
5. **Use `--lot-prices` flag** to see lot details
6. **Track lots with dates** for holding period calculations
7. **Tag transactions** for wash sale tracking

**Key Ledger features:**
- Automatic gain/loss calculation
- Multiple lot tracking
- Flexible lot selection (FIFO/LIFO)
- `--gain` flag for gain-only reports
- `--market` flag for current valuations
- `--unrealized` flag for paper gains

**Syntax:**
- `{$price}` = cost basis (lot price)
- `@ $price` = sale price (per-unit)
- `@@ $total` = sale price (total)
- No amount = automatically calculated (including gains)
