# Climate impact

> Most human endeavours should maintain and publish an environmental cost/benefit report. 
"Cost" means some environmental impact such as resources used (energy, water, land..)  
or undesirable waste generated (carbon dioxide, toxins, heat, noise, harm..)
<!-- --<https://ecoaccounting.org> -->

Here is the beginnings of one for the hledger project, with a catchier name.

## Development
Costs related to developing hledger come from:

- developer machine activity
  - recompiling, linking, building docs, browsing, running IDEs etc.
- test machine activity
  - CI workers recompiling on push, on PR updates etc.
- source code hosting
  - VCS operations, file and artifact hosting, rich web UIs, issue tracking, forks, notifications (github etc.)
- public websites and services
  - hledger.org doc hosting, updating
  - demo.hledger.org hosting
  - discussions (matrix, irc, reddit, hacker news..)
  - media (youtube..)
  - project analysis (libhunt..)

Benefits:
- providing effective accounting tools to people and organisations who would be less effective/less empowered by other tools, potentially unlocking further eco accounting activity and successes
- potentially help advance best practices and community know-how by sharing useful techniques, tools, processes, architecture, patterns

## Delivery
Costs related to packaging and shipping hledger to end-users. Related to development, but broken out separately here. This includes:

- Github artifact building / additional testing beyond standard dev tests
- Hackage hosting/maintenance
- Stackage hosting/maintenance
- Hosting/maintenance in all the other packaging systems and distributions on the Install page
- Download/install/cloning/build work done by user machines

Benefits:
- Roughly speaking, more work done on packaging and delivery means more users able to try out and benefit from the software, magnifying the Development benefits above

## Your hledger usage
Costs from your individual/organisational usage of hledger, other than Delivery costs above, may include:

- Machine usage every time you run hledger
- Hardware upgrade/purchase pressure to satisfy memory/disk space requirements
- Personal and online machine usage and human time while learning, discussing, configuring and maintaining hledger and PTA

Benefits:
- Hopefully, more effective accounting and eco accounting, reducing waste and increasing personal/organisational solvency, success, empowerment and positive impact

## Stats
Some useful statistics to guestimate:

- Yearly cost
- Yearly cost trend
- Cumulative cost
- Predicted lifetime cost
- Comparison with alternate solutions
  
## Related

- https://andymasley.com/visuals/carbon-footprint
