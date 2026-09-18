"""Converts an original map (reference/rise-of-legions/Maps/<Name>) into assets/maps/<Name>/:

  terrain.glb            the 513x513 heightmap as 16 chunk primitives (TTerrain: FScale 300/50/300, quadtree
                         TextureSplits 2 -> 4x4 chunks, chunk id = row * 4 + col, chunk textures
                         <Name><id>Diffuse/Normal.png copied next to it, UV = position inside the chunk)
  map.json               water surfaces (.wat), lights (.lig), vegetation instances (.veg, the engine's
                         Delphi Random replayed from each FRandSeed for mesh choice / rotation / size) and
                         decorations (.bcc entities -> Scripts/Environment/*.ets meshes)
assets/environment/      environment textures + TMesh xml copied 1:1 (meshes: tools/msh_to_gltf.py --environment)

Usage: python tools/convert_map.py Classic
"""
from __future__ import annotations

import base64
import json
import math
import re
import shutil
import struct
import sys
import zlib
from pathlib import Path
from xml.etree import ElementTree

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from msh import load as load_msh  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / "reference" / "rise-of-legions"
MAPS = REF / "Maps"
ENV_SRC = REF / "Graphics" / "Environment"
ENV_OUT = ROOT / "assets" / "environment"
SCRIPTS = REF / "Scripts"
OUT = ROOT / "assets" / "maps"

CUSTOM_B64 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+/"
STD_B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
SIZE_FACTOR_3DSMAX = 2.0 / 125.0


# ---------------------------------------------------------------- helpers

def num(text: str | None) -> float:
    return float((text or "0").strip().replace(",", "."))


def vec(node, keys=("X", "Y", "Z")) -> list[float]:
    return [num(node.find(k).text) for k in keys]


class DelphiRandom:
    """System.Random of Delphi (32-bit LCG on RandSeed): Random(N) and the [0, 1) float."""

    def __init__(self, seed: int) -> None:
        self.seed = seed & 0xFFFFFFFF

    def _step(self) -> int:
        self.seed = (self.seed * 134775813 + 1) & 0xFFFFFFFF
        return self.seed

    def random_int(self, n: int) -> int:
        return (self._step() * n) >> 32

    def random(self) -> float:
        return self._step() / 4294967296.0


# ---------------------------------------------------------------- terrain

def read_heights(ter_path: Path) -> tuple[np.ndarray, list[float], list[float]]:
    root = ElementTree.parse(ter_path).getroot()
    scale = vec(root.find("FScale"))
    position = vec(root.find("FPosition"))
    grid = root.find("GridData")
    size = int(grid.get("size"))
    text = "".join(grid.text.split()).translate(str.maketrans(CUSTOM_B64, STD_B64))
    raw = base64.b64decode(text + "=" * (-len(text) % 4))
    if str(grid.get("compressed")).lower() == "true":
        raw = zlib.decompress(raw)
    pos = 5   # outer dynamic array header (flag byte + count)
    rows = []
    for _ in range(size):
        pos += 5
        rows.append(np.frombuffer(raw, dtype=np.float32, count=size, offset=pos))
        pos += size * 4
    return np.stack(rows), scale, position   # heights[x][z] normalised (-0.5 .. 0.5)


def write_terrain_glb(name: str, heights: np.ndarray, scale: list[float], position: list[float], out_dir: Path) -> None:
    size = heights.shape[0]
    splits = 4
    chunk = (size - 1) // splits
    xs = (np.arange(size) / (size - 1) - 0.5) * scale[0] + position[0]
    zs = (np.arange(size) / (size - 1) - 0.5) * scale[2] + position[2]
    ys = heights * scale[1] + position[1]
    # normals from central differences (world units)
    dx = np.gradient(ys, xs, axis=0)
    dz = np.gradient(ys, zs, axis=1)
    normals = np.stack([-dx, np.ones_like(ys), -dz], axis=-1)
    normals /= np.linalg.norm(normals, axis=-1, keepdims=True)

    blob = bytearray()
    views, accessors, materials, images, textures, primitives = [], [], [], [], [], []

    def add(array: np.ndarray, component: int, kind: str, target: int, minmax: bool = False) -> int:
        data = np.ascontiguousarray(array).tobytes()
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
        blob.extend(data)
        acc = {"bufferView": len(views) - 1, "componentType": component, "count": int(array.shape[0]), "type": kind}
        if minmax:
            acc["min"] = [float(v) for v in array.min(axis=0)]
            acc["max"] = [float(v) for v in array.max(axis=0)]
        accessors.append(acc)
        return len(accessors) - 1

    for row in range(splits):
        for col in range(splits):
            chunk_id = row * splits + col
            x0, z0 = col * chunk, row * chunk
            gx = slice(x0, x0 + chunk + 1)
            gz = slice(z0, z0 + chunk + 1)
            px, pz = np.meshgrid(xs[gx], zs[gz], indexing="ij")
            pos3 = np.stack([px, ys[gx, gz], pz], axis=-1).reshape(-1, 3).astype(np.float32)
            nrm = normals[gx, gz].reshape(-1, 3).astype(np.float32)
            u, v = np.meshgrid(np.arange(chunk + 1) / chunk, np.arange(chunk + 1) / chunk, indexing="ij")
            # sample texel centers (D3D convention): the outermost texels sit ON the chunk border, so adjacent
            # chunks share their edge colour and no filtered seam line appears between them
            diffuse = MAPS / name / f"{name}{chunk_id}Diffuse.png"
            if diffuse.exists():
                with Image.open(diffuse) as img:
                    tw, th = img.size
                u = (0.5 + u * (tw - 1)) / tw
                v = (0.5 + v * (th - 1)) / th
            uv = np.stack([u, v], axis=-1).reshape(-1, 2).astype(np.float32)
            n = chunk + 1
            i = np.arange(chunk)[:, None] * n + np.arange(chunk)[None, :]
            a, b, c, d = i, i + 1, i + n, i + n + 1   # a=(x,z) b=(x,z+1) c=(x+1,z) d=(x+1,z+1)
            tris = np.stack([a, b, c, b, d, c], axis=-1).reshape(-1).astype(np.uint32)   # CCW seen from +Y
            for kind in ("Diffuse", "Normal"):
                src = MAPS / name / f"{name}{chunk_id}{kind}.png"
                if src.exists():
                    shutil.copy2(src, out_dir / src.name)
            images.append({"uri": f"{name}{chunk_id}Diffuse.png"})
            textures.append({"source": len(images) - 1, "sampler": 0})
            material = {"name": f"chunk{chunk_id}", "pbrMetallicRoughness": {"baseColorTexture": {"index": len(textures) - 1}, "metallicFactor": 0.0, "roughnessFactor": 1.0}}
            if (MAPS / name / f"{name}{chunk_id}Normal.png").exists():
                images.append({"uri": f"{name}{chunk_id}Normal.png"})
                textures.append({"source": len(images) - 1, "sampler": 0})
                material["normalTexture"] = {"index": len(textures) - 1}
            materials.append(material)
            primitives.append({
                "attributes": {"POSITION": add(pos3, 5126, "VEC3", 34962, True), "NORMAL": add(nrm, 5126, "VEC3", 34962),
                               "TEXCOORD_0": add(uv, 5126, "VEC2", 34962)},
                "indices": add(tris, 5125, "SCALAR", 34963), "material": len(materials) - 1, "mode": 4,
            })
    gltf = {
        "asset": {"version": "2.0", "generator": "CrystalClash convert_map"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": "Terrain", "mesh": 0}],
        "meshes": [{"name": "Terrain", "primitives": primitives}],
        "materials": materials, "images": images, "textures": textures,
        # 33071 = CLAMP_TO_EDGE: the default REPEAT bleeds the opposite chunk edge into the border (dark seam lines)
        "samplers": [{"wrapS": 33071, "wrapT": 33071}], "buffers": [{"byteLength": len(blob)}],
        "bufferViews": views, "accessors": accessors,
    }
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode()
    json_bytes += b" " * (-len(json_bytes) % 4)
    body = bytes(blob) + b"\0" * (-len(blob) % 4)
    header = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(json_bytes) + 8 + len(body))
    (out_dir / "terrain.glb").write_bytes(header + struct.pack("<II", len(json_bytes), 0x4E4F534A) + json_bytes + struct.pack("<II", len(body), 0x004E4942) + body)


# ---------------------------------------------------------------- water / lights

def read_water(path: Path) -> list[dict]:
    if not path.exists():
        return []
    root = ElementTree.parse(path).getroot()
    result = []
    for item in root.iter("Item"):
        def rgba(tag: str, default: list[float]) -> list[float]:
            node = item.find(tag + "/RGBA")
            return vec(node, ("X", "Y", "Z", "W")) if node is not None else default
        wave = (item.findtext("WaveTexture") or "").strip().replace("\\", "/")
        wave_name = ""
        if wave:
            src = path.parent / Path(wave).name
            candidates = [c for c in path.parent.iterdir() if c.name.lower() == Path(wave).name.lower()]
            if candidates:
                shutil.copy2(candidates[0], OUT / path.parent.name / candidates[0].name)
                wave_name = candidates[0].name
        result.append({
            "position": vec(item.find("Position")),
            "size": vec(item.find("GeometrySize"), ("X", "Y")),
            "shader_size": num(item.findtext("Size")),
            "color": rgba("WaterColor", [0.18, 0.36, 0.44, 0.0]),
            "sky_color": rgba("SkyColor", [0.63, 0.73, 0.92, 0.0]),
            "transparency": num(item.findtext("Transparency")),
            "roughness": num(item.findtext("Roughness")),
            "fresnel_offset": num(item.findtext("FresnelOffset")),
            "depth_transparency_range": num(item.findtext("DepthTransparencyRange")),
            "color_extinction_range": num(item.findtext("ColorExtinctionRange")),
            "specular_power": num(item.findtext("Specularpower")),
            "specular_intensity": num(item.findtext("Specularintensity")),
            "wave_height": num(item.findtext("WaveHeight")),
            "wave_texture": wave_name,
        })
    return result


def read_lights(path: Path) -> dict:
    if not path.exists():
        return {}
    root = ElementTree.parse(path).getroot()
    ambient = vec(root.find("FAmbient"), ("X", "Y", "Z", "W"))
    lights = []
    for item in root.find("FDirectionalLights").iter("Item"):
        lights.append({"direction": vec(item.find("Direction")), "color": vec(item.find("Color"), ("X", "Y", "Z", "W")),
                       "enabled": (item.findtext("Enabled") or "").strip() == "True"})
    return {"ambient": ambient, "directional": lights}


# ---------------------------------------------------------------- environment meshes

def env_folder_index() -> dict[str, dict[str, str]]:
    index: dict[str, dict[str, str]] = {}
    for folder in ENV_OUT.iterdir():
        if folder.is_dir():
            index[folder.name.lower()] = {f.name.lower(): f.name for f in folder.iterdir()}
    return index


def copy_environment_textures() -> int:
    count = 0
    for src in sorted(ENV_SRC.rglob("*")):
        if src.is_file() and src.suffix.lower() in (".tga", ".png", ".xml"):
            dst = ENV_OUT / src.relative_to(ENV_SRC)
            dst.parent.mkdir(parents=True, exist_ok=True)
            if not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime:
                shutil.copy2(src, dst)
            count += 1
    return count


def resolve_env_mesh(mesh_ref: str, index: dict) -> tuple[str, str] | None:
    """'Environment\\Palmtrees\\Palmtree1.fbx' or '...\\Bridge1.xml' -> (glb path under assets/environment, diffuse)."""
    parts = mesh_ref.replace("\\", "/").split("/")
    parts = [p for p in parts if p and p.lower() not in ("graphics", "environment")]
    if len(parts) < 2:
        return None
    folder, file = parts[-2], parts[-1]
    files = index.get(folder.lower())
    if files is None:
        return None
    real_folder = folder
    for f in ENV_OUT.iterdir():
        if f.name.lower() == folder.lower():
            real_folder = f.name
    stem = Path(file).stem.lower()
    diffuse = ""
    if file.lower().endswith(".xml") and stem + ".xml" in files:
        xml = ElementTree.parse(ENV_OUT / real_folder / files[stem + ".xml"]).getroot()
        geometry = (xml.findtext("GeometryFile") or "").strip()
        diffuse = (xml.findtext("DiffuseTetxure") or xml.findtext("DiffuseTexture") or "").strip()
        stem = Path(geometry).stem.lower() if geometry else stem
    glb = files.get(stem + ".glb")
    if glb is None:
        return None
    if not diffuse:
        diffuse = next((files[f] for f in files if "diffuse" in f and f.endswith((".tga", ".png"))), "")
    return f"{real_folder}/{glb}", f"{real_folder}/{files.get(diffuse.lower(), diffuse)}" if diffuse else ""


def read_vegetation(path: Path, index: dict) -> list[dict]:
    if not path.exists():
        return []
    root = ElementTree.parse(path).getroot()
    radius_cache: dict[str, float] = {}
    result = []
    for item in root.iter("Item"):
        meshes = [m.strip() for m in (item.findtext("Meshes") or "").splitlines() if m.strip()]
        if not meshes:
            continue
        rng = DelphiRandom(int(item.findtext("FRandSeed")))
        mesh_ref = meshes[rng.random_int(len(meshes))]
        rot = item.find("Rotation")
        mean, variance = vec(rot.find("Mean")), vec(rot.find("Variance"))
        rotation = [mean[i] + (rng.random() * 2 - 1) * variance[i] for i in range(3)]   # pitch, yaw, roll
        size_node = item.find("Size")
        size = num(size_node.findtext("Mean")) + (rng.random() * 2 - 1) * num(size_node.findtext("Variance"))
        resolved = resolve_env_mesh(mesh_ref, index)
        if resolved is None:
            continue
        glb, diffuse = resolved
        if glb not in radius_cache:
            msh_src = ENV_SRC / Path(glb).with_suffix(".msh")
            candidates = [c for c in msh_src.parent.glob("*.msh") if c.name.lower() == msh_src.name.lower()]
            radius_cache[glb] = load_msh(candidates[0]).sphere_radius if candidates else 1.0
        scale = size * num(item.findtext("Scale")) / (radius_cache[glb] * 2.0)
        diffuse_override = (item.findtext("Diffuse") or "").strip()
        if diffuse_override:
            resolved_override = resolve_env_mesh(diffuse_override, index)
            parts = diffuse_override.replace("\\", "/").split("/")
            files = index.get(parts[-2].lower(), {}) if len(parts) >= 2 else {}
            if parts[-1].lower() in files:
                diffuse = f"{Path(glb).parent}/{files[parts[-1].lower()]}"
        result.append({"mesh": glb, "diffuse": diffuse, "position": vec(item.find("FPosition")), "rotation": rotation, "scale": scale})
    return result


# ---------------------------------------------------------------- grass (TGrassTuft.ComputeAndSave)

def _normalize(v: np.ndarray) -> np.ndarray:
    n = np.linalg.norm(v)
    return v / n if n > 0 else v


def _rotate_axis(v: np.ndarray, axis: np.ndarray, angle: float) -> np.ndarray:
    """RVector3.RotateAxis (Rodrigues)."""
    a = _normalize(axis)
    return v * math.cos(angle) + np.cross(a, v) * math.sin(angle) + a * np.dot(a, v) * (1 - math.cos(angle))


def _arbitrary_orthogonal(v: np.ndarray) -> np.ndarray:
    r = np.cross(v, np.array([0.0, 1.0, 0.0]))
    if np.linalg.norm(r) < 1e-9:
        r = np.cross(v, np.array([1.0, 0.0, 0.0]))
    return _normalize(r)


def build_grass(path: Path) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, str]:
    """Bakes every TGrassTuft of the .veg like the engine: three crossed quads per tuft, random rotation,
    trapezial top, random size, the engine's Delphi Random replayed from FRandSeed."""
    positions, normals, uvs, indices = [], [], [], []
    diffuse = ""
    if not path.exists():
        return np.zeros((0, 3)), np.zeros((0, 3)), np.zeros((0, 2)), np.zeros(0, dtype=np.uint32), diffuse
    root = ElementTree.parse(path).getroot()
    for item in root.iter("Item"):
        if item.get("type") != "Engine.Vegetation.TGrassTuft":
            continue
        rng = DelphiRandom(int(item.findtext("FRandSeed")))
        position = np.array(vec(item.find("FPosition")))
        ground = _normalize(np.array(vec(item.find("FGroundNormal"))))
        rotation = rng.random() * 2 * math.pi
        top = ground.copy()
        side = _arbitrary_orthogonal(top)
        front = _normalize(np.cross(top, side))
        angle_node = item.find("Angle")
        angle = num(angle_node.findtext("Mean")) + (rng.random() * 2 - 1) * num(angle_node.findtext("Variance"))
        top = _normalize(_rotate_axis(top, side, angle - math.pi / 2))
        size_node = item.find("Size")
        mean = vec(size_node.find("Mean"), ("X", "Y"))
        variance = vec(size_node.find("Variance"), ("X", "Y"))
        real_size = [mean[i] + (rng.random() * 2 - 1) * variance[i] for i in range(2)]
        trap_node = item.find("Trapezial")
        trapezial = num(trap_node.findtext("Mean")) + (rng.random() * 2 - 1) * num(trap_node.findtext("Variance")) - 0.5
        rng.random()   # timeOffset (wind animation phase)
        mid_offset = num(item.findtext("MidOffset"))
        normal_adjust = num(item.findtext("NormalAdjustment"))
        scale = num(item.findtext("Scale"))
        diffuse = diffuse or (item.findtext("Diffuse") or "").strip()
        for i in range(3):
            r_angle = (i / 3) * 2 * math.pi + rotation
            normal = _normalize(_rotate_axis(_normalize(np.cross(top, side)), ground, r_angle))
            normal = _normalize(normal + (ground - normal) * normal_adjust)
            def corner(sx: float, up: float) -> np.ndarray:
                v = (side * sx * real_size[0] / 2 + top * up * real_size[1] + front * real_size[0] * mid_offset / 2) * scale
                return _rotate_axis(v, ground, r_angle) + position
            lt, rt, lb, rb = corner(1, 1), corner(-1, 1), corner(1, 0), corner(-1, 0)
            lt, rt = lt + (rt - lt) * trapezial, rt + (lt - rt) * trapezial
            base = len(positions)
            positions += [lt, rt, lb, rb]
            normals += [normal] * 4
            uvs += [[0, 0], [1, 0], [0, 1], [1, 1]]
            indices += [base, base + 2, base + 1, base + 1, base + 2, base + 3]
    return (np.array(positions, dtype=np.float32), np.array(normals, dtype=np.float32), np.array(uvs, dtype=np.float32),
            np.array(indices, dtype=np.uint32), diffuse)


def write_grass_glb(veg_path: Path, out_dir: Path, index: dict) -> dict | None:
    positions, normals, uvs, indices, diffuse = build_grass(veg_path)
    if len(positions) == 0:
        return None
    # the engine flips winding for DirectX: emit the opposite order (alpha-cut grass is drawn double-sided anyway)
    indices = indices.reshape(-1, 3)[:, ::-1].reshape(-1).copy()
    blob = bytearray()
    views, accessors = [], []

    def add(array, component, kind, target, minmax=False):
        data = np.ascontiguousarray(array).tobytes()
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
        blob.extend(data)
        acc = {"bufferView": len(views) - 1, "componentType": component, "count": int(array.shape[0]), "type": kind}
        if minmax:
            acc["min"] = [float(v) for v in array.min(axis=0)]
            acc["max"] = [float(v) for v in array.max(axis=0)]
        accessors.append(acc)
        return len(accessors) - 1

    primitive = {"attributes": {"POSITION": add(positions, 5126, "VEC3", 34962, True), "NORMAL": add(normals, 5126, "VEC3", 34962),
                                "TEXCOORD_0": add(uvs, 5126, "VEC2", 34962)}, "indices": add(indices, 5125, "SCALAR", 34963), "mode": 4}
    gltf = {"asset": {"version": "2.0", "generator": "CrystalClash convert_map"}, "scene": 0, "scenes": [{"nodes": [0]}],
            "nodes": [{"name": "Grass", "mesh": 0}], "meshes": [{"name": "Grass", "primitives": [primitive]}],
            "buffers": [{"byteLength": len(blob)}], "bufferViews": views, "accessors": accessors}
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode()
    json_bytes += b" " * (-len(json_bytes) % 4)
    body = bytes(blob) + b"\0" * (-len(blob) % 4)
    header = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(json_bytes) + 8 + len(body))
    (out_dir / "grass.glb").write_bytes(header + struct.pack("<II", len(json_bytes), 0x4E4F534A) + json_bytes + struct.pack("<II", len(body), 0x004E4942) + body)
    parts = diffuse.replace("\\", "/").split("/")
    files = index.get(parts[-2].lower(), {}) if len(parts) >= 2 else {}
    tex = f"{parts[-2]}/{files.get(parts[-1].lower(), parts[-1])}" if len(parts) >= 2 else ""
    return {"file": "grass.glb", "diffuse": tex, "tufts": int(len(positions) // 12)}


RE_ENV_MESH = re.compile(r"TMeshComponent\.Create(?:Grouped)?\(Entity(?:,\s*\[[^\]]*\])?,\s*'([^']*)'\)(.*?);", re.S)
RE_ENV_SIZE = re.compile(r"WriteGrouped\(eiModelSize,\s*\[([0-9.]+)\]")


def read_decorations(path: Path, index: dict) -> list[dict]:
    if not path.exists():
        return []
    root = ElementTree.parse(path).getroot()
    result = []
    for item in root.iter("Item"):
        script = (item.findtext("ScriptFilename") or "").strip().replace("\\", "/").lstrip("/")
        if not script.lower().endswith(".ets"):
            script += ".ets"
        script_path = SCRIPTS / script
        if not script_path.exists():
            continue
        text = script_path.read_text(encoding="utf-8", errors="replace")
        meshes = []
        for mesh_ref, chain in RE_ENV_MESH.findall(text):
            resolved = resolve_env_mesh(mesh_ref, index)
            if resolved is None:
                continue
            legacy = ".ApplyLegacySizeFactor" in chain
            m = RE_ENV_SIZE.search(text)
            model_size = float(m.group(1)) if m else 1.0
            meshes.append({"mesh": resolved[0], "diffuse": resolved[1], "scale": (SIZE_FACTOR_3DSMAX if legacy else 1.0) * model_size})
        if not meshes:
            continue
        entity_size = num(item.findtext("Size")) if item.find("Size") is not None else 1.0   # eiSize (BridgeParts 0.01)
        for m in meshes:
            m["scale"] *= entity_size
        result.append({"script": script, "position": vec(item.find("Position")), "front": vec(item.find("Front")), "meshes": meshes})
    return result


# ---------------------------------------------------------------- main

def convert(name: str) -> None:
    map_dir = MAPS / name
    out_dir = OUT / name
    out_dir.mkdir(parents=True, exist_ok=True)
    ENV_OUT.mkdir(parents=True, exist_ok=True)
    print("environment textures:", copy_environment_textures())
    index = env_folder_index()
    heights, scale, position = read_heights(map_dir / f"{name}.ter")
    write_terrain_glb(name, heights, scale, position, out_dir)
    # heightmap.png (16 bit, rows = x, columns = z, value = (h + 0.5) * 65535): the water shader computes its
    # depth from it because the Compatibility renderer has no depth texture
    Image.fromarray(((heights + 0.5) * 65535.0).clip(0, 65535).astype(np.uint16)).save(out_dir / "heightmap.png")
    data = {
        "name": name,
        "terrain": {"file": "terrain.glb", "scale": scale, "position": position, "size": int(heights.shape[0]), "heightmap": "heightmap.png"},
        "water": read_water(map_dir / f"{name}.wat"),
        "lights": read_lights(map_dir / f"{name}.lig"),
        "vegetation": read_vegetation(map_dir / f"{name}.veg", index),
        "decorations": read_decorations(map_dir / f"{name}.bcc", index),
    }
    grass = write_grass_glb(map_dir / f"{name}.veg", out_dir, index)
    if grass:
        data["grass"] = grass
    (out_dir / "map.json").write_text(json.dumps(data, indent=1), encoding="utf-8")
    print(f"{name}: terrain {heights.shape[0]}x{heights.shape[0]}, water {len(data['water'])}, lights {len(data['lights'].get('directional', []))}, "
          f"vegetation {len(data['vegetation'])}, grass tufts {data.get('grass', {}).get('tufts', 0)}, decorations {len(data['decorations'])} -> {out_dir}")


if __name__ == "__main__":
    convert(sys.argv[1] if len(sys.argv) > 1 else "Classic")
