# Cryptocurrency tax reporting

(This is the README in the hledger repo's [examples/csv/cctax/][cctax] directory,
also published as the [Cryptocurrency tax reporting] page on hledger.org.
The information here was last updated in 2025-12.
)
<!-- This page can be viewed on github or hledger.org, so use absolute urls -->
[Cryptocurrency tax reporting]: https://hledger.org/cctax.html
[cctax]:                        https://github.com/hledgerorg/hledger/tree/main/examples/csv/cctax

In this directory we are not concerned with importing to hledger,
but with exporting from hledger to cryptocurrency tax calculators.

Why do this ?
In most countries, the revenue and capital gain from receiving/selling/trading cryptocurrencies (cc) is taxable and must be reported.
There are several aspects to this:

- Calculating income. This is easy - at least, once you have recorded all transactions in hledger.
- Calculating capital gains. This can be hard, and depends on your country's rules.
- Calculating taxes owed. This also depends on your country's rules, and is often handled by specialised tax preparation software.

Centralised exchanges will calculate gains for you, but self-custodied wallets, decentralised exchanges, or other defi apps won't;
with those, you are responsible for calculating gains.

In some countries, such as the USA, this requires:
- tracking the acquisition date, cost, and wallet of every purchase/acquisition over your lifetime
- tracking these across movements/splits/merges
- disposing (selling/spending) them in a required order, such as:
  - FIFO - first in first out
  - LIFO - last in first out
  - HIFO - highest cost first out
  - LOFO - lowest cost first out
  - SpecId - specific identification of lots
- and thereby calculating the capital gains or losses.

In the US, before 2025 universal cost tracking was used to determine the disposal order;
this means you consider the acquisition costs/dates of all your holdings of an asset (cryptocurrency), across all wallets.
From tax year 2025, per-wallet cost tracking is required, which means you apply the disposal order separately within each wallet.
The "Safe Harbor" rule allows you to allocate pre-2025 lots to specific wallets (once), which could help optimise taxes in some cases.

In the UK, it's easier: you use each asset's average cost across all wallets.

There are several ways you could calculate gains. Eg, assuming the worst case (US taxes), you could:

1. Calculate gains using only hledger,
   by keeping track of each lot and lot movement with subaccounts,
   and selecting the appropriate lots/costs in disposal transactions.
   This is intuitive and robust. But also tedious, and above a certain level of activity it becomes unmanageable.

2. Calculate gains using the built-in lot tracking syntax of Ledger or Beancount. 
   (hledger doesn't have this feature.)
   Beancount's is more robust.
   These may be too limited to calculate gains accurately, eg when there are inter-wallet transfers.
   There may be additional plugins which help.

3. Online cryptocurrency tax calculators (Bitcoin.Tax, Cointracker, Coinledger, Koinly, Summ, TokenTax..)
   These let you upload transaction history from all of your cryptocurrency activities.
   Then they analyse this data, identify what happened (you may need to add configuration here), and provide gains reports.
   These apps are convenient and featureful, eg they may understand your country's tax rules; but they also add rather serious privacy risk.
   When they are hacked or infiltrated, potentially your entire past, present and future cryptocurrency activities can be analysed.

4. Offline cryptocurrency tax calculators. These tend to be more private.
   - [BittyTax] - UK and US variants (can do wallet-based cost tracking by using multiple configs)
   - [rotki]    - freemium, featureful, does not support US yet (wallet-based cost tracking, <https://github.com/rotki/rotki/issues/2438>)
   - [RP2]      - does not support US yet (<https://github.com/eprbell/rp2/issues/135>)

[bittytax]: https://github.com/BittyTax/BittyTax
[rotki]: http://rotki.com
[rp2]: https://github.com/eprbell/rp2

The main focus in this directory is exporting to offline calculators.
Examples of their CSV import format are collected here.
Each record represents an event in a particular cryptocurrency "wallet" (on an exchange or on a blockchain).
There are basic events like deposit, withdrawal, buy, sell, expense, income; and some more specialised event types.

[examples/csv/cctax/][cctax]
