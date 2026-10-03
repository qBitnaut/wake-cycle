// Wake Cycle tabby cat: lit toon shader for the player cat.
// Model: "cat toon shader" by ssombrinha570 (CC BY 4.0), recoloured from a
// black cat to a mackerel tabby so the nanotech goo and veins read on it.
//
// The model's texture is flat grey fur with black painted cel-shadow shapes.
// This shader keeps those shapes (texture luminance becomes a shade mask),
// recolours the fur, passes saturated texels (eyes, nose, inner ears, mouth,
// teeth) straight through, and adds procedural tabby stripes in bind-pose
// space so they stay on the fur while the skeleton animates.
// Lighting matches toon.gdshader: stepped diffuse bands and a back-lit rim.
//
// Needs vertex attributes baked by scripts/fx/cat_skin.gd:
//   CUSTOM0.xyz  bind-pose position in raw mesh units (nose to rump ~4.6)
//   CUSTOM1.xyz  skin region weights: x legs, y tail, z head (rest = torso)
//   CUSTOM2.xyz  bind-pose normal
// Without them every texel reads as torso at the origin, so apply the
// shader through CatSkin rather than by hand.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

#include "res://shaders/includes/fx_noise.gdshaderinc"

group_uniforms palette;
uniform vec4 fur_color : source_color = vec4(0.74, 0.52, 0.31, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.33, 0.20, 0.11, 1.0);
uniform vec4 cream_color : source_color = vec4(0.93, 0.84, 0.68, 1.0);
// The painted cel-shadow shapes multiply the local colour by this. Cream
// areas take half of it so the belly and chin stay light.
uniform vec4 shade_color : source_color = vec4(0.50, 0.52, 0.62, 1.0);
uniform float shade_strength : hint_range(0.0, 1.0) = 1.0;
// Eye rims and pupils: dark texels inside the eye zones.
uniform vec4 ink_color : source_color = vec4(0.08, 0.05, 0.04, 1.0);
// Darkens the back towards the stripe colour, as on a real tabby.
uniform float dorsal_shade : hint_range(0.0, 1.0) = 0.25;
// 0 = plain lit texture (mouth, teeth), 1 = recolour grey texels as fur.
uniform float coat_amount : hint_range(0.0, 1.0) = 1.0;
// The model's texture, bound twice: read raw (no sRGB decode) to classify
// texels (grey 0.2 = fur, black = painted shadow), and as source_color for
// the texels that pass through, so they get exactly the colour handling a
// StandardMaterial3D would give them on any renderer.
uniform sampler2D albedo_texture : filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D albedo_color_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;

group_uniforms stripes;
uniform float stripe_strength : hint_range(0.0, 1.0) = 1.0;
// Bands per raw mesh unit along the spine (the torso is ~2.6 units long).
uniform float stripe_frequency = 3.0;
// Dark fraction of each band period.
uniform float stripe_width : hint_range(0.05, 0.9) = 0.36;
uniform float stripe_softness : hint_range(0.0, 0.2) = 0.015;
// Flank stripes lean back as they run down from the spine.
uniform float stripe_sweep : hint_range(-1.0, 1.0) = 0.35;
// Noise warp of the band edges, and its frequency per raw mesh unit.
uniform float stripe_warp : hint_range(0.0, 1.0) = 0.3;
uniform float stripe_warp_scale = 1.5;
// Ragged, furry band edges.
uniform float stripe_roughness : hint_range(0.0, 0.2) = 0.05;
// Stripes narrow towards the belly (1 = taper to points).
uniform float stripe_taper : hint_range(0.0, 1.0) = 0.65;
uniform float leg_stripe_frequency = 3.4;
uniform float tail_stripe_frequency = 3.2;
// Dark tail tip, in raw mesh units from the end of the tail.
uniform float tail_tip_length = 0.32;
uniform float spine_line_width = 0.12;
// Forehead lines and cheek stripes.
uniform float head_stripe_strength : hint_range(0.0, 1.0) = 1.0;
uniform float head_stripe_frequency = 9.0;

group_uniforms body_map;
// Bind-pose landmarks for this rig (raw mesh units, +Y up, +Z forward).
uniform float back_height = 0.42;
// Stripes fade and the cream starts where the bind-pose surface turns to
// face down (normal.y): stripes are gone by stripe_fade, cream is full by
// cream_facing.
uniform float stripe_fade = -0.7;
uniform float cream_facing = -0.75;
uniform float cream_softness = 0.25;
// Tail axis in the YZ plane: root (y, z), direction and length.
uniform vec2 tail_root = vec2(0.40, -1.29);
uniform vec2 tail_dir = vec2(0.82, -0.57);
uniform float tail_length = 1.75;
// Muzzle and chin: cream in front of muzzle_z and below chin_height.
uniform float muzzle_z = 2.12;
uniform float chin_height = -0.12;
// Eye zones in UV (centre, radii) and the cream spectacles around them.
uniform vec4 eye_zone_left = vec4(0.4274, 0.3157, 0.034, 0.025);
uniform vec4 eye_zone_right = vec4(0.5200, 0.3142, 0.034, 0.025);
uniform float spectacles : hint_range(0.0, 1.0) = 0.45;

group_uniforms bands;
uniform int band_count : hint_range(1, 4) = 3;
uniform float band_softness : hint_range(0.0, 0.25) = 0.03;
// Wraps the terminator so the first band reaches round the form. A little
// more than toon.gdshader's 0.1 so the cat's flanks still read in moonlight.
uniform float wrap : hint_range(0.0, 0.5) = 0.2;
// Quantise shadows and light falloff too (see toon.gdshader).
uniform bool step_shadows = false;

group_uniforms rim;
uniform vec4 rim_color : source_color = vec4(0.62, 0.74, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 4.0) = 0.8;
// Slightly thinner than toon.gdshader's 0.3 so the rim does not wash the
// stripes off the cat's small, round forms.
uniform float rim_width : hint_range(0.0, 1.0) = 0.24;
uniform float rim_softness : hint_range(0.0, 0.5) = 0.06;
// Light-independent rim so the silhouette survives in deep shadow. Keep it
// tiny: the cat must not glow in the dark.
uniform float ambient_rim : hint_range(0.0, 1.0) = 0.03;

group_uniforms ambient;
uniform float ambient_hemisphere : hint_range(0.0, 1.0) = 0.55;

varying vec3 fur_pos;
varying vec3 region;
varying vec3 fur_normal;
varying vec3 world_normal;

float toon_steps(float x) {
	float n = float(band_count);
	float s = 0.0;
	for (int i = 1; i <= band_count; i++) {
		float t = (float(i) - 0.5) / n;
		s += smoothstep(t - band_softness, t + band_softness, x);
	}
	return s / n;
}

// 1 inside the dark part of a band; w is the dark fraction of the period.
float band(float s, float w) {
	float d = abs(fract(s) - 0.5);
	float aa = fwidth(s) * 0.75 + stripe_softness;
	return 1.0 - smoothstep(w * 0.5 - aa, w * 0.5 + aa, d);
}

float ellipse(vec2 uv, vec4 zone, float grow) {
	vec2 d = (uv - zone.xy) / (zone.zw * grow);
	return 1.0 - smoothstep(0.8, 1.0, length(d));
}

void vertex() {
	fur_pos = CUSTOM0.xyz;
	region = CUSTOM1.xyz;
	fur_normal = CUSTOM2.xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Stripe, cream and dorsal-shade coverage (0..1) for a bind-pose point.
vec3 tabby_marks(vec3 p, vec3 n) {
	float legs = clamp(region.x, 0.0, 1.0);
	float tail = clamp(region.y, 0.0, 1.0);
	float head = clamp(region.z, 0.0, 1.0);
	float body = clamp(1.0 - legs - tail - head, 0.0, 1.0);

	vec3 q = p * stripe_warp_scale;
	float warp = (fx_value_noise3(q) - 0.5) + 0.5 * (fx_value_noise3(q * 2.17 + 11.3) - 0.5);
	float rough = (fx_value_noise3(p * 14.0 + 3.7) - 0.5) * stripe_roughness;
	// Band width wanders along each stripe.
	float wobble = 0.7 + 0.6 * fx_value_noise3(p * 2.3 + 5.1);
	// 1 on the back and flanks, 0 where the surface faces the floor.
	float flank = smoothstep(stripe_fade, stripe_fade + 0.55, n.y + warp * 0.2);

	// Torso: bands round the body, leaning back as they run down the flank.
	// On the chest and rump, which face along the spine, they turn into
	// horizontal bands so they do not pool into one blot.
	float drop = max(back_height - p.y, 0.0);
	// Left and right flanks are half a band out of step, so the bands
	// alternate off the spine (fishbone) instead of forming a ladder.
	float side = smoothstep(-0.06, 0.06, p.x) * 0.5 / stripe_frequency;
	float s_ring = p.z + stripe_sweep * drop + side;
	float cap = smoothstep(0.55, 0.9, abs(n.z));
	float s_torso = (mix(s_ring, -p.y * 0.9, cap) + warp * stripe_warp + rough) * stripe_frequency;
	float m_torso = band(s_torso, stripe_width * wobble * mix(1.0, flank, stripe_taper)) * flank;
	// Dark line along the spine that the bands hang from.
	float top = smoothstep(0.5, 0.8, n.y) * smoothstep(back_height - 0.5, back_height - 0.2, p.y);
	float spine = (1.0 - smoothstep(spine_line_width, spine_line_width + 0.04, abs(p.x + warp * 0.08))) * top;
	m_torso = max(m_torso, spine);

	// Legs: horizontal bars, stopping short of the paws.
	float s_leg = (p.y + warp * stripe_warp * 0.7 + rough) * leg_stripe_frequency;
	float m_leg = band(s_leg, stripe_width * wobble) * smoothstep(-1.5, -1.32, p.y) * flank;

	// Tail: rings along its axis and a dark tip.
	float t = dot(p.yz - tail_root, normalize(tail_dir));
	float s_tail = (t + warp * stripe_warp * 0.5 + rough) * tail_stripe_frequency;
	float tip = smoothstep(tail_length - tail_tip_length - 0.03, tail_length - tail_tip_length + 0.03, t);
	float m_tail = max(band(s_tail, stripe_width * 1.1), tip);

	// Head: forehead lines between the ears and a cheek stripe back from
	// the eyes. Rings carry on down the neck from the torso.
	float brow = smoothstep(0.05, 0.2, p.y) * (1.0 - smoothstep(0.2, 0.28, abs(p.x)));
	brow *= smoothstep(1.62, 1.75, p.z) * (1.0 - smoothstep(2.12, 2.2, p.z));
	float m_brow = band((p.x + warp * 0.03) * head_stripe_frequency + 0.5, 0.32) * brow;
	float cheek = smoothstep(0.3, 0.4, abs(p.x)) * (1.0 - smoothstep(1.95, 2.1, p.z));
	float s_cheek = (p.y - (p.z - 1.6) * 0.45 + warp * 0.05) * head_stripe_frequency * 0.55;
	float m_cheek = band(s_cheek, 0.3) * cheek * smoothstep(-0.25, -0.1, p.y);
	float m_head = max(m_brow, m_cheek) * head_stripe_strength;

	float m = m_torso * body + m_leg * legs + m_tail * tail + m_head * head;

	// Cream belly and chest, muzzle and chin.
	float under = 1.0 - smoothstep(cream_facing, cream_facing + cream_softness, n.y + warp * 0.25);
	float chest = smoothstep(0.3, 0.6, n.z) * (1.0 - smoothstep(-0.3, 0.0, p.y + warp * 0.1));
	float cream = max(under, chest) * body;
	float muzzle = smoothstep(muzzle_z - 0.06, muzzle_z + 0.06, p.z) * (1.0 - smoothstep(0.02, 0.12, p.y));
	float chin = 1.0 - smoothstep(chin_height - 0.06, chin_height + 0.06, p.y);
	cream = max(cream, max(muzzle, chin) * head);
	float dorsal = smoothstep(0.4, 0.8, n.y) * body;
	return vec3(m * (1.0 - cream) * stripe_strength, cream, dorsal);
}

void fragment() {
	// The tiny +Y keeps unbaked meshes (CUSTOM2 = 0) from normalising zero.
	vec3 n = normalize(fur_normal + vec3(0.0, 1e-5, 0.0));
	vec3 marks = tabby_marks(fur_pos, n);

	vec2 uv = UV;
	float eye = max(ellipse(uv, eye_zone_left, 1.0), ellipse(uv, eye_zone_right, 1.0));
	float ring = max(ellipse(uv, eye_zone_left, 1.55), ellipse(uv, eye_zone_right, 1.55));
	float cream = max(marks.y, ring * spectacles);

	vec3 fur = mix(fur_color.rgb, stripe_color.rgb, marks.z * dorsal_shade);
	fur = mix(fur, stripe_color.rgb, marks.x * (1.0 - cream));
	fur = mix(fur, cream_color.rgb, cream);

	// Painted shading from the source texture.
	vec3 raw = texture(albedo_texture, uv).rgb;
	float hi = max(max(raw.r, raw.g), raw.b);
	float lo = min(min(raw.r, raw.g), raw.b);
	float luma = dot(raw, vec3(0.299, 0.587, 0.114));
	float keep = max(smoothstep(0.07, 0.13, hi - lo), smoothstep(0.4, 0.55, luma));
	float lit_paint = smoothstep(0.04, 0.16, luma);
	vec3 shade = mix(vec3(1.0), shade_color.rgb, shade_strength * (1.0 - 0.5 * cream));
	vec3 coat = fur * mix(shade, vec3(1.0), lit_paint);
	coat = mix(coat, ink_color.rgb, eye * (1.0 - lit_paint));
	vec3 col = mix(texture(albedo_color_texture, uv).rgb, coat, (1.0 - keep) * coat_amount);

	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	AO = mix(1.0 - ambient_hemisphere, 1.0, clamp(world_normal.y * 0.5 + 0.5, 0.0, 1.0));
	AO_LIGHT_AFFECT = 0.0;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float amb_rim = smoothstep(1.0 - rim_width - rim_softness, 1.0 - rim_width + rim_softness, 1.0 - facing);
	EMISSION = rim_color.rgb * amb_rim * ambient_rim;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrapped = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	float lit;
	if (step_shadows) {
		lit = toon_steps(wrapped * ATTENUATION);
	} else {
		lit = toon_steps(wrapped) * ATTENUATION;
	}
	DIFFUSE_LIGHT += LIGHT_COLOR * lit / PI;

	// Rim: strongest when the light sits behind the form (moonlit edges).
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = smoothstep(1.0 - rim_width - rim_softness, 1.0 - rim_width + rim_softness, 1.0 - facing);
	float back = clamp(dot(LIGHT, -VIEW) * 0.5 + 0.5, 0.0, 1.0);
	float rim_lit = rim * (0.35 + 0.65 * back) * smoothstep(-0.2, 0.2, ndl + 0.15);
	SPECULAR_LIGHT += rim_color.rgb * rim_strength * rim_lit * LIGHT_COLOR * ATTENUATION / PI;
}
