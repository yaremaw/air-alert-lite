shader_type canvas_item;
render_mode unshaded, blend_disabled;

// The land and sea round and under the two countries as an illustrated pixel
// map, painted once per map into a texture (see LiteTerrain), one texel an
// art pixel (`art` map units, as the site sprites): six broad biomes (plains,
// steppe, desert, winter, wetlands, forest) blending into each other, calm
// fields, forests of single trees, rivers and lakes, roads with bridges, towns
// and cities; no mountains (since 2026-11-15). The countries' colours go over it later (see
// lite_cmd_map.gdshader); a texel's alpha says how much of them it takes
// (water, roads and buildings keep more of their own colours).

uniform sampler2D ids : filter_nearest;      // the map's regions, 2 a unit; 255 sea
uniform sampler2D world : filter_nearest;    // the world round it, a cell `world_k` units
uniform bool has_world = false;
uniform vec2 world_pad;
uniform float world_k = 2.0;
uniform vec2 map_size = vec2(980.0, 720.0);
uniform vec2 origin;                         // map units of texel (0, 0)
uniform float art = 1.25;                    // map units an art pixel
uniform sampler2D elev : filter_linear;      // 0..1 height
uniform sampler2D moist : filter_linear;     // 0..1 wetness
uniform float climate_t = 0.46;  // the whole map's climate (LiteBiome.climate_shift): warmth aimed at,
uniform float climate_w = 0.0;   // how strongly,
uniform float dry = 1.0;         // and the wetness scale
uniform bool arid = false;       // a desert map: no fields, the steppe gravel and sand
uniform sampler2D temp : filter_linear;      // 0..1 how warm (with the latitude, see warmth)
uniform sampler2D farm : filter_linear;      // 0..1 where fields are
uniform sampler2D feat : filter_nearest;     // r water, g road, b settlement, a bridge
uniform sampler2D atlas : filter_nearest;    // the stamps (assets/ui/terrain.png)

float h1(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float h2(vec2 p) {
	return fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453);
}

// The two countries' own land (not the world round them).
bool countries_at(vec2 q) {
	vec2 mp = origin + (q + 0.5) * art;
	if (mp.x < 0.0 || mp.y < 0.0 || mp.x >= map_size.x || mp.y >= map_size.y) return false;
	int id = int(texelFetch(ids, ivec2(mp * 2.0), 0).r * 255.0 + 0.5);
	return id != 255;
}

bool land_at(vec2 q) {
	vec2 mp = origin + (q + 0.5) * art;
	if (mp.x >= 0.0 && mp.y >= 0.0 && mp.x < map_size.x && mp.y < map_size.y) {
		int id = int(texelFetch(ids, ivec2(mp * 2.0), 0).r * 255.0 + 0.5);
		if (id != 255) return true;
	}
	if (!has_world) return false;
	ivec2 ws = textureSize(world, 0);
	ivec2 wq = clamp(ivec2((mp + world_pad) / world_k), ivec2(0), ws - ivec2(1));
	int w = int(texelFetch(world, wq, 0).r * 255.0 + 0.5);
	return w != 0 && w != 255;
}

vec2 tsize() {
	return vec2(textureSize(feat, 0));
}
float e_at(vec2 q) { return texture(elev, (q + 0.5) / tsize()).r; }
float m_at(vec2 q) { return texture(moist, (q + 0.5) / tsize()).r * dry; }
float t_at(vec2 q) { return texture(temp, (q + 0.5) / tsize()).r; }
vec4 f_at(vec2 q) { return texelFetch(feat, ivec2(q), 0); }

// The biomes: six broad lands that blend into each other over a long way,
// from two very smooth fields, warmth (colder to the north) and wetness.
// Their weights at `q`: x winter, y desert, z steppe, w wetlands; and forest.
float warmth(vec2 q) {
	// Latitude from the map's own north (its top), not the texture's rows.
	float lat = (origin.y + (q.y + 0.5) * art) / map_size.y;
	return mix(mix(t_at(q), clamp(lat, -0.2, 1.2), 0.65), climate_t, climate_w);
}
vec4 biomes(vec2 q) {
	float t = warmth(q);
	float m = m_at(q);
	float e = e_at(q);
	float winter = smoothstep(0.34, 0.26, t);
	float desert = smoothstep(0.62, 0.7, t) * smoothstep(0.44, 0.36, m) * (1.0 - winter);
	float steppe = smoothstep(0.5, 0.58, t) * smoothstep(0.54, 0.46, m) * (1.0 - desert) * (1.0 - winter);
	float wet = smoothstep(0.6, 0.68, m) * smoothstep(0.52, 0.42, e) * (1.0 - desert);
	return vec4(winter, desert, steppe, wet);
}
float forest_at(vec2 q) {
	vec4 b = biomes(q);
	return smoothstep(0.55, 0.63, m_at(q)) * (1.0 - b.y) * (1.0 - b.z) * (1.0 - b.w * 0.7);
}

// A stamp from the atlas: its pixel at `local` (from its top left), its
// rect in the atlas.
vec4 stamp(vec2 local, vec4 rect) {
	if (local.x < 0.0 || local.y < 0.0 || local.x >= rect.z || local.y >= rect.w) return vec4(0.0);
	return texelFetch(atlas, ivec2(rect.xy + local), 0);
}

void fragment() {
	vec2 q = floor(FRAGCOORD.xy);
	bool land = land_at(q);
	vec4 ft = f_at(q);
	float e = e_at(q);
	vec3 col;
	if (!land) {
		// The sea: deep, lighter in the shallows by the coast, a few
		// glints of waves.
		float shallow = 0.0;
		for (int k = 1; k <= 3; k++) {
			float d = float(k) * 2.0;
			if (land_at(q + vec2(d, 0.0)) || land_at(q - vec2(d, 0.0)) || land_at(q + vec2(0.0, d)) || land_at(q - vec2(0.0, d))) {
				shallow = max(shallow, 1.0 - float(k - 1) / 3.0);
			}
		}
		col = mix(vec3(0.09, 0.17, 0.24), vec3(0.15, 0.27, 0.33), shallow);
		if (h1(floor(q / vec2(3.0, 1.0))) < 0.035 && mod(q.y, 4.0) < 1.0) col += vec3(0.05, 0.07, 0.07);
		COLOR = vec4(col, 1.0);
	} else {
		float m = m_at(q);
		vec4 bm = biomes(q);
		// The countries themselves are kept simple (fields, sand, snow): no
		// forests there; the world round them keeps its own.
		bool home = countries_at(q);
		float fo = home ? 0.0 : forest_at(q);
		// The ground of each biome, muted: plains olive-grey and green,
		// steppe dry yellow-green and brown, desert sand, winter dirty white
		// and blue-grey, wetlands dark olive and mud, forest dark green. Each
		// varies a little over a broad field, not pixel by pixel.
		float v = m_at(q * 0.5 + 300.0);
		vec3 plains = mix(vec3(0.36, 0.40, 0.29), vec3(0.32, 0.38, 0.27), v);
		vec3 steppe = mix(vec3(0.47, 0.45, 0.31), vec3(0.45, 0.39, 0.28), v);
		// Sand: warm gold, a little paler or redder over broad fields.
		vec3 desert = mix(vec3(0.80, 0.66, 0.43), vec3(0.74, 0.57, 0.37), v);
		vec3 snow = mix(vec3(0.68, 0.70, 0.71), vec3(0.56, 0.60, 0.65), v);
		vec3 wet = mix(vec3(0.27, 0.30, 0.21), vec3(0.32, 0.28, 0.21), v);
		col = plains;
		col = mix(col, steppe, bm.z);
		col = mix(col, desert, arid ? max(bm.y, 0.75 * bm.z + 0.5 * (1.0 - bm.w)) : bm.y);
		col = mix(col, wet, bm.w);
		// Forest floor (the trees stand on it, see below).
		col = mix(col, vec3(0.19, 0.25, 0.18), smoothstep(0.25, 0.55, fo));
		col = mix(col, snow, bm.x * (1.0 - 0.45 * smoothstep(0.25, 0.55, fo)));
		col *= 0.985 + 0.03 * h1(q);
		// Wetlands: a few dark pools.
		if (bm.w > 0.5 && h1(floor(q / 3.0) + 2.2) < 0.06 * bm.w) col = mix(col, vec3(0.16, 0.22, 0.22), 0.7);
		// Desert: ripples of drifted sand; snow: a few drifts.
		if (bm.y > 0.5 || arid) {
			// Dunes: long crescents across the wind, lit on their crests,
			// a shadow on the lee side, in a few stepped tones; between them
			// gravel flats.
			float warp = 0.9 * sin(q.x * 0.017 + 1.3 * sin(q.y * 0.011)) + 0.6 * sin(q.y * 0.023 + 0.8 * sin(q.x * 0.009 + 2.0));
			float band = fract((q.x * 0.55 + q.y * 0.95) / 11.0 + warp);
			float dune = smoothstep(0.35, 0.6, m_at(q * 0.35 + 77.0) + 0.25);
			vec3 sand = col;
			if (band < 0.08) sand = col * 1.12;
			else if (band < 0.2) sand = col * 0.86;
			else if (band < 0.28) sand = col * 0.93;
			col = mix(col, sand, dune * (arid ? 1.0 : smoothstep(0.5, 0.7, bm.y)));
			// Between the dune fields, gravel flats a shade darker.
			col *= mix(0.94, 1.0, dune);
		}
		if (home && bm.x > 0.5 && h1(floor(q / vec2(4.0, 2.0)) + 9.0) < 0.06) col = mix(col, vec3(0.84, 0.86, 0.88), 0.5);
		// Fields: large calm plots on the plains and the steppe only.
		float fa = texture(farm, (q + 0.5) / tsize()).r;
		float farmland = (1.0 - bm.x) * (1.0 - bm.y) * (1.0 - bm.w) * (1.0 - smoothstep(0.2, 0.4, fo));
		// In the countries the plains are fields almost everywhere.
		if (home) fa = max(fa, 0.66);
		if (arid) farmland = 0.0;
		if (fa > 0.58 && farmland > 0.5) {
			vec2 cs = vec2(20.0, 14.0);
			vec2 cq = floor(q / cs);
			float d1 = 1e9, d2 = 1e9;
			vec2 plot = vec2(0.0);
			for (int j = -1; j <= 1; j++) {
				for (int i = -1; i <= 1; i++) {
					vec2 cc = cq + vec2(float(i), float(j));
					vec2 pt = (cc + vec2(0.15 + 0.7 * h1(cc), 0.15 + 0.7 * h2(cc))) * cs;
					vec2 dd = (q + 0.5 - pt) * vec2(1.0, 1.3);
					float d = dot(dd, dd);
					if (d < d1) { d2 = d1; d1 = d; plot = cc; }
					else if (d < d2) { d2 = d; }
				}
			}
			float pick = h1(plot + 7.3);
			// Clear plots in a few crops: green, golden, ploughed brown.
			vec3 crop = col * (pick < 0.33 ? vec3(0.92, 1.14, 0.88) : (pick < 0.66 ? vec3(1.18, 1.10, 0.82) : vec3(1.02, 0.88, 0.78)));
			if (sqrt(d2) - sqrt(d1) < 1.0) crop = col * 0.78;
			col = mix(col, crop, smoothstep(0.58, 0.62, fa) * smoothstep(0.5, 0.7, farmland));
		}
		// Light from the top left, very gently.
		float sl = (e_at(q - vec2(1.0)) - e_at(q + vec2(1.0))) * 24.0;
		col *= 1.0 + floor(clamp(sl, -1.0, 1.0) * 1.5 + 0.5) / 1.5 * 0.03;

		// Rivers and lakes, their banks darker.
		bool water = ft.r > 0.5;
		float wash = water ? 0.2 : 1.0;
		if (water) {
			col = vec3(0.17, 0.33, 0.42);
			if (h1(q * 1.3) < 0.06) col = vec3(0.26, 0.45, 0.52);
			if (f_at(q - vec2(0.0, 1.0)).r < 0.5) col = vec3(0.26, 0.42, 0.48);
			// In the cold north, rivers and lakes frozen: pale ice, a few
			// cracks and snow drifts on it.
			float ice = biomes(q).x;
			if (ice > 0.5) {
				col = vec3(0.70, 0.78, 0.84);
				if (h1(q * 0.7 + 3.0) < 0.08) col = vec3(0.56, 0.66, 0.74);
				if (h2(q * 1.1) < 0.05) col = vec3(0.86, 0.89, 0.92);
				wash = 0.35;
			}
		} else if (f_at(q + vec2(1.0, 0.0)).r > 0.5 || f_at(q - vec2(1.0, 0.0)).r > 0.5 || f_at(q + vec2(0.0, 1.0)).r > 0.5 || f_at(q - vec2(0.0, 1.0)).r > 0.5) {
			col *= 0.72;
		}
		// Roads, and bridges where they cross water.
		if (ft.a > 0.5) {
			wash = 0.35;
			col = vec3(0.50, 0.42, 0.30);
			if (f_at(q + vec2(1.0, 0.0)).a < 0.5 || f_at(q - vec2(1.0, 0.0)).a < 0.5) col = vec3(0.22, 0.18, 0.14);
		} else if (ft.g > 0.5 && !water) {
			// Roads: visible, but quiet (under the borders and the routes).
			wash = 0.75;
			col = mix(col, vec3(0.58, 0.51, 0.37), 0.55);
		}

		vec4 over = vec4(0.0);
		bool free = !water && ft.g < 0.5;
		// Settlements (LiteSettle): what each pixel is, by its code (blue,
		// as a byte): streets and yards, squares, works yards, parks; and
		// buildings, their kind (roof colour) and part (roof, its lit top
		// edge, the south wall below it, details on the roof). In the snow
		// the roofs go white.
		int code = int(ft.b * 255.0 + 0.5);
		if (code > 0 && free) {
			if (code < 16) {
				vec3 g = vec3(0.30, 0.30, 0.29);
				if (code == 2) g = mix(col, vec3(0.31, 0.34, 0.27), 0.55);
				else if (code == 3) g = vec3(0.50, 0.48, 0.44);
				else if (code == 4) g = vec3(0.34, 0.32, 0.29);
				else if (code == 5) g = vec3(0.21, 0.31, 0.20);
				over = vec4(g, 1.0);
			} else {
				int k = (code - 16) / 8;
				int part = (code - 16) - k * 8;
				vec3 roof = vec3(0.56, 0.56, 0.55);
				if (k == 1) roof = vec3(0.62, 0.65, 0.68);
				else if (k == 2) roof = vec3(0.60, 0.33, 0.27);
				else if (k == 3) roof = vec3(0.50, 0.38, 0.29);
				else if (k == 4) roof = vec3(0.44, 0.49, 0.54);
				else if (k == 5) roof = vec3(0.36, 0.35, 0.34);
				else if (k == 6) roof = vec3(0.78, 0.75, 0.66);
				else if (k == 7) roof = vec3(0.40, 0.48, 0.56);
				else if (k == 8) roof = vec3(0.46, 0.28, 0.22);
				if (part != 2) roof = mix(roof, vec3(0.86, 0.88, 0.91), 0.65 * biomes(q).x);
				vec3 c = roof;
				if (part == 1) c = roof * 1.18;
				else if (part == 2) c = roof * 0.52;
				else if (part == 3) c = roof * 0.62;
				else if (part == 4) c = min(roof * 1.3, vec3(1.0));
				over = vec4(c, 1.0);
			}
		}
		// Trees: forests of them, and a few on their own in the open.
		if (over.a < 0.5 && free) {
			for (int dr = 1; dr >= 0; dr--) {
				float row = floor(q.y / 5.0) + float(dr);
				float off = mod(row, 2.0) * 2.0;
				float colt = floor((q.x - off) / 5.0);
				vec2 anchor = vec2(colt * 5.0 + off, row * 5.0);
				vec2 c2 = anchor + vec2(2.0, 2.0);
				// Dense in the middle of a forest, thinner at its edge; on the open
				// ground only now and then a lone tree.
				vec4 b2 = biomes(c2);
				// Forests dense; the wetlands' scrub and the north's lone firs sparse.
				float dens = countries_at(c2) ? 0.0 : forest_at(c2) * 0.85 + b2.w * 0.05 + b2.x * 0.02;
				vec4 fc = f_at(c2);
				if (h1(vec2(colt, row) + 0.37) < dens && fc.r < 0.5 && fc.g < 0.5 && fc.b < 0.002) {
					float v = h2(vec2(colt, row));
					// Firs in the cold north, broadleaf further south, bushes in the wetlands.
					int kind = b2.x > 0.5 ? (v < 0.6 ? 3 : 0) : (b2.w > 0.5 && forest_at(c2) < 0.3 ? 2 : (v < 0.45 ? 0 : (v < 0.8 ? 1 : 3)));
					vec4 sp = stamp(q - (anchor + vec2(0.0, -2.0)), vec4(float(kind) * 8.0, 0.0, 5.0, 7.0));
					if (sp.a > 0.5) {
						over = sp;
						break;
					}
				}
			}
		}
		if (over.a > 0.5) {
			col = over.rgb;
			if (code > 0) wash = 0.55;
		}
		COLOR = vec4(col, wash);
	}
}
