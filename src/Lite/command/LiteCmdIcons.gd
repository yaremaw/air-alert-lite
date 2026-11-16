class_name LiteCmdIcons
extends RefCounted
## The command interface's own line icons (sites and weapons use the game's
## glyphs, LiteGlyphs): one stroke weight, square ends, about 14 px across.

static func draw(ci: CanvasItem, name: String, c: Vector2, s: float, col: Color) -> void:
	var w: float = 1.5 * s
	match name:
		"select":
			var pts:= PackedVector2Array([Vector2(-4, -7), Vector2(5, 2), Vector2(0.5, 2.5), Vector2(3, 7), Vector2(1, 8), Vector2(-1.5, 3.5), Vector2(-4, 6)])
			_poly(ci, pts, c, s, col, w)
		"ranges":
			ci.draw_arc(c, 7.0 * s, 0, TAU, 32, col, w, true)
			ci.draw_arc(c, 3.5 * s, 0, TAU, 24, Color(col, 0.6), w * 0.8, true)
			ci.draw_circle(c, 1.2 * s, col, true, -1, true)
		"routes":
			ci.draw_dashed_line(c + Vector2(-7, 6) * s, c + Vector2(4, -5) * s, col, w, 3.0 * s, true, true)
			ci.draw_line(c + Vector2(6, -7) * s, c + Vector2(0, -6) * s, col, w, true)
			ci.draw_line(c + Vector2(6, -7) * s, c + Vector2(5, -1) * s, col, w, true)
		"stats":
			for i: int in 3:
				var h: float = [5.0, 10.0, 7.0][i] * s
				var x: float = c.x + (i - 1) * 5.0 * s
				ci.draw_line(Vector2(x, c.y + 6 * s), Vector2(x, c.y + 6 * s - h), col, 2.4 * s)
			ci.draw_line(c + Vector2(-8, 7) * s, c + Vector2(8, 7) * s, col, 1.0 * s)
		"menu":
			for i: int in 3:
				var y: float = c.y + (i - 1) * 4.5 * s
				ci.draw_line(Vector2(c.x - 7 * s, y), Vector2(c.x + 7 * s, y), col, w)
		"pause":
			ci.draw_line(c + Vector2(-3, -5) * s, c + Vector2(-3, 5) * s, col, 2.2 * s)
			ci.draw_line(c + Vector2(3, -5) * s, c + Vector2(3, 5) * s, col, 2.2 * s)
		"collapse":
			ci.draw_line(c + Vector2(-3, -5) * s, c + Vector2(2, 0) * s, col, w, true)
			ci.draw_line(c + Vector2(2, 0) * s, c + Vector2(-3, 5) * s, col, w, true)
		"expand":
			ci.draw_line(c + Vector2(3, -5) * s, c + Vector2(-2, 0) * s, col, w, true)
			ci.draw_line(c + Vector2(-2, 0) * s, c + Vector2(3, 5) * s, col, w, true)
		"down":
			ci.draw_line(c + Vector2(-5, -2) * s, c + Vector2(0, 3) * s, col, w, true)
			ci.draw_line(c + Vector2(0, 3) * s, c + Vector2(5, -2) * s, col, w, true)
		"up":
			ci.draw_line(c + Vector2(-5, 2) * s, c + Vector2(0, -3) * s, col, w, true)
			ci.draw_line(c + Vector2(0, -3) * s, c + Vector2(5, 2) * s, col, w, true)
		"warn":
			_poly(ci, PackedVector2Array([Vector2(0, -7), Vector2(7, 6), Vector2(-7, 6)]), c, s, col, w)
			ci.draw_line(c + Vector2(0, -2) * s, c + Vector2(0, 2) * s, col, w)
			ci.draw_circle(c + Vector2(0, 4) * s, 0.9 * s, col)
		"clear":
			ci.draw_arc(c, 6.5 * s, 0, TAU, 32, col, w, true)
			ci.draw_line(c + Vector2(-3, 0) * s, c + Vector2(-0.5, 2.5) * s, col, w, true)
			ci.draw_line(c + Vector2(-0.5, 2.5) * s, c + Vector2(3.5, -2.5) * s, col, w, true)

static func _poly(ci: CanvasItem, pts: PackedVector2Array, c: Vector2, s: float, col: Color, w: float) -> void:
	var loop:= PackedVector2Array()
	for p: Vector2 in pts:
		loop.append(c + p * s)
	loop.append(loop[0])
	ci.draw_polyline(loop, col, w, true)
