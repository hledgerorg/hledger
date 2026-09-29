# TESTS

About testing in the hledger project.
For how to run the tests, see [Developer workflows](DEVWORKFLOWS.md).

## Kinds of tests

<div style="margin:1em 2em; font-style:italic;">
"Here, then, is a list of properties of tests. Not all tests need to exhibit all properties. However, no property should be given up without receiving a property of greater value in return.

- Isolated — tests should return the same results regardless of the order in which they are run.
- Composable — if tests are isolated, then I can run 1 or 10 or 100 or 1,000,000 and get the same results.
- Fast — tests should run quickly.
- Inspiring — passing the tests should inspire confidence
- Writable — tests should be cheap to write relative to the cost of the code being tested.
- Readable — tests should be comprehensible for reader, invoking the motivation for writing this particular test.
- Behavioral — tests should be sensitive to changes in the behavior of the code under test. If the behavior changes, the test result should change.
- Structure-insensitive — tests should not change their result if the structure of the code changes.
- Automated — tests should run without human intervention.
- Specific — if a test fails, the cause of the failure should be obvious.
- Deterministic — if nothing changes, the test result shouldn’t change.
- Predictive — if the tests all pass, then the code under test should be suitable for production."
--[Kent Beck](https://medium.com/@kentbeck_7670/test-desiderata-94150638a4b3)
</div>

1.  Unit tests

    Unit tests exercise small chunks of functionality. In hledger, that
    means a function. So, many of our functions have one or more unit
    tests. These are mostly in hledger-lib, with a few in hledger.

    Our unit tests use the
    [tasty](https://hackage.haskell.org/package/tasty) test runner,
    [tasty-hunit](https://hackage.haskell.org/package/tasty-hunit) HUnit-style tests,
    and some helpers from
    [Hledger.Utils.Test](https://github.com/hledgerorg/hledger/blob/main/hledger-lib/Hledger/Utils/Test.hs),
    such as:

    - `tests` and `test` aliases for `testGroup` and `testCase`
    - `assert*` helpers for constructing various kinds of assertions

    We would like our unit tests to be:

    -   easy to read (clear, concise)
    -   easy to write (low boilerplate, low cognitive load)
    -   easy to maintain (easy to edit, easy to refactor, robust)
    -   easy to associate with the code under test (easy to view/jump
        between code & test, easy to estimate coverage)
    -   and scalable (usable for all devs, easy to run and select,
        suitable for small/large modules/packages).

    Here\'s the current pattern (let us know if you see a better way):

    ``` haskell
    module Foo (
      ...
      tests_Foo -- export this module's and submodules' tests
    )
    where
    import Hledger  -- provides Hledger.Utils.Test helpers
    import Bar      -- submodules, providing tests_Bar etc.
    import Baz

    functionA = ...
    functionB = ...
    functionC = ...
    functionD = ...

    tests_Foo = tests "Foo" [ -- define tests at the end of each module

       -- a group of several named tests for functionA
       tests "functionA" [
         test "a basic test"           $ assertBool "" SOMEBOOL
        ,test "a pretty equality test" $ SOMEEXPR @?= EXPECTEDVALUE
        ,test "a pretty parsing test"  $ assertParseEq PARSER INPUT EXPECTEDRESULT
        ,test "a multiple assertions test" $ do
          A @?= B
          doSomeIO
          C @?= D
        ]

       -- a single test containing multiple unnamed assertions for functionB
      ,test "functionB" $ do
         assertBool "" BOOL
         EXPR @?= VALUE

      ,tests_Bar            -- aggregate submodule tests
      ,tests_Baz
      ]
    ```

    Here are
    [some](https://github.com/hledgerorg/hledger/blob/main/hledger-lib/Hledger/Data/Posting.hs)
    real-world
    [examples](https://github.com/hledgerorg/hledger/blob/main/hledger-lib/Hledger/Read/JournalReader.hs)
    (search for `tests_`).

    The unit tests are shipped as part of the hledger executable, and
    can always be run via the [test](https://hledger.org/hledger.html#test)
    command (`hledger test`).

2.  Doc tests

    Like unit tests, but defined inside functions\' haddock
    documentation, in the style of a GHCI transcript. These test
    functionality, provide usage examples in the API docs, and test
    those examples, all at once. They are a bit more finicky and slower
    than unit tests; running them requires a separate build of hledger-lib.
    See [doctest](https://hackage.haskell.org/package/doctest) for more.

3.  Functional tests

    Functional tests test the overall functioning of the program. For
    hledger, that means running `hledger` with various inputs and
    options and checking for the expected output. This exercises
    functionality in the hledger and hledger-lib packages. We do this
    with
    [shelltestrunner](https://hackage.haskell.org/package/shelltestrunner).
    Tests are defined in files named `*.test` under
    [hledger/test/](https://github.com/hledgerorg/hledger/tree/main/hledger/test),
    grouped by *component* (command or topic name).
    For more about these, see the README there.

    When these test for an error, they usually match just a key phrase of the message.
    The layout of error messages is tested separately in
    [hledger/test/errors/](https://github.com/hledgerorg/hledger/tree/main/hledger/test/errors),
    which has one full-message example of each kind of error message
    (see [ERRORS](ERRORS.md)).

    hledger-web also has some browser tests, defined with playwright in
    [hledger-web/test/browser/](https://github.com/hledgerorg/hledger/tree/main/hledger-web/test/browser);
    see the README there.

4.  Code tests

    We have some tests aimed at testing eg code quality, generally runnable via just.
    Eg `just haddocktest` (haddock generation), `just embedtest` (embedded files),
    `just cabalfilestest` (cabal file syntax).

5.  Package test suites

    Haskell tools like stack and cabal recognise test suites defined in
    a package\'s cabal file (or package.yaml file). These can be run via
    `stack test`, `cabal test` etc., and they are required to build and
    pass by services like Stackage. Here are the current hledger
    package test suites:

    | package     | test suite | what it runs |
    |-------------|------------|--------------|
    | hledger-lib | unittest   | hledger-lib's unit tests |
    | hledger-lib | doctest    | doctests |
    | hledger     | unittest   | builtin test command (hledger\'s + hledger-lib\'s unit tests) |
    | hledger-ui  |            | |
    | hledger-web |            | |

## Coverage

This means how thoroughly the code is tested - both in breadth (are all
parts of the code tested at least a little ?) and in depth (are all
possible code paths, states, situations tested ?).

Our current test coverage can be summarised like so:

| package     | unit | doc | functional |
|-------------|------|-----|------------|
| hledger-lib | X    | X   | X          |
| hledger     | X    |     | X          |
| hledger-ui  |      |     |            |
| hledger-web |      |     | X (browser tests) |

There are ways to generate detailed coverage reports for haskell unit
tests, at least. It would be useful to set this up for hledger.

## How to run tests

See [Developer workflows](DEVWORKFLOWS.md) for the main commands
(`just functest`, `just doctest`, `just test`, `stack test` etc.),
and `just h test` for all test-related scripts.

Also, the unit tests are built in to the hledger executable, and can be
run any time with the `test` command:

``` example
$ hledger test               # run all unit tests
$ hledger test balance       # run tests with "balance" in their name
$ hledger test -- -h         # show tasty test runner options
```
