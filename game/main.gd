extends Node3D
## Sandbox: runs the Simulation at a fixed tick on the original map and renders the original unit models.
## Blue (you) plays deck slots with keys 1-9, 0, -, = at the mouse position (drops) or on the next free
## build field (spawners). Red plays a Black deck automatically. Real assets replace the capsules in phase 5.

const HUMAN_DECK := [
	"Units/White/FootmanDrop", "Units/White/ArcherDrop", "Units/White/FootmanSpawner", "Units/White/ArcherSpawner",
	"Units/White/BallistaDrop", "Units/White/PriestDrop", "Units/White/MonkDrop", "Units/White/SuntowerBuilding",
	"Spells/White/LightPulse.sps", "Spells/White/ShieldsUp.sps", "Spells/White/SolarFlare.sps", "Spells/White/HailOfArrows.sps",
]
const AI_DECK := [
	"Units/Black/VoidSkeletonDrop", "Units/Black/VoidBowmanDrop", "Units/Black/VoidSkeletonSpawner", "Units/Black/VoidBowmanSpawner",
	"Units/Black/VoidWormDrop", "Units/Black/VoidBaneDrop", "Units/Black/VoidCauldronDrop", "Units/Black/FrostgoyleFountainBuilding",
	"Units/Black/TyrusDrop", "Spells/Black/Frenzy.sps", "Spells/Black/Freeze.sps", "Spells/Black/ShatterIce.sps",
]
const SLOT_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUAL]

var sim: Simulation
var _accumulator_ms: float = 0.0
var _views: Dictionary = {}   # entity id -> Node3D (UnitModel or placeholder mesh)
var _last_fire: Dictionary = {}   # entity id -> fire_at last seen (attack animation trigger)
var _ready_effects: Dictionary = {}   # entity id -> [[ParticleEffect, wela group]] shown while that wela is ready
var _hud: Hud
var _selection_decal: MeshInstance3D
var _armed_slot: int = -1      # card clicked in the deck panel, played at the next left click on the ground
var _jump_return: Variant = null   # camera look-at to return to after a spawner jump
var _red_next_play_at: int = 15000
var _red_cursor: int = 0
## The sandbox human is team 2 (Red, +x side): the HUD, textures and effects still paint the own team blue
## (GetDisplayedTeam maps own -> 1), exactly like the client did in the owner's screenshots (own base top-right,
## lane leaving bottom-left, hover outline in the real team colour). The AI is team 1 (Blue, -x).
const HUMAN_TEAM := Simulation.TEAM_RED
const AI_TEAM := Simulation.TEAM_BLUE

## The original engine is left-handed (DirectX); Godot is right-handed. `World` is scaled -1 on Z so the
## sim / map coordinates (used verbatim inside it) render as the exact mirror Godot would otherwise show,
## i.e. exactly like the original client (shadow sides, texture details, docs/reference-material.md).
## Everything in global space (camera, mouse rays, HUD projections) converts with z_global = -z_sim.
@onready var _world: Node3D = $World
@onready var _units_root: Node3D = $World/Units
@onready var _camera: Camera3D = $Camera3D
@onready var _environment: WorldEnvironment = $WorldEnvironment
var _map: MapView
var _look_at := Vector2(96, -23)   # ground point the camera looks at (CameraFixedToLane: z = -23); set to the own nexus in _ready like the client
var _zoom := ZOOM_MAX              # TClientCameraComponent.FZoom: distance = zoom * 10 along CAMERAOFFSET
const ZOOM_MIN := 2.6              # coGameplayCameraMinZoom
const ZOOM_MAX := 3.8              # coGameplayCameraMaxZoom (the start zoom, TClientCameraComponent.Create)
const ZOOM_SPEED := 0.2            # ZOOMSPEED per wheel notch
const CAMERA_FOV := 0.6853981635   # coEngineCameraFoV (vertical, radians)
var _drag_anchor: Variant = null    # ground point under the mouse when the right drag started


func _ready() -> void:
	sim = Simulation.new(randi(), 4)
	sim.entity_spawned.connect(_on_spawned)
	sim.entity_died.connect(_on_died)
	sim.projectile_spawned.connect(_on_projectile_spawned)
	sim.projectile_removed.connect(_on_projectile_removed)
	sim.team_lost.connect(func(t): print("team %d lost" % t))
	sim.spawn_bases()
	_map = MapView.new()   # the original map: terrain, water, lights, vegetation, decorations
	_world.add_child(_map)
	_map.load_map(sim.map.name)
	var grid := BuildGrid.new()   # the spawner tiles of both build zones
	_world.add_child(grid)
	grid.setup(sim)
	_environment.environment.ambient_light_color = _map.ambient_color
	_environment.environment.ambient_light_energy = _map.ambient_energy
	# Decks go through the Deck rules (validates them) and its slot sort, like the real card bar.
	sim.commanders[HUMAN_TEAM].set_deck_from(Deck.from_scripts(HUMAN_DECK))
	sim.commanders[AI_TEAM].set_deck_from(Deck.from_scripts(AI_DECK))   # the AI plays Black so both factions show
	_hud = Hud.new()
	$HUD.add_child(_hud)
	_hud.setup(sim, HUMAN_TEAM, _camera)
	_hud.slot_clicked.connect(_on_slot_clicked)
	_hud.spawner_jump.connect(_spawner_jump)
	_hud.match_left.connect(func(): get_tree().reload_current_scene())   # sandbox: Continue restarts the match
	_selection_decal = _make_decal()
	_look_at = sim.map.base_layout(HUMAN_TEAM)["nexus"]
	_place_camera(_look_at)


func _process(delta: float) -> void:
	_accumulator_ms += delta * 1000.0
	while _accumulator_ms >= SimConstants.TICK_MS:
		_accumulator_ms -= SimConstants.TICK_MS
		sim.step()
		_red_ai()
	_sync_views()
	_hud.refresh()
	_sync_selection()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_drag_anchor = _mouse_world_2d() if event.pressed else null
			if event.pressed:
				_armed_slot = -1
		elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _armed_slot >= 0:
				_play(HUMAN_TEAM, _armed_slot, _mouse_world_2d())
				_armed_slot = -1
			else:
				_hud.select(_unit_at(_mouse_world_2d(), true))
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(ZOOM_MIN, _zoom - ZOOM_SPEED)
			_place_camera(_look_at)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(ZOOM_MAX, _zoom + ZOOM_SPEED)
			_place_camera(_look_at)
	elif event is InputEventMouseMotion and _drag_anchor != null:
		var now := _mouse_world_2d()   # keep the grabbed ground point under the cursor
		_place_camera(_look_at + (_drag_anchor - now))
	elif event is InputEventKey and event.is_pressed():
		var pan := Vector2.ZERO
		match event.keycode:
			KEY_LEFT: pan.x = -5.0
			KEY_RIGHT: pan.x = 5.0
			KEY_UP: pan.y = -5.0
			KEY_DOWN: pan.y = 5.0
		if pan != Vector2.ZERO:
			_place_camera(_look_at + pan)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.keycode == KEY_ESCAPE:
		get_tree().quit()
		return
	var slot := SLOT_KEYS.find(event.keycode)
	if slot >= 0 and slot < sim.commanders[HUMAN_TEAM].slots.size():
		_play(HUMAN_TEAM, slot, _mouse_world_2d())


var _pending_slot: int = -1        # multi-point spell (Relocate): press the key once per point
var _pending_points: Array = []


func _play(team: int, slot: int, where: Vector2) -> void:
	var c: Commander = sim.commanders[team]
	var card := c.slots[slot].card
	var target: Variant = where
	if card.is_spawner():
		target = _next_free_field(team)
		if target == null:
			return
	elif card.is_spell():
		if card.target_type == "ctEntity":   # SolarFlare, Frenzy: the unit under the mouse
			var unit := _unit_at(where)
			if unit == null:
				print("play %s: no unit under the mouse" % card.name)
				return
			target = unit.id
		else:
			var count := _spell_point_count(card)
			if count > 1:   # Relocate: A on the first press, B on the second
				if _pending_slot != slot:
					_pending_slot = slot
					_pending_points = []
				_pending_points.append(where)
				if _pending_points.size() < count:
					print("play %s: point %d of %d set" % [card.name, _pending_points.size(), count])
					return
				target = _pending_points
				_pending_slot = -1
	var result := sim.play_card(team, slot, target)
	if result != Simulation.PlayResult.OK:
		print("play %s: %s" % [card.name, Simulation.PlayResult.keys()[result]])


func _spell_point_count(card: Cards.CardDef) -> int:
	return int(UnitDb.raw(card.unit_id)["values"].get("eiAbilityTargetCount", {}).get("SpellGroup", 1))


func _spell_props(card: Cards.CardDef) -> Array:
	return UnitDb.raw(card.unit_id)["values"].get("eiUnitProperties", {}).get("SpellGroup", [])


## Card clicked in the deck panel: spawners go to the next free field at once, everything else waits
## for a left click on the ground.
func _on_slot_clicked(slot: int) -> void:
	var card: Cards.CardDef = sim.commanders[HUMAN_TEAM].slots[slot].card
	if card.is_spawner():
		_play(HUMAN_TEAM, slot, Vector2.ZERO)
	else:
		_armed_slot = slot


## TIngameHUD.SpawnerJump: camera to the own base (nexus + 10.5 towards the lane) and back.
func _spawner_jump() -> void:
	var nexus: SimEntity = sim.entities.get(sim.nexus_ids[HUMAN_TEAM])
	if nexus == null:
		return
	var base := nexus.position + Vector2(signf(nexus.position.x) * 10.5, 0)
	if base.distance_to(_look_at) > 20.0:
		_jump_return = _look_at
		_place_camera(base)
	elif _jump_return != null:
		_place_camera(_jump_return)
		_jump_return = null


func _make_decal() -> MeshInstance3D:
	var decal := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.orientation = PlaneMesh.FACE_Y
	decal.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = HudStyle.tex("HUD/Selection.png")
	decal.material_override = mat
	decal.visible = false
	_world.add_child(decal)
	return decal


func _sync_selection() -> void:
	var e := _hud.selected()
	_selection_decal.visible = e != null
	if e == null:
		return
	var mat: StandardMaterial3D = _selection_decal.material_override
	mat.albedo_texture = HudStyle.tex("HUD/SelectionBuilding.png" if e.is_building() else "HUD/Selection.png")
	var s := e.collision_radius * 3.0
	_selection_decal.scale = Vector3(s, 1, s)
	_selection_decal.position = Vector3(e.position.x, 0.05, e.position.y)


func _unit_at(where: Vector2, include_spawners: bool = false) -> SimEntity:
	var best: SimEntity = null
	var best_dist := INF
	for e in sim.alive_entities():
		if e.is_spawner():
			if not include_spawners:
				continue
		elif not e.is_targetable():
			continue
		var d := e.position.distance_to(where) - e.collision_radius
		if d <= 0.5 and d < best_dist:
			best_dist = d
			best = e
	return best


## Simple opponent: every few seconds play the first ready card: drops near its own lane node, spawners on
## the grid, spells on a random unit of the side the card is for (epics at the own nexus).
func _red_ai() -> void:
	if sim.time_ms < _red_next_play_at:
		return
	_red_next_play_at = sim.time_ms + 6000
	var c: Commander = sim.commanders[AI_TEAM]
	for k in c.slots.size():   # round-robin so spells and buildings get their turn
		var i: int = (_red_cursor + k) % c.slots.size()
		if not c.slots[i].is_ready(sim.time_ms, c):
			continue
		var card := c.slots[i].card
		if not card.is_spell():
			_red_cursor = i + 1
			_play(AI_TEAM, i, Vector2(sim.map.side(AI_TEAM) * (50 + sim.rng.randf() * 10), -23))
			return
		var props := _spell_props(card)
		var team := AI_TEAM if props.has("upSpellAlly") else HUMAN_TEAM
		var units := sim.alive_entities(team).filter(func(e): return e.has("upUnit") and e.is_targetable())
		if units.is_empty():
			continue
		var unit: SimEntity = units[sim.rng.randi_range(0, units.size() - 1)]
		var target: Variant = unit.position
		if card.target_type == "ctEntity":
			target = unit.id
		elif card.epic:
			target = sim.entities[sim.nexus_ids[AI_TEAM]].position + Vector2(-sim.map.side(AI_TEAM) * 8, 0)
		elif _spell_point_count(card) > 1:
			target = [unit.position, unit.position + Vector2(-5, 0)]
		if sim.play_card(AI_TEAM, i, target) == Simulation.PlayResult.OK:
			_red_cursor = i + 1
			return


func _next_free_field(team: int) -> Variant:
	for zone: BuildZone in sim.build_zones.values():
		if zone.team != team:
			continue
		for field in zone.spawn_slots():
			if zone.is_free(field):
				return [zone.id, field]
	return null


func _mouse_world_2d() -> Vector2:
	return _ground_at(get_viewport().get_mouse_position())


func _ground_at(m: Vector2) -> Vector2:   # screen pixel -> sim ground point (y = 0)
	var from := _camera.project_ray_origin(m)
	var dir := _camera.project_ray_normal(m)
	if absf(dir.y) < 0.0001:
		return Vector2.ZERO
	var t := -from.y / dir.y
	var hit := from + dir * t
	return Vector2(hit.x, -hit.z)   # global -> sim (World is mirrored on Z)


func _place_camera(look_at_2d: Vector2) -> void:
	# Original camera offset direction (Constants.Client.pas:34), scaled to see the lane.
	_look_at = look_at_2d
	_camera.fov = rad_to_deg(CAMERA_FOV)
	# CAMERAOFFSET (Constants.Client.pas:34, z sign flipped for Godot) = the live client's camera: rendered sweeps
	# at the reference window size scored by per-block alignment with the game-start screenshot put this vector
	# (pitch 54.3, yaw 47.4, distance 38 at zoom 3.8, original FOV) at ~6 px mean block error, better than any
	# flatter / closer / narrower variant (docs/reference-material.md). Blue sits at +x (SimMap).
	# In global (mirrored) space the original CAMERAOFFSET (-0.3947, 0.8121, -0.4297) becomes +z.
	var offset := Vector3(-0.394721269607544, 0.812130928039551, 0.429695725440979) * _zoom * 10.0
	var target := Vector3(look_at_2d.x, 0, -look_at_2d.y)   # sim -> global
	_camera.position = target + offset
	_camera.look_at(target, Vector3.UP)


func _on_spawned(e: SimEntity) -> void:
	if e.think_once_waits:   # one-tick helper entities (soul gather spawner) have no body
		return
	if e.is_lane_node():   # no mesh: the capture circle (TTextureRangeIndicatorComponent) and particle rings
		var holder := Node3D.new()
		holder.position = Vector3(e.position.x, 0.0, e.position.y)
		var range := e.bb.get_float("eiWelaRange", 1, 16.5)
		holder.add_child(RangeCircle.create(range, 0.5, [[0.57, 0.93], [0.07, 0.43]], "RangeLine.tga"))
		_units_root.add_child(holder)
		_views[e.id] = holder
		_spawn_effects(e, "create", holder)
		return
	var model := UnitModel.create(e.unit_id, HudStyle.displayed_team(e.team, HUMAN_TEAM))
	if model != null:
		_units_root.add_child(model)
		_views[e.id] = model
		_spawn_effects(e, "create", model)
		return
	if e.is_spell_effect() or not e.is_targetable():   # spell effects, fields: only their particle effects
		var holder := Node3D.new()
		holder.position = Vector3(e.position.x, 0.0, e.position.y)
		_units_root.add_child(holder)
		_views[e.id] = holder
		_spawn_effects(e, "create", holder)
		return
	var mesh := MeshInstance3D.new()
	if e.is_spawner():
		var box := BoxMesh.new()
		box.size = Vector3(1.6, 0.4, 1.6)
		mesh.mesh = box
	elif e.is_building():
		var box := BoxMesh.new()
		box.size = Vector3(e.collision_radius * 2, 4, e.collision_radius * 2)
		mesh.mesh = box
	else:
		var cap := CapsuleMesh.new()
		cap.radius = e.collision_radius
		cap.height = 1.8
		mesh.mesh = cap
	var mat := StandardMaterial3D.new()
	match HudStyle.displayed_team(e.team, HUMAN_TEAM):
		2: mat.albedo_color = Color(0.9, 0.25, 0.2)   # displayed team: enemy red
		1: mat.albedo_color = Color(0.2, 0.4, 0.95)   # displayed team: own blue
		_: mat.albedo_color = Color(0.6, 0.6, 0.6)
	mesh.material_override = mat
	_units_root.add_child(mesh)
	_views[e.id] = mesh


func _on_projectile_spawned(p: Projectile) -> void:
	var model := UnitModel.create(p.unit_id, HudStyle.displayed_team(p.team, HUMAN_TEAM))   # arrows, missiles ...
	if model != null:
		model.position = Vector3(p.position.x, 1.2, p.position.y)
		_units_root.add_child(model)
		_views[p.id] = model
		return
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.3)
	mesh.material_override = mat
	_units_root.add_child(mesh)
	_views[p.id] = mesh


func _on_died(e) -> void:
	var view: Node3D = _views.get(e.id)
	if view:
		if e is SimEntity:
			_spawn_effects(e, "die", null)
			_spawn_effects(e, "free", null)
		view.queue_free()
		_views.erase(e.id)
		_last_fire.erase(e.id)
		_ready_effects.erase(e.id)


func _on_projectile_removed(p: Projectile, _hit: bool) -> void:
	_spawn_effects(p, "firewarhead", null)
	_spawn_effects(p, "die", null)
	_spawn_effects(p, "free", null)
	_on_died(p)


## TParticleEffectComponent: plays the script's effects for an activation ("create", "fire", "die", ...).
## Attached effects follow the parent view; one-shot effects are placed at the entity's position.
func _spawn_effects(e, activation: String, parent: Node3D) -> void:
	if not UnitDb.has_unit(e.unit_id):
		return
	for effect in UnitDb.raw(e.unit_id).get("effects", []):
		if not effect.get("activate", []).has(activation):
			continue
		if effect.get("at_fire_target", false):
			continue   # needs target tracking (later)
		var path: String = effect["path"]
		if path.contains("%d"):
			path = path % HudStyle.displayed_team(e.team, HUMAN_TEAM)
		var groups: Array = effect.get("groups", [])
		var group := int(groups[0]) if not groups.is_empty() else 0
		var scale := 1.0
		match str(effect.get("scale_with", "")):
			"eiCollisionRadius": scale = e.collision_radius if e is SimEntity else 0.5
			"eiWelaRange": scale = e.range_of(group) if e is SimEntity else 1.0
			"eiWelaAreaOfEffect": scale = float(e.bb.get_value("eiWelaAreaOfEffect", group, 1.0)) if e is SimEntity else 1.0
		var model_size := 1.0
		var sizes: Dictionary = UnitDb.raw(e.unit_id).get("visuals", {}).get("model_sizes", {})
		for g in groups:
			if sizes.has(str(g)):
				model_size = sizes[str(g)]
				break
		var size := scale * (1.0 if effect.get("ignore_model_size", false) else model_size) / float(effect.get("size_normalization", 1.0))
		var fx := ParticleEffect.create(path, size)
		if fx == null:
			continue
		var offset := Vector3.ZERO
		if effect.has("model_offset"):
			var o: Array = effect["model_offset"]
			offset = Vector3(o[0], o[1], o[2]) * model_size
		if parent != null:
			var anchor := parent
			if parent is UnitModel and effect.has("bind_zone"):   # BindToSubPositionGroup: follow the zone's bone
				var attachment: Node3D = parent.bone_attachment(str(effect["bind_zone"]))
				if attachment != null:
					anchor = attachment
			anchor.add_child(fx)
			fx.position = offset
			if effect.get("visible_with_wela_ready", false) and e is SimEntity:
				_ready_effects.get_or_add(e.id, []).append([fx, group])
		else:
			_units_root.add_child(fx)
			fx.position = Vector3(e.position.x, 0.0, e.position.y) + offset


func _sync_views() -> void:
	for id in _views:
		var view: Node3D = _views[id]
		var p: Projectile = sim.projectiles.get(id)
		if p != null:
			var flight := Vector3(p.position.x, 1.2, p.position.y) - view.position   # face the flight direction
			view.position = Vector3(p.position.x, 1.2, p.position.y)
			if view is UnitModel and flight.length_squared() > 0.0001:
				view.rotation.y = atan2(flight.x, flight.z)
			continue
		var e: SimEntity = sim.entities.get(id)
		if e == null:
			continue
		if e.is_lane_node():   # ShowTeamColor: GetTeamColor(Owner.TeamID), neutral grey until a tower replaces it
			for child in view.get_children():
				if child is RangeCircle:
					child.set_color(HudStyle.team_color(e.team, HUMAN_TEAM))
			continue
		if view is UnitModel:
			view.position = Vector3(e.position.x, 0.0, e.position.y)
			view.set_moving(e.moving)
			for pair in _ready_effects.get(id, []):   # VisibleWithWelaReady
				var w := e.wela(pair[1])
				pair[0].visible = w != null and sim._wela_ready(e, w)
			if e.fire_at >= 0 and _last_fire.get(id, -1) != e.fire_at:   # a new attack started
				_last_fire[id] = e.fire_at
				view.play_attack()
				_spawn_effects(e, "fire", view)
				_spawn_effects(e, "prefire", view)
		else:
			var y := 0.2 if e.is_spawner() else (2.0 if e.is_building() else 0.9)
			view.position = Vector3(e.position.x, y, e.position.y)
		if e.front.length_squared() > 0.0:
			if view is UnitModel:   # the models face their local +Z
				view.rotation.y = atan2(e.front.x, e.front.y)
			else:
				view.rotation.y = atan2(-e.front.y, e.front.x) + PI / 2
