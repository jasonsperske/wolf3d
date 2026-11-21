-- | VSWAP pages contain column-major wall textures, command-column sprites,
-- and unsigned 8-bit 7042 Hz PCM. Sparse pages remain absent, not zero textures.
module Wolf.Media (Graphics(..), Picture, Swap(..), decodeSwap, decodeSprite,
                   decodeGraphics, decodeDigitized, pictureAt) where
import Control.Monad (forM)
import Data.Array.Unboxed (UArray, listArray, (!))
import qualified Data.ByteString as B
import qualified Data.Map.Strict as M
import Data.Word (Word32)
import Wolf.Binary
import Wolf.Palette

type Picture = UArray Int Word32 -- transparent pixels are zero; others ARGB

data Swap = Swap { spriteStart :: Int, soundStart :: Int, pages :: [B.ByteString] } deriving Show
data Graphics = Graphics { wallPictures :: M.Map Int Picture, spritePictures :: M.Map Int Picture,
                           doorTexture :: Int } deriving (Eq, Show)

pictureAt :: Picture -> Int -> Int -> Word32
pictureAt pic x y = pic ! (max 0 (min 63 y)*64+max 0 (min 63 x))

decodeSwap :: B.ByteString -> Either String Swap
decodeSwap bytes = do
  count <- word16 bytes 0
  sprites <- word16 bytes 2
  sounds <- word16 bytes 4
  check (count>0 && sprites>0 && sprites<sounds && sounds<count) "Invalid VSWAP page partitions"
  _ <- slice bytes 6 (count*6)
  chunks <- forM [0..count-1] $ \i -> do
    start <- word32 bytes (6+4*i)
    size <- word16 bytes (6+4*count+2*i)
    if start==0 then pure B.empty else do
      check (start>=toInteger (6+count*6) && start<=toInteger (B.length bytes)) "Invalid VSWAP page offset"
      slice bytes (fromInteger start) size
  pure (Swap sprites sounds chunks)

-- Sprite columns hold triples (endY*2, pixelBase, startY*2), terminated by 0.
-- Source pixel index is pixelBase+y, NOT pixelBase+(y-startY).
decodeSprite :: B.ByteString -> Either String Picture
decodeSprite bytes = do
  left <- word16 bytes 0
  right <- word16 bytes 2
  check (left<=right && right<64) "Invalid sprite column bounds"
  _ <- slice bytes 4 (2*(right-left+1))
  columns <- forM [left..right] $ \x -> do
    offset <- word16 bytes (4+2*(x-left))
    let walk pos previous = do
          end2 <- word16 bytes pos
          if end2==0 then pure [] else do
            source <- word16 bytes (pos+2)
            start2 <- word16 bytes (pos+4)
            check (even end2 && even start2 && start2>=previous*2 && start2<end2 && end2<=128)
              "Invalid sprite post range"
            values <- forM [start2 `div` 2..end2 `div` 2-1] $ \y -> do
              -- DOS adds these in a 16-bit offset register. Small sprites
              -- can encode a negative base as an unsigned wrapped word.
              color <- byte bytes ((source+y) `mod` 65536)
              pure (y*64+x,palette ! color)
            rest <- walk (pos+6) (end2 `div` 2)
            pure (values++rest)
    walk offset 0
  let pixels = M.fromList (concat columns)
  pure (listArray (0,4095) [M.findWithDefault 0 i pixels | i<-[0..4095]])

decodeGraphics :: Swap -> Either String Graphics
decodeGraphics swap = do
  walls <- forM (zip [0..] (take (spriteStart swap) (pages swap))) $ \(i,p) ->
    if B.null p then pure [] else do
      check (B.length p==4096) "Wall texture must be 64x64"
      pure [(i,listArray (0,4095) [palette ! fromIntegral (B.index p (x*64+y)) | y<-[0..63],x<-[0..63]])]
  sprites <- forM (zip [0..] (take (soundStart swap-spriteStart swap) (drop (spriteStart swap) (pages swap)))) $ \(i,p) ->
    if B.null p then pure [] else do pic <- decodeSprite p; pure [(i,pic)]
  pure (Graphics (M.fromList (concat walls)) (M.fromList (concat sprites)) (spriteStart swap-8))

decodeDigitized :: Swap -> Either String [B.ByteString]
decodeDigitized swap = case reverse (pages swap) of
  [] -> Left "Missing digitized sound directory"
  info:_ -> go info 0 (soundStart swap)
  where
    lastPage = length (pages swap)-1
    go info pos consumed
      | consumed>=lastPage = Right []
      | otherwise = do
          start <- word16 info pos
          size <- word16 info (pos+2)
          let first = soundStart swap+start
              count = (size+4095) `div` 4096
          check (size>0 && first==consumed && first+count<=lastPage) "Invalid digitized sound range"
          let chunks = take count (drop first (pages swap))
              absent = all B.null chunks -- registered-only sounds are sparse in WL1
              pcm = B.concat chunks
          check (absent || (all (not . B.null) chunks && B.length pcm>=size)) "Truncated digitized sample"
          rest <- go info (pos+4) (first+count)
          pure (B.take size pcm:rest)
