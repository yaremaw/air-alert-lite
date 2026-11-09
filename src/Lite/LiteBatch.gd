class_name LiteBatch
extends RefCounted

const FEATHER: float = 0.9
const MAX_VERTS: int = 60000
var _p: PackedVector2Array = PackedVector2Array()
var _c: PackedColorArray = PackedColorArray()
var _i: PackedInt32Array = PackedInt32Array()
var _np: int = 0
var _ni: int = 0
var _unit: PackedVector2Array = PackedVector2Array()

var _circles: Array[PackedVector2Array] = []

var _item: RID = RID()

## Soft puffs (smoke, fire, flashes) are not built from triangles: each is one
## square drawn with a soft round texture, two triangles however big it is.
## They are kept apart and sent in their own batch; whenever the drawing
## switches between puffs and other shapes, what came first is sent first, so
## everything still lands in the order it was drawn.
var _sp: PackedVector2Array = PackedVector2Array()
var _sc: PackedColorArray = PackedColorArray()
var _su: PackedVector2Array = PackedVector2Array()
var _si: PackedInt32Array = PackedInt32Array()
var _snp: int = 0
var _sni: int = 0
static var _soft: ImageTexture = null

func _init() -> void:
	_p.resize(8192)
	_c.resize(8192)
	_i.resize(24576)
	_unit.resize(66)
	_circles.resize(65)
	_sp.resize(4096)
	_sc.resize(4096)
	_su.resize(4096)
	_si.resize(6144)
	if _soft == null:
		_soft = _make_soft()

## The puff texture: white, its alpha 1 in the middle easing to 0 at the rim.
static func _make_soft() -> ImageTexture:
	const N: int = 64
	var img: Image = Image.create_empty(N, N, false, Image.FORMAT_RGBA8)
	for y: int in N:
		for x: int in N:
			var d: float = Vector2(x + 0.5 - N * 0.5, y + 0.5 - N * 0.5).length() / (N * 0.5)
			var a: float = pow(maxf(0.0, 1.0 - d * d), 1.6)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

func begin(ci: CanvasItem) -> void:
	_item = ci.get_canvas_item()
	_np = 0
	_ni = 0
	_snp = 0
	_sni = 0

func flush() -> void:
	_flush_shapes()
	_flush_soft()

func _flush_shapes() -> void:
	if _ni > 0:
		RenderingServer.canvas_item_add_triangle_array(_item, _i.slice(0, _ni), _p.slice(0, _np), _c.slice(0, _np))
	_np = 0
	_ni = 0

func _flush_soft() -> void:
	if _sni > 0:
		RenderingServer.canvas_item_add_triangle_array(_item, _si.slice(0, _sni), _sp.slice(0, _snp), _sc.slice(0, _snp),
			_su.slice(0, _snp), PackedInt32Array(), PackedFloat32Array(), _soft.get_rid())
	_snp = 0
	_sni = 0

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

func _room(verts: int) -> void:
	if _sni > 0:
		_flush_soft()
	if _np + verts > MAX_VERTS:
		_flush_shapes()
	if _np + verts > _p.size():
		var n: int = maxi(_p.size() * 2, _np + verts)
		_p.resize(n)
		_c.resize(n)

	if _ni + verts * 5 > _i.size():
		_i.resize(maxi(_i.size() * 2, _ni + verts * 5))

func line(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	line_grad(a, b, col, col, width)

func line_grad(a: Vector2, b: Vector2, ca: Color, cb: Color, width: float) -> void:
	var d: Vector2 = b - a
	var length: float = d.length()
	if length < 0.0001:
		return
	_room(8)
	var n: Vector2 = Vector2(-d.y, d.x) / length
	var ca0:= Color(ca, 0.0)
	var cb0:= Color(cb, 0.0)

	var k: int = _np
	var q: int = _ni
	if width <= 1.6:

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
		while at < length - 0.001:
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

	if _circles[n].is_empty():
		_make_unit(n, 0, TAU)
		_circles[n] = _unit.slice(0, n + 1)
	var unit: PackedVector2Array = _circles[n]
	var inner: float = maxf(0.1, r - FEATHER * 0.5) if soft else r
	var clear:= Color(col, 0.0)
	var center: int = _vert(c, col)
	var first: int = _np

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

			_i[_ni] = a
			_i[_ni + 1] = a + 1
			_i[_ni + 2] = b + 1
			_i[_ni + 3] = a
			_i[_ni + 4] = b + 1
			_i[_ni + 5] = b
			_ni += 6

## A soft round puff: `col` in the middle, thinning out to nothing at `r`.
## Smoke, fire and flashes are drawn with it, so they blend instead of
## stacking up as hard-edged circles.
func puff(c: Vector2, r: float, col: Color) -> void:
	puff_lit(c, r, col, col, Vector2.ZERO)

## A soft puff shaded like a ball lit from `light` (a unit vector, or zero for
## flat): `lit` on the side towards the light, `dark` on the far side.
## Fireballs and smoke are drawn with it, so they look round rather than
## flat. One textured square: its corners take the shading, the texture the
## soft round edge.
func puff_lit(c: Vector2, r: float, lit: Color, dark: Color, light: Vector2) -> void:
	if lit.a < 0.004 or r < 0.3:
		return
	if _ni > 0:
		_flush_shapes()
	if _snp + 4 > _sp.size():
		var n: int = _sp.size() * 2
		_sp.resize(n)
		_sc.resize(n)
		_su.resize(n)
		_si.resize(n * 3 / 2)
	var k: int = _snp
	for j: int in 4:
		var u:= Vector2(-1.0 if j == 0 or j == 3 else 1.0, -1.0 if j < 2 else 1.0)
		_sp[k + j] = c + u * r
		_su[k + j] = Vector2(0.0 if u.x < 0 else 1.0, 0.0 if u.y < 0 else 1.0)
		_sc[k + j] = dark.lerp(lit, 0.5 + 0.5 * u.dot(light) * 0.7071)
	_snp = k + 4
	var q: int = _sni
	_si[q] = k
	_si[q + 1] = k + 1
	_si[q + 2] = k + 2
	_si[q + 3] = k
	_si[q + 4] = k + 2
	_si[q + 5] = k + 3
	_sni = q + 6

## A tongue of flame standing on `base`, `h` tall along `up` (a unit vector,
## which may lean) and `w` wide: hot `hot` low in its middle, cooler `cool`
## higher up, soft all round and thinning to a point. Eleven vertices.
func flame(base: Vector2, up: Vector2, h: float, w: float, hot: Color, cool: Color) -> void:
	if hot.a < 0.004:
		return
	_room(12)
	var across:= Vector2(-up.y, up.x)
	var clear_hot:= Color(hot, 0.0)
	var clear_cool:= Color(cool, 0.0)
	var k: int = _np
	_vert(base + up * (h * 0.18), hot)
	_vert(base + up * (h * 0.55), cool)
	_vert(base + up * h, clear_cool)
	_vert(base + across * (w * 0.75) + up * (h * 0.45), clear_cool)
	_vert(base - across * (w * 0.75) + up * (h * 0.45), clear_cool)
	# The round bottom: a half circle from one side, under, to the other.
	for s: int in 6:
		var a: float = PI * s / 5.0
		_vert(base + (across * cos(a) - up * sin(a)) * w, clear_hot)
	# Fan from the hot middle round the bottom.
	for s: int in 5:
		_tri(k, k + 5 + s, k + 6 + s)
	_tri(k, k + 10, k + 4)
	_tri(k, k + 4, k + 1)
	_tri(k + 1, k + 4, k + 2)
	_tri(k + 1, k + 2, k + 3)
	_tri(k, k + 1, k + 3)
	_tri(k, k + 3, k + 5)

## A soft ribbon along `pts`, joined smoothly from point to point: at each
## point its colour along the middle, fading to nothing `half` to either side.
## Smoke trails are drawn with it, so they have no joints or hard edges.
func ribbon(pts: PackedVector2Array, half: PackedFloat32Array, cols: PackedColorArray) -> void:
	var n: int = pts.size()
	if n < 2:
		return
	_room(n * 3 + 3)
	var first: int = _np
	for k: int in n:
		var d: Vector2
		if k == 0:
			d = pts[1] - pts[0]
		elif k == n - 1:
			d = pts[k] - pts[k - 1]
		else:
			d = pts[k + 1] - pts[k - 1]
		var l: float = d.length()
		var across: Vector2 = Vector2(-d.y, d.x) / l if l > 0.0001 else Vector2(0, 1)
		var c: Color = cols[k]
		var clear:= Color(c, 0.0)
		_p[_np] = pts[k] + across * half[k]
		_c[_np] = clear
		_p[_np + 1] = pts[k]
		_c[_np + 1] = c
		_p[_np + 2] = pts[k] - across * half[k]
		_c[_np + 2] = clear
		_np += 3
	for k: int in n - 1:
		var a: int = first + k * 3
		var b: int = a + 3
		_quad(a, a + 1, b + 1, b)
		_quad(a + 1, a + 2, b + 2, b + 1)

func ring(c: Vector2, r: float, col: Color, width: float, from: float = 0, to: float = TAU) -> void:
	var span: float = to - from
	var n: int = clampi(int(_segments(r) * absf(span) / TAU) + 1, 3, 64)
	_room((n + 1) * 4)
	# A whole ring uses the circle worked out once; an arc its own points.
	var unit: PackedVector2Array = _unit
	if absf(span) >= TAU - 0.0001:
		if _circles[n].is_empty():
			_make_unit(n, 0, TAU)
			_circles[n] = _unit.slice(0, n + 1)
		unit = _circles[n]
	else:
		_make_unit(n, from, span)
	var h: float = maxf(0.05, width * 0.5 - FEATHER * 0.5)
	var o: float = h + FEATHER
	if width < FEATHER:
		col.a *= width / FEATHER
	var clear:= Color(col, 0.0)
	var first: int = _np
	for s: int in n + 1:
		var u: Vector2 = unit[s]
		_p[_np] = c + u * (r + o)
		_c[_np] = clear
		_p[_np + 1] = c + u * (r + h)
		_c[_np + 1] = col
		_p[_np + 2] = c + u * (r - h)
		_c[_np + 2] = col
		_p[_np + 3] = c + u * (r - o)
		_c[_np + 3] = clear
		_np += 4

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

## A filled polygon, turned and scaled, edged with `outline` (or a thin soft
## edge of its own colour; none at all when `rim` is false, for shadows).
## The edge is one band round the polygon, pushed out along each corner's
## mitre (worked out once per shape), with a soft fringe outside it: a few
## vertices per corner instead of a separate line along every side.
static var _miters: Dictionary = {}

static func _miter(pts: PackedVector2Array) -> PackedVector2Array:
	var m: Variant = _miters.get(pts)
	if m != null:
		return m
	var n: int = pts.size()
	var area: float = 0.0
	for i: int in n:
		area += pts[i].cross(pts[(i + 1) % n])
	var out: float = 1.0 if area > 0.0 else -1.0
	var res:= PackedVector2Array()
	res.resize(n)
	for i: int in n:
		var e0: Vector2 = (pts[i] - pts[(i + n - 1) % n]).normalized()
		var e1: Vector2 = (pts[(i + 1) % n] - pts[i]).normalized()
		var n0: Vector2 = Vector2(e0.y, -e0.x) * out
		var n1: Vector2 = Vector2(e1.y, -e1.x) * out
		var mid: Vector2 = (n0 + n1)
		mid = mid.normalized() if mid.length() > 0.001 else n0
		# Sharp corners would throw the mitre far out: kept to 2.2 times.
		res[i] = mid / maxf(0.45, mid.dot(n0))
	_miters[pts] = res
	return res

func shape(pts: PackedVector2Array, tris: PackedInt32Array, c: Vector2, s: float, angle: float, fill: Color, outline: Variant = null, rim_on: bool = true) -> void:
	var count: int = pts.size()
	_room(count * 4 + 8)
	var cs: float = cos(angle)
	var sn: float = sin(angle)
	var k: int = _np
	var q: int = _ni
	if rim_on:
		var rim: Color = outline if outline != null else Color(fill, fill.a * 0.6)
		var rim0: Color = Color(rim, 0.0)
		var band: float = 1.1 if outline != null else 0.45
		var mit: PackedVector2Array = _miter(pts)
		# Three rings of vertices: the edge, the band's outer edge, the fringe.
		for i: int in count:
			var v: Vector2 = pts[i] * s
			var m: Vector2 = mit[i]
			var a: Vector2 = v + m * band
			var f: Vector2 = a + m * FEATHER
			_p[k + i] = c + Vector2(v.x * cs - v.y * sn, v.x * sn + v.y * cs)
			_p[k + count + i] = c + Vector2(a.x * cs - a.y * sn, a.x * sn + a.y * cs)
			_p[k + 2 * count + i] = c + Vector2(f.x * cs - f.y * sn, f.x * sn + f.y * cs)
			_c[k + i] = rim
			_c[k + count + i] = rim
			_c[k + 2 * count + i] = rim0
		for i: int in count:
			var j: int = (i + 1) % count
			for r: int in 2:
				var a0: int = k + r * count
				var b0: int = a0 + count
				_i[q] = a0 + i
				_i[q + 1] = a0 + j
				_i[q + 2] = b0 + j
				_i[q + 3] = a0 + i
				_i[q + 4] = b0 + j
				_i[q + 5] = b0 + i
				q += 6
		k += 3 * count
	var first: int = k
	for i: int in count:
		var v: Vector2 = pts[i] * s
		_p[k] = c + Vector2(v.x * cs - v.y * sn, v.x * sn + v.y * cs)
		_c[k] = fill
		k += 1
	for t: int in tris:
		_i[q] = first + t
		q += 1
	_np = k
	_ni = q
