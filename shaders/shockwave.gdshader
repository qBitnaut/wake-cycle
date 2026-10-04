// Expanding shockwave ring: refracts the screen at the wavefront and adds a
// bright edge. Draw on a square ColorRect centred on the impact; `progress`
// runs 0..1. `flatten` < 1 squashes it into a ground-hugging ellipse.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float progress = 0.0;
uniform vec4 ring_color : source_color = vec4(0.62, 0.34, 1.0, 1.0);
uniform float energy = 2.0;
uniform float thickness = 0.12;
uniform float distortion = 6.0;     // px of refraction at the wavefront
uniform float flatten = 1.0;
uniform float rect_size = 64.0;

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

void fragment() {
	vec2 p = (floor(local_px) + 0.5) / rect_size * 2.0 - 1.0;
	p.y /= max(flatten, 0.05);
	float d = length(p);
	float r = progress;
	float band = 1.0 - smoothstep(0.0, thickness, abs(d - r));
	float inner = smoothstep(r - thickness * 2.5, r, d) * step(d, r);
	float life = 1.0 - progress;
	vec2 dir = d > 0.0 ? p / d : vec2(0.0);
	vec2 offs = round(dir * band * distortion * life) * SCREEN_PIXEL_SIZE;
	vec3 scr = texture(screen_tex, SCREEN_UV - offs).rgb;
	vec3 col = scr + ring_color.rgb * energy * (band * life + inner * 0.25 * life * life);
	float a = max(band, inner * 0.5) * step(d, 1.0) * clamp(life * 4.0, 0.0, 1.0);
	COLOR = vec4(col, a);
}
