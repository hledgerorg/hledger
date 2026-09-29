{-|

Currency names, symbols and codes.
Reference:
- https://www.xe.com/symbols
- https://www.xe.com/currency

-}

{-# LANGUAGE OverloadedStrings    #-}

module Hledger.Data.Currency (
  CurrencyCode,
  CurrencySymbol,
  currencies,
  cryptocurrencies,
  currencySymbolToCode,
  currencyCodeToSymbol,
  toCurrencyCode,
)
where
import Data.Map qualified as M
import           Data.Maybe (fromMaybe)
import           Data.Text (Text)

-- | An ISO 4217 currency code, like EUR.
-- Generally used for fiat currencies, but may also use the X* convention for non-country currencies
-- (eg XAU, XBT), or ISO 20022 cryptocurrency codes (eg ADA).
type CurrencyCode = Text

-- | A traditional currency symbol like $ or ¥ (as opposed to a currency code like USD or JPY).
-- Usually one character, sometimes more, like C$ or BZ$.
type CurrencySymbol = Text

-- | Look for a currency code corresponding to this currency symbol.
--
-- >>> currencySymbolToCode ""
-- Nothing
-- >>> currencySymbolToCode "$"
-- Just "USD"
currencySymbolToCode :: CurrencySymbol -> Maybe CurrencyCode
currencySymbolToCode s = M.lookup s currencyCodesBySymbol

-- | Look for a currency symbol corresponding to this currency code.
--
-- >>> currencyCodeToSymbol "CZK"  -- Just "Kč"
-- Just "K\269"
currencyCodeToSymbol :: CurrencyCode -> Maybe CurrencySymbol
currencyCodeToSymbol c = M.lookup c currencySymbolsByCode

-- | Like 'currencySymbolToCode', but return the input unchanged if no ISO
-- code is known. Useful for normalising free-form commodity labels: known
-- currency symbols become ISO codes, while tickers/abbreviations pass through.
--
-- >>> toCurrencyCode "$"
-- "USD"
-- >>> toCurrencyCode "BTC"
-- "BTC"
toCurrencyCode :: CurrencySymbol -> CurrencyCode
toCurrencyCode s = fromMaybe s (currencySymbolToCode s)

currencyCodesBySymbol = M.fromList [(s,c) | (_,c,s) <- currencies]
currencySymbolsByCode = M.fromList [(c,s) | (_,c,s) <- currencies]

currencies = [
  -- country and currency name           ISO 4217 code  symbol
  ("Albania Lek",                               "ALL",  "Lek"),
  ("Afghanistan Afghani",                       "AFN",  "؋"),
  ("Argentina Peso",                            "ARS",  "$"),
  ("Aruba Guilder",                             "AWG",  "ƒ"),
  ("Australia Dollar",                          "AUD",  "$"),
  ("Azerbaijan Manat",                          "AZN",  "₼"),
  ("Bahamas Dollar",                            "BSD",  "$"),
  ("Barbados Dollar",                           "BBD",  "$"),
  ("Belarus Ruble",                             "BYN",  "Br"),
  ("Belize Dollar",                             "BZD",  "BZ$"),
  ("Bermuda Dollar",                            "BMD",  "$"),
  ("Bolivia Bolíviano",                         "BOB",  "$b"),
  ("Bosnia and Herzegovina Convertible Mark",   "BAM",  "KM"),
  ("Botswana Pula",                             "BWP",  "P"),
  ("Bulgaria Lev",                              "BGN",  "лв"),
  ("Brazil Real",                               "BRL",  "R$"),
  ("Brunei Darussalam Dollar",                  "BND",  "$"),
  ("Cambodia Riel",                             "KHR",  "៛"),
  ("Canada Dollar",                             "CAD",  "$"),
  ("Cayman Islands Dollar",                     "KYD",  "$"),
  ("Chile Peso",                                "CLP",  "$"),
  ("China Yuan Renminbi",                       "CNY",  "¥"),
  ("Colombia Peso",                             "COP",  "$"),
  ("Costa Rica Colon",                          "CRC",  "₡"),
  ("Croatia Kuna",                              "HRK",  "kn"),
  ("Cuba Peso",                                 "CUP",  "₱"),
  ("Czech Republic Koruna",                     "CZK",  "Kč"),
  ("Denmark Krone",                             "DKK",  "kr"),
  ("Dominican Republic Peso",                   "DOP",  "RD$"),
  ("East Caribbean Dollar",                     "XCD",  "$"),
  ("Egypt Pound",                               "EGP",  "£"),
  ("El Salvador Colon",                         "SVC",  "$"),
  ("Euro Member Countries",                     "EUR",  "€"),
  ("Falkland Islands (Malvinas) Pound",         "FKP",  "£"),
  ("Fiji Dollar",                               "FJD",  "$"),
  ("Ghana Cedi",                                "GHS",  "¢"),
  ("Gibraltar Pound",                           "GIP",  "£"),
  ("Guatemala Quetzal",                         "GTQ",  "Q"),
  ("Guernsey Pound",                            "GGP",  "£"),
  ("Guyana Dollar",                             "GYD",  "$"),
  ("Honduras Lempira",                          "HNL",  "L"),
  ("Hong Kong Dollar",                          "HKD",  "$"),
  ("Hungary Forint",                            "HUF",  "Ft"),
  ("Iceland Krona",                             "ISK",  "kr"),
  ("India Rupee",                               "INR",  "₹"),
  ("Indonesia Rupiah",                          "IDR",  "Rp"),
  ("Iran Rial",                                 "IRR",  "﷼"),
  ("Isle of Man Pound",                         "IMP",  "£"),
  ("Israel Shekel",                             "ILS",  "₪"),
  ("Jamaica Dollar",                            "JMD",  "J$"),
  ("Japan Yen",                                 "JPY",  "¥"),
  ("Jersey Pound",                              "JEP",  "£"),
  ("Kazakhstan Tenge",                          "KZT",  "лв"),
  ("Korea (North) Won",                         "KPW",  "₩"),
  ("Korea (South) Won",                         "KRW",  "₩"),
  ("Kyrgyzstan Som",                            "KGS",  "лв"),
  ("Laos Kip",                                  "LAK",  "₭"),
  ("Lebanon Pound",                             "LBP",  "£"),
  ("Liberia Dollar",                            "LRD",  "$"),
  ("Macedonia Denar",                           "MKD",  "ден"),
  ("Malaysia Ringgit",                          "MYR",  "RM"),
  ("Mauritius Rupee",                           "MUR",  "₨"),
  ("Mexico Peso",                               "MXN",  "$"),
  ("Mongolia Tughrik",                          "MNT",  "₮"),
  ("Mozambique Metical",                        "MZN",  "MT"),
  ("Namibia Dollar",                            "NAD",  "$"),
  ("Nepal Rupee",                               "NPR",  "₨"),
  ("Netherlands Antilles Guilder",              "ANG",  "ƒ"),
  ("New Zealand Dollar",                        "NZD",  "$"),
  ("Nicaragua Cordoba",                         "NIO",  "C$"),
  ("Nigeria Naira",                             "NGN",  "₦"),
  ("Norway Krone",                              "NOK",  "kr"),
  ("Oman Rial",                                 "OMR",  "﷼"),
  ("Pakistan Rupee",                            "PKR",  "₨"),
  ("Panama Balboa",                             "PAB",  "B/."),
  ("Paraguay Guarani",                          "PYG",  "Gs"),
  ("Peru Sol",                                  "PEN",  "S/."),
  ("Philippines Peso",                          "PHP",  "₱"),
  ("Poland Zloty",                              "PLN",  "zł"),
  ("Qatar Riyal",                               "QAR",  "﷼"),
  ("Romania Leu",                               "RON",  "lei"),
  ("Russia Ruble",                              "RUB",  "₽"),
  ("Saint Helena Pound",                        "SHP",  "£"),
  ("Saudi Arabia Riyal",                        "SAR",  "﷼"),
  ("Serbia Dinar",                              "RSD",  "Дин."),
  ("Seychelles Rupee",                          "SCR",  "₨"),
  ("Singapore Dollar",                          "SGD",  "$"),
  ("Solomon Islands Dollar",                    "SBD",  "$"),
  ("Somalia Shilling",                          "SOS",  "S"),
  ("South Africa Rand",                         "ZAR",  "R"),
  ("Sri Lanka Rupee",                           "LKR",  "₨"),
  ("Sweden Krona",                              "SEK",  "kr"),
  ("Switzerland Franc",                         "CHF",  "CHF"),
  ("Suriname Dollar",                           "SRD",  "$"),
  ("Syria Pound",                               "SYP",  "£"),
  ("Taiwan New Dollar",                         "TWD",  "NT$"),
  ("Thailand Baht",                             "THB",  "฿"),
  ("Trinidad and Tobago Dollar",                "TTD",  "TT$"),
  ("Turkey Lira",                               "TRY",  "₺"),
  ("Tuvalu Dollar",                             "TVD",  "$"),
  ("Ukraine Hryvnia",                           "UAH",  "₴"),
  ("United Kingdom Pound",                      "GBP",  "£"),
  ("United States Dollar",                      "USD",  "$"),
  ("Uruguay Peso",                              "UYU",  "$U"),
  ("Uzbekistan Som",                            "UZS",  "лв"),
  ("Venezuela Bolívar",                         "VEF",  "Bs"),
  ("Viet Nam Dong",                             "VND",  "₫"),
  ("Yemen Rial",                                "YER",  "﷼"),
  ("Zimbabwe Dollar",                           "ZWD",  "Z$")
  ]

-- | The top 100 cryptocurrencies by market capitalisation, as ticker
-- symbols, in descending rank order. Snapshot taken from the CoinGecko
-- public API on 2026-04-30:
-- https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=100&page=1
cryptocurrencies :: [CurrencyCode]
cryptocurrencies =
  ["BTC","ETH","USDT","XRP","BNB","USDC","SOL","TRX","FIGR_HELOC","DOGE"
  ,"WBT","USDS","HYPE","LEO","ADA","BCH","XMR","LINK","ZEC","CC"
  ,"XLM","USD1","DAI","LTC","M","AVAX","USDE","HBAR","RAIN","SHIB"
  ,"SUI","PYUSD","TON","CRO","USYC","XAUT","USDG","TAO","BUIDL","PAXG"
  ,"MNT","UNI","DOT","WLFI","SKY","PI","USDF","OKB","NEAR","ASTER"
  ,"PEPE","HTX","USDD","RLUSD","AAVE","BGB","ICP","USDY","JTRSY","BFUSD"
  ,"ETC","ONDO","MORPHO","KCS","U","QNT","POL","EUTBL","ALGO","USTB"
  ,"BCAP","ATOM","ENA","NEXO","KAS","RENDER","APT","GT","WLD","ARB"
  ,"JST","STABLE","FIL","PUMP","FLR","PENGU","BDX","JUP","OUSG","VET"
  ,"XDC","USDTB","GHO","HASH","USD0","TRUMP","BONK","NIGHT","DEXE","YLDS"
  ]

-- tests_Currency = testGroup "Currency" []
