extends Node3D
## Sandbox: runs the Simulation at a fixed tick and renders entities with placeholder meshes.
## Blue (you) plays deck slots with keys 1-9, 0, -, = at the mouse position (drops) or on the next free
## build field (spawners). Red plays a Black deck automatically. Real assets replace the capsules in phase 5.

const BLUE_DECK := [
	"Units/White/FootmanDrop", "Units/White/ArcherDrop", "Units/White/FootmanSpawner", "Units/White/ArcherSpawner",
	"Units/White/BallistaDrop", "Units/White/PriestDrop", "Units/White/MonkDrop", "Units/White/MarksmanDrop",
	"Units/White/HeavyGunnerDrop", "Units/White/SuntowerBuilding", "Units/White/AvengerDrop", "Units/White/DefenderDrop",
]
const RED_DECK := [
	"Units/Black/VoidSkeletonDrop", "Units/Black/VoidBowmanDrop", "Units/Black/VoidSkeletonSpawner", "Units/Black/VoidBowmanSpawner",
	"Units/Black/VoidWormDrop", "Units/Black/VoidBaneDrop", "Units/Black/VoidCauldronDrop", "Units/Black/VoidSlimeDrop",
	"Units/Black/FrostgoyleFountainBuilding", "Units/Black/VoidWraithDrop", "Units/Black/VoidAltarBuilding", "Units/Black/TyrusDrop",
]
const SLOT_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUAL]

var sim: Simulation
var _accumulator_ms: float = 0.0
var _views: Dictionary = {}   # entity id -> MeshInstance3D
var _label: Label
var _red_next_play_at: int = 15000

@onready var _units_root: Node3D = $Units
@onready var _camera: Camera3D = $Camera3D
var _look_at := Vector2(-40, -23)   # ground point the camera looks at
var _camera_distance := 70.0
var _drag_anchor: Variant = null    # ground point under the mouse when the right drag started


func _ready() -> void:
	sim = Simulation.new(randi(), 4)
	sim.entity_spawned.connect(_on_spawned)
	sim.entity_died.connect(_on_died)
	sim.projectile_spawned.connect(_on_projectile_spawned)
	sim.projectile_removed.connect(func(p, _hit): _on_died(p))
	sim.team_lost.connect(func(t): print("team %d lost" % t))
	sim.spawn_bases()
	sim.commanders[Simulation.TEAM_BLUE].set_deck(BLUE_DECK)
	sim.commanders[Simulation.TEAM_RED].set_deck(RED_DECK)   # red plays Black so both factions show in the sandbox
	_label = $HUD/Label
	_place_camera(Vector2(-40, -23))


func _process(delta: float) -> void:
	_accumulator_ms += delta * 1000.0
	while _accumulator_ms >= SimConstants.TICK_MS:
		_accumulator_ms -= SimConstants.TICK_MS
		sim.step()
		_red_ai()
	_sync_views()
	var c: Commander = sim.commanders[Simulation.TEAM_BLUE]
	var charges := ""
	for i in c.slots.size():
		charges += "%d:%d " % [i + 1, c.slots[i].charges]
	_label.text = "t=%ds  gold=%d/%d wood=%d tier=%d income=%d  units=%d\n%s" % [
		sim.time_ms / 1000, c.gold, c.gold_cap(), c.wood, c.tier, c.income(), sim.alive_entities().size(), charges]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_drag_anchor = _mouse_world_2d() if event.pressed else null
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = maxf(25.0, _camera_distance - 5.0)
			_place_camera(_look_at)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = minf(140.0, _camera_distance + 5.0)
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
	if slot >= 0 and slot < sim.commanders[Simulation.TEAM_BLUE].slots.size():
		_play(Simulation.TEAM_BLUE, slot, _mouse_world_2d())


func _play(team: int, slot: int, where: Vector2) -> void:
	var c: Commander = sim.commanders[team]
	var target: Variant = where
	if c.slots[slot].card.is_spawner():
		target = _next_free_field(team)
		if target == null:
			return
	var result := sim.play_card(team, slot, target)
	if result != Simulation.PlayResult.OK:
		print("play %s: %s" % [c.slots[slot].card.name, Simulation.PlayResult.keys()[result]])


## Simple opponent: every few seconds play the first ready drop near its own lane node, spawners on the grid.
func _red_ai() -> void:
	if sim.time_ms < _red_next_play_at:
		return
	_red_next_play_at = sim.time_ms + 6000
	var c: Commander = sim.commanders[Simulation.TEAM_RED]
	for i in c.slots.size():
		if c.slots[i].is_ready(sim.time_ms, c):
			_play(Simulation.TEAM_RED, i, Vector2(50 + sim.rng.randf() * 10, -23))
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
	var m := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(m)
	var dir := _camera.project_ray_normal(m)
	if absf(dir.y) < 0.0001:
		return Vector2.ZERO
	var t := -from.y / dir.y
	var hit := from + dir * t
	return Vector2(hit.x, hit.z)


func _place_camera(look_at_2d: Vector2) -> void:
	# Original camera offset direction (Constants.Client.pas:34), scaled to see the lane.
	_look_at = look_at_2d
	var offset := Vector3(-0.3947, 0.8121, -0.4297).normalized() * _camera_distance
	var target := Vector3(look_at_2d.x, 0, look_at_2d.y)
	_camera.position = target + offset
	_camera.look_at(target, Vector3.UP)


func _on_spawned(e: SimEntity) -> void:
	if e.think_once_waits:   # one-tick helper entities (soul gather spawner) have no body
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
	match e.team:
		Simulation.TEAM_RED: mat.albedo_color = Color(0.9, 0.25, 0.2)
		Simulation.TEAM_BLUE: mat.albedo_color = Color(0.2, 0.4, 0.95)
		_: mat.albedo_color = Color(0.6, 0.6, 0.6)
	mesh.material_override = mat
	_units_root.add_child(mesh)
	_views[e.id] = mesh


func _on_projectile_spawned(p: Projectile) -> void:
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
	var view: MeshInstance3D = _views.get(e.id)
	if view:
		view.queue_free()
		_views.erase(e.id)


func _sync_views() -> void:
	for id in _views:
		var view: MeshInstance3D = _views[id]
		var p: Projectile = sim.projectiles.get(id)
		if p != null:
			view.position = Vector3(p.position.x, 1.2, p.position.y)
			continue
		var e: SimEntity = sim.entities.get(id)
		if e == null:
			continue
		var y := 0.2 if e.is_spawner() else (2.0 if e.is_building() else 0.9)
		view.position = Vector3(e.position.x, y, e.position.y)
		if e.front.length_squared() > 0.0:
			view.rotation.y = atan2(-e.front.y, e.front.x) + PI / 2
