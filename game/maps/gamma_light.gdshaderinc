// Shared by game/maps/gamma_lit.gdshader and game/maps/build_tile.gdshader: the original's gamma-space lighting
// (see gamma_lit.gdshader for the derivation). The including shader sets v_albedo (gamma texel) and v_glow in
// fragment() and leaves ALBEDO white; light() writes the final colour.
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
