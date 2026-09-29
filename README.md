# hledger

## Robust, intuitive plain text accounting
[![license](https://img.shields.io/badge/license-GPLv3+-brightgreen.svg)](https://www.gnu.org/licenses/gpl.html)
[![on hackage](https://img.shields.io/hackage/v/hledger.svg?label=hackage&colorB=green)](https://hackage.haskell.org/package/hledger)
[![](https://repology.org/badge/version-for-repo/stackage_nighly/hledger.svg)](https://repology.org/metapackage/hledger)
[![](https://repology.org/badge/version-for-repo/stackage_lts/hledger.svg)](https://repology.org/metapackage/hledger)
[![Open issues, all kinds](https://img.shields.io/github/issues/hledgerorg/hledger.svg "Open issues, all kinds.")](https://github.com/hledgerorg/hledger/issues?q=is:issue+state:open)

Welcome! This is a brief intro to hledger. For a more detailed version, see the home page: **<https://hledger.org>**

hledger is lightweight, cross platform, multi-currency, double-entry accounting software.
It lets you track money, investments, cryptocurrencies, invoices, time, inventory and more, 
in a safe, future-proof plain text data format with full version control and privacy. 

hledger aims to help both computer experts and regular folks
gain clarity in their finances and time management.
Though the UIs are basic, hledger can model any accounting situation and provide precise, clear reports.
It is reliable, quick, and backed by the highly supportive [Plain Text Accounting](https://plaintextaccounting.org) ecosystem. 
Using it is an excellent way to learn double entry accounting.

Compared to [other PTA apps](https://plaintextaccounting.org/#software), 
hledger is actively maintained, with regular releases,
and a strong focus on being easy to use and practical for everyday accounting.

More features:
- Installs easily on unix, mac or windows
- Complete, built-in documentation in multiple formats, beginner videos, tutorials etc.
- Multiple UIs: command-line, terminal, web, mobile, editors/IDEs
- Good at importing and exporting CSV; also outputs text/HTML/JSON/SQL
- A robust, general, well-specified multi-currency accounting engine
- Fast, analysing 25k transactions per second on a macbook air m1
- Accurate to 255 decimal places
- Supports your preferred account names, currencies, number formats
- Inspired by and partly compatible with Ledger CLI; interconvertible with Beancount
- Scriptable by CLI, HTTP or API, with plenty of examples
- Clean Haskell codebase, continually improved since 2007
- Free software licensed under GNU General Public License v3.0 or later.

## Examples

I use hledger to:
- track income and spending, sometimes with budgets
- see time reports by day/week/month/project
- track reimbursables, invoices and payments
- predict cashflow and account balances
- get accurate numbers for tax filing
- research past events

Here's an example of the journal file format:
```journal
2022-01-01 opening balances as of this date
    assets:bank:checking                $1000
    assets:bank:savings                 $2000
    assets:cash                          $100
    liabilities:creditcard               $-50
    equity:opening/closing balances

2022-01-15 market
    expenses:food             $50
    assets:cash              $-50

2022-02-01 GOODWORKS CORP
    assets:bank:checking           $1000
    income:salary                 $-1000
```
and some simple reports:
```cli
$ hledger bs
Balance Sheet 2022-02-15

                        || 2022-02-15 
========================++============
 Assets                 ||            
------------------------++------------
 assets:bank:checking   ||      $2000 
 assets:bank:savings    ||      $2000 
 assets:cash            ||        $50 
------------------------++------------
                        ||      $4050 
========================++============
 Liabilities            ||            
------------------------++------------
 liabilities:creditcard ||        $50 
------------------------++------------
                        ||        $50 
========================++============
 Net:                   ||      $4000 
```
```cli
$ hledger is --monthly                                            
Income Statement 2022-01-01..2022-02-28                                               
                                                                                      
               ||  Jan    Feb                                                         
===============++=============                                                        
 Revenues      ||                                                                     
---------------++-------------                                                        
 income:salary ||    0  $1000                                                         
---------------++-------------                                                        
               ||    0  $1000                                                         
===============++=============                                                        
 Expenses      ||                                                                     
---------------++-------------                                                        
 expenses:food ||  $50      0                                                         
---------------++-------------                                                        
               ||  $50      0                                                         
===============++=============                                                        
 Net:          || $-50  $1000                                                         
```

More examples and screenshots: <https://hledger.org/#how-to-get-started>

## hledger 1.x and 2.x

In 2026, the `master` branch was renamed to `hledger1`,
and work began on hledger 2.x, now in the `main` branch.

Some goals for 2.x:

- continue and improve 1.x's reliability
- provide excellent lot tracking and capital gains calculation
- explore ethical use of AI as a dev tool
- more cleanup and simplification of code, docs, process, finance
- more speed
- more interoperability
- more use of jj for version management
- easier contribution

and for 1.x:

- continued stability, installability
- bugfix releases to fix newly discovered regressions, if any
- preserve the non-AI-assisted codebase, and try to keep it that way

Related:

- [Thoughts on hledger 2 #2547](https://github.com/hledgerorg/hledger/issues/2547)
- <https://hledger.org/AI.html>
- <https://hledger.org/relnotes.html#2026-03-28-hledger-1991>

## Funding

hledger is brought to you by
[Simon Michael](http://joyful.com),
[140+ contributors](doc/CREDITS.md),
and the generous financial sponsors below.

After enjoying some personal or organisational success with hledger,
you might want to become one of them, to help support this work.
It's easy! Please see <https://hledger.org/sponsor.html> for details.

<!-- SPONSOR AVATARS BEGIN (generated by update-sponsors.sh, do not edit) -->
<a href="https://www.octoberswimmer.com" title="October Swimmer"><img src="https://images.opencollective.com/october-swimmer/487d631/logo/400.png" alt="October Swimmer" height="200"></a>
<a href="https://writersperhour.com" title="Writers Per Hour"><img src="https://images.opencollective.com/writersperhour/033b80a/logo/400.png" alt="Writers Per Hour" height="135"></a>
<a href="https://www.apmhelp.com" title="APM Help"><img src="https://images.opencollective.com/apmhelp/6d865c8/logo/400.png" alt="APM Help" height="117"></a>
<a href="https://finmasters.com" title="FinMasters"><img src="https://images.opencollective.com/finmasters/22f821d/logo/400.png" alt="FinMasters" height="102"></a>
<a href="https://opencollective.com/diasparsoft" title="Diaspar Software Services"><img src="https://images.opencollective.com/diasparsoft/logo/400.png" alt="Diaspar Software Services" height="88"></a>
<a href="https://joyful.com" title="Joyful Systems"><img src="https://images.opencollective.com/joyfulsystems/d7ce8c3/logo/400.png" alt="Joyful Systems" height="79"></a>
<br>
<a href="https://www.olsensrevision.dk" title="Olsens Revision ApS"><img src="https://images.opencollective.com/olsensrevision/c629690/avatar/400.png" alt="Olsens Revision ApS" height="120"></a>
<a href="https://opencollective.com/tony-xiao1" title="Tony Xiao"><img src="https://images.opencollective.com/tony-xiao1/a7aacdd/avatar/400.png" alt="Tony Xiao" height="75"></a>
<a href="https://joyful.com/" title="Simon Michael"><img src="https://images.opencollective.com/simon/f44851a/avatar/400.png" alt="Simon Michael" height="74"></a>
<a href="https://github.com/rhyanki" title="Rishi Hyanki"><img src="https://images.opencollective.com/rhyanki/avatar/400.png" alt="Rishi Hyanki" height="68"></a>
<a href="https://twitter.com/b_barker" title="Brandon Barker"><img src="https://images.opencollective.com/brandonbarker/595022d/avatar/400.png" alt="Brandon Barker" height="66"></a>
<a href="https://opencollective.com/jack-todaro" title="Jack Todaro"><img src="https://images.opencollective.com/jack-todaro/avatar/400.png" alt="Jack Todaro" height="66"></a>
<a href="https://opencollective.com/richard-kelly" title="Richard Kelly"><img src="https://images.opencollective.com/richard-kelly/1b2c64c/avatar/400.png" alt="Richard Kelly" height="64"></a>
<a href="https://opencollective.com/james-blachly" title="James Blachly"><img src="https://images.opencollective.com/james-blachly/ffc8288/avatar/400.png" alt="James Blachly" height="63"></a>
<a href="https://opencollective.com/ken-ewing" title="Ken Ewing"><img src="https://images.opencollective.com/ken-ewing/b5ace9b/avatar/400.png" alt="Ken Ewing" height="62"></a>
<a href="https://opencollective.com/marc11" title="Marc"><img src="https://images.opencollective.com/marc11/avatar/400.png" alt="Marc" height="60"></a>
<!-- SPONSOR AVATARS END -->

<!-- (If your logo/avatar isn't appearing here, eg because you didn't use Open Collective, please [let me know](mailto:webmaster@hledger.org).) -->
