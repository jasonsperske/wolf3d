# Wolf in Haskell: a teaching edition

This branch explores how a small Wolfenstein-style engine looks in Haskell. It is a new educational implementation inspired by the systems in the original source beside it. It is **not Carmack's unreleased experiment**, a line-by-line translation, or a compatible replacement for the original executable.

The game rules, raycaster, renderer, level validation, and AI are Haskell. A small C adapter connects the game to SDL2. No original game data, artwork, or sound files are required: the level and graphics are procedural.

## Build and play

Requirements: GHC (tested with 9.10.3), GNU Make, a C compiler, and SDL2 development headers/libraries. The Haskell libraries used (`base`, `array`, `containers`, `bytestring`) ship with ordinary GHC installations. There are no Hackage downloads in the Make build.

On Debian/Ubuntu, install the prerequisites with:

```sh
sudo apt install ghc make gcc libsdl2-dev
cd haskell
make
./build/wolf-haskell
```

On macOS, install GHC, Make, and SDL2 through your preferred package manager, then run the same Make commands. This path has not been tested here. Native Windows build instructions are not supplied; the included build is aimed at Linux and macOS.

Cabal metadata is also provided for editors and Cabal users:

```sh
cabal build
cabal test
cabal run wolf-haskell
```

Cabal requires `pkg-config` and may need its package index initialized. The Make workflow is the verified build path.

| Control | Action |
|---|---|
| W / S or up / down | Forward / backward |
| A / D | Strafe left / right |
| Left / right arrows | Turn |
| E | Open the door directly ahead, within reach |
| Space | Fire; holding repeats at a limited rate |
| R | Restart |
| Escape | Quit |

Find the green exit in the lower right of the minimap. Gold cells are doors; approach and press E, then wait roughly half a second. Guards pursue and shoot when they can see you. Aim the crosshair at a guard and fire. Health is shown at the bottom and in the window title; victory/defeat appears in the title and as a green/red strip. Ammo is unlimited. You can escape without killing every guard.

## Learn the implementation

Read [the design walkthrough](docs/DESIGN.md), then [the Haskell tradeoffs](docs/HASKELL-TRADEOFFS.md). Suggested source order:

1. `src/Wolf/Types.hs`: the vocabulary, vectors, explicit game states.
2. `src/Wolf/Level.hs`: validated map data and safe boundary lookup.
3. `src/Wolf/Raycast.hs`: the grid DDA algorithm and visibility queries.
4. `src/Wolf/Simulation.hs`: one pure tick, movement, doors, shooting, AI.
5. `src/Wolf/Render.hs`: camera projection, depth, sprites, local mutation.
6. `app/Main.hs` and `cbits/platform.c`: time, input, pixels, resource lifetime.
7. `test/Main.hs`: executable examples of the core contracts.

## Verify without playing

```sh
make test       # Pure core checks: no SDL or display needed
make snapshot   # build/demo.ppm, rendered by the actual game renderer
make smoke      # Initialize SDL, upload one frame, clean up; dummy video driver
```

`./build/wolf-haskell --snapshot other.ppm` runs without initializing SDL, though the executable still links against SDL2. `--smoke` checks the platform adapter but does not exercise a physical keyboard. For runtime allocation statistics, use `./build/wolf-haskell +RTS -s` and quit normally.

## Scope and intentional differences

Implemented: textured grid walls, perpendicular-depth projection, occluded billboard guards, player collision and wall sliding, opening doors, simple pursuit and line-of-sight attacks, hitscan shooting and cooldowns, health, death, exit victory, restart, a minimap, fixed simulation ticks, and headless checks.

Not implemented: original map/asset formats, original level layouts, sound, menus, multiple weapons, ammunition/pickups, pushwalls/secrets, exact enemy state machines, saves, or demo compatibility. Doors become passable as whole tiles after a delay and stay open. Guards use direct pursuit and can overlap; they do not pathfind around obstacles. Rendering is 320×200 scaled to the window, without floor textures. The minimap is intentionally sized for the included 16×13 level.

The original DOS sources and their existing license text remain in place. This addition does not change or replace the repository's licensing terms.
