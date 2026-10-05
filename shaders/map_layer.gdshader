// World map albedo: every painted layer (far skyline, mid district, street,
// landmarks, stairs, foreground) is tinted per screen column by the time of
// day at that point of the map. The map's p runs 0 (the warehouse, night) to
// 1 (home, morning); p_left / p_right are its values at the view's edges, so
// a pan drags the whole sky of colours across the frame and the warehouse
// stays in the dark while the street ahead grows light.
// show / hide dissolve a layer in or out over a band of p through a 4x4
// Bayer pattern in art pixels (the city skyline giving way to the hills).
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D tint_lut : filter_linear, repeat_disable;
uniform float p_left = 0.0;
uniform float p_right = 1.0;
// Dissolve in from show.x to show.y (show.x < 0: always in).
uniform vec2 show = vec2(-1.0, -1.0);
// Dissolve out from hide.x to hide.y.
uniform vec2 hide = vec2(2.0, 3.0);
// Locked bonus landmarks: towards a cold grey.
uniform float grey : hint_range(0.0, 1.0) = 0.0;
uniform float brightness = 1.0;
// Rim light on the first art row under a top outline (and, weaker, the left
// one): moonlight at night, warm at sunrise. rgb = colour x strength by p.
uniform sampler2D rim_lut : filter_linear, repeat_disable;
uniform float rim = 0.0;

const float B[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float p = mix(p_left, p_right, SCREEN_UV.x);
	float vis = 1.0;
	if (show.x >= 0.0) {
		vis *= smoothstep(show.x, show.y, p);
	}
	vis *= 1.0 - smoothstep(hide.x, hide.y, p);
	if (vis < 0.999) {
		ivec2 q = ivec2(floor(UV / TEXTURE_PIXEL_SIZE));
		float th = (B[(q.y & 3) * 4 + (q.x & 3)] + 0.5) / 16.0;
		if (vis < th) {
			discard;
		}
	}
	vec3 col = c.rgb;
	if (grey > 0.0) {
		float l = dot(col, vec3(0.30, 0.59, 0.11));
		col = mix(col, vec3(l * 0.62, l * 0.66, l * 0.78), grey);
	}
	vec3 tint = texture(tint_lut, vec2(clamp(p, 0.0, 1.0), 0.5)).rgb;
	col *= tint * brightness;
	if (rim > 0.0 && c.a > 0.5) {
		vec2 tp = TEXTURE_PIXEL_SIZE;
		float up1 = texture(TEXTURE, UV - vec2(0.0, tp.y)).a;
		float up2 = texture(TEXTURE, UV - vec2(0.0, tp.y * 2.0)).a;
		float lf1 = texture(TEXTURE, UV - vec2(tp.x, 0.0)).a;
		float lf2 = texture(TEXTURE, UV - vec2(tp.x * 2.0, 0.0)).a;
		float edge = max(step(0.5, up1) * (1.0 - step(0.5, up2)), 0.55 * step(0.5, lf1) * (1.0 - step(0.5, lf2)));
		col += texture(rim_lut, vec2(clamp(p, 0.0, 1.0), 0.5)).rgb * rim * edge;
	}
	COLOR = vec4(col, c.a);
}
