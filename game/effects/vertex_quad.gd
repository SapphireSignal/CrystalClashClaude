class_name VertexQuad
extends MeshInstance3D
## TVertexQuadComponent (BaseConflict.EntityComponents.Client.Visuals.pas:1085-1140, 1829-1935): a textured
## quad of Width x Height world units (times eiModelSize) at the entity, unlit, optionally additive and tinted,
## billboarded per the ScreenSpace / CameraOriented options (game/effects/vertex_quad.gdshader). Used for lens
## flares, magic shots, souls and arrow sprites. Records come from units.json `quads` (tools/extract_units.py).

const SHADER_PATH := "res://game/effects/vertex_quad.gdshader"
const VERTEX_TEXTURES := "res://assets/effects/vertex_textures/"    # Graphics/Effects/Textures
const PARTICLE_TEXTURES := "res://assets/effects/textures/"          # Graphics/Effects/ParticleEffects
const UNITS_DIR := "res://assets/units/"                             # Graphics/Units

static var _shaders: Dictionary = {}
static var _texture_cache: Dictionary = {}


static func create(quad: Dictionary, model_size: float) -> VertexQuad:
	var texture := graphics_texture(str(quad.get("texture", "")))
	if texture == null:
		return null
	var node := VertexQuad.new()
	node.mesh = QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = _shader(bool(quad.get("additive", false)))
	mat.set_shader_parameter("albedo_texture", texture)
	var size := Vector2(float(quad.get("width", 1.0)), float(quad.get("height", 1.0))) * model_size
	mat.set_shader_parameter("size", size)
	mat.set_shader_parameter("mode", 0 if quad.get("screen_space", false) else (1 if quad.get("camera_oriented", false) else 2))
	if quad.has("color"):   # $AARRGGBB
		var c: int = int(quad["color"])
		mat.set_shader_parameter("color", Color(((c >> 16) & 255) / 255.0, ((c >> 8) & 255) / 255.0, (c & 255) / 255.0, ((c >> 24) & 255) / 255.0))
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the quad's mesh extent is irrelevant (the shader places the corners): keep it from being culled
	node.custom_aabb = AABB(Vector3(-size.x, -size.y, -size.x), Vector3(size.x, size.y, size.x) * 2.0)
	if quad.get("unit_placeholder", false):   # SetUnitPlaceholder: the quad stands on the ground
		node.position.y = size.y / 2.0
	return node


static func _shader(additive: bool) -> Shader:
	var key := "add" if additive else "mix"
	if not _shaders.has(key):
		var shader := Shader.new()
		shader.code = ("#define BLEND_ADD\n" if additive else "") + FileAccess.get_file_as_string(SHADER_PATH)
		_shaders[key] = shader
	return _shaders[key]


## A texture by its path relative to the original Graphics/ folder (`{skin}` = the default skin, file name
## case as on disk), null when it was not converted.
static func graphics_texture(rel: String) -> Texture2D:
	if rel == "":
		return null
	if _texture_cache.has(rel):
		return _texture_cache[rel]
	var path := rel.replace("\\", "/").replace("{skin}", UnitModel.DEFAULT_SKIN)
	var res := ""
	if path.begins_with("Effects/Textures/"):
		res = VERTEX_TEXTURES + path.get_file()
	elif path.begins_with("Effects/ParticleEffects/"):
		res = PARTICLE_TEXTURES + path.get_file()
	elif path.begins_with("Units/"):
		res = UNITS_DIR + path.trim_prefix("Units/")
	else:
		res = VERTEX_TEXTURES + path.get_file()
	res = UnitModel._real_path(res)
	var texture: Texture2D = load(res) if ResourceLoader.exists(res) else null
	if texture == null:
		push_warning("vertex texture missing: " + rel)
	_texture_cache[rel] = texture
	return texture
