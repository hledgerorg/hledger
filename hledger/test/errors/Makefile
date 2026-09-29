HLEDGER ?= hledger

# Executable .j, .csv, .timeclock, and .timedot files are error example scripts.
# Some shenanigans here to order them nicely.
ERRORSCRIPTS := \
	$$(find -s . -name '*.j'         -perm +rwx -exec basename {} \; | grep -v csv) \
	$$(find -s . -name '*.timeclock' -perm +rwx -exec basename {} \; ) \
	$$(find -s . -name '*.timedot'   -perm +rwx -exec basename {} \; ) \
	$$(find -s . -name 'csv*.csv'    -perm +rwx -exec basename {} \; ) \
	$$(find -s . -name '*.sh'        -perm +rwx -exec basename {} \; ) \

list:
	@echo "Error example scripts detected:"
	@for s in $(ERRORSCRIPTS); do echo $$s; done

# Check error messages of $HLEDGER against current error tests.
# A few tests (csvstdinrules.sh) may use "hledger" in $PATH instead of $HLEDGER.
test:
	@printf "Running error message tests with hledger $$($(HLEDGER) --version | awk '{print $$2}'):\n"
	shelltest -w $(HLEDGER) *.test

# Update the readme based on the latest test journals and error output of hledger in $PATH.
update: readme

# Draft a *.test for each error example script that doesn't have one yet,
# using the error messages of hledger in $PATH.
# Existing tests are hand-maintained and are not touched.
tests:
	@printf "Drafting missing *.test with the error messages of hledger $$($(HLEDGER) --version | awk '{print $$2}')\n"
	@for f in $(ERRORSCRIPTS); do \
		t="$$(echo "$$f" | sed -E 's/\.[^.]+$$//').test"; \
		if [ ! -e "$$t" ]; then echo "HLEDGER=$(HLEDGER) ./hledger2shelltest $$f"; HLEDGER=$(HLEDGER) ./hledger2shelltest $$f; fi; \
	done

readme:
	@printf "Updating README.md with the error messages of hledger $$($(HLEDGER) --version)\n"
	sed '/<!-- GENERATED: -->/q' <README.md >README.md.tmp
	echo "$$($(HLEDGER) --version | cut -d, -f1) error messages:" >>README.md.tmp
	for f in $(ERRORSCRIPTS); do \
		printf '\n### %s\n```\n%s\n```\n\n' "$$(echo "$$f" | sed -E 's/\.[^.]+$$//')" "$$(./"$$f" 2>&1 | sed -E 's%[^ (]*/\./%/path/to/%g')"; \
	done >>README.md.tmp
	mv README.md.tmp README.md

