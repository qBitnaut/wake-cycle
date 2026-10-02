// Wake Cycle toon shader.
// Stepped diffuse bands, a back-lit rim and an optional toon highlight,
// sampling an albedo texture (Kenney kits share one colormap.png atlas).
// Pair with toon_outline.gdshader as next_pass for inverted-hull outlines.
// Use scripts/fx/toon_applier.gd to put both on an imported GLB.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

group_uniforms surface;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
// Multiply albedo by the mesh's vertex colours.
uniform bool use_vertex_color = false;
// Map albedo_texture in world space (metres per tile). 0 = use mesh UVs.
// Handy for blockout primitives whose UVs stretch.
uniform float world_uv_tile = 0.0;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 1.0;

group_uniforms bands;
uniform int band_count : hint_range(1, 4) = 3;
uniform float band_softness : hint_range(0.0, 0.25) = 0.03;
// Wraps the terminator so the first band reaches a little round the form.
uniform float wrap : hint_range(0.0, 0.5) = 0.1;
// Quantise shadows and light falloff too, for hard-edged toon shadows and
// stepped pools of light. Off steps only the form shading and keeps shadow
// edges and local light pools soft.
uniform bool step_shadows = false;

group_uniforms rim;
uniform vec4 rim_color : source_color = vec4(0.62, 0.74, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 4.0) = 0.8;
uniform float rim_width : hint_range(0.0, 1.0) = 0.3;
uniform float rim_softness : hint_range(0.0, 0.5) = 0.06;
// Light-independent rim so silhouettes survive in deep shadow.
uniform float ambient_rim : hint_range(0.0, 1.0) = 0.06;

group_uniforms ambient;
// Darkens ambient on faces turned away from the sky, so form still reads
// in shadow where only ambient light reaches.
uniform float ambient_hemisphere : hint_range(0.0, 1.0) = 0.55;

group_uniforms highlight;
uniform float specular_strength : hint_range(0.0, 4.0) = 0.0;
uniform float specular_size : hint_range(0.0, 0.5) = 0.05;

varying vec3 world_pos;
varying vec3 world_normal;

float toon_steps(float x) {
	float n = float(band_count);
	float s = 0.0;
	for (int i = 1; i <= band_count; i++) {
		float t = (float(i) - 0.5) / n;
		s += smoothstep(t - band_softness, t + band_softness, x);
	}
	return s / n;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	vec4 tex;
	if (world_uv_tile > 0.0) {
		// Cheap biplanar: pick the dominant axis instead of blending three taps.
		vec3 an = abs(world_normal);
		vec2 wuv = an.y > max(an.x, an.z) ? world_pos.xz : (an.x > an.z ? world_pos.zy : world_pos.xy);
		tex = texture(albedo_texture, wuv / world_uv_tile + uv_offset);
	} else {
		tex = texture(albedo_texture, uv);
	}
	vec3 col = tex.rgb * albedo_color.rgb;
	if (use_vertex_color) {
		col *= COLOR.rgb;
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	AO = mix(1.0 - ambient_hemisphere, 1.0, clamp(world_normal.y * 0.5 + 0.5, 0.0, 1.0));
	AO_LIGHT_AFFECT = 0.0;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float amb_rim = smoothstep(1.0 - rim_width - rim_softness, 1.0 - rim_width + rim_softness, 1.0 - facing);
	EMISSION = emission_color.rgb * emission_energy + rim_color.rgb * amb_rim * ambient_rim;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrapped = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	float lit;
	if (step_shadows) {
		// ATTENUATION carries shadows and falloff, so those get stepped too.
		lit = toon_steps(wrapped * ATTENUATION);
	} else {
		lit = toon_steps(wrapped) * ATTENUATION;
	}
	DIFFUSE_LIGHT += LIGHT_COLOR * lit / PI;

	// Rim: strongest when the light sits behind the form (moonlit edges).
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = smoothstep(1.0 - rim_width - rim_softness, 1.0 - rim_width + rim_softness, 1.0 - facing);
	float back = clamp(dot(LIGHT, -VIEW) * 0.5 + 0.5, 0.0, 1.0);
	float rim_lit = rim * (0.35 + 0.65 * back) * smoothstep(-0.2, 0.2, ndl + 0.15);
	SPECULAR_LIGHT += rim_color.rgb * rim_strength * rim_lit * LIGHT_COLOR * ATTENUATION / PI;

	if (specular_strength > 0.0) {
		vec3 h = normalize(LIGHT + VIEW);
		float nh = clamp(dot(NORMAL, h), 0.0, 1.0);
		float spec = smoothstep(1.0 - specular_size - 0.005, 1.0 - specular_size + 0.005, nh);
		SPECULAR_LIGHT += LIGHT_COLOR * spec * specular_strength * ATTENUATION / PI;
	}
}
