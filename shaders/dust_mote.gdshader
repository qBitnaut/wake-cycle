// Billboarded dust mote for CPUParticles3D. A mote only catches light while
// it drifts inside its beam: beam_inv maps world space into the beam's frame
// (source at the origin, shaft along -Y), set by scripts/fx/moonbeam.gd.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 mote_color : source_color = vec4(0.75, 0.84, 1.0, 1.0);
uniform float energy : hint_range(0.0, 8.0) = 1.6;
uniform mat4 beam_inv = mat4(1.0);
uniform float beam_length = 10.0;
uniform float radius_top = 1.0;
uniform float radius_bottom = 2.0;
uniform float wobble = 0.06;
uniform float twinkle : hint_range(0.0, 1.0) = 0.6;

varying float light_mask;

void vertex() {
	float id = float(INSTANCE_ID);
	vec3 center = MODEL_MATRIX[3].xyz;
	center += vec3(sin(TIME * 0.31 + id * 1.7), sin(TIME * 0.23 + id * 2.3) * 0.6, cos(TIME * 0.27 + id * 0.9)) * wobble;
	vec3 lp = (beam_inv * vec4(center, 1.0)).xyz;
	float t = -lp.y / beam_length;
	float r = mix(radius_top, radius_bottom, clamp(t, 0.0, 1.0));
	float radial = length(lp.xz) / max(r, 0.001);
	light_mask = (1.0 - smoothstep(0.45, 1.0, radial)) * smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.75, 1.0, t));
	float tw = 0.5 + 0.5 * sin(TIME * (1.3 + fract(id * 0.618) * 2.0) + id * 4.1);
	light_mask *= mix(1.0, tw, twinkle);

	float size = length(MODEL_MATRIX[0].xyz);
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = center + (cam_right * VERTEX.x + cam_up * VERTEX.y) * size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float dot_shape = 1.0 - smoothstep(0.15, 1.0, d);
	ALBEDO = mote_color.rgb * energy;
	ALPHA = clamp(dot_shape * dot_shape * light_mask * COLOR.a, 0.0, 1.0);
}
