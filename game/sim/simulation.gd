class_name Simulation
## Deterministic fixed-step simulation. Call step() once per SimConstants.TICK_MS.
## Server-authoritative model as in the original; clients only render this state.

signal entity_spawned(entity: SimEntity)
signal entity_died(entity: SimEntity)
signal attack_fired(attacker: SimEntity, target: SimEntity, damage: float)
signal projectile_spawned(projectile: Projectile)
signal projectile_removed(projectile: Projectile, hit: bool)
signal buff_applied(entity: SimEntity, buff: Buff)
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
var projectiles: Dictionary = {}     # id -> Projectile
var _next_id: int = 1
var commanders: Dictionary = {}      # team -> Commander
var nexus_ids: Dictionary = {}       # team -> entity id
var fired_events: Dictionary = {}
var build_zones: Dictionary = {}     # zone id -> BuildZone
var _spawn_rotations: Dictionary = {} # zone id -> Array[Vector2i] of fields not yet spawned this cycle


func _init(seed: int = 1, p_league: int = 4, map_name: String = SimMap.SINGLE) -> void:
	rng.seed = seed
	league = p_league
	map = SimMap.load_map(map_name)
	for team in [TEAM_BLUE, TEAM_RED]:
		commanders[team] = Commander.new(team, league)
	for zone in map.build_zones():
		build_zones[zone.id] = zone
		_spawn_rotations[zone.id] = []


## Spawns nexus and lanetowers for both teams (PvPRed.dws / PvPBlue.dws) and the neutral lane nodes (PvPBase.dws).
func spawn_bases() -> void:
	for team in [TEAM_BLUE, TEAM_RED]:
		var layout := map.base_layout(team)
		spawn("Units/Neutral/NexusLevel1", team, layout["nexus"])
		for p in layout["lanetowers"]:
			spawn("Units/Neutral/LanetowerLevel1", team, p)
	for p in map.lane_node_positions():
		spawn("Units/Neutral/LaneNode", 0, p)


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
	elif e.is_targetable() and not e.is_lane_node() and not e.has("upCharm"):
		_enter_tile(e)
		_stand(e)
	if e.has("upCharm") and commanders.has(team):
		_register_charm(e)
	for w in e.welas:   # TWarheadApplyScriptComponent.ApplyToSelfAtCreate (VoidBowman's Grievous Wounds)
		if w.apply_script_to_self_at_create and Buff.exists(w.apply_script):
			apply_buff(e, w.apply_script, {}, e)
	entity_spawned.emit(e)
	return e


## PromiseOfLifeSpell.ets groups 5-7: a new charm takes a commander charm slot; when the cap (3) is
## reached the oldest own charm is removed first (TWelaEfficiencyCreatedComponent + Kill.Remove).
func _register_charm(e: SimEntity) -> void:
	var c: Commander = commanders[e.team]
	if c.charm_count >= SimConstants.CHARM_COUNT_CAP:
		var oldest: SimEntity = null
		for other: SimEntity in entities.values():
			if other != e and other.alive and other.team == e.team and other.has("upCharm"):
				if oldest == null or other.created_at < oldest.created_at or (other.created_at == oldest.created_at and other.id < oldest.id):
					oldest = other
		if oldest != null:
			_remove_silently(oldest)
	c.charm_count += 1


func _release_charm(e: SimEntity) -> void:
	if e.has("upCharm") and commanders.has(e.team):
		commanders[e.team].charm_count = maxi(0, commanders[e.team].charm_count - 1)


## TWelaEffectReplaceComponent.KeepTakenDamage().KeepResource(reWelaCharge): the tech-up of a nexus or
## lanetower. The old entity vanishes without dying (no loss, no lane node).
func replace_entity(old: SimEntity, new_unit_id: String, new_team: int = -1) -> SimEntity:
	var team := old.team if new_team < 0 else new_team
	_remove_silently(old)
	var e := spawn(new_unit_id, team, old.position, old.front)
	if old.max_health > 0.0 and e.max_health > 0.0:
		e.health = maxf(1.0, e.max_health - (old.max_health - old.health))
	if old.ammo_cap > 0 and e.ammo_cap > 0:
		e.ammo = mini(old.ammo, e.ammo_cap)
	return e


func _remove_silently(e: SimEntity) -> void:
	e.alive = false
	e.died_at = time_ms
	_leave_tile(e)
	map.pathfinding.cancel_path(e.id)
	_release_charm(e)
	for other: SimEntity in entities.values():   # break auras this entity provided
		if other.linked_from(e.id):
			_break_link(e, other)
	entity_died.emit(e)


## ComputeSpawningPattern (BaseConflict.Types.Target.pas:177): squad formation around a point.
static func spawning_pattern(pos: Vector2, front: Vector2, is_spawner: bool, index: int, count: int) -> Vector2:
	if count <= 1:
		return pos
	const SPAWN_DISTANCE := 1.5 / 0.45
	var size := 0.2 if is_spawner else 0.45
	var side := front * SPAWN_DISTANCE * size
	match count:
		2: side = side.rotated(PI / 2) * 0.5
		3: side = side.rotated(PI / 3)
		4: side = side.rotated(PI / 4)
	side = side.rotated((float(index) / count) * TAU)
	return pos + side


## TWelaEffectFactoryComponent.SpreadSpawns without an area of effect: units spawn in formation and get
## Modifiers/SummoningSickness.dws for 1000 ms.
func spawn_squad(unit_id: String, team: int, pos: Vector2, count: int, is_spawner: bool) -> Array[SimEntity]:
	var result: Array[SimEntity] = []
	var front := Vector2(-1.0 if team == TEAM_RED else 1.0, 0.0)
	for i in count:
		var e := spawn(unit_id, team, spawning_pattern(pos, front, is_spawner, i, count), front)
		apply_buff(e, "SummoningSickness", {"Duration": SimConstants.SUMMONING_SICKNESS_MS})
		result.append(e)
	return result


## Drop card: squad appears in formation at the drop point.
func drop_squad(unit_id: String, team: int, pos: Vector2, count: int) -> Array[SimEntity]:
	return spawn_squad(unit_id, team, pos, count, false)


# ---------------------------------------------------------------- buffs (modifier scripts)

func apply_buff(e: SimEntity, script_name: String, params: Dictionary = {}, source: SimEntity = null) -> Buff:
	var b := Buff.create(script_name, time_ms, params)
	if source != null:
		b.source_id = source.id
	e.add_buff(b)
	if b.instant_heal > 0.0:
		e.health = minf(e.max_health, e.health + b.instant_heal)
	if b.stops_movement and e.moving:
		_stand(e)
	for w in e.welas:   # TAutoBrainOnUnitPropertyComponent.TriggerOn (HeavyGunner gains mana when blessed)
		if w.kind != Wela.Kind.ON_PROPERTY:
			continue
		for p in w.trigger_props:
			if b.properties.has(p):
				if w.resource == "reMana":
					e.mana = mini(e.mana_cap, e.mana + int(e.bb.get_float("eiWelaDamage", w.group, 1.0)))
				break
	buff_applied.emit(e, b)
	return b


func _update_buffs(e: SimEntity) -> void:
	for b in e.buffs.duplicate():
		if b.tick_interval > 0 and time_ms >= b.next_tick_at and b.tick_times != 0:
			b.next_tick_at += b.tick_interval
			if b.tick_times > 0:
				b.tick_times -= 1
			if b.dot_damage > 0.0 and not _has_any(e, b.dot_not_props):
				var dot: float = b.dot_damage * (e.max_health if b.dot_percent_of_max else 1.0)
				if b.dot_scales_with_charges:
					dot *= b.charges
				deal_damage(e, dot, b.dot_type, entities.get(b.source_id))
			if b.hot_heal > 0.0:
				heal(e, b.hot_heal, SimConstants.DamageType.HOT, entities.get(b.source_id))
			if b.mana_per_tick > 0:
				e.mana = mini(e.mana_cap, e.mana + b.mana_per_tick)
		if b.is_expired(time_ms) and e.alive:
			e.remove_buff(b)
			if b.kills_on_expiry:   # Undying runs out
				_kill(e)
				return


func _has_any(e: SimEntity, props: Array) -> bool:
	for p in props:
		if e.has(p):
			return true
	return false


## TAutoBrainPreventDeathComponent (Homeland rescue, Guarded): the first matching buff intercepts death,
## sets health, strips buffs, applies its scripts and may teleport the unit next to its own nexus.
func _try_prevent_death(e: SimEntity) -> bool:
	for b in e.buffs.duplicate():
		if not b.prevents_death:
			continue
		if b.rescue_needs_creator:
			var creator: SimEntity = entities.get(b.source_id)
			if creator == null or not creator.alive:
				continue
		e.health = b.rescue_health
		if not b.rescue_removes_all_except.is_empty():
			for other in e.buffs.duplicate():
				var keep := false
				for t in b.rescue_removes_all_except:
					if other.has_type(t):
						keep = true
				if not keep:
					e.remove_buff(other)
		if not b.rescue_removes_any.is_empty():
			for other in e.buffs.duplicate():
				for t in b.rescue_removes_any:
					if other.has_type(t):
						e.remove_buff(other)
						break
		for script in b.rescue_scripts:
			if Buff.exists(script):
				apply_buff(e, script, {}, entities.get(b.source_id))
		if b.rescue_teleports_to_nexus:
			var nexus: SimEntity = entities.get(nexus_ids.get(e.team, 0))
			if nexus != null:
				var toward := Vector2(1.0 if e.team == TEAM_BLUE else -1.0, 0.0)
				_teleport(e, nexus.position + toward * (nexus.collision_radius + e.collision_radius + 1.0))
		for key in e.link_buffs.keys():
			if e.link_buffs[key] == b:
				e.link_buffs.erase(key)
		e.remove_buff(b)
		_charge_creator_for_rescue(b)
		return true
	for w in e.welas:   # the unit's own TAutoBrainPreventDeathComponent (VoidSkeleton group 4: pays 1 soul)
		if w.kind != Wela.Kind.PREVENT_DEATH or w.used or not _wela_ready(e, w):
			continue
		e.mana -= w.mana_cost
		e.health = e.bb.get_float("eiWelaDamage", w.group, 1.0)
		if w.apply_script != "" and Buff.exists(w.apply_script):
			apply_buff(e, w.apply_script, {}, e)
		if w.remove_after_use:
			w.used = true
		return true
	return false


## Guarded payload: TWelaEffectFireComponent.FireInCreator -> creator group 2 pays one charge and, when the
## charges are gone, group 3 removes the creator (Promise of Life field).
func _charge_creator_for_rescue(b: Buff) -> void:
	var creator: SimEntity = entities.get(b.source_id)
	if creator == null or not creator.alive or creator.ammo_cap <= 0:
		return
	creator.ammo -= 1
	if creator.ammo <= 0:
		for w in creator.welas:
			if w.suicide_when_empty:
				_remove_silently(creator)
				return


func _teleport(e: SimEntity, pos: Vector2) -> void:
	_stand(e)
	_leave_standing(e)
	e.position = pos
	_enter_tile(e)
	_stand(e)


# ---------------------------------------------------------------- card play (TCommanderAbility)

enum PlayResult { OK, NOT_READY, BAD_TARGET, LEGENDARY_ALIVE, GAME_OVER }

## Play deck slot `slot_index` of a team. `target` is a Vector2 (drops, buildings) or [zone_id, Vector2i]
## for spawners. Validates readiness, tier, cost, zone and legendary limit, then pays and spawns.
func play_card(team: int, slot_index: int, target: Variant) -> PlayResult:
	if finished:
		return PlayResult.GAME_OVER
	var c: Commander = commanders[team]
	var slot: Commander.DeckSlot = c.slots[slot_index]
	if not slot.is_ready(time_ms, c):
		return PlayResult.NOT_READY
	var card := slot.card
	if card.legendary and _has_legendary_unit(team):
		return PlayResult.LEGENDARY_ALIVE
	var unit_data := UnitDb.raw(card.unit_id)
	var pattern: String = unit_data["values"].get("eiWelaUnitPattern", {}).get("0", "").replace("\\", "/")
	if card.is_spawner():
		if not (target is Array and target.size() == 2):
			return PlayResult.BAD_TARGET
		var zone: BuildZone = build_zones.get(target[0])
		if zone == null or zone.team != team or not zone.is_free(target[1]):
			return PlayResult.BAD_TARGET
		c.pay(slot, time_ms)
		place_spawner(card.unit_id, team, target[0], target[1])
		return PlayResult.OK
	if card.is_spell():
		return _cast_spell(team, c, slot, target)
	if not (target is Vector2) or not _in_drop_zone(team, target):
		return PlayResult.BAD_TARGET
	c.pay(slot, time_ms)
	if card.is_building():
		spawn(pattern, team, target)
	else:
		var count: int = int(unit_data["values"].get("eiWelaCount", {}).get("0", 1))
		drop_squad(pattern, team, target, count)
	return PlayResult.OK


## Spells (SpellTemplate.dws): ctCoordinate spells spawn their effect entity (eiWelaUnitPattern) inside
## the Walkzone; ctEntity spells fire the card entity's own group at the target unit. Multi-mode spells
## (Surge of Light) pick the mode whose constraints accept the target.
func _cast_spell(team: int, c: Commander, slot: Commander.DeckSlot, target: Variant) -> PlayResult:
	var card := slot.card
	if slot.spell_entity == null:
		var e := SimEntity.new()
		e.id = _next_id
		_next_id += 1
		e.team = team
		e.setup(card.unit_id, league)
		slot.spell_entity = e
	var caster := slot.spell_entity
	var map_ids := UnitDb.group_map(UnitDb.raw(card.unit_id))
	var spell_group: int = map_ids.get("SpellGroup", -1)
	if card.target_type == "ctEntity":
		if not (target is int) or not entities.has(target):
			return PlayResult.BAD_TARGET
		var unit: SimEntity = entities[target]
		if not unit.alive or not unit.is_targetable():
			return PlayResult.BAD_TARGET
		var chosen: Wela = null
		for w in caster.welas:
			if not w.commander_cast or not (w.heals or w.damages or w.projectile != "" or w.apply_script != ""):
				continue
			if w.target_allies != (unit.team == team) or not w.target_allowed(unit, caster):
				continue
			if w.charge_cost > 0 and caster.charges_of(w.group) < w.charge_cost:
				continue
			chosen = w
			break
		if chosen == null:
			return PlayResult.BAD_TARGET
		c.pay(slot, time_ms)
		caster.position = unit.position
		_fire_group(caster, chosen.group, unit)
		return PlayResult.OK
	if not (target is Vector2) or not map.in_zone("Walkzone", target):
		return PlayResult.BAD_TARGET
	var pattern: String = caster.bb.get_value("eiWelaUnitPattern", spell_group, "").replace("\\", "/")
	if pattern == "":
		return PlayResult.BAD_TARGET
	c.pay(slot, time_ms)
	var effect := spawn(pattern, team, target)
	_gain_field_charges(effect)
	_think_once(effect)
	return PlayResult.OK


## TThinkImpulseOnceComponent: every fight group fires at up to eiWelaTargetCount targets in range right
## away; a group with TWelaEffectSuicideComponent then removes the effect entity.
func _think_once(e: SimEntity) -> void:
	if not e.thinks_once or e.thought_once:
		return
	e.thought_once = true
	for w in e.welas:
		if w.kind != Wela.Kind.FIGHT:
			continue
		var count := e.bb.get_int("eiWelaTargetCount", w.group, 1)
		for target in _pick_targets(e, w, e.range_of(w.group), count):
			_fire_group(e, w.group, target)
	for w in e.welas:
		if w.suicide and w.kind != Wela.Kind.SELF_GROUND and not w.suicide_when_empty:
			_remove_silently(e)
			return


## Hail of Arrows: +1 charge for every allied unit passing group 3's constraints within its range.
func _gain_field_charges(e: SimEntity) -> void:
	for w in e.welas:
		if w.charge_gain_group < 0 or w.kind != Wela.Kind.FIGHT:
			continue
		for target in _pick_targets(e, w, e.range_of(w.group), 1000):
			e.ammo = mini(e.ammo_cap, e.ammo + 1)


## All valid targets of a wela within range, best first (same ordering as _pick_target).
func _pick_targets(e: SimEntity, w: Wela, range: float, count: int) -> Array[SimEntity]:
	var scored: Array = []
	for other: SimEntity in entities.values():
		if not other.alive or other == e or not other.is_targetable() or other.team == 0:
			continue
		if not w.target_any_team and w.target_allies != (other.team == e.team):
			continue
		if not w.target_allowed(other, e):
			continue
		var dist := e.position.distance_to(other.position) - other.collision_radius
		if dist > range:
			continue
		var key := rng.randf() * range if w.picks_random_targets else dist
		key += (100000.0 if other.has("upLowPrio") else 0.0) - _property_efficiency(w, other) * 1000000.0
		if w.prefer_allies and other.team != e.team:
			key += 10000000.0
		scored.append([key, other])
	scored.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array[SimEntity] = []
	for i in mini(count, scored.size()):
		out.append(scored[i][1])
	return out


## Drops need the map's Drop polygon (TWelaTargetConstraintZoneComponent ZONE_DROP) and the team's dynamic
## drop zone (dzDrop): radius eiWelaRange[3] around the own nexus (31.5) and own lanetowers (30),
## emitted by TDynamicZoneRadialEmitterComponent, so the zone grows as lane nodes are captured.
func _in_drop_zone(team: int, p: Vector2) -> bool:
	if not map.in_zone("Drop", p):
		return false
	for e: SimEntity in entities.values():
		if not e.alive or e.team != team or not (e.has("upNexus") or e.has("upLanetower")):
			continue
		if e.position.distance_to(p) <= e.bb.get_float("eiWelaRange", 3, 0.0):
			return true
	return false


func _has_legendary_unit(team: int) -> bool:
	for e: SimEntity in entities.values():
		if e.alive and e.team == team and e.has("upLegendary"):
			return true
	return false


## Place a spawner card on a build-grid field. Returns null when the field is not free or not the team's.
func place_spawner(unit_id: String, team: int, zone_id: int, field: Vector2i) -> SimEntity:
	var zone: BuildZone = build_zones.get(zone_id)
	if zone == null or zone.team != team or not zone.is_free(field):
		return null
	var e := spawn(unit_id, team, zone.center_of_field(field), zone.front)
	e.build_zone_id = zone_id
	e.build_field = field
	zone.occupy(field, e.id)
	if game_started:
		_spawner_fire(e)   # TBrainSpawnerComponent.OnDeploy
	return e


## TWelaEffectWaveSpawnComponent.Fire: one random not-yet-used field per zone; spawners there fire.
func _wave_spawn() -> void:
	for zone_id in build_zones:
		var rotation: Array = _spawn_rotations[zone_id]
		if rotation.is_empty():
			rotation.assign(build_zones[zone_id].spawn_slots())
		var field: Vector2i = rotation[rng.randi_range(0, rotation.size() - 1)]
		rotation.erase(field)
		var owner_id: int = build_zones[zone_id].entity_at(field)
		var spawner: SimEntity = entities.get(owner_id) if owner_id >= 0 else null
		if spawner != null and spawner.alive:
			_spawner_fire(spawner)


func _spawner_fire(spawner: SimEntity) -> void:
	var zone: BuildZone = build_zones[spawner.build_zone_id]
	var pos := zone.spawn_position_for_field(spawner.build_field)
	var pattern: String = spawner.bb.get_value("eiWelaUnitPattern", 0, "").replace("\\", "/")
	var count: int = spawner.bb.get_int("eiWelaCount", 0, 1)
	spawn_squad(pattern, spawner.team, pos, count, true)


func enemy_nexus(team: int) -> SimEntity:
	var other := TEAM_BLUE if team == TEAM_RED else TEAM_RED
	var e: SimEntity = entities.get(nexus_ids.get(other, 0))
	return e if e != null and e.alive else null


# ---------------------------------------------------------------- main loop

func step() -> void:
	if finished:
		return
	time_ms += SimConstants.TICK_MS
	_update_game_tick()
	for c: Commander in commanders.values():
		c.update_charges(time_ms)
	for e: SimEntity in entities.values():
		if not e.alive or e.is_spawner():
			continue
		if e.is_lane_node():
			_think_lane_node(e)
			continue
		if e.think_once_waits and not e.thought_once:   # TThinkImpulseOnceComponent.WaitOneFrame
			_think_once(e)
			continue
		_update_buffs(e)
		if not e.alive:
			continue
		_recharge_ammo(e)
		_regenerate(e)
		_resolve_pending_fire(e)
		if not e.can_think(time_ms):
			continue
		_think(e)
		_move(e)
		for w in e.welas:   # fields die when their charges are spent (Hail of Arrows group 2)
			if w.suicide_when_empty and e.ammo <= 0 and e.fire_at < 0:
				_remove_silently(e)
				break
	_move_projectiles()
	_cleanup_dead()


func _update_game_tick() -> void:
	if time_ms < next_game_tick_at:
		return
	next_game_tick_at += SimConstants.GAME_TICK_MS
	if not game_started:
		game_started = true
		game_event.emit("game_start")
		for e: SimEntity in entities.values():   # TBrainSpawnerComponent.OnGameStart
			if e.alive and e.is_spawner():
				_spawner_fire(e)
	tick_counter += 1
	for c: Commander in commanders.values():
		c.pay_income()
	if tick_counter % SimConstants.WAVE_EVERY_N_TICKS == 0:   # TWelaReadyNthComponent.Nth(2)
		_wave_spawn()
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
					c.raise_tier(2)
				_tech_up_buildings(2)
			elif name == "tech_level_3":
				for c: Commander in commanders.values():
					c.raise_tier(3)
				_tech_up_buildings(3)
			game_event.emit(name)


# ---------------------------------------------------------------- AI (think chain)

## Think chain in component order: each FIGHT wela (heal, main attack...) may claim the unit; the first
## that has a target in range fires. Otherwise approach the nearest enemy in attention range or follow the lane.
func _think(e: SimEntity) -> void:
	for w in e.welas:
		if w.kind == Wela.Kind.LINK:
			_think_link(e, w)
		elif w.kind == Wela.Kind.FIGHT and w.passive:
			_think_passive(e, w)
	if time_ms < e.locked_until:
		return
	for w in e.welas:
		if w.passive or not _wela_ready(e, w):
			continue
		if w.kind == Wela.Kind.SELF_GROUND:
			if time_ms >= w.cooldown_ready_at and e.fire_at < 0:
				_prefire(e, w, e)
			return
		if w.kind != Wela.Kind.FIGHT:
			continue
		var target := _pick_target(e, w, e.range_of(w.group, time_ms))
		if target == null:
			continue
		e.target_id = target.id
		_face(e, target.position)
		if e.moving:
			_stand(e)
		if time_ms >= w.cooldown_ready_at and e.fire_at < 0:
			_prefire(e, w, target)
		return
	if e.can_move():
		var main := e.wela(SimConstants.GROUP_MAINWEAPON)
		if main != null and e.can_attack():
			var approach := _pick_target(e, main, e.attention_range())
			if approach != null:
				e.target_id = approach.id
				_move_to(e, approach.id, approach.position, false)
				return
	e.target_id = 0
	if e.can_move():
		_follow_lane(e)


func _wela_ready(e: SimEntity, w: Wela) -> bool:
	if w.group == SimConstants.GROUP_MAINWEAPON and (not e.has_ammo() or e.has("upNoAutoAttack")):
		return false
	if w.mana_cost > 0 and e.mana < w.mana_cost:
		return false
	return w.owner_ready(e)


## ThinksPassively fight groups fire on their own cooldown without claiming the unit (Defender group 5).
func _think_passive(e: SimEntity, w: Wela) -> void:
	if time_ms < w.cooldown_ready_at or not _wela_ready(e, w):
		return
	var target := _pick_target(e, w, e.range_of(w.group, time_ms))
	if target == null:
		return
	w.cooldown_ready_at = time_ms + e.cooldown(w.group)
	_fire_group(e, w.group, target)


## TBrainWelaLinkComponent + TWelaLinkEffectComponent: an aura. After the activation delay, every ally in
## range that passes the constraints gets the link (a property and, when a payload script exists, its buff);
## links break when the target leaves the range or either side dies.
func _think_link(e: SimEntity, w: Wela) -> void:
	if time_ms < e.created_at + w.link_delay:
		return
	if w.charge_cost > 0 and e.ammo < w.charge_cost:   # Promise of Life: no charges, no new guards
		return
	var range := e.range_of(w.group)
	var key := SimEntity.link_key(e.id, w.group)
	for other: SimEntity in entities.values():
		var linked: bool = other.link_buffs.has(key)
		var in_range := other.alive and other.team == e.team and other != e \
			and other.position.distance_to(e.position) - other.collision_radius <= range
		if linked and not in_range:
			_break_link_key(other, key)
		elif not linked and in_range and other.is_targetable() and w.target_allowed(other, e):
			var payload := "Links/" + w.link_pattern.get_file().replace("Aura", "")
			var b: Buff
			if Buff.exists(payload):
				b = apply_buff(other, payload, {}, e)
			else:
				b = Buff.new()
				b.name = w.link_pattern
				other.add_buff(b)
			if w.link_property != "":
				b.properties.append(w.link_property)
			other.link_buffs[key] = b


## Break every aura link `source` provides to `target`.
func _break_link(source: SimEntity, target: SimEntity) -> void:
	for key in target.link_buffs.keys():
		if key.begins_with("%d:" % source.id):
			_break_link_key(target, key)


func _break_link_key(target: SimEntity, key: String) -> void:
	var b: Buff = target.link_buffs.get(key)
	if b != null:
		target.remove_buff(b)
		target.link_buffs.erase(key)


## TBrainFollowLaneComponent.ThinkChain: walk to the nearest enemy nexus using lane waypoints.
func _follow_lane(e: SimEntity) -> void:
	if e.moving:
		return
	var nexus := enemy_nexus(e.team)
	if nexus == null:
		return
	_move_to(e, nexus.id, nexus.position, true)


## TBrainActionComponent.OnPreFire: hit lands after actionpoint, unit locked for max(actionpoint, actionduration).
func _prefire(e: SimEntity, w: Wela, target: SimEntity) -> void:
	e.fire_group = w.group
	e.target_id = target.id
	e.fire_at = time_ms + e.actionpoint(w.group)
	e.locked_until = time_ms + maxi(e.actionpoint(w.group), e.actionduration(w.group))
	w.cooldown_ready_at = e.fire_at + e.cooldown(w.group)
	if w.group == SimConstants.GROUP_MAINWEAPON:
		e.cooldown_ready_at = w.cooldown_ready_at


func _resolve_pending_fire(e: SimEntity) -> void:
	if e.fire_at < 0 or time_ms < e.fire_at:
		return
	e.fire_at = -1
	var target: SimEntity = entities.get(e.target_id)
	if target == null or not target.alive:
		return
	_fire_group(e, e.fire_group, target)
	var w := e.wela(e.fire_group)
	var extra := e.target_count(e.fire_group) - 1   # eiWelaTargetCount > 1: hit more targets in range
	if w != null and extra > 0:
		for other in _pick_targets(e, w, e.range_of(e.fire_group, time_ms), extra + 1):
			if other != target and extra > 0:
				_fire_group(e, e.fire_group, other)
				extra -= 1


## eiFire for a wela group at a target: pay costs, run its warheads (heal / damage / kill / projectile /
## apply script / splash groups), then chained groups (TWelaEffectFireComponent) and cooldown resets.
func _fire_group(e: SimEntity, group: int, target: SimEntity) -> void:
	var w := e.wela(group)
	if w == null:
		return
	if group == SimConstants.GROUP_MAINWEAPON:
		e.ammo -= e.ammo_cost   # TWelaEffectPayCostComponent for reWelaCharge
	e.mana -= w.mana_cost
	var amount := e.damage(group)
	if w.damage_scales_with_charges_of >= 0:   # Surge of Light: damage x stored charges
		amount *= e.charges_of(w.damage_scales_with_charges_of)
	if w.charge_cost > 0:
		e.charges[group] = 0 if w.charge_consumes_all else e.charges_of(group) - w.charge_cost
	var dtype := e.damage_type(group)
	if group == e.fire_group or w.kind == Wela.Kind.FIGHT:
		attack_fired.emit(e, target, amount)
	if w.projectile != "":
		_launch_projectile(w.projectile, e, target, amount, dtype, group)
	elif w.changes_max and w.resource == "reHealth":   # eiResourceCapTransaction: raise the cap and fill it
		target.max_health += amount
		target.health += amount
	elif w.kills:
		if target.alive and target != e:
			target.exiled = w.exiles
			_kill(target, e)
	elif w.splash:
		_fire_splash(e, group, target.position)
	elif w.heals:
		heal(target, amount, dtype, e)
	elif w.damages:
		deal_damage(target, amount, dtype, e)
	if w.apply_script != "" and target.alive and Buff.exists(w.apply_script):
		apply_buff(target, w.apply_script, {}, e)
	if w.spawns:   # TWelaEffectFactoryComponent: units appear at the target position
		var pattern: String = e.bb.get_value("eiWelaUnitPattern", group, "").replace("\\", "/")
		var count := e.bb.get_int("eiWelaCount", group, 1)
		if pattern != "" and UnitDb.has_unit(pattern):
			var team := e.team if w.spawn_team < 0 else w.spawn_team
			if w.spawn_spread and count > 1:
				spawn_squad(pattern, team, target.position, count, false)
			else:
				for i in count:
					spawn(pattern, team, target.position)
	if w.charge_gain_group >= 0 and w.kind != Wela.Kind.FIGHT or (w.charge_gain_group >= 0 and w.commander_cast):
		e.charges[w.charge_gain_group] = e.charges_of(w.charge_gain_group) + 1
	for sg in w.instant_target_groups:   # splash warheads around the target position
		_fire_splash(e, sg, target.position)
	for cg in w.chain_groups:
		var cw := e.wela(cg)
		if cw == null or time_ms < cw.cooldown_ready_at or not _wela_ready(e, cw):
			continue
		var chain_target := e if w.chain_to_self else target
		if chain_target.alive and (w.chain_to_self or cw.target_allowed(chain_target, e)):
			_fire_group(e, cg, chain_target)
	for rg in w.reset_cooldown_groups:   # TWelaEffectResetCooldownComponent.Expire
		var rw := e.wela(rg)
		if rw != null:
			rw.cooldown_ready_at = time_ms
			if rg == SimConstants.GROUP_MAINWEAPON:
				e.cooldown_ready_at = time_ms


## TWarheadSplash*Component: every valid entity within eiWelaAreaOfEffect of the point.
func _fire_splash(e: SimEntity, group: int, center: Vector2) -> void:
	var w := e.wela(group)
	if w == null:
		return
	var radius := e.bb.get_float("eiWelaAreaOfEffect", group, 0.0)
	var cone := e.bb.get_float("eiWelaAreaOfEffectCone", group, 0.0)   # full angle; a cone starts at the owner
	var front := (center - e.position).normalized()
	if cone > 0.0:
		center = e.position
	var amount := e.damage(group)
	var dtype := e.damage_type(group)
	for other: SimEntity in entities.values():
		if not other.alive or not other.is_targetable() or other.team == 0:
			continue
		if w.target_allies != (other.team == e.team):
			continue
		if not w.target_allowed(other, e):
			continue
		var offset := other.position - center
		if offset.length() - other.collision_radius > radius:
			continue
		if cone > 0.0 and offset.length() > 0.0001:
			var width_angle := atan(other.collision_radius / maxf(0.01, offset.length()))
			if absf(front.angle_to(offset.normalized())) - width_angle > cone / 2.0:
				continue
		if w.heals:
			heal(other, amount, dtype, e)
		else:
			deal_damage(other, amount, dtype, e)


## Mana regeneration (Priest group 4): +1 per cooldown while below the cap.
func _regenerate(e: SimEntity) -> void:
	if e.mana_cap <= 0:
		return
	var w: Wela = null
	for x in e.welas:
		if x.kind == Wela.Kind.RESOURCE_REGEN and x.resource == "reMana" and e.bb.has_value("eiCooldown", x.group):
			w = x
	if w == null:
		return
	if e.mana >= e.mana_cap:
		w.next_at = -1
		return
	if w.next_at < 0:
		w.next_at = time_ms + e.cooldown(w.group)
	elif time_ms >= w.next_at:
		e.mana = mini(e.mana_cap, e.mana + 1)
		w.next_at = time_ms + e.cooldown(w.group)


## eiTakeDamage read chain: on-take-damage abilities (Shieldblock) then armor, then health.
func deal_damage(target: SimEntity, amount: float, damage_type: int, source: SimEntity) -> float:
	if not target.alive or target.has("upInvincible"):
		return 0.0
	if source != null and source.alive:
		amount = _will_deal_damage(source, amount, damage_type, target)
	amount = _on_take_damage(target, amount, damage_type)
	for b in target.buffs:   # TBuffTakenDamageMultiplierComponent (Spellshield aura)
		if b.taken_damage_mult != 1.0 and (b.taken_damage_types == 0 or damage_type & b.taken_damage_types):
			amount *= b.taken_damage_mult
	var final := SimConstants.apply_armor(amount, target.armor(), damage_type)
	var from_overheal := minf(final, target.overheal)   # THealthComponent.OnDamage: overheal absorbs first
	target.overheal -= from_overheal
	target.health -= final - from_overheal
	if final > 0.0 and source != null and source.alive:
		_on_dealt_damage(source, target)
	if target.health <= 0.0:
		_kill(target, source)
	return final


## TAutoBrainOnDealDamageComponent inside a buff (Grievous Wounds): when ready and the victim passes the
## constraints, apply the script, or refresh its duration and add a stack when it is already there.
func _on_dealt_damage(source: SimEntity, target: SimEntity) -> void:
	for b in source.buffs:
		if b.on_hit_script == "" or time_ms < b.on_hit_ready_at or target == source or not target.alive:
			continue
		if _has_any(target, b.on_hit_must_not_have):
			continue
		var ok := true
		for p in b.on_hit_must_have:
			if not target.has(p):
				ok = false
		if not ok:
			continue
		b.on_hit_ready_at = time_ms + b.on_hit_cooldown_ms
		var existing: Buff = null
		for tb in target.buffs:
			if tb.name == b.on_hit_script:
				existing = tb
		if existing != null:   # TWelaEffectResetCooldownComponent + reWelaCharge +1 on the beacon group
			existing.expires_at = time_ms + existing.duration_ms
			existing.charges = mini(existing.charge_cap, existing.charges + 1)
		elif Buff.exists(b.on_hit_script):
			apply_buff(target, b.on_hit_script, {}, source)


## TModifierMultiplyDealtDamageComponent (Archer Relentless): multiply by eiWelaModifier of the value group
## when the target passes that group's constraints and the damage type is allowed.
func _will_deal_damage(source: SimEntity, amount: float, damage_type: int, target: SimEntity) -> float:
	for w in source.welas:
		if w.kind != Wela.Kind.DEALT_DAMAGE_MULT or not w.weapon_groups.has(source.fire_group):
			continue
		if damage_type & w.must_not_have_damage_types:
			continue
		if w.target_allowed(target):
			amount *= source.bb.get_float("eiWelaModifier", w.group, 1.0)
	return amount


## TAutoBrainOnTakeDamageComponent.ModifiesAmount + TWelaTriggerCheckTakeDamageThresholdComponent (Shieldblock):
## when ready and the hit passes the threshold, the amount is multiplied by eiWelaModifier (0 = blocked).
func _on_take_damage(target: SimEntity, amount: float, _damage_type: int) -> float:
	for b in target.buffs.duplicate():   # Shieldblock granted by a buff (Shields Up): one block, then spent
		if b.block_threshold >= 0.0 and amount >= b.block_threshold:
			amount *= b.block_factor
			if b.block_once:
				target.remove_buff(b)
	for w in target.welas:
		if w.kind != Wela.Kind.ON_TAKE_DAMAGE or time_ms < w.cooldown_ready_at:
			continue
		var threshold := target.bb.get_float("eiWelaDamage", w.group, 0.0)
		var passes := amount <= threshold if w.threshold_lesser_equal else amount >= threshold
		if passes:
			amount *= target.bb.get_float("eiWelaModifier", w.group, 1.0)
			w.cooldown_ready_at = time_ms + target.cooldown(w.group)
	return amount


## THealthComponent.OnHeal: heal up to max health; with dtOverheal the rest becomes overheal, capped at
## max_health * OVERHEAL_LIMIT_FACTOR.
func heal(target: SimEntity, amount: float, damage_type: int, _source: SimEntity) -> float:
	if not target.alive or target.has("upUnhealable"):
		return 0.0
	for b in target.buffs:   # TBuffTakenDamageMultiplierComponent.ApplyOnHeal (Bleeding: 60 %)
		amount *= b.taken_heal_mult
	var healed := minf(amount, target.max_health - target.health)
	target.health += healed
	var over := 0.0
	if damage_type & SimConstants.DamageType.OVERHEAL:
		over = maxf(0.0, minf(amount - healed, target.max_health * SimConstants.OVERHEAL_LIMIT_FACTOR - target.overheal))
		target.overheal += over
	if healed + over > 0.0:
		_on_healed(target, healed + over)
	return healed + over


## TAutoBrainOnHealedComponent: fires once (or once per TimesForEach healed) on the owner; the group may
## add mana (HeavyGunner) or chain-fire another group (Defender's Wall of Light).
func _on_healed(e: SimEntity, healed: float) -> void:
	for w in e.welas:
		if w.kind != Wela.Kind.ON_HEALED:
			continue
		var times := 1 if w.times_for_each <= 0 else int(roundf(healed)) / w.times_for_each
		for i in times:
			if w.resource == "reMana":
				e.mana = mini(e.mana_cap, e.mana + 1)
			for cg in w.chain_groups:
				var cw := e.wela(cg)
				if cw == null or not _wela_ready(e, cw):
					continue
				var target := _pick_target(e, cw, e.range_of(cg))
				if target != null:
					_fire_group(e, cg, target)


func _kill(e: SimEntity, killer: SimEntity = null) -> void:
	if not e.exiled and _try_prevent_death(e):
		return
	if not e.exiled:
		_on_before_death(e, killer)
	e.alive = false
	e.health = 0.0
	e.died_at = time_ms
	_leave_tile(e)
	map.pathfinding.cancel_path(e.id)
	if e.is_spawner() and build_zones.has(e.build_zone_id):
		build_zones[e.build_zone_id].release(e.build_field)
	_release_charm(e)
	for other: SimEntity in entities.values():   # break auras this entity provided
		if other.linked_from(e.id):
			_break_link(e, other)
	entity_died.emit(e)
	_release_soul(e)
	if e.has("upNexus") and not finished:
		finished = true
		winner_team = TEAM_BLUE if e.team == TEAM_RED else TEAM_RED
		team_lost.emit(e.team)
	elif e.has("upLanetower") and not e.exiled:
		spawn("Units/Neutral/LaneNode", 0, e.position)   # Lanetower.ets group 2: TAutoBrainOnDeath -> LaneNode


## UnitTemplate/BuildingTemplate GROUP_SOUL: every death (unless exiled or upSoulless) spawns
## Projectiles/Black/SoulGatherProjectileSpawner at the corpse; next tick it sends one soul projectile
## to a random non-full upSoulGatherer within 12 (allies preferred, enemies eligible) and vanishes.
func _release_soul(e: SimEntity) -> void:
	if e.exiled or e.has("upSoulless"):
		return
	var pattern: String = e.bb.get_value("eiWelaUnitPattern", SimConstants.GROUP_SOUL, "").replace("\\", "/")
	if pattern != "" and UnitDb.has_unit(pattern):
		spawn(pattern, e.team, e.position)


## TWarheadSpottyResourceComponent(reMana) / eiResourceTransaction: souls and other mana gains, capped.
func gain_mana(e: SimEntity, amount: int) -> void:
	var fitted := mini(e.mana_cap - e.mana, amount)
	if fitted <= 0:
		return
	e.mana += fitted
	for w in e.welas:   # TAutoBrainOnResourceComponent: once, or once per unit that fit (TimesForEach)
		if w.kind != Wela.Kind.ON_RESOURCE or not w.resource_triggers.has("reMana") or not _wela_ready(e, w):
			continue
		for i in (fitted if w.times_for_each > 0 else 1):
			_fire_group(e, w.group, e)


## TAutoBrainOnBeforeDeath (deathrattles): fire the group's projectile at the current target, or at a
## random enemy in range when the wela picks random targets.
func _on_before_death(e: SimEntity, _killer: SimEntity) -> void:
	for w in e.welas:
		if w.kind != Wela.Kind.ON_DEATH or w.projectile == "" or not w.owner_ready(e):
			continue
		var count := e.target_count(w.group)
		var target: SimEntity = entities.get(e.target_id)
		if w.picks_random_targets or target == null or not target.alive:
			var candidates: Array[SimEntity] = []
			for other: SimEntity in entities.values():
				if other.alive and other.team != 0 and w.target_allies == (other.team == e.team) and other.is_targetable() \
					and w.target_allowed(other, e) \
					and other.position.distance_to(e.position) - other.collision_radius - e.collision_radius <= e.range_of(w.group):
					candidates.append(other)
			for i in count:
				if candidates.is_empty():
					break
				var index := rng.randi_range(0, candidates.size() - 1)
				_launch_projectile(w.projectile, e, candidates[index], e.damage(w.group), e.damage_type(w.group), w.group)
				if not w.picks_with_repetition:
					candidates.remove_at(index)
		elif count > 0:
			_launch_projectile(w.projectile, e, target, e.damage(w.group), e.damage_type(w.group), w.group)


## Targeting (Server.Welas.pas:1740-1790): efficiency first (missing health for heals), then upLowPrio last,
## then nearest. Allies or enemies per the wela's team constraint.
func _pick_target(e: SimEntity, w: Wela, range: float) -> SimEntity:
	var best: SimEntity = null
	var best_key := INF
	for other: SimEntity in entities.values():
		if not other.alive or other == e or not other.is_targetable():
			continue
		if w.target_allies != (other.team == e.team) or other.team == 0:
			continue
		if other.has("upFlying") and not other.has("upGround") and not e.may_target_flying():
			continue
		if not w.target_allowed(other, e):
			continue
		var dist := e.position.distance_to(other.position) - other.collision_radius - e.collision_radius
		if dist > range:
			continue
		var key := dist + (100000.0 if other.has("upLowPrio") else 0.0)
		if w.efficiency_missing_health:
			key -= (other.max_health - other.health) * 1000.0
		if w.efficiency_max_health != 0:
			key -= other.max_health * 1000.0 * w.efficiency_max_health
		key -= _property_efficiency(w, other) * 1000000.0
		if key < best_key:
			best_key = key
			best = other
	return best


## TWelaEfficiencyUnitPropertyComponent: 1 when the target has any prioritized property (0 otherwise), reversed if asked.
func _property_efficiency(w: Wela, target: SimEntity) -> float:
	if w.prioritize_props.is_empty():
		return 0.0
	var hit := 0.0
	for p in w.prioritize_props:
		if target.has(p):
			hit = 1.0
			break
	return 1.0 - hit if w.prioritize_reversed else hit


func _face(e: SimEntity, at: Vector2) -> void:
	var d := at - e.position
	if d.length_squared() > 0.0001:
		e.front = d.normalized()


# ---------------------------------------------------------------- projectiles

## TWelaEffectProjectileComponent.Fire: the projectile carries the shooter's weapon values.
func _launch_projectile(pattern: String, shooter: SimEntity, target: SimEntity, dmg: float, damage_type: int, group: int = -1) -> Projectile:
	var p := Projectile.new(pattern, league)
	p.id = _next_id
	_next_id += 1
	p.team = shooter.team
	p.source_id = shooter.id
	p.target_id = target.id
	p.position = shooter.position
	p.last_target_position = target.position
	p.damage = dmg
	p.damage_type = damage_type
	p.created_at = time_ms
	if group >= 0:   # the shooter's group values ride along (eiWelaAreaOfEffect, eiWelaSplashfactor)
		if shooter.bb.has_value("eiWelaAreaOfEffect", group):
			p.aoe = shooter.bb.get_float("eiWelaAreaOfEffect", group, 0.0)
		if shooter.bb.has_value("eiWelaSplashfactor", group):
			p.splash_factor = shooter.bb.get_float("eiWelaSplashfactor", group, 10000.0)
	projectiles[p.id] = p
	projectile_spawned.emit(p)
	return p


## TWarheadSplashDamageComponent on impact: every enemy within the area takes damage; with a splash
## factor the total pool is damage * factor spread evenly, each capped at the full damage.
func _projectile_splash(p: Projectile, primary: SimEntity) -> void:
	var source: SimEntity = entities.get(p.source_id)
	var targets: Array[SimEntity] = []
	for other: SimEntity in entities.values():
		if not other.alive or other.team == p.team or other.team == 0 or not other.is_targetable():
			continue
		if other.position.distance_to(primary.position) - other.collision_radius <= p.aoe:
			targets.append(other)
	if targets.is_empty():
		return
	var per_target := minf(p.damage, p.damage * p.splash_factor / targets.size())
	for other in targets:
		deal_damage(other, per_target, p.damage_type, source)


## TMovementComponent.IdleDirect with range 0 toward the (homing) target, then FireAtTarget on arrival.
func _move_projectiles() -> void:
	for id in projectiles.keys():
		var p: Projectile = projectiles[id]
		var target: SimEntity = entities.get(p.target_id)
		if target != null and target.alive:
			p.last_target_position = target.position
		var to_target := p.last_target_position - p.position
		var dist := to_target.length()
		var walking := p.speed * SimConstants.TICK_MS
		if dist <= walking:
			p.position = p.last_target_position
			var hit := target != null and target.alive
			if hit:
				if p.gives_mana:
					gain_mana(target, int(p.damage))
				elif p.aoe > 0.0:
					_projectile_splash(p, target)
				else:
					deal_damage(target, p.damage, p.damage_type, entities.get(p.source_id))
			projectiles.erase(id)
			projectile_removed.emit(p, hit)
		else:
			p.position += to_target / dist * walking


# ---------------------------------------------------------------- ammo, tech-ups, lane nodes

## Ammo group (Nexus.ets [6], Lanetower.ets [5]): after game start, +1 charge every cooldown, capped.
func _recharge_ammo(e: SimEntity) -> void:
	if e.ammo_recharge_ms <= 0 or not game_started:
		return
	if e.ammo_next_at < 0:
		e.ammo_next_at = time_ms + e.ammo_recharge_ms
	elif time_ms >= e.ammo_next_at:
		e.ammo = mini(e.ammo_cap, e.ammo + 1)
		e.ammo_next_at += e.ammo_recharge_ms


## NexusLevel1/LanetowerLevel1 -> Level2 at tech 2, Level2 -> Level3 at tech 3 (group 4 pattern).
func _tech_up_buildings(level: int) -> void:
	for e: SimEntity in entities.values():
		if not e.alive or not e.unit_id.ends_with("Level%d" % (level - 1)):
			continue
		var next: String = e.bb.get_value("eiWelaUnitPattern", 4, "").replace("\\", "/")
		if next != "":
			replace_entity(e, next)


## TBrainCapturePointComponent (LaneNode.ets): every 500 ms look for units/buildings of any team within
## 16.5. Exactly one team present primes the node for that team; two teams contest it. The primed team gains
## +1 team power per think (cap 15), the other loses 1. At 15 the node becomes that team's lanetower of the
## team's current tier.
func _think_lane_node(node: SimEntity) -> void:
	if not game_started or time_ms < node.capture_next_at:
		return
	node.capture_next_at = time_ms + node.bb.get_int("eiCooldown", 1, 500)
	var range := node.bb.get_float("eiWelaRange", 1, 16.5)
	var near_teams := {}
	for e: SimEntity in entities.values():
		if not e.alive or e.team == 0 or e.is_spawner() or e.has("upBase") or not (e.has("upUnit") or e.has("upBuilding")):
			continue
		if e.position.distance_to(node.position) - e.collision_radius <= range:
			near_teams[e.team] = true
	if near_teams.size() == 1:
		node.capturing_team = near_teams.keys()[0]
	elif near_teams.size() > 1:
		node.capturing_team = -1
	if node.capturing_team < 0:
		return
	var cap := node.bb.get_float("eiResourceCap.reTeamPower1", Blackboard.ANY_GROUP, 15.0)
	for team in [TEAM_BLUE, TEAM_RED]:
		var power: float = node.team_power.get(team, 0.0)
		power += 1.0 if team == node.capturing_team else -1.0
		node.team_power[team] = clampf(power, 0.0, cap)
	var winner: int = node.capturing_team
	if node.team_power[winner] >= cap:
		var tier: int = commanders[winner].tier
		replace_entity(node, "Units/Neutral/LanetowerLevel%d" % tier, winner)


# ---------------------------------------------------------------- movement (TMovementComponent, server side)

func _move_to(e: SimEntity, target_id: int, target_pos: Vector2, use_waypoints: bool) -> void:
	var same := e.moving and e.move_target_id == target_id and (target_id != 0 or e.move_target_pos == target_pos)
	if same:
		return
	e.move_target_id = target_id
	e.move_target_pos = target_pos
	e.move_use_waypoints = use_waypoints
	e.moving = true
	e.stand_since = -1
	_leave_standing(e)
	_compute_path(e)


func _compute_path(e: SimEntity) -> void:
	var goal := e.move_goal(self)
	var nexus := enemy_nexus(e.team)
	var direction := Lanes.direction_toward(e.position, nexus.position) if nexus else Lanes.NORMAL
	e.path = map.pathfinding.compute_path(e.id, e.position, goal, time_ms, e.speed(), e.move_use_waypoints, false, direction)
	e.path.reverse()   # walk from the back like FPath[high(FPath)]
	if not e.path.is_empty() and e.path.back() == e.current_tile:
		e.path.pop_back()


func _move(e: SimEntity) -> void:
	if not e.moving or time_ms < e.locked_until or not e.can_move():
		return
	var pf := map.pathfinding
	var walking := e.speed() * SimConstants.TICK_MS
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
	if e.moving or e.stand_since < 0:
		e.stand_since = time_ms
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


## Alive entities of a team; team -1 = every team (0 is the neutral team).
func alive_entities(team: int = -1) -> Array[SimEntity]:
	var out: Array[SimEntity] = []
	for e: SimEntity in entities.values():
		if e.alive and (team == -1 or e.team == team):
			out.append(e)
	return out
