// Cinematic zoom at the display's native resolution. CineZoom draws the
// 640x360 game frame to the window through this shader, magnified about
// `focus`. Sharp-bilinear sampling keeps every art pixel a crisp square
// while the zoom glides through fractional values: texel interiors are
// flat and only the one output pixel on each texel edge is blended, so
// there is none of the shimmer of a fractional Camera2D zoom at 640x360.
// Letterbox bars and a soft edge vignette are drawn here too, at native res.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D src : filter_linear;
uniform vec2 src_size = vec2(640.0, 360.0);
uniform vec2 out_size = vec2(1280.0, 720.0);   // destination rect, window px
uniform vec2 focus = vec2(320.0, 180.0);        // view centre, game px
uniform float zoom = 1.0;
uniform float bars = 0.0;                       // letterbox, 0..1
uniform float bar_height = 0.1;                 // of the frame height, at bars = 1
uniform float vignette = 0.0;

void fragment() {
	vec2 half_view = src_size * 0.5 / zoom;
	vec2 c = clamp(focus, half_view, src_size - half_view);
	vec2 p = c + (UV - 0.5) * src_size / zoom;  // game px, continuous
	vec2 scale = out_size * zoom / src_size;    // window px per game px
	vec2 base = floor(p);
	vec2 off = fract(p) - 0.5;
	vec2 inner = 0.5 - 0.5 / max(scale, vec2(1.0));
	vec2 f = (off - clamp(off, -inner, inner)) * scale + 0.5;
	vec3 col = texture(src, (base + f) / src_size).rgb;
	vec2 v = (UV - 0.5) * vec2(1.0, 0.8);
	col *= 1.0 - vignette * smoothstep(0.3, 0.75, length(v));
	float b = bars * bar_height;
	if (UV.y < b || UV.y > 1.0 - b) {
		col = vec3(0.0);
	}
	COLOR = vec4(col, 1.0);
}
