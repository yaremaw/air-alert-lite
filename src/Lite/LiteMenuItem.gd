class_name LiteMenuItem
extends Control

## One line of the home screen's menu: big capitals, no box. On hover a red bar grows on
## its left and the words slide right; the primary item keeps its bar and its white.

var text: String = ""
var note: String = ""
var primary: bool = false
## The item the game is about (the campaign): framed and lit, gently pulsing.
var featured: bool = false
var _t: float = 0.0
var clicked: Callable = Callable()

var _hover: float = 0.0
var _in: bool = false
var _drawn: int = -1

const H: float = 56.0

func _ready() -> void:
	custom_minimum_size = Vector2(380, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void: _in = true)
	mouse_exited.connect(func() -> void: _in = false)
	visibility_changed.connect(func() -> void: _in = false)

func _process(delta: float) -> void:
	_hover += ((1.0 if _in else 0.0) - _hover) * (1 - exp(-delta * 16.0))
	var now: int = int(_hover * 64)
	if featured:
		_t += delta
		now = int(_t * 30.0)
	if now != _drawn:
		_drawn = now
		queue_redraw()

func _gui_input(e: InputEvent) -> void:
	var mb:= e as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if clicked.is_valid():
			clicked.call()
		accept_event()

func _draw() -> void:
	var h: float = _hover
	if featured:
		# A lit plate behind it, framed in amber, its glow breathing.
		var pulse: float = 0.5 + 0.5 * sin(_t * 2.4)
		# As wide as its words and the note after them, whatever the menu's width.
		var need: float = 36.0 + LiteGlyphs.black.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		if note != "":
			need += 16.0 + LiteGlyphs.bold.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		need += 22.0
		var r:= Rect2(0, 3, maxf(size.x, need), H - 6)
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([Color(LiteGlyphs.YELLOW, 0.24 + 0.08 * h), Color(LiteGlyphs.YELLOW, 0.04), Color(LiteGlyphs.YELLOW, 0.04), Color(LiteGlyphs.YELLOW, 0.24 + 0.08 * h)]))
		draw_rect(r.grow(2.0 + 2.0 * pulse), Color(LiteGlyphs.YELLOW, 0.18 * (1.0 - pulse)), false, 2.0)
		draw_rect(r, Color(LiteGlyphs.YELLOW, 0.85), false, 1.5)
		draw_rect(Rect2(0, r.position.y, 6, r.size.y), LiteGlyphs.YELLOW)
	var bar: float = maxf(h, 1.0 if primary else 0.0)
	if bar > 0.01 and not featured:
		var bh: float = (H - 22) * bar
		draw_rect(Rect2(0, (H - bh) / 2, 5, bh), LiteGlyphs.ENEMY)
	if h > 0.01:
		# A faint band behind the words, fading out to the right.
		var band:= PackedVector2Array([Vector2(5, 6), Vector2(size.x, 6), Vector2(size.x, H - 6), Vector2(5, H - 6)])
		var a: float = 0.16 * h
		draw_polygon(band, PackedColorArray([Color(LiteGlyphs.ENEMY, a), Color(LiteGlyphs.ENEMY, 0), Color(LiteGlyphs.ENEMY, 0), Color(LiteGlyphs.ENEMY, a)]))
	var x: float = 26 + 10 * h
	var col: Color = Color.WHITE if primary else Color(0.78, 0.8, 0.84).lerp(Color.WHITE, h)
	var fs: int = 30
	if featured:
		col = LiteGlyphs.YELLOW.lerp(Color.WHITE, 0.35 + 0.4 * h)
		fs = 34
	draw_string(LiteGlyphs.black, Vector2(x, H / 2 + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	if note != "":
		var w: float = LiteGlyphs.black.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(LiteGlyphs.bold, Vector2(x + w + 16, H / 2 + 5), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			LiteGlyphs.MUTED.lerp(LiteGlyphs.TEXT, h))

## Hidden (itself or a parent), it does no work frame by frame: with dozens
## of these in the menus and the HUD, their _process added up.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_READY:
		set_process(is_visible_in_tree())
