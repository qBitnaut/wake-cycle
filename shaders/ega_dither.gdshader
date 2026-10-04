// EGA quantise: snaps the frame to the 16-colour EGA palette with a 4x4 Bayer
// ordered dither. Runs at the 320x180 game resolution, so each dither cell is
// one game pixel.
//
// Pair dithering keeps the hue: for each pixel it finds the 4 nearest EGA
// colours, picks the pair whose blend best matches the source, and lets the
// Bayer threshold choose between them. Night navy becomes black dithered with
// blue (as an EGA artist would draw it) instead of grey noise.
// `strength` mixes with the original so the lighting survives.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float exposure = 1.2;                           // lift the night before quantising
uniform float pair_penalty : hint_range(0.0, 1.0) = 0.12; // discourages blending far-apart colours

const vec3 EGA[16] = vec3[](
	vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.667), vec3(0.0, 0.667, 0.0), vec3(0.0, 0.667, 0.667),
	vec3(0.667, 0.0, 0.0), vec3(0.667, 0.0, 0.667), vec3(0.667, 0.333, 0.0), vec3(0.667, 0.667, 0.667),
	vec3(0.333, 0.333, 0.333), vec3(0.333, 0.333, 1.0), vec3(0.333, 1.0, 0.333), vec3(0.333, 1.0, 1.0),
	vec3(1.0, 0.333, 0.333), vec3(1.0, 0.333, 1.0), vec3(1.0, 1.0, 0.333), vec3(1.0, 1.0, 1.0)
);

const float BAYER[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

// Weighted RGB distance (green matters most, blue least).
float dist2(vec3 a, vec3 b) {
	vec3 d = a - b;
	return dot(d * d, vec3(0.3, 0.59, 0.11));
}

void fragment() {
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;
	vec3 c = clamp(src * exposure, 0.0, 1.0);
	// Four nearest palette entries (insertion into a tiny sorted list).
	int idx[4] = int[](0, 0, 0, 0);
	float best[4] = float[](1e9, 1e9, 1e9, 1e9);
	for (int i = 0; i < 16; i++) {
		float d = dist2(c, EGA[i]);
		if (d < best[3]) {
			int k = 3;
			while (k > 0 && d < best[k - 1]) {
				best[k] = best[k - 1];
				idx[k] = idx[k - 1];
				k--;
			}
			best[k] = d;
			idx[k] = i;
		}
	}
	// Best blend among the 6 pairs of those four.
	vec3 pa = EGA[idx[0]];
	vec3 pb = EGA[idx[0]];
	float pt = 0.0;
	float perr = best[0];
	for (int i = 0; i < 4; i++) {
		for (int j = i + 1; j < 4; j++) {
			vec3 a = EGA[idx[i]];
			vec3 b = EGA[idx[j]];
			vec3 ab = b - a;
			float t = clamp(dot(c - a, ab) / max(dot(ab, ab), 1e-5), 0.0, 1.0);
			float err = dist2(c, mix(a, b, t)) + pair_penalty * dist2(a, b) * 0.25;
			if (err < perr) {
				perr = err;
				pa = a;
				pb = b;
				pt = t;
			}
		}
	}
	ivec2 cell = ivec2(mod(floor(FRAGCOORD.xy), 4.0));
	float threshold = (BAYER[cell.y * 4 + cell.x] + 0.5) / 16.0;
	vec3 pick = pt > threshold ? pb : pa;
	COLOR = vec4(mix(src, pick, strength), 1.0);
}
