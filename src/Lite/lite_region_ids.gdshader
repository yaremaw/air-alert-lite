shader_type canvas_item;

// An operation's map drawn at full resolution (see LiteRegionMap): for each
// texel, the point of the war's map it shows (through the map's zigzag), the
// four war-map units round that point blended (whichever district holds most
// of their weight), and that district's region on this map. Written as the
// red channel, read back once. Borders come out as smooth curves, where a
// unit at a time drew them in steps.
uniform sampler2D units : filter_nearest; // war map units: district + 1, in two bytes (0: sea)
uniform sampler2D lut : filter_nearest;   // district + 1 -> this map's region id (255: none)
uniform sampler2D zig : filter_linear;    // the zigzag offsets, every `zg` units, 0.5 for none
uniform vec2 origin;  // the war-map point this map's corner shows
uniform float inv;    // war-map units per unit of this map
uniform float zr;     // the zigzag's reach, in war-map units
uniform float zg;
uniform vec2 grid;    // the zigzag grid's size
uniform vec2 cells;   // this map's size (and the war map's), in units

int unit_at(ivec2 q) {
	if (q.x < 0 || q.y < 0 || q.x >= int(cells.x) || q.y >= int(cells.y)) return 0;
	vec2 c = texelFetch(units, q, 0).rg * 255.0 + 0.5;
	return int(c.x) + int(c.y) * 256;
}

void fragment() {
	vec2 x = UV * cells;
	vec2 off = (texture(zig, (x / zg + 0.5) / grid).rg - 0.5) * 2.0 * zr;
	vec2 f = origin + x * inv + off - 0.5;
	vec2 base = floor(f);
	ivec2 b = ivec2(base);
	vec2 t = f - base;
	int k00 = unit_at(b);
	int k10 = unit_at(b + ivec2(1, 0));
	int k01 = unit_at(b + ivec2(0, 1));
	int k11 = unit_at(b + ivec2(1, 1));
	float w00 = (1.0 - t.x) * (1.0 - t.y);
	float w10 = t.x * (1.0 - t.y);
	float w01 = (1.0 - t.x) * t.y;
	float w11 = t.x * t.y;
	float s00 = w00 + (k10 == k00 ? w10 : 0.0) + (k01 == k00 ? w01 : 0.0) + (k11 == k00 ? w11 : 0.0);
	float s10 = w10 + (k00 == k10 ? w00 : 0.0) + (k01 == k10 ? w01 : 0.0) + (k11 == k10 ? w11 : 0.0);
	float s01 = w01 + (k00 == k01 ? w00 : 0.0) + (k10 == k01 ? w10 : 0.0) + (k11 == k01 ? w11 : 0.0);
	float s11 = w11 + (k00 == k11 ? w00 : 0.0) + (k10 == k11 ? w10 : 0.0) + (k01 == k11 ? w01 : 0.0);
	int k = k00;
	float top = s00;
	if (s10 > top) { top = s10; k = k10; }
	if (s01 > top) { top = s01; k = k01; }
	if (s11 > top) { k = k11; }
	float r = texelFetch(lut, ivec2(k, 0), 0).r;
	COLOR = vec4(r, 0.0, 0.0, 1.0);
}
