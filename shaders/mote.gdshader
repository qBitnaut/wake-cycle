// Light-only motes (dust, rain in a beam): invisible until a light touches
// them, then they add their lit colour. Used instead of CanvasItemMaterial
// LIGHT_ONLY because the Compatibility renderer still applies the
// CanvasModulate ambient to LIGHT_ONLY items, so they showed everywhere.
shader_type canvas_item;
render_mode blend_add;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	// No albedo, so the ambient (CanvasModulate) term adds nothing.
	COLOR = vec4(0.0, 0.0, 0.0, texture(TEXTURE, UV).a * tint.a);
}

void light() {
	LIGHT = vec4(tint.rgb * LIGHT_COLOR.rgb * LIGHT_ENERGY, LIGHT_COLOR.a);
}
