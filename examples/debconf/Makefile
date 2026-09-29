# download ledgers for all years
all: \
 dc17 \
 dc18 \
 dc19 \
 dc20 \
 dc21 \
 dc22 \
 dc23 \
 dc24 \
 dc25 \
# dc26 \

recent: \
 dc24 \
 dc25 \
# dc26 \

# make dc-YY - clone the budget directory for this year, make it hledger-readable, add a top-level file
dc%:
	git clone --filter=blob:none --sparse http://salsa.debian.org/debconf-team/public/data/$@
	git -C $@ sparse-checkout set --no-cone budget '!budget/invoices'
	git -C $@ apply --allow-empty ../patches/$@.patch
	printf 'include $@/budget/journal.ledger\ninclude $@/budget/forex.db\n' > $*.hledger

# make cmd-'CMD' - run a command in each repo's budget directory
cmd-%:
	@for d in dc*; do printf "\n$$d:\n"; (cd $$d/budget; $*;) done

# make hledger-'HLEDGERARGS' - run a hledger command on each repo's main journal
hledger-%:
	@for d in dc*; do printf "\n$$d:\n"; hledger -f $$(echo $$d | sed 's/dc//').hledger $*; done

# check hledger readability of all repos' main journal
hledger-check:
	@for d in dc*; do printf "$$d: ";    hledger -f $$(echo $$d | sed 's/dc//').hledger stats >/dev/null && echo ok; done

# make ledger-'LEDGERARGS' - run a ledger command on each repo's main journal
ledger-%:
	@for d in dc*; do printf "\n$$d:\n"; ledger -f $$d/budget/journal.ledger --price-db $$d/budget/forex.db $*; done

# check Ledger readability of all repos' main journal
ledger-check:
	@for d in dc*; do printf "$$d: ";    ledger -f $$d/budget/journal.ledger --price-db $$d/budget/forex.db stats >/dev/null && echo ok; done


# maintenance

clean:
	rm -rf dc* 2*.ledger

# make rg-PAT - ripgrep for PAT in ledger,inc,db files in all years
rg-%:
	rg -g '*.{ledger,inc,db}' '$*'

# make all years hledger-readable
fixups:
	# ensure at least two whitespace chars before amounts:
	sed -i -E 's/(\w)\t(\w)/ \t/' dc*/budget/*.ledger
	# ensure a decimal mark in commodity declarations:
	sed -i -E 's/^( +format +\w+ +[0-9]+(,[0-9]+)+)$$/\1.00/' dc*/budget/commodities.inc
	# convert amount expressions to simple amounts (use ledgereval or ledger eval)

# save patch files for each year
save-patches:
	for d in dc*; do git --no-pager -C $$d diff > patches/$$d.patch; done

