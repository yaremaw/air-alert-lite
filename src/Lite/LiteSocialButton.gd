class_name LiteSocialButton
extends Control
## A community link on the home screen: a small square in the network's own
## colour with its symbol on it; its name and what is there show as a
## tooltip. Lifts a little under the pointer; one can carry a sticker.

var title: String = ""
var caption: String = ""
## "discord", "youtube", "telegram", "instagram" or "tiktok".
var kind: String = ""
var sticker: String = ""
var clicked: Callable = Callable()
var _hover: float = 0.0
var _in: bool = false

const SIZE: float = 62.0
const COLOURS: Dictionary = {
	"discord": Color("#5865F2"),
	"youtube": Color("#FF2D2D"),
	"telegram": Color("#2AABEE"),
	"instagram": Color("#E1306C"),
	"tiktok": Color("#111318"),
}

func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "%s · %s" % [title, caption] if caption != "" else title
	mouse_entered.connect(func() -> void: _in = true)
	mouse_exited.connect(func() -> void: _in = false)

func _process(delta: float) -> void:
	var was: float = _hover
	_hover += ((1.0 if _in else 0.0) - _hover) * (1.0 - exp(-delta * 14.0))
	if absf(was - _hover) > 0.002:
		queue_redraw()

func _gui_input(e: InputEvent) -> void:
	var mb:= e as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if clicked.is_valid():
			clicked.call()
		accept_event()

func _draw() -> void:
	var lift: float = -3.0 * _hover
	var r:= Rect2(Vector2(0, lift), size)
	var col: Color = COLOURS.get(kind, LiteTheme.BLUE)
	if kind == "instagram":
		# Its gradient, purple at the top left to orange at the bottom right.
		var a: Color = Color("#833AB4")
		var b: Color = Color("#F77737")
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([a, col, b, col]))
	else:
		draw_rect(r, col)
	draw_rect(r, Color(1, 1, 1, 0.12 + 0.5 * _hover), false, 1.5)
	_icon(r.get_center(), size.y / 68.0)
	if sticker != "":
		# A sticker slapped on the corner, a little crooked.
		var font: Font = LiteGlyphs.black
		var sw: float = font.get_string_size(sticker, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 10.0
		draw_set_transform(Vector2(size.x - 4, lift - 3), 0.12, Vector2.ONE)
		draw_rect(Rect2(Vector2(-sw / 2, -8), Vector2(sw, 15)), Color("#FFD23F"))
		draw_string(font, Vector2(-sw / 2 + 5, 3), sticker, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#1A1A1A"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## The network's symbol, in white, drawn round `c` at scale `s` (1.0 for a
## 68-unit square).
func _icon(c: Vector2, s: float) -> void:
	var w: Color = Color.WHITE
	draw_set_transform(c, 0.0, Vector2(s, s))
	match kind:
		"youtube":
			var body: PackedVector2Array = _round_pts(Rect2(Vector2(-16, -11), Vector2(32, 22)), 6.0)
			draw_colored_polygon(body, w)
			draw_colored_polygon(PackedVector2Array([Vector2(-4, -6), Vector2(7, 0), Vector2(-4, 6)]), COLOURS["youtube"])
		"telegram":
			draw_colored_polygon(PackedVector2Array([Vector2(-15, -1), Vector2(14, -12), Vector2(9, 13), Vector2(1, 6), Vector2(-3, 11), Vector2(-4, 3)]), w)
			draw_line(Vector2(-4, 3), Vector2(10, -8), COLOURS["telegram"], 2.0, true)
		"instagram":
			# A camera: a rounded square outline, a lens, a flash.
			_round_box(Rect2(-14, -14, 28, 28), 7.0, w, 3.2)
			draw_arc(Vector2.ZERO, 6.5, 0, TAU, 32, w, 3.2, true)
			draw_circle(Vector2(8, -8), 2.2, w, true, -1, true)
		"tiktok":
			# A note, with its cyan and red echoes.
			_note(Vector2(-1.5, -1.5), Color("#25F4EE"))
			_note(Vector2(1.5, 1.5), Color("#FE2C55"))
			_note(Vector2.ZERO, w)
		_:
			_discord(w)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _note(o: Vector2, col: Color) -> void:
	draw_rect(Rect2(o + Vector2(1, -15), Vector2(5, 23)), col)
	draw_arc(o + Vector2(-3.5, 8), 5.5, 0, TAU, 24, col, 4.5, true)
	draw_colored_polygon(PackedVector2Array([o + Vector2(6, -15), o + Vector2(14, -8), o + Vector2(14, -3), o + Vector2(6, -9)]), col)

func _round_box(r: Rect2, rad: float, col: Color, width: float) -> void:
	var pts: PackedVector2Array = _round_pts(r, rad)
	pts.append(pts[0])
	draw_polyline(pts, col, width, true)

## A rectangle's outline with its corners rounded to `rad`.
static func _round_pts(r: Rect2, rad: float) -> PackedVector2Array:
	var pts:= PackedVector2Array()
	var corners: Array[Vector2] = [r.end - Vector2(rad, rad), Vector2(r.position.x + rad, r.end.y - rad), r.position + Vector2(rad, rad), Vector2(r.end.x - rad, r.position.y + rad)]
	for i: int in 4:
		for j: int in 7:
			var a: float = i * PI / 2 + j * (PI / 2) / 6.0
			pts.append(corners[i] + Vector2.from_angle(a) * rad)
	return pts

## The Discord mascot's head: a smooth outline through half of its points
## (mirrored for the other half), and its two eyes.
const _CLYDE: Array[Vector2] = [Vector2(0.0, 5.7), Vector2(-3.4, 5.0), Vector2(-6.3, 4.1), Vector2(-8.1, 5.3),
	Vector2(-10.4, 10.0), Vector2(-11.5, 16.6), Vector2(-9.6, 18.8), Vector2(-5.9, 20.4), Vector2(-4.5, 18.3),
	Vector2(-2.2, 18.0), Vector2(0.0, 18.2)]

func _discord(col: Color) -> void:
	var half: Array[Vector2] = _CLYDE
	var ring: Array[Vector2] = half.duplicate()
	for i: int in range(half.size() - 2, 0, -1):
		ring.append(Vector2(-half[i].x, half[i].y))
	var pts:= PackedVector2Array()
	var n: int = ring.size()
	const K: float = 1.45
	var mid:= Vector2(0, 12.2)
	for i: int in n:
		var p0: Vector2 = ring[(i - 1 + n) % n]
		var p1: Vector2 = ring[i]
		var p2: Vector2 = ring[(i + 1) % n]
		var p3: Vector2 = ring[(i + 2) % n]
		for j: int in 6:
			var t: float = j / 6.0
			var q: Vector2 = 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)
			pts.append((q - mid) * K)
	draw_colored_polygon(pts, col)
	var eye: Color = COLOURS["discord"]
	_eye(Vector2(-4.0, 13.0), eye, mid, K)
	_eye(Vector2(4.0, 13.0), eye, mid, K)

## An eye: an upright oval.
func _eye(at: Vector2, col: Color, mid: Vector2, k: float) -> void:
	var pts:= PackedVector2Array()
	for i: int in 20:
		var a: float = TAU * i / 20.0
		pts.append((at + Vector2(cos(a) * 2.1, sin(a) * 2.35) - mid) * k)
	draw_colored_polygon(pts, col)

## Hidden (itself or a parent), it does no work frame by frame: with dozens
## of these in the menus and the HUD, their _process added up.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_READY:
		set_process(is_visible_in_tree())
