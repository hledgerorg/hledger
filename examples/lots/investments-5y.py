#!/usr/bin/env python3
"""
Generate a realistic investment journal for testing holdings/roi/lots performance:
40 lot-tracked commodities in 3 brokerage accounts (with long account names),
5 years of daily market prices, weekly purchases and monthly partial sales.
About 12.8k transactions and 73k price directives (3.8 MB).

Usage: examples/lots/investments-5y.py > examples/lots/investments-5y.journal
"""
import datetime as dt
import random
import string
import sys

random.seed(1)
comms = ["TK" + a + b for a in "ABCD" for b in "ABCDEFGHIJ"]
accts = ["assets:investments:brokerage-taxable:fidelity-individual-account",
         "assets:investments:retirement-tax-deferred:vanguard-rollover-ira",
         "assets:investments:brokerage-taxable:schwab-joint-account-2019"]
start, end = dt.date(2021, 11, 15), dt.date(2026, 11, 14)
price = {c: random.uniform(10, 300) for c in comms}
held = {(a, c): 0 for a in accts for c in comms}
acctof = {c: accts[i % 3] for i, c in enumerate(comms)}
out = ["account revenues:capital-gains:realised ; type: G"] + ["commodity %s ; lots:" % c for c in comms] + [""]
d = start
while d <= end:
    for c in comms:
        price[c] *= random.lognormvariate(0.0002, 0.015)
        out.append("P %s %s $%.2f" % (d, c, price[c]))
    if d.weekday() == 0:
        for c in comms:
            a, q = acctof[c], random.randint(1, 20)
            out += ["", "%s buy %s" % (d, c), "    %s    %d %s @ $%.2f" % (a, q, c, price[c]),
                    "    assets:cash:checking-account-primary-household"]
            held[(a, c)] += q
    if d.day == 1:
        for c in comms:
            a = acctof[c]
            q = held[(a, c)] // 10
            if q > 0:
                out += ["", "%s sell %s" % (d, c), "    %s    -%d %s @ $%.2f" % (a, q, c, price[c]),
                        "    assets:cash:checking-account-primary-household", "    revenues:capital-gains:realised"]
                held[(a, c)] -= q
    d += dt.timedelta(days=1)
sys.stdout.write("\n".join(out) + "\n")
