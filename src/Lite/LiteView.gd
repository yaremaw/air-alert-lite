class_name LiteView
extends Node2D
## Draws the lite map: the region fills (a sprite of region ids coloured by
## a palette that eases towards each region's state), then names, air
## defence cover, sites, weapons with their tracks and routes, interceptors,
## blasts, and the ghost of whatever tool the player holds.
##
## The names are a child drawn once (LiteLabels). Everything that moves goes
## into one LiteBatch of triangles a frame, sent as a single command; only
## the capitals' names and the tool ghost are ordinary draw calls.
##
## Routes: what has flown leaves a track (drones a dotted one, missiles a
## fading line). Our own weapons show the rest of their route as a dashed
## line to the target. Of the enemy's we only see the heading, a short
## dashed line as far as the alert reaches ahead; a ballistic missile's
## fall is known, so its whole arc is dashed to the target.

var main: LiteMain
var _pal: Image
var _pal_tex: ImageTexture
var _shown: PackedColorArray = PackedColorArray()
var _clock: float = 0.0
var _pts: Array[Vector2] = []
var _b: LiteBatch = LiteBatch.new()
var _parts: LiteParticles = LiteParticles.new()
## The sim's effects already given their particles.
var _known: Dictionary = {}
var _sim_time: float = -1.0
## How hard the map shakes now, in pixels; hits on us set it, it settles fast.
var _shake: float = 0.0
var _shake_rng: RandomNumberGenerator = RandomNumberGenerator.new()

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


func target(i: int) -> Color:
	var sim_: LiteSim = main.sim
	var r: LiteRegion = main.map.regions[i]
	var c: Color = LiteGlyphs.OUR_LAND if r.side == 0 else LiteGlyphs.ENEMY_LAND
	if sim_.alert[i]:
		if r.side == 0:
			c = LiteGlyphs.BALLISTIC_ALERT if sim_.ballistic[i] else LiteGlyphs.AIR_ALERT
		else:
			c = LiteGlyphs.BALLISTIC_ALERT if sim_.ballistic[i] else LiteGlyphs.ENEMY_ALERT
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
	queue_redraw()


## Gives each new sim effect its particles, keeps ruins smoking, and shakes
## the map when something lands on us. Runs on sim time.
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
				if f.side == 1:
					_shake = minf(9.0, _shake + f.size * 0.3)
			LiteFxKind.POP:
				_parts.pop(f.a, f.size)
			LiteFxKind.LAUNCH:
				if f.life > 0.6:
					_parts.launch(f.a)
			LiteFxKind.PUFF:
				_parts.puff(f.a, f.size)
	_known = known
	if dts > 0:
		for s: LiteBuilding in sim_.buildings:
			if not s.alive and sim_.time - s.dead_at < 25.0 and shown(s) and randf() < dts / 0.3:
				_parts.ruin(s.pos)
	_parts.step(dts)
	_shake *= exp(-dt * 6.0)
	if _shake > 0.15:
		position = Vector2(_shake_rng.randf_range(-1, 1), _shake_rng.randf_range(-1, 1)) * _shake
	else:
		position = Vector2.ZERO


func shown(b: LiteBuilding) -> bool:
	return b.side == 0 or b.seen[0] or main.sim.winner >= 0


## Enemy weapons appear once our side has seen them.
func shown_weapon(w: LiteWeapon) -> bool:
	return w.alive and (w.seen[0] or main.sim.winner >= 0)


func _draw() -> void:
	var t0: float = LitePerf.now
	draw_all()
	LitePerf.draw_ms += LitePerf.now - t0


func draw_all() -> void:
	var sim_: LiteSim = sim
	var b: LiteBatch = _b
	b.begin(self)
	# Air defence cover: ours, and the enemy's that has shown itself.
	if LiteSettings.ranges:
		for s: LiteBuilding in sim_.buildings:
			if not s.alive or not (s.is_ad or s.is_gun) or not s.ready or not shown(s):
				continue
			var col: Color = LiteGlyphs.side_color(s.side)
			var r: float = LiteRules.range(s.kind)
			b.disc(s.pos, r, Color(col, 0.035), false)
			b.ring(s.pos, r, Color(col, 0.16 + 0.3 * s.fire_flash), 1.0)
	for f: LiteFx in sim_.fx:
		if f.kind == LiteFxKind.SCORCH:
			# A crater: a soft dark ring of soot round a darker pit, glowing
			# for the first seconds.
			var fade: float = 1 - f.age / f.life
			b.disc(f.a, f.size * 0.75, Color(0.04, 0.04, 0.05, 0.22 * fade))
			b.disc(f.a, f.size * 0.4, Color(0.02, 0.02, 0.02, 0.45 * fade))
			if f.age < 10.0:
				var glow: float = (1 - f.age / 10.0) * (0.75 + 0.25 * sin(_clock * 11.0 + f.a.x))
				b.disc(f.a, f.size * 0.3, Color(1.0, 0.4, 0.1, 0.4 * glow))
	_parts.draw_smoke(b)
	# Ballistic targets: a ring closing in as the missile comes down.
	for w: LiteWeapon in sim_.weapons:
		if not w.alive or w.arm != LiteArm.BALLISTIC:
			continue
		var col: Color = Color(1.0, 0.85, 0.8) if w.side == 1 else LiteGlyphs.OURS
		var k: float = w.progress
		b.ring(w.target, 7 + 20 * (1 - k), Color(col, 0.3 + 0.6 * k), 1.5)
		b.disc(w.target, 2.0, Color(col, 0.8))
	for w: LiteWeapon in sim_.weapons:
		if shown_weapon(w):
			draw_route(w)
	for s: LiteBuilding in sim_.buildings:
		if shown(s):
			draw_building(s)
	for w: LiteWeapon in sim_.weapons:
		if shown_weapon(w):
			draw_weapon(w)
	for i: LiteInterceptor in sim_.interceptors:
		if i.alive:
			draw_interceptor(i)
	for f: LiteFx in sim_.fx:
		draw_fx(f)
	_parts.draw_fire(b, _clock)
	b.flush()
	for s: LiteBuilding in sim_.buildings:
		if s.alive and s.kind == LiteKind.CAPITAL:
			LiteLabels.draw_label(self, s.pos + Vector2(0, 26), main.map.capital_name[s.side], 12, LiteGlyphs.TEXT)
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
			# Still burning: flames flickering in the ruins.
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


## The track behind a weapon and, if routes are shown, the way ahead.
func draw_route(w: LiteWeapon) -> void:
	var b: LiteBatch = _b
	var col: Color = weapon_color(w.side)
	var trail: PackedVector2Array = w.trail
	var n: int = trail.size()
	if w.arm == LiteArm.DRONE:
		for i: int in n:
			b.dot(trail[i], 1.1, Color(col, 0.65 * (i + 1) / (n + 1)))
	else:
		var width: float = 2.0 if w.arm == LiteArm.BALLISTIC else 1.5
		for i: int in n:
			var to: Vector2 = trail[i + 1] if i + 1 < n else w.pos
			b.line_grad(trail[i], to, Color(col, 0.55 * (i + 1) / (n + 1)), Color(col, 0.55 * (i + 2) / (n + 1)), width)
	if not LiteSettings.routes:
		return
	if w.side == 0:
		_pts.clear()
		_pts.append(w.pos)
		var path: PackedVector2Array = w.path
		for i: int in range(w.leg, path.size()):
			_pts.append(path[i])
		b.dashed(_pts, Color(col, 0.32), 1.1, 6, 6)
		var t: Vector2 = w.target
		b.line(t + Vector2(-3, -3), t + Vector2(3, 3), Color(col, 0.6), 1.2)
		b.line(t + Vector2(3, -3), t + Vector2(-3, 3), Color(col, 0.6), 1.2)
	elif w.arm == LiteArm.BALLISTIC:
		_pts.clear()
		_pts.append(w.pos)
		_pts.append(w.target)
		b.dashed(_pts, Color(col, 0.4), 1.2, 6, 4)
	else:
		var ahead: float = w.speed * LiteRules.heading(w.arm)
		var end: Vector2 = w.pos + w.dir * ahead
		_pts.clear()
		_pts.append(w.pos + w.dir * 8)
		_pts.append(end)
		b.dashed(_pts, Color(col, 0.38), 1.1, 4, 4)
		var back: Vector2 = -w.dir * 5
		b.line(end, end + back.rotated(0.6), Color(col, 0.5), 1.2)
		b.line(end, end + back.rotated(-0.6), Color(col, 0.5), 1.2)


const DARK: Color = Color(0.05, 0.05, 0.06, 0.85)


func draw_weapon(w: LiteWeapon) -> void:
	var col: Color = weapon_color(w.side)
	var ang: float = w.dir.angle()
	match w.arm:
		LiteArm.DRONE:
			LiteGlyphs.draw(_b, LiteGlyph.DRONE, w.pos, 0.85, col, ang, DARK)
		LiteArm.CRUISE:
			# The engine's glow just behind the tail.
			var fl: float = 0.8 + 0.2 * sin(_clock * 40.0 + w.pos.x)
			_b.disc(w.pos - w.dir * 6.5, 2.6 * fl, Color(1.0, 0.65, 0.25, 0.75))
			LiteGlyphs.draw(_b, LiteGlyph.CRUISE, w.pos, 0.85, col, ang, DARK)
		_:
			# Coming down hot: a glowing head over the halo.
			_b.disc(w.pos, 9.0, Color(1.0, 0.6, 0.3, 0.12 + 0.2 * w.progress))
			_b.disc(w.pos, 6.0, Color(col, 0.22))
			LiteGlyphs.draw(_b, LiteGlyph.BALLISTIC, w.pos, 0.9, col.lightened(0.25), 0, DARK)


func draw_interceptor(i: LiteInterceptor) -> void:
	var trail: PackedVector2Array = i.trail
	var n: int = trail.size()
	for k: int in n:
		var to: Vector2 = trail[k + 1] if k + 1 < n else i.pos
		_b.line_grad(trail[k], to, Color(1, 1, 1, 0.5 * (k + 1) / (n + 1)), Color(1, 1, 1, 0.5 * (k + 2) / (n + 1)), 1.2)
	_b.disc(i.pos, 1.8, Color.WHITE)


func draw_fx(f: LiteFx) -> void:
	var b: LiteBatch = _b
	var t: float = f.age / f.life
	var inv: float = 1 - t
	match f.kind:
		LiteFxKind.BLAST:
			var grow: float = 1 - inv * inv
			b.disc(f.a, f.size * (0.35 + 0.65 * grow), Color(1.0, 0.72, 0.32, 0.85 * inv * inv))
			b.disc(f.a, maxf(0.2, f.size * 0.3 * inv), Color(1.0, 0.95, 0.8, inv))
			b.ring(f.a, f.size * (0.5 + 1.1 * grow), Color(1.0, 0.6, 0.3, 0.7 * inv), 1.5)
		LiteFxKind.POP:
			b.disc(f.a, 1.5 + f.size * t, Color(1.0, 0.95, 0.7, 0.9 * inv))
			b.ring(f.a, 2 + f.size * 1.6 * t, Color(1, 1, 1, 0.6 * inv), 1.2)
		LiteFxKind.PUFF:
			b.disc(f.a, 2 + f.size * t, Color(0.75, 0.77, 0.8, 0.45 * inv))
		LiteFxKind.TRACER:
			b.line(f.a, f.b, Color(1.0, 0.88, 0.5, 0.8 * inv), 1.0)
		LiteFxKind.LAUNCH:
			b.ring(f.a, 2 + 9 * t, Color(LiteGlyphs.side_color(f.side), 0.6 * inv), 1.3)


func draw_tool() -> void:
	var p: Vector2 = main.mouse
	var sim_: LiteSim = main.sim
	var map_: LiteMap = main.map
	if main.build_tool != null and main.build_tool == LiteKind.FACTORY:
		# Factories go into regions: under each of ours, its room as pips,
		# filled for factories, crossed for ruins, empty for free places.
		for r: LiteRegion in map_.regions:
			if r.side != 0 or r.city:
				continue
			var f: int = sim_.factories_in(r.id)
			var ru: int = sim_.ruins_in(r.id)
			var n: int = sim_.slots[r.id]
			var at: Vector2 = r.label + Vector2(-(n - 1) * 5.0, 13)
			if n == 0:
				draw_string(LiteGlyphs.font, r.label + Vector2(-30, 18), "no room", HORIZONTAL_ALIGNMENT_CENTER, 60, 9, LiteGlyphs.FAINT)
				continue
			for i: int in n:
				var c: Vector2 = at + Vector2(i * 10.0, 0)
				var box: Rect2 = Rect2(c - Vector2(3.5, 3.5), Vector2(7, 7))
				if i < f:
					draw_rect(box, LiteGlyphs.OURS)
				elif i < f + ru:
					draw_rect(box, LiteGlyphs.MUTED, false, 1.2)
					draw_line(box.position, box.end, LiteGlyphs.MUTED, 1.2, true)
				else:
					draw_rect(box, LiteGlyphs.GOOD, false, 1.4)
		return
	if main.build_tool != null:
		var k: int = main.build_tool
		var ok: bool = sim_.can_place(0, p) and sim_.sides[0].money >= sim_.cost(0, k)
		var col: Color = LiteGlyphs.OURS if ok else LiteGlyphs.ENEMY
		if k != LiteKind.FACTORY:
			var r: float = LiteRules.range(k)
			draw_circle(p, r, Color(col, 0.08))
			draw_arc(p, r, 0, TAU, 72, Color(col, 0.55), 1.2, true)
		draw_circle(p, 8, Color(LiteGlyphs.PAGE, 0.85), true, -1, true)
		draw_arc(p, 8, 0, TAU, 36, col, 1.6, true)
		LiteGlyphs.draw_ci(self, LiteGlyphs.of(k), p, 0.95, Color(1, 1, 1, 0.85))
	elif main.strike_tool != null:
		var a: int = main.strike_tool
		var at: Vector2 = main.strike_target
		var ok: bool = map_.side_at(at) == 1
		if main.drawing != null:
			# The route being drawn, dashed, to the target under the mouse.
			var route: Array[Vector2] = main.drawing
			var pts: Array[Vector2] = route.duplicate()
			pts.append(at)
			var line: Color = Color(LiteGlyphs.YELLOW, 0.85)
			var i: int = 0
			while i + 1 < pts.size():
				draw_dashed_line(pts[i], pts[i + 1], line, 1.6, 6.0, true, true)
				i += 1
			draw_circle(pts[0], 3.0, line, true, -1, true)
		var col: Color = LiteGlyphs.YELLOW if ok else LiteGlyphs.MUTED
		var r: float = LiteRules.blast(a) + LiteRules.scatter(a)
		draw_arc(at, r, 0, TAU, 48, col, 1.4, true)
		for i: int in 4:
			var d: Vector2 = Vector2(1, 0).rotated(i * PI / 2)
			draw_line(at + d * (r - 4), at + d * (r + 5), col, 1.4, true)
		if main.strike_snap != null:
			draw_arc(at, 12, 0, TAU, 32, Color.WHITE, 1.2, true)
		if ok:
			var s: String = "%d× %s · $%d" % [main.salvo, LiteGlyphs.plural(a, main.salvo), LiteRules.cost(a) * main.salvo]
			var font: Font = LiteGlyphs.bold
			draw_string_outline(font, at + Vector2(r + 8, 4), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(0, 0, 0, 0.6))
			draw_string(font, at + Vector2(r + 8, 4), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LiteGlyphs.TEXT)
