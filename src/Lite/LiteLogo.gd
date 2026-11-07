class_name LiteLogo
extends Control

## The Strike Alert logo, drawn so it stays sharp at any size: the red crosshair round a
## white attack drone, then STRIKE in white and ALERT in red, and the line under it.
## `scale_k` 1.0 draws the wordmark 64 px tall.

var scale_k: float = 1.0
var tagline: String = "HOLD THE SKY  ·  STRIKE BACK"

## Half of the drone (the other half is its mirror): a narrow nose, a delta wing swept back
## to the tips, the trailing edge stepping in to the tail.
const _DRONE: Array[Vector2] = [Vector2(1.0, 0.0), Vector2(0.78, 0.07), Vector2(0.42, 0.11), Vector2(-0.52, 0.92),
	Vector2(-0.70, 0.92), Vector2(-0.46, 0.20), Vector2(-0.58, 0.10), Vector2(-0.70, 0.0)]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(560, 132) * scale_k

func _draw() -> void:
	var k: float = scale_k
	var r: float = 40.0 * k
	var c:= Vector2(r + 10 * k, r + 8 * k)
	# The crosshair: a ring with four ticks across it.
	draw_arc(c, r, 0, TAU, 72, LiteGlyphs.ENEMY, 7.0 * k, true)
	for a: float in [0.0, PI / 2, PI, PI * 1.5]:
		var d:= Vector2.from_angle(a)
		draw_line(c + d * (r - 9 * k), c + d * (r + 11 * k), LiteGlyphs.ENEMY, 7.0 * k, true)
	# The drone, nose up and to the right, as on the cover.
	var pts:= PackedVector2Array()
	var rot: float = -PI / 4
	var outline: Array[Vector2] = _DRONE.duplicate()
	for i: int in range(_DRONE.size() - 2, 0, -1):
		outline.append(Vector2(_DRONE[i].x, -_DRONE[i].y))
	for p: Vector2 in outline:
		pts.append(c + (p * r * 0.8 + Vector2(r * 0.06, 0)).rotated(rot))
	draw_colored_polygon(pts, Color("#eef0f3"))
	# The wordmark.
	var size: int = int(64 * k)
	var x: float = c.x + r + 30 * k
	var base: float = c.y + size * 0.36
	draw_string(LiteGlyphs.black, Vector2(x, base), "STRIKE", HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color("#eef0f3"))
	x += LiteGlyphs.black.get_string_size("STRIKE ", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(LiteGlyphs.black, Vector2(x, base), "ALERT", HORIZONTAL_ALIGNMENT_LEFT, -1, size, LiteGlyphs.ENEMY)
	if tagline != "":
		var ts: int = int(15 * k)
		var tx: float = c.x + r + 32 * k
		for ch: String in tagline:
			draw_string(LiteGlyphs.bold, Vector2(tx, c.y + r + 34 * k), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, LiteGlyphs.YELLOW)
			tx += LiteGlyphs.bold.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x + 3.2 * k
