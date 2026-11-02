class_name LiteMain
extends Node2D

var map: LiteMap
var sim: LiteSim
var ui: LiteUi
var audio: LiteAudio

var build_tool: Variant = null

var strike_tool: Variant = null
var salvo: int = 1
var seed: int = 0
var speed: float = 1
var paused: bool = true
var started: bool = false
var mouse: Vector2
var strike_target: Vector2
var strike_snap: LiteBuilding
var hover_building: LiteBuilding
var hover_region: int = -1

var drawing: Variant = null

var _view: LiteView
var _end_timer: float = -1
var _last_capital_post: float = -99
var _autoplay: bool = false

var _fake_mouse: Variant = null

const ENEMY_INCOME: Array[float] = [0.8, 1.1, 1.3]
const ENEMY_WAR_SHARE: Array[float] = [0.4, 0.5, 0.55]
const ENEMY_TEMPO: Array[float] = [1.3, 1.0, 0.85]

const _MONTHS: Array[String] = ["January", "February", "March", "April", "May", "June", "July",
	"August", "September", "October", "November", "December"]

func _ready() -> void:
	LiteGlyphs.load_fonts()
	RenderingServer.set_default_clear_color(LiteGlyphs.PAGE)
	var seed_: int = int(fmod(Time.get_unix_time_from_system(), 1000003.0))
	var shots: Variant = null
	var sim_seconds: int = 0
	var sim_seeds: int = 1
	var maps: int = 0
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--lite-seed=") and a.substr(12).is_valid_int():
			seed_ = a.substr(12).to_int()
		if a.begins_with("--lite-sim=") and a.substr(11).is_valid_int():
			sim_seconds = a.substr(11).to_int()
		if a.begins_with("--lite-seeds=") and a.substr(13).is_valid_int():
			sim_seeds = a.substr(13).to_int()
		if a.begins_with("--lite-shot="):
			shots = a.substr(12).lstrip("\"").rstrip("\"")
		if a.begins_with("--lite-maps=") and a.substr(12).is_valid_int():
			maps = a.substr(12).to_int()
			LiteMap.use_baked = "--lite-baked" in OS.get_cmdline_user_args()
		if a.begins_with("--lite-bake=") and a.substr(12).is_valid_int():
			bake(a.substr(12).to_int())
			return
	if sim_seconds > 0:
		run_balance(seed_, sim_seconds, sim_seeds)
		return

	LiteSettings.load()
	LiteSettings.apply_sound()
	audio = LiteAudio.new()
	add_child(audio)
	new_world(seed_)
	ui = LiteUi.new()
	ui.main = self
	add_child(ui)
	ui.build()
	ui.show_menu()
	if shots != null:
		run_shots(shots, maps)

## Writes `n` freshly generated maps to res://maps for the game to load.
func bake(n: int) -> void:
	DirAccess.make_dir_recursive_absolute(LiteMap.BAKED_DIR)
	for k: int in n:
		var t0: int = Time.get_ticks_msec()
		var m: LiteMap = LiteMap.generate(1000 + k * 7919)
		var path: String = LiteMap.BAKED_DIR + "map_%03d.bin" % k
		print("[bake] %s: %d regions, %d ms, %s" % [path, m.regions.size(), Time.get_ticks_msec() - t0, error_string(m.save_baked(path))])
	get_tree().quit()

func new_world(seed_: int) -> void:
	seed = seed_
	var t0: int = Time.get_ticks_msec()
	map = LiteMap.for_seed(seed_)
	sim = LiteSim.new(map, seed_)
	print("[lite] map %d: %d regions in %d ms" % [seed_, map.regions.size(), Time.get_ticks_msec() - t0])
	if _view != null:
		_view.queue_free()
	_view = LiteView.new()
	_view.main = self
	add_child(_view)
	move_child(_view, 0)
	_view.build()
	fit_view()


## The map is static: scaled once so the land fills the map area (the
## screen left of the panel), centred, never panned or zoomed after.
func fit_view() -> void:
	var land: Rect2 = map.land_rect.grow(14)
	var frame:= Rect2(6, 6, LiteMap.W - 12, LiteMap.H - 12)
	var k: float = minf(minf(frame.size.x / land.size.x, frame.size.y / land.size.y), 1.6)
	var off: Vector2 = frame.get_center() - land.get_center() * k
	get_viewport().canvas_transform = Transform2D(0, Vector2(k, k), 0, off)


## A point on the map to a point on the screen (for the HUD).
func to_screen(p: Vector2) -> Vector2:
	return get_viewport().canvas_transform * p

func new_game() -> void:
	if started:
		new_world((seed * 7919 + 104729) % 1000003)
	var d: int = LiteSettings.difficulty
	started = true
	paused = false
	build_tool = null
	strike_tool = null
	_end_timer = -1
	sim.income_scale[1] = ENEMY_INCOME[d]
	var ai: LiteAi = LiteAi.new(1, seed + 1, 22.0)
	ai.war_share = ENEMY_WAR_SHARE[d]
	ai.tempo = ENEMY_TEMPO[d]
	ai.smart = d > 0
	ai.waves = d > 0
	ai.adaptive = d > 1
	sim.ai[1] = ai
	if _autoplay:
		sim.ai[0] = LiteAi.new(0, seed + 2, 30.0)
	ui.close_menu()
	ui.stats_view.visible = false
	ui.report_card.visible = false
	ui.clear_feed()
	ui.post("War. The enemy capital is %s; its factories repair it. Its other sites are hidden: drones will find them." % map.capital_name[1], LiteGlyphs.MUTED)
	audio.click()

func set_speed(s: float) -> void:
	if not started or sim.winner >= 0:
		return
	if s <= 0:
		paused = true
		return
	paused = false
	speed = s

func select_build(k: int) -> void:
	if build_tool != null and build_tool == k:
		build_tool = null
	else:
		build_tool = k
	strike_tool = null
	audio.click()

func select_strike(a: int) -> void:
	if strike_tool != null and strike_tool == a:
		strike_tool = null
	else:
		strike_tool = a
	build_tool = null
	audio.click()

func clock_text(t: float, date: bool) -> String:

	var start: int = Time.get_unix_time_from_datetime_string("2026-10-26T21:00:00")
	var at: Dictionary = Time.get_datetime_dict_from_unix_time(start + int(floor(t * 60.0)))
	var hm: String = "%02d:%02d" % [int(at["hour"]), int(at["minute"])]
	if not date:
		return hm
	return "%d %s %s" % [int(at["day"]), _MONTHS[int(at["month"]) - 1], hm]

func _process(delta: float) -> void:
	if _fake_mouse != null:
		mouse = _fake_mouse
	else:
		mouse = get_global_mouse_position()
	update_hover()
	if drawing != null:
		if strike_tool == null or ui.menu_open:
			drawing = null
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var route: Array[Vector2] = drawing
			if route[route.size() - 1].distance_to(mouse) >= 16:
				route.append(mouse)
		else:
			finish_route()
	if started and not paused and not ui.menu_open:
		var t0: float = LitePerf.now
		var dt: float = delta * speed
		while dt > 0.0001:
			var h: float = minf(dt, 1 / 30.0)
			sim.step(h)
			dt -= h
		LitePerf.sim_ms += LitePerf.now - t0
	handle_events()
	engine_sounds(delta)
	if _end_timer > 0:
		_end_timer -= delta
		if _end_timer <= 0:
			show_end()

## The buzz of enemy drones and the whine of cruise missiles over our land,
## louder the more of them there are; silent while the war waits.
func engine_sounds(delta: float) -> void:
	if audio == null:
		return
	var drones: int = 0
	var cruise: int = 0
	if started and not paused and not ui.menu_open and sim.winner < 0:
		for w: LiteWeapon in sim.weapons:
			if not w.alive or w.side != 1 or not w.seen[0] or w.arm == LiteArm.BALLISTIC:
				continue
			if map.side_at(w.pos) != 0:
				continue
			if w.arm == LiteArm.DRONE:
				drones += 1
			else:
				cruise += 1
	audio.loop("drone_loop.wav", (0.3 + 0.7 * minf(1.0, drones / 10.0)) if drones > 0 else 0.0, -11.0, delta)
	audio.loop("cruise_loop.wav", (0.4 + 0.6 * minf(1.0, cruise / 5.0)) if cruise > 0 else 0.0, -13.0, delta)

func update_hover() -> void:
	hover_building = null
	hover_region = -1
	strike_snap = null
	strike_target = mouse
	if not started or ui.menu_open or (_fake_mouse == null and get_viewport().gui_get_hovered_control() != null):
		return
	var best: float = 11
	for b: LiteBuilding in sim.buildings:
		if not b.alive or not (b.side == 0 or b.seen[0]):
			continue
		var d: float = b.pos.distance_to(mouse)
		if d < best:
			best = d
			hover_building = b
	var id: int = map.region_at(mouse)
	hover_region = -1 if id == LiteMap.NONE else id
	if strike_tool != null and hover_building != null and hover_building.side == 1:
		strike_snap = hover_building
		strike_target = hover_building.pos

func _unhandled_input(e: InputEvent) -> void:

	var key: InputEventKey = e as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		if ui.menu_open:
			ui.back()
		elif build_tool != null or strike_tool != null:
			build_tool = null
			strike_tool = null
		elif started and sim.winner < 0:
			ui.show_menu()
		get_viewport().set_input_as_handled()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F11:
		LiteSettings.fullscreen = not LiteSettings.fullscreen
		LiteSettings.apply_window()
		get_viewport().set_input_as_handled()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_T and ui.stats_view.visible:
		ui.stats_view.visible = false
		audio.click()
		get_viewport().set_input_as_handled()
		return
	if not started or sim.winner >= 0 or ui.menu_open:
		return
	var mb: InputEventMouseButton = e as InputEventMouseButton
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_SPACE:
				if paused:
					set_speed(speed)
				else:
					paused = true
			KEY_1: select_build(LiteKind.FACTORY)
			KEY_2: select_build(LiteKind.GUN)
			KEY_3: select_build(LiteKind.SAM)
			KEY_Q: select_strike(LiteArm.DRONE)
			KEY_W: select_strike(LiteArm.CRUISE)
			KEY_E: select_strike(LiteArm.BALLISTIC)
			KEY_T: ui.show_stats()
			_: return
		get_viewport().set_input_as_handled()
	elif mb != null and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			build_tool = null
			strike_tool = null
			drawing = null
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if build_tool != null:
				try_build()

			elif strike_tool != null:
				var route: Array[Vector2] = [get_global_mouse_position()]
				drawing = route
			else:
				return
		else:
			return
		get_viewport().set_input_as_handled()

## The tool stays in hand after building, so several sites go down one
## click each; right-click, Esc or its button again puts it down.
func try_build() -> void:
	var k: int = build_tool
	if sim.sides[0].money < sim.cost(0, k):
		refuse("Not enough money: %s costs $%d" % [LiteGlyphs.name(k), sim.cost(0, k)])
		return
	if k == LiteKind.FACTORY:
		var r: int = map.regions[hover_region].parent if hover_region >= 0 and map.regions[hover_region].city else hover_region
		if r < 0 or map.regions[r].side != 0:
			refuse("Pick one of your regions")
			return
		if sim.free_slots(r) <= 0:
			refuse("No room for a factory in %s" % map.regions[r].name)
			return
		if sim.build_factory(0, r) == null:
			refuse("No free ground in %s" % map.regions[r].name)
			return
		audio.play("click.wav", -3.0)
		return
	if not sim.can_place(0, mouse):
		refuse("Build on your own territory, a little away from other sites")
		return
	sim.build(0, k, mouse)
	audio.play("click.wav", -3.0)

func finish_route() -> void:
	var pts: Array[Vector2] = drawing
	drawing = null
	var length: float = 0
	for i: int in range(1, pts.size()):
		length += pts[i - 1].distance_to(pts[i])
	if length < 20:
		try_strike(null)
		return
	for i: int in range(pts.size() - 1, -1, -1):
		if pts[i].distance_to(strike_target) < 14:
			pts.remove_at(i)
	if pts.size() > 0:
		try_strike(pts)
	else:
		try_strike(null)

func try_strike(route: Variant) -> void:
	var a: int = strike_tool
	if map.side_at(strike_target) != 1:
		refuse("Pick a target on enemy territory")
		return
	var n: int = salvo
	if sim.sides[0].money < LiteRules.cost(a):
		refuse("Not enough money: a %s costs $%d" % [LiteGlyphs.name_arm(a).to_lower(), LiteRules.cost(a)])
		return
	while n > 1 and sim.sides[0].money < LiteRules.cost(a) * n:
		n -= 1
	if route != null:
		var pts: Array[Vector2] = route
		sim.strike(0, a, strike_target, n, null, 0.0, pts)
	else:
		sim.strike(0, a, strike_target, n)
	audio.play("click.wav", -3.0)

func refuse(why: String) -> void:
	ui.hud.message(why)
	audio.play("click_off.wav", -4.0)

func region_name(id: int) -> String:
	return map.regions[id].name if id >= 0 and id < map.regions.size() else "the sea"

func _our_alert() -> bool:
	for i: int in map.regions.size():
		if map.regions[i].side == 0 and sim.alert[i]:
			return true
	return false

static func composition(r: LiteRaid) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i: int in 3:
		if r.by_arm[i] > 0:
			parts.append("%d %s" % [r.by_arm[i], LiteGlyphs.plural(i, r.by_arm[i])])
	return ", ".join(parts)

func handle_events() -> void:
	if sim == null:
		return
	for e: LiteEvent in sim.events:
		match e.type:
			LiteEv.RAID_ALERT:
				if e.side != 0:
					continue
				ui.post("Air alert in %s. Take cover." % region_name(e.region), LiteGlyphs.YELLOW)
				audio.siren("alert.wav", -8.0)
			LiteEv.ALL_CLEAR:
				if e.side == 0:
					ui.post("All clear. The alert lasted %s." % LiteHud.duration(e.value), LiteGlyphs.GOOD)
					if not _our_alert():
						audio.siren("all_clear.wav", -10.0)
			LiteEv.LAUNCH:
				if e.side == 0:
					audio.play("launch.wav", -15.0, 0.15)
					continue
				if e.arm == LiteArm.BALLISTIC:
					ui.post("Ballistic launch! Heading for %s." % region_name(e.region), LiteGlyphs.BALLISTIC_ALERT)
					audio.play("ballistic_warning.wav", -6.0, 4.0, 0.0)
			LiteEv.DETECTED:
				if e.side != 1 or e.raid == null or e.raid.reported:
					continue
				e.raid.reported = true
				ui.post("Enemy %s spotted over %s." % [LiteGlyphs.plural(e.arm, 2), region_name(e.region)], LiteGlyphs.YELLOW)
			LiteEv.SHOT_DOWN:
				audio.play("intercept.wav", -11.0 if e.side == 0 else -18.0, 0.08)
			LiteEv.HIT:
				var on_us: bool = e.side == 1
				audio.play("explosion_small_a.wav" if e.arm == LiteArm.DRONE else "explosion_a.wav", -7.0 if on_us else -15.0, 0.06)
			LiteEv.CAPITAL_HIT:
				if sim.time - _last_capital_post < 4:
					continue
				_last_capital_post = sim.time
				if e.side == 0:
					ui.post("%s is hit! %d/%d left." % [map.capital_name[0], roundi(e.value), roundi(LiteRules.max_hp(LiteKind.CAPITAL))], LiteGlyphs.ENEMY)
				else:
					ui.post("Hit on %s: %d/%d left." % [map.capital_name[1], roundi(e.value), roundi(LiteRules.max_hp(LiteKind.CAPITAL))], LiteGlyphs.OURS)
			LiteEv.DESTROYED:
				if e.kind == LiteKind.CAPITAL:
					continue
				if e.side == 0:
					ui.post("Our %s destroyed in %s." % [LiteGlyphs.name(e.kind), region_name(e.region)], LiteGlyphs.ENEMY)
				else:
					ui.post("Enemy %s destroyed in %s." % [LiteGlyphs.name(e.kind), region_name(e.region)], LiteGlyphs.GOOD)
				audio.play("wreck.wav", -9.0, 0.2)
			LiteEv.BUILT:
				if e.side == 0:
					audio.play("click_off.wav", -12.0)
			LiteEv.INDUSTRY:
				if e.side != 0:
					continue
				ui.post(("Industry moves to %s: room for one more factory there." % region_name(e.region)) if e.value > 0
					else ("%s loses room for a factory: workers called up." % region_name(e.region)), LiteGlyphs.MUTED)
			LiteEv.WARNING:
				if e.side != 1:
					continue
				ui.post("Intelligence: the enemy is massing drones and missiles for a large strike. Ready the air defence.", LiteGlyphs.BALLISTIC_ALERT)
				audio.siren("alert.wav", -6.0)
			LiteEv.REPORT:
				var rep: LiteReport = sim.stats.reports[int(e.value)]
				ui.report_card.show_report(rep)
				ui.post("Attack report: %d drones and missiles, %d shot down. Press T for all reports." % [rep.total, rep.total_downed], LiteGlyphs.OURS)
			LiteEv.SPOTTED:
				if e.side == 1 and e.kind == LiteKind.FACTORY:
					ui.post("The enemy has located our factory in %s." % region_name(e.region), LiteGlyphs.ENEMY)
				if e.side == 0:
					ui.post("Spotted: enemy %s in %s." % [LiteGlyphs.name(e.kind), region_name(e.region)], LiteGlyphs.OURS)
			LiteEv.RAID_OVER:
				var r: LiteRaid = e.raid
				var hits: String = "%d hit%s" % [r.hits, "" if r.hits == 1 else "s"]
				if r.side == 1:
					ui.post("Raid over: %s. %d shot down, %s." % [composition(r), r.down, hits],
						LiteGlyphs.GOOD if r.hits == 0 else (LiteGlyphs.ENEMY if r.destroyed.size() > 0 else LiteGlyphs.YELLOW))
				elif r.total > 1 or r.hits > 0:
					ui.post("Our strike: %s. %s, %d shot down." % [composition(r), hits, r.down], LiteGlyphs.OURS)
			LiteEv.GAME_OVER:
				_end_timer = 2.0
				build_tool = null
				strike_tool = null
				audio.play("explosion_b.wav", -2.0)
	sim.events.clear()

func show_end() -> void:
	var me: LiteSide = sim.sides[0]
	var won: bool = sim.winner == 0
	var stats: String = ("%s has fallen after %s of war.\n\n" % [map.capital_name[1 if won else 0], LiteHud.duration(sim.time)]) + ("Enemy weapons shot down: %d\n" % me.downed) + ("Our hits on enemy sites: %d\n" % me.hits) + ("Enemy sites destroyed: %d\n" % me.destroyed) + ("Our sites lost: %d" % me.lost)
	ui.show_end(won, stats)

func run_balance(seed_: int, seconds: int, seeds: int) -> void:
	for k: int in seeds:
		var sd: int = seed_ + k * 101
		var t0: int = Time.get_ticks_msec()
		var map_: LiteMap = LiteMap.generate(sd)
		var sim_: LiteSim = LiteSim.new(map_, sd)
		var ai0: LiteAi = LiteAi.new(0, sd + 2, 30.0)
		ai0.waves = true
		ai0.classic = true
		ai0.turtle = "--lite-turtle" in OS.get_cmdline_user_args()
		sim_.ai[0] = ai0
		if "--lite-hard" in OS.get_cmdline_user_args():
			sim_.income_scale[1] = ENEMY_INCOME[2]
		var ai1: LiteAi = LiteAi.new(1, sd + 1, 22.0)
		ai1.waves = true
		ai1.adaptive = true
		sim_.ai[1] = ai1
		var ours: int = 0
		for r: LiteRegion in map_.regions:
			if r.side == 0:
				ours += 1
		print("[lite] seed %d: %d regions (%d ours), map %d ms" % [sd, map_.regions.size(), ours, Time.get_ticks_msec() - t0])
		var alert_ticks: int = 0
		var ticks: int = 0
		var waves: int = 0
		var step: int = 1
		while step <= seconds * 30 and sim_.winner < 0:
			sim_.step(1 / 30.0)
			for e: LiteEvent in sim_.events:
				if e.type == LiteEv.WARNING:
					waves += 1
					print("  t=%d %s massing for $%d" % [roundi(sim_.time), "west" if e.side == 0 else "east", roundi(e.value)])
			sim_.events.clear()
			if step % 30 == 0:
				ticks += 1
				if sim_.alerted[0] > 0:
					alert_ticks += 1
			if step % (60 * 30) == 0:
				print("  " + line(sim_))
			step += 1
		var winner: String = "none" if sim_.winner < 0 else ("west" if sim_.winner == 0 else "east")
		print("  end t=%ds winner=%s alert %d%% of the time, %d massive strikes planned" % [roundi(sim_.time), winner, 100 * alert_ticks / maxi(1, ticks), waves])
		var st: LiteStats = sim_.stats
		print("  stats: enemy launched %s downed %s landed %s · alerts %d median %.0f min longest %.0f · peak %d · hours %d" % [st.launched, st.downed, st.landed, st.alerts, st.median_alert(), st.longest, st.peak, st.hourly.size()])
		for r: LiteReport in st.reports:
			print("  report %s-%s: %s launched, %s down, %d hits, lost %s" % [clock_text(r.start, false), clock_text(r.end, false), r.launched, r.downed, r.hits, r.lost])
	get_tree().quit()

static func _side_line(s: LiteSim, i: int) -> String:
	var sd: LiteSide = s.sides[i]
	var f: int = 0
	var g: int = 0
	var m: int = 0
	for b: LiteBuilding in s.buildings:
		if not b.alive or b.side != i:
			continue
		if b.kind == LiteKind.FACTORY:
			f += 1
		elif b.kind == LiteKind.GUN:
			g += 1
		elif b.kind == LiteKind.SAM:
			m += 1
	return "$%d +%.1f f%d g%d s%d cap%d launched%d hits%d downed%d" % [roundi(sd.money), sd.income, f, g, m, roundi(sd.capital.hp), sd.launched, sd.hits, sd.downed]

static func line(s: LiteSim) -> String:
	return "t=%d W[%s] E[%s] air%d" % [roundi(s.time), _side_line(s, 0), _side_line(s, 1), s.weapons.size()]

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout

func _until(cond: Callable) -> void:
	while not cond.call():
		await get_tree().process_frame

func _shot(dir: String, name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = dir.path_join(name_)
	img.save_png(path)
	print("[shot] %s t=%d" % [path, roundi(sim.time)])

func _enemy_in_air() -> int:
	var n: int = 0
	for w: LiteWeapon in sim.weapons:
		if w.alive and w.side == 1:
			n += 1
	return n

func run_shots(dir: String, maps: int) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	if maps > 0:
		var first: int = seed
		ui.close_menu()
		for k: int in maps:
			new_world(first + k * 101)
			await _wait(0.3)
			await _shot(dir, "map_%d.png" % seed)
		new_world(first)
		ui.show_menu()
	await _wait(1.0)
	await _shot(dir, "0_menu.png")
	ui.show_settings()
	await _wait(0.4)
	await _shot(dir, "0_settings.png")
	_autoplay = true
	new_game()
	speed = 3
	Engine.time_scale = 4
	await _until(func() -> bool: return sim.time > 4)
	await _shot(dir, "1_start.png")
	await _until(func() -> bool: return sim.winner >= 0 or sim.time > 260 or (sim.alerted[0] >= 3 and _enemy_in_air() >= 8))
	paused = true
	Engine.time_scale = 1
	await _wait(0.6)
	await _shot(dir, "2_raid.png")
	paused = false
	Engine.time_scale = 4
	await _until(func() -> bool: return sim.winner >= 0 or sim.time > 320)
	Engine.time_scale = 1
	build_tool = LiteKind.SAM
	_fake_mouse = map.capital[0] + Vector2(-60, 40)
	await _wait(0.6)
	await _shot(dir, "3_later.png")
	build_tool = null
	ui.show_menu()
	await _wait(0.4)
	await _shot(dir, "4_pause_menu.png")
	ui.close_menu()
	_fake_mouse = null
	# Statistics and an attack report, once the war has had one.
	Engine.time_scale = 4
	await _until(func() -> bool: return sim.winner >= 0 or sim.time > 900 or (sim.stats.reports.size() >= 2 and ui.report_card.visible))
	Engine.time_scale = 1
	await _wait(0.5)
	await _shot(dir, "6_report.png")
	ui.show_stats(0)
	await _wait(0.4)
	await _shot(dir, "7_stats.png")
	ui.show_stats(1)
	await _wait(0.4)
	await _shot(dir, "8_reports.png")
	ui.stats_view.visible = false
	await stress(dir)
	get_tree().quit()

func stress(dir: String) -> void:
	if sim.winner >= 0:
		print("[perf] the war ended before the stress stage")
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Engine.time_scale = 1
	speed = 1
	paused = false
	await measure("quiet sky", 1)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	for side: int in 2:
		sim.sides[side].money += 100000
		for i: int in 6:
			sim.strike(side, LiteArm.DRONE, sim.random_spot(1 - side, rng), 14)
			sim.strike(side, LiteArm.CRUISE, sim.random_spot(1 - side, rng), 4)
		sim.strike(side, LiteArm.BALLISTIC, sim.sides[1 - side].capital.pos, 4, null, 6.0)
	for i: int in 40:
		await get_tree().process_frame
	await measure("crowded sky", 3)
	await _shot(dir, "5_stress.png")

func measure(what: String, rounds: int) -> void:
	for round_: int in rounds:
		LitePerf.reset()
		var t0: float = LitePerf.now
		var process: float = 0
		var frames: int = 0
		while LitePerf.now - t0 < 2000:
			await get_tree().process_frame
			frames += 1
			process += Performance.get_monitor(Performance.TIME_PROCESS) * 1000
		var ms: float = (LitePerf.now - t0) / frames
		print(("[perf] %s: %d in the air, %d interceptors, %d effects: " % [what, sim.weapons.size(), sim.interceptors.size(), sim.fx.size()]) +
			("%d fps, frame %.1f ms, process %.1f ms (sim %.2f, map draw %.2f, ui draw %.2f, ui process %.2f); %s" % [
				roundi(1000 / ms), ms, process / frames, LitePerf.sim_ms / frames, LitePerf.draw_ms / frames,
				LitePerf.ui_ms / frames, LitePerf.ui_proc_ms / frames, LitePerf.monitors()]))
