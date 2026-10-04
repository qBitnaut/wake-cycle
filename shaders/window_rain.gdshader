// Rain seen through a window: procedural 1 px streaks in two depth layers,
// slanted by the wind. Cheap (no particles) and clipped to the rect for free.
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 rain_color : source_color = vec4(0.70, 0.80, 0.95, 1.0);
uniform float intensity = 0.35;
uniform float wind = 0.25;          // x shift per px of fall
uniform float speed = 220.0;        // px per second, near layer
uniform float density : hint_range(0.0, 1.0) = 0.5;
uniform float flash = 0.0;          // lightning brightens the streaks

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float layer(vec2 p, float spacing, float spd, float len, float seed) {
	float x = p.x + p.y * wind;
	float col = floor(x / spacing);
	if (fract(x / spacing) * spacing >= 1.0) return 0.0;
	float r = hash(col + seed);
	if (r > density) return 0.0;
	float period = len * (3.0 + hash(col * 1.7 + seed) * 5.0);
	float y = p.y - TIME * spd * (0.85 + r * 0.3) + hash(col * 3.1 + seed) * 500.0;
	float m = mod(y, period);
	return m < len ? (m + 1.0) / len : 0.0;
}

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

void fragment() {
	vec2 p = floor(local_px);
	float near = layer(p, 5.0, speed, 6.0, 1.0);
	float far = layer(p + vec2(2.0, 0.0), 3.0, speed * 0.6, 3.0, 7.0) * 0.45;
	float a = max(near, far) * intensity * (1.0 + flash * 3.0);
	COLOR = vec4(rain_color.rgb, a);
}
