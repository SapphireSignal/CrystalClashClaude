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


func spawn(unit_id: String, team: int, pos: Vector2, front: Vector2 = Vector2.ZERO, level: int = 0) -> SimEntity:
	var e := SimEntity.new()
	e.id = _next_id
	_next_id += 1
	e.team = team
	e.setup(unit_id, league, level)
	for g in e.bb.groups_of("eiCooldown"):   # SaplingchargeSapling: eiCooldown 'round(random * 500)'
		var v: Variant = e.bb.get_value("eiCooldown", g)
		if v is String:
			var m := RegEx.create_from_string("random\\s*\\*\\s*([0-9.]+)").search(v)
			assert(m != null, "unsupported eiCooldown expression %s in %s" % [v, unit_id])
			e.bb.set_value("eiCooldown", g, int(roundf(rng.randf() * float(m.get_string(1)))))
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
	if e.has("upGadget") and commanders.has(team):
		_register_gadget(e)
	for w in e.welas:
		if not w.ready_at_start:   # TWelaReadyCooldownComponent(false): the first use waits a full cooldown
			w.cooldown_ready_at = time_ms + e.cooldown(w.group)
		if w.apply_script_to_self_at_create and Buff.exists(w.apply_script):   # ApplyToSelfAtCreate
			apply_buff(e, w.apply_script, _script_params(w.apply_script, w.apply_script_values), e)
	entity_spawned.emit(e)
	return e


func _apply_scripted(target: SimEntity, script: String, values: Array, same_team: bool, e: SimEntity) -> void:
	var params := _script_params(script, values)
	if same_team:
		params["SameTeam"] = target.team == e.team
	apply_buff(target, script, params, e)


## PassIntValue(...) arguments matched to the script's parameter names (LegendarySpawn: Duration).
func _script_params(script: String, values: Array) -> Dictionary:
	var params := {}
	var names := Buff.params_of(script)
	for i in mini(names.size(), values.size()):
		params[names[i]] = values[i]
	return params


## Gadget building cards: TWelaReadyResourceCompareComponent(reGadgetCount).CheckFull -> the oldest gadget is
## sacrificed (a real death) when a 6th one is placed; gadgets count themselves in and out (groups 3/4).
func _register_gadget(e: SimEntity) -> void:
	var c: Commander = commanders[e.team]
	if c.gadget_count >= SimConstants.GADGET_COUNT_CAP:
		var oldest: SimEntity = null
		for other: SimEntity in entities.values():
			if other != e and other.alive and other.team == e.team and other.has("upGadget"):
				if oldest == null or other.created_at < oldest.created_at or (other.created_at == oldest.created_at and other.id < oldest.id):
					oldest = other
		if oldest != null:
			_kill(oldest)
	c.gadget_count += 1


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
func spawn_squad(unit_id: String, team: int, pos: Vector2, count: int, is_spawner: bool, level: int = 0) -> Array[SimEntity]:
	var result: Array[SimEntity] = []
	var front := Vector2(-1.0 if team == TEAM_RED else 1.0, 0.0)
	for i in count:
		var e := spawn(unit_id, team, spawning_pattern(pos, front, is_spawner, i, count), front, level)
		apply_buff(e, "SummoningSickness", {"Duration": SimConstants.SUMMONING_SICKNESS_MS})
		result.append(e)
	return result


## Drop card: squad appears in formation at the drop point.
func drop_squad(unit_id: String, team: int, pos: Vector2, count: int, level: int = 0) -> Array[SimEntity]:
	return spawn_squad(unit_id, team, pos, count, false, level)


# ---------------------------------------------------------------- buffs (modifier scripts)

func apply_buff(e: SimEntity, script_name: String, params: Dictionary = {}, source: SimEntity = null) -> Buff:
	var full := params.duplicate()   # Entity.HasDamageType(dtMelee / dtRanged) for conditional script parts
	var main_type := e.damage_type(SimConstants.GROUP_MAINWEAPON)
	full["__dtMelee"] = (main_type & SimConstants.DamageType.MELEE) != 0
	full["__dtRanged"] = (main_type & SimConstants.DamageType.RANGED) != 0
	var b := Buff.create(script_name, time_ms, full)
	if b.health_bonus_cap_factor != 0.0:   # BlessingHealth: +30 % of max health + 50
		b.health_bonus = b.health_bonus_cap_factor * e.max_health + b.health_bonus_add
	if source != null:
		b.source_id = source.id
	e.add_buff(b)
	if b.instant_heal > 0.0:
		e.health = minf(e.max_health, e.health + b.instant_heal)
	if b.stops_movement and e.moving:
		_stand(e)
	for w in e.welas:   # TAutoBrainOnUnitPropertyComponent.TriggerOn (HeavyGunner gains mana when blessed)
		if w.trigger_props.is_empty() or w.used:
			continue
		for p in w.trigger_props:
			if b.properties.has(p):
				if w.resource == "reMana" and not w.changes_max:
					e.mana = mini(e.mana_cap, e.mana + int(e.bb.get_float("eiWelaDamage", w.group, 1.0)))
				else:
					_fire_group(e, w.group, e)   # VoidSlime: +250 max health, once per status
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
				heal(e, b.hot_heal * (e.max_health if b.hot_percent_of_max else 1.0), SimConstants.DamageType.HOT, entities.get(b.source_id))
			if b.mana_per_tick > 0:
				e.mana = mini(e.mana_cap, e.mana + b.mana_per_tick)
			if b.shard_projectile != "":   # Frostspear: one shard at a random unit of the victim's team within range
				var candidates: Array[SimEntity] = []
				for other: SimEntity in entities.values():
					if other.alive and other != e and other.team == e.team and other.is_targetable() \
						and not _has_any(other, b.shard_must_not_have) \
						and other.position.distance_to(e.position) - other.collision_radius <= b.shard_range:
						candidates.append(other)
				if not candidates.is_empty():
					_launch_projectile(b.shard_projectile, e, candidates[rng.randi_range(0, candidates.size() - 1)], b.shard_damage, b.shard_type)
			if b.tick_times == 0 and b.remove_when_ticks_done:
				e.remove_buff(b)
				continue
		if b.is_expired(time_ms) and e.alive:
			if not b.late_properties.is_empty():   # Frozen ends, the immunity group keeps running
				b.properties = b.late_properties
				b.late_properties = []
				b.removed_properties = []
				b.expires_at = b.late_expires_at
				b.stops_movement = false
				if b.on_expire_script != "" and Buff.exists(b.on_expire_script):   # Grounded -> GroundedEnds take-off
					apply_buff(e, b.on_expire_script, {}, entities.get(b.source_id))
					b.on_expire_script = ""
				continue
			e.remove_buff(b)
			if b.on_expire_script != "" and Buff.exists(b.on_expire_script):   # Grounded -> GroundedEnds take-off
				apply_buff(e, b.on_expire_script, {}, entities.get(b.source_id))
			if b.kills_on_expiry:   # Undying runs out
				_kill(e)
				return


func _has_any_in(props: Array, wanted: Array) -> bool:
	for p in wanted:
		if props.has(p):
			return true
	return false


func _has_all(e: SimEntity, props: Array) -> bool:
	for p in props:
		if not e.has(p):
			return false
	return true


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
	slot.times_played += 1   # TWelaEffectIncreaseResourceComponent(reCardTimesPlayed) fires before the factory
	var level := mini(slot.times_played, int(UnitDb.raw(pattern)["values"].get("eiResourceCap.reLevel", {}).get("*", 0)))
	if card.is_building():
		spawn(pattern, team, target, Vector2.ZERO, level)
	else:
		var count: int = int(unit_data["values"].get("eiWelaCount", {}).get("0", 1))
		drop_squad(pattern, team, target, count, level)
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
			if not w.commander_cast or not (w.heals or w.damages or w.projectile != "" or w.apply_script != "" or w.spawns or w.kills):
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
		_on_commander_ability_used(team, unit.position)
		return PlayResult.OK
	if not (target is Vector2) or not map.in_zone("Walkzone", target):
		return PlayResult.BAD_TARGET
	var pattern: String = caster.bb.get_value("eiWelaUnitPattern", spell_group, "").replace("\\", "/")
	if pattern == "":
		return PlayResult.BAD_TARGET
	c.pay(slot, time_ms)
	var effect := spawn(pattern, team, target)
	_gain_field_charges(effect)
	if not effect.think_once_waits:   # timed effects (Rip Out Soul) act from step() after their delay
		_think_once(effect)
	_on_commander_ability_used(team, target)
	return PlayResult.OK


## TAutoBrainOnCommanderAbilityUsedComponent.ConstraintOnSameTeamID.ConstraintOnInWelaRange.FireAtSelf:
## Blue "Induction": every own unit with the group within eiWelaRange of the spell target fires it at itself.
func _on_commander_ability_used(team: int, at: Vector2) -> void:
	for e: SimEntity in entities.values():
		if not e.alive or e.team != team:
			continue
		for w in e.welas:
			if w.kind == Wela.Kind.ON_ABILITY_USED and not w.used and e.position.distance_to(at) <= e.range_of(w.group):
				_fire_group(e, w.group, e)


## TThinkImpulseOnceComponent: every fight group fires at up to eiWelaTargetCount targets in range right
## away; a group with TWelaEffectSuicideComponent then removes the effect entity.
var _in_think_once: bool = false   # one-shot effects remove themselves after all their groups fired


func _think_once(e: SimEntity) -> void:
	if not e.thinks_once or e.thought_once:
		return
	e.thought_once = true
	_in_think_once = true
	for w in e.welas:
		if w.kind == Wela.Kind.SELF_GROUND:
			_fire_group(e, w.group, e)
		if w.kind != Wela.Kind.FIGHT:
			continue
		var count := e.bb.get_int("eiWelaTargetCount", w.group, 1)
		for target in _pick_targets(e, w, e.range_of(w.group), count):
			_fire_group(e, w.group, target)
	_in_think_once = false
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
		if (w.prefer_allies and other.team != e.team) or (w.prefer_enemies and other.team == e.team):
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
			_think_passives(e)   # the recapture block (group 10 + team) expires through its own passive group
			_think_lane_node(e)
			continue
		if e.lifetime_ms > 0 and time_ms >= e.created_at + e.lifetime_ms:   # GROUP_BUILDING_LIFETIME suicide
			_kill(e)
			continue
		_update_buffs(e)
		if not e.alive:
			continue
		_recharge_ammo(e)
		_regenerate(e)
		_resolve_pending_fire(e)
		_think_passives(e)
		_think_timers(e)
		if e.think_once_waits and not e.thought_once:   # WaitOneFrame / TThinkImpulseTimerCooldownComponent
			if time_ms >= e.created_at + e.think_delay_ms:
				_think_once(e)
			continue
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
## Passive brains (auras, ThinksPassively fight groups, self-target groups) run every tick, even while the
## unit is frozen or stunned: Vecra melts her own prison while carrying upFrozen.
## TThinkImpulseTimerCooldownComponent: the group thinks every eiCooldown (first time after one period);
## fight groups pick their targets, self-ground groups fire at the owner, Nth gates the nth think.
func _think_timers(e: SimEntity) -> void:
	for w in e.welas:
		if w.timer_period < 0 or not e.alive:
			continue
		if w.next_at < 0:
			w.next_at = e.created_at + w.timer_period
		if time_ms < w.next_at:
			continue
		w.next_at += maxi(w.timer_period, SimConstants.TICK_MS)
		if not w.active or w.used:
			continue
		w.think_count += 1
		if w.nth > 0 and w.think_count != w.nth:
			continue
		if not _wela_ready(e, w):
			continue
		if w.kind == Wela.Kind.FIGHT:
			for target in _pick_targets(e, w, e.range_of(w.group), e.bb.get_int("eiWelaTargetCount", w.group, 1)):
				_fire_group(e, w.group, target)
		else:
			_fire_group(e, w.group, e)


func _think_passives(e: SimEntity) -> void:
	for w in e.welas:
		if not w.active and w.link_delay > 0 and time_ms >= e.created_at + w.link_delay:
			w.active = true   # TWelaHelperActivateTimerComponent
		if not w.active or w.used:
			continue
		if w.kind == Wela.Kind.LINK:
			_think_link(e, w)
		elif w.kind == Wela.Kind.FIGHT and w.passive and (not w.think_local or w.think_immediate):
			_think_passive(e, w)
		elif w.kind == Wela.Kind.SELF_PASSIVE:
			_think_self_passive(e, w)


func _think(e: SimEntity) -> void:
	if time_ms < e.locked_until:
		return
	var waiting := false   # a fight group has a target but is on cooldown: hold position, let other groups act
	for w in e.welas:
		if w.passive or not w.active or w.used or w.timer_period >= 0 or not _wela_ready(e, w):
			continue   # timer-driven groups think from _think_timers only
		if w.kind == Wela.Kind.SELF_GROUND:
			if time_ms >= w.cooldown_ready_at and e.fire_at < 0:
				_prefire(e, w, e)
				return
			continue
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
		waiting = true
	if waiting:
		return
	for w in e.welas:   # TBrainWelaLinkComponent.Preemptive: a linked Rootling stands still
		if w.kind == Wela.Kind.LINK and w.preemptive_link and _link_count(e, w) > 0:
			if e.moving:
				_stand(e)
			return
	for w in e.welas:   # TBrainWaitComponent: stop while an enemy is within its attention range
		if w.kind == Wela.Kind.WAIT and _pick_target(e, w, e.attention_range(w.group)) != null:
			if e.moving:
				_stand(e)
			return
	if e.can_move():
		for w in e.welas:   # TBrainApproachComponent groups, in order (group 0 enemies; HeartOfTheForest group 4 allies)
			if not w.approach or w.used or not _wela_ready(e, w):
				continue
			if w.group == SimConstants.GROUP_APPROACH and not e.can_attack():
				continue
			var approach := _pick_target(e, w, e.attention_range(w.group))
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
	if w.charge_cost > 0 and e.charges_of(w.group) < w.charge_cost:
		return false
	if w.ready_nearby_group >= 0:   # TWelaReadyEntityNearbyComponent: ObserverDrone cloaks while no enemy is within 15
		var nearby := e.wela(w.ready_nearby_group)
		var found := nearby != null and not _pick_targets(e, nearby, e.range_of(nearby.group), 1).is_empty()
		if found == w.ready_if_no_targets:
			return false
	return w.owner_ready(e)


## ThinksPassively fight groups fire on their own cooldown without claiming the unit (Defender group 5).
func _think_passive(e: SimEntity, w: Wela) -> void:
	if time_ms < w.cooldown_ready_at or not _wela_ready(e, w):
		return
	if w.passive_if_conscious and not e.can_think(time_ms):   # ThinksPassivelyIfConscious: not while stunned / frozen
		return
	var targets := _pick_targets(e, w, e.range_of(w.group, time_ms), e.target_count(w.group))
	if targets.is_empty():
		return
	w.cooldown_ready_at = time_ms + e.cooldown(w.group)
	for target in targets:
		_fire_group(e, w.group, target)
	if w.remove_after_use:   # Tyrus' Lord of Souls fires once
		w.used = true


## TBrainWelaSelftargetComponent.ThinksPassively: fires on the owner whenever ready (Frostgoyle Fountain
## spawning a Frostgoyle for 4 souls every 3 s). TWelaReadyCooldownComponent(false) starts on cooldown.
func _think_self_passive(e: SimEntity, w: Wela) -> void:
	if w.next_at < 0:
		w.next_at = e.created_at if w.ready_at_start else e.created_at + e.cooldown(w.group)
	if time_ms < w.next_at or not _wela_ready(e, w):
		return
	w.next_at = time_ms + e.cooldown(w.group)
	_fire_group(e, w.group, e)


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
	var max_links := e.bb.get_int("eiWelaTargetCount", w.group, 1)
	var links := _link_count(e, w)
	if w.link_pay_cost and links > 0:   # TWelaEffectLinkPayCostMyselfComponentServer: 1 energy per second of uptime
		if time_ms >= w.link_paid_until:
			if e.mana < w.mana_cost:
				for other: SimEntity in entities.values():
					_break_link_key(other, key)
				return
			e.mana -= w.mana_cost
			w.link_paid_until = time_ms + 1000
	if w.link_pay_cost and links == 0 and e.mana < w.mana_cost:
		return
	if not _wela_ready(e, w):   # TBrainWelaLinkComponent: an unready weapon breaks all its links
		if links > 0:
			for other: SimEntity in entities.values():
				_break_link_key(other, key)
		return
	if w.next_at > time_ms and links == 0:
		return   # LinkTime: re-acquire cadence
	var candidates: Array = [e] if w.target_self else entities.values()
	for other: SimEntity in candidates:
		var linked: bool = other.link_buffs.has(key)
		var allies := w.target_allies or not w.team_constraint_set   # auras link allies unless told otherwise
		var in_range := other.alive and (w.target_self or ((other.team == e.team) == allies and other.team != 0 and other != e \
			and other.position.distance_to(e.position) - other.collision_radius <= range and _in_cone(e, w, other)))
		var validator: Wela = e.wela(w.validate_group) if w.validate_group >= 0 else null
		if linked and (not in_range or (validator != null and not validator.target_allowed(other, e))):
			_break_link_key(other, key)
		elif not linked and in_range and links < max_links and other.is_targetable() and w.target_allowed(other, e):
			if w.link_pay_cost and links == 0:   # the first link costs one energy at once
				e.mana -= w.mana_cost
				w.link_paid_until = time_ms + 1000
			links += 1
			w.next_at = time_ms + w.link_time
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
			b.creator_group = w.link_creator_group
			if UnitDb.has_unit(w.link_pattern):   # a link entity with its own brain (Links/VecraAura.ets, RootlingLink.ets)
				var raw := UnitDb.raw(w.link_pattern)
				b.link_bb = Blackboard.new()
				UnitDb.fill_blackboard(b.link_bb, w.link_pattern, league)
				b.link_welas = Wela.parse(raw.get("components", []), b.link_bb, UnitDb.group_map(raw))
				# TLinkEventRedirecter: empty damage / cooldown / type reads fall back to the owner's link group
				b.link_damage = b.link_bb.get_float("eiWelaDamage", 0, e.bb.get_float("eiWelaDamage", w.group, 0.0))
				var types: Variant = b.link_bb.get_value("eiDamageType", 0, e.bb.get_value("eiDamageType", w.group, []))
				b.link_damage_type = SimConstants.damage_mask(types)
				b.link_leech = b.link_bb.get_float("eiWelaModifier", 1, 0.0)
				b.tick_interval = b.link_bb.get_int("eiCooldown", 0, e.bb.get_int("eiCooldown", w.group, 1000))
				b.next_tick_at = time_ms + b.tick_interval
				for lw in b.link_welas:
					if lw.fires_at_create_group >= 0:   # FiresAtCreate: root once when the beam forms
						_fire_link_group(e, other, b, lw.fires_at_create_group)
			other.link_buffs[key] = b
		elif linked:
			var b: Buff = other.link_buffs[key]
			if b.link_damage > 0.0 and time_ms >= b.next_tick_at:   # TLinkBrainComponent: hurt the target, leech to the owner
				b.next_tick_at += b.tick_interval
				var dealt := deal_damage(other, b.link_damage, b.link_damage_type, e)
				if dealt > 0.0 and b.link_leech > 0.0:
					heal(e, dealt * b.link_leech, SimConstants.DamageType.HOT, e)
				for lw in b.link_welas:
					if lw.group == 0:
						for cg in lw.chain_groups:
							_fire_link_group(e, other, b, cg)
					elif lw.link_brain:   # TLinkBrainComponent([0,1,2]): the other groups fire too (gatling splash)
						_fire_link_group(e, other, b, lw.group)


## TWelaTargetingRadialComponent.Cone: the target is inside when the angle between the world-space cone
## direction and the direction to it, minus the target's angular radius, is within half the opening.
func _in_cone(e: SimEntity, w: Wela, other: SimEntity) -> bool:
	if w.cone_angle <= 0.0:
		return true
	var offset := other.position - e.position
	var dist := offset.length()
	if dist <= 0.0001:
		return true
	return absf(w.cone_dir.angle_to(offset / dist)) - atan(other.collision_radius / dist) <= w.cone_angle / 2.0


func _link_count(e: SimEntity, w: Wela) -> int:
	var key := SimEntity.link_key(e.id, w.group)
	var n := 0
	for other: SimEntity in entities.values():
		if other.alive and other.link_buffs.has(key):
			n += 1
	return n


## A link entity's chained group fired at the linked target: apply script, or splash around the target
## (RedirectToGround) using the link's own values.
func _fire_link_group(owner: SimEntity, target: SimEntity, b: Buff, group: int) -> void:
	var lw: Wela = null
	for x in b.link_welas:
		if x.group == group:
			lw = x
	if lw == null or not target.alive:
		return
	if lw.splash:
		var radius := b.link_bb.get_float("eiWelaAreaOfEffect", group, 0.0)
		var amount := b.link_bb.get_float("eiWelaDamage", group, 0.0)
		var dtype := SimConstants.damage_mask(b.link_bb.get_value("eiDamageType", group, []))
		for other: SimEntity in entities.values():
			if not other.alive or not other.is_targetable() or other.team == 0:
				continue
			if lw.target_allies != (other.team == owner.team) or not lw.target_allowed(other, owner):
				continue
			if other.position.distance_to(target.position) - other.collision_radius <= radius:
				deal_damage(other, amount, dtype, owner)
	elif lw.target_allowed(target, owner):
		if lw.apply_script != "" and Buff.exists(lw.apply_script):
			apply_buff(target, lw.apply_script, {}, owner)


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
	for sg in w.shared_cooldown_groups:   # ForestGuardian: both artillery groups share one cooldown
		var sw := e.wela(sg)
		if sw != null:
			sw.cooldown_ready_at = w.cooldown_ready_at
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
		if e.charges.has(group):
			e.charges[group] = 0 if w.charge_consumes_all else e.charges_of(group) - w.charge_cost
		else:   # the entity-wide charge pool (On the Edge field: 10 enchantments)
			e.ammo = 0 if w.charge_consumes_all else e.ammo - w.charge_cost
	if w.damage_percent_of_max or w.heal_percent_of_max:
		amount *= target.max_health
	for t in w.removes_buff_types_any:   # TWarheadSpottyRemoveBuffComponent.MustHaveAny (Frenzy: strip state effects)
		for b in target.buffs.duplicate():
			if b.has_type(t):
				target.remove_buff(b)
	if not w.remove_beacon_props.is_empty():   # TWelaEffectRemoveBeaconComponent: drop the running Frozen groups
		for b in target.buffs.duplicate():
			if _has_any_in(b.properties + b.late_properties, w.remove_beacon_props):
				target.remove_buff(b)
	var dtype := e.damage_type(group)
	if w.teleport_to_target and target != e:   # PhaseDrone's Teleport Strike: blink to the near side of the target
		var away := (e.position - target.position).normalized()
		if away == Vector2.ZERO:
			away = -e.front
		_teleport(e, target.position + away * (w.teleport_offset + target.collision_radius + e.collision_radius))
		_face(e, target.position)
	if group == e.fire_group or w.kind == Wela.Kind.FIGHT:
		attack_fired.emit(e, target, amount)
	if w.chain_first:
		_fire_chains(e, w, target)
	if group == SimConstants.GROUP_MAINWEAPON:
		for b in e.buffs:   # Frenzy: melee heal per attack
			if b.on_fire_heal > 0.0:
				heal(e, b.on_fire_heal, b.on_fire_heal_type, e)
	if w.projectile_reverse and target != e:   # the projectile starts at the target and flies to the owner
		_launch_projectile(w.projectile, target, e, amount, dtype, group)
	if w.projectile != "" and not w.projectile_reverse:
		_launch_projectile(w.projectile, e, target, amount, dtype, group)
	elif w.changes_max and w.resource == "reHealth":   # eiResourceCapTransaction: raise the cap and fill it
		target.max_health += amount
		target.health += amount
	elif w.resource == "reHealth" and w.resource_sets_value:   # EvolveOracle: health := 60 % of the cap
		target.health = minf(target.max_health, amount * (target.max_health if w.resource_percentage else 1.0))
	elif w.resource == "reHealth" and not w.heals and w.kind != Wela.Kind.RESOURCE_REGEN and w.resource != "":
		target.health = minf(target.max_health, target.health + amount)
	elif w.resource == "reMana" and not w.changes_max and w.kind != Wela.Kind.RESOURCE_REGEN:
		gain_mana(target, int(amount))   # induction energy, ammo transfers
	elif w.resource == "reWelaChargeCapacity":
		var who := e if w.warhead_to_self else target
		who.charge_capacity = mini(who.charge_capacity_cap, who.charge_capacity + int(amount))
	elif w.kills:
		if target.alive and target != e:
			target.exiled = w.exiles
			_kill(target, e)
	elif w.splash:
		_fire_splash(e, group, e.position if w.redirect_to_ground else target.position)
	elif w.heals:
		heal(target, amount, dtype, e)
	elif w.damages:
		deal_damage(target, amount, dtype, e)
	if w.apply_script != "" and target.alive and Buff.exists(w.apply_script):
		_apply_scripted(target, w.apply_script, w.apply_script_values, w.apply_script_same_team, e)
	for item in w.extra_apply_scripts:
		if target.alive and Buff.exists(item[0]):
			_apply_scripted(target, item[0], item[1], item[2], e)
	for ag in w.activates_groups:   # TWelaEffectActivationAbilityComponent.SetsActive
		var aw := e.wela(ag)
		if aw != null:
			aw.active = true
	for rg in w.removes_groups:   # TWelaEffectRemoveAfterUseComponent.TargetGroup: those groups are gone for good
		e.removed_groups[rg] = true
		var rw := e.wela(rg)
		if rw != null:
			rw.used = true
	if w.remove_after_use:
		w.used = true
		e.removed_groups[group] = true
	if w.spawns:   # TWelaEffectFactoryComponent: units appear at the target position
		var pattern: String = e.bb.get_value("eiWelaUnitPattern", group, "").replace("\\", "/")
		if w.resolve_team_id:   # Lanetower death: LaneNode_Red / _Blue block the former owner's recapture
			pattern = str(e.bb.get_value("eiWelaUnitPattern.%d" % e.team, group, pattern)).replace("\\", "/").trim_suffix(".ets")
		var count := e.bb.get_int("eiWelaCount", group, 1)
		if pattern != "" and UnitDb.has_unit(pattern):
			var team := e.team if w.spawn_team < 0 else w.spawn_team
			var produced: Array[SimEntity] = []
			var area := e.bb.get_float("eiWelaAreaOfEffect", group, 0.0)
			if w.spawn_spread and area > 0.0:   # SpreadSpawns with an area: random offset up to the radius
				for i in count:
					var offset := Vector2.RIGHT.rotated(rng.randf() * TAU) * (rng.randf() * area)
					produced.append(spawn(pattern, team, target.position + offset))
			elif w.spawn_spread and count > 1:
				produced = spawn_squad(pattern, team, target.position, count, false)
			else:
				for i in count:
					produced.append(spawn(pattern, team, target.position))
			if w.produced_fire_group >= 0:   # TAutoBrainWelaTargetProducedUnitComponent (EvolveOracle: 60 % hp)
				for unit in produced:
					_fire_group(e, w.produced_fire_group, unit)
			for unit in produced:
				for item in w.produced_scripts:   # ApplyToProducedUnits (LegendarySpawn 660 ms, TimedLife 17 s)
					if Buff.exists(item[0]):
						apply_buff(unit, item[0], _script_params(item[0], item[1]), e)
				if unit.thinks_once and not unit.think_once_waits:   # effect entities act at once (VecraFreeze)
					_think_once(unit)
	if w.charge_gain_group >= 0 and w.kind != Wela.Kind.FIGHT or (w.charge_gain_group >= 0 and w.commander_cast):
		e.charges[w.charge_gain_group] = e.charges_of(w.charge_gain_group) + 1
	for sg in w.instant_target_groups:   # splash warheads around the target position
		_fire_splash(e, sg, target.position)
	for cg in w.companion_groups:   # a brain on several groups fires them all (Oracle [2,3])
		var cw := e.wela(cg)
		if cw != null:
			_fire_group(e, cg, e if cw.warhead_to_self else target)
	if not w.chain_first:
		_fire_chains(e, w, target)
	for rg in w.reset_cooldown_groups:   # TWelaEffectResetCooldownComponent.Expire
		var rw := e.wela(rg)
		if rw != null:
			rw.cooldown_ready_at = time_ms
			if rg == SimConstants.GROUP_MAINWEAPON:
				e.cooldown_ready_at = time_ms
	if w.suicide and e.alive and not _in_think_once:   # TWelaEffectSuicideComponent (DamperDrone's breaching charge)
		if e.is_targetable():
			_kill(e)   # a real unit dies (Sapling timed life)
		else:
			_remove_silently(e)   # a field vanishes (SporeField after 10 s)


## TWelaEffectFireComponent: fire the chained groups at the target (or the owner) when they are ready.
func _fire_chains(e: SimEntity, w: Wela, target: SimEntity) -> void:
	for cg in w.chain_groups:
		var cw := e.wela(cg)
		if cw == null or time_ms < cw.cooldown_ready_at or not _wela_ready(e, cw):
			continue
		var chain_target := e if w.chain_to_self else target
		if chain_target.alive and cw.target_allowed(chain_target, e):
			_fire_group(e, cg, chain_target)


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
		if w.line_width > 0.0:   # LineFromOwner: a segment from the owner along its facing, eiWelaAreaOfEffect long
			var seg_end := e.position + front * radius
			var closest := Geometry2D.get_closest_point_to_segment(other.position, e.position, seg_end)
			if other.position.distance_to(closest) - other.collision_radius > w.line_width / 2.0:
				continue
		elif offset.length() - other.collision_radius > radius:
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
	amount = _on_take_damage(target, amount, damage_type, source)
	for b in target.buffs:   # TBuffTakenDamageMultiplierComponent (Spellshield aura)
		if b.taken_damage_mult != 1.0 and (b.taken_damage_types == 0 or damage_type & b.taken_damage_types):
			amount *= b.taken_damage_mult
	var final := SimConstants.apply_armor(amount, target.armor(), damage_type)
	var from_overheal := minf(final, target.overheal)   # THealthComponent.OnDamage: overheal absorbs first
	target.overheal -= from_overheal
	var done := from_overheal + minf(final - from_overheal, target.health)   # damage done is capped at the health left
	target.health -= final - from_overheal
	if done > 0.0 and source != null and source.alive:
		_on_dealt_damage(source, target)
	if target.health <= 0.0:
		_kill(target, source)
	elif done > 0.0:
		_fire_on_hit(target, source, true)
	return done


## TAutoBrainOnDealDamageComponent inside a buff (Grievous Wounds): when ready and the victim passes the
## constraints, apply the script, or refresh its duration and add a stack when it is already there.
func _on_dealt_damage(source: SimEntity, target: SimEntity) -> void:
	for w in source.welas:
		if w.group != source.fire_group or w.on_deal_groups.is_empty():
			continue
		for cg in w.on_deal_groups:
			var cw := source.wela(cg)
			if cw != null and target.alive and cw.target_allowed(target, source):
				_fire_group(source, cg, target)
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
func _on_take_damage(target: SimEntity, amount: float, _damage_type: int, source: SimEntity = null) -> float:
	for w in target.welas:   # CheckSelfForTargetsInGroup + FireTargetsInGroup (VoidSlime passes its status to the attacker)
		if w.kind != Wela.Kind.ON_TAKE_DAMAGE or w.mirror_pairs.is_empty() or time_ms < w.cooldown_ready_at:
			continue
		if source == null or source == target or not source.alive:
			continue
		for pair in w.mirror_pairs:
			var sw := target.wela(pair[0])
			var ew := target.wela(pair[1])
			if sw != null and ew != null and sw.target_allowed(target, target) and ew.target_allowed(source, target):
				w.cooldown_ready_at = time_ms + target.cooldown(w.group)
				_fire_group(target, pair[1], source)
				break
	_fire_on_hit(target, source, false)
	for b in target.buffs.duplicate():   # Shieldblock granted by a buff (Shields Up): one block, then spent
		if b.block_threshold >= 0.0 and amount >= b.block_threshold:
			amount *= b.block_factor
			if b.block_once:
				target.remove_buff(b)
	for w in target.welas:
		if w.kind != Wela.Kind.ON_TAKE_DAMAGE or not w.modifies_amount or w.used or time_ms < w.cooldown_ready_at:
			continue
		if not _wela_ready(target, w):
			continue
		var threshold := target.bb.get_float("eiWelaDamage", w.group, 0.0)
		var passes := amount <= threshold if w.threshold_lesser_equal else amount >= threshold
		if passes:
			amount *= target.bb.get_float("eiWelaModifier", w.group, 1.0)
			target.mana -= w.mana_cost   # Tyrus' Soul Armor pays a soul per blocked hit
			w.cooldown_ready_at = time_ms + target.cooldown(w.group)
	for w in target.welas:   # TBuffTakenDamageMultiplierComponent on a unit group (Vecra's prison, Thistle's evasion)
		if w.used or (_damage_type & w.taken_mult_not_types):
			continue
		if w.taken_mult_types != 0 and not (_damage_type & w.taken_mult_types):
			continue
		if w.taken_mult != 1.0:
			amount *= w.taken_mult
		if w.dodge_chance > 0.0 and rng.randf() < w.dodge_chance:
			amount = 0.0
	return amount


## TAutoBrainOnTakeDamageComponent.FireSelfInGroup: the group fires on the owner when hit, or (with
## TThinkImpulseFireComponent.TargetGroup) its target groups pick a victim (Atlas' Active Armor shoots back,
## PhaseDrone's Shield Overload goes invincible). TriggersAfterDamage groups run once the health dropped.
func _fire_on_hit(target: SimEntity, source: SimEntity, after_damage: bool) -> void:
	for w in target.welas:
		if w.kind != Wela.Kind.ON_TAKE_DAMAGE or not w.fires_on_hit or w.used or w.triggers_after_damage != after_damage:
			continue
		if w.modifies_amount or not w.mirror_pairs.is_empty():
			continue   # Shieldblock / Soul Armor / VoidSlime mirrors are handled in _on_take_damage
		if time_ms < w.cooldown_ready_at or not _wela_ready(target, w):
			continue
		if w.trigger_not_self and (source == null or source == target):
			continue
		if w.passive_if_conscious and not target.can_think(time_ms):
			continue
		w.cooldown_ready_at = time_ms + target.cooldown(w.group)
		if w.chain_groups.is_empty():
			_fire_group(target, w.group, target)
		for cg in w.chain_groups:
			var cw := target.wela(cg)
			if cw == null or not _wela_ready(target, cw):
				continue
			var victim := _pick_target(target, cw, target.range_of(cg))
			if victim != null:
				_fire_group(target, cg, victim)


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
	if e.has("upGadget") and commanders.has(e.team):
		commanders[e.team].gadget_count -= 1
	for other: SimEntity in entities.values():   # break auras this entity provided
		if other.linked_from(e.id):
			_break_link(e, other)
	entity_died.emit(e)
	_release_soul(e)
	if e.has("upNexus") and not finished:
		finished = true
		winner_team = TEAM_BLUE if e.team == TEAM_RED else TEAM_RED
		team_lost.emit(e.team)


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
		if w.kind != Wela.Kind.ON_DEATH or not w.owner_ready(e):
			continue
		if w.spawns and w.projectile == "":   # TWelaEffectFactoryComponent: the field appears at the corpse (Spore)
			_fire_group(e, w.group, e)
			continue
		if w.projectile == "" and not (w.damages or w.heals or w.apply_script != "" or w.splash):
			continue   # FireAtSelf groups carry only client effects
		var count := e.target_count(w.group)
		var candidates: Array[SimEntity] = []
		for other: SimEntity in entities.values():
			if other.alive and other.team != 0 and w.target_allies == (other.team == e.team) and other.is_targetable() \
				and w.target_allowed(other, e) \
				and other.position.distance_to(e.position) - other.collision_radius - e.collision_radius <= e.range_of(w.group):
				candidates.append(other)
		var chosen: Array[SimEntity] = []
		var current: SimEntity = entities.get(e.target_id)
		if w.picks_random_targets:
			for i in count:
				if candidates.is_empty():
					break
				var index := rng.randi_range(0, candidates.size() - 1)
				chosen.append(candidates[index])
				if not w.picks_with_repetition:
					candidates.remove_at(index)
		elif count == 1 and current != null and candidates.has(current):
			chosen.append(current)   # FireAtTarget: the unit's current target when it qualifies
		else:
			candidates.sort_custom(func(a, b): return a.position.distance_squared_to(e.position) < b.position.distance_squared_to(e.position))
			chosen = candidates.slice(0, count)
		for target in chosen:
			if w.projectile != "":
				_launch_projectile(w.projectile, e, target, e.damage(w.group), e.damage_type(w.group), w.group)
			else:
				_fire_group(e, w.group, target)


## Targeting (Server.Welas.pas:1740-1790): efficiency first (missing health for heals), then upLowPrio last,
## then nearest. Allies or enemies per the wela's team constraint.
func _pick_target(e: SimEntity, w: Wela, range: float) -> SimEntity:
	var best: SimEntity = null
	var best_key := INF
	for other: SimEntity in entities.values():
		if not other.alive or other == e or not other.is_targetable():
			continue
		if (not w.target_any_team and w.target_allies != (other.team == e.team)) or other.team == 0:
			continue
		if not w.target_allowed(other, e):
			continue
		var dist := e.position.distance_to(other.position) - other.collision_radius - (0.0 if w.ignore_own_radius else e.collision_radius)
		if dist > range:
			continue
		var key := (rng.randf() * range if w.picks_random_targets else (-dist if w.prioritize_most_distant else dist)) \
			+ (100000.0 if other.has("upLowPrio") else 0.0)
		if (w.prefer_allies and other.team != e.team) or (w.prefer_enemies and other.team == e.team):
			key += 10000000.0
		if w.prioritize_damage_types != 0 and (other.damage_type(SimConstants.GROUP_MAINWEAPON) & w.prioritize_damage_types):
			key -= 1000000.0   # TWelaEfficiencyDamageTypeComponent (Rootdude prefers melee units)
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
	if p.speed_random > 0.0:   # eiSpeed '(3 + random * 3) / 1000' (VoidGatherProjectileTyrus)
		p.speed = (p.speed + rng.randf() * p.speed_random) / 1000.0
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


## TBrainProjectileComponent.OnMoveTargetReached: after the hit, an enemy target with upProjectileReflector
## sends the projectile back to its creator (once, team switched). The reflector link brain
## (Links/ProjectileReflector) fires for non-true, non-reflected shots: the projectile is modified
## (x0.4, dtReflected) and the link owner's creator group fires in the owner (10 true self damage).
func _reflect_projectile(p: Projectile, target: SimEntity) -> bool:
	if p.no_reflection or target.team == p.team or not target.has("upProjectileReflector"):
		return false
	var creator: SimEntity = entities.get(p.source_id)
	if creator == null or not creator.alive:
		return false
	for key in target.link_buffs:
		var b: Buff = target.link_buffs[key]
		if not b.reflects_projectiles or (p.damage_type & b.reflect_not_types):
			continue
		if b.projectile_script != "" and Buff.exists(b.projectile_script):
			var mod := Buff.create(b.projectile_script, time_ms)
			p.damage = mod.modify_damage(p.damage, 0, {})   # the projectile's warhead group
			p.damage_type |= mod.damage_type_add
		var owner: SimEntity = entities.get(b.source_id)
		if b.fire_in_creator and owner != null and owner.alive and b.creator_group >= 0:
			_fire_group(owner, b.creator_group, owner)
	p.no_reflection = true
	p.team = target.team
	p.target_id = creator.id
	p.last_target_position = creator.position
	return true


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
				for item in p.mult_vs_props:   # missiles: x2 against flying / monumental
					if _has_any(target, item[0]) and not (p.damage_type & SimConstants.DamageType.SPELL):
						p.damage *= item[1]
				if p.kills:   # AegisRiftProjectile: annihilate (exile) on impact
					target.exiled = p.exiles
					_kill(target, entities.get(p.source_id))
				elif p.gives_mana:
					gain_mana(target, int(p.damage))
				elif p.raises_max_health:   # Oracle's sapling: +60 max hp and +1 charge
					target.max_health += p.damage
					target.health += p.damage
					target.ammo = mini(target.ammo_cap, target.ammo + p.gives_charges)
				elif p.aoe > 0.0:
					_projectile_splash(p, target)
				elif not p.damages and p.impact_script != "":   # a pure buff carrier (Blessing of Strength)
					if Buff.exists(p.impact_script):
						apply_buff(target, p.impact_script, {}, entities.get(p.source_id))
				else:
					var dealt := deal_damage(target, p.damage, p.damage_type, entities.get(p.source_id))
					if dealt > 0.0 and p.on_hit_script != "" and target.alive and Buff.exists(p.on_hit_script) \
						and not _has_any(target, p.on_hit_must_not_have) and _has_all(target, p.on_hit_must_have):
						apply_buff(target, p.on_hit_script, {}, entities.get(p.source_id))
					if p.bounces_max > 0 and _bounce(p, target, dealt):
						continue
				if _reflect_projectile(p, target):   # ShieldDrone's Reflective Shield: back to the shooter
					continue
			projectiles.erase(id)
			projectile_removed.emit(p, hit)
		else:
			p.position += to_target / dist * walking


## TBrainProjectileComponent.Bounces: blacklist the hit target, deplete, then retarget a random enemy in range.
func _bounce(p: Projectile, hit: SimEntity, dealt: float) -> bool:
	p.hit_ids.append(hit.id)
	p.damage += dealt * p.damage_change_per_hit
	if p.bounce_count >= p.bounces_max or p.damage <= 0.0:
		return false
	var candidates: Array[SimEntity] = []
	for other: SimEntity in entities.values():
		if not other.alive or other.team == p.team or other.team == 0 or not other.is_targetable() or p.hit_ids.has(other.id):
			continue
		if _has_any(other, p.bounce_must_not_have):
			continue
		if other.position.distance_to(hit.position) - other.collision_radius <= p.bounce_range:
			candidates.append(other)
	if candidates.is_empty():
		return false
	p.target_id = candidates[rng.randi_range(0, candidates.size() - 1)].id
	p.bounce_count += 1
	return true


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
		if e.has("upInvisible") or e.has("upBanished"):   # stealthed / banished units don't affect capture points
			continue
		if e.position.distance_to(node.position) - e.collision_radius <= range:
			near_teams[e.team] = true
	if near_teams.size() == 1 and not _node_blocked_for(node, near_teams.keys()[0]):
		node.capturing_team = near_teams.keys()[0]
	elif near_teams.size() > 1:
		node.capturing_team = -1
	if node.capturing_team < 0 or _node_blocked_for(node, node.capturing_team):
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


## TBrainCapturePointComponent.IsBlockedForTeam: group 10 + team exists while its 40 s block runs.
func _node_blocked_for(node: SimEntity, team: int) -> bool:
	var w := node.wela(10 + team)
	return w != null and not w.used


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
	if e.no_pathfinding:
		e.path = []
		return
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
	if e.no_pathfinding:   # TMovementComponent.IdleDirect: straight to the goal, through everything (Brratu)
		var to_goal := goal - e.position
		if to_goal.length() <= walking:
			_face(e, goal)
			_set_position(e, goal)
			_stand(e)
		else:
			var next_pos := e.position + to_goal.normalized() * walking
			_face(e, next_pos)
			_set_position(e, next_pos)
		return
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
