shader_type canvas_item;

// The lite map: `ids` holds one region id per texel (255 = sea), the
// palette row 0 the colour each region shows now and row 1 its country.
// Fills are flat; a border is drawn wherever a neighbouring texel belongs to
// another region, in a darker shade of the two fills. The frontier between
// the two countries is an even dark line over that, soft at its sides. The
// coast fades out over one texel.
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
		float diff = 0.0, water = 0.0;
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
					diff += 1.0;
					other = min(other, texelFetch(palette, ivec2(n, 0), 0).rgb);
				}
				if (abs(texelFetch(palette, ivec2(n, 1), 0).r - side) > 0.5)
					near = min(near, length(vec2(float(dx), float(dy))) - 0.5);
			}
		}
		vec3 border = min(fill, other) * 0.62;
		vec3 col = mix(fill, border, clamp(diff / 3.0, 0.0, 1.0));
		// The frontier: one even line about three texels wide, centred on the
		// edge between the countries and soft at its sides, whatever its angle.
		float line = 1.0 - smoothstep(0.55, 1.85, near);
		col = mix(col, vec3(0.07, 0.07, 0.08), line * 0.6);
		COLOR = vec4(col, 1.0 - water / 8.0 * 0.75);
	}
}
