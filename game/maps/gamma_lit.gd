class_name GammaLit
extends RefCounted
## Builds ShaderMaterials for game/maps/gamma_lit.gdshader, the port of the original's gamma-space lighting
## used by terrain, vegetation, decorations and unit models. Shader variants (render modes cannot be uniforms)
## are compiled once per #define set.

const SHADER_PATH := "res://game/maps/gamma_lit.gdshader"

static var _shaders: Dictionary = {}   # define list -> Shader


## options: glow / normal (Texture2D), uv_clamp, alpha_scissor, semi_transparent, cull_disabled, flip_backface,
## specular_power, specular_intensity, specular_tint, shading_reduction, glow_gain.
static func material(albedo: Texture2D, options: Dictionary = {}) -> ShaderMaterial:
	var defines: Array[String] = []
	if options.get("cull_disabled", false):
		defines.append("CULL_DISABLED")
	if options.get("flip_backface", false):
		defines.append("FLIP_BACKFACE")
	if options.get("semi_transparent", false):
		defines.append("SEMI_TRANSPARENT")
	var mat := ShaderMaterial.new()
	mat.shader = _shader(defines)
	if albedo != null:
		mat.set_shader_parameter("albedo_texture", albedo)
	var glow: Texture2D = options.get("glow")
	if glow != null:
		mat.set_shader_parameter("glow_texture", glow)
		mat.set_shader_parameter("has_glow", true)
	var normal: Texture2D = options.get("normal")
	if normal != null:
		mat.set_shader_parameter("normal_texture", normal)
		mat.set_shader_parameter("has_normal", true)
	for key in ["uv_clamp", "alpha_scissor", "specular_power", "specular_intensity", "specular_tint", "shading_reduction", "glow_gain"]:
		if options.has(key):
			mat.set_shader_parameter(key, options[key])
	return mat


static func _shader(defines: Array[String]) -> Shader:
	var key := ",".join(defines)
	if _shaders.has(key):
		return _shaders[key]
	var shader := Shader.new()
	var prefix := ""
	for d in defines:
		prefix += "#define %s\n" % d
	shader.code = prefix + FileAccess.get_file_as_string(SHADER_PATH)
	_shaders[key] = shader
	return shader


## Material queries used by the effects that re-skin a unit (spawn mesh effect, hover outline).
static func albedo_of(mat: Material) -> Texture2D:
	if mat is ShaderMaterial:
		return mat.get_shader_parameter("albedo_texture")
	if mat is BaseMaterial3D:
		return mat.albedo_texture
	return null


static func glow_of(mat: Material) -> Texture2D:
	if mat is ShaderMaterial and mat.get_shader_parameter("has_glow") == true:   # null = default false
		return mat.get_shader_parameter("glow_texture")
	if mat is BaseMaterial3D and mat.emission_enabled:
		return mat.emission_texture
	return null


static func alpha_scissor_of(mat: Material) -> float:
	if mat is ShaderMaterial:
		var value = mat.get_shader_parameter("alpha_scissor")   # null when the uniform keeps its default
		return float(value) if value != null else 0.0
	if mat is BaseMaterial3D and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		return mat.alpha_scissor_threshold
	return 0.0


static func is_semi_transparent(mat: Material) -> bool:
	if mat is ShaderMaterial:
		return mat.shader.code.begins_with("#define SEMI_TRANSPARENT") or mat.shader.code.contains("\n#define SEMI_TRANSPARENT")
	if mat is BaseMaterial3D:
		return mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
	return false
