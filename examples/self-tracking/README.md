Some examples of working with the https://www.gibney.org/a_syntax_for_self-tracking logging format
(discussion: https://news.ycombinator.com/item?id=36492033).

If you have a.dat:

```
2020-05-28 18:41 Eat Pizza
2020-05-29 09:00 Slept with the window open
2020-05-29 09:00 Headaches
```

This is close enough to hledger's timedot format to do some reporting.
Each line is interpreted as an empty transaction:

```
$ hledger -f timedot:a.dat print 
2020-05-28 * 18:41 Eat Pizza

2020-05-29 * 09:00 Slept with the window open

2020-05-29 * 09:00 Headaches

```

And you could query those by date or description:

```
$ hledger -f timedot:a.dat print date:2020/5/28
2020-05-28 * 18:41 Eat Pizza

$ hledger -f timedot:a.dat print desc:eat
2020-05-28 * 18:41 Eat Pizza

```

Or by tag, if you added tags like so:

```
2020-05-28 18:41 Eat Pizza  ; food:
2020-05-29 09:00 Slept with the window open  ; body:, sleep:
2020-05-29 09:00 Headaches  ; body:
```

```
$ hledger -f timedot:b.dat print tag:sleep
2020-05-29 * 09:00 Slept with the window open  ; body:, sleep:

```

You could transform your format to a plain text accounting format with quantities.
Eg, make it TSV or CSV:

```
$ perl -pe '$c=0; $c++ while $c < 2 && s/ /\t/' a.dat > c.tsv
$ cat c.tsv
2020-05-28	18:41	Eat Pizza
2020-05-29	09:00	Slept with the window open
2020-05-29	09:00	Headaches
```

and use hledger CSV conversion rules to customise and enrich it:

```
$ cat c.tsv.rules
fields date, time, description

# save the time as a tag
comment time:%time

# count each item as one "event" by default
account1 (events)
amount1  1

# special cases
if pizza
 account1 (food)
 amount1  200 cal
```

Now you have a (single entry) accounting journal:

```
$ hledger -f c.tsv print

2020-05-28 Eat Pizza  ; time:18:41
    (food)         200 cal

2020-05-29 Slept with the window open  ; time:09:00
    (events)               1

2020-05-29 Headaches  ; time:09:00
    (events)               1

```

Allowing quantity reports:

```
$ hledger -f c.tsv balance -MATS cur:cal

Balance changes in 2020-05:

      ||     May    Total  Average 
======++===========================
 food || 200 cal  200 cal  200 cal 
------++---------------------------
      || 200 cal  200 cal  200 cal 
```

```
$ hledger -f c.tsv activity -D desc:headache
2020-05-28 
2020-05-29 *
```

```
$ hledger-bar -v -f c.tsv cur:cal
2020-05	       200 ++
```

```
$ hledger-ui --all -f c.tsv   # explore with a TUI
```

Or, with d.dat:

```
2023-06-27 06:40 Wakeup
2023-06-27 06:40 Last_night_sleep_time: 07h21
2023-06-27 06:40 Last_night_sleep_interruptions: 1
2023-06-27 06:40 Yesterdays_Steps: 11898
2023-06-27 08:49 Temperature: 24.8
2023-06-27 08:49 Humidity: 40%
2023-06-27 09:21 Take_Iron? No
2023-06-27 09:21 Take_VitaminD3? No
```

Convert to character-separated values again (using pipe this time):

```
$ cat d.dat | perl -pe '$c=0; $c++ while $c < 2 && s/ /|/' | perl -pe 's/: /|/; s/\? /?|/' > d.csv
$ cat d.csv
2023-06-27|06:40|Wakeup
2023-06-27|06:40|Last_night_sleep_time|07h21
2023-06-27|06:40|Last_night_sleep_interruptions|1
2023-06-27|06:40|Yesterdays_Steps|11898
2023-06-27|08:49|Temperature|24.8
2023-06-27|08:49|Humidity|40%
2023-06-27|09:21|Take_Iron?|No
2023-06-27|09:21|Take_VitaminD3?|No
```

Again, use rules to convert/enrich (or, add more structure in the source data,
requiring less enrichment):

```
$ cat d.csv.rules
separator |
fields date, time, description, value

comment time:%time, value:%value

account1 (events)

amount1  1
if %value ^[0-9]+$
 amount1 %value
if steps
 amount1 %value steps
if %value no
 amount1 0
if %value yes
 amount1 1

if
wake
sleep
 account1 (body:sleep)

if
steps
 account1 (body:exercise)

if
iron
vitamin
 account1 (body:supplements)

if
pizza
 account1 (food)
 amount1  200 cal
```

```
$ hledger -f d.csv print
2023-06-27 Wakeup  ; time:06:40, value:
    (body:sleep)               1

2023-06-27 Last_night_sleep_time  ; time:06:40, value:07h21
    (body:sleep)               1

2023-06-27 Last_night_sleep_interruptions  ; time:06:40, value:1
    (body:sleep)               1

2023-06-27 Yesterdays_Steps  ; time:06:40, value:11898
    (body:exercise)     11898 steps

2023-06-27 Temperature  ; time:08:49, value:24.8
    (events)               1

2023-06-27 Humidity  ; time:08:49, value:40%
    (events)               1

2023-06-27 Take_Iron?  ; time:09:21, value:No
    (body:supplements)               0

2023-06-27 Take_VitaminD3?  ; time:09:21, value:No
    (body:supplements)               0

```

```
$ hledger -f d.csv register sleep
2023-06-27 Wakeup               (body:sleep)                     1             1
2023-06-27 Last_night_sleep_..  (body:sleep)                     1             2
2023-06-27 Last_night_sleep_..  (body:sleep)                     1             3
```

```
$ hledger -f d.csv tags
time
value
```

hledger's data model doesn't include time, but we can pivot on the time tag
and take advantage of the colon to summarise activities by hour each day (eg):

```
$ hledger -f d.csv bal --pivot=time --depth 1 -DAE

Balance changes in 2023-06-27:

    ||            2023-06-27                Average 
====++==============================================
 06 || 3 events, 11898 steps  3 events, 11898 steps 
 08 ||              2 events               2 events 
 09 ||                     0                      0 
----++----------------------------------------------
    || 5 events, 11898 steps  5 events, 11898 steps 
```
