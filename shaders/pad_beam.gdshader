// Soft column of light rising from a pad: additive, fades upward, with thin
// streaks scrolling up. Pixel-snapped so the streaks stay one pixel wide.
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 beam_color : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform float intensity = 0.5;
uniform float rect_width = 20.0;
uniform float rect_height = 30.0;
uniform float speed = 14.0;          // reference px per second
uniform float px_scale = 1.0;        // FXScale: 2 at 640x360

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

float hash(float n) {
	return fract(sin(n * 91.7) * 43758.5453);
}

void fragment() {
	vec2 p = floor(local_px / px_scale);    // reference pixels: streaks keep their look
	float x = (p.x + 0.5) / (rect_width / px_scale);
	float y = 1.0 - (p.y + 0.5) / (rect_height / px_scale);     // 0 at the pad, 1 at the top
	float cx = (x - 0.5) * 2.0;
	float across = exp(-cx * cx * 3.5);
	float up = pow(1.0 - y, 1.8);
	// Thin rising streaks, only in the core so the column has no hard sides.
	float h = hash(p.x);
	float core = step(abs(cx), 0.45);
	float streak = core * step(0.6, h) * step(0.55, fract((p.y + TIME * speed * (0.6 + h)) / (8.0 + h * 10.0)));
	float a = (across * up * 0.6 + streak * up * 0.5) * intensity;
	COLOR = vec4(beam_color.rgb, a);
}
