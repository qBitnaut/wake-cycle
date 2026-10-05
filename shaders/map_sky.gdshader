// World map sky, drawn over the whole view behind everything. Per screen
// column it is the sky at that point of the map: the Warped City night sky
// (stars, the city's orange haze) at the warehouse end, a violet-to-peach
// pre-dawn over the fence, the clear morning sky (home art) over the suburbs.
// The three are blended through a 4x4 Bayer pattern in game pixels, so the
// hand-off reads as dithered pixel art, never a smear.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D night_sky : filter_nearest, repeat_enable;   // 128 x 240, tiles sideways
uniform sampler2D day_sky : filter_nearest, repeat_disable;    // 640 x 330
uniform float p_left = 0.0;
uniform float p_right = 1.0;
// The view's world x at its left edge (the night sky tiles with a little parallax).
uniform float scroll = 0.0;
uniform float night_horizon = 252.0;  // view y of the night sky's bottom row
uniform float night_brightness = 1.0;
// Pre-dawn bands, top to horizon, and the sunrise version of each.
uniform vec3 dawn_top : source_color = vec3(0.16, 0.17, 0.38);
uniform vec3 dawn_mid : source_color = vec3(0.42, 0.33, 0.56);
uniform vec3 dawn_low : source_color = vec3(0.86, 0.54, 0.47);
uniform vec3 rise_top : source_color = vec3(0.30, 0.43, 0.70);
uniform vec3 rise_mid : source_color = vec3(0.67, 0.62, 0.74);
uniform vec3 rise_low : source_color = vec3(0.99, 0.80, 0.60);
// p bands: night -> pre-dawn, pre-dawn -> sunrise, sunrise -> day.
uniform vec2 to_dawn = vec2(0.48, 0.64);
uniform vec2 to_rise = vec2(0.70, 0.82);
uniform vec2 to_day = vec2(0.82, 0.94);

const float B[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

vec3 band(vec3 top, vec3 mid, vec3 low, float t) {
	return t < 0.6 ? mix(top, mid, t / 0.6) : mix(mid, low, (t - 0.6) / 0.4);
}

void fragment() {
	vec2 view = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 px = floor(SCREEN_UV * view);
	float p = mix(p_left, p_right, SCREEN_UV.x);
	ivec2 q = ivec2(px);
	float th = (B[(q.y & 3) * 4 + (q.x & 3)] + 0.5) / 16.0;
	// Night: the Warped sky tile, bottom row on the horizon.
	vec2 nuv = vec2((px.x + scroll) / 128.0, (px.y - (night_horizon - 240.0)) / 240.0);
	vec3 night = texture(night_sky, vec2(nuv.x, clamp(nuv.y, 0.002, 0.998))).rgb * night_brightness;
	// Pre-dawn to sunrise. Low sky lightens first: the bands lean, so the dawn
	// climbs up from the horizon instead of standing as a vertical wall.
	float t = clamp(px.y / (night_horizon + 10.0), 0.0, 1.0);
	p += (t - 0.55) * 0.14;
	float r = smoothstep(to_rise.x, to_rise.y, p);
	vec3 dawn = mix(band(dawn_top, dawn_mid, dawn_low, t), band(rise_top, rise_mid, rise_low, t), r);
	// Day: the Home ending's sky.
	vec3 day = texture(day_sky, vec2(px.x / 640.0, clamp(px.y / 330.0, 0.0, 0.998))).rgb;
	float a = smoothstep(to_dawn.x, to_dawn.y, p);
	float b = smoothstep(to_day.x, to_day.y, p);
	vec3 col = a > th ? dawn : night;
	col = b > th ? day : col;
	COLOR = vec4(col, 1.0);
}
