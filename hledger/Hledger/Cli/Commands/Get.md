## get

Fetch new transactions and market prices for the journal,
by running `getdata` and `getprices` helper scripts.
New prices are merged into prices files automatically;
new transaction data is just saved, for later conversion & import by `import`.

```flags
Flags:
     --transactions         fetch transactions only
     --prices               fetch prices only
     --dry-run              just print the commands that would be run
```

By default, this command fetches both transactions and prices.

### Phase 1: transactions data

1. Creates a `data/` directory next to the main journal file, if it does not exist.
2. If the `data/getdata` helper script exists, runs it in the data directory,
   so it can save downloaded files (CSV/TSV/JSON/OFX/etc.) there.

### Phase 2: prices

1. Creates a `prices/` directory next to the main journal file, if it does not exist.
2. If the `prices/getprices` helper script exists,
   hledger first guesses the journal's base currency
   (the commodity most used as the target in P price directives;
   or if there are no P directives, the commodity most used in postings;
   or if there are no postings, "USD").
   Then for each other commodity in the journal, it fetches daily market prices in the base currency,
   from that commodity's earliest transaction until today,
   by running `getprices BASECUR COMM START END`.
   Each commodity's prices are merged into `prices/<COMM>.prices`, preserving existing prices.

Commands being run, and files being updated, are logged to stderr.
With `--dry-run`, you can preview the commands without running them.

### Merging new prices

Complete historical price data can be hard to get, so the prices phase is careful to preserve older prices.
If prices files already exist, the newly fetched prices will be merged as follows:

- Prices files will be updated only if they contain nothing but P directives (or blank lines).
- New prices for dates already seen are discarded. (So if you want to replace old prices, you must delete them before running `get`.)
- If no new prices remain to be added, the prices file is left as-is.
- Otherwise, the old prices plus the new prices are saved to the file, ordered by: date, from commodity, to commodity.
  Each price keeps the number format it was written with.

### get's helper scripts

Data downloading varies for everyone, and needs to be easily customisable, so it is done via helper scripts:

#### getdata

If you want `get` to download transaction data for you,
make your own `getdata` shell script (or executable program),
and install it in the `data` directory next to your main journal file.

It should download zero or more transaction data files into its current directory.
These are typically bank/brokerage CSV/TSV/SSV files, but could be anything that your hledger rules files can read.

#### getprices

If you want `get` to download historical market prices (useful for currency conversions, and value or gains reports),
install a `getprices` script in the `prices` directory next to your main journal file.

You can get one from the [hledger repo's bin directory](https://github.com/hledgerorg/hledger/tree/master/bin), and customise it if needed.
This script uses [pricehist](https://github.com/chrisberkhout/pricehist), so you will need to install that python tool also (eg with `uv tool install pricehist`).
Some price providers limit the commodity pairs, history, or number of requests available for free; you can get better data by paying them and setting up their API keys as environment variables.

Or, you can make your own `getprices` script. It should accept 3-4 arguments:

- ISO code for the base currency
- ISO code for the commodity to be priced
- ISO start date
- optional ISO end date (default: today)
