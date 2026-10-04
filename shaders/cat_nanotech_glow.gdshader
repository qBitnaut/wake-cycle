// The nanotech goo transformation, emissive pass: circuit veins racing from
// the feet up through the body to the eyes, the eyes igniting, sparks of
// nanotech at the rising goo front, and the flash. Unshaded and additive,
// with HDR values above 1 so the 2D glow blooms them.
//
// Same nano map and pixel grid as cat_nanotech.gdshader (see the include).
// Veins are baked one-pixel traces, so they are crisp at any zoom.
shader_type canvas_item;
render_mode unshaded, blend_add;

#include "res://shaders/cat_nanotech.gdshaderinc"

uniform float goo_level : hint_range(0.0, 1.0) = 0.0;
uniform float vein_progress : hint_range(0.0, 1.0) = 0.0;
uniform float absorb : hint_range(0.0, 1.0) = 0.0;
// Brief overall surge of the veins and eyes (the pulse before absorb, and
// the last faint flicker after it).
uniform float flash : hint_range(0.0, 4.0) = 0.0;
// Side branches glow vein_color, the trunk to the eyes vein_color_alt.
// Set both to a pad colour to tint the veins with that power.
uniform vec4 vein_color : source_color = vec4(0.12, 0.42, 1.0, 1.0);
uniform vec4 vein_color_alt : source_color = vec4(0.15, 1.0, 0.55, 1.0);
uniform vec4 eye_color : source_color = vec4(0.15, 1.0, 0.55, 1.0);
uniform vec4 rim_color : source_color = vec4(0.62, 0.72, 0.95, 1.0);
// Keep near 1: higher clips the hue (blue turns cyan); glow adds the bloom.
uniform float energy = 1.15;

float arrival(vec4 m) {
	return (m.g * 255.0 - 1.0) / 254.0;
}

bool lit_vein(vec4 m) {
	return m.g > 0.002 && m.b < 0.9 && arrival(m) <= vein_progress;
}

void fragment() {
	vec4 m = texture(TEXTURE, UV);
	vec2 fp = nano_frame_px(UV, TEXTURE_PIXEL_SIZE);
	vec3 col = vec3(0.0);
	float dim = 1.0 - smoothstep(0.0, 0.7, absorb);
	float after = flash * smoothstep(0.7, 1.0, absorb);   // the last faint flicker
	bool vein = m.g > 0.002 && m.b < 0.9;
	if (vein && arrival(m) <= vein_progress) {
		float a = arrival(m);
		// Trunk (feet to eyes) leans to vein_color_alt, side branches to
		// vein_color, both warming toward the head: two hues that stay
		// distinct through the bloom.
		float hue = (m.b > 0.55 ? 0.72 : 0.12) + 0.2 * a;
		vec3 c = mix(vein_color.rgb, vein_color_alt.rgb, clamp(hue, 0.0, 1.0));
		// The racing head is white-hot; packets of light run up behind it.
		float head = 1.0 - smoothstep(0.0, 0.07, vein_progress - a);
		float packet = pow(0.5 + 0.5 * sin((a * 5.0 - TIME * 1.6) * 6.2832), 6.0);
		float base = m.b > 0.55 ? 0.8 : 0.6;
		col = c * energy * ((base + 0.55 * packet) * dim + flash * 1.4 * dim + after * 0.6);
		col += mix(c, vec3(1.0), 0.6) * head * 1.8 * dim;
	} else if (m.b > 0.9) {
		// The eyes ignite last, flare with the pulse, and go back to yellow.
		float ig = smoothstep(0.86, 1.0, vein_progress) * (1.0 - smoothstep(0.25, 0.85, absorb));
		float flick = 0.85 + 0.15 * sin(TIME * 9.0);
		col = eye_color.rgb * (ig * 2.1 * flick + flash * 1.2 * (1.0 - absorb) + after * 0.5);
	} else if (m.a > 0.25 && nano_covered(m, fp.x, goo_level, TIME) && !nano_absorbed(fp, absorb)) {
		// Goo next to a lit vein carries a faint inner light (one pixel).
		vec2 tx = TEXTURE_PIXEL_SIZE;
		bool near = lit_vein(texture(TEXTURE, UV + vec2(tx.x, 0.0)))
			|| lit_vein(texture(TEXTURE, UV - vec2(tx.x, 0.0)))
			|| lit_vein(texture(TEXTURE, UV + vec2(0.0, tx.y)))
			|| lit_vein(texture(TEXTURE, UV - vec2(0.0, tx.y)));
		if (near) {
			col = mix(vein_color.rgb, vein_color_alt.rgb, 0.5) * 0.14 * (dim + flash);
		}
		// Nanites glinting at the front while the goo climbs.
		vec4 up = texture(TEXTURE, UV - vec2(0.0, tx.y));
		bool front = !nano_covered(up, fp.x, goo_level, TIME);
		float rising = step(0.02, goo_level) * (1.0 - step(0.98, goo_level));
		float tw = nano_hash(fp + floor(TIME * 7.0) * 1.37);
		if (front && tw > 0.84) {
			vec3 nc = mix(vein_color.rgb, vein_color_alt.rgb, nano_hash(fp * 3.1));
			col += nc * 0.9 * rising;
		}
		// Wet rim: the advancing front catches a little cool light even in
		// the dark; the silhouette top only a hint, on its highlight segments.
		if (front) {
			float seg = step(fract((fp.x + TIME * 3.0) / 9.0), 0.45);
			float k = up.a > 0.25 ? 0.12 : 0.04 * seg;
			col += mix(rim_color.rgb, vein_color.rgb, 0.35) * k * (1.0 - absorb);
		}
		// The pulse lights the whole skin for a moment.
		col += mix(vein_color.rgb, vein_color_alt.rgb, 0.5) * flash * 0.12 * dim;
	}
	COLOR = vec4(col, 1.0);
}
