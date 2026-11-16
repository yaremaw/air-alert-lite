shader_type canvas_item;

// The world round the two countries in the Modern Military Command look (see
// LiteCmdView); the legacy look is lite_world.gdshader, untouched. The sea a
// deep blue-black, the neighbouring countries a desaturated grey-blue with
// faint contour lines (as on the countries) and thin lines between them,
// the reference grid over both.
// Cells are blended over the four nearest (or `soft` round them on an
// operation's map, where the war map's world is drawn enlarged).
uniform sampler2D ids : filter_nearest;
uniform vec4 sea_col : source_color;
uniform vec4 land_col : source_color;
uniform vec4 line_col : source_color;
uniform vec4 coast_col : source_color;
uniform vec4 ours_col : source_color;
uniform vec4 theirs_col : source_color;
uniform int soft = 0;
uniform sampler2D relief : filter_linear, repeat_disable;
uniform vec2 relief_origin;
uniform vec2 relief_size = vec2(1.0);
// Where this texture lies in map units: its top left and the size of a cell.
uniform vec2 origin;
uniform float cell = 2.0;
uniform float grid_step = 60.0;
uniform vec4 grid_col : source_color;
uniform sampler2D terrain : filter_nearest;
uniform bool has_terrain = false;
uniform vec2 terrain_origin;
uniform float terrain_art = 1.25;
uniform vec3 ambient = vec3(1.0);

float hw(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

int id_at(ivec2 p, ivec2 size) {
	p = clamp(p, ivec2(0), size - ivec2(1));
	return int(texelFetch(ids, p, 0).r * 255.0 + 0.5);
}

void fragment() {
	ivec2 size = textureSize(ids, 0);
	vec2 at = UV * vec2(size) - 0.5;
	ivec2 b = ivec2(floor(at));
	vec2 f = fract(at);
	int c = id_at(ivec2(UV * vec2(size)), size);
	int k[4] = int[](id_at(b, size), id_at(b + ivec2(1, 0), size), id_at(b + ivec2(0, 1), size), id_at(b + ivec2(1, 1), size));
	float wt[4] = float[]((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
	bool any_neighbour = false;
	for (int i = 0; i < 4; i++) {
		if (k[i] != 0 && k[i] != 255) any_neighbour = true;
	}
	float land = 0.0, other = 0.0;
	if (soft > 0) {
		float total = 0.0;
		for (int dy = -soft; dy <= soft; dy++) {
			for (int dx = -soft; dx <= soft; dx++) {
				vec2 o = vec2(float(dx), float(dy)) + 0.5 - f;
				float g = exp(-dot(o, o) / float(soft * soft));
				int n = id_at(b + ivec2(dx, dy), size);
				total += g;
				if (n != 0 && n != 255) land += g;
				if (n != c && n != 0 && n != 255 && c != 0 && c != 255) other += g;
			}
		}
		land /= total;
		other /= total;
	} else {
		for (int i = 0; i < 4; i++) {
			bool is_land = k[i] != 0 && (k[i] != 255 || any_neighbour);
			if (is_land) land += wt[i];
			if (k[i] != c && k[i] != 0 && k[i] != 255 && c != 0 && c != 255) other += wt[i];
		}
	}
	vec2 mp = origin + UV * vec2(size) * cell;
	vec2 tuv = (mp - relief_origin) / relief_size;
	float ce = texture(relief, tuv).r * 16.0;
	float cw = max(fwidth(ce), 0.0001);
	float contour = 1.0 - smoothstep(0.0, cw * 1.1, abs(fract(ce + 0.5) - 0.5));
	vec2 te = 1.0 / vec2(textureSize(relief, 0));
	float hx = texture(relief, tuv + vec2(te.x, 0.0)).r - texture(relief, tuv - vec2(te.x, 0.0)).r;
	float hy = texture(relief, tuv + vec2(0.0, te.y)).r - texture(relief, tuv - vec2(0.0, te.y)).r;
	float lit = clamp(-(hx + hy) * 5.0, -1.0, 1.0);

	vec3 base = land_col.rgb * (0.95 + 0.1 * lit);
	vec3 sea = sea_col.rgb;
	bool painted = false;
	if (has_terrain) {
		// The same terrain as under the two countries, faded: other lands,
		// not the war's. Where it isn't painted (beyond its edge) the flat
		// colours as before.
		ivec2 ts = textureSize(terrain, 0);
		ivec2 tq = ivec2(floor((mp - terrain_origin) / terrain_art));
		if (tq.x >= 0 && tq.y >= 0 && tq.x < ts.x && tq.y < ts.y) {
			vec3 ter = texelFetch(terrain, tq, 0).rgb;
			float lum = dot(ter, vec3(0.3, 0.59, 0.11));
			base = mix(ter, vec3(lum), 0.5) * 0.7 + vec3(0.015, 0.02, 0.03);
			sea = ter;
			painted = true;
			// The sea moves: rows of small wave crests drifting along, the
			// light on it changing slowly.
			vec2 aq = vec2(tq);
			float wv = fract((aq.x * 0.35 + aq.y * 1.0) / 11.0 - TIME * 0.18);
			if (wv < 0.07 && hw(floor(aq / vec2(4.0, 1.0)) + floor(TIME * 0.25)) < 0.35) sea += vec3(0.05, 0.07, 0.08);
			sea *= 0.97 + 0.03 * sin(TIME * 0.7 + aq.x * 0.05 - aq.y * 0.08);
		}
	}
	if (c >= 100 && c < 170) base = painted ? mix(base, ours_col.rgb, 0.4) : ours_col.rgb;
	else if (c >= 170 && c < 254) base = painted ? mix(base, theirs_col.rgb, 0.4) : theirs_col.rgb;
	if (!painted) base = mix(base, base * 1.4 + vec3(0.015), contour * 0.14);
	vec3 col = mix(base, line_col.rgb, smoothstep(0.08, 0.4, other) * 0.8);
	// The coast: a thin line where land meets the sea.
	float coast = 1.0 - abs(land - 0.5) * 4.0;
	if (painted) {
		// The terrain draws its own coast, shallows and all.
		col = mix(col, line_col.rgb, smoothstep(0.08, 0.4, other) * 0.2);
		col = land > 0.5 || c != 0 ? col : sea;
	} else {
		col = mix(sea, col, smoothstep(0.35, 0.65, land));
		col = mix(col, coast_col.rgb, clamp(coast, 0.0, 1.0) * 0.8);
	}
	COLOR = vec4(col * ambient, 1.0);
}
