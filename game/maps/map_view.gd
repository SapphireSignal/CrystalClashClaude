class_name MapView
extends Node3D
## Renders an original map from assets/maps/<Name>/ (tools/convert_map.py): terrain glb, water surfaces,
## the map's lights and ambient, vegetation as MultiMeshes and the decoration entities (bridges, stones).

const MAPS_DIR := "res://assets/maps/"
const ENV_DIR := "res://assets/environment/"
## Lighting is the original's gamma-space formula, ported verbatim in game/maps/gamma_lit.gdshader (terrain,
## vegetation, decorations and unit models); the map's ambient / sun values reach it as the global shader
## parameters rol_ambient / rol_sun. The Godot light node only supplies direction and shadow.
## The engine's Glow post-effect (PostEffects.fxs:22-33: Kernelsize 3, AdditiveBlur, Intensity 0.44, one iteration)
## blurs the rsGlow buffer with the un-normalised GAUSS_3_ADDITIVE kernel (Shaderglobals.fx:24, taps sum 4.94164)
## once per axis, each pass scaled by the intensity, and adds the result to the scene (Engine.Core.pas:1835-1890):
## a flat glowing area gains (4.94164 * 0.44)^2 of its glow value. Godot has no such pass, so emissive surfaces
## carry this gain in their emission energy.
const GLOW_POST_GAIN := pow(4.94164 * 0.44, 2.0)   # 4.73

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
	# the glb's PBR materials carry the chunk textures; relight them with the original's formula
	for mi: MeshInstance3D in terrain.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if base == null:
				continue
			mi.set_surface_override_material(i, GammaLit.material(base.albedo_texture, {"normal": base.normal_texture, "uv_clamp": true}))
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
	ambient_energy = float(ambient[3])
	# Ambient = rgb premultiplied by the intensity (Engine.Core.pas:1009)
	RenderingServer.global_shader_parameter_set("rol_ambient", Vector3(ambient[0], ambient[1], ambient[2]) * float(ambient[3]))
	for light in lights.get("directional", []):
		if not light.get("enabled", false):
			continue
		var node := DirectionalLight3D.new()
		var d: Array = light["direction"]
		var dir := Vector3(d[0], d[1], d[2]).normalized()
		var c: Array = light["color"]
		node.light_color = Color(c[0], c[1], c[2])
		node.light_energy = float(c[3])
		# DirectionalLightColor.rgb * .a (Standardshader.fx:486); the shadow comes from the light node
		RenderingServer.global_shader_parameter_set("rol_sun", Vector3(c[0], c[1], c[2]) * float(c[3]))
		node.shadow_enabled = true
		node.shadow_blur = 1.5   # SHADOW_SAMPLING_RANGE 1: a small PCF blur
		# One orthogonal cascade like the original's single shadow map: the default PSSM4 shows its split
		# boundaries as straight brightness seams across the map at RTS camera distances.
		node.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		node.directional_shadow_max_distance = 420.0   # covers the whole map: no visible coverage edge
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
	# leaves / grass: cut-out alpha, both sides lit (the back face uses the flipped normal: the world node is
	# mirrored (main.gd), so a plain double-sided material showed the back faces with normals pointing away)
	var options := {"cull_disabled": true, "flip_backface": true, "alpha_scissor": 0.5} if foliage else {}
	var mat := GammaLit.material(texture, options)
	_material_cache[key] = mat
	return mat
