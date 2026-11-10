class_name LiteView
extends Node2D

var main: LiteMain
var _pal: Image
var _pal_tex: ImageTexture
var _shown: PackedColorArray = PackedColorArray()
var _clock: float = 0.0
var _pts: Array[Vector2] = []
var _b: LiteBatch = LiteBatch.new()
var _parts: LiteParticles = LiteParticles.new()

var _known: Dictionary = {}
var _sim_time: float = -1.0

var _shake: float = 0.0
var _shake_rng: RandomNumberGenerator = RandomNumberGenerator.new()

## The paths missiles leave in the air: a point every few map units, each
## fading over `fade` seconds of game time, so a trail outlives its missile
## and thins away slowly instead of vanishing with it.
class Trace:
	var pts: PackedVector2Array = PackedVector2Array()
	var born: PackedFloat32Array = PackedFloat32Array()
	## Per point, how thick its smoke is, 0 (the trail's own thin line) to 1
	## (a motor's smoke at full burn). It changes smoothly along the trail.
	var thick: PackedFloat32Array = PackedFloat32Array()
	## The thin line: its colour (and alpha), its half width and how much
	## wider it spreads as it ages.
	var col: Color = Color.WHITE
	var half: float = 1.5
	var spread: float = 2.5
	var fade: float = 3.0
	## Where its maker is now, while it lives, and how thick its smoke is
	## there: the trail runs right up to it.
	var head: Vector2 = Vector2.ZERO
	var head_thick: float = 0.0
	var live: bool = true
	## A smoke trail (a SAM's, a ballistic missile's) rather than a faint wake.
	var smoky: bool = false

## Live trails by the missile or interceptor that makes them; finished ones.
var _traces: Dictionary = {}
var _old_traces: Array[Trace] = []
const SAM_FADE: float = 4.5
const SAM_SMOKE: Color = Color(0.86, 0.87, 0.9, 0.38)
const BALLISTIC_FADE: float = 10.0
## A ballistic missile's motor burns for this much of its flight.
const BURN: float = 0.22
## A SAM climbs almost straight up for this much of its flight, then turns over
## onto its target.
const SAM_CLIMB: float = 0.3
const DRONE_WAKE: Color = Color(0.78, 0.8, 0.85, 0.22)
const CRUISE_WAKE: Color = Color(0.92, 0.94, 0.98, 0.4)

## Fires left burning where warheads landed: x, y, the game time the fire
## dies, and its size.
var _fires: Array[Vector4] = []

var sim: LiteSim:
	get: return main.sim
var map: LiteMap:
	get: return main.map

func build() -> void:
	var map_: LiteMap = map
	var img: Image = Image.create_from_data(LiteMap.RW, LiteMap.RH, false, Image.FORMAT_R8, map_.ids)
	_pal = Image.create_empty(256, 2, false, Image.FORMAT_RGBA8)
	_shown.resize(map_.regions.size())
	for i: int in _shown.size():
		_shown[i] = target(i)
		_pal.set_pixel(i, 0, _shown[i])
		_pal.set_pixel(i, 1, Color(map_.regions[i].side, 0, 0, 1))
	_pal_tex = ImageTexture.create_from_image(_pal)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://src/Lite/lite_map.gdshader") as Shader
	var ids: ImageTexture = ImageTexture.create_from_image(img)
	mat.set_shader_parameter("ids", ids)
	mat.set_shader_parameter("palette", _pal_tex)
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = ids
	sprite.centered = false
	sprite.scale = Vector2.ONE / LiteMap.S
	sprite.material = mat
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.show_behind_parent = true
	add_child(sprite)
	var labels: LiteLabels = LiteLabels.new()
	labels.map = map_
	labels.show_behind_parent = true
	add_child(labels)
	# Air defence ranges change only when a site is built, lost or spotted:
	# drawn on a layer of their own, over the map, and redrawn only then.
	_ranges = Node2D.new()
	_ranges.show_behind_parent = true
	_ranges.draw.connect(_draw_ranges)
	add_child(_ranges)
	# Drones and cruise missiles, and their shadows, are drawn many at a time
	# from one mesh each (see _fill_flock); shadows under everything else on
	# the map, the weapons over the trails and buildings. Above them a layer
	# for what flies or burns over the weapons: interceptors, blasts, fire.
	for k: int in 4:
		var mm:= MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		# Its bounds are never worked out again when its buffer is replaced
		# whole: a fixed box round the map, so it is never culled.
		mm.custom_aabb = AABB(Vector3(-500, -500, -1), Vector3(LiteMap.W + 1000, LiteMap.H + 1000, 2))
		var pts: PackedVector2Array = LiteGlyphs.DRONE_PTS if k % 2 == 0 else LiteGlyphs.CRUISE_PTS
		mm.mesh = LiteGlyphs.mesh(pts, WEAPON_SCALE, DARK if k < 2 else null)
		var node:= MultiMeshInstance2D.new()
		node.multimesh = mm
		node.show_behind_parent = k >= 2
		add_child(node)
		_flock.append(mm)
		_flock_buf.append(PackedFloat32Array())
	_top = Node2D.new()
	_top.draw.connect(_draw_top)
	add_child(_top)

## Drones (0) and cruise missiles (1), then their shadows (2, 3).
var _flock: Array[MultiMesh] = []
var _flock_buf: Array[PackedFloat32Array] = []
var _flock_n: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _top: Node2D = null
var _top_b: LiteBatch = LiteBatch.new()

## One copy of a weapon's glyph in its MultiMesh: where, which way, what colour.
func _put(k: int, at: Vector2, ang: float, col: Color) -> void:
	var n: int = _flock_n[k]
	var mm: MultiMesh = _flock[k]
	if n >= mm.instance_count:
		mm.instance_count = maxi(64, mm.instance_count * 2)
		_flock_buf[k].resize(mm.instance_count * 12)
	var buf: PackedFloat32Array = _flock_buf[k]
	var cs: float = cos(ang) * WEAPON_SCALE
	var sn: float = sin(ang) * WEAPON_SCALE
	var i: int = n * 12
	buf[i] = cs
	buf[i + 1] = -sn
	buf[i + 2] = 0.0
	buf[i + 3] = at.x
	buf[i + 4] = sn
	buf[i + 5] = cs
	buf[i + 6] = 0.0
	buf[i + 7] = at.y
	buf[i + 8] = col.r
	buf[i + 9] = col.g
	buf[i + 10] = col.b
	buf[i + 11] = col.a
	_flock_n[k] = n + 1

## Fills the MultiMeshes with this frame's drones and cruise missiles.
func _fill_flock() -> void:
	_flock_n.fill(0)
	for w: LiteWeapon in sim.weapons:
		if w.arm == LiteArm.BALLISTIC or not shown_weapon(w):
			continue
		var at: Vector2 = w.view_pos()
		var ang: float = w.dir.angle()
		if w.arm == LiteArm.DRONE:
			# It wobbles a little in the wind.
			_put(0, at, ang + sin(_clock * 5.0 + w.id * 1.7) * 0.08, weapon_color(w.side))
			_put(2, at - LIFT * 5.0, ang, SHADOW)
		else:
			_put(1, at, ang, weapon_color(w.side))
			_put(3, at - LIFT * 4.0, ang, SHADOW)
	for k: int in 4:
		var mm: MultiMesh = _flock[k]
		if mm.instance_count > 0:
			RenderingServer.multimesh_set_buffer(mm.get_rid(), _flock_buf[k])
		mm.visible_instance_count = _flock_n[k]

## The ranges layer, and what it shows (see _ranges_key).
var _ranges: Node2D = null
var _ranges_b: LiteBatch = LiteBatch.new()
var _ranges_at: int = -1

func _ranges_key() -> int:
	if not LiteSettings.ranges:
		return 0
	var key: int = 1
	for s: LiteBuilding in sim.buildings:
		if s.alive and (s.is_ad or s.is_gun) and s.ready and shown(s):
			key = (key * 31 + s.id) % 1000000007
	return key

func _draw_ranges() -> void:
	var b: LiteBatch = _ranges_b
	b.begin(_ranges)
	if LiteSettings.ranges:
		for s: LiteBuilding in sim.buildings:
			if not s.alive or not (s.is_ad or s.is_gun) or not s.ready or not shown(s):
				continue
			var col: Color = LiteGlyphs.side_color(s.side)
			var r: float = LiteRules.range(s.kind)
			b.disc(s.pos, r, Color(col, 0.035), false)
			b.ring(s.pos, r, Color(col, 0.16), 1.0)
	b.flush()

## A province changed hands: the shader draws the frontier from each region's
## side (row 1); the fills follow on their own.
func refresh_sides() -> void:
	for i: int in main.map.regions.size():
		_pal.set_pixel(i, 1, Color(main.map.regions[i].side, 0, 0, 1))
	_pal_tex.update(_pal)

func target(i: int) -> Color:
	var sim_: LiteSim = main.sim
	var r: LiteRegion = main.map.regions[i]
	var land: Color = LiteGlyphs.OUR_LAND if r.side == 0 else LiteGlyphs.ENEMY_LAND
	var c: Color = land
	# A campaign mission's province glows violet, gently pulsing, until it is decided.
	var m: LiteMission = main.mission
	if m != null and m.result < 0 and main.map.province(i) == m.region:
		c = c.lerp(LiteGlyphs.OBJECTIVE, 0.22 + 0.08 * sin(_clock * 2.6))
	if sim_.alert[i]:
		if r.side == 0:
			c = LiteGlyphs.MISSILE_ALERT if sim_.missile[i] else LiteGlyphs.AIR_ALERT
		else:
			c = LiteGlyphs.ENEMY_MISSILE_ALERT if sim_.missile[i] else LiteGlyphs.ENEMY_ALERT
	if i == main.hover_region:
		c = c.lightened(0.07)
	var f: float = sim_.region_flash[i]
	if f > 0:
		c = c.lerp(LiteGlyphs.HIT_GLOW, f * 0.4)
	return c

func _process(delta: float) -> void:
	var dt: float = delta
	_clock += dt
	var k: float = 1 - exp(-dt * 7.0)
	for i: int in _shown.size():
		_shown[i] = _shown[i].lerp(target(i), k)
		_pal.set_pixel(i, 0, _shown[i])
	_pal_tex.update(_pal)
	_particles(dt)
	_update_traces()
	queue_redraw()
	_top.queue_redraw()

func _update_traces() -> void:
	var sim_: LiteSim = main.sim
	var now: float = sim_.time
	for i: LiteInterceptor in sim_.interceptors:
		if i.alive:
			var f: float = sam_frac(i)
			# Thick smoke on the climb, thinning smoothly as it turns over.
			var k: float = 1.0 - smoothstep(SAM_CLIMB - 0.08, SAM_CLIMB + 0.3, f)
			_feed(i, sam_point(i, f), k, SAM_SMOKE, 1.6, 4.0, SAM_FADE, now, 3.0)
	for i: Variant in _sam_k.keys():
		if not i.alive:
			_sam_k.erase(i)
	for w: LiteWeapon in sim_.weapons:
		if not shown_weapon(w):
			continue
		match w.arm:
			LiteArm.BALLISTIC:
				var p: float = w.progress
				# Thick smoke while the motor burns, thinning into a pale streak.
				var k: float = 1.0 - smoothstep(BURN * 0.55, BURN * 1.5, p)
				_feed(w, _air(w, p), k, Color(weapon_color(w.side).lightened(0.55), 0.6), 1.5, 2.5, BALLISTIC_FADE, now, 5.0)
			LiteArm.CRUISE:
				_feed(w, w.view_pos() - w.dir * 5.4, 0.0, CRUISE_WAKE, 1.0, 2.5, 2.5, now, 14.0)
			_:
				_feed(w, w.view_pos() - w.dir * 2.4, 0.0, DRONE_WAKE, 1.0, 2.5, 1.5, now, 10.0)
	for owner: Variant in _traces.keys():
		if not owner.alive:
			var done: Trace = _traces[owner]
			done.live = false
			# A smoke trail cut off in the air: the smoke billows where it ends.
			var n: int = done.pts.size()
			if done.smoky and n >= 2 and not (owner is LiteWeapon and owner.arm == LiteArm.BALLISTIC and owner.progress > 0.97):
				var tip: Vector2 = done.head
				_parts.trail_end(tip, (tip - done.pts[n - 2]).normalized())
				done.pts.append(tip)
				done.born.append(now)
				done.thick.append(done.head_thick)
			_old_traces.append(done)
			_traces.erase(owner)
	var k: int = 0
	for t: Trace in _old_traces:
		_trim(t, now)
		if t.pts.size() >= 2:
			_old_traces[k] = t
			k += 1
	_old_traces.resize(k)
	for t: Trace in _traces.values():
		_trim(t, now)

func _feed(owner: Variant, p: Vector2, thick: float, col: Color, half: float, spread: float, fade: float, now: float, gap: float) -> void:
	var t: Trace = _traces.get(owner)
	if t == null:
		t = Trace.new()
		t.col = col
		t.half = half
		t.spread = spread
		t.fade = fade
		t.smoky = owner is LiteInterceptor or (owner is LiteWeapon and owner.arm == LiteArm.BALLISTIC)
		_traces[owner] = t
	t.head = p
	t.head_thick = thick
	var n: int = t.pts.size()
	if n == 0 or t.pts[n - 1].distance_to(p) > gap:
		t.pts.append(p)
		t.born.append(now)
		t.thick.append(thick)

## Drops the points that have faded out, oldest first.
func _trim(t: Trace, now: float) -> void:
	var cut: int = 0
	while cut < t.born.size() and now - t.born[cut] >= t.fade:
		cut += 1
	if cut > 0:
		t.pts = t.pts.slice(cut)
		t.born = t.born.slice(cut)
		t.thick = t.thick.slice(cut)

## A trail, drawn as one soft ribbon: smoke that spreads and thins as it ages,
## a pale streak, or a faint wake; all of it fades to nothing.
var _rp: PackedVector2Array = PackedVector2Array()
var _rh: PackedFloat32Array = PackedFloat32Array()
var _rc: PackedColorArray = PackedColorArray()

func draw_trace(t: Trace, now: float) -> void:
	var n: int = t.pts.size()
	var count: int = n + (1 if t.live and n > 0 else 0)
	if count < 2:
		return
	_rp.resize(count)
	_rh.resize(count)
	_rc.resize(count)
	for k: int in count:
		var age: float = clampf((now - t.born[k]) / t.fade, 0.0, 1.0) if k < n else 0.0
		var a: float = 1.0 - age
		var w: float = t.thick[k] if k < n else t.head_thick
		_rp[k] = t.pts[k] if k < n else t.head
		# One ribbon all along: the thin line and the thick smoke blend into
		# each other, in colour, width and strength, as `thick` changes.
		var thin:= Color(t.col, t.col.a * a)
		var thin_h: float = t.half + t.spread * age
		if w <= 0.001:
			_rc[k] = thin; _rh[k] = thin_h
			continue
		var smoke:= Color(0.86, 0.87, 0.9, 0.5 * a * a); var smoke_h: float = 2.5 + 7.0 * age
		_rc[k] = thin.lerp(smoke, w)
		_rh[k] = lerpf(thin_h, smoke_h, w)
	# The oldest end thins away instead of stopping square.
	_rc[0] = Color(_rc[0], 0.0)
	_rh[0] *= 0.5
	# Where a trail was cut off it does not stop dead either: its last stretch
	# spreads and fades out, into the smoke left there.
	if not t.live:
		var span: float = 22.0 if t.smoky else 10.0
		var run: float = 0.0
		var k: int = count - 1
		while k > 0 and run < span:
			var s: float = run / span
			s = s * s * (3.0 - 2.0 * s)
			_rc[k] = Color(_rc[k], _rc[k].a * s)
			_rh[k] *= 1.0 + 1.3 * (1.0 - s)
			run += _rp[k].distance_to(_rp[k - 1])
			k -= 1
	_b.ribbon(_rp, _rh, _rc)

func _particles(dt: float) -> void:
	var sim_: LiteSim = main.sim
	var dts: float = 0.0 if _sim_time < 0 else maxf(0.0, sim_.time - _sim_time)
	_sim_time = sim_.time
	var known: Dictionary = {}
	for f: LiteFx in sim_.fx:
		known[f] = true
		if _known.has(f):
			continue
		match f.kind:
			LiteFxKind.BLAST:
				_parts.blast(f.a, f.size)
				var heavy: bool = f.size >= 20.0
				if heavy:
					_parts.ballistic_blast(f.a, f.size, LIFT)
				# Ballistic and cruise warheads leave a fire burning, and smoke rolling off it.
				if f.size >= 14.0:
					_fires.append(Vector4(f.a.x, f.a.y, sim_.time + (16.0 if heavy else 7.0), f.size * (1.0 if heavy else 0.75)))
				if f.side == 1:
					_shake = minf(14.0 if heavy else 9.0, _shake + f.size * (0.6 if heavy else 0.3))
			LiteFxKind.POP:
				var at: Vector2 = f.a + f.b
				_parts.pop(at, f.size)
				_parts.debris(at, -LIFT, maxf(f.b.length(), 5.0))
			LiteFxKind.LAUNCH:
				if f.life > 0.6 and int(f.size) == LiteArm.BALLISTIC:
					_parts.ballistic_launch(f.a, LIFT)
				elif f.life > 0.6:
					_parts.launch(f.a)
				else:
					# A SAM firing: ours loud, the enemy's far off.
					main.audio.play("sam_launch.wav", -13.0 if f.side == 0 else -23.0, 0.15)
					_parts.sam_launch(f.a)
			LiteFxKind.TRACER:
				main.gun_shot_at[f.side] = sim_.time
			LiteFxKind.PUFF:
				_parts.puff(f.a + f.b, f.size)
	_known = known
	if dts > 0:
		for s: LiteBuilding in sim_.buildings:
			if not s.alive and sim_.time - s.dead_at < 25.0 and shown(s) and randf() < dts / 0.3:
				_parts.ruin(s.pos)
		# Motors leave puffs of smoke hanging in the air: a SAM's, thick while it
		# climbs; a ballistic missile's while it burns.
		for i: LiteInterceptor in sim_.interceptors:
			if not i.alive:
				continue
			var f: float = sam_frac(i)
			if f < SAM_CLIMB and randf() < dts / 0.03:
				_parts.contrail(sam_point(i, f), 2.0, 7.0, 2.5, 4.0)
		for w: LiteWeapon in sim_.weapons:
			if w.arm == LiteArm.BALLISTIC and shown_weapon(w) and w.progress < BURN and randf() < dts / 0.015:
				var p: float = w.progress
				_parts.contrail(_air(w, p) - _air_dir(w, p) * 9.0, 3.0, 11.0, 4.0, 7.0)
		# The fires: fiercest at first, dying down.
		var k: int = 0
		for f: Vector4 in _fires:
			var left: float = f.z - sim_.time
			if left <= 0.0:
				continue
			_fires[k] = f
			k += 1
			var fierce: float = clampf(left / 12.0, 0.15, 1.0)
			if randf() < dts / 0.06:
				_parts.burn(Vector2(f.x, f.y), f.w, fierce, LIFT)
		_fires.resize(k)
	_parts.step(dts)
	_shake *= exp(-dt * 6.0)
	if _shake > 0.15:
		position = Vector2(_shake_rng.randf_range(-1, 1), _shake_rng.randf_range(-1, 1)) * _shake
	else:
		position = Vector2.ZERO

func shown(b: LiteBuilding) -> bool:
	return b.side == 0 or b.seen[0] or main.sim.winner >= 0

func shown_weapon(w: LiteWeapon) -> bool:
	return w.alive and (w.seen[0] or main.sim.winner >= 0)

## Height on the map is drawn as a lift towards the top left, so the sun is up
## there and shadows fall to the bottom right. A weapon's own position (`pos`)
## is its ground track, where its shadow lies.
const LIFT: Vector2 = Vector2(-0.42, -0.91)

static func lifted(p: Vector2, h: float) -> Vector2:
	return p + LIFT * h

## Where a ballistic missile is in the air at progress `p`: its track is the
## straight line from launcher to target, its arc drawn square to it (see
## LiteWeapon.setup_arc).
static func _air(w: LiteWeapon, p: float) -> Vector2:
	return w.start.lerp(w.target, p) + w.arc * w.altitude_at(p)

## Which way it points there, on screen.
static func _air_dir(w: LiteWeapon, p: float) -> Vector2:
	var a: float = clampf(p - 0.01, 0.0, 0.98)
	var d: Vector2 = _air(w, a + 0.02) - _air(w, a)
	return d.normalized() if d.length() > 0.001 else w.dir

## A SAM as drawn. The sim flies it straight at its target; on screen it
## follows one smooth curve: straight up off its launcher, bending over and
## down onto where its target is drawn, so the two meet in the air. The curve
## is a quadratic Bezier from the launcher, through a point high above it, to
## the target; how far along it the SAM is only ever grows, so it never jumps
## back as its target moves.

## How far along its flight a SAM is in the sim, 0 to 1.
static func _sam_f(i: LiteInterceptor, at: Vector2) -> float:
	if i.from == null:
		return 1.0
	var d0: float = i.from.pos.distance_to(at)
	return d0 / maxf(1.0, d0 + at.distance_to(i.goal))

## How far along its curve it is drawn: never less than before.
var _sam_k: Dictionary = {}

func sam_frac(i: LiteInterceptor) -> float:
	var k: float = maxf(float(_sam_k.get(i, 0.0)), _sam_f(i, i.pos))
	_sam_k[i] = k
	return k

## Where a weapon is drawn: a ballistic missile up on its arc, the others on
## their track.
static func drawn_pos(w: LiteWeapon) -> Vector2:
	return _air(w, w.progress) if w.arm == LiteArm.BALLISTIC else w.view_pos()

static func _sam_top(i: LiteInterceptor) -> Vector2:
	return lifted(i.from.pos, clampf(i.from.pos.distance_to(i.goal) * 0.6, 25.0, 75.0))

## The point on its curve `f` of the way along.
static func sam_point(i: LiteInterceptor, f: float) -> Vector2:
	if i.from == null:
		return i.pos
	var u: float = 1.0 - f
	return i.from.pos * (u * u) + _sam_top(i) * (2.0 * u * f) + drawn_pos(i.target) * (f * f)

## The point on the ground under it.
static func sam_shadow(i: LiteInterceptor, f: float) -> Vector2:
	if i.from == null:
		return i.pos
	var u: float = 1.0 - f
	return i.from.pos * (u * u + 2.0 * u * f) + i.target.pos * (f * f)

## Which way it is flying there.
static func sam_dir(i: LiteInterceptor, f: float) -> Vector2:
	if i.from == null:
		return -LIFT
	var d: Vector2 = (_sam_top(i) - i.from.pos) * (2.0 * (1.0 - f)) + (drawn_pos(i.target) - _sam_top(i)) * (2.0 * f)
	return d.normalized() if d.length() > 0.001 else -LIFT

func draw_shadow(w: LiteWeapon) -> void:
	var ang: float = w.dir.angle()
	match w.arm:
		LiteArm.DRONE:
			LiteGlyphs.draw(_b, LiteGlyph.DRONE, w.view_pos() - LIFT * 5.0, WEAPON_SCALE, SHADOW, ang, null, false)
		LiteArm.CRUISE:
			LiteGlyphs.draw(_b, LiteGlyph.CRUISE, w.view_pos() - LIFT * 4.0, WEAPON_SCALE, SHADOW, ang, null, false)
		_:
			# The higher it is, the softer and fainter its shadow.
			var k: float = clampf(w.altitude() / 150.0, 0.0, 1.0)
			_b.disc(w.pos, 3.0 + 7.0 * k, Color(0, 0, 0, 0.16 - 0.08 * k))
			LiteGlyphs.missile(_b, w.pos, 1.1, Color(0, 0, 0, 0.5 - 0.3 * k), ang, null, false)

func _draw() -> void:
	var t0: float = LitePerf.now
	draw_all()
	LitePerf.draw_ms += LitePerf.now - t0

func draw_all() -> void:
	var sim_: LiteSim = sim
	var b: LiteBatch = _b
	b.begin(self)

	if LiteSettings.ranges:
		var key: int = _ranges_key()
		if key != _ranges_at:
			_ranges_at = key
			_ranges.queue_redraw()
		# A site firing lights its range up for a moment.
		for s: LiteBuilding in sim_.buildings:
			if s.fire_flash > 0.02 and s.alive and (s.is_ad or s.is_gun) and s.ready and shown(s):
				b.ring(s.pos, LiteRules.range(s.kind), Color(LiteGlyphs.side_color(s.side), 0.3 * s.fire_flash), 1.0)
	elif _ranges_at != 0:
		_ranges_at = 0
		_ranges.queue_redraw()
	for f: LiteFx in sim_.fx:
		if f.kind == LiteFxKind.SCORCH:

			var fade: float = 1 - f.age / f.life
			b.disc(f.a, f.size * 0.75, Color(0.04, 0.04, 0.05, 0.22 * fade))
			b.disc(f.a, f.size * 0.4, Color(0.02, 0.02, 0.02, 0.45 * fade))
			if f.age < 10.0:
				var glow: float = (1 - f.age / 10.0) * (0.75 + 0.25 * sin(_clock * 11.0 + f.a.x))
				b.disc(f.a, f.size * 0.3, Color(1.0, 0.4, 0.1, 0.4 * glow))
	_parts.draw_smoke(b)
	var now: float = sim_.time
	for t: Trace in _old_traces:
		draw_trace(t, now)
	for t: Trace in _traces.values():
		draw_trace(t, now)

	for w: LiteWeapon in sim_.weapons:
		if not w.alive or w.arm != LiteArm.BALLISTIC:
			continue
		var col: Color = Color(1.0, 0.85, 0.8) if w.side == 1 else LiteGlyphs.OURS
		var k: float = w.progress
		b.ring(w.target, 7 + 20 * (1 - k), Color(col, 0.3 + 0.6 * k), 1.5)
		b.disc(w.target, 2.0, Color(col, 0.8))
	_fill_flock()
	for w: LiteWeapon in sim_.weapons:
		if w.arm == LiteArm.BALLISTIC and shown_weapon(w):
			draw_shadow(w)
	# One route per salvo, from its lead weapon: the rest fly the same way.
	_route_raids.clear()
	for w: LiteWeapon in sim_.weapons:
		if shown_weapon(w) and not _route_raids.has(w.raid):
			_route_raids[w.raid] = true
			draw_route(w)
	for s: LiteBuilding in sim_.buildings:
		if shown(s):
			draw_building(s)
	for w: LiteWeapon in sim_.weapons:
		if shown_weapon(w):
			draw_weapon(w)
	b.flush()

## The layer over the weapons: interceptors, blasts, fires, the capitals'
## names and the tool under the mouse.
func _draw_top() -> void:
	var sim_: LiteSim = sim
	var now: float = sim_.time
	var main_b: LiteBatch = _b
	_b = _top_b
	var b: LiteBatch = _b
	b.begin(_top)
	for i: LiteInterceptor in sim_.interceptors:
		if i.alive:
			draw_interceptor(i)
	for f: LiteFx in sim_.fx:
		draw_fx(f)
	# The ground lit orange under each fire, flickering.
	for f: Vector4 in _fires:
		var left: float = f.z - now
		if left > 0.0:
			var fl: float = 0.8 + 0.2 * sin(_clock * 9.0 + f.x) * sin(_clock * 13.0 + f.y)
			b.puff(Vector2(f.x, f.y), f.w * 1.6, Color(1.0, 0.45, 0.12, 0.28 * clampf(left / 12.0, 0.2, 1.0) * fl))
	_parts.draw_fire(b, _clock)
	b.flush()
	_b = main_b
	for s: LiteBuilding in sim_.buildings:
		if s.alive and s.kind == LiteKind.CAPITAL:
			LiteLabels.draw_label(_top, s.pos + Vector2(0, 26), main.map.capital_name[s.side], 12, LiteGlyphs.TEXT)
	var m: LiteMission = main.mission
	if m != null and m.result < 0 and m.kind != LiteMission.CAPITAL:
		var word: String = "HOLD" if m.kind == LiteMission.HOLD else "OBJECTIVE"
		LiteLabels.draw_label(_top, main.map.regions[m.region].label + Vector2(0, -15), word, 10, LiteGlyphs.OBJECTIVE)
	draw_tool()

func draw_building(s: LiteBuilding) -> void:
	var b: LiteBatch = _b
	var col: Color = LiteGlyphs.side_color(s.side)
	var cap: bool = s.kind == LiteKind.CAPITAL
	var rad: float = 11.0 if cap else 8.0
	var p: Vector2 = s.pos
	if not s.alive:
		var since: float = main.sim.time - s.dead_at
		var a: float = clampf(1 - since / 30.0, 0, 1)
		b.disc(p, rad * 0.8, Color(0.07, 0.07, 0.08, 0.75 * a))
		if since < 20.0:

			var burn: float = 1 - since / 20.0
			for k: int in 3:
				var fl: float = 0.5 + 0.5 * sin(_clock * (9.0 + k * 4.0) + p.x * 0.7 + k * 2.1)
				var off: Vector2 = Vector2(cos(k * 2.1 + p.y), sin(k * 2.1 + p.x)) * rad * 0.35
				b.disc(p + off, rad * (0.35 + 0.25 * fl) * burn + 1.0, Color(1.0, 0.45 + 0.3 * fl, 0.12, 0.55 * burn * fl))
		var x: Color = Color(0.55, 0.57, 0.6, 0.8 * a)
		b.line(p + Vector2(-3.5, -3.5), p + Vector2(3.5, 3.5), x, 1.5)
		b.line(p + Vector2(3.5, -3.5), p + Vector2(-3.5, 3.5), x, 1.5)
		return
	b.disc(p + Vector2(0, 1.5), rad + 1.5, Color(0, 0, 0, 0.3))
	b.disc(p, rad, LiteGlyphs.PAGE.lerp(LiteGlyphs.HIT_GLOW, s.flash * 0.7))
	if s.ready:
		b.ring(p, rad, col, 1.6)
	else:
		b.ring(p, rad, Color(col, 0.25), 1.6)
		var k: float = 1 - s.build / s.build_total
		if k > 0.01:
			b.ring(p, rad, col, 1.6, -PI / 2, -PI / 2 + TAU * k)
	LiteGlyphs.draw(b, LiteGlyphs.of(s.kind), p, 1.25 if cap else 0.95, Color(1, 1, 1, 1.0 if s.ready else 0.45))
	if s.kind == LiteKind.SAM and s.ready and s.side == 0:
		for i: int in LiteRules.SAM_RACK:
			b.disc(p + Vector2((i - 1.5) * 4.0, -rad - 4.0), 1.3, LiteGlyphs.TEXT if i < s.ammo else Color(LiteGlyphs.TEXT, 0.2))
	if cap or s.hp < s.max_hp:
		var w: float = 28.0 if cap else 16.0
		var y: float = p.y + rad + 4
		var bar: Rect2 = Rect2(p.x - w / 2, y, w, 3)
		b.rect(bar, Color(0, 0, 0, 0.55))
		b.rect(Rect2(bar.position, Vector2(w * maxf(0, s.hp) / s.max_hp, 3)), col)

const ENEMY_WEAPON: Color = Color("#ff4f3f")
const OUR_WEAPON: Color = Color("#5cb0ff")

static func weapon_color(side: int) -> Color:
	return ENEMY_WEAPON if side == 1 else OUR_WEAPON

var _route_raids: Dictionary = {}

func draw_route(w: LiteWeapon) -> void:
	var b: LiteBatch = _b
	var col: Color = weapon_color(w.side)
	# Only our own strikes show where they are going; trails are drawn as Traces.
	if not LiteSettings.routes:
		return
	if w.side == 0:
		_pts.clear()
		_pts.append(w.view_pos())
		var path: PackedVector2Array = w.path
		for i: int in range(w.leg, path.size()):
			_pts.append(path[i])
		b.dashed(_pts, Color(col, 0.32), 1.1, 6, 6)
		var t: Vector2 = w.target
		b.line(t + Vector2(-3, -3), t + Vector2(3, 3), Color(col, 0.6), 1.2)
		b.line(t + Vector2(3, -3), t + Vector2(-3, 3), Color(col, 0.6), 1.2)

const DARK: Color = Color(0.05, 0.05, 0.06, 0.85)
const FIREBALL_HOT: Color = Color(1.0, 0.92, 0.6)
const FIREBALL_MID: Color = Color(1.0, 0.55, 0.12)
const FIREBALL_COOL: Color = Color(0.55, 0.12, 0.04)
const SHADOW: Color = Color(0, 0, 0, 0.32)
## Drones and cruise missiles are drawn this big (their glyphs' own size is 1).
const WEAPON_SCALE: float = 0.75

## What is drawn of a weapon besides its glyph (drones' and cruise missiles'
## glyphs come from _fill_flock): a drone's propeller, a cruise missile's
## exhaust, a ballistic missile whole.
func draw_weapon(w: LiteWeapon) -> void:
	match w.arm:
		LiteArm.DRONE:
			# It wobbles a little in the wind, and its pusher propeller spins at the tail.
			var wob: float = sin(_clock * 5.0 + w.id * 1.7) * 0.08
			var d: Vector2 = w.dir.rotated(wob)
			var at: Vector2 = w.view_pos()
			var tail: Vector2 = at - d * 2.4
			var spin: float = absf(sin(_clock * 37.0 + w.id))
			var across: Vector2 = Vector2(-d.y, d.x)
			_b.line(tail + across * 2.3 * spin, tail - across * 2.3 * spin, Color(0.9, 0.92, 0.96, 0.55), 0.8)
		LiteArm.CRUISE:
			# A jet engine: a hot core and a streak of exhaust behind it.
			var fl: float = 0.8 + 0.2 * sin(_clock * 40.0 + w.pos.x)
			var at: Vector2 = w.view_pos()
			var tail: Vector2 = at - w.dir * 5.4
			_b.line_grad(tail - w.dir * (8.0 + 4.0 * fl), tail, Color(1.0, 0.55, 0.2, 0.0), Color(1.0, 0.8, 0.5, 0.85), 1.8)
			_b.disc(tail, 1.7 * fl, Color(1.0, 0.95, 0.8, 0.9))
		_:
			draw_ballistic(w, weapon_color(w.side))

## A ballistic missile flies a parabola. Off the launcher on a short, bright
## burn that leaves smoke; then it coasts, its path behind it a pale trail that
## fades slowly (see Trace) and the rest of its arc dotted ahead to the target;
## on the way down the nose heats up and streaks until it meets its shadow.
func draw_ballistic(w: LiteWeapon, col: Color) -> void:
	var b: LiteBatch = _b
	var p: float = w.progress
	var at: Vector2 = _air(w, p)
	var dir: Vector2 = _air_dir(w, p)
	var k: float = clampf(w.altitude() / 140.0, 0.0, 1.0)
	# Nearer the camera when high up, so a little bigger.
	var s: float = 1.1 + 0.4 * k
	# Pale, over a thin dark edge, so the arc reads over any alert colour.
	var pale: Color = col.lightened(0.55)
	var ahead: int = maxi(2, int(16.0 * (1.0 - p)))
	var prev: Vector2 = at
	for j: int in range(1, ahead + 1):
		var pt: Vector2 = _air(w, lerpf(p, 1.0, float(j) / ahead))
		if j % 2 == 0:
			b.line(prev, pt, Color(0, 0, 0, 0.14), 2.6)
			b.line(prev, pt, Color(pale, 0.4), 1.1)
		prev = pt
	var nozzle: Vector2 = at - dir * 7.0 * s
	if p < BURN:
		# The motor: brightest at lift-off, burning out as it climbs.
		var r: float = 1.0 - p / BURN
		var fl: float = 0.75 + 0.25 * sin(_clock * 47.0 + w.start.x)
		b.disc(nozzle - dir * 6.0 * s, (6.0 + 9.0 * r) * s * fl, Color(1.0, 0.45, 0.12, 0.18 + 0.25 * r))
		b.line_grad(nozzle - dir * (8.0 + 18.0 * r * fl) * s, nozzle, Color(1.0, 0.5, 0.15, 0.0), Color(1.0, 0.78, 0.4, 0.95), (2.4 + 2.6 * r) * s)
		b.line(nozzle, nozzle - dir * (4.0 + 6.0 * r * fl) * s, Color(1.0, 0.97, 0.85, 0.95), (1.2 + 1.2 * r) * s)
		b.disc(nozzle - dir * 1.2 * s, (2.2 + 1.2 * r) * s, Color(1.0, 0.97, 0.88, 0.95))
	elif p > 0.62:
		# Coming down: the nose heats up, glows and streaks, brighter to the end.
		var r: float = (p - 0.62) / 0.38
		b.line_grad(at - dir * (12.0 + 30.0 * r), at, Color(1.0, 0.55, 0.25, 0.0), Color(1.0, 0.82, 0.6, 0.8 * r), 1.5 + 2.0 * r)
		b.disc(at + dir * 5.0 * s, 3.0 + 6.0 * r, Color(1.0, 0.55, 0.25, 0.12 + 0.25 * r))
		b.disc(at + dir * 5.0 * s, 1.5 + 2.0 * r, Color(1.0, 0.92, 0.75, 0.3 + 0.5 * r))
	LiteGlyphs.missile(b, at, s, col.lightened(0.35), dir.angle(), DARK)

## A SAM in flight: a small white missile on a burning motor; its smoke is
## its trail (see Trace). Its shadow runs along the ground below it.
func draw_interceptor(i: LiteInterceptor) -> void:
	var f: float = sam_frac(i)
	_b.disc(sam_shadow(i, f), 1.4, Color(0, 0, 0, 0.3))
	var head: Vector2 = sam_point(i, f)
	var dir: Vector2 = sam_dir(i, f)
	# The motor burns hardest on the climb.
	var hard: float = 1.4 if f < SAM_CLIMB else 1.0
	var fl: float = 0.75 + 0.25 * sin(_clock * 53.0 + i.age * 31.0)
	var nozzle: Vector2 = head - dir * 3.3
	_b.disc(nozzle - dir * 2.0, 3.4 * fl * hard, Color(1.0, 0.5, 0.15, 0.4))
	_b.line(nozzle, nozzle - dir * (5.0 + 4.0 * fl) * hard, Color(1.0, 0.75, 0.35, 0.85), 2.0 * hard)
	LiteGlyphs.missile(_b, head, 0.55, Color(0.94, 0.95, 0.98), dir.angle(), DARK)
	_b.disc(nozzle, 1.3, Color(1.0, 0.97, 0.85))

func draw_fx(f: LiteFx) -> void:
	var b: LiteBatch = _b
	var t: float = f.age / f.life
	var inv: float = 1 - t
	match f.kind:
		LiteFxKind.BLAST:
			var grow: float = 1 - inv * inv
			if f.size >= 20.0:
				# A ballistic warhead: the ground lights up wide round it.
				b.puff(f.a, f.size * (1.6 + 2.2 * grow), Color(1.0, 0.55, 0.25, 0.3 * inv * inv))
			# The fireball: a cluster of billows swelling and rising, lit on
			# top and sooty underneath, white-hot at first, then orange, then
			# dull red as it burns out, a hot core fading inside it.
			var heat: Color = FIREBALL_HOT.lerp(FIREBALL_MID, t / 0.3) if t < 0.3 else FIREBALL_MID.lerp(FIREBALL_COOL, (t - 0.3) / 0.7)
			var lit:= Color(heat, 0.95 * pow(inv, 0.7))
			var dark:= Color(heat.darkened(0.55), lit.a * 0.9)
			var ball: Vector2 = f.a + LIFT * f.size * 0.4 * grow
			var r: float = f.size * (0.35 + 0.55 * grow)
			for j: int in 5:
				var off: Vector2 = Vector2.from_angle(j * TAU / 5.0 + f.a.x * 0.13) * r * (0.35 + 0.25 * grow) + LIFT * r * 0.3 * (j % 2)
				b.puff_lit(ball + off, r * (0.8 - 0.07 * j), lit, dark, LiteParticles.LIGHT)
			b.puff(ball, maxf(0.5, f.size * 0.6 * inv * inv), Color(1.0, 0.96, 0.8, inv))
		LiteFxKind.POP:
			# A flash that glints for a moment, and its shockwave.
			var at: Vector2 = f.a + f.b
			var g: float = maxf(0.0, 1.0 - t * 3.0)
			if g > 0.0:
				var l: float = f.size * 3.2 * g
				b.line_grad(at - Vector2(l, 0), at, Color(1, 1, 1, 0), Color(1, 0.98, 0.9, 0.9 * g), 1.4)
				b.line_grad(at + Vector2(l, 0), at, Color(1, 1, 1, 0), Color(1, 0.98, 0.9, 0.9 * g), 1.4)
				b.line_grad(at - Vector2(0, l * 0.7), at, Color(1, 1, 1, 0), Color(1, 0.98, 0.9, 0.8 * g), 1.2)
				b.line_grad(at + Vector2(0, l * 0.7), at, Color(1, 1, 1, 0), Color(1, 0.98, 0.9, 0.8 * g), 1.2)
			b.ring(at, 2 + f.size * 1.8 * t, Color(1, 0.95, 0.85, 0.5 * inv * inv), 1.0)
		LiteFxKind.PUFF:
			b.disc(f.a + f.b, 2 + f.size * t, Color(0.75, 0.77, 0.8, 0.45 * inv))
		LiteFxKind.TRACER:
			# A burst of rounds flying out from the gun, a flash at the muzzle,
			# a spark where they reach.
			var d: Vector2 = f.b - f.a
			b.line(f.a + d * clampf(t * 1.4 - 0.4, 0.0, 1.0), f.a + d * clampf(t * 1.4, 0.0, 1.0), Color(1.0, 0.9, 0.55, 0.95), 1.3)
			if t < 0.35:
				b.disc(f.a + d.normalized() * 3.0, 2.4 * (1.0 - t / 0.35), Color(1.0, 0.85, 0.5, 0.85))
			if t > 0.75:
				b.disc(f.b, 1.6, Color(1.0, 0.9, 0.6, (t - 0.75) * 3.0))
		LiteFxKind.LAUNCH:
			b.ring(f.a, 2 + 9 * t, Color(LiteGlyphs.side_color(f.side), 0.6 * inv), 1.3)

func draw_tool() -> void:
	var p: Vector2 = main.mouse
	var sim_: LiteSim = main.sim
	var map_: LiteMap = main.map
	if main.build_tool != null and main.build_tool == LiteKind.FACTORY:

		for r: LiteRegion in map_.regions:
			if r.side != 0 or r.city:
				continue
			var f: int = sim_.factories_in(r.id)
			var ru: int = sim_.ruins_in(r.id)
			var n: int = sim_.slots[r.id]
			var at: Vector2 = r.label + Vector2(-(n - 1) * 5.0, 13)
			if n == 0:
				_top.draw_string(LiteGlyphs.font, r.label + Vector2(-30, 18), "no room", HORIZONTAL_ALIGNMENT_CENTER, 60, 9, LiteGlyphs.FAINT)
				continue
			for i: int in n:
				var c: Vector2 = at + Vector2(i * 10.0, 0)
				var box: Rect2 = Rect2(c - Vector2(3.5, 3.5), Vector2(7, 7))
				if i < f:
					_top.draw_rect(box, LiteGlyphs.OURS)
				elif i < f + ru:
					_top.draw_rect(box, LiteGlyphs.MUTED, false, 1.2)
					_top.draw_line(box.position, box.end, LiteGlyphs.MUTED, 1.2, true)
				else:
					_top.draw_rect(box, LiteGlyphs.GOOD, false, 1.4)
		return
	if main.build_tool != null:
		var k: int = main.build_tool
		var ok: bool = sim_.can_place(0, p) and sim_.sides[0].money >= sim_.cost(0, k)
		var col: Color = LiteGlyphs.OURS if ok else LiteGlyphs.ENEMY
		if k != LiteKind.FACTORY:
			var r: float = LiteRules.range(k)
			_top.draw_circle(p, r, Color(col, 0.08))
			_top.draw_arc(p, r, 0, TAU, 72, Color(col, 0.55), 1.2, true)
		_top.draw_circle(p, 8, Color(LiteGlyphs.PAGE, 0.85), true, -1, true)
		_top.draw_arc(p, 8, 0, TAU, 36, col, 1.6, true)
		LiteGlyphs.draw_ci(_top, LiteGlyphs.of(k), p, 0.95, Color(1, 1, 1, 0.85))
	elif main.strike_tool != null:
		var a: int = main.strike_tool
		var at: Vector2 = main.strike_target
		var ok: bool = map_.side_at(at) == 1
		if main.drawing != null:

			var route: Array[Vector2] = main.drawing
			var pts: Array[Vector2] = route.duplicate()
			pts.append(at)
			var line: Color = Color(LiteGlyphs.YELLOW, 0.85)
			var i: int = 0
			while i + 1 < pts.size():
				_top.draw_dashed_line(pts[i], pts[i + 1], line, 1.6, 6.0, true, true)
				i += 1
			_top.draw_circle(pts[0], 3.0, line, true, -1, true)
		var col: Color = LiteGlyphs.YELLOW if ok else LiteGlyphs.MUTED
		var r: float = LiteRules.blast(a) + LiteRules.scatter(a)
		_top.draw_arc(at, r, 0, TAU, 48, col, 1.4, true)
		for i: int in 4:
			var d: Vector2 = Vector2(1, 0).rotated(i * PI / 2)
			_top.draw_line(at + d * (r - 4), at + d * (r + 5), col, 1.4, true)
		if main.strike_snap != null:
			_top.draw_arc(at, 12, 0, TAU, 32, Color.WHITE, 1.2, true)
		if ok:
			var s: String = "%d× %s · $%d" % [main.salvo, LiteGlyphs.plural(a, main.salvo), LiteRules.cost(a) * main.salvo]
			var font: Font = LiteGlyphs.bold
			_top.draw_string_outline(font, at + Vector2(r + 8, 4), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(0, 0, 0, 0.6))
			_top.draw_string(font, at + Vector2(r + 8, 4), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LiteGlyphs.TEXT)
