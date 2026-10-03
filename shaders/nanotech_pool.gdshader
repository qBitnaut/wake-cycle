// Nanotech pool: the puddle surface model, darker and oily, with faint
// circuit-like traces in electric blue and green glowing beneath the surface
// and a slow pulse spreading from the centre. Two trace layers sit at
// different parallax depths so the glow reads as under the fluid.
// Use with scripts/fx/puddle.gd like a normal puddle.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

#include "res://shaders/includes/fx_noise.gdshaderinc"
#include "res://shaders/includes/fx_water.gdshaderinc"

group_uniforms surface;
uniform vec4 fluid_color : source_color = vec4(0.006, 0.005, 0.012, 1.0);
uniform float fluid_opacity : hint_range(0.0, 1.0) = 0.96;
uniform float roughness : hint_range(0.0, 1.0) = 0.04;
uniform float fresnel_min : hint_range(0.0, 1.0) = 0.12;
// Thin-film sheen of an oily surface.
uniform float oil_sheen : hint_range(0.0, 1.0) = 0.35;

group_uniforms circuitry;
uniform vec4 color_a : source_color = vec4(0.12, 0.42, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(0.15, 1.0, 0.55, 1.0);
uniform float circuit_energy : hint_range(0.0, 16.0) = 3.5;
// Trace cell size in metres for the near and deep layers.
uniform float cell_near = 0.42;
uniform float cell_deep = 0.19;
uniform float depth_near = 0.06;
uniform float depth_deep = 0.18;
uniform float trace_width : hint_range(0.01, 0.2) = 0.045;
uniform float pulse_speed = 0.6;
uniform float pulse_spacing = 2.2;
// Faint glowing meniscus along the edge.
uniform float rim_glow : hint_range(0.0, 4.0) = 0.12;

varying vec3 local_pos;
varying vec3 world_pos;
varying vec3 cam_local;

// Grid-graph traces with pads at dead ends. Returns x = trace, y = pad.
vec2 circuit(vec2 p, float w) {
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float r = step(0.52, fx_hash12(cell + vec2(3.1, 7.7)));
	float u = step(0.62, fx_hash12(cell + vec2(11.3, 1.9)));
	float l = step(0.52, fx_hash12(cell + vec2(2.1, 7.7)));
	float d = step(0.62, fx_hash12(cell + vec2(11.3, 0.9)));
	float aa = fwidth(p.x) * 0.9;
	float hx = 1.0 - smoothstep(w - aa, w + aa, abs(f.y));
	float vy = 1.0 - smoothstep(w - aa, w + aa, abs(f.x));
	float trace = max(max(hx * r * step(0.0, f.x), hx * l * step(f.x, 0.0)),
			max(vy * u * step(0.0, f.y), vy * d * step(f.y, 0.0)));
	float links = r + u + l + d;
	float dist = length(f);
	float pad_r = w * 2.6;
	float pad = (1.0 - smoothstep(pad_r - aa, pad_r + aa, dist)) * step(0.5, links) * step(links, 1.5);
	float hole = 1.0 - smoothstep(pad_r * 0.45 - aa, pad_r * 0.45 + aa, dist);
	return vec2(trace, pad * (1.0 - hole * 0.8));
}

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cam_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
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

	// Traces beneath the surface: parallax by depth, refracted by ripples.
	vec3 v_local = normalize(cam_local - local_pos);
	vec2 par = -v_local.xz / max(v_local.y, 0.25);
	vec2 refr = slope * 0.6;
	vec2 near_c = circuit((local_pos.xz + par * depth_near + refr) / cell_near, trace_width);
	vec2 deep_c = circuit((local_pos.xz + par * depth_deep + refr) / cell_deep + 17.0, trace_width * 1.3);
	float traces = max(near_c.x, near_c.y) + max(deep_c.x, deep_c.y) * 0.3;

	float dist = length(local_pos.xz);
	float wave = pow(0.5 + 0.5 * sin(dist * pulse_spacing - TIME * pulse_speed), 6.0);
	float breathe = 0.8 + 0.2 * sin(TIME * 0.5);
	float region = smoothstep(0.3, 0.7, fx_value_noise(local_pos.xz * 0.9 + TIME * 0.03));
	vec3 glow_col = mix(color_a.rgb, color_b.rgb, region);
	vec3 glow = glow_col * traces * (0.07 * breathe + wave * 1.4) * circuit_energy;
	glow *= water * (1.0 - fresnel * 0.75);

	// Oily thin-film sheen: hue drifts with a slow swirl and viewing angle.
	float film = fx_fbm2(local_pos.xz * 1.4 + slope * 6.0 + vec2(TIME * 0.025, -TIME * 0.018));
	vec3 sheen = 0.5 + 0.5 * cos(6.2832 * (film * 1.5 + ndv * 0.6 + vec3(0.0, 0.33, 0.67)));
	sheen = mix(vec3(dot(sheen, vec3(0.333))), sheen, 0.6) * oil_sheen * fresnel * 0.25;

	float meniscus = water * (1.0 - water) * 4.0;
	vec3 edge_glow = glow_col * meniscus * rim_glow * (0.5 + wave);

	ALBEDO = fluid_color.rgb;
	ROUGHNESS = mix(0.45, roughness, water);
	SPECULAR = mix(0.2, 0.7, water);
	METALLIC = 0.0;
	EMISSION = (refl * fresnel * reflection_strength + sheen) * water + glow + edge_glow;
	ALPHA = max(water * fluid_opacity, shape.y * wet_darkening);
}
