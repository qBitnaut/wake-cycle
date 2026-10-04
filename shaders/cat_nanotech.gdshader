// The nanotech goo transformation, coat pass: glossy black-ink goo rising
// from the cat's feet to the tips of its ears, then soaking in.
//
// Unshaded on purpose: ink absorbs light. Lit, the vein light and the moon
// lifted the coat to the very value of the dark wall behind the cat, and in
// the close-up the cat read as glass. The colours below are final (night
// already applied): a near-black body that sits clearly under the wall,
// held by a faint wet rim, with the moonlit sheen on its tops.
//
// Drawn by CatNanotech on an overlay sprite that mirrors the cat's sprite
// frame for frame (scripts/fx/cat_nanotech.gd); TEXTURE is the cat's nano
// map, so the goo knows each frame's own height and silhouette. The coat is
// one pixel wider than the cat all round, like a skin of liquid.
//
// The emissive half (veins, eyes, sparkle) is cat_nanotech_glow.gdshader on
// a second, additive overlay.
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/cat_nanotech.gdshaderinc"

uniform float goo_level : hint_range(0.0, 1.0) = 0.0;
uniform float absorb : hint_range(0.0, 1.0) = 0.0;
// Wet black ink, a touch blue so it reads as liquid, not a hole.
uniform vec4 goo_color : source_color = vec4(0.014, 0.016, 0.03, 1.0);
// Gloss: moonlit, cool, on the top edges and the rising front.
uniform vec4 sheen_color : source_color = vec4(0.4, 0.5, 0.78, 1.0);
// The faint wet rim on every edge against air, so the silhouette holds
// against a dark wall.
uniform float rim = 0.17;

void fragment() {
	vec4 m = texture(TEXTURE, UV);
	vec2 fp = nano_frame_px(UV, TEXTURE_PIXEL_SIZE);
	if (!nano_covered(m, fp.x, goo_level, TIME) || nano_absorbed(fp, absorb)) {
		discard;
	}
	vec4 up = texture(TEXTURE, UV - vec2(0.0, TEXTURE_PIXEL_SIZE.y));
	vec4 up2 = texture(TEXTURE, UV - vec2(0.0, 2.0 * TEXTURE_PIXEL_SIZE.y));
	bool top = !nano_covered(up, fp.x, goo_level, TIME);
	// The advancing front (fur above, not air) is the wet meniscus line.
	bool front = top && up.a > 0.25;
	bool under_top = !top && !nano_covered(up2, fp.x, goo_level, TIME);
	float l = texture(TEXTURE, UV - vec2(TEXTURE_PIXEL_SIZE.x, 0.0)).a;
	float r = texture(TEXTURE, UV + vec2(TEXTURE_PIXEL_SIZE.x, 0.0)).a;
	bool side = l < 0.25 || r < 0.25;
	// Slow bands crawling upward through the ink.
	float flow = 0.5 + 0.5 * sin(fp.y * 0.9 + TIME * 3.0 + sin(fp.x * 0.37) * 2.0);
	vec3 col = goo_color.rgb * (0.8 + 0.4 * flow);
	// A reflection streak sweeps diagonally across the body every few
	// seconds: the read that says wet, not painted.
	float streak = fract((fp.x * 0.5 - fp.y + TIME * 16.0) / 70.0);
	float glint = step(0.94, fract((fp.x + fp.y - TIME * 11.0) / 29.0));
	if (front) {
		col = mix(col, sheen_color.rgb, 0.45 + 0.4 * glint);
	} else if (top) {
		// Silhouette tops: short highlights drifting along the wet edge, not
		// an outline. A glint slides along them now and then.
		float seg = step(fract((fp.x + TIME * 3.0) / 9.0), 0.45);
		col = mix(col, sheen_color.rgb, rim + 0.3 * seg + 0.45 * glint);
	} else if (side) {
		col = mix(col, sheen_color.rgb, rim * 0.8);
	} else if (under_top) {
		col = mix(col, sheen_color.rgb, 0.08);
	} else if (streak < 0.035) {
		col = mix(col, sheen_color.rgb, 0.22);
	}
	// Thinning as it soaks in: the fur shows through before it breaks up.
	float alpha = 1.0 - 0.35 * smoothstep(0.0, 0.8, absorb);
	COLOR = vec4(col, alpha);
}
