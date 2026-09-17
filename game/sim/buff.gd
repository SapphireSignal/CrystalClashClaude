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
var late_properties: Array = []     # a second property group with its own longer cooldown (Frozen -> upImmuneToFrozen)
var removed_properties: Array = []  # TUnitPropertyComponent.Remove (Grounded strips upFlying)
var on_expire_script: String = ""   # TWarheadApplyScriptComponent in the duration group: applied when it runs out
var link_welas: Array = []          # link entity groups (Links/RootlingLink.ets) parsed as welas
var link_bb: Blackboard = null
var late_expires_at: int = -1
var link_damage: float = 0.0        # link entity brain (Links/VecraAura.ets): periodic damage to the linked target
var link_damage_type: int = 0
var link_leech: float = 0.0         # share of dealt damage healed back to the link owner
var creator_group: int = -1         # TWelaLinkEffectComponent.CreatorGroup: group fired in the link owner (FireInCreator)
var reflects_projectiles: bool = false   # Links/ProjectileReflector: TAutoBrainOnWelaHitByProjectileComponent
var reflect_not_types: int = 0      # TWelaTargetConstraintWelaPropertyComponent.MustNotHave on the projectile (true, reflected)
var fire_in_creator: bool = false   # TWelaEffectFireComponent.FireInCreator
var projectile_script: String = ""  # TWarheadApplyScriptComponent applied to the hitting projectile
var damage_type_add: int = 0        # TModifierDamageTypeComponent.Add (ProjectileReflectorProjectile: dtReflected)
var target_count_add: int = 0       # TModifierWelaTargetCountComponent on the main weapon (Frenzy: ranged +1)
var on_fire_group: int = -1         # TWelaEffectFireComponent on the main weapon, redirected to self
var on_fire_heal: float = 0.0       # Frenzy: melee heal 70 per attack
var on_fire_heal_type: int = 0
var shard_projectile: String = ""   # Frostspear: a projectile per tick at a random unit of the owner's team
var shard_damage: float = 0.0
var shard_type: int = 0
var shard_range: float = 0.0
var shard_must_not_have: Array = []
var shard_enemies: bool = false     # EnergyRift: the buff's fight group shoots enemies of the carrier (Frostspear: its allies)
var mana_cap_add: int = 0           # TModifierResourceComponent.DontFillCap.Resource(reMana) (BlessingEnergy: +2 max energy)
var bomb_script: String = ""        # OrbitalStrike: a script dropped on a random unit of the carrier's team every tick
var bomb_range: float = 0.0
var bomb_interval: int = 0
var bomb_next_at: int = 0           # first bomb after TWelaReadyCooldownComponent.Cooldown(ms).Once
var bomb_must_not_have: Array = []
var splash_damage: float = 0.0      # TWarheadSplashDamageComponent in a timer group (OrbitalStrikeBombardement)
var splash_radius: float = 0.0
var splash_type: int = 0
var splash_once: bool = false       # the splash group removes itself after firing
var teleport_at: int = -1           # Relocate: TWarheadSpottyTeleportComponent.ToCoordinate after the group's timer
var teleport_to: Vector2 = Vector2.ZERO
var tier_heal: Dictionary = {}      # ResolveTier heal on buildings: index (1 for tier 1/2, 3 otherwise) -> share of max hp
var tier_mana: Dictionary = {}      # ResolveTier energy refill: index -> share of the cap
var armor_requires_props: Array = []   # TModifierArmorTypeComponent.ReadyGroup: armor change only while these hold
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
var health_bonus_cap_factor: float = 0.0   # TModifierResourceComponent.ScaleWithResource(reHealth).UseResourceCap (BlessingHealth)
var health_bonus_add: float = 0.0
var hot_percent_of_max: bool = false
var stops_movement: bool = false
var taken_damage_mult: float = 1.0
var taken_damage_types: int = 0     # TBuffTakenDamageMultiplierComponent.DamageTypeMustHaveAny
var taken_heal_mult: float = 1.0    # TBuffTakenDamageMultiplierComponent.ApplyOnHeal (Bleeding: 0.6)
var instant_heal: float = 0.0       # TWarheadSpottyResourceComponent(reHealth) + TThinkImpulseNow (Undying full heal)
var kills_on_expiry: bool = false   # TWelaEffectSuicideComponent when the duration runs out (Undying)
var duration_ms: int = 0
var charges: int = 0                # reWelaCharge stacks (Bleeding)
var charge_cap: int = 0
# TAutoBrainOnDealDamageComponent (Grievous Wounds): hits on valid targets apply a script, or refresh and
# stack it when the target already carries it
var on_hit_group: int = -1
var on_hit_cooldown_ms: int = 0
var on_hit_ready_at: int = 0
var on_hit_must_have: Array = []
var on_hit_must_not_have: Array = []
var on_hit_script: String = ""
# TAutoBrainOnTakeDamageComponent.ModifiesAmount + threshold (Shieldblock buff): hits at or above the
# threshold are multiplied by the factor; with RemoveAfterUse the buff is spent by the first block
var block_threshold: float = -1.0
var block_factor: float = 1.0
var block_once: bool = false
# periodic self effects (group with a cooldown + instant warhead on self)
var dot_damage: float = 0.0
var dot_type: int = 0
var dot_percent_of_max: bool = false   # PercentageOfMaxHealth
var dot_scales_with_charges: bool = false
var dot_not_props: Array = []          # tick constraint MustNotHave (Bleeding: upBanished)
var hot_heal: float = 0.0
var mana_per_tick: int = 0
var tick_interval: int = 0
var tick_times: int = -1            # -1 = unlimited
var remove_when_ticks_done: bool = false   # the Nth group also removes the buff (Frostspear)
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


static func params_of(script_name: String) -> Array:
	load_db()
	return _db.get(script_name, {}).get("params", [])


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
	var defaults: Dictionary = data.get("defaults", {})
	for event in data["values"]:
		for sym in data["values"][event]:
			var v: Variant = data["values"][event][sym]
			if v is Dictionary and v.has("if"):   # if Entity.HasDamageType(dtMelee) then a else b
				v = v["then"] if params.get("__" + v["if"], false) else v["else"]
			elif v is String:
				v = _resolve_expression(v, params, defaults)
			b.values.get_or_add(event, {})[gid.call(sym)] = v
	var duration_group := -1
	var has_remove := false
	var tick_group := -1
	var cooldown_groups: Array = []   # groups with a TWelaReadyCooldownComponent and a cooldown value, in order
	var ending_groups := {}           # groups that remove or suicide when they fire
	var prop_groups: Array = []   # [group, props]
	var timer_ready := false
	var unready_groups := {}
	var pending_scripts: Array = []   # rescue scripts for prevent-death buffs, otherwise applied when the buff ends
	var nth_group := -1
	var fight_group := -1     # TBrainWelaFightComponent inside the buff (OrbitalStrike bombardment)
	var splash_group := -1
	var resolve_tier_groups := {}   # TWelaHelperResolveComponent.ResolveTier: indexed values picked by the carrier's tier
	var teleport_group := -1
	for comp in data["components"]:
		if comp.has("cond") and not params.get("__" + comp["cond"], false):
			continue   # component only exists for melee / ranged owners
		var groups: Array = comp["groups"].map(func(s): return gid.call(s))
		var g: int = groups[0] if not groups.is_empty() else -1
		var calls: Array = comp.get("calls", [])
		match comp["class"]:
			"TThinkImpulseTimerCooldownComponent":
				for call in calls:
					if call[0] == "TimerIsReady":
						timer_ready = true
			"TWelaEffectProjectileComponent":
				b.shard_projectile = str(b.values.get("eiWelaUnitPattern", {}).get(g, "")).replace("\\", "/")
				b.shard_damage = b._value("eiWelaDamage", g, 0.0)
				b.shard_type = SimConstants.damage_mask(b.values.get("eiDamageType", {}).get(g, []))
				b.shard_range = b._value("eiWelaRange", g, 0.0)
				tick_group = g
			"TWelaEffectFireComponent":
				if groups.has(SimConstants.GROUP_MAINWEAPON):
					for call in calls:
						if call[0] == "TargetGroup":
							b.on_fire_group = gid.call(call[1][0][0])
				for call in calls:
					if call[0] == "FireInCreator":
						b.fire_in_creator = true
			"TAutoBrainOnWelaHitByProjectileComponent":
				b.reflects_projectiles = true
			"TWelaTargetConstraintWelaPropertyComponent":
				for call in calls:
					if call[0] == "MustNotHave":
						b.reflect_not_types = SimConstants.damage_mask(call[1][0])
			"TModifierDamageTypeComponent":
				for call in calls:
					if call[0] == "Add":
						b.damage_type_add |= SimConstants.damage_mask(call[1][0])
			"TModifierWelaTargetCountComponent":
				var value_group := g
				for call in calls:
					if call[0] == "SetValueGroup":
						value_group = gid.call(call[1][0][0])
				b.target_count_add = int(b._value("eiWelaModifier", value_group, 0.0))
			"TAutoBrainBuffComponent":
				b.buff_types = comp.get("args", [[]])[0]
			"TUnitPropertyComponent":
				var removes := false
				for call in calls:
					if call[0] == "Remove":
						removes = true
				if removes:
					b.removed_properties.append_array(comp.get("args", [[]])[0])
				else:
					prop_groups.append([g, comp.get("args", [[]])[0]])
			"TBrainWelaFightComponent":
				fight_group = g
			"TWelaReadyCooldownComponent":
				if b.prevents_death:
					continue
				if g == fight_group:   # .Cooldown(1000).Once: a one-time delay before the bombardment starts
					for call in calls:
						if call[0] == "Cooldown":
							b.bomb_next_at = now + int(call[1][0])
					continue
				if not comp.get("args", []).is_empty() and str(comp["args"][0]).to_lower() == "false":
					unready_groups[g] = true   # starts on cooldown: the first tick waits even with a ready timer
				if g == b.on_hit_group:
					b.on_hit_cooldown_ms = int(b._value("eiCooldown", g, 0))
					continue
				if b.values.get("eiCooldown", {}).has(g):
					cooldown_groups.append(g)
					if tick_group < 0:
						tick_group = g
			"TWelaEffectRemoveAfterUseComponent":
				has_remove = true
				ending_groups[g] = true
			"TModifierWelaDamageComponent":
				var mod := {"groups": groups, "value_group": g, "multiply": false, "must_have": [], "factor": 1.0}
				for call in calls:
					if call[0] == "ScaleWithResource" and call[1][0] == "reWelaCharge":
						b.dot_scales_with_charges = true
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
				var value_group := -1
				for call in calls:
					if call[0] == "SetValueGroup":
						value_group = gid.call(call[1][0][0])
				if value_group >= 0 and b.values.get("eiWelaModifier", {}).has(value_group):
					b.cooldown_factor = b._value("eiWelaModifier", value_group, 1.0)
				else:
					b.cooldown_factor = b._value("eiWelaDamage", g, 1.0)
				b.cooldown_groups = groups
			"TModifierArmorTypeComponent":
				for call in calls:
					match call[0]:
						"Increase": b.armor_delta = int(b._value("eiWelaModifier", g, 1.0))
						"Decrease": b.armor_delta = -int(b._value("eiWelaModifier", g, 1.0))
						"SetTo": b.armor_set = SimConstants.ARMOR_NAMES.get(call[1][0], -1)
						"ReadyGroup":
							var rg: int = gid.call(call[1][0][0])
							for other in data["components"]:
								if other["class"] == "TWelaReadyUnitPropertyComponent" and other["groups"].map(func(s): return gid.call(s)).has(rg):
									for oc in other.get("calls", []):
										if oc[0] == "MustHave":
											b.armor_requires_props.append_array(oc[1][0])
			"TModifierResourceComponent":
				var scale_cap := false
				var add_modifier := false
				var is_health := false
				for call in calls:
					if call[0] == "Resource" and call[1][0] == "reHealth":
						is_health = true
					elif call[0] == "UseResourceCap":
						scale_cap = true
					elif call[0] == "AddModifier":
						add_modifier = true
				if is_health and scale_cap:   # v = damage x max health (+ modifier): resolved by the sim on apply
					b.health_bonus_cap_factor = b._value("eiWelaDamage", g, 0.0)
					b.health_bonus_add = b._value("eiWelaModifier", g, 0.0) if add_modifier else 0.0
				elif is_health:
					b.health_bonus = b._value("eiWelaDamage", g, 0.0) * b._value("eiWelaModifier", g, 1.0)
				for call in calls:
					if call[0] == "Resource" and call[1][0] == "reMana":
						b.mana_cap_add = int(b._value("eiWelaDamage", g, 0.0))   # DontFillCap: the balance stays
			"TBuffTakenDamageMultiplierComponent":
				var on_heal := false
				for call in calls:
					if call[0] == "DamageTypeMustHaveAny":
						b.taken_damage_types = SimConstants.damage_mask(call[1][0])
					elif call[0] == "ApplyOnHeal":
						on_heal = true
				if on_heal:
					b.taken_heal_mult = b._value("eiWelaModifier", g, 1.0)
				else:
					b.taken_damage_mult = b._value("eiWelaModifier", g, 1.0)
			"TAutoBrainOnDealDamageComponent":
				b.on_hit_group = g
			"TWelaTargetingRadialComponent":
				for call in calls:
					if call[0] == "SetTargetTeamConstraint" and call[1][0] == "tcEnemies":
						b.shard_enemies = true
			"TWelaTargetConstraintUnitPropertyComponent":
				for call in calls:
					if g == b.on_hit_group and call[0] == "MustHave":
						b.on_hit_must_have.append_array(call[1][0])
					elif g == b.on_hit_group and call[0] == "MustNotHave":
						b.on_hit_must_not_have.append_array(call[1][0])
					elif g == fight_group and fight_group >= 0 and call[0] == "MustNotHave":
						b.bomb_must_not_have.append_array(call[1][0])
						b.shard_must_not_have.append_array(call[1][0])   # EnergyRift: the fight group is also the shard group
					elif g == tick_group and call[0] == "MustNotHave":
						b.dot_not_props.append_array(call[1][0])
						b.shard_must_not_have.append_array(call[1][0])
			"TWelaEffectSuicideComponent":
				b.kills_on_expiry = true
				ending_groups[g] = true
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
				if b.reflects_projectiles:
					b.projectile_script = script   # modifies the reflected projectile (x0.4, dtReflected)
				elif g == fight_group and fight_group >= 0:
					b.bomb_script = script   # OrbitalStrike: dropped on the bombardment's random target
				elif b.on_hit_group >= 0:
					b.on_hit_script = script
				else:
					pending_scripts.append(script)
			"TWelaHelperResolveComponent":
				for call in calls:
					if call[0] == "ResolveTier":
						resolve_tier_groups[g] = true
			"TWarheadSpottyTeleportComponent":
				for call in calls:
					if call[0] == "ToNexus":
						b.rescue_teleports_to_nexus = true
					elif call[0] == "ToCoordinate":   # Relocate: 'Target.X + Offset.X', 'Target.Y + Offset.Y'
						var coords: Array = []
						for text in call[1]:
							var expr := str(text)
							for name in params:
								if params[name] is Vector2:
									expr = expr.replace(name + ".X", str(params[name].x)).replace(name + ".Y", str(params[name].y))
							var ex := Expression.new()
							assert(ex.parse(expr) == OK, "bad teleport coordinate %s" % expr)
							coords.append(float(ex.execute()))
						b.teleport_to = Vector2(coords[0], coords[1])
						teleport_group = g
			"TWarheadSpottyDamageComponent":
				if not b.prevents_death:
					b.dot_damage = b._value("eiWelaDamage", g, 0.0)
					b.dot_type = SimConstants.damage_mask(b.values.get("eiDamageType", {}).get(g, []))
					tick_group = g
					for call in calls:
						if call[0] == "PercentageOfMaxHealth":
							b.dot_percent_of_max = true
			"TWarheadSplashDamageComponent":   # OrbitalStrikeBombardement: 11 splash in 2.0 around the carrier after 174 ms
				b.splash_damage = b._value("eiWelaDamage", g, 0.0)
				b.splash_radius = b._value("eiWelaAreaOfEffect", g, 0.0)
				b.splash_type = SimConstants.damage_mask(b.values.get("eiDamageType", {}).get(g, []))
				splash_group = g
				tick_group = g
			"TWarheadSpottyHealComponent":
				if resolve_tier_groups.has(g):   # Relocate: buildings heal 30 / 25 / 15 % by tier index
					b.tier_heal = {1: b._value("eiWelaDamage.1", g, 0.0), 3: b._value("eiWelaDamage.3", g, 0.0)}
				elif g == b.on_fire_group:
					b.on_fire_heal = b._value("eiWelaDamage", g, 0.0)
					b.on_fire_heal_type = SimConstants.damage_mask(b.values.get("eiDamageType", {}).get(g, []))
				else:
					b.hot_heal = b._value("eiWelaDamage", g, 0.0)
					tick_group = g
					for call in calls:
						if call[0] == "PercentageOfMaxHealth":
							b.hot_percent_of_max = true
			"TWarheadSpottyResourceComponent":
				var is_mana := false
				for call in calls:
					if call[0] == "SetResourceType" and call[1][0] == "reMana":
						is_mana = true
				if is_mana and resolve_tier_groups.has(g):   # Relocate: energy refill 30 / 20 / 20 % by tier index
					b.tier_mana = {1: b._value("eiWelaDamage.1", g, 0.0), 3: b._value("eiWelaDamage.3", g, 0.0)}
				elif is_mana:
					b.mana_per_tick = int(b._value("eiWelaDamage", g, 1.0))
					tick_group = g
				elif b.on_hit_group < 0 and b.values.get("eiWelaDamage", {}).has(g):
					b.instant_heal = b._value("eiWelaDamage", g, 0.0)   # Undying: heal back to max at once
			"TWelaReadyNthComponent":
				for call in calls:
					if call[0] == "Times" or call[0] == "Nth":
						b.tick_times = int(call[1][0])
						nth_group = g
	b.remove_when_ticks_done = nth_group >= 0 and ending_groups.has(nth_group)
	for g in cooldown_groups:   # the duration is the cooldown whose group ends the buff, not a tick cadence
		if ending_groups.has(g):
			duration_group = g
			break
	if b.prevents_death:
		b.rescue_scripts = pending_scripts
	elif not pending_scripts.is_empty():
		b.on_expire_script = pending_scripts[0]
	for item in prop_groups:
		var own := int(b._value("eiCooldown", item[0], -1.0))
		if item[0] != duration_group and own > int(b._value("eiCooldown", duration_group, 0)) and has_remove and not b.prevents_death:
			b.late_properties.append_array(item[1])
			b.late_expires_at = now + own
		else:
			b.properties.append_array(item[1])
	if duration_group >= 0 and has_remove and not b.prevents_death:
		b.duration_ms = int(b._value("eiCooldown", duration_group, 0))
		b.expires_at = now + b.duration_ms
		b.charges = int(b._value("eiResourceBalance.reWelaCharge", duration_group, 0))
		b.charge_cap = int(b._value("eiResourceCap.reWelaCharge", duration_group, 0))
	for g in b.values.get("eiResourceCost.reWelaCharge", {}):   # ticks paid with charges (Giant Growth: 20 x 1)
		var pool := int(b._value("eiResourceBalance.reWelaCharge", g, 0))
		var cost := int(b._value("eiResourceCost.reWelaCharge", g, 1))
		if pool > 0 and cost > 0 and b.tick_times < 0:
			b.tick_times = pool / cost
			if tick_group >= 0 and not b.values.get("eiCooldown", {}).has(tick_group):
				b.tick_interval = int(b._value("eiCooldown", g, 1000))
	b.block_once = has_remove and b.block_threshold >= 0.0
	if b.bomb_script != "" and fight_group >= 0:
		b.bomb_range = b._value("eiWelaRange", fight_group, 0.0)
		b.bomb_interval = int(b._value("eiCooldown", fight_group, 1000))
		if b.bomb_next_at <= 0:
			b.bomb_next_at = now
	b.splash_once = splash_group >= 0 and ending_groups.has(splash_group)
	if teleport_group >= 0:   # Relocate: the group's timer (Once) delays the blink
		b.teleport_at = now + int(b._value("eiCooldown", teleport_group, 0))
	if tick_group >= 0 and (b.dot_damage > 0.0 or b.hot_heal > 0.0 or b.mana_per_tick > 0 or b.shard_projectile != "" or b.splash_damage > 0.0):
		if b.values.get("eiCooldown", {}).has(tick_group) or b.tick_interval <= 0:
			b.tick_interval = int(b._value("eiCooldown", tick_group, 1000))
		b.next_tick_at = now if timer_ready and not unready_groups.has(tick_group) else now + b.tick_interval
	b.stops_movement = b.properties.has("upStunned") or b.properties.has("upRooted") or b.properties.has("upFrozen")
	return b


## 'Duration' -> the passed or default parameter; 'Duration + 10000' -> evaluated with it.
static func _resolve_expression(text: String, params: Dictionary, defaults: Dictionary) -> Variant:
	var expr := text
	var names := params.keys() + defaults.keys()
	var known := false
	for name in names:
		if expr.contains(name):
			known = true
			expr = expr.replace(name, str(params.get(name, defaults.get(name))))
	if not known:
		return text
	var e := Expression.new()
	if e.parse(expr) != OK:
		return text
	var result: Variant = e.execute()
	return text if e.has_execute_failed() else result


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
