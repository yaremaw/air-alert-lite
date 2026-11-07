"""Records one staged scene of Strike Alert for a short video, at the game's own
speed (1x the whole time the camera is rolling): a copy of the game plays the
scene by itself in Godot's Movie Maker mode while a visible cursor clicks the real
buttons, and a slow camera frames the action.

    python tools/record_short.py SCENE OUT_DIR [--rng=N]
    python tools/record_short.py SCENE OUT_DIR --probe=1,2,3    # how each seed plays out

SCENE is one of the run_* scenes in the driver below (e.g. sam). Writes
OUT_DIR/movie.avi (1920x1080, 30 fps, with the game's sound), OUT_DIR/markers.txt
(the frame each beat starts on) and OUT_DIR/frame.txt (where the camera framed the
action, for the 9:16 cut). The game itself is not changed: the driver is added to
a temporary copy.
"""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = r"D:\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64.exe"

DRIVER = r'''

var _fake_press: bool = false
var _cursor: ShortCursor = null
const _AREA: Vector2 = Vector2(490, 360)   # the middle of the map area, left of the panel

class ShortCursor extends Node2D:
	var main: LiteMain
	var clicks: Array = []
	var shown: bool = false

	func _process(delta: float) -> void:
		for c: Array in clicks:
			c[1] += delta
		clicks = clicks.filter(func(c: Array) -> bool: return c[1] < 0.45)
		queue_redraw()

	func _draw() -> void:
		if not shown or main._fake_mouse == null:
			return
		for c: Array in clicks:
			var k: float = c[1] / 0.45
			draw_arc(c[0], 5 + 20 * k, 0, TAU, 40, Color(1, 1, 1, 0.85 * (1 - k)), 2.0, true)
		var at: Vector2 = main.to_screen(main._fake_mouse)
		var shape: Array[Vector2] = [Vector2(0, 0), Vector2(0, 17), Vector2(4.3, 13.2), Vector2(7.3, 19.6),
			Vector2(9.9, 18.4), Vector2(7.0, 12.2), Vector2(12.4, 12.2)]
		var pts:= PackedVector2Array()
		for q: Vector2 in shape:
			pts.append(at + q * 1.25)
		draw_colored_polygon(pts, Color.WHITE)
		pts.append(pts[0])
		draw_polyline(pts, Color(0.06, 0.07, 0.1), 1.6, true)

func _mark(name_: String) -> void:
	print("[short] %s %d t=%.2f" % [name_, Engine.get_frames_drawn(), sim.time])

func _put(side: int, kind: int, near: Vector2, r0: float, r1: float) -> LiteBuilding:
	var p: Variant = sim.find_spot(side, near, r0, r1)
	if p == null:
		return null
	var b: LiteBuilding = sim.add(side, kind, p, true)
	b.seen[0] = true
	b.seen[1] = true
	return b

func _screen_to_map(p: Vector2) -> Vector2:
	return get_viewport().canvas_transform.affine_inverse() * p

## The camera: map point `center` in the middle of the map area, `k` screen pixels per map unit.
func _cam_set(center: Vector2, k: float) -> void:
	get_viewport().canvas_transform = Transform2D(0, Vector2(k, k), 0, _AREA - center * k)

func _cam_get() -> Array:
	var t: Transform2D = get_viewport().canvas_transform
	return [(_AREA - t.origin) / t.x.x, t.x.x]

## Moves the camera smoothly; not awaited, it runs alongside the scene.
func _cam_glide(center: Vector2, k: float, secs: float) -> void:
	var from: Array = _cam_get()
	var t: float = 0
	while t < secs:
		await get_tree().process_frame
		t += get_process_delta_time()
		var e: float = smoothstep(0.0, 1.0, minf(t / secs, 1.0))
		_cam_set((from[0] as Vector2).lerp(center, e), exp(lerpf(log(from[1] as float), log(k), e)))

## Moves the cursor to a point on the screen, easing in and out.
func _glide(to: Vector2, secs: float) -> void:
	var from: Vector2 = to_screen(_fake_mouse) if _cursor.shown else to + Vector2(220, 140)
	_cursor.shown = true
	var t: float = 0
	while t < secs:
		await get_tree().process_frame
		t += get_process_delta_time()
		var k: float = smoothstep(0.0, 1.0, minf(t / secs, 1.0))
		_fake_mouse = _screen_to_map(from.lerp(to, k))
	_fake_mouse = _screen_to_map(to)

func _click() -> void:
	_cursor.clicks.append([to_screen(_fake_mouse), 0.0])

func _press(c: Control, then: Callable) -> void:
	await _glide(c.get_global_rect().get_center(), 0.55)
	await _wait(0.12)
	_click()
	then.call()
	await _wait(0.25)

## Drags the cursor along `pts` (map points) with the button held: a strike route.
func _drag(pts: Array[Vector2], secs: float) -> void:
	await _glide(to_screen(pts[0]), 0.5)
	await _wait(0.12)
	_click()
	var route: Array[Vector2] = [pts[0]]
	drawing = route
	_fake_press = true
	var lengths: Array[float] = [0.0]
	for i: int in range(1, pts.size()):
		lengths.append(lengths[i - 1] + pts[i - 1].distance_to(pts[i]))
	var total: float = lengths[lengths.size() - 1]
	var t: float = 0
	while t < secs:
		await get_tree().process_frame
		t += get_process_delta_time()
		var d: float = total * smoothstep(0.0, 1.0, minf(t / secs, 1.0))
		var i: int = 1
		while i < pts.size() - 1 and lengths[i] < d:
			i += 1
		var seg: float = maxf(lengths[i] - lengths[i - 1], 0.001)
		_fake_mouse = pts[i - 1].lerp(pts[i], clampf((d - lengths[i - 1]) / seg, 0, 1))
	_fake_mouse = pts[pts.size() - 1]
	await get_tree().process_frame
	await get_tree().process_frame
	_click()
	_fake_press = false
	await get_tree().process_frame

func _hide_cursor() -> void:
	_cursor.shown = false
	_fake_mouse = Vector2(-99999, -99999)

func _setup() -> void:
	var layer:= CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_cursor = ShortCursor.new()
	_cursor.main = self
	layer.add_child(_cursor)
	_hide_cursor()
	LiteSettings.volume = 3
	LiteSettings.ranges = true
	LiteSettings.routes = true
	LiteSettings.apply_sound()
	await _wait(0.3)
	new_world(7)
	started = false
	LiteSettings.difficulty = 1
	new_game()
	sim.ai[0] = null
	sim.ai[1] = null
	ui.clear_feed()
	_hide_cursor()

func _front(c0: Vector2, c1: Vector2) -> Vector2:
	for i: int in 200:
		var p: Vector2 = c0.lerp(c1, i / 200.0)
		if map.side_at(p) == 1:
			return p
	return c1

var _track: Array = []

func _rng_arg() -> int:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--lite-rng=") and a.substr(11).is_valid_int():
			return a.substr(11).to_int()
	return -1

## Prints where the tracked map points are on the game's screen, every frame.
func _log_track() -> void:
	var vis: Vector2 = get_viewport().get_visible_rect().size
	print("[short] visible %d %d" % [vis.x, vis.y])
	while true:
		await get_tree().process_frame
		var parts: PackedStringArray = PackedStringArray()
		for p: Vector2 in _track:
			var q: Vector2 = to_screen(p)
			parts.append("%.1f %.1f" % [q.x, q.y])
		print("[pos] %d %s" % [Engine.get_frames_drawn(), " ".join(parts)])

## Prints every new effect (launch, kill, blast...) as it appears, for laying sound to the cut.
func _log_fx() -> void:
	var seen: Dictionary = {}
	while true:
		await get_tree().process_frame
		var now: Dictionary = {}
		for f: LiteFx in sim.fx:
			now[f] = true
			if not seen.has(f):
				print("[fx] %d %d %d %.0f %.2f" % [Engine.get_frames_drawn(), f.kind, f.side, f.size, f.life])
		seen = now

func run_short(scene: String) -> void:
	await _setup()
	_log_track()
	_log_fx()
	match scene:
		"sam": await scene_sam()
		"drones": await scene_drones()
		"bait": await scene_bait()
		"swarm": await scene_swarm()
		"assault": await scene_assault()
		"epic": await scene_epic()
		"tot": await scene_tot()
	get_tree().quit()

## Keeps every weapon of ours on time: once it is in the air, its speed is set so it lands at
## `at` (within half to one and a half times its usual speed).
func _tot_tune(at: float) -> void:
	var done: Dictionary = {}
	while true:
		await get_tree().process_frame
		for w: LiteWeapon in sim.weapons:
			if w.alive and w.side == 0 and not done.has(w):
				done[w] = true
				var left: float = at - sim.time
				if left > 0.15:
					var v: float = LiteRules.speed(w.arm)
					w.speed = clampf((w.length - w.flown) / left, v * 0.5, v * 1.5)

var _tot_hits: Array[float] = []
var _tot_down: int = 0

## Notes when each of our weapons lands or is shot down.
func _tot_watch() -> void:
	var live: Dictionary = {}
	while true:
		await get_tree().process_frame
		for w: LiteWeapon in sim.weapons:
			if w.side == 0 and w.alive:
				live[w] = true
		for w: LiteWeapon in live.keys():
			if not w.alive:
				live.erase(w)
				if w.leg >= w.path.size():
					_tot_hits.append(sim.time)
				else:
					_tot_down += 1

## Puts map point `p` in the middle of the whole screen (no panel in this scene).
func _aim_cam(p: Vector2, k: float) -> void:
	_cam_want = p - Vector2(150.0 / k, 0)
	_cam_zoom = k

## Time on target: two drone formations round the flanks, a cruise salvo line abreast down
## the middle and a ballistic salvo, each launched on its own clock so they all land together.
func scene_tot() -> void:
	ui.visible = false
	var c0: Vector2 = map.capital[0]
	var c1: Vector2 = map.capital[1]
	var east: Vector2 = (c1 - c0).normalized()
	var north: Vector2 = east.orthogonal()
	var front: Vector2 = _front(c0, c1)
	for b: LiteBuilding in sim.buildings:
		if b.kind != LiteKind.CAPITAL:
			b.alive = false
	sim.buildings = sim.buildings.filter(func(b: LiteBuilding) -> bool: return b.alive)
	var base: Vector2 = front + east * _num("depth", 120.0)
	var put: Callable = func(kind: int, e: float, n: float) -> LiteBuilding:
		return _put(1, kind, base + east * e + north * n, 0, 6)
	var sam: LiteBuilding = put.call(LiteKind.SAM, 15, 5)
	var guns: Array = [put.call(LiteKind.GUN, -30, 45), put.call(LiteKind.GUN, -25, -45)]
	var facs: Array = [put.call(LiteKind.FACTORY, 40, 55), put.call(LiteKind.FACTORY, 55, -40),
		put.call(LiteKind.FACTORY, 80, 12), put.call(LiteKind.FACTORY, 20, -80)]
	for arr: Array in [guns, facs]:
		while arr.has(null):
			arr.erase(null)
	sim.sides[0].money = 90000.0
	sim.sides[1].money = 9000.0
	var seed_: int = _rng_arg()
	if seed_ >= 0:
		sim._rng.seed = seed_
	var tot: float = _num("tot", 9.5)
	var la: Vector2 = front - east * 30 + north * 95
	var lc: Vector2 = front - east * 30 - north * 95
	var lb: Vector2 = front - east * 150
	_cam_set(front - east * 10 - Vector2(150.0 / 1.5, 0), 1.5)
	_aim_cam(front - east * 10, 1.5)
	_director()
	await _wait(0.5)
	_mark("start")
	var t0: float = sim.time
	var at: float = t0 + tot
	_tot_tune(at)
	_tot_watch()
	# Two drone formations, four abreast and two deep, round the north and south flanks.
	var north_t: Array = [guns[0], facs[0], facs[2]] if guns.size() > 0 and facs.size() > 2 else facs
	var south_t: Array = [guns[guns.size() - 1], facs[1], facs[facs.size() - 1]] if guns.size() > 0 and facs.size() > 1 else facs
	for g: int in 2:
		var l: Vector2 = la if g == 0 else lc
		var s: float = 1.0 if g == 0 else -1.0
		var wp: Vector2 = base - east * 55 + north * s * 95
		var tg: Array = north_t if g == 0 else south_t
		var dir: Vector2 = (wp - l).normalized()
		var side: Vector2 = dir.orthogonal()
		for i: int in 8:
			var off: Vector2 = side * ((i % 4) - 1.5) * 7.0 - dir * (i / 4) * 8.0
			var t: LiteBuilding = tg[i % tg.size()]
			var route: Array[Vector2] = [l + off, wp + off]
			var est: float = (l.distance_to(wp) + wp.distance_to(t.pos)) / LiteRules.speed(LiteArm.DRONE)
			sim.strike(0, LiteArm.DRONE, t.pos, 1, null, maxf(0.0, tot - est - 0.3), route)
	# A cruise salvo, six line abreast, straight down the middle at the factories and guns.
	var cr_t: Array = facs + guns
	for i: int in 6:
		var o: float = (i - 2.5) * 9.0
		var t: LiteBuilding = cr_t[i % cr_t.size()]
		var r1: Vector2 = base - east * 75 + north * o * 0.7
		var route: Array[Vector2] = [lb + north * o, r1]
		var est: float = ((lb + north * o).distance_to(r1) + r1.distance_to(t.pos)) / LiteRules.speed(LiteArm.CRUISE)
		sim.strike(0, LiteArm.CRUISE, t.pos, 1, null, maxf(0.0, tot - est - 0.3), route)
	# The ballistic salvo last: the SAM and the biggest factories.
	var bl_t: Array = [sam, sam] + facs
	for i: int in 4:
		if bl_t[i] != null:
			sim.strike(0, LiteArm.BALLISTIC, bl_t[i].pos, 1, null, tot - 1.9 + 0.05 * i)
	# The camera: both launch points, then wide over the whole plan, then in for the impact.
	await _until(func() -> bool: return sim.time >= t0 + 2.2)
	_aim_cam(front + east * 45, 1.3)
	await _until(func() -> bool: return sim.time >= at - 3.2)
	_aim_cam(base - east * 10, 1.42)
	await _until(func() -> bool: return sim.time >= at - 0.9)
	_aim_cam(base + east * 12, 1.62)
	await _until(func() -> bool: return sim.time >= at)
	_mark("impact")
	await _until(func() -> bool: return sim.time >= at + 0.9)
	_aim_cam(base + east * 15, 1.45)
	await _wait(3.0)
	_mark("end")
	_tot_hits.sort()
	var spread: float = _tot_hits[_tot_hits.size() - 1] - _tot_hits[0] if _tot_hits.size() > 1 else 0.0
	var close: int = 0
	for h: float in _tot_hits:
		if absf(h - at) < 0.6:
			close += 1
	var left: int = 0
	for b: LiteBuilding in sim.buildings:
		if b.alive and b.side == 1 and b.kind != LiteKind.CAPITAL:
			left += 1
	print("[short] tot hits %d within0.6s %d spread %.2f down %d sites_left %d" % [_tot_hits.size(), close, spread, _tot_down, left])

## A tight wave of drones from one launch point: rows of `cols` side by side, each column
## flying its own lane to its own target, so the wave holds together until it splits
## over the targets.
func _wave(from: Vector2, targets: Array, rows: int, cols: int, delay: float, spacing: float) -> void:
	var c: Vector2 = Vector2.ZERO
	for t: LiteBuilding in targets:
		c += t.pos
	c /= targets.size()
	var dir: Vector2 = (c - from).normalized()
	var side: Vector2 = dir.orthogonal()
	var mid: Vector2 = from.lerp(c, 0.6)
	for r: int in rows:
		for k: int in cols:
			var o: float = (k - (cols - 1) / 2.0) * spacing
			var t: LiteBuilding = targets[(k + r) % targets.size()]
			var route: Array[Vector2] = [from + side * o, mid + side * o]
			sim.strike(0, LiteArm.DRONE, t.pos, 1, null, delay + r * 0.32, route)

## The camera as a director: it eases toward a centre and zoom chosen for each moment,
## and shakes when something big lands.
var _cam_want: Vector2 = Vector2.ZERO
var _cam_zoom: float = 1.5
var _shake: float = 0.0

func _director() -> void:
	var seen: Dictionary = {}
	var rng:= RandomNumberGenerator.new()
	rng.seed = 7
	var cur: Array = _cam_get()
	var at: Vector2 = cur[0]
	var k: float = cur[1]
	while true:
		await get_tree().process_frame
		var dt: float = get_process_delta_time()
		var now: Dictionary = {}
		for f: LiteFx in sim.fx:
			now[f] = true
			if not seen.has(f) and f.kind == LiteFxKind.BLAST:
				_shake = minf(14.0, _shake + (f.size - 8.0) * 0.55)
		seen = now
		var e: float = 1.0 - exp(-dt * 1.6)
		at = at.lerp(_cam_want, e)
		k = exp(lerpf(log(k), log(_cam_zoom), e))
		_shake *= exp(-dt * 5.0)
		var jig: Vector2 = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * _shake / k
		_cam_set(at + jig, k)

func _ours_centroid(fallback: Vector2) -> Vector2:
	var c: Vector2 = Vector2.ZERO
	var n: int = 0
	for w: LiteWeapon in sim.weapons:
		if w.alive and w.side == 0 and w.arm == LiteArm.DRONE:
			c += w.pos
			n += 1
	return c / n if n > 0 else fallback

## The epic cut: three tight drone waves from three launch points, a cruise salvo, then a
## ballistic barrage on their SAMs, guns and factories; the camera rides along.
func scene_epic() -> void:
	ui.visible = false
	var c0: Vector2 = map.capital[0]
	var c1: Vector2 = map.capital[1]
	var east: Vector2 = (c1 - c0).normalized()
	var north: Vector2 = east.orthogonal()
	var front: Vector2 = _front(c0, c1)
	for b: LiteBuilding in sim.buildings:
		if b.kind != LiteKind.CAPITAL:
			b.alive = false
	sim.buildings = sim.buildings.filter(func(b: LiteBuilding) -> bool: return b.alive)
	var base: Vector2 = front + east * 130
	var put: Callable = func(kind: int, e: float, n: float) -> LiteBuilding:
		return _put(1, kind, base + east * e + north * n, 0, 8)
	var north_ad: Array = [put.call(LiteKind.SAM, 10, 85), put.call(LiteKind.GUN, -30, 60), put.call(LiteKind.GUN, 30, 115)]
	var mid_ad: Array = [put.call(LiteKind.SAM, 45, 0), put.call(LiteKind.GUN, -35, -5), put.call(LiteKind.GUN, 5, 30)]
	var south_ad: Array = [put.call(LiteKind.SAM, 15, -90), put.call(LiteKind.GUN, -25, -60), put.call(LiteKind.GUN, 35, -120)]
	var facs: Array = [put.call(LiteKind.FACTORY, 95, 60), put.call(LiteKind.FACTORY, 110, -10),
		put.call(LiteKind.FACTORY, 90, -80), put.call(LiteKind.FACTORY, 150, 30), put.call(LiteKind.FACTORY, 140, -55)]
	for arr: Array in [north_ad, mid_ad, south_ad, facs]:
		while arr.has(null):
			arr.erase(null)
	sim.sides[0].money = 90000.0
	sim.sides[1].money = 9000.0
	var seed_: int = _rng_arg()
	if seed_ >= 0:
		sim._rng.seed = seed_
	var la: Vector2 = front - east * 95 + north * 115
	var lb: Vector2 = front - east * 105
	var lc: Vector2 = front - east * 95 - north * 115
	_cam_set(la + east * 20, 2.2)
	_cam_want = la + east * 20
	_cam_zoom = 2.2
	_director()
	await _wait(0.5)
	_mark("start")
	_wave(la, north_ad, 5, 4, 0.0, 8.0)
	_wave(lb, mid_ad, 5, 4, 1.6, 8.0)
	_wave(lc, south_ad, 5, 4, 3.2, 8.0)
	# The camera: up close on the first launch, then riding with the waves.
	await _wait(2.6)
	var t0: float = sim.time
	while sim.time - t0 < 8.5:
		_cam_want = _ours_centroid(base).lerp(base, 0.25)
		_cam_zoom = lerpf(1.75, 1.45, clampf((sim.time - t0) / 4.0, 0, 1))
		await get_tree().process_frame
	_mark("contact")
	# Over the targets: the cruise salvo in formation from the middle, then the barrage.
	_cam_want = base + east * 35
	_cam_zoom = 1.6
	for i: int in 8:
		var t: LiteBuilding = facs[i % facs.size()]
		var o: float = (i - 3.5) * 7.0
		var route: Array[Vector2] = [lb + north * o, lb.lerp(base, 0.55) + north * o]
		sim.strike(0, LiteArm.CRUISE, t.pos, 1, null, 0.12 * i, route)
	await _wait(4.5)
	_mark("barrage")
	_cam_zoom = 1.32
	var all_t: Array = facs + [north_ad[0], mid_ad[0], south_ad[0]]
	for i: int in 9:
		sim.strike(0, LiteArm.BALLISTIC, all_t[i % all_t.size()].pos, 1, null, 0.22 * i)
	await _wait(4.0)
	_mark("reveal")
	_cam_zoom = 1.12
	_cam_want = base + east * 45
	await _until(func() -> bool:
		if not sim._queue.is_empty():
			return false
		for w: LiteWeapon in sim.weapons:
			if w.alive and w.side == 0:
				return false
		return true)
	await _wait(3.0)
	_mark("end")
	var left: int = 0
	for b: LiteBuilding in sim.buildings:
		if b.alive and b.side == 1 and b.kind != LiteKind.CAPITAL:
			left += 1
	print("[short] epic done, their sites left %d, our weapons down %d, hits %d" % [left, sim.sides[1].downed, sim.sides[0].hits])

## Our assault, with no interface on screen: dozens of drones, then cruise and ballistic
## missiles, on their SAMs, guns and factories just behind the front.
func scene_assault() -> void:
	ui.visible = false
	var c0: Vector2 = map.capital[0]
	var c1: Vector2 = map.capital[1]
	var east: Vector2 = (c1 - c0).normalized()
	var north: Vector2 = east.orthogonal()
	var front: Vector2 = _front(c0, c1)
	for b: LiteBuilding in sim.buildings:
		if b.kind != LiteKind.CAPITAL:
			b.alive = false
	sim.buildings = sim.buildings.filter(func(b: LiteBuilding) -> bool: return b.alive)
	var base: Vector2 = front + east * 125
	var sams: Array = [_put(1, LiteKind.SAM, base + north * 60, 0, 10), _put(1, LiteKind.SAM, base - north * 70 + east * 25, 0, 10)]
	var guns: Array = []
	for o: Array in [[-35, 15], [35, -15], [70, 75], [-20, -95]]:
		guns.append(_put(1, LiteKind.GUN, base + east * o[0] + north * o[1], 0, 10))
	var facs: Array = []
	for o: Array in [[95, 25], [60, -110], [130, -45], [25, 120], [150, 90]]:
		facs.append(_put(1, LiteKind.FACTORY, base + east * o[0] + north * o[1], 0, 12))
	sim.sides[0].money = 50000.0
	sim.sides[1].money = 5000.0
	var seed_: int = _rng_arg()
	if seed_ >= 0:
		sim._rng.seed = seed_
	var mid: Vector2 = base + east * 30
	_cam_set(mid, 1.2)
	_cam_glide(mid + east * 10, 1.32, 30.0)
	await _wait(0.5)
	_mark("start")
	var ad: Array = guns + sams
	for i: int in 12:
		var t: LiteBuilding = ad[i % ad.size()]
		if t != null:
			sim.strike(0, LiteArm.DRONE, t.pos, 3, null, 0.25 * i)
	for i: int in 5:
		if facs[i] != null:
			sim.strike(0, LiteArm.CRUISE, facs[i].pos, 2, null, 5.0 + 0.6 * i)
	for i: int in 3:
		var t: LiteBuilding = facs[i] if i < 2 else sams[0]
		if t != null:
			sim.strike(0, LiteArm.BALLISTIC, t.pos, 2, null, 10.0 + 1.2 * i)
	await _until(func() -> bool:
		if sim.time < 15.0 or not sim._queue.is_empty():
			return false
		for w: LiteWeapon in sim.weapons:
			if w.alive and w.side == 0:
				return false
		return true)
	await _wait(2.5)
	_mark("end")

## A swarm against a defended factory: two SAMs and two AA guns stop a ballistic missile,
## then dozens of drones come in on several lanes at the SAMs and guns, and once the air
## defence is gone, two ballistic missiles flatten the factory.
func scene_swarm() -> void:
	var c0: Vector2 = map.capital[0]
	var c1: Vector2 = map.capital[1]
	var east: Vector2 = (c1 - c0).normalized()
	var north: Vector2 = east.orthogonal()
	var front: Vector2 = _front(c0, c1)
	for b: LiteBuilding in sim.buildings:
		if b.kind != LiteKind.CAPITAL:
			b.alive = false
	sim.buildings = sim.buildings.filter(func(b: LiteBuilding) -> bool: return b.alive)
	var fac: LiteBuilding = _put(0, LiteKind.FACTORY, front - east * _num("back", 200.0), 0, 10)
	var sams: Array = [_put(0, LiteKind.SAM, fac.pos + east * 55 + north * 45, 0, 8),
		_put(0, LiteKind.SAM, fac.pos + east * 55 - north * 45, 0, 8)]
	var guns: Array = [_put(0, LiteKind.GUN, fac.pos + east * 115 + north * 40, 0, 8),
		_put(0, LiteKind.GUN, fac.pos + east * 115 - north * 40, 0, 8)]
	_track = [sams[0].pos, sams[1].pos, guns[0].pos, guns[1].pos, fac.pos]
	sim.sides[0].money = 900.0
	sim.sides[1].money += 20000
	var seed_: int = _rng_arg()
	if seed_ >= 0:
		sim._rng.seed = seed_
	ui.clear_feed()
	var state: Callable = func() -> String:
		var parts: PackedStringArray = PackedStringArray()
		for b: LiteBuilding in sams + guns:
			parts.append(str(b.ammo if b.alive else -1))
		return "%s %d %.0f" % [" ".join(parts), _enemy_drones(), fac.hp if fac.alive else -1.0]
	_log_state(state)
	var mid: Vector2 = fac.pos + east * _num("cam", 85.0)
	var k0: float = _num("zoom", 1.25)
	_cam_set(mid, k0)
	_cam_glide(mid + east * 8, k0 * 1.08, 34.0)
	await _wait(0.6)
	_mark("start")
	# The swarm leaves first, on lanes from several places, at the guns and the SAMs.
	var nd: int = int(_num("nd", 40))
	var lanes: Array = [guns[0], guns[1], sams[0], sams[1]]
	for i: int in 8:
		var t: LiteBuilding = lanes[i % 4]
		sim.strike(1, LiteArm.DRONE, t.pos, nd / 8, null, 1.0 + 0.4 * i)
	await _wait(1.2)
	_mark("ballistic")
	sim.strike(1, LiteArm.BALLISTIC, fac.pos, 1)
	await _until(func() -> bool: return _enemy_ballistic() == 0 or sim.time > 60)
	_mark("ballistic_done")
	print("[short] ballistic hits %d down %d fac %.0f" % [sim.sides[1].hits, sim.sides[0].downed, fac.hp])
	await _until(func() -> bool:
		for w: LiteWeapon in sim.weapons:
			if w.alive and w.side == 1 and w.arm == LiteArm.DRONE and w.seen[0]:
				return true
		return sim.time > 90)
	_mark("drones")
	var shot0: float = gun_shot_at[0]
	await _until(func() -> bool: return gun_shot_at[0] != shot0 or sim.time > 90)
	_mark("contact")
	await _until(func() -> bool: return not sams[0].alive or not sams[1].alive or _enemy_drones() == 0 or sim.time > 150)
	_mark("first_sam")
	await _until(func() -> bool:
		return (not sams[0].alive and not sams[1].alive) or _enemy_drones() == 0 or sim.time > 150)
	_mark("sams_gone")
	print("[short] sams gone %s drones left %d" % [not sams[0].alive and not sams[1].alive, _enemy_drones()])
	await _wait(0.8)
	_mark("finale")
	sim.strike(1, LiteArm.BALLISTIC, fac.pos, 2)
	await _until(func() -> bool: return not fac.alive or (_enemy_ballistic() == 0 and sim.time > 0) or sim.time > 200)
	_mark("factory")
	await _wait(3.2)
	_mark("end")
	var alive: int = 0
	for b: LiteBuilding in sams + guns:
		if b.alive:
			alive += 1
	print("[short] swarm done ad alive %d fac alive %s drones down %d hits %d" % [alive, fac.alive,
		sim.sides[0].downed, sim.sides[1].hits])

## Prints a scene's state every frame.
func _log_state(state: Callable) -> void:
	while true:
		await get_tree().process_frame
		print("[ammo] %d %s" % [Engine.get_frames_drawn(), state.call()])

## A number passed as --lite-NAME=VALUE, or `fallback`.
func _num(name_: String, fallback: float) -> float:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--lite-%s=" % name_) and a.split("=")[1].is_valid_float():
			return a.split("=")[1].to_float()
	return fallback

var _watch: LiteBuilding = null

## Prints the watched SAM's missiles every frame.
func _log_ammo() -> void:
	while true:
		await get_tree().process_frame
		if _watch != null:
			print("[ammo] %d %d %d" % [Engine.get_frames_drawn(), _watch.ammo if _watch.alive else -1, _enemy_drones()])

func _enemy_ballistic() -> int:
	var n: int = 0
	for w: LiteWeapon in sim.weapons:
		if w.alive and w.side == 1 and w.arm == LiteArm.BALLISTIC:
			n += 1
	for p: Variant in sim._queue:
		if p.arm == LiteArm.BALLISTIC:
			n += 1
	return n

## Drones as bait: a ballistic missile at our factory is stopped by our SAM; a stream of
## cheap drones empties the SAM's rack, and the rest get through.
func scene_bait() -> void:
	var c0: Vector2 = map.capital[0]
	var c1: Vector2 = map.capital[1]
	var east: Vector2 = (c1 - c0).normalized()
	var north: Vector2 = east.orthogonal()
	var front: Vector2 = _front(c0, c1)
	for b: LiteBuilding in sim.buildings:
		if b.kind != LiteKind.CAPITAL:
			b.alive = false
	sim.buildings = sim.buildings.filter(func(b: LiteBuilding) -> bool: return b.alive)
	var fac: LiteBuilding = _put(0, LiteKind.FACTORY, front - east * _num("back", 200.0), 0, 12)
	var sam: LiteBuilding = _put(0, LiteKind.SAM, fac.pos + east * _num("fwd", 40.0) - north * 30, 0, 10)
	_track = [sam.pos, fac.pos]
	_watch = sam
	_log_ammo()
	sim.sides[0].money = 600.0
	sim.sides[1].money += 5000
	var seed_: int = _rng_arg()
	if seed_ >= 0:
		sim._rng.seed = seed_
	ui.clear_feed()
	var mid: Vector2 = fac.pos + east * 80
	_cam_set(mid, 1.04)
	_cam_glide(mid + east * 6, 1.12, 34.0)
	await _wait(0.6)
	_mark("start")
	var nb: int = int(_num("nb", 1))
	var nd: int = int(_num("nd", 10))
	var dfirst: float = _num("dfirst", 0.0)
	var target: Vector2 = sam.pos if _num("atsam", 0) > 0 else fac.pos
	# The drones leave first (they are slow); the ballistic missile `dfirst` seconds later.
	sim.strike(1, LiteArm.DRONE, target, nd, null, 1.2)
	await _wait(1.2 + dfirst)
	_mark("ballistic")
	sim.strike(1, LiteArm.BALLISTIC, fac.pos, nb)
	await _until(func() -> bool: return _enemy_ballistic() == 0 or sim.time > 60)
	_mark("ballistic_done")
	print("[short] ballistic hits %d down %d fac %.0f ammo %d" % [sim.sides[1].hits, sim.sides[0].downed, fac.hp, sam.ammo])
	await _until(func() -> bool:
		for w: LiteWeapon in sim.weapons:
			if w.alive and w.side == 1 and w.arm == LiteArm.DRONE and w.seen[0]:
				return true
		return sim.time > 90)
	_mark("drones")
	await _until(func() -> bool: return sam.ammo == 0 or _enemy_drones() == 0 or sim.time > 120)
	_mark("empty")
	print("[short] empty ammo %d drones left %d" % [sam.ammo, _enemy_drones()])
	await _until(func() -> bool: return _enemy_drones() == 0 or sim.time > 150)
	_mark("drones_done")
	await _wait(3.0)
	_mark("end")
	print("[short] bait done hits %d down %d fac alive %s hp %.0f sam alive %s" % [sim.sides[1].hits,
		sim.sides[0].downed, fac.alive, fac.hp, sam.alive])

func _our_alerts() -> int:
	var n: int = 0
	for i: int in map.regions.size():
		if map.regions[i].side == 0 and sim.alert[i]:
			n += 1
	return n

func _enemy_drones() -> int:
	var n: int = 0
	for w: LiteWeapon in sim.weapons:
		if w.alive and w.side == 1:
			n += 1
	return n + sim._queue.size()

## The alert map: a wave of drones crosses the front, each region they fly over goes on
## alert, AA guns along the way bring them down, and the map goes quiet again.
func scene_drones() -> void:
	var c0: Vector2 = map.capital[0]
	var c1: Vector2 = map.capital[1]
	var east: Vector2 = (c1 - c0).normalized()
	var north: Vector2 = east.orthogonal()
	var front: Vector2 = _front(c0, c1)
	for b: LiteBuilding in sim.buildings:
		if b.side == 0 and b.kind != LiteKind.CAPITAL:
			b.alive = false
	sim.buildings = sim.buildings.filter(func(b: LiteBuilding) -> bool: return b.alive)
	var fac: LiteBuilding = _put(0, LiteKind.FACTORY, front - east * 175 + north * 10, 0, 16)
	_put(0, LiteKind.FACTORY, front - east * 190 + north * 70, 0, 20)
	var guns: Array = []
	for off: Array in [[70, -40], [75, 35], [125, -10], [130, 60]]:
		guns.append(_put(0, LiteKind.GUN, front - east * off[0] + north * off[1], 0, 12))
	_track = [fac.pos]
	for g: LiteBuilding in guns:
		if g != null:
			_track.append(g.pos)
	var seed_: int = _rng_arg()
	if seed_ >= 0:
		sim._rng.seed = seed_
	ui.clear_feed()
	var mid: Vector2 = front - east * 85 + north * 15
	_cam_set(mid + east * 25, 1.55)
	_cam_glide(mid - east * 20, 1.7, 30.0)
	await _wait(0.6)
	_mark("start")
	sim.sides[1].money += 2000
	sim.strike(1, LiteArm.DRONE, fac.pos, 8)
	await _until(func() -> bool: return _our_alerts() >= 1 or sim.time > 60)
	_mark("alert")
	var shot0: float = gun_shot_at[0]
	await _until(func() -> bool: return gun_shot_at[0] != shot0 or sim.time > 90)
	_mark("guns")
	await _until(func() -> bool: return _enemy_drones() == 0 or sim.time > 120)
	_mark("last")
	print("[short] drones hits %d down %d, factory hp %.0f" % [sim.sides[1].hits, sim.sides[0].downed, fac.hp])
	await _until(func() -> bool: return _our_alerts() == 0 or sim.time > 150)
	_mark("clear")
	await _wait(2.5)
	_mark("end")
	print("[short] drones done hits %d down %d" % [sim.sides[1].hits, sim.sides[0].downed])

## How to get past a SAM: three cruise missiles straight at a factory it guards are shot
## down; three more on a route drawn round its reach get through.
func scene_sam() -> void:
	var c0: Vector2 = map.capital[0]
	var c1: Vector2 = map.capital[1]
	var east: Vector2 = (c1 - c0).normalized()
	var north: Vector2 = east.orthogonal()
	var front: Vector2 = _front(c0, c1)
	for b: LiteBuilding in sim.buildings:
		if b.side == 1 and b.kind != LiteKind.CAPITAL:
			b.alive = false
	sim.buildings = sim.buildings.filter(func(b: LiteBuilding) -> bool: return b.alive)
	var sam: LiteBuilding = _put(1, LiteKind.SAM, front + east * 60, 0, 12)
	var sp: Vector2 = sam.pos
	var around: Callable = func(deg: float, r: float) -> Vector2:
		var a: float = deg_to_rad(deg)
		return sp - east * cos(a) * r + north * sin(a) * r
	var fac: LiteBuilding = _put(1, LiteKind.FACTORY, around.call(150.0, 205.0), 0, 14)
	var tgt: Vector2 = fac.pos
	_track = [sp, tgt]
	sim.sides[0].money = 1000.0
	var seed_: int = _rng_arg()
	if seed_ >= 0:
		sim._rng.seed = seed_
	ui.clear_feed()
	# Frame the SAM's reach, the factory and the way round.
	var mid: Vector2 = sp + east * 20 + north * 40
	print("[short] frame %s %s" % [sp, tgt])
	_cam_set(mid, 1.5)
	_cam_glide(mid + north * 6, 1.66, 26.0)
	await _wait(0.6)
	_mark("start")
	await _wait(1.6)
	_mark("pick")
	await _press(ui._strike[1], func() -> void: select_strike(LiteArm.CRUISE))
	await _press(ui._salvo[1], func() -> void: salvo = 3)
	# Straight at it, past the SAM.
	var start: Vector2 = front - east * 70 + north * 10
	var straight: Array[Vector2] = []
	for i: int in 6:
		straight.append(start.lerp(tgt, i / 5.0))
	_mark("straight")
	await _drag(straight, 1.1)
	_hide_cursor()
	await _until(func() -> bool:
		if not sim._queue.is_empty():
			return false
		for w: LiteWeapon in sim.weapons:
			if w.alive and w.side == 0:
				return false
		return true)
	_mark("straight_done")
	print("[short] straight hits %d down %d" % [sim.sides[0].hits, sim.sides[1].downed])
	await _wait(1.4)
	# Round its reach.
	_mark("route")
	var route: Array[Vector2] = []
	for d: float in [0.0, 25.0, 50.0, 75.0, 100.0, 122.0]:
		route.append(around.call(d, 168.0))
	route.append(tgt)
	await _drag(route, 2.0)
	strike_tool = null
	_hide_cursor()
	await _until(func() -> bool: return not fac.alive or sim.time > 200)
	_mark("hit")
	await _wait(3.2)
	_mark("end")
	print("[short] factory alive %s, hits %d down %d" % [fac.alive, sim.sides[0].hits, sim.sides[1].downed])
'''


def prepare(w=1920, h=1080, boost=False):
    """A temporary copy of the game with the driver added, recording at w x h."""
    proj = tempfile.mkdtemp()
    for name in (".godot", "assets", "maps", "scenes", "src"):
        shutil.copytree(os.path.join(ROOT, name), os.path.join(proj, name))
    with open(os.path.join(ROOT, "project.godot"), encoding="utf-8") as f:
        settings = f.read()
    size = "window/size/viewport_height=720\n"
    assert size in settings
    settings = settings.replace(size, size + "window/size/window_width_override=%d\n"
                                "window/size/window_height_override=%d\n" % (w, h), 1)
    with open(os.path.join(proj, "project.godot"), "w", encoding="utf-8") as f:
        f.write(settings)
    main_gd = os.path.join(proj, "src", "Lite", "LiteMain.gd")
    with open(main_gd, encoding="utf-8") as f:
        s = f.read()
    # No droning under the video: the siren, the drones' buzz and the cruise whine are
    # silenced, the guns and the ballistic warning kept low; launches, hits and blasts stay.
    for old, new in (('audio.loop("alert_loop.wav", 1.0 if live and _our_alert() else 0.0, -10.0,',
                      'audio.loop("alert_loop.wav", 0.0, -80.0,'),
                     ('"drone_loop.wav", (0.3 + 0.7 * minf(1.0, drones / 10.0)) if drones > 0 else 0.0, -23.0,',
                      '"drone_loop.wav", 0.0, -80.0,'),
                     ('"cruise_loop.wav", (0.4 + 0.6 * minf(1.0, cruise / 5.0)) if cruise > 0 else 0.0, -17.0,',
                      '"cruise_loop.wav", 0.0, -80.0,'),
                     ('audio.loop("gun_loop.wav", 1.0 if firing else 0.0, -18.0 if side == 0 else -27.0,',
                      'audio.loop("gun_loop.wav", 1.0 if firing else 0.0, -27.0 if side == 0 else -34.0,'),
                     ('audio.play("ballistic_warning.wav", -9.0, 4.0, 0.0)',
                      'audio.play("ballistic_warning.wav", -30.0, 4.0, 0.0)')):
        assert old in s, old
        s = s.replace(old, new, 1)
    for old, new in (("\t\trun_shots(shots, maps)", "\t\trun_short(shots)"),
                     ("elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):",
                      "elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or _fake_press:")):
        assert old in s, old
        s = s.replace(old, new, 1)
    with open(main_gd, "w", encoding="utf-8") as f:
        f.write(s + DRIVER)
    # The enemy SAM's reach drawn a little stronger, so it reads on a phone.
    view_gd = os.path.join(proj, "src", "Lite", "LiteView.gd")
    with open(view_gd, encoding="utf-8") as f:
        v = f.read()
    for old, new in (("b.disc(s.pos, r, Color(col, 0.035), false)",
                      "b.disc(s.pos, r, Color(col, 0.07 if s.side == 1 and s.kind == LiteKind.SAM else 0.035), false)"),
                     ("b.ring(s.pos, r, Color(col, 0.16 + 0.3 * s.fire_flash), 1.0)",
                      "b.ring(s.pos, r, Color(col, (0.5 if s.side == 1 and s.kind == LiteKind.SAM else 0.16) + 0.3 * s.fire_flash), "
                      "1.8 if s.side == 1 and s.kind == LiteKind.SAM else 1.0)")):
        assert old in v, old
        v = v.replace(old, new, 1)
    if boost:
        # Bigger blasts and kills, longer and brighter interceptor trails: for show only.
        for old, new in (("_parts.blast(f.a, f.size)", "_parts.blast(f.a, f.size * 1.5)"),
                         ("_parts.pop(f.a, f.size)", "_parts.pop(f.a, f.size * 1.7)"),
                         ("Color(1, 1, 1, 0.5 * (k + 1) / (n + 1)), Color(1, 1, 1, 0.5 * (k + 2) / (n + 1)), 1.2)",
                          "Color(1, 1, 1, 0.75 * (k + 1) / (n + 1)), Color(1, 1, 1, 0.75 * (k + 2) / (n + 1)), 2.0)"),
                         ("_b.disc(i.pos, 1.8, Color.WHITE)", "_b.disc(i.pos, 2.6, Color.WHITE)")):
            assert old in v, old
            v = v.replace(old, new, 1)
        sim_gd = os.path.join(proj, "src", "Lite", "LiteSim.gd")
        with open(sim_gd, encoding="utf-8") as f:
            sm = f.read()
        old = "if i.trail.size() > 8: i.trail.remove_at(0)"
        assert old in sm, old
        with open(sim_gd, "w", encoding="utf-8") as f:
            f.write(sm.replace(old, "if i.trail.size() > 16: i.trail.remove_at(0)", 1))
    with open(view_gd, "w", encoding="utf-8") as f:
        f.write(v)
    return proj


def main():
    scene, out = sys.argv[1], os.path.abspath(sys.argv[2])
    opts = dict(a[2:].split("=", 1) for a in sys.argv[3:] if a.startswith("--") and "=" in a)
    scene_args = [a for a in sys.argv[3:] if a.startswith("--lite-")]   # passed on to the scene
    w, h = (int(v) for v in opts.get("size", "1920x1080").split("x"))
    os.makedirs(out, exist_ok=True)
    proj = prepare(w, h, opts.get("boost") == "1")
    if "probe" in opts:
        # Headless and as fast as it goes (--fixed-fps plays the same as the recording), each seed at once.
        runs = {seed: subprocess.Popen([GODOT, "--headless", "--path", proj, "--fixed-fps", "30", "--",
                                        "--lite-shot=" + scene, "--lite-rng=" + seed] + scene_args,
                                       stdout=subprocess.PIPE,
                                       stderr=subprocess.DEVNULL, text=True, errors="replace")
                for seed in opts["probe"].split(",")}
        for seed, p in runs.items():
            lines = p.communicate()[0].splitlines()
            print(seed, " | ".join(line[8:] for line in lines
                                   if line.startswith("[short]") and ("hits" in line or "empty" in line)))
        shutil.rmtree(proj, ignore_errors=True)
        return
    extra = ["--lite-rng=" + opts["rng"]] if "rng" in opts else []
    run = subprocess.run([GODOT, "--path", proj, "--write-movie", os.path.join(out, "movie.avi"), "--fixed-fps", opts.get("fps", "30"),
                          "--", "--lite-shot=" + scene] + extra + scene_args, capture_output=True, text=True,
                         errors="replace")
    lines = run.stdout.splitlines()
    marks = [line for line in lines if line.startswith("[short]")]
    with open(os.path.join(out, "markers.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(marks) + "\n")
    # The game's screen is 1280x720 widened to fit the window (which the OS may not let be a
    # full 1920x1080); Movie Maker draws it 1.5x and crops the widening off both sides.
    vis = [line.split()[2:4] for line in lines if line.startswith("[short] visible")]
    vw, vh = (float(vis[0][0]), float(vis[0][1])) if vis else (1280.0, 720.0)
    k = h / 720.0
    with open(os.path.join(out, "track.txt"), "w", encoding="utf-8") as f:
        for line in lines:
            if not line.startswith("[pos]"):
                continue
            parts = line.split()
            v = [float(x) for x in parts[2:]]
            xy = []
            for i in range(0, len(v), 2):
                xy += ["%.1f" % (v[i] * k - (vw - 1280) * k / 2), "%.1f" % (v[i + 1] * k - (vh - 720) * k / 2)]
            f.write(" ".join(parts[:2] + xy) + "\n")
    with open(os.path.join(out, "ammo.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(line for line in lines if line.startswith("[ammo]")) + "\n")
    with open(os.path.join(out, "fx.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(line for line in lines if line.startswith("[fx]")) + "\n")
    print("\n".join(marks))
    errs = [line for line in (run.stdout + run.stderr).splitlines() if "ERROR" in line or "SCRIPT" in line]
    if errs:
        print("\n".join(errs[:20]))
    shutil.rmtree(proj, ignore_errors=True)


if __name__ == "__main__":
    main()
