#!/usr/bin/env python3
# Here's an example of converting a particular CSV to hledger journal
# entries with your own custom script, without using hledger at all.
# This is worth considering if the conversion is hard to do with hledger's CSV rules.
# (You give up some of the domain knowledge built in to rules,
# but gain the full power of a programming language.)
#
# This script won't work as-is (without the original foo.csv); use it for inspiration.


__version__ = "1.0"
__author__ = "Simon Michael"

VERSION = "%prog " + __version__
USAGE = """%prog [options] [CSVFILE [JOURNALFILE]]
Reads a [certain kind of] CSV, writes a hledger journal.
Journal entries will be in the same order as the CSV records.

Requirements: python 3.
"""

# from pprint import pprint as pp
import csv
import datetime
import optparse
import re
import subprocess
import sys
import tempfile
# import warnings

def parse_options():
    parser = optparse.OptionParser(usage=USAGE, version=VERSION)
    opts, args = parser.parse_args()
    if len(args) > 2:
        parser.print_help()
        sys.exit()
    return opts, args

def single_space(ms):
    if ms is not None: ms = re.sub(r'  +',' ',ms)
    return ms

# Join two strings with the give separator, but omit the separator
# if either string is empty.
def intercalate2(sep,astr,bstr):
    if astr and bstr:
        return astr + sep + bstr
    else:
        return astr + bstr

def main():
    opts, args = parse_options()
    out = open(args[1],'w') if len(args) > 1 else sys.stdout
    with open(args[0],'r') if len(args) > 0 else sys.stdin as csvfile:

        # Process CSV records, and generate a hledger journal entry for each transaction.

        for r in csv.reader(csvfile):

            # skip headings (record containing no numbers)
            if all(map(lambda v: not any(c.isdigit() for c in v), r)): continue

            # hledger doesn't like records with only one field
            if len(r) < 2: continue

            # skip non-transaction records
            if re.match(r'^(Starting Balance|Net Change|Total|)$',r[0]): continue
            
            # write a hledger journal entry
            property_,date_,payee_payer_,type_,reference_,debit_,credit_,balance_,description_,gl_account_ = r
            date         = datetime.datetime.strptime(date_,"%m/%d/%Y").date().isoformat()
            code         = f" ({reference_})" if reference_ else ""
            description  = intercalate2(' | ', payee_payer_, intercalate2(' ', description_, type_))
            amount1      = f"${debit_}" if debit_ else ""
            amount2      = f"${credit_}" if credit_ else ""
            balance1     = balance_
            account1     = f"Properties:{property_}"
            if gl_account_[0].isdigit():
                account2 = f"{gl_account_[0]}xxx:{gl_account_}"
            else:
                account2 = f"{gl_account_}"
            account1, account2 = single_space(account1), single_space(account2)
            out.write(f"""\
{date}{code} {description}
    {account1}    {amount1} ; = {balance1}
    {account2}    {amount2}

""")

if __name__ == "__main__": main()
