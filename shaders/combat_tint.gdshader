shader_type canvas_item;

// The tint color to blend toward (yellow, red, pale blue, etc.)
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// 0.0 = original sprite, 1.0 = fully replaced with tint_color.
// Typical combat values: 0.35–0.65.
uniform float tint_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// Lerp the RGB toward the tint color. Alpha stays untouched so
	// transparent pixels remain transparent.
	COLOR = vec4(mix(tex.rgb, tint_color.rgb, tint_strength), tex.a);
}
