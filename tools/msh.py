"""Reader for the original engine's `.msh` mesh cache (delphi3d-engine Engine.Core.Mesh.pas TEngineRawMesh V.01).

The cache holds exactly what the game rendered: raw FBX units, bone hierarchy with local matrices, skin
bone links (bone-space offset matrices that already include the inverse mesh offset, Engine.Mesh.pas:1717),
vertices with bone weights and the bone animation channels (times in ms). Matrices are RMatrix4x3 (row-vector
style 3x3 plus a translation column, converted to column-vector form here); hierarchy = `Parent * Child`
(Engine.Mesh.pas:2195), skinning = `Combined * Offset * v` (Engine.Mesh.pas:2029).
"""
from __future__ import annotations

import struct
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

SHORTSTRING = 256
MAX_MORPH_TARGET_COUNT = 8
RECORD_BYTES = MAX_MORPH_TARGET_COUNT * 12 + 8 + 36 + 32 + 12   # SizeOf(RVertexMorph...) = 184


def vertex_bytes(morph_count: int) -> int:
    """RVertexMorphPositionNormalSNormalTextureTangentBinormalBoneIndicesWeight.GetSize: positions per morph
    target, uv, normal + tangent + binormal, bone weights + indices, smoothed normal."""
    return morph_count * 12 + 8 + 36 + 32 + 12


@dataclass
class Bone:
    name: str
    local: np.ndarray          # 4x4
    children: list["Bone"] = field(default_factory=list)


@dataclass
class SkinLink:
    bone: str
    offset: np.ndarray         # 4x4 bone-space offset matrix


@dataclass
class Channel:
    bone: str
    times: np.ndarray          # ms
    translation: np.ndarray    # n x 3
    scale: np.ndarray          # n x 3
    rotation: np.ndarray       # n x 4 (x, y, z, w)


@dataclass
class Animation:
    name: str
    channels: list[Channel]


@dataclass
class Msh:
    bbox_min: np.ndarray
    bbox_max: np.ndarray
    positions: np.ndarray      # n x 3 (morph target 0)
    normals: np.ndarray
    uvs: np.ndarray
    bone_weights: np.ndarray   # n x 4
    bone_indices: np.ndarray   # n x 4 (int)
    colors: np.ndarray         # n x 4
    indices: np.ndarray
    root: Bone | None
    bones: list[Bone]          # flat, in file order
    skin: list[SkinLink]
    animations: list[Animation]
    sphere_center: np.ndarray = field(default_factory=lambda: np.zeros(3))
    sphere_radius: float = 0.0

    def bone_by_name(self, name: str) -> Bone | None:
        low = name.lower()
        for b in self.bones:
            if b.name.lower() == low:
                return b
        return None

    def global_matrices(self, local_override: dict[str, np.ndarray] | None = None) -> dict[str, np.ndarray]:
        """CombinedMatrix per bone = Parent * (animated or original local), root parent = identity."""
        result: dict[str, np.ndarray] = {}

        def walk(bone: Bone, parent: np.ndarray) -> None:
            local = local_override.get(bone.name, bone.local) if local_override else bone.local
            combined = parent @ local
            result[bone.name] = combined
            for child in bone.children:
                walk(child, combined)

        if self.root is not None:
            walk(self.root, np.eye(4))
        return result

    def skinned_positions(self, local_override: dict[str, np.ndarray] | None = None) -> np.ndarray:
        """Vertex positions after skinning (Engine.Mesh.pas:2029: Combined * Offset * v, weighted)."""
        if not self.skin:
            return self.positions.copy()
        globals_ = self.global_matrices(local_override)
        mats = np.array([globals_.get(link.bone, np.eye(4)) @ link.offset for link in self.skin])
        out = np.zeros_like(self.positions)
        hom = np.concatenate([self.positions, np.ones((len(self.positions), 1), dtype=np.float32)], axis=1)
        for j in range(4):
            idx = self.bone_indices[:, j]
            w = self.bone_weights[:, j]
            valid = (w > 0) & (idx >= 0) & (idx < len(mats))
            if not valid.any():
                continue
            transformed = np.einsum("nij,nj->ni", mats[idx[valid]], hom[valid])[:, :3]
            out[valid] += transformed * w[valid, None]
        return out


def _matrix4x3(values: tuple[float, ...]) -> np.ndarray:
    """RMatrix4x3 rows (_11 _12 _13 _41 / _21 _22 _23 _42 / _31 _32 _33 _43) hold a row-vector style 3x3 with
    the translation in the last column; transposing the 3x3 gives a column-vector matrix (verified: the bind
    pose then reproduces the untransformed footman upright)."""
    m = np.eye(4, dtype=np.float64)
    m[0, :3] = (values[0], values[4], values[8])
    m[1, :3] = (values[1], values[5], values[9])
    m[2, :3] = (values[2], values[6], values[10])
    m[0, 3], m[1, 3], m[2, 3] = values[3], values[7], values[11]
    return m


def _shortstring(raw: bytes) -> str:
    length = raw[0]
    return raw[1:1 + length].decode("latin-1")


def load(path: Path) -> Msh:
    data = Path(path).read_bytes()
    pos = 0

    def read(fmt: str):
        nonlocal pos
        values = struct.unpack_from("<" + fmt, data, pos)
        pos += struct.calcsize("<" + fmt)
        return values

    ident, protector, version = data[0:5], data[5:10], data[10:15]
    if _shortstring(ident) != "%KMF" or _shortstring(version) != "V.01":
        raise ValueError(f"{path}: not a V.01 engine mesh")
    pos = 15
    (header_length,) = read("I")
    (morph_count,) = read("I")
    bbox = read("6f")
    sphere = read("4f")   # bounding sphere centre + radius (vegetation sizes divide by 2 * radius)
    pos += 33    # OriginalFileHash string[32]
    # vertex chunk
    pos += 5     # protector string[4]
    vertex_size, vertex_count = read("II")
    expected = vertex_bytes(morph_count)
    if vertex_size != expected:
        raise ValueError(f"{path}: vertex size {vertex_size} != {expected}")
    # the stream holds full records (SizeOf with MAX_MORPH_TARGET_COUNT positions); VertexSize is only a version check
    floats = RECORD_BYTES // 4
    raw = np.frombuffer(data, dtype=np.float32, count=vertex_count * floats, offset=pos).reshape(vertex_count, floats)
    pos += vertex_count * RECORD_BYTES
    base = MAX_MORPH_TARGET_COUNT * 3
    positions = raw[:, 0:3].copy()
    uvs = raw[:, base:base + 2].copy()
    normals = raw[:, base + 2:base + 5].copy()
    weights = raw[:, base + 11:base + 15].copy()
    bone_idx = raw[:, base + 15:base + 19].astype(np.int32)
    colors = np.frombuffer(data, dtype=np.float32, count=vertex_count * 4, offset=pos).reshape(vertex_count, 4).copy()
    pos += vertex_count * 16
    # index chunk
    pos += 5
    (index_count,) = read("I")
    indices = np.frombuffer(data, dtype=np.uint32, count=index_count, offset=pos).copy()
    pos += index_count * 4
    # bones
    pos += 5
    (bone_count,) = read("I")
    flat: list[tuple[str, np.ndarray, int]] = []
    for _ in range(bone_count):
        name = _shortstring(data[pos:pos + 129])
        pos += 129
        mat = _matrix4x3(read("12f"))
        (child_count,) = read("i")
        flat.append((name, mat, child_count))
    bones: list[Bone] = []
    cursor = 0

    def build() -> Bone:
        nonlocal cursor
        name, mat, child_count = flat[cursor]
        cursor += 1
        bone = Bone(name, mat)
        bones.append(bone)
        for _ in range(child_count):
            bone.children.append(build())
        return bone

    root = build() if bone_count > 0 else None
    # skin links
    pos += 5
    (link_count,) = read("I")
    skin = []
    for _ in range(link_count):
        name = _shortstring(data[pos:pos + 129])
        pos += 129
        skin.append(SkinLink(name, _matrix4x3(read("12f"))))
    # animations
    pos += 5
    bone_anim_count, morph_anim_count = read("II")
    animations = []
    for _ in range(bone_anim_count):
        name = _shortstring(data[pos:pos + SHORTSTRING])
        pos += SHORTSTRING
        (channel_count,) = read("i")
        channels = []
        for _ in range(channel_count):
            (key_count,) = read("i")
            keys = np.frombuffer(data, dtype=np.float32, count=key_count * 11, offset=pos).reshape(key_count, 11)
            times = np.frombuffer(data, dtype=np.int32, count=key_count * 11, offset=pos).reshape(key_count, 11)[:, 0].copy()
            pos += key_count * 44
            target = _shortstring(data[pos:pos + SHORTSTRING])
            pos += SHORTSTRING
            channels.append(Channel(target, times, keys[:, 1:4].copy(), keys[:, 4:7].copy(), keys[:, 7:11].copy()))
        animations.append(Animation(name, channels))
    msh = Msh(np.array(bbox[:3]), np.array(bbox[3:]), positions, normals, uvs, weights, bone_idx, colors, indices, root, bones, skin, animations)
    msh.sphere_center = np.array(sphere[:3])
    msh.sphere_radius = float(sphere[3])
    return msh


if __name__ == "__main__":
    import sys
    m = load(Path(sys.argv[1]))
    print(f"vertices {len(m.positions)} indices {len(m.indices)} bones {len(m.bones)} skin links {len(m.skin)} animations {[a.name for a in m.animations]}")
    print("bbox", m.bbox_min, m.bbox_max)
    for b in m.bones[:6]:
        print("bone", b.name, "children", len(b.children), "local t", b.local[:3, 3])
    for l in m.skin[:4]:
        print("skin", l.bone, "offset t", l.offset[:3, 3])
    for a in m.animations:
        for c in a.channels[:3]:
            print("anim", a.name, "channel", c.bone, "keys", len(c.times), "t", c.times[0], c.times[-1], "first T", c.translation[0], "S", c.scale[0], "R", c.rotation[0])
    p = m.skinned_positions()
    print("skinned bbox", p.min(axis=0), p.max(axis=0))
