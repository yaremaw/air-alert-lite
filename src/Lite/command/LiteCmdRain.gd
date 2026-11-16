class_name LiteCmdRain
extends Node2D
## Phase 4: what falls from the sky in the command look, as particles over
## the part of the map on screen (LiteCmdView draws the weather's light and
## haze in lite_weather.gdshader; this is what moves through it):
##
## - rain: drops falling down the screen, slanted by the wind, in three
##   depths (near ones longer, faster and brighter, far ones short and
##   faint), each its own speed and length; a small splash where a drop
##   lands on water;
## - snow: flakes drifting down slowly, swaying;
## - sand: dust streaking along with the wind, low and fast.
##
## Spawned above the top of the view and dropped when they pass its bottom;
## moved by the frame's time (never by frame count). Drawn in one batch.

## How much of each there is now, 0 to 1 (LiteCmdView sets them).
var rain: float = 0.0
var snow: float = 0.0
var sand: float = 0.0
## Wind: which way the weather blows, in map units a second (x), slanting the
## fall.
var wind: float = 9.0
## The map's area on screen, in map units.
var view: Rect2 = Rect2(0, 0, 980, 720)
## Is this map point water (a splash)? Set by the view.
var water_at: Callable = Callable()

## Each particle: x, y, speed, length, alpha, kind (0 rain, 1 snow, 2 sand),
## and where it lands (y) for a raindrop.
var _p: PackedFloat32Array = PackedFloat32Array()
const STRIDE: int = 7
## Splashes: x, y, age.
var _s: PackedFloat32Array = PackedFloat32Array()
var _pts: PackedVector2Array = PackedVector2Array()
var _cols: PackedColorArray = PackedColorArray()
var _rng:= RandomNumberGenerator.new()
var _carry: Array[float] = [0.0, 0.0, 0.0]

## Most particles at full strength, by kind.
const MOST: Array[int] = [700, 320, 360]

func _ready() -> void:
	_rng.randomize()

func step(dt: float) -> void:
	dt = minf(dt, 0.1)
	var amounts: Array[float] = [rain, snow, sand]
	# Spawn: how many a second each kind wants, by how much of it there is.
	for k: int in 3:
		var want: int = int(MOST[k] * amounts[k])
		var have: int = 0
		for i: int in range(0, _p.size(), STRIDE):
			if int(_p[i + 5]) == k:
				have += 1
		if have >= want:
			continue
		# Fill up over about a second.
		_carry[k] += float(want - have) * dt * 1.5
		while _carry[k] >= 1.0:
			_carry[k] -= 1.0
			_spawn(k, have < want * 0.5)
	# Move.
	var k2: int = 0
	var n: int = _p.size() / STRIDE
	var out:= PackedFloat32Array()
	out.resize(_p.size())
	for j: int in n:
		var i: int = j * STRIDE
		var kind: int = int(_p[i + 5])
		var sp: float = _p[i + 2]
		var x: float = _p[i]
		var y: float = _p[i + 1]
		match kind:
			0:
				y += sp * dt
				x += wind * (sp / 60.0) * dt
			1:
				y += sp * dt
				x += (wind * 0.5 + sin(y * 0.15 + _p[i + 3] * 10.0) * 6.0) * dt
			_:
				x += sp * dt * signf(wind)
				y += sp * 0.12 * dt
		var gone: bool = y > view.end.y + 6.0 or x < view.position.x - 30.0 or x > view.end.x + 30.0
		if kind == 0 and y >= _p[i + 6]:
			# Landed: a splash on water, then gone.
			if water_at.is_valid() and _p[i + 4] > 0.35 and _s.size() < 240 and water_at.call(Vector2(x, y)):
				_s.append_array([x, y, 0.0])
			gone = true
		if gone:
			continue
		for q: int in STRIDE:
			out[k2 * STRIDE + q] = _p[i + q]
		out[k2 * STRIDE] = x
		out[k2 * STRIDE + 1] = y
		k2 += 1
	out.resize(k2 * STRIDE)
	_p = out
	# Splashes age.
	var s2:= PackedFloat32Array()
	for i: int in range(0, _s.size(), 3):
		var age: float = _s[i + 2] + dt
		if age < 0.25:
			s2.append_array([_s[i], _s[i + 1], age])
	_s = s2
	queue_redraw()

## A new particle above the view (or anywhere in it, to fill a fresh
## shower at once).
func _spawn(kind: int, anywhere: bool) -> void:
	var depth: float = _rng.randf()
	var x: float = _rng.randf_range(view.position.x - 20.0, view.end.x + 20.0)
	var y: float = view.position.y - _rng.randf_range(2.0, 40.0)
	if anywhere:
		y = _rng.randf_range(view.position.y, view.end.y)
	var sp: float
	var ln: float
	var al: float
	match kind:
		0:
			# Near drops faster, longer and brighter; far ones faint.
			sp = lerpf(160.0, 300.0, depth) * _rng.randf_range(0.85, 1.15)
			ln = lerpf(3.0, 9.0, depth) * _rng.randf_range(0.7, 1.3)
			al = lerpf(0.2, 0.6, depth)
		1:
			sp = lerpf(10.0, 26.0, depth) * _rng.randf_range(0.8, 1.2)
			ln = lerpf(0.8, 1.8, depth)
			al = lerpf(0.5, 0.95, depth)
		_:
			sp = lerpf(70.0, 150.0, depth) * _rng.randf_range(0.8, 1.2)
			ln = lerpf(4.0, 12.0, depth)
			al = lerpf(0.15, 0.42, depth)
			x = view.position.x - 20.0 if wind > 0.0 else view.end.x + 20.0
			if anywhere:
				x = _rng.randf_range(view.position.x, view.end.x)
			y = _rng.randf_range(view.position.y, view.end.y)
	# Where a raindrop meets the ground: somewhere down the view.
	var land: float = _rng.randf_range(view.position.y + 20.0, view.end.y + 6.0)
	if anywhere and land < y:
		land = y + _rng.randf_range(20.0, 120.0)
	_p.append_array([x, y, sp, ln, al, float(kind), land])

func _draw() -> void:
	_pts.clear()
	_cols.clear()
	for i: int in range(0, _p.size(), STRIDE):
		var kind: int = int(_p[i + 5])
		var x: float = _p[i]
		var y: float = _p[i + 1]
		var ln: float = _p[i + 3]
		var al: float = _p[i + 4]
		match kind:
			0:
				var d:= Vector2(wind * (_p[i + 2] / 60.0), _p[i + 2]).normalized()
				_pts.append(Vector2(x, y) - d * ln)
				_pts.append(Vector2(x, y))
				var c:= Color(0.72, 0.78, 0.88, al)
				_cols.append(c)
			1:
				draw_rect(Rect2(x, y, ln, ln), Color(0.95, 0.97, 1.0, al))
			_:
				_pts.append(Vector2(x - ln * signf(wind), y))
				_pts.append(Vector2(x, y))
				_cols.append(Color(0.78, 0.62, 0.42, al))
	if _pts.size() >= 2:
		draw_multiline_colors(_pts, _cols, 0.9)
	for i: int in range(0, _s.size(), 3):
		var age: float = _s[i + 2]
		var k: float = age / 0.25
		draw_arc(Vector2(_s[i], _s[i + 1]), 0.6 + 1.6 * k, 0.0, TAU, 8, Color(0.8, 0.86, 0.95, 0.5 * (1.0 - k)), 0.5)
