{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE OverloadedStrings #-}
{-|

'AccountName's are strings like @assets:cash:petty@, with multiple
components separated by ':'.  From a set of these we derive the account
hierarchy.

-}

module Hledger.Data.AccountName (
   accountLeafName
  ,accountNameComponents
  ,accountNameDrop
  ,accountNameFromComponents
  ,accountNameLevel
  ,accountNameToAccountOnlyRegex
  ,accountNameToAccountOnlyRegexCI
  ,accountNameToAccountRegex
  ,accountNameToAccountRegexCI
  ,accountNameTreeFrom
  ,accountSummarisedName
  ,accountNameInferType
  ,accountNameInferTypeExcept
  ,accountNameType
  ,defaultBaseConversionAccount
  ,defaultGainAccount
  ,assetAccountRegex
  ,cashAccountRegex
  ,liabilityAccountRegex
  ,equityAccountRegex
  ,conversionAccountRegex
  ,revenueAccountRegex
  ,gainAccountRegex
  ,unrealisedGainAccountRegex
  ,expenseAccountRegex
  ,acctsep
  ,acctsepchar
  ,clipAccountName
  ,clipOrEllipsifyAccountName
  ,getAccountNameClippedDepth
  ,elideAccountName
  ,escapeName
  ,expandAccountName
  ,expandAccountNames
  ,isAccountNamePrefixOf
--  ,isAccountRegex
  ,isSubAccountNameOf
  ,parentAccountName
  ,parentAccountNames
  ,subAccountNamesFrom
  ,topAccountNames
  ,topAccountName
  ,unbudgetedAccountName
  ,accountNamePostingType
  ,accountNameWithoutPostingType
  ,accountNameWithPostingType
  ,joinAccountNames
  ,concatAccountNames
  ,accountNameApplyAliases
  ,accountNameApplyAliasesMemo
  ,tests_AccountName
)
where

import Control.Applicative ((<|>))
import Control.Monad (foldM)
import Data.Foldable (asum, find, toList)
import Data.List.NonEmpty qualified as NE
import Data.Map qualified as M
import Data.Maybe (mapMaybe)
import Data.MemoUgly (memo)
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import Data.Tree (Tree(..), unfoldTree)
import Safe
import Text.DocLayout (realLength)

import Hledger.Data.Types hiding (asubs)
import Hledger.Utils
import Data.List (partition)

-- $setup
-- >>> :set -XOverloadedStrings

acctsepchar :: Char
acctsepchar = ':'

acctsep :: Text
acctsep = T.pack [acctsepchar]

-- The base conversion account name used by --infer-equity,
-- when no other account of type V/Conversion has been declared.
defaultBaseConversionAccount = "equity:conversion"

-- The default account name for inferred gain postings,
-- when no other account of type G/Gain has been declared.
defaultGainAccount = "revenues:gain"

-- | Regular expressions matching common English top-level account names,
-- used as a fallback when account types are not declared.
assetAccountRegex      = toRegexCI' "^assets?(:|$)"
cashAccountRegex       = toRegexCI' "^assets?(:.+)?:(cash|bank|che(ck|que?)(ing)?|savings?|current)(:|$)"
liabilityAccountRegex  = toRegexCI' "^(debts?|liabilit(y|ies))(:|$)"
equityAccountRegex     = toRegexCI' "^equity(:|$)"
conversionAccountRegex = toRegexCI' "^equity:(trade|trades|trading|conversion)(:|$)"
revenueAccountRegex    = toRegexCI' "^(income|revenue)s?(:|$)"
gainAccountRegex       = toRegexCI' "^(income|revenue)s?:(capital[- ]?)?(gains?|loss(es)?)(:|$)"
unrealisedGainAccountRegex = toRegexCI' "^equity:unreali[sz]ed([- ](capital[- ])?gains?)?(:|$)"
expenseAccountRegex    = toRegexCI' "^expenses?(:|$)"

-- | Try to guess an account's type from its name,
-- matching common English top-level account names.
accountNameInferType :: AccountName -> Maybe AccountType
accountNameInferType a
  | regexMatchText cashAccountRegex            a = Just Cash
  | regexMatchText assetAccountRegex           a = Just Asset
  | regexMatchText liabilityAccountRegex       a = Just Liability
  | regexMatchText conversionAccountRegex      a = Just Conversion
  | regexMatchText unrealisedGainAccountRegex  a = Just UnrealisedGain
  | regexMatchText equityAccountRegex          a = Just Equity
  | regexMatchText gainAccountRegex            a = Just Gain
  | regexMatchText revenueAccountRegex         a = Just Revenue
  | regexMatchText expenseAccountRegex         a = Just Expense
  | otherwise                                    = Nothing

-- | Like accountNameInferType, but exclude the provided types from the guesses.
-- Used eg to prevent "equity:conversion" being inferred as Conversion when a different
-- account has been declared with that type.
accountNameInferTypeExcept :: [AccountType] -> AccountName -> Maybe AccountType
accountNameInferTypeExcept excludedtypes a =
  case accountNameInferType a of
    Just t | not $ t `elem` excludedtypes -> Just t
    _ -> Nothing

-- Extract the 'AccountType' of an 'AccountName' by looking it up in the
-- provided Map, traversing the parent accounts if necessary. If none of those
-- work, try 'accountNameInferType'.
accountNameType :: M.Map AccountName AccountType -> AccountName -> Maybe AccountType
accountNameType atypes a = asum (map (`M.lookup` atypes) $ a : parentAccountNames a)
                         <|> accountNameInferType a

-- accountNameComponents :: AccountName -> [String]
-- accountNameComponents = splitAtElement acctsepchar

accountNameComponents :: AccountName -> [Text]
accountNameComponents = T.splitOn acctsep

accountNameFromComponents :: [Text] -> AccountName
accountNameFromComponents = T.intercalate acctsep

accountLeafName :: AccountName -> Text
accountLeafName = last . accountNameComponents

-- | Truncate all account name components but the last to two characters.
accountSummarisedName :: AccountName -> Text
accountSummarisedName a
  --   length cs > 1 = take 2 (head cs) ++ ":" ++ a'
  | length cs > 1 = T.intercalate ":" (map (T.take 2) $ init cs) <> ":" <> a'
  | otherwise     = a'
    where
      cs = accountNameComponents a
      a' = accountLeafName a

-- | The level (depth) of an account name.
--
-- >>> accountNameLevel ""  -- special case
-- 0
-- >>> accountNameLevel "assets"
-- 1
-- >>> accountNameLevel "assets:cash"
-- 2
accountNameLevel :: AccountName -> Int
accountNameLevel "" = 0
accountNameLevel a = T.length (T.filter (==acctsepchar) a) + 1

-- | A top-level account prefixed to some accounts in budget reports.
-- Defined here so it can be ignored by accountNameDrop.
unbudgetedAccountName :: T.Text
unbudgetedAccountName = "<unbudgeted>"

accountNamePostingType :: AccountName -> PostingRealness
accountNamePostingType a
    | T.null a = RealPosting
    | T.head a == '[' && T.last a == ']' = BalancedVirtualPosting
    | T.head a == '(' && T.last a == ')' = VirtualPosting
    | otherwise = RealPosting

accountNameWithoutPostingType :: AccountName -> AccountName
accountNameWithoutPostingType a = case accountNamePostingType a of
                                    BalancedVirtualPosting -> textUnbracket a
                                    VirtualPosting -> textUnbracket a
                                    RealPosting -> a

accountNameWithPostingType :: PostingRealness -> AccountName -> AccountName
accountNameWithPostingType BalancedVirtualPosting = wrap "[" "]" . accountNameWithoutPostingType
accountNameWithPostingType VirtualPosting         = wrap "(" ")" . accountNameWithoutPostingType
accountNameWithPostingType RealPosting            = accountNameWithoutPostingType

-- | Prefix one account name to another, preserving posting type
-- indicators like concatAccountNames.
joinAccountNames :: AccountName -> AccountName -> AccountName
joinAccountNames a b = concatAccountNames $ filter (not . T.null) [a,b]

-- | Join account names into one. If any of them has () or [] posting type
-- indicators, these (the first type encountered) will also be applied to
-- the resulting account name.
concatAccountNames :: [AccountName] -> AccountName
concatAccountNames as = accountNameWithPostingType t $ T.intercalate ":" $ map accountNameWithoutPostingType as
    where t = headDef RealPosting $ filter (/= RealPosting) $ map accountNamePostingType as

-- | Rewrite an account name using all matching aliases from the given list, in sequence.
-- Each alias sees the result of applying the previous aliases.
-- Or, return any error arising from a bad regular expression in the aliases.
accountNameApplyAliases :: [AccountAlias] -> AccountName -> Either RegexError AccountName
accountNameApplyAliases aliases a =
  let (name,typ) = (accountNameWithoutPostingType a, accountNamePostingType a)
  in foldM
     (\acct alias -> dbg6 "result" $ aliasReplace (dbg6 "alias" alias) (dbg6 "account" acct))
     name
     aliases
     >>= Right . accountNameWithPostingType typ

-- | Memoising version of accountNameApplyAliases, maybe overkill.
accountNameApplyAliasesMemo :: [AccountAlias] -> AccountName -> Either RegexError AccountName
accountNameApplyAliasesMemo aliases = memo (accountNameApplyAliases aliases)
  -- XXX re-test this memoisation

-- aliasMatches :: AccountAlias -> AccountName -> Bool
-- aliasMatches (BasicAlias old _) a = old `isAccountNamePrefixOf` a
-- aliasMatches (RegexAlias re  _) a = regexMatchesCI re a

aliasReplace :: AccountAlias -> AccountName -> Either RegexError AccountName
aliasReplace (BasicAlias old new) a
  | old `isAccountNamePrefixOf` a || old == a =
      Right $ new <> T.drop (T.length old) a
  | otherwise = Right a
aliasReplace (RegexAlias re repl) a =
  fmap T.pack . regexReplace re repl $ T.unpack a -- XXX

-- | Remove some number of account name components from the front of the account name.
-- If the special "<unbudgeted>" top-level account is present, it is preserved and
-- dropping affects the rest of the account name.
accountNameDrop :: Int -> AccountName -> AccountName
accountNameDrop n a
  | a == unbudgetedAccountName = a
  | unbudgetedAccountAndSep `T.isPrefixOf` a =
      case accountNameDrop n $ T.drop (T.length unbudgetedAccountAndSep) a of
        "" -> unbudgetedAccountName
        a' -> unbudgetedAccountAndSep <> a'
  | otherwise = accountNameFromComponentsOrElide . drop n $ accountNameComponents a
  where
    unbudgetedAccountAndSep = unbudgetedAccountName <> acctsep
    accountNameFromComponentsOrElide [] = "..."
    accountNameFromComponentsOrElide xs = accountNameFromComponents xs

-- | Sorted unique account names implied by these account names,
-- ie these plus all their parent accounts up to the root.
-- Eg: ["a:b:c","d:e"] -> ["a","a:b","a:b:c","d","d:e"]
expandAccountNames :: [AccountName] -> [AccountName]
expandAccountNames = toList . foldMap (S.fromList . expandAccountName)

-- | "a:b:c" -> ["a","a:b","a:b:c"]
expandAccountName :: AccountName -> [AccountName]
expandAccountName = map accountNameFromComponents . NE.tail . NE.inits . accountNameComponents

-- | ["a:b:c","d:e"] -> ["a","d"]
topAccountNames :: [AccountName] -> [AccountName]
topAccountNames = filter ((1==) . accountNameLevel) . expandAccountNames

-- | "a:b:c" -> "a"
topAccountName :: AccountName -> AccountName
topAccountName = T.takeWhile (/= acctsepchar)

parentAccountName :: AccountName -> AccountName
parentAccountName = accountNameFromComponents . init . accountNameComponents

parentAccountNames :: AccountName -> [AccountName]
parentAccountNames a = parentAccountNames' $ parentAccountName a
    where
      parentAccountNames' "" = []
      parentAccountNames' a2 = a2 : parentAccountNames' (parentAccountName a2)

-- | Is the first account a parent or other ancestor of (and not the same as) the second ?
isAccountNamePrefixOf :: AccountName -> AccountName -> Bool
isAccountNamePrefixOf = T.isPrefixOf . (<> acctsep)

isSubAccountNameOf :: AccountName -> AccountName -> Bool
s `isSubAccountNameOf` p =
  (p `isAccountNamePrefixOf` s) && (accountNameLevel s == (accountNameLevel p + 1))

-- | From a list of account names, select those which are direct
-- subaccounts of the given account name.
subAccountNamesFrom :: [AccountName] -> AccountName -> [AccountName]
subAccountNamesFrom accts a = filter (`isSubAccountNameOf` a) accts

-- | Convert a list of account names to a tree, efficiently.
accountNameTreeFrom :: [AccountName] -> Tree AccountName
accountNameTreeFrom accts = unfoldTree grow ("root", expandAccountNames accts)
  where
    -- unfoldTree :: (b -> (a, [b])) -> b -> Tree a
    -- grow :: (b -> (a, [b]))
    -- a = AccountName                  - the label at each node of the tree
    -- b = (AccountName, [AccountName]) - the next node's account, and the accounts remaining to consume under it
    grow :: ((AccountName, [AccountName]) -> (AccountName, [(AccountName, [AccountName])]))
    grow (a,[])   = (a,[])
    grow (a,rest) = (a, [(s, filter (s `isAccountNamePrefixOf`) deepersubs) | s <- asubs])
      where
        (asubs, deepersubs) = partition (isChildOf a) rest
        isChildOf "root" = (1==) . accountNameLevel
        isChildOf acct   = (`isSubAccountNameOf` acct)

-- | Elide an account name to fit in the specified width.
-- From the ledger 2.6 news:
--
-- @
--   What Ledger now does is that if an account name is too long, it will
--   start abbreviating the first parts of the account name down to two
--   letters in length.  If this results in a string that is still too
--   long, the front will be elided -- not the end.  For example:
--
--     Expenses:Cash           ; OK, not too long
--     Ex:Wednesday:Cash       ; "Expenses" was abbreviated to fit
--     Ex:We:Afternoon:Cash    ; "Expenses" and "Wednesday" abbreviated
--     ; Expenses:Wednesday:Afternoon:Lunch:Snack:Candy:Chocolate:Cash
--     ..:Af:Lu:Sn:Ca:Ch:Cash  ; Abbreviated and elided!
-- @
elideAccountName :: Int -> AccountName -> AccountName
elideAccountName width s
  -- XXX special case for transactions register's multi-account pseudo-names
  | " (split)" `T.isSuffixOf` s =
    let
      names = T.splitOn ", " $ T.take (T.length s - 8) s
      widthpername = max 0 (width - 8 - 2 * (max 1 (length names) - 1)) `div` length names
    in
     fitText Nothing (Just width) True False $
     (<>" (split)") $
     T.intercalate ", "
     [accountNameFromComponents $ elideparts widthpername [] $ accountNameComponents s' | s' <- names]
  | otherwise =
    fitText Nothing (Just width) True False $ accountNameFromComponents $ elideparts width [] $ accountNameComponents s
      where
        elideparts :: Int -> [Text] -> [Text] -> [Text]
        elideparts w done ss
          | realLength (accountNameFromComponents $ done++ss) <= w = done++ss
          | length ss > 1 = elideparts w (done++[textTakeWidth 2 $ headErr ss]) (tailErr ss)  -- PARTIAL headErr, tailErr will succeed because length > 1
          | otherwise = done++ss

-- | Keep only the first n components of an account name, where n
-- is a positive integer.
clipAccountNameTo :: Int -> AccountName -> AccountName
clipAccountNameTo n = accountNameFromComponents . take n . accountNameComponents

-- | Calculate the depth to which an account name should be clipped for a given
-- 'DepthSpec'.
--
-- First checking whether the account name matches any of the regular
-- expressions controlling depth. If so, clip to the depth of the most specific
-- of those matches, i.e. the one which starts matching the latest as you
-- progress up the parents of the account. Otherwise clip to the flat depth
-- provided, or return the full name if Nothing.
getAccountNameClippedDepth :: DepthSpec -> AccountName -> Maybe Int
getAccountNameClippedDepth (DepthSpec flat regexps) acctName =
    mostSpecificRegexp regexps <|> flat
  where
    -- If any regular expressions match, choose the one with the greatest
    -- specificity and clip to that depth.
    mostSpecificRegexp = fmap snd . foldr takeMax Nothing . mapMaybe matchRegexp
      where
        -- If two regexps match, take the most specific one. If there is a tie,
        -- take the last one (this aligns with the behaviour for flat depths
        -- limiting).
        takeMax (s, d) (Just (s', d')) = Just $ if s'>= s then (s', d') else (s, d)
        takeMax (s, d) Nothing = Just (s, d)

    -- If the regular expression matches the account name, store the specificity and requested depth
    matchRegexp :: (Regexp, Int) -> Maybe (Int, Int)
    matchRegexp (r, d) = if regexMatchText r acctName then Just (getSpecificity r, d) else Nothing
    -- Specificity is the smallest parent of the account which matches the regular expression
    getSpecificity r = maybe maxBound fst $ find (regexMatchText r . snd) acctParents
    acctParents = zip [1..] . initDef [] $ expandAccountName acctName

-- | Clip an account name to a given 'DepthSpec', first checking whether it
-- matches any of the regular expressions controlling depth. If so, clip to the
-- depth of the most specific of those matches, i.e. the one which starts
-- matching the latest as you progress up the parents of the account. Otherwise
-- clip to the flat depth provided, or return the full name if Nothing.
clipAccountName :: DepthSpec -> AccountName -> AccountName
clipAccountName ds a = maybe id clipAccountNameTo (getAccountNameClippedDepth ds a) a

-- | As 'clipAccountName', but return '...' if asked to clip to depth 0.
clipOrEllipsifyAccountName :: DepthSpec -> AccountName -> AccountName
clipOrEllipsifyAccountName ds a = go (getAccountNameClippedDepth ds a)
  where
    go Nothing  = a
    go (Just 0) = "..."
    go (Just n) = clipAccountNameTo n a

-- | Escape an AccountName for use within a regular expression.
-- >>> putStr . T.unpack $ escapeName "First?!#$*?$(*) !@^#*? %)*!@#"
-- First\?!#\$\*\?\$\(\*\) !@\^#\*\? %\)\*!@#
-- >>> putStr . T.unpack $ escapeName "assets:broker:{2026-01-01, $50}"
-- assets:broker:\{2026-01-01, \$50\}
escapeName :: AccountName -> Text
escapeName = T.concatMap escapeChar
  where
    escapeChar c = if c `elem` escapedChars then T.snoc "\\" c else T.singleton c
    escapedChars = ['[', ']', '?', '+', '|', '(', ')', '*', '$', '^', '\\', '{', '}', '.']

-- | Convert an account name to a regular expression matching it and its subaccounts.
accountNameToAccountRegex :: AccountName -> Regexp
accountNameToAccountRegex a = toRegex' $ "^" <> escapeName a <> "(:|$)"  -- PARTIAL: Is this safe after escapeName?

-- | Convert an account name to a regular expression matching it and its subaccounts,
-- case insensitively.
accountNameToAccountRegexCI :: AccountName -> Regexp
accountNameToAccountRegexCI a = toRegexCI' $ "^" <> escapeName a <> "(:|$)"  -- PARTIAL: Is this safe after escapeName?

-- | Convert an account name to a regular expression matching it but not its subaccounts.
accountNameToAccountOnlyRegex :: AccountName -> Regexp
accountNameToAccountOnlyRegex a = toRegex' $ "^" <> escapeName a <> "$" -- PARTIAL: Is this safe after escapeName?

-- | Convert an account name to a regular expression matching it but not its subaccounts,
-- case insensitively.
accountNameToAccountOnlyRegexCI :: AccountName -> Regexp
accountNameToAccountOnlyRegexCI a = toRegexCI' $ "^" <> escapeName a <> "$" -- PARTIAL: Is this safe after escapeName?

-- -- | Does this string look like an exact account-matching regular expression ?
--isAccountRegex  :: String -> Bool
--isAccountRegex s = take 1 s == "^" && take 5 (reverse s) == ")$|:("

tests_AccountName = testGroup "AccountName" [
   testCase "accountNameTreeFrom" $ do
    accountNameTreeFrom ["a"]       @?= Node "root" [Node "a" []]
    accountNameTreeFrom ["a","b"]   @?= Node "root" [Node "a" [], Node "b" []]
    accountNameTreeFrom ["a","a:b"] @?= Node "root" [Node "a" [Node "a:b" []]]
    accountNameTreeFrom ["a:b:c"]   @?= Node "root" [Node "a" [Node "a:b" [Node "a:b:c" []]]]
  ,testCase "expandAccountNames" $ do
    expandAccountNames ["assets:cash","assets:checking","expenses:vacation"] @?=
     ["assets","assets:cash","assets:checking","expenses","expenses:vacation"]
  ,testCase "isAccountNamePrefixOf" $ do
    "assets" `isAccountNamePrefixOf` "assets" @?= False
    "assets" `isAccountNamePrefixOf` "assets:bank" @?= True
    "assets" `isAccountNamePrefixOf` "assets:bank:checking" @?= True
    "my assets" `isAccountNamePrefixOf` "assets:bank" @?= False
  ,testCase "isSubAccountNameOf" $ do
    "assets" `isSubAccountNameOf` "assets" @?= False
    "assets:bank" `isSubAccountNameOf` "assets" @?= True
    "assets:bank:checking" `isSubAccountNameOf` "assets" @?= False
    "assets:bank" `isSubAccountNameOf` "my assets" @?= False
  ,testCase "accountNameInferType" $ do
    accountNameInferType "assets"            @?= Just Asset
    accountNameInferType "assets:cash"       @?= Just Cash
    accountNameInferType "assets:A/R"        @?= Just Asset
    accountNameInferType "liabilities"       @?= Just Liability
    accountNameInferType "equity"            @?= Just Equity
    accountNameInferType "equity:conversion" @?= Just Conversion
    accountNameInferType "expenses"          @?= Just Expense
    accountNameInferType "revenues"          @?= Just Revenue
    accountNameInferType "revenue"           @?= Just Revenue
    accountNameInferType "income"            @?= Just Revenue
    accountNameInferType "income:gains"          @?= Just Gain
    accountNameInferType "revenue:gain"          @?= Just Gain
    accountNameInferType "revenues:capital-gains" @?= Just Gain
    accountNameInferType "income:capitalgain"    @?= Just Gain
    accountNameInferType "income:losses"         @?= Just Gain
    accountNameInferType "revenue:capital-loss"  @?= Just Gain
    accountNameInferType "income:gains:realized" @?= Just Gain
    accountNameInferType "equity:unrealised-gain"  @?= Just UnrealisedGain
    accountNameInferType "equity:unrealized gains" @?= Just UnrealisedGain
    accountNameInferType "equity:unrealisedfoo"    @?= Just Equity
  ,testCase "joinAccountNames" $ do
    joinAccountNames "assets" "cash"     @?= "assets:cash"
    joinAccountNames "assets:cash" "a"   @?= "assets:cash:a"
    joinAccountNames "assets" "(cash)"   @?= "(assets:cash)"
    joinAccountNames "assets" "[cash]"   @?= "[assets:cash]"
    joinAccountNames "(assets)" "cash"   @?= "(assets:cash)"
    joinAccountNames "" "assets"         @?= "assets"
    joinAccountNames "assets" ""         @?= "assets"
  ,testCase "concatAccountNames" $ do
    concatAccountNames ["assets", "cash"]   @?= "assets:cash"
    concatAccountNames ["assets:cash", "a"] @?= "assets:cash:a"
    concatAccountNames ["assets", "(cash)"] @?= "(assets:cash)"
    concatAccountNames ["assets", "[cash]"] @?= "[assets:cash]"
    concatAccountNames ["(assets)", "cash"] @?= "(assets:cash)"
    concatAccountNames ["", "assets"]       @?= ":assets"
    concatAccountNames ["assets", ""]       @?= "assets:"
 ]

