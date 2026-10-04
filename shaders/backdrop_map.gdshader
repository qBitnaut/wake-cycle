// Moonlit recolour for the ansimuz night-city layers: a gradient map from
// luminance to a cool ramp, keeping lit windows as warm or cyan accents.
// Unshaded, so the night tint does not double-darken it. `flash` brightens
// the whole layer for lightning.
shader_type canvas_item;
render_mode unshaded;

uniform vec4 dark : source_color = vec4(0.02, 0.03, 0.07, 1.0);
uniform vec4 mid : source_color = vec4(0.13, 0.17, 0.30, 1.0);
uniform vec4 light : source_color = vec4(0.48, 0.58, 0.80, 1.0);
uniform vec4 lamp : source_color = vec4(1.0, 0.72, 0.40, 1.0);
uniform float lamp_boost = 2.2;
uniform float brightness = 1.0;
uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(0.80, 0.86, 1.0, 1.0);

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	float l = dot(src.rgb, vec3(0.299, 0.587, 0.114));
	float t = clamp(l * 1.6, 0.0, 1.0);
	vec3 ramp = t < 0.5 ? mix(dark.rgb, mid.rgb, t * 2.0) : mix(mid.rgb, light.rgb, t * 2.0 - 1.0);
	// The source lamps are bright, saturated greens: make them warm windows.
	float sat = max(src.r, max(src.g, src.b)) - min(src.r, min(src.g, src.b));
	float is_lamp = smoothstep(0.55, 0.8, l) * smoothstep(0.15, 0.3, sat);
	vec3 col = mix(ramp, lamp.rgb * lamp_boost, is_lamp) * brightness;
	col = mix(col, flash_color.rgb * (0.35 + t * 1.6), flash * (1.0 - is_lamp * 0.5));
	COLOR = vec4(col, src.a * COLOR.a);
}
