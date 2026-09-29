#!/usr/bin/env bash
# Parse hledger's commands list and print all builtin command names and aliases.
# Currently add-on commands are excluded, except for ui and web.

set -euo pipefail
declare commands_help
commands_help=$(hledger)
# Keep synced with `hledger` output and known add-ons (+-prefixed commands in Hledger.Cli.Commands.commandsListSections):
{
    sed -rn 's/^[[:space:]]([a-z][-a-z]+)[[:space:]]+.*/\1/p; /OTHER ADDONS/q' <<< "$commands_help"
    sed -rn 's/^[[:space:]][a-z][-a-z]+[[:space:]]+\(([a-z][ ,a-z]+)\).*/\1/p' <<< "$commands_help"
} \
| sed -r '/(iadd|edit|lots|bar|plot|autosync|interest|pricehist|check-fancyassertions|check-tagfiles|git|pijul)/d;' \
| sort -u

# Local Variables:
# mode: sh
# sh-basic-offset: 4
# indent-tabs-mode: nil
# End:
# ex: ts=4 sw=4 et
