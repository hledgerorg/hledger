; Testing behaviour at PeriodData's limit.
; PeriodData is used in multi-period reports.
; On a 64 bit machine it can work with dates from -25252734927764696-04-22 to 25252734927768413-06-12.
; Dates outside that range wrap around, giving wrong results:
;
; $ hledger -f examples/farfuture.j reg -O csv -Y
; "txnidx","date","code","description","account","amount","total"
; "0","-25252734927764696-11-10","","","expenses","6","6"

25252734927768413-06-12 PeriodData's max date
   (expenses)   1

25252734927768413-06-13 one day past PeriodData's max date
   (expenses)   2

25252734927768413-12-01 farther past PeriodData's max date, same year
   (expenses)   3

25252734927768414-01-01 next year past PeriodData's max date
   (expenses)   4
