class_name LiteChip
extends Control
## A small rounded toggle: salvo size, speed, difficulty, switches.

var text: String = ""
var selected: bool = false
var accent: Color = LiteGlyphs.OURS
var font_size: int = 12
## Was `Action? Clicked`; called on a left click when valid.
var clicked: Callable = Callable()
var _hover: float = 0.0
var _sel: float = 0.0
var _in: bool = false
## What was drawn last; the chip is redrawn only when this changes.
## (A C# tuple (int, int, string); kept as three fields to avoid allocating.)
var _drawn_hover: int = 0
var _drawn_sel: int = 0
var _drawn_text: String = ""
var _box: StyleBoxFlat = LiteGlyphs.box(LiteGlyphs.PANEL, LiteGlyphs.LINE, 7)


func _ready() -> void:
	if custom_minimum_size.y == 0:
		custom_minimum_size = Vector2(custom_minimum_size.x, 28)
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
	var now_hover: int = int(_hover * 64)
	var now_sel: int = int(_sel * 64)
	if now_hover != _drawn_hover or now_sel != _drawn_sel or text != _drawn_text:
		_drawn_hover = now_hover
		_drawn_sel = now_sel
		_drawn_text = text
		queue_redraw()


func _gui_input(e: InputEvent) -> void:
	var mb := e as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if clicked.is_valid():
			clicked.call()
		accept_event()


func _draw() -> void:
	var t0: float = LitePerf.now
	_draw_body()
	LitePerf.ui_ms += LitePerf.now - t0


func _draw_body() -> void:
	_box.bg_color = LiteGlyphs.PANEL.lerp(LiteGlyphs.PANEL_HI, _hover).lerp(accent.darkened(0.6), _sel)
	_box.border_color = LiteGlyphs.LINE.lerp(accent, _sel)
	draw_style_box(_box, Rect2(Vector2.ZERO, size))
	var col: Color = LiteGlyphs.MUTED.lerp(Color.WHITE, maxf(_sel, _hover * 0.6))
	draw_string(LiteGlyphs.bold, Vector2(0, size.y / 2 + font_size * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, col)
