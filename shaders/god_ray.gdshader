// Moonlight shaft: an additive gradient across a quad (UV.x across, UV.y along)
// with slowly scrolling noise streaks and soft edges. Unshaded, so the night
// CanvasModulate does not darken it, and bright enough to feed 2D glow.
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 ray_color : source_color = vec4(0.55, 0.68, 1.0, 1.0);
uniform float intensity = 0.35;
uniform sampler2D noise : filter_linear, repeat_enable;
uniform float streak_scale = 2.5;
uniform float scroll_speed = 0.015;
uniform float edge_softness : hint_range(0.01, 0.5) = 0.3;
uniform float fade_in : hint_range(0.0, 1.0) = 0.06;
uniform float fade_out : hint_range(0.0, 1.0) = 0.45;
uniform float flicker = 0.0;

void fragment() {
	float x = UV.x;
	float y = UV.y;
	float edge = smoothstep(0.0, edge_softness, x) * smoothstep(0.0, edge_softness, 1.0 - x);
	float along = smoothstep(0.0, fade_in, y) * (1.0 - smoothstep(1.0 - fade_out, 1.0, y));
	// Streaks run along the shaft: stretch the noise in y, drift it across x.
	float t = TIME * scroll_speed;
	float n1 = texture(noise, vec2(x * streak_scale + t, y * 0.18 - t * 0.6)).r;
	float n2 = texture(noise, vec2(x * streak_scale * 0.47 - t * 0.8, y * 0.11 + t * 0.3)).r;
	float streak = mix(0.45, 1.25, clamp(n1 * 0.6 + n2 * 0.6, 0.0, 1.0));
	float f = 1.0 + flicker * (sin(TIME * 23.0) * 0.5 + sin(TIME * 7.3) * 0.5);
	float a = edge * along * streak * intensity * f;
	COLOR = vec4(ray_color.rgb, a);
}
