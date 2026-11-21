{-# LANGUAGE ForeignFunctionInterface #-}
module Main (main) where

import Control.Exception (bracket_)
import Control.Monad (unless)
import Data.Array.Unboxed (elems)
import Data.Bits (testBit)
import Data.Word (Word32)
import Foreign (Ptr, allocaArray, pokeArray)
import Foreign.C (CInt(..), CDouble(..), CString, peekCString)
import System.Environment (getArgs)
import System.Exit (die)
import Text.Read (readMaybe)
import Wolf.Assets
import Wolf.Pack
import Wolf.Media
import Wolf.Audio
import Wolf.Playback
import qualified Data.ByteString as B
import System.IO (hPutStrLn, stderr)
import Wolf.Types
import Wolf.Level
import Wolf.Simulation
import Wolf.Render

foreign import ccall unsafe "platform_open" platformOpen :: IO CInt
foreign import ccall unsafe "platform_close" platformClose :: IO ()
foreign import ccall unsafe "platform_error" platformError :: IO CString
foreign import ccall unsafe "platform_input" platformInput :: IO Word32
foreign import ccall unsafe "platform_present" platformPresent :: Ptr Word32 -> CInt -> CInt -> CInt -> IO CInt
foreign import ccall unsafe "platform_time" platformTime :: IO CDouble
foreign import ccall safe "platform_delay" platformDelay :: IO ()

data Mode = Play | Snapshot FilePath | AudioPreview FilePath | Smoke | ListLevels deriving (Eq)
data Options = Options { assetDirectory :: Maybe FilePath, levelNumber :: Int, mode :: Mode,
                         demo :: Bool, silent :: Bool }
data Resources = Resources Graphics AudioBank [B.ByteString] Int Bool

usage :: String
usage = "Usage: wolf-haskell [--assets DIR | --demo] [--level 1..100] [--no-audio] [--snapshot FILE | --audio-preview FILE.wav | --smoke | --list-levels]"

parseOptions :: [String] -> Either String Options
parseOptions = go (Options Nothing 1 Play False False)
  where
    go options []
      | demo options && assetDirectory options/=Nothing = Left "--demo and --assets cannot be combined"
      | otherwise = Right options
    go o ("--assets":dir:rest) = go (o {assetDirectory=Just dir}) rest
    go o ("--level":value:rest) = case readMaybe value of
      Just n | n>=1 && n<=100 -> go (o {levelNumber=n}) rest
      _ -> Left "--level must be an integer from 1 to 100"
    go o ("--demo":rest) = go (o {demo=True}) rest
    go o ("--no-audio":rest) = go (o {silent=True}) rest
    go o ("--snapshot":path:rest) | mode o==Play = go (o {mode=Snapshot path}) rest
    go o ("--audio-preview":path:rest) | mode o==Play = go (o {mode=AudioPreview path}) rest
    go o ("--smoke":rest) | mode o==Play = go (o {mode=Smoke}) rest
    go o ("--list-levels":rest) | mode o==Play = go (o {mode=ListLevels}) rest
    go _ _ = Left usage

-- Startup counterpart: [SetupGameLevel](../../WOLFSRC/WL_GAME.C#L625).
-- Command-line pack selection, headless modes, and explicit resource ownership
-- are new shell code; they are not translations of the DOS startup/menu system.
main :: IO ()
main = do
  args <- getArgs
  if args==["--help"] then putStrLn usage else do
    options <- either die pure (parseOptions args)
    found <- if demo options then pure (Right Nothing) else case assetDirectory options of
      Just dir -> fmap (fmap Just) (findPack dir)
      Nothing -> discoverPack
    pack <- either die pure found
    case pack of
      Nothing | mode options==ListLevels || levelNumber options/=1 -> die "No asset pack found; populate assets/shareware or assets/registered"
      Nothing -> either die (runMode (mode options) Nothing . initialWorld) demoLevel
      Just assets -> do
        header <- readResource assets "MAPHEAD" >>= either die pure
        game <- readResource assets "GAMEMAPS" >>= either die pure
        case mode options of
          ListLevels -> do
            numbers <- either die pure (availableMaps header)
            mapM_ (\n -> do
              raw <- either die pure (decodeMap header game n)
              putStrLn (show n++": "++mapName raw)) numbers
          _ -> do
            raw <- either die pure (decodeMap header game (levelNumber options))
            l <- either die pure (toLevel raw)
            swapBytes <- readResource assets "VSWAP" >>= either die pure
            swap <- either die pure (decodeSwap swapBytes)
            graphics <- either die pure (decodeGraphics swap)
            samples <- either die pure (decodeDigitized swap)
            audioHeader <- readResource assets "AUDIOHED" >>= either die pure
            audioData <- readResource assets "AUDIOT" >>= either die pure
            bank <- either die pure (decodeAudio audioHeader audioData)
            putStrLn ("Loaded "++mapName raw++" from "++packDirectory assets++" ("++packExtension assets++")")
            runMode (mode options) (Just (Resources graphics bank samples (levelNumber options) (silent options))) (initialWorld l)

runMode :: Mode -> Maybe Resources -> World -> IO ()
runMode selected resources w = case selected of
  Snapshot path -> writePPMWith graphics path w
  AudioPreview path -> case resources of
    Nothing -> die "Audio preview requires an asset pack"
    Just (Resources _ bank samples n _) -> bracket_ (do
      ok <- prepareAudio bank samples n
      unless ok (platformError >>= peekCString >>= die)) closeAudio (exportAudio path)
  Smoke -> withPlatform $ allocaArray (screenWidth*screenHeight) $ \buffer -> do
    _ <- setupAudio
    present graphics buffer w
  Play -> withPlatform $ allocaArray (screenWidth*screenHeight) $ \buffer -> do
    enabled <- setupAudio
    t <- realToFrac <$> platformTime
    loop graphics enabled buffer w w t 0
  ListLevels -> die "No asset pack found"
  where
    graphics = case resources of Nothing -> Nothing; Just (Resources g _ _ _ _) -> Just g
    setupAudio = case resources of
      Just (Resources _ bank samples n False) -> do
        prepared <- prepareAudio bank samples n
        enabled <- if prepared then startAudio else pure False
        unless enabled $ do
          message <- platformError >>= peekCString
          hPutStrLn stderr ("Audio unavailable: "++message++" (continuing muted)")
          closeAudio
        pure enabled
      _ -> pure False
    withPlatform = bracket_ acquire platformClose
    acquire = do
      ok <- platformOpen
      unless (ok/=0) $ do
        err <- platformError >>= peekCString
        platformClose
        die ("SDL initialization failed: "++err)

-- Presentation counterpart: [ThreeDRefresh](../../WOLFSRC/WL_DRAW.C#L1336).
-- The original combines drawing and VGA presentation; we keep pixel generation
-- pure and send a completed buffer through the SDL adapter.
present :: Maybe Graphics -> Ptr Word32 -> World -> IO ()
present graphics buffer w = do
  pokeArray buffer (elems (renderWith graphics w))
  let status = case outcome w of Playing -> 0; Won -> 1; Lost -> 2
  ok <- platformPresent buffer status (fromIntegral (health w))
         (fromIntegral (length (filter ((/=Dead) . guardMode) (guards w))))
  unless (ok/=0) (platformError >>= peekCString >>= die)

-- Cap catch-up at 250 ms after a pause. The simulation always receives the same
-- timestep; rendering can happen at any rate. Input is sampled once per frame.
-- C counterparts: [PlayLoop](../../WOLFSRC/WL_PLAY.C#L1368),
-- [PollControls](../../WOLFSRC/WL_PLAY.C#L455), and
-- [CalcTics](../../WOLFSRC/WL_DRAW.C#L1236). The order is recognizable, but the
-- accumulator uses fixed 60-Hz updates rather than the original variable tics.
loop :: Maybe Graphics -> Bool -> Ptr Word32 -> World -> World -> Double -> Double -> IO ()
loop graphics enabled buffer initial w previous remainder = do
  bits <- platformInput
  unless (testBit bits 0) $ do
    now <- realToFrac <$> platformTime
    let axis positive negative = fromIntegral (fromEnum (testBit bits positive)-fromEnum (testBit bits negative))
        input = Input (axis 1 2) (axis 4 3) (axis 6 5) (testBit bits 7) (testBit bits 8)
        accumulated = remainder + max 0 (min 0.25 (now-previous))
        ticks = floor (accumulated*60) :: Int
        advance 0 state = pure state
        advance n state = do
          let advanced = step (1/60) input state
          if enabled then playSounds (soundEvents state advanced) else pure ()
          advanced `seq` advance (n-1) advanced
    next <- if testBit bits 9 then pure initial else advance ticks w
    present graphics buffer next
    platformDelay
    loop graphics enabled buffer initial next now (accumulated-fromIntegral ticks/60)
