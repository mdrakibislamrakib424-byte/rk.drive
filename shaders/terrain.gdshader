shader_type spatial;
// Ground that blends two real PBR materials (grass and forest soil) with large soft
// patches, so the same texture never looks like an obvious repeating pattern.
// Everything is mapped by world position, so the ground never stretches.

uniform sampler2D grass_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_rough : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_rough : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;

// Metres covered by one texture tile.
uniform float grass_tile_m = 4.0;
uniform float dirt_tile_m = 4.0;
// Size of the grass / soil patches in metres.
uniform float patch_size_m = 38.0;
// Noise value above which the ground turns into soil (lower = more soil).
uniform float dirt_threshold : hint_range(0.0, 1.0) = 0.6;
uniform float patch_softness : hint_range(0.01, 0.5) = 0.12;
// Slow light/dark variation over a very large area, hides the tiling.
uniform float macro_size_m = 110.0;
uniform float macro_strength : hint_range(0.0, 0.6) = 0.22;
uniform vec3 grass_tint : source_color = vec3(1.0, 1.0, 1.0);
// Far away the detail is blurred towards this colour (prevents shimmering).
uniform vec3 far_color : source_color = vec3(0.16, 0.2, 0.09);
uniform float far_fade_start = 90.0;
uniform float far_fade_end = 340.0;

varying vec3 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Three layers of noise, result roughly between 0 and 1.
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		value += amplitude * value_noise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		amplitude *= 0.5;
	}
	return value / 0.875;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;

	// 0 = grass, 1 = soil
	float patches = fbm(p / patch_size_m);
	float soil = smoothstep(dirt_threshold - patch_softness, dirt_threshold + patch_softness, patches);

	vec2 grass_uv = p / grass_tile_m;
	vec2 dirt_uv = p / dirt_tile_m;

	vec3 grass = texture(grass_color, grass_uv).rgb * grass_tint;
	vec3 dirt = texture(dirt_color, dirt_uv).rgb;
	vec3 albedo = mix(grass, dirt, soil);

	float macro = fbm(p / macro_size_m + vec2(31.7, 12.4));
	albedo *= mix(1.0 - macro_strength, 1.0 + macro_strength, macro);

	float far_amount = smoothstep(far_fade_start, far_fade_end, length(VERTEX));
	albedo = mix(albedo, far_color, far_amount * 0.45);

	ALBEDO = albedo;
	NORMAL_MAP = mix(texture(grass_normal, grass_uv).rgb, texture(dirt_normal, dirt_uv).rgb, soil);
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = mix(texture(grass_rough, grass_uv).r, texture(dirt_rough, dirt_uv).r, soil);
	SPECULAR = 0.3;
}
