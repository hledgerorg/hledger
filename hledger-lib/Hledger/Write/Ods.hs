{- |
Export table data as OpenDocument Spreadsheet
<https://docs.oasis-open.org/office/OpenDocument/v1.3/>.
This format supports character encodings, fixed header rows and columns,
number formatting, text styles, merged cells, formulas, hyperlinks.
Currently we support Flat ODS, a plain uncompressed XML format.

This is derived from <https://hackage.haskell.org/package/classify-frog-0.2.4.3/src/src/Spreadsheet/Format.hs>

-}
module Hledger.Write.Ods (
    printFods,
    ) where

import Prelude hiding (Applicative(..))
import Control.Monad (guard)
import Control.Applicative (Applicative(..))

import Data.Text.Lazy qualified as TL
import Data.Text qualified as T
import Data.Text (Text)

import Data.Foldable qualified as Fold
import Data.List qualified as List
import Data.Map qualified as Map
import Data.Set qualified as Set
import Data.Foldable (fold)
import Data.Map (Map)
import Data.Set (Set)
import Data.Maybe (catMaybes)

import System.IO qualified as IO
import Text.Printf (printf)

import Hledger.Write.Spreadsheet qualified as Spr
import Hledger.Write.Spreadsheet (Type(..), Style(..), Emphasis(..), Cell(..))
import Hledger.Data.Types
        (Amount, CommoditySymbol, AmountPrecision(..), DigitGroupStyle(..),
         acommodity, aquantity, astyle, asprecision, asdigitgroups,
        )

printFods ::
    IO.TextEncoding ->
    Map Text ((Int, Int), [[Cell Spr.NumLines Text]]) -> TL.Text
printFods encoding tables =
    let fileOpen customStyles =
          map (map (\c -> case c of '\'' -> '"'; _ -> c)) $
          printf "<?xml version='1.0' encoding='%s'?>" (show encoding) :
          "<office:document" :
          "  office:mimetype='application/vnd.oasis.opendocument.spreadsheet'" :
          "  office:version='1.3'" :
          "  xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance'" :
          "  xmlns:xsd='http://www.w3.org/2001/XMLSchema'" :
          "  xmlns:text='urn:oasis:names:tc:opendocument:xmlns:text:1.0'" :
          "  xmlns:style='urn:oasis:names:tc:opendocument:xmlns:style:1.0'" :
          "  xmlns:meta='urn:oasis:names:tc:opendocument:xmlns:meta:1.0'" :
          "  xmlns:config='urn:oasis:names:tc:opendocument:xmlns:config:1.0'" :
          "  xmlns:xlink='http://www.w3.org/1999/xlink'" :
          "  xmlns:fo='urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0'" :
          "  xmlns:ooo='http://openoffice.org/2004/office'" :
          "  xmlns:office='urn:oasis:names:tc:opendocument:xmlns:office:1.0'" :
          "  xmlns:table='urn:oasis:names:tc:opendocument:xmlns:table:1.0'" :
          "  xmlns:number='urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0'" :
          "  xmlns:of='urn:oasis:names:tc:opendocument:xmlns:of:1.2'" :
          "  xmlns:field='urn:openoffice:names:experimental:ooo-ms-interop:xmlns:field:1.0'" :
          "  xmlns:form='urn:oasis:names:tc:opendocument:xmlns:form:1.0'>" :
          "<office:styles>" :
          "  <number:date-style style:name='iso-date'>" :
          "    <number:year number:style='long'/>" :
          "    <number:text>-</number:text>" :
          "    <number:month number:style='long'/>" :
          "    <number:text>-</number:text>" :
          "    <number:day number:style='long'/>" :
          "  </number:date-style>" :
          "  <number:number-style style:name='integer'>" :
          "    <number:number number:min-integer-digits='1'/>" :
          "  </number:number-style>" :
          customStyles ++
          "</office:styles>" :
          []

        fileClose =
          "</office:document>" :
          []

        tableConfig tableNames =
          " <office:settings>" :
          "  <config:config-item-set config:name='ooo:view-settings'>" :
          "   <config:config-item-map-indexed config:name='Views'>" :
          "    <config:config-item-map-entry>" :
          "     <config:config-item-map-named config:name='Tables'>" :
          (fold $
           flip Map.mapWithKey tableNames $ \tableName (topRow,leftColumn) ->
             printf "      <config:config-item-map-entry config:name='%s'>" tableName :
             ((guard (leftColumn>0) >>) $
                "       <config:config-item config:name='HorizontalSplitMode' config:type='short'>2</config:config-item>" :
                printf "       <config:config-item config:name='HorizontalSplitPosition' config:type='int'>%d</config:config-item>" leftColumn :
                printf "       <config:config-item config:name='PositionRight' config:type='int'>%d</config:config-item>" leftColumn :
                []) ++
             ((guard (topRow>0) >>) $
                "       <config:config-item config:name='VerticalSplitMode' config:type='short'>2</config:config-item>" :
                printf "       <config:config-item config:name='VerticalSplitPosition' config:type='int'>%d</config:config-item>" topRow :
                printf "       <config:config-item config:name='PositionBottom' config:type='int'>%d</config:config-item>" topRow :
                []) ++
             "      </config:config-item-map-entry>" :
             []) ++
          "     </config:config-item-map-named>" :
          "    </config:config-item-map-entry>" :
          "   </config:config-item-map-indexed>" :
          "  </config:config-item-set>" :
          " </office:settings>" :
          []

        tableOpen name =
          "<office:body>" :
          "<office:spreadsheet>" :
          printf "<table:table table:name='%s'>" name :
          []

        tableClose =
          "</table:table>" :
          "</office:spreadsheet>" :
          "</office:body>" :
          []

    in  TL.unlines $ map (TL.fromStrict . T.pack) $
        fileOpen
          (let styles = cellStyles (foldMap (concat.snd) tables) in
           (numberConfig =<< Set.toList (foldMap (numberParams.snd) styles))
           ++
           (cellConfig =<< Set.toList styles)) ++
        tableConfig (fmap fst tables) ++
        (Map.toAscList tables >>= \(name,(_,table)) ->
            tableOpen name ++
            (table >>= \row ->
                "<table:table-row>" :
                (row >>= formatCell) ++
                "</table:table-row>" :
                []) ++
            tableClose) ++
        fileClose


dataStyleFromType :: Type -> DataStyle
dataStyleFromType typ =
    case typ of
        TypeString -> DataString
        TypeInteger -> DataInteger
        TypeDate -> DataDate
        TypeAmount amt -> DataAmount $ commodityStyleFromAmount amt
        TypeMixedAmount -> DataMixedAmount

cellStyles ::
    (Ord border) =>
    [Cell border Text] ->
    Set ((Spr.Border border, Style), DataStyle)
cellStyles =
    Set.fromList .
    map (\cell ->
            ((cellBorder cell, cellStyle cell),
             dataStyleFromType $ cellType cell))

data CommodityStyle =
    CommodityStyle {
        commodityStyle :: CommoditySymbol,
        commodityPrecision :: AmountPrecision,
        commodityGrouping :: Bool
    } deriving (Eq, Ord, Show)

commodityStyleFromAmount :: Amount -> CommodityStyle
commodityStyleFromAmount amt =
    CommodityStyle
        (acommodity amt)
        (asprecision $ astyle amt)
        (case asdigitgroups $ astyle amt of
            Just (DigitGroups _ (_:_)) -> True
            _ -> False)

numberStyleName :: CommodityStyle -> String
numberStyleName (CommodityStyle comm prec grp) =
    printf "%s-%s%s"
        comm
        (case prec of
            NaturalPrecision -> "natural"
            Precision k -> show k)
        (if grp then "-grouping" else "")

numberParams :: DataStyle -> Set CommodityStyle
numberParams (DataAmount commStyle) = Set.singleton commStyle
numberParams _ = Set.empty

numberConfig :: CommodityStyle -> [String]
numberConfig commStyle@(CommodityStyle comm prec grp) =
    let precStr =
            case prec of
                NaturalPrecision -> ""
                Precision k -> printf " number:decimal-places='%d'" k
        grpStr =
            if grp
                then " number:grouping='true'"
                else ""
        name = numberStyleName commStyle
    in
    printf "  <number:number-style style:name='number-%s'>" name :
    printf "    <number:number number:min-integer-digits='1'%s%s/>"
                        precStr grpStr :
    printf "    <number:text>%s%s</number:text>"
      (if T.null comm then "" else " ") comm :
    "  </number:number-style>" :
    []

emphasisName :: Emphasis -> String
emphasisName emph =
    case emph of
        Item -> "item"
        Total -> "total"

cellStyleName :: Style -> String
cellStyleName style =
    case style of
        Head -> "head"
        Body emph -> emphasisName emph

linesName :: Spr.NumLines -> Maybe String
linesName prop =
    case prop of
        Spr.NoLine -> Nothing
        Spr.SingleLine -> Just "single"
        Spr.DoubleLine -> Just "double"

linesStyle :: Spr.NumLines -> String
linesStyle prop =
    case prop of
        Spr.NoLine -> "none"
        Spr.SingleLine -> "1.5pt solid #000000"
        Spr.DoubleLine -> "1.5pt double-thin #000000"

borderLabels :: Spr.Border String
borderLabels = Spr.Border "left" "right" "top" "bottom"

borderName :: Spr.Border Spr.NumLines -> String
borderName border =
    (\bs ->
        case bs of
            [] -> "noborder"
            _ ->
                ("border="++) $ List.intercalate "," $
                map (\(name,num) -> name ++ ':' : num) bs) $
    catMaybes $ Fold.toList $
    liftA2
        (\name numLines -> (,) name <$> linesName numLines)
        borderLabels
        border

borderStyle :: Spr.Border Spr.NumLines -> [String]
borderStyle border =
    if border == Spr.noBorder
        then []
        else (:[]) $
            printf "    <style:table-cell-properties%s/>" $
            (id :: String -> String) $ fold $
            liftA2 (printf " fo:border-%s='%s'") borderLabels $
            fmap linesStyle border

data DataStyle =
      DataString
    | DataInteger
    | DataDate
    | DataAmount CommodityStyle
    | DataMixedAmount
    deriving (Eq, Ord, Show)

cellConfig :: ((Spr.Border Spr.NumLines, Style), DataStyle) -> [String]
cellConfig ((border, cstyle), dataStyle) =
    let boldStyle = "    <style:text-properties fo:font-weight='bold'/>"
        alignTop =
            "    <style:table-cell-properties style:vertical-align='top'/>"
        alignParagraph =
            printf "    <style:paragraph-properties fo:text-align='%s'/>"
        moreStyles =
            borderStyle border
            ++
            (
            case cstyle of
                Body Item ->
                    alignTop :
                    []
                Body Total ->
                    alignTop :
                    boldStyle :
                    []
                Head ->
                    alignParagraph "center" :
                    boldStyle :
                    []
            )
            ++
            (
            case dataStyle of
                DataMixedAmount -> [alignParagraph "end"]
                _ -> []
            )
        style :: String
        style =
            let (styleName,dataStyleName) = styleNames cstyle border dataStyle
            in  printf "style:name='%s'" styleName
                ++
                foldMap (printf " style:data-style-name='%s'") dataStyleName
    in
    case moreStyles of
        [] ->
            printf "  <style:style style:family='table-cell' %s/>" style :
            []
        _ ->
            printf "  <style:style style:family='table-cell' %s>" style :
            moreStyles ++
            "  </style:style>" :
            []


formatCell :: Cell Spr.NumLines Text -> [String]
formatCell cell =
    let style, valueType :: String
        style =
            printf " table:style-name='%s'" $ fst $
            styleNames
                (cellStyle cell)
                (cellBorder cell)
                (dataStyleFromType $ cellType cell)

        valueType =
            case cellType cell of
                TypeInteger ->
                    printf
                        "office:value-type='float' office:value='%s'"
                        (cellContent cell)
                TypeAmount amt ->
                    printf
                        "office:value-type='float' office:value='%s'"
                        (show $ aquantity amt)
                TypeDate ->
                    printf
                        "office:value-type='date' office:date-value='%s'"
                        (cellContent cell)
                _ -> "office:value-type='string'"

        covered =
            case cellSpan cell of
                Spr.Covered -> "covered-"
                _ -> ""

        span_ =
            case cellSpan cell of
                Spr.SpanHorizontal n | n>1 ->
                    printf " table:number-columns-spanned='%d'" n
                Spr.SpanVertical n | n>1 ->
                    printf " table:number-rows-spanned='%d'" n
                _ -> ""

        anchor text =
            if T.null $ Spr.cellAnchor cell
                then text
                else printf "<text:a xlink:href='%s'>%s</text:a>"
                        (escape $ T.unpack $ Spr.cellAnchor cell) text

    in
    printf "<table:%stable-cell%s%s %s>" covered style span_ valueType :
    printf "<text:p>%s</text:p>"
        (anchor $ escape $ T.unpack $ cellContent cell) :
    printf "</table:%stable-cell>" covered :
    []

styleNames ::
    Style -> Spr.Border Spr.NumLines -> DataStyle -> (String, Maybe String)
styleNames cstyle border dataStyle =
    let cstyleName = cellStyleName cstyle in
    let bordName = borderName border in
    case dataStyle of
        DataDate ->
            (printf "%s-%s-date" cstyleName bordName, Just "iso-date")
        DataInteger ->
            (printf "%s-%s-integer" cstyleName bordName, Just "integer")
        DataAmount commStyle ->
            let name = numberStyleName commStyle in
            (printf "%s-%s-%s" cstyleName bordName name,
                Just $ printf "number-%s" name)
        DataMixedAmount ->
            (printf "%s-%s-mixedamount" cstyleName bordName, Nothing)
        DataString -> (printf "%s-%s" cstyleName bordName, Nothing)

escape :: String -> String
escape =
    concatMap $ \c ->
        case c of
            '\n' -> "&#10;"
            '&' -> "&amp;"
            '<' -> "&lt;"
            '>' -> "&gt;"
            '"' -> "&quot;"
            '\'' -> "&apos;"
            _ -> [c]
