// Cat augments, metal pass (lit, so the night tint and lamps shade it like
// the fur). TEXTURE is an augment sheet from tools/art/cat_augments.py: the
// metal art in the top half, data in the bottom half at UV + (0, 0.5)
// (B = reveal order). Pieces grow out of their emitters as `reveal` runs.
shader_type canvas_item;

uniform float reveal : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 metal = texture(TEXTURE, UV);
	vec4 d = texture(TEXTURE, UV + vec2(0.0, 0.5));
	if (metal.a < 0.5 || d.b > reveal * 1.2 - 0.1) {
		discard;
	}
	COLOR = metal;
}
