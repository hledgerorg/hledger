{- | Editor integration. -}

module Hledger.UI.Editor (
   -- TextPosition
   endPosition
  ,runEditor
  ,runIadd
  )
where

import Control.Applicative ((<|>))
import Data.List (intercalate)
import Data.Maybe (catMaybes)
import Data.Bifunctor (bimap)
import Safe
import System.Environment
import System.Exit
import System.FilePath
import System.Info (os)
import System.Process

import Hledger

-- | A position we can move to in a text editor: a line and optional column number.
-- Line number 1 or 0 means the first line. A negative line number means the last line.
type TextPosition = (Int, Maybe Int)

-- | The text position meaning "last line, first column".
endPosition :: Maybe TextPosition
endPosition = Just (-1, Nothing)

-- | Run the hledger-iadd executable on the given file, blocking until it exits,
-- and return the exit code; or raise an error.
-- hledger-iadd is an alternative to the built-in add command.
runIadd :: FilePath -> IO ExitCode
runIadd "-" = return ExitSuccess  -- journal was read from stdin; there is no file to add to
runIadd f = runCommand ("hledger-iadd -f " ++ shellQuoteIfNeeded f) >>= waitForProcess

-- | Run the user's preferred text editor (or try a default editor),
-- on the given file, blocking until it exits, and return the exit
-- code; or raise an error. If a text position is provided, the editor
-- will be focussed at that position in the file, if we know how.
runEditor :: Maybe TextPosition -> FilePath -> IO ExitCode
runEditor _ "-" = return ExitSuccess  -- journal was read from stdin; there is no file to edit
runEditor mpos f = editFileAtPositionCommand mpos f >>= runCommand >>= waitForProcess

-- | Get a shell command line to open the user's preferred text editor
-- (or a default editor) on the given file, and to focus it at the
-- given text position if one is provided and if we know how.
--
-- Just ('-' : _, _) is any text position with a negative line number.
-- A text position with a negative line number means the last line.
--
-- Some tests:
-- @
-- EDITOR program:  Maybe TextPosition    Command should be:
-- ---------------  --------------------- ------------------------------------
-- emacs            Just (line, Just col) emacs +LINE:COL FILE
--                  Just (line, Nothing)  emacs +LINE     FILE
--                  Just ('-' : _, _)     emacs FILE -f end-of-buffer
--                  Nothing               emacs           FILE
--
-- emacsclient      Just (line, Just col) emacsclient +LINE:COL FILE
--                  Just (line, Nothing)  emacsclient +LINE     FILE
--                  Just ('-' : _, _)     emacsclient           FILE
--                  Nothing               emacsclient           FILE
--
-- nano             Just (line, Just col) nano +LINE:COL FILE
--                  Just (line, Nothing)  nano +LINE     FILE
--                  Just ('-' : _, _)     nano           FILE
--                  Nothing               nano           FILE
--
-- vscode           Just (line, Just col) vscode --goto FILE:LINE:COL
--                  Just (line, Nothing)  vscode --goto FILE:LINE
--                  Just ('-' : _, _)     vscode        FILE
--                  Nothing               vscode        FILE
--
-- kak              Just (line, Just col) kak +LINE:COL FILE
--                  Just (line, Nothing)  kak +LINE     FILE
--                  Just ('-' : _, _)     kak +:        FILE
--                  Nothing               kak           FILE
--
-- vi & variants    Just (line, _)        vi +LINE FILE
--                  Just ('-' : _, _)     vi +     FILE
--                  Nothing               vi       FILE
-- 
-- zed & sublime    Just (line, Just col) zed FILE:LINE:COL
--                  Just (line, Nothing)  zed FILE:LINE
--                  Just ('-' : _, _)     zed FILE
--                  Nothing               zed FILE
--
-- (other PROG)     _                     PROG FILE
--
-- (not set)        Just (line, Just col) emacsclient -a '' -nw +LINE:COL FILE
--                  Just (line, Nothing)  emacsclient -a '' -nw +LINE     FILE
--                  Just ('-' : _, _)     emacsclient -a '' -nw           FILE
--                  Nothing               emacsclient -a '' -nw           FILE
-- @
--
editFileAtPositionCommand :: Maybe TextPosition -> FilePath -> IO String
editFileAtPositionCommand mpos f = do
  cmd <- getEditCommand
  let editor = lowercase $ takeBaseName $ headDef "" $ words' cmd
      f' = shellQuoteIfNeeded f
      mpos' = Just . bimap show (fmap show) =<< mpos
      join sep = intercalate sep . catMaybes
      args = case editor of
        "emacs" -> case mpos' of
          Nothing -> [f']
          Just ('-' : _, _) -> [f', "-f", "end-of-buffer"]
          Just (l, mc) -> ['+' : join ":" [Just l, mc], f']
        e | e `elem` ["emacsclient", "nano"] -> case mpos' of
          Nothing -> [f']
          Just ('-' : _, _) -> [f']
          Just (l, mc) -> ['+' : join ":" [Just l, mc], f']
        "vscode" -> case mpos' of
          Nothing -> [f']
          Just ('-' : _, _) -> [f']
          Just (l, mc) -> ["--goto", join ":" [Just f', Just l, mc]]
        "kak" -> case mpos' of
          Nothing -> [f']
          Just ('-' : _, _) -> ["+:", f']
          Just (l, mc) -> ['+' : join ":" [Just l, mc], f']
        e | e `elem` ["vi",  "vim", "view", "nvim", "evim", "eview",
                      "gvim", "gview", "rvim", "rview",
                      "rgvim", "rgview", "ex"] -> case mpos' of
          Nothing -> [f']
          Just ('-' : _, _) -> ["+", f']
          Just (l, _) -> ['+' : l, f']
        -- arch linux creates a symlink to /usr/lib/helix/hx at /usr/bin/helix
        e | e `elem` ["hx", "helix"] -> case mpos' of
          Nothing -> [f']
          Just ('-' : _, _) -> [f']
          Just (l, _) -> ['+' : l, f']
        e | e `elem` ["zed", "subl"] -> case mpos' of
          Nothing -> [f']
          Just ('-' : _, _) -> [f']
          Just (l, mc) -> [join ":" [Just f', Just l, mc]]
        _ -> [f']
  return $ unwords $ cmd:args

-- | Get the user's preferred edit command. This is the value of the
-- $HLEDGER_UI_EDITOR environment variable, or of $EDITOR, or an OS-specific default.
--
-- For non-windows machines that would be "emacsclient -a '' -nw",
-- which starts/connects to an emacs daemon in terminal mode.
--
-- For windows the default is a plain "notepad.exe"
getEditCommand :: IO String
getEditCommand = do
  hledger_ui_editor_env <- lookupEnv "HLEDGER_UI_EDITOR"
  editor_env            <- lookupEnv "EDITOR"
  let defaultEditor = Just $ if os == "mingw32" then "notepad.exe" else "emacsclient -a '' -nw"
  let Just cmd = hledger_ui_editor_env <|> editor_env <|> defaultEditor
  return cmd
