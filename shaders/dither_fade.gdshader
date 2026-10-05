// Pixel dissolve: the item disappears art pixel by art pixel through a 4x4
// Bayer pattern, from `amount` 1 (all there) to 0 (gone). A soft sweep from
// one side makes the dissolve travel (sweep_dir in UV, 0 = uniform).
// Used to open the cat's house like a dollhouse when it steps inside.
shader_type canvas_item;

uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform vec2 sweep_dir = vec2(0.0, 0.0);

const float B[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	ivec2 p = ivec2(floor(UV / TEXTURE_PIXEL_SIZE));
	// Coarse 2x2 cells read better than single pixels at this size.
	ivec2 q = p / 2;
	float th = (B[(q.y % 4) * 4 + (q.x % 4)] + 0.5) / 16.0;
	float k = length(sweep_dir);
	float sweep = dot(UV - 0.5, sweep_dir) + 0.5 * k;  // 0..k across the item
	float a = clamp(amount * (1.0 + k) - sweep, 0.0, 1.0);
	if (th > a) {
		discard;
	}
	COLOR = c;
}
