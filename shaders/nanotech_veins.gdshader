// Nanotech infusion overlay. Apply as GeometryInstance3D.material_overlay so
// it layers over whatever the body already wears (toon material, outline).
// A dark oily goo creeps up from the feet first, and glowing veins grow over
// the body behind it, both driven by progress (0..1). vein_color is a
// uniform so enhancement pads can recolour it (see NanoPalette).
// Heights and noise live in body space: scripts/fx/nanotech_infusion.gd sets
// body_inv (world -> body root) every frame plus the body's height range, so
// a body made of several meshes, skinned or not, reads as one surface.
// Skinned bodies whose meshes carry a bind-pose position in CUSTOM0 (see
// scripts/fx/cat_skin.gd) set use_bind_pose: body_pos then comes from that
// attribute through the static bind_to_body matrix, so the pattern stays on
// the fur while the skeleton animates instead of sliding through the limbs.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

#include "res://shaders/includes/fx_noise.gdshaderinc"

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 vein_color : source_color = vec4(0.12, 0.42, 1.0, 1.0);
uniform float vein_energy : hint_range(0.0, 16.0) = 4.0;

group_uniforms body;
uniform mat4 body_inv = mat4(1.0);
// Body-space Y range: feet and top of the head.
uniform float height_min = 0.0;
uniform float height_max = 1.0;
// Bind-pose path: body_pos = bind_to_body * CUSTOM0.xyz. Static (body_inv x
// the mesh's global transform at setup); CUSTOM0 is in raw mesh units.
uniform bool use_bind_pose = false;
uniform mat4 bind_to_body = mat4(1.0);

group_uniforms veins;
// Noise frequency per metre (scale with body size).
uniform float vein_scale = 5.0;
uniform float vein_width : hint_range(0.005, 0.2) = 0.045;
// How ragged the growth front is.
uniform float front_noise : hint_range(0.0, 0.5) = 0.18;
uniform float pulse_speed = 1.4;
uniform float pulse_spacing = 9.0;

group_uniforms goo;
uniform vec4 goo_color : source_color = vec4(0.012, 0.01, 0.02, 1.0);
// Fraction of the body height the goo climbs to at progress = 1.
uniform float goo_reach : hint_range(0.0, 1.2) = 0.55;
// Fade the goo out (e.g. after the cat leaves the pool) without losing veins.
uniform float goo_opacity : hint_range(0.0, 1.0) = 0.92;
uniform float goo_lead : hint_range(0.0, 0.5) = 0.15;

varying vec3 body_pos;

void vertex() {
	if (use_bind_pose) {
		body_pos = (bind_to_body * vec4(CUSTOM0.xyz, 1.0)).xyz;
	} else {
		vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		body_pos = (body_inv * vec4(world, 1.0)).xyz;
	}
}

void fragment() {
	float h = clamp((body_pos.y - height_min) / max(height_max - height_min, 0.001), 0.0, 1.0);
	vec3 q = body_pos * vein_scale;
	float jitter = fx_value_noise3(q * 0.7 + 3.1) - 0.5;

	// Goo rises first: its front leads the vein front.
	float goo_front = clamp(progress * (1.0 + goo_lead), 0.0, 1.0) * goo_reach;
	float goo_h = h + jitter * front_noise * 0.6;
	float goo = 1.0 - smoothstep(goo_front - 0.03, goo_front, goo_h);
	goo *= step(0.001, progress);
	float goo_edge = goo * (1.0 - smoothstep(0.0, 0.05, goo_front - goo_h));

	// Veins: zero set of warped gradient noise, revealed bottom-up.
	vec3 warp = vec3(fx_value_noise3(q * 0.5), fx_value_noise3(q * 0.5 + 9.2), fx_value_noise3(q * 0.5 + 4.7)) - 0.5;
	float n1 = fx_gradient_noise3(q + warp * 1.2);
	float n2 = fx_gradient_noise3(q * 2.1 + 5.3 + warp);
	float aa = fwidth(n1) * 0.8;
	float vein = 1.0 - smoothstep(vein_width - aa, vein_width + aa, abs(n1));
	float aa2 = fwidth(n2) * 0.8;
	float twig = (1.0 - smoothstep(vein_width * 0.6 - aa2, vein_width * 0.6 + aa2, abs(n2))) * 0.55;
	float lines = max(vein, twig);
	float vein_front = progress * 1.15;
	float vein_h = h + jitter * front_noise;
	float grown = 1.0 - smoothstep(vein_front - 0.08, vein_front, vein_h);
	float tip = grown * (1.0 - smoothstep(0.0, 0.1, vein_front - vein_h));
	lines *= grown;

	float pulse = 0.55 + 0.45 * pow(0.5 + 0.5 * sin(h * pulse_spacing - TIME * pulse_speed), 3.0);
	float glow = lines * (pulse + tip * 1.5);

	float goo_a = goo * goo_opacity;
	ALBEDO = goo_color.rgb;
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
	METALLIC = 0.0;
	EMISSION = vein_color.rgb * (glow * vein_energy + goo_edge * goo_opacity * 1.5);
	ALPHA = clamp(max(goo_a, lines * 0.95 + goo_edge * goo_opacity), 0.0, 1.0);
}
