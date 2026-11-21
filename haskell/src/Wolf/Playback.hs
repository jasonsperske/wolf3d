{-# LANGUAGE ForeignFunctionInterface #-}
-- | The small effectful audio shell. Resource bytes are copied by C during
-- initialization; no ByteString pointer escapes its withCString scope.
module Wolf.Playback (prepareAudio, startAudio, playSounds, closeAudio, exportAudio) where
import Control.Monad (forM_, unless)
import qualified Data.ByteString as B
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import Data.Int (Int16)
import Foreign (Ptr, allocaArray, peekArray, castPtr)
import Foreign.C (CInt(..), CString, withCString)
import System.Environment (getExecutablePath)
import System.FilePath ((</>), takeDirectory)
import Wolf.Audio

foreign import ccall unsafe "audio_prepare" prepare :: CString -> IO CInt
foreign import ccall unsafe "audio_music" music :: Ptr a -> CInt -> IO CInt
foreign import ccall unsafe "audio_pcm" pcm :: CInt -> Ptr a -> CInt -> IO CInt
foreign import ccall unsafe "audio_effect" effect :: CInt -> Ptr a -> CInt -> IO CInt
foreign import ccall unsafe "audio_play" play :: CInt -> IO ()
foreign import ccall unsafe "audio_start" start :: IO CInt
foreign import ccall unsafe "audio_close" closeAudio :: IO ()
foreign import ccall unsafe "audio_render" renderAudio :: Ptr Int16 -> CInt -> IO ()

prepareAudio :: AudioBank -> [B.ByteString] -> Int -> IO Bool
prepareAudio bank samples levelNumber = do
  exe <- getExecutablePath
  ok <- withCString (takeDirectory exe </> "libwolfopl.so") prepare
  if ok==0 then pure False else do
    let transfer callback bytes = B.useAsCStringLen bytes $ \(p,n) -> do
          result <- callback (castPtr p) (fromIntegral n)
          unless (result/=0) (ioError (userError "Failed to copy audio resource"))
    forM_ (zip [0..] samples) $ \(i,b) -> transfer (pcm i) b
    forM_ (zip [0..] (adlibSounds bank)) $ \(i,b) -> transfer (effect i) b
    case drop (levelMusic bank levelNumber) (musicTracks bank) of
      track:_ | not (B.null track) -> transfer music track
      _ -> pure ()
    pure True

startAudio :: IO Bool
startAudio = (/=0) <$> start
playSounds :: [Int] -> IO ()
playSounds = mapM_ (play . fromIntegral)

-- Five seconds of the selected original song, then gameplay effects mixed in.
-- Explicit little-endian WAV output works independently of host byte order.
exportAudio :: FilePath -> IO ()
exportAudio path = do
  chunks <- mapM chunk [0::Int ..4]
  let payload = mconcat chunks
      size = 5*44100*4 :: Int
      ascii = BB.string8
      header = ascii "RIFF" <> BB.word32LE (fromIntegral (36+size)) <> ascii "WAVEfmt " <>
        BB.word32LE 16 <> BB.word16LE 1 <> BB.word16LE 2 <> BB.word32LE 44100 <>
        BB.word32LE (44100*4) <> BB.word16LE 4 <> BB.word16LE 16 <> ascii "data" <> BB.word32LE (fromIntegral size)
  BL.writeFile path (BB.toLazyByteString (header<>payload))
  where
    chunk second = allocaArray (44100*2) $ \buffer -> do
      case second of 1 -> playSounds [24]; 2 -> playSounds [18]; 3 -> playSounds [16]; _ -> pure ()
      renderAudio buffer 44100
      values <- peekArray (44100*2) buffer
      pure (mconcat (map BB.int16LE values))
