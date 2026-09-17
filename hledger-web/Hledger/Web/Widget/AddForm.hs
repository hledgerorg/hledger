{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Web.Widget.AddForm
  ( addForm
  , addModal
  ) where

import Control.Monad.State.Strict (evalStateT)
import Data.Bifunctor (first)
import Data.Foldable (toList)
import Data.List (dropWhileEnd, unfoldr)
import Data.Maybe (isJust, fromMaybe)
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (Day)
import Text.Blaze.Internal (Markup)
import Text.Megaparsec (bundleErrors, eof, parseErrorTextPretty, runParser)
import Yesod

import Hledger.Utils.I18n (Translations, substitutePlaceholders, tr, trc, trf)
import Hledger
import Hledger.Web.App (App, Handler, Widget, HMsg(..), requestTranslations)
import Hledger.Web.Settings (widgetFile)
import Data.Function ((&))
import Control.Arrow (right)

addModal :: Route App -> Journal -> Day -> Widget
addModal addR j today = do
  (addView, addEnctype) <- handlerToWidget $ generateFormPost (addForm j today)
  [whamlet|
<dialog #addmodal aria-labelledby="addLabel">
  <div .modal-header>
    <button type="button" .close data-dismiss="modal" aria-label=_{HMsg "Close"}>&times;
    <h3 .modal-title #addLabel>_{HMsg "Add a transaction"}
  <div .modal-body>
    <form#addform.form action=@{addR} method=POST enctype=#{addEnctype}>
      ^{addView}
|]

addForm :: Journal -> Day -> Markup -> MForm Handler (FormResult (Transaction,FilePath), Widget)
addForm j today = identifyForm "add" $ \extra -> do
  trs <- lift requestTranslations
  let  -- bindings used in add-form.hamlet
    descriptions = foldMap S.fromList [journalPayeesDeclaredOrUsed j, journalDescriptions j]
    files = fst <$> jfiles j
    deffile = journalFilePath j
    accountPlaceholder = tr trs "Account {n}"
    amountPlaceholder = tr trs "Amount {n}"
    numbered template n = substitutePlaceholders [("n", T.pack (show n))] template
    -- custom fields
    dateField = textField & checkMMap (pure . right fromEFDay . validateDate) (T.pack . show)
      where
        validateDate s =
          first (const (tr trs "Invalid date format")) $
          fixSmartDateStrEither' today (T.strip s)
    dateSettings = FieldSettings "date" Nothing Nothing (Just "date") [("class", "form-control input-lg"), ("placeholder", trc trs "placeholder" "Date")]
    descSettings = FieldSettings "desc" Nothing Nothing (Just "description") [("class", "form-control input-lg"), ("placeholder", trc trs "placeholder" "Description"), ("size", "40"), ("list", "descriptionnames")]
  (dateRes, dateView) <- mreq dateField dateSettings Nothing
  (descRes, descView) <- mopt textField descSettings Nothing
  (acctsRes, _)       <- mreq listField acctSettings Nothing
  (amtsRes, _)        <- mreq listField amtSettings  Nothing
  (fileRes, fileView) <- mopt fileField' fileSettings Nothing
  let
    (postingsRes, displayRows) = validatePostings trs acctsRes amtsRes
    formRes = validateTransaction deffile dateRes descRes postingsRes fileRes
  return (formRes, $(widgetFile "add-form"))
  where
    listField = Field
      { fieldParse = const . pure . Right . Just . dropWhileEnd T.null
      , fieldView = error' "listField should not be used for rendering"  -- PARTIAL:
      , fieldEnctype = UrlEncoded
      }
    fileField' :: Field Handler FilePath
    fileField' = selectFieldList [(T.pack f, f) | f <- fs] & check validateFilepath
      where
        fs = journalFilePaths j
        validateFilepath :: FilePath -> Either FormMessage FilePath
        validateFilepath f
          | f `elem` fs = Right f
          | otherwise = Left $ MsgInputNotFound $ T.pack f
    -- field settings
    acctSettings = FieldSettings "account" Nothing Nothing (Just "account") []
    amtSettings  = FieldSettings "amount" Nothing Nothing (Just "amount") []
    fileSettings = FieldSettings "file" Nothing Nothing (Just "file") [("class", "form-control input-lg")]

validateTransaction ::
     FilePath -> FormResult Day -> FormResult (Maybe Text) -> FormResult [Posting] -> FormResult (Maybe FilePath)
  -> FormResult (Transaction, FilePath)
validateTransaction deffile dateRes descRes postingsRes fileRes =
  case makeTransaction <$> dateRes <*> descRes <*> postingsRes <*> fileRes of
    FormSuccess (txn,f) -> case balanceSingleTransaction defbalancingopts txn of
      Left e     -> FormFailure [T.pack e]
      Right txn' -> FormSuccess (txn',f)
    x -> x
  where
    makeTransaction date mdesc postings mfile =
      (nulltransaction {
         tdate = date
        ,tdescription = fromMaybe "" mdesc
        ,tpostings = postings
        ,tsourcepos = (initialPos f, initialPos f)
        }, f)
      where f = fromMaybe deffile mfile

-- | Parse a list of postings out of a list of accounts and a corresponding list
-- of amounts
validatePostings ::
     Translations -> FormResult [Text] -> FormResult [Text]
  -> (FormResult [Posting], [(Int, (Text, Text, Maybe Text, Maybe Text))])
validatePostings trs acctsRes amtsRes = let
  missingamount = tr trs "Missing amount"
  missingaccount = tr trs "Missing account"

  -- Zip accounts and amounts, fill in missing values and drop empty rows.
  rows :: [(Text, Text)]
  rows = filter (/= ("", "")) $ zipDefault "" (formSuccess [] acctsRes) (formSuccess [] amtsRes)

  -- Parse values and check for incomplete rows with only an account or an amount.
  -- The boolean in unfoldr state is for special handling of 'missingamt', where
  -- one row may have only an account and not an amount.
  postings :: [(Text, Text, Either (Maybe Text, Maybe Text) Posting)]
  postings = unfoldr go (True, rows)
    where
      go (True, (x, ""):y:xs) = Just ((x, "", zipRow (checkAccount x) (Left missingamount)), (True, y:xs))
      go (True, (x, ""):xs) = Just ((x, "", zipRow (checkAccount x) (Right missingamt)), (False, xs))
      go (False, (x, ""):xs) = Just ((x, "", zipRow (checkAccount x) (Left missingamount)), (False, xs))
      go (_, ("", y):xs) = Just (("", y, zipRow (Left missingaccount) (checkAmount y)), (False, xs))
      go (_, (x, y):xs) = Just ((x, y, zipRow (checkAccount x) (checkAmount y)), (True, xs))
      go (_, []) = Nothing

  zipRow (Left e) (Left e') = Left (Just e, Just e')
  zipRow (Left e) (Right _) = Left (Just e, Nothing)
  zipRow (Right _) (Left e) = Left (Nothing, Just e)
  zipRow (Right acct') (Right amt) = Right (nullposting {paccount = acct, preal = atype, pamount = mixedAmount amt})
    where
      acct = accountNameWithoutPostingType acct'
      atype = accountNamePostingType acct'

  -- The parser's own message stays in English, inside a translated frame.
  -- (The signature keeps this polymorphic under MonoLocalBinds, since it mentions trs.)
  errorToFormMsg :: Either HledgerParseErrors a -> Either Text a
  errorToFormMsg = first ((\e -> trf trs "Invalid value: {error}" [("error", e)]) . T.pack .
                          foldl (\s a -> s <> parseErrorTextPretty a) "" .
                          bundleErrors)
  checkAccount = errorToFormMsg . runParser (accountnamep <* eof) "" . T.strip
  checkAmount = errorToFormMsg . runParser (evalStateT (amountp <* eof) nulljournal) "" . T.strip

  -- Add errors to forms with zero rows if the form is not a FormMissing
  result :: [(Text, Text, Either (Maybe Text, Maybe Text) Posting)]
  result = case (acctsRes, amtsRes) of
    (FormMissing, FormMissing) -> postings
    _ -> case postings of
      [] -> [ ("", "", Left (Just missingaccount, Just missingamount))
           , ("", "", Left (Just missingaccount, Nothing))
           ]
      xs -> xs

  -- Prepare rows for rendering - resolve Eithers into error messages and pad to
  -- at least four rows
  display' = flip fmap result $ \(acc, amt, res) -> case res of
    Left (mAccountErr, mAmountErr) -> (acc, amt, mAccountErr, mAmountErr)
    Right _ -> (acc, amt, Nothing, Nothing)
  display = display' ++ replicate (4 - length display') ("", "", Nothing, Nothing)

  -- And finally prepare the final FormResult [Posting]
  formResult = case traverse (\(_, _, x) -> x) result of
    Left _ -> FormFailure [tr trs "Postings validation failed"]
    Right xs -> FormSuccess xs

  in (formResult, zip [(1 :: Int)..] display)

zipDefault :: a -> [a] -> [a] -> [(a, a)]
zipDefault def (b:bs) (c:cs) = (b, c):(zipDefault def bs cs)
zipDefault def (b:bs) [] = (b, def):(zipDefault def bs [])
zipDefault def [] (c:cs) = (def, c):(zipDefault def [] cs)
zipDefault _ _ _ = []

formSuccess :: a -> FormResult a -> a
formSuccess def res = case res of
  FormSuccess x -> x
  _ -> def
