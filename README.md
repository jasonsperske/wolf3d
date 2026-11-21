# Wolf in Haskell: a teaching edition

A playable educational engine inspired by the original source beside it. The
game rules, map/resource decoding, raycaster, and renderer are Haskell. SDL handles
window/input/audio output, and a small native audio mixer uses a replaceable OPL
emulator for original AdLib music and effects. This is not Carmack's unreleased
experiment or an original-game-compatible port.

## Build and run

Requirements: GHC (tested with 9.10.3), GNU Make, a C compiler, Python 3 for
bundling, and SDL2 development headers/libraries. Haskell dependencies ship with
ordinary GHC installations; the Make build does not download Hackage packages.
The OPL emulator source is vendored with its license, so builds need no network.

```sh
sudo apt install ghc make gcc python3 libsdl2-dev
# From the repository root:
make
./haskell/build/wolf-haskell
```

Assets live in the **Git-ignored root `assets/` folder**:

- `assets/shareware/`: your extracted `.WL1` files (already moved here).
- `assets/registered/`: your extracted `.WL6` files, if installed.
- `assets/archives/`: optional original archives; never included in bundles.

The game discovers assets automatically. Development prefers registered data
when that folder exists, otherwise shareware. With no pack, it runs the procedural
demo. Use `--demo` to force that demo, or `--assets /path/to/pack` to override
discovery. Files must be extracted and each folder must contain a single edition.

```sh
./haskell/build/wolf-haskell --level 2
./haskell/build/wolf-haskell --list-levels
./haskell/build/wolf-haskell --no-audio
```

Levels are one-based: the shareware pack contains eight regular floors, boss floor
9, and secret floor 10. Registered maps continue through the remaining episodes.
The supplied shareware files are verified; actual registered data has not been
available for integration testing.

## Bundle a build with your assets

```sh
make bundle
# Or select a particular pack explicitly:
make bundle ASSET_DIR=assets/shareware
make bundle ASSET_DIR=assets/registered
./dist/wolf-haskell/wolf-haskell
```

The output directory contains the executable, original resources in `assets/`,
`libwolfopl.so`, notices, emulator source, and a checksum manifest. Copy the whole
directory; it works from any working directory without `--assets`. The bundle is
ignored by Git and still requires the host SDL2 runtime. This is a Linux bundle
for the build machine's architecture, not a single-file or cross-platform package.

## Controls

| Control | Action |
|---|---|
| W / S or up / down | Forward / backward |
| A / D | Strafe |
| Left / right arrows | Turn |
| E | Open nearby door / activate elevator |
| Space | Fire; holding repeats with cooldown |
| R | Restart level |
| Escape | Quit |

The minimap marks doors in gold and exits/elevators in green. In asset levels,
approach the elevator panel and press E; the demo wins by walking onto the exit.
Health and victory/defeat appear in the window title and HUD. Ammo is unlimited.
There is no automatic floor transition; choose another map with `--level`.

## Learn the design

- [Design walkthrough](haskell/docs/DESIGN.md): follow a frame and compare systems with the DOS code.
- [Haskell tradeoffs](haskell/docs/HASKELL-TRADEOFFS.md): purity, state types, allocation, local mutation, FFI.
- [Map loading](haskell/docs/ASSET-LOADING.md): Carmack/RLEW decompression and gameplay translation.
- [Graphics, audio, and bundling](haskell/docs/MEDIA.md): resource formats, discovery, playback, packaging.

## How to read the code

Start with the procedural demo (`./haskell/build/wolf-haskell --demo`). Its tiny
text map lets you learn movement and rendering before following binary formats.
Keep [the core tests](haskell/test/Main.hs) open alongside the implementation:
they show small worlds, inputs, and expected outcomes without a window or assets.

### A first pass

| Read | Look for |
|---|---|
| [Types.hs](haskell/src/Wolf/Types.hs) | `World`, `Input`, `Level`, and explicit alternatives such as `DoorState` and `Outcome`. These are the vocabulary used everywhere else. |
| [Level.hs](haskell/src/Wolf/Level.hs) | `demoLevel`, `initialWorld`, `tileAt`, and `solidAt`. Notice how safe out-of-bounds lookup gives both collision and rays the same boundary rule. |
| [Simulation.hs](haskell/src/Wolf/Simulation.hs) | `step`: one input and one old world produce one new world. Read the update order before diving into movement, shooting, or guards. |
| [Raycast.hs](haskell/src/Wolf/Raycast.hs) | `castRay`: grid DDA advances to the next cell boundary. The same algorithm supplies wall hits and line-of-sight checks. |
| [Render.hs](haskell/src/Wolf/Render.hs) | `renderWith`: camera rays become wall columns, then depth-tested sprites and the HUD. Local mutation builds the pixels without changing the world. |
| [Main.hs](haskell/app/Main.hs) | `main`, `runMode`, and `loop`: resource loading, fixed simulation ticks, sound events, and presentation connect the pure pieces to IO. |

On this first pass, skip the generated palette values and the vendored OPL
emulator internals. Their interfaces matter more than their implementation when
learning how the game is organized.

### Interesting paths to trace

**A key press becoming movement.** Follow `platform_input` in
[platform.c](haskell/cbits/platform.c), the bitmask-to-`Input` conversion in
`Main.loop`, then `step → moveBody → canStand → solidAt`. Trace a diagonal move
against a wall: input normalization limits diagonal speed, while trying the axes
separately produces wall sliding. The fixed-tick accumulator lives in the shell;
`step` never reads a clock.

**One ray becoming a textured column.** Start with the `rays` binding in
`Render.renderWith`, follow `Raycast.castRay`, and return to `hitDistance`,
`hitU`, and `wallPicture`. Camera rays deliberately are not normalized: their
parameter is perpendicular depth, which avoids fisheye distortion. Compare that
with `Raycast.visible`, which normalizes its ray to compare Euclidean distances.
Then follow the per-column depth buffer into sprite drawing to see how a wall
hides only the covered portion of an enemy.

**A shot becoming both a state change and a sound.** Follow `Simulation.shoot`
through target filtering, visibility, and nearest-target selection. Then follow
`Audio.soundEvents old new → Playback.playSounds → audio_play` in
[audio.c](haskell/cbits/audio.c). The pure simulation changes guard state and
cooldowns; the shell interprets those changes as audio events once per tick.
The cooldown tests demonstrate why holding fire does not emit a shot every tick.

**A door opening across several ticks.** Follow `Simulation.openDoor`, the
`advance` function inside `step`, and `Level.solidAt`. The state moves from
`Closed` to `Opening progress` to `Open`; repeated use preserves progress.
Compare this explicit state transition with the simpler elevator path, which
sets `Won`. Both rendering and collision treat an opening door as solid until
it has finished opening.

**A disk file becoming a level.** Follow
[Pack.hs](haskell/src/Wolf/Pack.hs) for discovery and edition selection, then
[Assets.hs](haskell/src/Wolf/Assets.hs):
`decodeMap → carmackExpand → rlewExpand → toLevel`.
[Binary.hs](haskell/src/Wolf/Binary.hs) supplies checked little-endian reads.
Watch the distinction between bytes and words, overlapping backreferences, and
raw map data versus gameplay translation. The synthetic fixtures in
[AssetMain.hs](haskell/test/AssetMain.hs) make the compression edge cases small
enough to work through by hand.

**A sprite or song leaving its original DOS format.** In
[Media.hs](haskell/src/Wolf/Media.hs), follow `decodeSwap → decodeGraphics` and
`decodeSprite`: column-major textures, transparent sprite posts, and wrapping
16-bit offsets each need different handling. For sound, follow `decodeDigitized`
and [Audio.hs](haskell/src/Wolf/Audio.hs)'s `decodeAudio`/`decodeIMF`, then
[Playback.hs](haskell/src/Wolf/Playback.hs) and the native callback. Music delays,
effect notes, and PCM samples run at different rates. The tests in
[MediaMain.hs](haskell/test/MediaMain.hs) cover opaque black versus transparency,
sparse sound slots, and music metadata that must not be played.

### What to notice about Haskell

Read the type signatures first. `step :: Double -> Input -> World -> World`
makes the simulation's dependencies explicit; a new record shares unchanged
parts of the old world. Constructors and pattern matching describe state changes,
but still allow invalid values such as `Opening 42` unless validation prevents
them. Strict fields help avoid deferred arithmetic, but do not eliminate lists,
allocation, or garbage collection.

The most instructive boundary is `runSTUArray` in the renderer: it permits fast
local pixel writes while exposing an immutable result. Contrast that with the
FFI in `Playback`, where pointer lifetimes and native resource ownership require
explicit care. The [tradeoffs guide](haskell/docs/HASKELL-TRADEOFFS.md) explains
where these choices help and where they introduce costs.

For a small exercise, change movement speed and its fixed-tick test together,
then add a door state or a new sound event. For comparison with the original C,
start with `ClipMove` in [WL_AGENT.C](WOLFSRC/WL_AGENT.C), `MoveDoors` in
[WL_ACT1.C](WOLFSRC/WL_ACT1.C), and `CA_CacheMap` in [ID_CA.C](WOLFSRC/ID_CA.C).
The [design walkthrough](haskell/docs/DESIGN.md) maps more of the original systems
to their Haskell counterparts.

## Verify

```sh
make test                   # Pure game/decoder tests; no assets or display needed
make test-assets            # Actual pack decoding, map checks, and rendered PPMs
./haskell/build/wolf-haskell --snapshot /tmp/wolf.ppm
./haskell/build/wolf-haskell --audio-preview /tmp/wolf.wav
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./haskell/build/wolf-haskell --smoke
```

The five-second WAV preview includes the selected song plus pistol, door, and
damage effects. It uses the same native mixer as interactive play, without an
audio device. `+RTS -s` prints Haskell runtime allocation statistics on exit.

Cabal metadata supports editors and alternative builds. For a Cabal executable,
build the OPL shared library through Make and place it beside that executable
for audio; Make is the complete verified build/package workflow.

## Intentional limitations

Maps, wall textures, transparent sprites, digitized effects, AdLib effects, and
level music load from original resources. Enemy identities select original
standing, firing, and dead sprites, but pursuit/combat remain simplified. Enemy
rotation and full animation state machines are not implemented. Decorations and
pickups are visible but nonblocking/noncollectible. Doors stay open after a delay
and ignore keys; pushwalls stay fixed. The boss victory sequence is not implemented.

The HUD, floor, ceiling, and demo graphics remain procedural. Original VGA menus,
fonts, saves, demos, PC-speaker emulation, and positional sound are not implemented.
The original DOS source and its license remain in place. The OPL library retains
its separate upstream license in `haskell/vendor/nuked-opl3/`.
