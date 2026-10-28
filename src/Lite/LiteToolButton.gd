class_name LiteToolButton
extends Control
## A card in the side panel: icon, name and price. Hover and selection ease
## in rather than snap; a card you cannot afford dims and shows its price red.

var glyph: int = LiteGlyph.CAPITAL
var title: String = ""
var price: String = ""
var key: String = ""
var selected: bool = false
var affordable: bool = true
var accent: Color = LiteGlyphs.OURS
## Was `Action? Clicked`; called on a left click when valid.
var clicked: Callable = Callable()
var _hover: float = 0.0
var _sel: float = 0.0
var _press: float = 0.0
var _in: bool = false
## What was drawn last; the card is redrawn only when this changes.
## (A C# tuple (int, int, int, bool, string); kept as fields to avoid allocating.)
var _drawn_hover: int = 0
var _drawn_sel: int = 0
var _drawn_press: int = 0
var _drawn_affordable: bool = false
var _drawn_price: String = ""
var _box: StyleBoxFlat = LiteGlyphs.box(LiteGlyphs.PANEL, LiteGlyphs.LINE, 9)


func _ready() -> void:
	custom_minimum_size = Vector2(0, 72)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void: _in = true)
	mouse_exited.connect(func() -> void: _in = false)


func _process(delta: float) -> void:
	var tp: float = LitePerf.now
	_process_body(delta)
	LitePerf.ui_proc_ms += LitePerf.now - tp


func _process_body(delta: float) -> void:
	var k: float = 1 - exp(-delta * 14.0)
	_hover += ((1.0 if _in else 0.0) - _hover) * k
	_sel += ((1.0 if selected else 0.0) - _sel) * k
	_press = maxf(0, _press - delta * 5.0)
	var now_hover: int = int(_hover * 64)
	var now_sel: int = int(_sel * 64)
	var now_press: int = int(_press * 64)
	if now_hover != _drawn_hover or now_sel != _drawn_sel or now_press != _drawn_press \
			or affordable != _drawn_affordable or price != _drawn_price:
		_drawn_hover = now_hover
		_drawn_sel = now_sel
		_drawn_press = now_press
		_drawn_affordable = affordable
		_drawn_price = price
		queue_redraw()


func _gui_input(e: InputEvent) -> void:
	var mb := e as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_press = 1
		if clicked.is_valid():
			clicked.call()
		accept_event()


func _draw() -> void:
	var t0: float = LitePerf.now
	_draw_body()
	LitePerf.ui_ms += LitePerf.now - t0


func _draw_body() -> void:
	var dim: float = 1.0 if affordable else 0.45
	_box.bg_color = LiteGlyphs.PANEL.lerp(LiteGlyphs.PANEL_HI, _hover).lerp(accent.darkened(0.68), _sel * 0.9)
	_box.border_color = LiteGlyphs.LINE.lerp(accent, maxf(_sel, _press * 0.6))
	var inset: float = _press * 1.5
	draw_style_box(_box, Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2))
	var lift: float = -2.0 * _hover
	var icon: Color = Color(1, 1, 1, dim).lerp(accent.lightened(0.35), _sel * 0.6)
	var angle: float = -PI / 4 if glyph == LiteGlyph.DRONE or glyph == LiteGlyph.CRUISE else 0.0
	LiteGlyphs.draw_ci(self, glyph, Vector2(size.x / 2, 24 + lift), 1.55, icon, angle)
	draw_string(LiteGlyphs.bold, Vector2(0, 50), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color(LiteGlyphs.TEXT, dim))
	draw_string(LiteGlyphs.font, Vector2(0, 64), price, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, LiteGlyphs.MUTED if affordable else LiteGlyphs.ENEMY)
	if key != "":
		draw_string(LiteGlyphs.font, Vector2(8, 15), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LiteGlyphs.FAINT)
