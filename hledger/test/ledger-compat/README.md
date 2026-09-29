Tests of Ledger compatibility, focussed on reading journal format for now.
See https://github.com/hledgerorg/hledger/issues/1962.

The hledger-* tests test hledger's main journal syntax, 
other journal syntax supported by hledger,
and some Ledger journal syntax that we currently don't support.

The ledger-* directories contain examples and reference tests
but are not part of hledger's functional test suite currently.
ledger-baseline/ and ledger-regress/ are a snapshot of Ledger's
functional tests, with all but the sample data commented, and
converted to shelltests which test reading with hledger.
ledger-extra/ are additional tests of ledger journal format compatibility.

Scripts:

./find finds files to test.

./test runs all tests and saves a dated pretty log which can be browsed with org mode.
