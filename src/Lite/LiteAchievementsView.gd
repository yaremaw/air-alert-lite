class_name LiteAchievementsView
extends Control
## The achievements page, opened from the home screen: a grid of cells, each
## the achievement's picture (assets/ui/achievements/<id>.png, see
## LiteAchievements.ART_DIR; a medal until it has one) and its name; the won
## ones bright, the rest dim, a hidden one a question mark. A click opens a
## cell: the picture large, what it takes, when it was won (or how far
## along), and a quote. Back (or Esc) returns to the menu.

var main: LiteMain = null
var _back: Rect2 = Rect2()
var _hover_back: bool = false
var _cells: Array[Rect2] = []
var _hover: int = -1
## The cell opened, or -1.
var _open: int = -1

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func open() -> void:
	for a: Dictionary in LiteAchievements.LIST:
		LiteAchievements.art(a)
	visible = true
	_open = -1
	move_to_front()
	queue_redraw()
	# Once more a frame later, the pictures surely on the GPU by then.
	get_tree().process_frame.connect(queue_redraw, CONNECT_ONE_SHOT)

## Back: an opened cell first, then the page.
func close() -> void:
	if _open >= 0:
		_open = -1
		queue_redraw()
		return
	visible = false

func _gui_input(e: InputEvent) -> void:
	var mm:= e as InputEventMouseMotion
	if mm != null and _open >= 0:
		# An opened cell covers the page: nothing under it lights up.
		if _hover >= 0 or _hover_back:
			_hover = -1
			_hover_back = false
			mouse_default_cursor_shape = Control.CURSOR_ARROW
			queue_redraw()
	elif mm != null:
		var h: bool = _back.has_point(mm.position)
		var c: int = -1
		for i: int in _cells.size():
			if _cells[i].has_point(mm.position):
				c = i
		if h != _hover_back or c != _hover:
			_hover_back = h
			_hover = c
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h or c >= 0 else Control.CURSOR_ARROW
			queue_redraw()
	var mb:= e as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if main != null:
		main.audio.click()
	if _open >= 0:
		_open = -1
		_hover = -1
	elif _back.has_point(mb.position):
		close()
	else:
		for i: int in _cells.size():
			if _cells[i].has_point(mb.position):
				_open = i
				_hover = -1
				_hover_back = false
	queue_redraw()

func _draw() -> void:
	var vs: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, vs), LiteTheme.BG)
	for x: int in range(0, int(vs.x), 48):
		draw_rect(Rect2(x, 0, 1, vs.y), Color(LiteTheme.BORDER, 0.22))
	for y: int in range(0, int(vs.y), 48):
		draw_rect(Rect2(0, y, vs.x, 1), Color(LiteTheme.BORDER, 0.22))
	var black: Font = LiteGlyphs.black
	var bold: Font = LiteGlyphs.bold
	var list: Array = LiteAchievements.LIST
	var n: int = LiteAchievements.won_count()
	var left: float = 56.0
	draw_string(black, Vector2(left, 70), "ACHIEVEMENTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, LiteTheme.TEXT)
	draw_string(bold, Vector2(left, 96), "%d OF %d WON" % [n, list.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, LiteTheme.AMBER)
	var bar:= Rect2(left + 150, 86, 260, 10)
	draw_rect(bar, LiteTheme.PANEL)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(n) / list.size(), bar.size.y)), LiteTheme.AMBER)
	draw_rect(bar, LiteTheme.BORDER, false, 1.0)
	# The cells.
	var cols: int = 7
	var gap: float = 12.0
	var top: float = 118.0
	var rows: int = ceili(float(list.size()) / cols)
	var cw: float = (vs.x - left * 2 - gap * (cols - 1)) / cols
	var ch: float = minf(cw + 30.0, (vs.y - top - 84 - gap * (rows - 1)) / rows)
	_cells.clear()
	for i: int in list.size():
		var a: Dictionary = list[i]
		var r:= Rect2(left + (i % cols) * (cw + gap), top + (i / cols) * (ch + gap), cw, ch)
		_cells.append(r)
		_cell(r, a, i == _hover)
	# Back.
	_back = Rect2(left, vs.y - 62, 200, 40)
	draw_rect(_back, LiteTheme.PANEL)
	draw_rect(_back, LiteTheme.BLUE if _hover_back else LiteTheme.BORDER, false, 1.5)
	draw_string(black, _back.position + Vector2(20, 27), "BACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, LiteTheme.TEXT)
	if _open >= 0 and _open < list.size():
		_detail(list[_open])

## One cell: its picture (or medal) over its name.
func _cell(r: Rect2, a: Dictionary, hover: bool) -> void:
	var got: bool = LiteAchievements.is_won(a["id"])
	var secret: bool = bool(a.get("hidden", false)) and not got
	draw_rect(r, Color(LiteTheme.PANEL, 0.96 if got else 0.7))
	var pic:= Rect2(r.position + Vector2(4, 4), Vector2(r.size.x - 8, r.size.y - 36))
	draw_rect(pic, Color(LiteTheme.BG, 0.9))
	var tex: Texture2D = LiteAchievements.art(a) if not secret else null
	if tex != null:
		_cover(tex, pic, Color(1, 1, 1, 1.0) if got else Color(0.35, 0.37, 0.42, 1.0))
	elif secret:
		draw_string(LiteGlyphs.black, Vector2(pic.position.x, pic.get_center().y + 16), "?", HORIZONTAL_ALIGNMENT_CENTER, pic.size.x, 44, Color(LiteTheme.MUTED, 0.6))
	else:
		medal(self, pic.get_center() + Vector2(0, -6), minf(pic.size.x, pic.size.y) * 0.26, int(a["icon"]), got)
	var name: String = "???" if secret else String(a["title"]).to_upper()
	draw_string(LiteGlyphs.black, Vector2(r.position.x + 6, r.end.y - 12), name, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 12, 11, LiteTheme.TEXT if got else Color(LiteTheme.TEXT, 0.55))
	draw_rect(r, LiteTheme.AMBER if got else (LiteTheme.BLUE if hover else LiteTheme.BORDER), false, 2.0 if got else 1.0)

## An opened cell: the picture large, its name, what it takes, when won or
## how far along, its quote.
func _detail(a: Dictionary) -> void:
	var vs: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.7))
	var got: bool = LiteAchievements.is_won(a["id"])
	var secret: bool = bool(a.get("hidden", false)) and not got
	var w: float = minf(900.0, vs.x - 80.0)
	var h: float = 400.0
	var r:= Rect2((vs - Vector2(w, h)) / 2.0, Vector2(w, h))
	draw_rect(r, LiteTheme.PANEL)
	draw_rect(r, LiteTheme.AMBER if got else LiteTheme.BORDER, false, 2.0)
	var pic:= Rect2(r.position + Vector2(20, 20), Vector2(h - 40, h - 40))
	draw_rect(pic, LiteTheme.BG)
	var tex: Texture2D = LiteAchievements.art(a) if not secret else null
	if tex != null:
		_cover(tex, pic, Color(1, 1, 1, 1.0) if got else Color(0.35, 0.37, 0.42, 1.0))
	elif secret:
		draw_string(LiteGlyphs.black, Vector2(pic.position.x, pic.get_center().y + 30), "?", HORIZONTAL_ALIGNMENT_CENTER, pic.size.x, 96, Color(LiteTheme.MUTED, 0.6))
	else:
		medal(self, pic.get_center() + Vector2(0, -20), pic.size.x * 0.26, int(a["icon"]), got)
	var x: float = pic.end.x + 28
	var tw: float = r.end.x - x - 24
	var y: float = r.position.y + 58
	draw_string(LiteGlyphs.black, Vector2(x, y), "???" if secret else String(a["title"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, tw, 28, LiteTheme.TEXT)
	y += 30
	if got:
		var when: Dictionary = Time.get_datetime_dict_from_unix_time(int(LiteAchievements.won[a["id"]]))
		draw_string(LiteGlyphs.bold, Vector2(x, y), "WON %02d.%02d.%d" % [int(when["day"]), int(when["month"]), int(when["year"])], HORIZONTAL_ALIGNMENT_LEFT, tw, 12, LiteTheme.AMBER)
	else:
		var p: Array = LiteAchievements.progress(a)
		draw_string(LiteGlyphs.bold, Vector2(x, y), ("NOT YET · %d / %d" % [p[0], p[1]]) if int(p[1]) > 1 else "NOT YET", HORIZONTAL_ALIGNMENT_LEFT, tw, 12, LiteTheme.MUTED)
	y += 30
	var what: String = String(a.get("hint", a["what"])) if secret else String(a["what"])
	draw_multiline_string(LiteGlyphs.font, Vector2(x, y), what, HORIZONTAL_ALIGNMENT_LEFT, tw, 17, 3, LiteTheme.TEXT)
	if not secret:
		y = r.end.y - 110
		draw_rect(Rect2(x, y - 22, 3, 74), LiteTheme.AMBER)
		draw_multiline_string(LiteGlyphs.font, Vector2(x + 14, y), "“%s”" % a["quote"], HORIZONTAL_ALIGNMENT_LEFT, tw - 14, 16, 3, Color(LiteTheme.TEXT, 0.9))
		draw_string(LiteGlyphs.bold, Vector2(x + 14, y + 46), "— " + String(a["by"]), HORIZONTAL_ALIGNMENT_LEFT, tw - 14, 12, LiteTheme.MUTED)
	draw_string(LiteGlyphs.bold, Vector2(r.position.x, r.end.y + 26), "CLICK TO CLOSE", HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(LiteTheme.MUTED, 0.8))

## A picture covering `r`, cropped to its shape.
func _cover(tex: Texture2D, r: Rect2, tint: Color) -> void:
	var ts: Vector2 = tex.get_size()
	var k: float = maxf(r.size.x / ts.x, r.size.y / ts.y)
	var src_size: Vector2 = r.size / k
	draw_texture_rect_region(tex, r, Rect2((ts - src_size) / 2.0, src_size), tint)

static func medal(ci: CanvasItem, c: Vector2, r: float, icon: int, got: bool) -> void:
	var gold: Color = Color(0.95, 0.74, 0.28) if got else Color(0.36, 0.4, 0.46)
	var dark: Color = Color(0.45, 0.3, 0.08) if got else Color(0.16, 0.18, 0.22)
	# The ribbon behind.
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.7, 0), c + Vector2(-r * 0.2, 0), c + Vector2(-r * 0.45, r * 1.5), c + Vector2(-r * 0.9, r * 1.2)]), Color(0.7, 0.16, 0.14) if got else Color(0.25, 0.27, 0.3))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.2, 0), c + Vector2(r * 0.7, 0), c + Vector2(r * 0.9, r * 1.2), c + Vector2(r * 0.45, r * 1.5)]), Color(0.2, 0.35, 0.7) if got else Color(0.25, 0.27, 0.3))
	ci.draw_circle(c, r, dark)
	ci.draw_circle(c, r * 0.86, gold)
	ci.draw_circle(c, r * 0.68, gold.darkened(0.15))
	var k: float = r * 0.42
	match icon:
		0:
			# A shield.
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-k, -k), c + Vector2(k, -k), c + Vector2(k, 0), c + Vector2(0, k * 1.2), c + Vector2(-k, 0)]), dark)
		1:
			# A crosshair.
			ci.draw_arc(c, k, 0, TAU, 20, dark, maxf(1.0, r * 0.12))
			ci.draw_line(c + Vector2(-k * 1.3, 0), c + Vector2(k * 1.3, 0), dark, maxf(1.0, r * 0.1))
			ci.draw_line(c + Vector2(0, -k * 1.3), c + Vector2(0, k * 1.3), dark, maxf(1.0, r * 0.1))
		2:
			# A star.
			var pts:= PackedVector2Array()
			for i: int in 10:
				var rr: float = k * (1.25 if i % 2 == 0 else 0.5)
				pts.append(c + Vector2.from_angle(-PI / 2 + i * PI / 5) * rr)
			ci.draw_colored_polygon(pts, dark)
		3:
			# A flame.
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -k * 1.3), c + Vector2(k * 0.8, 0), c + Vector2(k * 0.6, k * 0.9), c + Vector2(-k * 0.6, k * 0.9), c + Vector2(-k * 0.8, 0), c + Vector2(-k * 0.2, -k * 0.4)]), dark)
		4:
			# A flag.
			ci.draw_line(c + Vector2(-k * 0.8, -k * 1.2), c + Vector2(-k * 0.8, k * 1.2), dark, maxf(1.0, r * 0.12))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-k * 0.8, -k * 1.2), c + Vector2(k * 1.1, -k * 0.7), c + Vector2(-k * 0.8, -k * 0.1)]), dark)
		6:
			# An atom: three orbits round a core.
			for j: int in 3:
				var pts:= PackedVector2Array()
				for i: int in 25:
					var t: float = i * TAU / 24.0
					pts.append(c + Vector2(cos(t) * k * 1.25, sin(t) * k * 0.45).rotated(j * PI / 3.0))
				ci.draw_polyline(pts, dark, maxf(1.0, r * 0.07))
			ci.draw_circle(c, k * 0.25, dark)
		_:
			# A factory.
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-k, k), c + Vector2(-k, -k * 0.2), c + Vector2(-k * 0.3, k * 0.2), c + Vector2(-k * 0.3, -k * 0.2), c + Vector2(k * 0.4, k * 0.2), c + Vector2(k * 0.4, -k * 1.1), c + Vector2(k, -k * 1.1), c + Vector2(k, k)]), dark)

## The toast when one is won: slides down under the top bar, stays a few
## seconds, goes.
class Toast extends Control:
	var _queue: Array = []
	var _t: float = -1.0
	var main: LiteMain = null
	const STAY: float = 4.2

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func show_one(a: Dictionary) -> void:
		_queue.append(a)
		if _t < 0.0:
			_t = 0.0

	func _process(delta: float) -> void:
		if _t < 0.0:
			return
		_t += delta
		if _t > STAY:
			_queue.pop_front()
			_t = 0.0 if not _queue.is_empty() else -1.0
		queue_redraw()

	func _draw() -> void:
		if _t < 0.0 or _queue.is_empty():
			return
		var a: Dictionary = _queue[0]
		var k: float = clampf(minf(_t / 0.3, (STAY - _t) / 0.4), 0.0, 1.0)
		# The whole toast fades together (the medal too).
		modulate.a = k
		var w: float = 380.0
		var h: float = 64.0
		# Just under the top bar (and an operation's strip), over the map's middle.
		var top: float = LiteTheme.top(main) if main != null and main.started else LiteTheme.TOP
		var cx: float = (size.x - (LiteTheme.LEFT if main != null and main.started else 0.0)) / 2.0
		var r:= Rect2(cx - w / 2.0, top + 8.0 - (1.0 - k) * 16.0, w, h)
		draw_rect(r, Color(LiteTheme.PANEL, 0.97 * k))
		draw_rect(r, Color(LiteTheme.AMBER, k), false, 1.5)
		LiteAchievementsView.medal(self, r.position + Vector2(36, 28), 18, int(a["icon"]), true)
		draw_string(LiteGlyphs.bold, r.position + Vector2(70, 24), "ACHIEVEMENT WON", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(LiteTheme.AMBER, k))
		draw_string(LiteGlyphs.black, r.position + Vector2(70, 46), String(a["title"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w - 84, 18, Color(LiteTheme.TEXT, k))
