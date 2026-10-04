// Soft dark vignette, multiplied over the frame. Quantised to whole game
// pixels so its edge never shimmers against the pixel art.
shader_type canvas_item;
render_mode unshaded, blend_mul;

uniform float strength : hint_range(0.0, 1.0) = 0.35;
uniform vec2 game_size = vec2(320.0, 180.0);

void fragment() {
	vec2 p = (floor(UV * game_size) + 0.5) / game_size - 0.5;
	p.x *= game_size.x / game_size.y * 0.8;
	float v = 1.0 - strength * smoothstep(0.25, 0.95, length(p));
	COLOR = vec4(vec3(v), 1.0);
}
