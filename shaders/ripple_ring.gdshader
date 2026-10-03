// Expanding ripple ring for a flat QuadMesh (orientation Face Y) emitted by
// CPUParticles3D. The particle's scale curve grows the ring; its colour
// ramp alpha fades it and thins the line as it spreads.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 ring_color : source_color = vec4(0.62, 0.74, 1.0, 1.0);
uniform float energy : hint_range(0.0, 8.0) = 0.6;
uniform float thickness : hint_range(0.005, 0.3) = 0.07;

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float life = COLOR.a;
	float th = thickness * (0.35 + life * 0.65);
	float ring = smoothstep(0.92 - th * 2.0, 0.92 - th * 0.5, d) * (1.0 - smoothstep(0.92 - th * 0.5, 0.92 + th * 0.3, d));
	float inner = smoothstep(0.55 - th, 0.55, d) * (1.0 - smoothstep(0.55, 0.55 + th, d)) * 0.35;
	ALBEDO = ring_color.rgb * energy;
	ALPHA = clamp((ring + inner) * life, 0.0, 1.0);
}
