shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Vegetation leaves / grass cards: alpha-tested, double-sided, lit on both sides (the back face uses the
// flipped normal). Needed because the world node is mirrored (main.gd): a plain double-sided material then
// shows the back faces with normals pointing away and the trees come out half as bright as the reference.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float alpha_scissor = 0.5;

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	if (tex.a < alpha_scissor) {
		discard;
	}
	ALBEDO = tex.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
