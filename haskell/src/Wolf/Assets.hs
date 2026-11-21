-- | Shareware map loading, separated from gameplay translation. The byte
-- decoders are pure and bounded: malformed files produce Left, never unchecked
-- array reads or an unbounded decompression allocation.
module Wolf.Assets
  ( MapData(..), readMapFiles, availableMaps, decodeMap, toLevel
  , carmackExpand, rlewExpand ) where

import Control.Monad (forM)
import Wolf.Binary
import Wolf.Pack
import Data.Array (array)
import qualified Data.ByteString as B
import Data.Char (chr)
import Data.Foldable (toList)
import qualified Data.Sequence as S
import Wolf.Types

-- Keep all original words, including unused object IDs and the third plane.
-- Future textures, pickups, and actors can use these without changing decoding.
data MapData = MapData
  { mapName :: !String, mapWidth :: !Int, mapHeight :: !Int
  , mapPlanes :: ![[Int]] } deriving (Eq, Show)

-- File-format reference: [CAL_SetupMapFile](../../../WOLFSRC/ID_CA.C#L942).
-- The original opens edition-specific files and allocates segmented buffers;
-- we read ByteStrings and leave edition discovery to Wolf.Pack.
readMapFiles :: FilePath -> IO (Either String (B.ByteString, B.ByteString))
readMapFiles dir = do
  found <- findPack dir
  case found of
    Left err -> pure (Left err)
    Right pack -> do
      header <- readResource pack "MAPHEAD"
      game <- readResource pack "GAMEMAPS"
      pure ((,) <$> header <*> game)

-- C reference: [CAL_SetupMapFile](../../../WOLFSRC/ID_CA.C#L942), specifically
-- its headeroffsets loop and sparse-map sentinel. The public API is one-based.
availableMaps :: B.ByteString -> Either String [Int]
availableMaps header = do
  check (B.length header == 402) "MAPHEAD must contain a tag and 100 offsets (402 bytes)"
  offsets <- mapM (word32 header . (2+) . (4*)) [0..99]
  pure [i | (i,o)<-zip [1..] offsets, o/=0 && o/=4294967295]

-- | First compression layer. The first word is the expanded BYTE count.
-- A7 = near copy, A8 = far copy. A zero count escapes a literal tag word.
-- Copies are deliberately incremental: backreferences may overlap their output.
-- Algorithm reference: [CAL_CarmackExpand](../../../WOLFSRC/ID_CA.C#L609).
-- Near/far copies and escaped tag bytes follow that codec; checked cursors and
-- an incrementally extended Sequence replace unchecked source/destination pointers.
carmackExpand :: B.ByteString -> Either String [Int]
carmackExpand bytes = do
  size <- word16 bytes 0
  check (even size && size>=2) "Invalid Carmack expanded byte count"
  go (size `div` 2) 2 S.empty
  where
    go target pos output
      | S.length output == target = do
          check (pos == B.length bytes) "Trailing bytes after Carmack stream"
          pure (toList output)
      | otherwise = do
          w <- word16 bytes pos
          let tag = w `div` 256
              count = w `mod` 256
          if tag/=0xa7 && tag/=0xa8 then go target (pos+2) (output S.|> w)
          else if count==0 then do
            literal <- byte bytes (pos+2)
            go target (pos+3) (output S.|> (tag*256+literal))
          else do
            offset <- if tag==0xa7 then byte bytes (pos+2) else word16 bytes (pos+2)
            let start = if tag==0xa7 then S.length output-offset else offset
            check (start>=0 && start<S.length output) "Carmack backreference points outside decoded data"
            check (count<=target-S.length output) "Carmack copy exceeds expanded size"
            copied <- copy count start output
            go target (pos + if tag==0xa7 then 3 else 4) copied
    copy 0 _ output = Right output
    copy n i output = case S.lookup i output of
      Nothing -> Left "Invalid Carmack copy"
      Just w -> copy (n-1) (i+1) (output S.|> w)

-- | Second compression layer: tag, count, value. Its first word is again an
-- expanded byte count, which must agree with the validated map dimensions.
-- Algorithm reference: [CA_RLEWexpand](../../../WOLFSRC/ID_CA.C#L734).
-- The marker/count/value format is preserved, with explicit output-size checks.
rlewExpand :: Int -> Int -> [Int] -> Either String [Int]
rlewExpand tag cells input = do
  check (cells>0 && cells<=4096) "Invalid RLEW cell count"
  case input of
    size:rest | size==cells*2 -> go cells rest []
    _ -> Left "RLEW expanded size does not match map dimensions"
  where
    go 0 [] output = Right (reverse output)
    go 0 _ _ = Left "Trailing words after RLEW stream"
    go _ [] _ = Left "Truncated RLEW stream"
    go remaining (w:rest) output
      | w/=tag = go (remaining-1) rest (w:output)
      | otherwise = case rest of
          count:value:tailWords -> do
            check (count>0 && count<=remaining) "Invalid RLEW run length"
            go (remaining-count) tailWords (replicate count value++output)
          _ -> Left "Truncated RLEW run"

-- | Map numbers are one-based, matching the CLI. This edition supports the
-- shipped 64x64 WL1/WL6 format; incompatible formats are rejected explicitly.
-- C references: [CA_CacheMap](../../../WOLFSRC/ID_CA.C#L1428) for the two
-- decompression stages and [maptype](../../../WOLFSRC/ID_CA.H#L17) for layout.
-- The original skips the inner size word; we verify it against map dimensions.
decodeMap :: B.ByteString -> B.ByteString -> Int -> Either String MapData
decodeMap header game number = do
  present <- availableMaps header
  check (number `elem` present) ("Map "++show number++" is absent (use --list-levels)")
  tag <- word16 header 0
  offset <- word32 header (2+4*(number-1))
  check (offset<=toInteger (B.length game)) "Map header offset is outside GAMEMAPS"
  info <- slice game (fromInteger offset) 38
  width <- word16 info 18
  height <- word16 info 20
  check (width==64 && height==64) "Only 64x64 Wolfenstein maps are supported"
  nameBytes <- slice info 22 16
  planes <- forM [0..2] $ \p -> do
    start <- word32 info (4*p)
    size <- word16 info (12+2*p)
    check (start<=toInteger (B.length game)) "Plane offset is outside GAMEMAPS"
    compressed <- slice game (fromInteger start) size
    expanded <- carmackExpand compressed
    rlewExpand tag (width*height) expanded
  pure (MapData (map (chr . fromIntegral) (B.unpack (B.takeWhile (/=0) nameBytes))) width height planes)

-- | Explicit compatibility policy: preserve geometry and easy-difficulty actor
-- positions and sprite identities, but use simplified guard behavior and unlocked
-- doors. Decorations/pickups are visible; their effects, patrols, and pushwalls
-- are not simulated.
-- C references: [SetupGameLevel](../../../WOLFSRC/WL_GAME.C#L625) interprets
-- geometry and doors; [ScanInfoPlane](../../../WOLFSRC/WL_GAME.C#L221) dispatches
-- object IDs. [SpawnPlayer](../../../WOLFSRC/WL_AGENT.C#L1100) supplies facing.
-- We preserve resource IDs/positions but substitute simplified actor behavior.
toLevel :: MapData -> Either String Level
toLevel raw = do
  let width = mapWidth raw
      height = mapHeight raw
  check (width==64 && height==64) "Unsupported map dimensions"
  case mapPlanes raw of
    [geometry,objects,unused] -> do
      check (all ((==width*height) . length) [geometry,objects,unused]) "Incorrect plane length"
      let positions = [(x,y) | y<-[0..height-1], x<-[0..width-1]]
          entries = zip3 positions geometry objects
          starts = [(p,o) | (p,_,o)<-entries, o>=19 && o<=22]
          center (x,y) = Vec (fromIntegral x+0.5) (fromIntegral y+0.5)
          tile n | n>=90 && n<=101 = Door
                 | n==21 = Elevator
                 | n==106 || n>=107 = Floor -- ambush marker and area codes
                 | otherwise = Wall
          enemy o
            | o>=108 && o<=115 = Just 50
            | o>=116 && o<=123 = Just 238
            | o>=126 && o<=133 = Just 138
            | o>=134 && o<=141 = Just 99
            | o>=216 && o<=223 = Just 188
            | otherwise = lookup o [(214,296),(197,385),(215,360),(179,395),(196,307),(160,319),(178,334)]
      -- Some shipped maps contain area codes at the boundary. Preserve them;
      -- tileAt treats everything beyond the array as solid, so DDA still stops.
      case starts of
        [(p,direction)] -> do
          check (any (\(q,n,_) -> q==p && tile n==Floor) entries) "Player start is not on floor"
          pure (Level (array ((0,0),(width-1,height-1)) [(q,tile n) | (q,n,_)<-entries])
            (center p) (fromIntegral (direction-20)*pi/2)
            [(center q,sprite) | (q,_,o)<-entries, Just sprite<-[enemy o]]
            (Just (array ((0,0),(width-1,height-1)) [(q,n) | (q,n,_)<-entries]))
            [(center q,o-23+2) | (q,_,o)<-entries, o>=23 && o<=70])
        _ -> Left "Map must contain exactly one player start"
    _ -> Left "Map must contain three planes"
