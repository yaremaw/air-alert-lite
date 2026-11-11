class_name LiteTutorial
extends Control
## The first time a war (or the campaign's front) is played: a few short tips,
## one at a time, each pointing at what it is about, the war paused meanwhile.
## Next, or Skip for all of it; shown once (see LiteSettings).

var main: LiteMain = null
## The tips: each [title, text, where it points (a Callable giving a screen
## rect, or null), what plays (an Callable run when it shows, or null), an
## animation name].
var _steps: Array = []
var _at: int = 0
var _clock: float = 0.0
var _panel: PanelContainer = null
var _title: Label = null
var _text: Label = null
var _next: Button = null
var _on_done: Callable = Callable()
var _was_paused: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", LiteGlyphs.box(LiteGlyphs.PANEL, LiteGlyphs.YELLOW.darkened(0.2), 12, 16))
	_panel.custom_minimum_size = Vector2(320, 0)
	add_child(_panel)
	var box:= VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_override("font", LiteGlyphs.black)
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", LiteGlyphs.YELLOW)
	box.add_child(_title)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Its width set, or the first layout wraps it a word to a line.
	_text.custom_minimum_size = Vector2(288, 0)
	_text.add_theme_font_size_override("font_size", 14)
	_text.add_theme_color_override("font_color", LiteGlyphs.TEXT)
	box.add_child(_text)
	var row:= HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var skip:= Button.new()
	skip.text = "Skip"
	skip.focus_mode = Control.FOCUS_NONE
	LiteUi._quiet(skip, true)
	skip.custom_minimum_size = Vector2(90, 34)
	skip.pressed.connect(finish)
	row.add_child(skip)
	_next = Button.new()
	_next.focus_mode = Control.FOCUS_NONE
	_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next.custom_minimum_size = Vector2(0, 34)
	_next.pressed.connect(next)
	row.add_child(_next)

var running: bool:
	get: return visible

## Starts the tips; `done` runs once they are over or skipped.
func run(steps: Array, done: Callable) -> void:
	_steps = steps
	_at = -1
	_on_done = done
	_was_paused = main.paused
	main.paused = true
	visible = true
	next()

func next() -> void:
	main.build_tool = null
	_at += 1
	if _at >= _steps.size():
		finish()
		return
	var s: Array = _steps[_at]
	_title.text = s[0]
	_text.text = s[1]
	_next.text = "Got it" if _at == _steps.size() - 1 else "Next  (%d/%d)" % [_at + 1, _steps.size()]
	if s[3] is Callable and (s[3] as Callable).is_valid():
		(s[3] as Callable).call()
	_clock = 0.0
	main.audio.click()
	_place()

func finish() -> void:
	main.build_tool = null
	visible = false
	main.paused = _was_paused
	if _on_done.is_valid():
		_on_done.call()

## The tip goes beside what it points at, on the map side of the screen.
func _place() -> void:
	var r: Rect2 = _target()
	_panel.size = Vector2.ZERO
	_panel.reset_size()
	var sz: Vector2 = _panel.get_combined_minimum_size()
	_panel.size = sz
	var view: Vector2 = get_viewport_rect().size
	var p: Vector2
	if r.size == Vector2.ZERO:
		p = (view - sz) * 0.5
	elif r.position.x > view.x * 0.6:
		p = Vector2(r.position.x - sz.x - 24, r.get_center().y - sz.y * 0.5)
	else:
		p = Vector2(r.end.x + 24, r.get_center().y - sz.y * 0.5)
		if p.x + sz.x > view.x - 300:
			p = Vector2(r.get_center().x - sz.x * 0.5, r.end.y + 24)
	p.x = clampf(p.x, 12, view.x - sz.x - 12)
	p.y = clampf(p.y, 12, view.y - sz.y - 12)
	_panel.position = p

func _target() -> Rect2:
	if _at < 0 or _at >= _steps.size():
		return Rect2()
	var t: Variant = _steps[_at][2]
	if t is Callable and (t as Callable).is_valid():
		return (t as Callable).call()
	return Rect2()

func _process(delta: float) -> void:
	if not visible:
		return
	_clock += delta
	queue_redraw()

func _input(e: InputEvent) -> void:
	if not visible:
		return
	var k: InputEventKey = e as InputEventKey
	if k != null and k.pressed and not k.echo:
		if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER or k.keycode == KEY_SPACE:
			next()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_ESCAPE:
			finish()
			get_viewport().set_input_as_handled()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.25))
	var r: Rect2 = _target()
	if r.size != Vector2.ZERO:
		var pulse: float = 0.5 + 0.5 * sin(_clock * 4.0)
		var g: Rect2 = r.grow(6 + 3 * pulse)
		draw_rect(g, Color(LiteGlyphs.YELLOW, 0.9), false, 2.0)
		draw_rect(g.grow(4), Color(LiteGlyphs.YELLOW, 0.25 * (1 - pulse)), false, 2.0)
	if _at >= 0 and _at < _steps.size() and _steps[_at][4] == "route":
		_draw_route()

## A strike being drawn: a dashed route growing from our land across the
## front to an enemy site, a drone flying it, the cursor at its tip.
func _draw_route() -> void:
	var sim: LiteSim = main.sim
	var to: Vector2 = sim.sides[1].capital.pos
	var from: Vector2 = sim.origin_near(0, to)
	var mid: Vector2 = (from + to) * 0.5 + (to - from).orthogonal().normalized() * 60.0
	var pts: Array[Vector2] = []
	for i: int in 25:
		var t: float = i / 24.0
		pts.append(from.lerp(mid, t).lerp(mid.lerp(to, t), t))
	var t: float = fmod(_clock / 2.4, 1.0)
	var n: int = int(t * 24.0)
	for i: int in n:
		draw_dashed_line(main.to_screen(pts[i]), main.to_screen(pts[i + 1]), Color(LiteGlyphs.YELLOW, 0.95), 2.0, 7.0, true, true)
	var tip: Vector2 = main.to_screen(pts[n])
	draw_circle(tip, 6.0, Color(LiteGlyphs.YELLOW, 0.4))
	draw_circle(tip, 3.0, Color.WHITE)
	var at: Vector2 = main.to_screen(to)
	draw_arc(at, 16.0, 0, TAU, 32, LiteGlyphs.YELLOW, 1.6, true)
	if n > 2:
		var dir: Vector2 = (pts[n] - pts[n - 1]).normalized()
		LiteGlyphs.draw_ci(self, LiteGlyph.DRONE, main.to_screen(pts[maxi(0, n - 3)]), 1.3, LiteGlyphs.OURS, dir.angle())
