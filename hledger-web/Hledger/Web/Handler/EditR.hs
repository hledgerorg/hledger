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
import Hledger.Cli.CliOptions (CliOpts(..))
import Hledger.Web.Import
import Hledger.Web.WebOptions (WebOpts(..))
import System.FilePath (takeFileName)
import Hledger.Web.Widget.Common
       (commitChanges, fromFormSuccess, helplink, journalFile404, writeJournalTextIfValidAndChanged)

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
  VD {j, trs, opts} <- getViewData
  require EditPermission

  (f', txt) <- journalFile404 f j
  ((res, view), enctype) <- runFormPost (editForm trs f' txt)
  newtxt <- fromFormSuccess (showForm view enctype) res
  runExceptT (writeJournalTextIfValidAndChanged f newtxt) >>= \case
    Left e -> do
      setMessage $ toHtml $ trf trs "Failed to load journal: {error}" [("error", T.pack e)]
      showForm view enctype
    Right () -> do
      merr <- liftIO $ commitChanges (rawopts_ $ cliopts_ opts) ("hledger-web edit: " <> takeFileName f) [f]
      setMessage $ toHtml $ maybe (trf trs "Saved journal {file}" [("file", T.pack f)] <> "\n") id merr
      redirect JournalR
  where
    showForm view enctype =
      sendResponse <=< defaultLayout $ do
        setTitleI (HMsg "Edit journal")
        [whamlet|<form method=post enctype=#{enctype}>^{view}|]
