// Soft additive light shaft for an open-capped cylinder or cone.
// Fresnel keeps the edges soft, a depth fade hides where the shaft meets
// geometry, and axis-stretched noise gives faint streaks. Driven by
// scripts/fx/moonbeam.gd, which keeps beam_length in sync with the mesh.
// The cylinder's local +Y end is the light's source (t = 0).
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/includes/fx_noise.gdshaderinc"

uniform vec4 beam_color : source_color = vec4(0.64, 0.74, 1.0, 1.0);
uniform float energy : hint_range(0.0, 8.0) = 0.5;
uniform float beam_length = 10.0;
// Higher = tighter, softer-edged core.
uniform float edge_power : hint_range(0.5, 8.0) = 2.2;
uniform float top_fade : hint_range(0.0, 1.0) = 0.1;
uniform float bottom_fade : hint_range(0.0, 1.0) = 0.5;
// Brightness kept at the far end (0 = fully faded).
uniform float tail : hint_range(0.0, 1.0) = 0.3;
uniform bool use_depth_fade = true;
uniform float depth_fade_distance : hint_range(0.01, 4.0) = 0.9;
uniform float camera_fade_distance = 1.5;
// Fog is disabled for additive blending, so distance fade stands in for it.
uniform float far_fade_distance = 55.0;
uniform float streaks : hint_range(0.0, 1.0) = 0.45;
uniform float streak_scale = 2.5;
uniform float shimmer : hint_range(0.0, 1.0) = 0.25;
uniform float shimmer_scale = 0.7;
uniform vec3 drift = vec3(0.04, -0.06, 0.03);
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

varying float along;
varying vec3 local_pos;
varying vec3 world_pos;

void vertex() {
	along = clamp(0.5 - VERTEX.y / beam_length, 0.0, 1.0);
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float core = pow(facing, edge_power);
	float ends = smoothstep(0.0, top_fade, along) * mix(tail, 1.0, 1.0 - smoothstep(1.0 - bottom_fade, 1.0, along));

	float view_dist = -VERTEX.z;
	float fade = clamp((view_dist - 0.2) / camera_fade_distance, 0.0, 1.0);
	fade *= 1.0 - smoothstep(far_fade_distance * 0.35, far_fade_distance, view_dist);
	if (use_depth_fade) {
		float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
		vec4 vp = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		float scene_dist = -vp.z / vp.w;
		fade *= clamp((scene_dist - view_dist) / depth_fade_distance, 0.0, 1.0);
	}

	// Streaks run along the axis; shimmer drifts through world space.
	vec2 around = normalize(local_pos.xz + vec2(0.0001));
	float s = fx_value_noise3(vec3(around * streak_scale, along * 1.2 + TIME * 0.02));
	float streak = mix(1.0, 0.45 + s * 1.1, streaks);
	float n = fx_value_noise3(world_pos * shimmer_scale + drift * TIME);
	float shim = mix(1.0, 0.6 + n * 0.8, shimmer);

	ALBEDO = beam_color.rgb * energy;
	ALPHA = clamp(core * ends * fade * streak * shim, 0.0, 1.0);
}
