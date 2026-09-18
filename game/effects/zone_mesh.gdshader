// TZoneRenderer mesh passes (BaseConflict.Classes.Client.pas:109): flat zone meshes drawn unlit into the
// zone render target with stencil masking. One shader per pass, selected by the preprocessor define:
//   MASK   : the Drop_<Map> base mesh marks the drop area (stencil 1, no colour)
//   FILL   : any mesh inside the mask replaces the colour (invalid fill, dynamic valid circles, invalid cutout)
//   ERASE  : the _Cutout mesh zeroes the alpha inside the mask so no border is generated there
shader_type spatial;
#if defined(ERASE)
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_mul;
stencil_mode read, compare_equal, 1;
#elif defined(FILL)
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_premul_alpha;
stencil_mode read, compare_equal, 1;
#else
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_mix;
stencil_mode write, 1;
#endif

uniform vec4 color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform sampler2D tex : source_color, filter_linear;

void fragment() {
	float a = texture(tex, UV).a;
#if defined(ERASE)
	ALBEDO = vec3(1.0);
	ALPHA = 1.0 - a;   // blend_mul: rgb kept, alpha *= (1 - mesh alpha) -> 0 inside the cutout
#elif defined(FILL)
	ALBEDO = color.rgb;
	ALPHA = step(0.001, a);   // premultiplied blend with alpha 1 = replace (the original's One/Zero blend);
	                          // the dynamic mesh's own 31 % alpha is applied by zone_post.gdshader
#else
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;       // stencil only
#endif
}
