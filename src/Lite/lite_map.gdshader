shader_type canvas_item;

// The lite map: `ids` holds one region id per texel (255 = sea), the
// palette row 0 the colour each region shows now, row 1 its country and row
// 2 its group (the campaign's front draws a group's provinces as one).
// Fills are flat; a border is drawn wherever a neighbouring texel belongs to
// another region, in a darker shade of the two fills. The frontier between
// the two countries is an even dark line over that, soft at its sides. The
// coast fades out over one texel.
uniform sampler2D ids : filter_nearest;
uniform sampler2D palette : filter_nearest;
// The district of each map unit (half the resolution of `ids`): districts
// are drawn as faint lines inside their province.
uniform sampler2D subs : filter_nearest;
// The world round the countries (see LiteWorld), to tell a coast from a land
// border with a neighbour: there the edge is drawn as a line, not faded out.
uniform sampler2D world : filter_nearest;
uniform bool has_world = false;
uniform vec2 world_pad;
uniform float world_k = 2.0;
uniform float per_unit = 2.0;
uniform vec4 edge_col : source_color;

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
	if (c == 255) {
		COLOR = vec4(0.0);
	} else {
		vec3 fill = texelFetch(palette, ivec2(c, 0), 0).rgb;
		float side = texelFetch(palette, ivec2(c, 1), 0).r;
		vec3 other = fill;
		float diff = 0.0, water = 0.0, same = 0.0;
		// How far the frontier is, in texels: the nearest texel of the other
		// country within two, less half a texel to the edge between them.
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
					// A province of the same campaign region: only a faint
					// line, as between districts.
					if (abs(texelFetch(palette, ivec2(n, 2), 0).r - texelFetch(palette, ivec2(c, 2), 0).r) < 0.002) {
						same += 1.0;
						continue;
					}
					diff += 1.0;
					other = min(other, texelFetch(palette, ivec2(n, 0), 0).rgb);
				}
				if (abs(texelFetch(palette, ivec2(n, 1), 0).r - side) > 0.5)
					near = min(near, length(vec2(float(dx), float(dy))) - 0.5);
			}
		}
		// A district edge inside the province: this map unit's district
		// differs from a neighbour's in the same province.
		int s = sub_at(p, size);
		float inner = 0.0;
		for (int k = 0; k < 4; k++) {
			ivec2 o = k == 0 ? ivec2(1, 0) : (k == 1 ? ivec2(-1, 0) : (k == 2 ? ivec2(0, 1) : ivec2(0, -1)));
			if (id_at(p + o, size) == c && sub_at(p + o, size) != s)
				inner = 1.0;
		}
		vec3 border = min(fill, other) * 0.62;
		vec3 col = mix(fill, fill * 0.82, max(inner * 0.7, clamp(same / 3.0, 0.0, 1.0) * 0.8));
		col = mix(col, border, clamp(diff / 3.0, 0.0, 1.0));
		// The frontier: one even line about three texels wide, centred on the
		// edge between the countries and soft at its sides, whatever its angle.
		float line = 1.0 - smoothstep(0.55, 1.85, near);
		col = mix(col, vec3(0.07, 0.07, 0.08), line * 0.6);
		float alpha = 1.0 - water / 8.0 * 0.75;
		if (water > 0.0 && has_world) {
			vec2 at = (vec2(p) + 0.5) / per_unit;
			ivec2 wsize = textureSize(world, 0);
			ivec2 wp = ivec2((at + world_pad) / world_k);
			bool beside = false;
			for (int dy = -1; dy <= 1; dy++) {
				for (int dx = -1; dx <= 1; dx++) {
					ivec2 q = clamp(wp + ivec2(dx, dy), ivec2(0), wsize - ivec2(1));
					int w = int(texelFetch(world, q, 0).r * 255.0 + 0.5);
					if (w != 0 && w != 255) beside = true;
				}
			}
			if (beside) {
				col = mix(col, edge_col.rgb, clamp(water / 3.0, 0.0, 1.0));
				alpha = 1.0;
			}
		}
		COLOR = vec4(col, alpha);
	}
}
