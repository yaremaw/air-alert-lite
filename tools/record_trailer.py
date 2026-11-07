"""Records gameplay for the trailer: a copy of the game plays a staged war by
itself in Godot's Movie Maker mode while a visible cursor clicks the real
buttons. Writes the recording and the frames where each beat starts and ends.

    python tools/record_trailer.py OUT_DIR [GODOT_EXE]

writes OUT_DIR/movie.avi (1920x1080, 30 fps, with the game's sound) and
OUT_DIR/markers.txt, which tools/gameplay_trailer.py cuts into the trailer.
The game itself is not changed: the driver below is added to a temporary copy.
"""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = r"D:\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64.exe"

# Added to LiteMain.gd in the copy; started instead of the screenshot run.
DRIVER = r'''

var _fake_press: bool = false
var _cursor: TrailerCursor = null

class TrailerCursor extends Node2D:
	var main: LiteMain
	var clicks: Array = []
	var shown: bool = false

	func _process(delta: float) -> void:
		for c: Array in clicks:
			c[1] += delta / maxf(Engine.time_scale, 0.001)
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
	print("[trailer] %s %d t=%.1f" % [name_, Engine.get_frames_drawn(), sim.time])

func _put(side: int, kind: int, near: Vector2, r0: float, r1: float) -> LiteBuilding:
	var p: Variant = sim.find_spot(side, near, r0, r1)
	if p == null:
		return null
	var b: LiteBuilding = sim.add(side, kind, p, true)
	b.seen[0] = true
	return b

func _near(side: int, at: Vector2, r: float) -> int:
	var n: int = 0
	for w: LiteWeapon in sim.weapons:
		if w.alive and w.side == side and w.pos.distance_to(at) < r:
			n += 1
	return n

func _fast(cond: Callable, limit: float) -> void:
	var t0: float = sim.time
	speed = 3
	Engine.time_scale = 4
	await _until(func() -> bool: return cond.call() or sim.time - t0 > limit)
	Engine.time_scale = 1

func _screen_to_map(p: Vector2) -> Vector2:
	return get_viewport().canvas_transform.affine_inverse() * p

## Moves the cursor to a point on the screen, easing in and out.
func _glide(to: Vector2, secs: float) -> void:
	var from: Vector2 = to_screen(_fake_mouse) if _cursor.shown else to + Vector2(260, 160)
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
	await _glide(c.get_global_rect().get_center(), 0.5)
	await _wait(0.12)
	_click()
	then.call()
	await _wait(0.25)

func _place(at: Vector2) -> void:
	await _glide(to_screen(at), 0.45)
	await _wait(0.15)
	_click()
	try_build()
	await _wait(0.2)

## Drags the cursor along `pts` (map points) with the button held: a strike route.
func _drag(pts: Array[Vector2], secs: float) -> void:
	await _glide(to_screen(pts[0]), 0.45)
	await _wait(0.1)
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

func run_trailer() -> void:
	var layer:= CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_cursor = TrailerCursor.new()
	_cursor.main = self
	layer.add_child(_cursor)
	_hide_cursor()
	LiteSettings.volume = 3
	LiteSettings.apply_sound()
	await _wait(0.5)

	# A war in its first minutes on map 7, staged: nobody else plays.
	new_world(7)
	started = false
	LiteSettings.difficulty = 1
	new_game()
	sim.ai[0] = null
	sim.ai[1] = null
	_hide_cursor()
	var c0: Vector2 = map.capital[0]
	var c1: Vector2 = map.capital[1]
	var east: Vector2 = (c1 - c0).normalized()
	var north: Vector2 = east.orthogonal()
	_put(0, LiteKind.SAM, c0 + east * 20, 10, 40)
	_put(0, LiteKind.GUN, c0 + east * 30, 10, 50)
	for i: int in 3:
		_put(0, LiteKind.FACTORY, c0 + east * 40 + north * (i - 1) * 50, 0, 40)
	# Their side: a SAM and guns just behind the front, a factory beyond the SAM's reach.
	var front: Vector2 = c1
	for i: int in 100:
		if map.side_at(c0.lerp(c1, i / 100.0)) == 1:
			front = c0.lerp(c1, i / 100.0)
			break
	var sam: LiteBuilding = _put(1, LiteKind.SAM, front + east * 55, 0, 20)
	var sp: Vector2 = sam.pos if sam != null else front + east * 55
	_put(1, LiteKind.GUN, sp, 18, 40)
	_put(1, LiteKind.GUN, sp, 18, 40)
	var around: Callable = func(deg: float, r: float) -> Vector2:
		var a: float = deg_to_rad(deg)
		return sp - east * cos(a) * r + north * sin(a) * r
	var fac: LiteBuilding = _put(1, LiteKind.FACTORY, around.call(150.0, 215.0), 0, 30)
	var tgt: Vector2 = fac.pos if fac != null else around.call(150.0, 215.0)
	print("[trailer] front %s sam %s target %s (%.0f from the SAM)" % [front, sp, tgt, tgt.distance_to(sp)])
	# Their raid: drones on a broad front, cruise and ballistic missiles behind them.
	sim.sides[1].money += 50000
	for off: float in [-130.0, -60.0, 0.0, 60.0, 130.0]:
		var t: Variant = sim.find_spot(0, c0 + east * 70 + north * off, 0, 40)
		sim.strike(1, LiteArm.DRONE, t if t != null else c0, 6)
	sim.strike(1, LiteArm.CRUISE, c0, 4, null, 9.0)
	# A second wave for the new defences to meet.
	for off: float in [-90.0, 0.0, 90.0]:
		var t: Variant = sim.find_spot(0, c0 + east * 40 + north * off, 0, 40)
		sim.strike(1, LiteArm.DRONE, t if t != null else c0, 6, null, 13.0)
	sim.strike(1, LiteArm.CRUISE, c0, 4, null, 17.0)
	sim.strike(1, LiteArm.BALLISTIC, c0, 2, null, 20.0)
	sim.sides[0].money = 860.0

	await _fast(func() -> bool: return sim.alerted[0] >= 1, 90)
	speed = 1.5
	await _wait(0.3)
	_mark("alert")
	await _wait(4.0)
	_mark("alert_end")

	# We build air defence in the raid's path.
	speed = 1
	_mark("build")
	await _press(ui._build[2], func() -> void: select_build(LiteKind.SAM))
	for off: float in [-55.0, 45.0]:
		var p: Variant = sim.find_spot(0, c0 + east * 60 + north * off, 0, 25)
		if p != null:
			await _place(p)
	await _press(ui._build[1], func() -> void: select_build(LiteKind.GUN))
	for off: float in [-100.0, 0.0, 95.0]:
		var p: Variant = sim.find_spot(0, c0 + east * 95 + north * off, 0, 25)
		if p != null:
			await _place(p)
	build_tool = null
	await _glide(to_screen(c0 + east * 150 + north * 160), 0.5)
	_hide_cursor()
	_mark("build_end")

	# The raid meets the defence.
	await _fast(func() -> bool: return _near(1, c0, LiteRules.range(LiteKind.SAM) * 1.5) >= 6, 30)
	speed = 1.5
	_mark("defend")
	await _wait(8.0)
	_mark("defend_end")

	# We strike back: three cruise missiles, routed round their SAM to the factory.
	await _fast(func() -> bool: return _near(1, c0, 400) <= 2, 40)
	speed = 1
	sim.sides[0].money += 400
	_mark("strike")
	await _press(ui._strike[1], func() -> void: select_strike(LiteArm.CRUISE))
	await _press(ui._salvo[1], func() -> void: salvo = 3)
	# Round the far side of their SAM, out of its reach, to the factory.
	var route: Array[Vector2] = [around.call(0.0, 185.0), around.call(40.0, 185.0), around.call(80.0, 185.0),
		around.call(115.0, 190.0), tgt]
	await _drag(route, 1.8)
	strike_tool = null
	await _wait(0.4)
	_hide_cursor()
	_mark("strike_end")
	await _fast(func() -> bool:
		for w: LiteWeapon in sim.weapons:
			if w.alive and w.side == 0 and w.pos.distance_to(tgt) < 70:
				return true
		return false, 120)
	speed = 1
	_mark("impact")
	await _wait(4.5)
	_mark("impact_end")
	for b: LiteBuilding in sim.buildings:
		if b.side == 1 and b.kind == LiteKind.FACTORY and b.pos.distance_to(tgt) < 1:
			print("[trailer] target factory alive %s" % b.alive)

	# The record of the war.
	ui.show_stats(0)
	await _wait(0.4)
	_mark("stats")
	await _wait(3.0)
	_mark("stats_end")
	get_tree().quit()
'''


def main():
    out = os.path.abspath(sys.argv[1])
    godot = sys.argv[2] if len(sys.argv) > 2 else GODOT
    os.makedirs(out, exist_ok=True)
    proj = tempfile.mkdtemp()
    for name in (".godot", "assets", "maps", "scenes", "src"):
        shutil.copytree(os.path.join(ROOT, name), os.path.join(proj, name))
    with open(os.path.join(ROOT, "project.godot"), encoding="utf-8") as f:
        settings = f.read()
    # Record at 1920x1080 with the game laid out as on a 1280x720 screen, scaled up.
    size = "window/size/viewport_height=720\n"
    assert size in settings
    settings = settings.replace(size, size + "window/size/window_width_override=1920\n"
                                "window/size/window_height_override=1080\n", 1)
    with open(os.path.join(proj, "project.godot"), "w", encoding="utf-8") as f:
        f.write(settings)
    main_gd = os.path.join(proj, "src", "Lite", "LiteMain.gd")
    with open(main_gd, encoding="utf-8") as f:
        s = f.read()
    for old, new in (("\t\trun_shots(shots, maps)", "\t\trun_trailer()"),
                     ("elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):",
                      "elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or _fake_press:")):
        assert old in s, old
        s = s.replace(old, new, 1)
    with open(main_gd, "w", encoding="utf-8") as f:
        f.write(s + DRIVER)
    log = subprocess.run([godot, "--path", proj, "--write-movie", os.path.join(out, "movie.avi"), "--fixed-fps", "30",
                          "--", "--lite-shot=trailer"], capture_output=True, text=True, errors="replace").stdout
    marks = [line for line in log.splitlines() if line.startswith("[trailer]")]
    with open(os.path.join(out, "markers.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(marks) + "\n")
    print("\n".join(marks))
    shutil.rmtree(proj, ignore_errors=True)


if __name__ == "__main__":
    main()
