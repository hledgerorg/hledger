# Some standard commands to benchmark. "just bench" runs these by default.
# There is another set of benchmarks in the hledger package: hledger/bench/bench.hs
# Here is a quick benchmarking guide. Note these are quick measurements which
# can be affected by system activity. Usually this isn't a problem. The last
# (criterion) is more robust.
# 
# Generate the test journals: 
# just samplejournals 
#
# Get quickbench: 
# git clone https://github.com/simonmichael/quickbench
# cd quickbench
# stack install  # must be run in source dir
#
# Measure performance (from the repo's top directory, since the commands use relative paths):
# time sh bench/bench.sh  # show if these work, what they do, total time (GNU time also shows max memory)
# just bench [OPTS]      # time each command, one or more times (runs quickbench -f bench/bench.sh)
# stack bench hledger    # time a different set of benchmarks (hledger/bench/bench.hs)
# stack bench hledger --ba --criterion  # time more carefully, using criterion 

# commands to benchmark:

# hledger -f ../examples/10ktxns-1kaccts.journal stats
# hledger -f ../examples/10ktxns-1kaccts.journal balance
# hledger -f ../examples/10ktxns-1kaccts.journal print
# hledger -f ../examples/10ktxns-1kaccts.journal register
hledger -f ../examples/100ktxns-1kaccts.journal stats
hledger -f ../examples/100ktxns-1kaccts.journal balance
hledger -f ../examples/100ktxns-1kaccts.journal print
hledger -f ../examples/100ktxns-1kaccts.journal register

