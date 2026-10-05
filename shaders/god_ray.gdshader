// God rays: the lit air in a shaft of moonlight or sunlight (MoonShaft). An
// additive, unshaded trapezoid, so the night CanvasModulate does not darken it.
//
// The shaft's coordinates come from the local vertex position and the shaft's
// geometry, not from UVs: Polygon2D hands UVs to its shader only when it has a
// texture (Godot 4.7), and affine UVs across a trapezoid's two triangles kink
// along the diagonal anyway. Every size is in world px, so the look does not
// depend on the window: the game renders at its internal size and scales up by
// whole pixels (2D vertex snapping keeps the edges still).
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 ray_color : source_color = vec4(0.64, 0.76, 1.0, 1.0);
uniform float intensity = 0.3;

// Geometry, local px: the opening is the origin and the shaft runs down +y.
uniform float shaft_length = 140.0;
uniform float lean = 0.0;           // x of the far end's centre
uniform float top_half = 13.0;      // core half width at the opening
uniform float bottom_half = 27.0;   // core half width at the far end

// Edge softness as a fraction of the half width; the penumbra widens with
// distance from the opening. The polygon is the core grown by it.
uniform float soft_top = 0.12;
uniform float soft_bottom = 0.4;
// 0 = flat across, 1 = round (a brighter middle, like a beam seen side on).
uniform float roundness = 0.6;
// Along the shaft: nothing above `start` (px below the opening: the underside
// of a thick roof), a short fade in below it, a gentle falloff to `far_level`
// at the far end, and an optional fade to nothing over the last `fade_out` of
// the length (open-air rays that dissolve before the ground).
uniform float start = 0.0;
uniform float fade_in = 0.08;
uniform float far_level = 0.35;
uniform float fade_out = 0.0;

// Streaks: dust and haze run along the shaft and drift slowly across it.
uniform sampler2D noise : filter_linear, repeat_enable;
uniform float streak_px = 10.0;     // feature size across, local px
uniform float streak_stretch = 10.0; // features are this many times longer along the shaft
uniform float streak_amount = 0.3;  // 0 = even haze
uniform float drift = 1.0;          // px per second
uniform float flicker = 0.0;

// The cat's shadow down the shaft: x, y (local, the middle of its body), its
// half width, and how dark the shadow is (0 = none).
uniform vec4 shade = vec4(0.0);

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	float t = clamp(local.y / shaft_length, 0.0, 1.0);
	float hw = max(mix(top_half, bottom_half, t), 0.5);
	float sx = (local.x - lean * t) / hw;
	float d = abs(sx);
	float soft = mix(soft_top, soft_bottom, t);
	float across = 1.0 - smoothstep(1.0 - soft, 1.0 + soft, d);
	float r = d / (1.0 + soft);
	across *= mix(1.0, sqrt(max(1.0 - r * r, 0.0)), roundness);

	float t0 = start / shaft_length;
	float along = smoothstep(t0, t0 + fade_in, t) * mix(1.0, far_level, smoothstep(0.0, 1.0, t));
	if (fade_out > 0.0) {
		along *= 1.0 - smoothstep(1.0 - fade_out, 1.0, t);
	}

	// The noise's features are about an eighth of its tile. Across, measure
	// relative to the shaft so the streaks spread with it.
	float tile = streak_px * 8.0;
	vec2 q = vec2(sx * 0.5 * (top_half + bottom_half) / tile, local.y / (tile * streak_stretch));
	float s = TIME * drift / tile;
	float n1 = texture(noise, q + vec2(s, -0.2 * s)).r;
	float n2 = texture(noise, q * vec2(0.47, 0.6) + vec2(0.37 - 0.6 * s, 0.11 + 0.15 * s)).r;
	float streak = 1.0 + streak_amount * clamp((n1 + n2 - 0.98) * 1.6, -1.0, 1.0);

	float f = 1.0 + flicker * (sin(TIME * 23.0) * 0.5 + sin(TIME * 7.3) * 0.5);

	float dark = 0.0;
	if (shade.w > 0.0) {
		vec2 dir = normalize(vec2(lean, shaft_length));
		vec2 rel = local - shade.xy;
		float down = dot(rel, dir);
		float side = abs(rel.x * dir.y - rel.y * dir.x);
		float w = shade.z + max(down, 0.0) * 0.12;
		dark = shade.w * smoothstep(-shade.z * 0.6, shade.z * 0.4, down)
			* (1.0 - smoothstep(w * 0.55, w * 1.25, side));
	}

	float a = across * along * streak * intensity * f * (1.0 - dark);
	COLOR = vec4(ray_color.rgb, a);
}
