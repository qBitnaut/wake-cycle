// Shared surface model for puddle.gdshader and nanotech_pool.gdshader:
// irregular soft-edged shape, ambient and drip ripples, and a fake
// reflection of the room (dark ceiling, roof openings and moonbeams).
// The Compatibility renderer has no SSR, so reflections are analytic:
// scripts/fx/puddle.gd feeds every moonbeam in the "moonbeams" group into
// beam_tops / beam_bottoms, and drip impacts into ripples.
// Requires fx_noise.gdshaderinc.

group_uniforms shape;
// Shape outline jitter and seed (UV space).
uniform float edge_noise : hint_range(0.0, 0.6) = 0.28;
uniform float edge_softness : hint_range(0.01, 0.5) = 0.07;
uniform float shape_seed = 0.0;
// Darkened wet ring around the water, as a fraction of the radius.
uniform float wet_margin : hint_range(0.0, 0.5) = 0.18;
uniform float wet_darkening : hint_range(0.0, 1.0) = 0.4;

group_uniforms ripples;
uniform float ambient_ripple : hint_range(0.0, 0.2) = 0.008;
uniform float ripple_strength : hint_range(0.0, 2.0) = 0.5;
uniform float ripple_speed = 0.35;
uniform float ripple_life = 1.8;
uniform int ripple_count = 0;
// xy = local position (metres), z = start time on fx_time, w = strength.
uniform vec4 ripples[6];
uniform float fx_time = 0.0;

group_uniforms reflection;
uniform float reflection_strength : hint_range(0.0, 4.0) = 1.0;
uniform vec4 ceiling_color : source_color = vec4(0.05, 0.06, 0.09, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.14, 0.18, 0.26, 1.0);
uniform vec4 opening_color : source_color = vec4(0.64, 0.74, 1.0, 1.0);
uniform float opening_energy = 2.5;
uniform float shaft_energy = 1.6;
uniform int beam_count = 0;
// xyz = world position, w = radius. Tops are the roof openings.
uniform vec4 beam_tops[6];
uniform vec4 beam_bottoms[6];
uniform vec4 beam_colors[6];

// Water shape: x = water mask, y = wet-ring mask.
vec2 fx_water_shape(vec2 uv) {
	vec2 p = (uv - 0.5) * 2.0;
	float n = fx_fbm2(p * 1.6 + shape_seed * 13.7) - 0.5;
	float r = length(p) + n * edge_noise;
	float water = 1.0 - smoothstep(1.0 - wet_margin - edge_softness, 1.0 - wet_margin, r);
	float wet = 1.0 - smoothstep(1.0 - edge_softness * 2.0, 1.0, r);
	return vec2(water, wet);
}

// Height-field slope (d/dx, d/dz) in local metres.
vec2 fx_water_slope(vec2 p, float t) {
	vec2 s = vec2(0.0);
	// Ambient: a few slow crossing swells.
	s += vec2(0.8, 0.6) * cos(dot(p, vec2(0.8, 0.6)) * 9.0 + t * 1.3);
	s += vec2(-0.5, 0.86) * cos(dot(p, vec2(-0.5, 0.86)) * 13.0 - t * 1.7) * 0.7;
	s += vec2(0.2, -0.98) * cos(dot(p, vec2(0.2, -0.98)) * 7.0 + t * 0.9) * 0.9;
	s *= ambient_ripple * (0.5 + fx_value_noise(p * 2.0 + t * 0.2));
	for (int i = 0; i < ripple_count; i++) {
		vec4 r = ripples[i];
		float age = fx_time - r.z;
		if (age < 0.0 || age > ripple_life) {
			continue;
		}
		vec2 dv = p - r.xy;
		float d = length(dv) + 0.0001;
		float x = d - age * ripple_speed;
		float env = exp(-x * x / 0.006) * pow(1.0 - age / ripple_life, 2.0) * r.w;
		s += (dv / d) * cos(x * 70.0) * env * ripple_strength;
	}
	return s;
}

// Fake reflection along world ray (ro, rd). Returns HDR colour.
vec3 fx_water_reflection(vec3 ro, vec3 rd) {
	vec3 col = mix(ceiling_color.rgb, horizon_color.rgb, pow(1.0 - clamp(rd.y, 0.0, 1.0), 4.0));
	for (int i = 0; i < beam_count; i++) {
		vec3 a = beam_tops[i].xyz;
		vec3 b = beam_bottoms[i].xyz;
		float ra = beam_tops[i].w;
		float rb = beam_bottoms[i].w;
		vec3 bc = beam_colors[i].rgb;
		// The opening: where the ray crosses the roof plane.
		if (rd.y > 0.02) {
			float th = (a.y - ro.y) / rd.y;
			vec3 h = ro + rd * th;
			float od = length(h.xz - a.xz) / max(ra, 0.01);
			col += opening_color.rgb * opening_energy * (1.0 - smoothstep(0.55, 1.05, od));
		}
		// The shaft: closest approach between the ray and the beam axis.
		vec3 v = b - a;
		vec3 w = ro - a;
		float bb = dot(rd, v);
		float cc = dot(v, v);
		float dd = dot(rd, w);
		float ee = dot(v, w);
		float den = max(cc - bb * bb, 0.0001);
		float sc = clamp((ee - bb * dd) / den, 0.0, 1.0);
		float tc = max(dot(a + v * sc - ro, rd), 0.0);
		float dist = length(ro + rd * tc - (a + v * sc));
		float rad = mix(ra, rb, sc);
		float shaft = 1.0 - smoothstep(0.0, rad * 1.6, dist);
		// Match the beam's own profile: bright under the opening, fading
		// towards the floor (see moonbeam.gdshader top/bottom fades).
		float profile = smoothstep(0.0, 0.1, sc) * mix(0.3, 1.0, 1.0 - smoothstep(0.5, 1.0, sc));
		col += bc * shaft * shaft * profile * shaft_energy;
	}
	return col;
}
