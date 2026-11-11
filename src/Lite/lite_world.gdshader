shader_type canvas_item;

// The world round the two countries (see LiteWorld): the sea, and the
// neighbouring countries in a flat grey darker than either side's, with thin
// lighter lines between them. Its grid is coarse (a cell is two map units),
// so coasts and lines are worked out from the four nearest cells, blended,
// to come out smooth rather than in steps. Under the two countries (255) it
// counts as land where a neighbour is beside it, so their soft edge sits on
// land there, and as sea elsewhere.
uniform sampler2D ids : filter_nearest;
uniform vec4 sea_col : source_color;
uniform vec4 land_col : source_color;
uniform vec4 line_col : source_color;
// On an operation's map the world is the war map's, drawn several times
// larger, so its cells' steps show: there coasts and lines are blended over
// the cells within `soft` of each point, not just the four nearest.
uniform int soft = 0;
// On an operation's map, the war's provinces beyond it: faded, ours lighter
// (ids 100 to 169), the enemy's darker (170 to 253).
uniform vec4 ours_col : source_color;
uniform vec4 theirs_col : source_color;

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
	float w[4] = float[]((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
	bool any_neighbour = false;
	for (int i = 0; i < 4; i++) {
		if (k[i] != 0 && k[i] != 255) any_neighbour = true;
	}
	float land = 0.0, other = 0.0;
	if (soft > 0) {
		// A gaussian over the cells round the point.
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
			if (is_land) land += w[i];
			// Another neighbour's land (not sea, not the two countries).
			if (k[i] != c && k[i] != 0 && k[i] != 255 && c != 0 && c != 255) other += w[i];
		}
	}
	vec3 base = land_col.rgb;
	if (c >= 100 && c < 170) base = ours_col.rgb;
	else if (c >= 170 && c < 254) base = theirs_col.rgb;
	vec3 col = mix(base, line_col.rgb, smoothstep(0.08, 0.4, other));
	col = mix(sea_col.rgb, col, smoothstep(0.3, 0.7, land));
	COLOR = vec4(col, 1.0);
}
