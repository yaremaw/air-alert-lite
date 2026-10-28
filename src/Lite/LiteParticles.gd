class_name LiteParticles
extends RefCounted
## Short-lived particles layered over the sim's effects: fireballs, shock
## rings, sparks, embers and smoke that drifts with the wind. Visual only:
## the sim never reads them. They age with the sim's clock, so they stop on
## pause and hurry at higher speeds like everything else on the map.

enum { SMOKE, FIRE, EMBER, SPARK, SHOCK, FLASH }
## More than this and new ones are dropped: a crowded sky stays smooth.
const MAX: int = 1100
## Map units a second; smoke leans east and a little north.
const WIND: Vector2 = Vector2(6.0, -2.5)

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


## A warhead going off on the ground; `size` is the sim's blast size.
func blast(p: Vector2, size: float) -> void:
	add(FLASH, p, Vector2.ZERO, 0.16, size * 1.7, size * 0.6)
	add(SHOCK, p, Vector2.ZERO, 0.5, size * 0.4, size * 3.4)
	for i: int in 7 + int(size / 3):
		add(FIRE, p + _jitter(size * 0.3), _dir(size * 0.4, size * 1.4), _rng.randf_range(0.55, 1.1), size * _rng.randf_range(0.22, 0.42), size * _rng.randf_range(0.5, 0.85))
	for i: int in 10 + int(size):
		add(SPARK, p, _dir(size * 4.0, size * 11.0), _rng.randf_range(0.3, 0.8), 0, 0)
	for i: int in 6 + int(size / 2):
		add(SMOKE, p + _jitter(size * 0.45), _dir(1.0, 5.0) + WIND, _rng.randf_range(5.0, 9.0), size * _rng.randf_range(0.25, 0.4), size * _rng.randf_range(0.9, 1.4))
	for i: int in 3:
		add(EMBER, p + _jitter(size * 0.35), Vector2.ZERO, _rng.randf_range(4.0, 8.0), _rng.randf_range(1.0, 1.8), 0)


## Something shot down in the air: a burst, falling sparks, a small cloud.
func pop(p: Vector2, size: float) -> void:
	add(FLASH, p, Vector2.ZERO, 0.12, size * 1.5, size * 0.5)
	add(SHOCK, p, Vector2.ZERO, 0.3, size * 0.3, size * 1.8)
	for i: int in 4:
		add(FIRE, p + _jitter(size * 0.2), _dir(size * 0.5, size * 1.5), _rng.randf_range(0.3, 0.55), size * 0.3, size * 0.55)
	for i: int in 9:
		add(SPARK, p, _dir(size * 3.0, size * 9.0) + Vector2(0, size * 1.5), _rng.randf_range(0.4, 1.0), 0, 0)
	for i: int in 3:
		add(SMOKE, p + _jitter(size * 0.3), _dir(0.5, 3.0) + WIND, _rng.randf_range(2.5, 4.5), size * 0.3, size * 1.0)


## A launch: a cloud of exhaust on the pad.
func launch(p: Vector2) -> void:
	for i: int in 4:
		add(SMOKE, p + _jitter(2.0), _dir(3.0, 9.0) + WIND, _rng.randf_range(1.6, 2.8), 2.0, 7.0)


## An interceptor's puff: a little grey cloud that hangs a moment.
func puff(p: Vector2, size: float) -> void:
	add(SMOKE, p, _dir(0.5, 2.0) + WIND, _rng.randf_range(1.2, 2.0), size * 0.5, size * 1.6)


## A burning ruin breathes out smoke and the odd flame.
func ruin(p: Vector2) -> void:
	add(SMOKE, p + _jitter(3.0), _dir(0.5, 2.0) + WIND * 1.3, _rng.randf_range(4.0, 7.0), 2.5, 11.0)
	if _rng.randf() < 0.5:
		add(FIRE, p + _jitter(3.0), Vector2(0, -6) + _dir(0.0, 3.0), _rng.randf_range(0.35, 0.6), 1.6, 3.2)


func step(dt: float) -> void:
	if dt <= 0:
		return
	var n: int = _kind.size()
	var k: int = 0
	var drag_spark: float = exp(-dt * 3.5)
	var drag_fire: float = exp(-dt * 4.0)
	var drag_smoke: float = exp(-dt * 0.35)
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
		elif kind == SMOKE:
			v = WIND + (v - WIND) * drag_smoke
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
const FIRE_HOT: Color = Color(1.0, 0.93, 0.7)
const FIRE_MID: Color = Color(1.0, 0.55, 0.15)
const FIRE_COOL: Color = Color(0.55, 0.12, 0.05)


## Smoke goes under everything else, so it is drawn on its own first.
func draw_smoke(b: LiteBatch) -> void:
	for i: int in _kind.size():
		if _kind[i] != SMOKE:
			continue
		var t: float = _age[i] / _life[i]
		var grow: float = 1.0 - (1.0 - t) * (1.0 - t)
		var a: float = minf(1.0, t * 12.0) * pow(1.0 - t, 1.5) * 0.42
		var c: Color = SMOKE_DARK.lerp(SMOKE_LIGHT, t)
		c.a = a
		b.disc(_pos[i], lerpf(_r0[i], _r1[i], grow), c)


func draw_fire(b: LiteBatch, clock: float) -> void:
	for i: int in _kind.size():
		var kind: int = _kind[i]
		if kind == SMOKE:
			continue
		var t: float = _age[i] / _life[i]
		var inv: float = 1.0 - t
		var p: Vector2 = _pos[i]
		match kind:
			FIRE:
				var c: Color = FIRE_HOT.lerp(FIRE_MID, minf(1.0, t * 2.5)) if t < 0.4 else FIRE_MID.lerp(FIRE_COOL, (t - 0.4) / 0.6)
				c.a = 0.9 * inv
				b.disc(p, lerpf(_r0[i], _r1[i], 1.0 - inv * inv), c)
			EMBER:
				var f: float = 0.55 + 0.45 * sin(clock * 17.0 + float(i) * 2.3) * sin(clock * 7.0 + float(i))
				b.disc(p, _r0[i] * 2.6, Color(1.0, 0.35, 0.08, 0.22 * f * inv))
				b.disc(p, _r0[i], Color(1.0, 0.75, 0.35, 0.85 * f * minf(1.0, inv * 3.0)))
			SPARK:
				var v: Vector2 = _vel[i]
				var c: Color = FIRE_HOT.lerp(FIRE_MID, t)
				c.a = inv
				b.line(p, p - v * 0.045, c, 1.2)
			SHOCK:
				var r: float = lerpf(_r0[i], _r1[i], 1.0 - inv * inv * inv)
				b.ring(p, r, Color(1.0, 0.92, 0.8, 0.55 * inv * inv), 0.6 + 2.2 * inv)
			FLASH:
				b.disc(p, lerpf(_r0[i], _r1[i], t), Color(1.0, 0.97, 0.88, 0.95 * inv * inv))
