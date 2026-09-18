class_name SpawnMeshEffect
extends Node
## TMeshEffectSpawn port (Visuals.pas:796): Modifiers/Drop.dws assigns it to every dropped unit. For the
## faction's EFFECT_TIMES the unit's meshes render through spawn_mesh.gdshader (SpawnShader_<Color>.fx) with
## progress 0..1, cull disabled, then the normal materials come back. Attach with `SpawnMeshEffect.apply(model, color)`.

const EFFECT_TIMES := {"ecColorless": 1000, "ecBlack": 2500, "ecGreen": 2500, "ecRed": 2500, "ecBlue": 1500, "ecWhite": 2500}
const MODES := {"ecWhite": 0, "ecBlack": 1, "ecGreen": 2, "ecBlue": 3, "ecColorless": 4, "ecRed": 0}
## GLOW_COLOR_MAP (Constants.Client.pas:160): the fading colour per faction.
const GLOW_COLORS := {
	"ecColorless": Color("8080A0"), "ecBlack": Color("327AA2"), "ecGreen": Color("80E92B"),
	"ecRed": Color("B83E26"), "ecBlue": Color("5BA9FF"), "ecWhite": Color("FEFF98"),
}
const MASK := "res://assets/effects/textures/SpawnMask.png"

static var _shaders: Dictionary = {}   # variant define -> Shader

var _duration_ms: int = 1000
var _elapsed_ms: float = 0.0
var _materials: Array[ShaderMaterial] = []
var _restore: Array = []   # [MeshInstance3D, surface, original material]


static func apply(model: Node3D, color: String) -> void:
	var fx := SpawnMeshEffect.new()
	fx._duration_ms = int(EFFECT_TIMES.get(color, 2500))
	var mode: int = MODES.get(color, 0)
	var fading: Color = GLOW_COLORS.get(color, Color.WHITE)
	# model_height = the transformed bounding box top (FMesh.BoundingBoxTransformed.Max.Y)
	var height := 0.0
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mi.global_transform * mi.get_aabb()
		height = maxf(height, box.end.y - model.global_position.y)
	height = maxf(height, 0.1)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var original: Material = mi.get_surface_override_material(i)
			if original == null:
				original = mi.mesh.surface_get_material(i)
			var mat := _spawn_material(original as StandardMaterial3D, mode, fading, height, model.global_position)
			if mat == null:
				continue
			fx._restore.append([mi, i, mi.get_surface_override_material(i)])
			mi.set_surface_override_material(i, mat)
			fx._materials.append(mat)
	if fx._materials.is_empty():
		fx.free()
		return
	model.add_child(fx)


static func _spawn_material(base: StandardMaterial3D, mode: int, fading: Color, height: float, origin: Vector3) -> ShaderMaterial:
	if base == null:
		return null
	var variant := ""
	if base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
		variant = "TRANSPARENT"
	elif base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		variant = "SCISSOR"
	if not _shaders.has(variant):
		var shader := Shader.new()
		var code: String = FileAccess.get_file_as_string("res://game/effects/spawn_mesh.gdshader")
		shader.code = ("#define %s\n" % variant if variant != "" else "") + code
		_shaders[variant] = shader
	var m := ShaderMaterial.new()
	m.shader = _shaders[variant]
	m.set_shader_parameter("albedo_tex", base.albedo_texture)
	m.set_shader_parameter("emission_tex", base.emission_texture if base.emission_enabled else null)
	m.set_shader_parameter("has_emission", 1.0 if base.emission_enabled and base.emission_texture != null else 0.0)
	m.set_shader_parameter("emission_gain", base.emission_energy_multiplier)
	m.set_shader_parameter("roughness", base.roughness)
	m.set_shader_parameter("specular", base.metallic_specular)
	m.set_shader_parameter("alpha_scissor", base.alpha_scissor_threshold)
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("model_height", height)
	m.set_shader_parameter("object_position", origin)
	m.set_shader_parameter("fading_color", fading)
	m.set_shader_parameter("progress", 0.0)
	if ResourceLoader.exists(MASK):
		m.set_shader_parameter("mask_tex", load(MASK))
	return m


func _process(delta: float) -> void:
	_elapsed_ms += delta * 1000.0
	var progress := clampf(_elapsed_ms / _duration_ms, 0.0, 1.0)
	for m in _materials:
		m.set_shader_parameter("progress", progress)
	if progress >= 1.0:
		for item in _restore:
			if is_instance_valid(item[0]):
				item[0].set_surface_override_material(item[1], item[2])
		queue_free()
