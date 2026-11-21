module Main (main) where
import Control.Monad (unless)
import qualified Data.ByteString as B
import qualified Data.Map.Strict as M
import Data.Array.Unboxed ((!))
import System.Environment (getArgs)
import System.Exit (die)
import Wolf.Media
import Wolf.Audio
import Wolf.Pack

assert :: String -> Bool -> IO ()
assert label value = unless value (die ("FAIL: "++label))
left :: Either a b -> Bool
left (Left _) = True
left _ = False
words16 :: [Int] -> B.ByteString
words16 = B.pack . concatMap (\w -> [fromIntegral w,fromIntegral (w `div` 256)])
words32 :: [Int] -> B.ByteString
words32 = words16 . concatMap (\w -> [w `mod` 65536,w `div` 65536])

main :: IO ()
main = do
  let sprite = words16 [0,0,6,4,14,0,0] <> B.pack [0,15]
  pic <- either die pure (decodeSprite sprite)
  assert "black sprite pixels are opaque" (pic ! 0==0xff000000)
  assert "unpainted sprite pixels are transparent" (pic ! 1==0)
  assert "sprite source uses base plus row" (pic ! 64/=0)
  let wrapped = words16 [0,0,6,120,65514,116,0] <> B.replicate 22 0 <> B.pack [15,15]
  p <- either die pure (decodeSprite wrapped)
  assert "16-bit sprite base wrapping" (p ! (58*64)/=0 && p ! (57*64)==0)
  assert "sprite bounds checked" (left (decodeSprite (words16 [0,64,6])))
  assert "sprite source checked" (left (decodeSprite (words16 [0,0,6,4,200,0,0])))
  assert "sprite reversed post rejected" (left (decodeSprite (words16 [0,0,6,4,14,6,0])))
  assert "sprite missing terminator rejected" (left (decodeSprite (B.take 12 sprite)))
  assert "sprite odd row rejected" (left (decodeSprite (words16 [0,0,6,3,14,0,0])))
  let wall = B.pack [fromIntegral (x `mod` 16) | x<-[0::Int ..63], _y<-[0::Int ..63]]
      sample = B.pack [0,64,128,255]
      info = words16 [0,4]
      chunks = [wall,sprite,sample,info]
      offsets = take 4 (scanl (+) 30 (map B.length chunks))
      swapBytes = words16 [4,1,2] <> words32 offsets <> words16 (map B.length chunks) <> B.concat chunks
  swap <- either die pure (decodeSwap swapBytes)
  graphics <- either die pure (decodeGraphics swap)
  let texture = wallPictures graphics M.! 0
  assert "column-major texture transposed" (texture ! 0==texture ! 64 && texture ! 0/=texture ! 1)
  assert "PCM assembly" (decodeDigitized swap==Right [sample])
  assert "sparse sound preserved" (decodeDigitized (Swap 1 2 [wall,sprite,B.empty,info])==Right [B.empty])
  assert "short PCM rejected" (left (decodeDigitized (Swap 1 2 [wall,sprite,B.pack [0],info])))
  assert "truncated VSWAP table rejected" (left (decodeSwap (B.take 15 swapBytes)))
  assert "bad VSWAP range rejected" (left (decodeSwap (B.take (B.length swapBytes-1) swapBytes)))
  let imf = B.pack [4,0,32,1,1,0]
  assert "IMF metadata ignored" (decodeIMF (imf<>B.pack [99,88])==Right (B.drop 2 imf))
  assert "unavailable music track" (decodeIMF (B.pack [0,0,99])==Right B.empty)
  assert "truncated IMF rejected" (left (decodeIMF (B.take 5 imf)))
  assert "zero-time IMF loop rejected" (left (decodeIMF (B.pack [4,0,32,1,0,0])))
  assert "non-event IMF size rejected" (left (decodeIMF (B.pack [3,0,32,1,0])))
  let effect = words32 [1] <> words16 [0] <> B.replicate 16 0 <> B.pack [1,100]
      audioChunks = replicate 87 B.empty ++ [effect] ++ replicate 173 B.empty ++ replicate 27 imf
      audioOffsets = scanl (+) 0 (map B.length audioChunks)
  bank <- either die pure (decodeAudio (words32 audioOffsets) (B.concat audioChunks))
  assert "registered-style sound directory" (length (adlibSounds bank)==87 && length (musicTracks bank)==27)
  assert "episode music selection" (levelMusic bank 1==3 && levelMusic bank 11==8 && levelMusic bank 60==26)
  assert "audio offset monotonicity" (left (decodeAudio (words32 (0:1:0:drop 3 audioOffsets)) (B.concat audioChunks)))
  args <- getArgs
  case args of
    [] -> pure ()
    [dir] -> integration dir
    _ -> die "Usage: media-tests [asset-directory]"
  putStrLn "All media checks passed."

integration :: FilePath -> IO ()
integration dir = do
  pack <- findPack dir >>= either die pure
  raw <- readResource pack "VSWAP" >>= either die pure
  swap <- either die pure (decodeSwap raw)
  graphics <- either die pure (decodeGraphics swap)
  samples <- either die pure (decodeDigitized swap)
  header <- readResource pack "AUDIOHED" >>= either die pure
  audio <- readResource pack "AUDIOT" >>= either die pure
  bank <- either die pure (decodeAudio header audio)
  assert "wall and pistol graphics available" (M.member 0 (wallPictures graphics) && M.member 421 (spritePictures graphics))
  assert "pistol PCM available" (case drop 5 samples of p:_ -> not (B.null p); _ -> False)
  assert "first level music available" (case drop (levelMusic bank 1) (musicTracks bank) of t:_ -> not (B.null t); _ -> False)
  putStrLn ("Decoded "++show (M.size (wallPictures graphics))++" textures, "++show (M.size (spritePictures graphics))++
    " sprites, "++show (length (filter (not . B.null) samples))++" PCM sounds, "++
    show (length (filter (not . B.null) (musicTracks bank)))++" music tracks")
