"""Converts the original particle effects (Graphics/Effects/ParticleEffects/**/*.pfx, docs/particles.md) into
assets/effects/<same path>.json and copies the particle textures into assets/effects/textures/.

Each json: {"emitters": [...], "triggers": [...]} with every emitter's path nodes resolved (the XML uses
`identifier` back-references for shared simulation data). Values keep the engine's units: positions in world
units (scaled by the effect size at runtime), times in ms, angles in radians, colours rgba 0..1.

Usage: python tools/convert_particles.py [<name filter> ...]
"""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "reference" / "rise-of-legions" / "Graphics" / "Effects" / "ParticleEffects"
EFFECT_TEXTURES = ROOT / "reference" / "rise-of-legions" / "Graphics" / "Effects" / "Textures"   # only RangeLine*: names collide with particle textures (Trace.tga)
OUT = ROOT / "assets" / "effects"
TEXTURES_OUT = OUT / "textures"
TEXTURE_CASE: dict[str, str] = {}   # lowercase name -> actual disk name (pfx references vary in case)


def num(text: str | None, default: float = 0.0) -> float:
    if text is None or not text.strip():
        return default
    return float(text.strip().replace(",", "."))


def child_text(node, key: str) -> str | None:
    """Axis tags are written `<X>` in most files and `<x>` in a few (e.g. LaneNode.pfx): match case-insensitively."""
    for child in node:
        if child.tag.lower() == key.lower():
            return child.text
    return None


def vec(node, keys=("X", "Y", "Z"), default: float = 0.0) -> list[float]:
    if node is None:
        return [default] * len(keys)
    return [num(child_text(node, k), default) for k in keys]


def varied(node, keys=("X", "Y", "Z")) -> dict:
    """RVariedVector3/4: {"mean": [...], "variance": [...], "radial": bool}."""
    if node is None:
        return {"mean": [0.0] * len(keys), "variance": [0.0] * len(keys)}
    result = {"mean": vec(node.find("Mean"), keys), "variance": vec(node.find("Variance"), keys)}
    if (node.findtext("FRadialVaried") or "").strip() == "True":
        result["radial"] = True
    return result


def varied_scalar(node) -> dict:
    if node is None:
        return {"mean": 0.0, "variance": 0.0}
    return {"mean": num(node.findtext("Mean")), "variance": num(node.findtext("Variance"))}


class Resolver:
    """Elements carry identifier="N"; an empty element with the same identifier is a back-reference."""

    def __init__(self, root) -> None:
        self.by_id: dict[str, object] = {}
        for el in root.iter():
            ident = el.get("identifier")
            if ident and len(el) > 0 and ident not in self.by_id:
                self.by_id[ident] = el

    def resolve(self, el):
        if el is None:
            return None
        if len(el) == 0 and el.get("identifier") in self.by_id:
            return self.by_id[el.get("identifier")]
        return el


def list_items(node) -> list:
    """Serialized lists come as <Item> children or as <FItems type="array"><element_N>."""
    if node is None:
        return []
    items = [c for c in node if c.tag == "Item"]
    if items:
        return items
    arr = node.find("FItems")
    if arr is not None:
        return [c for c in arr if c.tag.startswith("element_")]
    return []


def parse_node(item) -> dict:
    pattern = item.find("ParticlePattern")
    return {
        "rotation": varied(pattern.find("Rotation") if pattern is not None else None),
        "front": vec(pattern.find("Front") if pattern is not None else None),
        "up": vec(pattern.find("Up") if pattern is not None else None),
        "size": varied(pattern.find("Size") if pattern is not None else None),
        "color": varied(pattern.find("Color") if pattern is not None else None, ("X", "Y", "Z", "W")),
        "scheme": (item.findtext("InterpolationScheme") or "isLinear").strip(),
        "position": varied(item.find("Position")),
        "tangent1": varied(item.find("Tangent1")),
        "tangent2": varied(item.find("Tangent2")),
        "time": varied_scalar(item.find("PathTime")),
    }


def parse_emitter(el, resolver: Resolver) -> dict:
    texture = el.find("FParticleTexture")
    atlas = el.find("FTextureAtlasSize")
    emitter = {
        "position": vec(el.find("FPosition")),
        "front": vec(el.find("FFront")),
        "up": vec(el.find("FUp")),
        "rotation": varied(el.find("FRotation")),
        "type": (el.findtext("FParticleType") or "ptQuad").strip().replace("pt", "", 1).lower(),
        "count": int(num(el.findtext("FEmissionCount"), 1)),
        "times": max(1, int(num(el.findtext("FTimes"), 1))),
        "offset": varied_scalar(el.find("FStartingOffset")),
        "stick_to_emitter": (el.findtext("FStickToEmitter") or "").strip() == "True",
        "die_with_emitter": (el.findtext("FDieWithEmitter") or "").strip() == "True",
        "emitted_effect": (el.findtext("FEmittedEffect") or "").strip().replace("\\", "/"),
        "texture": {
            "file": (texture.findtext("TextureFileName") or "").strip() if texture is not None else "",
            "blend": (texture.findtext("BlendMode") or "pbAdditive").strip().replace("pb", "", 1).lower() if texture is not None else "additive",
            "ignore_z": (texture.findtext("IgnoreZ") or "").strip() == "True" if texture is not None else False,
            "soft": (texture.findtext("Softparticle") or "").strip() == "True" if texture is not None else False,
            "draw_order": int(num(texture.findtext("DrawOrder"), 0)) if texture is not None else 0,
        },
        "atlas": [int(v) for v in vec(atlas, ("X", "Y"), 0)] if atlas is not None else [0, 0],
        "path": [],
    }
    sim = resolver.resolve(el.find("FSimulationData"))
    if sim is not None:
        path = resolver.resolve(sim.find("FPath"))
        if path is not None:
            emitter["path"] = [parse_node(item) for item in list_items(resolver.resolve(path.find("FParticlePathNodes")))]
    return emitter


def convert_file(src: Path, dst: Path) -> dict:
    root = ElementTree.parse(src).getroot()
    resolver = Resolver(root)
    emitters = []
    ids: dict[str, int] = {}
    for el in list_items(root.find("FEmitter")):
        el = resolver.resolve(el)
        if el.get("identifier") in ids:
            continue
        ids[el.get("identifier") or str(len(emitters))] = len(emitters)
        emitters.append(parse_emitter(el, resolver))
    triggers = []
    for el in list_items(root.find("FTrigger")):
        kind = (el.get("type") or "").split(".")[-1]
        target = el.find("FEmitter")
        index = ids.get(target.get("identifier")) if target is not None else None
        if index is None:
            continue
        trigger = {"emitter": index}
        if kind == "TIntervalEmissionTrigger":
            trigger["type"] = "interval"
            interval = el.find("FInterval")
            trigger["interval"] = num(interval.findtext("Interval"), 1000) if interval is not None else 1000.0
        elif kind == "TDistanceEmissionTrigger":
            trigger["type"] = "distance"
            trigger["distance"] = num(el.findtext("FEmitDistance"), 1.0)
        else:
            trigger["type"] = "instant"
        triggers.append(trigger)
    for e in emitters:   # pfx texture references may differ in case from the file on disk (Slice.png vs slice.png)
        name = e.get("texture", {}).get("file", "")
        if name:
            e["texture"]["file"] = TEXTURE_CASE.get(name.lower(), name)
    data = {"emitters": emitters, "triggers": triggers}
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
    return data


def main(filters: list[str]) -> int:
    if not SRC.is_dir():
        print(f"missing {SRC}", file=sys.stderr)
        return 1
    TEXTURES_OUT.mkdir(parents=True, exist_ok=True)
    textures = 0
    for src in list(SRC.rglob("*")) + list(EFFECT_TEXTURES.glob("RangeLine*")) + list(EFFECT_TEXTURES.glob("SpawnMask.png")):
        if src.suffix.lower() in (".tga", ".png"):
            dst = TEXTURES_OUT / src.name
            if not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime:
                shutil.copy2(src, dst)
            TEXTURE_CASE[src.name.lower()] = src.name
            textures += 1
    count = failed = 0
    for src in sorted(SRC.rglob("*.pfx")):
        rel = src.relative_to(SRC)
        if filters and not any(f.lower() in rel.as_posix().lower() for f in filters):
            continue
        try:
            convert_file(src, OUT / rel.with_suffix(".json"))
            count += 1
        except Exception as exc:  # noqa: BLE001
            failed += 1
            print(f"FAILED {rel}: {exc}", file=sys.stderr)
    print(f"converted {count} effects ({failed} failed), {textures} textures -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
