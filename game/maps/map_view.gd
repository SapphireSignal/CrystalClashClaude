class_name MapView
extends Node3D
## Renders an original map from assets/maps/<Name>/ (tools/convert_map.py): terrain glb, water surfaces,
## the map's lights and ambient, vegetation as MultiMeshes and the decoration entities (bridges, stones).

const MAPS_DIR := "res://assets/maps/"
const ENV_DIR := "res://assets/environment/"
## The original lit in gamma space (Standardshader.fx:515 colour * (NdotL * light + ambient)); Godot lights in
## linear space, so the map's intensities are scaled to match the reference screenshots' brightness.
const LIGHT_SCALE := 0.7

static var _material_cache: Dictionary = {}

var ambient_color := Color.WHITE
var ambient_energy := 1.0


func load_map(map_name: String) -> void:
	for child in get_children():
		child.queue_free()
	var dir := MAPS_DIR + map_name + "/"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "map.json"))
	_add_terrain(dir + str(data["terrain"]["file"]))
	for water in data.get("water", []):
		_add_water(water)
	_add_lights(data.get("lights", {}))
	_add_vegetation(data.get("vegetation", []))
	for deco in data.get("decorations", []):
		_add_decoration(deco)
	if data.has("grass"):
		_add_grass(dir, data["grass"])


func _add_terrain(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_error("missing terrain " + path)
		return
	var terrain: Node3D = (load(path) as PackedScene).instantiate()
	terrain.name = "Terrain"
	add_child(terrain)


## TWaterSurface: a plane of GeometrySize at Position with the water colour (the original's reflective /
## refractive water shader is not ported yet).
func _add_water(water: Dictionary) -> void:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(water["size"][0], water["size"][1])
	mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	var c: Array = water["color"]
	mat.albedo_color = Color(c[0], c[1], c[2], 1.0 - float(water.get("transparency", 0.3)))
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	mat.metallic_specular = 0.8
	mesh.material_override = mat
	mesh.position = Vector3(water["position"][0], water["position"][1], water["position"][2])
	mesh.name = "Water"
	add_child(mesh)


## TLightManager: ambient (rgb, W = intensity) and up to three directional lights (Color.W = intensity).
func _add_lights(lights: Dictionary) -> void:
	var ambient: Array = lights.get("ambient", [1, 1, 1, 1])
	ambient_color = Color(ambient[0], ambient[1], ambient[2])
	ambient_energy = float(ambient[3]) * LIGHT_SCALE
	for light in lights.get("directional", []):
		if not light.get("enabled", false):
			continue
		var node := DirectionalLight3D.new()
		var d: Array = light["direction"]
		var dir := Vector3(d[0], d[1], d[2]).normalized()
		var c: Array = light["color"]
		node.light_color = Color(c[0], c[1], c[2])
		node.light_energy = float(c[3]) * LIGHT_SCALE
		node.shadow_enabled = true
		add_child(node)
		node.look_at_from_position(Vector3(0, 60, 0), Vector3(0, 60, 0) + dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)


## TVegetationMesh instances: one MultiMesh per mesh + diffuse texture, transform = T * R(pitch, yaw, roll) * S.
func _add_vegetation(items: Array) -> void:
	var groups: Dictionary = {}
	for item in items:
		var key := "%s|%s" % [item["mesh"], item.get("diffuse", "")]
		groups.get_or_add(key, []).append(item)
	for key in groups:
		var entries: Array = groups[key]
		var first: Dictionary = entries[0]
		var mesh := _mesh_of(ENV_DIR + str(first["mesh"]))
		if mesh == null:
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = entries.size()
		for i in entries.size():
			var e: Dictionary = entries[i]
			var r: Array = e["rotation"]
			var basis := Basis.from_euler(Vector3(r[0], r[1], r[2]), EULER_ORDER_YXZ).scaled(Vector3.ONE * float(e["scale"]))
			var p: Array = e["position"]
			multi.set_instance_transform(i, Transform3D(basis, Vector3(p[0], p[1], p[2])))
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multi
		instance.material_override = _environment_material(str(first.get("diffuse", "")), true)
		instance.name = str(first["mesh"]).get_file().get_basename()
		add_child(instance)


## TGrassTuft quads baked by the converter, drawn with the grass texture cut out (no wind animation yet).
func _add_grass(dir: String, grass: Dictionary) -> void:
	var mesh := _mesh_of(dir + str(grass["file"]))
	if mesh == null:
		return
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _environment_material(str(grass.get("diffuse", "")), true)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.name = "Grass"
	add_child(instance)


## RDecoEntityDescription: a script entity at Position facing Front; its meshes come from the script.
func _add_decoration(deco: Dictionary) -> void:
	var p: Array = deco["position"]
	var f: Array = deco["front"]
	var root := Node3D.new()
	root.position = Vector3(p[0], p[1], p[2])
	root.rotation.y = atan2(float(f[0]), float(f[2]))   # model +Z -> front
	root.name = str(deco["script"]).get_file().get_basename()
	add_child(root)
	for m in deco["meshes"]:
		var mesh := _mesh_of(ENV_DIR + str(m["mesh"]))
		if mesh == null:
			continue
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = _environment_material(str(m.get("diffuse", "")), false)
		instance.scale = Vector3.ONE * float(m["scale"])
		root.add_child(instance)


## The (single) ArrayMesh inside an environment glb.
func _mesh_of(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		push_warning("missing environment mesh " + path)
		return null
	var scene: Node = (load(path) as PackedScene).instantiate()
	var found: MeshInstance3D = null
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		found = mi
		break
	var mesh: Mesh = found.mesh if found != null else null
	scene.free()
	return mesh


static func _environment_material(diffuse: String, foliage: bool) -> StandardMaterial3D:
	var key := diffuse + ("|foliage" if foliage else "")
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := StandardMaterial3D.new()
	var path := ENV_DIR + diffuse
	if diffuse != "" and ResourceLoader.exists(path):
		mat.albedo_texture = load(path)
	if foliage:   # leaves: cut-out alpha, both sides
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.metallic_specular = 0.2
	_material_cache[key] = mat
	return mat
