class_name LiteGunner
extends Node2D
## The player at one of our guns: the view closes in on an armoured AA gun
## (it stands and turns its rotary cannon) or a pickup with a heavy machine
## gun (it drives about its region, WASD); the mouse aims, the left button
## held fires real rounds that fly out and must meet the drone or missile
## (a mark ahead of each one in reach shows where to lead). The gun does not
## fire by itself meanwhile (LiteBuilding.manual). Esc or the right button
## gives the gun back. SAM sites are not for the hand.
##
## Started by LiteMain.take_gun; frees itself when done.

## How much closer than the whole map the view comes.
const ZOOM: float = 3.2
## Rounds: how often one leaves the barrel, how fast it flies (map units a
## second), how wide they scatter (radians), how many make one magazine
## "burst" (the sim's ammo unit), how likely one that meets its target
## brings it down.
const GUN_EVERY: float = 0.035
const MG_EVERY: float = 0.09
const GUN_SPEED: float = 330.0
const MG_SPEED: float = 260.0
const GUN_SPREAD: float = 0.035
const MG_SPREAD: float = 0.05
const GUN_PER_MAG: int = 10
const MG_PER_MAG: int = 6
## The size of what can be hit, round its drawn place (map units).
const HIT_DRONE: float = 4.6
const HIT_CRUISE: float = 3.8

var main: LiteMain = null
var gun: LiteBuilding = null
## Rounds in the air: [where, velocity, distance left].
var _rounds: Array = []
## Sparks where rounds met something: [where, age].
var _sparks: Array = []
var _cool: float = 0.0
var _left_in_mag: int = 0
var _home: Transform2D
var _zoom_k: float = 0.0
var _speed_before: float = 1.0
var _leaving: bool = false
var _clock: float = 0.0
var _flash: float = 0.0
## What this gunner has brought down.
var kills: int = 0
## The trigger held without the mouse (the test harness).
var trigger: bool = false
var _hud: Control = null

static func can_take(b: LiteBuilding) -> bool:
	return b != null and b.alive and b.ready and b.side == 0 and (b.kind == LiteKind.GUN or b.kind == LiteKind.MOBILE) and not LiteSim.classic_rules

func start(main_: LiteMain, b: LiteBuilding) -> void:
	main = main_
	gun = b
	gun.manual = true
	z_index = 200
	_home = get_viewport().canvas_transform
	_zoom_k = _home.x.x
	_speed_before = main.speed
	main.speed = 1.0
	main.build_tool = null
	main.strike_tool = null
	_left_in_mag = _per_mag()
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	var layer:= CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.draw.connect(_draw_hud)
	layer.add_child(_hud)
	main.audio.play("click.wav", -6.0)
	main.ui.post("At the gun: %s" % _name(), LiteGlyphs.OURS)

func _name() -> String:
	return "armoured AA gun" if gun.kind == LiteKind.GUN else "gun truck"

func _per_mag() -> int:
	return GUN_PER_MAG if gun.kind == LiteKind.GUN else MG_PER_MAG

## Gives the gun back to its crew and the view back to the whole map.
func leave() -> void:
	if _leaving:
		return
	_leaving = true
	if gun != null:
		gun.manual = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if main.started and main.sim.winner < 0:
		main.speed = _speed_before
	var to: Transform2D = LiteTheme.fit_transform(main) if main._view is LiteCmdView else _home
	var tw: Tween = main.create_tween()
	tw.tween_property(main.get_viewport(), "canvas_transform", to, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(main._view.refit)
	if kills > 0:
		main.ui.post("Left the gun · %d brought down by hand" % kills, LiteGlyphs.OURS)
	main.gunner = null
	queue_free()

## Where the rounds leave: the end of the turret's barrels (the turret
## turns to the pointer, see LiteCmdView._turn_turrets).
func _muzzle() -> Vector2:
	if main._view is LiteCmdView:
		return LiteCmdView.muzzle(gun)
	return gun.pos + Vector2(1.5 if gun.kind == LiteKind.GUN else 0.5, -4.0)

## Which of the twin cannons fires next (the armoured gun's, left and right).
var _barrel: int = 0
## A little kick to the view while it fires.
var _kick: float = 0.0

## How far its rounds carry (a little past where it would fire by itself).
func _reach() -> float:
	return main.sim.ad_range(gun) * 1.25

func _process(delta: float) -> void:
	if _leaving:
		return
	if gun == null or not gun.alive or not main.started or main.sim.winner >= 0 or (main.mission != null and main.mission.result >= 0):
		if gun != null and not gun.alive:
			main.ui.post("The gun is lost", LiteGlyphs.ENEMY)
		leave()
		return
	_clock += delta
	var live: bool = not main.paused and not main.ui.menu_open
	var dt: float = delta * main.speed if live else 0.0
	_drive(dt)
	# The turret laid on the pointer.
	gun.aim_to = (_aim() - gun.pos).angle()
	gun.aim_time = main.sim.time
	_follow(delta)
	_fire(dt)
	_fly(dt)
	_flash = maxf(0.0, _flash - delta * 8.0)
	queue_redraw()
	_hud.queue_redraw()

## The camera closes in and keeps the gun in the middle of the map's frame.
func _follow(delta: float) -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var centre: Vector2 = vs / 2.0
	if main._view is LiteCmdView:
		var t: float = LiteTheme.top(main)
		centre = Vector2(10 + (vs.x - LiteTheme.LEFT - 20) / 2.0, t + 10 + (vs.y - t - LiteTheme.bottom() - 20) / 2.0)
	var want_k: float = _home.x.x * ZOOM
	var k0: float = _zoom_k
	_zoom_k = lerpf(_zoom_k, want_k, minf(1.0, delta * 5.0))
	var cur: Transform2D = get_viewport().canvas_transform
	var want_off: Vector2 = centre - gun.pos * _zoom_k
	var off: Vector2 = cur.origin.lerp(want_off, minf(1.0, delta * 6.0)) if absf(_zoom_k - want_k) < 0.01 else want_off
	# The kick of the gun, a pixel or two.
	_kick = maxf(0.0, _kick - delta * 10.0)
	off += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _kick * 1.6
	get_viewport().canvas_transform = Transform2D(0, Vector2(_zoom_k, _zoom_k), 0, off)
	if absf(_zoom_k - k0) > 0.001:
		main._view.refit()

## A gun truck drives with WASD, only inside its own region.
func _drive(dt: float) -> void:
	if dt <= 0.0:
		gun.pace = 0.0
		return
	var d:= Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)), float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	if d == Vector2.ZERO:
		gun.pace = 0.0
		return
	d = d.normalized()
	var v: float = LiteRules.MOBILE_CHASE * 1.4 * (0.72 if gun.kind == LiteKind.GUN else 1.0)
	var map: LiteMap = main.map
	var home: int = gun.home if gun.home >= 0 else gun.region
	for step: Vector2 in [d, Vector2(d.x, 0), Vector2(0, d.y)]:
		if step == Vector2.ZERO:
			continue
		var to: Vector2 = gun.pos + step.normalized() * v * dt
		var sim: LiteSim = main.sim
		if map.region_at(to) == home and (not sim.blocked(to) or sim.blocked(gun.pos)):
			gun.pos = to
			gun.heading = step.angle()
			gun.pace = v
			gun.goal = to
			return
	gun.pace = 0.0

func _aim() -> Vector2:
	return main.mouse

func _fire(dt: float) -> void:
	_cool -= dt
	if dt <= 0.0 or not (trigger or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		# The trigger let go: the next round leaves as soon as it is pressed.
		_cool = maxf(_cool, 0.0)
		return
	if gun.ammo <= 0 and _left_in_mag <= 0:
		return
	var every: float = GUN_EVERY if gun.kind == LiteKind.GUN else MG_EVERY
	while _cool <= 0.0:
		_cool += every
		if _left_in_mag <= 0:
			if gun.ammo <= 0:
				_cool = maxf(_cool, 0.0)
				return
			gun.ammo -= 1
			_left_in_mag = _per_mag()
		_left_in_mag -= 1
		var at: Vector2 = _muzzle()
		var dir0: Vector2 = Vector2.from_angle(gun.turret)
		if gun.kind == LiteKind.GUN:
			# The twin cannons, one each side of the turret, by turns.
			_barrel = 1 - _barrel
			at += dir0.orthogonal() * (2.6 if _barrel == 0 else -2.6)
		var spread: float = GUN_SPREAD if gun.kind == LiteKind.GUN else MG_SPREAD
		var ang: float = gun.turret + randf_range(-spread, spread)
		var v: float = GUN_SPEED if gun.kind == LiteKind.GUN else MG_SPEED
		_rounds.append([at, Vector2.from_angle(ang) * v, _reach()])
		_flashes.append([at, dir0, 0.0])
		_flash = 1.0
		_kick = minf(1.0, _kick + (0.25 if gun.kind == LiteKind.GUN else 0.4))
		gun.fire_flash = 1
		# A spent case thrown out sideways, now and then a puff of smoke.
		var parts: LiteParticles = main._view._parts
		parts.add(LiteParticles.SPARK, at - dir0 * 3.0, dir0.orthogonal() * randf_range(14.0, 24.0) * (1.0 if randf() < 0.5 else -1.0) - dir0 * 6.0, 0.35, 0, 0)
		if randf() < 0.3:
			parts.add(LiteParticles.SMOKE, at + dir0 * 1.5, dir0 * 6.0, randf_range(0.8, 1.4), 1.0, 3.0)
	# The sound: the rotary cannon's growl or the machine gun's hammering.
	if gun.kind == LiteKind.GUN:
		main.gun_shot_at[0] = main.sim.time
	else:
		main.mg_shot_at[0] = main.sim.time

## Rounds fly; one that passes close enough to a hostile drone or missile
## (where it is drawn) may bring it down.
func _fly(dt: float) -> void:
	if dt <= 0.0:
		return
	var sim: LiteSim = main.sim
	for i: int in range(_rounds.size() - 1, -1, -1):
		var r: Array = _rounds[i]
		var a: Vector2 = r[0]
		var v: Vector2 = r[1]
		var b: Vector2 = a + v * dt
		r[0] = b
		r[2] = float(r[2]) - v.length() * dt
		var gone: bool = float(r[2]) <= 0.0
		if not gone:
			for w: LiteWeapon in sim.weapons:
				if not w.alive or w.side == 0 or w.arm == LiteArm.BALLISTIC:
					continue
				var p: Vector2 = w.view_pos()
				var reach: float = HIT_DRONE if w.arm == LiteArm.DRONE else HIT_CRUISE
				if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) > reach:
					continue
				gone = true
				_sparks.append([p + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)), 0.0])
				# Bits flying off where it is hit.
				for k: int in 3:
					main._view._parts.add(LiteParticles.SPARK, p, Vector2.from_angle(randf() * TAU) * randf_range(20.0, 45.0), 0.3, 0, 0)
				var pk: float = (0.4 if w.arm == LiteArm.DRONE else 0.2) if gun.kind == LiteKind.GUN else (0.5 if w.arm == LiteArm.DRONE else 0.12)
				if w.jet:
					pk *= LiteRules.JET_PK
				if randf() < pk:
					sim.kill(w, 0, gun)
					kills += 1
					LiteAchievements.note("hand_kill", 1)
					if kills == 6:
						LiteAchievements.note("hand_streak", 1)
					if w.arm == LiteArm.CRUISE:
						LiteAchievements.note("hand_cruise", 1)
				break
		if gone:
			_rounds.remove_at(i)
	for s: Array in _sparks:
		s[1] = float(s[1]) + dt
	while not _sparks.is_empty() and float(_sparks[0][1]) > 0.35:
		_sparks.pop_front()
	for f: Array in _flashes:
		f[2] = float(f[2]) + dt
	while not _flashes.is_empty() and float(_flashes[0][2]) > 0.07:
		_flashes.pop_front()

## Muzzle flashes: [where, which way, age].
var _flashes: Array = []

func _unhandled_input(e: InputEvent) -> void:
	if _leaving:
		return
	var key:= e as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_ESCAPE or key.keycode == KEY_G:
			leave()
			get_viewport().set_input_as_handled()
			return
		# Space still pauses; the rest of the keys are the gun's.
		if key.keycode != KEY_SPACE and key.keycode != KEY_F11:
			get_viewport().set_input_as_handled()
		return
	var mb:= e as InputEventMouseButton
	if mb != null and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			leave()
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()

func _draw() -> void:
	if gun == null:
		return
	var muzzle: Vector2 = _muzzle()
	var aim: Vector2 = _aim()
	var reach: float = _reach()
	# Its reach, and the line it is laid on.
	draw_arc(gun.pos, reach, 0, TAU, 96, Color(LiteTheme.BLUE, 0.35), 0.6)
	var dir: Vector2 = (aim - muzzle).normalized()
	for j: int in 10:
		var u0: float = j * 0.1 + fmod(_clock * 0.4, 0.1)
		draw_line(muzzle + dir * reach * u0, muzzle + dir * reach * (u0 + 0.04), Color(1, 1, 1, 0.18), 0.5)
	# Muzzle flashes: a star of fire out of the barrel, a glow round it.
	for f: Array in _flashes:
		var fp: Vector2 = f[0]
		var fd: Vector2 = f[1]
		var k: float = 1.0 - float(f[2]) / 0.07
		var ln: float = (5.0 if gun.kind == LiteKind.GUN else 4.0) * (0.7 + 0.3 * k)
		draw_circle(fp + fd * 1.0, 2.6 * k, Color(1.0, 0.75, 0.35, 0.35 * k))
		draw_colored_polygon(PackedVector2Array([fp, fp + fd * ln + fd.orthogonal() * 0.9, fp + fd * (ln + 1.5), fp + fd * ln - fd.orthogonal() * 0.9]), Color(1.0, 0.92, 0.6, 0.95 * k))
		draw_line(fp, fp + fd.rotated(0.7) * ln * 0.45, Color(1.0, 0.8, 0.4, 0.8 * k), 0.6)
		draw_line(fp, fp + fd.rotated(-0.7) * ln * 0.45, Color(1.0, 0.8, 0.4, 0.8 * k), 0.6)
	# Where to lead each hostile drone or missile in reach: where it will be
	# when a round gets there.
	var v: float = GUN_SPEED if gun.kind == LiteKind.GUN else MG_SPEED
	for w: LiteWeapon in main.sim.weapons:
		if not w.alive or w.side == 0 or w.arm == LiteArm.BALLISTIC or not w.seen[0]:
			continue
		var p: Vector2 = w.view_pos()
		var dist: float = p.distance_to(muzzle)
		if dist > reach * 1.15:
			continue
		var lead: Vector2 = p + w.dir * w.speed * (dist / v)
		var c: Color = Color(LiteTheme.RED, 0.85)
		draw_arc(p, HIT_DRONE if w.arm == LiteArm.DRONE else HIT_CRUISE, 0, TAU, 20, Color(c, 0.5), 0.5)
		draw_line(p, lead, Color(c, 0.35), 0.4)
		var s: float = 1.6
		draw_polyline(PackedVector2Array([lead + Vector2(0, -s), lead + Vector2(s, 0), lead + Vector2(0, s), lead + Vector2(-s, 0), lead + Vector2(0, -s)]), c, 0.5)
	# The rounds: bright streaks.
	for r: Array in _rounds:
		var at: Vector2 = r[0]
		var rv: Vector2 = r[1]
		draw_line(at - rv.normalized() * 7.0, at, Color(1.0, 0.7, 0.25, 0.55), 1.4)
		draw_line(at - rv.normalized() * 4.0, at, Color(1.0, 0.92, 0.6, 0.95), 0.7)
		draw_circle(at, 0.6, Color(1.0, 0.97, 0.85, 1.0))
	for s: Array in _sparks:
		var k: float = 1.0 - float(s[1]) / 0.35
		draw_circle(s[0], 0.6 + 1.6 * (1.0 - k), Color(1.0, 0.9, 0.5, 0.8 * k))
	# The crosshair.
	var ch: Color = Color(1, 1, 1, 0.9)
	draw_arc(aim, 2.4, 0, TAU, 24, ch, 0.4)
	for o: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_line(aim + o * 3.2, aim + o * 5.0, ch, 0.4)

## What the gunner reads: the gun's name, the magazine, kills, the keys.
func _draw_hud() -> void:
	var vs: Vector2 = _hud.size
	var font: Font = LiteGlyphs.bold
	var w: float = 520.0
	var cx: float = (vs.x - (LiteTheme.LEFT if main._view is LiteCmdView else 0.0)) / 2.0
	var r:= Rect2(cx - w / 2.0, vs.y - (LiteTheme.bottom() if main._view is LiteCmdView else 0.0) - 58 - 14, w, 58)
	_hud.draw_rect(r, Color(LiteTheme.PANEL, 0.92))
	_hud.draw_rect(r, LiteTheme.BORDER, false, 1.0)
	_hud.draw_rect(Rect2(r.position, Vector2(3, r.size.y)), LiteTheme.AMBER)
	_hud.draw_string(LiteGlyphs.black, r.position + Vector2(14, 20), "MANUAL · " + _name().to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, LiteTheme.TEXT)
	_hud.draw_string(font, Vector2(r.end.x - 14 - font.get_string_size("DOWNED %d" % kills, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, r.position.y + 20), "DOWNED %d" % kills, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteTheme.GREEN)
	# The magazine: one block a burst, the one in the breech counting down.
	var mag: int = LiteRules.GUN_MAG if gun.kind == LiteKind.GUN else LiteRules.MOBILE_MAG
	var full: float = (maxf(0, gun.ammo) + float(_left_in_mag) / _per_mag()) / mag
	_hud.draw_string(font, r.position + Vector2(14, 41), "AMMO", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LiteTheme.MUTED)
	var bar:= Rect2(r.position + Vector2(52, 33), Vector2(150, 9))
	_hud.draw_rect(bar, Color(LiteTheme.BG, 0.9))
	_hud.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(full, 0.0, 1.0), bar.size.y)), LiteTheme.AMBER if full > 0.2 else LiteTheme.RED)
	var keys: String = "AIM: MOUSE · FIRE: HOLD LEFT · " + "DRIVE: WASD · " + "LEAVE: ESC"
	_hud.draw_string(font, r.position + Vector2(214, 41), keys, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 224, 9, LiteTheme.MUTED)
	if gun.ammo <= 0 and _left_in_mag <= 0:
		var s: String = "RELOADING"
		_hud.draw_string(LiteGlyphs.black, Vector2(cx - LiteGlyphs.black.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x / 2.0, r.position.y - 12), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(LiteTheme.RED, 0.6 + 0.4 * sin(_clock * 8.0)))
