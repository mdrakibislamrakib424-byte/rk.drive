shader_type spatial;
render_mode cull_disabled, specular_disabled;
// Billboard "cards" of a tree. Each card is a picture of the real 3D tree (rendered once,
// offline) on a flat quad; three crossed cards make a tree that looks right from every side.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
// Cards are baked from the plain colour texture, so they need a little lift to match lit 3D objects.
uniform float brightness = 1.3;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.45;

void vertex() {
	// Every card is lit like a horizontal surface. The whole tree then reacts to the sun,
	// the sky light and the day/night change in the same way from every direction.
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	// COLOR carries the per-tree tint (MultiMesh instance colour), so no two trees look identical.
	ALBEDO = tex.rgb * brightness * COLOR.rgb;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ROUGHNESS = 1.0;
}
