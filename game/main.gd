extends Node3D
## Sandbox: runs the Simulation at a fixed tick and renders entities with placeholder meshes.
## Keys: 1/2 drop Footmen/Archers for red, 3/4 for blue. Real assets replace the capsules in phase 5.

const SIM_X_SCALE := 1.0

var sim: Simulation
var _accumulator_ms: float = 0.0
var _views: Dictionary = {}   # entity id -> MeshInstance3D
var _label: Label

@onready var _units_root: Node3D = $Units
@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	sim = Simulation.new(randi(), 4)
	sim.entity_spawned.connect(_on_spawned)
	sim.entity_died.connect(_on_died)
	sim.team_lost.connect(func(t): print("team %d lost" % t))
	sim.spawn_bases()
	_label = $HUD/Label
	_place_camera(Vector2(0, -23))


func _process(delta: float) -> void:
	_accumulator_ms += delta * 1000.0
	while _accumulator_ms >= SimConstants.TICK_MS:
		_accumulator_ms -= SimConstants.TICK_MS
		sim.step()
	_sync_views()
	var red: Simulation.Commander = sim.commanders[Simulation.TEAM_RED]
	_label.text = "t=%ds tick=%d  gold=%d/%d wood=%d tier=%d  units=%d" % [
		sim.time_ms / 1000, sim.tick_counter, red.gold, red.gold_cap(), red.wood, red.tier, sim.alive_entities().size()]


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	match event.keycode:
		KEY_1: sim.drop_squad("Units/White/Footman", Simulation.TEAM_BLUE, Vector2(-60, -23), 4)
		KEY_2: sim.drop_squad("Units/White/Archer", Simulation.TEAM_BLUE, Vector2(-60, -23), 2)
		KEY_3: sim.drop_squad("Units/White/Footman", Simulation.TEAM_RED, Vector2(60, -23), 4)
		KEY_4: sim.drop_squad("Units/White/Archer", Simulation.TEAM_RED, Vector2(60, -23), 2)
		KEY_5: _place_next_spawner("Units/White/FootmanSpawner", Simulation.TEAM_BLUE)
		KEY_6: _place_next_spawner("Units/White/ArcherSpawner", Simulation.TEAM_RED)
		KEY_ESCAPE: get_tree().quit()


## Sandbox helper: put a spawner on the first free field of the team's build zone.
func _place_next_spawner(unit_id: String, team: int) -> void:
	for zone: BuildZone in sim.build_zones.values():
		if zone.team != team:
			continue
		for field in zone.spawn_slots():
			if zone.is_free(field):
				sim.place_spawner(unit_id, team, zone.id, field)
				return


func _place_camera(look_at_2d: Vector2) -> void:
	# Original camera offset direction (Constants.Client.pas:34), scaled to see the lane.
	var offset := Vector3(-0.3947, 0.8121, -0.4297).normalized() * 70.0
	var target := Vector3(look_at_2d.x, 0, look_at_2d.y)
	_camera.position = target + offset
	_camera.look_at(target, Vector3.UP)


func _on_spawned(e: SimEntity) -> void:
	var mesh := MeshInstance3D.new()
	if e.is_building():
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
		view.position = Vector3(e.position.x, 0.9 if not e.is_building() else 2.0, e.position.y)
		if e.front.length_squared() > 0.0:
			view.rotation.y = atan2(-e.front.y, e.front.x) + PI / 2
