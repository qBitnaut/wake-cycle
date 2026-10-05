// World map lamps and lit windows: the landmarks' *_glow sheets, drawn
// additively over the albedo, HDR so the 2D glow blooms them. They burn at
// night and go out towards morning (by the same per-column p as map_layer),
// with a slow flicker per art pixel so a row of windows is never uniform.
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float p_left = 0.0;
uniform float p_right = 1.0;
// Full strength up to off.x, gone by off.y.
uniform vec2 off = vec2(0.72, 0.9);
uniform float strength = 1.6;
uniform float flicker = 0.12;
// Locked bonus landmarks keep their lamps dim.
uniform float dim : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 v) {
	return fract(sin(dot(v, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float p = mix(p_left, p_right, SCREEN_UV.x);
	float k = 1.0 - smoothstep(off.x, off.y, p);
	vec2 cell = floor(UV / TEXTURE_PIXEL_SIZE / 6.0);
	float f = 1.0 - flicker * (0.5 + 0.5 * sin(TIME * (0.6 + hash(cell) * 1.7) + hash(cell + 3.1) * 6.28));
	COLOR = vec4(c.rgb * c.a * strength * k * f * (1.0 - dim * 0.75), 1.0);
}
