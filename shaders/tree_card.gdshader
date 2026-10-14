shader_type spatial;
render_mode cull_disabled, specular_disabled;
// Billboard "cards" of a tree: a picture of the real 3D tree (rendered once, offline) on flat quads.
// Three crossed cards make a tree that looks right from every side. The tree sways in the wind.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float brightness = 1.3;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.45;
// Height of the card in metres (used to sway the top more than the bottom).
uniform float card_height = 4.5;
uniform float sway_amount = 0.12;
uniform float sway_speed = 1.1;

void vertex() {
	// Lit like a horizontal surface, so the whole tree reacts to sun, sky and night the same way.
	NORMAL = vec3(0.0, 1.0, 0.0);
	float h = clamp(VERTEX.y / card_height, 0.0, 1.0);
	h = h * h;
	// Every tree gets its own phase (from its position), so they do not move in step.
	float phase = dot(MODEL_MATRIX[3].xz, vec2(0.21, 0.17));
	VERTEX.x += sin(TIME * sway_speed + phase) * sway_amount * h;
	VERTEX.z += sin(TIME * sway_speed * 0.8 + phase * 1.7 + 1.3) * sway_amount * 0.6 * h;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	ALBEDO = tex.rgb * brightness * COLOR.rgb;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ROUGHNESS = 1.0;
}
