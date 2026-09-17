extends Node3D
## Sandbox: runs the Simulation at a fixed tick and renders entities with placeholder meshes.
## Blue (you) plays deck slots with keys 1-9, 0, -, = at the mouse position (drops) or on the next free
## build field (spawners). Red plays the same deck automatically. Real assets replace the capsules in phase 5.

const BLUE_DECK := [
	"Units/White/FootmanDrop", "Units/White/ArcherDrop", "Units/White/FootmanSpawner", "Units/White/ArcherSpawner",
	"Units/White/BallistaDrop", "Units/White/PriestDrop", "Units/White/MonkDrop", "Units/White/MarksmanDrop",
	"Units/White/HeavyGunnerDrop", "Units/White/SuntowerBuilding", "Units/White/AvengerDrop", "Units/White/DefenderDrop",
]
const SLOT_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUAL]

var sim: Simulation
var _accumulator_ms: float = 0.0
var _views: Dictionary = {}   # entity id -> MeshInstance3D
var _label: Label
var _red_next_play_at: int = 15000

@onready var _units_root: Node3D = $Units
@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	sim = Simulation.new(randi(), 4)
	sim.entity_spawned.connect(_on_spawned)
	sim.entity_died.connect(_on_died)
	sim.team_lost.connect(func(t): print("team %d lost" % t))
	sim.spawn_bases()
	for team in [Simulation.TEAM_BLUE, Simulation.TEAM_RED]:
		sim.commanders[team].set_deck(BLUE_DECK)
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
	var offset := Vector3(-0.3947, 0.8121, -0.4297).normalized() * 70.0
	var target := Vector3(look_at_2d.x, 0, look_at_2d.y)
	_camera.position = target + offset
	_camera.look_at(target, Vector3.UP)


func _on_spawned(e: SimEntity) -> void:
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
	mat.albedo_color = Color(0.9, 0.25, 0.2) if e.team == Simulation.TEAM_RED else Color(0.2, 0.4, 0.95)
	mesh.material_override = mat
	_units_root.add_child(mesh)
	_views[e.id] = mesh


func _on_died(e: SimEntity) -> void:
	var view: MeshInstance3D = _views.get(e.id)
	if view:
		view.queue_free()
		_views.erase(e.id)


func _sync_views() -> void:
	for id in _views:
		var e: SimEntity = sim.entities.get(id)
		if e == null:
			continue
		var view: MeshInstance3D = _views[id]
		var y := 0.2 if e.is_spawner() else (2.0 if e.is_building() else 0.9)
		view.position = Vector3(e.position.x, y, e.position.y)
		if e.front.length_squared() > 0.0:
			view.rotation.y = atan2(-e.front.y, e.front.x) + PI / 2
