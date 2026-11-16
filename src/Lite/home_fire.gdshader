shader_type canvas_item;
render_mode blend_add;
// The home screen's fire (see LiteHomeScene): the picture's own flames
// (assets/ui/home_fire.png) added over themselves, rippling upwards in the
// heat and flickering, so the painted fire burns rather than a fire being
// drawn on it.

uniform float t = 0.0;
uniform float gain = 0.5;

void fragment() {
	vec2 uv = UV;
	// More ripple the higher up the flames.
	float up = clamp(1.0 - uv.y, 0.0, 1.0);
	uv.x += (sin(uv.y * 38.0 - t * 9.0) * 0.012 + sin(uv.y * 17.0 - t * 5.3) * 0.008) * up;
	uv.y += sin(uv.x * 25.0 + t * 7.0) * 0.010 * up + 0.006 * sin(t * 13.0) * up;
	vec4 c = texture(TEXTURE, uv);
	float flick = 0.7 + 0.2 * sin(t * 11.0 + uv.y * 9.0) + 0.1 * sin(t * 23.0 + uv.x * 13.0);
	COLOR = vec4(c.rgb, c.a * gain * flick);
}
