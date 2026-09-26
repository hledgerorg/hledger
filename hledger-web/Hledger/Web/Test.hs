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
  -- query logic, more options logic
  let depthlessinitialq = filterQuery (not . queryIsDepth) . _rsQuery . reportspec_ $ cliopts_ wopts
      j' = filterJournalTransactions depthlessinitialq j
      h = host_ wopts
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

import Data.Aeson (encode)
import Data.String (fromString)
import Data.Function ((&))
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Encoding qualified as TLE
import Network.Wai.Test (SResponse(..))
import System.Directory (getTemporaryDirectory)
import System.FilePath ((</>))
import Test.Hspec (expectationFailure, hspec)
import Web.Cookie (defaultSetCookie, setCookieName, setCookieValue)
import Yesod.Default.Config
import Yesod.Test

import Hledger.Web.Application ( makeAppWith )
import Hledger.Web.WebOptions  -- ( WebOpts(..), defwebopts, prognameandversion )
import Hledger.Web.Import hiding (get, j)
import Hledger.Web.Widget.Common (transactionFragment)
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
editFieldName = do
  els <- htmlQuery "textarea"
  case els of
    [] -> error' "no textarea in the edit form"
    (e:_) -> do
      let needle = "name=\""
          html = TL.toStrict (TLE.decodeUtf8 e)
          (_, fromneedle) = T.breakOn needle html
          afterneedle = T.drop (T.length needle) fromneedle
          fieldname = T.takeWhile (/= '"') afterneedle
      if T.null fromneedle
        then error' "the edit form's textarea has no name"
        else return fieldname

-- | The current response's Content-Security-Policy header, failing the test
-- if there is none.
cspHeaderValue :: YesodExample App T.Text
cspHeaderValue = withResponse $ \res ->
  case lookup "Content-Security-Policy" (simpleHeaders res) of
    Just h  -> return $ TE.decodeUtf8 h
    Nothing -> failing "the response has no Content-Security-Policy header"

-- | The nonce in the current response's Content-Security-Policy, failing the
-- test if the header or the nonce is missing.
cspNonce :: YesodExample App T.Text
cspNonce = do
  csp <- cspHeaderValue
  let (_, fromnonce) = T.breakOn "'nonce-" csp
  if T.null fromnonce
    then failing "the Content-Security-Policy has no nonce"
    else return $ T.takeWhile (/= '\'') $ T.drop (T.length "'nonce-") fromnonce

-- | Fail the current test with a message. (yesod-test's own version of this
-- is not exported.)
failing :: String -> YesodExample App a
failing msg = liftIO (expectationFailure msg) >> error "unreachable: expectationFailure returned"

-- | Run hledger-web's built-in tests using the hspec test runner.
hledgerWebTest :: IO ()
hledgerWebTest = do
  putStrLn $ "Running tests for " ++ prognameandversion -- ++ " (--test --help for options)"
  let d = fromGregorian 2000 1 1

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

  -- The balance page: the balance report, or with a period expression,
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

    yit "serves the balance report, linking accounts to their register" $ do
      get BalanceR
      statusIs 200
      bodyContains "<h2>Balance report</h2>"
      bodyContains "href=\"register?q=inacct:assets:bank:checking\""
      bodyContains "<tfoot>"
      bodyContains "class=\"amount negative\""

    yit "styles the report through the stylesheet, not inline styles" $ do
      get BalanceR
      statusIs 200
      bodyNotContains "<style"
      bodyNotContains "style=\""

    yit "serves the multi-period report for a period expression" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "period" "monthly"
      statusIs 200
      bodyContains "Balance changes in 2025-01-01..2025-02-28"
      bodyContains ">2025-01<"
      bodyContains ">2025-02<"
      -- the search form keeps the period, and marks the current report
      bodyContains "<input type=\"hidden\" name=\"period\" value=\"monthly\">"
      bodyContains "class=\"current\""

    yit "restricts the report to the period expression's date span" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "period" "2025-01"
      statusIs 200
      -- the report's own account links are relative (the sidebar's are not),
      -- and carry the period, so the register they open is restricted too
      bodyContains "href=\"register?q=inacct:assets:bank:checking+date:2025-01\""
      bodyNotContains "href=\"register?q=inacct:expenses:food"

    yit "honors a depth limit in the search" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "depth:1"
      statusIs 200
      bodyContains "href=\"register?q=inacct:assets+depth:1\""
      bodyNotContains "href=\"register?q=inacct:assets:bank:checking"

    yit "reports a period expression it cannot parse" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "period" "bogus"
      statusIs 200
      bodyContains "Could not parse the period expression"
      bodyNotContains "<tfoot>"

    yit "takes an interval from a date: search term, as the cli does" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "date:monthly"
      statusIs 200
      bodyContains ">2025-01<"
      bodyContains ">2025-02<"

    yit "prefers a search term's interval to the period parameter" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "period" "yearly"
        addGetParam "q" "date:monthly"
      statusIs 200
      bodyContains ">2025-01<"
      bodyNotContains ">2025<"
    yit "marks the report being shown for the interval" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "period" "monthly"
        addGetParam "q" "date:yearly"
      statusIs 200
      -- the search term wins, so the yearly link is the current one
      bodyContains ("class=\"current\" href=\"" ++ defbaseurl defhost defport ++ "/balance?period=yearly")

    yit "keeps the period's date span in the report links" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "period" "monthly in 2025"
      statusIs 200
      bodyContains "balance?period=yearly%202025"

    yit "uses --title for the heading, unaltered" $ do
      get BalanceR
      statusIs 200
      bodyContains "<h2>Balance report</h2>"

    yit "escapes account names and search terms in the page" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "q" "<img src=x onerror=alert(1)>"
      statusIs 200
      bodyNotContains "<img src=x onerror"

    yit "keeps the period parameter off the other pages' search forms" $ do
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "period" "monthly"
      statusIs 200
      bodyNotContains "name=\"period\""

    yit "shows balance changes for a period, and says so" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "period" "2025-02"
      statusIs 200
      bodyContains "<h2>Balance changes in 2025-02</h2>"
      -- the report's own links are relative (the sidebar's are not)
      bodyNotContains "href=\"register?q=inacct:income:salary"
      bodyContains ("class=\"current\" href=\"" ++ defbaseurl defhost defport ++ "/balance?period=2025-02\" title=\"Show how much")

    yit "shows ending balances with accum=historical, asking their registers for the same" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "period" "2025-02"
        addGetParam "accum" "historical"
      statusIs 200
      bodyContains "<h2>Ending balances (historical) in 2025-02</h2>"
      -- no February postings, but a balance, whose register must start from before February
      bodyContains "href=\"register?q=inacct:income:salary+date:2025-02&amp;accum=historical\""
      -- the search form and the interval links keep the mode; the mode links mark it
      bodyContains "<input type=\"hidden\" name=\"accum\" value=\"historical\">"
      bodyContains "/balance?period=monthly%202025-02&amp;accum=historical\""
      bodyContains ("class=\"current\" href=\"" ++ defbaseurl defhost defport ++ "/balance?period=2025-02&amp;accum=historical\"")

    yit "heads ending balance columns with their end dates, linking to this report for the period" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "period" "monthly"
        addGetParam "accum" "historical"
      statusIs 200
      bodyContains ">2025-01-31<"
      bodyContains ">2025-02-28<"
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/balance?period=2025-01&amp;accum=historical\" title=\"Show this report for this period\"")

    yit "links a balance change column's heading to this report for the period" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "period" "monthly"
        addGetParam "q" "date:2025"
      statusIs 200
      bodyContains ">2025-01<"
      -- the column's period replaces the search's date term
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/balance?period=2025-01\" title=\"Show this report for this period\"")

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

  -- The journal, register, and sidebar link to one another: a date to that
  -- day's journal entries, an account to its register, an amount to the
  -- register that derives it, an entry to itself on either page.
  -- The journal, register, and sidebar link to one another: a date to that
  -- day's journal entries, an account to its register, an amount to the
  -- register that derives it, an entry to itself on either page.
  let base = defbaseurl defhost defport
      -- an entry's id (transaction-FILE-INDEX), as the pages compute it
      frag desc = maybe (error' $ "no transaction " ++ desc) (transactionFragment bj) $
        find ((== T.pack desc) . tdescription) (jtxns bj)
  runTests "hledger-web journal, register, and sidebar links" [] bj $ do

    yit "links a journal entry's date to that day's entries, and its accounts to their registers at the entry" $ do
      get JournalR
      statusIs 200
      bodyContains ("href=\"" ++ base ++ "/journal?q=date%3A2025-01-05#" ++ frag "pay" ++ "\" title=\"Show the journal entries on this date\">")
      bodyContains ("href=\"" ++ base ++ "/register?q=inacct%3Aassets%3Abank%3Achecking#" ++ frag "lunch" ++ "\" title=\"assets:bank:checking\">")

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
        addGetParam "q" "inacct:assets:bank:checking"
      statusIs 200
      bodyContains ("<tr id=\"" ++ frag "lunch" ++ "\"")
      bodyContains ("href=\"" ++ base ++ "/journal?q=date%3A2025-02-05#" ++ frag "lunch" ++ "\" title=\"Show this entry and the other journal entries on its date\">")
      bodyContains ("href=\"" ++ base ++ "/register?q=inacct%3Aexpenses%3Afood#" ++ frag "lunch" ++ "\" title=\"expenses:food\">")
      -- the chart's points name the entries the same way, and its base link is the register's
      bodyContains ("&quot;" ++ frag "lunch" ++ "&quot;")
      bodyContains ("data-baselink=\"" ++ base ++ "/register?q=inacct%3Aassets%3Abank%3Achecking\"")

    yit "replaces the search's date terms in a date link, and keeps its other terms" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "q" "inacct:assets:bank:checking date:2025-02 not:desc:\"x y\""
      statusIs 200
      bodyContains ("href=\"" ++ base ++ "/journal?q=date%3A2025-02-05%20%22not%3Adesc%3Ax%20y%22#" ++ frag "lunch" ++ "\"")
      -- (the sidebar's Journal link keeps the search as typed; the date links are the ones with a fragment)
      bodyNotContains "/journal?q=date%3A2025-02%20%22not%3Adesc%3Ax%20y%22#"

    yit "links the sidebar's amounts where their account names go" $ do
      get JournalR
      statusIs 200
      bodyContains ("<a href=\"" ++ base ++ "/register?q=inacct%3Aassets%3Abank%3Achecking\" title=\"Show the transactions that make up this balance\">")
      -- an empty search adds no trailing term to the account links
      bodyNotContains "inacct%3Aassets%20\""
      -- an unfiltered journal's total is zero, and does not link
      bodyNotContains "Show the transactions that make up this total"

    yit "keeps the search, minus its account term, on the sidebar's Journal link" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "q" "inacct:assets:bank:checking date:2025"
      statusIs 200
      bodyContains ("<a href=\"" ++ base ++ "/journal?q=date%3A2025\" title=\"Show general journal entries, most recent first\">")
      get JournalR
      statusIs 200
      bodyContains ("<a class=\"inacct\" href=\"" ++ base ++ "/journal\" title=\"Show general journal entries, most recent first\">")

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

    -- The register's table has a tbody; the sidebar, which shows the same
    -- accounts, has none, so these assertions look only at the register.
    yit "totals the period from zero by default" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "q" "inacct:assets:bank:checking date:2025-02"
      statusIs 200
      bodyContains ">Period Total</a>"
      htmlAnyContain "#main-content tbody td.amount" "-10"
      bodyNotContains ">90<"
      bodyNotContains "Balance brought forward"
      bodyNotContains "name=\"accum\""
      -- the balance column's heading switches to historical mode
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/register?q=inacct%3Aassets%3Abank%3Achecking%20date%3A2025-02&amp;accum=historical\" title=\"Show the running balance including everything before this period\">Period Total</a>")

    yit "starts from the balance brought forward with accum=historical" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "q" "inacct:assets:bank:checking date:2025-02"
        addGetParam "accum" "historical"
      statusIs 200
      bodyContains ">Historical Total</a>"
      htmlAnyContain "#main-content tbody td.amount" "90"
      -- the oldest row is the balance brought forward, linking to the transactions before the period
      htmlAnyContain "#main-content tbody tr.broughtforward td.amount" "100"
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/register?q=inacct%3Aassets%3Abank%3Achecking%20date%3A..2025-02-01\" title=\"Show the transactions before this period\">")
      -- the search form, the other-account links, and the chart's base link keep the mode
      bodyContains "<input type=\"hidden\" name=\"accum\" value=\"historical\">"
      bodyContains "&amp;accum=historical#"
      bodyContains ("data-baselink=\"" ++ defbaseurl defhost defport ++ "/register?q=inacct%3Aassets%3Abank%3Achecking&amp;accum=historical\"")
      -- the heading switches back, dropping the mode
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/register?q=inacct%3Aassets%3Abank%3Achecking%20date%3A2025-02\" title=\"Show the running balance from the start of this period\">Historical Total</a>")

    yit "cuts the balance brought forward off by the kind of date the query has" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "q" "inacct:assets:bank:checking date2:2025-02"
        addGetParam "accum" "historical"
      statusIs 200
      bodyContains "date2%3A..2025-02-01\" title=\"Show the transactions before this period\">"

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
      bodyContains "<tr class=\"section\"><th colspan=\"2\" scope=\"rowgroup\">Assets</th></tr>"
      bodyContains "<tr class=\"section\"><th colspan=\"2\" scope=\"rowgroup\">Liabilities</th></tr>"
      bodyContains "<tr class=\"subtotal\">"
      bodyContains "<tfoot>"
      bodyContains "Net:"
      -- figures link to registers in historical mode, restricted to the
      -- section's account types; a liability's says its sign differs
      bodyContains "href=\"register?q=inacct:assets:bank:checking+type:A&amp;accum=historical\""
      bodyContains "href=\"register?q=inacct:liabilities:card+date:2025-01-01..2025-02-07+type:L&amp;accum=historical\" title=\"Show the transactions behind this balance, which the register shows with the opposite sign\">"
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
        addGetParam "period" "monthly"
      statusIs 200
      bodyContains "<h2>Monthly Balance Sheet 2025-01-31..2025-02-28</h2>"
      bodyContains ">2025-01-31<"
      bodyContains ">2025-02-28<"
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/balancesheet?period=2025-01\" title=\"Show this report for this period\"")
      bodyContains "<input type=\"hidden\" name=\"period\" value=\"monthly\">"

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
      bodyContains "/balancesheet?period=monthly&amp;accum=change\""

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
      bodyContains "href=\"register?q=inacct:income:salary+date:2025-01-01..2025-02-07+type:R\" title=\"Show the transactions that make up this amount, which the register shows with the opposite sign\">"
      bodyContains "href=\"register?q=type:RX+date:2025-01-01..2025-02-07\" title=\"Show the transactions that make up this total, which the register shows with the opposite sign\">"
      bodyNotContains "accum="

    yit "shows the income statement's ending balances when asked, and says so" $ do
      request $ do
        setMethod "GET"
        setUrl IncomestatementR
        addGetParam "accum" "historical"
      statusIs 200
      bodyContains "<h2>Income Statement 2025-02-06 (Historical Ending Balances)</h2>"
      bodyContains "<input type=\"hidden\" name=\"accum\" value=\"historical\">"
      bodyContains "href=\"register?q=inacct:income:salary+type:R&amp;accum=historical\""

    yit "serves the cashflow statement, with one section and no net total" $ do
      get CashflowR
      statusIs 200
      bodyContains "<h2>Cashflow Statement 2025-01-01..2025-02-06</h2>"
      bodyContains ">Cash flows</th>"
      bodyNotContains "<tfoot>"

    yit "serves the balance sheet with equity" $ do
      get BalancesheetequityR
      statusIs 200
      bodyContains "<h2>Balance Sheet With Equity 2025-02-06</h2>"
      bodyContains ">Equity</th>"
      bodyContains "href=\"register?q=type:ALE+date:2025-01-01..2025-02-07&amp;accum=historical\""

    yit "links the reports to one another, marking the one shown, and to the balance report" $ do
      request $ do
        setMethod "GET"
        setUrl IncomestatementR
        addGetParam "period" "quarterly"
        addGetParam "q" "inacct:assets:bank:checking expenses"
      statusIs 200
      -- the links keep the period and the search minus its account term
      bodyContains ("class=\"current\" href=\"" ++ defbaseurl defhost defport ++ "/incomestatement?period=quarterly&amp;q=expenses\" title=\"Show revenues and expenses\"")
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/balancesheet?period=quarterly&amp;q=expenses\" title=\"Show assets, liabilities, and net worth\"")
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/balance?period=quarterly&amp;q=expenses\" title=\"Show the balance report: any accounts, by period\"")

    yit "links the balance report to the statements too" $ do
      get BalanceR
      statusIs 200
      bodyContains ("class=\"current\" href=\"" ++ defbaseurl defhost defport ++ "/balance\" title=\"Show the balance report: any accounts, by period\"")
      bodyContains ("href=\"" ++ defbaseurl defhost defport ++ "/incomestatement\" title=\"Show revenues and expenses\"")

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
        addGetParam "period" "quarterly"
        addGetParam "accum" "historical"
        addGetParam "q" "inacct:assets:bank:checking expenses"
      statusIs 200
      -- the period is kept, the mode is not: it belongs to this report
      bodyContains ("colspan=\"2\"><a href=\"" ++ defbaseurl defhost defport ++ "/balancesheet?period=quarterly&amp;q=expenses\" title=\"Show assets, liabilities, and net worth\">")
      bodyNotContains "/balancesheet?period=quarterly&amp;accum"

    yit "links the sidebar's reports from the journal and register too" $ do
      request $ do
        setMethod "GET"
        setUrl RegisterR
        addGetParam "q" "inacct:assets:bank:checking date:2025"
      statusIs 200
      bodyContains ("colspan=\"2\"><a href=\"" ++ defbaseurl defhost defport ++ "/balancesheet?q=date%3A2025\" title=\"Show assets, liabilities, and net worth\">")
      request $ do
        setMethod "GET"
        setUrl JournalR
        addGetParam "q" "date:2025"
      statusIs 200
      bodyContains ("colspan=\"2\"><a href=\"" ++ defbaseurl defhost defport ++ "/incomestatement?q=date%3A2025\" title=\"Show revenues and expenses\">")

    yit "escapes account names and search terms in the statements" $ do
      get IncomestatementR
      statusIs 200
      bodyContains "title=\"Show transactions affecting this account and subaccounts\">expenses:snacks&lt;i&gt;x</a>"
      bodyNotContains "snacks<i>x"
      request $ do
        setMethod "GET"
        setUrl IncomestatementR
        addGetParam "q" "<img src=x onerror=alert(1)>"
      statusIs 200
      bodyNotContains "<img src=x onerror"

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

    yit "says when the accounts are all hidden zero balances" $ do
      get BalancesheetR
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
      bodyContains "href=\"register?q=inacct:assets:zeroed\""
      -- a zero sidebar amount has an empty register, and no link
      bodyNotContains "inacct%3Aassets%3Azeroed\" title=\"Show the transactions that make up this balance\""
      bodyContains "inacct%3Aassets%3Akept\" title=\"Show the transactions that make up this balance\""

    yit "hides them when the sidebar does (the e key's cookie)" $ do
      testSetCookie defaultSetCookie{setCookieName = "hideemptyaccts", setCookieValue = "1"}
      get BalanceR
      statusIs 200
      bodyContains "href=\"register?q=inacct:assets:kept\""
      bodyNotContains "href=\"register?q=inacct:assets:zeroed\""

  runTests "hledger-web with -E" [("empty","")] ej $ do

    yit "hides zero items, the opposite of the command line" $ do
      get BalanceR
      statusIs 200
      bodyContains "href=\"register?q=inacct:assets:kept\""
      bodyNotContains "href=\"register?q=inacct:assets:zeroed\""

  runTests "hledger-web with --monthly" [("monthly","")] bj $ do

    yit "keeps the interval the server was started with" $ do
      get BalanceR
      statusIs 200
      bodyContains ">2025-01<"
      bodyContains ">2025-02<"

    yit "and still takes a period parameter over it" $ do
      request $ do
        setMethod "GET"
        setUrl BalanceR
        addGetParam "period" "yearly"
      statusIs 200
      bodyContains ">2025<"
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


