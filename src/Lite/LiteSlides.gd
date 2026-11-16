class_name LiteSlides
extends Control
## The story told in pictures: one full-screen picture after another, with a
## line or two typed out over its lower part. A click shows the whole line,
## then moves on; Esc skips the rest. Without its picture (see
## LiteStory.image) a slide shows on a dark backdrop, the words alone.

var _slides: Array = []
var _at: int = 0
var _then: Callable = Callable()
var _pic: TextureRect = null
var _text: Label = null
var _count: Label = null
var _t: float = 0.0
## Letters shown a second as the line is typed out.
const SPEED: float = 55.0

func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var back:= ColorRect.new()
	back.color = Color("#070b11")
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	_pic = TextureRect.new()
	_pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pic)
	# A dark fall from the middle of the screen down, so the words read on any picture.
	var shade:= TextureRect.new()
	var g:= Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0.02, 0.03, 0.05, 0.92))
	var gt:= GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_left = 0; shade.anchor_right = 1; shade.anchor_top = 0.42; shade.anchor_bottom = 1
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_text = Label.new()
	_text.anchor_left = 0; _text.anchor_right = 1; _text.anchor_top = 1; _text.anchor_bottom = 1
	_text.offset_left = 90; _text.offset_right = -90; _text.offset_top = -210; _text.offset_bottom = -78
	_text.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_override("font", LiteGlyphs.bold)
	_text.add_theme_font_size_override("font_size", 30)
	_text.add_theme_color_override("font_color", Color("#F2F5F8"))
	_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_text.add_theme_constant_override("shadow_offset_y", 2)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)
	_count = Label.new()
	_count.anchor_left = 0; _count.anchor_right = 1; _count.anchor_top = 1; _count.anchor_bottom = 1
	_count.offset_left = 90; _count.offset_right = -90; _count.offset_top = -56; _count.offset_bottom = -30
	_count.add_theme_font_override("font", LiteGlyphs.bold)
	_count.add_theme_font_size_override("font_size", 13)
	_count.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)

## Shows `slides` ([picture key, line] each), then calls `then`.
func play(slides: Array, then: Callable = Callable()) -> void:
	_slides = slides
	_then = then
	_at = -1
	visible = true
	# Over everything made after it, too (the front's strip and cards).
	get_parent().move_child(self, -1)
	_next()

func _next() -> void:
	_at += 1
	if _at >= _slides.size():
		visible = false
		if _then.is_valid():
			_then.call()
		return
	var s: Array = _slides[_at]
	_pic.texture = LiteStory.image(s[0])
	_text.text = s[1]
	_text.visible_characters = 0
	_t = 0.0
	_count.text = ("%d / %d  ·  click to continue  ·  Esc skips" % [_at + 1, _slides.size()]) if _slides.size() > 1 else "Click to continue"

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var n: int = int(_t * SPEED)
	if n != _text.visible_characters and _text.visible_characters >= 0:
		_text.visible_characters = mini(n, _text.text.length())

func _done_typing() -> bool:
	return _text.visible_characters < 0 or _text.visible_characters >= _text.text.length()

func _advance() -> void:
	if not _done_typing():
		_text.visible_characters = -1
		return
	_next()

func _gui_input(e: InputEvent) -> void:
	var mb:= e as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_advance()
		accept_event()

func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	var k:= e as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_ESCAPE:
		_at = _slides.size()
		_next()
	elif k.keycode == KEY_SPACE or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		_advance()
	get_viewport().set_input_as_handled()

## Hidden (itself or a parent), it does no work frame by frame: with dozens
## of these in the menus and the HUD, their _process added up.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_READY:
		set_process(is_visible_in_tree())
