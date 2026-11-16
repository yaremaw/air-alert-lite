class_name LiteCmdStyle
extends RefCounted
## The command interface's visual language, shared by its buttons, bars and
## panels, in the manner of the map's pixel sprites: panels with their
## corners notched off, a one-pixel light edge on top and a dark one under,
## hard outlines, hatching for what can't be used, small keycaps for
## shortcuts, square indicator lights.

## A panel: `r` with its corners cut by `notch`, filled, outlined in `edge`,
## lit along its top edge and shaded along its bottom one.
static func panel(ci: CanvasItem, r: Rect2, fill: Color, edge: Color, notch: float = 3.0) -> void:
	var pts: PackedVector2Array = _notched(r, notch)
	ci.draw_colored_polygon(pts, fill)
	# Light on top, shade under: one pixel each, inside the outline.
	ci.draw_line(Vector2(r.position.x + notch, r.position.y + 1.5), Vector2(r.end.x - notch, r.position.y + 1.5), Color(1, 1, 1, 0.07), 1.0)
	ci.draw_line(Vector2(r.position.x + notch, r.end.y - 1.5), Vector2(r.end.x - notch, r.end.y - 1.5), Color(0, 0, 0, 0.35), 1.0)
	pts.append(pts[0])
	ci.draw_polyline(pts, edge, 1.0)

## The outline of `r` with its corners cut off by `notch`.
static func _notched(r: Rect2, notch: float) -> PackedVector2Array:
	var a: Vector2 = r.position
	var b: Vector2 = r.end
	var n: float = minf(notch, minf(r.size.x, r.size.y) * 0.3)
	return PackedVector2Array([Vector2(a.x + n, a.y), Vector2(b.x - n, a.y), Vector2(b.x, a.y + n), Vector2(b.x, b.y - n),
		Vector2(b.x - n, b.y), Vector2(a.x + n, b.y), Vector2(a.x, b.y - n), Vector2(a.x, a.y + n)])

## Diagonal hatching over `r` (what is locked or out of reach).
static func hatch(ci: CanvasItem, r: Rect2, col: Color, gap: float = 6.0) -> void:
	var x: float = r.position.x - r.size.y
	while x < r.end.x:
		var p0:= Vector2(x, r.end.y)
		var p1:= Vector2(x + r.size.y, r.position.y)
		# Clip the stripe to the rect.
		if p0.x < r.position.x:
			p0 = Vector2(r.position.x, r.end.y - (r.position.x - p0.x))
		if p1.x > r.end.x:
			p1 = Vector2(r.end.x, r.position.y + (p1.x - r.end.x))
		if p0.x <= p1.x:
			ci.draw_line(p0, p1, col, 1.0)
		x += gap

## A small keycap with `key` on it, its top right corner at `tr`.
static func keycap(ci: CanvasItem, tr: Vector2, key: String) -> void:
	var font: Font = LiteGlyphs.bold
	var w: float = maxf(11.0, font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 6.0)
	var r:= Rect2(tr - Vector2(w, 0), Vector2(w, 12))
	ci.draw_rect(r, Color(LiteTheme.BG, 0.85))
	ci.draw_rect(r, Color(LiteTheme.MUTED, 0.45), false, 1.0)
	ci.draw_line(Vector2(r.position.x + 1, r.end.y - 1), Vector2(r.end.x - 1, r.end.y - 1), Color(LiteTheme.MUTED, 0.6), 1.0)
	ci.draw_string(font, Vector2(r.position.x, r.position.y + 9), key, HORIZONTAL_ALIGNMENT_CENTER, w, 9, Color(LiteTheme.TEXT, 0.8))

## A square indicator light: lit, or dark.
static func led(ci: CanvasItem, c: Vector2, col: Color, on: bool) -> void:
	ci.draw_rect(Rect2(c - Vector2(3, 3), Vector2(6, 6)), Color(0, 0, 0, 0.6))
	ci.draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), col if on else Color(col, 0.22))
	if on:
		ci.draw_rect(Rect2(c - Vector2(2, 2), Vector2(2, 2)), Color(1, 1, 1, 0.45))

## A small padlock, drawn in pixels, centred on `c`.
static func lock(ci: CanvasItem, c: Vector2, col: Color) -> void:
	ci.draw_rect(Rect2(c + Vector2(-4, -1), Vector2(8, 6)), col)
	ci.draw_rect(Rect2(c + Vector2(-3, -5), Vector2(1, 4)), col)
	ci.draw_rect(Rect2(c + Vector2(2, -5), Vector2(1, 4)), col)
	ci.draw_rect(Rect2(c + Vector2(-3, -6), Vector2(6, 1)), col)
	ci.draw_rect(Rect2(c + Vector2(-1, 1), Vector2(2, 2)), Color(LiteTheme.BG, 0.9))

## A bar of `n` blocks, the first `filled` of them lit: health, ammunition.
static func blocks(ci: CanvasItem, r: Rect2, n: int, filled: float, col: Color) -> void:
	var gap: float = 1.0
	var w: float = (r.size.x - gap * (n - 1)) / n
	for i: int in n:
		var on: float = clampf(filled - i, 0.0, 1.0)
		var br:= Rect2(r.position.x + i * (w + gap), r.position.y, w, r.size.y)
		ci.draw_rect(br, Color(col, 0.16))
		if on > 0.0:
			ci.draw_rect(Rect2(br.position, Vector2(br.size.x * on, br.size.y)), col)

## A label in a notched tag: NEWS, BREAKING, RADIO.
static func tag(ci: CanvasItem, at: Vector2, text: String, fill: Color, ink: Color, size: int, h: float) -> float:
	var font: Font = LiteGlyphs.black
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 18.0
	var r:= Rect2(at, Vector2(w, h))
	panel(ci, r, fill, fill.darkened(0.35), 4.0)
	ci.draw_string(font, Vector2(r.position.x, r.position.y + h * 0.5 + size * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, ink)
	return w
