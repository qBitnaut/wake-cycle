// Drifting fog band. Samples a baked tileable noise PNG (never a runtime
// NoiseTexture2D: that hitches the first frame on the web). Lit like any other
// canvas item, so fog brightens inside moon shafts and lamp pools.
shader_type canvas_item;

uniform sampler2D noise : filter_linear, repeat_enable;
uniform vec4 fog_color : source_color = vec4(0.42, 0.50, 0.70, 1.0);
uniform float density : hint_range(0.0, 1.0) = 0.5;
uniform float brightness = 1.0;         // >1 so the night tint leaves a visible haze
uniform vec2 scroll = vec2(4.0, 0.0);   // px per second
uniform float noise_scale = 1.0;        // noise texels per screen px
uniform float rect_height = 48.0;
uniform float fade_top = 0.6;           // fraction of the height that fades in from the top
uniform float fade_bottom = 0.15;
uniform float repeats = 2.0;            // noise tiles across rect_width; keep it an integer
uniform float rect_width = 512.0;
uniform float steps = 0.0;              // >0 posterises the density for a retro look

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

void fragment() {
	vec2 p = floor(local_px) + 0.5;
	vec2 uv1 = vec2(p.x / rect_width * repeats, p.y / 128.0 * noise_scale) + TIME * scroll / vec2(rect_width / repeats, 128.0);
	vec2 uv2 = vec2(p.x / rect_width * repeats * 2.0, p.y / 64.0 * noise_scale) - TIME * scroll * 0.6 / vec2(rect_width / repeats, 64.0) + vec2(0.37, 0.11);
	float n = texture(noise, uv1).r * 0.65 + texture(noise, uv2).r * 0.45;
	n = smoothstep(0.3, 0.95, n);
	float y = p.y / max(rect_height, 1.0);
	float band = smoothstep(0.0, fade_top, y) * (1.0 - smoothstep(1.0 - fade_bottom, 1.0, y));
	float a = n * band * density;
	if (steps > 0.0) {
		a = floor(a * steps + 0.5) / steps;
	}
	COLOR = vec4(fog_color.rgb * brightness, a);
}
