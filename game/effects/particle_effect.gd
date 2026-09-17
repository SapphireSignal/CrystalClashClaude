class_name ParticleEffect
extends Node3D
## Plays an original particle effect (assets/effects/<path>.json from tools/convert_particles.py) the way the
## engine did (docs/particles.md): emitters spawn particles that follow randomised path nodes (position, size,
## colour, rotation lerped per segment, Hermite optional), quads are oriented per frame like
## TQuadParticle.WriteToBuffer (billboard / cylindrical / fixed) and drawn as MultiMesh instances with the
## particle texture and blend mode. Lights, traces, nested effects, distortion and soft particles are skipped.

const EFFECTS_DIR := "res://assets/effects/"
const TEXTURES_DIR := "res://assets/effects/textures/"

static var _cache: Dictionary = {}
static var _texture_cache: Dictionary = {}
static var _material_cache: Dictionary = {}
static var _shaders: Dictionary = {}

## Unshaded textured quads: instance colour x texture, atlas cell from INSTANCE_CUSTOM (x, y, w, h); the blend
## mode (pbAdditive / pbLinear / pbSubtractive) is a render_mode, so one shader per mode.
const SHADER_SOURCE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, %s;
uniform sampler2D particle_texture : source_color, filter_linear_mipmap, repeat_disable;
varying vec4 tint;
varying vec4 cell;
void vertex() {
	tint = COLOR;
	cell = INSTANCE_CUSTOM;
}
void fragment() {
	vec4 tex = texture(particle_texture, cell.xy + UV * cell.zw);
	ALBEDO = tex.rgb * tint.rgb;
	ALPHA = tex.a * tint.a;
}
"""

var effect_size := 1.0
var emitting := false
var finished := false

var _data: Dictionary
var _emitters: Array = []      # EmitterState
var _rng := RandomNumberGenerator.new()
var _time_ms := 0.0
var _last_position := Vector3.INF


class Particle:
	var origin: Transform3D
	var spawn_ms: float
	var time_sum: float
	var positions: PackedVector3Array
	var tangent1: PackedVector3Array
	var tangent2: PackedVector3Array
	var fronts: PackedVector3Array
	var ups: PackedVector3Array
	var sizes: PackedVector3Array
	var rotations: PackedVector3Array
	var colors: PackedColorArray
	var times: PackedFloat32Array
	var schemes: PackedStringArray
	var atlas_rect: Color
	var alive := true


class EmitterState:
	var data: Dictionary
	var base: Transform3D
	var particles: Array = []
	var multimesh: MultiMeshInstance3D
	var interval_ms := 0.0
	var next_emit_ms := -1.0
	var emit_distance := 0.0
	var travelled := 0.0


## Loads an effect by its original path ("\White\shield_block.pfx" or "White/shield_block") at the given scale.
static func create(effect_path: String, size: float = 1.0) -> ParticleEffect:
	var rel := effect_path.replace("\\", "/").trim_prefix("/").trim_suffix(".pfx")
	var json_path := EFFECTS_DIR + rel + ".json"
	var data: Dictionary
	if _cache.has(json_path):
		data = _cache[json_path]
	else:
		if not FileAccess.file_exists(json_path):
			return null
		data = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		_cache[json_path] = data
	var effect := ParticleEffect.new()
	effect._data = data
	effect.effect_size = size
	effect.name = rel.get_file()
	return effect


func _ready() -> void:
	_rng.randomize()
	for e in _data.get("emitters", []):
		if e["type"] not in ["quad", "pointsprite"] or e["texture"]["blend"] == "distortion":
			continue
		var state := EmitterState.new()
		state.data = e
		state.base = _base_transform(_v3(e["position"]), _v3(e["front"]), _v3(e["up"]))
		state.multimesh = MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		var quad := QuadMesh.new()
		quad.size = Vector2(2, 2)
		mm.mesh = quad
		state.multimesh.multimesh = mm
		state.multimesh.material_override = _material(e["texture"])
		state.multimesh.top_level = true   # particles live in world space
		state.multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(state.multimesh)
		_emitters.append(state)
	for t in _data.get("triggers", []):
		var index: int = t["emitter"]
		for state: EmitterState in _emitters:
			if _data["emitters"].find(state.data) == index:
				if t["type"] == "interval":
					state.interval_ms = float(t["interval"])
				elif t["type"] == "distance":
					state.emit_distance = float(t["distance"])
	start()


func start() -> void:
	emitting = true
	for state: EmitterState in _emitters:
		var has_trigger := false
		for t in _data.get("triggers", []):
			if _data["emitters"].find(state.data) == t["emitter"]:
				has_trigger = true
				if t["type"] == "instant":
					_emit(state)
				elif t["type"] == "interval":
					state.next_emit_ms = _time_ms
		if not has_trigger:
			_emit(state)


## TIntervalEmissionTrigger.StopEmission: no new bursts; the node frees itself once every particle died.
func stop() -> void:
	emitting = false


func _process(delta: float) -> void:
	_time_ms += delta * 1000.0
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var moved := 0.0
	if _last_position != Vector3.INF:
		moved = global_position.distance_to(_last_position)
	_last_position = global_position
	var alive_total := 0
	for state: EmitterState in _emitters:
		if emitting and state.interval_ms > 0.0 and state.next_emit_ms >= 0.0:
			var bursts := 0
			while _time_ms >= state.next_emit_ms and bursts < 40:
				_emit(state)
				state.next_emit_ms += state.interval_ms
				bursts += 1
		if emitting and state.emit_distance > 0.0:
			state.travelled += moved
			while state.travelled >= state.emit_distance:
				state.travelled -= state.emit_distance
				_emit(state)
		alive_total += _update_particles(state, camera)
	if alive_total == 0 and not _has_running_emitter():
		finished = true
		queue_free()


func _has_running_emitter() -> bool:
	if not emitting:
		return false
	for state: EmitterState in _emitters:
		if state.interval_ms > 0.0 or state.emit_distance > 0.0:
			return true
	return false


## TParticleEmitter.Emit: Times x EmissionCount particles with the emitter's random rotation, time offset and
## an individual path (TIndividualParticlePath) in the effect's current base.
func _emit(state: EmitterState) -> void:
	var e: Dictionary = state.data
	var count: int = maxi(1, int(e["count"]))
	var times: int = maxi(1, int(e.get("times", 1)))
	var current_base := global_transform * Transform3D(Basis().scaled(Vector3.ONE * effect_size), Vector3.ZERO)
	var rot: Dictionary = e["rotation"]
	var offset: Dictionary = e["offset"]
	for iteration in times:
		for i in count:
			var factor := float(i) / float(count - 1) if count > 1 else 0.0
			var final_rot := _random_vector(rot)
			if float(rot["variance"][0]) < 0.0:
				final_rot.x = float(rot["mean"][0]) + float(rot["variance"][0]) * (factor * 2.0 - 1.0)
			if float(rot["variance"][1]) < 0.0:
				final_rot.y = float(rot["mean"][1]) + float(rot["variance"][1]) * (factor * 2.0 - 1.0)
			var rot_basis := Basis.from_euler(-final_rot, EULER_ORDER_YXZ)   # CreateRotationPitchYawRoll (DirectX sign)
			var total := times * count
			var fixed := float(i + iteration * count) / float(total - 1) if total > 1 else 0.0
			var p := Particle.new()
			p.origin = current_base * state.base * Transform3D(rot_basis, Vector3.ZERO)
			var time_offset: float
			if float(offset["variance"]) < 0.0:
				time_offset = float(offset["mean"]) + float(offset["variance"]) * (factor * 2.0 - 1.0)
			else:
				time_offset = float(offset["mean"]) + (_rng.randf() * 2.0 - 1.0) * float(offset["variance"])
			p.spawn_ms = _time_ms + time_offset
			_build_path(p, e["path"], fixed)
			var atlas: Array = e.get("atlas", [0, 0])
			if int(atlas[0]) > 0 and int(atlas[1]) > 0:
				var cx := _rng.randi_range(0, int(atlas[0]) - 1)
				var cy := _rng.randi_range(0, int(atlas[1]) - 1)
				p.atlas_rect = Color(float(cx) / atlas[0], float(cy) / atlas[1], 1.0 / atlas[0], 1.0 / atlas[1])
			else:
				p.atlas_rect = Color(0, 0, 1, 1)
			state.particles.append(p)


## TIndividualParticlePath.Create: randomise every node, chain positions relative to the previous node's
## mean, carry the previous node's size jitter, sum the path times (all but the last node).
func _build_path(p: Particle, nodes: Array, fixed: float) -> void:
	var direction := 1.0 if _rng.randi_range(0, 1) == 1 else -1.0
	var last_mean := Vector3.ZERO
	var last_size_jitter := Vector3.ZERO
	p.time_sum = 0.0
	for i in nodes.size():
		var n: Dictionary = nodes[i]
		var pos := _random_vector_special(n["position"], fixed)
		var size_mean := _v3(n["size"]["mean"])
		var size := _random_vector(n["size"])
		var rot_mean := _v3(n["rotation"]["mean"]).abs()
		var rot_var := _v3(n["rotation"]["variance"])
		var rotation := (rot_mean + Vector3(rot_var.x * _rng.randf(), rot_var.y * _rng.randf(), rot_var.z * _rng.randf()).abs()) * direction
		if i > 0:
			pos = (pos - last_mean) + p.positions[i - 1]
			if size.x >= 0.0:
				size.x = maxf(0.0, size.x + last_size_jitter.x)
			if size.y >= 0.0:
				size.y = maxf(0.0, size.y + last_size_jitter.y)
		last_mean = _v3(n["position"]["mean"])
		last_size_jitter = size - size_mean
		var t: Dictionary = n["time"]
		var path_time: float
		if float(t["variance"]) < 0.0:
			path_time = float(t["mean"]) + (fixed * 2.0 - 1.0) * float(t["variance"])
		else:
			path_time = float(t["mean"]) + (_rng.randf() * 2.0 - 1.0) * float(t["variance"])
		if i != nodes.size() - 1:
			p.time_sum += path_time
		p.positions.append(pos)
		p.tangent1.append(_random_vector_special(_vd(n["tangent1"]), fixed))
		p.tangent2.append(_random_vector_special(_vd(n["tangent2"]), fixed))
		p.fronts.append(_v3(n["front"]))
		p.ups.append(_v3(n["up"]))
		p.sizes.append(size)
		p.rotations.append(rotation)
		var c := _random_vector4(n["color"])
		p.colors.append(Color(c.x, c.y, c.z, c.w))
		p.times.append(path_time)
		p.schemes.append(str(n.get("scheme", "isLinear")))


## Per frame: TIndividualParticlePath.getCurrentParticleData + TQuadParticle.WriteToBuffer.
func _update_particles(state: EmitterState, camera: Camera3D) -> int:
	var particles: Array = state.particles
	var alive := []
	for p: Particle in particles:
		var elapsed: float = _time_ms - p.spawn_ms
		if elapsed > p.time_sum:
			continue
		alive.append(p)
	state.particles = alive
	var mm: MultiMesh = state.multimesh.multimesh
	if mm.instance_count < alive.size():
		mm.instance_count = alive.size()
	mm.visible_instance_count = alive.size()
	var cam_dir := -camera.global_transform.basis.z
	var screen_left := -camera.global_transform.basis.x
	var screen_up := camera.global_transform.basis.y
	for idx in alive.size():
		var p: Particle = alive[idx]
		var elapsed: float = maxf(0.0, _time_ms - p.spawn_ms)
		var d := _evaluate(p, elapsed)
		var origin: Transform3D = p.origin
		var position: Vector3 = origin * d["position"]
		var front: Vector3 = (origin.basis * d["front"])
		var up: Vector3 = (origin.basis * d["up"])
		var scaling: Vector3 = d["size"] * Vector3(origin.basis.x.length(), origin.basis.y.length(), origin.basis.z.length())
		if _time_ms < p.spawn_ms:
			scaling = Vector3.ZERO
		if scaling.y < 0.0:
			scaling.y = scaling.x
		var t_front: Vector3
		var t_up: Vector3
		var pointsprite: bool = state.data["type"] == "pointsprite"
		if pointsprite or (front.is_zero_approx() and up.is_zero_approx()):
			t_front = screen_left * (scaling.y / 2.0)
			t_up = screen_up * (scaling.x / 2.0)
		elif front.is_zero_approx():
			t_up = up.normalized() * (scaling.x / 2.0)
			t_front = cam_dir.cross(t_up).normalized() * (scaling.y / 2.0)
		elif up.is_zero_approx():
			t_front = front.normalized() * (scaling.y / 2.0)
			t_up = cam_dir.cross(t_front).normalized() * (scaling.x / 2.0)
		else:
			t_front = front.normalized() * (scaling.y / 2.0)
			t_up = up.normalized() * (scaling.x / 2.0)
		var normal := t_front.cross(t_up).normalized()
		var rotation: Vector3 = d["rotation"]
		if rotation.z != 0.0:
			t_front = t_front.rotated(normal, rotation.z)
			t_up = t_up.rotated(normal, rotation.z)
		if rotation.y != 0.0 and not t_up.is_zero_approx():
			t_front = t_front.rotated(t_up.normalized(), rotation.y)
			normal = normal.rotated(t_up.normalized(), rotation.y)
		if rotation.x != 0.0 and not t_front.is_zero_approx():
			normal = normal.rotated(t_front.normalized(), rotation.x)
			t_up = t_up.rotated(t_front.normalized(), rotation.x)
		# quad vertices: LeftTop = P + tFront + tUp -> basis x = -tFront (texture left at -x), y = tUp
		mm.set_instance_transform(idx, Transform3D(Basis(-t_front, t_up, normal.normalized() * 0.001 if normal.is_zero_approx() else normal), position))
		mm.set_instance_color(idx, d["color"])
		mm.set_instance_custom_data(idx, p.atlas_rect)
	return alive.size()


func _evaluate(p: Particle, elapsed: float) -> Dictionary:
	var n := p.positions.size()
	if n == 0:
		return {"position": Vector3.ZERO, "front": Vector3.ZERO, "up": Vector3.ZERO, "size": Vector3.ZERO, "rotation": Vector3.ZERO, "color": Color.WHITE}
	if elapsed <= 0.0:
		return _node_data(p, 0)
	var time := 0.0
	for i in n:
		if time > elapsed and i > 0 and p.times[i - 1] > 0.0:
			var s := 1.0 - clampf((time - elapsed) / p.times[i - 1], 0.0, 1.0)
			return _lerp_nodes(p, i - 1, i, s)
		time += p.times[i]
	return _node_data(p, n - 1)


func _node_data(p: Particle, i: int) -> Dictionary:
	return {"position": p.positions[i], "front": p.fronts[i], "up": p.ups[i], "size": p.sizes[i], "rotation": p.rotations[i], "color": p.colors[i]}


func _lerp_nodes(p: Particle, a: int, b: int, s: float) -> Dictionary:
	var scheme := p.schemes[a]
	var front := p.fronts[a].lerp(p.fronts[b], s).normalized()
	var up := p.ups[a].lerp(p.ups[b], s).normalized()
	var position: Vector3
	if scheme in ["isLinear", "isLinearTangentFront", "isLinearTangentUp"]:
		position = p.positions[a].lerp(p.positions[b], s)
		if scheme == "isLinearTangentFront":
			front = (p.positions[b] - p.positions[a]).normalized()
		elif scheme == "isLinearTangentUp":
			up = (p.positions[b] - p.positions[a]).normalized()
	else:
		position = _hermite(p.positions[a], p.positions[b], p.tangent1[a], p.tangent2[a], s)
		if scheme == "isHermiteTangentFront":
			front = _hermite_tangent(p.positions[a], p.positions[b], p.tangent1[a], p.tangent2[a], s).normalized()
		elif scheme == "isHermiteTangentUp":
			up = _hermite_tangent(p.positions[a], p.positions[b], p.tangent1[a], p.tangent2[a], s).normalized()
	return {"position": position, "front": front, "up": up, "size": p.sizes[a].lerp(p.sizes[b], s),
		"rotation": p.rotations[a].lerp(p.rotations[b], s), "color": p.colors[a].lerp(p.colors[b], s)}


static func _hermite(p0: Vector3, p1: Vector3, t0: Vector3, t1: Vector3, s: float) -> Vector3:
	var s2 := s * s
	var s3 := s2 * s
	return p0 * (2 * s3 - 3 * s2 + 1) + t0 * (s3 - 2 * s2 + s) + p1 * (-2 * s3 + 3 * s2) + t1 * (s3 - s2)


static func _hermite_tangent(p0: Vector3, p1: Vector3, t0: Vector3, t1: Vector3, s: float) -> Vector3:
	var s2 := s * s
	return p0 * (6 * s2 - 6 * s) + t0 * (3 * s2 - 4 * s + 1) + p1 * (-6 * s2 + 6 * s) + t1 * (3 * s2 - 2 * s)


## RMatrix.CreateTranslation(pos) * CreateSaveBase(front, up): columns (up x front, up, front).
static func _base_transform(position: Vector3, front: Vector3, up: Vector3) -> Transform3D:
	var f := front.normalized() if not front.is_zero_approx() else Vector3(0, 0, 1)
	var u := up.normalized() if not up.is_zero_approx() else Vector3(0, 1, 0)
	var left := u.cross(f)
	if left.is_zero_approx():
		left = Vector3(1, 0, 0)
	left = left.normalized()
	u = f.cross(left).normalized()
	return Transform3D(Basis(left, u, f), position)


func _random_vector(v: Dictionary) -> Vector3:
	var mean := _v3(v["mean"])
	var variance := _v3(v["variance"])
	if v.get("radial", false):
		return mean + _random_in_sphere(variance.x)
	return mean + Vector3((_rng.randf() * 2 - 1) * variance.x, (_rng.randf() * 2 - 1) * variance.y, (_rng.randf() * 2 - 1) * variance.z)


## GetRandomVectorSpecial: negative variances use the particle's fixed random factor (coherent sweeps).
func _random_vector_special(v: Dictionary, fixed: float) -> Vector3:
	var mean := _v3(v["mean"])
	var variance := _v3(v["variance"])
	if v.get("radial", false):
		return mean + _random_in_sphere(variance.x)
	var out := Vector3.ZERO
	for i in 3:
		var f := (fixed * 2 - 1) if variance[i] < 0.0 else (_rng.randf() * 2 - 1)
		out[i] = mean[i] + f * variance[i]
	return out


func _random_vector4(v: Dictionary) -> Vector4:
	var m: Array = v["mean"]
	var s: Array = v["variance"]
	return Vector4(float(m[0]) + (_rng.randf() * 2 - 1) * float(s[0]), float(m[1]) + (_rng.randf() * 2 - 1) * float(s[1]),
		float(m[2]) + (_rng.randf() * 2 - 1) * float(s[2]), float(m[3]) + (_rng.randf() * 2 - 1) * float(s[3]))


func _random_in_sphere(radius: float) -> Vector3:
	var v := Vector3(_rng.randf() * 2 - 1, _rng.randf() * 2 - 1, _rng.randf() * 2 - 1)
	while v.length_squared() > 1.0:
		v = Vector3(_rng.randf() * 2 - 1, _rng.randf() * 2 - 1, _rng.randf() * 2 - 1)
	return v * radius


static func _v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _vd(a: Array) -> Dictionary:
	return {"mean": a, "variance": [0.0, 0.0, 0.0]}


static func _material(texture: Dictionary) -> ShaderMaterial:
	var key := "%s|%s|%s" % [texture["file"], texture["blend"], texture.get("ignore_z", false)]
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := ShaderMaterial.new()
	var mode := "blend_mix"
	match str(texture["blend"]):
		"additive", "glow": mode = "blend_add"
		"subtractive": mode = "blend_sub"
	if not _shaders.has(mode):
		var shader := Shader.new()
		shader.code = SHADER_SOURCE % mode
		_shaders[mode] = shader
	mat.shader = _shaders[mode]
	var tex_path := TEXTURES_DIR + str(texture["file"])
	if _texture_cache.has(tex_path):
		mat.set_shader_parameter("particle_texture", _texture_cache[tex_path])
	elif ResourceLoader.exists(tex_path):
		var tex: Texture2D = load(tex_path)
		_texture_cache[tex_path] = tex
		mat.set_shader_parameter("particle_texture", tex)
	mat.render_priority = clampi(int(texture.get("draw_order", 0)), -128, 127)
	_material_cache[key] = mat
	return mat
