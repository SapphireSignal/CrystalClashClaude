class_name VertexTrace
extends MeshInstance3D
## TVertexTraceComponent + TVertexTrace (Visuals.pas:6614-6795, Engine.Vertex.pas TVertexTrace): a ribbon that
## follows the parent view. Every SamplingDistance a track point is set (with a running texture offset of
## distance / TexturePerDistance); the oldest part fades in over FadeLength (alpha and width + FadeWidening),
## the track is rolled up beyond MaxLength and by RollUpSpeed per second. Drawn unlit in world space with the
## ribbon's side vector = front x camera direction. Records come from units.json `traces`.

const VERTEX_TEXTURES := "res://assets/effects/vertex_textures/"
const MAX_NEW_TRACKS := 20

var width := 0.4
var sampling_distance := 0.5
var fade_length := 15.0
var max_length := 15.0
var texture_per_distance := 4.0
var fade_widening := 0.0
var roll_up_speed := 0.0
var color := Color.WHITE
var tracking := false

var _track: Array = []          # [world position, texture offset] oldest first; the last entry is the live pencil
var _last := Vector3.ZERO
var _texture_offset := 0.0
var _mesh := ImmediateMesh.new()


static func create(trace: Dictionary) -> VertexTrace:
	var texture := VertexQuad.graphics_texture(str(trace.get("texture", "")))
	var node := VertexTrace.new()
	node.width = float(trace.get("width", 0.4))
	node.sampling_distance = float(trace.get("sampling_distance", 0.5))
	node.fade_length = float(trace.get("fade_length", 15.0))
	node.max_length = float(trace.get("max_length", 15.0))
	node.texture_per_distance = float(trace.get("texture_per_distance", 4.0))
	node.fade_widening = float(trace.get("fade_widening", 0.0))
	node.roll_up_speed = float(trace.get("roll_up_speed", 0.0))
	if trace.has("color"):
		var c: int = int(trace["color"])
		node.color = Color(((c >> 16) & 255) / 255.0, ((c >> 8) & 255) / 255.0, (c & 255) / 255.0, ((c >> 24) & 255) / 255.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if trace.get("additive", false) else BaseMaterial3D.BLEND_MODE_MIX
	if texture != null:
		mat.albedo_texture = texture
	node.material_override = mat
	node.mesh = node._mesh
	node.top_level = true   # world space: the parent only supplies the pencil position
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-1000, -100, -1000), Vector3(2000, 200, 2000))
	return node


## StartTracking: the ribbon begins at the pencil's current position.
func activate() -> void:
	var p := _pencil()
	_track = [[p, 0.0], [p, 0.0]]
	_last = p
	_texture_offset = 0.0
	tracking = true


func deactivate() -> void:
	tracking = false


func _pencil() -> Vector3:
	var parent := get_parent() as Node3D
	return parent.global_position if parent != null else global_position


func _process(delta: float) -> void:
	if tracking:
		_set_position(_pencil())
	if roll_up_speed > 0.0:
		_roll_up(roll_up_speed * delta)
	_rebuild()


## TVertexTrace.SetPosition: fixed track points every sampling distance, the live pencil as the last point.
func _set_position(pos: Vector3) -> void:
	if _track.size() >= 2:
		_track.pop_back()   # the dynamic segment
	var added := 0
	while _last.distance_to(pos) >= sampling_distance and added < MAX_NEW_TRACKS:
		_texture_offset += sampling_distance / texture_per_distance
		var next := _last.lerp(pos, sampling_distance / _last.distance_to(pos))
		_track.append([next, _texture_offset])
		_last = next
		added += 1
	if added == MAX_NEW_TRACKS:
		_last = pos
	_track.append([pos, _texture_offset + _last.distance_to(pos) / texture_per_distance])
	var length := 0.0
	for i in range(_track.size() - 1):
		length += (_track[i][0] as Vector3).distance_to(_track[i + 1][0])
	if length > max_length:
		_roll_up(length - max_length)


## TVertexTrace.RollUp: shorten the oldest end by a distance (the dynamic segment is never removed).
func _roll_up(distance: float) -> void:
	while _track.size() > 2 and distance > 0.0:
		var a: Vector3 = _track[0][0]
		var b: Vector3 = _track[1][0]
		var segment := a.distance_to(b)
		if distance >= segment:
			distance -= segment
			_track.pop_front()
		else:
			var t := distance / segment
			_track[0] = [a.lerp(b, t), lerpf(_track[0][1], _track[1][1], t)]
			return


func _front(i: int) -> Vector3:
	var n := _track.size()
	if i == 0:
		return ((_track[1][0] as Vector3) - (_track[0][0] as Vector3)).normalized()
	if i == n - 1:
		return ((_track[n - 1][0] as Vector3) - (_track[n - 2][0] as Vector3)).normalized()
	var a := ((_track[i][0] as Vector3) - (_track[i - 1][0] as Vector3)).normalized()
	var b := ((_track[i + 1][0] as Vector3) - (_track[i][0] as Vector3)).normalized()
	if a.dot(b) < 0.0:
		a = -a
	return (a + b).normalized()


## TVertexTrace.ComputeAndSave: two triangles per segment, alpha and width fading from the oldest point.
func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _track.size() < 2:
		return
	var camera := get_viewport().get_camera_3d()
	var up := -camera.global_transform.basis.z if camera != null else Vector3.UP
	var track_length := 0.0
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(_track.size() - 1):
		var p: Vector3 = _track[i][0]
		var q: Vector3 = _track[i + 1][0]
		var alpha := clampf(track_length / fade_length, 0.0, 1.0)
		track_length += p.distance_to(q)
		var nalpha := clampf(track_length / fade_length, 0.0, 1.0)
		var half := width / 2.0 + fade_widening * (1.0 - alpha)
		var left := _front(i).cross(up) * half
		var next_left := _front(i + 1).cross(up) * half
		var ca := Color(color.r, color.g, color.b, color.a * alpha)
		var cb := Color(color.r, color.g, color.b, color.a * nalpha)
		var ta: float = _track[i][1]
		var tb: float = _track[i + 1][1]
		_vertex(p + left, ca, Vector2(0, ta))
		_vertex(p - left, ca, Vector2(1, ta))
		_vertex(q + next_left, cb, Vector2(0, tb))
		_vertex(p - left, ca, Vector2(1, ta))
		_vertex(q - next_left, cb, Vector2(1, tb))
		_vertex(q + next_left, cb, Vector2(0, tb))
	_mesh.surface_end()


func _vertex(p: Vector3, c: Color, uv: Vector2) -> void:
	_mesh.surface_set_color(c)
	_mesh.surface_set_uv(uv)
	_mesh.surface_add_vertex(p)
