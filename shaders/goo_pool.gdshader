// Nanotech goo: a dark, oily body with PCB traces (baked mask) that pulse
// blue and green as packets of light run along them. Unshaded so the traces
// read as emissive; energies stay near 1.0 so hues survive, glow does the rest.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D circuit : filter_nearest, repeat_enable;
uniform sampler2D noise : filter_linear, repeat_enable;
uniform vec4 body_color : source_color = vec4(0.03, 0.04, 0.065, 1.0);
uniform vec4 sheen_color : source_color = vec4(0.35, 0.42, 0.62, 1.0);
uniform vec4 color_a : source_color = vec4(0.12, 0.42, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(0.15, 1.0, 0.55, 1.0);
uniform float glow_energy = 1.4;
uniform float idle = 0.22;          // trace brightness between packets
uniform float pulse_speed = 26.0;   // px per second
uniform float rect_width = 72.0;
uniform float rect_height = 14.0;
uniform float surge = 0.0;          // 0..1 extra brightness, e.g. when stepped in

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

void fragment() {
	vec2 p = floor(local_px);
	vec2 csize = vec2(textureSize(circuit, 0));
	float trace = texture(circuit, (p + 0.5) / csize).a;
	// Packets: a sawtooth running right, phase-shifted per row so they stagger.
	float ph = fract((p.x - TIME * pulse_speed + p.y * 7.0) / 48.0);
	float packet = pow(smoothstep(0.75, 1.0, ph), 2.0) + pow(smoothstep(0.35, 0.0, ph), 6.0) * 0.4;
	float lvl = idle + packet * 1.6 + surge;
	float mixer = texture(noise, vec2(p.x * 0.008 + TIME * 0.015, p.y * 0.03)).r;
	vec3 tc = mix(color_a.rgb, color_b.rgb, smoothstep(0.38, 0.62, mixer));
	float depth = clamp(p.y / max(rect_height, 1.0), 0.0, 1.0);
	vec3 col = body_color.rgb;
	// Oily sheen: slow, sparse bands, strongest just under the surface.
	float sheen = texture(noise, vec2(p.x * 0.012 - TIME * 0.04, p.y * 0.06 + TIME * 0.015)).r;
	col += sheen_color.rgb * smoothstep(0.62, 0.85, sheen) * (1.0 - depth) * 0.3;
	// Faint glow bleeding around the traces.
	col += tc * 0.06 * (1.0 + packet) * (1.0 - depth * 0.5);
	col += tc * trace * lvl * glow_energy * (1.0 - depth * 0.45);
	// Surface line: a thin meniscus that catches the glow.
	if (p.y < 1.0) {
		col = tc * (0.45 + packet * 0.8 + surge) + sheen_color.rgb * 0.25;
	}
	float ends = min(p.x, rect_width - 1.0 - p.x);
	COLOR = vec4(col, clamp(ends + 1.0, 0.0, 1.0));
}
