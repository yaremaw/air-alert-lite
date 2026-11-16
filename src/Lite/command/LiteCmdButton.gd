class_name LiteCmdButton
extends Control
## A button of the Modern Military Command interface (see LiteCmdUi): an icon
## (a site or weapon glyph, or one of LiteCmdIcons) or a short text, a hotkey
## in its corner, a price or caption under it. Selected: a tinted face and an
## accent bar on its leading edge. Redrawn only when its state changes.

var glyph: int = -1
var icon: String = ""
var text: String = ""
var key: String = ""
var sub: String = ""
var selected: bool = false
## Dimmed (and its caption red) when it can't be afforded.
var enabled: bool = true
var accent: Color = LiteTheme.BLUE
## Where the selected bar is: on the left (toolbar) or along the bottom.
var bar_left: bool = true
var font_size: int = 11
var sub_size: int = 12
var clicked: Callable = Callable()
## A pixel sprite instead of a glyph (a region of a sprite sheet), how big it
## is drawn and its tint.
var sprite: Texture2D = null
var sprite_region: Rect2 = Rect2()
var sprite_size: float = 34.0
var sprite_tint: Color = Color.WHITE

var _hover: float = 0.0
var _sel: float = 0.0
var _in: bool = false
var _drawn: String = ""

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE
	mouse_entered.connect(func() -> void: _in = true)
	mouse_exited.connect(func() -> void: _in = false)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var k: float = 1 - exp(-delta * 16.0)
	_hover += ((1.0 if _in else 0.0) - _hover) * k
	_sel += ((1.0 if selected else 0.0) - _sel) * k
	var now: String = "%d|%d|%s|%s|%s|%s" % [int(_hover * 32), int(_sel * 32), enabled, text, sub, key]
	if now != _drawn:
		_drawn = now
		refresh()

func _gui_input(e: InputEvent) -> void:
	var mb:= e as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if clicked.is_valid():
			clicked.call()
		accept_event()

## The painter that draws it with its neighbours (see Painter), or null:
## it draws itself.
var painter: Control = null

## To be drawn again (by its painter, if it has one).
func refresh() -> void:
	if painter != null:
		painter.queue_redraw()
	else:
		queue_redraw()

func _draw() -> void:
	if painter != null:
		return
	for pass_: int in PASSES:
		paint(self, pass_)

## How many passes it is drawn in (see paint).
const PASSES: int = 4

## The hatching over what is locked or out of reach, as a small tile.
static var _hatch: Texture2D = null

static func hatch_tile() -> Texture2D:
	if _hatch == null:
		var img:= Image.create_empty(6, 6, false, Image.FORMAT_RGBA8)
		for i: int in 6:
			img.set_pixel(i, 5 - i, Color(1, 1, 1, 1))
		_hatch = ImageTexture.create_from_image(img)
	return _hatch

## A notched panel (as LiteCmdStyle.panel) in filled rectangles only: they
## batch into one draw call with the rest of the toolbar's.
static func _panel_rects(ci: CanvasItem, r: Rect2, fill: Color, edge: Color, notch: float) -> void:
	var a: Vector2 = r.position.round()
	var w: float = roundf(r.size.x)
	var h: float = roundf(r.size.y)
	var n: float = roundf(minf(notch, minf(w, h) * 0.3))
	ci.draw_rect(Rect2(a.x + n, a.y, w - 2.0 * n, h), fill)
	ci.draw_rect(Rect2(a.x, a.y + n, n, h - 2.0 * n), fill)
	ci.draw_rect(Rect2(a.x + w - n, a.y + n, n, h - 2.0 * n), fill)
	# The light top edge, the shaded bottom one.
	ci.draw_rect(Rect2(a.x + n, a.y + 1, w - 2.0 * n, 1), Color(1, 1, 1, 0.07))
	ci.draw_rect(Rect2(a.x + n, a.y + h - 2, w - 2.0 * n, 1), Color(0, 0, 0, 0.35))
	# The outline, its cut corners in steps.
	ci.draw_rect(Rect2(a.x + n, a.y, w - 2.0 * n, 1), edge)
	ci.draw_rect(Rect2(a.x + n, a.y + h - 1, w - 2.0 * n, 1), edge)
	ci.draw_rect(Rect2(a.x, a.y + n, 1, h - 2.0 * n), edge)
	ci.draw_rect(Rect2(a.x + w - 1, a.y + n, 1, h - 2.0 * n), edge)
	for i: int in int(n):
		ci.draw_rect(Rect2(a.x + n - 1 - i, a.y + i, 1, 1), edge)
		ci.draw_rect(Rect2(a.x + w - n + i, a.y + i, 1, 1), edge)
		ci.draw_rect(Rect2(a.x + n - 1 - i, a.y + h - 1 - i, 1, 1), edge)
		ci.draw_rect(Rect2(a.x + w - n + i, a.y + h - 1 - i, 1, 1), edge)

## One pass of it, drawn on `ci` (its transform at this button's corner):
## 0 its shapes, 1 hatching, 2 its sprite, 3 its words. A painter draws all its buttons'
## shapes, then all their sprites, then all their words: a few draw calls
## for a whole toolbar instead of half a dozen for each button (each texture
## change is a draw call, and on a weak GPU each costs).
func paint(ci: CanvasItem, pass_: int) -> void:
	var r:= Rect2(Vector2.ZERO, size).grow(-0.5)
	var locked: bool = sub == "LOCKED" or sub == "LOCK"
	var has_sub: bool = sub != ""
	var strip_h: float = 15.0 if has_sub and size.y >= 40 else 0.0
	var cy: float = (size.y - strip_h) / 2.0 + (1.0 if strip_h > 0.0 else (-8.0 if has_sub else 0.0))
	var c:= Vector2(size.x / 2.0, cy)
	var ink: Color = LiteTheme.MUTED.lerp(LiteTheme.TEXT, maxf(_sel, _hover * 0.7))
	if not enabled:
		ink = Color(ink, 0.45)
	var kw: float = maxf(11.0, LiteGlyphs.bold.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 6.0)
	var kr:= Rect2(Vector2(size.x - 3, 3) - Vector2(kw, 0), Vector2(kw, 12))
	match pass_:
		0:
			# The face: dark, lighter under the pointer, tinted when selected.
			var face: Color = LiteTheme.PANEL.lerp(LiteTheme.PANEL_HI, _hover).lerp(accent.darkened(0.7), _sel)
			if not enabled:
				face = face.darkened(0.25)
			var edge: Color = LiteTheme.BORDER.lerp(accent, _sel * 0.85).lerp(LiteTheme.MUTED, _hover * 0.25 * (1.0 - _sel))
			_panel_rects(ci, r, face, edge, 3.0 if size.y > 24 else 2.0)
			if _sel > 0.02:
				if bar_left:
					ci.draw_rect(Rect2(r.position.x + 1, r.position.y + 3, 3, r.size.y - 6), Color(accent, _sel))
				else:
					ci.draw_rect(Rect2(r.position.x + 3, r.end.y - 3, r.size.x - 6, 2), Color(accent, _sel))
			# A strip at the foot for the price or caption.
			if strip_h > 0.0:
				var st:= Rect2(r.position.x + 2, r.end.y - strip_h - 1, r.size.x - 4, strip_h)
				ci.draw_rect(st, Color(0, 0, 0, 0.28))
				ci.draw_rect(Rect2(st.position, Vector2(st.size.x, 1)), Color(LiteTheme.BORDER, 0.8))
			if sprite == null:
				if glyph >= 0:
					LiteGlyphs.draw_ci(ci, glyph, c, 1.45, ink, -PI / 4 if glyph == LiteGlyph.DRONE or glyph == LiteGlyph.CRUISE or glyph == LiteGlyph.BALLISTIC else 0.0)
				elif icon != "":
					LiteCmdIcons.draw(ci, icon, c, 1.0, ink)
			if locked:
				LiteCmdStyle.lock(ci, c + Vector2(0, -1), Color(LiteTheme.RED, 0.9))
			if key != "":
				var k2: Rect2 = Rect2(kr.position.round(), kr.size.round())
				ci.draw_rect(k2, Color(LiteTheme.BG, 0.85))
				var kc:= Color(LiteTheme.MUTED, 0.45)
				ci.draw_rect(Rect2(k2.position, Vector2(k2.size.x, 1)), kc)
				ci.draw_rect(Rect2(k2.position.x, k2.end.y - 1, k2.size.x, 1), Color(LiteTheme.MUTED, 0.6))
				ci.draw_rect(Rect2(k2.position, Vector2(1, k2.size.y)), kc)
				ci.draw_rect(Rect2(k2.end.x - 1, k2.position.y, 1, k2.size.y), kc)
		1:
			if not enabled or locked:
				ci.draw_texture_rect(hatch_tile(), r.grow(-2), true, Color(0, 0, 0, 0.28 if not locked else 0.4))
		2:
			if sprite != null:
				var sz: float = minf(sprite_size, minf(size.x - 12, size.y - strip_h - 8))
				var tint: Color = sprite_tint if enabled else Color(sprite_tint, 0.4)
				ci.draw_texture_rect_region(sprite, Rect2(c - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), sprite_region, tint)
		_:
			if sprite == null and glyph < 0 and icon == "" and text != "":
				ci.draw_string(LiteGlyphs.bold, Vector2(0, cy + font_size * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, ink)
			if has_sub:
				var sc: Color = (LiteTheme.TEXT if _sel > 0.5 else LiteTheme.MUTED) if enabled else Color(LiteTheme.RED, 0.85)
				if locked:
					sc = Color(LiteTheme.RED, 0.85)
				var sy: float = (r.end.y - 4.0) if strip_h > 0.0 else (size.y - 7)
				ci.draw_string(LiteGlyphs.bold, Vector2(0, sy), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x, sub_size, sc)
			if key != "":
				ci.draw_string(LiteGlyphs.bold, Vector2(kr.position.x, kr.position.y + 9), key, HORIZONTAL_ALIGNMENT_CENTER, kw, 9, Color(LiteTheme.TEXT, 0.8))

## Draws a group of buttons (all those under `root`) itself, pass by pass
## (see paint); the buttons draw nothing of their own. Over them, letting the
## pointer through.
class Painter extends Control:
	var buttons: Array[LiteCmdButton] = []

	func _init(root: Node) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is LiteCmdButton:
				var b: LiteCmdButton = n
				b.painter = self
				buttons.append(b)
				b.resized.connect(queue_redraw)
				b.visibility_changed.connect(queue_redraw)
			for c: Node in n.get_children():
				stack.append(c)

	func _draw() -> void:
		for pass_: int in LiteCmdButton.PASSES:
			for b: LiteCmdButton in buttons:
				if not is_instance_valid(b) or not b.is_visible_in_tree():
					continue
				draw_set_transform(b.global_position - global_position)
				b.paint(self, pass_)
		draw_set_transform(Vector2.ZERO)

## Hidden (itself or a parent), it does no work frame by frame: with dozens
## of these in the menus and the HUD, their _process added up.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_READY:
		set_process(is_visible_in_tree())
