class_name LiteHomeScene
extends Control

## The home screen's background: the cover art (night city, the big drone, the burning
## plant; its logo painted out, see assets/ui/home_bg.jpg), placed so the drone sits to
## the right of the menu with the fire below it, and a very slow push-in so the picture
## is never quite still. One texture, nothing else.

const ART: Vector2 = Vector2(1200, 896)
const FOCUS: Vector2 = Vector2(600, 380)     # the big drone, in the picture's pixels
const TOP_ROW: float = 60.0                  # the picture's row shown at the top of the screen

var _tex: Texture2D = null
var _t: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex = load("res://assets/ui/home_bg.jpg") as Texture2D

func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	draw_rect(Rect2(Vector2.ZERO, size), LiteGlyphs.PAGE)
	if _tex == null:
		return
	# Scale with the window's height; the drone at 62% across, so it clears the menu.
	var s: float = maxf(h / 720.0, 1.0) * 0.97
	var x0: float = w * 0.62 - FOCUS.x * s
	if x0 + ART.x * s < w:
		x0 = w - ART.x * s
	var y0: float = -TOP_ROW * s
	# The push-in: 3% over half a minute and back, round the drone.
	var z: float = 1.0 + 0.03 * (0.5 - 0.5 * cos(_t * TAU / 60.0))
	var c:= Vector2(x0, y0) + FOCUS * s
	var pos: Vector2 = c + (Vector2(x0, y0) - c) * z
	var size_: Vector2 = ART * s * z
	draw_texture_rect(_tex, Rect2(pos, size_), false)
	# The picture's left edge fades into the page under the menu.
	var e0: float = pos.x
	var e1: float = pos.x + 260.0 * s
	var page: Color = LiteGlyphs.PAGE
	draw_polygon(PackedVector2Array([Vector2(e0, 0), Vector2(e1, 0), Vector2(e1, h), Vector2(e0, h)]),
		PackedColorArray([page, Color(page, 0), Color(page, 0), page]))
