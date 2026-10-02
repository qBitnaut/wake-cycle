// Top plate of an enhancement pad: dark glass with a glowing rim band, a
// ticked inner ring and slow rings travelling outward. pad_color and pulse
// are driven by scripts/fx/enhancement_pad.gd.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform vec4 pad_color : source_color = vec4(0.12, 0.42, 1.0, 1.0);
uniform float energy : hint_range(0.0, 16.0) = 3.0;
// 0..1 burst from the script, synced with the pad's light.
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float radius = 0.8;
uniform vec4 plate_color : source_color = vec4(0.02, 0.025, 0.035, 1.0);
uniform float ring_speed = 0.35;

varying vec3 local_pos;

float band(float x, float a, float b, float aa) {
	return smoothstep(a - aa, a + aa, x) * (1.0 - smoothstep(b - aa, b + aa, x));
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 p = local_pos.xz / radius;
	float r = length(p);
	float aa = fwidth(r) * 1.2;
	float ang = atan(p.y, p.x) / 6.2832 + 0.5;

	float rim = band(r, 0.86, 0.97, aa);
	float inner = band(r, 0.58, 0.62, aa);
	float ticks = band(r, 0.66, 0.74, aa) * step(0.7, fract(ang * 24.0));
	float travel = fract(r - TIME * ring_speed);
	float rings = pow(travel, 10.0) * (1.0 - smoothstep(0.82, 0.86, r)) * 0.6;
	float core = (1.0 - smoothstep(0.0, 0.55, r)) * 0.08;

	float lift = 1.0 + pulse * 1.5;
	float glow = (rim * 1.0 + inner * 0.7 + ticks * 0.45 + rings + core) * lift;
	ALBEDO = plate_color.rgb;
	ROUGHNESS = 0.25;
	SPECULAR = 0.5;
	EMISSION = pad_color.rgb * glow * energy;
}
