// Port of the original water (delphi3d-engine Engine/Shader/Watershader.fx, deferred path) for the
// Compatibility renderer: two scrolling wave normal maps, Fresnel towards the sky colour, depth based
// transparency and colour extinction over the scene behind the surface, the sun's sharp specular.
// Screen-space reflections / refraction ray marching and caustics are not ported (sky colour only).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D wave_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 water_color = vec3(0.177, 0.365, 0.443);
uniform vec3 sky_color = vec3(0.63, 0.73, 0.92);
uniform float roughness = 0.9;
uniform float fresnel_offset = 0.192;
uniform float water_transparency = 0.328;
uniform float depth_transparency_range = 0.48;
uniform float color_extinction_range = 52.0;
uniform float specular_power = 68.0;
uniform float specular_intensity = 0.936;
uniform float size = 224.0;
uniform vec2 texture_normalization = vec2(0.148, 0.142);
uniform vec3 sun_direction = vec3(-0.024, -0.672, -0.368);   // direction the light travels (RDirectionalMapLight)
uniform vec3 sun_color = vec3(1.0);

varying vec3 world_pos;
varying vec2 plane_uv;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	plane_uv = UV;
}

void fragment() {
	float speed = TIME / 10.0 / 3.0 / size / max(texture_normalization.x, texture_normalization.y);
	vec2 scale = 0.45 * size * texture_normalization;
	vec2 dir = normalize(vec2(1.0, 0.6));
	vec3 n1 = normalize(texture(wave_texture, (plane_uv + dir * speed * 1.35) * scale * 4.0).gbr * 2.0 - 1.0);
	vec3 n2 = normalize(texture(wave_texture, (plane_uv - dir * speed * 1.35) * scale * 3.5).gbr * 2.0 - 1.0);
	vec3 n = normalize(mix(vec3(0.0, 1.0, 0.0), normalize(n1 + n2), roughness));
	vec3 N = vec3(0.0, 1.0, 0.0);
	vec3 T = normalize(cross(vec3(1.0, -0.1, 0.0), N));
	vec3 B = normalize(cross(N, T));
	n = normalize(n.x * T + n.y * N + n.z * B);

	vec3 view = normalize(world_pos - CAMERA_POSITION_WORLD);
	float fresnel = clamp(mix(pow(1.0 - dot(n, -view), 5.0), 1.0, fresnel_offset), 0.0, 1.0);

	// distance between the surface and the scene behind it along the view ray
	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth * 2.0 - 1.0, 1.0);
	scene_view.xyz /= scene_view.w;
	float surface_z = -(VIEW_MATRIX * vec4(world_pos, 1.0)).z;
	vec3 cam_forward = -normalize(vec3(INV_VIEW_MATRIX[2].xyz));
	float depth = max(-scene_view.z - surface_z, 0.0) / max(dot(view, cam_forward), 0.2);

	float transparency = mix(0.0, 1.0 - water_transparency, clamp((depth - 0.1) / depth_transparency_range, 0.0, 1.0));
	vec3 scene_color = texture(screen_texture, SCREEN_UV).rgb;
	vec3 extinction = clamp(water_color, 0.001, 1.0);
	vec3 result = mix(scene_color, water_color, clamp(vec3(depth) / color_extinction_range / extinction, 0.0, 1.0));
	result = mix(result, sky_color, fresnel);
	result = mix(scene_color, result, transparency);

	vec3 halfway = normalize(-view - normalize(sun_direction));
	float spec = clamp((pow(clamp(dot(n, halfway), 0.0, 1.0), specular_power) - 0.8) / 0.2, 0.0, 1.0);
	result = mix(result, sun_color, spec * specular_intensity * transparency);
	ALBEDO = result;
	ALPHA = 1.0;
}
