## rotki Generic Import

You can import data (trades & events) from exchanges not supported by rotki by clicking "Import Data" on the left sidebar, selecting `Custom Import` and following the prompt. This involves the user converting the source (a not directly supported exchange, protocol, etc.) data to match the import format of rotki.

> **Note**: Keep in mind that all assets that you enter are identified by their asset identifier and not the symbol, as symbols are not unique. The identifier differs per asset and at the moment for ERC20 tokens follows the [CAIP-19](https://github.com/ChainAgnostic/CAIPs/blob/main/CAIPs/caip-19.md) format, and for others, it's just the asset symbol or a random string for manually input tokens.

For the CAIP-19 format, it's essentially calculated by knowing the chain ID and the address of your token. So for mainnet (chain ID 1) and USDT (0xdAC17F958D2ee523a2206206994597C13D831ec7), it's `eip155:1/erc20:0xdAC17F958D2ee523a2206206994597C13D831ec7`.

You can easily find the identifier of each asset by going to `Manage Assets > Assets` section and copying the identifier of the asset in question.

The import is split into two types:

### rotki Generic Trades Import

This is solely for importing generic trades. The expected file format is **CSV** with the following headers and descriptions as a guide:

1. **Location**: This is the source of the data. It should be one of rotki's [supported locations](#supported-locations). If it is not supported, use `"external"`.
2. **Spend Currency**: The currency you spent in the trade, can be a token address (e.g., `eip155:1/erc20:0xdAC17F958D2ee523a2206206994597C13D831ec7`) or symbol (e.g., `BTC`).
3. **Spend Amount**: The amount of currency you spent.
4. **Receive Currency**: The currency you received in the trade, can be a token address or symbol.
5. **Receive Amount**: The amount of currency you received.
6. **Fee**: The amount charged for the trade. This is optional.
7. **Fee Currency**: The currency in which the fee was charged. This is optional.
8. **Description**: A description of the trade if any. This is optional.
9. **Timestamp**: The UTC Unix timestamp at which the trade took place. This is a milliseconds timestamp.

A sample generic trades template can be found below:

<CsvTable title="rotki Generic Trades Template" csvUrl="/files/rotki_generic_trades.csv" />
Location,Spend Currency,Receive Currency,Receive Amount,Spend Amount,Fee,Fee Currency,Description,Timestamp
binance,eip155:1/erc20:0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,ETH,1.0000,1875.64,,,Trade USDC for ETH,1659085200000
kraken,LTC,BTC,4.3241,392.8870,,,Trade LTC for BTC,1659171600000
kucoin,eip155:1/erc20:0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984,eip155:1/erc20:0x6B175474E89094C44Da98b954EedeAC495271d0F,880.0000,20.0000,0.1040,USD,Trade UNI for DAI,1659344400000
luno,ADA,BCH,16.3444,4576.6400,5.1345,USD,Trade ADA for BCH,1659344900000
bisq,eip155:1/erc20:0xdAC17F958D2ee523a2206206994597C13D831ec7,eip155:1/erc20:0x6B175474E89094C44Da98b954EedeAC495271d0F,0,4576.6400,5.1345,USD,Trade USDT for DAI,1659345600000

### rotki Generic Events Import

This is for importing generic events. Supported events are `"Deposit"`, `"Withdrawal"`, `"Income"`, `"Loss"`, `"Spend"` and `"Staking"`. The expected file format is **CSV** with the following headers and descriptions as a guide:

1. **Type**: The event type. It can be one of `"Deposit"`, `"Withdrawal"`, `"Income"`, `"Loss"`, `"Spend"` or `"Staking"`.
2. **Location**: This is the source of the data. It should be one of rotki's [supported locations](#supported-locations). If it is not supported, use `"external"`.
3. **Currency**: The currency used during the specified event.
4. **Amount**: The amount of the currency used by the event.
5. **Fee**: The amount charged for the event. This is optional.
6. **Fee Currency**: The currency in which the fee was charged. This is optional.
7. **Description**: A description of the event that was carried out, if any. This is optional.
8. **Timestamp**: The UTC Unix timestamp at which the event took place. This is a milliseconds timestamp.

A sample generic events template can be found below:

<CsvTable title="rotki Generic Events Template" csvUrl="/files/rotki_generic_events.csv" />
Type,Location,Currency,Amount,Fee,Fee Currency,Description,Timestamp
Deposit,kucoin,EUR,1000.00,,,Deposit EUR to Kucoin,1658912400000
Withdrawal,binance,eip155:1/erc20:0xdAC17F958D2ee523a2206206994597C13D831ec7,99.00,1.00,eip155:1/erc20:0xdAC17F958D2ee523a2206206994597C13D831ec7,,1658998800000
Withdrawal,kraken,eip155:1/erc20:0xB8c77482e45F1F44dE1745F52C74426C631bDD52,1.01,,,,1659085200000
Staking,luno,ETH,0.0513,,,ETH Staking reward from QRS,1659340800000
Loss,coinbase,BTC,0.0910,,,,1659430800000
Income,cex,eip155:1/erc20:0x6B175474E89094C44Da98b954EedeAC495271d0F,1000.00,,,,1659513600000
Invalid,bisq,BCH,0.3456,,,,1659686400000

### Supported Locations

A list of supported locations in rotki are `"external"`, `"kraken"`, `"poloniex"`, `"bittrex"`, `"binance"`, `"bitmex"`, `"coinbase"`, `"banks"`, `"blockchain"`, `"gemini"`, `"equities"`, `"realestate"`, `"commodities"`, `"cryptocom"`, `"uniswap"`, `"bitstamp"`, `"binanceus"`, `"bitfinex"`, `"bitcoinde"`, `"iconomi"`, `"kucoin"`, `"balancer"`, `"loopring"`, `"ftx"`, `"nexo"`, `"blockfi"`, `"independentreserve"`, `"gitcoin"`, `"sushiswap"`, `"shapeshift"`, `"uphold"`, `"bitpanda"`, `"bisq"`, `"ftxus"` and `"okx"`.

> **Note**: In the columns where an asset is expected, you will need to use the identifier that such asset has in rotki; otherwise, the row won't be read.

> **Note**: If at any point, you're confused about the CSV format, feel free to send us a message on [Discord](https://discord.rotki.com).
