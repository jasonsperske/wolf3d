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

- [Design walkthrough](docs/DESIGN.md): follow a frame and compare systems with the DOS code.
- [Haskell tradeoffs](docs/HASKELL-TRADEOFFS.md): purity, state types, allocation, local mutation, FFI.
- [Map loading](docs/ASSET-LOADING.md): Carmack/RLEW decompression and gameplay translation.
- [Graphics, audio, and bundling](docs/MEDIA.md): resource formats, discovery, playback, packaging.

Suggested source order: `Types`, `Level`, `Raycast`, `Simulation`, `Render`,
then `Binary`, `Assets`, `Media`, `Audio`, `Pack`, `Playback`, and `app/Main.hs`.
The tests use synthetic resources to demonstrate format boundaries without
requiring licensed assets.

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
its separate upstream license in `vendor/nuked-opl3/`.
