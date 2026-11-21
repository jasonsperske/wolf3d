module Main (main) where
import Control.Monad (unless)
import Data.Array.Unboxed (elems)
import qualified Data.Map.Strict as M
import System.Exit (die)
import Wolf.Types
import Wolf.Level
import Wolf.Raycast
import Wolf.Simulation
import Wolf.Render
import Wolf.Audio

assert :: String -> Bool -> IO ()
assert label ok = unless ok (die ("FAIL: "++label))
near :: Double -> Double -> Bool
near a b = abs (a-b)<1e-8
isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _ = False
fixture :: [String] -> IO World
fixture rows = either die (pure . initialWorld) (parseLevel rows)
ticks :: Int -> Input -> World -> World
ticks n input w = iterate (step (1/60) input) w !! n

main :: IO ()
main = do
  assert "empty level rejected" (isLeft (parseLevel []))
  assert "ragged level rejected" (isLeft (parseLevel ["#####","#P.E#","####"]))
  assert "open boundary rejected" (isLeft (parseLevel ["##.##","#P.E#","#####"]))
  assert "duplicate spawn rejected" (isLeft (parseLevel ["######","#PPE.#","######"]))
  assert "unknown tile rejected" (isLeft (parseLevel ["#####","#PXE#","#####"]))
  assert "missing exit rejected" (isLeft (parseLevel ["#####","#P..#","#####"]))
  w <- fixture ["########", "#P....E#", "#......#", "########"]
  let h = castRay w (player w) (Vec 1 0)
  assert "axis aligned DDA" (near (hitDistance h) 5.5 && hitCell h==(7,1))
  assert "negative DDA" (near (hitDistance (castRay w (player w) (Vec (-1) 0))) 0.5)
  assert "perpendicular depth scales with ray direction" (near (hitDistance (castRay w (player w) (Vec 2 0))) 2.75)
  assert "zero ray terminates" (hitDistance (castRay w (player w) (Vec 0 0))==1e9)
  assert "outside lookup is solid" (solidAt w (-1,0))
  assert "body footprint blocks near wall" (not (canStand w (Vec 1.1 1.5)))
  let blocked = ticks 120 (noInput { forward = -1 }) w
  assert "movement cannot cross wall" (canStand blocked (player blocked) && cell (player blocked)==(1,1))
  let slid = moveBody w (Vec 1.25 1.5) (Vec (-0.1) 0.1)
  assert "wall sliding" (slid == Vec 1.25 1.6)
  assert "oversized timestep is clamped" (step 5 noInput w == step (1/60) noInput w)
  let Vec replayX replayY = player (ticks 60 (noInput {forward=1}) w)
  assert "60 fixed ticks move 2.5 tiles" (near replayX 4 && near replayY 1.5)
  d <- fixture ["#######", "#PD.GE#", "#######"]
  assert "closed door occludes guard" (not (visible d (player d) (Vec 4.5 1.5)))
  let opening = step (1/60) (noInput {use=True}) d
  assert "use starts opening" (M.lookup (2,1) (doors opening)==Just (Opening 0))
  assert "opening emits door sound once" (18 `elem` soundEvents d opening && 18 `notElem` soundEvents opening (step (1/60) (noInput {use=True}) opening))
  assert "opening remains solid" (solidAt opening (2,1))
  let opened = ticks 40 noInput opening
  assert "door becomes traversable" (not (solidAt opened (2,1)))
  assert "open door reveals guard" (all (visible opened (player opened) . guardPos) (guards opened))
  let shotBlocked = step (1/60) (noInput {fire=True}) d
  assert "cannot shoot through door" (all ((/=Dead) . guardMode) (guards shotBlocked))
  s <- fixture ["########", "#P.G.GE#", "########"]
  let fired = step (1/60) (noInput {fire=True}) s
  assert "only nearest guard hit" (map guardMode (guards fired)==[Dead,Chasing])
  assert "shot emits original pistol sound" (24 `elem` soundEvents s fired)
  let again = step (1/60) (noInput {fire=True}) fired
  assert "weapon cooldown" (length (filter ((==Dead) . guardMode) (guards again))==1)
  assert "cooldown does not re-emit pistol sound" (24 `notElem` soundEvents fired again)
  let killed = step (1/60) (noInput {fire=True}) (ticks 20 noInput fired)
  assert "dead guards do not block shots" (all ((==Dead) . guardMode) (guards killed))
  single <- fixture ["######", "#P.GE#", "######"]
  let attacked = step (1/60) noInput single
  assert "guard attack damages health" (health attacked==92)
  assert "guard cooldown limits damage" (health (step (1/60) noInput attacked)==92)
  let lost = step (1/60) noInput (single {health=1})
  assert "death transition" (outcome lost==Lost && health lost==0)
  assert "terminal state frozen" (step (1/60) (noInput {fire=True}) lost==lost)
  let won = ticks 130 (noInput {forward=1}) w
  assert "exit triggers win" (outcome won==Won)
  assert "wall depth hides guard sprites" (render d == render (d {guards=[]}))
  assert "visible guard draws a sprite" (render s /= render (s {guards=[]}))
  let frame = elems (render w)
  assert "frame size" (length frame==screenWidth*screenHeight)
  assert "renderer draws more than background" (case frame of [] -> False; p:_ -> length (filter (/=p) frame)>1000)
  assert "camera rotation changes frame" (render w /= render (w {angle=pi/2}))
  putStrLn "All core checks passed."
