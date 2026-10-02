// Shared hash and noise helpers for the Wake Cycle atmosphere shaders.
// All functions are cheap enough for the Compatibility (WebGL2) renderer.

float fx_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float fx_hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 fx_hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

vec3 fx_hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// Value noise in [0, 1].
float fx_value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = fx_hash12(i);
	float b = fx_hash12(i + vec2(1.0, 0.0));
	float c = fx_hash12(i + vec2(0.0, 1.0));
	float d = fx_hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Value noise in [0, 1], 3D.
float fx_value_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = fx_hash13(i);
	float n100 = fx_hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = fx_hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = fx_hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = fx_hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = fx_hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = fx_hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = fx_hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y),
		u.z);
}

// Gradient noise in roughly [-1, 1], 3D. Its zero set draws smooth curves,
// which is what the vein shader thresholds into lines.
float fx_gradient_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float r = 0.0;
	float n000 = dot(fx_hash33(i) * 2.0 - 1.0, f);
	float n100 = dot(fx_hash33(i + vec3(1.0, 0.0, 0.0)) * 2.0 - 1.0, f - vec3(1.0, 0.0, 0.0));
	float n010 = dot(fx_hash33(i + vec3(0.0, 1.0, 0.0)) * 2.0 - 1.0, f - vec3(0.0, 1.0, 0.0));
	float n110 = dot(fx_hash33(i + vec3(1.0, 1.0, 0.0)) * 2.0 - 1.0, f - vec3(1.0, 1.0, 0.0));
	float n001 = dot(fx_hash33(i + vec3(0.0, 0.0, 1.0)) * 2.0 - 1.0, f - vec3(0.0, 0.0, 1.0));
	float n101 = dot(fx_hash33(i + vec3(1.0, 0.0, 1.0)) * 2.0 - 1.0, f - vec3(1.0, 0.0, 1.0));
	float n011 = dot(fx_hash33(i + vec3(0.0, 1.0, 1.0)) * 2.0 - 1.0, f - vec3(0.0, 1.0, 1.0));
	float n111 = dot(fx_hash33(i + vec3(1.0, 1.0, 1.0)) * 2.0 - 1.0, f - vec3(1.0, 1.0, 1.0));
	r = mix(
		mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y),
		u.z);
	return r * 1.8;
}

// Two-octave value fbm in [0, 1].
float fx_fbm2(vec2 p) {
	float n = fx_value_noise(p) * 0.65;
	n += fx_value_noise(p * 2.13 + 7.31) * 0.35;
	return n;
}
