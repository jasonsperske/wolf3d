-- | Pure at the boundary, mutable on the inside. ST lets a local framebuffer
-- be updated in place, but its mutable reference cannot escape runSTUArray.
module Wolf.Render (render, renderWith, screenWidth, screenHeight, writePPM, writePPMWith) where

import Control.Monad (forM_, when)
import Data.Array (listArray, bounds, inRange, (!))
import Data.Array.ST (newArray, writeArray, runSTUArray)
import Data.Array.Unboxed (UArray, elems)
import Data.Bits ((.|.), shiftL, shiftR, (.&.))
import Data.List (sortOn)
import Data.Ord (Down(..))
import Data.Word (Word32)
import qualified Data.ByteString as B
import qualified Data.Map.Strict as M
import Data.Maybe (isJust)
import Wolf.Media
import Wolf.Types
import Wolf.Level
import Wolf.Raycast

screenWidth, screenHeight :: Int
screenWidth = 320
screenHeight = 200
rgb :: Int -> Int -> Int -> Word32
rgb r g b = 0xff000000 .|. shiftL (fromIntegral r) 16 .|. shiftL (fromIntegral g) 8 .|. fromIntegral b

render :: World -> UArray Int Word32
render = renderWith Nothing

renderWith :: Maybe Graphics -> World -> UArray Int Word32
renderWith graphics w = runSTUArray $ do
  buffer <- newArray (0,screenWidth*screenHeight-1) 0
  let pixel x y c = when (x>=0 && x<screenWidth && y>=0 && y<screenHeight) $
                     writeArray buffer (y*screenWidth+x) c
      rect x y width height c = forM_ [max 0 y..min (screenHeight-1) (y+height-1)] $ \j ->
        forM_ [max 0 x..min (screenWidth-1) (x+width-1)] $ \i -> pixel i j c
  forM_ [0..screenHeight-1] $ \y ->
    rect 0 y screenWidth 1 (if y<100 then rgb 35 39 49 else rgb 58 53 46)
  forM_ (zip [0..] rays) $ \(x,h) -> do
    let depth = max 0.05 (hitDistance h)
        height = min 4000 (floor (160/depth))
        top = 100-height `div` 2
        isDoor = tileAt (level w) (hitCell h) == Door
        isElevator = tileAt (level w) (hitCell h) == Elevator
        shade = (if hitSide h == Vertical then 1 else 0.72) / (1+depth*0.075)
    forM_ [max 0 top..min 199 (top+height)] $ \y -> do
      let u = floor (hitU h*64) :: Int
          v = ((y-top)*64) `div` max 1 height
          mortar = v `mod` 16 < 2 || (u + (v `div` 16 `mod` 2)*16) `mod` 32 < 2
          (r,g,b) | isElevator = (40,190,80)
                  | isDoor = if u `mod` 16 < 2 then (60,44,25) else (157,112,48)
                  | mortar = (55,57,61)
                  | otherwise = (128,139,150)
      case wallPicture h of
        Just pic -> pixel x y (pictureAt pic u v)
        Nothing -> pixel x y (rgb (floor (r*shade)) (floor (g*shade)) (floor (b*shade)))
  -- All billboards share painter order and wall-depth clipping. Transparent
  -- sprite pixels never touch the framebuffer, preserving scenery behind them.
  forM_ sprites $ \(depth,lateral,sprite,generic) -> when (depth>0.1) $ do
    let size = min 2000 (floor (160/depth))
        centerX = floor (160 + 160*lateral/(0.66*depth))
        pic = graphics >>= M.lookup sprite . spritePictures
        width = if isJust pic then max 1 size else max 1 (size `div` 2)
        left = centerX-width `div` 2
        top = 100-size `div` 2
    forM_ [max 0 left..min 319 (left+width-1)] $ \x -> when (depth < depths ! x) $
      forM_ [max 0 top..min 199 (top+size-1)] $ \y -> do
        let u = fromIntegral (x-left)/fromIntegral width :: Double
            v = fromIntegral (y-top)/fromIntegral (max 1 size) :: Double
            headShape = (u-0.5)^ (2::Int)*8 + (v-0.17)^ (2::Int)*35 < 1
            body = v>0.3 && v<0.75 && u>0.12 && u<0.88
            legs = v>=0.75 && (u<0.4 || u>0.6) && u>0.18 && u<0.82
        case pic of
          Just texture -> do
            let color = pictureAt texture (floor (u*64)) (floor (v*64))
            when (color/=0) (pixel x y color)
          Nothing -> when (generic && (headShape || body || legs)) $ pixel x y
            (if headShape then rgb 207 162 116 else if legs then rgb 45 42 38 else rgb 123 103 54)
  case graphics >>= M.lookup (if muzzle w>0 then 423 else 421) . spritePictures of
    Just pistol -> forM_ [0..127] $ \y -> forM_ [0..127] $ \x -> do
      let color = pictureAt pistol (x `div` 2) (y `div` 2)
      when (color/=0) (pixel (96+x) (72+y) color)
    Nothing -> do
      rect 146 159 28 41 (rgb 50 53 58)
      rect 152 148 16 40 (rgb 95 99 107)
      when (muzzle w>0) $ do
        rect 148 135 24 12 (rgb 255 185 40)
        rect 156 130 8 22 (rgb 255 245 167)
  rect 156 100 9 1 (rgb 230 230 220)
  rect 160 96 1 9 (rgb 230 230 220)
  rect 7 187 104 9 (rgb 20 20 20)
  rect 9 189 (max 0 (health w)) 5 (rgb 175 40 35)
  let ((minX,minY),(maxX,maxY)) = bounds (tiles (level w))
      mapScale = max 1 (min 3 (64 `div` max (maxX-minX+1) (maxY-minY+1)))
  forM_ [minX..maxX] $ \x -> forM_ [minY..maxY] $ \y ->
    rect (5+(x-minX)*mapScale) (5+(y-minY)*mapScale) mapScale mapScale (case tileAt (level w) (x,y) of
      Wall -> rgb 120 125 130
      Door -> if solidAt w (x,y) then rgb 165 115 40 else rgb 50 70 50
      Elevator -> rgb 40 210 90
      Exit -> rgb 40 210 90
      Floor -> rgb 25 27 30)
  let Vec px py = player w
  rect (5+floor ((px-fromIntegral minX)*fromIntegral mapScale)) (5+floor ((py-fromIntegral minY)*fromIntegral mapScale)) 2 2 (rgb 255 250 180)
  when (outcome w /= Playing) $
    rect 112 8 96 6 (if outcome w==Won then rgb 40 220 80 else rgb 230 40 40)
  pure buffer
  where
    f = heading (angle w)
    right = heading (angle w+pi/2)
    rays = [castRay w (player w) (add f (scale (0.66*(2*(fromIntegral x+0.5)/320-1)) right))
           | x<-[0::Int ..319]]
    depths = listArray (0,319) (map hitDistance rays)
    wallPicture h = do
      media <- graphics
      codes <- wallCodes (level w)
      let code = if inRange (bounds codes) (hitCell h) then codes ! hitCell h else 1
          side = if hitSide h==Vertical then 1 else 0
          door = tileAt (level w) (hitCell h)==Door
          index | door = doorTexture media + (if code>=100 then 4 else if code>=92 then 6 else 0) + side
                | otherwise = max 0 ((code-1)*2+side)
      M.lookup index (wallPictures media)
    frame g
      | guardMode g==Dead = maybe (guardSprite g) fst (lookup (guardSprite g) states)
      | guardCooldown g>1.05 = maybe (guardSprite g) snd (lookup (guardSprite g) states)
      | otherwise = guardSprite g
    states = [(50,(95,96)),(99,(134,135)),(138,(183,184)),(188,(233,234)),
              (238,(284,285)),(296,(303,300)),(307,(316,311)),(319,(333,327)),
              (334,(341,338)),(360,(369,364)),(385,(392,389)),(395,(407,400))]
    entities = [(guardPos g,frame g,guardMode g/=Dead) | g<-guards w,
                  guardMode g/=Dead || isJust graphics] ++
               [(p,s,False) | (p,s)<-decorations (level w)]
    sprites = sortOn (Down . first) [(dot v f,dot v right,s,generic) | (p,s,generic)<-entities,
                                    let v = sub p (player w)]
    first (d,_,_,_) = d

-- | Headless artifact: exactly the same renderer used by the windowed game.
writePPM :: FilePath -> World -> IO ()
writePPM = writePPMWith Nothing

writePPMWith :: Maybe Graphics -> FilePath -> World -> IO ()
writePPMWith graphics path w = B.writeFile path $ B.concat
  [B.pack (map (fromIntegral . fromEnum) "P6\n320 200\n255\n"),
   B.pack [fromIntegral ((p `shiftR` s) .&. 255) | p<-elems (renderWith graphics w), s<-[16,8,0]]]
