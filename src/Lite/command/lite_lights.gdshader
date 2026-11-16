shader_type canvas_item;
render_mode blend_add, unshaded;

// The settlements' lights at night (see LiteSettle, LiteCmdView): each light
// one terrain pixel (windows, street lamps, works floodlights), coming on one
// by one at dusk; the ones marked so (alpha under 1) flickering now and then;
// and a soft glow over the whole lit footprint (a blurred mip of the same
// image), so a city reads from afar. Near a fresh impact the lights round it
// flash and stutter for a moment (`hits`).

uniform sampler2D px_tex : filter_nearest;
uniform sampler2D glow_tex : filter_linear_mipmap;
uniform float night = 0.0;
uniform vec2 origin;          // map units at the texture's top left
uniform float art = 1.25;     // map units a pixel
// Recent impacts: xy where (map units), z seconds since, w how strong.
uniform vec4 hits[8];
// Blackouts (see LiteCmdView.blackout): the map's regions (2 texels a map
// unit), and for each region (by id) when its lights went out (r, in `now`'s
// clock) and for how long they stay out (g).
uniform sampler2D ids : filter_nearest;
uniform sampler2D blackout : filter_nearest;
uniform float now = 0.0;

// A region's lights after a strike at `t` seconds: out, back on for a
// moment, out again, then stuttering back. `len` stretches the dark part
// (a power station lost: out for long). 1 lit, 0 dark.
float pattern(float t, float len) {
	if (t < 0.0) return 1.0;
	if (t < 1.1 * len) return 0.0;
	if (t < 1.1 * len + 0.35) return 1.0;
	if (t < 2.4 * len + 0.35) return 0.0;
	float u = t - (2.4 * len + 0.35);
	if (u < 1.2) return step(0.45, fract(u * 6.0)) * u / 1.2;
	return 1.0;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 ts = vec2(textureSize(px_tex, 0));
	vec2 px = floor(UV * ts);
	vec4 l = texture(px_tex, UV);
	vec3 g = textureLod(glow_tex, UV, 3.0).rgb + textureLod(glow_tex, UV, 4.5).rgb * 0.8;
	float h = hash(px);
	// Lights come on one by one as it gets dark.
	float on = smoothstep(h * 0.8, h * 0.8 + 0.15, night * 1.05);
	float fl = 1.0;
	if (l.a > 0.01 && l.a < 0.9) {
		// A faulty light: off now and then, in short stutters.
		float t = floor(TIME * 7.0 + h * 50.0);
		fl = hash(vec2(t, h * 91.0)) < 0.18 ? 0.15 : 1.0;
	}
	// Impacts nearby: a flash, then the lights round it stuttering.
	vec2 mp = origin + (px + 0.5) * art;
	float flash = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 hv = hits[i];
		if (hv.w <= 0.0) continue;
		float d = distance(mp, hv.xy);
		float reach = 26.0 + 14.0 * hv.w;
		if (d < reach) {
			float k = 1.0 - d / reach;
			flash += k * hv.w * exp(-hv.z * 3.0);
			if (hv.z < 2.5 && hash(vec2(floor(TIME * 12.0), h * 37.0 + float(i))) < 0.35 * k) fl *= 0.2;
		}
	}
	// The region's blackout: its districts going out one after another
	// (each block of the map a little later than the next).
	float bo = 1.0;
	vec2 its = vec2(textureSize(ids, 0));
	vec2 iuv = mp * 2.0 / its;
	if (iuv.x >= 0.0 && iuv.y >= 0.0 && iuv.x < 1.0 && iuv.y < 1.0) {
		int rid = int(texture(ids, iuv).r * 255.0 + 0.5);
		if (rid < 255) {
			vec4 b = texelFetch(blackout, ivec2(rid, 0), 0);
			if (b.g > 0.0) {
				float delay = hash(floor(mp / 14.0)) * 0.6;
				bo = pattern(now - b.r - delay, b.g);
			}
		}
	}
	vec3 c = (l.rgb * fl * on * (1.0 + flash * 1.5) + g * 2.2 * night) * bo;
	COLOR = vec4(c * night, 1.0);
}
