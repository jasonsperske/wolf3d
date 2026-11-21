-- | Shared vocabulary. Strict fields keep each frame from retaining chains of
-- unevaluated arithmetic. Constructors describe alternatives, not magic flags.
module Wolf.Types where

import Data.Array (Array)
import qualified Data.Map.Strict as M

data Vec = Vec !Double !Double deriving (Eq, Show)
add, sub :: Vec -> Vec -> Vec
add (Vec x y) (Vec u v) = Vec (x+u) (y+v)
sub (Vec x y) (Vec u v) = Vec (x-u) (y-v)
scale :: Double -> Vec -> Vec
scale k (Vec x y) = Vec (k*x) (k*y)
dot :: Vec -> Vec -> Double
dot (Vec x y) (Vec u v) = x*u+y*v
magnitude :: Vec -> Double
magnitude v = sqrt (dot v v)
unit :: Vec -> Vec
unit v = scale (1 / max 1e-9 (magnitude v)) v
heading :: Double -> Vec
heading a = Vec (cos a) (sin a)
cell :: Vec -> (Int,Int)
cell (Vec x y) = (floor x, floor y)

data Tile = Floor | Wall | Door | Exit | Elevator deriving (Eq, Show)
-- C data counterparts: [gametype](../../../WOLFSRC/WL_DEF.H#L734),
-- [objtype](../../../WOLFSRC/WL_DEF.H#L676), and the global tilemap/actorat grids
-- used by [SetupGameLevel](../../../WOLFSRC/WL_GAME.C#L625). These records are
-- deliberately smaller models, not binary-compatible copies of those structs.
data Level = Level { tiles :: !(Array (Int,Int) Tile), spawn :: !Vec,
                     spawnAngle :: !Double,
                     guardSpawns :: ![(Vec,Int)],
                     wallCodes :: !(Maybe (Array (Int,Int) Int)),
                     decorations :: ![(Vec,Int)] } deriving (Eq, Show)
-- Progress lives inside the state that needs it. Open doors never have a
-- nonsensical animation fraction. Doors stay open in this teaching edition.
-- C counterpart: [doorobj_t](../../../WOLFSRC/WL_DEF.H#L641) stores an action
-- enum and tic count. Progress is attached only to Opening here; Closing is omitted.
data DoorState = Closed | Opening !Double | Open deriving (Eq, Show)
-- Compare [statetype](../../../WOLFSRC/WL_DEF.H#L609)'s think/action callbacks
-- and next-state pointer. Three constructors replace that full actor-state graph.
data GuardMode = Idle | Chasing | Dead deriving (Eq, Show)
data Guard = Guard { guardPos :: !Vec, guardMode :: !GuardMode,
                     guardCooldown :: !Double, guardSprite :: !Int } deriving (Eq, Show)
data Outcome = Playing | Won | Lost deriving (Eq, Show)
data World = World { level :: !Level, player :: !Vec, angle :: !Double,
                     health :: !Int, doors :: !(M.Map (Int,Int) DoorState),
                     guards :: ![Guard], shotCooldown :: !Double,
                     muzzle :: !Double, outcome :: !Outcome } deriving (Eq, Show)
-- This value is also the replay/test interface. IO never appears in step.
-- C counterpart: [PollControls](../../../WOLFSRC/WL_PLAY.C#L455) updates global
-- controlx/controly/buttonstate; this value carries those responsibilities explicitly.
data Input = Input { forward :: !Double, strafe :: !Double, turn :: !Double,
                     use :: !Bool, fire :: !Bool } deriving (Eq, Show)
noInput :: Input
noInput = Input 0 0 0 False False
