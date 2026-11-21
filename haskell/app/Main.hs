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

data Mode = Play | Snapshot FilePath | Smoke | ListLevels deriving (Eq)
data Options = Options (Maybe FilePath) Int Mode

usage :: String
usage = "Usage: wolf-haskell [--assets DIR [--level 1..100]] [--snapshot FILE | --smoke | --list-levels]"

-- Explicit opt-in keeps the asset-free demo runnable from any working directory.
parseOptions :: [String] -> Either String Options
parseOptions = go (Options Nothing 1 Play)
  where
    go options [] = Right options
    go (Options _ n mode) ("--assets":dir:rest) = go (Options (Just dir) n mode) rest
    go (Options dir _ mode) ("--level":value:rest) = case readMaybe value of
      Just n | n>=1 && n<=100 -> go (Options dir n mode) rest
      _ -> Left "--level must be an integer from 1 to 100"
    go (Options dir n Play) ("--snapshot":path:rest) = go (Options dir n (Snapshot path)) rest
    go (Options dir n Play) ("--smoke":rest) = go (Options dir n Smoke) rest
    go (Options dir n Play) ("--list-levels":rest) = go (Options dir n ListLevels) rest
    go _ _ = Left usage

main :: IO ()
main = do
  args <- getArgs
  if args==["--help"] then putStrLn usage else do
    Options directory number mode <- either die pure (parseOptions args)
    case directory of
      Nothing | mode==ListLevels || "--level" `elem` args -> die "--list-levels and --level require --assets DIR"
      Nothing -> either die (runMode mode . initialWorld) demoLevel
      Just dir -> do
        (header,game) <- readMapFiles dir >>= either die pure
        case mode of
          ListLevels -> do
            numbers <- either die pure (availableMaps header)
            mapM_ (\n -> do
              raw <- either die pure (decodeMap header game n)
              putStrLn (show n++": "++mapName raw++" ("++show (mapWidth raw)++"x"++show (mapHeight raw)++")")) numbers
          _ -> do
            raw <- either die pure (decodeMap header game number)
            l <- either die pure (toLevel raw)
            putStrLn ("Loaded "++mapName raw++"; procedural graphics and simplified actors. E activates elevators.")
            runMode mode (initialWorld l)

runMode :: Mode -> World -> IO ()
runMode mode w = case mode of
  Snapshot path -> writePPM path w
  Smoke -> withPlatform $ allocaArray (screenWidth*screenHeight) $ \buffer -> present buffer w
  Play -> withPlatform $ allocaArray (screenWidth*screenHeight) $ \buffer -> do
    t <- realToFrac <$> platformTime
    loop buffer w w t 0
  ListLevels -> die "--list-levels requires --assets DIR"
  where
    withPlatform = bracket_ acquire platformClose
    acquire = do
      ok <- platformOpen
      unless (ok/=0) $ do
        err <- platformError >>= peekCString
        platformClose
        die ("SDL initialization failed: "++err)

present :: Ptr Word32 -> World -> IO ()
present buffer w = do
  pokeArray buffer (elems (render w))
  let status = case outcome w of Playing -> 0; Won -> 1; Lost -> 2
  ok <- platformPresent buffer status (fromIntegral (health w))
         (fromIntegral (length (filter ((/=Dead) . guardMode) (guards w))))
  unless (ok/=0) (platformError >>= peekCString >>= die)

-- Cap catch-up at 250 ms after a pause. The simulation always receives the same
-- timestep; rendering can happen at any rate. Input is sampled once per frame.
loop :: Ptr Word32 -> World -> World -> Double -> Double -> IO ()
loop buffer initial w previous remainder = do
  bits <- platformInput
  unless (testBit bits 0) $ do
    now <- realToFrac <$> platformTime
    let axis positive negative = fromIntegral (fromEnum (testBit bits positive)-fromEnum (testBit bits negative))
        input = Input (axis 1 2) (axis 4 3) (axis 6 5) (testBit bits 7) (testBit bits 8)
        accumulated = remainder + max 0 (min 0.25 (now-previous))
        ticks = floor (accumulated*60) :: Int
        advance 0 state = state
        advance n state = let advanced = step (1/60) input state in advanced `seq` advance (n-1) advanced
        next = if testBit bits 9 then initial else advance ticks w
    present buffer next
    platformDelay
    loop buffer initial next now (accumulated-fromIntegral ticks/60)
