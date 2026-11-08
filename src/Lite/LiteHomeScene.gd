class_name LiteHomeScene
extends Control

## The home screen's background: the cover art (a night city, a plant burning
## between the blocks, its smoke rolling up and away; assets/ui/home_bg.jpg),
## placed so the fire sits to the right of the menu, with a very slow push-in
## so the picture is never quite still. Over it, live: embers rising off the
## fire and drifting with the smoke, the fire's glow flickering on everything
## round it, and now and then a flash far off on the horizon.

const ART: Vector2 = Vector2(1200, 896)
const FOCUS: Vector2 = Vector2(610, 500)     # the fire, in the picture's pixels
const TOP_ROW: float = 60.0                  # the picture's row shown at the top of the screen
## Where embers rise from, in the picture's pixels: the top of the flames.
const FIRE: Rect2 = Rect2(450, 380, 350, 190)
const EMBERS: int = 70

var _tex: Texture2D = null
var _t: float = 0.0
var _rng:= RandomNumberGenerator.new()
## Embers, in the picture's pixels: where, how fast, how old, how long they last.
var _pos:= PackedVector2Array()
var _vel:= PackedVector2Array()
var _age:= PackedFloat32Array()
var _life:= PackedFloat32Array()
## A flash on the horizon: where (x in the picture), when it started.
var _flash_x: float = 0.0
var _flash_at: float = -99.0
var _next_flash: float = 6.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex = load("res://assets/ui/home_bg.jpg") as Texture2D
	_rng.randomize()
	for i: int in EMBERS:
		_pos.append(Vector2.ZERO)
		_vel.append(Vector2.ZERO)
		_age.append(0.0)
		_life.append(1.0)
		_spawn(i)
		# Start them part way through their lives, so the sky is not empty at first.
		_age[i] = _rng.randf() * _life[i]
		_pos[i] += _vel[i] * _age[i]

func _spawn(i: int) -> void:
	_pos[i] = FIRE.position + Vector2(_rng.randf() * FIRE.size.x, _rng.randf() * FIRE.size.y)
	# Up and off to the right, with the smoke.
	_vel[i] = Vector2(_rng.randf_range(4.0, 26.0), -_rng.randf_range(22.0, 55.0))
	_age[i] = 0.0
	_life[i] = _rng.randf_range(3.0, 7.0)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	for i: int in EMBERS:
		_age[i] += delta
		if _age[i] >= _life[i]:
			_spawn(i)
			continue
		# A little sway in the hot air, and the wind picking up higher up.
		var v: Vector2 = _vel[i]
		v.x += (6.0 * sin(_t * 2.3 + i * 1.7) + 4.0) * delta
		_vel[i] = v
		_pos[i] += v * delta
	if _t >= _next_flash:
		_flash_at = _t
		_flash_x = _rng.randf_range(250.0, 1100.0)
		_next_flash = _t + _rng.randf_range(7.0, 16.0)
	queue_redraw()

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	draw_rect(Rect2(Vector2.ZERO, size), LiteGlyphs.PAGE)
	if _tex == null:
		return
	# Scale with the window's height; the fire at 62% across, so it clears the menu.
	var s: float = maxf(h / 720.0, 1.0) * 0.97
	var x0: float = w * 0.62 - FOCUS.x * s
	if x0 + ART.x * s < w:
		x0 = w - ART.x * s
	var y0: float = -TOP_ROW * s
	# The push-in: 3% over half a minute and back, round the fire.
	var z: float = 1.0 + 0.03 * (0.5 - 0.5 * cos(_t * TAU / 60.0))
	var c:= Vector2(x0, y0) + FOCUS * s
	var pos: Vector2 = c + (Vector2(x0, y0) - c) * z
	var k: float = s * z
	draw_texture_rect(_tex, Rect2(pos, ART * k), false)

	# A flash far off: the sky along the horizon lights up and dies away.
	var since: float = _t - _flash_at
	if since < 1.2:
		var f: float = (1.0 - since / 1.2)
		f *= f * (0.7 + 0.3 * sin(since * 40.0))
		_glow(pos + Vector2(_flash_x, 330.0) * k, 260.0 * k, Color(1.0, 0.55, 0.25, 0.22 * f))
	# The fire's light on everything round it, flickering.
	var fl: float = 0.75 + 0.15 * sin(_t * 7.3) + 0.1 * sin(_t * 12.9 + 1.3)
	_glow(pos + FOCUS * k, 330.0 * k, Color(1.0, 0.45, 0.12, 0.13 * fl))
	_glow(pos + (FOCUS + Vector2(0, 20)) * k, 130.0 * k, Color(1.0, 0.7, 0.3, 0.12 * fl))
	# Embers: square, like the picture's own pixels, glowing and fading as they cool.
	var px: float = maxf(2.0, 2.4 * k)
	for i: int in EMBERS:
		var t: float = _age[i] / _life[i]
		var tw: float = 0.6 + 0.4 * sin(_t * 9.0 + i * 2.1)
		var a: float = minf(1.0, t * 6.0) * (1.0 - t) * tw
		var col: Color = Color(1.0, 0.85, 0.45).lerp(Color(1.0, 0.35, 0.1), t)
		var p: Vector2 = (pos + _pos[i] * k).floor()
		var r: float = px * (1.0 if i % 3 else 1.5)
		draw_rect(Rect2(p - Vector2(r, r), Vector2(r, r) * 3.0), Color(col, a * 0.18))
		draw_rect(Rect2(p, Vector2(r, r)), Color(col, a))
	# The picture's left edge fades into the page under the menu.
	var e0: float = pos.x
	var e1: float = pos.x + 260.0 * s
	var page: Color = LiteGlyphs.PAGE
	draw_polygon(PackedVector2Array([Vector2(e0, 0), Vector2(e1, 0), Vector2(e1, h), Vector2(e0, h)]),
		PackedColorArray([page, Color(page, 0), Color(page, 0), page]))

## A soft round light: `col` in the middle, fading to nothing at radius `r`.
func _glow(c: Vector2, r: float, col: Color) -> void:
	const N: int = 24
	var pts:= PackedVector2Array([c])
	var cols:= PackedColorArray([col])
	var clear:= Color(col, 0.0)
	for i: int in N + 1:
		pts.append(c + Vector2.from_angle(i * TAU / N) * r)
		cols.append(clear)
	for i: int in N:
		draw_primitive(PackedVector2Array([pts[0], pts[i + 1], pts[i + 2]]), PackedColorArray([col, clear, clear]), PackedVector2Array())
