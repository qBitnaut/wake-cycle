// Nanotech goo. Dormant, it reads as dark, oily water: a dim mirror with a
// cool meniscus line and its circuit traces all but invisible. Up close (the
// cat within reveal_radius), when disturbed (surge) or while it grips the
// cat (grip), the traces wake: packets of blue and green light run along
// them and the meniscus takes their colour. Unshaded so the traces read as
// emissive; energies stay near 1.0 so hues survive, glow does the rest.
//
// The rect starts `top_margin` px above the resting surface: headroom for
// the mound that swells up round the cat's legs when it grips.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D circuit : filter_nearest, repeat_enable;
uniform sampler2D noise : filter_linear, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec4 body_color : source_color = vec4(0.03, 0.04, 0.065, 1.0);
uniform vec4 sheen_color : source_color = vec4(0.35, 0.42, 0.62, 1.0);
uniform vec4 color_a : source_color = vec4(0.12, 0.42, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(0.15, 1.0, 0.55, 1.0);
uniform float glow_energy = 1.4;
uniform float idle = 0.22;          // trace brightness between packets
uniform float pulse_speed = 26.0;   // px per second
uniform float rect_width = 72.0;
uniform float rect_height = 14.0;   // depth below the resting surface
uniform float top_margin = 0.0;
uniform float surge = 0.0;          // 0..1 extra brightness, e.g. when stepped in
uniform float px_scale = 1.0;       // art pixel size: 2 at 640x360 with the baked mask
// 1 = dark water from a distance; 0 = traces always awake (the old look).
uniform float dormancy = 1.0;
uniform float reveal = 0.0;         // how close the cat is, 0..1
uniform float reveal_x = -10000.0;  // the cat's local x, px
uniform float reveal_radius = 64.0;
uniform float grip = 0.0;           // 0..1 the goo has hold of the cat
uniform float grip_x = 0.0;         // local x of the grip, px
uniform float mound_height = 4.0;
uniform float reflectivity = 0.22;
uniform vec4 reflect_tint : source_color = vec4(0.55, 0.62, 0.8, 1.0);

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

void fragment() {
	float x = floor(local_px.x);
	float y = floor(local_px.y - top_margin);   // rows below the resting surface
	// The mound: goo swelling up round whatever it grips, with a slow churn.
	float gx = (x - grip_x) / 13.0;
	float bell = exp(-gx * gx);
	float mound = grip * (mound_height * bell + sin(x * 0.7 + TIME * 4.0) * bell);
	float surf = -floor(mound + 0.5);
	if (y < surf) {
		discard;
	}
	float d = y - surf;                          // px below the local surface
	vec2 p = floor(vec2(x, max(y, 0.0)) / px_scale);
	float rw = rect_width / px_scale;
	vec2 csize = vec2(textureSize(circuit, 0));
	float trace = texture(circuit, (p + 0.5) / csize).a;
	// Packets: a sawtooth running right, phase-shifted per row so they stagger.
	float ph = fract((p.x - TIME * pulse_speed + p.y * 7.0) / 48.0);
	float packet = pow(smoothstep(0.75, 1.0, ph), 2.0) + pow(smoothstep(0.35, 0.0, ph), 6.0) * 0.4;
	float near = reveal * (1.0 - smoothstep(reveal_radius * 0.35, reveal_radius, abs(x - reveal_x)));
	float held = grip * (1.0 - smoothstep(12.0, 44.0, abs(x - grip_x)));
	// Up close it is only a subtle glow; a surge or the grip wakes it fully.
	float awake = clamp(max(max(1.0 - dormancy, surge), max(near * 0.4, held)), 0.0, 1.0);
	float lvl = (idle + packet * 1.6) * mix(0.05, 1.0, awake) + surge * 0.6 + held * 0.3;
	float mixer = texture(noise, vec2(p.x * 0.008 + TIME * 0.015, p.y * 0.03)).r;
	vec3 tc = mix(color_a.rgb, color_b.rgb, smoothstep(0.38, 0.62, mixer));
	float depth = clamp(d / max(rect_height, 1.0), 0.0, 1.0);
	vec3 col = body_color.rgb;
	// A dim, wobbling mirror: the cue that says liquid, darker than a puddle.
	vec2 uv = SCREEN_UV;
	uv.y -= 2.0 * (d + 0.5) * SCREEN_PIXEL_SIZE.y;
	uv.x += round(sin(y * 0.9 + TIME * 1.6 + x * 0.13) * 0.7) * SCREEN_PIXEL_SIZE.x;
	vec3 refl = texture(screen_tex, uv).rgb;
	col = mix(col, refl * reflect_tint.rgb, reflectivity * (1.0 - depth * 0.7));
	// Oily sheen: slow, sparse bands, strongest just under the surface.
	float sheen = texture(noise, vec2(p.x * 0.012 - TIME * 0.04, p.y * 0.06 + TIME * 0.015)).r;
	col += sheen_color.rgb * smoothstep(0.62, 0.85, sheen) * (1.0 - depth) * 0.3;
	// Faint glow bleeding around the traces, only once awake. The light
	// gathers at the surface and fades into the deep.
	col += tc * 0.06 * (1.0 + packet) * (1.0 - depth * 0.7) * awake;
	col += tc * trace * lvl * glow_energy * (1.0 - depth * 0.8);
	// Surface line: a cool moonlit meniscus that takes the trace colour awake.
	if (d < 1.0) {
		vec3 calm = sheen_color.rgb * 0.75;
		vec3 lit = tc * (0.45 + packet * 0.8 + surge) + sheen_color.rgb * 0.25;
		col = mix(calm, lit, awake);
	}
	float ends = min(x / px_scale, rw - 1.0 - x / px_scale);
	COLOR = vec4(col, clamp(ends + 1.0, 0.0, 1.0));
}
