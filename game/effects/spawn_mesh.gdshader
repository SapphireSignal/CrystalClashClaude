// TMeshEffectSpawn (Visuals.pas:796) = the per-faction SpawnShader_<Color>.fx (Graphics/Effects/Shader) applied
// to a dropped unit's meshes for EFFECT_TIMES ms: White rises out of a glowing mask, Black melts up from below
// and wobbles, Green falls as a seed and grows, Blue spins/scales in from above, Colorless rises and squeezes.
// Lit like the unit's normal material (albedo / glow texture); `mode` picks the faction block.
shader_type spatial;
#ifdef TRANSPARENT
render_mode cull_disabled, world_vertex_coords, depth_draw_always;
#else
render_mode cull_disabled, world_vertex_coords;
#endif

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D emission_tex : source_color, filter_linear_mipmap;
uniform sampler2D mask_tex : filter_linear_mipmap;   // SpawnMask.png (White)
uniform float has_emission = 0.0;
uniform float emission_gain = 1.0;
uniform float roughness = 0.7;
uniform float specular = 0.5;
uniform float alpha_scissor = 0.0;
uniform int mode = 0;            // 0 White, 1 Black, 2 Green, 3 Blue, 4 Colorless
uniform float progress = 0.0;    // spawn timer 0..1
uniform float model_height = 1.0;
uniform vec3 object_position = vec3(0.0);
uniform vec3 fading_color : source_color = vec3(1.0);

varying float rel_height;

float powlerp(float x) {
	float t = x - 1.0;
	return t * t * t * t * t + 1.0;
}

float cos_lerp(float x) {
	float t = (1.0 + cos(x * 3.141)) / 2.0;
	return t < 0.5 ? 4.0 * t * t * t : (t - 1.0) * (2.0 * t - 2.0) * (2.0 * t - 2.0) + 1.0;
}

void vertex() {
	vec3 wp = VERTEX;
	if (mode == 1) {   // Black: melt up (MELT_FINISH 0.6, MELT_LENGTH 3) + wobble (WOBBLE_FINISH 0.9, 4 turns)
		float melt = clamp(progress / 0.6, 0.0, 1.0);
		melt = clamp(melt / max(1.0 - clamp(wp.y / model_height, 0.0, 1.0), 0.0001), 0.0, 1.0);
		wp.y = mix(-3.0 * model_height, wp.y, melt);
		float wobble = 1.0 - clamp(progress / 0.9, 0.0, 1.0);
		vec3 lead = vec3(sin(wobble * 4.0 * 2.0 * 3.141), 0.0, cos(wobble * 4.0 * 2.0 * 3.141));
		float strength = clamp(dot(lead, normalize(NORMAL)) * 0.1 + 0.01, 0.0, 1.0);
		wp += lead * strength * wobble;
	} else if (mode == 2) {   // Green: fall (0.1) as a sphere seed (0.4), grow (0.7)
		vec3 center = object_position + vec3(0.0, 0.3, 0.0);
		vec3 between = wp - center;
		float fall = clamp(progress / 0.1, 0.0, 1.0);
		float seed = clamp((progress - 0.1) / 0.3, 0.0, 1.0);
		float grow = clamp((progress - 0.4) / 0.3, 0.0, 1.0);
		float between_factor = 1.0 / mix(length(between) / (0.15 * mix(2.0, 3.0, seed)), 1.0, powlerp(grow));
		float spawn_factor = powlerp(fall) * 0.5 + 0.5;
		float squash = (1.0 - sin(3.14159 * clamp(seed * 3.0, 0.0, 1.0))) * 0.3 + 0.7;
		wp = center + between * between_factor * spawn_factor * vec3(1.0 / squash, squash, 1.0 / squash);
		wp.y += mix(4.0, 0.0, fall);
	} else if (mode == 3) {   // Blue: spin in (ROT 0.166..0.666), scale up (0.083), drop from above
		vec3 rel = wp - object_position;
		float rot_factor = clamp(progress / 0.666 - 0.166, 0.0, 1.0);
		float rotation = cos_lerp(1.0 - clamp(rot_factor * 1.3, 0.0, 1.0)) * 2.0 * 3.141592;
		mat3 rot = mat3(vec3(cos(rotation), 0.0, -sin(rotation)), vec3(0.0, 1.0, 0.0), vec3(sin(rotation), 0.0, cos(rotation)));
		rel = rot * rel;
		float scale_progress = clamp(progress / 0.083 - 0.5, 0.0, 1.0);
		rel *= scale_progress + sin(scale_progress * 3.14159);
		wp = object_position + rel;
		wp.y += 50.0 * model_height * pow(1.0 - clamp(progress / 0.5 - 0.166, 0.0, 1.0), 5.0);
	} else if (mode == 4) {   // Colorless: rise from below (BREAK 0.4 + 0.15), squeeze (0.4 + 0.3)
		float melt = clamp((progress - 0.4) / 0.15, 0.0, 1.0);
		wp.y -= (model_height * 1.1) * (1.0 - melt);
		float squeeze = clamp((progress - 0.4) / 0.3, 0.0, 1.0);
		vec3 rel = wp - object_position;
		rel *= 0.35 * vec3(1.0, -1.0, 1.0) * -sin(squeeze * 3.14159 * 2.0) + 1.0;
		wp = object_position + rel;
	}
	rel_height = wp.y / max(model_height, 0.0001);
	VERTEX = wp;
}

void fragment() {
	vec4 albedo = texture(albedo_tex, UV);
	vec3 rgb = albedo.rgb;
	vec3 emission = has_emission > 0.5 ? texture(emission_tex, UV).rgb * emission_gain : vec3(0.0);
	if (mode == 0) {   // White: clip from the ground up (CLIP_SPEED 3.14), fade band (0.4) through SpawnMask
		float mask = texture(mask_tex, UV).r;
		float threshold = 1.0 - progress * 1.4;
		if ((1.0 - progress * 3.14) - rel_height > 0.0) {
			discard;
		}
		float value = 1.0 - clamp(-(threshold - rel_height) / 0.4 + mask, 0.0, 1.0);
		rgb = mix(rgb, fading_color, value);
		emission += fading_color * value * 0.4;
	} else if (mode == 1) {   // Black: dark until COLOR_START 0.3 .. 0.5
		rgb = mix(vec3(0.15, 0.15, 0.19), rgb, clamp((progress - 0.3) / 0.2, 0.0, 1.0));
	} else if (mode == 2) {   // Green: seed brown, glow while growing
		float glow_factor = 1.0 - clamp((progress - 0.7) / 0.3, 0.0, 1.0);
		float seed = clamp((progress - 0.1) / 0.3, 0.0, 1.0);
		rgb = mix(vec3(0.49, 0.38, 0.27), rgb, seed);
		emission += fading_color * glow_factor * 0.8 * seed;
	} else if (mode == 3) {   // Blue: tinted by the glow colour while it materialises
		float glow_factor = 1.0 - clamp(progress - 0.166, 0.0, 1.0);
		rgb = mix(rgb, fading_color, glow_factor * 0.7);
		emission += fading_color * glow_factor * 0.1;
	} else if (mode == 4) {   // Colorless: cyan crystal until COLOR_START 0.4 .. 1.0
		float color_factor = clamp((progress - 0.4) / 0.6, 0.0, 1.0);
		rgb = mix(vec3(0.24, 1.0, 1.0), rgb, color_factor);
		emission += vec3(0.24, 1.0, 1.0) * (1.0 - color_factor) * 0.3;
	}
	ALBEDO = rgb;
	EMISSION = emission;
	ROUGHNESS = roughness;
	SPECULAR = specular;
#if defined(TRANSPARENT)
	ALPHA = albedo.a;
#elif defined(SCISSOR)
	ALPHA = albedo.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
#endif
}
