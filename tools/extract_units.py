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
RE_INHERITS = re.compile(r"InheritsFrom(?:Preceding)?\s*:\s*string\s*=\s*'([^']+)'")
RE_ARITH = re.compile(r"^[0-9.+\-*/() ]+$")


def strip_annotations(s: str) -> str:
    return re.sub(r"\{@?\w+\}", "", s)  # {@UBL_Health} balance tags and {1766} old-value notes


RE_FOR_LOOP = re.compile(r"for\s+(\w+)\s*:=\s*(\d+)\s+to\s+(\d+)\s+do\s*begin(.*?)end;", re.S)


def expand_for_loops(body: str) -> str:
    """'for i := 3 to 6 do begin ... end;' (Aegis gatlings) -> the block repeated with i replaced."""

    def expand(m: re.Match) -> str:
        var, lo, hi, block = m.group(1), int(m.group(2)), int(m.group(3)), m.group(4)
        return "\n".join(re.sub(rf"\b{var}\b", str(i), block) for i in range(lo, hi + 1))

    return RE_FOR_LOOP.sub(expand, body)


def create_data_body(text: str) -> str:
    """Return the CreateData procedure body with CLIENT-only blocks removed."""
    m = re.search(r"procedure CreateData\(.*?\);(.*?)^end;", text, re.S | re.M)
    if not m:
        return ""
    body = m.group(1)
    body = re.sub(r"\{\$IFDEF CLIENT\}.*?\{\$ENDIF\}", "", body, flags=re.S)
    body = re.sub(r"\{\$IFDEF SERVER\}|\{\$ENDIF\}", "", body)
    return body


RE_ASSIGN = re.compile(r"^\s*(\w+)\s*:=\s*(.+?);\s*$")
RE_LEVEL_CHAIN = re.compile(
    r"if\s+(\w+)\s*<\s*(\d+)\s+then\s*Entity\.Blackboard\.SetValue\((\w+),\s*\[\],\s*(\w+)\)"
    r"((?:\s*else\s+if\s+\1\s*<\s*\d+\s+then\s*Entity\.Blackboard\.SetValue\(\3,\s*\[\],\s*\w+\))*)"
    r"\s*else\s*Entity\.Blackboard\.SetValue\(\3,\s*\[\],\s*(\w+)\);",
    re.S,
)
RE_LEVEL_BAND = re.compile(r"<\s*(\d+)\s+then\s*Entity\.Blackboard\.SetValue\(\w+,\s*\[\],\s*(\w+)\)")


def resolve_level_logic(body: str) -> str:
    """Atlas: 'if CurrentLevel < N then SetValue(...) else if ... else SetValue(...)' chains become one
    SetValue with a '<level:2=a;4=b;*=c>' value, and CreateData local variables (CurrentLevel := Entity.BalanceInt(reLevel);
    AdjustedHealth := AdjustedHealth + 70.0 * Max(0, CurrentLevel - 1)) are substituted into the SetValue lines."""

    def chain(m: re.Match) -> str:
        bands = [f"{m.group(2)}={m.group(4)}"] + [f"{t}={v}" for t, v in RE_LEVEL_BAND.findall(m.group(5))]
        return f"Entity.Blackboard.SetValue({m.group(3)}, [], <level:{';'.join(bands)};*={m.group(6)}>);"

    body = RE_LEVEL_CHAIN.sub(chain, body)
    subs: dict = {}
    out = []
    for line in body.splitlines():
        m = RE_ASSIGN.match(line)
        if m:
            name, expr = m.groups()
            for k, v in subs.items():
                expr = re.sub(rf"\b{k}\b", f"({v})", expr)
            subs[name] = expr
            continue
        for k, v in subs.items():
            line = re.sub(rf"\b{k}\b", v, line)
        out.append(line)
    return "\n".join(out)


def parse_value(raw: str):
    raw = strip_annotations(raw).strip()
    if raw.startswith("<level:") and raw.endswith(">"):
        bands = [b.split("=") for b in raw[7:-1].split(";")]
        return {"by_level": [[int(t), parse_value(v)] for t, v in bands if t != "*"],
                "else": parse_value(dict(bands)["*"])}
    if "Entity.BalanceInt(reLevel)" in raw:
        expr = raw.replace("Entity.BalanceInt(reLevel)", "level").replace("Max(", "max(").replace("Min(", "min(")
        return {"level_expr": re.sub(r"\s+", " ", expr)}
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


FIXED_GROUPS = {"GROUP_BUILDING_LIFETIME": 10, "GROUP_SOUL": 11}
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
        if "GROUP_" in m.group(3):
            # BaseConflict.Constants.pas: spawner groups are 0, GROUP_BUILDING_LIFETIME 10, GROUP_SOUL 11
            groups = [FIXED_GROUPS.get(g, 0) for g in re.findall(r"GROUP_\w+", groups)]
        else:  # numeric groups (also '10+1'), or symbolic ones reserved by inlined procedures
            groups = [int(group_token(g)) if group_token(g).isdigit() else g for g in (x.strip() for x in groups.split(",")) if g]
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


RE_COND_BLOCK = re.compile(r"if Entity\.HasDamageType\((\w+)\) then\s*(?:begin(.*?)end;|((?:(?!\bif\b).)*?;))", re.S)


def parse_components(body: str) -> list:
    """Component declarations; components inside 'if Entity.HasDamageType(dtX) then ...' carry cond = dtX."""
    body = strip_comments(body)
    body = re.sub(r"\{\$IFDEF CLIENT\}.*?\{\$ENDIF\}", "", body, flags=re.S)
    body = expand_for_loops(body)
    out = []
    pos = 0
    for m in RE_COND_BLOCK.finditer(body):
        out += _parse_components_plain(body[pos:m.start()])
        for comp in _parse_components_plain(m.group(2) or m.group(3)):
            comp["cond"] = m.group(1)
            out.append(comp)
        pos = m.end()
    return out + _parse_components_plain(body[pos:])


def group_token(g: str) -> str:
    """'10+1' (LaneNode_Red: block group 10 + team id) -> '11'; names stay symbolic."""
    g = g.strip()
    if re.fullmatch(r"[0-9+\-* ]+", g):
        return str(eval(g, {"__builtins__": {}}, {}))
    return g


def _parse_components_plain(body: str) -> list:
    body = strip_comments(body)
    body = re.sub(r"\{\$IFDEF SERVER\}|\{\$ENDIF\}|\{\$IFNDEF \w+\}|\{\$ELSE\}", "", body)
    out = []
    for stmt in body.split(";"):
        stmt = " ".join(stmt.split())
        skin = re.match(r"^if Entity\.SkinID\s*=.*?\bthen\b(.*?)\belse\b(.*)$", stmt)
        if skin:  # skins only change visuals: keep the default (else) branch (PhaseDrone's Invincibility ApplyBlue)
            stmt = skin.group(2)
        # drop leading control flow such as "if Game.IsPvP then" or "begin"
        stmt = re.sub(r"^(?:.*?\bthen\b\s*)?(?:begin\s*)?(?:else\s*)?", "", stmt, count=1) if "then" in stmt or stmt.startswith(("begin", "else")) else stmt
        m = RE_COMPONENT.match(stmt.strip())
        if not m:
            continue
        cls, grouped, groups, extra, chain = m.groups()
        comp = {"class": cls, "groups": [group_token(g) for g in groups.split(",") if g.strip()] if groups is not None else []}
        if extra:
            comp["args"] = parse_args(extra)
        calls = []
        for cm in RE_CALL.finditer(chain or ""):
            calls.append([cm.group(1), parse_args(cm.group(2)) if cm.group(2) else []])
        if calls:
            comp["calls"] = calls
        out.append(comp)
    return out


RE_LOCAL_PROC = re.compile(
    r"^procedure (\w+)\(Entity : TEntity(?:;([^)]*))?\);\s*(?:var ([^;]*);)?\s*begin(.*?)^end;", re.S | re.M)


def _names(decl: str) -> list:
    """'a, b : integer; c : string' -> ['a', 'b', 'c']"""
    out = []
    for part in decl.split(";"):
        if ":" in part:
            out += [n.strip() for n in part.split(":")[0].split(",") if n.strip()]
    return out


def inline_local_procedures(text: str) -> str:
    """VoidSlime.ets builds its abilities with local procedures (ApplyAbsorbToSelf(Entity, upStunned) ...) that
    reserve fresh groups. Expand every call in place: parameters become the arguments, reserved groups become
    unique symbolic names, so the components look like ordinary declarations."""
    procs = {}
    for m in RE_LOCAL_PROC.finditer(text):
        name, params, local_vars, body = m.groups()
        if name in ("CreateData", "CreateMeta", "CreateEntity") or not name.startswith("Apply"):
            continue
        procs[name] = (_names(params or ""), _names(local_vars or ""), body)
    if not procs:
        return text
    counter = {}

    def expand(m: re.Match) -> str:
        name = m.group(1)
        if name not in procs:
            return m.group(0)
        params, local_vars, body = procs[name]
        args = [a.strip() for a in m.group(2).split(",")]
        counter[name] = counter.get(name, 0) + 1
        body = re.sub(r"^\s*\w+\s*:=\s*Entity\.ReserveFreeGroup\(\);\s*$", "", body, flags=re.M)
        for var in local_vars:
            body = re.sub(rf"\b{var}\b", f"{name}{counter[name]}{var}", body)
        for pname, arg in zip(params, args):
            body = re.sub(rf"\b{pname}\b", lambda _m, a=arg: a, body)  # args may hold backslashes ('Modifiers\Stun.dws')
        return body

    return re.sub(r"^\s*(\w+)\(Entity\s*,\s*([^;]*?)\);\s*$", expand, text, flags=re.M)


def create_entity_body(text: str) -> str:
    m = re.search(r"procedure CreateEntity\(.*?\);(.*?)^end;", text, re.S | re.M)
    return m.group(1) if m else ""


def create_meta_body(text: str) -> str:
    """CreateMeta holds shared (server + client) components such as spell target constraints."""
    m = re.search(r"procedure CreateMeta\(.*?\);(.*?)^end;", text, re.S | re.M)
    return m.group(1) if m else ""


def parse_modifier(path: Path) -> dict:
    """Scripts/Modifiers/*.dws: procedure Apply(Entity; params) with SetValue lines and components."""
    text = path.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"(?:procedure|function) Apply\((.*?)\)(?:\s*:\s*[\w ]+)?;(.*?)^end;", text, re.S | re.M)
    if not m:
        return {}
    params = [p.split(":")[0].strip() for p in m.group(1).split(";")[1:] if ":" in p]
    body = m.group(2)
    defaults: dict = {}
    delegate = re.search(r"(Apply\w+)\(Entity\s*,\s*([^)]*)\)", body)
    if delegate and "Create" not in body:  # Frozen.dws: Apply just calls ApplyWithDuration(Entity, DEFAULT_DURATION)
        target = re.search(rf"procedure {delegate.group(1)}\((.*?)\);(.*?)^end;", text, re.S | re.M)
        if target:
            params = [p.split(":")[0].strip() for p in target.group(1).split(";")[1:] if ":" in p]
            args = [a.strip() for a in delegate.group(2).split(",")]
            defines = dict(re.findall(r"^#define\s+(\w+)\s+([0-9.]+)", text, re.M))
            body = target.group(2)
            for name, arg in zip(params, args):
                defaults[name] = parse_value(defines.get(arg, arg))
    raw = re.search(r"function Apply(?:Raw|Effect)\(.*?\)\s*:\s*\w+;(.*?)^end;", text, re.S | re.M)
    if raw:  # some scripts split the server part into ApplyRaw/ApplyEffect (Invincibility, BlessingGrievousWounds)
        body = raw.group(1) + "\n" + body
    body = strip_comments(body)
    body = re.sub(r"\{\$IFDEF CLIENT\}.*?\{\$ENDIF\}", "", body, flags=re.S)
    consts = {k: float(v) if "." in v else int(v) for k, v in RE_CONST.findall(body)}
    for k, v in re.findall(r"^#define\s+(\w+)\s+([0-9.]+)", text, re.M):
        consts[k] = float(v) if "." in v else int(v)
    values: dict = {}
    conditional = re.compile(
        r"if Entity\.HasDamageType\((\w+)\) then\s*Entity\.Blackboard\.SetValue\((\w+),\s*\[(\w+)\],\s*([^)]+)\)"
        r"\s*else\s*Entity\.Blackboard\.SetValue\(\2,\s*\[\3\],\s*([^)]+)\)", re.S)
    for m in conditional.finditer(body):
        values.setdefault(m.group(2), {})[m.group(3)] = {"if": m.group(1), "then": parse_value(m.group(4).strip()), "else": parse_value(m.group(5).strip())}
    body = conditional.sub("", body)
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
    return {"params": params, "defaults": defaults, "consts": consts, "values": values, "components": parse_components(body)}


def extract_modifiers() -> dict:
    out = {}
    for path in sorted(SCRIPTS.glob("Modifiers/*.dws")):
        data = parse_modifier(path)
        if data:
            out[path.stem] = data
    for path in sorted(SCRIPTS.glob("Links/*.dws")):
        data = parse_modifier(path)
        if data:
            out["Links/" + path.stem] = data
    for path in sorted(SCRIPTS.glob("Spells/**/*.dws")):
        data = parse_modifier(path)
        if data:
            out[str(path.relative_to(SCRIPTS).with_suffix("")).replace("\\", "/")] = data
    return out


def parse_script(path: Path) -> dict:
    text = inline_local_procedures(path.read_text(encoding="utf-8", errors="replace"))
    body = create_data_body(text)
    data: dict = {"script": str(path.relative_to(SCRIPTS)).replace("\\", "/"), "values": {}}
    inc = RE_INCLUDE.search(text)
    if inc:
        data["template"] = inc.group(1)
        limited_life = re.search(r"InitBuildingData\(\s*Entity\s*,\s*True\s*\)", text) is not None
        for event, by_group in template_values(inc.group(1)).items():
            if event == "eiCooldown" and not limited_life:
                by_group = {g: v for g, v in by_group.items() if g != "10"}  # GROUP_BUILDING_LIFETIME only if LimitedLifeTime
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
    parse_set_lines(resolve_level_logic(body), data["values"])
    entity_body = create_entity_body(text)
    parse_set_lines(re.sub(r"\{\$IFDEF CLIENT\}.*?\{\$ENDIF\}", "", entity_body, flags=re.S), data["values"])
    data["components"] = data.get("components", []) + parse_components(create_meta_body(text)) + parse_components(entity_body)
    return data


RE_SPELL_INIT = re.compile(r"PrepareSpellData\(Entity,\s*SpellGroup,\s*ChargeGroup,\s*(True|False)\s*,\s*(?:\{@\w+\})?(\d)")


def parse_spell(path: Path) -> dict:
    """Spells/*/*.sps: CreateData(Entity, SpellGroup, ChargeGroup) + AddSpell body, groups stay symbolic."""
    text = path.read_text(encoding="utf-8", errors="replace")
    data: dict = {"script": str(path.relative_to(SCRIPTS)).replace("\\", "/"), "spell": True, "values": {}, "components": []}
    m = RE_SPELL_INIT.search(text)
    if m:
        data["legendary"] = m.group(1) == "True"
        data["tier"] = int(m.group(2))
    bodies = []
    for name in ("CreateData", "AddSpell"):
        mm = re.search(r"procedure %s\(.*?\);(.*?)^end;" % name, text, re.S | re.M)
        if mm:
            bodies.append(strip_comments(re.sub(r"\{\$IFDEF CLIENT\}.*?\{\$ENDIF\}", "", mm.group(1), flags=re.S)))
    for body in bodies:
        for line in body.splitlines():
            line = line.strip()
            mm = re.match(r"Entity\.Blackboard\.Set(Indexed)?Value\(\s*(\w+)\s*,\s*\[([^\]]*)\]\s*,\s*(?:(\w+)\s*,\s*)?(.+?)\);", line)
            if not mm:
                continue
            indexed, event, groups, index, raw = mm.groups()
            raw = strip_annotations(raw).strip()
            cost = re.match(r"GetCardBaseCost\(.*?\)\s*([+-]\s*\d+)?$", raw)
            value = ("base_cost" + cost.group(1).replace(" ", "")) if cost else parse_value(raw)
            key = event if not indexed else f"{event}.{index}"
            entry = data["values"].setdefault(key, {})
            for g in [x.strip() for x in groups.split(",") if x.strip()]:
                entry[g] = value
        data["components"] += parse_components(body)
    return data


def extract_units() -> dict:
    units = {}
    paths = list(SCRIPTS.glob("Units/**/*.ets")) + list(SCRIPTS.glob("Projectiles/**/*.ets")) + list(SCRIPTS.glob("Spells/**/*.ets")) \
        + list(SCRIPTS.glob("Links/*.ets")) + list(SCRIPTS.glob("Effects/**/*.ets"))
    for path in sorted(paths):
        units[str(path.relative_to(SCRIPTS).with_suffix("")).replace("\\", "/")] = parse_script(path)
    for path in sorted(SCRIPTS.glob("Spells/**/*.sps")):
        units[str(path.relative_to(SCRIPTS)).replace("\\", "/")] = parse_spell(path)   # key keeps .sps
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


def fix_pattern_case(units: dict) -> None:
    """Scripts name patterns with sloppy case (VoidWorm.ets: 'VoidwormProjectile'); the original file system
    was case-insensitive, so map every pattern to the real script key."""
    lower = {k.lower(): k for k in units}
    for data in units.values():
        for event in ("eiWelaUnitPattern", "eiLinkPattern"):
            by_group = data.get("values", {}).get(event, {})
            for g, v in list(by_group.items()):
                if isinstance(v, str):
                    key = v.replace("\\", "/")
                    if key not in units and key.lower() in lower:
                        by_group[g] = lower[key.lower()].replace("/", "\\")


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    units = extract_units()
    fix_pattern_case(units)
    cards = extract_cards()
    lower = {k.lower(): k for k in units}
    for card in cards:   # the card registry spells some scripts differently (SaplingCharge vs Saplingcharge.sps)
        if card["script"] not in units and card["script"].lower() in lower:
            card["script"] = lower[card["script"].lower()]
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
