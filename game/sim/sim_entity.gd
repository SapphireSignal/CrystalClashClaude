class_name SimEntity
## One simulated unit/building. Pure data + stats; behaviour lives in Simulation.
## Stat reads go through the buff chain like the original eventbus "Read" pipeline.

var id: int = 0
var unit_id: String = ""
var team: int = 0
var league: int = 4
var level: int = 0                  # reLevel: Atlas "Supreme" = min(times the card was played, 10)
var position: Vector2 = Vector2.ZERO
var front: Vector2 = Vector2.RIGHT
var collision_radius: float = 0.5
var bb: Blackboard = Blackboard.new()
var properties: Dictionary = {}     # "upFlying" -> true, from eiUnitProperties (base only)
var welas: Array[Wela] = []
var buffs: Array[Buff] = []

var health: float = 0.0
var max_health: float = 0.0
var overheal: float = 0.0            # reOverheal: absorbed before health, capped at max_health * 2
var alive: bool = true
var card_drop: bool = false          # produced by a drop/building card: Modifiers/Drop.dws client effects (DropTemplate.dws:53)
var spawner_placed: bool = false     # a placed spawner: Modifiers/Spawner.dws impact animation (SpawnerTemplate.dws:42)
var base_armor: SimConstants.ArmorType = SimConstants.ArmorType.UNARMORED
var base_speed: float = SimConstants.DEFAULT_SPEED   # units per ms
var mana: int = 0
var mana_cap: int = 0
var charge_capacity: int = 0         # reWelaChargeCapacity (Oracle: saplings eaten)
var charge_capacity_cap: int = 0
var no_pathfinding: bool = false     # eiUnitData.udUsePathfinding False: walks straight, ignores tiles (Brratu)
var charges: Dictionary = {}         # group -> reWelaCharge balance kept per group (spell modes, fields)
var thinks_once: bool = false        # TThinkImpulseOnceComponent: spell effect acts once on creation
var thought_once: bool = false
var think_once_waits: bool = false   # TThinkImpulseOnceComponent.WaitOneFrame: acts on the next tick instead
var think_delay_ms: int = 0          # TThinkImpulseTimerCooldownComponent: acts once after this delay (RipOutSoul 500)
var lifetime_ms: int = 0             # BuildingTemplate GROUP_BUILDING_LIFETIME: the building dies after this
var lifetime_started_at: int = 0     # restarted by FactoryReset (TWelaEffectResetCooldownComponent on the beacon)
var saved_targets: Array = []        # eiWelaSavedTargets: the spell's target points (Relocate: A, B), PassTargets
var group_properties: Dictionary = {}   # TUnitPropertyComponent on a wela group: group -> props, gone when the group is removed
var removed_groups: Dictionary = {}     # TWelaEffectRemoveAfterUseComponent.TargetGroup

# Main weapon state (group 1)
var target_id: int = 0
var cooldown_ready_at: int = 0
var fire_at: int = -1            # time when the pending hit lands, -1 = none
var fire_group: int = SimConstants.GROUP_MAINWEAPON
var locked_until: int = 0        # action duration lock

# Ammo (reWelaCharge) for nexus / lanetower weapons: cost per shot, recharge one per cooldown of the
# ammo group (group 6 in Nexus.ets, group 5 in Lanetower.ets), active after game start.
var stage: int = 1                   # ServerGame.Commanders.First tier at creation (Cataclysm's ScaleWithStage range)
var ammo: int = 0
var ammo_cap: int = 0
var ammo_cost: int = 0
var ammo_recharge_ms: int = 0
var ammo_next_at: int = -1

# Lane node capture state (TBrainCapturePointComponent, LaneNode.ets)
var team_power: Dictionary = {}      # team -> float
var capturing_team: int = -1
var capture_next_at: int = 0

# Spawner card state (TBrainSpawnerComponent)
var build_zone_id: int = -1
var build_field: Vector2i = Vector2i(-1, -1)

var created_at: int = 0
var died_at: int = -1

# Movement state (TMovementComponent / TPathfindingComponent)
var moving: bool = false
var move_target_id: int = 0          # entity we walk to, 0 = position target
var move_target_pos: Vector2 = Vector2.ZERO
var move_use_waypoints: bool = false
var path: Array = []                 # tile indices, walked from the back (path.back() is next)
var current_tile: int = -1
var standing_on_tile: int = -1       # tile currently counted as blocked by this entity
var stand_since: int = -1            # time the unit last came to a stand (Marksman range ramp)
var exiled: bool = false             # killed by exile: no death effects, no soul
var link_buffs: Dictionary = {}      # "<owner id>:<group>" -> Buff granted by that aura group


static func link_key(source_id: int, group: int) -> String:
	return "%d:%d" % [source_id, group]


func linked_from(source_id: int) -> bool:
	for key in link_buffs:
		if key.begins_with("%d:" % source_id):
			return true
	return false


func setup(p_unit_id: String, p_league: int, p_level: int = 0) -> void:
	unit_id = p_unit_id
	league = p_league
	level = p_level
	UnitDb.fill_blackboard(bb, unit_id, league, level)
	collision_radius = bb.get_float("collision_radius", Blackboard.ANY_GROUP, 0.5)
	for p in bb.get_value("eiUnitProperties", Blackboard.ANY_GROUP, []):
		properties[p] = true
	max_health = bb.get_float("eiResourceCap.reHealth", Blackboard.ANY_GROUP, 0.0)
	health = bb.get_float("eiResourceBalance.reHealth", Blackboard.ANY_GROUP, max_health)
	base_armor = SimConstants.ARMOR_NAMES.get(bb.get_value("eiArmorType", Blackboard.ANY_GROUP, "atUnarmored"), SimConstants.ArmorType.UNARMORED)
	base_speed = bb.get_float("eiSpeed", Blackboard.ANY_GROUP, SimConstants.DEFAULT_SPEED)
	mana_cap = bb.get_int("eiResourceCap.reMana", Blackboard.ANY_GROUP, 0)
	mana = bb.get_int("eiResourceBalance.reMana", Blackboard.ANY_GROUP, mana_cap)
	charge_capacity_cap = bb.get_int("eiResourceCap.reWelaChargeCapacity", Blackboard.ANY_GROUP, 0)
	charge_capacity = bb.get_int("eiResourceBalance.reWelaChargeCapacity", Blackboard.ANY_GROUP, 0)
	no_pathfinding = bb.get_value("eiUnitData.udUsePathfinding", Blackboard.ANY_GROUP, true) == false
	if bb.has_value("eiResourceCap.reWelaCharge"):
		ammo_cap = bb.get_int("eiResourceCap.reWelaCharge")
		ammo = bb.get_int("eiResourceBalance.reWelaCharge", Blackboard.ANY_GROUP, ammo_cap)
		ammo_cost = bb.get_int("eiResourceCost.reWelaCharge", SimConstants.GROUP_MAINWEAPON, 0)
		var ammo_group := 5 if has("upLanetower") else 6
		ammo_recharge_ms = bb.get_int("eiCooldown", ammo_group, 0)
	var data := UnitDb.raw(unit_id)
	var map := UnitDb.group_map(data)
	welas = Wela.parse(data.get("components", []), bb, map)
	var main := wela(SimConstants.GROUP_MAINWEAPON)
	if main != null and not main.ready_cost:   # a cost without TWelaReadyCostComponent is only paid (SiegeGolem melee dumps charges)
		ammo_cost = 0
	for g in bb.groups_of("eiResourceBalance.reWelaCharge"):
		if g != Blackboard.ANY_GROUP:
			charges[g] = bb.get_int("eiResourceBalance.reWelaCharge", g)
	if is_building():
		lifetime_ms = bb.get_int("eiCooldown", 10, 0)
	for w in welas:
		w.active = bb.get_value("eiWelaActive", w.group, true)
	for comp in data.get("components", []):
		if comp["class"] == "TUnitPropertyComponent" and not comp["groups"].is_empty():
			var g: int = UnitDb.group_id(comp["groups"][0], map)
			group_properties[g] = comp.get("args", [[]])[0]
		if comp["class"] == "TThinkImpulseOnceComponent":
			thinks_once = true
			for c in comp.get("calls", []):
				if c[0] == "WaitOneFrame":
					think_once_waits = true


func charges_of(group: int) -> int:
	return int(charges.get(group, ammo))


func is_spell_effect() -> bool:
	return unit_id.begins_with("Spells/")


func move_goal(sim) -> Vector2:
	if move_target_id != 0:
		var t: SimEntity = sim.entities.get(move_target_id)
		if t != null:
			return t.position
	return move_target_pos


# ---------------------------------------------------------------- properties and buffs

## Unit property check including buffs and the derived upInjured (health below max).
func has(prop: String) -> bool:
	for b in buffs:
		if b.removed_properties.has(prop):
			return false
	if properties.has(prop):
		return true
	if prop == "upInjured":
		return max_health > 0.0 and health < max_health
	for g in group_properties:
		if not removed_groups.has(g) and group_properties[g].has(prop):
			return true
	for b in buffs:
		if b.properties.has(prop) or b.late_properties.has(prop):
			return true
	return false


func all_properties() -> Dictionary:
	var out := properties.duplicate()
	for g in group_properties:
		if not removed_groups.has(g):
			for p in group_properties[g]:
				out[p] = true
	for b in buffs:
		for p in b.properties:
			out[p] = true
		for p in b.late_properties:
			out[p] = true
	return out


func add_buff(b: Buff) -> void:
	buffs.append(b)
	if b.health_bonus != 0.0:   # eiResourceCapTransaction: the cap moves and the balance follows it
		max_health += b.health_bonus
		health = minf(health + b.health_bonus, max_health) if b.health_bonus > 0.0 else minf(health, max_health)
	mana_cap += b.mana_cap_add   # BlessingEnergy: DontFillCap, the balance stays


func remove_buff(b: Buff) -> void:
	buffs.erase(b)
	if b.health_bonus != 0.0:
		max_health -= b.health_bonus
		health = minf(health, max_health)
	mana_cap -= b.mana_cap_add
	mana = mini(mana, mana_cap)


func has_buff(script_name: String) -> bool:
	for b in buffs:
		if b.name == script_name:
			return true
	return false


# ---------------------------------------------------------------- stat reads (Read chain)

func speed() -> float:
	var s := base_speed
	for b in buffs:
		s *= b.speed_factor
	return s


func armor() -> SimConstants.ArmorType:
	var a := int(base_armor)
	for b in buffs:
		var allowed := true
		for p in b.armor_requires_props:
			if not has(p):
				allowed = false
		if b.armor_set >= 0 and allowed:
			a = b.armor_set
		if allowed:
			a += b.armor_delta
	return clampi(a, 0, SimConstants.ArmorType.FORTIFIED) as SimConstants.ArmorType


func damage(group: int = SimConstants.GROUP_MAINWEAPON) -> float:
	var d := bb.get_float("eiWelaDamage", group, 0.0)
	var props := all_properties()
	for w in welas:   # TModifierWelaDamageComponent.ScaleWithResource on the unit (Brratu: + modifier x health)
		if w.group == group and w.damage_scale_resource == "reHealth":
			d += bb.get_float("eiWelaModifier", w.damage_scale_group, 0.0) * health
		elif w.group == group and w.damage_scale_resource == "reMana":
			d += bb.get_float("eiWelaModifier", w.damage_scale_group, 0.0) * mana
	for b in buffs:
		d = b.modify_damage(d, group, props)
	return d


func cooldown(group: int = SimConstants.GROUP_MAINWEAPON) -> int:
	var c := float(bb.get_int("eiCooldown", group, 0))   # no TWelaReadyCooldownComponent = always ready
	for b in buffs:
		if b.cooldown_groups.has(group):
			c *= b.cooldown_factor
	return int(c)


## eiWelaRange with TModifierWelaRangeComponent (AddModifier): Marksman gains range while standing
## (ScaleWithTime over the value group's cooldown), Ballista while its ready group holds (upFlying).
func range_of(group: int = SimConstants.GROUP_MAINWEAPON, now: int = -1) -> float:
	var r := bb.get_float("eiWelaRange", group, 0.0)
	if group == SimConstants.GROUP_MAINWEAPON:
		for b in buffs:
			r += b.range_add + (b.range_add_building if is_building() else 0.0)
	var w := wela(group)
	if w == null or w.range_modifier_group < 0:
		return r
	var bonus := bb.get_float("eiWelaModifier", w.range_modifier_group, 0.0)
	if w.range_ready_group >= 0:
		var ready := wela(w.range_ready_group)
		if ready == null or not ready.owner_ready(self):
			return r
	if w.range_scales_with_time:
		if moving or stand_since < 0 or now < 0:
			return r
		var ramp := float(bb.get_int("eiCooldown", w.range_modifier_group, 1))
		bonus *= clampf(float(now - stand_since) / ramp, 0.0, 1.0)
	if w.range_scales_with_stage:
		bonus *= stage
	return r + bonus


func damage_type(group: int = SimConstants.GROUP_MAINWEAPON) -> int:
	return SimConstants.damage_mask(bb.get_value("eiDamageType", group, []))


func actionpoint(group: int = SimConstants.GROUP_MAINWEAPON) -> int:
	return bb.get_int("eiWelaActionpoint", group, 0)


func actionduration(group: int = SimConstants.GROUP_MAINWEAPON) -> int:
	return bb.get_int("eiWelaActionduration", group, 0)


## eiWelaTargetCount with TModifierWelaTargetCountComponent (adds eiWelaModifier of the value group).
func target_count(group: int = SimConstants.GROUP_MAINWEAPON) -> int:
	var n := bb.get_int("eiWelaTargetCount", group, 1)
	var w := wela(group)
	if w != null and w.target_count_add_group >= 0:
		var add := bb.get_int("eiWelaModifier", w.target_count_add_group, 0)
		if add > 0 and w.target_count_scale_resource == "reMana":
			add *= mana
		if add > 0:
			n += add
	if group == SimConstants.GROUP_MAINWEAPON:
		for b in buffs:
			n += b.target_count_add
	return n


func attention_range(group: int = SimConstants.GROUP_APPROACH) -> float:
	return bb.get_float("eiAttentionrange", group, SimConstants.DEFAULT_ATTENTION_RANGE)


# ---------------------------------------------------------------- classification

func is_building() -> bool:
	return has("upBuilding")


func is_spawner() -> bool:
	return has("upSpawner")


func is_lane_node() -> bool:
	return has("upLaneNode")


## True for real battlefield entities (units/buildings); false for card entities like spawners and
## for undamageable things like lane nodes (no health).
func is_targetable() -> bool:
	return not is_spawner() and not has("upUntargetable") and max_health > 0.0


func can_attack() -> bool:
	return bb.has_value("eiWelaDamage", SimConstants.GROUP_MAINWEAPON) and not has("upNoAutoAttack")


func can_move() -> bool:
	if is_building() or is_lane_node() or is_spell_effect() or has("upCharm") or speed() <= 0.0 or max_health <= 0.0:
		return false
	for p in ["upRooted", "upGrounded", "upLifted", "upImmobilized"]:
		if has(p):
			return false
	return true


## UNIT_PROPERTIES_PREVENT_THINKING
func can_think(_now: int) -> bool:
	if not alive:
		return false
	for p in ["upSummoningSickness", "upStunned", "upFrozen", "upBanished", "upPetrified"]:
		if has(p):
			return false
	return true


func has_ammo() -> bool:
	return ammo_cost == 0 or ammo >= ammo_cost


func wela(group: int) -> Wela:
	for w in welas:
		if w.group == group:
			return w
	return null
