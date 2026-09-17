class_name MapView
extends Node3D
## Renders an original map from assets/maps/<Name>/ (tools/convert_map.py): terrain glb, water surfaces,
## the map's lights and ambient, vegetation as MultiMeshes and the decoration entities (bridges, stones).

const MAPS_DIR := "res://assets/maps/"
const ENV_DIR := "res://assets/environment/"
## The original lit in gamma space (Standardshader.fx:515 colour * (NdotL * light + ambient)): with ambient 0.772
## and sun 0.52 a shadowed patch shows 63 % of the lit brightness on screen. Godot lights in linear space, so
## the same numbers would show ~80 % (flat look). Ambient x0.35 and sun x1.06 give the 63 % display ratio with
## the lit sand / platform at the reference's brightness (patch medians, docs/reference-material.md).
const AMBIENT_SCALE := 0.35
const SUN_SCALE := 1.06
const LIVE_WATER_COLOR := Color(0.0, 0.33, 0.48)   # see _add_water
const LIVE_WATER_TRANSPARENCY := 0.0
const LIVE_WATER_FRESNEL := 0.1

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
		_add_water(water, dir, data.get("lights", {}), data["terrain"])
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


## TWaterSurface: a plane of GeometrySize at Position drawn with the water shader port (game/maps/water.gdshader)
## fed with the .wat parameters (TextureNormalization = GeometrySize / 2000, Engine.Water.pas:366).
func _add_water(water: Dictionary, dir: String, lights: Dictionary, terrain: Dictionary) -> void:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(water["size"][0], water["size"][1])
	mesh.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load("res://game/maps/water.gdshader")
	# depth from the terrain heightmap (no depth texture on the Compatibility renderer)
	var ts: Array = terrain["scale"]
	var tp: Array = terrain["position"]
	var heights := Image.load_from_file(ProjectSettings.globalize_path(dir + str(terrain.get("heightmap", "heightmap.png"))))   # raw data, not colour: bypass the importer
	mat.set_shader_parameter("terrain_heights", ImageTexture.create_from_image(heights))
	mat.set_shader_parameter("terrain_scale", Vector3(ts[0], ts[1], ts[2]))
	mat.set_shader_parameter("terrain_position", Vector3(tp[0], tp[1], tp[2]))
	mat.set_shader_parameter("water_height", float(water["position"][1]))
	# Live-client water (docs/reference-material.md): the 2022 .wat colour (45,93,113) with 33 % see-through gives
	# a pale grey-green; the reference's deep water is opaque saturated blue (0,95,134). The live .wat is not in
	# the repo, so these three values are set to reproduce the measured reference patches.
	water = water.duplicate()
	water["color"] = [LIVE_WATER_COLOR.r, LIVE_WATER_COLOR.g, LIVE_WATER_COLOR.b, 0.0]
	water["transparency"] = LIVE_WATER_TRANSPARENCY
	water["fresnel_offset"] = LIVE_WATER_FRESNEL
	var c: Array = water["color"]
	var sky: Array = water.get("sky_color", [0.63, 0.73, 0.92, 0])
	mat.set_shader_parameter("water_color", Vector3(c[0], c[1], c[2]))
	mat.set_shader_parameter("sky_color", Vector3(sky[0], sky[1], sky[2]))
	mat.set_shader_parameter("roughness", float(water.get("roughness", 0.9)))
	mat.set_shader_parameter("fresnel_offset", float(water.get("fresnel_offset", 0.19)))
	mat.set_shader_parameter("water_transparency", float(water.get("transparency", 0.33)))
	mat.set_shader_parameter("depth_transparency_range", float(water.get("depth_transparency_range", 0.48)))
	mat.set_shader_parameter("color_extinction_range", float(water.get("color_extinction_range", 52.0)))
	mat.set_shader_parameter("specular_power", float(water.get("specular_power", 68.0)))
	mat.set_shader_parameter("specular_intensity", float(water.get("specular_intensity", 0.94)))
	mat.set_shader_parameter("size", float(water.get("shader_size", 224.0)))
	mat.set_shader_parameter("texture_normalization", Vector2(water["size"][0], water["size"][1]) / 2000.0)
	var wave := str(water.get("wave_texture", ""))
	if wave != "" and ResourceLoader.exists(dir + wave):
		mat.set_shader_parameter("wave_texture", load(dir + wave))
	for light in lights.get("directional", []):
		if light.get("enabled", false):
			var d: Array = light["direction"]
			var col: Array = light["color"]
			mat.set_shader_parameter("sun_direction", Vector3(d[0], d[1], -d[2]))   # world space: World is mirrored on Z
			mat.set_shader_parameter("sun_color", Vector3(col[0], col[1], col[2]))
			break
	mesh.material_override = mat
	mesh.position = Vector3(water["position"][0], water["position"][1], water["position"][2])
	mesh.name = "Water"
	add_child(mesh)


## TLightManager: ambient (rgb, W = intensity) and up to three directional lights (Color.W = intensity).
func _add_lights(lights: Dictionary) -> void:
	var ambient: Array = lights.get("ambient", [1, 1, 1, 1])
	ambient_color = Color(ambient[0], ambient[1], ambient[2])
	ambient_energy = float(ambient[3]) * AMBIENT_SCALE
	for light in lights.get("directional", []):
		if not light.get("enabled", false):
			continue
		var node := DirectionalLight3D.new()
		var d: Array = light["direction"]
		var dir := Vector3(d[0], d[1], d[2]).normalized()
		var c: Array = light["color"]
		node.light_color = Color(c[0], c[1], c[2])
		node.light_energy = float(c[3]) * SUN_SCALE
		node.shadow_enabled = true
		node.shadow_blur = 1.5   # SHADOW_SAMPLING_RANGE 1: a small PCF blur
		node.top_level = true   # placed in global space: the map lives under the Z-mirrored World node (main.gd)
		add_child(node)
		var dir_global := Vector3(dir.x, dir.y, -dir.z)
		node.look_at_from_position(Vector3(0, 60, 0), Vector3(0, 60, 0) + dir_global, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)


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


static func _environment_material(diffuse: String, foliage: bool) -> Material:
	var key := diffuse + ("|foliage" if foliage else "")
	if _material_cache.has(key):
		return _material_cache[key]
	var path := ENV_DIR + diffuse
	var texture: Texture2D = load(path) if diffuse != "" and ResourceLoader.exists(path) else null
	if foliage:   # leaves: cut-out alpha, both sides lit (game/maps/foliage.gdshader)
		var leaf := ShaderMaterial.new()
		leaf.shader = preload("res://game/maps/foliage.gdshader")
		if texture != null:
			leaf.set_shader_parameter("albedo_texture", texture)
		_material_cache[key] = leaf
		return leaf
	var mat := StandardMaterial3D.new()
	if texture != null:
		mat.albedo_texture = texture
	mat.roughness = 1.0
	mat.metallic_specular = 0.2
	_material_cache[key] = mat
	return mat
