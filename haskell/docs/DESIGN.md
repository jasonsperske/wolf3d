# Design walkthrough

## 1. Follow a single frame

`Main.loop` reads SDL input into an `Input` record, measures elapsed time, and runs zero or more 1/60-second simulation steps. It renders the resulting `World`, copies packed pixels into an FFI buffer, and asks SDL to present them. The reusable pixel buffer is allocated outside the loop and cleaned up when the loop exits.

The two central interfaces are:

```haskell
step   :: Double -> Input -> World -> World
render :: World -> UArray Int Word32
```

Neither performs IO. They cannot read a keyboard, fetch time, or secretly mutate a global player. Given the same inputs, they produce the same result. The SDL boundary contains the effects. This makes a small headless test harness useful rather than a separate imitation of the game.

`World` holds a reference to the immutable `Level`, player position/orientation, guards, doors, health, and transient cooldowns. Updating a record shares unchanged values; it does not deep-copy the map. Strict fields force scalar results as the next world is built. They do not recursively force an entire list: guard lists still require care if the engine grows.

## 2. Coordinates and maps

One map cell is one world unit. Integer coordinates index tiles; the center of cell `(x,y)` is `(x+0.5,y+0.5)`. Positive x points right/east; positive y points down/south. Angle zero faces east, and increasing the angle turns toward south. `heading a` is `(cos a, sin a)`.

The parser accepts `#` walls, `.` floors, `P` player, `G` guards, `D` or `+` doors, and `E` exits. It rejects uneven rows, unknown characters, open boundaries, incorrect player counts, and missing exits. These checks establish structure, not reachability: a valid map can still contain an unreachable exit. Positions are removed from the tile layer and stored separately.

`tileAt` returns a wall outside the map. That single convention makes rays and collision safe at the boundary. Keep production worlds behind the validated constructor if exposing this as a library; the teaching modules currently export record constructors for easy experiments.

## 3. Trace a ray through the grid

A ray is `origin + t * direction`. Digital differential analysis (DDA) tracks how far the ray must travel to reach its next vertical and horizontal grid boundary. Each iteration crosses whichever boundary has the smaller parameter, then checks the cell it entered. The parameter increment between vertical boundaries is `abs (1/dx)`; the horizontal increment is `abs (1/dy)`.

For an axis-aligned ray, the unused increment is positive infinity. A separate zero-component branch prevents `0 * infinity` from making NaNs at a boundary. A completely zero direction has a defined no-hit sentinel. Normal callers supply finite coordinates and directions; this is not a general-purpose API hardened against arbitrary NaN inputs.

For each screen column, the renderer builds:

```text
forward = heading angle
right   = heading (angle + pi/2)
ray     = forward + right * (0.66 * cameraX)
```

The center-sampled `cameraX` ranges almost from -1 to +1. These rays deliberately are **not normalized**. Their forward component is one, so the returned parameter `t` is camera-perpendicular depth. Projected wall height is `160 / t`. Using Euclidean ray length here would create the familiar curved-wall/fisheye distortion. The camera plane factor 0.66 gives about a 67-degree horizontal field of view; vertical projection is independently chosen for the retro framebuffer.

DDA also returns the wall side and fractional texture coordinate. The renderer synthesizes a brick pattern from that coordinate and the vertical position in the wall slice. Horizontal faces are shaded more darkly; depth reduces brightness. There is no texture file decoder to obscure this lesson.

`visible` reuses DDA with a **normalized** direction. In that case `t` is Euclidean distance, which can be compared directly to the target distance.

## 4. Move and interact

`step` advances doors and cooldowns, moves the player, processes door use, processes shooting, updates guards, then resolves death or victory. That ordering is intentional: a guard killed this tick cannot fire back later in the same tick. Death wins over reaching the exit on a tick that causes both.

Movement combines forward and strafe vectors, limiting diagonal movement to the same speed as straight movement. A player has an axis-aligned 0.4×0.4 footprint. `canStand` checks every tile overlapped by that footprint. `moveBody` attempts x and then y separately, letting the body slide along a wall when one component is blocked. The axis ordering introduces a small asymmetry at corners; it is an explicit simplicity tradeoff.

The normal displacement is small relative to a tile. `step` clamps caller-supplied time to 1/60 second to prevent large steps from tunnelling. It does not consume the remainder of a large requested timestep: the shell is responsible for splitting elapsed time into ticks. The shell limits catch-up to 250 milliseconds so returning from a long pause does not run thousands of updates.

A use ray finds a door within 1.35 units. Its state changes from `Closed` to `Opening progress` to `Open`. Repeated use does not reset progress. Until fully open it remains an opaque, solid tile. There is no partial door geometry or closing/crushing rule; the opening delay is not visually interpolated. This keeps collision and raycasting in agreement with very little code.

## 5. Combat and enemies

A shot filters living guards to those ahead of the player, within a 0.28-unit lateral aim tolerance, and visible through the map. It kills the nearest eligible guard. This is a simplified hitscan strip, not a full ray/sprite intersection or an angular cone. The cooldown limits firing to roughly three shots per second; muzzle flash uses a separate timer.

Each guard is `Idle`, `Chasing`, or `Dead`. A living guard that sees the player within eight units starts chasing. It moves directly toward the player until within two units, using the same wall collision as the player. If it sees the player within four units and its attack cooldown expires, it deals eight damage. It retains pursuit after losing sight, using the player's current position; realistic last-seen memory and navigation are useful extensions. Guards do not collide with one another or block player movement.

The update returns each new guard plus its damage. Summing the damage avoids hidden mutation of player health during traversal. The order of guards therefore does not change their movement or damage calculations. This is particularly easy to test in Haskell.

## 6. Paint sprites and pixels

Walls produce a per-column depth buffer. Each living guard is transformed into forward depth and lateral camera coordinates, then projected into a billboard. Sprites are drawn farthest first. Each column checks the wall depth before drawing, so walls correctly hide guards. A procedural silhouette replaces original artwork. Dead guards disappear.

The framebuffer is an unboxed array of packed ARGB words. Constructing a fresh immutable array for every individual pixel write would be impractical. `runSTUArray` allows local in-place writes and returns an immutable result. Its type prevents the mutable reference escaping. This is real mutation with a restricted lifetime, not a promise that mutation is always unnecessary.

At the boundary, `elems` plus `pokeArray` copies the frame into foreign memory. It is easy to follow but allocates a list and incurs a copy. A production renderer should consider pinned storage or a scoped SDL texture lock after measuring the cost. A pure result is convenient; it is not free.

## 7. Compare with the original sources

These are conceptual correspondences, not claims of algorithmic or behavior compatibility:

| Original source | Haskell counterpart | What changed |
|---|---|---|
| `WOLFSRC/WL_AGENT.C`: `ClipMove`, `Thrust` | `Simulation.moveBody`, `step` | Record values and doubles replace global object mutation and fixed-point motion. |
| `WOLFSRC/WL_DRAW.C`: `ThreeDRefresh`, `TransformActor` | `Render.render`, sprite projection | One readable software renderer replaces VGA/scaling machinery. |
| `WOLFSRC/WL_ACT1.C`: `MoveDoors`, opening states | `DoorState`, `openDoor`, `step` | Algebraic states and whole-tile delayed opening simplify geometry. |
| `WOLFSRC/WL_STATE.C` and `WL_ACT2.C` | `updateGuards` | Three states and direct pursuit replace the richer actor system. |
| `WOLFSRC/ID_IN.C`, `ID_VL.C` | `Main`, `platform.c` | SDL owns modern window/input presentation. |
| `WOLFSRC/ID_CA.C`, `ID_PM.C`, `ID_MM.C` | `Level`, managed arrays | Embedded map and procedural art avoid original asset/cache formats. |

The original hardware constraints shaped much of its complexity. Removing DOS, segmented memory, VGA, and asset compatibility explains a large part of the reduction in code. Do not attribute that entire reduction to Haskell.

## 8. Exercises that preserve the architecture

Add one change at a time and keep the pure interfaces:

1. Add a pickup tile and test that walking over it restores health only once.
2. Add a `Closing` door state, then decide how to prevent a door closing on a body.
3. Add last-seen positions and grid pathfinding to guard state.
4. Replace procedural colors with a tiny in-memory texture atlas.
5. Store and replay a list of `Input` values, one per fixed tick. Current display-frame input sampling is not itself an event recording format.
6. Profile before replacing list-backed guard traversal or the framebuffer copy.

Supporting original maps and resources would be a separate substantial project: binary parsing, decompression, sprite/texture decoding, exact state machines, and compatibility tests. It should build on this core rather than be implied by it.
