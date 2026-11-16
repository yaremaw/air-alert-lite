shader_type canvas_item;
// The home screen's fog (see LiteHomeScene): banks of mist drifting slowly
// sideways, thickest low in the valley in front of the city, a thin haze
// higher up; kept light over the launcher in front and the menu's side.

uniform float t = 0.0;
// The rect's size, where the picture's (0, 0) is on it and its scale.
uniform vec2 rect_size = vec2(1280.0, 720.0);
uniform vec2 origin = vec2(0.0);
uniform float scale = 1.0;
uniform vec3 fog_col = vec3(0.68, 0.7, 0.74);

float h(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1.0, 0.0)), u.x), mix(h(i + vec2(0.0, 1.0)), h(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vn(p);
		p = p * 2.03 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 art = (UV * rect_size - origin) / scale;
	// Two layers, the big banks slow, the wisps over them quicker and
	// bent by the banks, all drifting to the right.
	float f1 = fbm(art / vec2(460.0, 150.0) + vec2(t * 0.030, 0.0));
	float f2 = fbm(art / vec2(190.0, 70.0) + vec2(t * 0.075, t * 0.006) + f1 * 0.9);
	float d = smoothstep(0.38, 0.86, f1 * 0.55 + f2 * 0.6);
	// Lying low, along the valley floor in front of the city: none over the
	// blocks' upper floors, the tower or the sky.
	float low = smoothstep(735.0, 800.0, art.y) * (1.0 - smoothstep(860.0, 960.0, art.y));
	float a = d * low;
	// Never up to the launcher on the hill in front: gone before it.
	a *= 1.0 - smoothstep(1130.0, 1240.0, art.x);
	a *= mix(0.35, 1.0, smoothstep(250.0, 800.0, art.x));
	COLOR = vec4(fog_col, clamp(a * 0.6, 0.0, 0.6));
}
