shader_type canvas_item;
render_mode unshaded;

// The weather over the map in the command look (see LiteCmdView, LiteEnv), in
// one pass, in pixels as big as the terrain's (`art` map units): shadows of
// clouds drifting with the wind, patches of fog, a storm's gloom, a
// sandstorm's dust, blowing snow, the flash of lightning. Over the land and
// the sites, under what flies. What falls (rain, snow, sand) is particles:
// LiteCmdRain.

uniform vec2 origin;                 // map units at the rect's top left
uniform vec2 extent;                 // the rect's size in map units
uniform float art = 1.25;
uniform float cloud = 0.0;           // 0..1
uniform float fog = 0.0;             // 0..1
uniform float rain = 0.0;            // 0..1
uniform float flash = 0.0;           // 0..1 lightning
uniform float sand = 0.0;            // 0..1 sandstorm haze
uniform float snow = 0.0;            // 0..1 blowing snow
uniform float night = 0.0;           // 0..1
uniform vec2 wind = vec2(6.0, 2.0);  // map units a second

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.03 + 17.0) * 0.3 + vnoise(p * 4.1 + 41.0) * 0.15;
}

void fragment() {
	vec2 mp = origin + UV * extent;
	// In the terrain's pixels.
	vec2 q = floor(mp / art) * art;
	vec4 o = vec4(0.0);
	if (cloud > 0.01) {
		float n = fbm((q - wind * TIME) * 0.012);
		float a = smoothstep(0.52, 0.72, n) * 0.26 * cloud;
		o = vec4(mix(vec3(0.03, 0.05, 0.08), o.rgb, 0.0), a);
	}
	if (fog > 0.01) {
		float f = fbm((q - wind * TIME * 0.4) * 0.007 + 31.0);
		float a = (0.16 + 0.3 * smoothstep(0.35, 0.8, f)) * fog;
		vec3 fc = mix(vec3(0.72, 0.75, 0.78), vec3(0.28, 0.31, 0.37), night);
		o.rgb = mix(o.rgb, fc, a / max(0.001, o.a + a * (1.0 - o.a)));
		o.a = o.a + a * (1.0 - o.a);
	}
	if (rain > 0.01) {
		// The storm's gloom, heavier under the passing rain bands (the drops
		// themselves are particles, see LiteCmdRain).
		float band = fbm((q - wind * TIME * 1.5) * 0.01 + 77.0);
		float g = (0.08 + 0.12 * smoothstep(0.4, 0.75, band)) * rain;
		o.rgb = mix(o.rgb, vec3(0.04, 0.05, 0.08), g / max(0.001, o.a + g * (1.0 - o.a)));
		o.a = o.a + g * (1.0 - o.a);
	}
	if (sand > 0.01) {
		// Dust: an ochre haze in moving billows.
		float d = fbm((q - vec2(wind.x * 4.0, wind.y) * TIME) * 0.009 + 13.0);
		float a = (0.22 + 0.3 * smoothstep(0.3, 0.8, d)) * sand;
		vec3 dc = mix(vec3(0.66, 0.50, 0.32), vec3(0.24, 0.19, 0.14), night);
		o.rgb = mix(o.rgb, dc, a / max(0.001, o.a + a * (1.0 - o.a)));
		o.a = o.a + a * (1.0 - o.a);
	}
	if (snow > 0.01) {
		// Blowing snow: a pale whiteout in drifts.
		float d = fbm((q - wind * TIME * 2.0) * 0.011 + 5.0);
		float a = (0.16 + 0.24 * smoothstep(0.35, 0.8, d)) * snow;
		vec3 sc = mix(vec3(0.86, 0.89, 0.93), vec3(0.34, 0.37, 0.44), night);
		o.rgb = mix(o.rgb, sc, a / max(0.001, o.a + a * (1.0 - o.a)));
		o.a = o.a + a * (1.0 - o.a);
	}
	if (flash > 0.01) {
		float a = 0.3 * flash;
		o.rgb = mix(o.rgb, vec3(0.9, 0.92, 1.0), a / max(0.001, o.a + a * (1.0 - o.a)));
		o.a = o.a + a * (1.0 - o.a);
	}
	COLOR = o;
}
