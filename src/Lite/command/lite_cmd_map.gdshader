shader_type canvas_item;

// The two countries in the Modern Military Command look (see LiteCmdView);
// the legacy look is lite_map.gdshader, untouched.
//
// `ids` holds one region id per texel (255 = sea). The palette: row 0 the
// fill each region shows now (friendly blue-grey, hostile dark red, a shade
// apart per region), row 1 its country, row 2 its campaign group, row 3 its
// state: r how strongly it is under alert, g whether that alert is for
// missiles (red) rather than drones (amber), b a hit's flash, a how strongly
// it is selected or under the pointer.
//
// Over the fills: the land's elevation (`relief`, one smooth field per map,
// worked out once) as an operational map shows it: thin contour lines, every
// fourth heavier, over very slight elevation bands and a light hill-shading
// from the top left;
// thin sharp borders lighter than the fills, faint district lines, alerts as
// a tint with a diagonal hatch, the frontier as a two-tone line (blue on our
// side, red on theirs), a crisp coastline and a faint reference grid.
uniform sampler2D ids : filter_nearest;
uniform sampler2D palette : filter_nearest;
uniform sampler2D subs : filter_nearest;
// Alerts district by district (r how strongly, g whether for missiles), when
// the war tracks them (`has_sub_alerts`); else each province's own (row 3).
uniform sampler2D sub_alerts : filter_nearest;
uniform bool has_sub_alerts = false;
uniform sampler2D world : filter_nearest;
uniform bool has_world = false;
uniform vec2 world_pad;
uniform float world_k = 2.0;
uniform float per_unit = 2.0;
uniform sampler2D relief : filter_linear, repeat_disable;
// Where the relief texture lies, in map units.
uniform vec2 relief_origin;
uniform vec2 relief_size = vec2(1.0);
uniform vec2 map_size = vec2(980.0, 720.0);
uniform float grid_step = 60.0;
uniform vec4 edge_col : source_color;
uniform vec4 coast_col : source_color;
uniform vec4 border_col : source_color;
uniform vec4 ours_line : source_color;
uniform vec4 theirs_line : source_color;
uniform vec4 amber_col : source_color;
uniform vec4 red_col : source_color;
uniform vec4 select_col : source_color;
uniform vec4 grid_col : source_color;
// The illustrated terrain under it all (see LiteTerrain): one texel an art
// pixel, `terrain_art` map units, its top left at `terrain_origin`.
uniform sampler2D terrain : filter_nearest;
uniform bool has_terrain = false;
// How strongly the countries' colours wash the terrain, and how much of the
// terrain's own colour is kept (desert and winter maps show more of theirs).
uniform float wash = 0.21;
uniform float keep_sat = 0.75;
uniform float keep_contrast = 0.8;
uniform vec2 terrain_origin;
uniform float terrain_art = 1.25;
// The contested band along the front (see LiteCmdView._update_contested):
// 1 on the line, 0 beyond the band; `contested_extent` map units across.
uniform sampler2D contested : filter_linear, repeat_disable;
uniform vec2 contested_extent = vec2(984.0, 724.0);
uniform bool has_contested = false;
// The light of the hour and the weather (see LiteEnv): the land is multiplied
// by it (the borders, labels and sites are not).
uniform vec3 ambient = vec3(1.0);

float hc(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

int id_at(ivec2 p, ivec2 size) {
	p = clamp(p, ivec2(0), size - ivec2(1));
	return int(texelFetch(ids, p, 0).r * 255.0 + 0.5);
}

int sub_at(ivec2 p, ivec2 size) {
	p = clamp(p, ivec2(0), size - ivec2(1));
	return int(texelFetch(subs, p / 2, 0).r * 255.0 + 0.5);
}

void fragment() {
	ivec2 size = textureSize(ids, 0);
	ivec2 p = ivec2(UV * vec2(size));
	int c = id_at(p, size);
	// Map units, and how many of them a screen pixel spans (worked out before
	// any branch: derivatives need every pixel of a quad).
	vec2 mp = UV * map_size;
	float w = max(fwidth(mp.x), 0.001);
	vec2 tuv = (mp - relief_origin) / relief_size;
	float elev = texture(relief, tuv).r;
	// Contour levels, and how many of them a pixel spans (for crisp lines).
	float ce = elev * 16.0;
	float cw = max(fwidth(ce), 0.0001);
	// How contested this spot is (see has_contested), and how fast that
	// changes across a pixel (for the trenches' width).
	float cz = has_contested ? texture(contested, mp / contested_extent).r : 0.0;
	float czw = max(fwidth(cz), 0.0005);
	if (c == 255) {
		COLOR = vec4(0.0);
	} else {
		vec3 fill = texelFetch(palette, ivec2(c, 0), 0).rgb;
		float side = texelFetch(palette, ivec2(c, 1), 0).r;
		float group = texelFetch(palette, ivec2(c, 2), 0).r;
		vec4 st = texelFetch(palette, ivec2(c, 3), 0);
		float diff = 0.0, water = 0.0, same = 0.0, alert_n = 0.0;
		float near = 9.0;
		for (int dy = -2; dy <= 2; dy++) {
			for (int dx = -2; dx <= 2; dx++) {
				if (dx == 0 && dy == 0) continue;
				bool inner = abs(dx) <= 1 && abs(dy) <= 1;
				int n = id_at(p + ivec2(dx, dy), size);
				if (n == 255) {
					if (inner) water += 1.0;
					continue;
				}
				if (n == c) continue;
				if (inner) {
					if (abs(texelFetch(palette, ivec2(n, 2), 0).r - group) < 0.002) {
						same += 1.0;
						continue;
					}
					diff += 1.0;
					alert_n = max(alert_n, texelFetch(palette, ivec2(n, 3), 0).r);
				}
				if (abs(texelFetch(palette, ivec2(n, 1), 0).r - side) > 0.5)
					near = min(near, length(vec2(float(dx), float(dy))) - 0.5);
			}
		}
		int s = sub_at(p, size);
		float district = 0.0;
		for (int k = 0; k < 4; k++) {
			ivec2 o = k == 0 ? ivec2(1, 0) : (k == 1 ? ivec2(-1, 0) : (k == 2 ? ivec2(0, 1) : ivec2(0, -1)));
			if (id_at(p + o, size) == c && sub_at(p + o, size) != s)
				district = 1.0;
		}

		// The terrain, under a see-through wash of its country's colour (blue
		// ours, red theirs), a little lighter as the region's own fill is
		// (under the pointer, selected).
		vec3 col = fill;
		if (has_terrain) {
			ivec2 tq = ivec2(floor((mp - terrain_origin) / terrain_art));
			vec4 tt = texelFetch(terrain, tq, 0);
			// The terrain is the bottom layer: muted, low in contrast.
			vec3 ter = tt.rgb;
			float tl = dot(ter, vec3(0.3, 0.59, 0.11));
			ter = mix(vec3(tl), ter, keep_sat);
			ter = mix(vec3(0.29), ter, keep_contrast);
			vec3 tint = side < 0.5 ? vec3(0.30, 0.52, 0.86) : vec3(0.86, 0.30, 0.28);
			float lum = dot(ter, vec3(0.3, 0.59, 0.11));
			float lift = clamp(dot(fill, vec3(0.33)) * 1.6 - 0.25, 0.0, 0.25);
			// Water, roads and towns keep more of their own colours (the
			// terrain's alpha).
			col = mix(ter, tint * (0.32 + lum * 1.15), wash * tt.a) * (1.0 + lift);
			// Rivers and lakes move: small glints drifting one way.
			if (tt.a < 0.25) {
				vec2 aq = vec2(tq);
				float wv = fract((aq.x * 0.55 + aq.y * 0.9) / 9.0 - TIME * 0.22);
				if (wv < 0.09 && hc(floor(aq / vec2(3.0, 1.0))) < 0.55) col += vec3(0.05, 0.08, 0.08);
				col *= 0.97 + 0.03 * sin(TIME * 0.9 + aq.x * 0.11 + aq.y * 0.07);
			}
		}

		// The contested band along the front: the ground scorched, browner and
		// greyer the nearer the line, pocked with shell craters (a dark pit
		// with a pale rim of thrown-up earth), on the terrain's own pixels.
		if (has_contested && cz > 0.01) {
			float lum2 = dot(col, vec3(0.3, 0.59, 0.11));
			col = mix(col, vec3(lum2) * vec3(1.08, 0.95, 0.8), cz * 0.55);
			col *= 1.0 - cz * 0.1;
			vec2 aq = floor((mp - terrain_origin) / terrain_art);
			// Churned earth in blotches.
			vec2 bl = floor(aq / 3.0);
			if (hc(bl + 1.7) < cz * 0.45)
				col = mix(col, vec3(0.38, 0.31, 0.22), 0.45);
			// Trenches: a zigzag line each side of the front, part way into
			// the band.
			float zig = (abs(mod(aq.x + aq.y, 8.0) - 4.0) - 2.0) * 0.012;
			float tr = abs(cz - 0.58 + zig);
			if (tr < czw * 0.9) col = vec3(0.12, 0.10, 0.08);
			else if (tr < czw * 1.8 && cz - 0.58 + zig > 0.0) col = mix(col, vec3(0.55, 0.48, 0.36), 0.5);
			// Shell craters: a dark pit in a ring of thrown-up earth, lit on
			// its top left.
			vec2 cell = floor(aq / 7.0);
			if (hc(cell) < cz * cz * 0.6) {
				bool big = hc(cell + 5.3) < 0.4;
				vec2 c0 = cell * 7.0 + vec2(2.0 + floor(hc(cell + 3.7) * 3.0), 2.0 + floor(hc(cell + 9.1) * 3.0)) + (big ? vec2(0.5) : vec2(0.0));
				vec2 o = aq + 0.5 - c0;
				float d = length(o);
				float pit = big ? 1.05 : 0.6;
				float ring = big ? 2.1 : 1.5;
				if (d < pit) col = vec3(0.12, 0.10, 0.08);
				else if (d < ring) col = (o.x + o.y < 0.0) ? vec3(0.60, 0.52, 0.38) : vec3(0.30, 0.25, 0.18);
			}
		}

		col *= ambient;

		// Districts, and the provinces of one campaign group, in faint lines.
		col = mix(col, col * 0.72, max(district * 0.45, clamp(same / 3.0, 0.0, 1.0) * 0.6));

		// Under alert: a tint and a diagonal hatch, amber for drones, red for
		// missiles, the country's own colour still showing through.
		float a = st.r;
		float mis = st.g;
		if (has_sub_alerts && s != 255) {
			vec4 sa = texelFetch(sub_alerts, ivec2(s, 0), 0);
			a = sa.r;
			mis = sa.g;
		}
		vec3 acol = mix(amber_col.rgb, red_col.rgb, mis);
		float hatch = fract((mp.x + mp.y) / 9.0);
		float stripe = smoothstep(0.0, w / 9.0 * 1.5, hatch) * (1.0 - smoothstep(0.32, 0.32 + w / 9.0 * 1.5, hatch));
		col = mix(col, mix(col, acol, 0.14), a);
		col = mix(col, acol, a * stripe * 0.3);
		col = mix(col, vec3(1.0, 0.56, 0.26), st.b * 0.35);

		// Borders between provinces: thin and lighter than the fills; in the
		// alert's colour round a region under alert.
		float edge = clamp(diff / 3.0, 0.0, 1.0);
		float an = has_sub_alerts ? a : max(a, alert_n);
		vec3 bc = mix(mix(col, vec3(0.86, 0.9, 0.94), 0.55), acol, an * 0.85);
		col = mix(col, bc, edge * (0.75 + 0.25 * an));
		// The edge of an alerted district inside its province, in the alert's colour.
		col = mix(col, acol, district * a * 0.55);
		// The province selected or under the pointer: a clear outline.
		col = mix(col, select_col.rgb, edge * st.a);

		// The frontier: blue on our side of it, red on theirs.
		float line = 1.0 - smoothstep(0.95, 1.6, near);
		col = mix(col, side < 0.5 ? ours_line.rgb : theirs_line.rgb, line * 0.92);


		// The coast: a crisp line; where a neighbouring country lies, a border.
		float alpha = 1.0;
		if (water > 0.0) {
			bool beside = false;
			if (has_world) {
				vec2 at = (vec2(p) + 0.5) / per_unit;
				ivec2 wsize = textureSize(world, 0);
				ivec2 wp = ivec2((at + world_pad) / world_k);
				for (int dy = -1; dy <= 1; dy++) {
					for (int dx = -1; dx <= 1; dx++) {
						ivec2 qq = clamp(wp + ivec2(dx, dy), ivec2(0), wsize - ivec2(1));
						int wn = int(texelFetch(world, qq, 0).r * 255.0 + 0.5);
						if (wn != 0 && wn != 255) beside = true;
					}
				}
			}
			col = mix(col, beside ? edge_col.rgb : coast_col.rgb, clamp(water / 2.0, 0.0, 1.0));
			if (!beside) alpha = 1.0 - water / 8.0 * 0.5;
		}
		COLOR = vec4(col, alpha);
	}
}
