shader_type sky;
// Cross-fades between a day and a night HDR panorama (equirectangular).
// textureLod() with level 0 avoids the visible seam line that normal texture()
// sampling creates where the panorama wraps around.

uniform sampler2D day_sky : filter_linear, repeat_enable;
uniform sampler2D night_sky : filter_linear, repeat_enable;
uniform float night_amount : hint_range(0.0, 1.0) = 0.0;
uniform float day_energy = 1.0;
uniform float night_energy = 1.0;
// The sun disc in a real HDR photo is thousands of times brighter than the sky.
// Clamping keeps it from blowing out the whole screen.
uniform float max_brightness = 8.0;

vec2 equirect_uv(vec3 dir) {
	float u = atan(dir.x, -dir.z) / TAU + 0.5;
	float v = acos(clamp(dir.y, -1.0, 1.0)) / PI;
	return vec2(u, v);
}

void sky() {
	vec2 uv = equirect_uv(EYEDIR);
	vec3 color = vec3(0.0);
	if (night_amount < 0.999) {
		color += textureLod(day_sky, uv, 0.0).rgb * day_energy * (1.0 - night_amount);
	}
	if (night_amount > 0.001) {
		color += textureLod(night_sky, uv, 0.0).rgb * night_energy * night_amount;
	}
	COLOR = min(color, vec3(max_brightness));
}
