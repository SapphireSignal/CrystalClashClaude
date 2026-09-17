class_name RangeCircle
extends MeshInstance3D
## TVertexWorldspaceCircle port (Engine.Vertex.pas:3531): a textured ring of linear segments on the ground,
## U runs along the circle (0..1 = full turn from +Z about +Y), V from the outer (0) to the inner (1) edge.
## Used by TTextureRangeIndicatorComponent (lane node capture circle, RangeLine.tga, DrawCircle(0.5), slices).

const GROUND_EPSILON := 0.01
const TEXTURES := "res://assets/effects/textures/"

var _material: StandardMaterial3D


## slices: Array of [from, to] fractions of the turn (Slice(SliceFrom, SliceTo)); [[0, 1]] = a full ring.
static func create(radius: float, thickness: float, slices: Array, texture_name: String) -> RangeCircle:
	var c := RangeCircle.new()
	var samples := 64 if radius < 20.0 else 128
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := Vector3(0, 0, radius - thickness / 2.0)
	var outer := Vector3(0, 0, radius + thickness / 2.0)
	for slice in slices:
		var from: float = slice[0]
		var to: float = slice[1]
		for i in samples - 1:
			var sample := float(i) / (samples - 1)
			var next := float(i + 1) / (samples - 1)
			if next < from or sample > to:
				continue
			sample = maxf(sample, from)
			next = minf(next, to)
			var a := sample * TAU
			var b := next * TAU
			var left_top := outer.rotated(Vector3.UP, a)
			var right_top := outer.rotated(Vector3.UP, b)
			var left_bottom := inner.rotated(Vector3.UP, a)
			var right_bottom := inner.rotated(Vector3.UP, b)
			_push(st, left_top, Vector2(sample, 0))
			_push(st, left_bottom, Vector2(sample, 1))
			_push(st, right_top, Vector2(next, 0))
			_push(st, right_top, Vector2(next, 0))
			_push(st, left_bottom, Vector2(sample, 1))
			_push(st, right_bottom, Vector2(next, 1))
	c.mesh = st.commit()
	c._material = StandardMaterial3D.new()
	c._material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	c._material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	c._material.cull_mode = BaseMaterial3D.CULL_DISABLED
	c._material.albedo_texture = load(TEXTURES + texture_name)
	c.material_override = c._material
	c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.position.y = GROUND_EPSILON
	return c


static func _push(st: SurfaceTool, v: Vector3, uv: Vector2) -> void:
	st.set_uv(uv)
	st.add_vertex(v)


func set_color(color: Color) -> void:
	_material.albedo_color = color
