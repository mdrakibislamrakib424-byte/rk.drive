shader_type spatial;
render_mode cull_disabled;
// Distant mountains. The mesh is a flat grid that follows the car; the height of every
// vertex comes from noise of its WORLD position, so the mountains stay where they are.
// Near the car the height is zero (hidden under the ground), further away it rises.

uniform vec2 center_xz = vec2(0.0);
uniform float amplitude = 1300.0;
uniform float inner_radius = 1500.0;
uniform float blend_distance = 1400.0;
uniform float noise_scale = 2600.0;
uniform float cell_size = 150.0;
uniform vec3 grass_color : source_color = vec3(0.16, 0.22, 0.09);
uniform vec3 forest_color : source_color = vec3(0.045, 0.09, 0.04);
uniform vec3 forest_light : source_color = vec3(0.12, 0.2, 0.07);
uniform vec3 rock_color : source_color = vec3(0.36, 0.33, 0.3);
// Height (0-1 of the amplitude) where bare rock starts to show.
uniform float rock_start : hint_range(0.0, 1.0) = 0.62;

varying float v_height;
varying float v_up;
varying vec2 v_world_xz;

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return v / 0.9375;
}

// Sharp ridges, like real mountain chains.
float ridged(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 4; i++) {
		float n = 1.0 - abs(2.0 * value_noise(p) - 1.0);
		v += a * n * n;
		p = p * 2.1 + vec2(7.3, 3.7);
		a *= 0.5;
	}
	return v;
}

float terrain_height(vec2 p) {
	float d = length(p - center_xz);
	float mask = smoothstep(inner_radius, inner_radius + blend_distance, d);
	float h = 0.25 * fbm(p / noise_scale) + 0.75 * ridged(p / (noise_scale * 0.7) + vec2(13.1, 5.9));
	// Mountains get taller the further away they are.
	float grow = mix(0.45, 1.0, smoothstep(inner_radius, inner_radius + 5000.0, d));
	return mask * clamp(h, 0.0, 1.0) * grow * amplitude;
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = terrain_height(world.xz);
	float hx = terrain_height(world.xz + vec2(cell_size, 0.0));
	float hz = terrain_height(world.xz + vec2(0.0, cell_size));
	// A metre below the ground near the car, so it can never poke through the grass.
	VERTEX.y = h - 1.0;
	NORMAL = normalize(vec3(h - hx, cell_size, h - hz));
	v_height = h / amplitude;
	v_up = NORMAL.y;
	v_world_xz = world.xz;
}

void fragment() {
	float patches = fbm(v_world_xz / 260.0);
	// Small bumps like the tops of thousands of trees (forest canopy).
	float canopy = 0.55 * value_noise(v_world_xz / 26.0) + 0.45 * value_noise(v_world_xz / 8.0);
	vec3 trees = mix(forest_color, forest_light, canopy);
	vec3 lowland = mix(grass_color, trees, smoothstep(0.25, 0.5, patches));
	float steep = 1.0 - smoothstep(0.62, 0.8, v_up);
	float high = smoothstep(rock_start, rock_start + 0.25, v_height);
	float rock = clamp(max(steep, high), 0.0, 1.0);
	vec3 rock_tint = rock_color * (0.75 + 0.5 * patches);
	ALBEDO = mix(lowland, rock_tint, rock);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
