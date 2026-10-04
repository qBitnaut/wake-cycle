// CRT at the display's native resolution: per game-row beam profile
// (scanlines), an aperture-grille mask, gentle barrel curvature and vignette.
// PostFX draws this in a full-resolution viewport fed by the 320x180 frame.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D src : filter_linear;
uniform vec2 src_size = vec2(320.0, 180.0);
uniform float curvature = 0.045;
uniform float scanline = 0.6;       // 0 none, 1 black gaps between rows
uniform float mask = 0.22;          // aperture grille strength
uniform float brightness = 1.3;     // compensates the darkening
uniform float vignette = 0.3;
uniform float sharpness = 2.0;      // horizontal: higher = crisper pixels

void fragment() {
	vec2 cc = UV - 0.5;
	vec2 uv = 0.5 + cc * (1.0 + curvature * dot(cc, cc) * 4.0);
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		vec2 sp = uv * src_size;
		// Sharpen the horizontal blend so pixels stay readable but soft-edged.
		float fx = fract(sp.x) - 0.5;
		float sx = floor(sp.x) + 0.5 + clamp(fx * sharpness, -0.5, 0.5);
		float row = floor(sp.y) + 0.5;
		vec3 c = texture(src, vec2(sx, row) / src_size).rgb;
		// Beam: bright rows bloom wider, dark rows stay thin.
		float dy = fract(sp.y) - 0.5;
		float lum = dot(c, vec3(0.3, 0.59, 0.11));
		float w = mix(0.22, 0.42, clamp(lum, 0.0, 1.0));
		float beam = exp(-(dy * dy) / (2.0 * w * w));
		c *= mix(1.0, beam, scanline);
		int m = int(mod(FRAGCOORD.x, 3.0));
		vec3 grille = vec3(1.0 - mask);
		grille[m] = 1.0;
		c *= grille * brightness;
		float v = 1.0 - vignette * dot(cc, cc) * 2.2;
		COLOR = vec4(c * v, 1.0);
	}
}
