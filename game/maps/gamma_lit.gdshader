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
//   CULL_DISABLED (Cullmode cmNone), FLIP_BACKFACE (sfCullAdjustNormal: Standardshader.fx:400-405 flips the normal
//   on back faces, used by the vegetation leaf shader), SEMI_TRANSPARENT (TextureSemiTransparency: the texture
//   alpha blends), UV_CLAMP (terrain chunk textures).
#ifdef CULL_DISABLED
render_mode cull_disabled, ambient_light_disabled, specular_disabled, depth_draw_opaque;
#else
render_mode ambient_light_disabled, specular_disabled, depth_draw_opaque;
#endif

// UV_CLAMP (terrain chunks): CLAMP_TO_EDGE samplers like the converter's glTF; wrapping bleeds the opposite chunk
// edge into the border at coarser mip levels and draws dark seam lines along the chunk grid.
#ifdef UV_CLAMP
uniform sampler2D albedo_texture : filter_linear_mipmap, repeat_disable;   // raw texels = gamma-space colour
uniform sampler2D glow_texture : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_disable;   // terrain NormalMap.png
#else
uniform sampler2D albedo_texture : filter_linear_mipmap, repeat_enable;   // raw texels = gamma-space colour
uniform sampler2D glow_texture : hint_default_black, filter_linear_mipmap, repeat_enable;   // GlowTexture (rgb * alpha baked)
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
#endif
uniform bool has_glow = false;
uniform bool has_normal = false;
uniform float alpha_scissor = 0.0;      // AlphaTestTreshold (0 = off)
#include "res://game/maps/gamma_light.gdshaderinc"

void fragment() {
	vec2 uv = UV;
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

