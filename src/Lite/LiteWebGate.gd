class_name LiteWebGate
extends Control
## The web build's first screen: play here in the browser, or download the
## game (better visuals, smoother play) from its itch.io page. Two picture
## tiles, the download one marked as recommended; a click picks one. Shown
## once per page load, over everything; the browser version starts behind it.

const PAGE: String = "https://tenchery.itch.io/strike-alert"

var main: LiteMain = null
var _pics: Array[Texture2D] = []
var _hover: int = -1
var _tiles: Array[Rect2] = []
var _t: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for path: String in ["res://assets/ui/home_bg.jpg", "res://assets/ui/home_war.jpg"]:
		_pics.append(load(path) as Texture2D if ResourceLoader.exists(path) else null)

func _process(delta: float) -> void:
	_t += delta
	# Over everything added to the screen after it.
	if get_parent() != null and get_index() != get_parent().get_child_count() - 1:
		move_to_front()
	queue_redraw()

func _gui_input(e: InputEvent) -> void:
	var mm:= e as InputEventMouseMotion
	if mm != null:
		var h: int = -1
		for i: int in _tiles.size():
			if _tiles[i].has_point(mm.position):
				h = i
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
	var mb:= e as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	for i: int in _tiles.size():
		if _tiles[i].has_point(mb.position):
			if main != null and main.audio != null:
				main.audio.click()
			if i == 0:
				queue_free()
			else:
				OS.shell_open(PAGE)
			accept_event()
			return

func _draw() -> void:
	var font: Font = LiteGlyphs.black
	var bold: Font = LiteGlyphs.bold
	draw_rect(Rect2(Vector2.ZERO, size), LiteTheme.BG)
	# A faint grid, as on the command map.
	for x: int in range(0, int(size.x), 48):
		draw_rect(Rect2(x, 0, 1, size.y), Color(LiteTheme.BORDER, 0.25))
	for y: int in range(0, int(size.y), 48):
		draw_rect(Rect2(0, y, size.x, 1), Color(LiteTheme.BORDER, 0.25))
	var cx: float = size.x / 2.0
	var w: float = minf(size.x * 0.84, 1180.0)
	# The recommendation.
	var top:= Rect2(cx - w / 2.0, size.y * 0.09, w, 74)
	LiteCmdStyle.panel(self, top, LiteTheme.PANEL, LiteTheme.BORDER)
	_center(font, "FOR BETTER VISUALS AND SMOOTHER GAMEPLAY,", Vector2(cx, top.position.y + 32), 22, LiteTheme.AMBER)
	_center(font, "WE RECOMMEND DOWNLOADING THE GAME.", Vector2(cx, top.position.y + 60), 22, LiteTheme.AMBER)
	# The two tiles.
	var gap: float = 48.0
	var tw: float = (w - gap) / 2.0
	var th: float = tw * 0.52
	var ty: float = size.y * 0.36
	_tiles = [Rect2(cx - w / 2.0, ty, tw, th), Rect2(cx + gap / 2.0, ty, tw, th)]
	var heads: Array[String] = ["PLAY IN BROWSER", "DOWNLOAD THE GAME"]
	var subs: Array[String] = ["Starts the game here", "Opens our itch.io page"]
	for i: int in 2:
		var r: Rect2 = _tiles[i]
		_center(font, heads[i], Vector2(r.get_center().x, r.position.y - 44), 26, LiteTheme.TEXT if _hover == i else Color(LiteTheme.TEXT, 0.85))
		_center(bold, subs[i], Vector2(r.get_center().x, r.position.y - 16), 15, LiteTheme.MUTED)
		var lift: float = 4.0 if _hover == i else 0.0
		var rr: Rect2 = r.grow(lift)
		if _pics[i] != null:
			var tex: Texture2D = _pics[i]
			# Cover the tile, cropped to its shape.
			var ts: Vector2 = tex.get_size()
			var k: float = maxf(rr.size.x / ts.x, rr.size.y / ts.y)
			var src_size: Vector2 = rr.size / k
			draw_texture_rect_region(tex, rr, Rect2((ts - src_size) / 2.0, src_size), Color(1, 1, 1, 1.0 if _hover == i else 0.82))
		else:
			draw_rect(rr, LiteTheme.PANEL)
		# The download tile is the recommended one: framed in green.
		var edge: Color = LiteTheme.GREEN if i == 1 else (LiteTheme.BLUE if _hover == i else LiteTheme.BORDER)
		var wdt: float = 5.0 if i == 1 else 2.0
		draw_rect(rr, edge, false, wdt)
		# Its sign in the corner: play, or download.
		var c: Vector2 = rr.position + Vector2(34, rr.size.y - 34)
		draw_circle(c, 22, Color(LiteTheme.BG, 0.8))
		var col: Color = LiteTheme.AMBER
		if i == 0:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -12), c + Vector2(13, 0), c + Vector2(-8, 12)]), col)
		else:
			draw_rect(Rect2(c + Vector2(-3, -13), Vector2(6, 12)), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-10, -2), c + Vector2(10, -2), c + Vector2(0, 8)]), col)
			draw_rect(Rect2(c + Vector2(-12, 10), Vector2(24, 4)), col)
		if i == 1:
			LiteCmdStyle.tag(self, rr.position + Vector2(rr.size.x - 150, 16), "RECOMMENDED", LiteTheme.GREEN, LiteTheme.BG, 12, 22)
	var pulse: float = 0.6 + 0.4 * sin(_t * 3.0)
	_center(font, "CLICK TO SELECT", Vector2(cx, ty + th + 70), 22, Color(LiteTheme.AMBER, pulse))

func _center(font: Font, text: String, at: Vector2, fsize: int, col: Color) -> void:
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_string(font, Vector2(at.x - tw / 2.0, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
