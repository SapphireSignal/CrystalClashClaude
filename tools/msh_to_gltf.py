"""Converts the original engine's `.msh` mesh caches (tools/msh.py) into glTF binaries (.glb) that Godot imports.

The `.msh` holds exactly what the game rendered (raw units, bone hierarchy with assimp pivot nodes, skin
offset matrices, animation channels in ms), so the glb reproduces the original 1:1 where Godot's own FBX
import loses pivot animations (NexusCrystal). Node local matrices stay as they are; animated nodes get the
key TRS (the engine replaces the local matrix with the animated TRS, Engine.Mesh.pas:2188). Vertices are
skinned as `Combined * Offset * v`, which is glTF's `jointMatrix = globalJoint * inverseBindMatrix` with the
mesh node at the root, so the offset matrices become the inverse bind matrices unchanged.

Usage: python tools/msh_to_gltf.py <file.msh> <out.glb>
       python tools/msh_to_gltf.py --all           (every Graphics/Units/**/*.msh -> assets/units/<same path>.glb)
       python tools/msh_to_gltf.py --environment   (Graphics/Environment/**/*.msh -> assets/environment/...)
"""
from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from msh import Msh, load  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
GRAPHICS = ROOT / "reference" / "rise-of-legions" / "Graphics"
TREES = {"--all": (GRAPHICS / "Units", ROOT / "assets" / "units"),
         "--environment": (GRAPHICS / "Environment", ROOT / "assets" / "environment")}

FLOAT = 5126
UINT16 = 5123
UINT32 = 5125
ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963


def _quat_from_matrix(m: np.ndarray) -> list[float]:
    """Rotation part of a 3x3 (scale removed) -> (x, y, z, w)."""
    t = np.trace(m)
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        w = 0.25 * s
        x = (m[2, 1] - m[1, 2]) / s
        y = (m[0, 2] - m[2, 0]) / s
        z = (m[1, 0] - m[0, 1]) / s
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        w = (m[2, 1] - m[1, 2]) / s
        x = 0.25 * s
        y = (m[0, 1] + m[1, 0]) / s
        z = (m[0, 2] + m[2, 0]) / s
    elif m[1, 1] > m[2, 2]:
        s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        w = (m[0, 2] - m[2, 0]) / s
        x = (m[0, 1] + m[1, 0]) / s
        y = 0.25 * s
        z = (m[1, 2] + m[2, 1]) / s
    else:
        s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        w = (m[1, 0] - m[0, 1]) / s
        x = (m[0, 2] + m[2, 0]) / s
        y = (m[1, 2] + m[2, 1]) / s
        z = 0.25 * s
    n = math.sqrt(x * x + y * y + z * z + w * w) or 1.0
    return [x / n, y / n, z / n, w / n]


def _decompose(m: np.ndarray) -> tuple[list[float], list[float], list[float]]:
    """4x4 (column vectors) -> translation, rotation quaternion, scale."""
    t = m[:3, 3].tolist()
    basis = m[:3, :3].copy()
    scale = [float(np.linalg.norm(basis[:, i])) for i in range(3)]
    if np.linalg.det(basis) < 0:
        scale[0] = -scale[0]
    rot = basis.copy()
    for i in range(3):
        if scale[i] != 0:
            rot[:, i] /= scale[i]
    return t, _quat_from_matrix(rot), scale


class GlbWriter:
    def __init__(self) -> None:
        self.blob = bytearray()
        self.buffer_views: list[dict] = []
        self.accessors: list[dict] = []

    def add(self, array: np.ndarray, component: int, kind: str, target: int | None = None, minmax: bool = False) -> int:
        data = np.ascontiguousarray(array).tobytes()
        while len(self.blob) % 4:
            self.blob.append(0)
        view = {"buffer": 0, "byteOffset": len(self.blob), "byteLength": len(data)}
        if target is not None:
            view["target"] = target
        self.blob.extend(data)
        self.buffer_views.append(view)
        count = int(array.shape[0]) if array.ndim > 1 else int(array.shape[0])
        accessor = {"bufferView": len(self.buffer_views) - 1, "componentType": component, "count": count, "type": kind}
        if minmax:
            flat = array.reshape(count, -1)
            accessor["min"] = [float(v) for v in flat.min(axis=0)]
            accessor["max"] = [float(v) for v in flat.max(axis=0)]
        self.accessors.append(accessor)
        return len(self.accessors) - 1


PIVOT = "_$AssimpFbx$_"


def _trs_matrix(t, r, s) -> np.ndarray:
    x, y, z, w = r
    n = math.sqrt(x * x + y * y + z * z + w * w) or 1.0
    x, y, z, w = x / n, y / n, z / n, w / n
    rot = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])
    m = np.eye(4)
    m[:3, :3] = rot * np.asarray(s, dtype=float)[None, :]
    m[:3, 3] = t
    return m


def _sample(channel, time_ms: float) -> np.ndarray:
    """Channel TRS at a time (linear translation / scale, normalised lerp rotation), as a local matrix."""
    times = channel.times
    if time_ms <= times[0]:
        i, f = 0, 0.0
    elif time_ms >= times[-1]:
        i, f = len(times) - 1, 0.0
    else:
        i = int(np.searchsorted(times, time_ms, side="right") - 1)
        span = float(times[i + 1] - times[i])
        f = (time_ms - times[i]) / span if span > 0 else 0.0
    j = min(i + 1, len(times) - 1)
    t = channel.translation[i] * (1 - f) + channel.translation[j] * f
    sc = channel.scale[i] * (1 - f) + channel.scale[j] * f
    q0, q1 = channel.rotation[i], channel.rotation[j]
    if np.dot(q0, q1) < 0:
        q1 = -q1
    r = q0 * (1 - f) + q1 * f
    return _trs_matrix(t, r, sc)


def collapse_pivots(msh: Msh) -> tuple[list[dict], dict[str, int], int | None]:
    """assimp pivot nodes (`X_$AssimpFbx$_Translation` ...) are folded into their bone X: the bone's local
    matrix becomes the chain product, animated pivots are sampled at the union of their key times and the
    composed transform is keyed on the bone. Returns glTF nodes, name -> index, root index."""
    channels: dict[str, object] = {}
    for anim in msh.animations:
        for ch in anim.channels:
            channels[ch.bone] = ch
    nodes: list[dict] = []
    index: dict[str, int] = {}
    keyed: dict[str, dict] = {}   # bone name -> {"times": [...], "t": [...], "r": [...], "s": [...]}

    def real_name(node) -> str:
        return node.name.split(PIVOT)[0] if PIVOT in node.name else node.name

    def add(bone, chain: list, parent_idx: int | None) -> None:
        chain = chain + [bone]
        if PIVOT in bone.name:
            for child in bone.children:
                add(child, chain, parent_idx)
            return
        # a real node: fold the chain (pivots + itself) into one glTF node
        idx = len(nodes)
        node: dict = {"name": bone.name}
        nodes.append(node)
        index[bone.name] = idx
        if parent_idx is not None:
            nodes[parent_idx].setdefault("children", []).append(idx)
        animated = [n for n in chain if n.name in channels]
        if animated:
            times = np.unique(np.concatenate([channels[n.name].times for n in animated]).astype(np.float64))
            keys = {"times": times, "t": [], "r": [], "s": []}
            for tm in times:
                m = np.eye(4)
                for n in chain:
                    m = m @ (_sample(channels[n.name], tm) if n.name in channels else n.local)
                t, r, sc = _decompose(m)
                keys["t"].append(t)
                keys["r"].append(r)
                keys["s"].append(sc)
            keyed[bone.name] = keys
            t, r, sc = keys["t"][0], keys["r"][0], keys["s"][0]
        else:
            m = np.eye(4)
            for n in chain:
                m = m @ n.local
            # static nodes keep the exact matrix (column-major); decomposing zero-scale pivots would lose the rotation
            node["matrix"] = [float(v) for v in np.asarray(m, dtype=np.float64).T.reshape(16)]
            for child in bone.children:
                add(child, [], idx)
            return
        node["translation"], node["rotation"], node["scale"] = t, r, sc
        for child in bone.children:
            add(child, [], idx)

    if msh.root is not None:
        add(msh.root, [], None)
    return nodes, index, keyed, (0 if nodes else None)


def convert(msh: Msh, name: str) -> bytes:
    w = GlbWriter()
    nodes, bone_index, keyed, root_bone = collapse_pivots(msh)

    # mesh: positions, normals, uvs, joints, weights, indices
    positions = msh.positions.astype(np.float32)
    attributes = {
        "POSITION": w.add(positions, FLOAT, "VEC3", ARRAY_BUFFER, minmax=True),
        "NORMAL": w.add(msh.normals.astype(np.float32), FLOAT, "VEC3", ARRAY_BUFFER),
        "TEXCOORD_0": w.add(msh.uvs.astype(np.float32), FLOAT, "VEC2", ARRAY_BUFFER),
    }
    skin_index = None
    if msh.skin:
        joints = np.clip(msh.bone_indices, 0, len(msh.skin) - 1).astype(np.uint16)
        weights = msh.bone_weights.astype(np.float32)
        joints[weights <= 0] = 0
        attributes["JOINTS_0"] = w.add(joints, UINT16, "VEC4", ARRAY_BUFFER)
        attributes["WEIGHTS_0"] = w.add(weights, FLOAT, "VEC4", ARRAY_BUFFER)
        ibm = np.array([np.asarray(link.offset, dtype=np.float32).T for link in msh.skin], dtype=np.float32)  # column-major
        joint_nodes = [bone_index[link.bone] for link in msh.skin]
        skin = {"joints": joint_nodes, "inverseBindMatrices": w.add(ibm.reshape(len(msh.skin), 16), FLOAT, "MAT4")}
        if root_bone is not None:
            skin["skeleton"] = root_bone
        skin_index = 0
    indices = msh.indices.astype(np.uint32)
    if len(indices) == 0:
        indices = np.arange(len(positions), dtype=np.uint32)
    # the engine reversed the FBX winding for DirectX (Engine.Mesh.pas:1695 MirrorMesh); glTF wants it back
    indices = indices.reshape(-1, 3)[:, ::-1].reshape(-1).copy()
    primitive = {"attributes": attributes, "indices": w.add(indices, UINT32, "SCALAR", ELEMENT_ARRAY_BUFFER), "mode": 4}
    mesh_node = {"name": name, "mesh": 0}
    if skin_index is not None:
        mesh_node["skin"] = skin_index
    nodes.append(mesh_node)
    scene_nodes = [len(nodes) - 1]
    if root_bone is not None:
        scene_nodes.append(root_bone)

    animations = []
    if keyed:
        samplers: list[dict] = []
        channels: list[dict] = []
        for bone_name, keys in keyed.items():
            times = w.add((np.asarray(keys["times"], dtype=np.float32) / 1000.0).reshape(-1, 1), FLOAT, "SCALAR", minmax=True)
            for path, values, kind in (("translation", keys["t"], "VEC3"), ("rotation", keys["r"], "VEC4"), ("scale", keys["s"], "VEC3")):
                out = w.add(np.asarray(values, dtype=np.float32), FLOAT, kind)
                samplers.append({"input": times, "output": out, "interpolation": "LINEAR"})
                channels.append({"sampler": len(samplers) - 1, "target": {"node": bone_index[bone_name], "path": path}})
        anim_name = msh.animations[0].name.replace("AnimStack::", "") if msh.animations else "Take 001"
        animations.append({"name": anim_name, "samplers": samplers, "channels": channels})

    gltf: dict = {
        "asset": {"version": "2.0", "generator": "CrystalClash msh_to_gltf"},
        "scene": 0,
        "scenes": [{"nodes": scene_nodes}],
        "nodes": nodes,
        "meshes": [{"name": name, "primitives": [primitive]}],
        "buffers": [{"byteLength": len(w.blob)}],
        "bufferViews": w.buffer_views,
        "accessors": w.accessors,
    }
    if skin_index is not None:
        gltf["skins"] = [skin]
    if animations:
        gltf["animations"] = animations
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4:
        json_bytes += b" "
    blob = bytes(w.blob)
    while len(blob) % 4:
        blob += b"\0"
    header = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(json_bytes) + 8 + len(blob))
    return header + struct.pack("<II", len(json_bytes), 0x4E4F534A) + json_bytes + struct.pack("<II", len(blob), 0x004E4942) + blob


def convert_file(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(convert(load(src), src.stem))


def main(argv: list[str]) -> int:
    if argv and argv[0] in TREES:
        SRC, OUT = TREES[argv[0]]
        count = 0
        for src in sorted(SRC.rglob("*.msh")):
            rel = src.relative_to(SRC)
            dst = OUT / rel.with_suffix(".glb")
            if dst.exists() and dst.stat().st_mtime >= src.stat().st_mtime:
                continue
            try:
                convert_file(src, dst)
                count += 1
            except Exception as exc:  # noqa: BLE001 - report and continue with the other models
                print(f"FAILED {rel}: {exc}", file=sys.stderr)
        print(f"converted {count} meshes into {OUT}")
        return 0
    if len(argv) != 2:
        print(__doc__)
        return 1
    convert_file(Path(argv[0]), Path(argv[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
