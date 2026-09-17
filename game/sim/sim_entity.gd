class_name SimEntity
## One simulated unit/building. Pure data + stats; behaviour lives in Simulation.

var id: int = 0
var unit_id: String = ""
var team: int = 0
var league: int = 4
var position: Vector2 = Vector2.ZERO
var front: Vector2 = Vector2.RIGHT
var collision_radius: float = 0.5
var bb: Blackboard = Blackboard.new()
var properties: Dictionary = {}     # "upFlying" -> true, from eiUnitProperties

var health: float = 0.0
var max_health: float = 0.0
var alive: bool = true
var armor: SimConstants.ArmorType = SimConstants.ArmorType.UNARMORED
var speed: float = SimConstants.DEFAULT_SPEED   # units per ms

# Main weapon state (group 1)
var target_id: int = 0
var cooldown_ready_at: int = 0
var fire_at: int = -1            # time when the pending hit lands, -1 = none
var locked_until: int = 0        # action duration lock
var summoning_sick_until: int = 0

var created_at: int = 0
var died_at: int = -1

# Ammo (reWelaCharge) for nexus / lanetower weapons: cost per shot, recharge one per cooldown of the
# ammo group (group 6 in Nexus.ets, group 5 in Lanetower.ets), active after game start.
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

# Movement state (TMovementComponent / TPathfindingComponent)
var moving: bool = false
var move_target_id: int = 0          # entity we walk to, 0 = position target
var move_target_pos: Vector2 = Vector2.ZERO
var move_use_waypoints: bool = false
var path: Array = []                 # tile indices, walked from the back (path.back() is next)
var current_tile: int = -1
var standing_on_tile: int = -1       # tile currently counted as blocked by this entity


func move_goal(sim) -> Vector2:
	if move_target_id != 0:
		var t: SimEntity = sim.entities.get(move_target_id)
		if t != null:
			return t.position
	return move_target_pos


func setup(p_unit_id: String, p_league: int) -> void:
	unit_id = p_unit_id
	league = p_league
	UnitDb.fill_blackboard(bb, unit_id, league)
	collision_radius = bb.get_float("collision_radius", Blackboard.ANY_GROUP, 0.5)
	for p in bb.get_value("eiUnitProperties", Blackboard.ANY_GROUP, []):
		properties[p] = true
	max_health = bb.get_float("eiResourceCap.reHealth", Blackboard.ANY_GROUP, 0.0)
	health = bb.get_float("eiResourceBalance.reHealth", Blackboard.ANY_GROUP, max_health)
	armor = SimConstants.ARMOR_NAMES.get(bb.get_value("eiArmorType", Blackboard.ANY_GROUP, "atUnarmored"), SimConstants.ArmorType.UNARMORED)
	speed = bb.get_float("eiSpeed", Blackboard.ANY_GROUP, SimConstants.DEFAULT_SPEED)
	if bb.has_value("eiResourceCap.reWelaCharge"):
		ammo_cap = bb.get_int("eiResourceCap.reWelaCharge")
		ammo = bb.get_int("eiResourceBalance.reWelaCharge", Blackboard.ANY_GROUP, ammo_cap)
		ammo_cost = bb.get_int("eiResourceCost.reWelaCharge", SimConstants.GROUP_MAINWEAPON, 0)
		var ammo_group := 5 if has("upLanetower") else 6
		ammo_recharge_ms = bb.get_int("eiCooldown", ammo_group, 0)


func has_ammo() -> bool:
	return ammo_cost == 0 or ammo >= ammo_cost


func is_lane_node() -> bool:
	return has("upLaneNode")


func has(prop: String) -> bool:
	return properties.has(prop)


func is_building() -> bool:
	return has("upBuilding")


func is_spawner() -> bool:
	return has("upSpawner")


## True for real battlefield entities (units/buildings); false for card entities like spawners and
## for undamageable things like lane nodes (no health).
func is_targetable() -> bool:
	return not is_spawner() and not has("upUntargetable") and max_health > 0.0


func can_attack() -> bool:
	return bb.has_value("eiWelaDamage", SimConstants.GROUP_MAINWEAPON) and not has("upNoAutoAttack")


func can_move() -> bool:
	return not is_building() and not is_lane_node() and speed > 0.0


func attack_range() -> float:
	return bb.get_float("eiWelaRange", SimConstants.GROUP_MAINWEAPON, 0.0)


func attack_damage() -> float:
	return bb.get_float("eiWelaDamage", SimConstants.GROUP_MAINWEAPON, 0.0)


func attack_cooldown() -> int:
	return bb.get_int("eiCooldown", SimConstants.GROUP_MAINWEAPON, 1000)


func attack_actionpoint() -> int:
	return bb.get_int("eiWelaActionpoint", SimConstants.GROUP_MAINWEAPON, 0)


func attack_actionduration() -> int:
	return bb.get_int("eiWelaActionduration", SimConstants.GROUP_MAINWEAPON, 0)


func attack_damage_type() -> int:
	return SimConstants.damage_mask(bb.get_value("eiDamageType", SimConstants.GROUP_MAINWEAPON, []))


func attention_range() -> float:
	return bb.get_float("eiAttentionrange", SimConstants.GROUP_APPROACH, SimConstants.DEFAULT_ATTENTION_RANGE)


func can_think(now: int) -> bool:
	return alive and now >= summoning_sick_until and not has("upStunned") and not has("upFrozen") \
		and not has("upBanished") and not has("upPetrified")


func may_target_flying() -> bool:
	return not has("upRangedGroundOnly")
