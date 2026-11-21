# Asset packs, original graphics, and audio

## Layout and bundling

Place one complete edition under a root-level ignored directory:

```
assets/
  shareware/     MAPHEAD.WL1, GAMEMAPS.WL1, VSWAP.WL1, AUDIOHED.WL1, AUDIOT.WL1
  registered/    MAPHEAD.WL6, GAMEMAPS.WL6, VSWAP.WL6, AUDIOHED.WL6, AUDIOT.WL6
  archives/      optional original ZIPs
```

Filenames are matched case-insensitively. Never mix WL1 and WL6 in the same
folder. The resource extensions come from MAPHEAD, and every resource uses that
same extension; there is no accidental mixing of shareware maps and registered
textures. The existing shareware data was moved into `assets/shareware`.

From the repository root:

```sh
make
./haskell/build/wolf-haskell
make bundle                              # prefers registered if present, otherwise shareware
make bundle ASSET_DIR=assets/registered  # select registered data explicitly
./dist/wolf-haskell/wolf-haskell          # no --assets needed
```

Copy the **whole** generated directory to move the game. This is an executable
with an adjacent asset folder and shared OPL library, not a single-file executable.
It still needs the host SDL2 runtime and targets the build machine's OS/architecture.
The verified build is Linux. Windows and macOS packaging are not implemented.

Discovery checks an `assets/` directory beside the executable first, then the
repository's `assets/registered/`, then `assets/shareware/`. Working-directory
fallbacks support development. An existing selected pack that is malformed
reports an error, rather than silently loading a different edition. `--assets DIR`
remains available as an override; `--demo` always selects the procedural demo.

`make bundle` copies only the chosen edition's required files and optional VGA
resources, verifies the copied resources with the actual runtime from another
working directory, and writes a SHA-256 manifest. ZIP archives and other installed
editions are excluded. `assets/` and `dist/` are both ignored by Git. Bundles retain
the original resource terms; bundling does not change those terms.

## Graphics pipeline

`Wolf.Media` validates the VSWAP header, page table, offsets, lengths, and the
wall/sprite/sound partitions. Sparse pages remain absent. Walls are 64×64 bytes
stored by column, converted into row-major ARGB arrays once at load time.
Original map wall codes select paired texture pages: `(code-1)*2 + face`.
The final eight wall pages supply door variants. Door motion still follows the
teaching engine's whole-tile delayed-opening rule.

Sprites contain a left/right column range and offsets to column command lists.
Each post supplies an exclusive doubled end row, a pixel base offset, and a
doubled start row. Pixel indices use `base + row`. The decoder checks ranges and
source offsets (including original 16-bit wrapping), then writes an immutable 64×64 image with transparent pixels.
Transparency is separate from palette index zero: black pixels stay opaque.

The renderer uses these pictures for enemies, corpses, decorations, pickups,
and the pistol. It depth-tests columns against walls and paints billboards from
back to front. Enemy states select standing, attacking, or dead frames; full
eight-direction animation and original state timing remain future work.
The palette is derived from the existing source release's `GAMEPAL.OBJ`, where
the original code stored it, rather than extracted from the user executable.

The UI, crosshair, minimap, health bar, ceiling, and floor remain procedural.
VGAGRAPH fonts/menu art are not used. Decorations and pickups are visible but
retain the teaching edition's nonblocking/noncollectible behavior. Original
textures and sprites do not imply original gameplay compatibility.

## Audio pipeline

`Wolf.Audio` validates AUDIOHED offsets, identifies the 69- or 87-effect layout,
and decodes the 27 music chunks and AdLib effects. `Wolf.Media` reconstructs
unsigned 8-bit, 7042 Hz digitized samples from VSWAP sound pages and its final
directory. The audio callback mixes up to eight digitized voices at 44100 Hz.
Nearest-neighbor resampling is intentional and retains the low-rate source sound.

Music is an IMF register/value/delay stream. Trailing editor metadata is ignored
and zero-length shareware placeholders remain silent. Delays run at 700 Hz; AdLib effect
frequency bytes run at 140 Hz. The level selects the original episode track.
A pinned, unmodified Nuked-OPL3 library emulates the chip, loaded dynamically from
beside the executable. Music and effects have separate emulated chips, allowing
effects to play without stealing a music channel. The resulting mix therefore
is not a cycle-exact reproduction of the original whole audio system.

The Haskell simulation remains pure. `soundEvents old new` produces sound IDs per
simulation tick for firing, opening doors, guard alerts/attacks/deaths, damage,
player death, and victory. The shell sends those IDs to the native mixer, which
prefers original digitized effects where available and otherwise uses AdLib.
No game rules, file parsing, or resource selection run in the audio callback.

No PC-speaker emulation is provided. Sound prioritization/spatialization and the
full original set of gameplay triggers are not implemented. Restart resets game
state but does not rewind the current music track. If opening the device fails,
the game reports the error and continues muted. `--no-audio` explicitly disables
playback. Audio parsing still runs, so corrupted packs are reported consistently.

## Inspect and verify

```sh
make test
make test-assets
./haskell/build/wolf-haskell --snapshot /tmp/wolf.ppm
./haskell/build/wolf-haskell --audio-preview /tmp/wolf.wav
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./haskell/build/wolf-haskell --smoke
```

The WAV preview renders five seconds through the same OPL/mixer path, with
pistol, door, and damage effects at seconds one, two, and three. It needs no
physical audio device. The bundled executable supports the same commands.
The supplied WL1 files are integration-tested. Registered WL6 support uses the
same formats and directory discovery; no registered data is included or claimed
as tested against an actual registered release.

The optional Cabal build still compiles the game, but the shared OPL library must
be built with `make -C haskell build/libwolfopl.so` and copied beside Cabal's
executable for sound. Prefer Make for a complete runnable build and bundle.
