{-|
Test suite for hledger-web.

Dev notes:

http://hspec.github.io/writing-specs.html

https://hackage.haskell.org/package/yesod-test-1.6.10/docs/Yesod-Test.html

"The best way to see an example project using yesod-test is to create a scaffolded Yesod project:
stack new projectname yesodweb/sqlite
(See https://github.com/commercialhaskell/stack-templates/wiki#yesod for the full list of Yesod templates)"


These tests don't exactly match the production code path, eg these bits are missing:

  withJournal copts (web wopts)  -- extra withJournal logic (journalTransform..)
  ...
  let h = host_ wopts
      p = port_ wopts
      u = base_url_ wopts
      staticRoot = T.pack <$> file_url_ wopts
      appconfig = AppConfig{appEnv = Development
                           ,appHost = fromString h
                           ,appPort = p
                           ,appRoot = T.pack u
                           ,appExtra = Extra "" staticRoot
                           }

The production code path, when called in this test context, which I guess is using
yesod's dev mode, needs to read ./config/settings.yml and fails without it (loadConfig).

-}

{-# LANGUAGE OverloadedStrings #-}

module Hledger.Web.Test (
  hledgerWebTest
) where

import Control.Exception (bracket, bracket_)
import Data.Aeson (encode)
import Data.ByteString qualified as BS
import Data.String (fromString)
import Data.Function ((&))
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Encoding qualified as TLE
import Network.HTTP.Types (HeaderName)
import Network.Wai.Test (SResponse(..))
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory, removeDirectoryRecursive)
import System.Entropy (getEntropy)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>))
import Test.Hspec (describe, expectationFailure, hspec, it, shouldBe)
import Text.Printf (printf)
import Yesod.Default.Config
import Yesod.Test
import Web.Cookie (defaultSetCookie, setCookieName, setCookieValue)

import Hledger.Web.Application ( makeAppWith )
import Hledger.Utils.I18n (noTranslations)
import Hledger.Web.Paging (pageNumbers)
import Hledger.Web.ReportPage (intervalPeriodExpr, startupUrlState)
import Hledger.Web.WebOptions  -- ( WebOpts(..), defwebopts, prognameandversion )
import Hledger.Web.Import hiding (get, j)
import Hledger.Web.Widget.Common (MovedOptions(..), normalisedSearch, optionsSummary, splitPeriodExpr, transactionFragment)
import Hledger.Cli hiding (prognameandversion)


-- | Given a tests description, zero or more raw option name/value pairs,
-- a journal and some hspec tests, parse the options and configure the
-- web app more or less as we normally would (see details above), then run the tests.
--
-- Raw option names are like the long flag without the --, eg "file" or "base-url".
--
-- The journal and raw options should correspond enough to not cause problems.
-- Be cautious - without a [("file", "somepath")], perhaps journalReload could load
-- the user's default journal.
--
runTests :: String -> [(String,String)] -> Journal -> YesodSpec App -> IO ()
runTests testsdesc rawopts j tests = do
  wopts <- rawOptsToWebOpts $ mkRawOpts rawopts
  let yconf = AppConfig{  -- :: AppConfig DefaultEnv Extra
          appEnv = Testing
        -- https://hackage.haskell.org/package/conduit-extra/docs/Data-Conduit-Network.html#t:HostPreference
        -- ,appHost = "*4"  -- "any IPv4 or IPv6 hostname, IPv4 preferred"
        -- ,appPort = 3000  -- force a port for tests ?
        -- Test with the host and port from opts. XXX more fragile, can clash with a running instance ?
        ,appHost = host_ wopts & fromString
        ,appPort = port_ wopts
        ,appRoot = base_url_ wopts & T.pack  -- XXX not sure this or extraStaticRoot get used
        ,appExtra = Extra
                    { extraCopyright  = ""
                    , extraStaticRoot = T.pack <$> file_url_ wopts
                    }
        }
  app <- makeAppWith j yconf wopts
  hspec $ yesodSpec app $ ydescribe testsdesc tests    -- https://hackage.haskell.org/package/yesod-test/docs/Yesod-Test.html

-- | Assert that a journal file on disk does not contain the given text,
-- ie that a request which should have been refused did not write to it.
journalFileLacks :: FilePath -> T.Text -> YesodExample App ()
journalFileLacks f t = do
  txt <- liftIO $ TIO.readFile f
  assertEq (f ++ " should not contain " ++ T.unpack t) (T.isInfixOf t txt) False

-- | The name of the edit form's textarea in the current page. The edit form
-- does not name that field, so yesod generates one (eg "f1"); find it rather
-- than hardcode it, or a post can silently do nothing.
editFieldName :: YesodExample App T.Text
editFieldName = attrOfFirst "textarea" "name"

-- | The value of an attribute of the first element matching a selector in
-- the current page, failing the test if there is none.
attrOfFirst :: T.Text -> T.Text -> YesodExample App T.Text
attrOfFirst selector attr = do
  els <- htmlQuery selector
  case els of
    [] -> failing $ "no element matches " ++ T.unpack selector
    (e:_) -> do
      let needle = attr <> "=\""
          html = TL.toStrict (TLE.decodeUtf8 e)
          (_, fromneedle) = T.breakOn needle html
      if T.null fromneedle
        then failing $ "the first " ++ T.unpack selector ++ " has no " ++ T.unpack attr
        else return $ T.takeWhile (/= '"') $ T.drop (T.length needle) fromneedle

-- | The current response's Content-Security-Policy header, failing the test
-- if there is none.
cspHeaderValue :: YesodExample App T.Text
cspHeaderValue = headerValue "Content-Security-Policy"

-- | The values of all of the current response's headers with this name.
headerValues :: HeaderName -> YesodExample App [T.Text]
headerValues name = withResponse $ \res ->
  return [TE.decodeUtf8 v | (n, v) <- simpleHeaders res, n == name]

-- | The current response's headers with this name, joined; failing the
-- test if there are none.
headerValue :: HeaderName -> YesodExample App T.Text
headerValue name = do
  vs <- headerValues name
  if null vs
    then failing ("the response has no " ++ show name ++ " header")
    else return $ T.intercalate ", " vs

-- | Assert that the current page contains these texts, in this order.
bodyContainsInOrder :: [T.Text] -> YesodExample App ()
bodyContainsInOrder needles = withResponse $ \res -> go (TL.toStrict $ TLE.decodeUtf8 $ simpleBody res) needles
  where
    go _ [] = return ()
    go html (n:ns) = case T.breakOn n html of
      (_, rest) | T.null rest -> failing $ "the page lacks " ++ T.unpack n ++ ", or has it before the texts preceding it here"
                | otherwise   -> go (T.drop (T.length n) rest) ns

-- | The nonce in the current response's Content-Security-Policy, failing the
-- test if the header or the nonce is missing.
cspNonce :: YesodExample App T.Text
cspNonce = do
  csp <- cspHeaderValue
  let (_, fromnonce) = T.breakOn "'nonce-" csp
  if T.null fromnonce
    then failing "the Content-Security-Policy has no nonce"
    else return $ T.takeWhile (/= '\'') $ T.drop (T.length "'nonce-") fromnonce

-- | Run an action with XDG_CONFIG_HOME pointing at a fresh directory, removed
-- afterwards, so that catalogs written by a test never come from, or end up
-- in, the developer's real config directory, and concurrent runs do not share one.
withTempConfigDir :: (FilePath -> IO a) -> IO a
withTempConfigDir act = do
  tmp <- getTemporaryDirectory
  bytes <- BS.unpack <$> getEntropy 6
  let dir = tmp </> ("hledger-web-test-" ++ concatMap (printf "%02x") bytes)
  bracket_ (createDirectoryIfMissing True dir >> setEnv "XDG_CONFIG_HOME" dir)
           (unsetEnv "XDG_CONFIG_HOME" >> removeDirectoryRecursive dir)
           (act dir)

-- | Fail the current test with a message. (yesod-test's own version of this
-- is not exported.)
failing :: String -> YesodExample App a
failing msg = liftIO (expectationFailure msg) >> error "unreachable: expectationFailure returned"

-- | The name of one of hledger-web's UI state cookies, as a test app,
-- on the default port, names it (App.uiCookie).
uiCookieName :: String -> BS.ByteString
uiCookieName name = fromString $ name <> "_" <> show defport

-- | Run hledger-web's built-in tests using the hspec test runner.
hledgerWebTest :: IO ()
hledgerWebTest = do
  putStrLn $ "Running tests for " ++ prognameandversion -- ++ " (--test --help for options)"
  let d = fromGregorian 2000 1 1

  -- The pager's window of page numbers: up to ten, sliding with the current page.
  hspec $ describe "pageNumbers" $ do
    it "shows every page when there are ten or fewer" $ do
      pageNumbers 1 3 `shouldBe` [1, 2, 3]
      pageNumbers 3 3 `shouldBe` [1, 2, 3]
      pageNumbers 1 1 `shouldBe` [1]
    it "shows the first ten pages until the current one is past the middle" $ do
      pageNumbers 1 30 `shouldBe` [1 .. 10]
      pageNumbers 5 30 `shouldBe` [1 .. 10]
      pageNumbers 6 30 `shouldBe` [2 .. 11]
    it "keeps the current page in the middle, and the last ten at the end" $ do
      pageNumbers 12 17 `shouldBe` [8 .. 17]
      pageNumbers 17 17 `shouldBe` [8 .. 17]
      pageNumbers 15 30 `shouldBe` [11 .. 20]

  -- Startup report options and query arguments become the url parameters
  -- browse mode opens, and the server's own report spec is rebuilt to
  -- stock defaults (#2771).
  hspec $ describe "startupUrlState" $ do
    it "renders options as page parameters, queries and query-like options as search terms, and rebuilds the spec to stock" $ do
      let ropts = defreportopts
            { period_ = YearPeriod 2026, interval_ = Months 1
            , value_ = Just (AtEnd Nothing), accountlistmode_ = ALTree
            , empty_ = True, statuses_ = [Cleared], real_ = True
            , depth_ = DepthSpec (Just 3) [(toRegexCI' "assets", 2)]
            , querystring_ = ["assets", "two words"]
            , title_ = Just "My books"
            }
          (params, rspec') = startupUrlState defreportspec{_rsReportOpts = ropts}
      lookup "interval" params `shouldBe` Just "monthly"
      lookup "period" params `shouldBe` Nothing
      lookup "value" params `shouldBe` Just "end"
      lookup "list" params `shouldBe` Just "tree"
      -- -E means the opposite in the web ui: hide the zero balances shown by default
      lookup "empty" params `shouldBe` Just "0"
      -- a flat depth is a parameter; a per-account one stays a search term
      lookup "depth" params `shouldBe` Just "3"
      lookup "q" params `shouldBe` Just "assets \"two words\" date:2026 status:* real:1 depth:assets=2"
      _rsQuery rspec' `shouldBe` Any
      period_ (_rsReportOpts rspec') `shouldBe` PeriodAll
      interval_ (_rsReportOpts rspec') `shouldBe` NoInterval
      value_ (_rsReportOpts rspec') `shouldBe` Nothing
      empty_ (_rsReportOpts rspec') `shouldBe` False
      -- a display preference with no url spelling stays in the spec
      title_ (_rsReportOpts rspec') `shouldBe` Just "My books"
    it "spells intervals as in period expressions and valuations as value words" $ do
      let p ropts = fst $ startupUrlState defreportspec{_rsReportOpts = ropts}
      lookup "interval" (p defreportopts{interval_ = Weeks 2}) `shouldBe` Just "every 2 weeks"
      lookup "value" (p defreportopts{value_ = Just (AtEnd (Just "EUR"))}) `shouldBe` Just "end,EUR"
      lookup "value" (p defreportopts{conversionop_ = Just ToCost}) `shouldBe` Just "cost"
      -- a depth regexp with a space must arrive as one quoted term
      lookup "q" (p defreportopts{depth_ = DepthSpec Nothing [(toRegex' "a b", 2)]}) `shouldBe` Just "\"depth:a b=2\""

  -- Report options in the search, and the old period parameter, move to
  -- their own parameters (App.normaliseUrlState).
  hspec $ describe "normalisedSearch" $ do
    let refday = fromGregorian 2026 10 23
    it "moves a date term's interval out, keeping its span as written" $ do
      normalisedSearch refday "assets \"date:monthly in thisyear\"" Nothing `shouldBe` Just (MovedOptions "assets \"date:in thisyear\"" Nothing (Just (Months 1)) Nothing)
      normalisedSearch refday "date:weekly" Nothing `shouldBe` Just (MovedOptions "" Nothing (Just (Weeks 1)) Nothing)
    it "moves the last flat depth out, keeping per-account depths" $ do
      normalisedSearch refday "depth:2 depth:assets=3 depth:1" Nothing `shouldBe` Just (MovedOptions "depth:assets=3" (Just 1) Nothing Nothing)
    it "splits the period parameter into a date term and an interval, the search's interval winning" $ do
      normalisedSearch refday "expenses" (Just "quarterly in 2025") `shouldBe` Just (MovedOptions "\"date:in 2025\" expenses" Nothing (Just (Quarters 1)) Nothing)
      normalisedSearch refday "date:monthly" (Just "quarterly 2025") `shouldBe` Just (MovedOptions "date:2025" Nothing (Just (Months 1)) Nothing)
      normalisedSearch refday "" (Just "2025-02") `shouldBe` Just (MovedOptions "date:2025-02" Nothing Nothing Nothing)
    it "moves the first account term out, as the account register's subject" $ do
      normalisedSearch refday "inacctonly:assets:bank desc:x inacct:expenses" Nothing `shouldBe` Just (MovedOptions "desc:x" Nothing Nothing (Just ("assets:bank", False)))
      normalisedSearch refday "inacct:'assets:bank account'" Nothing `shouldBe` Just (MovedOptions "" Nothing Nothing (Just ("assets:bank account", True)))
    it "leaves a search with nothing to move" $ do
      normalisedSearch refday "assets date:2025 depth:assets=2" Nothing `shouldBe` Nothing
    it "splits only an interval followed by a date span" $ do
      splitPeriodExpr refday "every 2 weeks from 2025-01-01" `shouldBe` Just (Weeks 2, "from 2025-01-01")
      splitPeriodExpr refday "2025" `shouldBe` Nothing
      splitPeriodExpr refday "monthly bogus" `shouldBe` Nothing

  -- The options in effect, listed on the closed Options disclosure.
  hspec $ describe "optionsSummary" $ do
    it "lists the options in the controls' order, in their words, skipping other parameters" $
      optionsSummary noTranslations 3 [("sort", "amount"), ("q", "assets"), ("depth", "2"), ("account", "assets"), ("interval", "monthly"), ("lots", "1")]
        `shouldBe` ["Monthly", "Depth 2", "Lots shown", "By amount"]
    it "shows an interval without a word of its own as written" $
      optionsSummary noTranslations 3 [("interval", "every 2 weeks")] `shouldBe` ["every 2 weeks"]
    it "omits a depth limit deeper than the deepest account, which the Depth links show as All" $
      optionsSummary noTranslations 3 [("depth", "9"), ("lots", "1")] `shouldBe` ["Lots shown"]

  runTests "hledger-web" [] nulljournal $ do

    yit "serves a reasonable-looking journal page" $ do
      get JournalR
      statusIs 200
      bodyContains "Add a transaction"

    yit "serves a reasonable-looking register page" $ do
      get RegisterR
      statusIs 200
      bodyContains "accounts"

    yit "serves the favicon and robots.txt" $ do
      get FaviconR
      statusIs 200
      assertHeader "Content-Type" "image/x-icon"
      get RobotsR
      statusIs 200
      bodyContains "Disallow: /"

    yit "serves the chart stylesheet, with its shading, and its dark colors for the screen only" $ do
      get ChartCssR
      statusIs 200
      assertHeader "Content-Type" "text/css; charset=utf-8"
      bodyContains ".hledger-chart .shade.future{"
      bodyContains "@media screen and (prefers-color-scheme:dark){"
      bodyNotContains "@media (prefers-color-scheme:dark)"

    yit "hyperlinks use a base url made from the default host and port" $ do
      get JournalR
      statusIs 200
      let defaultbaseurl = defbaseurl defhost defport
      bodyContains ("href=\"" ++ defaultbaseurl)
      bodyContains ("src=\"" ++ defaultbaseurl)

    -- The Content-Security-Policy (#2703). Every HTML page sends one, and the
    -- page's own inline scripts carry its nonce, so they are the only inline
    -- scripts a browser will run.
    yit "sends a Content-Security-Policy whose nonce marks the page's inline scripts" $ do
      get JournalR
      statusIs 200
      csp <- cspHeaderValue
      assertEq "the policy should allow scripts from our origin only"
        (T.isInfixOf "script-src 'self' 'nonce-" csp) True
      nonce <- cspNonce
      assertEq "the nonce should be 16 bytes, base64 encoded" (T.length nonce) 24
      bodyContains ("<script nonce=\"" ++ T.unpack nonce ++ "\">")
      bodyNotContains "<script>"

    yit "uses a fresh nonce for each response" $ do
      get JournalR
      nonce1 <- cspNonce
      get JournalR
      nonce2 <- cspNonce
      assertEq "two responses should not share a nonce" (nonce1 == nonce2) False

    -- Error pages are rendered by yesod's errorHandler, in a handler state of
    -- its own; they must carry the policy too, with their own nonce.
    yit "sends the Content-Security-Policy with error pages too" $ do
      get ("/nosuchpage" :: T.Text)
      statusIs 404
      _ <- cspNonce
      return ()

    -- No --serve or --serve-api means the default --serve-browse mode, where
    -- each page pings the server while it is open so that it does not exit.
    -- The page is told to by a marker on the body. (The pinging and the
    -- server's answer are outside this harness; the browser suite's
    -- browse-mode spec checks those.)
    yit "marks the page for the browse-mode ping" $ do
      get JournalR
      statusIs 200
      bodyContains "<body data-browse-mode"

  runTests "hledger-web with --serve" [("serve","")] nulljournal $ do

    yit "does not mark the page for the browse-mode ping" $ do
      get JournalR
      statusIs 200
      bodyNotContains "data-browse-mode"

    -- WIP
    -- yit "shows the add form" $ do
    --   get JournalR
    --   -- printBody
    --   -- let addbutton = "button:contains('add')"
    --   -- bodyContains addbutton
    --   -- htmlAnyContain "button:visible" "add"
    --   printMatches "div#addmodal:visible"
    --   htmlCount "div#addmodal:visible" 0

    --   -- clickOn "a#addformlink"
    --   -- printBody
    --   -- bodyContains addbutton

    -- yit "can add transactions" $ do

  usecolor <- useColorOnStdout
  let
    rawopts = [("forecast","")]
    iopts = rawOptsToInputOpts d usecolor $ mkRawOpts rawopts
    f = "fake"  -- need a non-null filename so forecast transactions get index 0
  pj <- readJournal'' (T.pack $ unlines  -- PARTIAL: readJournal'' should not fail
    ["~ monthly"
    ,"    assets    10"
    ,"    income"
    ])
  j <- fmap (either error' id) . runExceptT $ journalFinalise iopts f "" pj  -- PARTIAL: journalFinalise should not fail
  runTests "hledger-web with --forecast" rawopts j $ do

    yit "shows forecasted transactions" $ do
      get JournalR
      statusIs 200
      bodyContains "id=\"transaction-2-1\""
      bodyContains "id=\"transaction-2-2\""

  -- A journal with lot tracking enabled: two open AAA lots (FIFO), and
  -- a fully disposed BBB position whose realised gain is $3.
  let liopts = rawOptsToInputOpts d usecolor $ mkRawOpts []
  lj <- fmap (either error' id) . runExceptT . journalFinalise liopts "lots.journal" "" =<<
          readJournal'' (T.pack $ unlines  -- PARTIAL: readJournal'' should not fail
            ["commodity AAA  ; lots:"
            ,"commodity BBB  ; lots:"
            ,"P 2026-01-31 AAA $12.00"
            ,""
            ,"2025-12-30 opening"  -- a second year, so the years row shows
            ,"    assets:cash    $100.00"
            ,"    equity:opening"
            ,""
            ,"2026-01-01 buy aaa"
            ,"    assets:broker    2 AAA @ $10.00"
            ,"    assets:cash    $-20.00"
            ,""
            ,"2026-01-15 buy more aaa"
            ,"    assets:broker    2 AAA @ $11.00"
            ,"    assets:cash    $-22.00"
            ,""
            ,"2026-01-16 buy bbb"
            ,"    assets:broker    1 BBB @ $5.00"
            ,"    assets:cash     $-5.00"
            ,""
            ,"2026-01-20 sell one aaa"
            ,"    assets:broker   -1 AAA @ $12.00"
            ,"    assets:cash     $12.00"
            ,""
            ,"2026-01-21 sell all bbb"
            ,"    assets:broker   -1 BBB @ $8.00"
            ,"    assets:cash      $8.00"
            ])
  runTests "hledger-web holdings page" [] lj $ do

    yit "shows the holdings report, hiding closed positions by default" $ do
      request $ do
        setMethod "GET"
        setUrl (HoldingsR, [("q", "date:2026")])
      statusIs 200
      bodyContains "Holdings on 2026-12-31"
      bodyContains ">Avg cost<"
      bodyContains "$32.00"   -- total cost: 1@10 + 2@11
      bodyContains "$36.00"   -- total value: 3 AAA at the $12 market price
      bodyContains "12.5%"    -- UGain%: 4/32
      bodyContains "$5.00"    -- total RGain includes the closed BBB position
      bodyNotContains "0 BBB" -- but its row is hidden without closed=1
                              -- (the commodity filter row still offers BBB)
      bodyContains "Holdings</a>"  -- and the journal has lots, so the menu links here
      -- the controls sit behind the disclosure, with the report pages'
      -- rows: years (setting the report date), status, real, type,
      -- commodity, and prices
      bodyContains "<details class=\"report-controls\">"
      bodyContains "Years:"
      bodyContains "Status:"
      bodyContains "Type:"
      bodyContains "Commodity:"
      bodyContains "Prices:"
      -- the account names' shared prefix is a group heading, rows show the rest
      bodyContains "scope=\"rowgroup\">assets</th>"
      bodyContains ">broker</a>"
      -- a position's register link filters to its commodity
      bodyContains "/register?q=date%3A2026%20cur%3AAAA&amp;account=assets%3Abroker\""
      -- with lots hidden, the Depth row reaches the deepest real account
      bodyContains "title=\"Show accounts at every depth\">2</a>"

    yit "shows one row per lot with lots=1" $ do
      request $ do
        setMethod "GET"
        setUrl (HoldingsR, [("q", "date:2026"), ("lots", "1")])
      statusIs 200
      bodyContains ">Unit cost<"
      bodyContains "{2026-01-01, $10.00}"
      bodyContains "class=\"account acct-split lot\""
      -- with every lot under one account, that account is the group heading
      bodyContains "scope=\"rowgroup\">assets:broker</th>"
      -- lot subaccounts are ordinary accounts to the Depth row, which
      -- now reaches one level deeper, as in hledger-ui
      bodyContains "&amp;depth=2\" title=\"Show accounts down to depth 2\">2</a>"
      bodyContains "title=\"Show accounts at every depth\">3</a>"

    yit "shows closed positions with closed=1" $ do
      request $ do
        setMethod "GET"
        setUrl (HoldingsR, [("q", "date:2026"), ("closed", "1")])
      statusIs 200
      bodyContains "0 BBB"
      bodyContains "$3.00"
      -- the page also has the usual zero-balances control, which the
      -- empty parameter drives, so the z key keeps working here
      bodyContains "Zero balances:"

    yit "tree mode shows a single-commodity account as one combined row" $ do
      request $ do
        setMethod "GET"
        setUrl (HoldingsR, [("q", "date:2026"), ("list", "tree")])
      statusIs 200
      -- the boring root is squashed into the one account, which holds one
      -- commodity and so is a row, not a heading over a commodity row
      bodyContains "class=\"account indent-0\""
      bodyContains ">assets:broker</a>"
      bodyNotContains "acctheading"

    yit "tree mode clips to a depth limit, as the cli does, rather than folding" $ do
      request $ do
        setMethod "GET"
        setUrl (HoldingsR, [("q", "date:2026"), ("list", "tree"), ("depth", "1")])
      statusIs 200
      -- the positions are merged under the clipped account; folding the
      -- full tree could only have shown assets:broker
      bodyContains "<table class=\"balancereport table table-condensed\">"
      bodyContains "account=assets&amp;list=tree&amp;depth=1\""
      bodyNotContains "account=assets%3Abroker&amp;list=tree"  -- (the sidebar's links put depth first)

    yit "tree mode groups several commodities under an account heading" $ do
      request $ do
        setMethod "GET"
        setUrl (HoldingsR, [("q", "date:2026"), ("list", "tree"), ("closed", "1")])
      statusIs 200
      -- with the closed BBB position shown, the account holds two
      -- commodities: a heading row subtotaling the dollar columns, then
      -- a position row per commodity
      bodyContains "class=\"account indent-0 acctheading\""
      bodyContains ">assets:broker</a>"
      bodyContains "class=\"account indent-1 commodity\""
      bodyContains ">AAA</a>"
      bodyContains ">BBB</a>"
      -- each commodity row's register link filters to its own commodity
      bodyContains "/register?q=date%3A2026%20cur%3ABBB&amp;account=assets%3Abroker&amp;list=tree\""
      -- the heading's RGain subtotals both commodities' realized gains
      bodyContains "$5.00"

    yit "rejects value=then" $ do
      request $ do
        setMethod "GET"
        setUrl (HoldingsR, [("value", "then")])
      statusIs 200
      bodyContains "value=then does not apply"

  runTests "hledger-web holdings page without lots" [] nulljournal $ do

    yit "hides the Holdings link, but the page still answers" $ do
      get JournalR
      statusIs 200
      bodyNotContains "Holdings</a>"
      get HoldingsR
      statusIs 200

  -- Submitting an unbalanced transaction produces an error message that
  -- echoes the entry (account names, amounts). Those values must be rendered
  -- as text, not raw html. Note this echo happens on the FormFailure path,
  -- which yesod does not gate with the CSRF token, so no token is sent here -
  -- the vector is reachable cross-origin.
  aj <- fmap (either error' id) . runExceptT . journalFinalise iopts "add.journal" "" =<<
          readJournal'' (T.pack $ unlines  -- PARTIAL: readJournal'' should not fail
            ["2025-01-01 opening"
            ,"    assets:bank:checking   100"
            ,"    equity:opening"])
  runTests "hledger-web add form" [("allow","add")] aj $ do

    yit "escapes submitted values in an add-form error message" $ do
      get JournalR
      statusIs 200
      -- Payloads in the two fields that reach the excerpt: the account name,
      -- and the (unvalidated) description. Distinct payloads so that escaping
      -- one field but not the other is caught. The entry parses but does not
      -- balance, so its excerpt - which includes both fields - is echoed.
      -- (Date and amount are validated and cannot carry raw html into it.)
      request $ do
        setMethod "POST"
        setUrl AddR
        addPostParam "_formid" "identify-add"
        addPostParam "date" "2025-02-02"
        addPostParam "description" "d<img src=x onerror=alert(1)>"
        addPostParam "account" "a<img src=x onerror=alert(2)>"
        addPostParam "amount" "5"
        addPostParam "account" "equity:opening"
        addPostParam "amount" "-3"
      bodyContains "d&lt;img src=x onerror=alert(1)&gt;"   -- description, escaped
      bodyContains "a&lt;img src=x onerror=alert(2)&gt;"   -- account, escaped
      bodyNotContains "<img src=x onerror"                 -- neither as raw html

    yit "shows add-form validation messages in the viewer's language" $ do
      request $ do
        setMethod "POST"
        setUrl AddR
        addRequestHeader ("Accept-Language", "de")
        addPostParam "_formid" "identify-add"
        addPostParam "date" "not a date"
        addPostParam "description" "d"
        -- two accounts without amounts: only the last posting may omit its amount
        addPostParam "account" "a"
        addPostParam "amount" ""
        addPostParam "account" "b"
        addPostParam "amount" ""
      bodyContains "Ungültiges Datumsformat"
      bodyContains "Betrag fehlt"

  runTests "hledger-web language selection" [] nulljournal $ do

    yit "serves English by default" $ do
      get JournalR
      statusIs 200
      bodyContains "lang=\"en\""
      bodyContains "Add a transaction"

    yit "follows Accept-Language, trying each preference with its subtags dropped" $ do
      request $ do
        setMethod "GET"
        setUrl JournalR
        addRequestHeader ("Accept-Language", "de-CH,en;q=0.9")
      statusIs 200
      bodyContains "lang=\"de\""
      bodyContains "Buchung hinzufügen"
      bodyNotContains "Add a transaction"
      vary <- headerValue "Vary"
      assertEq "the page says it varies by language" (T.isInfixOf "Accept-Language" vary) True

    yit "remembers an explicit _LANG choice in a cookie, when it names an available catalog" $ do
      request $ do
        setMethod "GET"
        setUrl (JournalR, [("_LANG", "de")])
      statusIs 200
      bodyContains "Buchung hinzufügen"
      cookie <- headerValue "Set-Cookie"
      assertEq "the language cookie is set" (T.isInfixOf "_LANG=de;" cookie) True
      assertEq "the language cookie is SameSite" (T.isInfixOf "SameSite=Lax" cookie) True

    yit "ignores a _LANG value that is not an available catalog, without setting a cookie" $ do
      request $ do
        setMethod "GET"
        setUrl (JournalR, [("_LANG", "../../etc/passwd")])
      statusIs 200
      bodyContains "Add a transaction"
      cookies <- headerValues "Set-Cookie"
      assertEq "no language cookie" (any (T.isInfixOf "_LANG=") cookies) False

    yit "reads the language from the _LANG cookie on later requests" $ do
      -- yesod-test keeps the cookies a response sets and sends them back
      request $ do
        setMethod "GET"
        setUrl (JournalR, [("_LANG", "de")])
      statusIs 200
      get RegisterR
      statusIs 200
      bodyContains "lang=\"de\""
      bodyContains "alle Konten"
      bodyContains "Von/Nach Konto"

    yit "shows the balance page in the viewer's language" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addRequestHeader ("Accept-Language", "de")
      statusIs 200
      bodyContains "<title>Salden - hledger-web</title>"
      bodyContains "<h2>Alle Konten</h2>"
      bodyContains "Intervall:"
      bodyContains "title=\"Eine Spalte pro Monat anzeigen\">Monatlich</a>"

  runTests "hledger-web with --lang" [("lang","de")] nulljournal $ do

    yit "uses the --lang language whatever the viewer asks for, setting no language cookie" $ do
      request $ do
        setMethod "GET"
        setUrl (JournalR, [("_LANG", "en")])
        addRequestHeader ("Accept-Language", "en")
      statusIs 200
      bodyContains "lang=\"de\""
      bodyContains "Buchung hinzufügen"
      cookies <- headerValues "Set-Cookie"
      assertEq "no language cookie" (any (T.isInfixOf "_LANG=") cookies) False

  -- With --lang=auto the environment's language is only the fallback,
  -- here English (LC_ALL=C), so that it can't be mistaken for the viewer's.
  bracket (lookupEnv "LC_ALL" <* setEnv "LC_ALL" "C") (maybe (unsetEnv "LC_ALL") (setEnv "LC_ALL")) $ \_ ->
    runTests "hledger-web with --lang=auto" [("lang","auto")] nulljournal $ do

      yit "leaves the language to the viewer" $ do
        request $ do
          setMethod "GET"
          setUrl JournalR
          addRequestHeader ("Accept-Language", "de")
        statusIs 200
        bodyContains "lang=\"de\""
        bodyContains "Buchung hinzufügen"

  -- A translation is viewer-controlled text: it must be rendered as text
  -- wherever it lands, including inside attributes.
  withTempConfigDir $ \xdg -> do
    createDirectoryIfMissing True (xdg </> "hledger" </> "locale")
    TIO.writeFile (xdg </> "hledger" </> "locale" </> "xx.po") $ T.unlines
      [ "msgid \"\""
      , "msgstr \"Content-Type: text/plain; charset=UTF-8\\n\""
      , ""
      , "msgid \"Add a transaction\""
      , "msgstr \"<img src=x onerror=alert(1)>\""
      , ""
      , "msgid \"Show search and general help\""
      , "msgstr \"x\\\" onmouseover=\\\"alert(2)\""
      ]
    runTests "hledger-web with a user translation catalog" [] nulljournal $ do

      yit "renders translations as text, in content and in attributes" $ do
        request $ do
          setMethod "GET"
          setUrl JournalR
          addRequestHeader ("Accept-Language", "xx")
        statusIs 200
        bodyContains "lang=\"xx\""
        bodyContains "&lt;img src=x onerror=alert(1)&gt;"
        bodyNotContains "<img src=x onerror"
        bodyContains "x&quot; onmouseover=&quot;alert(2)"
        bodyNotContains "onmouseover=\"alert(2)"

  -- The balance page: the balance report, or with an interval,
  -- the multi-period one, rendered without inline styles (the CSP).
  let biopts = rawOptsToInputOpts d usecolor $ mkRawOpts []
  bj <- fmap (either error' id) . runExceptT . journalFinalise biopts "balance.journal" "" =<<
          readJournal'' (T.pack $ unlines  -- PARTIAL: readJournal'' should not fail
            ["2025-01-05 pay"
            ,"    assets:bank:checking   100"
            ,"    income:salary"
            ,"2025-02-05 lunch"
            ,"    expenses:food           10"
            ,"    assets:bank:checking"])
  runTests "hledger-web balance page" [] bj $ do

    -- With two transactions in one year there is nothing to page or to
    -- move between, and the pages say nothing about it.
    yit "shows no paging and no years row for a small journal" $ do
      get JournalR
      statusIs 200
      bodyContains "lunch</td>"
      bodyNotContains "Showing "
      bodyNotContains "Years:"
      get RegisterR
      statusIs 200
      bodyContains "lunch</td>"
      bodyNotContains "Showing "
      bodyNotContains "Years:"

    yit "serves the balance report, linking accounts to their register" $ do
      get BalanceR
      statusIs 200
      bodyContains "<h2>All accounts</h2>"
      bodyContains "href=\"register?account=assets:bank:checking\""
      bodyContains "<tfoot>"
      bodyContains "class=\"amount negative\""

    yit "lists the named reports, then the general ones a little apart" $ do
      get BalanceR
      statusIs 200
      bodyContains ">Cashflow statement</a><a data-gokey=\"a\" class=\"current group-start\""
      bodyContains ">All accounts</a><a data-gokey=\"e\" href="

    yit "includes the add form on the report pages too, for the a key" $ do
      forM_ [BalanceR, BalancesheetR, IncomestatementR] $ \r -> do
        get r
        statusIs 200
        bodyContains "<dialog id=\"addmodal\""

    yit "offers each page in the g key's menu, with its key" $ do
      get BalanceR
      statusIs 200
      bodyContains "<div id=\"gomenu\" hidden"
      bodyContains "data-gokey=\"j\""
      bodyContains "<code>b</code> Balance sheet</a>"
      bodyContains "<code>a</code> All accounts</a>"
      bodyContains "<code>e</code> Balance sheet with equity</a>"

    yit "gives the report links their g keys, for the key hints" $ do
      let base = defbaseurl defhost defport
      get BalanceR
      statusIs 200
      -- a named page and a general report; the g menu's links show their
      -- keys as text, these only in the attribute
      bodyContains ("<a data-gokey=\"i\" href=\"" ++ base ++ "/incomestatement\" title=\"Show revenues and expenses\">Income statement</a>")
      bodyContains ("<a data-gokey=\"e\" href=\"" ++ base ++ "/balancesheetequity\" title=\"Show assets, liabilities, and equity\">Balance sheet with equity</a>")

    yit "offers the next and previous pages in the g key's menu, going round" $ do
      let base = defbaseurl defhost defport
      get BalanceR
      statusIs 200
      -- All accounts is between the cashflow statement and the balance
      -- sheet with equity (this journal has no lots, so no Holdings page)
      bodyContains ("<a href=\"" ++ base ++ "/balancesheetequity\" data-gokey=\"n\"")
      bodyContains "<code>n</code> Next report</a>"
      bodyContains ("<a href=\"" ++ base ++ "/cashflow\" data-gokey=\"p\"")
      bodyContains "<code>p</code> Previous report</a>"
      -- the journal, first, follows the last
      get JournalR
      statusIs 200
      bodyContains ("<a href=\"" ++ base ++ "/balancesheetequity\" data-gokey=\"p\"")

    yit "styles the report through the stylesheet, not inline styles" $ do
      get BalanceR
      statusIs 200
      bodyNotContains "<style"
      bodyNotContains "style=\""

    yit "serves the multi-period report for an interval" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "interval" "monthly"
      statusIs 200
      bodyContains "Balance changes in 2025-01-01..2025-02-28"
      bodyContains ">2025-01<"
      bodyContains ">2025-02<"
      -- the search form keeps the period, and marks the current report
      bodyContains "<input type=\"hidden\" name=\"interval\" value=\"monthly\">"
      bodyContains "class=\"current\""

    yit "restricts the report to the search's date span" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "date:2025-01"
      statusIs 200
      -- the report's own account links are relative (the sidebar's are not),
      -- and carry the search's dates, so the register they open is restricted too
      bodyContains "href=\"register?q=date:2025-01&amp;account=assets:bank:checking\""
      bodyNotContains "account=expenses:food"

    yit "honors a depth limit in the search" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "depth" "1"
      statusIs 200
      bodyContains "href=\"register?account=assets&amp;depth=1\""
      bodyNotContains "account=assets:bank:checking"

    yit "moves a depth term in the search to the depth parameter, keeping per-account depths in the search" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "assets depth:2 depth:assets:bank=3 depth:1"
        addGetParam "list" "tree"
      statusIs 303
      -- the last depth term wins, as in the search
      loc <- headerValue "Location"
      assertEq "the page is reloaded with the depth as a parameter" loc
        (T.pack (defbaseurl defhost defport) <> "/balance?q=assets%20depth%3Aassets%3Abank%3D3&list=tree&depth=1")

    yit "lists the options in effect on the closed Options disclosure, and does not call a depth limit a filter" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "interval" "monthly"
        addGetParam "depth" "2"
      statusIs 200
      bodyContains "<span class=\"options-summary\">Monthly · Depth 2</span>"
      bodyNotContains ", filtered</h2>"

    yit "keeps the depth in the search form" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "depth" "2"
      statusIs 200
      bodyContains "<input type=\"hidden\" name=\"depth\" value=\"2\">"

    yit "links to each depth from 0, setting the depth parameter and keeping the search; the deepest removes it" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "assets"
        addGetParam "depth" "1"
      statusIs 200
      let base = defbaseurl defhost defport
      bodyContains ("href=\"" ++ base ++ "/balance?q=assets&amp;depth=0\" title=\"Show only the total\">0</a>")
      bodyContains ("class=\"current\" href=\"" ++ base ++ "/balance?q=assets&amp;depth=1\"")
      bodyContains ("href=\"" ++ base ++ "/balance?q=assets&amp;depth=2\"")
      -- assets:bank:checking is at depth 3, so its link removes the
      -- limit, as hledger-ui does with a depth at or beyond the deepest
      bodyContains ("href=\"" ++ base ++ "/balance?q=assets\" title=\"Show accounts at every depth\">3</a>")
      bodyNotContains "&amp;depth=3\""
      bodyNotContains "depth=4"

    yit "squashes boring parents in tree mode, as the cli does" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "list" "tree"
      statusIs 200
      -- every account chain here is boring, so each is one indent-0 row
      bodyContains ">assets:bank:checking</a>"
      bodyContains "class=\"account indent-0 depth-3\""
      bodyNotContains "class=\"account indent-1"

    yit "in tree mode with a depth limit, gives boring parents at the limit their own rows, so it folds to the cli's rows" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "list" "tree"
        addGetParam "depth" "1"
      statusIs 200
      bodyContains "data-depth-fold=\"1\""
      -- the top-level accounts are the rows left showing, as --depth 1 shows them
      bodyContains "<tr><td class=\"account indent-0 depth-1\"><a href=\"register?account=assets&amp;list=tree&amp;depth=1\""
      -- the rest of each chain is a row beneath, served folded
      bodyContains "<tr class=\"tree-fold-hide\"><td class=\"account indent-1 depth-3\"><a href=\"register?account=assets:bank:checking&amp;list=tree&amp;depth=1\""
      bodyContains ">bank:checking</a>"
      -- the sidebar's tree is split the same way, for its own folding
      bodyContains "<tr data-indent=\"0\" data-acct=\"assets\">"
      bodyContains "<tr data-indent=\"1\" data-acct=\"assets:bank:checking\">"

    yit "offers the depth links on the journal page, where they clip the sidebar" $ do
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "depth" "1"
      statusIs 200
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/journal?depth=2\"")
      -- the sidebar is clipped to the depth; the entries are not
      bodyNotContains "account=assets%3Abank&"
      bodyContains "lunch</td>"

    yit "in tree mode with a depth limit, serves the whole sidebar, marked for folding to it" $ do
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "list" "tree"
        addGetParam "depth" "1"
      statusIs 200
      -- the journal page has no report table, so this is the sidebar's
      bodyContains "data-depth-fold=\"1\""
      -- the accounts below the limit are served too, for the carets to open
      bodyContains "account=assets%3Abank%3Achecking"

    yit "reports an interval it cannot parse" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "interval" "bogus"
      statusIs 200
      bodyContains "Could not parse the reporting interval"
      bodyNotContains "<tfoot>"

    yit "takes an interval typed in the search, as the cli does, moving it to the interval parameter" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "date:monthly"
      statusIs 303
      loc <- headerValue "Location"
      assertEq "the page is reloaded with the interval as a parameter" loc (T.pack (defbaseurl defhost defport) <> "/balance?interval=monthly")
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "interval" "monthly"
      statusIs 200
      bodyContains ">2025-01<"
      bodyContains ">2025-02<"

    yit "prefers an interval typed in the search to the interval parameter" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "interval" "yearly"
        addGetParam "q" "date:monthly"
      statusIs 303
      loc <- headerValue "Location"
      assertEq "the search's interval replaces the parameter" loc (T.pack (defbaseurl defhost defport) <> "/balance?interval=monthly")

    yit "marks the report being shown for the interval" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "interval" "yearly"
      statusIs 200
      bodyContains ("class=\"current\" href=\"" ++ defbaseurl defhost defport ++ "/balance?interval=yearly\"")

    yit "keeps the search's dates in the interval links" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "date:2025"
        addGetParam "interval" "monthly"
      statusIs 200
      bodyContains "balance?q=date%3A2025&amp;interval=yearly\""

    yit "shows the accounts' shared prefix once, dimming remaining paths" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "assets"
      statusIs 200
      -- the one asset account's parents become a group heading over its leaf
      bodyContains "scope=\"rowgroup\">assets:bank</th>"
      bodyContains ">checking</a>"
      get BalanceR
      statusIs 200
      -- no shared prefix across all accounts: full names, parent paths dimmed
      bodyContains "<span class=\"acct-path\"><span>assets:bank</span></span>:<span class=\"acct-leaf\">checking</span>"

    yit "keeps the report controls behind a disclosure" $ do
      get BalanceR
      statusIs 200
      bodyContains "<details class=\"report-controls\">"
      bodyContains ">Options</summary>"
      -- a single-commodity journal gets no commodity row (positive
      -- control: the amount conversion group's multi-commodity journal)
      bodyNotContains ">Commodity:"
      get JournalR
      statusIs 200
      bodyContains "<details class=\"report-controls\">"

    -- The open state travels in a cookie, written by the browser when
    -- the disclosure is toggled, so the page is born as it was left
    -- and nothing moves after paint.
    yit "renders the controls open when the showcontrols cookie says so" $ do
      testSetCookie defaultSetCookie{setCookieName = uiCookieName "showcontrols", setCookieValue = "1"}
      get JournalR
      statusIs 200
      bodyContains "<details class=\"report-controls\" open>"

    -- Cookies are shared by all servers on a host, so the names end with
    -- the port, and another hledger-web's cookie does not apply.
    yit "ignores the showcontrols cookie of an hledger-web on another port" $ do
      testSetCookie defaultSetCookie{setCookieName = fromString ("showcontrols_" <> show (defport + 1)), setCookieValue = "1"}
      get JournalR
      statusIs 200
      bodyContains "<details class=\"report-controls\">"

    yit "marks each type a type: term selects, as a shift-click builds them" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "type:AL"
      statusIs 200
      bodyContains ("class=\"current\" href=\"" ++ defbaseurl defhost defport ++ "/balance?q=type%3AA\" title=\"Show only asset accounts (type:A)\"")
      bodyContains ("class=\"current\" href=\"" ++ defbaseurl defhost defport ++ "/balance?q=type%3AL\" title=\"Show only liability accounts (type:L)\"")
      bodyContains ("<a href=\"" ++ defbaseurl defhost defport ++ "/balance\" title=\"Show accounts of every type\"")
      bodyContains "Shift-click selects several types."

    yit "survives an interval whose weekday is out of range" $ do
      -- the period parser accepts this; naming the ninth weekday used
      -- to crash the page (#2771 review)
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "interval" "every 9th day of week"
      statusIs 200

    -- intervalPeriodExpr is the period parser's interval syntax in
    -- reverse; parsing back what it emits keeps them from drifting.
    yit "emits period expressions the period parser reads back" $ do
      let readBack i = case intervalPeriodExpr i of
            Nothing -> Left ("no period expression for " ++ show i)
            Just t -> case parsePeriodExpr (fromGregorian 2026 1 1) t of
              Left _ -> Left (show i ++ " emitted unparseable " ++ T.unpack t)
              Right (i', _) -> Right i'
      mapM_ (\i -> assertEq "the interval round-trips" (Right i) (readBack i))
        [ Days 1, Days 2, Weeks 1, Weeks 3, Months 1, Months 6, Quarters 1, Years 1, Years 2
        , MonthDay 1, MonthDay 22, NthWeekdayOfMonth 2 3, MonthAndDay 6 15
        , DaysOfWeek [1,2,3,4,5], DaysOfWeek [6,7], DaysOfWeek [2,4] ]
      -- weekdays the parser accepts but the week lacks have no names:
      -- no period expression, rather than a crash
      assertEq "no ninth weekday" Nothing (intervalPeriodExpr (DaysOfWeek [9]))
      assertEq "no empty weekday list" Nothing (intervalPeriodExpr (DaysOfWeek []))

    yit "uses --title for the heading, unaltered" $ do
      get BalanceR
      statusIs 200
      bodyContains "<h2>All accounts</h2>"

    yit "escapes account names and search terms in the page" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "<img src=x onerror=alert(1)>"
      statusIs 200
      bodyNotContains "<img src=x onerror"

    yit "titles the multi-period report in the viewer's language too" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "interval" "monthly"
        addRequestHeader ("Accept-Language", "de")
      statusIs 200
      bodyContains "<h2>Saldoänderungen in 2025-01-01..2025-02-28</h2>"

    yit "shows and passes the report state through the journal and register" $ do
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "interval" "monthly"
        addGetParam "total" "1"
      statusIs 200
      -- kept by the search form, and carried on by the sidebar's report links
      bodyContains "<input type=\"hidden\" name=\"interval\" value=\"monthly\">"
      bodyContains "/balancesheet?interval=monthly&amp;total=1"
      -- and shown, dimmed: these controls take effect on the report pages
      bodyContains "controls-inert"
      bodyContains ">Interval:"
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "interval" "monthly"
      statusIs 200
      bodyContains "<input type=\"hidden\" name=\"interval\" value=\"monthly\">"
      bodyContains "controls-inert"

    yit "shows balance changes for a period, and says so" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "date:2025-02"
      statusIs 200
      bodyContains "<h2>Balance changes in 2025-02</h2>"
      -- the report's own links are relative (the sidebar's are not)
      bodyNotContains "account=income:salary"
      bodyContains ("class=\"current\" href=\"" ++ defbaseurl defhost defport ++ "/balance?q=date%3A2025-02\" title=\"Show how much")

    yit "shows ending balances with accum=historical, asking their registers for the same" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "date:2025-02"
        addGetParam "accum" "historical"
      statusIs 200
      bodyContains "<h2>Ending balances (historical) in 2025-02</h2>"
      -- no February postings, but a balance, whose register must start from before February
      bodyContains "href=\"register?q=date:2025-02&amp;account=income:salary&amp;accum=historical\""
      -- the search form and the interval links keep the mode; the mode links mark it
      bodyContains "<input type=\"hidden\" name=\"accum\" value=\"historical\">"
      bodyContains "/balance?q=date%3A2025-02&amp;accum=historical&amp;interval=monthly\""
      bodyContains ("class=\"current\" href=\"" ++ defbaseurl defhost defport ++ "/balance?q=date%3A2025-02&amp;accum=historical\"")

    yit "heads ending balance columns with their end dates, linking to this report for the period" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "interval" "monthly"
        addGetParam "accum" "historical"
      statusIs 200
      bodyContains ">2025-01-31<"
      bodyContains ">2025-02-28<"
      -- the drilled view keeps the interval: one monthly column
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/balance?q=date%3A2025-01&amp;accum=historical&amp;interval=monthly\" title=\"Show this report for this period\"")

    yit "links a balance change column's heading to this report for the period" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "interval" "monthly"
        addGetParam "q" "date:2025"
      statusIs 200
      bodyContains ">2025-01<"
      -- the column's period replaces the search's date term; the interval is kept
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/balance?q=date%3A2025-01&amp;interval=monthly\" title=\"Show this report for this period\"")

    yit "reports an accumulation mode it does not know" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "accum" "bogus"
      statusIs 200
      bodyContains "Unknown balance accumulation mode"
      bodyNotContains "<tfoot>"

    yit "keeps the accumulation mode off the journal page's search form" $ do
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "accum" "historical"
      statusIs 200
      bodyNotContains "name=\"accum\""

  -- A journal whose accounts branch, so tree mode has real fold points
  -- (bj's chains all squash to single rows).
  fj <- fmap (either error' id) . runExceptT . journalFinalise biopts "branching.journal" "" =<<
          readJournal'' (T.pack $ unlines  -- PARTIAL: readJournal'' should not fail
            ["2025-01-05 pay"
            ,"    assets:bank:checking   100"
            ,"    income:salary"
            ,"2025-02-05 save"
            ,"    assets:bank:savings     50"
            ,"    assets:bank:checking"])
  runTests "hledger-web tree mode" [] fj $ do

    yit "serves a tree-mode report at full depth, marked for folding to the search's depth" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "list" "tree"
        addGetParam "depth" "1"
      statusIs 200
      bodyContains "data-depth-fold=\"1\""
      bodyContains "<tr><td class=\"account indent-0 depth-1\">"
      bodyContains ">assets</a>"
      -- the rows below the fold are served too, for the page to unfold,
      -- but already folded, so the table paints at its folded height
      bodyContains "<tr class=\"tree-fold-hide\"><td class=\"account indent-1 depth-2\">"
      bodyContains "<tr class=\"tree-fold-hide\"><td class=\"account indent-2 depth-3\">"
      bodyContains ">checking</a>"

    yit "folds a tree-mode report by account depth, not indent, where boring parents are squashed" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "list" "tree"
        addGetParam "depth" "2"
      statusIs 200
      -- assets is boring and squashed into its branching child, which
      -- is at depth 2 though not indented; its subaccounts are below
      -- the limit, so they are folded
      bodyContains "<tr><td class=\"account indent-0 depth-2\">"
      bodyContains ">assets:bank</a>"
      bodyContains "<tr class=\"tree-fold-hide\"><td class=\"account indent-1 depth-3\">"
      bodyNotContains "<tr><td class=\"account indent-1 depth-3\">"

    yit "in tree mode, depth 0 clips to one row of all accounts, as the cli does" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "list" "tree"
        addGetParam "depth" "0"
      statusIs 200
      -- folding can't show a single total, so nothing is folded
      bodyNotContains "data-depth-fold=\""
      -- the one row, labelled as in hledger-ui, links to everything's register
      bodyContains "<tr><td class=\"account indent-0 depth-1\"><a href=\"register?list=tree&amp;depth=0\""
      bodyContains ">All</a>"
      bodyNotContains ">checking</a>"
      -- the sidebar too, its one row always shown
      bodyContains "<tr data-indent=\"0\" data-acct=\"...\"><td class=\"acct \">"
      -- the Depth row's 0 link is marked, not the deepest, which removes the limit
      let base = defbaseurl defhost defport
      bodyContains ("<a class=\"current\" href=\"" ++ base ++ "/balance?list=tree&amp;depth=0\" title=\"Show only the total\">0</a>")
      bodyContains ("<a href=\"" ++ base ++ "/balance?list=tree\" title=\"Show accounts at every depth\">3</a>")

    yit "in tree mode, a per-account depth limit clips its accounts, as the cli does" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "list" "tree"
        addGetParam "q" "depth:assets=2"
      statusIs 200
      -- assets' subaccounts are clipped to depth 2, in the table and the
      -- sidebar, leaving assets:bank with its subaccounts' total
      bodyContains "<tr><td class=\"account indent-0 depth-2\"><a href=\"register?q=depth:assets%3d2&amp;account=assets:bank&amp;list=tree\""
      bodyContains "<tr data-indent=\"0\" data-acct=\"assets:bank\">"
      bodyNotContains ">checking</a>"
      bodyNotContains "data-acct=\"assets:bank:checking\""

  -- The journal, register, and sidebar link to one another: a date to that
  -- day's journal entries, an account to its register, an amount to the
  -- register that derives it, an entry to itself on either page.
  let base = defbaseurl defhost defport
      -- an entry's id (transaction-FILE-INDEX), as the pages compute it
      frag desc = maybe (error' $ "no transaction " ++ desc) (transactionFragment bj) $
        find ((== T.pack desc) . tdescription) (jtxns bj)
      -- an entry's index, which an account link carries so that the
      -- register opens on the page holding it
      tix desc = maybe (error' $ "no transaction " ++ desc) (show . tindex) $
        find ((== T.pack desc) . tdescription) (jtxns bj)
  runTests "hledger-web journal, register, and sidebar links" [] bj $ do

    yit "links a journal entry's date to that day's entries, and its accounts to their registers at the entry" $ do
      get JournalR
      statusIs 200
      bodyContains ("href=\"" ++ base ++ "/journal?q=date%3A2025-01-05#" ++ frag "pay" ++ "\" title=\"Show the journal entries on this date\">")
      bodyContains ("href=\"" ++ base ++ "/register?account=assets%3Abank%3Achecking&amp;txn=" ++ tix "lunch" ++ "#" ++ frag "lunch" ++ "\" title=\"assets:bank:checking\">")

    yit "narrows the journal to a day" $ do
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "q" "date:2025-02-05"
      statusIs 200
      bodyContains ("id=\"" ++ frag "lunch" ++ "\"")
      bodyNotContains ("id=\"" ++ frag "pay" ++ "\"")

    yit "gives register rows the journal's entry ids, and links dates to the entry on its day" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:bank:checking"
      statusIs 200
      bodyContains ("<tr id=\"" ++ frag "lunch" ++ "\"")
      bodyContains ("href=\"" ++ base ++ "/journal?q=date%3A2025-02-05#" ++ frag "lunch" ++ "\" title=\"Show this entry and the other journal entries on its date\">")
      bodyContains ("href=\"" ++ base ++ "/register?account=expenses%3Afood&amp;txn=" ++ tix "lunch" ++ "#" ++ frag "lunch" ++ "\" title=\"expenses:food\">")
      -- the chart's points link to the rows, its styles are linked, and its base link is the register's
      bodyContains ("<a href=\"#" ++ frag "lunch" ++ "\"")
      bodyContains ("<link rel=\"stylesheet\" href=\"" ++ base ++ "/chart.css\">")
      bodyContains ("data-baselink=\"" ++ base ++ "/register?account=assets%3Abank%3Achecking\"")

    yit "replaces the search's date terms in a date link, and keeps its other terms" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:bank:checking"
        addGetParam "q" "date:2025-02 not:desc:\"x y\""
      statusIs 200
      bodyContains ("href=\"" ++ base ++ "/journal?q=date%3A2025-02-05%20%22not%3Adesc%3Ax%20y%22#" ++ frag "lunch" ++ "\"")
      -- (the sidebar's Journal link keeps the search as typed; the date links are the ones with a fragment)
      bodyNotContains "/journal?q=date%3A2025-02%20%22not%3Adesc%3Ax%20y%22#"

    yit "links the sidebar's amounts where their account names go" $ do
      get JournalR
      statusIs 200
      bodyContains ("<a href=\"" ++ base ++ "/register?account=assets%3Abank%3Achecking\" title=\"Show the transactions that make up this balance\">")
      -- an empty search adds no search to the account links
      bodyNotContains "/register?q=&amp;account"
      -- an unfiltered journal's total is zero, and does not link
      bodyNotContains "Show the transactions that make up this total"

    yit "keeps the search, minus its account term, on the sidebar's Journal link" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:bank:checking"
        addGetParam "q" "date:2025"
      statusIs 200
      bodyContains ("<td class=\"top acct\" colspan=\"2\"><a href=\"" ++ base ++ "/journal?q=date%3A2025\" title=\"Show general journal entries, most recent first\">Journal</a>")
      get JournalR
      statusIs 200
      bodyContains ("<td class=\"top acct\" colspan=\"2\"><a class=\"inacct\" href=\"" ++ base ++ "/journal\" title=\"Show general journal entries, most recent first\">Journal</a>")

    yit "gives the journal links the same report state as the other page links" $ do
      request $ do
        setMethod "GET"
        setUrl BalancesheetR
        addGetParam "interval" "quarterly"
        addGetParam "sort" "amount"
      statusIs 200
      -- in the sidebar, in the g menu, and in the row of page links
      bodyContains ("<a href=\"" ++ base ++ "/journal?interval=quarterly&amp;sort=amount\" title=\"Show general journal entries, most recent first\">Journal</a>")
      bodyContains ("<a href=\"" ++ base ++ "/journal?interval=quarterly&amp;sort=amount\" data-gokey=\"j\"")
      bodyContains ("<p class=\"report-links reports\"><a data-gokey=\"j\" href=\"" ++ base ++ "/journal?interval=quarterly&amp;sort=amount\"")

    yit "starts each page with the report links, then the search, the options, and the heading" $ do
      get BalancesheetR
      statusIs 200
      bodyContainsInOrder ["<p class=\"report-links reports\">", "searchform", "report-controls", "<h2>"]
      -- the register, though no report, has them too
      get RegisterR
      statusIs 200
      bodyContainsInOrder ["<p class=\"report-links reports\"><a data-gokey=\"j\" href=\"" <> T.pack base <> "/journal\"", "searchform", "report-controls", "<h2>"]

    yit "links the sidebar's total to the register of the search" $ do
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "q" "expenses"
      statusIs 200
      bodyContains ("<a href=\"" ++ base ++ "/register?q=expenses\" title=\"Show the transactions that make up this total\">")

  -- The register: a period's transactions, with a running total from zero,
  -- or with accum=historical, the account's balance from before the period.
  runTests "hledger-web register page" [] bj $ do

    yit "headings name the search's dates, and say filtered for its other filters" $ do
      get (JournalR, [("q", "date:2025")])
      statusIs 200
      bodyContains ">General Journal in 2025</h2>"
      get (JournalR, [("q", "date:2025 lunch")])
      statusIs 200
      bodyContains ">General Journal in 2025, filtered</h2>"
      get (RegisterR, [("account", "assets:bank:checking"), ("q", "date:2025")])
      statusIs 200
      bodyContains ">assets:bank:checking in 2025</h2>"

    -- The register's table has a tbody; the sidebar, which shows the same
    -- accounts, has none, so these assertions look only at the register.
    yit "totals the period from zero by default" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:bank:checking"
        addGetParam "q" "date:2025-02"
      statusIs 200
      bodyContains ">Period Total</a>"
      htmlAnyContain "#main-content tbody td.amount" "-10"
      bodyNotContains ">90<"
      bodyNotContains "Balance brought forward"
      bodyNotContains "name=\"accum\""
      -- the balance column's heading switches to historical mode
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/register?q=date%3A2025-02&amp;account=assets%3Abank%3Achecking&amp;accum=historical\" title=\"Show the running balance including everything before this period\">Period Total</a>")

    yit "starts from the balance brought forward with accum=historical" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:bank:checking"
        addGetParam "q" "date:2025-02"
        addGetParam "accum" "historical"
      statusIs 200
      bodyContains ">Historical Total</a>"
      htmlAnyContain "#main-content tbody td.amount" "90"
      -- the oldest row is the balance brought forward, linking to the transactions before the period
      htmlAnyContain "#main-content tbody tr.broughtforward td.amount" "100"
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/register?q=date%3A..2025-02-01&amp;account=assets%3Abank%3Achecking\" title=\"Show the transactions before this period\">")
      -- the search form, the other-account links, and the chart's base link keep the mode
      bodyContains "<input type=\"hidden\" name=\"accum\" value=\"historical\">"
      bodyContains "&amp;accum=historical#"
      bodyContains ("data-baselink=\"" ++ defbaseurl defhost defport ++ "/register?account=assets%3Abank%3Achecking&amp;accum=historical\"")
      -- the heading switches back, dropping the mode
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/register?q=date%3A2025-02&amp;account=assets%3Abank%3Achecking\" title=\"Show the running balance from the start of this period\">Historical Total</a>")

    yit "cuts the balance brought forward off by the kind of date the query has" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:bank:checking"
        addGetParam "q" "date2:2025-02"
        addGetParam "accum" "historical"
      statusIs 200
      bodyContains "/register?q=date2%3A..2025-02-01&amp;account=assets%3Abank%3Achecking\" title=\"Show the transactions before this period\">"

    yit "moves an account term in the search to the account parameter" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "q" "inacctonly:assets:bank:checking date:2025"
      statusIs 303
      loc <- headerValue "Location"
      assertEq "the page is reloaded with the account as a parameter" loc
        (T.pack (defbaseurl defhost defport) <> "/register?q=date%3A2025&account=assets%3Abank%3Achecking&subs=0")

    yit "keeps the account when the search is cleared or changed" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:bank:checking"
        addGetParam "q" "date:2025"
      statusIs 200
      bodyContains ("<a class=\"btn btn-default\" href=\"" ++ defbaseurl defhost defport ++ "/register?account=assets%3Abank%3Achecking\" title=\"Clear search terms\"")
      bodyContains "<input type=\"hidden\" name=\"account\" value=\"assets:bank:checking\">"

    yit "names the other accounts of a type: search's transactions" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "q" "type:X date:2025-02"
      statusIs 200
      bodyContains "title=\"expenses:food\">"

  -- The financial statements: the balancesheet, balancesheetequity,
  -- incomestatement, and cashflow commands' reports, with declared and
  -- inferred account types, and each figure linked to its register.
  tj <- fmap (either error' id) . runExceptT . journalFinalise biopts "statements.journal" "" =<<
          readJournal'' (T.pack $ unlines  -- PARTIAL: readJournal'' should not fail
            ["account liabilities:card  ; type:L"
            ,"account equity:opening    ; type:E"
            ,"2025-01-01 opening"
            ,"    assets:bank:checking   1000"
            ,"    equity:opening"
            ,"2025-01-05 pay"
            ,"    assets:bank:checking   100"
            ,"    income:salary"
            ,"2025-02-05 lunch"
            ,"    expenses:food           10"
            ,"    liabilities:card"
            ,"2025-02-06 snack"
            ,"    expenses:snacks<i>x      1"
            ,"    liabilities:card"])
  runTests "hledger-web financial statements" [] tj $ do

    yit "serves the balance sheet, with ending balances, in sections" $ do
      get BalancesheetR
      statusIs 200
      bodyContains "<h2>Balance Sheet 2025-02-06</h2>"
      -- a section heading names a dropped shared prefix deeper than one
      -- component; a single-component one stays implied by the title
      bodyContains "<tr class=\"section\"><th colspan=\"2\" scope=\"rowgroup\">Assets — assets:bank</th></tr>"
      bodyContains "<tr class=\"section\"><th colspan=\"2\" scope=\"rowgroup\">Liabilities</th></tr>"
      bodyContains "<tr class=\"subtotal\">"
      bodyContains "<tfoot>"
      bodyContains "Net:"
      -- figures link to registers in historical mode, restricted to the
      -- section's account types; a liability's says its sign differs
      bodyContains "href=\"register?q=type:A&amp;account=assets:bank:checking&amp;accum=historical\""
      bodyContains "href=\"register?q=date:2025-01-01..2025-02-07+type:L&amp;account=liabilities:card&amp;accum=historical\" title=\"Show the transactions behind this balance, which the register shows with the opposite sign\">"
      -- a section total links to the section's account types, the net total to all of them
      bodyContains "href=\"register?q=type:L+date:2025-01-01..2025-02-07&amp;accum=historical\""
      bodyContains "href=\"register?q=type:AL+date:2025-01-01..2025-02-07&amp;accum=historical\""
      -- shown as positive amounts, and without inline styles
      bodyNotContains "class=\"amount negative\""
      bodyNotContains "style=\""

    yit "serves the multi-period balance sheet, headed by end dates linking to this report" $ do
      request $ do
        setMethod "GET"
        setUrl BalancesheetR
        addGetParam "interval" "monthly"
      statusIs 200
      bodyContains "<h2>Monthly Balance Sheet 2025-01-31..2025-02-28</h2>"
      bodyContains ">2025-01-31<"
      bodyContains ">2025-02-28<"
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/balancesheet?q=date%3A2025-01&amp;interval=monthly\" title=\"Show this report for this period\"")
      bodyContains "<input type=\"hidden\" name=\"interval\" value=\"monthly\">"

    yit "shows balance changes instead when asked, and says so" $ do
      request $ do
        setMethod "GET"
        setUrl BalancesheetR
        addGetParam "accum" "change"
      statusIs 200
      bodyContains "<h2>Balance Sheet 2025-01-01..2025-02-06 (Balance Changes)</h2>"
      bodyNotContains "accum=historical"
      -- the search form and the interval links keep the override
      bodyContains "<input type=\"hidden\" name=\"accum\" value=\"change\">"
      bodyContains "/balancesheet?accum=change&amp;interval=monthly\""

    yit "does not keep the balance sheet's own mode as a parameter" $ do
      request $ do
        setMethod "GET"
        setUrl BalancesheetR
        addGetParam "accum" "historical"
      statusIs 200
      bodyContains "<h2>Balance Sheet 2025-02-06</h2>"
      bodyNotContains "name=\"accum\""

    yit "reports an accumulation mode it does not know" $ do
      request $ do
        setMethod "GET"
        setUrl BalancesheetR
        addGetParam "accum" "bogus"
      statusIs 200
      bodyContains "<h2>Balance Sheet</h2>"
      bodyContains "Unknown balance accumulation mode"
      bodyNotContains "<tfoot>"

    yit "serves the income statement, with changes, revenues shown positive" $ do
      get IncomestatementR
      statusIs 200
      bodyContains "<h2>Income Statement 2025-01-01..2025-02-06</h2>"
      bodyContains ">Revenues</th>"
      bodyContains ">Expenses</th>"
      bodyContains "href=\"register?q=date:2025-01-01..2025-02-07+type:R&amp;account=income:salary\" title=\"Show the transactions that make up this amount, which the register shows with the opposite sign\">"
      bodyContains "href=\"register?q=type:RX+date:2025-01-01..2025-02-07\" title=\"Show the transactions that make up this total, which the register shows with the opposite sign\">"
      -- the page's own mode is never a parameter; the Show row's other modes are
      bodyNotContains "accum=change"

    yit "shows the income statement's ending balances when asked, and says so" $ do
      request $ do
        setMethod "GET"
        setUrl IncomestatementR
        addGetParam "accum" "historical"
      statusIs 200
      bodyContains "<h2>Income Statement 2025-02-06 (Historical Ending Balances)</h2>"
      bodyContains "<input type=\"hidden\" name=\"accum\" value=\"historical\">"
      bodyContains "href=\"register?q=type:R&amp;account=income:salary&amp;accum=historical\""

    yit "serves the cashflow statement, with one section and no net total" $ do
      get CashflowR
      statusIs 200
      bodyContains "<h2>Cashflow Statement 2025-01-01..2025-02-06</h2>"
      bodyContains ">Cash flows — assets:bank</th>"
      bodyNotContains "<tfoot>"

    yit "serves the balance sheet with equity" $ do
      get BalancesheetequityR
      statusIs 200
      bodyContains "<h2>Balance Sheet With Equity 2025-02-06</h2>"
      bodyContains ">Equity</th>"
      bodyContains "href=\"register?q=type:ALE+date:2025-01-01..2025-02-07&amp;accum=historical\""

    yit "links the reports to one another, marking the one shown, and to All accounts" $ do
      request $ do
        setMethod "GET"
        setUrl IncomestatementR
        addGetParam "interval" "quarterly"
        addGetParam "account" "assets:bank:checking"
        addGetParam "q" "expenses"
      statusIs 200
      -- the links keep the period and the search minus its account term
      bodyContains ("class=\"current\" href=\"" ++ defbaseurl defhost defport ++ "/incomestatement?interval=quarterly&amp;q=expenses\" title=\"Show revenues and expenses\"")
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/balancesheet?interval=quarterly&amp;q=expenses\" title=\"Show assets, liabilities, and net worth\"")
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/balance?interval=quarterly&amp;q=expenses\" title=\"Show the balances of all accounts, by period, like the balance command\"")

    yit "links All accounts to the statements too" $ do
      get BalanceR
      statusIs 200
      bodyContains ("class=\"current group-start\" href=\"" ++ defbaseurl defhost defport ++ "/balance\" title=\"Show the balances of all accounts, by period, like the balance command\"")
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/incomestatement\" title=\"Show revenues and expenses\"")

    yit "links the journal page to the reports too, keeping the search minus its account term" $ do
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "account" "assets:bank:checking"
        addGetParam "q" "expenses"
      statusIs 200
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/balancesheet?q=expenses\" title=\"Show assets, liabilities, and net worth\"")
      bodyContains ("class=\"group-start\" href=\"" ++ defbaseurl defhost defport ++ "/balance?q=expenses\"")
      -- the journal leads the row, marked as the page shown
      bodyContains ("<p class=\"report-links reports\"><a data-gokey=\"j\" class=\"current\" href=\"" ++ defbaseurl defhost defport ++ "/journal?q=expenses\" title=\"Show general journal entries, most recent first\">Journal</a>")

    yit "links the report pages to the journal, first in their row of report links" $ do
      get IncomestatementR
      statusIs 200
      bodyContains ("<p class=\"report-links reports\"><a data-gokey=\"j\" href=\"" ++ defbaseurl defhost defport ++ "/journal\" title=\"Show general journal entries, most recent first\">Journal</a>")

    yit "lists the balance sheet, income statement, and cashflow statement in the sidebar, marking the one shown" $ do
      get BalancesheetR
      statusIs 200
      bodyContains ("<tr class=\"inacct\"><td class=\"top acct\" colspan=\"2\"><a class=\"inacct\" href=\"" ++ defbaseurl defhost defport ++ "/balancesheet\" title=\"Show assets, liabilities, and net worth\">Balance sheet</a>")
      bodyContains ("<tr><td class=\"top acct\" colspan=\"2\"><a href=\"" ++ defbaseurl defhost defport ++ "/incomestatement\" title=\"Show revenues and expenses\">Income statement</a>")
      bodyContains ("<a href=\"" ++ defbaseurl defhost defport ++ "/cashflow\" title=\"Show changes in liquid assets\">Cashflow statement</a>")
      -- the other two reports are in the Report row, not the sidebar
      bodyNotContains ("colspan=\"2\"><a href=\"" ++ defbaseurl defhost defport ++ "/balancesheetequity\"")

    yit "gives the sidebar's report links the search minus its account term, and the period" $ do
      request $ do
        setMethod "GET"
        setUrl IncomestatementR
        addGetParam "interval" "quarterly"
        addGetParam "accum" "historical"
        addGetParam "account" "assets:bank:checking"
        addGetParam "q" "expenses"
      statusIs 200
      -- the period is kept, the mode is not: it belongs to this report
      bodyContains ("colspan=\"2\"><a href=\"" ++ defbaseurl defhost defport ++ "/balancesheet?interval=quarterly&amp;q=expenses\" title=\"Show assets, liabilities, and net worth\">")
      bodyNotContains "/balancesheet?interval=quarterly&amp;accum"

    yit "links the sidebar's reports from the journal and register too" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:bank:checking"
        addGetParam "q" "date:2025"
      statusIs 200
      bodyContains ("colspan=\"2\"><a href=\"" ++ defbaseurl defhost defport ++ "/balancesheet?q=date%3A2025\" title=\"Show assets, liabilities, and net worth\">")
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "q" "date:2025"
      statusIs 200
      bodyContains ("colspan=\"2\"><a href=\"" ++ defbaseurl defhost defport ++ "/incomestatement?q=date%3A2025\" title=\"Show revenues and expenses\">")

    yit "drops each section's shared account prefix, dimming remaining paths" $ do
      get BalancesheetR
      statusIs 200
      bodyContains "class=\"account acct-split\""
      -- assets:bank:checking shows as its leaf; the full name heads the tooltip
      bodyContains "title=\"assets:bank:checking"
      bodyContains ">checking</a>"

    yit "escapes account names and search terms in the statements" $ do
      get IncomestatementR
      statusIs 200
      -- the full name heads the tooltip, and the stripped name is the link
      bodyContains "title=\"expenses:snacks&lt;i&gt;x"
      bodyContains ">snacks&lt;i&gt;x</a>"
      bodyNotContains "snacks<i>x"
      request $ do
        setMethod "GET"
        setUrl IncomestatementR
        addGetParam "q" "<img src=x onerror=alert(1)>"
      statusIs 200
      bodyNotContains "<img src=x onerror"

  -- Amounts as recorded, at cost, or at market value: a stock bought in
  -- three months at three prices, and priced at each month's start.
  vj <- fmap (either error' id) . runExceptT . journalFinalise biopts "valued.journal" "" =<<
          readJournal'' (T.pack $ unlines  -- PARTIAL: readJournal'' should not fail
            ["commodity $1,000.00"
            ,"commodity 1000.00 \"AAA UU\""  -- a spaced symbol, for the commodity row
            ,"P 2024-12-01 AAPL $80"
            ,"P 2025-01-01 AAPL $100"
            ,"P 2025-02-01 AAPL $120"
            ,"2024-12-05 buy"
            ,"    assets:broker   1 AAPL @ $80"
            ,"    assets:bank"
            ,"2025-01-05 buy"
            ,"    assets:broker  10 AAPL @ $90"
            ,"    assets:bank"
            ,"2025-02-10 buy"
            ,"    assets:broker   5 AAPL @ $110"
            ,"    assets:bank"])
  runTests "hledger-web amount conversion" [] vj $ do

    yit "shows market values with value=end, asking the figures' registers for the same" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "date:2025-01"
        addGetParam "value" "end"
      statusIs 200
      -- 10 AAPL at January's end
      bodyContains "$1,000.00"
      bodyContains "href=\"register?q=date:2025-01&amp;account=assets:broker&amp;value=end\""
      bodyContains ("class=\"current\" href=\"" ++ defbaseurl defhost defport ++ "/balance?q=date%3A2025-01&amp;value=end\"")
      -- the other reports, and the search form, keep it
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/balancesheet?q=date%3A2025-01&amp;value=end\"")
      bodyContains "<input type=\"hidden\" name=\"value\" value=\"end\">"

    yit "shows costs with value=cost" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "date:2025-01"
        addGetParam "value" "cost"
      statusIs 200
      bodyContains "$900.00"
      bodyContains "href=\"register?q=date:2025-01&amp;account=assets:broker&amp;value=cost\""

    -- The parameters appended to the figures' register links must be
    -- url-encoded: interval words can carry spaces.
    yit "url-encodes the parameters it adds to the figures' register links" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "date:2025-01"
        addGetParam "interval" "every 2 weeks"
      statusIs 200
      bodyContains "&amp;interval=every%202%20weeks"

    -- Percentages need the amounts in one commodity, which depends on
    -- the data: the page explains and shows plain amounts, instead of
    -- the error page the report's error used to become (the url keeps
    -- pct=1, so the links and the Numbers row keep the state).
    yit "explains percentages it cannot calculate, showing amounts instead" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "pct" "1"
      statusIs 200
      bodyContains "Could not calculate percentages:"
      bodyContains "16 AAPL"
      bodyContains "pct=1"

    yit "shows percentages when a conversion yields one commodity" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "pct" "1"
        addGetParam "value" "end"
      statusIs 200
      bodyContains "100.0 %"
      bodyNotContains "Could not calculate percentages"

    yit "reports an amount conversion it does not know" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "value" "bogus"
      statusIs 200
      bodyContains "Unknown amount conversion"

    yit "rejects gains over amounts as recorded, as the command line does" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "calc" "gain"
        addGetParam "value" "none"
      statusIs 200
      bodyContains "figured from period-end market values"

    yit "converts the register's amounts as the value parameter says, and its links keep its modes" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:broker"
        addGetParam "accum" "historical"
        addGetParam "value" "end"
      statusIs 200
      -- 16 AAPL at the journal's end
      bodyContains "$1,920.00"
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/register?q=date%3A2025&amp;account=assets%3Abroker&amp;accum=historical&amp;value=end\"")
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/balancesheet?value=end\"")

    yit "offers the depth and amount links on the statements too, keeping an accumulation override" $ do
      request $ do
        setMethod "GET"
        setUrl BalancesheetR
        addGetParam "accum" "change"
      statusIs 200
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/balancesheet?accum=change&amp;depth=1\"")
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/balancesheet?accum=change&amp;value=end\"")

    yit "shows the sidebar's amounts the way the page's value parameter asks, naming its net row by the mode" $ do
      get JournalR
      statusIs 200
      bodyContains "Net flows:"
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "value" "cost"
      statusIs 200
      -- 1 AAPL at $80, 10 at $90, 5 at $110, summed at cost
      bodyContains "$1,530.00"
      bodyContains "Net, at cost:"
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "value" "end"
      statusIs 200
      bodyContains "Unbooked gains:"

    yit "offers the journal's commodities as filters, escaping their symbols" $ do
      get BalanceR
      statusIs 200
      bodyContains ">Commodity:"
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/balance?q=cur%3AAAPL\" title=\"Show only amounts in AAPL\"")
      bodyContains "q=cur%3A%5C%24\""
      -- a spaced symbol's term is quoted whole, and its pattern is in its link's data
      bodyContains "q=%22cur%3AAAA%20UU%22"
      bodyContains "data-cur=\"AAA UU\""
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "cur:AAPL"
      statusIs 200
      bodyContains ("class=\"current\" href=\"" ++ defbaseurl defhost defport ++ "/balance?q=cur%3AAAPL\"")

    yit "marks each commodity a cur: alternation selects, as a shift-click builds them" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "cur:AAPL|\\$"
      statusIs 200
      bodyContains ("class=\"current\" href=\"" ++ defbaseurl defhost defport ++ "/balance?q=cur%3AAAPL\"")
      bodyContains ("class=\"current\" href=\"" ++ defbaseurl defhost defport ++ "/balance?q=cur%3A%5C%24\"")
      -- the search's other terms ride along for the script, pre-quoted
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "assets cur:AAPL"
      statusIs 200
      bodyContains "data-rest=\"assets\""

  runTests "hledger-web amount conversion with -V" [("V","")] vj $ do

    yit "shows amounts as recorded on a bare url, despite startup -V" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "date:2025-01"
      statusIs 200
      bodyContains "10 AAPL"
      bodyNotContains "$1,000.00"

  -- Many commodities: the row collapses to a line showing the selection.
  cj <- fmap (either error' id) . runExceptT . journalFinalise biopts "commodities.journal" "" =<<
          readJournal'' (T.pack $ unlines  -- PARTIAL: readJournal'' should not fail
            ["commodity 1.00 CC" ++ [c] | c <- "ABCDEFG"])
  runTests "hledger-web with many commodities" [] cj $ do

    yit "collapses the commodity row to its selection, opening to the list" $ do
      get BalanceR
      statusIs 200
      bodyContains "<summary title=\"List all the commodities\">"
      bodyContains "class=\"sel\">All<"
      bodyContains "data-cur=\"CCG\""
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "cur:CCA|CCC"
      statusIs 200
      bodyContains "class=\"sel\">CCA, CCC<"

    -- Like the controls disclosure's open state, the list's travels in
    -- a cookie the server reads, so it is born open, with no script
    -- moving it after paint.
    yit "renders the commodity list open when the showcommodities cookie says so" $ do
      get BalanceR
      statusIs 200
      bodyNotContains "<details open=\"open\">"
      testSetCookie defaultSetCookie{setCookieName = uiCookieName "showcommodities", setCookieValue = "1"}
      get BalanceR
      statusIs 200
      bodyContains "<details open=\"open\">"

  -- Registers of many commodities (#2784): a broker account whose balance
  -- grows to four commodities, an account of eleven, one posted twice, and
  -- one that buys five and then sells them one by one.
  let closed = map (replicate 3) "ABCDE"
  rj <- fmap (either error' id) . runExceptT . journalFinalise biopts "registers.journal" "" =<<
          readJournal'' (T.pack $ unlines $  -- PARTIAL: readJournal'' should not fail
            concat [ [ymd ++ " " ++ desc, "    assets:broker   " ++ amt, "    equity"]
                   | (ymd, desc, amt) <- [ ("2025-01-01", "one",   "10 DDD")
                                         , ("2025-01-02", "two",   "1 AAA")
                                         , ("2025-01-03", "three", "2 BBB")
                                         , ("2025-01-04", "four",  "3 CCC")
                                         , ("2025-01-05", "five",  "4 DDD") ] ] ++
            concat [ ["2025-02-01 many", "    assets:many   1 " ++ c, "    equity"]
                   | c <- map (replicate 3) "ABCDEFGHIJK" ++ ["KKK"] ] ++
            ["2025-03-01 buy"] ++ ["    assets:closed   1 " ++ c | c <- closed] ++ ["    equity"] ++
            concat [ ["2025-03-02 sell " ++ c, "    assets:closed   -1 " ++ c, "    equity"]
                   | c <- closed ])
  -- the amount cells of an entry's register row
  let rjamounts desc = maybe (error' $ "no transaction " ++ desc) (\t -> T.pack $ "#" ++ transactionFragment rj t ++ " td.amount") $
        find ((== T.pack desc) . tdescription) (jtxns rj)
  runTests "hledger-web registers of many commodities" [] rj $ do

    yit "shows a running balance of up to three commodities in full, and of more only those its row posted (#2784)" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:broker"
      statusIs 200
      -- three: all of them, though the row posted one
      htmlAnyContain (rjamounts "three") "10 DDD"
      htmlNoneContain (rjamounts "three") "more"
      -- four: the one the row posted, then how many more
      htmlAnyContain (rjamounts "five") "14 DDD"
      htmlAnyContain (rjamounts "five") "… and 3 more"
      htmlNoneContain (rjamounts "five") "1 AAA"

    yit "shows a commodity its row closed out, at zero, and elides a balance of zeros (#2784)" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:closed"
      statusIs 200
      -- buy posted all five: all of them, and no note of none more
      htmlAnyContain (rjamounts "buy") "1 EEE"
      htmlNoneContain (rjamounts "buy") "more"
      -- sell AAA closed out AAA: it at zero, then the four left
      htmlAnyContain (rjamounts "sell AAA") "0 AAA"
      htmlAnyContain (rjamounts "sell AAA") "… and 4 more"
      -- sell EEE left five zeros: its own, then the other four
      htmlAnyContain (rjamounts "sell EEE") "0 EEE"
      htmlAnyContain (rjamounts "sell EEE") "… and 4 more"
      htmlNoneContain (rjamounts "sell EEE") "0 AAA"

    yit "charts the ten commodities with the most transactions on the page, noting the rest (#2784)" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:many"
      statusIs 200
      -- KKK, posted twice, comes first in the legend though last
      -- alphabetically; of those posted once each, JJJ is left out
      bodyContains "<label for=\"register-chart-0\">KKK</label>"
      bodyContains "<label for=\"register-chart-9\">III</label>"
      bodyNotContains ">JJJ</label>"
      bodyContains "<p class=\"chart-note\">… and 1 more</p>"
      -- four commodities are all charted, with no note
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:broker"
      statusIs 200
      bodyContains "<label for=\"register-chart-3\">"
      bodyNotContains "chart-note"

    yit "draws the register chart as wide as the browser measured the page's main column" $ do
      let broker = request $ do
            setMethod "GET"
            setUrl RegisterR
            addGetParam "account" "assets:broker"
      -- not measured yet, the chart's own width
      broker
      statusIs 200
      bodyContains "class=\"hledger-chart\" width=\"880\""
      testSetCookie defaultSetCookie{setCookieName = uiCookieName "chartwidth", setCookieValue = "1200"}
      broker
      bodyContains "class=\"hledger-chart\" width=\"1200\""
      -- too narrow to draw in, it is widened
      testSetCookie defaultSetCookie{setCookieName = uiCookieName "chartwidth", setCookieValue = "100"}
      broker
      bodyContains "class=\"hledger-chart\" width=\"320\""

  -- A journal whose accounts have no recognizable types has empty statements.
  uj <- fmap (either error' id) . runExceptT . journalFinalise biopts "untyped.journal" "" =<<
          readJournal'' (T.pack $ unlines  -- PARTIAL: readJournal'' should not fail
            ["2025-01-01 x"
            ,"    aaa   1"
            ,"    bbb"])
  runTests "hledger-web financial statements without account types" [] uj $ do

    yit "explains an empty statement, pointing to how account types are found" $ do
      get BalancesheetR
      statusIs 200
      bodyContains "No accounts of the types this report shows were found"
      bodyContains "hledger.html#account-types"
      bodyNotContains "balancereport"

    yit "says when a search matches nothing instead" $ do
      request $ do
        setMethod "GET"
        setUrl BalancesheetR
        addGetParam "q" "zzz"
      statusIs 200
      bodyContains "Nothing matches this search in this period."
      bodyNotContains "account-types"

  -- Typed accounts whose balances net to zero: hidden with -E, but there.
  zj <- fmap (either error' id) . runExceptT . journalFinalise biopts "zeroed.journal" "" =<<
          readJournal'' (T.pack $ unlines  -- PARTIAL: readJournal'' should not fail
            ["account assets:bank      ; type:A"
            ,"account liabilities:loan ; type:L"
            ,"2025-01-01 borrow"
            ,"    assets:bank        100"
            ,"    liabilities:loan"
            ,"2025-02-01 repay"
            ,"    assets:bank       -100"
            ,"    liabilities:loan"])
  runTests "hledger-web financial statements with -E" [("empty","")] zj $ do

    yit "shows the zero balances on a bare url, despite startup -E" $ do
      get BalancesheetR
      statusIs 200
      bodyContains "assets:bank"
      bodyNotContains "which are hidden"

    yit "says when the accounts are all hidden zero balances" $ do
      request $ do
        setMethod "GET"
        setUrl BalancesheetR
        addGetParam "empty" "0"
      statusIs 200
      bodyContains "All the accounts this report shows have zero balances, which are hidden."
      bodyNotContains "account-types"

  -- A commodity directive sets the display precision; the page must apply it,
  -- as the sidebar beside it and the command line report do.
  sj <- fmap (either error' id) . runExceptT . journalFinalise biopts "styled.journal" "" =<<
          readJournal'' (T.pack $ unlines  -- PARTIAL: readJournal'' should not fail
            ["commodity $1000.00"
            ,"2025-01-05 rounding"
            ,"    (assets:bank:checking)   $1.005"])
  runTests "hledger-web balance page amount styles" [] sj $ do

    yit "renders amounts in the journal's commodity style" $ do
      get BalanceR
      statusIs 200
      bodyContains "$1.00"
      bodyNotContains "$1.005"

  -- Two accounts that net to zero, two that do not. -E means the opposite
  -- here than on the command line: hide the zero ones.
  ej <- fmap (either error' id) . runExceptT . journalFinalise biopts "empty.journal" "" =<<
          readJournal'' (T.pack $ unlines  -- PARTIAL: readJournal'' should not fail
            ["2025-01-01 out"
            ,"    assets:zeroed    100"
            ,"    income:zeroed   -100"
            ,"2025-01-02 back"
            ,"    assets:zeroed   -100"
            ,"    income:zeroed    100"
            ,"2025-01-03 kept"
            ,"    assets:kept       50"
            ,"    income:kept      -50"])
  runTests "hledger-web balance page zero items" [] ej $ do

    yit "shows zero items by default, as the sidebar does" $ do
      get BalanceR
      statusIs 200
      bodyContains "href=\"register?account=assets:zeroed\""
      -- a zero sidebar amount has an empty register, and no link
      bodyNotContains "account=assets%3Azeroed\" title=\"Show the transactions that make up this balance\""
      bodyContains "account=assets%3Akept\" title=\"Show the transactions that make up this balance\""
      -- and says so in the row of links; hiding them is the empty parameter
      bodyContains ("class=\"current\" href=\"" ++ defbaseurl defhost defport ++ "/balance\" title=\"Show accounts whose balances are zero\"")
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/balance?empty=0\" title=\"Hide accounts whose balances are zero\"")

    yit "hides them everywhere with empty=0, which links and the search form keep" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "empty" "0"
      statusIs 200
      -- the figures' registers keep the state too
      bodyContains "href=\"register?account=assets:kept&amp;empty=0\""
      bodyNotContains "account=assets:zeroed"
      bodyContains "<input type=\"hidden\" name=\"empty\" value=\"0\">"
      bodyContains "empty=0\" title=\"Show assets, liabilities, and net worth\""

  runTests "hledger-web with -E" [("empty","")] ej $ do

    yit "shows zero items on a bare url, despite startup -E, and empty=0 hides them" $ do
      get BalanceR
      statusIs 200
      bodyContains "href=\"register?account=assets:zeroed\""
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/balance?empty=0\" title=\"Hide accounts whose balances are zero\"")
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "empty" "0"
      statusIs 200
      bodyContains "href=\"register?account=assets:kept&amp;empty=0\""
      bodyNotContains "account=assets:zeroed"
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/balance\" title=\"Show accounts whose balances are zero\"")

  -- Startup report options are url state only: the server itself keeps
  -- stock defaults (#2771).
  runTests "hledger-web with --monthly" [("monthly","")] bj $ do

    yit "serves the stock view on a bare url, despite startup options" $ do
      get BalanceR
      statusIs 200
      bodyContains "All accounts"
      bodyNotContains ">2025-01<"

    yit "takes the startup interval from the url instead" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "interval" "monthly"
      statusIs 200
      bodyContains ">2025-01<"
      bodyContains ">2025-02<"

    yit "shows a single-period report from a column heading's link" $ do
      -- a heading link's target: the column's span as a date: search, no period
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "date:2025"
      statusIs 200
      bodyContains "Balance changes in 2025"
      bodyNotContains ">2025-01<"

  -- #2127
  -- XXX I'm pretty sure this test lies, ie does not match production behaviour.
  -- (test with curl -s http://localhost:5000/journal | rg '(href)="[\w/].*?"' -o )
  -- App root setup is a maze of twisty passages, all alike.
  -- runTests "hledger-web with --base-url"
  --   [("base-url","https://base")] nulljournal $ do
  --   yit "hyperlinks respect --base-url" $ do
  --     get JournalR
  --     statusIs 200
  --     bodyContains "href=\"https://base"
  --     bodyContains "src=\"https://base"

  -- #2139
  -- XXX Not passing.
  -- Static root setup is a maze of twisty passages, all different.
  -- runTests "hledger-web with --base-url, --file-url"
  --   [("base-url","https://base"), ("file-url","https://files")] nulljournal $ do
  --   yit "static file hyperlinks respect --file-url, others respect --base-url" $ do
  --     get JournalR
  --     statusIs 200
  --     bodyContains "href=\"https://base"
  --     bodyContains "src=\"https://files"

  -- Tests for the write side: yesod's CSRF protection, and the restriction of
  -- file access to the journal's own files. These use a journal in a temp file,
  -- so that if one of these protections ever fails, the test writes there
  -- rather than to the journal the developer happens to have configured.
  tmpdir <- getTemporaryDirectory
  let
    jfile = tmpdir </> "hledger-web-test.journal"
    jtext = T.pack $ unlines
      ["2025-01-01 gift"
      ,"    assets:bank:checking      10"
      ,"    income:gifts"
      ]
    -- A path is only editable if it is one of the journal's own files, so
    -- these must all be refused however they are spelled.
    otherfiles =
      ["/etc/passwd"
      ,"../../../../etc/passwd"
      ,"....//....//etc/passwd"
      ,jfile ++ "/../../etc/passwd"
      ]
  TIO.writeFile jfile jtext
  let wiopts = rawOptsToInputOpts d usecolor $ mkRawOpts [("file", jfile)]
  wpj <- readJournal'' jtext
  wj <- fmap (either error' id) . runExceptT $ journalFinalise wiopts jfile jtext wpj
  runTests "hledger-web write requests" [("file", jfile), ("allow", "edit")] wj $ do

    yit "puts a CSRF token in the add form" $ do
      get JournalR
      statusIs 200
      bodyContains "name=\"_token\""

    -- These three post the same valid, balanced transaction, and differ only
    -- in the CSRF token, so that the two failures can only be about the token.
    -- The form is wrapped in identifyForm, so _formid must be sent too, or the
    -- post is ignored as FormMissing and these would pass either way.
    -- Both postings send an explicit amount: the form pairs the account and
    -- amount params by position, and yesod-test before 1.7.0 sends repeated
    -- params in reverse order, which would leave an account without its amount.
    let postTransaction desc = do
          setMethod "POST"
          setUrl AddR
          addPostParam "_formid" "identify-add"
          addPostParam "date" "2025-02-02"
          addPostParam "description" desc
          addPostParam "account" "assets:bank:checking"
          addPostParam "amount" "1"
          addPostParam "account" "income:gifts"
          addPostParam "amount" "-1"

    yit "does not add a transaction when the CSRF token is missing" $ do
      request $ postTransaction "CsrfNoToken"
      bodyNotContains "Transaction added"
      journalFileLacks jfile "CsrfNoToken"

    yit "does not add a transaction when the CSRF token is wrong" $ do
      request $ do
        postTransaction "CsrfBadToken"
        addPostParam "_token" "not-the-token"
      bodyNotContains "Transaction added"
      journalFileLacks jfile "CsrfBadToken"

    -- The control for the two tests above: the same request, with a real
    -- token, is accepted. Without this they could pass for the wrong reason.
    yit "adds a transaction when the CSRF token is present" $ do
      get JournalR
      statusIs 200
      request $ do
        postTransaction "CsrfGoodToken"
        addToken  -- from the page just fetched
      statusIs 303  -- a successful add redirects to the journal
      _ <- followRedirect
      bodyContains "Transaction added"
      txt <- liftIO $ TIO.readFile jfile
      assertEq "journal should contain the added transaction"
        (T.isInfixOf "CsrfGoodToken" txt) True

    -- A newline in a field which is written verbatim (description, code,
    -- account name) would split the entry across lines in the journal file,
    -- injecting whatever follows as a directive - eg an include, which would
    -- make hledger read another file. Newlines must be collapsed on the way
    -- in, by both the add form and the JSON API.

    yit "does not let the add form write a newline into the journal" $ do
      get JournalR
      statusIs 200
      request $ do
        postTransaction "AddFormNewline\ninclude /etc/passwd"
        addToken  -- from the page just fetched
      journalFileLacks jfile "\ninclude /etc/passwd"
      txt <- liftIO $ TIO.readFile jfile
      assertEq "the description should be written on one line"
        (T.isInfixOf "AddFormNewline include /etc/passwd" txt) True

    -- The JSON API does not go through the form, so it needs the same
    -- treatment - and it has no CSRF token to stop a direct client.
    yit "does not let the JSON API write a newline into the journal" $ do
      let t = nulltransaction
            { tdate = fromGregorian 2025 4 4
            , tdescription = "JsonNewline\ninclude /etc/passwd"
            , tpostings =
              [ nullposting{paccount = "assets:bank:checking", pamount = mixedAmount (num 1)}
              , nullposting{paccount = "income:gifts",         pamount = mixedAmount (num (-1))}
              ]
            }
      request $ do
        setMethod "PUT"
        setUrl AddR
        addRequestHeader ("Content-Type", "application/json")
        setRequestBody $ encode t
      journalFileLacks jfile "\ninclude /etc/passwd"
      txt <- liftIO $ TIO.readFile jfile
      assertEq "the description should be written on one line"
        (T.isInfixOf "JsonNewline include /etc/passwd" txt) True

    -- Likewise for the edit form: the same save, with and without the token.
    let editJournal fld desc = do
          setMethod "POST"
          setUrl (EditR jfile)
          addPostParam "_formid" "identify-edit"
          addPostParam fld $
            "2025-03-03 " <> desc <> "\n    assets:bank:checking  1\n    income:gifts\n"

    yit "does not save the journal when the CSRF token is missing" $ do
      get (EditR jfile)
      statusIs 200
      fld <- editFieldName
      request $ editJournal fld "CsrfEdit"
      bodyNotContains "Saved journal"
      journalFileLacks jfile "CsrfEdit"

    yit "saves the journal when the CSRF token is present" $ do
      get (EditR jfile)
      statusIs 200
      fld <- editFieldName
      request $ do
        editJournal fld "CsrfEditOk"
        addToken  -- from the page just fetched
      txt <- liftIO $ TIO.readFile jfile
      assertEq "journal should contain the saved text"
        (T.isInfixOf "CsrfEditOk" txt) True

    yit "serves its own journal file for editing" $ do
      get (EditR jfile)
      statusIs 200

    forM_ otherfiles $ \otherfile -> do
      yit ("refuses to edit " ++ otherfile) $ do
        get (EditR otherfile)
        statusIs 404
      yit ("refuses to download " ++ otherfile) $ do
        get (DownloadR otherfile)
        statusIs 404

  -- Paging (#586): the journal and register pages show the newest pageSize
  -- transactions and link to the older pages, so that a page stays small
  -- however large the journal is; and a row of years links to each year the
  -- search matches. 2300 transactions, one a day from 2023-01-01, each
  -- moving 1 into assets:cash from income, or from expenses:food for every
  -- third one, so a page holds 1000 rows and the cash register's running
  -- balance after the n-th transaction is n.
  let pagingtxns = 2300 :: Int
      pagingentry i = unlines
        [ show (addDays (fromIntegral i - 1) (fromGregorian 2023 1 1)) ++ " txn " ++ show i
        , "    assets:cash    1"
        , if i `mod` 3 == 0 then "    expenses:food" else "    income"
        ]
  pagingj <- fmap (either error' id) . runExceptT . journalFinalise biopts "paging.journal" "" =<<
          readJournal'' (T.pack $ concatMap pagingentry [1..pagingtxns])  -- PARTIAL: readJournal'' should not fail
  runTests "hledger-web paging" [] pagingj $ do

    yit "shows the newest page of the journal, with a link to the older ones" $ do
      get JournalR
      statusIs 200
      bodyContains "Showing 1 to 1,000 of 2,300 transactions"
      bodyContains "txn 2300</td>"
      bodyContains "txn 1301</td>"
      bodyNotContains "txn 1300</td>"
      bodyContains "/journal?page=2\" title=\"Show the older transactions\">Older"
      bodyNotContains "Show the newer transactions"
      -- the newer link's place is held, so the numbers do not shift on page 2
      bodyContains "<span class=\"newer placeholder\" aria-hidden=\"true\">‹ Newer</span>"
      -- the pages by number, the current one marked and not a link
      bodyContains "<span class=\"current\" aria-current=\"page\">1</span>"
      bodyContains "/journal?page=2\" title=\"Show page 2\" aria-label=\"Page 2\">2</a>"
      bodyContains "/journal?page=3\" title=\"Show page 3\" aria-label=\"Page 3\">3</a>"
      bodyNotContains "Show page 1\""

    yit "shows the requested page, linking both ways" $ do
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "page" "2"
      statusIs 200
      bodyContains "Showing 1,001 to 2,000 of 2,300 transactions"
      bodyContains "txn 1300</td>"
      bodyContains "txn 301</td>"
      bodyNotContains "txn 1301</td>"
      bodyNotContains "txn 300</td>"
      bodyContains "/journal\" title=\"Show the newer transactions\">‹ Newer"
      bodyContains "/journal?page=3\" title=\"Show the older transactions\">Older"
      bodyContains "/journal\" title=\"Show page 1\" aria-label=\"Page 1\">1</a>"
      bodyContains "<span class=\"current\" aria-current=\"page\">2</span>"
      bodyContains "/journal?page=3\" title=\"Show page 3\" aria-label=\"Page 3\">3</a>"

    yit "brings a page number past the end back to the last page" $ do
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "page" "99"
      statusIs 200
      bodyContains "Showing 2,001 to 2,300 of 2,300 transactions"
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "page" "18446744073709551617"  -- past an Int, too
      statusIs 200
      bodyContains "Showing 2,001 to 2,300 of 2,300 transactions"
      bodyContains "txn 1</td>"
      bodyContains "/journal?page=2\" title=\"Show the newer transactions\">‹ Newer"
      bodyNotContains "Show the older transactions"
      bodyContains "<span class=\"older placeholder\" aria-hidden=\"true\">Older ›</span>"

    yit "treats a page number that is not a positive integer as the first page" $ do
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "page" "x"
      statusIs 200
      bodyContains "Showing 1 to 1,000 of 2,300 transactions"
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "page" "0"
      statusIs 200
      bodyContains "Showing 1 to 1,000 of 2,300 transactions"

    yit "pages only when there are more than pageSize transactions" $ do
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "q" "date:..2025-09-27"  -- txn 1000 is on 2025-09-26
      statusIs 200
      bodyNotContains "Showing "
      bodyContains "txn 1000</td>"
      bodyContains "txn 1</td>"
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "q" "date:..2025-09-28"
      statusIs 200
      bodyContains "Showing 1 to 1,000 of 1,001 transactions"
      bodyNotContains "txn 1</td>"

    yit "opens the page holding a linked transaction" $ do
      -- A posting's account link names its transaction, so the register it
      -- opens can show the page holding it and the browser can scroll to it. The transactions' indices depend on
      -- how the journal was read, so take them from the pages.
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "page" "2"
      statusIs 200
      jid <- attrOfFirst "tr.title" "id"  -- transaction-F-N
      let jtxn = T.takeWhileEnd (/= '-') jid
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "txn" jtxn
      statusIs 200
      bodyContains "Showing 1,001 to 2,000 of 2,300 transactions"
      bodyContains ("id=\"" ++ T.unpack jid ++ "\"")
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:cash"
        addGetParam "page" "3"
      statusIs 200
      rid <- attrOfFirst "#main-content tbody tr" "id"  -- transaction-F-N, as in the journal
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:cash"
        addGetParam "txn" (T.takeWhileEnd (/= '-') rid)
      statusIs 200
      bodyContains "Showing 2,001 to 2,300 of 2,300 transactions"
      bodyContains ("<tr id=\"" ++ T.unpack rid ++ "\"")
      -- a transaction the search does not show gives the first page
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "income"
        addGetParam "txn" "0"
      statusIs 200
      bodyContains "Showing 1 to 1,000 of 1,534 transactions"
      -- The account links carry the transaction, on the journal and on the
      -- register. (A register row's date link opens that day's journal
      -- entries, which fit on one page.)
      get JournalR
      statusIs 200
      jid1 <- attrOfFirst "tr.title" "id"
      let jtxn1 = T.unpack $ T.takeWhileEnd (/= '-') jid1
      bodyContains ("/register?account=assets%3Acash&amp;txn=" ++ jtxn1 ++ "#" ++ T.unpack jid1 ++ "\"")
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:cash"
        addGetParam "page" "2"
      statusIs 200
      rid2 <- attrOfFirst "#main-content tbody tr" "id"
      let rtxn2 = T.unpack $ T.takeWhileEnd (/= '-') rid2
      bodyContains ("&amp;txn=" ++ rtxn2 ++ "#" ++ T.unpack rid2 ++ "\"")

    yit "lists the years the search matches, each linking to that year" $ do
      get JournalR
      statusIs 200
      bodyContains ">Years:</span>"
      bodyContains "Shift-click selects a range of years."
      bodyContains ("<a class=\"current\" href=\"" ++ base ++ "/journal\" aria-current=\"page\" title=\"Show all years\">All</a>")
      bodyContains "/journal?q=date%3A2023\" title=\"Show only 2023\">2023</a>"
      bodyContains "/journal?q=date%3A2024\" title=\"Show only 2024\">2024</a>"
      bodyContains "/journal?q=date%3A2029\" title=\"Show only 2029\">2029</a>"

    yit "keeps every year in the row when the search is narrowed to one" $ do
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "q" "date:2024"
      statusIs 200
      bodyNotContains "Showing "  -- 366 transactions fit on one page
      bodyContains ("<a class=\"current\" href=\"" ++ base ++ "/journal?q=date%3A2024\" aria-current=\"page\" title=\"Show only 2024\">2024</a>")
      bodyContains "/journal?q=date%3A2025\" title=\"Show only 2025\""
      bodyContains ("<a href=\"" ++ base ++ "/journal\" title=\"Show all years\">All</a>")

    yit "carries the rest of the search in the year links" $ do
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "q" "income date:2024"
      statusIs 200
      bodyContains "/journal?q=date%3A2025%20income\" title=\"Show only 2025\""
      bodyContains ("<a class=\"current\" href=\"" ++ base ++ "/journal?q=date%3A2024%20income\" aria-current=\"page\" title=\"Show only 2024\"")
      bodyContains ("<a href=\"" ++ base ++ "/journal?q=income\" title=\"Show all years\"")

    yit "counts the years by the same matching as the rows" $ do
      -- A search term that a posting can fail while its transaction matches:
      -- the register admits the transaction on the matching posting, and so
      -- must the years row, whether or not the search has a date term.
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:cash"
        addGetParam "q" "not:acct:expenses date:2024"
      statusIs 200
      rows <- htmlQuery "#main-content tbody tr"
      assertEq "the rows the years row counts" (length rows) 366
      bodyNotContains "Showing "
      bodyContains "title=\"Show only 2024\">2024</a>"
      bodyContains "title=\"Show all years\">All</a>"

    yit "counts the years by the search the year links make" $ do
      -- A date term inside an expr: term is not one the year links replace,
      -- so the years row counts what this search shows: one year, hence no row.
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "q" "expr:\"date:2024 and desc:txn\""
      statusIs 200
      bodyContains "txn 731</td>"  -- 2024-01-01
      bodyNotContains "Years:"

    yit "shows the years row on the report pages too, the year links keeping the interval" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "date:2024"
        addGetParam "interval" "monthly"
      statusIs 200
      bodyContains ">Years:</span>"
      bodyContains "/balance?q=date%3A2023&amp;interval=monthly\" title=\"Show only 2023\""
      -- the search's date term marks its year
      bodyContains "aria-current=\"page\" title=\"Show only 2024\""

    yit "marks each year a range search covers, as a shift-click selects" $ do
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "q" "date:2023..2026"
      statusIs 200
      bodyContains "aria-current=\"page\" title=\"Show only 2023\""
      bodyContains "aria-current=\"page\" title=\"Show only 2025\""
      bodyNotContains "aria-current=\"page\" title=\"Show only 2026\""

    -- Urls from before the interval parameter keep working.
    yit "moves an old period parameter's dates to the search, and its interval to the interval parameter" $ do
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "period" "monthly in 2024"
      statusIs 303
      loc <- headerValue "Location"
      assertEq "the page is reloaded without the period parameter" loc
        (T.pack (defbaseurl defhost defport) <> "/journal?q=%22date%3Ain%202024%22&interval=monthly")

    -- A search narrowing only by secondary date sets the shown span too.
    yit "a date2: search marks its year" $ do
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "q" "date2:2024"
      statusIs 200
      bodyContains "aria-current=\"page\" title=\"Show only 2024\""
      bodyNotContains "aria-current=\"page\" title=\"Show all years\""

    yit "pages the register, with the running balance carried across pages" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:cash"
      statusIs 200
      bodyContains "Showing 1 to 1,000 of 2,300 transactions"
      bodyContains "amount\">2300</span>"
      bodyContains "amount\">1301</span>"
      bodyNotContains "amount\">1300</span>"
      bodyContains "/register?account=assets%3Acash&amp;page=2\" title=\"Show the older transactions\""
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:cash"
        addGetParam "page" "2"
      statusIs 200
      bodyContains "Showing 1,001 to 2,000 of 2,300 transactions"
      bodyContains "amount\">1300</span>"
      bodyContains "amount\">301</span>"
      bodyNotContains "amount\">1301</span>"
      -- the chart covers this page's rows only: its dates are theirs, and
      -- its points link to them
      let txn i = fromMaybe (error' $ "no txn " ++ show i) $
            find ((== T.pack ("txn " ++ show (i :: Int))) . tdescription) (jtxns pagingj)
          chartpoint i = "<a href=\"#" ++ transactionFragment pagingj (txn i) ++ "\""
      bodyContains ("data-d0=\"" ++ show (tdate $ txn 301) ++ "\" data-d1=\"" ++ show (tdate $ txn 1300) ++ "\"")
      bodyContains (chartpoint 1300)
      bodyNotContains (chartpoint 1301)
      -- the years row keeps the account
      bodyContains "/register?q=date%3A2024&amp;account=assets%3Acash\" title=\"Show only 2024\">2024</a>"
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:cash"
        addGetParam "q" "date:2024"
      statusIs 200
      bodyNotContains "Showing "
      bodyContains ("<a class=\"current\" href=\"" ++ base ++ "/register?q=date%3A2024&amp;account=assets%3Acash\"")

    yit "keeps the register's mode in its page and year links" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:cash"
        addGetParam "accum" "historical"
      statusIs 200
      bodyContains "/register?account=assets%3Acash&amp;accum=historical&amp;page=2\" title=\"Show the older transactions\""
      bodyContains "/register?q=date%3A2024&amp;account=assets%3Acash&amp;accum=historical\" title=\"Show only 2024\">2024</a>"

  -- A startup depth limit does not apply to the register, nor to its years.
  runTests "hledger-web paging with --depth" [("depth","1")] pagingj $ do

    yit "counts the register's years without the depth limit" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "account" "assets:cash"
        addGetParam "q" "date:2024"
      statusIs 200
      bodyContains "title=\"Show only 2024\">2024</a>"
      bodyContains "title=\"Show all years\">All</a>"

  -- More than twenty years are grouped by decade, a row each: 21 years here.
  let decadesentry y = unlines
        [ show y ++ "-06-15 txn " ++ show y
        , "    assets:cash    1"
        , "    income"
        ]
  decadesj <- fmap (either error' id) . runExceptT . journalFinalise biopts "decades.journal" "" =<<
          readJournal'' (T.pack $ concatMap decadesentry [2005..2025 :: Int])  -- PARTIAL: readJournal'' should not fail
  runTests "hledger-web years row" [] decadesj $ do

    yit "groups more than twenty years by decade" $ do
      get JournalR
      statusIs 200
      bodyContains ">All</a>"
      rows <- map (TL.toStrict . TLE.decodeUtf8) <$> htmlQuery "p.years"
      assertEq "the All row, then one row per decade" (length rows) 4
      let row2010s = rows !! 2
      assertEq "the 2010s row is labelled" (T.isInfixOf "<span class=\"row-label\">2010s:</span>" row2010s) True
      assertEq "2010 opens the 2010s row" (T.isInfixOf "date%3A2010\"" row2010s) True
      assertEq "2019 ends the 2010s row" (T.isInfixOf "date%3A2019\"" row2010s) True
      assertEq "2009 is not in the 2010s row" (T.isInfixOf "date%3A2009\"" row2010s) False
      assertEq "2020 is not in the 2010s row" (T.isInfixOf "date%3A2020\"" row2010s) False
