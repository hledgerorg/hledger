# Regressions

A hledger regression bug is
something that used to work, that broke without notice, in a released version of hledger.

We aim for zero regressions; but in a project with this level of features, flexibility, and level of funding, that's not easy!
So we try to detect them quickly, repair them quickly, and reduce their frequency.

Here are all the regressions found since 2020
(and old related bounties, discussed [below](#old-regression-bounties)).
This page has a shortcut url: [regressions.hledger.org](https://regressions.hledger.org).

<!-- 
This table keeps evolving. Bold things are unresolved. The formatting evolves like this:
     (unclaimed)                (submitted)               (paid)
**NAME FINDORFIXDATE** -> **[NAME](EXPENSEPAGE)** -> [NAME](EXPENSEPAGE)
                                               or -> NAME donated
Finder bounties began on 2021-06-14.
Fixer  bounties began on 2024-01-01.

-->

| New&nbsp;regressions&nbsp; | Fixed&nbsp;in  | Finder bounty                                                                                                                                                                   | Fixer bounty                                                                                            |
|----------------------------|----------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------|
| **1.19** 2020-09-01        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#1568]                    | 1.22           | jolmg         (N/A)                                                                                                                                                             | N/A                                                                                                     |
| [#1688]                    | 1.23           | Simon Michael (N/A)                                                                                                                                                             | N/A                                                                                                     |
| [#1698]                    | 1.23           | [David Lowe](https://opencollective.com/hledger/expenses/50380)                                                                                                                 | N/A                                                                                                     |
| [#1745]                    | 1.24           | [Arne Schlüter](https://opencollective.com/hledger/expenses/54446)                                                                                                              | N/A                                                                                                     |
| [#1800]                    | 1.25           | [Chuck Holmes](https://opencollective.com/hledger/expenses/61802)                                                                                                               | N/A                                                                                                     |
| **1.20** 2020-12-05        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#1439]                    | 1.20.3         | apauley       (N/A)                                                                                                                                                             | N/A                                                                                                     |
| [#1468]                    | 1.21           | Simon Michael (N/A)                                                                                                                                                             | N/A                                                                                                     |
| [#1566]                    | 1.22           | benwebber     (N/A)                                                                                                                                                             | N/A                                                                                                     |
| **1.21** 2021-03-10        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#1508]                    | 1.22           | edlanglois    (N/A)                                                                                                                                                             | N/A                                                                                                     |
| [#1523]                    | 1.22           | Simon Michael (N/A)                                                                                                                                                             | N/A                                                                                                     |
| [#1526]                    | 1.22           | lestephane    (N/A)                                                                                                                                                             | N/A                                                                                                     |
| [#1527]                    | 1.22           | lestephane    (N/A)                                                                                                                                                             | N/A                                                                                                     |
| [#1656]                    | 1.23           | [Stephen Morgan](https://opencollective.com/hledger/expenses/48246)                                                                                                             | N/A                                                                                                     |
| [#2284]                    | 1.41           | [lakshayg](https://opencollective.com/hledger/expenses/227577)                                                                                                                  | GLaknovik (donated)                                                                                     |
| [#2302]                    | 1.42           | [lowercasename](https://opencollective.com/hledger/expenses/232210)                                                                                                             | [Simon Michael](https://opencollective.com/hledger/expenses/264103)                                     |
| **1.22** 2021-07-03        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#1597]                    | 1.22.1         | [Simon Michael](https://opencollective.com/hledger/expenses/44939)                                                                                                              | N/A                                                                                                     |
| [#1607]                    | 1.22.1         | [Simon Michael](https://opencollective.com/hledger/expenses/45547)                                                                                                              | N/A                                                                                                     |
| [#1625]                    | 1.22.1         | [Julian Klode](https://opencollective.com/hledger/expenses/46431)                                                                                                               | N/A                                                                                                     |
| [#1736]                    | 1.24           | [Romain Gehrig](https://opencollective.com/hledger/expenses/55510)                                                                                                              | N/A                                                                                                     |
| [#1851]                    | 1.26           | [Eric Langlois](https://opencollective.com/hledger/expenses/72187)                                                                                                              | N/A                                                                                                     |
| **1.22.1** 2021-08-02      | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#1638]                    | 1.22.2         | [Yann Büchau](https://opencollective.com/hledger/expenses/46918)                                                                                                                | N/A                                                                                                     |
| [#1642]                    | 1.22.2         | Simon Michael (N/A)                                                                                                                                                             | N/A                                                                                                     |
| **1.23** 2021-09-21        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#1933]                    | 1.32           | [Simon Michael](https://opencollective.com/hledger/expenses/95068)                                                                                                              | N/A                                                                                                     |
| [#2071]                    | 1.33           | [William Pierce](https://opencollective.com/hledger/expenses/195768)                                                                                                            | [Simon Michael](https://opencollective.com/hledger/expenses/223927)                                     |
| **1.24** 2021-12-01        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#1782]                    | 1.24.1         | Simon Michael (N/A)                                                                                                                                                             | N/A                                                                                                     |
| **1.25** 2022-03-04        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#2032]                    | 1.32           | [Simon Michael](https://opencollective.com/hledger/expenses/137410)                                                                                                             | N/A                                                                                                     |
| [#2196]                    | 1.33.1         | [Pranesh Prakash](https://opencollective.com/hledger/expenses/220683)                                                                                                           | [Simon Michael](https://opencollective.com/hledger/expenses/223926), <br>Bas van Dijk [#2224] (donated) |
| **1.26** 2022-06-04        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| **1.27** 2022-09-01        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#1932]                    | 1.27.1         | [Andras Fabian](https://opencollective.com/hledger/expenses/95112)                                                                                                              | N/A                                                                                                     |
| [#2018]                    | 1.29.2         | [Allan Odgaard](https://opencollective.com/hledger/expenses/130591)                                                                                                             | N/A                                                                                                     |
| [#2469]                    |                | [Quả Cầu](https://opencollective.com/hledger/expenses/267824)                                                                                                                   | Simon Michael (N/A)                                                                                     |
| **1.28** 2022-12-01        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| **1.29** 2023-03-11        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#2012]                    | 1.32           | Simon Michael   (N/A)                                                                                                                                                           | N/A                                                                                                     |
| [#2020]                    | 1.32           | [Pablo Mora](https://opencollective.com/hledger/expenses/131350)                                                                                                                | N/A                                                                                                     |
| [#2023]                    | 1.32           | [Simon Michael](https://opencollective.com/hledger/expenses/132635)                                                                                                             | N/A                                                                                                     |
| [#2034]                    | 1.32           | Simon Michael   (N/A)                                                                                                                                                           | N/A                                                                                                     |
| [#2045]                    | 1.32           | [Pranesh Prakash](https://opencollective.com/hledger/expenses/150171)                                                                                                           | N/A                                                                                                     |
| [#2153]                    | 1.32.3         | markokocic (donated)                                                                                                                                                            | N/A                                                                                                     |
| **1.30** 2023-06-01        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#2072]                    | 1.32.3         | [Simon Michael](https://opencollective.com/hledger/expenses/223926), <br>usaAmch ([#2137], donated), <br>[ipvych](https://opencollective.com/hledger/expenses/221597) ([#2150]) | [Simon Michael](https://opencollective.com/hledger/expenses/223926)                                     |
| **1.31** 2023-09-03        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#2091]                    | 1.32           | [Petr Slansky](https://opencollective.com/hledger/expenses/166632)                                                                                                              | N/A                                                                                                     |
| [#2115]                    | 1.32           | usaAmch (donated)                                                                                                                                                               | N/A                                                                                                     |
| **1.32** 2023-12-01        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#2125]                    | 1.32.1         | Simon Michael   (N/A)                                                                                                                                                           | N/A                                                                                                     |
| [#2127]                    | 1.32.2         | [Rajeev N](https://opencollective.com/hledger/expenses/177761)                                                                                                                  | N/A                                                                                                     |
| [#2130]                    | 1.32.2         | Simon Michael   (N/A)                                                                                                                                                           | N/A                                                                                                     |
| [#2134]                    | 1.32.2         | pepe_pecas (donated)                                                                                                                                                            | N/A                                                                                                     |
| [#2156]                    | 1.32.3         | ishmaelavila (donated)                                                                                                                                                          | [Simon Michael](https://opencollective.com/hledger/expenses/223926)                                     |
| [#2254]                    | 1.41           | akanshaG42 (donated)                                                                                                                                                            | [Simon Michael](https://opencollective.com/hledger/expenses/223926)                                     |
| [#2407]                    | 1.43.2         | Simon Michael (N/A)                                                                                                                                                             | Simon Michael (N/A)                                                                                     |
| **1.32.1** 2023-12-07      | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#2444]                    | 1.50           | Simon Michael (N/A)                                                                                                                                                             | Simon Michael (N/A)                                                                                     |
| **1.33** 2024-04-18        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#2227]                    | 1.41           | [Henning Thielemann](https://opencollective.com/hledger/expenses/224252)                                                                                                        | [Henning Thielemann](https://opencollective.com/hledger/expenses/224252)                                |
| **1.34** 2024-06-01        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| **1.40** 2024-09-09        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#2225]                    | 1.41           | Bas van Dijk (donated)                                                                                                                                                          | [Henning Thielemann](https://opencollective.com/hledger/expenses/224252)                                |
| **1.41** 2024-12-09        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| **1.42** 2025-03-07        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#2352]                    | 1.42.1         | [Matt Gass](https://opencollective.com/hledger/expenses/242346)                                                                                                                 | N/A                                                                                                     |
| [#2386]                    | 1.42.2         | Simon Michael  (N/A)                                                                                                                                                            | N/A                                                                                                     |
| [#2389]                    | 1.42.2         | [Simaex](https://opencollective.com/hledger/expenses/251451)                                                                                                                    | [Simon Michael](https://opencollective.com/hledger/expenses/250298)                                     |
| **1.43** 2025-06-01        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#2396]                    | 1.43.1         | aragaer (donated)                                                                                                                                                               | [Simon Michael](https://opencollective.com/hledger/expenses/252666)                                     |
| [#2397]                    | 1.43.1         | Dmitry Astapov (donated)                                                                                                                                                        | [Simon Michael](https://opencollective.com/hledger/expenses/252666)                                     |
| [#2405]                    | 1.43.2         | Simon Michael (N/A)                                                                                                                                                             | Simon Michael (N/A)                                                                                     |
| [#2406]                    | 1.43.2         | [Wojciech Geisler](https://opencollective.com/hledger/expenses/253455)                                                                                                          | [Simon Michael](https://opencollective.com/hledger/expenses/253673)                                     |
| [#2417]                    | 1.50           | [Frank Schmidt](https://opencollective.com/hledger/expenses/256445)                                                                                                             | [Simon Michael](https://opencollective.com/hledger/expenses/264102)                                     |
| [#2478]                    | 1.50.3         | [dotlambda](https://opencollective.com/hledger/expenses/269024)                                                                                                                 | [Simon Michael](https://opencollective.com/hledger/expenses/274083)                                     |
| **1.50** 2025-09-03        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#2452]                    | 1.50.1         | [Samim Pezeshki](https://opencollective.com/hledger/expenses/264435)                                                                                                            | Stephen Morgan (N/A)                                                                                    |
| [#2454]                    | 1.50.1         | [Nic Mollel](https://opencollective.com/hledger/expenses/265257)                                                                                                                | Stephen Morgan (N/A)                                                                                    |
| [#2465]                    | 1.50.2         | [Paul Dest](https://opencollective.com/hledger/expenses/266959)                                                                                                                 | Simon Michael (N/A)                                                                                     |
| [#2479]                    | 1.50.3         | [Simon Michael](https://opencollective.com/hledger/expenses/269085)                                                                                                             | [Simon Michael](https://opencollective.com/hledger/expenses/269085)                                     |
| [#2493]                    | 1.50.3         | Simon Michael (N/A)                                                                                                                                                             | Simon Michael (N/A)                                                                                     |
| [#2498]                    | 1.50.4         | Peter Sagerson (donated)                                                                                                                                                        | Simon Michael (N/A)                                                                                     |
| [#2512]                    | 1.51.2         | amano-kenji (donated)                                                                                                                                                           | Simon Michael (N/A)                                                                                     |
| [#2564]                    | 1.52           | [Juliano Solanho](https://opencollective.com/hledger/expenses/290360)                                                                                                           | [Juliano Solanho](https://opencollective.com/hledger/expenses/290360)                                   |
| **1.50.2** 2025-09-26      | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#2495]                    | 1.50.3         | alix-aspersa                                                                                                                                                                    | [Simon Michael](https://opencollective.com/hledger/expenses/274113)                                     |
| **1.50.3** 2025-11-18      | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#2514]                    | 1.51.2         | Simon Michael (N/A)                                                                                                                                                             | Simon Michael (N/A)                                                                                     |
| **1.51** 2025-12-05        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#2503]                    | 1.50.5, 1.51.1 | Simon Michael (N/A)                                                                                                                                                             | Simon Michael (N/A)                                                                                     |
| **1.51.2** 2026-01-08      | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#2553]                    | 1.52           | [pierovera](https://opencollective.com/hledger/expenses/287130)                                                                                                                 | Simon Michael (N/A)                                                                                     |
| **1.52** 2026-03-20        | ---            | ---                                                                                                                                                                             | ---                                                                                                     |
| [#2642]                    |                | Simon Michael (N/A)                                                                                                                                                             | Simon Michael (N/A)                                                                                     |


- [All regression bugs](https://bugs.hledger.org/regressions)
- [Open Collective expense requests](https://opencollective.com/hledger/expenses)  <!-- not ?amount=50-100 because other currencies -->


[#2642]: https://github.com/hledgerorg/hledger/issues/2642
[#2564]: https://github.com/hledgerorg/hledger/issues/2564
[#2553]: https://github.com/hledgerorg/hledger/issues/2553
[#2514]: https://github.com/hledgerorg/hledger/issues/2514
[#2512]: https://github.com/hledgerorg/hledger/issues/2512
[#2503]: https://github.com/hledgerorg/hledger/issues/2503
[#2498]: https://github.com/hledgerorg/hledger/issues/2498
[#2495]: https://github.com/hledgerorg/hledger/issues/2495
[#2493]: https://github.com/hledgerorg/hledger/issues/2493
[#2479]: https://github.com/hledgerorg/hledger/issues/2479
[#2478]: https://github.com/hledgerorg/hledger/issues/2478
[#2469]: https://github.com/hledgerorg/hledger/issues/2469
[#2465]: https://github.com/hledgerorg/hledger/issues/2465
[#2454]: https://github.com/hledgerorg/hledger/issues/2454
[#2452]: https://github.com/hledgerorg/hledger/issues/2452
[#2444]: https://github.com/hledgerorg/hledger/issues/2444
[#2417]: https://github.com/hledgerorg/hledger/issues/2417
[#2407]: https://github.com/hledgerorg/hledger/issues/2407
[#2406]: https://github.com/hledgerorg/hledger/issues/2406
[#2405]: https://github.com/hledgerorg/hledger/issues/2405
[#2397]: https://github.com/hledgerorg/hledger/issues/2397
[#2396]: https://github.com/hledgerorg/hledger/issues/2396
[#2389]: https://github.com/hledgerorg/hledger/issues/2389
[#2386]: https://github.com/hledgerorg/hledger/issues/2386
[#2352]: https://github.com/hledgerorg/hledger/issues/2352
[#2302]: https://github.com/hledgerorg/hledger/issues/2302
[#2284]: https://github.com/hledgerorg/hledger/issues/2284
[#2254]: https://github.com/hledgerorg/hledger/issues/2254
[#2227]: https://github.com/hledgerorg/hledger/issues/2227
[#2225]: https://github.com/hledgerorg/hledger/issues/2225
[#2224]: https://github.com/hledgerorg/hledger/issues/2224
[#2196]: https://github.com/hledgerorg/hledger/issues/2196
[#2156]: https://github.com/hledgerorg/hledger/issues/2156
[#2153]: https://github.com/hledgerorg/hledger/issues/2153
[#2150]: https://github.com/hledgerorg/hledger/issues/2150
[#2137]: https://github.com/hledgerorg/hledger/issues/2137
[#2134]: https://github.com/hledgerorg/hledger/issues/2134
[#2130]: https://github.com/hledgerorg/hledger/issues/2130
[#2127]: https://github.com/hledgerorg/hledger/issues/2127
[#2125]: https://github.com/hledgerorg/hledger/issues/2125
[#2115]: https://github.com/hledgerorg/hledger/issues/2115
[#2091]: https://github.com/hledgerorg/hledger/issues/2091
[#2072]: https://github.com/hledgerorg/hledger/issues/2072
[#2071]: https://github.com/hledgerorg/hledger/issues/2071
[#2045]: https://github.com/hledgerorg/hledger/issues/2045
[#2034]: https://github.com/hledgerorg/hledger/issues/2034
[#2032]: https://github.com/hledgerorg/hledger/issues/2032
[#2023]: https://github.com/hledgerorg/hledger/issues/2023
[#2020]: https://github.com/hledgerorg/hledger/issues/2020
[#2018]: https://github.com/hledgerorg/hledger/issues/2018
[#2012]: https://github.com/hledgerorg/hledger/issues/2012
[#1933]: https://github.com/hledgerorg/hledger/issues/1933
[#1932]: https://github.com/hledgerorg/hledger/issues/1932
[#1851]: https://github.com/hledgerorg/hledger/issues/1851
[#1800]: https://github.com/hledgerorg/hledger/issues/1800
[#1782]: https://github.com/hledgerorg/hledger/issues/1782
[#1745]: https://github.com/hledgerorg/hledger/issues/1745
[#1736]: https://github.com/hledgerorg/hledger/issues/1736
[#1698]: https://github.com/hledgerorg/hledger/issues/1698
[#1688]: https://github.com/hledgerorg/hledger/issues/1688
[#1656]: https://github.com/hledgerorg/hledger/issues/1656
[#1642]: https://github.com/hledgerorg/hledger/issues/1642
[#1638]: https://github.com/hledgerorg/hledger/issues/1638
[#1625]: https://github.com/hledgerorg/hledger/issues/1625
[#1607]: https://github.com/hledgerorg/hledger/issues/1607
[#1597]: https://github.com/hledgerorg/hledger/issues/1597
[#1568]: https://github.com/hledgerorg/hledger/issues/1568
[#1566]: https://github.com/hledgerorg/hledger/issues/1566
[#1527]: https://github.com/hledgerorg/hledger/issues/1527
[#1526]: https://github.com/hledgerorg/hledger/issues/1526
[#1523]: https://github.com/hledgerorg/hledger/issues/1523
[#1508]: https://github.com/hledgerorg/hledger/issues/1508
[#1468]: https://github.com/hledgerorg/hledger/issues/1468
[#1439]: https://github.com/hledgerorg/hledger/issues/1439


## Old regression bounties

From 2021 to 2026-07, we offered bounties for finding or fixing regressions.
This was a good project discipline and good marketing.
But,

- The bounties did not measurably cause regressions to be produced less, or found faster.
  In practice regressions are produced and found at a fairly steady rate, mostly correlated with how ambitious a release is.
- The regression finder bounty was therefore somewhat redundant. Regressions get reported for free, because users want them fixed.
- From 2026, bounties strongly increase the rate of AI-assisted or fully AI-generated-and-discussed submissions, often of low quality, duplicative, or not following our AI policy.
- Managing bounties, and AI submissions, consumes maintainer (and contributor) time that can be better spent elsewhere.
- Finding/fixing regressions isn't our bottleneck; reviewing new code is. So we should use our funds for incentivising that instead.

Here's the old description of the regression bounties, for the record:

> ### Regression finder bounty
> 
> **Before 2026-07** we offered a $50 bounty for newly reported regression bugs (arising any time in the past, still affecting latest main).
> ([original announcement](https://github.com/hledgerorg/hledger/issues/1570))
> 
> ### Regression fixer bounty
> 
> **Before 2026-07** we offered a separate $50 bounty for regression bug fixes landed in main.
> (If you caused the regression, there's no bounty, though we do appreciate you reporting or fixing it.)
> 
> ### Is there a time limit ?
> Yes - once the bounty is confirmed, please claim it within 7 days.
> If not, it will be automatically converted to a project donation at that time.
> This reduces wasteful admin work.
> 
> ### Should I claim the bounty ?
> If you don't want the bounty, you can choose to donate it back to the project treasury,
> by saying so or simply by not claiming it within the time limit.
> But consider claiming - it's good for the project in several ways.
> 
> ### How to claim the bounty
> 
> 1. Discover a new regression and report it in the [hledger bug tracker](http://bugs.hledger.org).
>    And/or, fix an open issue which has the `regression` label.
> 2. Wait for confirmation from the issue manager ([SM](https://joyful.com)).
> 3. Send an expense reimbursement request to [hledger's open collective](https://opencollective.com/hledger).
>    Note this might reveal your real name.
>    Here's the procedure:
>    - at hledger's open collective, click [Submit Expense](https://opencollective.com/hledger/expenses/new).  (If you are logged in, this will be under the ACTIONS menu.)
>    - choose **Invoice**; choose a Payout method; click Next
>    - Expense title: **Regression (finder / fixer / finder & fixer) bounty for #NNNN**
>    - Description: **(Found / Fixed) ISSUEURL, WORKDATE(S)**
>    - Date: **today's date** (you may need to click and select it to make it work)
>    - Amount: **USD 50** (or **100** if you found and fixed).
>      Or convert to another currency with today's rate (and mention that rate in Description).
>    - Next, Submit Expense
> 5. Wait for the finance manager (SM) to get the email notification and approve it. This should not take more than a day or two.
>    (For fastest response, mention on the issue page or in chat that you've submitted.)
> 6. Wait for Open Collective to pay it. This should happen within a week (payouts happen twice a week).
