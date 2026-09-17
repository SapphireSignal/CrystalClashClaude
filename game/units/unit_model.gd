class_name UnitModel
extends Node3D
## The original unit visuals (TMeshComponent, BaseConflict.EntityComponents.Client.Visuals.pas) built from
## units.json `visuals`: the FBX scene per mesh entry, the TMesh xml's textures as a StandardMaterial3D,
## the original's scale (SIZE_FACTOR_3DSMAX for ApplyLegacySizeFactor meshes, eiModelSize) and the
## animation clips cut from the FBX take by frame ranges at 30 fps.

const SIZE_FACTOR_3DSMAX := 2.0 / 125.0     # Visuals.pas:873, applied by ApplyLegacySizeFactor
const FRAME_MS := 1000.0 / 30.0             # Engine.Mesh.pas:2697 (frames -> ms)
const DEFAULT_SKIN := "_Default"
const MODELS_JSON := "res://game/data/models.json"
const UNITS_DIR := "res://assets/units/"

static var _models: Dictionary = {}          # relative FBX path -> {"unit_scale": cm per FBX unit}
static var _scene_cache: Dictionary = {}     # FBX path -> PackedScene
static var _material_cache: Dictionary = {}  # xml path -> StandardMaterial3D
static var _folder_index: Dictionary = {}    # folder -> {lowercase name -> real name}

var _players: Array[AnimationPlayer] = []
var _speeds: Dictionary = {}                 # animation name -> SetAnimationSpeed factor
var _has_attack_loop := false
var _current := ""
var _one_shot := false


## Builds the model for a unit script, or null when the script has no client visuals / model files.
static func create(unit_id: String) -> UnitModel:
	if not UnitDb.has_unit(unit_id):
		return null
	var visuals: Dictionary = UnitDb.raw(unit_id).get("visuals", {})
	if visuals.is_empty():
		return null
	var model := UnitModel.new()
	var sizes: Dictionary = visuals.get("model_sizes", {})   # eiModelSize per wela group
	for mesh in visuals["meshes"]:
		var model_size := 1.0
		if not mesh.get("ignore_model_size", false):
			for g in mesh.get("groups", []):
				if sizes.has(str(g)):
					model_size = sizes[str(g)]
					break
		var node := _build_mesh(mesh, model_size)
		if node != null:
			model.add_child(node)
	if model.get_child_count() == 0:
		model.free()
		return null
	model._speeds = visuals["meshes"][0].get("animation_speeds", {})
	model._has_attack_loop = visuals["meshes"][0].get("has_attack_loop", false)
	for p in model.find_children("*", "AnimationPlayer", true, false):
		model._players.append(p)
		p.animation_finished.connect(model._on_animation_finished)
	model.play("stand")
	return model


static func _build_mesh(mesh: Dictionary, model_size: float) -> Node3D:
	var xml_rel: String = str(mesh["path"]).replace("{skin}", DEFAULT_SKIN).replace("\\", "/")
	if not xml_rel.begins_with("Units/"):
		return null   # Effects/Meshes/* (spell decorations) are not unit models yet
	var xml_path := _real_path(UNITS_DIR + xml_rel.trim_prefix("Units/"))
	var descriptor := _read_descriptor(xml_path)
	if descriptor.is_empty():
		return null
	var fbx_path := _real_path(xml_path.get_base_dir() + "/" + descriptor.get("GeometryFile", ""))
	if not ResourceLoader.exists(fbx_path):
		return null
	var scene: PackedScene = _scene_cache.get(fbx_path)
	if scene == null:
		scene = load(fbx_path)
		_scene_cache[fbx_path] = scene
	var node: Node3D = scene.instantiate()
	var material := _material(xml_path, descriptor)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, material)
	# original scale: raw units x SIZE_FACTOR_3DSMAX (legacy) or x 1; Godot scaled raw units by unit_scale / 100
	var unit_scale: float = _models_index().get(fbx_path.trim_prefix(UNITS_DIR).get_base_dir() + "/" + fbx_path.get_file(), {}).get("unit_scale", 1.0)
	var raw_scale := SIZE_FACTOR_3DSMAX if mesh.get("legacy_size_factor", false) else 1.0
	var s := raw_scale / (unit_scale / 100.0) * model_size
	node.scale = Vector3(s, s, s)
	if mesh.has("model_offset"):
		var o: Array = mesh["model_offset"]
		node.position = Vector3(o[0], o[1], o[2])
	var player: AnimationPlayer = node.find_child("AnimationPlayer", true, false)
	if player != null:
		_cut_animations(player, mesh.get("animations", {}))
	return node


## TMeshComponent.CreateNewAnimation: a named clip = frames [first, last] of the FBX take at 30 fps.
static func _cut_animations(player: AnimationPlayer, ranges: Dictionary) -> void:
	var takes := player.get_animation_list()
	if takes.is_empty():
		return
	var take: Animation = player.get_animation(takes[0])
	var frame := FRAME_MS / 1000.0
	var library := AnimationLibrary.new()
	for name in ranges:
		var start: float = ranges[name][0] * frame
		var end: float = maxf(start, ranges[name][1] * frame)
		var clip := Animation.new()
		clip.length = maxf(end - start, frame)
		clip.step = frame
		clip.loop_mode = Animation.LOOP_LINEAR if name in ["stand", "walk", "attack_loop"] else Animation.LOOP_NONE
		for t in take.get_track_count():
			var nt := clip.add_track(take.track_get_type(t))
			clip.track_set_path(nt, take.track_get_path(t))
			clip.track_set_interpolation_type(nt, take.track_get_interpolation_type(t))
			# keys inside the range, plus the neighbours just outside clamped onto the edges (same time = replace)
			for k in take.track_get_key_count(t):
				var time := take.track_get_key_time(t, k)
				if time < start - frame or time > end + frame:
					continue
				clip.track_insert_key(nt, clampf(time - start, 0.0, clip.length), take.track_get_key_value(t, k))
		library.add_animation(name, clip)
	player.add_animation_library("unit", library)


func has_animation(name: String) -> bool:
	for p in _players:
		if p.has_animation("unit/" + name):
			return true
	return false


## Plays a clip on every mesh; one-shot clips (attack, spawn) return to the default afterwards.
func play(name: String, one_shot: bool = false) -> void:
	if not has_animation(name):
		return
	if _current == name and not one_shot:
		return
	_current = name
	_one_shot = one_shot
	var speed: float = _speeds.get(name, 1.0)
	for p in _players:
		if p.has_animation("unit/" + name):
			p.play("unit/" + name, -1, speed)
			if one_shot:
				p.seek(0.0, true)


func is_busy() -> bool:
	return _one_shot


## Idle / walking state from the simulation; ignored while a one-shot clip runs.
func set_moving(moving: bool) -> void:
	if _one_shot:
		return
	play("walk" if moving else "stand")


func play_attack(alternate: bool = false) -> void:
	var name := "attack2" if alternate and has_animation("attack2") else "attack"
	play(name, true)


func _on_animation_finished(_anim: StringName) -> void:
	if _one_shot:
		_one_shot = false
		_current = ""
		play("stand")


static func _models_index() -> Dictionary:
	if _models.is_empty() and FileAccess.file_exists(MODELS_JSON):
		_models = JSON.parse_string(FileAccess.get_file_as_string(MODELS_JSON))
	return _models


## The TMesh xml: GeometryFile, DiffuseTetxure (sic), SpecularTexture, Cullmode, SpecularPower ...
static func _read_descriptor(xml_path: String) -> Dictionary:
	if not FileAccess.file_exists(xml_path):
		return {}
	var result := {}
	var parser := XMLParser.new()
	parser.open(xml_path)
	var current := ""
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				current = parser.get_node_name()
			XMLParser.NODE_TEXT:
				var text := parser.get_node_data().strip_edges()
				if current != "" and text != "" and not result.has(current):
					result[current] = text
			XMLParser.NODE_ELEMENT_END:
				current = ""
	return result


## Standardshader.fx: diffuse albedo; Material.tga argb = (shading reduction, specular intensity, specular
## power, specular tint). Godot's spec/roughness approximate the specular term; no shadow reduction.
static func _material(xml_path: String, descriptor: Dictionary) -> StandardMaterial3D:
	if _material_cache.has(xml_path):
		return _material_cache[xml_path]
	var mat := StandardMaterial3D.new()
	var folder := xml_path.get_base_dir()
	var diffuse := str(descriptor.get("DiffuseTetxure", descriptor.get("DiffuseTexture", "")))
	if diffuse != "":
		var tex_path := _real_path(folder + "/" + diffuse)
		if ResourceLoader.exists(tex_path):
			mat.albedo_texture = load(tex_path)
	if str(descriptor.get("Cullmode", "cmCCW")) == "cmNone":
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if str(descriptor.get("TextureSemiTransparency", "False")) == "True":
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	elif float(str(descriptor.get("AlphaTestTreshold", "0")).replace(",", ".")) > 0.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = float(str(descriptor["AlphaTestTreshold"]).replace(",", "."))
	var spec_power := float(str(descriptor.get("SpecularPower", "128")).replace(",", "."))
	mat.roughness = clampf(1.0 - spec_power / 256.0, 0.3, 1.0)
	mat.metallic = 0.0
	mat.metallic_specular = clampf(float(str(descriptor.get("SpecularIntensity", "1")).replace(",", ".")) * 0.5, 0.0, 1.0)
	_material_cache[xml_path] = mat
	return mat


## Case-insensitive resolution of a res:// path against the folder listing (the originals mix cases).
static func _real_path(path: String) -> String:
	var folder := path.get_base_dir()
	if not _folder_index.has(folder):
		var index := {}
		if DirAccess.dir_exists_absolute(folder):
			for file in DirAccess.get_files_at(folder):
				var name := file.trim_suffix(".import").trim_suffix(".remap")
				index[name.to_lower()] = name
			for sub in DirAccess.get_directories_at(folder):
				index[sub.to_lower()] = sub
		_folder_index[folder] = index
	return folder + "/" + _folder_index[folder].get(path.get_file().to_lower(), path.get_file())
