class_name Simulation
## Deterministic fixed-step simulation. Call step() once per SimConstants.TICK_MS.
## Server-authoritative model as in the original; clients only render this state.

signal entity_spawned(entity: SimEntity)
signal entity_died(entity: SimEntity)
signal attack_fired(attacker: SimEntity, target: SimEntity, damage: float)
signal game_tick(counter: int)
signal game_event(name: String)
signal team_lost(team: int)

const TEAM_BLUE: int = 1    # -x side (PvPBlue.dws spawns with team 1)
const TEAM_RED: int = 2     # +x side (PvPRed.dws spawns with team 2)

var time_ms: int = 0
var tick_counter: int = 0            # game ticks (1 s) since game start
var next_game_tick_at: int = SimConstants.GAME_WARMING_MS
var game_started: bool = false
var finished: bool = false
var winner_team: int = 0
var league: int = 4
var rng := RandomNumberGenerator.new()

var map: SimMap
var entities: Dictionary = {}        # id -> SimEntity
var _next_id: int = 1
var commanders: Dictionary = {}      # team -> Commander
var nexus_ids: Dictionary = {}       # team -> entity id
var fired_events: Dictionary = {}


class Commander:
	var team: int
	var gold: float = SimConstants.STARTING_GOLD
	var wood: float = SimConstants.STARTING_WOOD
	var tier: int = SimConstants.STARTING_TIER
	var income_upgrades: int = 0

	func gold_cap() -> float:
		return SimConstants.GOLD_CAP + SimConstants.GOLD_CAP_PER_TIER * (tier - 1)

	func income() -> float:
		return SimConstants.STARTING_INCOME + SimConstants.INCOME_PER_UPGRADE * income_upgrades

	func income_upgrade_cost() -> float:
		return SimConstants.INCOME_UPGRADE_COST + SimConstants.INCOME_UPGRADE_COST_STEP * income_upgrades

	## TCommanderIncomeDefaultComponent + TCommanderIncomeOverflowComponent: gold above cap becomes wood.
	func pay_income() -> void:
		var amount := income()
		var room := maxf(0.0, gold_cap() - gold)
		var to_gold := minf(amount, room)
		gold += to_gold
		wood += amount - to_gold


func _init(seed: int = 1, p_league: int = 4, map_name: String = SimMap.SINGLE) -> void:
	rng.seed = seed
	league = p_league
	map = SimMap.load_map(map_name)
	for team in [TEAM_BLUE, TEAM_RED]:
		var c := Commander.new()
		c.team = team
		commanders[team] = c


## Spawns nexus and lanetowers for both teams (PvPRed.dws / PvPBlue.dws).
func spawn_bases() -> void:
	for team in [TEAM_BLUE, TEAM_RED]:
		var layout := map.base_layout(team)
		spawn("Units/Neutral/NexusLevel1", team, layout["nexus"])
		for p in layout["lanetowers"]:
			spawn("Units/Neutral/LanetowerLevel1", team, p)


func spawn(unit_id: String, team: int, pos: Vector2, front: Vector2 = Vector2.ZERO) -> SimEntity:
	var e := SimEntity.new()
	e.id = _next_id
	_next_id += 1
	e.team = team
	e.setup(unit_id, league)
	e.position = pos
	e.front = front if front != Vector2.ZERO else Vector2(-1.0 if team == TEAM_RED else 1.0, 0.0)
	e.created_at = time_ms
	entities[e.id] = e
	if e.has("upNexus"):
		nexus_ids[team] = e.id
	if e.is_building():
		map.pathfinding.block_permanent_area(pos, e.collision_radius)
	else:
		_enter_tile(e)
		_stand(e)
	entity_spawned.emit(e)
	return e


## Drop a squad the way TWelaEffectFactoryComponent.SpreadSpawns does: scattered inside the drop radius.
func drop_squad(unit_id: String, team: int, pos: Vector2, count: int, radius: float = 3.0) -> Array[SimEntity]:
	var result: Array[SimEntity] = []
	for i in count:
		var offset := Vector2.ZERO
		if count > 1:
			offset = Vector2.RIGHT.rotated(rng.randf() * TAU) * (rng.randf() * radius)
		var e := spawn(unit_id, team, pos + offset)
		e.summoning_sick_until = time_ms + SimConstants.SUMMONING_SICKNESS_MS
		result.append(e)
	return result


func enemy_nexus(team: int) -> SimEntity:
	var other := TEAM_BLUE if team == TEAM_RED else TEAM_RED
	var e: SimEntity = entities.get(nexus_ids.get(other, 0))
	return e if e != null and e.alive else null


func step() -> void:
	if finished:
		return
	time_ms += SimConstants.TICK_MS
	_update_game_tick()
	for e: SimEntity in entities.values():
		if not e.alive:
			continue
		_resolve_pending_fire(e)
		if not e.can_think(time_ms):
			continue
		_think(e)
		_move(e)
	_cleanup_dead()


func _update_game_tick() -> void:
	if time_ms < next_game_tick_at:
		return
	next_game_tick_at += SimConstants.GAME_TICK_MS
	if not game_started:
		game_started = true
		game_event.emit("game_start")
	tick_counter += 1
	for c: Commander in commanders.values():
		c.pay_income()
	_fire_scheduled_events()
	game_tick.emit(tick_counter)


func _fire_scheduled_events() -> void:
	var idx := clampi(league, 1, 5) - 1
	var schedule := {
		"tech_level_2": SimConstants.TECH_LEVEL_2_SECONDS[idx],
		"tech_level_3": SimConstants.TECH_LEVEL_3_SECONDS[idx],
		"showdown": SimConstants.SHOWDOWN_SECONDS[idx],
	}
	for name in schedule:
		if tick_counter >= schedule[name] and not fired_events.has(name):
			fired_events[name] = true
			if name == "tech_level_2":
				for c: Commander in commanders.values():
					c.tier = maxi(c.tier, 2)
			elif name == "tech_level_3":
				for c: Commander in commanders.values():
					c.tier = maxi(c.tier, 3)
			game_event.emit(name)


# ---------------------------------------------------------------- AI (think chain)

func _think(e: SimEntity) -> void:
	if time_ms < e.locked_until:
		return
	if e.can_attack():
		var target := _pick_target(e, e.attack_range())
		if target != null:
			e.target_id = target.id
			_face(e, target.position)
			if e.moving:
				_stand(e)
			if time_ms >= e.cooldown_ready_at and e.fire_at < 0:
				_prefire(e)
			return
		if e.can_move():
			var approach := _pick_target(e, e.attention_range())
			if approach != null:
				e.target_id = approach.id
				_move_to(e, approach.id, approach.position, false)
				return
	e.target_id = 0
	if e.can_move():
		_follow_lane(e)


## TBrainFollowLaneComponent.ThinkChain: walk to the nearest enemy nexus using lane waypoints.
func _follow_lane(e: SimEntity) -> void:
	if e.moving:
		return
	var nexus := enemy_nexus(e.team)
	if nexus == null:
		return
	_move_to(e, nexus.id, nexus.position, true)


## TBrainActionComponent.OnPreFire: hit lands after actionpoint, unit locked for max(actionpoint, actionduration).
func _prefire(e: SimEntity) -> void:
	e.fire_at = time_ms + e.attack_actionpoint()
	e.locked_until = time_ms + maxi(e.attack_actionpoint(), e.attack_actionduration())
	e.cooldown_ready_at = e.fire_at + e.attack_cooldown()


func _resolve_pending_fire(e: SimEntity) -> void:
	if e.fire_at < 0 or time_ms < e.fire_at:
		return
	e.fire_at = -1
	var target: SimEntity = entities.get(e.target_id)
	if target == null or not target.alive:
		return
	var dmg := e.attack_damage()
	attack_fired.emit(e, target, dmg)
	deal_damage(target, dmg, e.attack_damage_type(), e)


func deal_damage(target: SimEntity, amount: float, damage_type: int, _source: SimEntity) -> float:
	if not target.alive or target.has("upInvincible"):
		return 0.0
	var final := SimConstants.apply_armor(amount, target.armor, damage_type)
	target.health -= final
	if target.health <= 0.0:
		_kill(target)
	return final


func _kill(e: SimEntity) -> void:
	e.alive = false
	e.health = 0.0
	e.died_at = time_ms
	_leave_tile(e)
	map.pathfinding.cancel_path(e.id)
	entity_died.emit(e)
	if e.has("upNexus") and not finished:
		finished = true
		winner_team = TEAM_BLUE if e.team == TEAM_RED else TEAM_RED
		team_lost.emit(e.team)


## Targeting priority (Server.Welas.pas:1740-1790): efficiency, then upLowPrio last, then nearest.
## Efficiency modifiers are not implemented yet, so this is: non-low-prio nearest first.
func _pick_target(e: SimEntity, range: float) -> SimEntity:
	var best: SimEntity = null
	var best_key := INF
	for other: SimEntity in entities.values():
		if not other.alive or other.team == e.team or other.has("upUntargetable"):
			continue
		if other.has("upFlying") and not other.has("upGround") and not e.may_target_flying():
			continue
		var dist := e.position.distance_to(other.position) - other.collision_radius - e.collision_radius
		if dist > range:
			continue
		var key := dist + (100000.0 if other.has("upLowPrio") else 0.0)
		if key < best_key:
			best_key = key
			best = other
	return best


func _face(e: SimEntity, at: Vector2) -> void:
	var d := at - e.position
	if d.length_squared() > 0.0001:
		e.front = d.normalized()


# ---------------------------------------------------------------- movement (TMovementComponent, server side)

func _move_to(e: SimEntity, target_id: int, target_pos: Vector2, use_waypoints: bool) -> void:
	var same := e.moving and e.move_target_id == target_id and (target_id != 0 or e.move_target_pos == target_pos)
	if same:
		return
	e.move_target_id = target_id
	e.move_target_pos = target_pos
	e.move_use_waypoints = use_waypoints
	e.moving = true
	_leave_standing(e)
	_compute_path(e)


func _compute_path(e: SimEntity) -> void:
	var goal := e.move_goal(self)
	var nexus := enemy_nexus(e.team)
	var direction := Lanes.direction_toward(e.position, nexus.position) if nexus else Lanes.NORMAL
	e.path = map.pathfinding.compute_path(e.id, e.position, goal, time_ms, e.speed, e.move_use_waypoints, false, direction)
	e.path.reverse()   # walk from the back like FPath[high(FPath)]
	if not e.path.is_empty() and e.path.back() == e.current_tile:
		e.path.pop_back()


func _move(e: SimEntity) -> void:
	if not e.moving or time_ms < e.locked_until:
		return
	var pf := map.pathfinding
	var walking := e.speed * SimConstants.TICK_MS
	var goal := e.move_goal(self)
	var target_tile := pf.index_of(pf.tile_of(goal))
	if e.path.is_empty():
		if e.current_tile == target_tile:
			_stand(e)
			return
		_compute_path(e)
		if e.path.is_empty():
			return
	var pos := e.position
	while not e.path.is_empty():
		var next: int = e.path.back()
		if next != e.current_tile and pf.is_blocked(next) and next != target_tile:
			_compute_path(e)
			return
		var target_pos := goal if next == target_tile else pf.tile_center(pf.tile_from_index(next))
		var dist := pos.distance_to(target_pos)
		if dist <= walking:
			pos = target_pos
			walking -= dist
			e.path.pop_back()
		else:
			pos += (target_pos - pos).normalized() * walking
			break
	_face(e, pos)
	_set_position(e, pos)
	if e.current_tile == target_tile:
		_stand(e)


func _set_position(e: SimEntity, pos: Vector2) -> void:
	e.position = pos
	var tile := map.pathfinding.index_of(map.pathfinding.tile_of(pos))
	if tile != e.current_tile:
		_leave_standing(e)
		e.current_tile = tile


func _enter_tile(e: SimEntity) -> void:
	e.current_tile = map.pathfinding.index_of(map.pathfinding.tile_of(e.position))


## TMovementComponent.OnStand + TPathfindingComponent.OnStand: stop, drop the path, block the tile.
func _stand(e: SimEntity) -> void:
	e.moving = false
	e.path = []
	map.pathfinding.cancel_path(e.id)
	if e.standing_on_tile != e.current_tile:
		_leave_standing(e)
		e.standing_on_tile = e.current_tile
		map.pathfinding.stand_on(e.current_tile)


func _leave_standing(e: SimEntity) -> void:
	if e.standing_on_tile >= 0:
		map.pathfinding.leave(e.standing_on_tile)
		e.standing_on_tile = -1


func _leave_tile(e: SimEntity) -> void:
	_leave_standing(e)
	e.current_tile = -1


func _cleanup_dead() -> void:
	for id in entities.keys():
		var e: SimEntity = entities[id]
		if not e.alive and time_ms - e.died_at > 5000:
			entities.erase(id)


func alive_entities(team: int = 0) -> Array[SimEntity]:
	var out: Array[SimEntity] = []
	for e: SimEntity in entities.values():
		if e.alive and (team == 0 or e.team == team):
			out.append(e)
	return out
