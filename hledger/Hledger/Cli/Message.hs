{-|
List of all texts the CLI program can output in different languages
and related utilities.
-}

module Hledger.Cli.Message (
   Message(..)
  ,Noun(..)
  ,Interval(..)
  ,Genus
  ,getText
  ,getGenus
  ,getInflected
)
where

import Data.Default (Default(def))
import Data.ByteString.Char8 qualified as B
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Text.Encoding qualified as TE
-- import Text.Printf (printf)

import Data.Gettext (Catalog, gettext)


-- | List of all hledger text messages
data Message =
    None
  | Account
  | Revenues
  | Expenses
  | Assets
  | Liabilities
  | Equity
  | CashFlows
  | Net
  | Total
  | Average
  | RightTotal
  | RightAverage
  | Commodity
  | Balance
  | Budget
  | Noun Noun
  | Interval Interval
  deriving (Eq, Ord, Show)

instance Default Message where
  def = None

data Noun =
    BalanceSheet
  | BalanceSheetWithEquity
  | IncomeStatement
  | CashflowStatement
  deriving (Eq, Ord, Show, Enum, Bounded)

data Interval =
    Periodic
  | Days1
  | Weeks1
  | Weeks2
  | Months1
  | Months2
  | Months3
  | Months6
  | Years1
  | Years2
  deriving (Eq, Ord, Show, Enum, Bounded)


-- ToDo: We must ensure that a Catalog is always available, we must embed a standard catalog
getText :: Maybe Catalog -> Message -> Text
getText Nothing = T.pack . makeKey
getText (Just cat) = TL.toStrict . gettext cat . B.pack . makeKey

newtype Genus = Genus B.ByteString

getGenus :: Maybe Catalog -> Message -> Genus
getGenus (Just cat) (Noun noun) =
    Genus . TE.encodeUtf8 . TL.toStrict .
    gettext cat . B.pack $ (show noun ++ "_genus")
getGenus _cat _msg = Genus $ B.empty

getInflected :: Maybe Catalog -> Interval -> Genus -> Text
getInflected Nothing i _g = T.pack $ show i
getInflected (Just cat) i (Genus g) =
    TL.toStrict . gettext cat $ B.pack (show i) <> g

makeKey :: Message -> String
makeKey (Interval i) = show i
makeKey (Noun noun) = show noun
makeKey msg = show msg

