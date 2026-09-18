shader_type spatial;
// TVertexWorldspaceQuad (delphi3d-engine Engine.Vertex.pas:1471-1500): a Width x Height quad at the entity, drawn
// unlit with its texture and a colour. mode 0 = ScreenSpace (Left/Up zero: camera screen axes), 1 = CameraOriented
// (Left = the entity's front, Up = camera direction x Left), 2 = fixed (Left = front, Up = the entity's up).
// GammaLit's blend variant: BLEND_ADD is prepended by VertexQuad for .Additive().
#ifdef BLEND_ADD
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add, world_vertex_coords;
#else
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, world_vertex_coords;
#endif

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform vec4 color : source_color = vec4(1.0);
uniform vec2 size = vec2(1.0, 1.0);
uniform int mode = 0;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 cam_right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 cam_up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 cam_dir = -normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 left;
	vec3 up;
	if (mode == 0) {
		left = -cam_right;
		up = cam_up;
	} else {
		left = normalize(MODEL_MATRIX[2].xyz);   // the views face their local +Z
		if (mode == 1) {
			up = normalize(cross(cam_dir, left));
		} else {
			up = normalize(MODEL_MATRIX[1].xyz);
		}
	}
	// QuadMesh: x -0.5 (u 0) .. 0.5, y 0.5 (v 0, top) .. -0.5; TL = Position + Left * w/2 + Up * h/2
	VERTEX = center - VERTEX.x * size.x * left + VERTEX.y * size.y * up;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb * color.rgb;
	ALPHA = tex.a * color.a;
}
