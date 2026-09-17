"""Copies the original unit models (FBX + textures + TMesh xml) from reference/rise-of-legions/Graphics/Units
into assets/units/<same relative path> and writes game/data/models.json with each FBX's UnitScaleFactor
(the original scales raw FBX units by SIZE_FACTOR_3DSMAX = 2/125 for ApplyLegacySizeFactor meshes, while Godot
converts them to metres by UnitScaleFactor / 100; docs/assets.md). Godot imports the FBX itself (ufbx); the
engine's .msh caches are skipped.

Usage: python tools/copy_unit_assets.py [<folder filter> ...]   e.g. Footman_Default White/Archer
"""
import json
import re
import shutil
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "reference" / "rise-of-legions" / "Graphics" / "Units"
OUT = ROOT / "assets" / "units"
MODELS_JSON = ROOT / "game" / "data" / "models.json"
EXTENSIONS = {".fbx", ".tga", ".png", ".xml"}


def unit_scale_factor(fbx: Path) -> float:
    """UnitScaleFactor property of a binary FBX (centimetres per unit; 2.54 = inches, 1 = cm)."""
    data = fbx.read_bytes()
    i = data.find(b"UnitScaleFactor")
    if i < 0:
        return 1.0
    m = re.search(rb"\x00D(.{8})", data[i + 15:i + 80], re.S)
    return struct.unpack("<d", m.group(1))[0] if m else 1.0


def main(filters: list[str]) -> int:
    if not SRC.is_dir():
        print(f"missing {SRC}", file=sys.stderr)
        return 1
    models = json.loads(MODELS_JSON.read_text(encoding="utf-8")) if MODELS_JSON.exists() else {}
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
        if src.suffix.lower() == ".fbx":
            models[rel.as_posix()] = {"unit_scale": unit_scale_factor(src)}
        count += 1
    MODELS_JSON.write_text(json.dumps(models, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print(f"copied {count} files into {OUT}, {len(models)} models in {MODELS_JSON.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
