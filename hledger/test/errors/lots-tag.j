#!/usr/bin/env -S hledger check -f

commodity AAPL  ; lots: BADMETHOD

2022-01-01 buy
    assets:stocks    10 AAPL {$50}
    assets:checking
