// Night sky: deep blue gradient, sparse stars and a moon placed by the first
// DirectionalLight3D (the moonlight). Static (no TIME), so the radiance map
// is only rendered once, which keeps it cheap on the web.
shader_type sky;

uniform vec4 zenith_color : source_color = vec4(0.02, 0.04, 0.1, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.13, 0.18, 0.3, 1.0);
uniform vec4 ground_color : source_color = vec4(0.03, 0.04, 0.06, 1.0);
uniform float star_density = 90.0;
uniform float star_amount : hint_range(0.0, 1.0) = 0.06;
uniform float star_energy = 1.6;
uniform vec4 moon_color : source_color = vec4(0.85, 0.9, 1.0, 1.0);
uniform float moon_size_deg = 2.2;
uniform float moon_energy = 6.0;
uniform float halo_energy = 0.5;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;
	vec3 col = mix(horizon_color.rgb, zenith_color.rgb, pow(clamp(up, 0.0, 1.0), 0.45));
	col = mix(col, ground_color.rgb, smoothstep(0.0, -0.08, up));

	// Stars: one candidate per grid cell, most cells empty.
	vec3 p = dir * star_density;
	vec3 cell = floor(p);
	float h = hash13(cell);
	if (h > 1.0 - star_amount && up > 0.02) {
		vec3 jitter = vec3(hash13(cell + 1.7), hash13(cell + 4.1), hash13(cell + 8.3)) * 0.6 + 0.2;
		float d = length(fract(p) - jitter);
		float b = 1.0 - smoothstep(0.0, 0.09, d);
		float tint = hash13(cell + 2.9);
		vec3 star_col = mix(vec3(0.7, 0.8, 1.0), vec3(1.0, 0.92, 0.8), tint);
		col += star_col * b * star_energy * (0.3 + 0.7 * fract(h * 37.0)) * smoothstep(0.02, 0.25, up);
	}

	if (LIGHT0_ENABLED) {
		float c = dot(dir, LIGHT0_DIRECTION);
		float size = cos(radians(moon_size_deg));
		float disc = smoothstep(size - 0.00004, size + 0.00004, c);
		col = mix(col, moon_color.rgb * moon_energy, disc);
		col += moon_color.rgb * halo_energy * pow(max(c, 0.0), 300.0);
		col += moon_color.rgb * halo_energy * 0.15 * pow(max(c, 0.0), 12.0);
	}
	COLOR = col;
}
