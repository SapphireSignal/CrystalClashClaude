"""Extract unit/card data from the original Rise of Legions scripts into game/data/*.json.

Sources (read-only): reference/rise-of-legions/Scripts/**/*.ets|*.sps, BaseConflict.Constants.Cards.pas, Lang/cards.csv
Output: game/data/units.json, game/data/cards.json

Only the CreateData section of each script is parsed (pure numbers), skipping {$IFDEF CLIENT} blocks.
League-dependent values like f([a,b,c,d,e], Entity.CardLeague) are kept as 5-element lists.
"""
import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / "reference" / "rise-of-legions"
SCRIPTS = REF / "Scripts"
OUT = ROOT / "game" / "data"

RE_SET = re.compile(
    r"Entity\.Blackboard\.Set(Indexed)?Value\(\s*(\w+)\s*,\s*\[([^\]]*)\]\s*,\s*(?:(\w+)\s*,\s*)?(.+?)\);\s*(?://.*)?$"
)
RE_RADIUS = re.compile(r"Entity\.CollisionRadius\s*:=\s*([0-9.]+)")
RE_INIT_CARD = re.compile(r"Init(Drop|Spawner|BuildingCard)Data\(Entity,\s*(True|False)\s*,\s*(?:\{@\w+\})?(\d)")
RE_LEAGUE_ARR = re.compile(r"^(?:([0-9.]+)\s*\*\s*)?[fi]\(\s*\[([^\]]*)\]\s*,\s*Entity\.CardLeague(?:\([^)]*\))?\s*\)$")
RE_INHERITS = re.compile(r"InheritsFrom\s*:\s*string\s*=\s*'([^']+)'")
RE_ARITH = re.compile(r"^[0-9.+\-*/() ]+$")


def strip_annotations(s: str) -> str:
    return re.sub(r"\{@\w+\}", "", s)


def create_data_body(text: str) -> str:
    """Return the CreateData procedure body with CLIENT-only blocks removed."""
    m = re.search(r"procedure CreateData\(.*?\);(.*?)^end;", text, re.S | re.M)
    if not m:
        return ""
    body = m.group(1)
    body = re.sub(r"\{\$IFDEF CLIENT\}.*?\{\$ENDIF\}", "", body, flags=re.S)
    body = re.sub(r"\{\$IFDEF SERVER\}|\{\$ENDIF\}", "", body)
    return body


def parse_value(raw: str):
    raw = strip_annotations(raw).strip()
    m = RE_LEAGUE_ARR.match(raw)
    if m:
        scale = float(m.group(1)) if m.group(1) else 1.0
        values = [parse_value(x) for x in m.group(2).split(",")]
        return [v * scale for v in values] if scale != 1.0 else values
    if raw in ("True", "False"):
        return raw == "True"
    if raw.startswith("[") and raw.endswith("]"):
        return [x.strip() for x in raw[1:-1].split(",") if x.strip()]
    if raw.startswith("'") and raw.endswith("'"):
        return raw[1:-1]
    m = re.fullmatch(r"\(?\s*([0-9.]+)\s*/\s*([0-9.]+)\s*\)?", raw)
    if m:
        return float(m.group(1)) / float(m.group(2))
    try:
        return int(raw)
    except ValueError:
        pass
    try:
        return float(raw)
    except ValueError:
        pass
    if RE_ARITH.match(raw):
        return eval(raw, {"__builtins__": {}}, {})  # digits and operators only
    return raw  # expression we do not evaluate; kept verbatim


RE_INCLUDE = re.compile(r"\{\$INCLUDE\s+'(\w+Template)\.dws'\}")
_template_cache: dict = {}


def template_values(name: str) -> dict:
    """SetValue lines of the Init<X>Data procedure in HelperScripts/<name>.dws (e.g. InitUnitData)."""
    if name in _template_cache:
        return _template_cache[name]
    text = (SCRIPTS / "HelperScripts" / f"{name}.dws").read_text(encoding="utf-8", errors="replace")
    values: dict = {}
    m = re.search(r"procedure Init\w+Data\(.*?\);(.*?)^end;", text, re.S | re.M)
    if m:
        body = re.sub(r"\{\$IFDEF CLIENT\}.*?\{\$ENDIF\}", "", m.group(1), flags=re.S)
        parse_set_lines(body, values)
    _template_cache[name] = values
    return values


def parse_set_lines(body: str, values: dict) -> None:
    for line in body.splitlines():
        line = line.strip()
        m = RE_SET.match(line)
        if not m:
            continue
        indexed, event, groups, index, raw = m.groups()
        groups = [int(g) for g in re.findall(r"\d+", groups)] or []
        if "GROUP_" in m.group(3):
            groups = [0]  # GROUP_DROP_SPAWNER / GROUP_SPELL_SPAWNER / GROUP_TEMPLATE_SPAWNER are all 0
        value = parse_value(raw)
        key = event if not indexed else f"{event}.{index}"
        entry = values.setdefault(key, {})
        for g in (groups or ["*"]):
            entry[str(g)] = value


RE_COMPONENT = re.compile(
    r"(T\w+)\.Create(Grouped)?\(\s*Entity\s*(?:,\s*\[([^\]]*)\])?\s*(?:,\s*(.*?))?\)((?:\s*\.\w+(?:\([^()]*(?:\([^()]*\)[^()]*)*\))?)*)\s*$",
    re.S,
)
RE_CALL = re.compile(r"\.(\w+)(?:\(([^()]*(?:\([^()]*\)[^()]*)*)\))?")
RE_CONST = re.compile(r"^\s*(?:const\s+)?(\w+)\s*=\s*([0-9.]+)\s*;", re.M)


def parse_args(raw: str) -> list:
    """Split a Delphi argument list at top-level commas and parse each value."""
    args, depth, cur = [], 0, ""
    for ch in raw:
        if ch in "[(":
            depth += 1
        elif ch in "])":
            depth -= 1
        if ch == "," and depth == 0:
            args.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        args.append(cur)
    return [parse_value(a) for a in args]


def strip_comments(body: str) -> str:
    return re.sub(r"//[^\n]*", "", body)


def parse_components(body: str) -> list:
    """Component declarations (class, groups, fluent calls) from a CreateEntity / Apply body."""
    body = strip_comments(body)
    body = re.sub(r"\{\$IFDEF CLIENT\}.*?\{\$ENDIF\}", "", body, flags=re.S)
    body = re.sub(r"\{\$IFDEF SERVER\}|\{\$ENDIF\}|\{\$IFNDEF \w+\}|\{\$ELSE\}", "", body)
    out = []
    for stmt in body.split(";"):
        stmt = " ".join(stmt.split())
        # drop leading control flow such as "if Game.IsPvP then" or "begin"
        stmt = re.sub(r"^(?:.*?\bthen\b\s*)?(?:begin\s*)?(?:else\s*)?", "", stmt, count=1) if "then" in stmt or stmt.startswith(("begin", "else")) else stmt
        m = RE_COMPONENT.match(stmt.strip())
        if not m:
            continue
        cls, grouped, groups, extra, chain = m.groups()
        comp = {"class": cls, "groups": [g.strip() for g in groups.split(",") if g.strip()] if groups is not None else []}
        if extra:
            comp["args"] = parse_args(extra)
        calls = []
        for cm in RE_CALL.finditer(chain or ""):
            calls.append([cm.group(1), parse_args(cm.group(2)) if cm.group(2) else []])
        if calls:
            comp["calls"] = calls
        out.append(comp)
    return out


def create_entity_body(text: str) -> str:
    m = re.search(r"procedure CreateEntity\(.*?\);(.*?)^end;", text, re.S | re.M)
    return m.group(1) if m else ""


def parse_modifier(path: Path) -> dict:
    """Scripts/Modifiers/*.dws: procedure Apply(Entity; params) with SetValue lines and components."""
    text = path.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"procedure Apply\((.*?)\);(.*?)^end;", text, re.S | re.M)
    if not m:
        return {}
    params = [p.split(":")[0].strip() for p in m.group(1).split(";")[1:] if ":" in p]
    body = strip_comments(m.group(2))
    body = re.sub(r"\{\$IFDEF CLIENT\}.*?\{\$ENDIF\}", "", body, flags=re.S)
    consts = {k: float(v) if "." in v else int(v) for k, v in RE_CONST.findall(body)}
    values: dict = {}
    for line in body.splitlines():
        line = line.strip()
        mm = re.match(r"Entity\.Blackboard\.Set(Indexed)?Value\(\s*(\w+)\s*,\s*\[([^\]]*)\]\s*,\s*(?:(\w+)\s*,\s*)?(.+?)\);", line)
        if not mm:
            continue
        indexed, event, groups, index, raw = mm.groups()
        raw = strip_annotations(raw).strip()
        for name, const_value in consts.items():
            raw = re.sub(rf"\b{name}\b", str(const_value), raw)
        value = parse_value(raw)
        key = event if not indexed else f"{event}.{index}"
        entry = values.setdefault(key, {})
        for g in [x.strip() for x in groups.split(",") if x.strip()]:
            entry[g] = value
    return {"params": params, "consts": consts, "values": values, "components": parse_components(body)}


def extract_modifiers() -> dict:
    out = {}
    for path in sorted(SCRIPTS.glob("Modifiers/*.dws")):
        data = parse_modifier(path)
        if data:
            out[path.stem] = data
    return out


def parse_script(path: Path) -> dict:
    text = path.read_text(encoding="utf-8", errors="replace")
    body = create_data_body(text)
    data: dict = {"script": str(path.relative_to(SCRIPTS)).replace("\\", "/"), "values": {}}
    inc = RE_INCLUDE.search(text)
    if inc:
        data["template"] = inc.group(1)
        for event, by_group in template_values(inc.group(1)).items():
            data["values"][event] = dict(by_group)
    m = RE_INHERITS.search(text)
    if m:
        parent = parse_script(SCRIPTS / m.group(1).replace("\\", "/"))
        data["inherits"] = parent["script"]
        for k in ("collision_radius", "card_kind", "legendary", "tier"):
            if k in parent:
                data[k] = parent[k]
        for event, by_group in parent["values"].items():
            data["values"][event] = dict(by_group)
        data["components"] = parent["components"]
    m = RE_RADIUS.search(body)
    if m:
        data["collision_radius"] = float(m.group(1))
    m = RE_INIT_CARD.search(body)
    if m:
        data["card_kind"] = m.group(1)
        data["legendary"] = m.group(2) == "True"
        data["tier"] = int(m.group(3))
    parse_set_lines(body, data["values"])
    data["components"] = data.get("components", []) + parse_components(create_entity_body(text))
    return data


def extract_units() -> dict:
    units = {}
    for path in sorted(list(SCRIPTS.glob("Units/**/*.ets")) + list(SCRIPTS.glob("Projectiles/**/*.ets"))):
        units[str(path.relative_to(SCRIPTS).with_suffix("")).replace("\\", "/")] = parse_script(path)
    return units


def extract_cards() -> list:
    pas = (REF / "BaseConflict.Constants.Cards.pas").read_text(encoding="utf-8", errors="replace")
    names = {}
    with (REF / "Lang" / "cards.csv").open(encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f, delimiter=";"):
            names[row["Column"]] = row["en"]
    cards = []
    for m in re.finditer(
        r"AddCard\('([0-9a-f-]+)',\s*TCardInfo\.Create\((ct\w+),\s*\[([^\]]*)\],\s*'([^']+)',\s*(\d)\)", pas
    ):
        uid, ctype, colors, script, tier = m.groups()
        base = script.replace("\\", "/")
        short = Path(base).stem.lower()
        cards.append({
            "uid": uid,
            "type": ctype,
            "colors": [c.strip() for c in colors.split(",") if c.strip()],
            "script": base,
            "tier": int(tier),
            "name": names.get(f"card_name_{short}") or names.get(f"card_name_{short.removesuffix('drop').removesuffix('spawner').removesuffix('building')}", short),
        })
    return cards


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    units = extract_units()
    cards = extract_cards()
    modifiers = extract_modifiers()
    (OUT / "units.json").write_text(json.dumps(units, separators=(",", ":")), encoding="utf-8")
    (OUT / "cards.json").write_text(json.dumps(cards, indent=1), encoding="utf-8")
    (OUT / "modifiers.json").write_text(json.dumps(modifiers, separators=(",", ":")), encoding="utf-8")
    print(f"units: {len(units)}  cards: {len(cards)}  modifiers: {len(modifiers)}")
    missing = [u for u, d in units.items() if "eiResourceCap.reHealth" not in d["values"] and "card_kind" not in d]
    print(f"units without health (spawner/drop cards expected): {len(missing)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
