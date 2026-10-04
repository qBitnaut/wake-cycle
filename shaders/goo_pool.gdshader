// The goo: black, oily liquid with no colour of its own. A dim desaturated
// mirror, a muted silver sheen, a slow viscous undulation, and dark bubbles
// that swell and pop at the surface (boiling round whatever it grips). The
// colour of the transformation belongs to the cat, never to the pool.
//
// circuit_on = 1 brings back the old nanotech look: circuit traces that wake up
// close, when disturbed (surge) or while gripping, with packets of blue and
// green light (unshaded, energies near 1 so hues survive the glow).
//
// The rect starts `top_margin` px above the resting surface: headroom for
// the mound, the undulation and the bubbles.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D circuit : filter_nearest, repeat_enable;
uniform sampler2D noise : filter_linear, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec4 body_color : source_color = vec4(0.03, 0.04, 0.065, 1.0);
uniform vec4 sheen_color : source_color = vec4(0.38, 0.43, 0.55, 1.0);
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
uniform vec4 reflect_tint : source_color = vec4(0.5, 0.54, 0.62, 1.0);
uniform float circuit_on = 0.0;     // 1 = the old glowing traces
uniform float ripple = 1.0;         // undulation and bubble strength

float pool_hash(vec2 q) {
	return fract(sin(dot(q, vec2(12.9898, 78.233))) * 43758.5453);
}

// A bubble that swells and pops: slot k comes round every `period` s at a
// random x near `cx` (spread `w`); returns its height at x, px.
float bubble(float x, float k, float period, float cx, float w, float size) {
	float u = (TIME + k * 1.37) / period;
	float n = floor(u);
	float f = fract(u);
	float bx = cx + (pool_hash(vec2(n, k)) - 0.5) * w;
	float r = 1.5 + size * pool_hash(vec2(k, n + 3.0));
	float life = smoothstep(0.0, 0.18, f) * (1.0 - step(0.26, f));
	float dx = (x - bx) / r;
	return max(1.0 - dx * dx, 0.0) * life * (0.8 + size * 0.5);
}

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
	// Slow viscous undulation, stronger when disturbed or gripping.
	float amp = ripple * (0.55 + surge * 1.2 + grip * 0.6);
	mound += amp * (0.5 + 0.3 * sin(x * 0.09 - TIME * 0.9) + 0.2 * sin(x * 0.23 + TIME * 0.55));
	// Dark bubbles: a few slow ones anywhere, a boil round the grip.
	float bub = 0.0;
	for (float k = 0.0; k < 3.0; k += 1.0) {
		bub = max(bub, bubble(x, k, 2.6 + k * 0.9, rect_width * 0.5, rect_width * 0.9, 1.0));
	}
	if (grip > 0.01) {
		for (float k = 3.0; k < 7.0; k += 1.0) {
			bub = max(bub, grip * bubble(x, k, 0.7 + (k - 3.0) * 0.17, grip_x, 34.0, 2.0));
		}
	}
	mound += ripple * bub;
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
	float awake = circuit_on * clamp(max(max(1.0 - dormancy, surge), max(near * 0.4, held)), 0.0, 1.0);
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
	// Desaturated: the mirror never carries colour into the goo.
	refl = vec3(dot(refl, vec3(0.3, 0.59, 0.11)));
	col = mix(col, refl * reflect_tint.rgb, reflectivity * (1.0 - depth * 0.7));
	// Oily sheen: slow, sparse bands, strongest just under the surface.
	float sheen = texture(noise, vec2(p.x * 0.012 - TIME * 0.04, p.y * 0.06 + TIME * 0.015)).r;
	col += sheen_color.rgb * smoothstep(0.62, 0.85, sheen) * (1.0 - depth) * 0.3;
	// Faint glow bleeding around the traces, only once awake. The light
	// gathers at the surface and fades into the deep.
	col += tc * 0.06 * (1.0 + packet) * (1.0 - depth * 0.7) * awake;
	col += tc * trace * lvl * glow_energy * (1.0 - depth * 0.8) * circuit_on;
	// Surface line: a cool moonlit meniscus that takes the trace colour awake.
	if (d < 1.0) {
		// Brighter on the crests of the swell and the tops of the bubbles.
		vec3 calm = sheen_color.rgb * (0.62 + 0.25 * clamp(-surf, 0.0, 2.0));
		vec3 lit = tc * (0.45 + packet * 0.8 + surge) + sheen_color.rgb * 0.25;
		col = mix(calm, lit, awake);
	} else if (d < 2.0) {
		col = mix(col, sheen_color.rgb, 0.08);
	}
	float ends = min(x / px_scale, rw - 1.0 - x / px_scale);
	COLOR = vec4(col, clamp(ends + 1.0, 0.0, 1.0));
}
