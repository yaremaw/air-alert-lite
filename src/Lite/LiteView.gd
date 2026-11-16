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
## When the bomb went off (for its flash over everything), -99 never.
var _nuke_at: float = -99.0

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

## Where drones, cruise missiles and interceptors are drawn and which way
## they point, eased out of sudden changes (a corner taken in one step); the
## sim's own positions are only read (see LiteMotion, _track_motion).
var motion: LiteMotion = LiteMotion.new()
var _motion_time: float = -1.0

var sim: LiteSim:
	get: return main.sim
var map: LiteMap:
	get: return main.map

func build() -> void:
	# The legacy look keeps its soft smoke and fire (see LiteCmdView).
	LiteParticles.pixel = false
	var map_: LiteMap = map
	var img: Image = Image.create_from_data(LiteMap.RW, LiteMap.RH, false, Image.FORMAT_R8, map_.ids)
	_pal = Image.create_empty(256, 3, false, Image.FORMAT_RGBA8)
	_shown.resize(map_.regions.size())
	for i: int in _shown.size():
		_shown[i] = target(i)
		_pal.set_pixel(i, 0, _shown[i])
		_pal.set_pixel(i, 1, Color(map_.regions[i].side, 0, 0, 1))
		_pal.set_pixel(i, 2, Color(i / 255.0, 0, 0, 1))
	_pal_tex = ImageTexture.create_from_image(_pal)
	# The world round the two countries, under everything.
	if map_.world != null:
		var wimg: Image = Image.create_from_data(LiteWorld.WW, LiteWorld.WH, false, Image.FORMAT_R8, map_.world.ids)
		var wmat:= ShaderMaterial.new()
		wmat.shader = load("res://src/Lite/lite_world.gdshader") as Shader
		var wtex: ImageTexture = ImageTexture.create_from_image(wimg)
		wmat.set_shader_parameter("ids", wtex)
		wmat.set_shader_parameter("sea_col", LiteGlyphs.SEA)
		wmat.set_shader_parameter("land_col", LiteGlyphs.NEUTRAL_LAND)
		wmat.set_shader_parameter("line_col", LiteGlyphs.NEUTRAL_LINE)
		wmat.set_shader_parameter("ours_col", LiteGlyphs.OUR_LAND.lerp(LiteGlyphs.NEUTRAL_LAND, 0.25))
		wmat.set_shader_parameter("theirs_col", LiteGlyphs.ENEMY_LAND.lerp(LiteGlyphs.NEUTRAL_LAND, 0.2))
		# An operation's map (towns marked) shows the war map's world enlarged.
		wmat.set_shader_parameter("soft", 2 if map_.towns.size() > 0 else 0)
		var ws: Sprite2D = Sprite2D.new()
		ws.texture = wtex
		ws.centered = false
		ws.position = -LiteWorld.PAD
		ws.scale = Vector2(LiteWorld.K, LiteWorld.K)
		ws.material = wmat
		ws.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ws.show_behind_parent = true
		add_child(ws)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://src/Lite/lite_map.gdshader") as Shader
	var ids: ImageTexture = ImageTexture.create_from_image(img)
	mat.set_shader_parameter("ids", ids)
	mat.set_shader_parameter("palette", _pal_tex)
	# Districts, one per map unit; a map baked before them has none to draw.
	var subs: Image
	if map_.sub.size() == LiteMap.W * LiteMap.H:
		subs = Image.create_from_data(LiteMap.W, LiteMap.H, false, Image.FORMAT_R8, map_.sub)
	else:
		subs = Image.create_empty(LiteMap.W, LiteMap.H, false, Image.FORMAT_R8)
	mat.set_shader_parameter("subs", ImageTexture.create_from_image(subs))
	if map_.world != null:
		mat.set_shader_parameter("world", ImageTexture.create_from_image(Image.create_from_data(LiteWorld.WW, LiteWorld.WH, false, Image.FORMAT_R8, map_.world.ids)))
		mat.set_shader_parameter("has_world", true)
		mat.set_shader_parameter("world_pad", LiteWorld.PAD)
		mat.set_shader_parameter("world_k", float(LiteWorld.K))
		mat.set_shader_parameter("per_unit", float(LiteMap.S))
		mat.set_shader_parameter("edge_col", LiteGlyphs.NEUTRAL_EDGE)
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
func _put(k: int, at: Vector2, ang: float, col: Color, scale: float = 1.0) -> void:
	var n: int = _flock_n[k]
	var mm: MultiMesh = _flock[k]
	if n >= mm.instance_count:
		mm.instance_count = maxi(64, mm.instance_count * 2)
		_flock_buf[k].resize(mm.instance_count * 12)
	var buf: PackedFloat32Array = _flock_buf[k]
	var cs: float = cos(ang) * WEAPON_SCALE * scale
	var sn: float = sin(ang) * WEAPON_SCALE * scale
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
		var at: Vector2 = vis_pos(w)
		var ang: float = vis_angle(w)
		if w.arm == LiteArm.DRONE:
			# It wobbles a little in the wind.
			_put(0, at, ang + sin(_clock * 5.0 + w.id * 1.7) * 0.08, Color(weapon_color(w.side), sure(w)), ARM_K[0])
			_put(2, at - LIFT * 5.0, ang, SHADOW, ARM_K[0])
		else:
			_put(1, at, ang, Color(weapon_color(w.side), sure(w)), ARM_K[1])
			_put(3, at - LIFT * 4.0, ang, SHADOW, ARM_K[1])
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

## The campaign's front: regions drawn as one, the provinces inside each in
## fainter lines (palette row 2: each region's group).
func set_groups(group_of: PackedInt32Array) -> void:
	for i: int in main.map.regions.size():
		var g: int = group_of[i] if i < group_of.size() and group_of[i] >= 0 else i
		_pal.set_pixel(i, 2, Color(g / 255.0, 0, 0, 1))
	_pal_tex.update(_pal)

func target(i: int) -> Color:
	var sim_: LiteSim = main.sim
	var r: LiteRegion = main.map.regions[i]
	var land: Color = LiteGlyphs.OUR_LAND if r.side == 0 else LiteGlyphs.ENEMY_LAND
	var c: Color = land
	# A campaign operation's province glows violet, gently pulsing, until it
	# is decided; on the front, the provinces that can be attacked a little,
	# the one picked more.
	var m: LiteMission = main.mission
	if m != null and m.result < 0 and main.map.focus.has(i):
		c = c.lerp(LiteGlyphs.OBJECTIVE, 0.16 + 0.06 * sin(_clock * 2.6))
	elif m == null and main.front_open:
		var p: int = main.campaign.group_at(i) if main.campaign != null else main.map.province(i)
		if p == main.front_pick:
			c = c.lerp(LiteGlyphs.OBJECTIVE, 0.32 + 0.08 * sin(_clock * 2.6))
		elif main.front_options.has(p):
			c = c.lerp(LiteGlyphs.OBJECTIVE, 0.12)
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
	_track_motion(dt)
	_particles(dt)
	_update_traces()
	queue_redraw()
	_top.queue_redraw()

## Follows this frame's drones, cruise missiles and interceptors in `motion`,
## once, before anything is drawn: where each really is drawn, which way it
## really points, and how far it could have moved since the last frame. While
## the war waits (no game time passed) nothing is eased.
func _track_motion(dt: float) -> void:
	var sim_: LiteSim = main.sim
	var sim_dt: float = 0.0 if _motion_time < 0.0 else maxf(0.0, sim_.time - _motion_time)
	_motion_time = sim_.time
	motion.begin(dt if sim_dt > 0.0 else 0.0)
	# Drawn pointing the way they are seen to move (face_motion): a weapon
	# drawn in its salvo's lane drifts across its track, and must turn with
	# that drift rather than slide.
	for w: LiteWeapon in sim_.weapons:
		if w.alive and w.arm != LiteArm.BALLISTIC:
			motion.track(w, w.view_pos(), w.dir.angle(), w.speed * sim_dt * 1.5 + 1.0, true)
	var flying: Dictionary = {}
	for i: LiteInterceptor in sim_.interceptors:
		if i.alive:
			flying[i] = true
			motion.track(i, sam_pos(i), sam_tangent(i).angle(), LiteRules.INTERCEPTOR_SPEED * 1.3 * sim_dt * 2.0 + 2.0)
	for i: Variant in _plans.keys():
		if not flying.has(i):
			_plans.erase(i)
	motion.end()

## An interceptor's flight as drawn, planned once at its launch and kept: a
## curve from its launcher, up off it and over onto the point where it is
## expected to meet its target (the sim's own pursuit flown ahead against the
## target flying on as it is), timed by the flight that pursuit predicts. It
## never re-aims mid-flight; only in the last third of its flight does the
## end of its curve close onto where the target is really drawn, so the two
## meet. The sim alone decides the hit, as before.
class SamPlan:
	var a: Vector2 = Vector2.ZERO
	var top: Vector2 = Vector2.ZERO
	var b: Vector2 = Vector2.ZERO
	## The same point on the ground (under a ballistic missile's arc).
	var ground: Vector2 = Vector2.ZERO
	var time: float = 1.0
	var born: float = 0.0
	## The end of its curve as last drawn, held there once its target is gone.
	var end: Vector2 = Vector2.ZERO

var _plans: Dictionary = {}

func _plan(i: LiteInterceptor) -> SamPlan:
	var p: SamPlan = _plans.get(i)
	if p != null:
		return p
	p = SamPlan.new()
	var w: LiteWeapon = i.target
	p.a = i.from.pos if i.from != null else i.pos
	p.born = main.sim.time - i.age
	var at: Vector2 = i.pos
	var wp: Vector2 = w.pos
	var prog: float = w.progress
	var t: float = 0.0
	var h: float = 1.0 / 30.0
	while i.age + t < 4.0:
		if w.arm == LiteArm.BALLISTIC:
			prog = minf(1.0, prog + w.speed * h * LiteRules.ballistic_pace(prog) / maxf(1.0, w.length))
			wp = w.start.lerp(w.target, prog)
		else:
			wp += w.dir * w.speed * h
		var to: Vector2 = wp - at
		var d: float = to.length()
		var step: float = LiteRules.INTERCEPTOR_SPEED * LiteRules.sam_pace(i.age + t) * h
		if d <= step + 3.0:
			break
		at += to / d * step
		t += h
	p.time = maxf(0.2, t + i.age)
	p.ground = wp
	p.b = _air(w, prog) if w.arm == LiteArm.BALLISTIC else wp + w.off
	# A shallow climb and turn: its flight lasts half a second or so, and a
	# tall loop would have it spin on screen.
	p.top = lifted(p.a, clampf(p.a.distance_to(p.b) * 0.35, 14.0, 40.0))
	p.end = p.b
	_plans[i] = p
	return p

## How far along its planned flight an interceptor is, 0 to 1, by time.
func sam_f(i: LiteInterceptor) -> float:
	var p: SamPlan = _plan(i)
	return clampf((main.sim.time - p.born) / p.time, 0.0, 1.0)

## The end of its curve now: the planned meeting point, closing onto the
## target as drawn over the last third of the flight.
func _sam_end(i: LiteInterceptor, f: float) -> Vector2:
	var p: SamPlan = _plan(i)
	if i.target.alive:
		p.end = p.b.lerp(drawn_pos(i.target), smoothstep(0.66, 1.0, f))
	return p.end

## Where an interceptor is on its planned curve (before easing).
func sam_pos(i: LiteInterceptor) -> Vector2:
	var p: SamPlan = _plan(i)
	var f: float = sam_f(i)
	var u: float = 1.0 - f
	return p.a * (u * u) + p.top * (2.0 * u * f) + _sam_end(i, f) * (f * f)

## Which way the curve runs there.
func sam_tangent(i: LiteInterceptor) -> Vector2:
	var p: SamPlan = _plan(i)
	var f: float = sam_f(i)
	var d: Vector2 = (p.top - p.a) * (2.0 * (1.0 - f)) + (_sam_end(i, f) - p.top) * (2.0 * f)
	return d.normalized() if d.length() > 0.001 else -LIFT

## The point on the ground under it.
func sam_ground(i: LiteInterceptor) -> Vector2:
	var p: SamPlan = _plan(i)
	var f: float = sam_f(i)
	var u: float = 1.0 - f
	return p.a * (u * u + 2.0 * u * f) + p.ground * (f * f)

## Where a drone or cruise missile is drawn, which way it points (an angle,
## and as a unit vector): eased (see _track_motion).
func vis_pos(w: LiteWeapon) -> Vector2:
	# An enemy weapon we have lost: where we reckon it is (LiteSense).
	if w.side != 0 and w.lost[0] > 0.0 and w.arm != LiteArm.BALLISTIC:
		return motion.pos(w, w.believed(0) + w.off)
	return motion.pos(w, w.view_pos())

func vis_angle(w: LiteWeapon) -> float:
	return motion.angle(w, w.dir.angle())

func vis_dir(w: LiteWeapon) -> Vector2:
	return motion.dir(w, w.dir)

## Where an interceptor is drawn on its curve, and which way it points there.
func sam_vis(i: LiteInterceptor) -> Vector2:
	return motion.pos(i, sam_pos(i))

## It faces its curve's own tangent, exactly: no easing, which would lag
## behind a curve flown in a few frames.
func sam_vis_dir(i: LiteInterceptor) -> Vector2:
	return sam_tangent(i)

func _update_traces() -> void:
	var sim_: LiteSim = main.sim
	var now: float = sim_.time
	for i: LiteInterceptor in sim_.interceptors:
		if i.alive:
			var f: float = sam_f(i)
			# Thick smoke on the climb, thinning smoothly as it turns over.
			var k: float = 1.0 - smoothstep(SAM_CLIMB - 0.08, SAM_CLIMB + 0.3, f)
			_feed(i, sam_vis(i), k, SAM_SMOKE, 1.6, 4.0, SAM_FADE, now, 3.0)
	for i: Variant in _sam_k.keys():
		if not i.alive:
			_sam_k.erase(i)
	for w: LiteWeapon in sim_.weapons:
		if not shown_weapon(w):
			continue
		# A lost track leaves no trail: nobody sees where it really goes.
		if w.side != 0 and w.lost[0] > 0.0:
			continue
		match w.arm:
			LiteArm.BALLISTIC:
				# The enemy's leaves no line behind it: where it is headed is
				# not known until it lands (the whole country is on alert).
				if w.side != 0:
					continue
				var p: float = w.progress
				# Thick smoke while the motor burns, thinning into a pale streak.
				var k: float = 1.0 - smoothstep(BURN * 0.55, BURN * 1.5, p)
				_feed(w, _air(w, p), k, Color(weapon_color(w.side).lightened(0.55), 0.6), 1.5, 2.5, BALLISTIC_FADE, now, 5.0)
			LiteArm.CRUISE:
				_feed(w, vis_pos(w) - vis_dir(w) * 5.4, 0.0, CRUISE_WAKE, 1.0, 2.5, 2.5, now, 14.0)
			_:
				_feed(w, vis_pos(w) - vis_dir(w) * 2.4, 0.0, DRONE_WAKE, 1.0, 2.5, 1.5, now, 10.0)
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
	if LiteParticles.pixel:
		_draw_trace_pixel(t, now, n, count)
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
	if LiteParticles.pixel:
		# A trail of small squares, every few units along it.
		var acc: float = 0.0
		for k: int in range(1, count):
			acc += _rp[k].distance_to(_rp[k - 1])
			if acc < 2.2:
				continue
			acc = 0.0
			var hw: float = maxf(0.75, roundf(_rh[k] * 0.5 / 0.75) * 0.75)
			_b.rect(Rect2((_rp[k] / 1.5).floor() * 1.5 - Vector2(hw, hw), Vector2(hw, hw) * 2.0), _rc[k])
		return
	_b.ribbon(_rp, _rh, _rc)

## A trail as small squares every few units along it (the command look),
## the colour and width worked out only where a square goes: as the ribbon's
## (see draw_trace), its cut-off end spreading and fading the same way.
const TRAIL_STEP: float = 2.6

func _draw_trace_pixel(t: Trace, now: float, n: int, count: int) -> void:
	var span: float = 22.0 if t.smoky else 10.0
	var total: float = 0.0
	if not t.live:
		for k: int in range(1, n):
			total += t.pts[k].distance_to(t.pts[k - 1])
	var acc: float = 0.0
	var since: float = 0.0
	var prev: Vector2 = t.pts[0]
	for k: int in range(1, count):
		var p: Vector2 = t.pts[k] if k < n else t.head
		var d: float = p.distance_to(prev)
		prev = p
		acc += d
		since += d
		if since < TRAIL_STEP:
			continue
		since = 0.0
		var age: float = clampf((now - t.born[k]) / t.fade, 0.0, 1.0) if k < n else 0.0
		var a: float = 1.0 - age
		var w: float = t.thick[k] if k < n else t.head_thick
		var col:= Color(t.col, t.col.a * a)
		var h: float = t.half + t.spread * age
		if w > 0.001:
			col = col.lerp(Color(0.86, 0.87, 0.9, 0.5 * a * a), w)
			h = lerpf(h, 2.5 + 7.0 * age, w)
		if not t.live:
			var run: float = total - acc
			if run < span:
				var s: float = run / span
				s = s * s * (3.0 - 2.0 * s)
				col.a *= s
				h *= 1.0 + 1.3 * (1.0 - s)
		var hw: float = maxf(0.75, roundf(h * 0.5 / 0.75) * 0.75)
		_b.rect(Rect2((p / 1.5).floor() * 1.5 - Vector2(hw, hw), Vector2(hw, hw) * 2.0), col)

## Where a factory's chimney is, from its middle (see the sprites).
const CHIMNEY: Vector2 = Vector2(4.0, -10.0)

## Points along the front line (where the two sides' land meets), worked out
## again when land changes hands.
var _front_pts: PackedVector2Array = PackedVector2Array()
var _front_key: int = -1

## A point near the front, a little to either side of it; null if there is
## no front on this map.
func front_point() -> Variant:
	var map_: LiteMap = main.map
	var key: int = 0
	for r: LiteRegion in map_.regions:
		key = key * 3 + r.side + 1
		key = key % 1000003
	if key != _front_key or _front_pts.is_empty():
		_front_key = key
		_front_pts = PackedVector2Array()
		const STEP: int = 3
		for y: int in range(0, LiteMap.H - STEP, STEP):
			for x: int in range(0, LiteMap.W - STEP, STEP):
				var a: int = map_.cell[y * LiteMap.W + x]
				if a == LiteMap.NONE:
					continue
				var r: int = map_.cell[y * LiteMap.W + x + STEP]
				var d: int = map_.cell[(y + STEP) * LiteMap.W + x]
				if (r != LiteMap.NONE and map_.regions[r].side != map_.regions[a].side) or (d != LiteMap.NONE and map_.regions[d].side != map_.regions[a].side):
					_front_pts.append(Vector2(x + STEP * 0.5, y + STEP * 0.5))
	if _front_pts.is_empty():
		return null
	return _front_pts[randi() % _front_pts.size()] + Vector2.from_angle(randf() * TAU) * randf_range(2.0, 12.0)

## What crosses the front between operations, just to be seen: [from, to,
## time flown, time to fly, side, arm, shot down at (share of the way, or 2)].
var flyers: Array = []
## Towns burning near the front (fixed for the front shown).
var _front_fires: PackedVector2Array = PackedVector2Array()
var _front_fires_key: int = -1
var _flyer_puff: float = 0.0

func _front_life(dt: float) -> void:
	# Shells all along the line.
	if randf() < dt / 0.08:
		var at: Variant = front_point()
		if at != null:
			_parts.shell(at, 3.0 if randf() < 0.75 else 5.5)
	# A few towns burning near the front.
	if _front_fires_key != _front_key or _front_fires.is_empty():
		_front_fires = PackedVector2Array()
		_front_fires_key = _front_key
		for k: int in 8:
			var at: Variant = front_point()
			if at != null:
				_front_fires.append(at + Vector2(randf_range(-18, 18), randf_range(-18, 18)))
	for f: Vector2 in _front_fires:
		if randf() < dt / 0.25:
			_parts.ruin(f)
	# What is in the air is what the campaign says is going on (phase 4):
	# an enemy offensive massing against one of our regions sends its drones
	# and missiles there; a raid coming at our capital or our industry, its
	# cruise missiles; our recon drones over the region picked for the next
	# operation. Nothing flies for show.
	var c: LiteCampaign = main.campaign
	if c != null and flyers.size() < 14 and randf() < dt / 0.6:
		var aims: Array = []
		if c.counter >= 0 and main.map.regions[c.counter].side == 0:
			aims.append([1, c.counter, LiteArm.DRONE if randf() < 0.75 else LiteArm.CRUISE])
		if c.threat >= 0 and c.threat_group >= 0 and main.map.regions[c.threat_group].side == 0:
			aims.append([1, c.threat_group, LiteArm.CRUISE if randf() < 0.5 else LiteArm.DRONE])
		if main.front_pick >= 0 and main.map.regions[main.front_pick].side == 1:
			aims.append([0, main.front_pick, LiteArm.DRONE])
		# And the war along the front never stops: the enemy's drones at our
		# regions on it, ours at theirs.
		var ours: Array[int] = []
		var theirs: Array[int] = []
		for g: int in main.front_options:
			(ours if main.map.regions[g].side == 0 else theirs).append(g)
		if not theirs.is_empty():
			aims.append([0, theirs[randi() % theirs.size()], LiteArm.DRONE])
		for r: LiteRegion in main.map.regions:
			if r.side == 0 and not r.city and main.map.on_front(r.id) and ours.size() < 6:
				ours.append(r.id)
		if not ours.is_empty():
			aims.append([1, ours[randi() % ours.size()], LiteArm.DRONE])
			aims.append([1, ours[randi() % ours.size()], LiteArm.DRONE if randf() < 0.7 else LiteArm.CRUISE])
		if not aims.is_empty():
			var a: Array = aims[randi() % aims.size()]
			var side: int = a[0]
			var to_r: LiteRegion = main.map.regions[int(main.front_labels.get(a[1], a[1]))]
			var to: Vector2 = to_r.label + Vector2(randf_range(-14, 14), randf_range(-10, 10))
			var from: Variant = _front_spot(side, 150.0)
			if from != null and (from as Vector2).distance_to(to) > 40.0:
				var arm: int = a[2]
				var d: float = (from as Vector2).distance_to(to)
				# Ours (recon) come back; theirs are shot down now and then by
				# the air defence there.
				flyers.append([from, to, 0.0, d / (45.0 if arm == LiteArm.DRONE else 95.0), side, arm, randf_range(0.5, 0.9) if side == 1 and randf() < 0.45 else 2.0])
	_flyer_puff -= dt
	var puff: bool = _flyer_puff <= 0.0
	if puff:
		_flyer_puff = 0.07
	var keep: Array = []
	for f: Array in flyers:
		f[2] = float(f[2]) + dt
		var k: float = float(f[2]) / float(f[3])
		var at: Vector2 = flyer_pos(f)
		if k >= float(f[6]):
			_parts.pop(at, 3.0)
			continue
		if k >= 1.0:
			_parts.shell(f[1], 4.0)
			continue
		if puff and int(f[5]) == LiteArm.CRUISE:
			_parts.contrail(at, 0.8, 2.6, 0.8, 1.4)
		keep.append(f)
	flyers = keep

## Where a flyer is now: along its way, a little arched.
func flyer_pos(f: Array) -> Vector2:
	var k: float = clampf(float(f[2]) / float(f[3]), 0.0, 1.0)
	var a: Vector2 = f[0]
	var b: Vector2 = f[1]
	var n: Vector2 = (b - a).orthogonal().normalized()
	return a.lerp(b, k) + n * sin(k * PI) * 10.0

## A spot in `side`'s land within `reach` of the front, or null.
func _front_spot(side: int, reach: float) -> Variant:
	var at: Variant = front_point()
	if at == null:
		return null
	var map_: LiteMap = main.map
	for t: int in 12:
		var q: Vector2 = (at as Vector2) + Vector2.from_angle(randf() * TAU) * randf_range(20.0, reach)
		if map_.side_at(q) == side:
			return q
	return null

## A new blast on the map (the command look keeps its crater, see LiteCmdView).
func on_blast(_f: LiteFx) -> void:
	pass

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
				on_blast(f)
				_parts.blast(f.a, f.size)
				var heavy: bool = f.size >= 20.0
				if heavy:
					_parts.ballistic_blast(f.a, f.size, LIFT)
				# Ballistic and cruise warheads leave a fire burning, and smoke rolling off it.
				if f.size >= 14.0:
					_fires.append(Vector4(f.a.x, f.a.y, sim_.time + (16.0 if heavy else 7.0), f.size * (1.0 if heavy else 0.75)))
				if f.side == 1:
					_shake = minf(14.0 if heavy else 9.0, _shake + f.size * (0.6 if heavy else 0.3))
			LiteFxKind.NUKE:
				_parts.nuke(f.a, f.size)
				_shake = 28.0
				_nuke_at = _clock
				for k: int in 8:
					var off: Vector2 = Vector2.from_angle(k * 0.8) * randf_range(10.0, f.size * 0.7)
					_fires.append(Vector4(f.a.x + off.x, f.a.y + off.y, sim_.time + 120.0 + k * 10.0, 22.0))
			LiteFxKind.SCORCH:
				# A refinery hit (a scorch this big): oil burning for a long
				# time, heavy smoke rolling off it.
				if f.size >= 30.0:
					for k: int in 3:
						var off: Vector2 = Vector2.from_angle(k * 2.1) * 4.0
						_fires.append(Vector4(f.a.x + off.x, f.a.y + off.y, sim_.time + 90.0 + k * 15.0, 18.0))
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
				if int(f.size) == 1:
					main.mg_shot_at[f.side] = sim_.time
				else:
					main.gun_shot_at[f.side] = sim_.time
			LiteFxKind.PUFF:
				_parts.puff(f.a + f.b, f.size)
	_known = known
	if dts > 0:
		for s: LiteBuilding in sim_.buildings:
			if not s.alive and sim_.time - s.dead_at < 25.0 and shown(s) and randf() < dts / 0.3:
				_parts.ruin(s.pos)
			# Factories at work smoke; under an air alert, barely.
			elif s.alive and s.ready and s.kind == LiteKind.FACTORY and shown(s):
				var calm: bool = not sim_.alert[s.region]
				if randf() < dts / (0.35 if calm else 1.4):
					_parts.chimney(s.pos + CHIMNEY, calm)
		# Shelling along the front line, now here, now there.
		if randf() < dts / 0.22:
			var at: Variant = front_point()
			if at != null:
				_parts.shell(at, 2.4 if randf() < 0.8 else 4.5)
		# Motors leave puffs of smoke hanging in the air: a SAM's, thick while it
		# climbs; a ballistic missile's while it burns.
		for i: LiteInterceptor in sim_.interceptors:
			if not i.alive:
				continue
			var f: float = sam_f(i)
			if f < SAM_CLIMB and randf() < dts / 0.03:
				_parts.contrail(sam_vis(i), 2.0, 7.0, 2.5, 4.0)
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
	# The campaign's front between operations: no war runs there, but the
	# front line is never quiet (in real time).
	var front: bool = main.campaign != null and main.mission == null and main.front_open
	if front:
		_front_life(dt)
	elif main.started and main.sim != null and main.sim.winner < 0 and dts > 0.0 and LiteTheme.command:
		# During a war the front is never quite still either: now and then a
		# shell lands somewhere along it (no troops: just where the fighting is).
		if randf() < dts / 4.0:
			var at: Variant = front_point()
			if at != null:
				_parts.shell(at, 2.5 if randf() < 0.8 else 4.0)
	_parts.step(dt if front else dts)
	_shake *= exp(-dt * 6.0)
	if _shake > 0.15:
		position = Vector2(_shake_rng.randf_range(-1, 1), _shake_rng.randf_range(-1, 1)) * _shake
	else:
		position = Vector2.ZERO

func shown(b: LiteBuilding) -> bool:
	return b.side == 0 or b.seen[0] or main.sim.winner >= 0

func shown_weapon(w: LiteWeapon) -> bool:
	return w.alive and (w.seen[0] or main.sim.winner >= 0)

## How sure the map is of an enemy weapon: 1 while seen, fading over a lost
## track's last seconds.
func sure(w: LiteWeapon) -> float:
	if w.side == 0 or w.lost[0] <= 0.0 or main.sim.winner >= 0:
		return 1.0
	return clampf(1.0 - w.lost[0] / LiteRules.TRACK_HOLD, 0.0, 1.0) * 0.7

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
	var ang: float = vis_angle(w)
	match w.arm:
		LiteArm.DRONE:
			LiteGlyphs.draw(_b, LiteGlyph.DRONE, vis_pos(w) - LIFT * 5.0, WEAPON_SCALE * ARM_K[0], SHADOW, ang, null, false)
		LiteArm.CRUISE:
			LiteGlyphs.draw(_b, LiteGlyph.CRUISE, vis_pos(w) - LIFT * 4.0, WEAPON_SCALE * ARM_K[1], SHADOW, ang, null, false)
		_:
			# The higher it is, the softer and fainter its shadow.
			var k: float = clampf(w.altitude() / 150.0, 0.0, 1.0)
			_b.disc(w.pos, 3.0 + 7.0 * k, Color(0, 0, 0, 0.16 - 0.08 * k))
			LiteGlyphs.missile(_b, w.pos, 1.1 * ARM_K[2], Color(0, 0, 0, 0.5 - 0.3 * k), ang, null, false)

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
	var tq: float = LitePerf.now
	for t: Trace in _old_traces:
		draw_trace(t, now)
	for t: Trace in _traces.values():
		draw_trace(t, now)
	LitePerf.add("map traces", tq)
	tq = LitePerf.now
	for w: LiteWeapon in sim_.weapons:
		# Our own only: where an enemy's will come down is not known.
		if not w.alive or w.arm != LiteArm.BALLISTIC or w.side != 0:
			continue
		var col: Color = Color(1.0, 0.85, 0.8) if w.side == 1 else LiteGlyphs.OURS
		var k: float = w.progress
		b.ring(w.target, 7 + 20 * (1 - k), Color(col, 0.3 + 0.6 * k), 1.5)
		b.disc(w.target, 2.0, Color(col, 0.8))
	LitePerf.add("map ballistic", tq)
	tq = LitePerf.now
	_fill_flock()
	LitePerf.add("map flock", tq)
	tq = LitePerf.now
	for w: LiteWeapon in sim_.weapons:
		if w.arm == LiteArm.BALLISTIC and shown_weapon(w):
			draw_shadow(w)
	# One route per salvo, from its lead weapon: the rest fly the same way.
	_route_raids.clear()
	for w: LiteWeapon in sim_.weapons:
		if shown_weapon(w) and not _route_raids.has(w.raid):
			_route_raids[w.raid] = true
			draw_route(w)
	LitePerf.add("map routes", tq)
	tq = LitePerf.now
	for s: LiteBuilding in sim_.buildings:
		if shown(s) and s.kind != LiteKind.UNIT:
			draw_building(s)
	LitePerf.add("map buildings", tq)
	tq = LitePerf.now
	for w: LiteWeapon in sim_.weapons:
		if shown_weapon(w):
			draw_weapon(w)
	LitePerf.add("map weapons", tq)
	tq = LitePerf.now
	b.flush()
	LitePerf.add("map flush", tq)

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
		# Enemy forces on the move (the command look draws more, see LiteCmdView).
		elif s.alive and s.kind == LiteKind.UNIT and shown(s) and not self is LiteCmdView:
			LiteUnit.symbol(_top, s.pos, s.unit, 6.5, 1.0, s.flash)
	# On the front: a badge on each province that can be attacked, showing
	# what it is; the enemy capital's with its defences.
	if main.front_open and main.campaign != null:
		for id: int in main.front_options:
			var r: LiteRegion = main.map.regions[int(main.front_labels.get(id, id))]
			var at: Vector2 = r.label + Vector2(0, -19)
			var cap: bool = id == main.campaign.group_at(main.map.capital_province(1))
			var glyph: int
			if main.map.regions[id].side == 0:
				glyph = LiteGlyph.SAM
			elif cap:
				glyph = LiteGlyph.CAPITAL
			else:
				glyph = LiteGlyphs.of(LiteMission.target_kinds(main.campaign.character(id))[0])
			var picked: bool = id == main.front_pick
			_top.draw_circle(at, 9.5, LiteGlyphs.PAGE, true, -1, true)
			_top.draw_arc(at, 9.5, 0, TAU, 32, LiteGlyphs.OBJECTIVE if picked else Color(LiteGlyphs.OBJECTIVE, 0.6), 1.6 if picked else 1.2, true)
			LiteGlyphs.draw_ci(_top, glyph, at, 0.8, Color.WHITE)
			if cap:
				_top.draw_string(LiteGlyphs.bold, at + Vector2(13, 4), "×%d" % main.campaign.capital_defence(main.map), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LiteGlyphs.TEXT)
	# An operation's targets: a violet ring round each one still standing.
	var m: LiteMission = main.mission
	if m != null and m.result < 0:
		for t: LiteBuilding in m.targets:
			if t.alive and shown(t):
				var r: float = (15.0 if t.kind == LiteKind.CAPITAL else 12.5) + 1.2 * sin(_clock * 3.0)
				_top.draw_arc(t.pos, r, 0, TAU, 40, Color(LiteGlyphs.OBJECTIVE, 0.9), 1.6, true)
		# A convoy: a yellow ring, pulsing faster.
		if m.convoy != null and m.convoy.alive:
			_top.draw_arc(m.convoy.pos, 13.0 + 2.0 * sin(_clock * 6.0), 0, TAU, 40, Color(LiteGlyphs.YELLOW, 0.95), 1.8, true)
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
		_pts.append(vis_pos(w))
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
## How big the flying weapons are drawn (glyphs and their shadows); purely
## visual, the simulation's ranges are its own. 0.75 at first, a fifth smaller
## since 2026-11-15.
const WEAPON_SCALE: float = 0.6
## The same reduction for what is drawn round a weapon by hand (propellers,
## exhausts, a ballistic missile, interceptors), against their first sizes.
const WEAPON_K: float = WEAPON_SCALE / 0.75
## And on top of that, by weapon (drone, cruise, ballistic), what they were
## cut by on 2026-11-15 (phase 4): drones by 30%, cruise missiles by 10%,
## ballistic missiles by 20%. Only how they are drawn: the simulation's sizes
## (blast, reach, what hits them) are its own (LiteRules).
const ARM_K: Array[float] = [0.7, 0.9, 0.8]

## What is drawn of a weapon besides its glyph (drones' and cruise missiles'
## glyphs come from _fill_flock): a drone's propeller, a cruise missile's
## exhaust, a ballistic missile whole.
func draw_weapon(w: LiteWeapon) -> void:
	match w.arm:
		LiteArm.DRONE when w.jet:
			# A jet: the engine's hot core at the back and a streak of exhaust.
			var fl: float = 0.8 + 0.2 * sin(_clock * 45.0 + w.pos.y)
			var at: Vector2 = vis_pos(w)
			var d: Vector2 = vis_dir(w)
			var ck: float = WEAPON_K * ARM_K[0]
			var tail: Vector2 = at - d * 5.6 * ck
			_b.line_grad(tail - d * (7.0 + 4.0 * fl) * ck, tail, Color(1.0, 0.5, 0.2, 0.0), Color(1.0, 0.85, 0.55, 0.85), 1.6 * ck)
			_b.disc(tail, 1.5 * fl * ck, Color(1.0, 0.95, 0.8, 0.9))
		LiteArm.DRONE:
			# It wobbles a little in the wind, and its pusher propeller spins at the tail.
			var wob: float = sin(_clock * 5.0 + w.id * 1.7) * 0.08
			var d: Vector2 = vis_dir(w).rotated(wob)
			var at: Vector2 = vis_pos(w)
			var tail: Vector2 = at - d * 2.4 * WEAPON_K * ARM_K[0]
			var spin: float = absf(sin(_clock * 37.0 + w.id))
			var across: Vector2 = Vector2(-d.y, d.x) * WEAPON_K * ARM_K[0]
			_b.line(tail + across * 2.3 * spin, tail - across * 2.3 * spin, Color(0.9, 0.92, 0.96, 0.55), 0.8)
		LiteArm.CRUISE:
			# A jet engine: a hot core and a streak of exhaust behind it.
			var fl: float = 0.8 + 0.2 * sin(_clock * 40.0 + w.pos.x)
			var at: Vector2 = vis_pos(w)
			var d: Vector2 = vis_dir(w)
			var ck: float = WEAPON_K * ARM_K[1]
			var tail: Vector2 = at - d * 5.4 * ck
			_b.line_grad(tail - d * (8.0 + 4.0 * fl) * ck, tail, Color(1.0, 0.55, 0.2, 0.0), Color(1.0, 0.8, 0.5, 0.85), 1.8 * ck)
			_b.disc(tail, 1.7 * fl * ck, Color(1.0, 0.95, 0.8, 0.9))
		_:
			draw_ballistic(w, weapon_color(w.side))

## Draws a ballistic missile's body another way (a sprite: see LiteCmdView);
## false to have the glyph drawn.
func ballistic_body(_w: LiteWeapon, _at: Vector2, _s: float, _dir: Vector2) -> bool:
	return false

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
	var s: float = (1.1 + 0.4 * k) * WEAPON_K * ARM_K[2]
	# Pale, over a thin dark edge, so the arc reads over any alert colour.
	var pale: Color = col.lightened(0.55)
	# The rest of its arc, dotted: faint while it is high and out of reach,
	# brighter over its final dive, where SAMs can engage it (see
	# LiteRules.BALLISTIC_TERMINAL), with a tick where the dive begins.
	var ahead: int = maxi(2, int(16.0 * (1.0 - p))) if w.side == 0 else 0
	var prev: Vector2 = at
	for j: int in range(1, ahead + 1):
		var q: float = lerpf(p, 1.0, float(j) / ahead)
		var pt: Vector2 = _air(w, q)
		if j % 2 == 0:
			var dive: bool = q >= LiteRules.BALLISTIC_TERMINAL
			b.line(prev, pt, Color(0, 0, 0, 0.14), 2.6)
			b.line(prev, pt, Color(pale, 0.7 if dive else 0.28), 1.3 if dive else 1.0)
		prev = pt
	if p < LiteRules.BALLISTIC_TERMINAL and w.side == 0:
		var mark: Vector2 = _air(w, LiteRules.BALLISTIC_TERMINAL)
		var across: Vector2 = _air_dir(w, LiteRules.BALLISTIC_TERMINAL).orthogonal()
		b.line(mark - across * 4.0, mark + across * 4.0, Color(pale, 0.8), 1.3)
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
	if not ballistic_body(w, at, s, dir):
		LiteGlyphs.missile(b, at, s, col.lightened(0.35), dir.angle(), DARK)

## A SAM in flight: a small white missile on a burning motor; its smoke is
## its trail (see Trace). Its shadow runs along the ground below it.
func draw_interceptor(i: LiteInterceptor) -> void:
	var f: float = sam_f(i)
	_b.disc(sam_ground(i), 1.4, Color(0, 0, 0, 0.3))
	var head: Vector2 = sam_vis(i)
	var dir: Vector2 = sam_vis_dir(i)
	# The motor burns hardest on the climb.
	var hard: float = 1.4 if f < SAM_CLIMB else 1.0
	var fl: float = 0.75 + 0.25 * sin(_clock * 53.0 + i.age * 31.0)
	var nozzle: Vector2 = head - dir * 3.3 * WEAPON_K
	_b.disc(nozzle - dir * 2.0 * WEAPON_K, 3.4 * fl * hard * WEAPON_K, Color(1.0, 0.5, 0.15, 0.4))
	_b.line(nozzle, nozzle - dir * (5.0 + 4.0 * fl) * hard * WEAPON_K, Color(1.0, 0.75, 0.35, 0.85), 2.0 * hard * WEAPON_K)
	LiteGlyphs.missile(_b, head, 0.55 * WEAPON_K, Color(0.94, 0.95, 0.98), dir.angle(), DARK)
	_b.disc(nozzle, 1.3 * WEAPON_K, Color(1.0, 0.97, 0.85))

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
			if f.size >= 2.0:
				# The rotary cannon: a dense stream of rounds, a hose of
				# light from the muzzle to the target, swaying a little,
				# the muzzle flickering all the while.
				var dir: Vector2 = d.normalized()
				var side_v: Vector2 = dir.orthogonal()
				for j: int in 12:
					var u: float = t * 2.2 - j * 0.1
					if u > 0.0 and u < 1.0:
						var p: Vector2 = f.a + d * u + side_v * sin(j * 1.7 + f.a.x) * 0.8 * u
						b.line(p - dir * 3.0, p, Color(1.0, 0.8, 0.35, 0.75), 0.8)
						b.disc(p, 0.5, Color(1.0, 0.96, 0.8, 1.0))
				if t < 0.7:
					var fl: float = 1.4 + 0.8 * absf(sin(t * 90.0))
					b.disc(f.a + dir * 2.5, fl, Color(1.0, 0.88, 0.5, 0.9))
				if t > 0.45:
					b.disc(f.b, 1.2 * (1.0 - t), Color(1.0, 0.9, 0.6, 0.8))
				return
			if f.size >= 1.0:
				# A mobile unit's twin cannon: rounds in a stream, each a
				# bright dot with a short streak, flying out one after another.
				for j: int in 4:
					var u: float = t * 1.6 - j * 0.18
					if u > 0.0 and u < 1.0:
						var p: Vector2 = f.a + d * u
						b.line(p - d.normalized() * 2.2, p, Color(1.0, 0.85, 0.45, 0.8), 0.9)
						b.disc(p, 0.7, Color(1.0, 0.95, 0.75, 1.0))
				if t < 0.6 and fmod(t * 20.0, 2.0) < 1.0:
					b.disc(f.a + d.normalized() * 2.5, 1.8, Color(1.0, 0.85, 0.5, 0.9))
				return
			b.line(f.a + d * clampf(t * 1.4 - 0.4, 0.0, 1.0), f.a + d * clampf(t * 1.4, 0.0, 1.0), Color(1.0, 0.9, 0.55, 0.95), 1.3)
			if t < 0.35:
				b.disc(f.a + d.normalized() * 3.0, 2.4 * (1.0 - t / 0.35), Color(1.0, 0.85, 0.5, 0.85))
			if t > 0.75:
				b.disc(f.b, 1.6, Color(1.0, 0.9, 0.6, (t - 0.75) * 3.0))
		LiteFxKind.LAUNCH:
			b.ring(f.a, 2 + 9 * t, Color(LiteGlyphs.side_color(f.side), 0.6 * inv), 1.3)

## Where a region's factory places are drawn: a row of squares under its
## name, or above it, or further off, wherever the whole row lies inside the
## region (a row spilling into the next region would be clicked as that one).
func slot_row(r: LiteRegion, n: int) -> Vector2:
	var map_: LiteMap = main.map
	for off: Vector2 in [Vector2(0, 13), Vector2(0, -13), Vector2(0, 22), Vector2(0, -22), Vector2(0, 30)]:
		var at: Vector2 = r.label + off + Vector2(-(n - 1) * 5.0, 0)
		var inside: bool = true
		for i: int in n:
			var q: Vector2 = at + Vector2(i * 10.0, 0)
			if map_.province(map_.region_at(q)) != r.id:
				inside = false
				break
		if inside:
			return at
	return r.label + Vector2(-(n - 1) * 5.0, 13)

## The region whose factory place (a square) is under `p`, or -1.
func slot_region_at(p: Vector2) -> int:
	var sim_: LiteSim = main.sim
	for r: LiteRegion in main.map.regions:
		if r.side != 0 or r.city:
			continue
		var n: int = sim_.slots[r.id]
		if n == 0:
			continue
		var at: Vector2 = slot_row(r, n)
		for i: int in n:
			if (at + Vector2(i * 10.0, 0)).distance_to(p) < 7.0:
				return r.id
	return -1

## The band along the front where nothing of ours can be launched (see
## LiteRules.LAUNCH_STANDOFF), shaded over our land while a strike is aimed.
var _band_tex: ImageTexture = null
var _band_map: LiteMap = null
var _band_sides: int = -1

func _draw_no_launch() -> void:
	var sim_: LiteSim = main.sim
	var map_: LiteMap = main.map
	var sides_now: int = 0
	for r: LiteRegion in map_.regions:
		if r.side == 0:
			sides_now = sides_now * 31 + r.id
	if _band_tex == null or _band_map != map_ or _band_sides != sides_now:
		_band_map = map_
		_band_sides = sides_now
		var gw: int = LiteMap.W / LiteSim.FG + 1
		var gh: int = LiteMap.H / LiteSim.FG + 1
		var img:= Image.create(gw, gh, false, Image.FORMAT_RGBA8)
		var col: Color = LiteGlyphs.ENEMY
		for y: int in gh:
			for x: int in gw:
				var p:= Vector2(x * LiteSim.FG + LiteSim.FG / 2.0, y * LiteSim.FG + LiteSim.FG / 2.0)
				if map_.side_at(p) != 0:
					continue
				var d: float = sim_.front_distance(0, p)
				if d < LiteRules.LAUNCH_STANDOFF:
					# Stripes, so it reads as "no", not as another territory.
					var stripe: float = 0.10 if (x + y) % 4 < 2 else 0.05
					img.set_pixel(x, y, Color(col, stripe + 0.12 * (1.0 - d / LiteRules.LAUNCH_STANDOFF)))
		_band_tex = ImageTexture.create_from_image(img)
	_top.draw_texture_rect(_band_tex, Rect2(Vector2.ZERO, Vector2((LiteMap.W / LiteSim.FG + 1) * LiteSim.FG, (LiteMap.H / LiteSim.FG + 1) * LiteSim.FG)), false)

func draw_tool() -> void:
	# Tools belong to a war under way (not to the front between operations).
	if not main.started:
		return
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
			var at: Vector2 = slot_row(r, n)
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
	if main.build_tool != null and main.build_tool == LiteMain.REPAIR_TOOL:
		for s: LiteBuilding in main.sim.buildings:
			if s.side == 0 and LiteStock.can_repair(s):
				_top.draw_arc(s.pos, 9.0, 0, TAU, 24, Color(1.0, 0.75, 0.3, 0.8), 1.2, true)
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
		_draw_no_launch()
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
