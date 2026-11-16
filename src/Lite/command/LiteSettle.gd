class_name LiteSettle
extends RefCounted
## Phase 4: the map's settlements, laid out building by building in the
## terrain's pixels (written into the terrain's feature image, see
## LiteTerrain; the bake shader paints them), and their lights at night
## (an image of its own, see LiteCmdView's lights layer). Three sizes:
##
## - a village: a handful of houses scattered along a lane, fields round it;
## - a town: two streets crossing at a small square, houses and shops packed
##   along them, a little works on one side;
## - a city: a grid of streets with avenues through the middle, a centre of
##   offices and a few towers round a square, apartment blocks round that,
##   houses with gardens on the edge, an industrial district on one side, a
##   park; its outline ragged, not a circle.
##
## Each region gets one at its name, sized by how big it is; the larger
## regions a village or two more. The capitals are drawn live instead (see
## LiteCmdCity: they take damage), only their suburbs here.
##
## The feature image's blue channel holds what each pixel is (see the codes
## below); its lights image the colour of each light, alpha < 1 for the ones
## that flicker.

## Ground codes (blue channel, as a byte).
const STREET: int = 1
const YARD: int = 2
const PLAZA: int = 3
const WORKYARD: int = 4
const PARK: int = 5
## Building codes: BUILDING + kind * 8 + part.
const BUILDING: int = 16
enum { APART, OFFICE, RED, BROWN, SHED, WAREHOUSE, LANDMARK, TOWER, BARN }
enum { ROOF, ROOF_LIGHT, WALL, DETAIL_DARK, DETAIL_LIGHT }

## Lights: warm windows, orange ones, cool white works floodlights, the
## yellow of street lamps.
const WARM:= Color(1.0, 0.80, 0.46)
const ORANGE:= Color(1.0, 0.62, 0.30)
const WORKLIGHT:= Color(0.92, 0.90, 0.80)
const LAMP:= Color(1.0, 0.86, 0.55)

var feat: Image
var lights: Image
var rng: RandomNumberGenerator
## Is this art pixel free land of the countries (not water, not off the map)?
var free_at: Callable
## Pixels that must stay clear (the capitals' cities), as [centre, radius].
var keep_clear: Array = []

func _init(f: Image, l: Image, r: RandomNumberGenerator, free_fn: Callable) -> void:
	feat = f
	lights = l
	rng = r
	free_at = free_fn

func _clear(q: Vector2i) -> bool:
	if q.x < 1 or q.y < 1 or q.x >= feat.get_width() - 1 or q.y >= feat.get_height() - 1:
		return false
	for k: Array in keep_clear:
		if Vector2(q).distance_to(k[0]) < k[1]:
			return false
	if not free_at.call(Vector2(q)):
		return false
	var px: Color = feat.get_pixelv(q)
	return px.r < 0.5 and _code(px) == 0

static func _code(px: Color) -> int:
	return int(px.b * 255.0 + 0.5)

func _put_code(q: Vector2i, code: int) -> void:
	var px: Color = feat.get_pixelv(q)
	px.b = code / 255.0
	feat.set_pixelv(q, px)

func _light(q: Vector2i, c: Color, flicker: bool = false, k: float = 1.0) -> void:
	if q.x < 0 or q.y < 0 or q.x >= lights.get_width() or q.y >= lights.get_height():
		return
	lights.set_pixelv(q, Color(c.r * k, c.g * k, c.b * k, 0.6 if flicker else 1.0))

## A single light at `q`, `k` bright.
func lamp(q: Vector2i, k: float) -> void:
	if _clear(q) or (q.x >= 0 and q.y >= 0 and q.x < feat.get_width() and q.y < feat.get_height()):
		_light(q, WARM if randf() < 0.7 else LAMP, randf() < 0.1, k)

## Whether a whole rect is free.
func _room(r: Rect2i) -> bool:
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			if not _clear(Vector2i(x, y)):
				return false
	return true

## A building: its roof (`r`), lit along its top edge, its south wall `wall`
## pixels tall below it (so tall ones stand up off the map), details on big
## roofs; lit windows on its wall and roof by `lit` (0..1).
func building(r: Rect2i, kind: int, wall: int, lit: float, light: Color = WARM) -> bool:
	var full:= Rect2i(r.position, r.size + Vector2i(0, wall))
	if not _room(full):
		return false
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			var part: int = ROOF_LIGHT if y == r.position.y else ROOF
			if r.size.x >= 3 and r.size.y >= 3 and part == ROOF and rng.randf() < 0.12:
				part = DETAIL_DARK if rng.randf() < 0.6 else DETAIL_LIGHT
			_put_code(Vector2i(x, y), BUILDING + kind * 8 + part)
			if part == ROOF and rng.randf() < lit * 0.25:
				_light(Vector2i(x, y), light, rng.randf() < 0.1, 0.55)
	for y: int in range(r.end.y, r.end.y + wall):
		for x: int in range(r.position.x, r.end.x):
			_put_code(Vector2i(x, y), BUILDING + kind * 8 + WALL)
			if rng.randf() < lit:
				_light(Vector2i(x, y), light if rng.randf() < 0.75 else ORANGE, rng.randf() < 0.08)
	return true

func ground(q: Vector2i, code: int) -> void:
	if _clear(q):
		_put_code(q, code)

# --- Settlements ---------------------------------------------------------------

## A village round `c` (art pixels).
func village(c: Vector2, rr: float) -> void:
	var n: int = rng.randi_range(4, 9)
	var lane: Vector2 = Vector2.from_angle(rng.randf() * PI)
	for i: int in n * 3:
		if n <= 0:
			break
		var t: float = rng.randf_range(-rr, rr)
		var at: Vector2 = c + lane * t + lane.orthogonal() * rng.randf_range(-2.5, 2.5)
		var w: int = rng.randi_range(2, 3)
		var h: int = rng.randi_range(1, 2)
		var kind: int = [RED, BROWN, RED, BROWN, BARN][rng.randi_range(0, 4)]
		if building(Rect2i(Vector2i(at.round()), Vector2i(w, h)), kind, 1, 0.3):
			n -= 1
	# A lamp or two on the lane.
	for k: int in 2:
		var q: Vector2i = Vector2i((c + lane * rng.randf_range(-rr, rr)).round())
		if _clear(q):
			_light(q, LAMP, false, 0.6)

## A town round `c`: streets crossing at a square, packed buildings along
## them, works on one side.
func town(c: Vector2, rr: float, away: Vector2) -> void:
	var ci: Vector2i = Vector2i(c.round())
	var r: int = int(rr)
	# The two streets, and the square where they cross.
	for t: int in range(-r, r + 1):
		ground(ci + Vector2i(t, 0), STREET)
		ground(ci + Vector2i(0, t), STREET)
		if absi(t) % 3 == 0 and absi(t) > 1:
			_light(ci + Vector2i(t, 0), LAMP, false, 0.7)
			_light(ci + Vector2i(0, t), LAMP, false, 0.7)
	for y: int in range(-1, 2):
		for x: int in range(-1, 2):
			if x != 0 or y != 0:
				ground(ci + Vector2i(x, y), PLAZA)
	# Buildings along them, densest near the middle.
	for k: int in int(rr * rr * 1.2):
		var at: Vector2 = c + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * rr
		var d: float = at.distance_to(c) / rr
		var works: bool = d > 0.5 and (at - c).normalized().dot(away) > 0.6
		var kind: int
		var w: int
		var h: int
		var wall: int = 1
		if works:
			kind = SHED if rng.randf() < 0.6 else WAREHOUSE
			w = rng.randi_range(3, 5)
			h = 2
		elif d < 0.4:
			kind = OFFICE if rng.randf() < 0.5 else APART
			w = rng.randi_range(2, 3)
			h = rng.randi_range(2, 3)
			wall = 2
		else:
			kind = RED if rng.randf() < 0.5 else BROWN
			w = 2
			h = rng.randi_range(1, 2)
		var lit: float = 0.12 if works else (0.5 if d < 0.4 else 0.3)
		if building(Rect2i(Vector2i(at.round()), Vector2i(w, h)), kind, wall, lit, WORKLIGHT if works else WARM) and works and rng.randf() < 0.5:
			_light(Vector2i(at.round()), WORKLIGHT, false, 1.2)

## A city round `c`: blocks between streets, avenues through the middle, a
## centre with towers round a square, apartments, houses on the edge, an
## industrial district towards `away`, a park.
func city(c: Vector2, rr: float, away: Vector2) -> void:
	var ci: Vector2i = Vector2i(c.round())
	var step: int = 6
	var r: int = int(rr) + step
	var wob: float = rng.randf() * TAU
	var park_at: Vector2 = c + Vector2.from_angle(rng.randf() * TAU) * rr * 0.45
	# The streets (every `step`) and the avenues (two pixels wide) through
	# the middle, inside the city's ragged outline.
	for y: int in range(-r, r + 1):
		for x: int in range(-r, r + 1):
			var q: Vector2i = ci + Vector2i(x, y)
			if not _inside_city(Vector2(q), c, rr, wob):
				continue
			var avenue: bool = x == 0 or y == 0
			var street: bool = posmod(x, step) == 0 or posmod(y, step) == 0
			if avenue or street:
				ground(q, STREET)
				if (avenue and (posmod(x + y, 3) == 0)) or (street and posmod(x * 7 + y * 3, 5) == 0 and rng.randf() < 0.6):
					_light(q, LAMP, rng.randf() < 0.05, 0.8 if avenue else 0.55)
	# The blocks, between the streets.
	var s0: int = -(r / step) * step
	for by: int in range(s0, r + 1, step):
		for bx: int in range(s0, r + 1, step):
			var o:= Vector2i(bx + 1, by + 1)
			var mid: Vector2 = c + Vector2(o) + Vector2(2.5, 2.5)
			if not _inside_city(mid, c, rr, wob):
				continue
			var d: float = mid.distance_to(c) / rr
			if mid.distance_to(park_at) < rr * 0.16:
				for y: int in 5:
					for x: int in 5:
						ground(ci + o + Vector2i(x, y), PARK)
				continue
			if d < 0.16:
				# The central square.
				for y: int in 5:
					for x: int in 5:
						ground(ci + o + Vector2i(x, y), PLAZA)
				_light(ci + o + Vector2i(2, 2), LAMP, false, 1.0)
				continue
			_block(ci + o, d, (mid - c).normalized().dot(away) > 0.55 and d > 0.45)

func _block(o: Vector2i, d: float, works: bool) -> void:
	if works:
		# Long sheds, a yard, floodlights.
		for y: int in 5:
			for x: int in 5:
				ground(o + Vector2i(x, y), WORKYARD)
		_set_block_free(o)
		building(Rect2i(o, Vector2i(5, 2)), SHED if rng.randf() < 0.6 else WAREHOUSE, 1, 0.1, WORKLIGHT)
		building(Rect2i(o + Vector2i(0, 4), Vector2i(3, 1)), WAREHOUSE, 0, 0.1, WORKLIGHT)
		_light(o + Vector2i(4, 4), WORKLIGHT, false, 1.3)
		_light(o, WORKLIGHT, rng.randf() < 0.2, 1.1)
		return
	if d < 0.4:
		# The centre: offices, and towers standing up over the rest.
		if rng.randf() < 0.45:
			building(Rect2i(o + Vector2i(1, 0), Vector2i(3, 2)), TOWER, 3, 0.7, WARM)
			building(Rect2i(o + Vector2i(0, 4), Vector2i(5, 1)), OFFICE, 0, 0.5)
		else:
			building(Rect2i(o, Vector2i(5, 2)), OFFICE, 2, 0.6)
			building(Rect2i(o + Vector2i(0, 4), Vector2i(2, 1)), APART, 0, 0.5)
			building(Rect2i(o + Vector2i(3, 4), Vector2i(2, 1)), OFFICE, 0, 0.5)
	elif d < 0.75:
		# Apartment blocks round a yard.
		for y: int in 5:
			for x: int in 5:
				ground(o + Vector2i(x, y), YARD)
		_set_block_free(o)
		building(Rect2i(o, Vector2i(5, 1)), APART, 2, 0.45)
		if rng.randf() < 0.7:
			building(Rect2i(o + Vector2i(0, 3), Vector2i(1, 2)), APART, 0, 0.4)
		if rng.randf() < 0.7:
			building(Rect2i(o + Vector2i(3, 3), Vector2i(2, 1)), APART, 1, 0.4)
	else:
		# Houses with gardens.
		for y: int in 5:
			for x: int in 5:
				ground(o + Vector2i(x, y), YARD)
		_set_block_free(o)
		for q: Vector2i in [Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 3), Vector2i(3, 3)]:
			if rng.randf() < 0.75:
				building(Rect2i(o + q, Vector2i(2, 1)), RED if rng.randf() < 0.55 else BROWN, 1, 0.3)

## Ground laid for a block (yard, works yard) is free to build on again.
func _set_block_free(o: Vector2i) -> void:
	for y: int in 5:
		for x: int in 5:
			var q: Vector2i = o + Vector2i(x, y)
			var px: Color = feat.get_pixelv(q)
			var code: int = _code(px)
			if code == YARD or code == WORKYARD:
				px.b = 0.0
				feat.set_pixelv(q, px)
				_pending.append([q, code])

var _pending: Array = []

## The ground under a block's buildings, put back round them once they stand.
func settle_ground() -> void:
	for e: Array in _pending:
		var q: Vector2i = e[0]
		var px: Color = feat.get_pixelv(q)
		if _code(px) == 0 and px.r < 0.5:
			px.b = int(e[1]) / 255.0
			feat.set_pixelv(q, px)
	_pending.clear()

func _inside_city(q: Vector2, c: Vector2, rr: float, wob: float) -> bool:
	var a: float = (q - c).angle()
	var reach: float = rr * (0.84 + 0.12 * sin(a * 3.0 + wob) + 0.07 * sin(a * 5.0 - wob * 1.7))
	return q.distance_to(c) <= reach

## Suburbs round a capital's city: houses and a few blocks in a ring from
## `r0` to `r1` (art pixels) round `c`.
func suburbs(c: Vector2, r0: float, r1: float) -> void:
	for k: int in int(r1 * 3.0):
		var at: Vector2 = c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(r0, r1)
		var kind: int = [RED, BROWN, APART, RED][rng.randi_range(0, 3)]
		var w: int = 2 if kind != APART else 4
		building(Rect2i(Vector2i(at.round()), Vector2i(w, 1)), kind, 1, 0.3)
