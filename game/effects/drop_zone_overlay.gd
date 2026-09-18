class_name DropZoneOverlay
extends CanvasLayer
## TZoneRenderer port (BaseConflict.Classes.Client.pas:35): while a drop card (or an epic spell) is armed the
## drop area is painted over the ground - valid colour inside the dynamic zones (circles around the own nexus
## and lanetowers), invalid colour on the rest of the map's Drop_<Map> mesh, holes at the _Cutout mesh - then
## composited over the scene by PostprocessZone.fx (zone_post.gdshader). The zone meshes render into their own
## SubViewport from a camera that mirrors the game camera; this layer sits below the HUD (layer 0).

const ZONE_DIR := "res://assets/gameplay/Zone/"
const VALID_COLOR := Color(0.0, 1.0, 0.0, 1.0)     # coGameplayDropValidColor $FF00FF00
const INVALID_COLOR := Color(1.0, 0.0, 0.0, 1.0)   # coGameplayDropInvalidColor $FFFF0000
const GROUND_Y := 0.01

enum Mode { HIDE, AREA, CURSOR, ALL }   # EnumDropZoneMode (dzHide, dzArea, dzCursor, dzAll)

var mode: int = Mode.ALL

var _viewport: SubViewport
var _camera: Camera3D
var _world: Node3D
var _dynamic_mesh: Mesh
var _dynamic_instances: Array[MeshInstance3D] = []
var _rect: ColorRect
var _post: ShaderMaterial
var _game_camera: Camera3D
var _visible := false
static var _shader_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}


func setup(map_name: String, game_camera: Camera3D) -> void:
	layer = -1   # above the 3D scene, below the HUD's canvas layer
	_game_camera = game_camera
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = false
	_viewport.own_world_3d = true
	_viewport.world_3d = World3D.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.positional_shadow_atlas_size = 0
	add_child(_viewport)
	_camera = Camera3D.new()
	_viewport.add_child(_camera)
	_world = Node3D.new()
	_world.scale = Vector3(1, 1, -1)   # the game's mirrored World: zone meshes are in sim coordinates
	_viewport.add_child(_world)

	var base_tex := _texture("Drop_%s_Diffuse.tga" % map_name)
	var dyn_tex := _texture("Drop_Diffuse.tga")
	# render order = the original's stencil passes: mask, invalid fill, valid circles, invalid cutout, alpha erase
	_add_mesh("drop_%s" % map_name.to_lower(), "MASK", Color.BLACK, base_tex, -10)
	_add_mesh("drop_%s" % map_name.to_lower(), "FILL", INVALID_COLOR, base_tex, -8)
	_dynamic_mesh = _mesh("drop_dynamic")
	_add_mesh("drop_%s_invalid" % map_name.to_lower(), "FILL", INVALID_COLOR, base_tex, -4)
	_add_mesh("drop_%s_cutout" % map_name.to_lower(), "ERASE", Color.WHITE, base_tex, -2)
	_dyn_material = _material("FILL", VALID_COLOR, dyn_tex, -6)

	_post = ShaderMaterial.new()
	_post.shader = load("res://game/effects/zone_post.gdshader")
	_post.set_shader_parameter("zone_tex", _viewport.get_texture())
	_rect = ColorRect.new()
	_rect.material = _post
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	set_shown(false)


var _dyn_material: ShaderMaterial


## circles: Array of [Vector2 centre (sim), float radius] (eiDrawSpawnZone: the RCircle list).
func set_dynamic_zones(circles: Array) -> void:
	while _dynamic_instances.size() < circles.size():
		var mi := MeshInstance3D.new()
		mi.mesh = _dynamic_mesh
		mi.material_override = _dyn_material
		_world.add_child(mi)
		_dynamic_instances.append(mi)
	for i in _dynamic_instances.size():
		var mi := _dynamic_instances[i]
		mi.visible = i < circles.size()
		if mi.visible:
			var c: Vector2 = circles[i][0]
			mi.position = Vector3(c.x, GROUND_Y, c.y)
			mi.scale = Vector3.ONE * float(circles[i][1]) * 4.0   # FDynamic.Scale := Radius * 4


func set_shown(shown: bool) -> void:
	_visible = shown and mode != Mode.HIDE
	_rect.visible = _visible
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _visible else SubViewport.UPDATE_DISABLED


## Every frame while shown: mirror the game camera and feed the post shader (mouse_pos = ground point under
## the cursor in global space).
func update(mouse_ground_global: Vector3) -> void:
	if not _visible:
		return
	var size := _rect.get_viewport_rect().size
	if Vector2(_viewport.size) != size:
		_viewport.size = Vector2i(size)
	_camera.global_transform = _game_camera.global_transform
	_camera.fov = _game_camera.fov
	_camera.near = _game_camera.near
	_camera.far = _game_camera.far
	_camera.keep_aspect = _game_camera.keep_aspect
	var view := Projection(_game_camera.get_camera_transform().affine_inverse())
	var vp := _game_camera.get_camera_projection() * view
	_post.set_shader_parameter("view_projection_inverse", vp.inverse())
	_post.set_shader_parameter("camera_position", _game_camera.global_position)
	_post.set_shader_parameter("mouse_pos", mouse_ground_global)
	_post.set_shader_parameter("pixel_size", Vector2(1.0 / size.x, 1.0 / size.y))
	_post.set_shader_parameter("highlight_area", 1 if mode in [Mode.AREA, Mode.ALL] else 0)
	_post.set_shader_parameter("highlight_cursor", 1 if mode in [Mode.CURSOR, Mode.ALL] else 0)


func _add_mesh(name: String, pass_define: String, color: Color, tex: Texture2D, priority: int) -> void:
	var mesh := _mesh(name)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(pass_define, color, tex, priority)
	mi.position.y = GROUND_Y
	_world.add_child(mi)


static func _material(pass_define: String, color: Color, tex: Texture2D, priority: int) -> ShaderMaterial:
	if not _shader_cache.has(pass_define):
		var shader := Shader.new()
		var code: String = FileAccess.get_file_as_string("res://game/effects/zone_mesh.gdshader")
		shader.code = "#define %s\n" % pass_define + code
		_shader_cache[pass_define] = shader
	var m := ShaderMaterial.new()
	m.shader = _shader_cache[pass_define]
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("tex", tex)
	m.render_priority = priority
	return m


static func _texture(name: String) -> Texture2D:
	var path := ZONE_DIR + name
	return load(path) if ResourceLoader.exists(path) else null


static func _mesh(name: String) -> Mesh:
	if _mesh_cache.has(name):
		return _mesh_cache[name]
	var path := ZONE_DIR + name + ".glb"
	var found: Mesh = null
	if ResourceLoader.exists(path):
		var root: Node = (load(path) as PackedScene).instantiate()
		var stack: Array = [root]
		while not stack.is_empty() and found == null:
			var n: Node = stack.pop_back()
			if n is MeshInstance3D:
				found = n.mesh
			stack.append_array(n.get_children())
		root.free()
	else:
		push_warning("DropZoneOverlay: missing zone mesh " + path)
	_mesh_cache[name] = found
	return found
