// Small additive glowing particle or mesh: water drops, splash droplets and
// the specks rising off enhancement pads. Multiplies by the particle COLOR,
// so CPUParticles3D colour ramps fade it.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 glow_color : source_color = vec4(0.7, 0.82, 1.0, 1.0);
uniform float energy : hint_range(0.0, 16.0) = 1.5;
// Face the camera (use with a QuadMesh).
uniform bool billboard = false;
// 0 = solid mesh, 1 = soft round dot, 2 = crisp square speck.
uniform int shape : hint_range(0, 2) = 0;

void vertex() {
	if (billboard) {
		vec3 center = MODEL_MATRIX[3].xyz;
		float size = length(MODEL_MATRIX[0].xyz);
		vec3 world = center + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * size;
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	}
}

void fragment() {
	float a = 1.0;
	vec2 c = (UV - 0.5) * 2.0;
	if (shape == 1) {
		a = 1.0 - smoothstep(0.1, 1.0, length(c));
		a *= a;
	} else if (shape == 2) {
		float d = max(abs(c.x), abs(c.y));
		a = 1.0 - smoothstep(0.55, 0.75, d);
		a += (1.0 - smoothstep(0.0, 1.0, length(c))) * 0.25;
	}
	ALBEDO = glow_color.rgb * COLOR.rgb * energy;
	ALPHA = clamp(a * COLOR.a, 0.0, 1.0);
}
