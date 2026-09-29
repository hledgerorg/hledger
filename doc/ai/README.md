Additional notes about the hledger project's AI usage, complementing ../AI.md.

See also the ai scripts in Justfile: `just ai-help`
Files that might exist here (+ are committed)::

+ ccusage.rules       - for reading `ccusage` output (to generate ccusage.journal)
- ccusage.journal     - a local snapshot of claude code usage (from ccusage). Transient.
+ ai.rules            - for reading ccusage.journal's monthly areg report (for import to ai.journal)
- aicommits.csv       - a local snapshot of AI usage info from the hledger repo's commit messages
+ aicommits.csv.rules - for reading aicommits.csv (for import to ai.journal)
- aiextra.csv         - a local log of additional AI usage not recorded in commit messages (for import to ai.journal)
+ ai.journal          - the project's public log of estimated monthly overall AI usage
+ commodities.journal - commodity declarations and unit conversion rates
