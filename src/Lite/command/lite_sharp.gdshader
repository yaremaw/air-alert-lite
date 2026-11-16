shader_type canvas_item;

// Pixel art drawn at any size without uneven pixels: every texel is a crisp
// square, its edges blended over one screen pixel ("sharp bilinear"). For the
// site sprites, which are drawn a little smaller or larger than their own
// pixels (see LiteCmdView._sites). Needs the item's filter set to linear.

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 ts = vec2(textureSize(TEXTURE, 0));
	vec2 p = UV * ts;
	vec2 fw = max(fwidth(p), vec2(1e-4));
	vec2 c = floor(p) + 0.5 + clamp((fract(p) - 0.5) / fw, -0.5, 0.5);
	COLOR = texture(TEXTURE, c / ts) * tint;
}
