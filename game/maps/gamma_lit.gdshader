shader_type spatial;
// Port of the original's lighting (delphi3d-engine Standardshader.fx:486-515 forward path, identical in the
// deferred DeferredDirectionalAmbientLight.fx used by default: DeferredShading = True):
//   colour = tex * lerp(NdotL * (1 - shadow) * sun + ambient, 1, shading_reduction) + specular * light
// computed in GAMMA space (DX9-era textures and lights are never sRGB-decoded), then the Glow post adds the
// blurred glow buffer (PostEffects.fxs Glow, RenderOrder 2) and ColorCorrection (RenderOrder 10,
// PosteffectColorCorrection.fx: saturate((c - shadows) / lights) ^ midtones with 0 / 0.956 / 1.008).
// Godot lights in linear space, so this shader samples the textures raw (no source_color decode), evaluates
// the formula in gamma space inside light() (that is where the shadow term ATTENUATION lives) and converts
// the final gamma colour to linear once, so the display shows the original's value.
// Variants are selected with #define lines prepended by GammaLit (game/maps/gamma_lit.gd):
//   CULL_DISABLED (Cullmode cmNone), FLIP_BACKFACE (vegetation cards lit on both sides), SEMI_TRANSPARENT
//   (TextureSemiTransparency: the texture alpha blends).
#ifdef CULL_DISABLED
render_mode cull_disabled, ambient_light_disabled, specular_disabled, depth_draw_opaque;
#else
render_mode ambient_light_disabled, specular_disabled, depth_draw_opaque;
#endif

uniform sampler2D albedo_texture : filter_linear_mipmap, repeat_enable;   // raw texels = gamma-space colour
uniform sampler2D glow_texture : hint_default_black, filter_linear_mipmap, repeat_enable;   // GlowTexture (rgb * alpha baked)
uniform bool has_glow = false;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;   // terrain NormalMap.png
uniform bool has_normal = false;
uniform bool uv_clamp = false;          // terrain chunks: clamp to the outermost texel centres (glTF CLAMP_TO_EDGE)
uniform float alpha_scissor = 0.0;      // AlphaTestTreshold (0 = off)
// TMaterial defaults (Engine.Mesh.pas:630-633): no specular unless the mesh xml sets it.
uniform float specular_power = 128.0;
uniform float specular_intensity = 0.0;
uniform float specular_tint = 1.0;
uniform float shading_reduction = 0.0;
// Glow post gain: (GAUSS_3_ADDITIVE taps 4.94164 x Intensity 0.44)^2, see MapView.GLOW_POST_GAIN.
uniform float glow_gain = 4.73;
// TLightManager values (map .lights): Ambient = rgb * intensity (Engine.Core.pas:1009 PremultiplyAlpha),
// sun = DirectionalLightColor.rgb * .a; set by MapView from the map file.
global uniform vec3 rol_ambient;
global uniform vec3 rol_sun;

// ColorCorrection post (PostEffects.fxs: Shadows 0, Midtones 1.008, Lights 0.956)
const float CC_SHADOWS = 0.0;
const float CC_MIDTONES = 1.008;
const float CC_LIGHTS = 0.956;

varying vec3 v_albedo;   // gamma-space texel, read in light() (ALBEDO stays white: Godot multiplies DIFFUSE_LIGHT by it)
varying vec3 v_glow;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void fragment() {
	vec2 uv = UV;
	if (uv_clamp) {
		vec2 half_texel = 0.5 / vec2(textureSize(albedo_texture, 0));
		uv = clamp(uv, half_texel, 1.0 - half_texel);
	}
	vec4 tex = texture(albedo_texture, uv);
	if (alpha_scissor > 0.0 && tex.a < alpha_scissor) {
		discard;
	}
	v_albedo = tex.rgb;
	ALBEDO = vec3(1.0);
#ifdef SEMI_TRANSPARENT
	ALPHA = tex.a;
#endif
	v_glow = has_glow ? texture(glow_texture, uv).rgb : vec3(0.0);
	if (has_normal) {
		NORMAL_MAP = texture(normal_texture, uv).rgb;
	}
#ifdef FLIP_BACKFACE
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
#endif
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

// One directional light per map (both maps enable exactly one): the whole formula is evaluated here because
// the shadow factor only exists in light(). ATTENUATION = 1 - Shadowstrength for a directional light.
void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	vec3 intensity = ndotl * ATTENUATION * rol_sun;
	vec3 halfway = normalize(VIEW + LIGHT);
	vec3 specular = mix(rol_sun, v_albedo, specular_tint) * pow(max(dot(NORMAL, halfway), 0.0), specular_power) * specular_intensity;
	vec3 c = v_albedo * mix(intensity + rol_ambient, vec3(1.0), shading_reduction) + specular * intensity;
	c = min(c + v_glow * glow_gain, vec3(1.0));   // Glow post: additive, saturating (render order 2)
	c = pow(clamp((c - CC_SHADOWS) / CC_LIGHTS, 0.0, 1.0), vec3(CC_MIDTONES));   // ColorCorrection (order 10)
	DIFFUSE_LIGHT = srgb_to_linear(c);
	SPECULAR_LIGHT = vec3(0.0);
}
