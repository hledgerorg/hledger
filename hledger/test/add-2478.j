; Example from https://github.com/hledgerorg/hledger/issues/2478 -
; the funky ordering requires whole-journal awareness when checking balance assertions.

2025-01-02 second transaction
    a                            1 ==* 1    ; date:1/1
    b                           -1

2025-01-01 first transaction
    a                           -1
    c                            1

