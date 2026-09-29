# This is another set of quickbench benchmarks, as in bench.sh.
# These are used to compare Ledger and hledger, so they should all
# be commands that Ledger can run.
# Example, from the repo's top directory: just bench -f bench/bench-ledger.sh -w ledger,hledger

hledger -f examples/10ktxns-1kaccts.journal print
hledger -f examples/10ktxns-1kaccts.journal register
hledger -f examples/10ktxns-1kaccts.journal balance
hledger -f examples/100ktxns-1kaccts.journal balance
hledger -f examples/100ktxns-1kaccts.journal balance ff
