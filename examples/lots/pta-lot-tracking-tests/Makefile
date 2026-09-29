
subaccounts.beancount: subaccounts.hledger
	sed -E 's/_[^0-9]*([0-9]+)[.,]([0-9]+)/-\1-\2/' $< | hledger print --alias revenues=income -f- -O beancount | bean-format - >$@

lotter.lotter: lotter.hledger
	lotter -f $< >$@

hledger-bal-%:
	@printf "$$ "
	hledger -f $*.hledger bal -YE aaa

ledger-bal-%:
	@printf "$$ "
	ledger -f $*.hledger bal --flat -E aaa

lotter-bal: lotter.lotter
	@printf "$$ "
	hledger -f lotter.lotter bal -YE --invert Lot cur:AAA

ledger-lots:
	@printf "$$ "
	ledger -f ledger.ledger bal --lots --flat -E --no-total aaa

beancount-bal-%:
	@printf "$$ "
	bean-query subaccounts.beancount "SELECT account, units(sum(position)), cost(sum(position)) WHERE account ~ 'Aaa' GROUP BY 1 ORDER BY account;"

beancount-lots-%:
	@printf "$$ "
	bean-query $*.beancount "SELECT account, units(sum(position)) as units, cost_number as cost, cost_date as acquisition_date WHERE account ~ 'Aaa' GROUP BY account, cost_date, currency, cost_currency, cost_number, account_sortkey(account) ORDER BY account_sortkey(account), currency, cost_date"
	@printf "$$ "
	bean-query $*.beancount "SELECT account, units(sum(position)) as units, cost_number as cost, first(getprice(currency, cost_currency)) as price, cost(sum(position)) as book_value, value(sum(position)) as market_value, safediv((abs(sum(number(value(position)))) - abs(sum(number(cost(position))))), sum(number(cost(position)))) * 100 as unrealized_profit_pct, cost_date as acquisition_date WHERE account ~ 'Aaa' GROUP BY account, cost_date, currency, cost_currency, cost_number, account_sortkey(account) ORDER BY account_sortkey(account), currency, cost_date"

bals: hledger-bal-subaccounts ledger-bal-subaccounts beancount-bal-subaccounts beancount-bal-beancount
