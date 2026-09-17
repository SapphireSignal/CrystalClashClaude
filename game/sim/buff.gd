class_name Buff
## An applied modifier script (Scripts/Modifiers/*.dws via game/data/modifiers.json). The script's
## symbolic groups ("Group", "DoTGroup"...) get fresh group ids on the entity. The components are
## interpreted into stat modifiers (TModifier*Component), unit properties (TUnitPropertyComponent),
## a duration (TWelaReadyCooldownComponent + TWelaEffectRemoveAfterUseComponent) and DoT ticks.

const MODIFIERS_PATH := "res://game/data/modifiers.json"
static var _db: Dictionary = {}

var name: String
var source_id: int = 0
var buff_types: Array = []          # btPositive, btNegative, btState, btSummoningSickness ...
var properties: Array = []          # unit properties granted while active
var expires_at: int = -1
var values: Dictionary = {}         # "eiWelaModifier" -> {group_id: value}
var damage_mods: Array = []         # {groups, value_group, multiply, must_have, factor}
var speed_factor: float = 1.0
var cooldown_factor: float = 1.0
var cooldown_groups: Array = []
var armor_delta: int = 0
var armor_set: int = -1
var health_bonus: float = 0.0
var stops_movement: bool = false
var dot_damage: float = 0.0
var dot_type: int = 0
var dot_interval: int = 0
var dot_times: int = 0
var dot_next_at: int = 0


static func load_db() -> void:
	if not _db.is_empty():
		return
	var file := FileAccess.open(MODIFIERS_PATH, FileAccess.READ)
	assert(file != null, "missing %s, run tools/extract_units.py" % MODIFIERS_PATH)
	_db = JSON.parse_string(file.get_as_text())


static func exists(script_name: String) -> bool:
	load_db()
	return _db.has(script_name)


## Build a buff from a modifier script. `params` maps script parameters (e.g. "Duration") to values.
static func create(script_name: String, now: int, params: Dictionary = {}) -> Buff:
	load_db()
	assert(_db.has(script_name), "unknown modifier script %s" % script_name)
	var data: Dictionary = _db[script_name]
	var b := Buff.new()
	b.name = script_name
	var group_ids := {}   # symbolic name -> id; scripts use ReserveFreeGroup(), ids start above the fixed ones
	var gid := func(sym: String) -> int:
		if sym.is_valid_int():
			return int(sym)
		if not group_ids.has(sym):
			group_ids[sym] = 20 + group_ids.size()
		return group_ids[sym]
	for event in data["values"]:
		for sym in data["values"][event]:
			var v: Variant = data["values"][event][sym]
			if v is String and params.has(v):
				v = params[v]
			b.values.get_or_add(event, {})[gid.call(sym)] = v
	var duration_group := -1
	var has_remove := false
	for comp in data["components"]:
		var groups: Array = comp["groups"].map(func(s): return gid.call(s))
		var g: int = groups[0] if not groups.is_empty() else -1
		match comp["class"]:
			"TAutoBrainBuffComponent":
				b.buff_types = comp.get("args", [[]])[0]
			"TUnitPropertyComponent":
				b.properties.append_array(comp.get("args", [[]])[0])
			"TWelaReadyCooldownComponent":
				if duration_group < 0:
					duration_group = g
			"TWelaEffectRemoveAfterUseComponent":
				has_remove = true
			"TModifierWelaDamageComponent":
				var mod := {"groups": groups, "value_group": g, "multiply": false, "must_have": [], "factor": 1.0}
				for call in comp.get("calls", []):
					match call[0]:
						"SetValueGroup": mod["value_group"] = gid.call(call[1][0][0])
						"Multiply": mod["multiply"] = true
						"FactorForUnitProperty":
							mod["must_have"] = call[1][0]
							mod["factor"] = float(call[1][1])
				b.damage_mods.append(mod)
			"TModifierMultiplyMovementSpeedComponent":
				b.speed_factor = b._value("eiWelaDamage", g, 1.0)
			"TModifierMultiplyCooldownComponent":
				b.cooldown_factor = b._value("eiWelaDamage", g, 1.0)
				b.cooldown_groups = groups
			"TModifierArmorTypeComponent":
				for call in comp.get("calls", []):
					match call[0]:
						"Increase": b.armor_delta = int(b._value("eiWelaModifier", g, 1.0))
						"Decrease": b.armor_delta = -int(b._value("eiWelaModifier", g, 1.0))
						"SetTo": b.armor_set = SimConstants.ARMOR_NAMES.get(call[1][0], -1)
			"TModifierResourceComponent":
				var is_health := false
				for call in comp.get("calls", []):
					if call[0] == "Resource" and call[1][0] == "reHealth":
						is_health = true
				if is_health:
					b.health_bonus = b._value("eiWelaDamage", g, 0.0)
			"TWarheadSpottyDamageComponent":
				b.dot_damage = b._value("eiWelaDamage", g, 0.0)
				b.dot_type = SimConstants.damage_mask(b.values.get("eiDamageType", {}).get(g, []))
				b.dot_interval = int(b._value("eiCooldown", g, 1000))
	for comp in data["components"]:
		if comp["class"] == "TWelaReadyNthComponent":
			for call in comp.get("calls", []):
				if call[0] == "Times":
					b.dot_times = int(call[1][0])
	if duration_group >= 0 and has_remove:
		b.expires_at = now + int(b._value("eiCooldown", duration_group, 0))
	b.dot_next_at = now + b.dot_interval
	b.stops_movement = b.properties.has("upStunned") or b.properties.has("upRooted") or b.properties.has("upFrozen")
	return b


func _value(event: String, group: int, default: float) -> float:
	return float(values.get(event, {}).get(group, default))


func is_expired(now: int) -> bool:
	return expires_at >= 0 and now >= expires_at


## Damage modification for a weapon group of the owner (TModifierWelaDamageComponent.OnWelaDamage).
func modify_damage(amount: float, group: int, owner_props: Dictionary) -> float:
	for mod in damage_mods:
		if not mod["groups"].has(group):
			continue
		var factor := _value("eiWelaModifier", mod["value_group"], 1.0)
		if not mod["must_have"].is_empty():
			var all := true
			for p in mod["must_have"]:
				if not owner_props.has(p):
					all = false
			if all:
				factor *= mod["factor"]
		amount = amount * factor if mod["multiply"] else amount + factor
	return amount
