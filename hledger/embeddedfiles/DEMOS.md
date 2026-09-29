# Scripts and notes for demos
## install.cast
Installing hledger from source with hledger-install
https://asciinema.org/a/567934

``` 80x44
curl -O
https://raw.githubusercontent.com/hledgerorg/hledger/main/hledger-install/hledger-install.sh

ls -l hledger-install.sh less hledger-install.sh

bash hledger-install.sh
```
Issues:
- with PATH not set up, hledger-install does not find the stack it installed

## ghcup.cast
Installing hledger from source with ghcup
```
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org
```

Issues:
- ghcup installs an older version of ghc 9.2
- with PATH not set up, ghcup does not find the cabal it installed

## help.cast
Getting help
### Things to cover
#### hledger  
show this commands list
#### hledger -h  
show hledger's command-line help
#### hledger CMD -h  
show CMD's command-line help and manual
#### hledger help [-i|-m|-p] [TOPIC]  
show hledger's manual with info, man, or pager
#### hledger demo [DEMO] -- [ASCOPTS]  
show brief demos on various topics
#### https://hledger.org  
 html manuals, tutorials, support

## demo.cast
Watching the built-in demos
https://asciinema.org/a/567944

## add.cast
The simplest way to start a journal (add)
https://asciinema.org/a/567935

## print.cast
Show full transactions (print)
https://asciinema.org/a/567936

## balance.cast
Show account balances and changes (balance)
https://asciinema.org/a/567937

