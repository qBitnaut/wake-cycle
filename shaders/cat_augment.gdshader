// Cat augments, metal pass (lit, so the night tint and lamps shade it like
// the fur). TEXTURE is an augment sheet from tools/art/cat_augments.py: the
// metal art in the top half, data in the bottom half at UV + (0, 0.5)
// (B = reveal time on the shared schedule). As `reveal` runs 0..1 the
// pieces land one by one, each growing out of its emitter.
shader_type canvas_item;

uniform float reveal : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 metal = texture(TEXTURE, UV);
	vec4 d = texture(TEXTURE, UV + vec2(0.0, 0.5));
	if (metal.a < 0.5 || d.b > reveal + 0.002) {
		discard;
	}
	COLOR = metal;
}
