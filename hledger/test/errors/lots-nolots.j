#!/usr/bin/env -S hledger check lots -f

commodity AAPL  ; lots:

2022-01-01 sell shares not held (a short sale, in the wrong kind of account)
    assets:stocks    -10 AAPL @ $50
    assets:checking
