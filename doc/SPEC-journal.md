# journal format

Key features of hledger's journal syntax:

1. Indentation matters: Postings must be indented (at least one space or tab)
2. Double-space rule: In many contexts, a double space separates fields (like between account name and amount)
3. Status marks: * for cleared, ! for pending
4. Virtual postings: Accounts in parentheses (account) or brackets [account] denote virtual postings
5. Comments: Lines starting with ;, #, *, %, or any indented line starting with ;
6. Balance assertions: =, =*, ==, ==* variants
7. Costs: @ for unit cost, @@ for total cost, {} for lot costs
8. Flexible amounts: Commodity symbols can appear before or after quantities; different number styles supported

## Grammar

A rough approximation of hledger's journal format. For documentation only.
May not be completely in sync with the implementation (JournalReader.hs, Common.hs).

This EBNF is simplified and doesn't capture all edge cases
(like virtual postings, lot dates, multipliers in transaction modifiers, etc.)
but covers the core syntax elements.

See also: hledger.m4.md > Journal > Journal cheatsheet

```ebnf
(* Journal Structure *)
journal = { journal-item } ;

journal-item = transaction
             | periodic-transaction
             | transaction-modifier
             | directive
             | market-price-directive
             | comment-line
             | blank-line ;

(* Comments *)
comment-line = ( ";" | "#" | "*" | "%" ), { any-char - newline }, newline ;
line-comment = ";", { any-char - newline } ;
blank-line = [ whitespace ], newline ;

(* Transactions *)
transaction = simple-date, [ "=", secondary-date ], [ whitespace ],
              [ status ], [ code ], [ description ], [ line-comment ], newline,
              [ transaction-comment ],
              { posting } ;

periodic-transaction = "~", [ whitespace ], period-expr, [ whitespace ],
                      [ status ], [ code ], [ description ], [ line-comment ], newline,
                      [ transaction-comment ],
                      { posting } ;

transaction-modifier = "=", [ whitespace ], query-expr, [ line-comment ], newline,
                      [ transaction-comment ],
                      { posting } ;

simple-date = date-year, date-sep, date-month, date-sep, date-day ;
secondary-date = simple-date ;
date-year = digit, digit, digit, digit ;
date-month = digit, [ digit ] ;
date-day = digit, [ digit ] ;
date-sep = "/" | "-" | "." ;

status = "*"   (* cleared *)
       | "!"   (* pending *)
       ;

code = "(", { any-char - ")" }, ")" ;

description = { any-char - ";" - newline } ;

transaction-comment = { comment-line-indented } ;
comment-line-indented = whitespace-1, ";", { any-char - newline }, newline ;

(* Postings *)
posting = whitespace-1, [ status ], [ whitespace ],
          account-name, [ whitespace ],
          [ amount-expr ], [ whitespace ],
          [ balance-assertion ], [ whitespace ],
          [ line-comment ], newline,
          [ posting-comment ] ;

posting-comment = { comment-line-indented } ;

account-name = account-name-component, { ":", account-name-component } ;
account-name-component = account-char, { account-char } ;
account-char = any-char - ";" - newline - ":" - "  " (* two spaces *) ;

(* Amounts *)
amount-expr = amount, [ cost-expr ] ;

amount = [ "-" | "+" ], commodity-symbol, quantity-no-sep
       | [ "-" | "+" ], quantity, [ whitespace ], commodity-symbol ;

quantity = { digit | digit-group-mark }, decimal-mark, { digit }
         | { digit | digit-group-mark }
         | decimal-mark, digit, { digit } ;

quantity-no-sep = { digit }, [ decimal-mark, { digit } ] ;

commodity-symbol = ( letter, { letter | digit | symbol-char } )
                 | ( symbol-char, { symbol-char } )
                 | ( '"', { any-char - '"' }, '"' ) ;

decimal-mark = "." | "," ;
digit-group-mark = "," | "." | " " ;

(* Cost notation *)
cost-expr = unit-cost | total-cost | lot-cost ;

unit-cost = "@", [ whitespace ], amount ;
total-cost = "@@", [ whitespace ], amount ;

lot-cost = "{", [ whitespace ], [ "=" ], [ whitespace ], amount, [ whitespace ], "}"
         | "{{", [ whitespace ], [ "=" ], [ whitespace ], amount, [ whitespace ], "}}"
         | "[", simple-date, "]" ;

(* Balance Assertions *)
balance-assertion = "=", [ "=" ], [ whitespace ], amount
                  | "=", [ "=" ], [ "=" ], [ whitespace ], amount (* == for subaccount inclusive *) ;

(* Directives *)
directive = [ "!" | "@" ], directive-keyword ;

directive-keyword = account-directive
                  | commodity-directive
                  | default-commodity-directive
                  | default-year-directive
                  | alias-directive
                  | end-aliases-directive
                  | payee-directive
                  | tag-directive
                  | apply-account-directive
                  | end-apply-account-directive
                  | include-directive
                  | decimal-mark-directive ;

account-directive = "account", whitespace-1, account-name,
                   [ line-comment ], newline,
                   { subdirective } ;

commodity-directive = "commodity", whitespace-1,
                     ( amount | commodity-symbol ),
                     [ line-comment ], newline,
                     { subdirective } ;

subdirective = whitespace-1, ( "format", whitespace-1, amount
                             | any-text ), newline ;

default-commodity-directive = "D", whitespace-1, amount, newline ;

default-year-directive = ( "Y" | "year" | "apply year" ),
                        [ whitespace ], date-year, newline ;

alias-directive = "alias", whitespace-1, ( account-name, "=", account-name
                 | "/", regex, "/", "=", replacement ), newline ;

end-aliases-directive = "end", whitespace-1, "aliases", newline ;

payee-directive = "payee", whitespace-1, ( quoted-text | text ), [ line-comment ], newline ;

tag-directive = "tag", whitespace-1, tag-name, [ line-comment ], newline ;

apply-account-directive = "apply", whitespace-1, "account", whitespace-1, account-name, newline ;

end-apply-account-directive = "end", whitespace-1, "apply", whitespace-1, "account", newline ;

include-directive = "include", whitespace-1, file-path, [ line-comment ], newline ;

decimal-mark-directive = "decimal-mark", whitespace-1, ( "." | "," ), newline ;

(* Market prices *)
market-price-directive = "P", [ whitespace ], datetime,
                        whitespace-1, commodity-symbol,
                        whitespace-1, amount, newline ;

datetime = simple-date, [ whitespace-1, time ] ;
time = digit, digit, ":", digit, digit, [ ":", digit, digit ], [ timezone ] ;
timezone = ( "+" | "-" ), digit, digit, digit, digit ;

(* Period expressions for periodic transactions *)
period-expr = interval, [ whitespace-1, "from", whitespace-1, simple-date ],
             [ whitespace-1, "to", whitespace-1, simple-date ]
           | simple-date, [ whitespace-1, "to", whitespace-1, simple-date ]
           | "every", whitespace-1, interval ;

interval = "daily" | "weekly" | "monthly" | "quarterly" | "yearly"
         | "every", whitespace-1, number, whitespace-1, ( "days" | "weeks" | "months" | "quarters" | "years" )
         | "every", whitespace-1, nth, whitespace-1, day-of-week,
           [ whitespace-1, "of", whitespace-1, "month" ] ;

day-of-week = "monday" | "tuesday" | "wednesday" | "thursday" | "friday" | "saturday" | "sunday" ;

nth = "1st" | "2nd" | "3rd" | digit, "th" ;

(* Common elements *)
query-expr = any-text ;
file-path = any-text ;
tag-name = letter, { letter | digit | "-" | "_" } ;
quoted-text = '"', { any-char - '"' }, '"' ;
text = { any-char - ";" - newline } ;
any-text = { any-char - newline } ;
number = digit, { digit } ;

whitespace = { " " | tab } ;
whitespace-1 = ( " " | tab ), { " " | tab } ;

digit = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ;
letter = "a" | ... | "z" | "A" | ... | "Z" ;
symbol-char = "$" | "£" | "€" | "¥" | etc. ;
any-char = ? any character ? ;
newline = "\n" ;
tab = "\t" ;
```

