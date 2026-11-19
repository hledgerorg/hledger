m4_dnl _commands_
m4_dnl Used in the hledger manual to include all command docs.
m4_dnl Keep synced with Hledger.Cli.Commands.commandsListSections, hledger.m4.md.
m4_define({{_commands_}}, 
{{
<a name="help-commands"></a>

# User interface commands

_command_({{Help}})
_command_({{Repl}})
_command_({{Run}})

## ui

Runs [hledger-ui](hledger-ui.md), a terminal UI (if installed).

## web

Runs [hledger-web](hledger-web.md), a web UI (if installed).


# Data entry commands

_command_({{Add}})
_command_({{Get}})
_command_({{Import}})

<a name="basic-report-commands"></a>

<a name="standard-report-commands"></a>

<a name="advanced-report-commands"></a>

<a name="chart-commands"></a>

# Report commands

_command_({{Accounts}})
_command_({{Activity}})
_command_({{Aregister}})
_command_({{Balance}})
_command_({{Balancesheet}})
_command_({{Balancesheetequity}})
_command_({{Cashflow}})
_command_({{Codes}})
_command_({{Commodities}})
_command_({{Descriptions}})
_command_({{Files}})
_command_({{Holdings}})
_command_({{Incomestatement}})
_command_({{Notes}})
_command_({{Payees}})
_command_({{Prices}})
_command_({{Print}})
_command_({{Register}})
_command_({{Roi}})
_command_({{Stats}})
_command_({{Tags}})
_command_({{Transactions}})

# Maintenance commands

_command_({{Setup}})
_command_({{Init}})
_command_({{Check}})
_command_({{Diff}})

# Data generation commands

_command_({{Close}})
_command_({{Rewrite}})

}})m4_dnl
m4_dnl
m4_dnl _command_(MDFILE)
m4_dnl Include a command's doc. The doc should start with a level two heading. '
m4_define({{_command_}},
{{
m4_include(hledger/Hledger/Cli/Commands/$1.md)
}})m4_dnl
