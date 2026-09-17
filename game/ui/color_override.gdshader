shader_type canvas_item;
// Port of the engine's COLOR_REPLACEMENT: rgb = lerp(rgb, override.rgb, override.a), alpha untouched
// (Standardshader.fx:373). Used for the GUI "BackgroundColorOverride" darken states.
uniform vec4 override_color : source_color = vec4(0.0);

void fragment() {
	COLOR.rgb = mix(COLOR.rgb, override_color.rgb, override_color.a);
}
