module Wolf.Simulation (step, canStand, moveBody) where

import Data.List (minimumBy)
import Data.Ord (comparing)
import qualified Data.Map.Strict as M
import Wolf.Types
import Wolf.Level
import Wolf.Raycast

-- | Fixed 1/60 s ticks are supplied by the shell. Clamp for defensive callers;
-- large elapsed times must be split into ticks to avoid tunnelling through walls.
-- C counterparts: [PlayLoop](../../../WOLFSRC/WL_PLAY.C#L1368) orders doors,
-- actors, and rendering; [ControlMovement](../../../WOLFSRC/WL_AGENT.C#L149)
-- and [Thrust](../../../WOLFSRC/WL_AGENT.C#L928) handle player movement.
-- This is a pure, fixed-60-Hz redesign, not the original global/tics update loop.
step :: Double -> Input -> World -> World
step elapsed input old
  | outcome old /= Playing = old
  | otherwise = finish $ updateGuards dt $ shoot input $ openDoor input moved
  where
    dt = max 0 (min (1/60) elapsed)
    animated = old { doors = M.map advance (doors old),
                     shotCooldown = max 0 (shotCooldown old-dt),
                     muzzle = max 0 (muzzle old-dt) }
    -- C reference: [DoorOpening](../../../WOLFSRC/WL_ACT1.C#L554) and
    -- [MoveDoors](../../../WOLFSRC/WL_ACT1.C#L686). We retain the state progression,
    -- but omit area connectivity, partial door geometry, and automatic closing.
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
-- C reference: [TryMove](../../../WOLFSRC/WL_AGENT.C#L801) checks the tiles
-- overlapped by the player's footprint. Its additional actor-collision checks
-- are intentionally absent here; our body size and numeric representation differ.
canStand :: World -> Vec -> Bool
canStand w (Vec x y) = all (not . solidAt w)
  [(i,j) | i<-[floor (x-r)..floor (x+r)], j<-[floor (y-r)..floor (y+r)]]
  where r = 0.20

-- Axis separation gives wall sliding; see ClipMove in WL_AGENT.C.
-- C reference: [ClipMove](../../../WOLFSRC/WL_AGENT.C#L866). The original tries
-- the complete displacement before its x-only/y-only fallbacks; this version
-- always resolves x then y, so corner behavior is similar but not identical.
moveBody :: World -> Vec -> Vec -> Vec
moveBody w p@(Vec x y) (Vec dx dy) =
  let px = Vec (x+dx) y
      q@(Vec qx _) = if canStand w px then px else p
      py = Vec qx (y+dy)
  in if canStand w py then py else q

-- C references: [Cmd_Use](../../../WOLFSRC/WL_AGENT.C#L1008),
-- [OperateDoor](../../../WOLFSRC/WL_ACT1.C#L498), and
-- [OpenDoor](../../../WOLFSRC/WL_ACT1.C#L400). Our short use ray replaces the
-- original adjacent-tile/direction checks; locks and pushwalls are not simulated.
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
-- C reference: [GunAttack](../../../WOLFSRC/WL_AGENT.C#L1168) selects a nearby
-- on-screen target and checks visibility before applying damage. Here the aim
-- strip is in world space and one hit kills; original damage rolls are omitted.
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
-- Conceptual C counterparts: [T_Chase](../../../WOLFSRC/WL_ACT2.C#L3069),
-- [T_Shoot](../../../WOLFSRC/WL_ACT2.C#L3444), and
-- [SightPlayer](../../../WOLFSRC/WL_STATE.C#L1404). This deliberately replaces
-- their richer state machines, tile navigation, and hit chances with direct pursuit.
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
