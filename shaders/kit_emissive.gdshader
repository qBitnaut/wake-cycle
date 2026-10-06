// Emissive pass for the actor kit: draws only the red sensor pixels (eyes, domes,
// lenses) of a sprite, unshaded and additive, so they glow under the night ambient.
// Values above 1 bloom through the 2D glow. Drawn by KitGlow over a copy of the sprite.
shader_type canvas_item;
render_mode unshaded, blend_add;

// How far over 1.0 the sensor is pushed (the night tint multiplies it back down).
uniform float energy = 2.4;
uniform float pulse_speed = 1.6;
uniform float pulse_depth = 0.12;

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	// Saturated, bright red: the sensor ink. Orange armour and rust fail the g/b ratios.
	float red = smoothstep(0.74, 0.86, t.r) * (1.0 - smoothstep(0.38, 0.5, t.g / max(t.r, 0.001)))
		* (1.0 - smoothstep(0.45, 0.58, t.b / max(t.r, 0.001)));
	float pulse = 1.0 + pulse_depth * sin(TIME * pulse_speed * 6.2832);
	COLOR = vec4(t.rgb * red * t.a * energy * pulse, 1.0);
}
