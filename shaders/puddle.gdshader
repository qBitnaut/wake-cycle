// Dark glossy puddle for a flat PlaneMesh (local +Y up) lying on the floor.
// Soft irregular edge with a darkened wet ring, ambient and drip ripples,
// real GGX highlights from scene lights, and an analytic fake reflection of
// the room (see includes/fx_water.gdshaderinc). Use with scripts/fx/puddle.gd.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

#include "res://shaders/includes/fx_noise.gdshaderinc"
#include "res://shaders/includes/fx_water.gdshaderinc"

group_uniforms surface;
uniform vec4 water_color : source_color = vec4(0.008, 0.012, 0.02, 1.0);
uniform float water_opacity : hint_range(0.0, 1.0) = 0.9;
uniform float roughness : hint_range(0.0, 1.0) = 0.06;
uniform float fresnel_min : hint_range(0.0, 1.0) = 0.18;

varying vec3 local_pos;
varying vec3 world_pos;

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 shape = fx_water_shape(UV);
	float water = shape.x;
	if (shape.y < 0.001) {
		discard;
	}

	vec2 slope = fx_water_slope(local_pos.xz, TIME) * water;
	vec3 n_local = normalize(vec3(-slope.x, 1.0, -slope.y));
	vec3 n_world = normalize((MODEL_MATRIX * vec4(n_local, 0.0)).xyz);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - world_pos);
	float ndv = clamp(dot(n_world, to_cam), 0.0, 1.0);
	float fresnel = mix(fresnel_min, 1.0, pow(1.0 - ndv, 5.0));
	vec3 refl = fx_water_reflection(world_pos, reflect(-to_cam, n_world));

	ALBEDO = mix(water_color.rgb, water_color.rgb * 0.5, water);
	ROUGHNESS = mix(0.45, roughness, water);
	SPECULAR = mix(0.2, 0.6, water);
	METALLIC = 0.0;
	EMISSION = refl * fresnel * reflection_strength * water;
	ALPHA = max(water * water_opacity, shape.y * wet_darkening);
}
