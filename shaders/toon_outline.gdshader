// Inverted-hull outline. Use as next_pass of a toon material.
// Low-poly meshes have split (hard) normals, which crack a hull at every
// corner. ToonApplier can bake smoothed normals into the TANGENT channel
// (which skinning also transforms); enable use_smoothed_normals to use them.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.02, 0.03, 0.07, 1.0);
// Width in metres at reference_distance.
uniform float outline_width : hint_range(0.0, 0.2, 0.001) = 0.015;
// 0 = constant world width; 1 = constant screen width.
uniform float screen_space : hint_range(0.0, 1.0) = 0.6;
uniform float reference_distance = 6.0;
uniform bool use_smoothed_normals = false;

void vertex() {
	vec3 dir = use_smoothed_normals ? TANGENT : NORMAL;
	vec3 view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 view_dir = normalize((MODELVIEW_MATRIX * vec4(dir, 0.0)).xyz);
	float dist = max(-view_pos.z, 0.05);
	float w = outline_width * mix(1.0, clamp(dist / reference_distance, 0.4, 4.0), screen_space);
	view_pos += view_dir * w;
	POSITION = PROJECTION_MATRIX * vec4(view_pos, 1.0);
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
