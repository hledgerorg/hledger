{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Web.Handler.EditR
  ( getEditR
  , postEditR
  ) where

import Control.Monad.Except (runExceptT)
import Data.Text qualified as T
import Hledger.Utils.I18n (Translations, tr, trf)
import Hledger.Web.Import
import Hledger.Web.Widget.Common
       (fromFormSuccess, helplink, journalFile404, writeJournalTextIfValidAndChanged)

editForm :: Translations -> FilePath -> Text -> Form Text
editForm trs f txt =
  identifyForm "edit" $ \extra -> do
    (tRes, tView) <- mreq textareaField fs (Just (Textarea txt))
    pure (unTextarea <$> tRes, $(widgetFile "edit-form"))
  where
    fs = FieldSettings "text" mzero mzero mzero [("class", "form-control"), ("rows", "25")]

getEditR :: FilePath -> Handler ()
getEditR f = do
  checkServerSideUiEnabled
  postEditR f

postEditR :: FilePath -> Handler ()
postEditR f = do
  checkServerSideUiEnabled
  VD {j, trs} <- getViewData
  require EditPermission

  (f', txt) <- journalFile404 f j
  ((res, view), enctype) <- runFormPost (editForm trs f' txt)
  newtxt <- fromFormSuccess (showForm view enctype) res
  runExceptT (writeJournalTextIfValidAndChanged f newtxt) >>= \case
    Left e -> do
      setMessage $ toHtml $ trf trs "Failed to load journal: {error}" [("error", T.pack e)]
      showForm view enctype
    Right () -> do
      setMessage $ toHtml $ trf trs "Saved journal {file}" [("file", T.pack f)] <> "\n"
      redirect JournalR
  where
    showForm view enctype =
      sendResponse <=< defaultLayout $ do
        setTitleI (HMsg "Edit journal")
        [whamlet|<form method=post enctype=#{enctype}>^{view}|]
