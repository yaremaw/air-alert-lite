class_name LiteUi
extends CanvasLayer

var main: LiteMain = null
var hud: LiteHud = null
var stats_view: LiteStatsView = null
var _build: Array[LiteToolButton] = [null, null, null]
var _strike: Array[LiteToolButton] = [null, null, null]
var _salvo: Array[LiteChip] = [null, null, null]
var _speed: Array[LiteChip] = [null, null, null, null]
var _diff: Array[LiteChip] = [null, null, null]
var _volume: Array[LiteChip] = [null, null, null, null]
var _window: Array[LiteChip] = [null, null]
var _routes: Array[LiteChip] = [null, null]
var _ranges: Array[LiteChip] = [null, null]
var _sam_toggle: LiteChip = null
var _feed: VBoxContainer = null
var _panel: Control = null
var _menu: Control = null
var _new_game: Control = null
var _settings: Control = null
var _end: Control = null
var home: LiteHome = null
var _end_title: Label = null
var _end_text: Label = null
var _campaign: Control = null
var _cdiff: Array[LiteChip] = [null, null, null]
var _campaign_go: Button = null
var _campaign_new: Button = null
var _briefing: Control = null
var _brief_box: VBoxContainer = null
var _debrief: Control = null
var _debrief_title: Label = null
var _debrief_text: Label = null
var _debrief_next: Button = null
var _front: Control = null
var _op_card: LiteOpCard = null
var _withdraw: LiteChip = null
var tutorial: LiteTutorial = null
var _front_box: VBoxContainer = null
var _loading: Control = null
var _loading_text: Label = null

var menu_open: bool:
	get: return _menu.visible or _new_game.visible or _settings.visible or stats_view.visible or briefing_open or _debrief.visible

## The home screen or one of the screens it opens (New war, Settings).
var home_open: bool:
	get: return _menu.visible or _new_game.visible or _settings.visible or _campaign.visible

var briefing_open: bool:
	get: return _briefing != null and _briefing.visible

var debrief_open: bool:
	get: return _debrief != null and _debrief.visible

const BUILD_KINDS: Array[int] = [LiteKind.FACTORY, LiteKind.GUN, LiteKind.SAM]
const ARMS: Array[int] = [LiteArm.DRONE, LiteArm.CRUISE, LiteArm.BALLISTIC]
const SALVOS: Array[int] = [1, 3, 6]
const SPEEDS: Array[float] = [0.0, 1.0, 2.0, 3.0]

const BUILD_TIPS: Array[String] = [
	"Factory: +$4/s and repairs the capital. Built into a region with room for it; the front has more room than the rear. Each one costs $20 more than the last. While its region is under air alert the workers shelter and it runs at half its pace.",
	"AA gun: cheap and short-ranged. Shoots at drones, now and then hits a cruise missile. Its shells cost nothing.",
	"SAM: long range. Hits drones, cruise and ballistic missiles. Every interceptor costs $10.",
]
const STRIKE_TIPS: Array[String] = [
	"Attack drone: slow and cheap, wanders on its way. Reveals enemy sites it flies over. 1 damage.",
	"Cruise missile: fast and accurate, launched from deep inside our country. 2 damage.",
	"Ballistic missile: very fast, hard to intercept, a little scattered. 3 damage.",
]

func build() -> void:
	var root:= Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	hud = LiteHud.new()
	hud.main = main
	root.add_child(hud)

	var panel:= PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.anchor_left = 1; panel.anchor_right = 1; panel.anchor_top = 0; panel.anchor_bottom = 1
	panel.offset_left = -292; panel.offset_right = -10; panel.offset_top = 10; panel.offset_bottom = -10
	panel.add_theme_stylebox_override("panel", LiteGlyphs.box(Color(LiteGlyphs.PANEL, 0.97), LiteGlyphs.LINE, 14, 14))
	root.add_child(panel)
	_panel = panel
	var vb:= VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var status:= LiteStatus.new()
	status.main = main
	status.custom_minimum_size = Vector2(0, 156)
	vb.add_child(status)
	var op:= LiteOpCard.new()
	op.main = main
	op.visible = false
	vb.add_child(op)
	_op_card = op
	# Calling an attack off: a second click to be sure.
	_withdraw = LiteChip.new()
	_withdraw.text = "Withdraw"
	_withdraw.font_size = 11
	_withdraw.tooltip_text = "Call the operation off. It counts as failed."
	_withdraw.clicked = func() -> void:
		if _withdraw.text == "Withdraw":
			_withdraw.text = "Click again to withdraw"
			main.audio.click()
		else:
			_withdraw.text = "Withdraw"
			main.withdraw_operation()
	vb.add_child(_withdraw)

	vb.add_child(_section("BUILD", "on your territory"))
	var row: HBoxContainer = _row(vb)
	for i in 3:
		var k: int = BUILD_KINDS[i]
		var b:= LiteToolButton.new()
		b.glyph = LiteGlyphs.of(k)
		b.title = LiteGlyphs.name(k)
		b.price = "$%d" % LiteRules.cost_kind(k)
		b.key = "%d" % (i + 1)
		b.tooltip_text = BUILD_TIPS[i]
		b.clicked = func() -> void: main.select_build(k)
		_build[i] = b
		row.add_child(b)

	vb.add_child(_section("STRIKE", "at enemy territory"))
	row = _row(vb)
	var keys: Array[String] = ["Q", "W", "E"]
	for i in 3:
		var a: int = ARMS[i]
		var b:= LiteToolButton.new()
		b.glyph = LiteGlyphs.of_arm(a)
		b.title = LiteGlyphs.name_arm(a)
		b.price = "$%d" % LiteRules.cost(a)
		b.key = keys[i]
		b.accent = LiteGlyphs.YELLOW
		b.tooltip_text = STRIKE_TIPS[i]
		b.clicked = func() -> void: main.select_strike(a)
		_strike[i] = b
		row.add_child(b)
	row = _row(vb)
	var salvo_label:= Label.new()
	salvo_label.text = "Salvo"
	salvo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	salvo_label.custom_minimum_size = Vector2(46, 0)
	salvo_label.add_theme_color_override("font_color", LiteGlyphs.MUTED)
	salvo_label.add_theme_font_size_override("font_size", 12)
	row.add_child(salvo_label)
	for i in 3:
		var n: int = SALVOS[i]
		var c:= LiteChip.new()
		c.text = "%d×" % n
		c.accent = LiteGlyphs.YELLOW
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.tooltip_text = "Launch %d at each click" % n
		c.clicked = func() -> void:
			main.salvo = n
			main.audio.click()
		_salvo[i] = c
		row.add_child(c)
	_sam_toggle = LiteChip.new()
	_sam_toggle.text = ""
	_sam_toggle.tooltip_text = "SAM interceptors cost $10 each, about what a drone costs. Switch off to leave drones to the guns."
	_sam_toggle.font_size = 11
	_sam_toggle.clicked = func() -> void:
		main.sim.sams_on_drones[0] = not main.sim.sams_on_drones[0]
		main.audio.click()
	vb.add_child(_sam_toggle)

	vb.add_child(_section("FEED", ""))

	var scroll:= ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.custom_minimum_size = Vector2(0, 40)
	vb.add_child(scroll)
	_feed = VBoxContainer.new()
	_feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feed.add_theme_constant_override("separation", 5)
	scroll.add_child(_feed)

	row = _row(vb)
	var menu:= LiteChip.new()
	menu.text = "Menu"
	menu.tooltip_text = "Menu and settings (Esc)"
	menu.custom_minimum_size = Vector2(58, 28)
	menu.clicked = func() -> void:
		show_menu()
		main.audio.click()
	row.add_child(menu)
	var stats:= LiteChip.new()
	stats.text = "Stats"
	stats.tooltip_text = "War statistics and attack reports (T)"
	stats.custom_minimum_size = Vector2(52, 28)
	stats.clicked = func() -> void:
		show_stats()
		main.audio.click()
	row.add_child(stats)
	var speed_text: Array[String] = ["II", "1×", "2×", "3×"]
	for i in 4:
		var s: float = SPEEDS[i]
		var c:= LiteChip.new()
		c.text = speed_text[i]
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.tooltip_text = "Pause (Space)" if s == 0 else "Speed %s×" % str(int(s))
		c.clicked = func() -> void:
			main.set_speed(s)
			main.audio.click()
		_speed[i] = c
		row.add_child(c)

	_menu = _build_menu(root)
	_new_game = _build_new_game(root)
	_settings = _build_settings(root)
	_campaign = _build_campaign(root)
	_briefing = _build_briefing(root)
	_front = _build_front(root)
	_loading = _build_loading(root)
	_debrief = _build_debrief(root)
	_end = _build_end(root)
	stats_view = LiteStatsView.new()
	stats_view.main = main
	root.add_child(stats_view)
	tutorial = LiteTutorial.new()
	tutorial.main = main
	root.add_child(tutorial)

static func _row(parent: Control) -> HBoxContainer:
	var row:= HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	return row

static func _section(title: String, hint: String) -> Control:
	var row:= HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 16)
	var t:= Label.new()
	t.text = title
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_override("font", LiteGlyphs.bold)
	t.add_theme_font_size_override("font_size", 10)
	t.add_theme_color_override("font_color", LiteGlyphs.MUTED)
	row.add_child(t)
	var h:= Label.new()
	h.text = hint
	h.add_theme_font_size_override("font_size", 10)
	h.add_theme_color_override("font_color", LiteGlyphs.FAINT)
	row.add_child(h)
	return row

static func _make_theme() -> Theme:
	var t:= Theme.new()
	t.default_font = LiteGlyphs.font
	t.default_font_size = 13
	t.set_stylebox("panel", "TooltipPanel", LiteGlyphs.box(Color(LiteGlyphs.PANEL, 0.98), LiteGlyphs.LINE, 7, 8))
	t.set_color("font_color", "TooltipLabel", LiteGlyphs.TEXT)
	t.set_font_size("font_size", "TooltipLabel", 12)
	t.set_color("font_color", "Label", LiteGlyphs.TEXT)
	t.set_stylebox("normal", "Button", LiteGlyphs.box(LiteGlyphs.OURS, LiteGlyphs.OURS, 9, 10))
	t.set_stylebox("hover", "Button", LiteGlyphs.box(LiteGlyphs.OURS.lightened(0.12), LiteGlyphs.OURS.lightened(0.12), 9, 10))
	t.set_stylebox("pressed", "Button", LiteGlyphs.box(LiteGlyphs.OURS.darkened(0.15), LiteGlyphs.OURS, 9, 10))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_font("font", "Button", LiteGlyphs.bold)
	t.set_font_size("font_size", "Button", 15)
	return t

func _overlay(root: Control, width: float) -> Array:
	var o:= Control.new()
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	o.visible = false
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim:= ColorRect.new()
	dim.color = Color(LiteGlyphs.PAGE, 0.8)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.add_child(dim)
	var center:= CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.add_child(center)
	var panel:= PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.add_theme_stylebox_override("panel", LiteGlyphs.box(LiteGlyphs.PANEL, LiteGlyphs.LINE, 16, 26))
	center.add_child(panel)
	var box:= VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	root.add_child(o)
	return [o, box]

static func _text(s: String, size: int, col: Color, bold: bool = false) -> Label:
	var l:= Label.new()
	l.text = s
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", LiteGlyphs.bold)
	return l

func _wide(parent: Control, text: String, primary: bool, pressed: Callable) -> Button:
	var b:= Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44 if primary else 40)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_quiet(b, not primary)
	b.pressed.connect(func() -> void:
		main.audio.click()
		pressed.call())
	parent.add_child(b)
	return b

static func _quiet(b: Button, quiet: bool) -> void:
	for st: String in ["normal", "hover", "pressed"]:
		b.remove_theme_stylebox_override(st)
	for st: String in ["font_color", "font_hover_color"]:
		b.remove_theme_color_override(st)
	if not quiet:
		return
	b.add_theme_stylebox_override("normal", LiteGlyphs.box(LiteGlyphs.PANEL_HI, LiteGlyphs.LINE, 9, 10))
	b.add_theme_stylebox_override("hover", LiteGlyphs.box(LiteGlyphs.PANEL_HI.lightened(0.06), LiteGlyphs.MUTED, 9, 10))
	b.add_theme_stylebox_override("pressed", LiteGlyphs.box(LiteGlyphs.PANEL, LiteGlyphs.MUTED, 9, 10))
	b.add_theme_color_override("font_color", LiteGlyphs.TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)

static func _title(box: VBoxContainer, title: String) -> void:
	var head:= _text("STRIKE ALERT", 12, LiteGlyphs.ENEMY, true)
	head.add_theme_font_override("font", LiteGlyphs.black)
	box.add_child(head)
	var t:= _text(title, 34, LiteGlyphs.TEXT, true)
	t.add_theme_font_override("font", LiteGlyphs.black)
	box.add_child(t)

## The home screen (and the pause menu): see LiteHome.
func _build_menu(root: Control) -> Control:
	home = LiteHome.new()
	home.main = main
	home.visible = false
	root.add_child(home)
	home.build()
	home.on_continue = close_menu
	home.on_new_war = func() -> void: _show_screen(_new_game)
	home.on_campaign = show_campaign
	home.on_settings = func() -> void: _show_screen(_settings)
	home.on_quit = func() -> void: main.get_tree().quit()
	return home

func _build_new_game(root: Control) -> Control:
	var ob: Array = _overlay(root, 500)
	var o: Control = ob[0]
	var box: VBoxContainer = ob[1]
	_title(box, "New war")
	box.add_child(_text(
		"Hold the sky over your country and strike back.\n\n" +
		"•  Factories earn the money and repair your capital. Under air alert they slow down.\n" +
		"•  AA guns and SAMs shoot down drones and missiles flying into range.\n" +
		"•  The enemy's sites are hidden: send drones to find them, missiles to destroy them.\n" +
		"•  Its capital heals while its factories work: hit them, and the air defence guarding them, first.\n" +
		"•  Destroy the enemy capital before it destroys yours.",
		13, LiteGlyphs.MUTED))
	var row: HBoxContainer = _row(box)
	var names: Array[String] = ["Easy", "Normal", "Hard"]
	for i in 3:
		var d: int = i
		var c:= LiteChip.new()
		c.text = names[i]
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.custom_minimum_size = Vector2(0, 32)
		c.clicked = func() -> void:
			LiteSettings.difficulty = d
			LiteSettings.save()
			main.audio.click()
		_diff[i] = c
		row.add_child(c)
	_wide(box, "Start", true, func() -> void:
		_show_screen(null)
		main.new_game())
	_wide(box, "Back", false, func() -> void: _show_screen(_menu))
	box.add_child(_text("1 2 3 build  ·  Q W E strike  ·  T statistics  ·  Space pause  ·  F11 fullscreen  ·  Esc cancel or menu", 11, LiteGlyphs.FAINT))
	return o

func _build_settings(root: Control) -> Control:
	var ob: Array = _overlay(root, 460)
	var o: Control = ob[0]
	var box: VBoxContainer = ob[1]
	_title(box, "Settings")
	_choice(box, "Sound", ["Off", "Low", "Medium", "High"], _volume, func(i: int) -> void:
		LiteSettings.volume = i
		LiteSettings.apply_sound())
	_choice(box, "Window", ["Windowed", "Fullscreen"], _window, func(i: int) -> void:
		LiteSettings.fullscreen = i == 1
		LiteSettings.apply_window())
	_choice(box, "Weapon routes", ["Shown", "Hidden"], _routes, func(i: int) -> void: LiteSettings.routes = i == 0)
	_choice(box, "Air defence ranges", ["Shown", "Hidden"], _ranges, func(i: int) -> void: LiteSettings.ranges = i == 0)
	var tips: Dictionary = {}
	tips["button"] = _wide(box, "Show the tips again", false, func() -> void:
		LiteSettings.tips_war = false
		LiteSettings.tips_front = false
		LiteSettings.save()
		(tips["button"] as Button).text = "The tips will show in your next war")
	_wide(box, "Back", false, func() -> void: _show_screen(_menu))
	return o

func _choice(box: VBoxContainer, label: String, options: Array[String], chips: Array[LiteChip], pick: Callable) -> void:
	var row: HBoxContainer = _row(box)
	var l:= Label.new()
	l.text = label
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(140, 0)
	l.add_theme_color_override("font_color", LiteGlyphs.MUTED)
	row.add_child(l)
	for i in options.size():
		var k: int = i
		var c:= LiteChip.new()
		c.text = options[i]
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.custom_minimum_size = Vector2(0, 30)
		c.clicked = func() -> void:
			pick.call(k)
			LiteSettings.save()
			main.audio.click()
		chips[i] = c
		row.add_child(c)

func _build_end(root: Control) -> Control:
	var ob: Array = _overlay(root, 420)
	var o: Control = ob[0]
	var box: VBoxContainer = ob[1]
	_end_title = _text("", 34, LiteGlyphs.TEXT, true)
	_end_text = _text("", 13, LiteGlyphs.MUTED)
	box.add_child(_end_title)
	box.add_child(_end_text)
	_wide(box, "New war", true, func() -> void:
		_end.visible = false
		_show_screen(_new_game))
	_wide(box, "Statistics", false, func() -> void: show_stats())
	_wide(box, "Main menu", false, func() -> void:
		_end.visible = false
		show_menu())
	return o

func _build_campaign(root: Control) -> Control:
	var ob: Array = _overlay(root, 500)
	var o: Control = ob[0]
	var box: VBoxContainer = ob[1]
	_title(box, "Campaign")
	box.add_child(_text(
		"One war, fought province by province.\n\n" +
		"•  Between operations you see the front, and choose which enemy province to attack next.\n" +
		"•  Each operation is fought on that province's own map, district by district, against its targets: depots, radars, drone launch sites, factories.\n" +
		"•  Take a province and what it was works for you: its industry, its depots, or the air base the enemy loses.\n" +
		"•  Now and then the enemy strikes back at one of yours, and it has to be held.\n" +
		"•  Take the enemy's capital province to win; lose yours and the war is lost.",
		13, LiteGlyphs.MUTED))
	var row: HBoxContainer = _row(box)
	var names: Array[String] = ["Easy", "Normal", "Hard"]
	for i in 3:
		var d: int = i
		var c:= LiteChip.new()
		c.text = names[i]
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.custom_minimum_size = Vector2(0, 32)
		c.tooltip_text = "For a new campaign; one under way keeps its own"
		c.clicked = func() -> void:
			LiteSettings.difficulty = d
			LiteSettings.save()
			main.audio.click()
		_cdiff[i] = c
		row.add_child(c)
	_campaign_go = _wide(box, "Continue", true, func() -> void:
		_show_screen(null)
		main.start_campaign(false))
	_campaign_new = _wide(box, "New campaign", true, func() -> void:
		_show_screen(null)
		main.start_campaign(true))
	_wide(box, "Back", false, func() -> void: _show_screen(_menu))
	return o

func show_campaign() -> void:
	var saved: LiteCampaign = LiteCampaign.load_saved()
	_campaign_go.visible = saved != null
	if saved != null:
		_campaign_go.text = "Continue · operation %d" % (saved.ops + 1)
	_quiet(_campaign_new, saved != null)
	_campaign_new.text = "New campaign" if saved == null else "Start over"
	_show_screen(_campaign)

## The front between a campaign's operations: a panel on the right, over
## the war panel's place, the map left free to pick provinces on.
func _build_front(root: Control) -> Control:
	var panel:= PanelContainer.new()
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.anchor_left = 1; panel.anchor_right = 1; panel.anchor_top = 0; panel.anchor_bottom = 1
	panel.offset_left = -330; panel.offset_right = -10; panel.offset_top = 10; panel.offset_bottom = -10
	panel.add_theme_stylebox_override("panel", LiteGlyphs.box(LiteGlyphs.PANEL, LiteGlyphs.OBJECTIVE.darkened(0.3), 14, 18))
	var scroll:= ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_front_box = VBoxContainer.new()
	_front_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_front_box.add_theme_constant_override("separation", 9)
	scroll.add_child(_front_box)
	root.add_child(panel)
	return panel

func show_front(c: LiteCampaign) -> void:
	for n: Node in _front_box.get_children():
		_front_box.remove_child(n)
		n.queue_free()
	var box: VBoxContainer = _front_box
	var war: LiteMap = main.war_map
	var head:= _text("OPERATION %d OF %d  ·  %s" % [c.ops + 1, LiteCampaign.MAX_OPS, main.clock_text(0.0, true).to_upper()], 11, LiteGlyphs.OBJECTIVE, true)
	head.add_theme_font_override("font", LiteGlyphs.black)
	box.add_child(head)
	var holding: bool = c.counter >= 0
	var t:= _text("Hold the line" if holding else "Next operation", 26, LiteGlyphs.TEXT, true)
	t.add_theme_font_override("font", LiteGlyphs.black)
	box.add_child(t)
	if holding:
		box.add_child(_text("The enemy is attacking %s." % c.group_name(war, c.counter), 12, LiteGlyphs.ENEMY))
	var d: int = c.capital_defence(war)
	box.add_child(_text("%s: %d SAM batteries. Each region round it you take removes one." % [war.capital_name[1], d], 11, LiteGlyphs.MUTED))
	for id: int in main.front_options:
		var picked: bool = id == main.front_pick
		var kind: String = "Defend" if war.regions[id].side == 0 else ("Capital" if id == c.group_at(war.capital_province(1)) else LiteMission.character_short(c.character(id)))
		var label: String = "%s  ·  %s" % [c.group_name(war, id), kind]
		var pid: int = id
		var b: Button = _wide(box, label, picked, func() -> void: main.pick_front(pid))
		b.custom_minimum_size = Vector2(0, 36)
		b.add_theme_font_size_override("font_size", 13)
	if main.front_pick >= 0:
		var m: LiteMission = c.make_op(war, main.front_pick)
		box.add_child(_section(m.title.to_upper(), ""))
		box.add_child(_text(m.summary(), 12, LiteGlyphs.TEXT))
		if m.kind == LiteMission.STRIKE:
			box.add_child(LiteIconList.of_kinds(LiteMission.target_kinds(m.character)))
			box.add_child(_text("Reward: " + LiteMission.character_gain(m.character), 12, LiteGlyphs.GOOD))
		_wide(box, "Launch operation", true, main.launch_operation)
	_wide(box, "Main menu", false, func() -> void:
		close_front()
		main.to_title())
	_front.visible = true

func close_front() -> void:
	_front.visible = false

## A notice over everything while an operation's map is built.
func _build_loading(root: Control) -> Control:
	var ob: Array = _overlay(root, 420)
	_loading_text = _text("", 16, LiteGlyphs.TEXT, true)
	(ob[1] as VBoxContainer).add_child(_loading_text)
	(ob[1] as VBoxContainer).add_child(_text("Drawing the province's map and its districts…", 12, LiteGlyphs.MUTED))
	return ob[0]

func show_loading(text: String) -> void:
	_loading_text.text = text
	_loading.visible = true

func close_loading() -> void:
	_loading.visible = false

## The first-time tips for a war (and an operation's goal in the campaign).
func tips_war() -> void:
	if LiteSettings.tips_war or tutorial.running:
		return
	var m: LiteMission = main.mission
	var cap: Vector2 = main.to_screen(main.sim.sides[0].capital.pos)
	var steps: Array = []
	steps.append(["Your country", "Defend it from drones and missiles. Destroy the enemy capital to win." if m == null
		else "Defend it, and destroy the ringed targets before time runs out.",
		func() -> Rect2: return Rect2(cap - Vector2(26, 26), Vector2(52, 52)), null, ""])
	if m != null:
		steps.append(["The goal", "Targets, time left and events are here.",
			func() -> Rect2: return _op_card.get_global_rect(), null, ""])
	steps.append(["Factories", "They earn money. Build them on the green squares.",
		func() -> Rect2: return _build[0].get_global_rect(),
		func() -> void: main.build_tool = LiteKind.FACTORY, ""])
	steps.append(["Air defence", "AA guns and SAMs shoot down what flies into their circle.",
		func() -> Rect2: return _build[1].get_global_rect().merge(_build[2].get_global_rect()), null, ""])
	steps.append(["Strike back", "Pick a weapon, then click enemy land. Hold and drag to draw its route.",
		func() -> Rect2: return _strike[0].get_global_rect().merge(_strike[2].get_global_rect()), null, "route"])
	steps.append(["Air alerts", "Yellow: drones overhead. Red: missiles. Factories slow down under alert.",
		func() -> Rect2: return Rect2(LiteMap.W / 2.0 - 120, 14, 240, 54), null, ""])
	steps.append(["Time", "Space pauses. 1×, 2× and 3× set the speed.",
		func() -> Rect2: return _speed[0].get_global_rect().merge(_speed[3].get_global_rect()), null, ""])
	tutorial.run(steps, func() -> void:
		LiteSettings.tips_war = true
		LiteSettings.save())

## The first-time tips for the campaign's front.
func tips_front() -> void:
	if LiteSettings.tips_front or tutorial.running:
		return
	var war: LiteMap = main.war_map
	var cap: Vector2 = main.to_screen(war.regions[war.capital_province(1)].label)
	var steps: Array = [
		["The front", "Pick the next region to attack, here or on the map. Its badge shows what is there.",
			func() -> Rect2: return _front.get_global_rect(), null, ""],
		["The enemy capital", "Taking it wins the war. Each region round it you take removes one of its SAM batteries.",
			func() -> Rect2: return Rect2(cap - Vector2(30, 30), Vector2(60, 60)), null, ""],
	]
	tutorial.run(steps, func() -> void:
		LiteSettings.tips_front = true
		LiteSettings.save())

## A side overlay over the panel, leaving the map in view: the briefing and the
## debrief, so the province fought over can be seen on the map beside them.
func _side_overlay(root: Control) -> Array:
	var o:= Control.new()
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	o.visible = false
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim:= ColorRect.new()
	dim.color = Color(LiteGlyphs.PAGE, 0.25)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.add_child(dim)
	var panel:= PanelContainer.new()
	panel.anchor_left = 1; panel.anchor_right = 1; panel.anchor_top = 0.5; panel.anchor_bottom = 0.5
	panel.offset_left = -430; panel.offset_right = -10
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override("panel", LiteGlyphs.box(LiteGlyphs.PANEL, LiteGlyphs.OBJECTIVE.darkened(0.3), 16, 24))
	o.add_child(panel)
	var box:= VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	root.add_child(o)
	return [o, box]

func _build_briefing(root: Control) -> Control:
	var ob: Array = _side_overlay(root)
	_brief_box = ob[1]
	return ob[0]

func show_briefing(m: LiteMission, c: LiteCampaign) -> void:
	for n: Node in _brief_box.get_children():
		_brief_box.remove_child(n)
		n.queue_free()
	var box: VBoxContainer = _brief_box
	var head:= _text("OPERATION %d  ·  %s" % [m.number, main.clock_text(0.0, true).to_upper()], 11, LiteGlyphs.OBJECTIVE, true)
	head.add_theme_font_override("font", LiteGlyphs.black)
	box.add_child(head)
	var t:= _text(m.title, 28, LiteGlyphs.TEXT, true)
	t.add_theme_font_override("font", LiteGlyphs.black)
	box.add_child(t)
	box.add_child(_text(m.summary(), 14, LiteGlyphs.TEXT))
	if m.kind != LiteMission.HOLD:
		var kinds: Array[int] = []
		for b: LiteBuilding in m.targets:
			kinds.append(b.kind)
		box.add_child(LiteIconList.of_kinds(kinds))
	if m.kind == LiteMission.STRIKE:
		box.add_child(_text("Reward: " + LiteMission.character_gain(m.character), 12, LiteGlyphs.GOOD))
	if m.optional != LiteMission.NONE:
		box.add_child(_text("Optional: " + m.optional_text(true), 12, LiteGlyphs.MUTED))
	_wide(box, "Begin", true, main.launch_mission)
	_briefing.visible = true

func close_briefing() -> void:
	_briefing.visible = false

func _build_debrief(root: Control) -> Control:
	var ob: Array = _side_overlay(root)
	var o: Control = ob[0]
	var box: VBoxContainer = ob[1]
	_debrief_title = _text("", 30, LiteGlyphs.TEXT, true)
	_debrief_title.add_theme_font_override("font", LiteGlyphs.black)
	_debrief_text = _text("", 13, LiteGlyphs.MUTED)
	box.add_child(_debrief_title)
	box.add_child(_debrief_text)
	_debrief_next = _wide(box, "Back to the front", true, main.next_mission)
	_wide(box, "Statistics", false, func() -> void: show_stats())
	_wide(box, "Main menu", false, func() -> void:
		_debrief.visible = false
		main.to_title())
	return o

func show_debrief(m: LiteMission, title: String, text: String, last: bool, good: bool) -> void:
	_debrief_title.text = title
	_debrief_title.add_theme_color_override("font_color", LiteGlyphs.GOOD if good else LiteGlyphs.ENEMY)
	_debrief_text.text = text
	_debrief_next.visible = not last
	_debrief.visible = true

func close_debrief() -> void:
	_debrief.visible = false

## The home screen stays behind New war and Settings (their dim lies over it).
func _show_screen(screen: Control) -> void:
	_menu.visible = screen != null
	_new_game.visible = screen == _new_game
	_settings.visible = screen == _settings
	_campaign.visible = screen == _campaign
	# The front panel shows again once the menus are closed.
	if _front != null:
		_front.visible = screen == null and main.front_open

func show_menu() -> void:
	if main.started and main.sim.winner >= 0:
		main.to_title()          # after a war ends, back to the home screen's own war
		return
	var live: bool = main.started or main.front_open
	var sub: String = "A real-time air war on a live air-alert map."
	if main.front_open:
		sub = "Campaign · at the front · %s" % main.clock_text(0.0, true)
	elif live and main.mission != null:
		sub = "Campaign, operation %d: %s · paused · %s" % [main.mission.number, main.mission.title, main.clock_text(main.sim.time, true)]
	elif live:
		sub = "The war is paused · %s" % main.clock_text(main.sim.time, true)
	home.set_live(live, sub)
	_end.visible = false
	_show_screen(_menu)

## Enter: Start on the New war screen, the leading item on the home screen.
func enter() -> void:
	if briefing_open:
		main.launch_mission()
	elif _campaign.visible:
		_show_screen(null)
		main.start_campaign(not _campaign_go.visible)
	elif _new_game.visible:
		_show_screen(null)
		main.new_game()
	elif _menu.visible and not _settings.visible:
		home.activate_primary()

func show_settings() -> void:
	_show_screen(_settings)

func close_menu() -> void:
	_show_screen(null)

func show_stats(tab: int = 0) -> void:
	if main.started:
		stats_view.open(tab)

func back() -> void:
	if stats_view.visible:
		stats_view.visible = false
	elif _new_game.visible or _settings.visible or _campaign.visible:
		_show_screen(_menu)
	elif _menu.visible and (main.started or main.front_open) and main.sim.winner < 0:
		close_menu()

func show_end(won: bool, stats: String) -> void:
	_end_title.text = "Victory" if won else "Defeat"
	_end_title.add_theme_color_override("font_color", LiteGlyphs.GOOD if won else LiteGlyphs.ENEMY)
	_end_text.text = stats
	_show_screen(null)
	_end.visible = true

func clear_feed() -> void:
	for c: Node in _feed.get_children():
		c.queue_free()

func post(text: String, tone: Color) -> void:
	var card:= PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box: StyleBoxFlat = LiteGlyphs.box(Color(LiteGlyphs.PANEL_HI, 0.7), tone, 7)
	box.border_width_top = 0
	box.border_width_right = 0
	box.border_width_bottom = 0
	box.border_width_left = 3
	box.content_margin_left = 10; box.content_margin_right = 8; box.content_margin_top = 6; box.content_margin_bottom = 7
	card.add_theme_stylebox_override("panel", box)
	var vb:= VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.add_child(_text(main.stamp(main.sim.time), 10, LiteGlyphs.FAINT))
	vb.add_child(_text(text, 12, LiteGlyphs.TEXT))
	card.add_child(vb)
	card.modulate = Color(1, 1, 1, 0)
	_feed.add_child(card)
	_feed.move_child(card, 0)
	card.create_tween().tween_property(card, "modulate:a", 1.0, 0.35)
	while _feed.get_child_count() > 8:
		var old: Node = _feed.get_child(_feed.get_child_count() - 1)
		_feed.remove_child(old)
		old.queue_free()

func _process(_delta: float) -> void:
	if main.sim == null:
		return
	var me: LiteSide = main.sim.sides[0]
	for i in 3:
		_build[i].selected = main.build_tool == BUILD_KINDS[i]
		var price: int = main.sim.cost(0, BUILD_KINDS[i])
		_build[i].affordable = me.money >= price
		_build[i].price = "$%d" % price
		_strike[i].selected = main.strike_tool == ARMS[i]
		_strike[i].affordable = me.money >= LiteRules.cost(ARMS[i])
		_salvo[i].selected = main.salvo == SALVOS[i]
		_diff[i].selected = LiteSettings.difficulty == i
		_cdiff[i].selected = LiteSettings.difficulty == i
	for i in 4:
		_volume[i].selected = LiteSettings.volume == i
	# The browser can leave fullscreen on its own (its Esc): follow it.
	var mode: int = DisplayServer.window_get_mode()
	LiteSettings.fullscreen = mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	for i in 2:
		_window[i].selected = LiteSettings.fullscreen == (i == 1)
		_routes[i].selected = LiteSettings.routes == (i == 0)
		_ranges[i].selected = LiteSettings.ranges == (i == 0)
	_panel.visible = main.started and not home_open
	var m: LiteMission = main.mission
	_withdraw.visible = m != null and main.started and m.result < 0 and not m.timed
	if not _withdraw.visible:
		_withdraw.text = "Withdraw"
	hud.visible = not home_open
	for i in 4:
		_speed[i].selected = main.paused if i == 0 else (not main.paused and main.speed == SPEEDS[i])
	var on: bool = main.sim.sams_on_drones[0]
	_sam_toggle.text = "SAMs fire at drones: ON" if on else "SAMs fire at drones: OFF (guns only)"
	_sam_toggle.selected = on
