#!/usr/bin/env -S hledger check lots -f

2022-01-01 buy
    assets:stocks    10 AAPL {$50}
    assets:checking

2022-02-01 sell
    assets:stocks    -15 AAPL {$50} @ $55
    assets:checking   $825
