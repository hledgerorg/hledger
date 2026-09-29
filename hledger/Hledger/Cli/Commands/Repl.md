## repl

Start an interactive prompt for running hledger commands.
Input files are reloaded only when they change, so commands run faster.

```flags
Flags:
     --no-watch             disable automatic reloading of changed input
                            files, config aliases and addon commands
```

`hledger repl` starts a read-eval-print loop (REPL) where you can enter commands interactively.
As with the `run` command, each input file (or each input file/input options combination) is parsed just once,
so commands will run more quickly than if you ran them individually at the command line.

The input file(s) specified for the `repl` command will be used throughout the session;
but you can override this temporarily by specifying new `-f` options for a command.

Before running a command, any input files which have changed on disk are automatically reloaded
(including CSV rules files).
Also command aliases are reloaded if the config file has changed,
and addon commands are re-detected if PATH's contents have changed.
The `--no-watch` flag disables all of this reloading,
so as to work with a stable snapshot of the data,
or to avoid file/directory polling on a slow network drive.

Any other general flags given to `repl` - input, reporting, or display flags such as
`-I`, `--strict`, `--alias`, `-b`/`-e`, `--depth`, `--cost`, `--value`, `--color` -
are also applied to every command you run.
A command can still override them by specifying its own flags.

The command syntax is the same as with `run`:

- enter one hledger command at a time, without the usual `hledger` first word
- empty lines and comment text from `#` to end of line are ignored
- enclose arguments in quotes if they contain spaces.

Use `help` (or `h`) to show the quick reference, or `help commands` to list commands.
Addons in PATH and command aliases defined in a config file can also be used.
Generally `repl` should feel much like using hledger at the command line.
But `repl` requires full command names or official abbreviations (it does not recognise ad hoc abbreviations).

To run a single shell command, type `! SHELLCMD` (eg `! ls` or `! git status`).

While it is running, the REPL remembers your command history, and you can navigate in the usual ways:

- Keypad or Emacs navigation keys to edit the current command line
- UP/DOWN or control-P/control-N to step back/forward through history
- control-R to search for a past command
- TAB to complete file paths.

You can type control-C to cancel a long-running command (but only once; typing it a second time will exit the REPL).

In most shells you can type control-Z to temporarily exit to the shell (and then `fg` to return to the REPL).

To exit the REPL, use control-D or `q` or `quit` or `exit`.

### Examples

Start the REPL and enter some commands:
```cli
$ hledger repl 
hledger 1.52
Enter hledger commands. To exit, enter 'quit' or 'exit', or send EOF / control-d.
2025> stats
Main file           : .../2025.journal
...
2025> stats -f 2024/2024.journal 
Main file           : .../2024.journal
...
2025> stats
Main file           : .../2025.journal
...
```

or:
```cli
$ hledger repl -f some.journal
hledger 1.52
Enter hledger commands. To exit, enter 'quit' or 'exit', or send EOF / control-d.
some> bs
...
some> print -b 'last week'
...
some> bs -f other.journal
...
```
