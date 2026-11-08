class_name LiteParticles
extends RefCounted

enum { SMOKE, FIRE, EMBER, SPARK, SHOCK, FLASH, FLAME, DEBRIS, HAZE }

## At most this many at once: fewer in a browser, where every one costs more.
static var MAX: int = 1000 if OS.has_feature("web") else 1600

const WIND: Vector2 = Vector2(6.0, -2.5)
## Up, on the map as drawn (see LiteView.LIFT): smoke rises this way.
const UP: Vector2 = Vector2(-0.42, -0.91)
## Where the light comes from: up, and a little to the left.
const LIGHT: Vector2 = Vector2(-0.55, -0.835)

var _kind: PackedByteArray = PackedByteArray()
var _pos: PackedVector2Array = PackedVector2Array()
var _vel: PackedVector2Array = PackedVector2Array()
var _age: PackedFloat32Array = PackedFloat32Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _r0: PackedFloat32Array = PackedFloat32Array()
var _r1: PackedFloat32Array = PackedFloat32Array()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var count: int:
	get: return _kind.size()

func _init() -> void:
	_rng.randomize()

func add(kind: int, pos: Vector2, vel: Vector2, life: float, r0: float, r1: float) -> void:
	if _kind.size() >= MAX:
		return
	_kind.append(kind)
	_pos.append(pos)
	_vel.append(vel)
	_age.append(0.0)
	_life.append(life)
	_r0.append(r0)
	_r1.append(r1)

func _dir(speed_lo: float, speed_hi: float) -> Vector2:
	return Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(speed_lo, speed_hi)

func _jitter(r: float) -> Vector2:
	return Vector2.from_angle(_rng.randf() * TAU) * r * sqrt(_rng.randf())

func blast(p: Vector2, size: float) -> void:
	add(FLASH, p, Vector2.ZERO, 0.16, size * 1.7, size * 0.6)
	add(SHOCK, p, Vector2.ZERO, 0.5, size * 0.4, size * 3.4)
	for i: int in 7 + int(size / 3):
		add(FIRE, p + _jitter(size * 0.3), _dir(size * 0.4, size * 1.2) + UP * size * _rng.randf_range(0.4, 1.2), _rng.randf_range(0.55, 1.1), size * _rng.randf_range(0.22, 0.42), size * _rng.randf_range(0.5, 0.85))
	for i: int in 6 + int(size / 2):
		add(SPARK, p, _dir(size * 4.0, size * 11.0), _rng.randf_range(0.3, 0.8), 0, 0)
	for i: int in 6 + int(size / 2):
		add(SMOKE, p + _jitter(size * 0.45), _dir(1.0, 5.0) + WIND, _rng.randf_range(5.0, 9.0), size * _rng.randf_range(0.25, 0.4), size * _rng.randf_range(0.9, 1.4))
	for i: int in 1:
		add(EMBER, p + _jitter(size * 0.35), Vector2.ZERO, _rng.randf_range(4.0, 8.0), _rng.randf_range(1.0, 1.8), 0)

## A missile or drone blown apart in the air: a white flash, a fireball
## that burns out in a moment, a ring of sparks, and a dark ragged cloud of
## smoke that hangs where it burst. Its wreckage falls (see `debris`).
func pop(p: Vector2, size: float) -> void:
	add(FLASH, p, Vector2.ZERO, 0.1, size * 2.0, size * 0.7)
	add(SHOCK, p, Vector2.ZERO, 0.35, size * 0.3, size * 2.2)
	for i: int in 5:
		add(FIRE, p + _jitter(size * 0.25), _dir(size * 0.6, size * 1.8), _rng.randf_range(0.3, 0.55), size * 0.25, size * 0.6)
	for i: int in 12:
		add(SPARK, p, _dir(size * 4.0, size * 10.0), _rng.randf_range(0.3, 0.7), 0, 0)
	for i: int in 5:
		add(SMOKE, p + _jitter(size * 0.4), _dir(1.0, 4.0) + WIND * 0.5, _rng.randf_range(3.5, 5.5), size * 0.3, size * _rng.randf_range(0.9, 1.3))

func launch(p: Vector2) -> void:
	for i: int in 4:
		add(SMOKE, p + _jitter(2.0), _dir(3.0, 9.0) + WIND, _rng.randf_range(1.6, 2.8), 2.0, 7.0)

func puff(p: Vector2, size: float) -> void:
	add(SMOKE, p, _dir(0.5, 2.0) + WIND, _rng.randf_range(1.2, 2.0), size * 0.5, size * 1.6)

func ruin(p: Vector2) -> void:
	add(SMOKE, p + _jitter(3.0), UP * _rng.randf_range(5.0, 9.0) + _dir(0.0, 1.5), _rng.randf_range(5.0, 8.0), 2.5, 12.0)
	if _rng.randf() < 0.5:
		add(FIRE, p + _jitter(3.0), Vector2(0, -6) + _dir(0.0, 3.0), _rng.randf_range(0.35, 0.6), 1.6, 3.2)

## Smoke left in the air behind a missile's motor.
func contrail(p: Vector2, r0: float = 2.0, r1: float = 6.5, life_lo: float = 2.0, life_hi: float = 3.5) -> void:
	add(SMOKE, p + _jitter(r0 * 0.75), _dir(0.5, 2.0) + UP * 2.0 + WIND * 0.4, _rng.randf_range(life_lo, life_hi), r0, r1)

## The wreckage of something shot down falling (along `down`) from `h` up:
## burning pieces, each trailing a streak of smoke, and a few sparks.
func debris(p: Vector2, down: Vector2, h: float) -> void:
	var fall: float = clampf(h / 45.0, 0.35, 1.6)
	for i: int in 5 if h > 8.0 else 3:
		add(DEBRIS, p + _jitter(2.0), _dir(6.0, 22.0) + down * _rng.randf_range(4.0, 14.0), fall * _rng.randf_range(0.7, 1.1), _rng.randf_range(0.8, 1.4), 0)
	for i: int in 6:
		add(SPARK, p + _jitter(2.0), down * _rng.randf_range(20.0, 50.0) + _dir(5.0, 20.0), _rng.randf_range(0.4, 0.8), 0, 0)

## Where a smoke trail is cut off in the air (going `dir` when it was): its
## pale smoke billows out a little and hangs there.
func trail_end(p: Vector2, dir: Vector2) -> void:
	for i: int in 4:
		add(HAZE, p - dir * (i * 4.5) + _jitter(2.0), _dir(1.0, 3.5) + dir * (3.0 - i * 0.6), _rng.randf_range(3.5, 5.5), 3.0, _rng.randf_range(9.0, 13.0))

## A ballistic missile leaving its launcher: a blinding flash and two
## shockwaves, a fireball of exhaust, a cloud of dust and smoke rolling out
## over the ground, and a column of it rising (along `up`) after the missile.
func ballistic_launch(p: Vector2, up: Vector2) -> void:
	add(FLASH, p, Vector2.ZERO, 0.4, 34.0, 10.0)
	add(SHOCK, p, Vector2.ZERO, 0.7, 4.0, 36.0)
	add(SHOCK, p, Vector2.ZERO, 1.1, 3.0, 22.0)
	for i: int in 14:
		add(FIRE, p + _jitter(4.0), up * _rng.randf_range(4.0, 18.0) + _dir(3.0, 12.0), _rng.randf_range(0.6, 1.2), 4.0, 12.0)
	for i: int in 26:
		var d: Vector2 = Vector2.from_angle(i * TAU / 26 + _rng.randf() * 0.25)
		add(SMOKE, p + d * 4.0, d * _rng.randf_range(5.0, 12.0) + WIND, _rng.randf_range(6.0, 11.0), 5.0, 18.0)
	for i: int in 10:
		add(SMOKE, p + up * _rng.randf_range(0.0, 14.0) + _jitter(4.0), up * _rng.randf_range(4.0, 10.0) + WIND, _rng.randf_range(8.0, 13.0), 5.0, 16.0)
	for i: int in 12:
		add(SPARK, p, _dir(30.0, 90.0), _rng.randf_range(0.3, 0.7), 0, 0)

## A ballistic warhead landing, on top of the usual blast: a wide shockwave and
## a second one, a second flash, a ring of dust rolling out, a fireball, a tall
## column of smoke rising (along `up`), sparks and embers.
func ballistic_blast(p: Vector2, size: float, up: Vector2) -> void:
	add(SHOCK, p, Vector2.ZERO, 0.9, size * 0.6, size * 5.5)
	add(FLASH, p, Vector2.ZERO, 0.25, size * 2.8, size)
	for i: int in 22:
		var d: Vector2 = Vector2.from_angle(i * TAU / 22 + _rng.randf() * 0.25)
		add(SMOKE, p + d * size * 0.5, d * _rng.randf_range(7.0, 13.0) + WIND, _rng.randf_range(6.0, 10.0), size * 0.25, size * 0.8)
	for i: int in 10:
		add(FIRE, p + _jitter(size * 0.4), up * _rng.randf_range(4.0, 14.0) + _dir(size * 0.3, size * 1.0), _rng.randf_range(0.6, 1.2), size * 0.3, size * 0.75)
	for i: int in 12:
		var rise: float = _rng.randf()
		add(SMOKE, p + up * size * 0.8 * rise + _jitter(size * 0.25), up * _rng.randf_range(16.0, 26.0), _rng.randf_range(10.0, 16.0), size * 0.3, size * 1.1)
	for i: int in 10:
		add(SPARK, p, _dir(size * 5.0, size * 13.0), _rng.randf_range(0.4, 1.0), 0, 0)
	for i: int in 3:
		add(EMBER, p + _jitter(size * 0.7), _dir(2.0, 8.0), _rng.randf_range(5.0, 10.0), _rng.randf_range(1.2, 2.0), 0)

## A fire burning where a warhead landed: flames licking up at the base and a
## column of dark smoke rising from it, spreading as it climbs and leaning
## with the wind higher up. `fierce` is how hard it still burns, 1 down to
## near 0.
func burn(p: Vector2, size: float, fierce: float, up: Vector2) -> void:
	var k: float = 0.45 + 0.55 * fierce
	add(FLAME, p + _jitter(size * 0.22), up * _rng.randf_range(1.0, 4.0), _rng.randf_range(0.5, 0.9), size * _rng.randf_range(0.2, 0.3) * k, size * _rng.randf_range(0.7, 1.2) * k)
	if _rng.randf() < 0.75:
		add(SMOKE, p + _jitter(size * 0.15) + up * size * 0.4, up * _rng.randf_range(20.0, 28.0) * (0.6 + 0.4 * fierce) + _dir(0.0, 1.5),
			_rng.randf_range(7.5, 10.5), size * 0.3, size * (0.85 + 0.45 * fierce))

## A SAM leaving its launcher: a flash, and a ring of smoke and dust blown out
## round the rack.
func sam_launch(p: Vector2) -> void:
	add(FLASH, p, Vector2.ZERO, 0.15, 9.0, 3.0)
	for i: int in 7:
		var d: Vector2 = Vector2.from_angle(i * TAU / 7 + _rng.randf() * 0.5)
		add(SMOKE, p + d * 2.0, d * _rng.randf_range(4.0, 9.0) + WIND, _rng.randf_range(2.0, 3.5), 2.0, 7.0)
	for i: int in 2:
		add(FIRE, p + _jitter(1.5), _dir(1.0, 5.0), _rng.randf_range(0.2, 0.4), 1.5, 3.5)

func step(dt: float) -> void:
	if dt <= 0:
		return
	var n: int = _kind.size()
	var k: int = 0
	var drag_spark: float = exp(-dt * 3.5)
	var drag_fire: float = exp(-dt * 4.0)
	var drag_smoke: float = exp(-dt * 0.35)
	var drag_debris: float = exp(-dt * 1.2)
	for i: int in n:
		var age: float = _age[i] + dt
		if age >= _life[i]:
			continue
		var kind: int = _kind[i]
		var v: Vector2 = _vel[i]
		_pos[i] = _pos[i] + v * dt
		if kind == SPARK:
			v *= drag_spark
		elif kind == FIRE:
			v *= drag_fire
		elif kind == SMOKE or kind == HAZE:
			v = WIND + (v - WIND) * drag_smoke
		elif kind == DEBRIS:
			v = v * drag_debris - UP * (70.0 * dt)
		if k != i:
			_kind[k] = kind
			_pos[k] = _pos[i]
			_life[k] = _life[i]
			_r0[k] = _r0[i]
			_r1[k] = _r1[i]
		_vel[k] = v
		_age[k] = age
		k += 1
	if k != n:
		_kind.resize(k)
		_pos.resize(k)
		_vel.resize(k)
		_age.resize(k)
		_life.resize(k)
		_r0.resize(k)
		_r1.resize(k)

func clear() -> void:
	_kind.clear()
	_pos.clear()
	_vel.clear()
	_age.clear()
	_life.clear()
	_r0.clear()
	_r1.clear()

const SMOKE_DARK: Color = Color(0.13, 0.13, 0.14)
const SMOKE_LIGHT: Color = Color(0.36, 0.36, 0.38)
const FIRE_HOT: Color = Color(1.0, 0.9, 0.55)
const FIRE_MID: Color = Color(1.0, 0.5, 0.1)
const FIRE_COOL: Color = Color(0.6, 0.1, 0.03)

func draw_smoke(b: LiteBatch) -> void:
	for i: int in _kind.size():
		var kind: int = _kind[i]
		if kind != SMOKE and kind != HAZE:
			continue
		var t: float = _age[i] / _life[i]
		var a: float = minf(1.0, t * 12.0) * pow(1.0 - t, 1.5) * 0.5
		if a < 0.01:
			continue
		if kind == HAZE:
			var r: float = lerpf(_r0[i], _r1[i], 1.0 - (1.0 - t) * (1.0 - t))
			b.puff(_pos[i], r * 1.3, Color(0.86, 0.87, 0.9, a * 0.7))
			continue
		var grow: float = 1.0 - (1.0 - t) * (1.0 - t)
		var c: Color = SMOKE_DARK.lerp(SMOKE_LIGHT, t)
		c.a = a
		# Lit a little on top, darker underneath: a billow, not a blot.
		b.puff_lit(_pos[i], lerpf(_r0[i], _r1[i], grow) * 1.3, c.lightened(0.18), c.darkened(0.3), LIGHT)

func draw_fire(b: LiteBatch, clock: float) -> void:
	# Puffs first (fireballs, the glow round embers, flashes), then the shapes
	# over them, so the batch switches between the two once, not per particle.
	for i: int in _kind.size():
		var kind: int = _kind[i]
		if kind != FIRE and kind != EMBER and kind != FLASH:
			continue
		var t: float = _age[i] / _life[i]
		var inv: float = 1.0 - t
		var p: Vector2 = _pos[i]
		match kind:
			FIRE:
				# A ball of fire: white-hot, then orange, then deep red as it
				# cools; lit on top, dark and sooty underneath.
				var c: Color = FIRE_HOT.lerp(FIRE_MID, minf(1.0, t * 2.5)) if t < 0.4 else FIRE_MID.lerp(FIRE_COOL, (t - 0.4) / 0.6)
				c.a = 0.95 * inv
				var r: float = lerpf(_r0[i], _r1[i], 1.0 - inv * inv) * 1.35
				b.puff_lit(p, r, c.lightened(0.15), Color(c.darkened(0.5), c.a * 0.9), LIGHT)
			EMBER:
				b.puff(p, _r0[i] * 3.2, Color(1.0, 0.35, 0.08, 0.3 * _flicker(clock, i) * inv))
			FLASH:
				b.puff(p, lerpf(_r0[i], _r1[i], t) * 1.3, Color(1.0, 0.97, 0.88, 0.95 * inv * inv))
	for i: int in _kind.size():
		var kind: int = _kind[i]
		if kind == SMOKE or kind == HAZE or kind == FIRE or kind == FLASH:
			continue
		var t: float = _age[i] / _life[i]
		var inv: float = 1.0 - t
		var p: Vector2 = _pos[i]
		match kind:
			FLAME:
				# Grows up fast, flickers and leans, dies down.
				var rise: float = minf(1.0, t * 4.0) * (1.0 - t * t)
				var fl: float = 0.8 + 0.2 * sin(clock * 15.0 + float(i) * 1.9)
				var lean: Vector2 = UP.rotated(0.18 * sin(clock * 5.0 + float(i) * 0.7) + 0.12)
				var hot: Color = FIRE_HOT.lerp(FIRE_MID, t)
				hot.a = 0.95 * minf(1.0, inv * 2.0)
				var cool: Color = FIRE_MID.lerp(FIRE_COOL, t)
				cool.a = 0.8 * inv
				b.flame(p, lean, _r1[i] * rise * fl, _r0[i] * (0.7 + 0.3 * rise), hot, cool)
			EMBER:
				b.disc(p, _r0[i], Color(1.0, 0.75, 0.35, 0.85 * _flicker(clock, i) * minf(1.0, inv * 3.0)))
			DEBRIS:
				# A burning piece falling, smoke streaming off it.
				var v: Vector2 = _vel[i]
				var tail: Vector2 = p - v.normalized() * minf(16.0, 3.0 + v.length() * 0.3)
				b.line_grad(tail, p, Color(0.4, 0.4, 0.42, 0.0), Color(0.75, 0.6, 0.5, 0.6 * inv), _r0[i] * 1.6)
				var f: float = 0.6 + 0.4 * sin(clock * 23.0 + float(i) * 3.1)
				b.disc(p, _r0[i] * 0.9, Color(1.0, 0.7 * f + 0.2, 0.3, 0.95 * inv))
			SPARK:
				var v: Vector2 = _vel[i]
				var c: Color = FIRE_HOT.lerp(FIRE_MID, t)
				c.a = inv
				b.line(p, p - v * 0.045, c, 1.2)
			SHOCK:
				var r: float = lerpf(_r0[i], _r1[i], 1.0 - inv * inv * inv)
				b.ring(p, r, Color(1.0, 0.92, 0.8, 0.55 * inv * inv), 0.6 + 2.2 * inv)

static func _flicker(clock: float, i: int) -> float:
	return 0.55 + 0.45 * sin(clock * 17.0 + float(i) * 2.3) * sin(clock * 7.0 + float(i))
