extends Node3D
## Sandbox: runs the Simulation at a fixed tick on the original map and renders the original unit models.
## Blue (you) plays deck slots with keys 1-9, 0, -, = at the mouse position (drops) or on the next free
## build field (spawners). Red plays a Black deck automatically. Real assets replace the capsules in phase 5.

signal match_left   # the final screen's Continue: the client state machine returns to the main menu

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
var _prev_pos: Dictionary = {}   # entity id -> Vector2 position before the last sim step (render interpolation)
var _last_fire: Dictionary = {}   # entity id -> fire_at last seen (attack animation trigger)
var _ready_effects: Dictionary = {}   # entity id -> [[ParticleEffect, wela group]] shown while that wela is ready
var _buff_fx: Dictionary = {}         # entity id -> {Buff: [ParticleEffect]} attached while the buff lasts
var _hud: Hud
var _menu: IngameMenu = null          # hud.IsMenuOpen
var _settings: SettingsMenu = null    # diSettings
var _exit_dialog: ExitDialog = null   # ExitDialog.dui
var _selection_decal: MeshInstance3D
var _armed_slot: int = -1      # armed card (TClientInputComponent.FPreparedSpell): key/click arms, ground click plays
var _prev_front := {}                   # entity id -> front before the last sim step (turn interpolation)
var _preview_root: Node3D = null       # ghost unit models while a card is armed (TProductionPreviewComponent)
var _reticle: MeshInstance3D = null    # ground target decal (TSpelltargetVisualizerShowTextureComponent)
var _armed_cell: Variant = null        # [zone_id, Vector2i] under the cursor while a spawner card is armed
var _zone_overlay: DropZoneOverlay = null   # TZoneRenderer: drop area while a drop / epic card is armed
var _grid: BuildGrid = null                 # the spawner tiles (occupation tints while armed)
var _hovered_id: int = -1                   # unit under the cursor (eiDrawOutline each frame)
var _view_y: Dictionary = {}                # entity id -> model height offset (TPositionerOffsetComponent)
var _jump_return: Variant = null   # camera look-at to return to after a spawner jump
var _red_next_play_at: int = 15000
var _red_cursor: int = 0
## The sandbox human is team 2 (Red, +x side): the HUD, textures and effects still paint the own team blue
## (GetDisplayedTeam maps own -> 1) like the original client: own base top-right, lane leaving bottom-left,
## hover outline in the real team colour. The AI is team 1 (Blue, -x).
## The 2022 sandbox (CreateTestserverGameInfo / the sandbox branch, BaseConflict.Game.Server.pas:379-393) inserts the
## team-2 commander at slot 0 and then the team-1 commander at slot 0: the local player is team 1 (Blue at -x).
const HUMAN_TEAM := Simulation.TEAM_BLUE
const AI_TEAM := Simulation.TEAM_RED

## The original engine is left-handed (DirectX); Godot is right-handed. `World` is scaled -1 on Z so the
## sim / map coordinates (used verbatim inside it) render as the exact mirror Godot would otherwise show,
## i.e. exactly like the original client (shadow sides, texture details match reference/rolmedia).
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
const OUTLINE_SHADER: Shader = preload("res://game/effects/outline.gdshader")
## BORDER_TEAMCOLORS (Visuals.pas:3053): outline by the real team id (NPC grey, team 1 blue, team 2 red).
const BORDER_TEAM_COLORS := [Color("404040"), Color("0036FF"), Color("FF1818")]
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
	_grid = BuildGrid.new()   # the spawner tiles of both build zones
	_world.add_child(_grid)
	_grid.setup(sim)
	_zone_overlay = DropZoneOverlay.new()
	add_child(_zone_overlay)
	_zone_overlay.setup(sim.map.name, _camera)
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
	_hud.minimap.move_to.connect(func(world: Vector2): _place_camera(world))   # eiMiniMapMoveToEvent -> CameraMoveTo(pos, 0)
	_hud.unit_bars.position_of = view_position
	_hud.match_left.connect(_on_match_left)
	_hud.minimap.menu_pressed.connect(_toggle_menu)
	_selection_decal = _make_decal()
	_look_at = sim.map.base_layout(HUMAN_TEAM)["nexus"]
	_place_camera(_look_at)


## Escape / the minimap's menu button: hud.IsMenuOpen toggles the game menu (HUD/Menu.dui).
func _toggle_menu() -> void:
	if _menu != null:
		_menu.close()
		return
	_menu = IngameMenu.new()
	_menu.closed.connect(func(): _menu = null)
	_menu.settings_requested.connect(_open_settings)
	_menu.surrender_requested.connect(func(): sim.surrender(HUMAN_TEAM))
	_menu.exit_requested.connect(_open_exit_dialog)
	$HUD.add_child(_menu)


## dialogs.OpenDialog(diSettings) over the game menu (the original nests it, $zoffset-nested-dialog).
func _open_settings() -> void:
	if _settings != null:
		return
	_settings = SettingsMenu.new()
	_settings.in_game = true
	_settings.closed.connect(func(): _settings = null)
	$HUD.add_child(_settings)


## The game menu's Quit (client.CloseForcePrompt): the exit dialog over the menu.
func _open_exit_dialog() -> void:
	if _exit_dialog != null:
		return
	_exit_dialog = ExitDialog.new()
	_exit_dialog.closed.connect(func(): _exit_dialog = null)
	$HUD.add_child(_exit_dialog)


## The final screen's Continue (or its timeout): TGameStateCoreGame.EnterMainMenu hands over to the client state
## machine (app.gd); run stand-alone (no listener) the sandbox simply restarts the match.
func _on_match_left() -> void:
	if match_left.get_connections().is_empty():
		get_tree().reload_current_scene()
	else:
		match_left.emit()


func _process(delta: float) -> void:
	_accumulator_ms += delta * 1000.0
	while _accumulator_ms >= SimConstants.TICK_MS:
		_accumulator_ms -= SimConstants.TICK_MS
		_capture_prev()
		sim.step()
		_red_ai()
	_sync_views()
	_hud.refresh()
	_sync_selection()
	_update_preview()
	_update_zone_display()
	_update_hover()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_drag_anchor = _mouse_world_2d() if event.pressed else null
			if event.pressed:
				_disarm()   # kbSecondaryAction: right click cancels the armed card
		elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _armed_slot >= 0:
				_confirm_armed()
			else:
				_hud.select(_unit_at(_mouse_world_2d(), true))
		elif event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
			_spawner_jump()   # coKeybindingBindingNexusJumpAlt = mbMiddle (Settings.Client.pas:664)
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
	if event.keycode == KEY_SPACE and _menu == null or (event.keycode == KEY_SPACE and not _menu.visible):
		_spawner_jump()   # kbNexusJump: Space (Settings.Client.pas:663) -> HUD.SpawnerJump
		return
	if event.keycode == KEY_ESCAPE:
		if _exit_dialog != null:
			_exit_dialog.close()
		elif _settings != null:
			_settings.discard()
		elif _armed_slot >= 0:   # kbMainCancel: Escape unarms the card before it opens the menu
			_disarm()
		else:
			_toggle_menu()
		return
	if _menu != null or _settings != null or _exit_dialog != null:
		return
	var slot := SLOT_KEYS.find(event.keycode)
	if slot >= 0 and slot < sim.commanders[HUMAN_TEAM].slots.size():
		_arm(slot)


var _pending_slot: int = -1        # multi-point spell (Relocate): press the key once per point
var _pending_points: Array = []


func _play(team: int, slot: int, where: Vector2, spawner_cell: Variant = null) -> int:
	var c: Commander = sim.commanders[team]
	var card := c.slots[slot].card
	var target: Variant = where
	if card.is_spawner():
		target = spawner_cell if spawner_cell != null else _next_free_field(team)
		if target == null:
			return Simulation.PlayResult.BAD_TARGET
	elif card.is_spell():
		if card.target_type == "ctEntity":   # SolarFlare, Frenzy: the unit under the mouse
			var unit := _unit_at(where)
			if unit == null:
				print("play %s: no unit under the mouse" % card.name)
				return Simulation.PlayResult.BAD_TARGET
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
					return Simulation.PlayResult.OK
				target = _pending_points
				_pending_slot = -1
	var result := sim.play_card(team, slot, target)
	if result != Simulation.PlayResult.OK:
		print("play %s: %s" % [card.name, Simulation.PlayResult.keys()[result]])
	return result


func _spell_point_count(card: Cards.CardDef) -> int:
	return int(UnitDb.raw(card.unit_id)["values"].get("eiAbilityTargetCount", {}).get("SpellGroup", 1))


func _spell_props(card: Cards.CardDef) -> Array:
	return UnitDb.raw(card.unit_id)["values"].get("eiUnitProperties", {}).get("SpellGroup", [])


func _on_slot_clicked(slot: int) -> void:
	_arm(slot)


# ---------------------------------------------------------------- card arming (TClientInputComponent.PrepareAction)

## Arm a deck slot: ghost preview at the cursor (TProductionPreviewComponent) + ground reticle; a left
## click plays the card, right click / Escape cancels, an invalid click keeps the card armed.
func _arm(slot: int) -> void:
	_disarm()
	_armed_slot = slot
	var card: Cards.CardDef = sim.commanders[HUMAN_TEAM].slots[slot].card
	_reticle = _make_decal()
	_reticle.visible = true
	var s := 3.0
	_reticle.scale = Vector3(s, 1, s)
	_preview_root = Node3D.new()
	_world.add_child(_preview_root)
	if not card.is_spell():
		var unit_data := UnitDb.raw(card.unit_id)
		var ghost_ids: Array = []
		if card.is_spawner():
			ghost_ids = [card.unit_id]
		else:
			var pattern: String = str(unit_data["values"].get("eiWelaUnitPattern", {}).get("0", "")).replace("\\", "/")
			var count := 1 if card.is_building() else int(unit_data["values"].get("eiWelaCount", {}).get("0", 1))
			for i in count:
				ghost_ids.append(pattern)
		for i in ghost_ids.size():
			var ghost := UnitModel.create(ghost_ids[i], HudStyle.displayed_team(HUMAN_TEAM, HUMAN_TEAM))
			if ghost == null:
				continue
			for mi: MeshInstance3D in ghost.find_children("*", "MeshInstance3D", true, false):
				mi.transparency = 0.55   # the original tints previews via ColorAdjustment; translucent ghosts here
			_preview_root.add_child(ghost)
	_update_preview()


func _disarm() -> void:
	_armed_slot = -1
	_armed_cell = null
	if _preview_root != null:
		_preview_root.queue_free()
		_preview_root = null
	if _reticle != null:
		_reticle.queue_free()
		_reticle = null


## Every frame while armed: place the ghosts/reticle at the cursor and colour by validity.
func _update_preview() -> void:
	if _armed_slot < 0 or _reticle == null:
		return
	var card: Cards.CardDef = sim.commanders[HUMAN_TEAM].slots[_armed_slot].card
	var where := _mouse_world_2d()
	var valid := false
	var at := where
	_armed_cell = null
	if card.is_spawner():
		for zone_id in sim.build_zones:
			var zone: BuildZone = sim.build_zones[zone_id]
			if zone.team != HUMAN_TEAM:
				continue
			var coord := zone.position_to_coord(where)
			if zone.in_range(coord) and zone.is_free(coord):
				_armed_cell = [zone_id, coord]
				at = zone.center_of_field(coord)
				valid = true
				break
	elif card.is_spell():
		if card.target_type == "ctEntity":
			var unit := _unit_at(where)
			valid = unit != null
			if unit != null:
				at = unit.position
		elif card.epic:
			valid = sim._in_nexus_zone(HUMAN_TEAM, where)
		else:
			valid = sim.map.in_zone_padded("Walkzone", where, 0.0)
	else:
		valid = sim._in_drop_zone(HUMAN_TEAM, where)
	var tex := "Spelltarget/SpelltargetEntity%s.png" if card.is_spell() and card.target_type == "ctEntity" \
		else "Spelltarget/SpelltargetGround%s.png"
	var mat: StandardMaterial3D = _reticle.material_override
	mat.albedo_texture = HudStyle.tex(tex % ("" if valid else "Invalid"))
	_reticle.position = Vector3(at.x, 0.06, at.y)
	if _preview_root != null:
		var front: Vector2 = (sim.entities[sim.nexus_ids[AI_TEAM]].position - at).normalized()
		var ghosts := _preview_root.get_children()
		for i in ghosts.size():
			var p := Simulation.spawning_pattern(at, front, card.is_spawner(), i, ghosts.size())
			ghosts[i].position = Vector3(p.x, 0.0, p.y)
			ghosts[i].rotation.y = atan2(front.x, front.y)


## Left click while armed: play the card; BAD_TARGET keeps it armed (PlayCardError), OK unarms
## (multi-point spells stay armed until the last point is set).
func _confirm_armed() -> void:
	var slot := _armed_slot
	var card: Cards.CardDef = sim.commanders[HUMAN_TEAM].slots[slot].card
	var target := _mouse_world_2d()
	var result: int
	if card.is_spawner():
		if _armed_cell == null:
			return   # no free field under the cursor: stays armed
		result = _play(HUMAN_TEAM, slot, target, _armed_cell)
	else:
		result = _play(HUMAN_TEAM, slot, target)
	if result == Simulation.PlayResult.OK and _pending_slot != slot:
		_disarm()


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
	# CAMERAOFFSET (BaseConflict.Constants.Client.pas:34), CameraDirection = zoom * CAMERAOFFSET.Normalize * 10
	# (EntityComponents.Client.pas:2078), zoom 2.6..3.8 (Settings.Client.pas:576-577), FoV 0.6854 rad (:512).
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
		if e.is_spawner():
			_view_y[e.id] = 0.2   # Modifiers/Spawner.dws: TPositionerOffsetComponent.Offset(0, 0.2, 0)
		model.position = Vector3(e.position.x, _view_y.get(e.id, 0.0), e.position.y)
		model.rotation.y = atan2(e.front.x, e.front.y)
		_units_root.add_child(model)
		_views[e.id] = model
		_attach_vertex_visuals(e, model)
		_spawn_effects(e, "create", model)
		if e.card_drop:
			_play_drop(e, model)
		if e.spawner_placed:
			_play_spawner_place(e, model)
		return
	if e.is_spell_effect() or not e.is_targetable() or _has_vertex_visuals(e):   # spell effects, fields, quad sprites
		var holder := Node3D.new()
		holder.position = Vector3(e.position.x, 0.0, e.position.y)
		holder.rotation.y = atan2(e.front.x, e.front.y)
		_units_root.add_child(holder)
		_views[e.id] = holder
		_attach_vertex_visuals(e, holder)
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
		_attach_vertex_visuals(p, model)
		_spawn_effects(p, "create", model)
		return
	if UnitDb.has_unit(p.unit_id) and (not UnitDb.raw(p.unit_id).get("effects", []).is_empty() or _has_vertex_visuals(p)):
		var holder := Node3D.new()   # effect-only projectiles (magic shots, sprites, trails): no mesh
		holder.position = Vector3(p.position.x, 1.2, p.position.y)
		_units_root.add_child(holder)
		_views[p.id] = holder
		_attach_vertex_visuals(p, holder)
		_spawn_effects(p, "create", holder)
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


## A buff's client effects (modifiers.json `effects`) follow the unit while the buff is active: attach the
## "now"/"create"-activated ones when the buff appears, free them when it is gone (Shieldblock ring, Frenzy...).
func _sync_buff_effects(e: SimEntity, view: UnitModel) -> void:
	var cur: Dictionary = _buff_fx.get_or_add(e.id, {})
	for b in cur.keys():
		if not e.buffs.has(b):
			for fx in cur[b]:
				if is_instance_valid(fx):
					fx.queue_free()
			cur.erase(b)
	for b in e.buffs:
		if cur.has(b):
			continue
		var list := []
		for effect in Buff.effects(b.name):
			var activate: Array = effect.get("activate", [])
			if not (activate.has("now") or activate.has("create")):
				continue   # "fire" effects (shield_block_trigger) need a block trigger; not wired yet
			var scale := 1.0
			if str(effect.get("scale_with", "")) == "eiCollisionRadius":
				scale = e.collision_radius
			var size := scale / float(effect.get("size_normalization", 1.0))
			var fx := ParticleEffect.create(effect["path"], size)
			if fx == null:
				continue
			var anchor: Node3D = view
			if effect.has("bind_zone"):
				var attachment := view.bone_attachment(str(effect["bind_zone"]))
				if attachment != null:
					anchor = attachment
			anchor.add_child(fx)
			list.append(fx)
		cur[b] = list


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
		_buff_fx.erase(e.id)
		_view_y.erase(e.id)
		if _hovered_id == e.id:
			_hovered_id = -1


func _on_projectile_removed(p: Projectile, _hit: bool) -> void:
	_spawn_effects(p, "firewarhead", null)
	_spawn_effects(p, "die", null)
	_spawn_effects(p, "free", null)
	_on_died(p)


## TParticleEffectComponent: plays the script's effects for an activation ("create", "fire", "die", ...).
## Attached effects follow the parent view; one-shot effects are placed at the entity's position.
func _has_vertex_visuals(e) -> bool:
	if not UnitDb.has_unit(e.unit_id):
		return false
	var raw := UnitDb.raw(e.unit_id)
	return not raw.get("quads", []).is_empty() or not raw.get("traces", []).is_empty()


## TVertexQuadComponent / TVertexTraceComponent of the script (units.json `quads` / `traces`): sprites and
## ribbons on the view. Quads scale with the group's eiModelSize (FModelsize); traces track from creation
## unless they activate on fire / prefire.
func _attach_vertex_visuals(e, view: Node3D) -> void:
	if not UnitDb.has_unit(e.unit_id):
		return
	var raw := UnitDb.raw(e.unit_id)
	var sizes: Dictionary = raw.get("visuals", {}).get("model_sizes", {})
	for quad in raw.get("quads", []):
		var model_size := float(sizes.get("*", 1.0))
		for g in quad.get("groups", []):
			if sizes.has(str(g)):
				model_size = float(sizes[str(g)])
				break
		var node := VertexQuad.create(quad, model_size)
		if node != null:
			view.add_child(node)
	for trace in raw.get("traces", []):
		var node := VertexTrace.create(trace)
		node.set_meta("activate", trace.get("activate", "create"))
		view.add_child(node)
		if not trace.has("activate"):   # OnAfterCreate: Activate unless ActivateOnFire
			node.activate()


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
		var fx := _attach_effect(e, effect, path, parent)
		if fx != null and effect.get("visible_with_wela_ready", false) and e is SimEntity:
			var groups: Array = effect.get("groups", [])
			_ready_effects.get_or_add(e.id, []).append([fx, int(groups[0]) if not groups.is_empty() else 0])


## TParticleEffectComponent sizing + binding: size = scale source x model size / SizeNormalization (gameplay
## scale events skip the model size), attached to the bind zone's bone or placed at the entity on the ground.
func _attach_effect(e, effect: Dictionary, path: String, parent: Node3D) -> ParticleEffect:
	var groups: Array = effect.get("groups", [])
	var group := int(groups[0]) if not groups.is_empty() else 0
	var scale := 1.0
	var gameplay_scale := false   # eiWelaRange/eiWelaAreaOfEffect skip model size (GAMEPLAY_SCALE_EVENTS)
	match str(effect.get("scale_with", "")):
		"eiCollisionRadius": scale = e.collision_radius if e is SimEntity else 0.5
		"eiWelaRange":
			scale = e.range_of(group) if e is SimEntity else 1.0
			gameplay_scale = true
		"eiWelaAreaOfEffect":
			scale = float(e.bb.get_value("eiWelaAreaOfEffect", group, 1.0)) if e is SimEntity else 1.0
			gameplay_scale = true
	if effect.has("scale_range"):   # .ScaleRange(min, max)
		scale = clampf(scale, float(effect["scale_range"][0]), float(effect["scale_range"][1]))
	var model_size := 1.0
	var sizes: Dictionary = UnitDb.raw(e.unit_id).get("visuals", {}).get("model_sizes", {})
	for g in groups:
		if sizes.has(str(g)):
			model_size = sizes[str(g)]
			break
	var size := scale * (1.0 if gameplay_scale or effect.get("ignore_model_size", false) else model_size) / float(effect.get("size_normalization", 1.0))
	var fx := ParticleEffect.create(path, size)
	if fx == null:
		return null
	var offset := Vector3.ZERO
	if effect.has("model_offset"):
		var o: Array = effect["model_offset"]
		offset = Vector3(o[0], o[1], o[2]) * model_size
	if parent != null and not effect.get("fixed_height_ground", false):
		var anchor := parent
		if parent is UnitModel and effect.has("bind_zone"):   # BindToSubPositionGroup: follow the zone's bone
			var attachment: Node3D = parent.bone_attachment(str(effect["bind_zone"]))
			if attachment != null:
				anchor = attachment
		anchor.add_child(fx)
		fx.position = offset
	else:
		_units_root.add_child(fx)
		fx.position = Vector3(e.position.x, 0.0, e.position.y) + offset
	return fx


## Modifiers/Drop.dws (applied to every unit a drop / building card produces): the faction's drop_<color>.pfx
## plus TMeshEffectSpawn on the model.
func _play_drop(e: SimEntity, model: UnitModel) -> void:
	var color := str(e.bb.get_value("eiColorIdentity", 0, "ecWhite"))
	var folder: String = {"ecGreen": "/Green/", "ecBlack": "/Black/", "ecBlue": "/Blue/", "ecColorless": "/Colorless/"}.get(color, "/White/")
	for effect in Buff.effects("Drop"):
		if str(effect["path"]).begins_with(folder):
			_attach_effect(e, effect, effect["path"], model)
			break
	SpawnMeshEffect.apply(model, color)


## Modifiers/Spawner.dws (ApplyToSelfAtCreate): the spawner slams in - TAnimatorComponent scales Y 3 -> 0.3 -> 1
## and drops from 3 to 0 over 0/160/300 ms, SpawnerImpact.pfx (2.4) after 160 ms.
func _play_spawner_place(e: SimEntity, model: UnitModel) -> void:
	var base_y: float = _view_y.get(e.id, 0.0)
	var tween := model.create_tween()
	tween.set_parallel(true)
	model.scale.y = 3.0
	_view_y[e.id] = base_y + 3.0
	tween.tween_property(model, "scale:y", 0.3, 0.16)
	tween.tween_method(func(y: float): _view_y[e.id] = base_y + y, 3.0, 0.0, 0.16)
	tween.chain().tween_property(model, "scale:y", 1.0, 0.14)
	for effect in Buff.effects("Spawner"):
		var delay := float(effect.get("delay", 0.0))
		if delay > 0.0:
			get_tree().create_timer(delay / 1000.0).timeout.connect(func():
				if is_instance_valid(model):
					_attach_effect(e, effect, effect["path"], null))
		else:
			_attach_effect(e, effect, effect["path"], null)


# ---------------------------------------------------------------- zone display + hover outline (TClientInputComponent.Idle)

## TZoneRenderer visible while a drop card or an epic spell is armed; the build grid tints red then
## (ShowInvalid), or green/red by occupation while a spawner card is armed (ShowOccupation).
func _update_zone_display() -> void:
	var card: Cards.CardDef = sim.commanders[HUMAN_TEAM].slots[_armed_slot].card if _armed_slot >= 0 else null
	var show_zone := card != null and not card.is_spawner() and (not card.is_spell() or card.epic)
	_zone_overlay.set_shown(show_zone)
	if show_zone:
		_grid.show_invalid()
		var circles: Array = []   # eiDrawSpawnZone: own nexus (dzDrop + dzNexus) and lanetowers (dzDrop), range group 3
		for u in sim.alive_entities():
			if u.team != HUMAN_TEAM:
				continue
			if u.has("upNexus") or (u.has("upLanetower") and not card.epic):
				circles.append([u.position, u.bb.get_float("eiWelaRange", 3, 0.0)])
		_zone_overlay.set_dynamic_zones(circles)
		var m := _mouse_world_2d()
		_zone_overlay.update(Vector3(m.x, 0.0, -m.y))
	elif card != null and card.is_spawner():
		_grid.show_occupation(HUMAN_TEAM)
	else:
		_grid.reset_colors()


## The unit under the cursor gets its team-colour outline every frame (eiDrawOutline); while an entity spell
## is armed only targetable units highlight.
func _update_hover() -> void:
	var unit: SimEntity = null
	if _menu == null and _settings == null and _exit_dialog == null:
		unit = _unit_at(_mouse_world_2d(), true)
		if unit != null and _armed_slot >= 0:
			var card: Cards.CardDef = sim.commanders[HUMAN_TEAM].slots[_armed_slot].card
			if not (card.is_spell() and card.target_type == "ctEntity"):
				unit = null
	var id := unit.id if unit != null else -1
	if id == _hovered_id:
		return
	_set_outline(_hovered_id, false)
	_hovered_id = id
	_set_outline(id, true)


func _set_outline(id: int, on: bool) -> void:
	var view: Node3D = _views.get(id)
	if view == null or not (view is UnitModel):
		return
	var e: SimEntity = sim.entities.get(id)
	for mi: MeshInstance3D in view.find_children("*", "MeshInstance3D", true, false):
		if not on:
			mi.material_overlay = null
			continue
		var m := ShaderMaterial.new()
		m.shader = OUTLINE_SHADER
		m.set_shader_parameter("outline_color", BORDER_TEAM_COLORS[clampi(e.team if e != null else 0, 0, 2)])
		m.set_shader_parameter("albedo_tex", GammaLit.albedo_of(mi.get_surface_override_material(0)))
		mi.material_overlay = m


## The sim ticks at 31 Hz: views interpolate from the pre-step state so movement stays smooth at any frame rate
## (player-invisible engineering; the original client also rendered decoupled from the game tick).
func _capture_prev() -> void:
	_prev_pos.clear()
	_prev_front.clear()
	for id in _views:
		var p: Projectile = sim.projectiles.get(id)
		if p != null:
			_prev_pos[id] = p.position
			continue
		var e: SimEntity = sim.entities.get(id)
		if e != null:
			_prev_pos[id] = e.position
			_prev_front[id] = e.front


## The interpolated (displayed) position of an entity this frame, for the HUD bars projected over the units.
func view_position(id: int, e) -> Vector2:
	return _lerp_pos(id, e.position, clampf(_accumulator_ms / SimConstants.TICK_MS, 0.0, 1.0))


func _lerp_pos(id: int, current: Vector2, alpha: float) -> Vector2:
	var prev: Variant = _prev_pos.get(id)
	if prev == null:
		return current
	return (prev as Vector2).lerp(current, alpha)


func _sync_views() -> void:
	var alpha := clampf(_accumulator_ms / SimConstants.TICK_MS, 0.0, 1.0)
	for id in _views:
		var view: Node3D = _views[id]
		var p: Projectile = sim.projectiles.get(id)
		if p != null:
			var pp := _lerp_pos(id, p.position, alpha)
			var flight := Vector3(pp.x, 1.2, pp.y) - view.position   # face the flight direction
			view.position = Vector3(pp.x, 1.2, pp.y)
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
			var ep := _lerp_pos(id, e.position, alpha)
			view.position = Vector3(ep.x, _view_y.get(id, 0.0), ep.y)
			view.set_moving(e.moving, e.speed())
			_sync_buff_effects(e, view)
			for pair in _ready_effects.get(id, []):   # VisibleWithWelaReady (eiIsReady includes the cooldown)
				var w := e.wela(pair[1])
				pair[0].visible = w != null and sim.time_ms >= w.cooldown_ready_at and sim._wela_ready(e, w)
			if e.fire_at >= 0 and _last_fire.get(id, -1) != e.fire_at:   # a new attack started
				_last_fire[id] = e.fire_at
				view.play_attack()
				_spawn_effects(e, "fire", view)
				_spawn_effects(e, "prefire", view)
				for child in view.get_children():
					if child is VertexTrace and child.get_meta("activate", "create") in ["fire", "prefire"]:
						child.activate()
		else:
			var y := 0.2 if e.is_spawner() else (2.0 if e.is_building() else 0.9)
			var ep2 := _lerp_pos(id, e.position, alpha)
			view.position = Vector3(ep2.x, y, ep2.y)
		if e.front.length_squared() > 0.0:
			if view is UnitModel:   # the models face their local +Z; the turn interpolates like the position
				var target := atan2(e.front.x, e.front.y)
				var pf: Variant = _prev_front.get(id)
				view.rotation.y = lerp_angle(atan2(pf.x, pf.y), target, alpha) if pf != null and (pf as Vector2).length_squared() > 0.0 else target
			else:
				view.rotation.y = atan2(-e.front.y, e.front.x) + PI / 2
