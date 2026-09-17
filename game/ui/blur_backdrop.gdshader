shader_type canvas_item;
// GUI "Blur : True" backdrop (Engine.GUI.pas RenderLayerBlur + GUIBlur.fx): the scene behind the panel is
// blurred (TTextureBlur, kernel 4) and recoloured to the panel's BlurColor: hue and saturation of the colour,
// value = (0.5 * blurred value + 0.2) * colour value. $blur-color = $FFAFFFFF (__constants.scss).

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform vec4 blur_color : source_color = vec4(0.686, 1.0, 1.0, 1.0);
uniform float spread = 2.0;   // pixels between the taps (kernel 4 ~ 2 px sigma)

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * spread;
	vec3 sum = vec3(0.0);
	float weights[3] = float[3](0.204, 0.304, 0.094);   // 5-tap gaussian per axis, separable applied as 5x5
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			float w = weights[abs(x)] * weights[abs(y)];
			sum += texture(screen, SCREEN_UV + vec2(float(x), float(y)) * px).rgb * w;
		}
	}
	vec3 orig = rgb_to_hsv(sum);
	vec3 target = rgb_to_hsv(blur_color.rgb);
	COLOR = vec4(hsv_to_rgb(vec3(target.x, target.y, (0.5 * orig.z + 0.2) * target.z)), 1.0);
}
