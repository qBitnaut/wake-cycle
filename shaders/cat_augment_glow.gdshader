// Cat augments, emissive pass: emitters pulsing in the active power colour,
// the bright edge where metal is still materialising, and the flare burst.
// Unshaded and additive; values above 1 bloom through the 2D glow.
//
// Data half of the augment sheet (UV + (0, 0.5)):
//   R emitter strength (1 emitter, 0.78 seam, 0.27 eye ring, 0 metal)
//   G pulse phase      B reveal time       A augment pixel
// Each piece lands at its own time on the reveal schedule; its emitter
// flashes as it does, and freshly printed metal glows for a moment.
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 power_color : source_color = vec4(0.13, 0.65, 0.82, 1.0);
// Idle emitter level; keep near 1 so the hue survives (glow does the rest).
uniform float energy = 0.8;
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
// The bright emitter flash at the end of a reveal.
uniform float flash = 0.0;
// Burst on shockwave or dash.
uniform float flare = 0.0;
uniform float pulse_speed = 0.8;

void fragment() {
	vec4 metal = texture(TEXTURE, UV);
	vec4 d = texture(TEXTURE, UV + vec2(0.0, 0.5));
	if (d.a < 0.5 || d.b > reveal + 0.002) {
		discard;
	}
	vec3 col = vec3(0.0);
	// Materialising edge: freshly printed pixels glow, then cool to metal.
	float age = reveal - d.b;
	float fresh = (1.0 - smoothstep(0.0, 0.05, age)) * (1.0 - step(0.999, reveal));
	col += mix(power_color.rgb, vec3(1.0), 0.45) * fresh * 1.5;
	if (d.r > 0.0) {
		float pulse = 0.5 + 0.5 * sin((TIME * pulse_speed - d.g) * 6.2832);
		// The emitter flashes as its piece lands, then settles to the pulse.
		float landed = (1.0 - smoothstep(0.0, 0.09, age)) * (1.0 - step(0.999, reveal));
		col += power_color.rgb * d.r * (energy * (0.55 + 0.45 * pulse) + flash * 2.6 + flare * 2.2 + landed * 3.0);
	} else if (metal.a > 0.5 && metal.g > 0.5) {
		// Light metal edges catch the emitters' colour, and the burst.
		col += power_color.rgb * (energy * 0.1 + flare * 0.55 + flash * 0.3);
	}
	COLOR = vec4(col, 1.0);
}
