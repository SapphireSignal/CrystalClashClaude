r"""Convert the original Rise of Legions maps (.bcm + .ter) to JSON + raw heightmap.

Usage: python D:\Games\CrystalClashClaude\tools\extract_maps.py

Input : reference/rise-of-legions/Maps/<Map>/<Map>.bcm  (BaseConflict.Map.TMap, XML)
        reference/rise-of-legions/Maps/<Map>/<Map>.ter  (Engine.Terrain.TTerrain, XML)
Output: game/data/maps/<Map>.json
        game/data/maps/<Map>.heights.f32  (little-endian float32, index = x * size + y,
                                            matching the Delphi FGridData[x, y] layout)
"""
import json
import struct
import zlib
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAPS_IN = ROOT / "reference" / "rise-of-legions" / "Maps"
MAPS_OUT = ROOT / "game" / "data" / "maps"
MAP_NAMES = ["Single", "Classic"]


# Engine.Helferlein.Windows.pas DecodeBase64: custom alphabet (digits first), no padding.
ENGINE_B64 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+/"
ENGINE_B64_INDEX = {c: i for i, c in enumerate(ENGINE_B64)}


def decode_engine_base64(text):
    out = bytearray()
    bits = 0
    acc = 0
    for ch in text:
        val = ENGINE_B64_INDEX.get(ch)
        if val is None:
            break  # the Delphi decoder stops at the first invalid char
        acc = (acc << 6) | val
        bits += 6
        if bits >= 8:
            bits -= 8
            out.append((acc >> bits) & 0xFF)
            acc &= (1 << bits) - 1
    return bytes(out)


def parse_bool(text):
    return (text or "").strip().lower() == "true"


def parse_num(text):
    text = (text or "").strip()
    try:
        return int(text)
    except ValueError:
        return float(text)


def parse_vector(node, keys):
    return [parse_num(node.findtext(k)) for k in keys]


def parse_zones(zones_node):
    zones = {}
    for item in zones_node.findall("Item"):
        name = item.findtext("Key")
        polys = []
        polygons_node = item.find("Value/FPolygons")
        if polygons_node is not None:
            for poly_item in polygons_node.findall("Item"):
                polygon = poly_item.find("Polygon")
                nodes = polygon.find("FNodes") if polygon is not None else None
                points = [parse_vector(n, ("X", "Y")) for n in nodes.findall("Item")] if nodes is not None else []
                polys.append({
                    "closed": parse_bool(polygon.findtext("FClosed") if polygon is not None else "False"),
                    "subtractive": parse_bool(poly_item.findtext("Subtractive")),
                    "points": points,
                })
        zones[name] = polys
    return zones


def parse_entities(map_node):
    # TMap has no entity list in the shipped .bcm files; support RWorldEntitiy items if present.
    entities = []
    for container_name in ("Entities", "WorldEntities", "FEntities"):
        container = map_node.find(container_name)
        if container is None:
            continue
        for item in container.findall("Item"):
            entities.append({
                "script_file": item.findtext("ScriptFile"),
                "position": parse_vector(item.find("Position"), ("X", "Y")),
                "front": parse_vector(item.find("Front"), ("X", "Y")),
                "team_id": parse_num(item.findtext("TeamID")),
                "slot_id": parse_num(item.findtext("SlotID")),
            })
    return entities


def read_nested_array(block, size):
    """TXMLSerializer.SetArrayFromMemoryBlock layout: per array level a 1-byte hasChildArrays flag
    and an int32 length, then either child arrays or the raw element bytes (RSaveRawNode = 1 single)."""
    pos = 0
    has_children, count = struct.unpack_from("<?i", block, pos)
    pos += 5
    if not has_children or count != size:
        raise ValueError(f"GridData outer array: has_children={has_children} count={count}, expected {size} rows")
    rows = []
    for _ in range(size):
        has_children, count = struct.unpack_from("<?i", block, pos)
        pos += 5
        if has_children or count != size:
            raise ValueError(f"GridData inner array: has_children={has_children} count={count}, expected {size} floats")
        rows.append(block[pos:pos + count * 4])
        pos += count * 4
    if pos != len(block):
        raise ValueError(f"GridData has {len(block) - pos} trailing bytes")
    return b"".join(rows)


def parse_terrain(ter_path, heights_out):
    root = ET.parse(ter_path).getroot()
    grid = root.find("GridData")
    size = int(grid.get("size"))
    raw = decode_engine_base64("".join(grid.text.split()))
    if grid.get("compressed", "false").lower() == "true":
        raw = zlib.decompress(raw)
    raw = read_nested_array(raw, size)
    heights_out.write_bytes(raw)
    heights = struct.unpack("<%df" % (size * size), raw)
    return {
        "size": size,
        "scale": parse_vector(root.find("FScale"), ("X", "Y", "Z")),
        "position": parse_vector(root.find("FPosition"), ("X", "Y", "Z")),
        "heights_file": heights_out.name,
        "heights_layout": "row-major by x: index = x * size + y",
        "height_min": min(heights),
        "height_max": max(heights),
    }


def extract(name):
    map_dir = MAPS_IN / name
    root = ET.parse(map_dir / f"{name}.bcm").getroot()
    data = {
        "name": name,
        "team_count": parse_num(root.findtext("TeamCount")),
        "player_count": parse_num(root.findtext("PlayerCount")),
        "bounds": {k.lower(): parse_num(root.findtext(f"MapBoundaries/{k}")) for k in ("Left", "Top", "Right", "Bottom")},
        "zones": parse_zones(root.find("Zones")),
        "entities": parse_entities(root),
        "terrain": parse_terrain(map_dir / f"{name}.ter", MAPS_OUT / f"{name}.heights.f32"),
    }
    (MAPS_OUT / f"{name}.json").write_text(json.dumps(data, indent=1), encoding="utf-8")
    return data


def main():
    MAPS_OUT.mkdir(parents=True, exist_ok=True)
    for name in MAP_NAMES:
        d = extract(name)
        print(f"{name}: teams={d['team_count']} players={d['player_count']} bounds={d['bounds']} entities={len(d['entities'])}")
        for zone, polys in d["zones"].items():
            print(f"  zone {zone}: {len(polys)} polygon(s), {sum(len(p['points']) for p in polys)} points")
        t = d["terrain"]
        print(f"  terrain size={t['size']} scale={t['scale']} height min={t['height_min']:.4f} max={t['height_max']:.4f}")


if __name__ == "__main__":
    main()
