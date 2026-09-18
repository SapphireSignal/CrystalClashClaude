// PostprocessZone.fx port (Graphics/Gameplay/Zone): composites the zone render target over the scene with
// 70 % transparency, a colour-difference border (7x7 kernel, +0.2 alpha), a procedural yellow noise pattern
// in world space and the cursor highlight (dzAll: fade to 30 % five units away from the mouse).
shader_type canvas_item;
render_mode blend_mix;

const int KERNEL_START = -3;
const int KERNEL_SIZE = 7;
const float TRANSPARENCY = 0.7;
const float BORDER_TRANSPARENCY = 0.2;
const float FADE_LENGTH = 5.0;
const float FADE_OFFSET = 0.3;
const float VALID_ALPHA = 80.0 / 255.0;   // Drop_Diffuse.tga alpha: the dynamic (valid) zone mesh is that translucent

uniform sampler2D zone_tex : filter_nearest, repeat_disable;
uniform mat4 view_projection_inverse;
uniform vec3 camera_position;
uniform vec3 mouse_pos;
uniform vec2 pixel_size;
uniform int highlight_area = 1;     // dzArea / dzAll
uniform int highlight_cursor = 1;   // dzCursor / dzAll

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float pattern(vec3 x) {
	vec3 p = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float n = p.x + p.y * 57.0 + 113.0 * p.z;
	return mix(mix(mix(hash(n + 0.0), hash(n + 1.0), f.x), mix(hash(n + 57.0), hash(n + 58.0), f.x), f.y),
		mix(mix(hash(n + 113.0), hash(n + 114.0), f.x), mix(hash(n + 170.0), hash(n + 171.0), f.x), f.y), f.z);
}

void fragment() {
	vec4 c = texture(zone_tex, UV);
	// the valid (green) fill is the translucent Drop_Diffuse mesh, the invalid fill is solid
	c.a *= mix(1.0, VALID_ALPHA, step(0.5, c.g) * step(c.r, 0.5));
	c.a *= TRANSPARENCY;

	float difference = 0.0;
	for (int i = KERNEL_START; i < KERNEL_START + KERNEL_SIZE; i++) {
		for (int j = KERNEL_START; j < KERNEL_START + KERNEL_SIZE; j++) {
			vec3 s = texture(zone_tex, UV + vec2(pixel_size.x * float(j), pixel_size.y * float(i))).rgb;
			difference += abs(s.r - c.r) + abs(s.g - c.g) + abs(s.b - c.b);
		}
	}
	difference = clamp(difference, 0.0, 1.0) * ((c.r + c.g + c.b <= 0.0) ? 0.0 : BORDER_TRANSPARENCY);
	c.a += difference;

	// unproject to the ground plane (y = 0)
	vec4 near_p = view_projection_inverse * vec4(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0, -1.0, 1.0);
	vec4 far_p = view_projection_inverse * vec4(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0, 1.0, 1.0);
	vec3 ray = far_p.xyz / far_p.w - near_p.xyz / near_p.w;
	float ray_y = (abs(ray.y) < 0.0001) ? -0.0001 : ray.y;
	vec3 world_position = camera_position + ray * (-camera_position.y / ray_y);

	c.rgb = clamp(c.rgb + vec3(1.0, 1.0, 0.0) * pattern(world_position * 80.0) * 0.2, 0.0, 1.0);

	if (highlight_cursor == 1) {
		float fade = clamp(1.0 - distance(mouse_pos, world_position) / FADE_LENGTH, 0.0, 1.0);
		c.a *= (highlight_area == 1) ? mix(fade, 1.0, FADE_OFFSET) : fade;
	} else {
		c.a *= FADE_OFFSET;
	}
	COLOR = c;
}
