class_name BuildGrid
extends Node3D
## TBuildGridManagerComponent port (EntityComponents.Client.pas:504): one tile mesh per free build field
## (Gameplay/Buildgrid/Buildgrid<1-4>, random variant and 0/90/180/270 deg rotation, scale GRIDNODESIZE / 1.84
## + 0.08, sunk 0.04), cyan glow (GlowOvershoot.fx, $00FFFF) while the field is still in the wave rotation:
## eiWaveSpawn dims it over 1000 ms, all tiles light up again over 500 ms once every field spawned.

const MESHES := "res://assets/gameplay/Buildgrid/"
const VARIANTS := 4
const GLOW_TIME_IN := 0.5
const GLOW_TIME_OUT := 1.0
const GLOW_COLOR := Color(0.0, 1.0, 1.0)
const GLOW_COLOR_INTENSITY := 0.4
const SINK := 0.04

var _sim: Simulation
var _tiles: Dictionary = {}          # zone id -> Array of tiles {coord, mesh, material, active, glow, target, speed}
var _rotation_left: Dictionary = {}  # zone id -> fields left in the current rotation
var _rng := RandomNumberGenerator.new()
static var _mesh_cache: Dictionary = {}


func setup(sim: Simulation) -> void:
	_sim = sim
	_rng.seed = 1
	for zone_id in sim.build_zones:
		var zone: BuildZone = sim.build_zones[zone_id]
		var tiles: Array = []
		for x in zone.size.x:
			for y in zone.size.y:
				var coord := Vector2i(x, y)
				if zone.is_banned(coord):
					continue
				tiles.append(_make_tile(zone, coord))
		_tiles[zone_id] = tiles
		_rotation_left[zone_id] = tiles.size()
	sim.wave_spawned.connect(_on_wave_spawn)


func _make_tile(zone: BuildZone, coord: Vector2i) -> Dictionary:
	var variant := _rng.randi_range(1, VARIANTS)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _mesh(variant)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(MESHES + "Buildgrid%dDiffuse.tga" % variant)
	mat.metallic_specular = 0.0
	mat.roughness = 1.0
	# GlowOvershoot.fx: rgb = lerp(diffuse, go_color, go_overshoot); overshoot = GLOW_COLOR_INTENSITY 0.4 without
	# the post-effect glow (the live screenshots show that strong teal), fading to 0 once the field spawned.
	mat.emission_enabled = true
	mat.emission = GLOW_COLOR
	_apply_glow(mat, 1.0)
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var c := zone.center_of_field(coord)
	mesh.position = Vector3(c.x, -SINK, c.y)
	mesh.rotation.y = PI / 2.0 * _rng.randi_range(0, 3)
	mesh.scale = Vector3.ONE * (BuildZone.GRIDNODESIZE / 1.84 + 0.08)
	add_child(mesh)
	return {"coord": coord, "mesh": mesh, "material": mat, "active": true, "glow": 1.0, "target": 1.0, "speed": 1.0 / GLOW_TIME_IN}


func _mesh(variant: int) -> Mesh:
	if not _mesh_cache.has(variant):
		var scene: PackedScene = load(MESHES + "buildgrid%d.glb" % variant)
		var root := scene.instantiate()
		var found: Mesh = null
		var stack: Array = [root]
		while not stack.is_empty() and found == null:
			var n: Node = stack.pop_back()
			if n is MeshInstance3D:
				found = n.mesh
			stack.append_array(n.get_children())
		root.free()
		_mesh_cache[variant] = found
	return _mesh_cache[variant]


func _on_wave_spawn(zone_id: int, field: Vector2i) -> void:
	for tile in _tiles.get(zone_id, []):
		if tile.coord == field and tile.active:
			tile.active = false
			tile.target = 0.0
			tile.speed = 1.0 / GLOW_TIME_OUT
			_rotation_left[zone_id] -= 1
	if _rotation_left[zone_id] <= 0:
		_rotation_left[zone_id] = _tiles[zone_id].size()
		for tile in _tiles[zone_id]:
			tile.active = true
			tile.target = 1.0
			tile.speed = 1.0 / GLOW_TIME_IN


func _process(delta: float) -> void:
	for zone_id in _tiles:
		for tile in _tiles[zone_id]:
			if tile.glow != tile.target:
				tile.glow = move_toward(tile.glow, tile.target, delta * tile.speed)
				_apply_glow(tile.material, tile.glow)


static func _apply_glow(mat: StandardMaterial3D, glow: float) -> void:
	# Fitted to the live client's tile colour (ref (120,205,204) from diffuse ~(101,114,113)): 0.6 x diffuse +
	# 0.30 x cyan overshoot + 0.23 x white bloom (the post-effect glow the original adds on top).
	var overshoot := GLOW_COLOR_INTENSITY * glow
	mat.albedo_color = Color(1.0 - overshoot, 1.0 - overshoot, 1.0 - overshoot)
	mat.emission = Color(0.27, 0.60, 0.60)
	mat.emission_energy_multiplier = glow
