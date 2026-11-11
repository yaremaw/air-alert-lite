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
## When each side's guns last fired (sim time), so their sound lasts as long as the firing.
var gun_shot_at: Array[float] = [-99.0, -99.0]
var _autoplay: bool = false

var _fake_mouse: Variant = null

## The campaign being played and its mission now (null in a single war).
var campaign: LiteCampaign = null
var mission: LiteMission = null
## Game time before this war began, for the clock: a campaign's runs on from
## one mission to the next.
var clock_offset: float = 0.0
var _debrief_timer: float = -1
## The campaign's front: the war's map between operations, the provinces that
## can be attacked from it (or must be held), and the one picked.
var war_map: LiteMap = null
var front_open: bool = false
var front_options: Array[int] = []
var front_pick: int = -1
## On the front, each region's province its name (and badge) is on.
var front_labels: Dictionary = {}


## The enemy's income on Easy, Normal and Hard. Hard was 1.3 until the maps
## grew more varied (more of them favour the side with more to spend): at
## 1.15 it wins about two wars in three against our own planner again.
const ENEMY_INCOME: Array[float] = [0.8, 1.1, 1.15]
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
		if a == "--lite-audit":
			audit()
			return
		if a == "--lite-repack":
			repack()
			return
		if a.begins_with("--lite-bake=") and a.substr(12).is_valid_int():
			bake(a.substr(12).to_int())
			return
	if sim_seconds > 0:
		run_balance(seed_, sim_seconds, sim_seeds)
		return

	LiteSettings.load()
	LiteSettings.apply_sound()
	if not OS.has_feature("web"):
		DisplayServer.window_set_title("Strike Alert")
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
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--lite-tips-shot="):
			tips_shots(a.substr(17).lstrip("\"").rstrip("\""))
		if a.begins_with("--lite-region-shot="):
			region_shots(a.substr(19).lstrip("\"").rstrip("\""))
		if a.begins_with("--lite-campaign="):
			run_campaign(a.substr(16).lstrip("\"").rstrip("\""))
	# The web build's benchmark: open the page with ?bench to play a war on
	# its own, without sound, and print [perf] lines to the browser console.
	# (--lite-bench runs the same on the desktop.)
	if "--lite-bench" in OS.get_cmdline_user_args() or OS.has_feature("web") and str(JavaScriptBridge.eval("location.search")).contains("bench"):
		run_bench()

## Writes `n` freshly generated maps to res://maps for the game to load.
func bake(n: int) -> void:
	DirAccess.make_dir_recursive_absolute(LiteMap.BAKED_DIR)
	for k: int in n:
		var t0: int = Time.get_ticks_msec()
		var m: LiteMap = LiteMap.generate(1000 + k * 7919)
		var path: String = LiteMap.BAKED_DIR + "map_%03d.bin" % k
		print("[bake] %s: %d regions, %d ms, %s" % [path, m.regions.size(), Time.get_ticks_msec() - t0, error_string(m.save_baked(path))])
	get_tree().quit()

## Province shapes on every baked map (or `--lite-seeds=N` fresh ones with
## `--lite-fresh`): each map's thinnest provinces, and how many are slivers.
func audit() -> void:
	var fresh: bool = "--lite-fresh" in OS.get_cmdline_user_args()
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--lite-audit-seed="):
			var m: LiteMap = LiteMap.generate(a.substr(18).to_int())
			for r: LiteRegion in m.regions:
				print("[audit] %d %s side %d area %d" % [r.id, r.name, r.side, r.area])
			var img:= Image.create(LiteMap.RW, LiteMap.RH, false, Image.FORMAT_RGB8)
			var rng:= RandomNumberGenerator.new()
			var cols: Array[Color] = []
			for r: LiteRegion in m.regions:
				cols.append(Color.from_hsv(rng.randf(), 0.5, 0.45 if r.side == 1 else 0.85))
			for y: int in LiteMap.RH:
				for x: int in LiteMap.RW:
					var id: int = m.ids[y * LiteMap.RW + x]
					img.set_pixel(x, y, Color.BLACK if id == LiteMap.NONE else cols[id])
			for a2: String in OS.get_cmdline_user_args():
				if a2.begins_with("--lite-shot="):
					img.save_png(a2.substr(12).path_join("regions_%d.png" % m.seed))
			get_tree().quit()
			return
	var n: int = LiteMap.baked_count()
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--lite-seeds=") and a.substr(13).is_valid_int():
			n = a.substr(13).to_int()
	if "--lite-check-maps" in OS.get_cmdline_user_args():
		var old: int = 0
		for k: int in n:
			var m: LiteMap = LiteMap.load_baked(k)
			var fresh_: bool = m != null and m.world != null and m.sub.size() == LiteMap.W * LiteMap.H
			if not fresh_:
				old += 1
				print("[check] map %d is OLD (world %s, districts %d)" % [k, m.world != null if m != null else false, m.sub.size() if m != null else -1])
		print("[check] %d of %d maps old" % [old, n])
		get_tree().quit()
		return
	if "--lite-rects" in OS.get_cmdline_user_args():
		for k: int in n:
			var m: LiteMap = LiteMap.load_baked(k)
			var lo:= Vector2(LiteMap.W, LiteMap.H)
			var hi:= Vector2.ZERO
			for y: int in LiteMap.H:
				for x: int in LiteMap.W:
					if m.cell[y * LiteMap.W + x] != LiteMap.NONE:
						lo = lo.min(Vector2(x, y))
						hi = hi.max(Vector2(x + 1, y + 1))
			print("[rects] map %d saved %s real %s" % [k, m.land_rect, Rect2(lo, hi - lo)])
		get_tree().quit()
		return
	var slivers: int = 0
	var all: int = 0
	for k: int in n:
		var m: LiteMap = LiteMap.generate(1000 + k * 7919) if fresh else LiteMap.load_baked(k)
		var worst: Array = m.shapes()
		worst.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
		var bad: PackedStringArray = PackedStringArray()
		for w: Array in worst:
			all += 1
			if w[1] > 4.0:
				slivers += 1
				bad.append("%s %.1f (r %d, %s)" % [m.regions[w[0]].name, w[1], roundi(w[2]), "ours" if m.regions[w[0]].side == 0 else "theirs"])
		# Water between the two countries (a gap in the frontier), and how much
		# of the map the land fills.
		var gaps: int = 0
		var land_n: int = 0
		for y: int in range(2, LiteMap.RH - 2):
			for x: int in range(2, LiteMap.RW - 2):
				var id: int = m.ids[y * LiteMap.RW + x]
				if id != LiteMap.NONE:
					land_n += 1
					continue
				var seen: Array[bool] = [false, false]
				for d: Vector2i in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
					var o: int = m.ids[(y + d.y) * LiteMap.RW + x + d.x]
					if o != LiteMap.NONE:
						seen[m.regions[o].side] = true
				if seen[0] and seen[1]:
					gaps += 1
		print("[audit] map %d: frontier gaps %d texels, land %d%% of the map" % [k, gaps, roundi(100.0 * land_n / (LiteMap.RW * LiteMap.RH))])
		var names: PackedStringArray = PackedStringArray()
		for r: LiteRegion in m.regions:
			names.append(r.name)
		print("[audit] map %d: worst %.1f · slivers: %s · %s" % [k, worst[0][1], ", ".join(bad) if bad.size() > 0 else "none", " ".join(names)])
	print("[audit] %d of %d provinces thinner than 4" % [slivers, all])
	get_tree().quit()

## Saves the baked maps again in the current file format.
func repack() -> void:
	for k: int in LiteMap.baked_count():
		var m: LiteMap = LiteMap.load_baked(k)
		var path: String = LiteMap.BAKED_DIR + "map_%03d.bin" % k
		print("[repack] %s: %s" % [path, error_string(m.save_baked(path)) if m != null else "unreadable"])
	get_tree().quit()

func new_world(seed_: int) -> void:
	seed = seed_
	var t0: int = Time.get_ticks_msec()
	show_map(LiteMap.for_seed(seed_), seed_, t0)

## Puts a map up for a war: a new war on it and the view to show it.
func show_map(m: LiteMap, sim_seed: int, t0: int = 0) -> void:
	map = m
	sim = LiteSim.new(map, sim_seed)
	gun_shot_at = [-99.0, -99.0]
	print("[lite] map %d: %d regions in %d ms" % [sim_seed, map.regions.size(), Time.get_ticks_msec() - t0])
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
	# A little clear of the top, where the air alert banner sits.
	var frame:= Rect2(6, 30, LiteMap.W - 12, LiteMap.H - 36)
	var k: float = minf(minf(frame.size.x / land.size.x, frame.size.y / land.size.y), 1.6)
	var off: Vector2 = frame.get_center() - land.get_center() * k
	get_viewport().canvas_transform = Transform2D(0, Vector2(k, k), 0, off)


## Back to the home screen after a war ends, with a fresh map ready for the next war.
func to_title() -> void:
	started = false
	paused = true
	build_tool = null
	strike_tool = null
	_end_timer = -1
	_leave_campaign()
	new_world((seed * 7919 + 104729) % 1000003)
	ui.clear_feed()
	ui.show_menu()

func _leave_campaign() -> void:
	campaign = null
	mission = null
	war_map = null
	front_open = false
	front_pick = -1
	front_options = []
	clock_offset = 0.0
	_debrief_timer = -1

## A point on the map to a point on the screen (for the HUD).
func to_screen(p: Vector2) -> Vector2:
	return get_viewport().canvas_transform * p

func new_game() -> void:
	if started or campaign != null:
		_leave_campaign()
		new_world((seed * 7919 + 104729) % 1000003)
	_start_war(LiteSettings.difficulty)
	paused = false
	ui.post("War. The enemy capital is %s; its factories repair it. Its other sites are hidden: drones will find them." % map.capital_name[1], LiteGlyphs.MUTED)
	if not _autoplay:
		ui.tips_war()

func _start_war(d: int) -> void:
	started = true
	build_tool = null
	strike_tool = null
	_end_timer = -1
	sim.income_scale[1] = ENEMY_INCOME[d]
	var ai: LiteAi = LiteAi.new(1, seed + 1 + (campaign.ops * 13 if campaign != null else 0), 22.0)
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
	ui.clear_feed()
	audio.click()

## A campaign from its start, or the saved one from where it was left: the
## front first.
func start_campaign(fresh: bool, map_seed: int = -1) -> void:
	if fresh:
		LiteCampaign.forget()
		var c: LiteCampaign = LiteCampaign.fresh(map_seed if map_seed >= 0 else int(fmod(Time.get_unix_time_from_system(), 1000003.0)), LiteSettings.difficulty)
		c.save()
		campaign = c
	else:
		campaign = LiteCampaign.load_saved()
		if campaign == null:
			return
	show_front()

## The front between operations: the war's map as the campaign has left it,
## no war on it, the provinces that can be attacked (or the one that must be
## held) glowing, and the panel to choose from.
func show_front() -> void:
	var c: LiteCampaign = campaign
	ui.close_menu()
	mission = null
	started = false
	build_tool = null
	strike_tool = null
	drawing = null
	paused = true
	_debrief_timer = -1
	seed = c.map_seed
	war_map = LiteMap.for_seed(c.map_seed)
	c.make_groups(war_map)
	c.apply_map(war_map)
	show_map(war_map, c.map_seed)
	# Only the capitals stand on it: sites belong to an operation's map.
	var keep: Array[LiteBuilding] = []
	for b: LiteBuilding in sim.buildings:
		if b.kind == LiteKind.CAPITAL:
			keep.append(b)
	sim.buildings = keep
	clock_offset = c.clock
	front_open = true
	front_options = c.options(war_map)
	front_pick = front_options[0] if not front_options.is_empty() else -1
	# The front shows the campaign's regions: one name each, the provinces
	# inside them in faint lines.
	front_labels = c.label_groups(war_map)
	_view.set_groups(c.group_of)
	ui.clear_feed()
	ui.show_front(c)
	if not _autoplay:
		ui.tips_front()

## The province picked on the front (from the list or the map).
func pick_front(province: int) -> void:
	if front_options.has(province):
		front_pick = province
		ui.show_front(campaign)
		audio.click()

## An operation over the picked province: its map built (a few seconds, with
## a notice up meanwhile), the war set up on it, then the briefing.
func launch_operation() -> void:
	var c: LiteCampaign = campaign
	var province: int = front_pick
	if province < 0:
		return
	ui.close_front()
	ui.show_loading("Preparing the operation in %s…" % war_map.regions[province].name)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var m: LiteMap = await LiteRegionMap.build(war_map, c.group(province), province, c.map_seed * 131 + c.ops * 17 + province, self)
	ui.close_loading()
	if m == null:
		ui.show_front(c)
		refuse("No operation is possible there")
		return
	front_open = false
	mission = c.make_op(war_map, province)
	show_map(m, c.map_seed + c.ops * 977)
	_start_war(c.difficulty)
	c.setup(mission, sim, sim.ai[1])
	paused = true
	ui.post("%s. %s" % [mission.title, mission.goal_text(sim)], LiteGlyphs.OBJECTIVE)
	ui.show_briefing(mission, c)

## Closes the briefing and starts the operation's clock.
func launch_mission() -> void:
	ui.close_briefing()
	paused = false
	audio.click()
	if not _autoplay:
		ui.tips_war()

## The operation's events, as their times come.
func _operation_events() -> void:
	var m: LiteMission = mission
	while not m.events.is_empty() and sim.time >= float(m.events[0][0]):
		var e: int = m.events[0][1]
		m.events.remove_at(0)
		LiteCampaign.happen(m, e, sim)
		ui.post(LiteMission.event_text(e), LiteGlyphs.YELLOW)
		ui.hud.message(LiteMission.event_text(e))
		audio.click()
	# A convoy: destroyed in time pays; missed, it is gone.
	if m.convoy != null:
		if not m.convoy.alive:
			sim.sides[0].money += LiteMission.CONVOY_REWARD
			ui.post("Convoy destroyed: +$%d." % LiteMission.CONVOY_REWARD, LiteGlyphs.GOOD)
			m.convoy = null
		elif sim.time > m.convoy_until:
			m.convoy.alive = false
			m.convoy.dead_at = sim.time
			ui.post("The convoy got away.", LiteGlyphs.MUTED)
			m.convoy = null

## The operation called off (the Withdraw button): it counts as failed.
func withdraw_operation() -> void:
	if mission == null or mission.result >= 0 or not started:
		return
	mission.withdraw()
	end_mission()

## The operation is over: the province's districts change hands on its map
## at once (taken, or lost), then the debrief.
func end_mission() -> void:
	var m: LiteMission = mission
	var to: int = -1
	if m.result == 0 and m.kind != LiteMission.HOLD:
		to = 0
	elif m.result == 1 and m.kind == LiteMission.HOLD:
		to = 1
	if to >= 0:
		for id: int in map.focus:
			sim.hand_over(id, to)
		_view.refresh_sides()
		if to == 0:
			ui.post("Our troops take %s. The front moves forward." % m.region_name, LiteGlyphs.GOOD)
		else:
			ui.post("The enemy takes %s. The front moves back." % m.region_name, LiteGlyphs.ENEMY)
		audio.play("explosion_b.wav", -9.0)
	else:
		ui.post(m.outcome, LiteGlyphs.GOOD if m.result == 0 else LiteGlyphs.ENEMY)
	campaign.after(m, war_map, sim)
	build_tool = null
	strike_tool = null
	_debrief_timer = 2.5

func show_debrief() -> void:
	paused = true
	var c: LiteCampaign = campaign
	var m: LiteMission = mission
	var lines: PackedStringArray = PackedStringArray([m.outcome])
	if m.optional != LiteMission.NONE:
		lines.append(("Optional goal met: %s." if m.optional_done else "Optional goal missed: %s.") % m.optional_text().to_lower())
	lines.append("Provinces taken: %d · lost: %d" % [c.taken[0], c.taken[1]])
	if c.counter >= 0:
		lines.append("")
		lines.append("The enemy strikes back at %s: it has to be held next." % c.group_name(war_map, c.counter))
	if c.finished:
		LiteCampaign.forget()
		var won: bool = c.won == 0
		lines.append("")
		var how: String = "won: the enemy asks for a ceasefire" if won else ("over: out of time, a ceasefire" if c.won == 2 else "lost")
		lines.append("The war is %s." % how)
		ui.show_debrief(m, "Victory" if won else ("Ceasefire" if c.won == 2 else "Defeat"), "\n".join(lines), true, won)
		return
	c.save()
	ui.show_debrief(m, "Operation complete" if m.result == 0 else "Operation failed", "\n".join(lines), false, m.result == 0)

func next_mission() -> void:
	ui.close_debrief()
	show_front()

func set_speed(s: float) -> void:
	if not started or sim.winner >= 0 or (mission != null and mission.result >= 0) or ui.briefing_open:
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
	# To ten minutes: at this pace the minutes would only flicker.
	var at: Dictionary = Time.get_datetime_dict_from_unix_time(start + int(floor((t + clock_offset) * LiteRules.GAME_MINUTES / 10.0)) * 600)
	var hm: String = "%02d:%02d" % [int(at["hour"]), int(at["minute"])]
	if not date:
		return hm
	return "%d %s %s" % [int(at["day"]), _MONTHS[int(at["month"]) - 1], hm]

## The day and time, short, for the feed: "27 Oct 14:30".
func stamp(t: float) -> String:
	var s: String = clock_text(t, true)
	var parts: PackedStringArray = s.split(" ")
	return "%s %s %s" % [parts[0], parts[1].substr(0, 3), parts[2]]

## The day of the month `t` seconds into the war.
func day_of_month(t: float) -> int:
	return int(clock_text(t, true).split(" ")[0])

func _process(delta: float) -> void:
	if ui == null:
		return
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
	# The home screen's picture covers the map: no need to draw the map under it.
	_view.visible = not ui.home_open
	handle_events()
	if mission != null and started and mission.result < 0:
		_operation_events()
		mission.update(sim)
		if mission.result >= 0:
			end_mission()
	engine_sounds(delta)
	if _end_timer > 0:
		_end_timer -= delta
		if _end_timer <= 0:
			show_end()
	if _debrief_timer > 0:
		_debrief_timer -= delta
		if _debrief_timer <= 0:
			show_debrief()

## The buzz of enemy drones and the whine of cruise missiles over our land,
## louder the more of them there are; silent while the war waits.
func engine_sounds(delta: float) -> void:
	if audio == null:
		return
	var drones: int = 0
	var cruise: int = 0
	var live: bool = started and not paused and not ui.menu_open and sim.winner < 0
	if live:
		for w: LiteWeapon in sim.weapons:
			if not w.alive or w.side != 1 or not w.seen[0] or w.arm == LiteArm.BALLISTIC:
				continue
			if map.side_at(w.pos) != 0:
				continue
			if w.arm == LiteArm.DRONE:
				drones += 1
			else:
				cruise += 1
	audio.loop("drone_loop.wav", (0.3 + 0.7 * minf(1.0, drones / 10.0)) if drones > 0 else 0.0, -23.0, delta)
	audio.loop("cruise_loop.wav", (0.4 + 0.6 * minf(1.0, cruise / 5.0)) if cruise > 0 else 0.0, -17.0, delta)
	# The siren wails for as long as any of our regions is under alert.
	audio.loop("alert_loop.wav", 1.0 if live and _our_alert() else 0.0, -10.0, delta, 0.6, "", true)
	# Guns sound while they fire and stop with them: a gun shoots every GUN_INTERVAL.
	for side: int in 2:
		var since: float = sim.time - gun_shot_at[side]
		var firing: bool = live and since >= 0.0 and since < LiteRules.GUN_INTERVAL + 0.15
		audio.loop("gun_loop.wav", 1.0 if firing else 0.0, -18.0 if side == 0 else -27.0, delta, 14.0, "gun_%d" % side)

func update_hover() -> void:
	hover_building = null
	hover_region = -1
	strike_snap = null
	strike_target = mouse
	if front_open and not ui.menu_open and (_fake_mouse != null or get_viewport().gui_get_hovered_control() == null):
		var fid: int = map.region_at(mouse)
		hover_region = -1 if fid == LiteMap.NONE else fid
		return
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
		elif (started and sim.winner < 0) or front_open:
			ui.show_menu()
		get_viewport().set_input_as_handled()
		return
	if key != null and key.pressed and not key.echo and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER) and (ui.home_open or ui.briefing_open):
		ui.enter()
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
	var click: InputEventMouseButton = e as InputEventMouseButton
	if front_open and not ui.menu_open and click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and hover_region >= 0:
		pick_front(campaign.group_at(hover_region))
		get_viewport().set_input_as_handled()
		return
	if not started or sim.winner >= 0 or ui.menu_open or (mission != null and mission.result >= 0):
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
		# A click on a factory place counts for its region, wherever it lies.
		var on_slot: int = _view.slot_region_at(mouse)
		if on_slot >= 0:
			r = on_slot
		if r < 0 or map.regions[r].side != 0:
			refuse("Pick one of your regions")
			return
		if sim.free_slots(r) <= 0:
			refuse("No room for a factory in %s" % map.regions[r].name)
			return
		if sim.build_factory(0, r) == null:
			refuse("No free ground in %s" % map.regions[r].name)
			return
		audio.play("click.wav", -6.0)
		return
	if not sim.can_place(0, mouse):
		refuse("Build on your own territory, a little away from other sites")
		return
	sim.build(0, k, mouse)
	audio.play("click.wav", -6.0)

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
	audio.play("click.wav", -6.0)

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
	# The feed carries only news: a raid's outcome when it was a real one,
	# hits on the capitals, sites lost or destroyed, ballistic launches and
	# warnings. Alerts and all-clears show on the map and the banner.
	for e: LiteEvent in sim.events:
		if mission != null:
			mission.on_event(e, map)
		match e.type:
			LiteEv.ALL_CLEAR:
				if e.side == 0:
					if not _our_alert():
						audio.siren("all_clear.wav", -10.0)
			LiteEv.LAUNCH:
				if e.side == 0:
					audio.play("launch.wav", -19.0, 0.15)
					continue
				if e.arm == LiteArm.BALLISTIC:
					# One line per salvo, not per missile.
					if e.raid == null or not e.raid.reported:
						if e.raid != null:
							e.raid.reported = true
						ui.post("Ballistic launch towards %s." % region_name(e.region), LiteGlyphs.BALLISTIC_ALERT)
					audio.play("ballistic_warning.wav", -9.0, 4.0, 0.0)
			LiteEv.SHOT_DOWN:
				audio.play("intercept.wav", -15.0 if e.side == 0 else -22.0, 0.08)
			LiteEv.HIT:
				var on_us: bool = e.side == 1
				audio.play("explosion_small_a.wav" if e.arm == LiteArm.DRONE else "explosion_a.wav", -11.0 if on_us else -19.0, 0.06)
			LiteEv.CAPITAL_HIT:
				if sim.time - _last_capital_post < 4:
					continue
				_last_capital_post = sim.time
				if e.side == 0:
					ui.post("%s hit · %d/%d" % [map.capital_name[0], roundi(e.value), roundi(LiteRules.max_hp(LiteKind.CAPITAL))], LiteGlyphs.ENEMY)
				else:
					ui.post("Hit on %s · %d/%d" % [map.capital_name[1], roundi(e.value), roundi(LiteRules.max_hp(LiteKind.CAPITAL))], LiteGlyphs.OURS)
			LiteEv.DESTROYED:
				if e.kind == LiteKind.CAPITAL:
					continue
				if e.side == 0:
					ui.post("Lost: our %s in %s" % [LiteGlyphs.name(e.kind), region_name(e.region)], LiteGlyphs.ENEMY)
				else:
					ui.post("Destroyed: enemy %s in %s" % [LiteGlyphs.name(e.kind), region_name(e.region)], LiteGlyphs.GOOD)
				audio.play("wreck.wav", -13.0, 0.2)
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
				ui.post("Intelligence: a large strike is being prepared.", LiteGlyphs.BALLISTIC_ALERT)
				if not _our_alert():
					audio.siren("alert.wav", -9.0)
			LiteEv.REPORT:
				var rep: LiteReport = sim.stats.reports[int(e.value)]
				ui.post("Attack report: %d launched, %d shot down (T)" % [rep.total, rep.total_downed], LiteGlyphs.OURS)
			LiteEv.SPOTTED:
				if e.side == 1 and e.kind == LiteKind.FACTORY:
					ui.post("The enemy has located our factory in %s." % region_name(e.region), LiteGlyphs.ENEMY)
				if e.side == 0 and e.kind == LiteKind.FACTORY:
					ui.post("Found: enemy factory in %s" % region_name(e.region), LiteGlyphs.OURS)
			LiteEv.RAID_OVER:
				var r: LiteRaid = e.raid
				var hits: String = "%d hit%s" % [r.hits, "" if r.hits == 1 else "s"]
				# Lone scouts and stray drones are not news.
				if r.side == 1 and (r.total >= 4 or r.hits > 0):
					ui.post("Enemy raid: %s · %d down, %s" % [composition(r), r.down, hits],
						LiteGlyphs.GOOD if r.hits == 0 else (LiteGlyphs.ENEMY if r.destroyed.size() > 0 else LiteGlyphs.YELLOW))
				elif r.side == 0 and (r.total >= 3 or r.hits > 0):
					ui.post("Our strike: %s · %s, %d lost" % [composition(r), hits, r.down], LiteGlyphs.OURS)
			LiteEv.GAME_OVER:
				# In a campaign operation a command falling ends the
				# operation (see LiteMission.update), not the war.
				if mission == null:
					_end_timer = 2.0
				build_tool = null
				strike_tool = null
				audio.play("explosion_b.wav", -5.0)
	sim.events.clear()

func show_end() -> void:
	var me: LiteSide = sim.sides[0]
	var won: bool = sim.winner == 0
	var stats: String = ("%s has fallen after %s of war.\n\n" % [map.capital_name[1 if won else 0], LiteHud.duration(sim.time + clock_offset)]) + ("Enemy weapons shot down: %d\n" % me.downed) + ("Our hits on enemy sites: %d\n" % me.hits) + ("Enemy sites destroyed: %d\n" % me.destroyed) + ("Our sites lost: %d" % me.lost)
	if campaign != null:
		# A capital falling ends the whole campaign, whichever mission it was.
		stats = ("%s has fallen in operation %d. The campaign is %s.\n\nProvinces taken: %d · lost: %d" %
			[map.capital_name[1 if won else 0], mission.number, "won" if won else "lost",
			campaign.taken[0], campaign.taken[1]])
		LiteCampaign.forget()
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
		# `--lite-map-ids=3,7,12`: those baked maps (by index) instead.
		var picks: Array[int] = []
		for a: String in OS.get_cmdline_user_args():
			if a.begins_with("--lite-map-ids="):
				for t: String in a.substr(15).split(","):
					picks.append(t.to_int())
		if picks.is_empty():
			for k: int in maps:
				picks.append(first + k * 101)
		for p: int in picks:
			new_world(p)
			await _wait(0.3)
			await _shot(dir, "map_%d.png" % seed)
		# `--lite-maps-only`: no game screenshots after the maps.
		if "--lite-maps-only" in OS.get_cmdline_user_args():
			get_tree().quit()
			return
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
	await _until(func() -> bool: return sim.winner >= 0 or sim.time > 900 or sim.stats.reports.size() >= 2)
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

## A campaign played through by our own planner, without sound, for testing:
## `--lite-campaign=<dir>` plays up to `--lite-ops=N` operations (4), each
## the first offered on the front, and saves a screenshot of the front, each
## briefing, each operation under way and each debrief there, printing how
## each went. Our planner is pointed at each operation's targets, as a player
## would be.
func run_campaign(dir: String) -> void:
	AudioServer.set_bus_mute(0, true)
	LiteCampaign.path = "user://lite_campaign_test.json"
	DirAccess.make_dir_recursive_absolute(dir)
	_autoplay = true
	var most: int = 4
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--lite-ops=") and a.substr(11).is_valid_int():
			most = a.substr(11).to_int()
		if a == "--lite-counter":
			LiteCampaign.counter_chance = 1.0
		if a.begins_with("--lite-difficulty=") and a.substr(18).is_valid_int():
			LiteSettings.difficulty = clampi(a.substr(18).to_int(), 0, 2)
	await _wait(0.5)
	start_campaign(true, seed)
	# `--lite-hold`: the enemy attacking one of ours from the start.
	if "--lite-hold" in OS.get_cmdline_user_args():
		campaign.counter = campaign.group_at(LiteCampaign._border(war_map, 0)[0])
		show_front()
	var n: int = 0
	while campaign != null and n < most:
		await _wait(0.6)
		await _shot(dir, "c%d_a_front.png" % n)
		var t0: int = Time.get_ticks_msec()
		await launch_operation()
		if mission == null:
			print("[campaign] no operation could start")
			break
		var m: LiteMission = mission
		print("[campaign] op %d %s (%s): %s, %d targets, %d days, map in %d ms, events %s" % [m.number, m.title,
			LiteMission.character_name(m.character), m.goal_text(sim), m.targets.size(), roundi(m.days), Time.get_ticks_msec() - t0, m.events])
		await _wait(0.6)
		await _shot(dir, "c%d_b_briefing.png" % n)
		launch_mission()
		# The planner that holds its own against Normal in the balance runs.
		sim.ai[0].classic = true
		sim.ai[0].waves = true
		if m.kind == LiteMission.HOLD:
			# What a player would do first: air defence over the province.
			for id: int in map.focus:
				var p: Variant = sim.find_spot(0, map.regions[id].label, 6, 30)
				if p != null:
					sim.build(0, LiteKind.SAM, p)
		else:
			sim.ai[0].focus_set = map.focus
			sim.ai[0].focus_weight = 5.0
		if m.kind != LiteMission.HOLD:
			_salvos(m)
		speed = 3
		Engine.time_scale = 6
		await _until(func() -> bool: return m.result >= 0 or sim.winner >= 0 or sim.time > m.length * 0.35)
		Engine.time_scale = 1
		await _wait(0.4)
		await _shot(dir, "c%d_c_war.png" % n)
		Engine.time_scale = 6
		await _until(func() -> bool:
			# A test player stuck far past the operation's usual length gives up.
			if m.result < 0 and sim.time > m.length * 3.0:
				withdraw_operation()
			return m.result >= 0)
		Engine.time_scale = 1
		print("[campaign] op %d: result %d at t=%d (%s) · targets %d/%d · optional %s · %s" % [m.number, m.result, roundi(sim.time),
			m.outcome, m.destroyed(), m.targets.size(), m.optional_done, line(sim)])
		if sim.winner >= 0:
			print("[campaign] a command fell: winner %d" % sim.winner)
			break
		await _until(func() -> bool: return ui.debrief_open)
		await _wait(0.6)
		await _shot(dir, "c%d_d_debrief.png" % n)
		if campaign.finished:
			print("[campaign] the war is over: %s" % ("won" if campaign.won == 0 else "lost"))
			break
		next_mission()
		n += 1
	LiteCampaign.forget()
	get_tree().quit()

## The test player against an operation's targets: ballistic missiles, four at a
## time at the first target still standing, the rest of the war left to the planner.
func _salvos(m: LiteMission) -> void:
	while m.result < 0 and sim.winner < 0 and campaign != null and mission == m:
		await _wait(0.2)
		var aim: LiteBuilding = null
		for t: LiteBuilding in m.targets:
			if t.alive:
				aim = t
				break
		if aim != null and sim.time > 30.0 and sim.sides[0].money >= 4 * LiteRules.cost(LiteArm.BALLISTIC) + 250:
			sim.strike(0, LiteArm.BALLISTIC, aim.pos, 4)

## The tips and an operation's screens for testing, `--lite-tips-shot=<dir>`:
## each war tip, the front's tips, a briefing, and an operation under way
## with its card, without sound and without saving anything.
func tips_shots(dir: String) -> void:
	AudioServer.set_bus_mute(0, true)
	LiteSettings.dry = true
	LiteCampaign.path = "user://lite_campaign_test.json"
	DirAccess.make_dir_recursive_absolute(dir)
	LiteSettings.tips_war = false
	LiteSettings.tips_front = false
	await _wait(0.5)
	ui.close_menu()
	new_game()
	for k: int in 7:
		await _wait(0.5)
		if not ui.tutorial.running:
			break
		await _shot(dir, "t_war_%d.png" % k)
		ui.tutorial.next()
	ui.tutorial.finish()
	start_campaign(true, seed)
	await _wait(0.6)
	await _shot(dir, "t_front_0.png")
	ui.tutorial.next()
	await _wait(0.4)
	await _shot(dir, "t_front_1.png")
	ui.tutorial.finish()
	await _wait(0.3)
	await _shot(dir, "t_front_2.png")
	await launch_operation()
	await _wait(0.6)
	await _shot(dir, "t_briefing.png")
	LiteSettings.tips_war = false
	launch_mission()
	await _wait(0.5)
	await _shot(dir, "t_op_tip0.png")
	ui.tutorial.next()
	await _wait(0.4)
	await _shot(dir, "t_op_tip1.png")
	ui.tutorial.finish()
	_autoplay = true
	sim.ai[0] = LiteAi.new(0, seed + 2, 30.0)
	speed = 3
	Engine.time_scale = 6
	var m: LiteMission = mission
	await _until(func() -> bool: return m.result >= 0 or sim.time > m.length * 0.55)
	Engine.time_scale = 1
	await _wait(0.4)
	await _shot(dir, "t_op_war.png")
	LiteCampaign.forget()
	get_tree().quit()

## Operation maps for testing, `--lite-region-shot=<dir>`: on this seed's war
## map, each of the first few enemy provinces on the front drawn as an
## operation's map, a screenshot of each.
func region_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	ui.close_menu()
	LiteRegionMap.timing = true
	var war: LiteMap = map
	var front: Array[int] = LiteCampaign._border(war, 1)
	for k: int in mini(4, front.size()):
		var t0: int = Time.get_ticks_msec()
		var one: Array[int] = [front[k]]
		var m: LiteMap = await LiteRegionMap.build(war, one, front[k], war.seed * 31 + front[k], self)
		if m == null:
			print("[region] %s: no map" % war.regions[front[k]].name)
			continue
		print("[region] %s: %d districts in view, built in %d ms" % [war.regions[front[k]].name, m.regions.size(), Time.get_ticks_msec() - t0])
		show_map(m, 7 + k)
		started = true
		await _wait(0.5)
		await _shot(dir, "region_%d.png" % k)
	get_tree().quit()

func run_bench() -> void:
	AudioServer.set_bus_mute(0, true)
	await _wait(0.5)
	_autoplay = true
	new_game()
	speed = 3
	Engine.time_scale = 4
	await _until(func() -> bool: return sim.winner >= 0 or sim.time > 150)
	await stress("")
	print("[perf] bench done")
	if not OS.has_feature("web"):
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
	if dir != "":
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
