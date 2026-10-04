// Shared by cat_nanotech.gdshader (the lit goo coat) and
// cat_nanotech_glow.gdshader (the emissive veins and eyes), so both passes
// agree on where the goo is, pixel for pixel.
//
// Both draw a CatNanotech overlay sprite whose frames come from the nano map
// (tools/art/cat_anchors.py). The map has the cat sheet's exact layout:
//   R  height inside the frame's opaque bounds (0 = feet, 1 = top)
//   G  vein arrival (0 = no vein, else (G * 255 - 1) / 254)
//   B  0.39 branch vein, 0.67 trunk vein, 1.0 eye
//   A  1.0 silhouette, 0.5 the one-pixel coat ring around it

const float NANO_FRAME = 100.0;

// Frame-local pixel of this fragment (integer, top-left origin). Hashes use
// it, so every effect sits on the art's pixel grid and holds still across
// the frames of an animation.
vec2 nano_frame_px(vec2 uv, vec2 texel) {
	return mod(floor(uv / texel), NANO_FRAME);
}

float nano_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float nano_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = nano_hash(i);
	float b = nano_hash(i + vec2(1.0, 0.0));
	float c = nano_hash(i + vec2(0.0, 1.0));
	float d = nano_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Goo front height (in map height units) for frame column x. Viscous wobble
// and a few climbing fingers while it rises; flat and past the top at 1.
float nano_goo_front(float x, float level, float t) {
	float rising = smoothstep(0.0, 0.08, level) * (1.0 - smoothstep(0.86, 1.0, level));
	float wob = 0.032 * sin(x * 0.61 + t * 2.1) + 0.022 * sin(x * 1.73 - t * 1.37);
	float col = floor(x * 0.5);
	float hx = nano_hash(vec2(col, 7.0));
	float finger = step(0.78, hx) * (0.05 + 0.09 * nano_hash(vec2(col, 3.0)));
	finger *= 0.65 + 0.35 * sin(t * 2.4 + hx * 40.0);
	return level * 1.2 - 0.1 + (wob + finger) * rising;
}

// True where map texel m (at column x) is under the goo.
bool nano_covered(vec4 m, float x, float level, float t) {
	return m.a > 0.25 && m.r <= nano_goo_front(x, level, t);
}

// Goo that has soaked in during absorb (0 = all goo left, 1 = none).
// Clumped value noise plus per-pixel grain, so it breaks up in patches.
bool nano_absorbed(vec2 fp, float absorb) {
	float keep = 0.6 * nano_vnoise(fp / 3.0) + 0.4 * nano_hash(fp + 0.5);
	return keep < absorb * 1.08;
}
