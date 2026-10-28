class_name LiteBatch
extends RefCounted
## Collects the map's moving pictures (lines, discs, rings, glyphs) as plain
## triangles and hands them to the renderer in one command. Hundreds of
## weapons with their tracks would otherwise be thousands of separate
## antialiased draw calls a frame. Edges are softened by a thin feather of
## vertices fading to nothing, in place of the renderer's antialiasing.

const FEATHER: float = 0.9
const MAX_VERTS: int = 60000
var _p: PackedVector2Array = PackedVector2Array()
var _c: PackedColorArray = PackedColorArray()
var _i: PackedInt32Array = PackedInt32Array()
var _np: int = 0
var _ni: int = 0
var _unit: PackedVector2Array = PackedVector2Array()
## The points of _unit for a whole circle of n segments, by n.
var _circles: Array[PackedVector2Array] = []
## Shape's points, placed (was the local function At).
var _at: PackedVector2Array = PackedVector2Array()
var _item: RID = RID()


func _init() -> void:
	_p.resize(8192)
	_c.resize(8192)
	_i.resize(24576)
	_unit.resize(66)
	_circles.resize(65)


func begin(ci: CanvasItem) -> void:
	_item = ci.get_canvas_item()
	_np = 0
	_ni = 0


## Sends what has been collected; later draw_* calls of the item go above it.
func flush() -> void:
	if _ni > 0:
		RenderingServer.canvas_item_add_triangle_array(_item, _i.slice(0, _ni), _p.slice(0, _np), _c.slice(0, _np))
	_np = 0
	_ni = 0


func _vert(p: Vector2, c: Color) -> int:
	_p[_np] = p
	_c[_np] = c
	_np += 1
	return _np - 1


func _tri(a: int, b: int, c: int) -> void:
	_i[_ni] = a
	_i[_ni + 1] = b
	_i[_ni + 2] = c
	_ni += 3


func _quad(a: int, b: int, c: int, d: int) -> void:
	_i[_ni] = a
	_i[_ni + 1] = b
	_i[_ni + 2] = c
	_i[_ni + 3] = a
	_i[_ni + 4] = c
	_i[_ni + 5] = d
	_ni += 6


## Makes sure `verts` more vertices (and their triangles) fit, sending the batch first if it is full.
func _room(verts: int) -> void:
	if _np + verts > MAX_VERTS:
		flush()
	if _np + verts > _p.size():
		var n: int = maxi(_p.size() * 2, _np + verts)
		_p.resize(n)
		_c.resize(n)
	# A soft disc, the hungriest shape, takes under five indices a vertex.
	if _ni + verts * 5 > _i.size():
		_i.resize(maxi(_i.size() * 2, _ni + verts * 5))


## Was the Line(a, b, col, width) overload.
func line(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	line_grad(a, b, col, col, width)


## Was the Line(a, b, ca, cb, width) overload: colour `ca` at `a` blending to `cb` at `b`.
func line_grad(a: Vector2, b: Vector2, ca: Color, cb: Color, width: float) -> void:
	var d: Vector2 = b - a
	var length: float = d.length()
	if length < 1e-4:
		return
	_room(8)
	var n: Vector2 = Vector2(-d.y, d.x) / length
	var ca0 := Color(ca, 0.0)
	var cb0 := Color(cb, 0.0)
	# The vertices and triangles go straight into the buffers (as Vert and Quad).
	var k: int = _np
	var q: int = _ni
	if width <= 1.6:
		# Thin: full colour along the middle fading to nothing at both edges.
		var e: Vector2 = n * (width * 0.5 + FEATHER * 0.5)
		_p[k] = a + e
		_c[k] = ca0
		_p[k + 1] = a
		_c[k + 1] = ca
		_p[k + 2] = a - e
		_c[k + 2] = ca0
		_p[k + 3] = b + e
		_c[k + 3] = cb0
		_p[k + 4] = b
		_c[k + 4] = cb
		_p[k + 5] = b - e
		_c[k + 5] = cb0
		_np = k + 6
		# Quad(t, t + 1, t + 4, t + 3), Quad(t + 1, t + 2, t + 5, t + 4)
		_i[q] = k
		_i[q + 1] = k + 1
		_i[q + 2] = k + 4
		_i[q + 3] = k
		_i[q + 4] = k + 4
		_i[q + 5] = k + 3
		_i[q + 6] = k + 1
		_i[q + 7] = k + 2
		_i[q + 8] = k + 5
		_i[q + 9] = k + 1
		_i[q + 10] = k + 5
		_i[q + 11] = k + 4
		_ni = q + 12
		return
	var h: Vector2 = n * (width * 0.5 - FEATHER * 0.5)
	var o: Vector2 = n * (width * 0.5 - FEATHER * 0.5 + FEATHER)
	_p[k] = a + o
	_c[k] = ca0
	_p[k + 1] = a + h
	_c[k + 1] = ca
	_p[k + 2] = a - h
	_c[k + 2] = ca
	_p[k + 3] = a - o
	_c[k + 3] = ca0
	_p[k + 4] = b + o
	_c[k + 4] = cb0
	_p[k + 5] = b + h
	_c[k + 5] = cb
	_p[k + 6] = b - h
	_c[k + 6] = cb
	_p[k + 7] = b - o
	_c[k + 7] = cb0
	_np = k + 8
	# Quad(k, k + 1, k + 5, k + 4), Quad(k + 1, k + 2, k + 6, k + 5), Quad(k + 2, k + 3, k + 7, k + 6)
	for j: int in 3:
		var r: int = k + j
		_i[q] = r
		_i[q + 1] = r + 1
		_i[q + 2] = r + 5
		_i[q + 3] = r
		_i[q + 4] = r + 5
		_i[q + 5] = r + 4
		q += 6
	_ni = q


## A dashed line along the points: `dash` drawn, `gap` left out.
## `pts`: Array[Vector2] (was List<Vector2>) or PackedVector2Array.
func dashed(pts: Variant, col: Color, width: float, dash: float, gap: float) -> void:
	var phase: float = 0.0
	var period: float = dash + gap
	var count: int = pts.size()
	var i: int = 0
	while i + 1 < count:
		var a: Vector2 = pts[i]
		var d: Vector2 = pts[i + 1] - a
		i += 1
		var length: float = d.length()
		if length < 0.01:
			continue
		var u: Vector2 = d / length
		var at: float = 0.0
		while at < length - 1e-3:
			var on: bool = phase < dash
			var step: float = maxf(0.01, minf((dash if on else period) - phase, length - at))
			if on:
				line(a + u * at, a + u * (at + step), col, width)
			at += step
			phase = fmod(phase + step, period)


func _segments(r: float) -> int:
	return clampi(int(r * 0.9) + 6, 6, 64)


func _make_unit(n: int, from: float, span: float) -> void:
	for s: int in n + 1:
		var a: float = from + span * s / n
		_unit[s] = Vector2(cos(a), sin(a))


func disc(c: Vector2, r: float, col: Color, soft: bool = true) -> void:
	var n: int = _segments(r)
	_room(n * 2 + 3)
	# Unit(n, 0, Tau), worked out once for each n.
	if _circles[n].is_empty():
		_make_unit(n, 0, TAU)
		_circles[n] = _unit.slice(0, n + 1)
	var unit: PackedVector2Array = _circles[n]
	var inner: float = maxf(0.1, r - FEATHER * 0.5) if soft else r
	var clear := Color(col, 0.0)
	var center: int = _vert(c, col)
	var first: int = _np
	# The vertices and triangles written straight into the buffers (as Vert, Tri, Quad).
	for s: int in n:
		var u: Vector2 = unit[s]
		_p[_np] = c + u * inner
		_c[_np] = col
		_np += 1
		if soft:
			_p[_np] = c + u * (inner + FEATHER)
			_c[_np] = clear
			_np += 1
	var step: int = 2 if soft else 1
	for s: int in n:
		var a: int = first + s * step
		var b: int = first + (s + 1) % n * step
		_i[_ni] = center
		_i[_ni + 1] = a
		_i[_ni + 2] = b
		_ni += 3
		if soft:
			# Quad(a, a + 1, b + 1, b)
			_i[_ni] = a
			_i[_ni + 1] = a + 1
			_i[_ni + 2] = b + 1
			_i[_ni + 3] = a
			_i[_ni + 4] = b + 1
			_i[_ni + 5] = b
			_ni += 6


func ring(c: Vector2, r: float, col: Color, width: float, from: float = 0, to: float = TAU) -> void:
	var span: float = to - from
	var n: int = clampi(int(_segments(r) * absf(span) / TAU) + 1, 3, 64)
	_room((n + 1) * 4)
	_make_unit(n, from, span)
	var h: float = maxf(0.05, width * 0.5 - FEATHER * 0.5)
	var o: float = h + FEATHER
	if width < FEATHER:
		col.a *= width / FEATHER
	var clear := Color(col, 0.0)
	var first: int = _np
	for s: int in n + 1:
		var u: Vector2 = _unit[s]
		_p[_np] = c + u * (r + o)
		_c[_np] = clear
		_p[_np + 1] = c + u * (r + h)
		_c[_np + 1] = col
		_p[_np + 2] = c + u * (r - h)
		_c[_np + 2] = col
		_p[_np + 3] = c + u * (r - o)
		_c[_np + 3] = clear
		_np += 4
	# Quad(k, k + 1, k + 5, k + 4), Quad(k + 1, k + 2, k + 6, k + 5),
	# Quad(k + 2, k + 3, k + 7, k + 6) for each step, written out.
	var q: int = _ni
	for s: int in n:
		var k: int = first + s * 4
		_i[q] = k
		_i[q + 1] = k + 1
		_i[q + 2] = k + 5
		_i[q + 3] = k
		_i[q + 4] = k + 5
		_i[q + 5] = k + 4
		_i[q + 6] = k + 1
		_i[q + 7] = k + 2
		_i[q + 8] = k + 6
		_i[q + 9] = k + 1
		_i[q + 10] = k + 6
		_i[q + 11] = k + 5
		_i[q + 12] = k + 2
		_i[q + 13] = k + 3
		_i[q + 14] = k + 7
		_i[q + 15] = k + 2
		_i[q + 16] = k + 7
		_i[q + 17] = k + 6
		q += 18
	_ni = q


## A speck too small to need roundness: a square of the same area as a disc of radius `r`.
func dot(c: Vector2, r: float, col: Color) -> void:
	var h: float = r * 0.89
	rect(Rect2(c.x - h, c.y - h, h * 2, h * 2), col)


func rect(r: Rect2, col: Color) -> void:
	_room(4)
	var k: int = _vert(r.position, col)
	_vert(Vector2(r.end.x, r.position.y), col)
	_vert(r.end, col)
	_vert(Vector2(r.position.x, r.end.y), col)
	_quad(k, k + 1, k + 2, k + 3)


## A polygon already cut into triangles (`tris` index `pts`), placed at
## `c`, scaled by `s` and turned by `angle`; a soft rim of its own colour,
## or an outline in another (`outline`: a Color, or null).
func shape(pts: PackedVector2Array, tris: PackedInt32Array, c: Vector2, s: float, angle: float, fill: Color, outline: Variant = null) -> void:
	var count: int = pts.size()
	_room(count * 9 + 8)
	var cs: float = cos(angle)
	var sn: float = sin(angle)
	if _at.size() < count:
		_at.resize(count)
	for i: int in count:
		var v: Vector2 = pts[i] * s
		_at[i] = c + Vector2(v.x * cs - v.y * sn, v.x * sn + v.y * cs)
	var rim: Color = outline if outline != null else Color(fill, fill.a * 0.6)
	var rim_width: float = 2.2 if outline != null else 0.9
	for i: int in count:
		line(_at[i], _at[(i + 1) % count], rim, rim_width)
	var first: int = _np
	for i: int in count:
		_vert(_at[i], fill)
	for t: int in tris:
		_i[_ni] = first + t
		_ni += 1
