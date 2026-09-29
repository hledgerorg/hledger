# -*- mode: sh; sh-basic-offset: 4; indent-tabs-mode: nil -*-
# ex: ft=sh ts=4 sw=4 et
# shellcheck disable=2034,2154

# Completion script for hledger.
# Created using a Makefile and real hledger.

# This script is sourced by an interactive shell, so do NOT do things like
# 'set -o pipefail' or mangle the global environment in any other way!
# That said, we *do* remove colon (:) from COMP_WORDBREAKS which impacts
# the rest of the session and completion for other programs.

# INSTALLATION:
# To install you can simply source this file from your shell's startup files.
#
# Alternatively, copy/symlink it into `${BASH_COMPLETION_USER_DIR}/completions`
# or `${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions`, rename
# it to either `hledger`, `_hledger` or `hledger.bash`, and it will be loaded
# dynamically the first time you use the `hledger` command. Optionally, create
# symlinks to this file for any extensions used e.g.:
#
# mkdir -p "${BASH_COMPLETION_USER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion}/completions" &&
# cd "${BASH_COMPLETION_USER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion}/completions" &&
# cp /path/to/hledger-completion.bash hledger &&
# ln -s hledger hledger-ui &&
# ln -s hledger hledger-web &&
# : done.


_hledger_completion() {
    local cur prev words cword
    _init_completion -n : || return 0

    # Current treatment for special characters:
    # - exclude colon (:) from COMP_WORDBREAKS
    # - option processing assumes that `=` is in COMP_WORDBREAKS
    # - use compopt -o filenames selectively to escape the rest
    COMP_WORDBREAKS=${COMP_WORDBREAKS//:}
    case $COMP_WORDBREAKS in
        *=*) : ;;
        *)   COMP_WORDBREAKS=$COMP_WORDBREAKS= ;;
    esac

    local subcommand
    local subcommandOptions
    local i
    for ((i=1; i<${#words[@]}; i++)); do
        subcommand=${words[i]}
        if ! grep -Fxqe "$subcommand" <<< "$_hledger_complist_commands"; then
            subcommand=
            continue
        fi
        # There could be other commands begining with $subcommand, e.g.:
        # $subcommand == reg --> register, register-match,
        # $subcommand == bal --> balance, balancesheet, balancesheetequity, etc.
        # Do not ignore them!
        if ((i == cword)); then
            _hledger_compreply "$(
                _hledger_compgen "$_hledger_complist_commands"
            )"
            return 0
        fi

        # Replace dashes with underscores and use indirect expansion
        subcommandOptions=_hledger_complist_options_${subcommand//-/_}

        if [[ $cur == -* ]]; then
            _hledger_compreply "$(_hledger_compgen "${!subcommandOptions}")"
            # Suspend space on completion of long options requiring an argument
            [[ ${COMPREPLY[0]} == --*= ]] && compopt -o nospace

            return 0
        fi
        break
    done

    # Option argument completion
    _hledger_compreply_optarg && return

    if [[ -z $subcommand ]]; then
        if [[ $cur == -* ]]; then
            _hledger_compreply "$(
                _hledger_compgen "$_hledger_complist_generic_options"
            )"
            # Suspend space on completion of long options requiring an argument
            [[ ${COMPREPLY[0]} == --*= ]] && compopt -o nospace
        else
            _hledger_compreply "$(
                _hledger_compgen "$_hledger_complist_commands"
            )"
        fi

        return 0
    fi

    # Set this from here on because queries tend to have lots of special chars
    # TODO: better handling of special characters
    compopt -o filenames

    # Query completion
    _hledger_compreply_query && return

    # Subcommand specific
    case $subcommand in
        # These do not expect or support any query arguments
        commodities|check|files|help|import|print-unique|test)
            return 0
            ;;
    esac

    # Offer query filters and accounts for the rest
    _hledger_compreply "$(_hledger_compgen "$_hledger_complist_query_filters")"
    if [[ -z $cur ]]; then
        _hledger_compreply_append "$(
            _hledger_compgen "$(_hledger accounts --flat --depth 1)"
        )"
    else
        _hledger_compreply_append "$(
            _hledger_compgen "$(_hledger accounts --flat)"
        )"
    fi

    # Suspend space on completion of query prefix
    # Do not sort, keep accounts and query filters grouped separately
    [[ ${COMPREPLY[0]} == *: ]] && compopt -o nospace
    compopt -o nosort

    return 0
}

_hledger_extension_completion() {
    local cmd=${1##*/}
    local ext=${cmd#hledger-}
    # Pretend that hledger is called with the given extension
    # as the first argument and call main completion function
    COMP_WORDS=("hledger" "$ext" "${COMP_WORDS[@]:1}")
    COMP_CWORD=$((COMP_CWORD + 1))
    _hledger_completion "hledger" "${@:1}"
}

# Register completion function for hledger:
complete -F _hledger_completion hledger

# Register completion functions for hledger extensions:
complete -F _hledger_extension_completion hledger-ui hledger-web

# Helpers

# Comment out when done
_hledger_debug() {
    ((HLEDGER_DEBUG)) || return 0
    local var vars=(words)
    (($#)) && vars=("$@")
    for var in "${vars[@]}"; do
        printf '\ndebug: %s\n' "$(declare -p "$var")" >&2
    done
}

# Stolen from bash-completion
# This function quotes the argument in a way so that readline dequoting
# results in the original argument.  This is necessary for at least
# `compgen' which requires its arguments quoted/escaped:
_hledger_quote_by_ref()
{
    printf -v "$2" %q "$1"

    # If result becomes quoted like this: $'string', re-evaluate in order to
    # drop the additional quoting.  See also: http://www.mail-archive.com/
    # bash-completion-devel@lists.alioth.debian.org/msg01942.html
    [[ ${!2} == \$* ]] && eval "$2=${!2}"
}

# Set the value of COMPREPLY from newline delimited completion candidates
_hledger_compreply() {
    local IFS=$'\n'
    # shellcheck disable=2206
    COMPREPLY=($1)
}

# Append the value of COMPREPLY from newline delimited completion candidates
_hledger_compreply_append() {
    local IFS=$'\n'
    # shellcheck disable=2206
    COMPREPLY+=($1)
}

# Generate input suitable for _hledger_compreply() from newline delimited
# completion candidates. It doesn't seem there is a way to feed a literal
# word list to compgen -- it will eat your quotes, drink your booze and...
# Completion candidates are quoted accordingly first and then we leave it to
# compgen to deal with readline.
#
# Arguments:
# $1: a newline separated list with completion cadidates
# $2: (optional) a prefix string to add to generated completions
# $3: (optional) a word to match instead of $cur, the default.
# If $match is null and $prefix is defined the match is done against $cur
# stripped of $prefix. If both $prefix and $match are null we match against
# $cur and no prefix is added to completions.
_hledger_compgen() {
    local complist=$1
    local prefix=$2
    local match=$3
    local quoted=()
    local word
    local i=0

    while IFS= read -r word; do
        _hledger_quote_by_ref "$word" word
        quoted[i++]=$word
    done <<< "$complist"

    if (($# < 3)); then
        match=${cur:${#prefix}}
    fi

    local IFS=$'\n'
    compgen -P "$prefix" -W "${quoted[*]}" -- "$match"
}

# Try required option argument completion. Set COMPREPLY and return 0 on
# success, 1 if option doesn't require an argument or out of context
_hledger_compreply_optarg() {
    local option=${words[cword - 1]}
    local match=$cur
    local wordlist

    # Match the empty string on --file=<TAB>, not the equal sign itself
    if [[ $cur == = ]]; then
        match=""
    # Once input is present, cword is incremented so we compensate
    elif [[ $prev == = ]]; then
        option=${words[cword - 2]}
    fi

    [[ $option == -* ]] || return

    case $option in
        --alias)
            compopt -o nospace -o filenames
            _hledger_compreply "$(
                _hledger_compgen "$(_hledger accounts --flat)" "" "$match"
            )"
            ;;
        -f|--file|--rules-file|-o|--output-file)
            compopt -o filenames
            _hledger_compreply "$(compgen -f -- "$match")"
            ;;
        --pivot)
            compopt -o nosort
            wordlist="code description note payee"
            _hledger_compreply "$(compgen -W "$wordlist" -- "$match")"
            _hledger_compreply_append "$(
                _hledger_compgen "$(_hledger tags)" "" "$match"
            )"
            ;;
        --value)
            wordlist="cost then end now"
            _hledger_compreply "$(compgen -W "$wordlist" -- "$match")"
            ;;
        -X|--exchange)
            _hledger_compreply "$(
                _hledger_compgen "$(_hledger commodities)" "" "$match"
            )"
            ;;
        --color|--colour)
            compopt -o nosort
            wordlist="auto always yes never no"
            _hledger_compreply "$(compgen -W "$wordlist" -- "$match")"
            ;;
        -O|--output-format)
            wordlist="txt csv json sql"
            _hledger_compreply "$(compgen -W "$wordlist" -- "$match")"
            ;;
        --close-acct|--open-acct)
            compopt -o filenames
            _hledger_compreply "$(
                _hledger_compgen "$(_hledger accounts --flat)" "" "$match"
            )"
            ;;
        --debug)
            wordlist="{1..9}"
            _hledger_compreply "$(compgen -W "$wordlist" -- "$match")"
            ;;
        # Argument required, but no handler (yet)
        -b|-e|-p)
            _hledger_compreply ""
            ;;
        # Check if an unhandled long option requires an argument
        *)
            local optionList argRequired

            if [[ -n $subcommandOptions ]]; then
                optionList=${!subcommandOptions}
            else
                optionList=$_hledger_complist_generic_options
            fi

            while IFS= read -r argRequired; do
                if [[ $argRequired == "$option=" ]]; then
                    _hledger_compreply ""
                    return 0
                fi
            done <<< "$optionList"

            return 1
            ;;
    esac

    return 0
}

# Query filter completion through introspection
_hledger_compreply_query() {
    [[ $cur =~ .: ]] || return
    local query=${cur%%:*}:
    local match=${cur#*:}
    grep -Fxqe "$query" <<< "$_hledger_complist_query_filters" || return

    local hledgerArgs=()
    case $query in
        acct:)
            if (( ${#match} )); then
                hledgerArgs=(accounts --flat)
            else
                hledgerArgs=(accounts --flat --depth 1)
            fi
            ;;
        code:)  hledgerArgs=(codes) ;;
        cur:)   hledgerArgs=(commodities) ;;
        desc:)  hledgerArgs=(descriptions) ;;
        note:)  hledgerArgs=(notes) ;;
        payee:) hledgerArgs=(payees) ;;
        tag:)   hledgerArgs=(tags) ;;
        *)
            local wordlist
            case $query in
                amt:)    wordlist="< <= > >=" ;;
                real:)   wordlist="\  0" ;;
                status:) wordlist="\  * !" ;;
                *)       return 1 ;;
            esac
            _hledger_compreply "$(
                compgen -P "$query" -W "$wordlist" -- "$match"
            )"
            return 0
            ;;
    esac

    _hledger_compreply "$(
        _hledger_compgen "$(_hledger "${hledgerArgs[@]}")" "$query"
    )"

    return 0
}

# Parse the command line so far and fill the array $optarg with the arguments to
# given options. $optarg should be declared by the caller
_hledger_optarg() {
    local options=("$@")
    local i j offset
    optarg=()

    # hledger balance --file ~/ledger _
    # 0       1       2      3        4
    for ((i=1; i < ${#words[@]} - 2; i++)); do
        offset=0
        for j in "${!options[@]}"; do
            if [[ ${words[i]} == "${options[j]}" ]]; then
                if [[ ${words[i+1]} == '=' ]]; then
                    offset=2
                else
                    offset=1
                fi
                # Pass it through compgen to unescape it
                optarg+=("$(compgen -W "${words[i + offset]}")")
            fi
        done
        ((i += offset))
    done
}

# Get ledger file from -f --file arguments from COMP_WORDS and pass it to the
# 'hledger' call. Note that --rules-file - if present - must also be passed!
# Multiple files are allowed so pass them all in the order of appearance.
_hledger() {
    local hledgerArgs=("$@")
    local file
    local -a optarg

    _hledger_optarg -f --file
    for file in "${optarg[@]}"; do
        [[ -f $file ]] && hledgerArgs+=(--file "$file")
    done

    _hledger_optarg --rules-file
    for file in "${optarg[@]}"; do
        [[ -f $file ]] && hledgerArgs+=(--rules-file "$file")
    done

    # Discard errors. Is there a way to validate files before using them?
    hledger "${hledgerArgs[@]}" 2>/dev/null
}

# Include lists of commands and options generated by the Makefile using the
# m4 macro processor.
# Included files must have exactly one newline at EOF to prevent weired errors.

read -r -d "" _hledger_complist_commands <<"__TEXT__"
accounts
activity
add
areg
aregister
bal
balance
balancesheet
balancesheetequity
bs
bse
cashflow
cf
check
close
codes
commodities
descriptions
diff
files
help
import
incomestatement
is
notes
payees
prices
print
reg
register
rewrite
roi
stats
tags
test
__TEXT__

read -r -d "" _hledger_complist_query_filters <<"__TEXT__"
acct:
amt:
code:
cur:
date:
date2:
depth:
desc:
inacct:
not:
note:
payee:
real:
status:
tag:
__TEXT__

read -r -d "" _hledger_complist_generic_options <<"__TEXT__"
--alias=
--auto
--begin=
--cleared
--color=
--commodity-style=
--conf=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--man
--market
--monthly
--no-conf
--pending
--period=
--pivot=
--pretty
--quarterly
--real
--rules=
--strict
--tldr
--today=
--unmarked
--value=
--verbose-tags
--version
--weekly
--yearly
__TEXT__

# Dashes are replaced by m4 with underscores to form valid identifiers
# Referenced by indirect expansion of $subcommandOptions

read -r -d "" _hledger_complist_options_accounts <<"__TEXT__"
--alias=
--auto
--begin=
--cleared
--color=
--commodity-style=
--cost
--daily
--date2
--debug=
--declared
--depth=
--directives
--drop=
--empty
--end=
--exchange=
--file=
--find
--flat
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--locations
--man
--market
--monthly
--pending
--period=
--pivot=
--pretty
--quarterly
--real
--rules=
--strict
--tldr
--today=
--tree
--types
--undeclared
--unmarked
--unused
--used
--value=
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_activity <<"__TEXT__"
--alias=
--auto
--begin=
--cleared
--color=
--commodity-style=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--man
--market
--monthly
--pending
--period=
--pivot=
--pretty
--quarterly
--real
--rules=
--strict
--tldr
--today=
--unmarked
--value=
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_add <<"__TEXT__"
--alias=
--auto
--debug=
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--man
--no-new-accounts
--pivot=
--rules=
--strict
--tldr
--verbose-tags
--version
__TEXT__

read -r -d "" _hledger_complist_options_areg <<"__TEXT__"
--alias=
--align-all
--auto
--begin=
--cleared
--color=
--commodity-style=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--man
--market
--monthly
--no-elide
--output-file=
--output-format=
--pending
--period=
--pivot=
--pretty
--quarterly
--real
--rules=
--strict
--tldr
--today=
--txn-dates
--unmarked
--value=
--verbose-tags
--version
--weekly
--width=
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_aregister <<"__TEXT__"
--alias=
--align-all
--auto
--begin=
--cleared
--color=
--commodity-style=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--man
--market
--monthly
--no-elide
--output-file=
--output-format=
--pending
--period=
--pivot=
--pretty
--quarterly
--real
--rules=
--strict
--tldr
--today=
--txn-dates
--unmarked
--value=
--verbose-tags
--version
--weekly
--width=
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_bal <<"__TEXT__"
--alias=
--auto
--average
--begin=
--budget
--change
--cleared
--color=
--commodity-style=
--cost
--count
--cumulative
--daily
--date2
--debug=
--declared
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--gain
--help
--historical
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--invert
--layout
--layout=
--man
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty
--quarterly
--real
--related
--row-total
--rules=
--sort-amount
--strict
--sum
--summary-only
--tldr
--today=
--transpose
--tree
--unmarked
--value=
--valuechange
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_balance <<"__TEXT__"
--alias=
--auto
--average
--begin=
--budget
--change
--cleared
--color=
--commodity-style=
--cost
--count
--cumulative
--daily
--date2
--debug=
--declared
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--gain
--help
--historical
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--invert
--layout
--layout=
--man
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty
--quarterly
--real
--related
--row-total
--rules=
--sort-amount
--strict
--sum
--summary-only
--tldr
--today=
--transpose
--tree
--unmarked
--value=
--valuechange
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_balancesheet <<"__TEXT__"
--alias=
--auto
--average
--begin=
--budget
--change
--cleared
--color=
--commodity-style=
--cost
--cumulative
--daily
--date2
--debug=
--declared
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--gain
--help
--historical
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--layout=
--man
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty
--quarterly
--real
--row-total
--rules=
--sort-amount
--strict
--sum
--summary-only
--tldr
--today=
--tree
--unmarked
--value=
--valuechange
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_balancesheetequity <<"__TEXT__"
--alias=
--auto
--average
--begin=
--budget
--change
--cleared
--color=
--commodity-style=
--cost
--cumulative
--daily
--date2
--debug=
--declared
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--gain
--help
--historical
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--layout=
--man
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty
--quarterly
--real
--row-total
--rules=
--sort-amount
--strict
--sum
--summary-only
--tldr
--today=
--tree
--unmarked
--value=
--valuechange
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_bs <<"__TEXT__"
--alias=
--auto
--average
--begin=
--budget
--change
--cleared
--color=
--commodity-style=
--cost
--cumulative
--daily
--date2
--debug=
--declared
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--gain
--help
--historical
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--layout=
--man
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty
--quarterly
--real
--row-total
--rules=
--sort-amount
--strict
--sum
--summary-only
--tldr
--today=
--tree
--unmarked
--value=
--valuechange
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_bse <<"__TEXT__"
--alias=
--auto
--average
--begin=
--budget
--change
--cleared
--color=
--commodity-style=
--cost
--cumulative
--daily
--date2
--debug=
--declared
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--gain
--help
--historical
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--layout=
--man
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty
--quarterly
--real
--row-total
--rules=
--sort-amount
--strict
--sum
--summary-only
--tldr
--today=
--tree
--unmarked
--value=
--valuechange
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_cashflow <<"__TEXT__"
--alias=
--auto
--average
--begin=
--budget
--change
--cleared
--color=
--commodity-style=
--cost
--cumulative
--daily
--date2
--debug=
--declared
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--gain
--help
--historical
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--layout=
--man
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty
--quarterly
--real
--row-total
--rules=
--sort-amount
--strict
--sum
--summary-only
--tldr
--today=
--tree
--unmarked
--value=
--valuechange
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_cf <<"__TEXT__"
--alias=
--auto
--average
--begin=
--budget
--change
--cleared
--color=
--commodity-style=
--cost
--cumulative
--daily
--date2
--debug=
--declared
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--gain
--help
--historical
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--layout=
--man
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty
--quarterly
--real
--row-total
--rules=
--sort-amount
--strict
--sum
--summary-only
--tldr
--today=
--tree
--unmarked
--value=
--valuechange
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_check <<"__TEXT__"
--alias=
--auto
--begin=
--cleared
--color=
--commodity-style=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--man
--market
--monthly
--pending
--period=
--pivot=
--pretty
--quarterly
--real
--rules=
--strict
--tldr
--today=
--unmarked
--value=
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_close <<"__TEXT__"
--alias=
--assert
--assertion-type=
--assign
--auto
--begin=
--cleared
--close
--close-acct=
--close-desc=
--color=
--commodity-style=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--explicit
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--interleaved
--man
--market
--migrate
--monthly
--open
--open-acct=
--open-desc=
--pending
--period=
--pivot=
--pretty
--quarterly
--real
--retain
--round=
--rules=
--show-costs
--strict
--tldr
--today=
--unmarked
--value=
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_codes <<"__TEXT__"
--alias=
--auto
--begin=
--cleared
--color=
--commodity-style=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--man
--market
--monthly
--pending
--period=
--pivot=
--pretty
--quarterly
--real
--rules=
--strict
--tldr
--today=
--unmarked
--value=
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_commodities <<"__TEXT__"
--alias=
--auto
--debug=
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--man
--pivot=
--rules=
--strict
--tldr
--verbose-tags
--version
__TEXT__

read -r -d "" _hledger_complist_options_descriptions <<"__TEXT__"
--alias=
--auto
--begin=
--cleared
--color=
--commodity-style=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--man
--market
--monthly
--pending
--period=
--pivot=
--pretty
--quarterly
--real
--rules=
--strict
--tldr
--today=
--unmarked
--value=
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_diff <<"__TEXT__"
--alias=
--auto
--debug=
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--man
--pivot=
--rules=
--strict
--tldr
--verbose-tags
--version
__TEXT__

read -r -d "" _hledger_complist_options_files <<"__TEXT__"
--alias=
--auto
--debug=
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--man
--pivot=
--rules=
--strict
--tldr
--verbose-tags
--version
__TEXT__

read -r -d "" _hledger_complist_options_help <<"__TEXT__"
--debug=
--help
--info
--man
--tldr
--version
__TEXT__

read -r -d "" _hledger_complist_options_import <<"__TEXT__"
--alias=
--auto
--begin=
--catchup
--cleared
--color=
--commodity-style=
--cost
--daily
--date2
--debug=
--depth=
--dry-run
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--man
--market
--monthly
--pending
--period=
--pivot=
--pretty
--quarterly
--real
--rules=
--strict
--tldr
--today=
--unmarked
--value=
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_incomestatement <<"__TEXT__"
--alias=
--auto
--average
--begin=
--budget
--change
--cleared
--color=
--commodity-style=
--cost
--cumulative
--daily
--date2
--debug=
--declared
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--gain
--help
--historical
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--layout=
--man
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty
--quarterly
--real
--row-total
--rules=
--sort-amount
--strict
--sum
--summary-only
--tldr
--today=
--tree
--unmarked
--value=
--valuechange
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_is <<"__TEXT__"
--alias=
--auto
--average
--begin=
--budget
--change
--cleared
--color=
--commodity-style=
--cost
--cumulative
--daily
--date2
--debug=
--declared
--depth=
--drop=
--empty
--end=
--exchange=
--file=
--flat
--forecast
--format=
--gain
--help
--historical
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--layout=
--man
--market
--monthly
--no-elide
--no-total
--output-file=
--output-format=
--pending
--percent
--period=
--pivot=
--pretty
--quarterly
--real
--row-total
--rules=
--sort-amount
--strict
--sum
--summary-only
--tldr
--today=
--tree
--unmarked
--value=
--valuechange
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_notes <<"__TEXT__"
--alias=
--auto
--begin=
--cleared
--color=
--commodity-style=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--man
--market
--monthly
--pending
--period=
--pivot=
--pretty
--quarterly
--real
--rules=
--strict
--tldr
--today=
--unmarked
--value=
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_payees <<"__TEXT__"
--alias=
--auto
--begin=
--cleared
--color=
--commodity-style=
--cost
--daily
--date2
--debug=
--declared
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--man
--market
--monthly
--pending
--period=
--pivot=
--pretty
--quarterly
--real
--rules=
--strict
--tldr
--today=
--unmarked
--used
--value=
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_prices <<"__TEXT__"
--alias=
--auto
--begin=
--cleared
--color=
--commodity-style=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--man
--market
--monthly
--pending
--period=
--pivot=
--pretty
--quarterly
--real
--rules=
--show-reverse
--strict
--tldr
--today=
--unmarked
--value=
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_print <<"__TEXT__"
--alias=
--auto
--begin=
--cleared
--color=
--commodity-style=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--explicit
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--man
--market
--match=
--monthly
--new
--output-file=
--output-format=
--pending
--period=
--pivot=
--pretty
--quarterly
--real
--round=
--rules=
--show-costs
--strict
--tldr
--today=
--unmarked
--value=
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_reg <<"__TEXT__"
--alias=
--align-all
--auto
--average
--begin=
--cleared
--color=
--commodity-style=
--cost
--cumulative
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--historical
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--invert
--man
--market
--match=
--monthly
--output-file=
--output-format=
--pending
--period=
--pivot=
--pretty
--quarterly
--real
--related
--rules=
--sort=
--strict
--tldr
--today=
--unmarked
--value=
--verbose-tags
--version
--weekly
--width=
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_register <<"__TEXT__"
--alias=
--align-all
--auto
--average
--begin=
--cleared
--color=
--commodity-style=
--cost
--cumulative
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--historical
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--invert
--man
--market
--match=
--monthly
--output-file=
--output-format=
--pending
--period=
--pivot=
--pretty
--quarterly
--real
--related
--rules=
--sort=
--strict
--tldr
--today=
--unmarked
--value=
--verbose-tags
--version
--weekly
--width=
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_rewrite <<"__TEXT__"
--add-posting=
--alias=
--auto
--begin=
--cleared
--color=
--commodity-style=
--cost
--daily
--date2
--debug=
--depth=
--diff
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--man
--market
--monthly
--pending
--period=
--pivot=
--pretty
--quarterly
--real
--rules=
--strict
--tldr
--today=
--unmarked
--value=
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_roi <<"__TEXT__"
--alias=
--auto
--begin=
--cashflow
--cleared
--color=
--commodity-style=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--investment=
--man
--market
--monthly
--pending
--period=
--pivot=
--pretty
--profit-loss=
--quarterly
--real
--rules=
--strict
--tldr
--today=
--unmarked
--value=
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_stats <<"__TEXT__"
--alias=
--auto
--begin=
--cleared
--color=
--commodity-style=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--man
--market
--monthly
--output-file=
--pending
--period=
--pivot=
--pretty
--quarterly
--real
--rules=
--strict
--tldr
--today=
--unmarked
--value=
--verbose
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_tags <<"__TEXT__"
--alias=
--auto
--begin=
--cleared
--color=
--commodity-style=
--cost
--daily
--date2
--debug=
--depth=
--empty
--end=
--exchange=
--file=
--forecast
--help
--ignore-assertions
--infer-costs
--infer-equity
--infer-market-prices
--info
--man
--market
--monthly
--parsed
--pending
--period=
--pivot=
--pretty
--quarterly
--real
--rules=
--strict
--tldr
--today=
--unmarked
--value=
--values
--verbose-tags
--version
--weekly
--yearly
__TEXT__

read -r -d "" _hledger_complist_options_test <<"__TEXT__"
--debug=
--help
--info
--man
--tldr
--version
__TEXT__

return 0
