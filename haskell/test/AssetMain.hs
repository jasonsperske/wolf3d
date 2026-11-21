module Main (main) where

import Control.Monad (forM_, unless, when)
import qualified Data.ByteString as B
import Data.Array (bounds, (!))
import System.Environment (getArgs)
import System.Exit (die)
import Wolf.Assets
import Wolf.Pack
import Wolf.Media
import Wolf.Types
import Wolf.Level
import Wolf.Simulation
import Wolf.Render

assert :: String -> Bool -> IO ()
assert label condition = unless condition (die ("FAIL: "++label))
left :: Either a b -> Bool
left (Left _) = True
left _ = False
wordsLE :: [Int] -> B.ByteString
wordsLE = B.pack . concatMap (\w -> [fromIntegral (w `mod` 256), fromIntegral (w `div` 256)])

-- An entirely synthetic, uncompressed 64x64 map exercises header offsets and
-- row-major translation without shipping any original game data in tests.
synthetic :: (B.ByteString,B.ByteString)
synthetic = (header,game)
  where
    header = B.pack ([0xcd,0xab,8,0,0,0]++replicate 396 0)
    geometry = [if x==0 || x==63 || y==0 || y==63 then 1
                else if (x,y)==(3,1) then 90 else if (x,y)==(4,1) then 21 else 107
               | y<-[0::Int ..63], x<-[0::Int ..63]]
    objects = [if (x,y)==(1,1) then 19 else if (x,y)==(2,1) then 108 else 0
               | y<-[0::Int ..63], x<-[0::Int ..63]]
    plane ws = wordsLE (8194:8192:ws)
    size = 8196
    info = B.concat [wordsLE (concatMap (\o -> [o,0]) [46,46+size,46+2*size]),
                     wordsLE [size,size,size,64,64], B.pack (map (fromIntegral . fromEnum) "Synthetic"++replicate 7 0)]
    game = B.concat [B.replicate 8 0,info,plane geometry,plane objects,plane (replicate 4096 0)]

main :: IO ()
main = do
  assert "Carmack literal" (carmackExpand (wordsLE [4,42,43])==Right [42,43])
  assert "Carmack escaped near and far tags" (carmackExpand (B.pack [4,0,0,167,17,0,168,18])==Right [0xa711,0xa812])
  assert "near copy overlaps output" (carmackExpand (B.pack [8,0,7,0,3,167,1])==Right [7,7,7,7])
  assert "far copy overlaps output" (carmackExpand (wordsLE [8,7,0xa803,0])==Right [7,7,7,7])
  assert "backreference before output rejected" (left (carmackExpand (B.pack [2,0,1,167,1])))
  assert "zero near offset rejected" (left (carmackExpand (B.pack [4,0,7,0,1,167,0])))
  assert "far forward reference rejected" (left (carmackExpand (wordsLE [4,7,0xa801,2])))
  assert "oversized Carmack copy rejected" (left (carmackExpand (wordsLE [4,7,0xa803,0])))
  assert "odd expanded byte count rejected" (left (carmackExpand (wordsLE [3,7])))
  assert "truncated escaped literal rejected" (left (carmackExpand (wordsLE [2,0xa700])))
  assert "trailing Carmack bytes rejected" (left (carmackExpand (wordsLE [2,7,8])))
  assert "RLEW run and literal" (rlewExpand 0xabcd 4 [8,7,0xabcd,3,42]==Right [7,42,42,42])
  assert "RLEW tag can itself be repeated" (rlewExpand 0xabcd 1 [2,0xabcd,1,0xabcd]==Right [0xabcd])
  assert "RLEW expanded size checked" (left (rlewExpand 0xabcd 1 [4,7]))
  assert "RLEW overflow rejected" (left (rlewExpand 0xabcd 1 [2,0xabcd,2,7]))
  assert "RLEW zero run rejected" (left (rlewExpand 0xabcd 1 [2,0xabcd,0,7]))
  assert "RLEW truncated run rejected" (left (rlewExpand 0xabcd 1 [2,0xabcd,1]))
  assert "RLEW trailing words rejected" (left (rlewExpand 0xabcd 1 [2,7,8]))
  let (header,game) = synthetic
  assert "present map listing" (availableMaps header==Right [1])
  assert "absent map rejected" (left (decodeMap header game 2))
  assert "negative map rejected" (left (decodeMap header game (-1)))
  forM_ [0,1,400,401] $ \n -> assert "truncated header rejected" (left (availableMaps (B.take n header)))
  forM_ [0,8,45,B.length game-1] $ \n -> assert "truncated map rejected" (left (decodeMap header (B.take n game) 1))
  let badOffset = B.take 2 header <> B.pack [255,255,255,127] <> B.drop 6 header
      badDimension = B.take 26 game <> wordsLE [63] <> B.drop 28 game
  assert "out-of-range map offset rejected" (left (decodeMap badOffset game 1))
  assert "unsupported dimensions rejected" (left (decodeMap header badDimension 1))
  raw <- either die pure (decodeMap header game 1)
  l <- either die pure (toLevel raw)
  assert "map name" (mapName raw=="Synthetic")
  assert "row-major coordinates" (tiles l ! (3,1)==Door && tiles l ! (1,3)==Floor)
  assert "player direction" (spawn l==Vec 1.5 1.5 && spawnAngle l==(-pi/2))
  assert "actor location" (guardSpawns l==[(Vec 2.5 1.5,50)])
  let w = (initialWorld l) {player=Vec 4.5 2.5, angle=(-pi/2)}
  assert "elevator is solid" (solidAt w (4,1))
  assert "using elevator wins" (outcome (step (1/60) (noInput {use=True}) w)==Won)
  args <- getArgs
  case args of
    [] -> pure ()
    [dir] -> integration dir
    _ -> die "Usage: asset-tests [shareware-directory]"
  putStrLn "All asset checks passed."

integration :: FilePath -> IO ()
integration dir = do
  pack <- findPack dir >>= either die pure
  (header,game) <- readMapFiles dir >>= either die pure
  swapBytes <- readResource pack "VSWAP" >>= either die pure
  swap <- either die pure (decodeSwap swapBytes)
  graphics <- either die pure (decodeGraphics swap)
  numbers <- either die pure (availableMaps header)
  when (packExtension pack=="WL1") $ assert "ten shareware maps" (numbers==[1..10])
  -- Weighted plane checksums and spawns independently decoded from the supplied
  -- December 1992 WL1 files. These integration goldens are version-specific.
  let expected =
        [(277564585,27295850,(29,57)), (654966181,67777523,(16,61)),
         (626434419,49987304,(20,1)), (569795013,54078077,(3,3)),
         (551724333,58224349,(32,34)), (415590621,37573597,(44,23)),
         (639663768,43796286,(40,44)), (452429339,39483919,(34,58)),
         (255287290,5124682,(34,58)), (565534596,47240131,(5,38))]
      checksum ws = sum (zipWith (*) [1::Integer ..] (map toInteger ws))
  forM_ numbers $ \n -> do
    raw <- either die pure (decodeMap header game n)

    l <- either die pure (toLevel raw)
    assert "64x64 tile array" (bounds (tiles l)==((0,0),(63,63)))
    when (packExtension pack=="WL1") $ case drop (n-1) expected of
      (geometrySum,objectSum,start):_ -> do
        assert ("plane checksums "++show n) (map checksum (mapPlanes raw)==[geometrySum,objectSum,0])
        assert "original player location" (cell (spawn l)==start)
      _ -> die "Unexpected shareware map number"
    assert "valid player footprint" (canStand (initialWorld l) (spawn l))
    writePPMWith (Just graphics) ("build/shareware-"++show n++".ppm") (initialWorld l)
    putStrLn ("Verified "++mapName raw)
