## run 

Run a sequence of hledger commands, provided as files or command line arguments.
Input files are parsed just once, so the commands run faster.

```flags
Flags:
no command-specific flags
```

You can use `run` in three ways:

- `hledger run -- CMD1 -- CMD2 -- CMD3`  - read commands from the command line, separated by `--`
- `hledger run SCRIPTFILE1 SCRIPTFILE2`  - read commands from one or more files
- `cat SCRIPTFILE1 | hledger run`        - read commands from standard input.

`run` first loads the input file(s) specified by `LEDGER_FILE` or by `-f` options, in the usual way.
Then it runs each command in turn, each using the same input data.
But if you want a particular command to use different input, you can specify an `-f` option within that command.
This will override (not add to) the default input, just for that command.

Any other general flags given to `run` - input, reporting, or display flags such as
`-I`, `--strict`, `--alias`, `-b`/`-e`, `--depth`, `--cost`, `--value`, `--color` -
are also applied to every command it runs.
A command can still override them by specifying its own flags.

Each input file (more precisely, each combination of input file and input options) is parsed only once.
This means that commands will not see any changes made to these files, until the next run.
But the commands will run more quickly than if run individually (typically about twice as fast).

Command scripts, whether in a file or written on the command line, have a simple syntax:

- each line may contain a single hledger command and its arguments, without the usual `hledger` first word
- empty lines are ignored
- text from `#` to end of line is a comment, and ignored
- you can use single or double quotes to quote arguments when needed, as on the command line
- these extra commands are available: `echo TEXT` prints some text (interpreting the backslash escapes `\n`, `\t`, `\r`, `\\`), and `exit` or `quit` ends the run.

On unix systems you can use `#!/usr/bin/env hledger run` in the first line of a command file to make it a runnable script.
If that gives an error, use `#!/usr/bin/env -S hledger run`.

It's ok to use the `run` command recursively within a command script.

Command aliases defined in a config file can also be used in command scripts.

You may find some differences in behaviour between `run` command lines and normal hledger command lines.
`run` is a little stricter;
eg it requires full command names or official abbreviations (as seen in the commands list),
and command options must be written after the command name.

### Examples

Run commands from the command line:
```cli
hledger -f some.journal run -- balance assets --depth 2 -- balance liabilities -f /some/other.journal --depth 3 --transpose -- stats
```
This would load `some.journal`, run `balance assets --depth 2` on it, then run `balance liabilities --depth 3 --transpose` on `/some/other.journal`, and finally run `stats` on `some.journal`

Run commands from standard input:
```cli
(echo "files"; echo "stats") | hledger -f some.journal run
```

Run commands as a script:
```cli
$ cat report
#!/usr/bin/env -S hledger run -f some.journal

echo "List of accounts in some.journal"
accounts

echo "Assets of some.journal"
balance assets --depth 2

echo "Liabilities from /some/other.journal"
balance liabilities -f /some/other.journal --depth 3 --transpose

echo "Commands from another.script, applied to another.journal"
run -f another.journal another.script
```
```cli
$ chmod +x report
$ ./report
List of accounts in some.journal
...
```
