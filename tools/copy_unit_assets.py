"""Copies the original unit textures and TMesh descriptors from reference/rise-of-legions/Graphics/Units into
assets/units/<same relative path>. The meshes themselves come from tools/msh_to_gltf.py (the engine's .msh
caches -> .glb); the FBX sources are not copied (Godot's FBX import loses the assimp pivot animations).

Usage: python tools/copy_unit_assets.py [<folder filter> ...]   e.g. Footman_Default White/Archer
"""
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "reference" / "rise-of-legions" / "Graphics" / "Units"
OUT = ROOT / "assets" / "units"
EXTENSIONS = {".tga", ".png", ".xml"}


def main(filters: list[str]) -> int:
    if not SRC.is_dir():
        print(f"missing {SRC}", file=sys.stderr)
        return 1
    count = 0
    for src in sorted(SRC.rglob("*")):
        if not src.is_file() or src.suffix.lower() not in EXTENSIONS:
            continue
        rel = src.relative_to(SRC)
        if filters and not any(f.lower() in rel.as_posix().lower() for f in filters):
            continue
        dst = OUT / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        if not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime:
            shutil.copy2(src, dst)
        count += 1
    print(f"copied {count} files into {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
