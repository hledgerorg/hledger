#!/usr/bin/env -S hledger check -f
# An assert directive which fails.

assert none daily  type:A balance:<0

2022-01-01
    assets:checking     $100
    equity:opening

2022-01-05
    expenses:rent       $120
    assets:checking
