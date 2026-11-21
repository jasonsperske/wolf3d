module Wolf.Level (parseLevel, demoLevel, initialWorld, tileAt, solidAt) where

import Data.Array (array, bounds, inRange, (!))
import qualified Data.Map.Strict as M
import Wolf.Types

-- | Validate external data once. Everywhere else can rely on a rectangular,
-- enclosed map with exactly one player and at least one exit.
parseLevel :: [String] -> Either String Level
parseLevel rows
  | h < 3 || w < 3 = Left "Map must be at least 3 by 3"
  | any ((/= w) . length) rows = Left "Map rows must have equal width"
  | any (`notElem` "#.PGE+D") (concat rows) = Left "Unknown map character"
  | any (\((x,y),c) -> (x==0 || y==0 || x==w-1 || y==h-1) && c/='#') cells = Left "Map boundary must be walls"
  | length starts /= 1 = Left "Map needs exactly one P"
  | not (any ((=='E') . snd) cells) = Left "Map needs an exit E"
  | otherwise = case starts of
      [p] -> Right (Level (array ((0,0),(w-1,h-1)) [(i,tile c) | (i,c)<-cells]) p enemies)
      _ -> Left "Map needs exactly one P"
  where
    h = length rows
    w = case rows of [] -> 0; r:_ -> length r
    cells = [((x,y),c) | (y,r)<-zip [0..] rows, (x,c)<-zip [0..] r]
    center (x,y) = Vec (fromIntegral x+0.5) (fromIntegral y+0.5)
    starts = [center i | (i,'P')<-cells]
    enemies = [center i | (i,'G')<-cells]
    tile '#' = Wall
    tile 'D' = Door
    tile '+' = Door
    tile 'E' = Exit
    tile _ = Floor

demoLevel :: Either String Level
demoLevel = parseLevel
  [ "################"
  , "#P.....#.......#"
  , "#......D...G...#"
  , "#......#.......#"
  , "#..##..#..##...#"
  , "#......#.......#"
  , "###D#######D####"
  , "#......#.......#"
  , "#..G...D.......#"
  , "#......#...G...#"
  , "#......#.......#"
  , "#......#.....E.#"
  , "################" ]

initialWorld :: Level -> World
initialWorld l = World l (spawn l) 0 100 M.empty
  [Guard p Idle 0 | p<-guardSpawns l] 0 0 Playing

tileAt :: Level -> (Int,Int) -> Tile
tileAt l p | inRange (bounds (tiles l)) p = tiles l ! p
           | otherwise = Wall -- total lookup: outside the map is never walkable

solidAt :: World -> (Int,Int) -> Bool
solidAt w p = case tileAt (level w) p of
  Wall -> True
  Door -> M.findWithDefault Closed p (doors w) /= Open
  _ -> False
