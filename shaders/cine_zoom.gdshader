// Cinematic zoom at the display's native resolution. CineZoom draws the
// 640x360 game frame to the window through this shader, magnified about
// `focus`. Sharp-bilinear sampling keeps every art pixel a crisp square
// while the zoom glides through fractional values: texel interiors are
// flat and only the one output pixel on each texel edge is blended, so
// there is none of the shimmer of a fractional Camera2D zoom at 640x360.
// The output is opaque with blending off: the close-up replaces what is
// under it and never mixes with it. A soft edge vignette is drawn here too,
// at native res (CineZoom draws the letterbox as its own item, over any HD
// effects).
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D src : filter_linear;
uniform vec2 src_size = vec2(640.0, 360.0);
uniform vec2 out_size = vec2(1280.0, 720.0);   // destination rect, window px
uniform vec2 focus = vec2(320.0, 180.0);        // view centre, game px
uniform float scale = 2.0;                      // window px per game px, zoom included
uniform float vignette = 0.0;

void fragment() {
	vec2 half_view = min(out_size * 0.5 / scale, src_size * 0.5);
	vec2 c = clamp(focus, half_view, src_size - half_view);
	vec2 p = c + (UV - 0.5) * out_size / scale;  // game px, continuous
	vec2 base = floor(p);
	vec2 off = fract(p) - 0.5;
	float inner = 0.5 - 0.5 / max(scale, 1.0);
	vec2 f = (off - clamp(off, -inner, inner)) * scale + 0.5;
	vec3 col = texture(src, (base + f) / src_size).rgb;
	// Elliptical at 16:9 whatever the window's aspect.
	vec2 v = (UV - 0.5) * vec2(1.0, out_size.y / out_size.x * 1.42);
	col *= 1.0 - vignette * smoothstep(0.3, 0.75, length(v));
	COLOR = vec4(col, 1.0);
}
