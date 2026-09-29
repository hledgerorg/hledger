# How to Report Realized Gains with Rustledger

Generated: 2026-01-18, Claude

Rustledger is a [pure Rust implementation of Beancount](https://github.com/rustledger/rustledger) that serves as a drop-in replacement, claiming to be 10x faster while maintaining 100% compatibility with Beancount file format. Since rustledger uses the **same Beancount syntax and file format**, the capital gains tracking methods are identical to Beancount.

## Important Note

**Rustledger uses Beancount file format** - all the syntax, methods, and approaches are the same as Beancount. See `beancount-gains-howto.md` in this directory for detailed examples.

The key difference is that rustledger provides:
- **Faster performance** (10x faster than Python Beancount)
- **Single binary** (no Python dependencies)
- **100% compatibility** with existing `.beancount` files
- **Rust-based commands** with `rledger-` prefix (e.g., `rledger-check`, `rledger-query`)

## Quick Start with Rustledger

### Installation

```bash
# Using Cargo
cargo install rustledger

# Using Homebrew (macOS)
brew install rustledger

# Using Nix
nix-shell -p rustledger

# Using Docker
docker pull ghcr.io/rustledger/rustledger
```

### Available Commands

Rustledger provides these commands (compatible with `bean-*` commands):

- `rledger-check` - Validate ledger files with detailed error messages
- `rledger-query` - Run BQL (Beancount Query Language) queries
- `rledger-format` - Auto-format beancount files
- `rledger-report` - Generate balance, account, and statistics reports
- `rledger-doctor` - Debugging tools for ledger issues
- `rledger-extract` - Import transactions from CSV/OFX bank statements
- `rledger-price` - Fetch commodity prices from online sources

For compatibility, you can also use `bean-check`, `bean-query`, etc.

## Realized Gains Tracking

Since rustledger uses Beancount syntax, use the same methods as Beancount:

### Method 1: Explicit Gains Postings

```beancount
; Purchase
2024-01-01 * "Buy stock"
  Assets:Brokerage:Stock    10 AAPL {150.00 USD}
  Assets:Brokerage:Cash    -1500.00 USD

; Sale with explicit gain
2024-06-01 * "Sell stock"
  Assets:Brokerage:Stock    -10 AAPL {150.00 USD}
  Assets:Brokerage:Cash      1700.00 USD
  Income:CapitalGains:LongTerm  -200.00 USD
```

### Method 2: Automatic Gain Calculation

```beancount
; Purchase
2024-01-01 * "Buy stock"
  Assets:Brokerage:Stock    10 AAPL {150.00 USD}
  Assets:Brokerage:Cash

; Sale - rustledger calculates the gain
2024-06-01 * "Sell stock"
  Assets:Brokerage:Stock    -10 AAPL {150.00 USD} @ 170.00 USD
  Income:CapitalGains:LongTerm
  Assets:Brokerage:Cash      1700.00 USD
```

## Booking Methods

Rustledger supports seven booking methods:

```beancount
option "booking_method" "FIFO"   ; First In, First Out (default)
; Other options:
; "LIFO"    - Last In, First Out
; "HIFO"    - Highest Cost First
; "AVERAGE" - Average cost basis
; "STRICT"  - Strict booking (must specify lots)
; "NONE"    - No automatic booking
```

## Rustledger-Specific Plugins for Gains

### sellgains Plugin

Cross-check capital gains against sales:

```beancount
plugin "beancount.plugins.sellgains"

; Your transactions...
```

### unrealized Plugin

Calculate unrealized gains:

```beancount
plugin "beancount.plugins.unrealized" "Unrealized"

; This creates virtual entries showing unrealized gains
```

## Reporting with Rustledger

### Using rledger-query

```bash
# Show all realized gains
rledger-query myfile.beancount "
  SELECT account, sum(position)
  WHERE account ~ 'Income:CapitalGains'
  GROUP BY account
"

# Show gains by year
rledger-query myfile.beancount "
  SELECT year(date) as year, sum(position)
  WHERE account ~ 'Income:CapitalGains'
  GROUP BY year
"

# Interactive query mode
rledger-query myfile.beancount
```

### Using rledger-report

```bash
# Generate balance report
rledger-report myfile.beancount balances

# Account-specific report
rledger-report myfile.beancount account Income:CapitalGains

# Statistics report
rledger-report myfile.beancount statistics
```

### Using rledger-check

```bash
# Validate your file (checks balances, lots, etc.)
rledger-check myfile.beancount

# Verbose validation
rledger-check myfile.beancount --verbose
```

## Performance Advantage

Rustledger's main advantage is speed:

```bash
# Python Beancount might take several seconds on large files
time bean-check myfile.beancount

# Rustledger is ~10x faster on the same file
time rledger-check myfile.beancount
```

This is especially valuable for:
- Large journals with many transactions
- Complex lot tracking with many securities
- Frequent validation during data entry
- Automated reporting pipelines

## Complete Example

```beancount
option "operating_currency" "USD"
option "booking_method" "FIFO"

plugin "beancount.plugins.sellgains"
plugin "beancount.plugins.unrealized" "Unrealized"

2020-01-01 open Assets:Brokerage:Cash         USD
2020-01-01 open Assets:Brokerage:Stock        AAPL
2020-01-01 open Income:CapitalGains:LongTerm  USD
2020-01-01 open Income:CapitalGains:ShortTerm USD

; Purchase lots
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

; Balance assertion to verify
2024-03-01 balance Assets:Brokerage:Stock  5 AAPL
```

Validate and query:

```bash
# Check the file
rledger-check example.beancount

# Query capital gains
rledger-query example.beancount "
  SELECT account, sum(position)
  WHERE account ~ 'CapitalGains'
  GROUP BY account
"

# Generate report
rledger-report example.beancount balances
```

## Migration from Python Beancount

If you're already using Python Beancount:

1. **No changes needed** - Your `.beancount` files work as-is
2. **Replace commands** - Use `rledger-*` instead of `bean-*`
3. **Same queries** - BQL queries work identically
4. **Same plugins** - Most Beancount plugins are supported
5. **Faster performance** - Expect ~10x speed improvement

## Export for Tax Reporting

```bash
# Export to CSV using query
rledger-query file.beancount "
  SELECT date, narration, position
  WHERE account = 'Income:CapitalGains:LongTerm'
    AND year = 2024
  ORDER BY date
" --output-format csv > gains_2024.csv
```

## Differences from Python Beancount

While rustledger is 100% compatible, there are some implementation differences:

1. **Performance** - ~10x faster than Python Beancount
2. **Single binary** - No Python runtime required
3. **Command names** - `rledger-*` instead of `bean-*` (though `bean-*` aliases work)
4. **Plugin support** - Most common plugins supported, some obscure ones may not work
5. **Error messages** - May differ slightly in format/detail

## Resources

- **Official Website**: [rustledger.github.io](https://rustledger.github.io/)
- **GitHub Repository**: [github.com/rustledger/rustledger](https://github.com/rustledger/rustledger)
- **Beancount Documentation**: Since rustledger uses Beancount format, refer to [Beancount docs](https://beancount.github.io/docs/)
- **Plain Text Accounting**: [plaintextaccounting.org](https://plaintextaccounting.org/)

## Summary

**For realized gains tracking with rustledger:**

1. Use **Beancount syntax** (see `beancount-gains-howto.md`)
2. Specify **cost basis** with `{price}` on purchases
3. Use **booking methods** (FIFO, LIFO, HIFO, etc.)
4. Enable **sellgains plugin** for validation
5. Query with **rledger-query** (same BQL syntax as Beancount)
6. Enjoy **10x faster** performance on large files

**Key syntax:**
- `{$150.00 USD}` = cost basis (lot price)
- `@ $170.00 USD` = sale price (per-unit)
- `booking_method` = FIFO, LIFO, HIFO, AVERAGE, STRICT
- `plugin "beancount.plugins.sellgains"` = validate capital gains

Since rustledger is a drop-in replacement for Beancount, all Beancount tutorials and documentation for capital gains apply directly to rustledger.

---

**Sources:**
- [Rustledger Official Site](https://rustledger.github.io/)
- [Rustledger GitHub Repository](https://github.com/rustledger/rustledger)
- [Plain Text Accounting](https://plaintextaccounting.org/)
