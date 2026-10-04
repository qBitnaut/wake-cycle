// Puddle reflection: mirrors the screen above the puddle's top edge, with
// ripple distortion, a dark water tint and ripple rings from drips.
// Put it on a ColorRect whose top edge is the water line (local y = 0).
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D noise : filter_linear, repeat_enable;
uniform vec4 water_tint : source_color = vec4(0.10, 0.14, 0.24, 1.0);
uniform float reflectivity : hint_range(0.0, 1.0) = 0.7;
uniform float wave_amp = 0.6;       // px of sideways wobble
uniform float wave_freq = 0.9;
uniform float wave_speed = 1.6;
uniform float edge_fade = 10.0;     // px of soft puddle ends
uniform float depth_fade = 0.35;    // reflection fades with distance below the line
uniform float rect_width = 64.0;
uniform float rect_height = 6.0;
uniform vec4 highlight : source_color = vec4(0.62, 0.74, 1.0, 1.0);
uniform float px_scale = 1.0;       // FXScale: wobble, rings and edges in 320x180 pixels
// Up to 4 ripples: x = local x (px), y = age (s), z = strength.
uniform vec3 ripples[4];

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

void fragment() {
	vec2 q = local_px / px_scale;               // reference pixels
	float d = local_px.y;                       // real px below the water line (exact mirror)
	float wob = sin(q.y * wave_freq + TIME * wave_speed + q.x * 0.13) * wave_amp;
	wob += (texture(noise, vec2(q.x * 0.02 + TIME * 0.03, q.y * 0.15)).r - 0.5) * wave_amp * 1.5;
	float ring = 0.0;
	for (int i = 0; i < 4; i++) {
		vec3 r = ripples[i];
		if (r.z <= 0.0) continue;
		float rq = r.x / px_scale;
		float radius = r.y * 26.0;
		float dist = abs(q.x - rq) + q.y * 2.5;     // flattened ring: side view
		float band = 1.0 - smoothstep(0.0, 1.6, abs(dist - radius));
		float fade = r.z * clamp(1.0 - r.y / 1.1, 0.0, 1.0);
		ring += band * fade;
		wob += band * fade * 2.0 * sign(q.x - rq);
	}
	vec2 uv = SCREEN_UV;
	uv.y -= 2.0 * d * SCREEN_PIXEL_SIZE.y;  // mirror about the top edge
	uv.x += round(wob * px_scale) * SCREEN_PIXEL_SIZE.x;
	vec3 refl = texture(screen_tex, uv).rgb;
	float depth = 1.0 - clamp(d / max(rect_height, 1.0), 0.0, 1.0) * depth_fade;
	vec3 col = mix(water_tint.rgb, refl * mix(vec3(1.0), water_tint.rgb * 4.0, 0.15), reflectivity * depth);
	col += highlight.rgb * ring * 0.8;
	// Brighter line at the water's edge, and the odd twinkling glint.
	col += highlight.rgb * 0.45 * (1.0 - smoothstep(0.0, 1.0, q.y));
	float g = fract(sin(dot(floor(q), vec2(12.9898, 78.233)) + floor(TIME * 3.0)) * 43758.5453);
	col += highlight.rgb * step(0.985, g) * 0.6 * (1.0 - d / max(rect_height, 1.0));
	// Ragged ends: noise-shaped soft edge.
	float ends = min(q.x, rect_width / px_scale - q.x);
	float jag = texture(noise, vec2(q.y * 0.21, q.x * 0.01)).r * edge_fade;
	float a = smoothstep(0.0, edge_fade * 0.6, ends - jag * 0.6 - q.y * 1.5);
	COLOR = vec4(col, a * water_tint.a);
}
