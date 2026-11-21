module Wolf.Simulation (step, canStand, moveBody) where

import Data.List (minimumBy)
import Data.Ord (comparing)
import qualified Data.Map.Strict as M
import Wolf.Types
import Wolf.Level
import Wolf.Raycast

-- | Fixed 1/60 s ticks are supplied by the shell. Clamp for defensive callers;
-- large elapsed times must be split into ticks to avoid tunnelling through walls.
step :: Double -> Input -> World -> World
step elapsed input old
  | outcome old /= Playing = old
  | otherwise = finish $ updateGuards dt $ shoot input $ openDoor input moved
  where
    dt = max 0 (min (1/60) elapsed)
    animated = old { doors = M.map advance (doors old),
                     shotCooldown = max 0 (shotCooldown old-dt),
                     muzzle = max 0 (muzzle old-dt) }
    advance (Opening t) | t+dt*1.8 >= 1 = Open
                        | otherwise = Opening (t+dt*1.8)
    advance d = d
    a = angle old + clamp (turn input)*dt*2.3
    wish = add (scale (clamp (forward input)) (heading a))
               (scale (clamp (strafe input)) (heading (a+pi/2)))
    velocity = scale (2.5*dt / max 1 (magnitude wish)) wish
    moved = animated { angle = atan2 (sin a) (cos a),
                       player = moveBody animated (player old) velocity }
    clamp = max (-1) . min 1
    finish w | health w <= 0 = w { health = 0, outcome = Lost }
             | tileAt (level w) (cell (player w)) == Exit = w { outcome = Won }
             | otherwise = w

-- | A small axis-aligned body, not just a point. Check every overlapped tile.
canStand :: World -> Vec -> Bool
canStand w (Vec x y) = all (not . solidAt w)
  [(i,j) | i<-[floor (x-r)..floor (x+r)], j<-[floor (y-r)..floor (y+r)]]
  where r = 0.20

-- Axis separation gives wall sliding; see ClipMove in WL_AGENT.C.
moveBody :: World -> Vec -> Vec -> Vec
moveBody w p@(Vec x y) (Vec dx dy) =
  let px = Vec (x+dx) y
      q@(Vec qx _) = if canStand w px then px else p
      py = Vec qx (y+dy)
  in if canStand w py then py else q

openDoor :: Input -> World -> World
openDoor input w
  | use input && hitDistance h < 1.35 && tileAt (level w) (hitCell h) == Elevator =
      w { outcome = Won }
  | use input && hitDistance h < 1.35 && tileAt (level w) (hitCell h) == Door =
      w { doors = M.insertWith (\_ existing -> existing) (hitCell h) (Opening 0) (doors w) }
  | otherwise = w
  where h = castRay w (player w) (heading (angle w))

-- Hitscan chooses the closest living guard within a narrow aim strip.
-- Wall visibility is checked independently; corpses cannot absorb bullets.
shoot :: Input -> World -> World
shoot input w
  | not (fire input) || shotCooldown w > 0 = w
  | otherwise = w { guards = [if Just i == target then g { guardMode = Dead } else g
                              | (i,g)<-zip [0::Int ..] (guards w)],
                    shotCooldown = 0.3, muzzle = 0.09 }
  where
    f = heading (angle w)
    candidates = [(i,magnitude v) | (i,g)<-zip [0::Int ..] (guards w),
                  guardMode g /= Dead, let v = sub (guardPos g) (player w),
                  dot v f > 0, abs (cross f v) < 0.28,
                  visible w (player w) (guardPos g)]
    target = case candidates of [] -> Nothing; _ -> Just (fst (minimumBy (comparing snd) candidates))
    cross (Vec x y) (Vec u v) = x*v-y*u

-- Pure traversal returns both the updated guards and their total damage.
-- AI deliberately uses direct pursuit, not a hidden pathfinding subsystem.
updateGuards :: Double -> World -> World
updateGuards _ w | outcome w /= Playing = w
updateGuards dt w = w { guards = map fst results, health = health w-sum (map snd results) }
  where
    results = map update (guards w)
    update g | guardMode g == Dead = (g,0)
    update g =
      let v = sub (player w) (guardPos g)
          d = magnitude v
          sees = d < 8 && visible w (guardPos g) (player w)
          mode = if sees then Chasing else guardMode g
          cooldown = max 0 (guardCooldown g-dt)
          attacking = sees && d < 4 && cooldown <= 0
          p = if mode == Chasing && d > 2 then
                moveBody w (guardPos g) (scale (dt*0.75) (unit v)) else guardPos g
      in (g { guardPos = p, guardMode = mode,
              guardCooldown = if attacking then 1.2 else cooldown }, if attacking then 8 else 0)
