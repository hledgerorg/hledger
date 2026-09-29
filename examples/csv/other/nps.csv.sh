#!/usr/bin/env bash
# Script to clean Indian National Pension Scheme CSV and import new transactions.
# See also nps.csv.rules.

# Ex: $ ./nps.csv.sh nps_fy20-21.csv
# removes all lines before the last 'Date'
# substitutes certain descriptions
# outputs to a temporary file
# runs hledger csv import as a dry-run with nps.csv.rules.

cat "$1" \
  | awk 's{s=s"\n"$0;} /Date/{s=$0;} END{print s;}' \
  | sed 's/On account of Rebalancing of Assets as per Regulatory Requirement/Rebalancing/g' \
  | sed 's/To unit redemption - on account of payment of annual persistency charges to POP/POP Persistency Charge/g' \
  | sed 's/By Voluntary Contributions/Contribution/g' \
  | sed 's/By Contribution/Contribution/g' \
  > nps.csv
hledger import --dry-run nps.csv
