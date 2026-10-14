shader_type spatial;
render_mode cull_disabled, specular_disabled;
// Grass tufts and meadow flowers: crossed cards that sway in the wind.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float brightness = 1.2;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;
uniform float card_height = 0.95;
uniform float sway_amount = 0.09;
uniform float sway_speed = 1.7;

void vertex() {
	NORMAL = vec3(0.0, 1.0, 0.0);
	float h = clamp(VERTEX.y / card_height, 0.0, 1.0);
	h = h * h;
	float phase = dot(MODEL_MATRIX[3].xz, vec2(0.9, 0.7));
	VERTEX.x += (sin(TIME * sway_speed + phase) + 0.4 * sin(TIME * sway_speed * 2.3 + phase * 2.1)) * sway_amount * h;
	VERTEX.z += sin(TIME * sway_speed * 0.7 + phase * 1.3) * sway_amount * 0.5 * h;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	// Darker at the root (looks like shadow between the blades).
	float root = mix(0.55, 1.0, clamp((1.0 - UV.y) * 2.2, 0.0, 1.0));
	ALBEDO = tex.rgb * brightness * root * COLOR.rgb;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ROUGHNESS = 1.0;
}
