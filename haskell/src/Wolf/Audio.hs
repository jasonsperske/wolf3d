-- | Original IMF music and AdLib effects stay as validated register streams.
-- Hardware emulation and SDL mixing belong to the platform, not the game rules.
module Wolf.Audio (AudioBank(..), decodeAudio, decodeIMF, levelMusic, soundEvents) where
import Control.Monad (forM)
import qualified Data.ByteString as B
import qualified Data.Map.Strict as M
import Wolf.Binary
import Wolf.Types

data AudioBank = AudioBank { musicTracks :: [B.ByteString], adlibSounds :: [B.ByteString] } deriving Show

decodeIMF :: B.ByteString -> Either String B.ByteString
decodeIMF bytes = do
  size <- word16 bytes 0
  check (size `mod` 4==0 && size+2<=B.length bytes) "Invalid IMF stream length"
  -- The resource compiler appends editor metadata. Only the declared event
  -- bytes are music; zero-length streams mark unavailable shareware tracks.
  events <- slice bytes 2 size
  delays <- mapM (word16 events . (+2)) [0,4..size-4]
  check (size==0 || any (>0) delays) "IMF must advance time"
  pure events

decodeAudio :: B.ByteString -> B.ByteString -> Either String AudioBank
decodeAudio header bytes = do
  check (B.length header `mod` 4==0) "Invalid AUDIOHED length"
  let count = B.length header `div` 4-1
      sounds = (count-27) `div` 3
  check (sounds `elem` [69,87] && count==sounds*3+27) "Unsupported Wolfenstein audio directory"
  offsets <- mapM (word32 header . (*4)) [0..count]
  check (and (zipWith (<=) offsets (drop 1 offsets)) && all (<=toInteger (B.length bytes)) offsets)
    "Invalid audio chunk offsets"
  chunks <- forM (zip offsets (drop 1 offsets)) $ \(a,b) -> slice bytes (fromInteger a) (fromInteger (b-a))
  music <- mapM (\b -> if B.null b then pure b else decodeIMF b) (drop (sounds*3) chunks)
  effects <- forM (take sounds (drop sounds chunks)) $ \b -> if B.null b then pure b else do
    len <- word32 b 0
    check (len>0 && len<=65535 && len+23<=toInteger (B.length b)) "Invalid AdLib effect length"
    slice b 0 (23+fromInteger len)
  pure (AudioBank music effects)

levelMusic :: AudioBank -> Int -> Int
levelMusic bank number = table !! ((number-1) `mod` 60)
  where
    boss = if length (adlibSounds bank)==69 then 26 else 2
    ep1 = [3,11,9,12,3,11,9,12,boss,0]
    ep2 = [8,18,17,4,8,18,4,17,boss,1]
    ep3 = [6,20,22,21,6,20,21,22,19,26]
    table = ep1++ep2++ep3++ep1++ep2++ep3

-- Event IDs use the stable first 69 sound numbers in AUDIOWL*.H. Extract once
-- per simulation tick, so a slow rendered frame does not miss an entire shot.
soundEvents :: World -> World -> [Int]
soundEvents old new =
  [24 | muzzle new>muzzle old] ++
  [18 | M.size (doors new)>M.size (doors old)] ++
  [16 | health new<health old && health new>0] ++
  [9 | outcome old/=Lost && outcome new==Lost] ++
  [40 | outcome old/=Won && outcome new==Won] ++
  [21 | or (zipWith (\a b -> guardMode a==Idle && guardMode b==Chasing) (guards old) (guards new))] ++
  [29 | or (zipWith (\a b -> guardMode a/=Dead && guardMode b==Dead) (guards old) (guards new))] ++
  [58 | or (zipWith (\a b -> guardCooldown b>guardCooldown a) (guards old) (guards new))]
