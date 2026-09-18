// Buildgrid tile (TBuildGridManagerComponent.TTile, EntityComponents.Client.pas:507): GlowOvershoot.fx overshoot
// toward cyan while the field is in the wave rotation, plus the engine's HSV ColorAdjustment (Standardshader.fx
// COLORADJUSTMENT: hue offset wraps, saturation/value offsets clamp, AbsoluteHSV replaces a channel) used by
// ShowOccupation (green free / red occupied) and ShowInvalid (red) while a card is armed.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float overshoot = 0.0;                 // GLOW_COLOR_INTENSITY x glow
uniform vec3 bloom_color = vec3(0.27, 0.6, 0.6);
uniform float bloom = 0.0;
uniform vec3 hsv_offset = vec3(0.0);
uniform vec3 hsv_absolute = vec3(0.0);

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 adjust(vec3 rgb) {
	if (hsv_offset == vec3(0.0) && hsv_absolute == vec3(0.0)) {
		return rgb;
	}
	vec3 hsv = rgb2hsv(rgb);
	hsv = mix(hsv, hsv_offset, hsv_absolute);
	vec3 shifted = vec3(abs(fract(hsv.x + hsv_offset.x)), clamp(hsv.yz + hsv_offset.yz, 0.0, 1.0));
	hsv = mix(shifted, hsv, hsv_absolute);
	return hsv2rgb(hsv);
}

void fragment() {
	// GlowOvershoot runs before the colour adjustment (#inherited after it): the tint recolours the glow too
	ALBEDO = adjust(texture(albedo_tex, UV).rgb * (1.0 - overshoot));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = adjust(bloom_color) * bloom;
}
