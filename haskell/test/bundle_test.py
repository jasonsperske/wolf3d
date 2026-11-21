#!/usr/bin/env python3
"""Integration checks for built bundles using a caller-supplied local pack.

No proprietary files are fixtures in Git. A renamed WL6 fixture tests extension
routing only; it is not a claim of testing actual registered-release contents.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import wave

ROOT = Path(__file__).resolve().parents[2]
EXE = ROOT / "haskell/build/wolf-haskell"
ENV = {**os.environ, "SDL_VIDEODRIVER": "dummy", "SDL_AUDIODRIVER": "dummy"}


def run(executable, *args, success=True):
    result = subprocess.run([str(executable), *map(str, args)], cwd="/tmp", env=ENV,
                            capture_output=True, text=True, timeout=30)
    assert (result.returncode == 0) == success, result.stdout + result.stderr
    return result


with tempfile.TemporaryDirectory(prefix="wolf-bundle-test-") as temporary:
    temp = Path(temporary)
    source = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "assets/shareware").resolve()
    target = temp / "game"
    subprocess.run([sys.executable, str(ROOT / "haskell/tools/bundle.py"), str(source), str(target)], check=True)
    # Relocate the directory and change cwd, then exercise both video and audio.
    relocated = temp / "moved-game"
    target.rename(relocated)
    run(relocated / "wolf-haskell", "--smoke")
    run(relocated / "wolf-haskell", "--audio-preview", temp / "audio.wav")
    with wave.open(str(temp / "audio.wav")) as audio:
        assert (audio.getnchannels(), audio.getframerate(), audio.getnframes()) == (2, 44100, 220500)
        assert any(audio.readframes(44100)), "Music must generate a nonzero waveform"
    manifest = json.loads((relocated / "bundle-manifest.json").read_text())
    assert set(manifest["files"]) >= {name + "." + manifest["edition"] for name in ("MAPHEAD", "GAMEMAPS", "VSWAP", "AUDIOHED", "AUDIOT")}
    assert not list(relocated.rglob("*.zip"))
    # Lowercase filenames and the WL6 extension use exactly the same loader.
    renamed = temp / "renamed"
    renamed.mkdir()
    for p in (relocated / "assets").iterdir():
        shutil.copy2(p, renamed / (p.stem.lower() + ".wl6"))
    run(EXE, "--assets", renamed, "--smoke", "--no-audio")
    shutil.copy2(renamed / "maphead.wl6", renamed / "MAPHEAD.WL1")
    assert "Mixed WL1/WL6" in run(EXE, "--assets", renamed, "--smoke", success=False).stderr
    incomplete = temp / "incomplete"
    incomplete.mkdir()
    shutil.copy2(renamed / "maphead.wl6", incomplete / "MAPHEAD.WL6")
    assert "Missing GAMEMAPS" in run(EXE, "--assets", incomplete, "--smoke", success=False).stderr
    run(EXE, "--demo", "--smoke")
    run(EXE, "--assets", renamed, "--demo", success=False)
print("Bundle relocation, audio export, edition routing, and error-path checks passed.")
