class_name Buff
## An applied modifier script (Scripts/Modifiers/*.dws and Scripts/Links/*.dws payloads, via
## game/data/modifiers.json). The script's symbolic groups ("Group", "DoTGroup"...) get fresh group ids
## on the entity. The components are interpreted into stat modifiers (TModifier*Component), unit
## properties (TUnitPropertyComponent), a duration (TWelaReadyCooldownComponent +
## TWelaEffectRemoveAfterUseComponent), DoT / HoT / mana ticks, taken-damage multipliers and
## prevent-death rescues (Homeland, Guarded).

const MODIFIERS_PATH := "res://game/data/modifiers.json"
const FIXED_GROUPS := {"GROUP_APPROACH_MAINWEAPON": 0, "GROUP_MAINWEAPON": 1, "GROUP_TEMPLATE_SPAWNER": 0,
	"GROUP_DROP_SPAWNER": 0, "GROUP_SPELL_SPAWNER": 0, "GROUP_BUILDING_LIFETIME": 10, "GROUP_SOUL": 11}
static var _db: Dictionary = {}

var name: String
var source_id: int = 0
var buff_types: Array = []          # btPositive, btNegative, btState, btSummoningSickness ...
var properties: Array = []          # unit properties granted while active
var expires_at: int = -1
var values: Dictionary = {}         # "eiWelaModifier" -> {group_id: value}
var damage_mods: Array = []         # {groups, value_group, multiply, must_have, factor}
var range_add: float = 0.0          # TModifierWelaRangeComponent.AddModifier on the main weapon
var range_add_building: float = 0.0 # extra when the owner is a building (RangeUpgrade)
var speed_factor: float = 1.0
var cooldown_factor: float = 1.0
var cooldown_groups: Array = []
var armor_delta: int = 0
var armor_set: int = -1
var health_bonus: float = 0.0
var stops_movement: bool = false
var taken_damage_mult: float = 1.0
var taken_damage_types: int = 0     # TBuffTakenDamageMultiplierComponent.DamageTypeMustHaveAny
# TAutoBrainOnTakeDamageComponent.ModifiesAmount + threshold (Shieldblock buff): hits at or above the
# threshold are multiplied by the factor; with RemoveAfterUse the buff is spent by the first block
var block_threshold: float = -1.0
var block_factor: float = 1.0
var block_once: bool = false
# periodic self effects (group with a cooldown + instant warhead on self)
var dot_damage: float = 0.0
var dot_type: int = 0
var hot_heal: float = 0.0
var mana_per_tick: int = 0
var tick_interval: int = 0
var tick_times: int = -1            # -1 = unlimited
var next_tick_at: int = 0
# prevent death (TAutoBrainPreventDeathComponent): set health, strip buffs, apply scripts, teleport home
var prevents_death: bool = false
var rescue_health: float = 1.0
var rescue_removes_all_except: Array = []   # buff types kept when "All" removal runs
var rescue_removes_any: Array = []          # buff types removed by a MustHaveAny removal
var rescue_scripts: Array = []
var rescue_teleports_to_nexus: bool = false
var rescue_needs_creator: bool = false      # TWelaReadyCreatorComponent: only while the aura owner lives


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
		if FIXED_GROUPS.has(sym):
			return FIXED_GROUPS[sym]
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
	var tick_group := -1
	for comp in data["components"]:
		var groups: Array = comp["groups"].map(func(s): return gid.call(s))
		var g: int = groups[0] if not groups.is_empty() else -1
		var calls: Array = comp.get("calls", [])
		match comp["class"]:
			"TAutoBrainBuffComponent":
				b.buff_types = comp.get("args", [[]])[0]
			"TUnitPropertyComponent":
				b.properties.append_array(comp.get("args", [[]])[0])
			"TWelaReadyCooldownComponent":
				if b.prevents_death:
					continue
				if b.values.get("eiCooldown", {}).has(g):
					if duration_group < 0:
						duration_group = g
					if tick_group < 0:
						tick_group = g
			"TWelaEffectRemoveAfterUseComponent":
				has_remove = true
			"TModifierWelaDamageComponent":
				var mod := {"groups": groups, "value_group": g, "multiply": false, "must_have": [], "factor": 1.0}
				for call in calls:
					match call[0]:
						"SetValueGroup": mod["value_group"] = gid.call(call[1][0][0])
						"Multiply": mod["multiply"] = true
						"FactorForUnitProperty":
							mod["must_have"] = call[1][0]
							mod["factor"] = float(call[1][1])
				b.damage_mods.append(mod)
			"TModifierWelaRangeComponent":
				var value_group: int = groups[-1] if groups.size() > 1 else g
				var ready_group: int = -1
				for call in calls:
					if call[0] == "SetValueGroup":
						value_group = gid.call(call[1][0][0])
					elif call[0] == "ReadyGroup":
						ready_group = gid.call(call[1][0][0])
				var amount := b._value("eiWelaModifier", value_group, 0.0)
				if ready_group >= 0:
					b.range_add_building += amount   # RangeUpgrade: extra range gated on upBuilding
				else:
					b.range_add += amount
			"TModifierMultiplyMovementSpeedComponent":
				b.speed_factor = b._value("eiWelaDamage", g, 1.0)
			"TModifierMultiplyCooldownComponent":
				b.cooldown_factor = b._value("eiWelaDamage", g, 1.0)
				b.cooldown_groups = groups
			"TModifierArmorTypeComponent":
				for call in calls:
					match call[0]:
						"Increase": b.armor_delta = int(b._value("eiWelaModifier", g, 1.0))
						"Decrease": b.armor_delta = -int(b._value("eiWelaModifier", g, 1.0))
						"SetTo": b.armor_set = SimConstants.ARMOR_NAMES.get(call[1][0], -1)
			"TModifierResourceComponent":
				for call in calls:
					if call[0] == "Resource" and call[1][0] == "reHealth":
						b.health_bonus = b._value("eiWelaDamage", g, 0.0)
			"TBuffTakenDamageMultiplierComponent":
				b.taken_damage_mult = b._value("eiWelaModifier", g, 1.0)
				for call in calls:
					if call[0] == "DamageTypeMustHaveAny":
						b.taken_damage_types = SimConstants.damage_mask(call[1][0])
			"TAutoBrainOnTakeDamageComponent":
				b.block_threshold = b._value("eiWelaDamage", g, 0.0)
				b.block_factor = b._value("eiWelaModifier", g, 1.0)
			"TAutoBrainPreventDeathComponent":
				b.prevents_death = true
				b.rescue_health = b._value("eiWelaDamage", g, 1.0)
			"TWelaReadyCreatorComponent":
				b.rescue_needs_creator = true
			"TWarheadSpottyRemoveBuffComponent":
				for call in calls:
					if call[0] == "MustNotHave":
						b.rescue_removes_all_except = call[1][0]
					elif call[0] == "MustHaveAny":
						b.rescue_removes_any = call[1][0]
			"TWarheadApplyScriptComponent":
				var script: String = Wela.script_key(str(comp.get("args", [""])[0]))
				b.rescue_scripts.append(script)
			"TWarheadSpottyTeleportComponent":
				for call in calls:
					if call[0] == "ToNexus":
						b.rescue_teleports_to_nexus = true
			"TWarheadSpottyDamageComponent":
				if not b.prevents_death:
					b.dot_damage = b._value("eiWelaDamage", g, 0.0)
					b.dot_type = SimConstants.damage_mask(b.values.get("eiDamageType", {}).get(g, []))
					tick_group = g
			"TWarheadSpottyHealComponent":
				b.hot_heal = b._value("eiWelaDamage", g, 0.0)
				tick_group = g
			"TWarheadSpottyResourceComponent":
				var is_mana := false
				for call in calls:
					if call[0] == "SetResourceType" and call[1][0] == "reMana":
						is_mana = true
				if is_mana:
					b.mana_per_tick = int(b._value("eiWelaDamage", g, 1.0))
					tick_group = g
			"TWelaReadyNthComponent":
				for call in calls:
					if call[0] == "Times":
						b.tick_times = int(call[1][0])
	if duration_group >= 0 and has_remove and not b.prevents_death:
		b.expires_at = now + int(b._value("eiCooldown", duration_group, 0))
	b.block_once = has_remove and b.block_threshold >= 0.0
	if tick_group >= 0 and (b.dot_damage > 0.0 or b.hot_heal > 0.0 or b.mana_per_tick > 0):
		b.tick_interval = int(b._value("eiCooldown", tick_group, 1000))
		b.next_tick_at = now + b.tick_interval
	b.stops_movement = b.properties.has("upStunned") or b.properties.has("upRooted") or b.properties.has("upFrozen")
	return b


func _value(event: String, group: int, default: float) -> float:
	var v: Variant = values.get(event, {}).get(group, default)
	return float(v) if (v is float or v is int) else default


func is_expired(now: int) -> bool:
	return expires_at >= 0 and now >= expires_at


func has_type(t: String) -> bool:
	return buff_types.has(t)


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
