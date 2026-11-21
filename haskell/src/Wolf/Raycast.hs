module Wolf.Raycast (Hit(..), Side(..), castRay, visible) where

import Wolf.Types
import Wolf.Level

data Side = Vertical | Horizontal deriving (Eq, Show)
data Hit = Hit { hitDistance :: !Double, hitCell :: !(Int,Int),
                 hitSide :: !Side, hitU :: !Double } deriving (Eq, Show)

-- | Grid DDA visits one boundary at a time, rather than sampling tiny steps.
-- Return parameter t in origin + t*direction, NOT Euclidean distance. Camera
-- rays have a forward component of 1, so t is already perpendicular depth.
-- Original rendering path: [ThreeDRefresh](../../../WOLFSRC/WL_DRAW.C#L1336)
-- reaches the grid traversal in [AsmRefresh](../../../WOLFSRC/WL_DR_A.ASM#L185).
-- That hot loop is assembly, not C. This DDA is a new Double-based formulation;
-- compare its returned depth with [CalcHeight](../../../WOLFSRC/WL_DRAW.C#L359),
-- rather than expecting the original fixed-point stepping or door intersections.
castRay :: World -> Vec -> Vec -> Hit
castRay w origin@(Vec ox oy) (Vec dx dy)
  | magnitude (Vec dx dy) < 1e-12 = Hit 1e9 (cell origin) Vertical 0
  | solidAt w (cell origin) = Hit 0 (cell origin) Vertical 0
  | otherwise = walk mx my tx ty
  where
    (mx,my) = cell origin
    sx = if dx < 0 then -1 else 1
    sy = if dy < 0 then -1 else 1
    delta d = if abs d < 1e-12 then 1/0 else abs (1/d)
    ddx = delta dx
    ddy = delta dy
    edge o m s d = if abs d < 1e-12 then 1/0 else
      (fromIntegral (if s>0 then m+1 else m)-o)/d
    tx = edge ox mx sx dx
    ty = edge oy my sy dy
    walk x y ax ay
      | ax < ay = visit (x+sx) y ax Vertical (ax+ddx) ay
      | otherwise = visit x (y+sy) ay Horizontal ax (ay+ddy)
    visit x y t side ax ay
      | solidAt w (x,y) =
          let coord = case side of Vertical -> oy+t*dy; Horizontal -> ox+t*dx
          in Hit t (x,y) side (coord-fromIntegral (floor coord :: Int))
      | otherwise = walk x y ax ay

-- C counterpart: [CheckLine](../../../WOLFSRC/WL_STATE.C#L1037) performs a
-- separate grid visibility trace. We reuse castRay instead, with the teaching
-- engine's whole-tile door rule rather than the original partial-door test.
visible :: World -> Vec -> Vec -> Bool
visible w a b = let v = sub b a; d = magnitude v
                in d < 1e-9 || hitDistance (castRay w a (unit v)) >= d-0.05
