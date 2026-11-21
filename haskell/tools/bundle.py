#!/usr/bin/env python3
"""Create a relocatable directory, bundling one explicit local asset edition.

Never scan or copy the repository wholesale: archives and other installed game
editions must not leak into the distributable. The selected pack is validated by
our actual runtime before replacing an earlier generated bundle.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
REQUIRED = ("MAPHEAD", "GAMEMAPS", "VSWAP", "AUDIOHED", "AUDIOT")
OPTIONAL = ("VGADICT", "VGAGRAPH", "VGAHEAD")


def build_bundle(source: Path, destination: Path) -> None:
    source = source.resolve()
    destination = destination.resolve()
    # Only replace generated bundles, never arbitrary user directories.
    if destination.exists() and not (destination / "bundle-manifest.json").is_file():
        raise ValueError(f"Refusing to replace a directory without a bundle manifest: {destination}")
    if source == destination or destination in source.parents or source in destination.parents:
        raise ValueError("Source assets and destination bundle must not overlap")
    files = {p.name.upper(): p for p in source.iterdir() if p.is_file()}
    editions = [ext for ext in ("WL1", "WL6") if f"MAPHEAD.{ext}" in files]
    if len(editions) != 1:
        raise ValueError("Select one unmixed WL1 or WL6 asset directory")
    ext = editions[0]
    for name in REQUIRED:
        if f"{name}.{ext}" not in files:
            raise ValueError(f"Missing {name}.{ext}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=".wolf-bundle-", dir=destination.parent))
    try:
        (stage / "assets").mkdir()
        manifest = {"edition": ext, "files": {}}
        for name in REQUIRED + OPTIONAL:
            file = files.get(f"{name}.{ext}")
            if file is not None:
                target = stage / "assets" / f"{name}.{ext}"
                shutil.copy2(file, target)
                manifest["files"][target.name] = hashlib.sha256(target.read_bytes()).hexdigest()
        for name in ("wolf-haskell", "libwolfopl.so"):
            shutil.copy2(ROOT / "haskell" / "build" / name, stage / name)
        # Keep the LGPL library replaceable, with its exact corresponding source.
        shutil.copytree(ROOT / "haskell" / "vendor" / "nuked-opl3", stage / "nuked-opl3-source")
        shutil.copy2(ROOT / "README.rst", stage / "ORIGINAL-README.rst")
        shutil.copy2(ROOT / "haskell" / "docs" / "MEDIA.md", stage / "MEDIA.md")
        (stage / "README.txt").write_text(
            "Run ./wolf-haskell from any working directory. Assets are discovered next to the executable.\n"
            "Use --level N to select another map; --no-audio mutes playback; --demo selects the procedural demo.\n"
            "This bundle requires the host SDL2 runtime. It is built for the current OS/architecture.\n"
            "The game files remain under their original terms. See ORIGINAL-README.rst and MEDIA.md.\n"
            "Replaceable OPL emulator source and LGPL notice: nuked-opl3-source/.\n"
            "Rebuild that library: cc -O2 -fPIC -shared nuked-opl3-source/opl3.c -o libwolfopl.so\n"
        )
        # A different working directory proves that executable-relative discovery
        # works and all five required resources can actually be decoded.
        subprocess.run([str(stage / "wolf-haskell"), "--smoke", "--no-audio"],
                       cwd=tempfile.gettempdir(), check=True,
                       env={**os.environ, "SDL_VIDEODRIVER": "dummy", "SDL_AUDIODRIVER": "dummy"})
        (stage / "bundle-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        if destination.exists():
            shutil.rmtree(destination)
        stage.rename(destination)
        print(f"Bundle ready: {destination}")
    finally:
        if stage.exists():
            shutil.rmtree(stage)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: bundle.py ASSET_DIRECTORY OUTPUT_DIRECTORY")
    try:
        build_bundle(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
