shader_type canvas_item;

// The lite map: `ids` holds one region id per texel (255 = sea), the
// palette row 0 the colour each region shows now and row 1 its country.
// Fills are flat; a border is drawn wherever a neighbouring texel belongs to
// another region, in a darker shade of the two fills, a touch heavier on the
// frontier between the two countries. The coast fades out over one texel.
uniform sampler2D ids : filter_nearest;
uniform sampler2D palette : filter_nearest;

int id_at(ivec2 p, ivec2 size) {
	p = clamp(p, ivec2(0), size - ivec2(1));
	return int(texelFetch(ids, p, 0).r * 255.0 + 0.5);
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
		float diff = 0.0, frontier = 0.0, water = 0.0;
		for (int dy = -1; dy <= 1; dy++) {
			for (int dx = -1; dx <= 1; dx++) {
				if (dx == 0 && dy == 0) continue;
				int n = id_at(p + ivec2(dx, dy), size);
				if (n == 255) { water += 1.0; continue; }
				if (n != c) {
					diff += 1.0;
					other = min(other, texelFetch(palette, ivec2(n, 0), 0).rgb);
					if (abs(texelFetch(palette, ivec2(n, 1), 0).r - side) > 0.5) frontier += 1.0;
				}
			}
		}
		vec3 border = min(fill, other) * 0.62;
		vec3 col = mix(fill, border, clamp(diff / 3.0, 0.0, 1.0));
		col = mix(col, vec3(0.07, 0.07, 0.08), clamp(frontier / 3.0, 0.0, 1.0) * 0.55);
		COLOR = vec4(col, 1.0 - water / 8.0 * 0.75);
	}
}
