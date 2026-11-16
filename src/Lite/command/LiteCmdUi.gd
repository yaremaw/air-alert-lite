class_name LiteCmdUi
extends Control
## The Modern Military Command interface round the battle map (see
## LiteTheme). It stands in for the legacy war panel and HUD while the
## command look is on (LiteUi hides those then) and drives the same game:
## every button calls what the legacy panel's button calls, every figure is
## read from the war as it is. Nothing here keeps state of its own but what
## is pinned in the panel and whether the panel is folded.
##
## - top bar: the game, funds and income, the air alert and the threats in
##   the air, both capitals' health, the day and time, pause and speed,
##   statistics, the menu;
## - right toolbar: put the tool down, build (1 2 3), strike (Q W E), salvo,
##   air defence ranges, whether SAMs fire at drones;
## - in an operation, a strip under the top bar: the operation, its targets
##   and how each stands, the optional goal, events under way, Withdraw;
## - bottom: the news ticker (the war's news, and the country's);
## - over the map: its frame and grid references, the tooltip, tool hints,
##   refusals and warning banners; and the big announcements (Announce).

var main: LiteMain = null

var _top: Top = null
var _toolbar: Control = null
var _nuke: LiteCmdButton = null
var _tools: Dictionary = {}
var _speed: Array[LiteCmdButton] = []
var _salvo: Array[LiteCmdButton] = []
var _panel: Control = null
var _sam: LiteCmdButton = null
var _withdraw: LiteCmdButton = null
var _ticker: Ticker = null
## Unfolds the news line again, when it is folded away.
var _news_tab: LiteCmdButton = null
## The big announcement (a province taken, a war won or lost): in LiteUi's
## root beside this interface, so it shows on the front too, where this
## interface is hidden.
var announce: Announce = null
## The theatre of war's name over the whole screen as a war begins.
var theatre: Theatre = null
## The campaign's front in this look (LiteCmdFront), beside this interface.
var front: LiteCmdFront = null
var _overlay: Overlay = null
var _view_rect_size: Vector2 = Vector2.ZERO
## The radio card: one of the cast speaking during play (see Comms).
var comms: Comms = null

## One of the cast says `line` over the radio (cast key: see LiteStory.CAST).
func say(key: String, line: String) -> void:
	if comms != null:
		comms.say(key, line)

const BUILD_KINDS: Array[int] = [LiteKind.FACTORY, LiteKind.REFINERY, LiteKind.GUN, LiteKind.SAM, LiteKind.RADAR]
## The gun slot's tip while it holds gun trucks (BUILD_TIPS[2] is the armoured gun's).
const TRUCK_TIP: String = "Gun truck: a pickup with a heavy machine gun. Cheap, patrols its region and chases drones over it. Good against drones, a long shot at a cruise missile. G to drive it and shoot yourself."
const BUILD_TIPS: Array[String] = [
	"Factory: makes weapons for its line (drones, cruise, ballistic or SAM interceptors; L to switch). Launching them is free. Each one costs $20 more than the last.",
	"Refinery: makes the money (+$2.5/s), an oil field in the desert. Hit, it burns for a long time.",
	"Armoured AA gun: tracked, a rotary cannon that hoses down drones close in, now and then a cruise missile. Patrols its region. Aimed by eye: worse at night and in fog unless a radar links it. G takes the gun yourself.",
	"SAM: drones, cruise and ballistic missiles. With a radar's picture it reaches far and rarely misses; alone it reaches two thirds as far and misses more.",
	"Long-range radar: sees far and links the air defence round it (dashed ring): earlier warning, better aim. A prime target: lose it and its sites fight blind.",
]
const ARMS: Array[int] = [LiteArm.DRONE, LiteArm.CRUISE, LiteArm.BALLISTIC]
const SALVOS: Array[int] = [1, 3, 10]
const SPEEDS: Array[float] = [0.0, 1.0, 2.0, 3.0]

func build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_overlay = Overlay.new()
	_overlay.ui = self
	add_child(_overlay)
	_build_top()
	_build_toolbar()
	# Its buttons drawn together, pass by pass (see LiteCmdButton.Painter).
	_toolbar.add_child(LiteCmdButton.Painter.new(_toolbar))
	_build_op_strip()
	_ticker = Ticker.new()
	_ticker.ui = self
	_ticker.anchor_left = 0; _ticker.anchor_right = 1; _ticker.anchor_top = 1; _ticker.anchor_bottom = 1
	_ticker.offset_top = -LiteTheme.BOTTOM
	add_child(_ticker)
	var fold_news:= LiteCmdButton.new()
	fold_news.icon = "down"
	fold_news.anchor_left = 1; fold_news.anchor_right = 1
	fold_news.offset_left = -46; fold_news.offset_right = -8
	fold_news.offset_top = 9; fold_news.offset_bottom = LiteTheme.BOTTOM - 9
	fold_news.tooltip_text = "Fold the news away"
	fold_news.clicked = func() -> void: set_news_hidden(true)
	_ticker.add_child(fold_news)
	_news_tab = LiteCmdButton.new()
	_news_tab.icon = "up"
	_news_tab.text = ""
	_news_tab.anchor_top = 1; _news_tab.anchor_bottom = 1
	_news_tab.anchor_left = 1; _news_tab.anchor_right = 1
	_news_tab.offset_left = -LiteTheme.LEFT + 8; _news_tab.offset_right = -8
	_news_tab.offset_top = -22; _news_tab.offset_bottom = -2
	_news_tab.tooltip_text = "Show the news"
	_news_tab.clicked = func() -> void: set_news_hidden(false)
	add_child(_news_tab)
	front = LiteCmdFront.new()
	front.main = main
	main.ui.get_child(0).add_child(front)
	front.build()
	announce = Announce.new()
	main.ui.get_child(0).add_child(announce)
	theatre = Theatre.new()
	theatre.main = main
	main.ui.get_child(0).add_child(theatre)
	comms = Comms.new()
	comms.ui = self
	add_child(comms)
	comms.build()
	main.ui.posted.connect(_post)
	main.ui.feed_cleared.connect(func() -> void: _ticker.clear())

# --- Building --------------------------------------------------------------

func _build_top() -> void:
	_top = Top.new()
	_top.ui = self
	_top.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_top.anchor_left = 0; _top.anchor_right = 1
	_top.offset_bottom = LiteTheme.TOP
	_top.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_top)
	var row:= HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.anchor_left = 1; row.anchor_right = 1
	row.offset_left = -232; row.offset_right = -8
	row.offset_top = 6; row.offset_bottom = LiteTheme.TOP - 6
	row.alignment = BoxContainer.ALIGNMENT_END
	_top.add_child(row)
	var labels: Array[String] = ["", "1×", "2×", "3×"]
	for i: int in 4:
		var s: float = SPEEDS[i]
		var b:= LiteCmdButton.new()
		b.custom_minimum_size = Vector2(34, 0)
		b.bar_left = false
		if i == 0:
			b.icon = "pause"
			b.tooltip_text = "Pause (Space)"
		else:
			b.text = labels[i]
			b.tooltip_text = "Speed %d× (Space resumes)" % int(s)
		b.clicked = func() -> void:
			main.set_speed(s)
			main.audio.click()
		_speed.append(b)
		row.add_child(b)
	var gap:= Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	row.add_child(gap)
	var stats:= LiteCmdButton.new()
	stats.icon = "stats"
	stats.custom_minimum_size = Vector2(34, 0)
	stats.tooltip_text = "War statistics and attack reports (T)"
	stats.clicked = func() -> void:
		main.ui.show_stats()
		main.audio.click()
	row.add_child(stats)
	var menu:= LiteCmdButton.new()
	menu.icon = "menu"
	menu.custom_minimum_size = Vector2(34, 0)
	menu.tooltip_text = "Menu and settings (Esc)"
	menu.clicked = func() -> void:
		main.ui.show_menu()
		main.audio.click()
	row.add_child(menu)

func _build_toolbar() -> void:
	var bar:= PanelContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.anchor_top = 0; bar.anchor_bottom = 1
	bar.anchor_left = 1; bar.anchor_right = 1
	bar.offset_top = LiteTheme.TOP; bar.offset_bottom = -LiteTheme.BOTTOM
	bar.offset_left = -LiteTheme.LEFT; bar.offset_right = 0
	var box: StyleBoxFlat = LiteGlyphs.box(LiteTheme.BG2, LiteTheme.BORDER, 0, 6)
	box.border_width_right = 0; box.border_width_top = 0; box.border_width_bottom = 0
	bar.add_theme_stylebox_override("panel", box)
	add_child(bar)
	_toolbar = bar
	var vb:= VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	bar.add_child(vb)
	var sel: LiteCmdButton = _tool(vb, "select", "Select · puts the tool down (Esc, right-click). Click a site to keep its details and its coverage up.")
	sel.custom_minimum_size = Vector2(0, 40)
	sel.icon = "select"
	sel.clicked = func() -> void:
		main.build_tool = null
		main.strike_tool = null
		main.drawing = null
		main.audio.click()
	vb.add_child(_gap())
	# Two to a row: five kinds of site.
	for row_i: int in 3:
		var row:= HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		vb.add_child(row)
		for col_i: int in 2:
			var i: int = row_i * 2 + col_i
			if i >= BUILD_KINDS.size():
				break
			var k: int = BUILD_KINDS[i]
			var b: LiteCmdButton = _tool(row, "build%d" % i, "%s (%d). %s" % [LiteGlyphs.name(k), i + 1, BUILD_TIPS[i]])
			b.custom_minimum_size = Vector2(0, 46)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.sprite = _sheet("res://assets/ui/sites.png")
			b.sprite_region = Rect2(k * 16, 0, 16, 16)
			b.sprite_size = 22.0
			b.sub_size = 9
			b.font_size = 9
			b.key = "%d" % (i + 1)
			b.clicked = func() -> void: main.select_build(k)
	vb.add_child(_gap())
	var keys: Array[String] = ["Q", "W", "E"]
	for i: int in 3:
		var a: int = ARMS[i]
		var b: LiteCmdButton = _tool(vb, "strike%d" % i, "%s (%s). %s" % [LiteGlyphs.name_arm(a), keys[i], LiteUi.STRIKE_TIPS[i]])
		b.sprite = _sheet("res://assets/ui/weapons.png")
		b.sprite_region = Rect2([0, 64, 96][i], 0, 32, 32)
		b.sprite_size = 40.0
		b.sub_size = 9
		b.sprite_tint = LiteTheme.BLUE.lightened(0.25)
		b.key = keys[i]
		b.accent = LiteTheme.RED
		b.clicked = func() -> void: main.select_strike(a)
	# The bomb, there only once it may be used (see LiteMain.select_nuke).
	_nuke = _tool(vb, "nuke", "The bomb (N). One missile; everything round where it falls is gone.")
	_nuke.text = "NUKE"
	_nuke.font_size = 12
	_nuke.key = "N"
	_nuke.accent = LiteTheme.RED
	_nuke.custom_minimum_size = Vector2(0, 34)
	_nuke.visible = false
	_nuke.clicked = func() -> void: main.select_nuke()
	var salvo_row:= HBoxContainer.new()
	salvo_row.add_theme_constant_override("separation", 1)
	vb.add_child(salvo_row)
	for i: int in 3:
		var n: int = SALVOS[i]
		var c:= LiteCmdButton.new()
		c.text = "%d" % n
		c.font_size = 9
		c.bar_left = false
		c.accent = LiteTheme.RED
		c.custom_minimum_size = Vector2(15, 18)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.tooltip_text = "Salvo: launch %d at each click" % n
		c.clicked = func() -> void:
			main.salvo = n
			main.audio.click()
		_salvo.append(c)
		salvo_row.add_child(c)
	vb.add_child(_gap())
	var ranges: LiteCmdButton = _tool(vb, "ranges", "Air defence ranges: weapon range, detection range (dotted), enemy threat zones (red)")
	ranges.icon = "ranges"
	ranges.clicked = func() -> void:
		LiteSettings.ranges = not LiteSettings.ranges
		LiteSettings.save()
		main.audio.click()
	_sam = _tool(vb, "sam", "SAMs fire at drones too, using up interceptors your factories make: switch off to keep them for missiles and leave drones to the guns.")
	_sam.sprite = _sheet("res://assets/ui/sites.png")
	_sam.sprite_region = Rect2(LiteKind.SAM * 16, 0, 16, 16)
	_sam.sprite_size = 28.0
	_sam.sub_size = 9
	_sam.clicked = func() -> void:
		main.sim.sams_on_drones[0] = not main.sim.sams_on_drones[0]
		main.audio.click()

## A sprite sheet, loaded once.
static func _sheet(path: String) -> Texture2D:
	return load(path) as Texture2D

func _tool(parent: Control, key: String, tip: String) -> LiteCmdButton:
	var b:= LiteCmdButton.new()
	b.custom_minimum_size = Vector2(0, 54)
	b.tooltip_text = tip
	parent.add_child(b)
	_tools[key] = b
	return b

## Space between the toolbar's groups (select, build, strike, layers).
static func _gap() -> Control:
	var c:= Control.new()
	c.custom_minimum_size = Vector2(0, 10)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## An operation's card over the map's top left corner: its goal and targets,
## time and events, and Withdraw. Up only in an operation.
## An operation's strip under the top bar, over the map's width (see OpStrip).
func _build_op_strip() -> void:
	var strip:= OpStrip.new()
	strip.ui = self
	strip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	strip.mouse_filter = Control.MOUSE_FILTER_STOP
	strip.anchor_left = 0; strip.anchor_right = 1
	strip.offset_top = LiteTheme.TOP; strip.offset_bottom = LiteTheme.TOP + LiteTheme.OP_STRIP
	strip.offset_right = -LiteTheme.LEFT
	add_child(strip)
	_panel = strip
	_withdraw = LiteCmdButton.new()
	_withdraw.text = "WITHDRAW"
	_withdraw.font_size = 10
	_withdraw.bar_left = false
	_withdraw.accent = LiteTheme.RED
	_withdraw.anchor_left = 1; _withdraw.anchor_right = 1
	_withdraw.offset_left = -176; _withdraw.offset_right = -8
	_withdraw.offset_top = 4; _withdraw.offset_bottom = LiteTheme.OP_STRIP - 4
	_withdraw.tooltip_text = "Call the operation off. It counts as failed."
	_withdraw.clicked = func() -> void:
		if _withdraw.text == "WITHDRAW":
			_withdraw.text = "CLICK AGAIN TO WITHDRAW"
			main.audio.click()
		else:
			_withdraw.text = "WITHDRAW"
			main.withdraw_operation()
	strip.add_child(_withdraw)

# --- State -------------------------------------------------------------------

## Folds the news line away or back; the map slides to fill the room.
func set_news_hidden(on: bool) -> void:
	LiteTheme.news_hidden = on
	LiteTheme.save()
	main.audio.click()
	_refit(true)

func _refit(smooth: bool) -> void:
	_ticker.visible = not LiteTheme.news_hidden
	_news_tab.visible = LiteTheme.news_hidden
	_toolbar.offset_bottom = -LiteTheme.bottom() - (24.0 if LiteTheme.news_hidden else 0.0)
	if not main._view is LiteCmdView:
		return
	var to: Transform2D = LiteTheme.fit_transform(main)
	var view: LiteCmdView = main._view
	if smooth:
		var tw: Tween = create_tween()
		tw.tween_property(get_viewport(), "canvas_transform", to, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_callback(view.refit)
	else:
		get_viewport().canvas_transform = to
		view.refit()
	_overlay.queue_redraw()

## The site or region pinned in the panel (a click on the map with no tool
## in hand), or nothing.
var pinned: LiteBuilding:
	get: return (main._view as LiteCmdView).pinned if main._view is LiteCmdView else null
var pinned_region: int:
	get: return (main._view as LiteCmdView).pinned_region if main._view is LiteCmdView else -1

func _unhandled_input(e: InputEvent) -> void:
	if not visible or not main._view is LiteCmdView or not main.started or main.ui.menu_open:
		return
	var view: LiteCmdView = main._view
	var mb:= e as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT and main.build_tool == null and main.strike_tool == null:
		view.pinned = main.hover_building
		view.pinned_region = main.hover_region if main.hover_building == null else -1
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		view.pinned = null
		view.pinned_region = -1

func _process(_delta: float) -> void:
	var t_perf: float = LitePerf.now
	_process_timed(_delta)
	LitePerf.add("hud process", t_perf)

func _process_timed(_delta: float) -> void:
	var on: bool = main.started and LiteTheme.hud_on(main)
	visible = on
	if not on:
		return
	var tp: float = LitePerf.now
	var vs: Vector2 = get_viewport_rect().size
	if vs != _view_rect_size:
		_view_rect_size = vs
		_refit(false)
	var me: LiteSide = main.sim.sides[0]
	for i: int in BUILD_KINDS.size():
		var b: LiteCmdButton = _tools["build%d" % i]
		var k: int = BUILD_KINDS[i]
		# The gun slot holds whichever gun the side has now (LiteSim.gun_kind).
		if k == LiteKind.GUN and not LiteSim.classic_rules:
			k = main.sim.gun_kind[0]
			if b.sprite_region.position.x != k * 16:
				b.sprite_region = Rect2(k * 16, 0, 16, 16)
				b.tooltip_text = "%s (3). %s" % [LiteGlyphs.name(k), TRUCK_TIP if k == LiteKind.MOBILE else BUILD_TIPS[2]]
				b.refresh()
		var price: int = main.sim.cost(0, k)
		b.selected = main.build_tool == k
		if not main.sim.may_build(0, k):
			b.enabled = false
			b.sub = "LOCK"
			continue
		b.enabled = me.money >= price
		b.sub = "$%d" % price
	if _nuke != null:
		_nuke.visible = main.sim.nuke_ready[0] or main.nuke_tool
		_nuke.selected = main.nuke_tool
	# The drone button shows a jet once the side has them.
	var drone_x: float = 128.0 if main.sim.jet_drones[0] else 0.0
	var db: LiteCmdButton = _tools["strike0"]
	if db.sprite_region.position.x != drone_x:
		db.sprite_region = Rect2(drone_x, 0, 32, 32)
		db.refresh()
	for i: int in 3:
		var s: LiteCmdButton = _tools["strike%d" % i]
		s.selected = main.strike_tool == ARMS[i]
		# Weapons a campaign's first operations don't have yet: locked. Under
		# phase 4 rules: how many are in the stockpile, and the price.
		var have: bool = main.sim.has_arm(0, ARMS[i])
		var n: int = main.sim.in_stock(0, ARMS[i])
		s.enabled = have and me.money >= main.sim.arm_cost(0, ARMS[i]) and n > 0
		if not have:
			s.sub = "LOCKED"
		elif LiteSim.classic_rules:
			s.sub = "$%d" % main.sim.arm_cost(0, ARMS[i])
		else:
			s.sub = "%d / %d" % [n, int(me.hold[ARMS[i]])]
		_salvo[i].selected = main.salvo == SALVOS[i]
	(_tools["select"] as LiteCmdButton).selected = main.build_tool == null and main.strike_tool == null
	(_tools["ranges"] as LiteCmdButton).selected = LiteSettings.ranges
	for i: int in 4:
		_speed[i].selected = main.paused if i == 0 else (not main.paused and main.speed == SPEEDS[i])
	var m: LiteMission = main.mission
	_withdraw.visible = m != null and m.result < 0 and not m.timed
	if not _withdraw.visible:
		_withdraw.text = "WITHDRAW"
	var sams: bool = main.sim.sams_on_drones[0]
	_sam.sub = "DRONES ON" if sams else "DRONES OFF"
	_sam.selected = sams
	var on_op: bool = m != null
	if on_op != _panel.visible:
		_panel.visible = on_op
		_refit(false)
	_panel.queue_redraw()
	LitePerf.ui_proc_ms += LitePerf.now - tp

const CONDITIONS: Array[String] = ["Operational", "Damaged", "Heavily damaged", "Destroyed"]

## A site in a line for its tooltip: its state, and what it is doing.
func site_text(b: LiteBuilding) -> String:
	var sim: LiteSim = main.sim
	if b.region < 0 or b.region >= sim.alert.size() or not sim.buildings.has(b):
		return ""
	if not b.ready:
		return "Building · %ds" % roundi(b.build)
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%s %d/%d" % [CONDITIONS[b.condition], roundi(maxf(0.0, b.hp)), roundi(b.max_hp)])
	if b.kind == LiteKind.UNIT:
		if b.unit == LiteUnit.LAUNCHER:
			parts.append("fired %d · moves after firing" % b.salvos)
		elif b.wait > 0.0 and b.dist > 1.0:
			parts.append("halted")
		elif b.route_len > 0.0:
			parts.append("%d%% of its way" % roundi(100.0 * b.dist / b.route_len))
		return " · ".join(parts)
	if b.side != 0:
		if LiteKind.shoots(b.kind) and b.kind != LiteKind.CAPITAL:
			parts.append("radar-linked" if b.linked else "no radar link")
		return " · ".join(parts)
	if b.hp < b.max_hp and b.kind != LiteKind.CAPITAL and not LiteSim.classic_rules:
		parts.append("repairs paused: air alert" if sim.alert[b.region] else "repairing itself")
	match b.kind:
		LiteKind.SAM:
			parts.append("interceptors %d/%d" % [b.ammo, sim.rack[0]])
			parts.append("radar-linked" if b.linked else "no radar link: shorter reach")
		LiteKind.GUN, LiteKind.MOBILE:
			parts.append("magazine %d" % b.ammo)
			parts.append("radar-linked" if b.linked else "no radar link")
			if not LiteSim.classic_rules:
				parts.append("double-click: take the gun")
		LiteKind.FACTORY:
			if not LiteSim.classic_rules:
				parts.append("makes %s" % LiteStock.LINE_NAMES[b.line].to_lower())
			if sim.alert[b.region]:
				parts.append("sheltering")
		LiteKind.RADAR, LiteKind.MRADAR:
			var n: int = 0
			for o: LiteBuilding in sim.buildings:
				if o.alive and o.link == b:
					n += 1
			parts.append("links %d air defence site%s" % [n, "" if n == 1 else "s"] if LiteSense.radar_works(sim, b) else "out of action")
		LiteKind.REFINERY:
			parts.append("+$%.1f/s" % (LiteRules.REFINERY_INCOME * LiteStock.CONDITION_K[b.condition]))
		LiteKind.OILRIG, LiteKind.SUBSTATION, LiteKind.PUMP, LiteKind.SILO:
			parts.append("+$%.1f/s" % LiteBiome.income(b.kind))
			if b.kind == LiteKind.SUBSTATION:
				parts.append("powers the radars round it")
	return " · ".join(parts)

## For the first-time tips: where each tool is in this interface.
func tip_rect(key: String) -> Rect2:
	match key:
		"build0": return (_tools["build0"] as Control).get_global_rect()
		"air_defence": return (_tools["build2"] as Control).get_global_rect().merge((_tools["build4"] as Control).get_global_rect())
		"economy": return (_tools["build0"] as Control).get_global_rect().merge((_tools["build1"] as Control).get_global_rect())
		"strike": return (_tools["strike0"] as Control).get_global_rect().merge((_tools["strike2"] as Control).get_global_rect())
		"speed": return _speed[0].get_global_rect().merge(_speed[3].get_global_rect())
		"alert": return _top.alert_rect()
		"capitals": return _top.capitals_rect()
		"op": return _panel.get_global_rect()
		"sam": return (_tools["sam"] as Control).get_global_rect()
		"funds": return _top.funds_rect()
		"layers": return (_tools["ranges"] as Control).get_global_rect()
		"news": return _ticker.get_global_rect() if _ticker.visible else _news_tab.get_global_rect()
	return Rect2()

# --- The news -----------------------------------------------------------------

## A piece of the war's news (LiteUi.post): to the news ticker, unless it is
## routine (our own strikes' tallies, attack reports: they are in Statistics);
## what needs the player's eyes now gets a banner over the map too: ballistic
## launches and intelligence warnings, an operation's events, the front moving.
func _post(text: String, tone: Color) -> void:
	if main.sim == null:
		return
	if tone == LiteGlyphs.BALLISTIC_ALERT or tone == LiteGlyphs.YELLOW or text.contains("The front moves"):
		var col: Color = LiteTheme.RED if tone == LiteGlyphs.BALLISTIC_ALERT or tone == LiteGlyphs.ENEMY else (LiteTheme.AMBER if tone == LiteGlyphs.YELLOW else LiteTheme.BLUE)
		_overlay.warn(text, col)
	# The ticker is the country's news, not a log of the war: no hits,
	# launches or interceptions (those are on the map and in Statistics).
	# Only a few big things make it: the front moving, a turn in an
	# operation, a big strike coming. A capital hit now and then brings a
	# made-up story of its own instead (see Ticker.react).
	if text.begins_with("Hit on"):
		_ticker.react(1)
		return
	if main.map != null and text.begins_with(main.map.capital_name[0] + " hit"):
		_ticker.react(0)
		return
	var big: bool = tone == LiteGlyphs.YELLOW or text.contains("front moves") or text.contains("The enemy takes") \
		or text.begins_with("Intelligence:")
	if not big:
		return
	var col2: Color = LiteTheme.TEXT
	if tone == LiteGlyphs.ENEMY or tone == LiteGlyphs.BALLISTIC_ALERT:
		col2 = LiteTheme.RED
	elif tone == LiteGlyphs.GOOD:
		col2 = LiteTheme.GREEN
	elif tone == LiteGlyphs.YELLOW:
		col2 = LiteTheme.AMBER
	elif tone == LiteGlyphs.OURS:
		col2 = LiteTheme.BLUE
	_ticker.push("BREAKING", text.trim_suffix("."), col2, true)

# --- What the war looks like now (shared by the bars and the panel) ------------

## The air alert over our country: 0 none, 1 drones, 2 missiles; the title
## and line under it; its colour.
func alert_state() -> Array:
	var sim: LiteSim = main.sim
	var regions: int = sim.alerted[0]
	var threats: int = 0
	var ballistic: bool = false
	var missiles: bool = false
	for wp: LiteWeapon in sim.weapons:
		if wp.alive and wp.side == 1 and wp.seen[0]:
			threats += 1
			if wp.arm == LiteArm.BALLISTIC:
				ballistic = true
			if wp.arm != LiteArm.DRONE:
				missiles = true
	var state: int = 0 if regions == 0 else (2 if missiles else 1)
	var title: String
	var sub: String
	var tone: Color = LiteTheme.GREEN
	if state == 2:
		title = "BALLISTIC THREAT" if ballistic else "MISSILE THREAT · %d REGION%s" % [regions, "" if regions == 1 else "S"]
		tone = LiteTheme.RED
	elif state == 1:
		title = "AIR ALERT · %d REGION%s" % [regions, "" if regions == 1 else "S"]
		tone = LiteTheme.AMBER
	else:
		title = "NO AIR ALERT"
	if state > 0:
		sub = "SINCE %s · %d TRACK%s" % [main.clock_text(sim.side_alert_since[0], false), threats, "" if threats == 1 else "S"]
	elif sim.side_quiet_since[0] > 0:
		sub = "ALL CLEAR SINCE %s" % main.clock_text(sim.side_quiet_since[0], false)
	else:
		sub = "SKY QUIET"
	var ai: LiteAi = sim.ai[1]
	if state == 0 and ai != null and ai.massing:
		title = "LARGE STRIKE EXPECTED"
		sub = "INTEL: ENEMY MASSING DRONES AND MISSILES"
		tone = LiteTheme.AMBER
		state = 1
	return [state, title, sub, tone]

## Hostile tracks we see, and our own weapons in the air, by arm.
func tracks() -> Array:
	var hostile: Array[int] = [0, 0, 0]
	var own: Array[int] = [0, 0, 0]
	for wp: LiteWeapon in main.sim.weapons:
		if not wp.alive:
			continue
		if wp.side == 1 and wp.seen[0]:
			hostile[wp.arm] += 1
		elif wp.side == 0:
			own[wp.arm] += 1
	return [hostile, own]

## Counts by arm as words, leaving out the zeros: "4 drones · 1 cruise".
static func by_arm(n: Array[int], none: String) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var names: Array[String] = ["drone", "cruise", "ballistic"]
	for a: int in 3:
		if n[a] > 0:
			parts.append("%d %s%s" % [n[a], names[a], "s" if a == 0 and n[a] != 1 else ""])
	return " · ".join(parts) if not parts.is_empty() else none

## The war's day, from its first.
func day() -> int:
	return int((main.sim.time + main.clock_offset) / LiteRules.DAY) + 1


# ==============================================================================

## The top bar.
class Top extends Control:
	var ui: LiteCmdUi = null
	var _t: float = 0.0
	var _state: int = -1
	var _pulse: float = 0.0
	var _alert_x: float = 0.0
	var _alert_w: float = 0.0
	var _caps_x: float = 0.0
	var _funds_x: float = 158.0

	func funds_rect() -> Rect2:
		return Rect2(global_position + Vector2(_funds_x - 4, 4), Vector2(150, size.y - 8))

	func alert_rect() -> Rect2:
		return Rect2(global_position + Vector2(_alert_x, 4), Vector2(_alert_w, size.y - 8))

	func capitals_rect() -> Rect2:
		return Rect2(global_position + Vector2(_caps_x - MORALE_W - 12.0, 2), Vector2(MORALE_W + 12.0 + CAP_W * 2 + 14, size.y - 4))

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_pulse = maxf(0.0, _pulse - delta * 1.5)
		_t -= delta
		if _t <= 0.0 or _pulse > 0.0:
			_t = 0.2
			queue_redraw()

	func _draw() -> void:
		var main: LiteMain = ui.main
		var sim: LiteSim = main.sim
		draw_rect(Rect2(Vector2.ZERO, size), LiteTheme.BG2)
		draw_rect(Rect2(0, size.y - 2, size.x, 1), LiteTheme.BORDER)
		draw_rect(Rect2(0, size.y - 1, size.x, 1), Color(0, 0, 0, 0.5))
		var cy: float = size.y / 2.0
		LiteLogo.draw_mark(self, Vector2(22, cy), 10.0)
		draw_string(LiteGlyphs.black, Vector2(40, cy + 4.5), "STRIKE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteTheme.TEXT)
		draw_string(LiteGlyphs.black, Vector2(40 + LiteGlyphs.black.get_string_size("STRIKE ", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, cy + 4.5), "ALERT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteTheme.RED)
		var x: float = 146.0
		x += 4.0
		var m: LiteMission = main.mission
		# Funds, the figure checked most: big, its income beside it.
		var me: LiteSide = sim.sides[0]
		var money: String = "$%d" % floori(me.money)
		var inc: String = "+%.1f/s" % me.income
		var mw: float = LiteGlyphs.bold.get_string_size(money, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 8.0
		var fw: float = mw + LiteGlyphs.bold.get_string_size(inc, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 22.0
		LiteCmdStyle.panel(self, Rect2(x, cy - 14, fw, 28), LiteTheme.PANEL, LiteTheme.BORDER)
		draw_string(LiteGlyphs.bold, Vector2(x + 10, cy + 7), money, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, LiteTheme.TEXT)
		draw_string(LiteGlyphs.bold, Vector2(x + 10 + mw, cy + 6), inc, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LiteTheme.GREEN)
		_funds_x = x
		_draw_alert(x + fw + 12.0, cy)
		# The day and time, left of the speed controls, with the hour and the
		# weather and what they do to the war (see LiteEnv).
		var clock: String = main.clock_text(sim.time, true)
		var parts: PackedStringArray = clock.split(" ")
		var date: String = "%s %s" % [parts[0], parts[1].substr(0, 3).to_upper()] if parts.size() >= 3 else clock
		var hm: String = parts[parts.size() - 1]
		var cx: float = size.x - 240.0
		var paused: bool = main.paused and sim.winner < 0 and not main.ui.briefing_open and not (m != null and m.result >= 0)
		var env: LiteEnv = sim.env
		var cond: String = "%s · %s" % [_time_of_day(env), env.weather_name().to_upper()]
		var fx: String = _effects_short(env)
		var hw: float = LiteGlyphs.bold.get_string_size(hm, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		# Paused: said in amber where the date goes, so it can't be missed.
		var top_line: String = "PAUSED" if paused else "DAY %d · %s" % [ui.day(), date]
		var dw: float = maxf(LiteGlyphs.bold.get_string_size(top_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x,
			LiteGlyphs.bold.get_string_size(cond + ("  " + fx if fx != "" else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x)
		var clock_r:= Rect2(cx - hw - dw - 44, cy - 14, hw + dw + 50, 28)
		LiteCmdStyle.panel(self, clock_r, LiteTheme.PANEL, Color(LiteTheme.AMBER, 0.9) if paused else LiteTheme.BORDER)
		_env_icon(Vector2(clock_r.position.x + 13, cy), env)
		_right(LiteGlyphs.bold, cx, cy + 6, hm, 17, LiteTheme.TEXT)
		var lx: float = clock_r.position.x + 26.0
		draw_string(LiteGlyphs.bold, Vector2(lx, cy - 3), top_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, LiteTheme.AMBER if paused else LiteTheme.MUTED)
		draw_string(LiteGlyphs.bold, Vector2(lx, cy + 9), cond, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, LiteTheme.TEXT)
		if fx != "":
			var cw: float = LiteGlyphs.bold.get_string_size(cond + "  ", HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			draw_string(LiteGlyphs.bold, Vector2(lx + cw, cy + 9), fx, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, LiteTheme.RED if env.drones_grounded() else LiteTheme.AMBER)
		_env_rect = clock_r
		var right_end: float = clock_r.position.x - 12.0
		_draw_capitals(maxf(_alert_x + _alert_w + 18.0 + MORALE_W + 12.0, minf(right_end - CAP_W * 2 - 24.0, size.x - 560.0)), cy)

	## The air alert over our country, and the hostile tracks in the air by
	## kind: a coloured box, then a count beside each weapon's symbol.
	func _draw_alert(x: float, cy: float) -> void:
		var st: Array = ui.alert_state()
		var state: int = st[0]
		var col: Color = st[3]
		var sim: LiteSim = ui.main.sim
		var title: String = st[1]
		if state > 0 and title.begins_with("AIR ALERT"):
			title = "AIR ALERT · %d" % sim.alerted[0]
		elif state > 0 and title.begins_with("MISSILE THREAT"):
			title = "MISSILE THREAT · %d" % sim.alerted[0]
		if state > 0:
			_pulse = maxf(_pulse, 0.0)
		var font: Font = LiteGlyphs.bold
		var tw: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var h: Array[int] = ui.tracks()[0]
		var w: float = tw + 24.0 + 3.0 * 34.0
		_alert_x = x
		_alert_w = w
		w += 12.0
		_alert_w = w
		var r:= Rect2(x, cy - 14, w, 28)
		LiteCmdStyle.panel(self, r, LiteTheme.PANEL.lerp(col, 0.12 if state > 0 else 0.0), Color(col, 0.75 if state > 0 else 0.35))
		# The light: blinking while the alert is on.
		var blink: bool = state == 0 or fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6
		LiteCmdStyle.led(self, Vector2(x + 12, cy), col, blink)
		draw_string(font, Vector2(x + 22, cy + 4.5), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col if state > 0 else LiteTheme.TEXT)
		var gx: float = x + tw + 32.0
		var tex: Texture2D = LiteCmdUi._sheet("res://assets/ui/weapons.png")
		for a: int in 3:
			var c: Color = LiteTheme.RED.lightened(0.15) if h[a] > 0 else Color(LiteTheme.NEUTRAL, 0.7)
			draw_texture_rect_region(tex, Rect2(gx - 2, cy - 10, 20, 20), Rect2([0, 64, 96][a], 0, 32, 32), c)
			draw_string(font, Vector2(gx + 18, cy + 4.5), "%d" % h[a], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteTheme.TEXT if h[a] > 0 else LiteTheme.NEUTRAL)
			gx += 34.0

	const CAP_W: float = 50.0
	## The morale meter's width, left of the capitals.
	const MORALE_W: float = 128.0
	var _nation_rect: Rect2 = Rect2()
	var _env_rect: Rect2 = Rect2()

	## The hour as a word: day, dusk, night, dawn.
	func _time_of_day(env: LiteEnv) -> String:
		if env.night <= 0.0:
			return "DAY"
		if env.night >= 1.0:
			return "NIGHT"
		return "DAWN" if env.hour < 12.0 else "DUSK"

	## What the hour and the weather do now, the one that matters most, in a
	## few letters (the rest in the tooltip).
	func _effects_short(env: LiteEnv) -> String:
		if env.drones_grounded():
			return "NO DRONES"
		var g: float = env.gun_factor()
		if g < 0.97:
			return "AA %d%%" % roundi(g * 100.0)
		return ""

	## A small pixel picture of the sky: sun or moon, cloud, fog, storm.
	func _env_icon(c: Vector2, env: LiteEnv) -> void:
		var w: int = env.weather
		if w == LiteEnv.CLEAR or w == LiteEnv.CLOUDY:
			if env.night >= 0.5:
				draw_circle(c + Vector2(-1, -1), 5.0, Color(0.86, 0.88, 0.95))
				draw_circle(c + Vector2(1.5, -2.5), 4.2, LiteTheme.PANEL)
			else:
				draw_rect(Rect2(c - Vector2(3.5, 3.5) + Vector2(-1, -1), Vector2(7, 7)), Color(1.0, 0.8, 0.3))
				for k: int in 4:
					var d: Vector2 = Vector2.from_angle(k * PI / 2.0) * 6.5
					draw_rect(Rect2(c + Vector2(-1, -1) + d - Vector2(1, 1), Vector2(2, 2)), Color(1.0, 0.8, 0.3))
		if w == LiteEnv.CLOUDY or w == LiteEnv.STORM:
			var cc: Color = Color(0.72, 0.76, 0.82) if w == LiteEnv.CLOUDY else Color(0.5, 0.54, 0.62)
			draw_rect(Rect2(c + Vector2(-6, 0), Vector2(12, 4)), cc)
			draw_rect(Rect2(c + Vector2(-4, -3), Vector2(6, 3)), cc)
			draw_rect(Rect2(c + Vector2(0, -5), Vector2(4, 5)), cc)
		if w == LiteEnv.STORM:
			draw_rect(Rect2(c + Vector2(-1, 4), Vector2(2, 3)), Color(1.0, 0.85, 0.3))
			draw_rect(Rect2(c + Vector2(0, 6), Vector2(2, 3)), Color(1.0, 0.85, 0.3))
		if w == LiteEnv.FOG:
			for k: int in 3:
				draw_rect(Rect2(c + Vector2(-6 + (k % 2) * 2, -4 + k * 3.5), Vector2(11, 1.6)), Color(0.75, 0.78, 0.82))

	## Hovering over the clock: what the hour and the weather do, in full.
	func _get_tooltip(at: Vector2) -> String:
		if ui.main.sim != null and _nation_rect.has_point(at):
			return _nation_tip()
		if not _env_rect.has_point(at) or ui.main.sim == null:
			return ""
		var env: LiteEnv = ui.main.sim.env
		var t: String = "%s, %s.
" % [_time_of_day(env).capitalize(), env.weather_name().to_lower()]
		t += "AA guns hit %d%% as often as usual" % roundi(env.gun_factor() * 100.0)
		if env.gun_range() < 0.99:
			t += " and see %d%% as far" % roundi(env.gun_range() * 100.0)
		t += " (night and fog hurt guns; SAMs are guided by radar and work as ever).
"
		t += "Drones grounded by the storm: those in the air fly home and land." if env.drones_grounded() else "Drones can fly."
		return t

	## The country's morale (phase 4, LiteMorale): its state in a word, a
	## meter, which way it is going; then both capitals' state.
	func _nation_tip() -> String:
		var sim: LiteSim = ui.main.sim
		var me: LiteSide = sim.sides[0]
		var them: LiteSide = sim.sides[1]
		var t: String = "National morale: %s (%d/100), %s.\n" % [LiteMorale.state_name(me.morale), roundi(me.morale),
			"rising" if me.morale_trend > 0.3 else ("falling" if me.morale_trend < -0.3 else "steady")]
		t += "The country works at %d%% (income and production).\n" % roundi(LiteMorale.efficiency(me.morale) * 100.0)
		t += "Strikes that land, lost factories and a hit capital lower it; enemy weapons shot down, our strikes, repairs and quiet days raise it. At zero the country gives up.\n"
		t += "Enemy morale (intelligence): %s." % LiteMorale.state_name(them.morale)
		return t

	func _draw_morale(x: float, cy: float) -> void:
		var me: LiteSide = ui.main.sim.sides[0]
		var st: int = LiteMorale.state(me.morale)
		var col: Color = [LiteTheme.GREEN, LiteTheme.TEXT, LiteTheme.AMBER, LiteTheme.RED, LiteTheme.RED][st]
		draw_string(LiteGlyphs.bold, Vector2(x, cy - 4), "MORALE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, LiteTheme.MUTED)
		var word: String = LiteMorale.STATES[st].to_upper()
		var arrow: String = "▲" if me.morale_trend > 0.3 else ("▼" if me.morale_trend < -0.3 else "")
		_right(LiteGlyphs.bold, x + MORALE_W, cy - 4, word + (" " + arrow if arrow != "" else ""), 8, col)
		var blink: bool = st < 4 or fmod(Time.get_ticks_msec() / 1000.0, 0.8) < 0.5
		LiteCmdStyle.blocks(self, Rect2(x, cy + 5, MORALE_W, 5), 10, me.morale / 10.0, col if blink else Color(col, 0.4))

	## Both capitals' health: the figure and a bar under it; ours in blue,
	## the enemy's in red. The morale meter left of them.
	func _draw_capitals(x: float, cy: float) -> void:
		var sim: LiteSim = ui.main.sim
		_caps_x = x
		# An operation has no national morale (see LiteCampaign.setup): its
		# task is on the strip under this bar.
		if not LiteSim.classic_rules and ui.main.mission != null:
			_nation_rect = Rect2()
			return
		var nation: bool = not LiteSim.classic_rules
		var left: float = x - (MORALE_W + 12.0 if nation else 0.0)
		_nation_rect = Rect2(left - 10, cy - 14, x - left + CAP_W * 2 + 34, 28)
		LiteCmdStyle.panel(self, _nation_rect, LiteTheme.PANEL, LiteTheme.BORDER)
		if nation:
			_draw_morale(left, cy)
			draw_rect(Rect2(x - 7, cy - 10, 1, 20), LiteTheme.BORDER)
			# The enemy's morale, as far as intelligence can tell.
			var them: LiteSide = sim.sides[1]
			var st: int = LiteMorale.state(them.morale)
			draw_string(LiteGlyphs.bold, Vector2(x, cy - 4), "ENEMY", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, LiteTheme.MUTED)
			_right(LiteGlyphs.bold, x + CAP_W * 2 + 14, cy - 4, LiteMorale.STATES[st].to_upper(), 8, LiteTheme.RED)
			LiteCmdStyle.blocks(self, Rect2(x, cy + 5, CAP_W * 2 + 14, 5), 10, them.morale / 10.0, LiteTheme.RED)
			return
		for side: int in 2:
			var cap: LiteBuilding = sim.sides[side].capital
			if cap == null:
				continue
			var bx: float = x + side * (CAP_W + 14.0)
			var col: Color = LiteTheme.BLUE if side == 0 else LiteTheme.RED
			var f: float = clampf(maxf(0.0, cap.hp) / cap.max_hp, 0.0, 1.0)
			# The capital's star in its side's colour, then its state.
			LiteGlyphs.draw_ci(self, LiteGlyph.CAPITAL, Vector2(bx + 6, cy - 4), 0.55, col)
			var hp: String = "%d" % roundi(maxf(0.0, cap.hp))
			var tone: Color = LiteTheme.TEXT if f > 0.33 else LiteTheme.RED
			_right(LiteGlyphs.bold, bx + CAP_W, cy + 1, hp, 13, tone)
			LiteCmdStyle.blocks(self, Rect2(bx, cy + 5, CAP_W, 5), 8, f * 8.0, col if f > 0.33 else LiteTheme.RED)

	func _right(font: Font, x: float, y: float, text: String, fsize: int, col: Color) -> void:
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		draw_string(font, Vector2(x - tw, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


## The radio: one of the cast speaking, in the bottom bar over the news line
## (never over the map while the news line is up), a few seconds each, one
## after another (a short queue; the stale are dropped): their portrait, their
## name, and the line.
class Comms extends PanelContainer:
	var ui: LiteCmdUi = null
	var _queue: Array = []
	var _left: float = 0.0
	var _pic: TextureRect = null
	var _bar: ColorRect = null
	var _name: Label = null
	var _line: Label = null
	const HOLD: float = 5.5
	const ACCENT: Dictionary = {"varga": Color("#E8A33D"), "moroz": Color("#45D1E0"), "bilyk": Color("#F07A3A"), "rudin": Color("#F05B50")}

	func build() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
		var box: StyleBoxFlat = LiteGlyphs.box(LiteTheme.BG2, LiteTheme.BORDER, 0, 0)
		box.content_margin_left = 6; box.content_margin_right = 12; box.content_margin_top = 4; box.content_margin_bottom = 4
		box.border_width_left = 0; box.border_width_right = 0; box.border_width_bottom = 0
		add_theme_stylebox_override("panel", box)
		anchor_left = 0; anchor_right = 1; anchor_top = 1; anchor_bottom = 1
		offset_right = -52
		var row:= HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		add_child(row)
		_bar = ColorRect.new()
		_bar.custom_minimum_size = Vector2(4, 0)
		row.add_child(_bar)
		_pic = TextureRect.new()
		_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_pic.custom_minimum_size = Vector2(LiteTheme.BOTTOM - 8, LiteTheme.BOTTOM - 8)
		row.add_child(_pic)
		var col:= VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		_name = Label.new()
		_name.add_theme_font_override("font", LiteGlyphs.bold)
		_name.add_theme_font_size_override("font_size", 13)
		col.add_child(_name)
		_line = Label.new()
		_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_line.custom_minimum_size = Vector2(700, 0)
		_line.add_theme_font_size_override("font_size", 21)
		_line.add_theme_color_override("font_color", LiteTheme.TEXT)
		col.add_child(_line)

	func say(key: String, line: String) -> void:
		for q: Array in _queue:
			if q[1] == line:
				return
		_queue.append([key, line])
		while _queue.size() > 2:
			_queue.pop_front()

	func _process(delta: float) -> void:
		if not ui.visible:
			visible = false
			return
		# The tips and the briefing come first: the radio waits for them.
		var lui: LiteUi = ui.main.ui
		if lui.tutorial.running or lui.briefing_open or lui.slides.visible or lui.page_open:
			visible = false
			return
		if _left > 0.0:
			visible = true
			_left -= delta
			var a: float = clampf(minf(_left, HOLD - _left) / 0.25, 0.0, 1.0)
			modulate.a = a
			# Rising into the bar, and sinking out of it.
			offset_top = -LiteTheme.BOTTOM + (1.0 - a) * 18.0
			offset_bottom = (1.0 - a) * 18.0
			if _left <= 0.0:
				visible = false
			return
		if _queue.is_empty():
			return
		var q: Array = _queue.pop_front()
		var key: String = q[0]
		var cast: Array = LiteStory.CAST.get(key, ["", ""])
		var col: Color = ACCENT.get(key, LiteTheme.AMBER)
		var tex: Texture2D = LiteStory.image("portrait_" + key)
		_pic.texture = tex
		_pic.visible = tex != null
		_bar.color = col
		_name.text = ("%s  ·  %s" % [String(cast[0]).to_upper(), cast[1]]) if key != "rudin" else "INTERCEPTED  ·  %s" % String(cast[0]).to_upper()
		_name.add_theme_color_override("font_color", col)
		_line.text = "“%s”" % q[1]
		_left = HOLD
		visible = true
		offset_top = -LiteTheme.BOTTOM
		offset_bottom = 0
		ui.main.audio.play("click_off.wav", -14.0)

## The operation's strip: OPERATION n · ITS TITLE, then each target with its
## symbol, coloured as it stands (destroyed green, located white, hidden grey
## with a question mark), the optional goal, events under way; Withdraw at
## its right end.
class OpStrip extends Control:
	var ui: LiteCmdUi = null

	func _draw() -> void:
		var main: LiteMain = ui.main
		var m: LiteMission = main.mission
		draw_rect(Rect2(Vector2.ZERO, size), LiteTheme.BG2)
		draw_rect(Rect2(0, size.y - 1, size.x, 1), LiteTheme.BORDER)
		if m == null or main.sim == null:
			return
		var sim: LiteSim = main.sim
		var cy: float = size.y / 2.0
		var font: Font = LiteGlyphs.bold
		var x: float = 12.0
		var head: String = "OPERATION %d · %s" % [m.number, m.title.to_upper()]
		draw_string(font, Vector2(x, cy + 4.5), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteTheme.TEXT)
		x += font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0
		draw_rect(Rect2(x, 7, 1, size.y - 14), LiteTheme.BORDER)
		x += 14.0
		var end: float = size.x - 190.0
		if m.result >= 0:
			var done: String = "COMPLETE" if m.result == 0 else "FAILED"
			draw_string(font, Vector2(x, cy + 4.5), done, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteTheme.GREEN if m.result == 0 else LiteTheme.RED)
			return
		if m.defensive and m.plot == LiteMission.PLOT_NONE:
			var t: String = "ENEMY HITS %d / %d" % [m.hits, m.need]
			draw_string(font, Vector2(x, cy + 4.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteTheme.RED if m.hits > 0 else LiteTheme.TEXT)
			x += font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 18.0
			var left: String = "HOLD FOR %s" % LiteHud.duration(m.time_left(sim)).to_upper()
			draw_string(font, Vector2(x, cy + 4.5), left, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteTheme.MUTED)
			x += font.get_string_size(left, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 18.0
		elif m.plot != LiteMission.PLOT_NONE:
			# Forces on the move: their symbols (struck through when gone),
			# then how the race stands.
			var units: Array[LiteBuilding] = m.targets.duplicate()
			units.append_array(m.extras)
			for t: LiteBuilding in units:
				if t.unit == LiteUnit.WAGON:
					continue
				var a: float = 1.0 if t.alive else 0.35
				if t.kind == LiteKind.UNIT:
					LiteUnit.symbol(self, Vector2(x + 9, cy), t.unit, 9.0, a, 0.0, t.side == 0)
				else:
					LiteGlyphs.draw_ci(self, LiteGlyphs.of(t.kind), Vector2(x + 9, cy), 0.9, Color(LiteTheme.RED, a))
				if not t.alive:
					draw_line(Vector2(x, cy + 8), Vector2(x + 18, cy - 8), LiteTheme.GREEN if not t.crossed else LiteTheme.RED, 2.0)
				x += 24.0
			x += 8.0
			var status: String = ""
			var tone: Color = LiteTheme.TEXT
			match m.plot:
				LiteMission.PLOT_COLUMN:
					status = "STOPPED %d / %d · LEAD %d%% TO THE BORDER" % [m.destroyed(), m.targets.size(), roundi(m.lead() * 100.0)]
					tone = LiteTheme.RED if m.lead() > 0.75 else LiteTheme.TEXT
				LiteMission.PLOT_TRAIN:
					var burnt: int = 0
					for w: LiteBuilding in m.extras:
						burnt += 0 if w.alive else 1
					status = "TRAIN %s · WAGONS BURNT %d / %d" % [m.goal_progress(sim).to_upper(), burnt, m.extras.size()]
					tone = LiteTheme.RED if m.lead() > 0.75 else LiteTheme.TEXT
				LiteMission.PLOT_HUNT:
					status = "DESTROYED %d / %d · SALVOS %d / %d" % [m.destroyed(), m.targets.size(), m.salvos(), m.salvo_limit]
				LiteMission.PLOT_ASSAULT:
					status = "STOPPED %d / %d · LEAD %d%% TO %s · HOLD %s" % [m.destroyed(), m.targets.size(), roundi(m.lead() * 100.0), m.region_name.to_upper(), LiteHud.duration(m.time_left(sim)).to_upper()]
					tone = LiteTheme.RED if m.lead() > 0.75 else LiteTheme.TEXT
				LiteMission.PLOT_PORT:
					status = "PORT %d / %d DESTROYED · SHIPS SUNK %d (+%d CP) · AWAY %d" % [m.destroyed(), m.targets.size(), m.ships_sunk(), m.ships_sunk(), m.crossed]
				LiteMission.PLOT_GRID:
					status = "STATIONS DOWN %d / %d · REPAIRED %d / %d" % [m.destroyed(), m.targets.size(), m.repairs, m.repair_limit]
					tone = LiteTheme.RED if m.repairs >= m.repair_limit - 1 else LiteTheme.TEXT
				LiteMission.PLOT_DEPOT:
					status = "DESTROYED %d / %d · CONVOYS THROUGH %d / %d" % [m.destroyed(), m.targets.size(), m.crossed, m.escape_limit]
					tone = LiteTheme.RED if m.crossed >= m.escape_limit - 1 else LiteTheme.TEXT
				LiteMission.PLOT_EVAC:
					status = "OUT %d · LOST %d / %d ALLOWED" % [m.saved, m.destroyed(), m.may_lose]
					tone = LiteTheme.RED if m.destroyed() >= m.may_lose else LiteTheme.TEXT
					tone = LiteTheme.RED if m.salvos() >= m.salvo_limit - 2 else LiteTheme.TEXT
			draw_string(font, Vector2(x, cy + 4.5), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tone)
			x += font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 18.0
		else:
			for t: LiteBuilding in m.targets:
				var col: Color = LiteTheme.GREEN if not t.alive else (LiteTheme.TEXT if t.seen[0] else LiteTheme.NEUTRAL)
				var name: String = LiteGlyphs.name(t.kind) + ("  ✓" if not t.alive else ("" if t.seen[0] else "  ?"))
				var w: float = 22.0 + font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 18.0
				if x + w > end:
					break
				LiteCmdStyle.panel(self, Rect2(x - 4, 5, w - 10, size.y - 10), LiteTheme.PANEL, Color(col, 0.45), 2.0)
				var tex: Texture2D = LiteCmdUi._sheet("res://assets/ui/sites.png")
				draw_texture_rect_region(tex, Rect2(x - 1, cy - 8, 16, 16), Rect2(t.kind * 16, 16 if not t.alive else 0, 16, 16), Color(1, 1, 1, 1.0 if t.seen[0] else 0.35))
				draw_string(font, Vector2(x + 22, cy + 4.5), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
				x += w
		var extras: Array = []
		if m.optional != LiteMission.NONE:
			extras.append(["OPTIONAL: %s · %s" % [m.optional_text(true).to_upper(), m.optional_progress().to_upper()],
				LiteTheme.GREEN if m.optional_done else LiteTheme.MUTED])
		if m.storm_until > sim.time:
			extras.append(["STORM: DRONES GROUNDED %s" % LiteHud.duration(m.storm_until - sim.time).to_upper(), LiteTheme.AMBER])
		if m.outage_until > sim.time:
			extras.append(["ENEMY SAMS SILENT %s" % LiteHud.duration(m.outage_until - sim.time).to_upper(), LiteTheme.AMBER])
		if m.convoy != null and m.convoy.alive:
			extras.append(["CONVOY +$%d · %s" % [LiteMission.CONVOY_REWARD, LiteHud.duration(maxf(0.0, m.convoy_until - sim.time)).to_upper()], LiteTheme.AMBER])
		for e: Array in extras:
			var t: String = e[0]
			var w2: float = LiteGlyphs.font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 26.0
			if x + w2 > end:
				break
			draw_rect(Rect2(x, 7, 1, size.y - 14), LiteTheme.BORDER)
			draw_string(LiteGlyphs.font, Vector2(x + 13, cy + 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, e[1])
			x += w2



## The news line along the bottom: the war's big events as they come (a
## ballistic launch, a capital hit, the front moving, an operation's turns),
## and between them the country's news: made up, mostly about the war, some
## of it light. It runs slowly from right to left, the war's own news
## jumping the queue; the button at its right end folds it away.
class Ticker extends Control:
	var ui: LiteCmdUi = null
	const SPEED: float = 78.0
	const GAP: float = 80.0
	const LEFT: float = 130.0
	const RIGHT_END: float = 52.0
	const FONT: int = 23
	## On the strip: [x, tag, text, colour, width]; waiting: [tag, text, colour, urgent].
	var _on: Array = []
	var _queue: Array = []
	var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var _deck: Array[int] = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		_rng.randomize()

	func clear() -> void:
		_on.clear()
		_queue.clear()

	## A piece of news; the war's own (`urgent`) goes ahead of the rest.
	func push(tag: String, text: String, col: Color, urgent: bool) -> void:
		var item: Array = [tag, text, col, urgent]
		if urgent:
			for q: Array in _queue:
				if q[1] == text:
					return
			var at: int = 0
			while at < _queue.size() and _queue[at][3]:
				at += 1
			_queue.insert(at, item)
			while _queue.size() > 5:
				_queue.pop_back()
		else:
			_queue.append(item)

	func _process(delta: float) -> void:
		if not is_visible_in_tree() or ui.main.sim == null:
			return
		for it: Array in _on:
			it[0] = float(it[0]) - SPEED * delta
		while not _on.is_empty() and float(_on[0][0]) + float(_on[0][4]) < LEFT:
			_on.pop_front()
		var end: float = LEFT
		if not _on.is_empty():
			var last: Array = _on[_on.size() - 1]
			end = float(last[0]) + float(last[4]) + GAP
		if end < size.x:
			if _queue.is_empty():
				_story()
			if not _queue.is_empty():
				var q: Array = _queue.pop_front()
				var w: float = LiteGlyphs.font.get_string_size(str(q[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x
				if str(q[0]) != "":
					# As _draw lays it out: the tag (see LiteCmdStyle.tag) and the gap after it.
					w += LiteGlyphs.black.get_string_size(str(q[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 18.0 + 12.0
				_on.append([maxf(end, size.x), q[0], q[1], q[2], w])
		queue_redraw()

	## A capital hit (`side`'s): now and then, not every time, a story about
	## it, made up like the rest.
	var _react_at: float = -1000.0
	func react(side: int) -> void:
		var now: float = ui.main.sim.time
		if now - _react_at < 120.0 or _rng.randf() > 0.35:
			return
		_react_at = now
		var map: LiteMap = ui.main.map
		var cap: String = map.capital_name[0].trim_prefix("HQ ")
		var ecap: String = map.capital_name[1].trim_prefix("HQ ")
		var ours: Array[String] = [
			"Firefighters in %s work through the night; by morning the trams are running again" % cap,
			"Neighbours in %s sweep up the glass together and open a soup kitchen in the courtyard" % cap,
			"The mayor of %s gives his briefing from the street: \"We are still here\"" % cap,
			"The queue outside a blood bank in %s stretches two blocks after the night's strike" % cap,
		]
		var theirs: Array[String] = [
			"%s state TV says the explosions in the city were \"planned exercises\"" % ecap,
			"Residents of %s film the smoke over the ministry; the videos vanish within the hour" % ecap,
			"Officials in %s blame a gas leak for the fire at the defence ministry" % ecap,
			"Traffic jams on every road out of %s, local channels report, then stop reporting" % ecap,
		]
		var list: Array[String] = ours if side == 0 else theirs
		push("", list[_rng.randi_range(0, list.size() - 1)], LiteTheme.TEXT, true)

	## A story from round the country: places drawn from the map in play.
	func _story() -> void:
		var map: LiteMap = ui.main.map
		var ours: Array[String] = []
		var theirs: Array[String] = []
		for r: LiteRegion in map.regions:
			if r.city or r.name == "":
				continue
			(ours if r.side == 0 else theirs).append(r.name)
		if ours.is_empty() or theirs.is_empty():
			return
		var nb: Array[String] = []
		if map.world != null:
			for k: int in map.world.label_text.size():
				if map.world.label_kind[k] == 0:
					nb.append(map.world.label_text[k])
		if nb.is_empty():
			nb.append("A neighbouring country")
		var a: String = ours[_rng.randi_range(0, ours.size() - 1)]
		var a2: String = ours[_rng.randi_range(0, ours.size() - 1)]
		var b: String = theirs[_rng.randi_range(0, theirs.size() - 1)]
		var n: String = nb[_rng.randi_range(0, nb.size() - 1)]
		var cap: String = map.capital_name[0].trim_prefix("HQ ")
		var ecap: String = map.capital_name[1].trim_prefix("HQ ")
		var stories: Array[String] = [
			"A farmer in %s tows a downed enemy drone home with his tractor: \"It came to my field, it's mine now\"" % a,
			"Air defence crew in %s adopts a stray cat; it now turns up for every alert" % a,
			"Bakery in %s launches the \"SAM bun\": crisp outside, intercepts hunger" % cap,
			"%s state TV reports a great victory over a flock of migrating geese" % ecap,
			"Grandmother in %s refuses to go down to the shelter until her borscht is ready" % a,
			"Enemy drone lands in a sunflower field in %s; villagers charge to see it, proceeds go to the army" % a,
			"Schoolchildren in %s can now tell a drone from a cruise missile by ear" % a,
			"Engineers in %s rebuild a bridge in four days; the mayor had promised a week" % a,
			"%s announces the capture of %s for the third time this month" % [ecap, a],
			"Radio amateurs in %s track enemy drones from a garage roof" % a2,
			"Volunteers in %s weave two thousand camouflage nets in one weekend" % cap,
			"A rooster in %s crows at every air alert; neighbours say he has never been wrong" % a,
			"Officials in %s blame the weather for the fire at a depot in %s" % [ecap, b],
			"Brewery in %s names its new lager \"All Clear\"" % a2,
			"Football match in %s plays on through the alert; it ends 0-0 anyway" % cap,
			"Enemy soldiers in %s caught selling their rations for phone credit" % b,
			"Army dogs in %s get medals for sniffing out unexploded drones" % a,
			"Enemy leaflets dropped over %s end up as kindling, stove sellers report" % a2,
			"Wedding in %s moves into the metro during an alert; guests say it was the best dance floor in town" % cap,
			"Hackers put a cartoon on enemy television in %s for twenty minutes" % b,
			"Students in %s build a drone detector out of old phones" % a,
			"Enemy general in %s promises victory \"within two weeks\", as he did in spring" % ecap,
			"Power engineers restore supply in %s within six hours of the strike" % a,
			"Rail traffic to %s runs on schedule again" % a2,
			"Satellite images show fuel depots still burning in %s" % b,
			"Talks on an exchange of prisoners stall again",
			"Blood donors queue round the block in %s" % cap,
			"Weather: low cloud along the front tonight, drones expected" ,
			"Air bases near %s on alert, according to reports from the border" % b,
			"Factories in %s keep their lines running through the alerts" % a,
			"%s sends a convoy of generators and field hospitals to %s" % [n, cap],
			"%s closes its airspace along the border after a stray drone" % n,
			"Conscription extended in %s; long queues at the border crossings" % b,
			"Partisans report a railway bridge out near %s" % b,
			"Analysts: the enemy is running short of cruise missiles, again",
			"New shelters open in the %s metro, with Wi-Fi and a library" % cap,
			"Repair crews in %s rename their truck \"The Phoenix\" after its fifth rebuild" % a,
			"Enemy column near %s halted by its own minefield, observers say" % b,
			"%s museum opens an exhibition of shot-down drones" % cap,
			"Fishermen haul a missile tail fin from the sea; it will hang in the village pub" ,
			"Volunteers in %s print drone parts on a school 3D printer" % a2,
			"Enemy officers in %s reported moving their families away from the front" % b,
		]
		if _deck.is_empty():
			for i: int in stories.size():
				_deck.append(i)
			_deck.shuffle()
		# In a campaign, every third story is about the campaign itself.
		var c: LiteCampaign = ui.main.campaign
		var m: LiteMission = ui.main.mission
		if c != null and m != null and m.result < 0 and _rng.randf() < 0.3:
			push("RADIO", LiteStory.radio(m, ui.main.war_map if ui.main.war_map != null else map, _rng), LiteTheme.AMBER, false)
			return
		if c != null and _rng.randf() < 0.34:
			var war: LiteMap = ui.main.war_map if ui.main.war_map != null else map
			var told: String = LiteStory.news(c, war, _rng)
			if told != "":
				push("", told, LiteTheme.TEXT, false)
				return
		push("", stories[_deck.pop_back()], LiteTheme.TEXT, false)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), LiteTheme.BG2)
		draw_rect(Rect2(0, 0, size.x, 1), LiteTheme.BORDER)
		draw_rect(Rect2(0, 1, size.x, 1), Color(0, 0, 0, 0.5))
		# The strip the news runs along, recessed a little.
		var lane:= Rect2(LEFT - 14, 10, size.x - LEFT - RIGHT_END + 14, size.y - 20)
		draw_rect(lane, Color(0, 0, 0, 0.22))
		draw_line(lane.position, Vector2(lane.end.x, lane.position.y), Color(0, 0, 0, 0.4), 1.0)
		draw_line(Vector2(lane.position.x, lane.end.y), lane.end, Color(1, 1, 1, 0.04), 1.0)
		var y: float = size.y / 2.0 + FONT * 0.36
		for it: Array in _on:
			var x: float = it[0]
			var tag: String = str(it[1])
			if tag != "":
				var tc: Color = it[3]
				x += LiteCmdStyle.tag(self, Vector2(x, size.y / 2.0 - 12), tag, Color(tc, 0.9), LiteTheme.BG, 13, 24) + 12.0
			draw_string(LiteGlyphs.font, Vector2(x, y), str(it[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, it[3])
			# Between items, a small square in two tones.
			var dot: float = float(it[0]) + float(it[4]) + GAP / 2.0
			draw_rect(Rect2(dot - 4, size.y / 2.0 - 4, 8, 8), LiteTheme.RED.darkened(0.45))
			draw_rect(Rect2(dot - 4, size.y / 2.0 - 4, 4, 4), LiteTheme.RED.darkened(0.1))
		# The tag at the left and the fold button's place at the right, over the strip.
		draw_rect(Rect2(0, 2, LEFT - 14, size.y - 2), LiteTheme.BG2)
		LiteCmdStyle.panel(self, Rect2(14, 12, LEFT - 40, size.y - 24), LiteTheme.RED, LiteTheme.RED.darkened(0.45), 4.0)
		LiteCmdStyle.led(self, Vector2(28, size.y / 2.0), Color.WHITE, fmod(Time.get_ticks_msec() / 1000.0, 1.2) < 0.7)
		draw_string(LiteGlyphs.black, Vector2(36, size.y / 2.0 + 7), "NEWS", HORIZONTAL_ALIGNMENT_CENTER, LEFT - 64, 19, LiteTheme.TEXT)
		draw_rect(Rect2(size.x - RIGHT_END, 2, RIGHT_END, size.y - 2), LiteTheme.BG2)


## The theatre of war as a war begins: PLAINS, WINTER or DESERT across the
## whole screen, a kicker over it and a line under it, rules drawing out to
## either side; it fades in, holds a moment, its letters spreading slowly,
## and fades out. Then `done` (the war's tips).
class Theatre extends Control:
	const FADE_IN: float = 0.8
	const HOLD: float = 2.2
	const FADE_OUT: float = 1.0
	var _age: float = 99.0
	var _climate: int = 0
	var _done: Callable = Callable()
	var main: LiteMain = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		set_process(false)

	func play(climate: int, done: Callable) -> void:
		_climate = climate
		_done = done
		_age = 0.0
		move_to_front()
		set_process(true)
		queue_redraw()

	var active: bool:
		get: return _age < FADE_IN + HOLD + FADE_OUT

	## Gone at once, and what was to follow it with it (the home screen or
	## the menu opened over it).
	func clear() -> void:
		_age = 99.0
		_done = Callable()
		set_process(false)
		queue_redraw()

	func _process(delta: float) -> void:
		if main != null and (main.ui.home_open or main.ui.menu_open):
			clear()
			return
		_age += delta
		queue_redraw()
		if not active:
			set_process(false)
			if _done.is_valid():
				var d: Callable = _done
				_done = Callable()
				d.call()

	func _draw() -> void:
		if not active:
			return
		var t: float = _age
		var a: float = clampf(t / FADE_IN, 0.0, 1.0)
		a = a * a * (3.0 - 2.0 * a)
		var out: float = clampf((t - FADE_IN - HOLD) / FADE_OUT, 0.0, 1.0)
		a *= 1.0 - out * out * (3.0 - 2.0 * out)
		var name: String = ["PLAINS", "DESERT", "WINTER"][clampi(_climate, 0, 2)]
		var line: String = [
			"Open fields and long sight lines. Nowhere to hide.",
			"Sand, heat and haze. Every launch is seen for miles.",
			"Frozen ground, short days and long nights.",
		][clampi(_climate, 0, 2)]
		var col: Color = [Color("#9FCB7A"), Color("#E8B45A"), Color("#B9DDF5")][clampi(_climate, 0, 2)]
		var vs: Vector2 = size
		# The screen darkened, most in the middle band.
		draw_rect(Rect2(Vector2.ZERO, vs), Color(LiteTheme.BG, 0.45 * a))
		var cy: float = vs.y * 0.44
		draw_rect(Rect2(0, cy - 92, vs.x, 184), Color(LiteTheme.BG, 0.55 * a))
		# The name, its letters spreading a little the whole time: each
		# letter placed on its own at a fractional spacing, eased, so the
		# spread is smooth rather than a pixel at a time.
		var u: float = clampf(t / (FADE_IN + HOLD + FADE_OUT), 0.0, 1.0)
		var track: float = 14.0 + 10.0 * (1.0 - (1.0 - u) * (1.0 - u))
		var font: Font = LiteGlyphs.black
		var fs: int = 92
		var widths: Array[float] = []
		var w: float = 0.0
		for i: int in name.length():
			var cw: float = font.get_char_size(name.unicode_at(i), fs).x
			widths.append(cw)
			w += cw + (track if i < name.length() - 1 else 0.0)
		var x: float = (vs.x - w) / 2.0
		var rise: float = 10.0 * (1.0 - clampf(t / FADE_IN, 0.0, 1.0))
		var cx: float = x
		for i: int in name.length():
			var ch: String = name[i]
			# Moved by the transform, not the string's own position (that one
			# is snapped to whole pixels at this size).
			draw_set_transform(Vector2(cx, cy + 34 + rise))
			draw_string(font, Vector2(3, 4), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6 * a))
			draw_string(font, Vector2.ZERO, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, a))
			cx += widths[i] + track
		draw_set_transform(Vector2.ZERO)
		# Rules drawing out from the name to either side.
		var grow: float = clampf((t - 0.2) / 1.2, 0.0, 1.0)
		grow = 1.0 - (1.0 - grow) * (1.0 - grow)
		var len: float = minf(260.0, x - 60.0) * grow
		for side: float in [-1.0, 1.0]:
			var from: float = x - 34.0 if side < 0 else x + w + 34.0
			draw_rect(Rect2(from - (len if side < 0 else 0.0), cy - 1, len, 2), Color(col, 0.8 * a))
			draw_rect(Rect2(from - 3 if side < 0 else from - 3, cy - 4, 6, 8), Color(col, a))
		# The kicker over it, the line under it.
		var kick: String = "THEATRE OF WAR"
		var kf: Font = LiteGlyphs.bold
		draw_string(kf, Vector2(0, cy - 56 + rise), kick, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 15, Color(LiteTheme.AMBER, a))
		draw_string(LiteGlyphs.font, Vector2(0, cy + 74 + rise), line, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 18, Color(LiteTheme.TEXT, 0.9 * a))


## A big announcement over the map: a title and a line under it, in a band
## across the screen; it slides in, holds, and fades.
class Announce extends Control:
	var _title: String = ""
	var _sub: String = ""
	var _col: Color = LiteTheme.BLUE
	var _age: float = 99.0
	var _hold: float = 2.5

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func show_text(title: String, sub: String, col: Color, hold: float = 2.5) -> void:
		_title = title
		_sub = sub
		_col = col
		_hold = hold
		_age = 0.0

	var active: bool:
		get: return _age < _hold + 0.6

	## Gone at once (an end screen is opening over it).
	func clear() -> void:
		_age = 99.0
		queue_redraw()

	func _process(delta: float) -> void:
		var was: bool = active
		_age += delta
		if was or active:
			queue_redraw()

	func _draw() -> void:
		if not active or _title == "":
			return
		var a: float = clampf(_age / 0.3, 0.0, 1.0) * clampf((_hold + 0.6 - _age) / 0.6, 0.0, 1.0)
		var vs: Vector2 = size
		var h: float = 96.0
		var y: float = vs.y * 0.3 - h / 2.0 + 12.0 * (1.0 - clampf(_age / 0.3, 0.0, 1.0))
		draw_rect(Rect2(0, y, vs.x, h), Color(LiteTheme.BG, 0.86 * a))
		draw_rect(Rect2(0, y, vs.x, 2), Color(_col, a))
		draw_rect(Rect2(0, y + h - 2, vs.x, 2), Color(_col, a))
		draw_string(LiteGlyphs.black, Vector2(0, y + 50), _title, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 34, Color(_col, a))
		draw_string(LiteGlyphs.bold, Vector2(0, y + 76), _sub, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 15, Color(LiteTheme.TEXT, a))


## Over the map, under the bars: the map's frame with grid references, the
## tooltip, the tool's hint and any refusal.
class Overlay extends Control:
	var ui: LiteCmdUi = null
	var _t: float = 0.0
	var _mouse: Vector2 = Vector2.ZERO
	var _key: String = ""
	## The warning banner: its text, colour and how long it has been up.
	const WARN_TIME: float = 4.0
	var _warn: String = ""
	var _warn_col: Color = LiteTheme.RED
	var _warn_age: float = 99.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func warn(text: String, col: Color) -> void:
		_warn = text
		_warn_col = col
		_warn_age = 0.0

	func _process(delta: float) -> void:
		_warn_age += delta
		if not is_visible_in_tree():
			return
		var main: LiteMain = ui.main
		var hud: LiteHud = main.ui.hud
		var key: String = "%s|%s|%s|%s|%s" % [main.hover_building, main.hover_region, main.build_tool, main.strike_tool, hud._msg_age < 2.4]
		_t -= delta
		if key != _key or (main.mouse != _mouse and (main.hover_building != null or main.hover_region >= 0)) or hud._msg_age < 2.4 or _warn_age < WARN_TIME + 0.1 or _t <= 0.0:
			_key = key
			_mouse = main.mouse
			_t = 0.25
			queue_redraw()

	func _draw() -> void:
		var main: LiteMain = ui.main
		var vs: Vector2 = size
		var t: float = LiteTheme.top(main)
		var frame:= Rect2(0, t, vs.x - LiteTheme.LEFT, vs.y - t - LiteTheme.bottom())
		_frame(main, frame)
		_hint(main, frame)
		_banner(frame)
		_tooltip(main, frame)

	## The warning banner under the top bar: slides in, holds, fades.
	func _banner(frame: Rect2) -> void:
		if _warn_age >= WARN_TIME or _warn == "":
			return
		var a: float = clampf(_warn_age / 0.2, 0.0, 1.0) * clampf((WARN_TIME - _warn_age) / 0.6, 0.0, 1.0)
		var font: Font = LiteGlyphs.bold
		var w: float = minf(font.get_string_size(_warn, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 64.0, frame.size.x - 40.0)
		var y: float = frame.position.y + 22.0 - 8.0 * (1.0 - clampf(_warn_age / 0.2, 0.0, 1.0))
		w += 20.0
		var r:= Rect2(frame.get_center().x - w / 2.0, y, w, 34)
		LiteCmdStyle.panel(self, r, Color(LiteTheme.PANEL, 0.97 * a), Color(_warn_col, 0.8 * a), 4.0)
		# A block of hazard stripes at its left end, the warning's colour.
		var hz:= Rect2(r.position.x + 3, r.position.y + 3, 30, r.size.y - 6)
		draw_rect(hz, Color(_warn_col.darkened(0.55), a))
		LiteCmdStyle.hatch(self, hz, Color(_warn_col, 0.85 * a), 5.0)
		LiteCmdStyle.hatch(self, Rect2(hz.position + Vector2(1, 0), hz.size - Vector2(1, 0)), Color(_warn_col, 0.85 * a), 5.0)
		LiteCmdIcons.draw(self, "warn", Vector2(r.position.x + 50, r.get_center().y), 0.95, Color(_warn_col, a))
		draw_string(font, Vector2(r.position.x + 66, r.get_center().y + 5), _warn, HORIZONTAL_ALIGNMENT_LEFT, w - 76, 14, Color(LiteTheme.TEXT, a))

	## The map's frame: a tick at each corner.
	func _frame(main: LiteMain, frame: Rect2) -> void:
		# Corner ticks.
		var c: Color = Color(LiteTheme.MUTED, 0.5)
		for corner: Vector2 in [frame.position + Vector2(4, 4), Vector2(frame.end.x - 4, frame.position.y + 4), Vector2(frame.position.x + 4, frame.end.y - 4), frame.end - Vector2(4, 4)]:
			var sx: float = 1.0 if corner.x < frame.get_center().x else -1.0
			var sy: float = 1.0 if corner.y < frame.get_center().y else -1.0
			draw_line(corner, corner + Vector2(12 * sx, 0), c, 1.0)
			draw_line(corner, corner + Vector2(0, 12 * sy), c, 1.0)

	static func _col_name(i: int) -> String:
		var s: String = ""
		var n: int = i
		while true:
			s = String.chr(65 + n % 26) + s
			n = n / 26 - 1
			if n < 0:
				break
		return s

	func _hint(main: LiteMain, frame: Rect2) -> void:
		var hint: String = ""
		if main.build_tool != null and int(main.build_tool) == LiteKind.FACTORY:
			hint = "BUILD FACTORY ($%d) · click a region with a free place (green) · right-click puts the tool down" % main.sim.cost(0, LiteKind.FACTORY)
		elif main.build_tool != null:
			var k: int = int(main.build_tool)
			hint = "BUILD %s ($%d) · click your territory · right-click puts the tool down" % [LiteGlyphs.name(k).to_upper(), main.sim.cost(0, k)]
		elif main.strike_tool != null:
			var a: int = int(main.strike_tool)
			hint = "STRIKE · %s · click enemy territory, or drag a route from your land (never from the striped band) · right-click cancels" % LiteGlyphs.plural(a, 2).to_upper()
		var y: float = frame.end.y - 22.0
		var hud: LiteHud = main.ui.hud
		if hud._msg_age < 2.2:
			var a: float = clampf((2.2 - hud._msg_age) / 0.4, 0, 1)
			_pill(hud._msg, frame.get_center().x, y - (30.0 if hint != "" else 0.0), Color(LiteTheme.RED, a), a)
		if hint != "":
			_pill(hint, frame.get_center().x, y, LiteTheme.MUTED, 1.0)

	func _pill(text: String, cx: float, y: float, col: Color, alpha: float) -> void:
		var font: Font = LiteGlyphs.font
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 24.0
		var r:= Rect2(cx - w / 2.0, y - 12, w, 24)
		draw_rect(r, Color(LiteTheme.PANEL, 0.94 * alpha))
		draw_rect(r, Color(LiteTheme.BORDER, alpha), false, 1.0)
		draw_rect(Rect2(r.position, Vector2(2, r.size.y)), col)
		draw_string(font, Vector2(r.position.x + 12, y + 4.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)

	func _tooltip(main: LiteMain, frame: Rect2) -> void:
		if (main.build_tool != null and int(main.build_tool) != LiteKind.FACTORY and int(main.build_tool) != LiteMain.REPAIR_TOOL) or main.strike_tool != null:
			return
		var sim: LiteSim = main.sim
		var head: String = ""
		var body: String = ""
		var col: Color = LiteTheme.TEXT
		var b: LiteBuilding = main.hover_building
		var pinned: bool = false
		if b == null and main.hover_region < 0 and ui.pinned != null and ui.pinned.alive:
			b = ui.pinned
			pinned = true
		if b != null:
			head = ("FRIENDLY " if b.side == 0 else "HOSTILE ") + (LiteUnit.name(b.unit) if b.kind == LiteKind.UNIT else LiteGlyphs.name(b.kind)).to_upper()
			col = LiteTheme.BLUE if b.side == 0 else LiteTheme.RED
			body = ui.site_text(b)
		elif main.hover_region >= 0:
			var r: LiteRegion = main.map.regions[main.hover_region]
			head = r.name.to_upper()
			col = LiteTheme.BLUE if r.side == 0 else LiteTheme.RED
			if r.side == 0 and not r.city:
				head += " · FACTORIES %d/%d" % [sim.factories_in(r.id), sim.slots[r.id]]
			if sim.alert[r.id]:
				body = "%s · %s" % ["Ballistic threat" if sim.ballistic[r.id] else ("Missile threat" if sim.missile[r.id] else "Air alert · drones"), LiteHud.duration(sim.time - sim.alert_since[r.id])]
			else:
				body = "No alert" if r.side == 0 else "Hostile territory"
		if head == "":
			return
		var font: Font = LiteGlyphs.font
		var w: float = maxf(LiteGlyphs.bold.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, font.get_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) + 22.0
		var p: Vector2 = main.to_screen(b.pos if pinned else main.mouse) + Vector2(16, 14)
		if p.x + w > frame.end.x - 4:
			p.x -= w + 28
		if p.y + 40 > frame.end.y - 4:
			p.y -= 56
		var rect:= Rect2(p, Vector2(w, 42))
		draw_rect(rect, Color(LiteTheme.PANEL, 0.97))
		draw_rect(rect, LiteTheme.BORDER, false, 1.0)
		draw_rect(Rect2(rect.position, Vector2(2, rect.size.y)), col)
		draw_string(LiteGlyphs.bold, p + Vector2(11, 16), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LiteTheme.TEXT)
		draw_string(font, p + Vector2(11, 33), body, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteTheme.MUTED)
