// MeshOutline.fx / rsOutline stage: the unit under the cursor gets a coloured silhouette in its team colour
// (BORDER_TEAMCOLORS, Visuals.pas:3053). Drawn as a material_overlay shell: back faces pushed out along the
// normal by ~2.5 px, alpha from the model's own texture like the original (pso.Color.a * outline_color.a).
shader_type spatial;
render_mode unshaded, cull_front, world_vertex_coords;

uniform vec4 outline_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float pixels = 2.5;

void vertex() {
	float dist = length(CAMERA_POSITION_WORLD - VERTEX);
	VERTEX += normalize(NORMAL) * dist * 0.00065 * pixels;   // ~world units per pixel at the game's FOV / 1080p
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = texture(albedo_tex, UV).a * outline_color.a;
}
