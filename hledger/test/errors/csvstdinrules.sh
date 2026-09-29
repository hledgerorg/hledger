#!/usr/bin/env -S sh
# Try to read CSV from stdin without specifying a rules file.
echo | hledger -fcsv:- check
