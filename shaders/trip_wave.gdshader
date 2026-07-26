shader_type canvas_item;
render_mode unshaded, blend_mix;

// Translucent rainbow wash — no screen_texture (avoids white-buffer failures on Metal).
uniform float intensity : hint_range(0.0, 1.5) = 0.0;
uniform float time_scale = 1.4;
uniform float hue_speed = 0.65;

void fragment() {
	float i = clamp(intensity, 0.0, 1.5);
	if (i < 0.01) {
		COLOR = vec4(0.0);
		return;
	}

	float t = TIME * time_scale;
	vec2 uv = UV;

	// Soft wavy bands so the tint feels like a trip, not a solid sheet.
	float band = 0.55 + 0.45 * sin(uv.y * 14.0 + t * 2.2 + sin(uv.x * 9.0 + t));
	float swirl = 0.5 + 0.5 * cos(uv.x * 11.0 - t * 1.6 + uv.y * 7.0);

	float hue = fract(t * hue_speed + uv.x * 0.45 + uv.y * 0.25 + band * 0.15);
	vec3 rainbow = 0.5 + 0.5 * cos(6.28318 * (hue + vec3(0.0, 0.33, 0.67)));

	// Keep gameplay readable: low alpha, bright tint only.
	float a = clamp(0.18 + 0.28 * i * band * swirl, 0.0, 0.55);
	COLOR = vec4(rainbow, a);
}
