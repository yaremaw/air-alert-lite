class_name LiteUi
extends CanvasLayer

var main: LiteMain = null
var hud: LiteHud = null
var stats_view: LiteStatsView = null
var _build: Array[LiteToolButton] = [null, null, null, null, null, null]
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
## The achievements page (LiteAchievementsView), from the home screen.
var achievements: LiteAchievementsView = null
var _end_title: Label = null
var _end_text: Label = null
var _end_stats: Button = null
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
## Map theme hooks (src/Lite/command/): the Settings choice, and the feed's
## news for the command interface's event log.
var _theme: Array[LiteChip] = [null, null]
signal posted(text: String, tone: Color)
signal feed_cleared

var menu_open: bool:
	get: return _menu.visible or _new_game.visible or _settings.visible or stats_view.visible or briefing_open or _debrief.visible

## The home screen or one of the screens it opens (New war, Settings).
var home_open: bool:
	get: return _menu.visible or _new_game.visible or _settings.visible or _campaign.visible

var briefing_open: bool:
	get: return _briefing != null and _briefing.visible

var debrief_open: bool:
	get: return _debrief != null and _debrief.visible

const BUILD_KINDS: Array[int] = [LiteKind.FACTORY, LiteKind.REFINERY, LiteKind.GUN, LiteKind.SAM, LiteKind.RADAR]
const ARMS: Array[int] = [LiteArm.DRONE, LiteArm.CRUISE, LiteArm.BALLISTIC]
const SALVOS: Array[int] = [1, 3, 10]
const SPEEDS: Array[float] = [0.0, 1.0, 2.0, 3.0]

const BUILD_TIPS: Array[String] = [
	"Factory: +$4/s and repairs the capital. Built into a region with room for it; the front has more room than the rear. Each one costs $20 more than the last. While its region is under air alert the workers shelter and it runs at half its pace.",
	"AA gun: cheap and short-ranged. Shoots at drones, now and then hits a cruise missile. Its shells cost nothing.",
	"SAM: long range. Hits drones, cruise and ballistic missiles; after a shot at a ballistic missile it reloads for a few seconds. Every interceptor costs $10.",
]
const STRIKE_TIPS: Array[String] = [
	"Attack drone: slow and cheap, wanders on its way. Reveals enemy sites it flies over. 1 damage.",
	"Cruise missile: fast and accurate, launched from deep inside our country. 2 damage.",
	"Ballistic missile: a high, fast arc; nobody knows where it lands until its final dive. Only SAMs can stop it, and each shot ties a SAM up while it reloads. 3 damage.",
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
	for i in BUILD_KINDS.size():
		if i == 3:
			row = _row(vb)
		var k: int = BUILD_KINDS[i]
		var b:= LiteToolButton.new()
		b.glyph = LiteGlyphs.of(k)
		b.title = ["Factory", "Refinery", "AA gun", "SAM", "Radar"][i]
		b.price = "$%d" % LiteRules.cost_kind(k)
		b.key = "%d" % (i + 1)
		b.tooltip_text = LiteCmdUi.BUILD_TIPS[i]
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
	_build_page(root)
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
	campaign_end = LiteCampaignEnd.new()
	campaign_end.main = main
	root.add_child(campaign_end)
	campaign_end.build()
	# The web build first asks: play here, or download the game?
	if OS.has_feature("web") or "--lite-webgate" in OS.get_cmdline_user_args():
		var gate:= LiteWebGate.new()
		gate.main = main
		root.add_child(gate)
	slides = LiteSlides.new()
	root.add_child(slides)
	slides.build()

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
	# Map theme hook: buttons in the command look: a deep blue face, a bright
	# edge, square corners.
	var face: Color = LiteGlyphs.OURS
	var hi: Color = LiteGlyphs.OURS.lightened(0.12)
	var lo: Color = LiteGlyphs.OURS.darkened(0.15)
	if LiteTheme.command:
		face = LiteTheme.BLUE.darkened(0.5)
		hi = LiteTheme.BLUE.darkened(0.38)
		lo = LiteTheme.BLUE.darkened(0.62)
	t.default_font = LiteGlyphs.font
	t.default_font_size = 13
	t.set_stylebox("panel", "TooltipPanel", LiteGlyphs.box(Color(LiteGlyphs.PANEL, 0.98), LiteGlyphs.LINE, 7, 8))
	t.set_color("font_color", "TooltipLabel", LiteGlyphs.TEXT)
	t.set_font_size("font_size", "TooltipLabel", 12)
	t.set_color("font_color", "Label", LiteGlyphs.TEXT)
	var edge: Color = LiteTheme.BLUE if LiteTheme.command else LiteGlyphs.OURS
	t.set_stylebox("normal", "Button", LiteGlyphs.box(face, edge if LiteTheme.command else face, 9, 10))
	t.set_stylebox("hover", "Button", LiteGlyphs.box(hi, edge if LiteTheme.command else hi, 9, 10))
	t.set_stylebox("pressed", "Button", LiteGlyphs.box(lo, edge, 9, 10))
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
	dim.color = LiteTheme.ui(Color(LiteGlyphs.PAGE, 0.8))
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

## A full-screen screen (phase 4): `pic` over the whole screen, dark at the
## left where its words and buttons stand on a translucent plate, bottom left.
func _full_overlay(root: Control, pic: Texture2D, right: bool = false) -> Array:
	var o:= Control.new()
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	o.visible = false
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back:= ColorRect.new()
	back.color = Color(0.03, 0.04, 0.07, 1.0)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.add_child(back)
	var art:= TextureRect.new()
	art.texture = pic
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.add_child(art)
	var shade:= TextureRect.new()
	var g:= Gradient.new()
	g.set_color(0, Color(0.02, 0.03, 0.05, 0.92))
	g.set_color(1, Color(0.02, 0.03, 0.05, 0.0))
	var gt:= GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	gt.width = 64
	gt.height = 4
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.anchor_right = 0.75; shade.anchor_bottom = 1
	if right:
		# The words on the right, the picture's subject left clear.
		shade.flip_h = true
		shade.anchor_left = 0.25; shade.anchor_right = 1
	o.add_child(shade)
	var foot:= TextureRect.new()
	var fg:= Gradient.new()
	fg.set_color(0, Color(0.02, 0.03, 0.05, 0.0))
	fg.set_color(1, Color(0.02, 0.03, 0.05, 0.85))
	var ft:= GradientTexture2D.new()
	ft.gradient = fg
	ft.fill_to = Vector2(0, 1)
	ft.width = 4
	ft.height = 64
	foot.texture = ft
	foot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	foot.stretch_mode = TextureRect.STRETCH_SCALE
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.anchor_top = 0.45; foot.anchor_right = 1; foot.anchor_bottom = 1
	o.add_child(foot)
	var panel:= PanelContainer.new()
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.anchor_left = 0; panel.anchor_top = 1; panel.anchor_bottom = 1
	panel.offset_left = 80; panel.offset_right = 80 + 460; panel.offset_bottom = -64
	if right:
		panel.anchor_left = 1; panel.anchor_right = 1
		panel.offset_left = -80 - 460; panel.offset_right = -80
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	o.add_child(panel)
	var box:= VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	root.add_child(o)
	return [o, box]

static func _text(s: String, size: int, col: Color, bold: bool = false) -> Label:
	var l:= Label.new()
	l.text = s
	# Map theme hook: the command look's colours.
	col = LiteTheme.ui(col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", LiteGlyphs.bold)
	return l

func _wide(parent: Control, text: String, primary: bool, pressed: Callable) -> Button:
	var b:= Button.new()
	b.text = text.to_upper() if LiteTheme.command else text
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

## A short line and a "?" that opens the full description under it.
func _explain(box: VBoxContainer, text: String) -> void:
	var lines: PackedStringArray = text.split("\n")
	var row:= HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var short: Label = _text(lines[0], 14, LiteGlyphs.MUTED)
	short.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(short)
	var full: Label = _text(text.substr(lines[0].length()).strip_edges(), 13, LiteGlyphs.MUTED)
	full.visible = false
	var q:= LiteChip.new()
	q.text = "?"
	q.font_size = 15
	q.custom_minimum_size = Vector2(32, 30)
	q.tooltip_text = "How it works"
	q.clicked = func() -> void:
		full.visible = not full.visible
		q.selected = full.visible
		main.audio.click()
	row.add_child(q)
	box.add_child(full)

static func _title(box: VBoxContainer, title: String, kicker: bool = true) -> void:
	var cmd: bool = LiteTheme.command
	if kicker:
		var head:= _text("STRIKE ALERT  //  COMMAND" if cmd else "STRIKE ALERT", 12, LiteGlyphs.ENEMY, true)
		head.add_theme_font_override("font", LiteGlyphs.black)
		box.add_child(head)
	var t:= _text(title.to_upper() if cmd else title, 30 if cmd else 34, LiteGlyphs.TEXT, true)
	t.add_theme_font_override("font", LiteGlyphs.black)
	box.add_child(t)
	if cmd:
		box.add_child(_Rule.new())

## A full-screen screen's title: big, over the picture, its shadow under it.
static func _big_title(box: VBoxContainer, title: String) -> void:
	var t:= _text(title.to_upper() if LiteTheme.command else title, 54, LiteGlyphs.TEXT, true)
	t.add_theme_font_override("font", LiteGlyphs.black)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	t.add_theme_constant_override("shadow_offset_y", 3)
	box.add_child(t)

## Under a dialog's title in the command look: a hatched band, as on the
## map's alerts, ended by a small red block.
class _Rule extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(0, 6)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r:= Rect2(Vector2.ZERO, Vector2(size.x - 14, 6))
		draw_rect(r, Color(LiteTheme.BORDER, 0.35))
		LiteCmdStyle.hatch(self, r, Color(LiteTheme.MUTED, 0.45), 5.0)
		draw_rect(Rect2(size.x - 10, 0, 10, 6), LiteTheme.RED)

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
	achievements = LiteAchievementsView.new()
	achievements.main = main
	root.add_child(achievements)
	home.on_achievements = func() -> void:
		main.audio.click()
		achievements.open()
	arsenal = LiteArsenalView.new()
	arsenal.main = main
	root.add_child(arsenal)
	home.on_arsenal = func() -> void:
		main.audio.click()
		arsenal.open()
	home.on_quit = func() -> void: main.get_tree().quit()
	return home

func _build_new_game(root: Control) -> Control:
	var ob: Array = _full_overlay(root, _art("war") if _art("war") != null else LiteStory.image("military"), true)
	var o: Control = ob[0]
	var box: VBoxContainer = ob[1]
	_big_title(box, "New war")
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
	_choice(box, "Map theme", ["Legacy", "Command"], _theme, func(i: int) -> void: LiteTheme.set_command(main, i == 1))
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
	var ob: Array = _overlay(root, 500)
	var o: Control = ob[0]
	var box: VBoxContainer = ob[1]
	# The victory or the defeat as a picture (assets/ui/story/victory, defeat).
	_end_pic = TextureRect.new()
	_end_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_end_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_end_pic.custom_minimum_size = Vector2(0, 200)
	_end_pic.clip_contents = true
	box.add_child(_end_pic)
	_end_title = _text("", 34, LiteGlyphs.TEXT, true)
	_end_title.add_theme_font_override("font", LiteGlyphs.black)
	_end_text = _text("", 13, LiteGlyphs.MUTED)
	box.add_child(_end_title)
	box.add_child(_end_text)
	_wide(box, "New war", true, func() -> void:
		_end.visible = false
		_show_screen(_new_game))
	_end_stats = _wide(box, "Statistics", false, func() -> void: show_stats())
	_wide(box, "Main menu", false, func() -> void:
		_end.visible = false
		show_menu())
	return o

func _build_campaign(root: Control) -> Control:
	var ob: Array = _full_overlay(root, _art("campaign"))
	var o: Control = ob[0]
	var box: VBoxContainer = ob[1]
	_big_title(box, "Campaign")
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
	if LiteTheme.command:
		_campaign_go.text = _campaign_go.text.to_upper()
		_campaign_new.text = _campaign_new.text.to_upper()
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

## Map theme hook: the command look's front (no side panel, LiteCmdFront).
func _cmd_front() -> bool:
	return LiteTheme.command and main.cmd_ui != null and main.cmd_ui.front != null

func show_front(c: LiteCampaign) -> void:
	if _cmd_front():
		_front.visible = false
		main.cmd_ui.front.show_front(c)
		return
	for n: Node in _front_box.get_children():
		_front_box.remove_child(n)
		n.queue_free()
	var box: VBoxContainer = _front_box
	var war: LiteMap = main.war_map
	var head:= _text("OPERATION %d  ·  %s" % [c.ops + 1, main.clock_text(0.0, true).to_upper()], 11, LiteGlyphs.OBJECTIVE, true)
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
	if c.capital_locked():
		box.add_child(_text("%s can be attacked once %d regions are taken (%d so far)." % [war.capital_name[1], LiteCampaign.CAPITAL_AFTER, c.taken[0]], 11, LiteGlyphs.YELLOW))
	box.add_child(_text("Weapons this operation: %s." % LiteCampaign.arms_text(LiteCampaign.arms_at(c.ops)), 11, LiteGlyphs.MUTED))
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
	if _cmd_front():
		main.cmd_ui.front.hide_front()

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
	var steps: Array = []
	var gun: LiteBuilding = null
	for bb: LiteBuilding in main.sim.buildings:
		if bb.alive and bb.side == 0 and (bb.kind == LiteKind.GUN or bb.kind == LiteKind.MOBILE):
			gun = bb
			break
	if m == null:
		steps.append(["Your country", "Defend it from drones and missiles. You win when the enemy's morale breaks: strike its capital, its oil and its factories.",
			func() -> Rect2: return Rect2(main.to_screen(main.sim.sides[0].capital.pos) - Vector2(26, 26), Vector2(52, 52)), null, ""])
	else:
		steps.append(["The task", "Each operation has one task, here under the top bar, with how it stands. No morale here: just the task.",
			func() -> Rect2: return _tip("op", _op_card.get_global_rect()), null, ""])
	steps.append(["Economy", "1 Factory: builds your drones and missiles; launching is free. 2 Refinery: makes the money. Damaged sites repair themselves.",
		func() -> Rect2: return _tip("economy", _build[0].get_global_rect()),
		func() -> void: main.build_tool = LiteKind.FACTORY, ""])
	steps.append(["Air defence", "3 AA gun: patrols its region and chases drones (gun trucks first in a campaign, armoured AA later). 4 SAM: long reach, every kind of missile. 5 Radar: makes the air defence round it hit harder.",
		func() -> Rect2: return _tip("air_defence", _build[1].get_global_rect().merge(_build[2].get_global_rect())), null, ""])
	steps.append(["Take the gun", "Double-click one of our AA guns or gun trucks to take it yourself. The turret follows your mouse; hold the left button to fire, WASD to drive, Esc to leave.",
		func() -> Rect2: return Rect2(main.to_screen(gun.pos) - Vector2(22, 22), Vector2(44, 44)) if gun != null else _tip("air_defence", Rect2()), null, ""])
	steps.append(["Strike back", "Q, W, E pick a weapon; click enemy land to send it, or hold and drag to draw the way it flies. 1, 3, 10 set the salvo. Strikes home in on units on the move.",
		func() -> Rect2: return _tip("strike", _strike[0].get_global_rect().merge(_strike[2].get_global_rect())), null, "route"])
	steps.append(["Air alerts", "Yellow: drones overhead. Red: missiles. Factories slow down under alert.",
		func() -> Rect2: return _tip("alert", Rect2(LiteMap.W / 2.0 - 120, 14, 240, 54)), null, ""])
	# Map theme hook: the command interface's own controls.
	if _cmd_front():
		if m == null:
			steps.append(["Morale", "Both countries' morale: ours, and the enemy's as far as we can tell. Hits on a capital hurt it most. At zero a country gives up.",
				func() -> Rect2: return _tip("capitals", Rect2()), null, ""])
		steps.append(["SAMs and drones", "Switch whether SAMs also fire at drones. Interceptors come from your factories: keep them for missiles if you are short.",
			func() -> Rect2: return _tip("sam", Rect2()), null, ""])
		steps.append(["Air defence ranges", "Shows or hides the reach of air defence: ours in blue, the enemy's known sites in red.",
			func() -> Rect2: return _tip("layers", Rect2()), null, ""])
	steps.append(["Time", "Space pauses. 1×, 2× and 3× set the speed. T opens the statistics.",
		func() -> Rect2: return _tip("speed", _speed[0].get_global_rect().merge(_speed[3].get_global_rect())), null, ""])
	tutorial.run(steps, func() -> void:
		LiteSettings.tips_war = true
		LiteSettings.save())

## Map theme hook: where a tip points, at the command interface's own control
## while that interface is up (src/Lite/command/), else at the legacy one.
func _tip(key: String, legacy: Rect2) -> Rect2:
	return main.cmd_ui.tip_rect(key) if main.cmd_ui != null and LiteTheme.hud_on(main) else legacy

## The first-time tips for the campaign's front.
func tips_front() -> void:
	if LiteSettings.tips_front or tutorial.running:
		return
	var war: LiteMap = main.war_map
	var steps: Array = [
		["The front", "Click a marked region: its card says what the operation is, and the map shows the plan: our thrust in blue, the enemy's moves in red." if _cmd_front()
			else "Pick the next region to attack, here or on the map. Its badge shows what is there.",
			func() -> Rect2: return main.cmd_ui.front.option_rect() if _cmd_front() else _front.get_global_rect(), null, ""],
		["New equipment", "Win operations and new weapons arrive: SAMs and cruise missiles, armoured AA, jet drones, ballistic missiles.",
			func() -> Rect2: return main.cmd_ui.front.option_rect() if _cmd_front() else _front.get_global_rect(), null, ""],
	]
	if _cmd_front():
		steps.append(["War council", "Every operation won earns command points: spend them here on upgrades that last the whole campaign.",
			func() -> Rect2: return main.cmd_ui.front.council_rect(), null, ""])
	steps.append(["The enemy capital", "It opens once enough regions are ours. Take every region but the capital, and a last resort becomes possible.",
		func() -> Rect2: return Rect2(main.to_screen(war.capital[1]) - Vector2(34, 34), Vector2(68, 68)), null, ""])
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
	dim.color = LiteTheme.ui(Color(LiteGlyphs.PAGE, 0.25))
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

## The briefing before an operation, over the whole screen: the region's
## picture (see LiteStory.image) and, over its darkened lower left, what the
## operation is, why it matters, who says what, its targets and reward, and
## the button to begin.
func _build_briefing(root: Control) -> Control:
	var o:= Control.new()
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	o.visible = false
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back:= ColorRect.new()
	back.color = Color(0.03, 0.04, 0.07, 0.86)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.add_child(back)
	_brief_pic = TextureRect.new()
	_brief_pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_brief_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_brief_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_brief_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.add_child(_brief_pic)
	# Dark from the bottom up and from the left across, where the words are.
	for horizontal: bool in [false, true]:
		var shade:= TextureRect.new()
		var g:= Gradient.new()
		g.set_color(0, Color(0.02, 0.03, 0.05, 0.0))
		g.set_color(1, Color(0.02, 0.03, 0.05, 0.9 if not horizontal else 0.0))
		if horizontal:
			g.set_color(0, Color(0.02, 0.03, 0.05, 0.75))
			g.set_color(1, Color(0.02, 0.03, 0.05, 0.0))
		var gt:= GradientTexture2D.new()
		gt.gradient = g
		gt.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
		gt.width = 64 if horizontal else 4
		gt.height = 4 if horizontal else 64
		shade.texture = gt
		shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shade.stretch_mode = TextureRect.STRETCH_SCALE
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if horizontal:
			shade.anchor_left = 0; shade.anchor_right = 0.7; shade.anchor_top = 0; shade.anchor_bottom = 1
		else:
			shade.anchor_left = 0; shade.anchor_right = 1; shade.anchor_top = 0.3; shade.anchor_bottom = 1
		o.add_child(shade)
	var box:= VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.anchor_left = 0; box.anchor_right = 0.62; box.anchor_top = 1; box.anchor_bottom = 1
	box.offset_left = 70; box.offset_right = 0; box.offset_bottom = -44
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	o.add_child(box)
	_brief_box = box
	# The situation, on a dark plate at the right.
	var side_panel:= PanelContainer.new()
	side_panel.add_theme_stylebox_override("panel", LiteGlyphs.box(Color(0.02, 0.03, 0.05, 0.72), Color(LiteGlyphs.LINE, 0.6), 4, 16))
	side_panel.anchor_left = 0.76; side_panel.anchor_right = 1; side_panel.anchor_top = 1; side_panel.anchor_bottom = 1
	side_panel.offset_left = 0; side_panel.offset_right = -46; side_panel.offset_bottom = -44
	side_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	side_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.add_child(side_panel)
	_brief_side = VBoxContainer.new()
	_brief_side.add_theme_constant_override("separation", 7)
	side_panel.add_child(_brief_side)
	o.gui_input.connect(func(e: InputEvent) -> void:
		var mb:= e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and o.visible and not _brief_loading:
			main.audio.click()
			main.launch_mission())
	root.add_child(o)
	return o

## A briefing's line of story: the first sentences of its lead, short.
func _story_line(m: LiteMission) -> String:
	var lead: String = m.briefing.split("\n")[0]
	var out: String = ""
	for part: String in lead.split(". "):
		var next: String = (out + ". " + part) if out != "" else part
		if out != "" and next.length() > 170:
			break
		out = next
	return out if out.ends_with(".") or out.ends_with("!") else out + "."

var _brief_pic: TextureRect = null
var _brief_side: VBoxContainer = null

# --- Full-screen pages (phase 4): an operation's result, an event between
# operations. A picture over the whole screen, the words bottom left, the
# details on a plate at the right, a few buttons. ---

var _page: Control = null
var _page_pic: TextureRect = null
var _page_box: VBoxContainer = null
var _page_side: VBoxContainer = null

func _build_page(root: Control) -> void:
	var o:= Control.new()
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	o.visible = false
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back:= ColorRect.new()
	back.color = Color(0.03, 0.04, 0.07, 0.94)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.add_child(back)
	_page_pic = TextureRect.new()
	_page_pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_page_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_page_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.add_child(_page_pic)
	for horizontal: bool in [false, true]:
		var shade:= TextureRect.new()
		var g:= Gradient.new()
		g.set_color(0, Color(0.02, 0.03, 0.05, 0.0))
		g.set_color(1, Color(0.02, 0.03, 0.05, 0.92 if not horizontal else 0.0))
		if horizontal:
			g.set_color(0, Color(0.02, 0.03, 0.05, 0.78))
			g.set_color(1, Color(0.02, 0.03, 0.05, 0.0))
		var gt:= GradientTexture2D.new()
		gt.gradient = g
		gt.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
		gt.width = 64 if horizontal else 4
		gt.height = 4 if horizontal else 64
		shade.texture = gt
		shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shade.stretch_mode = TextureRect.STRETCH_SCALE
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if horizontal:
			shade.anchor_left = 0; shade.anchor_right = 0.7; shade.anchor_top = 0; shade.anchor_bottom = 1
		else:
			shade.anchor_left = 0; shade.anchor_right = 1; shade.anchor_top = 0.25; shade.anchor_bottom = 1
		o.add_child(shade)
	# A thin military frame: corner ticks.
	var frame:= Control.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.draw.connect(func() -> void:
		var r:= Rect2(Vector2(24, 24), frame.size - Vector2(48, 48))
		var c: Color = Color(LiteTheme.MUTED, 0.5)
		for sx: float in [0.0, 1.0]:
			for sy: float in [0.0, 1.0]:
				var p: Vector2 = r.position + r.size * Vector2(sx, sy)
				var dx: float = 22.0 * (1.0 if sx == 0.0 else -1.0)
				var dy: float = 22.0 * (1.0 if sy == 0.0 else -1.0)
				frame.draw_line(p, p + Vector2(dx, 0), c, 1.5)
				frame.draw_line(p, p + Vector2(0, dy), c, 1.5))
	o.add_child(frame)
	var box:= VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.anchor_left = 0; box.anchor_right = 0.6; box.anchor_top = 1; box.anchor_bottom = 1
	box.offset_left = 70; box.offset_right = 0; box.offset_bottom = -48
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	o.add_child(box)
	_page_box = box
	var side_panel:= PanelContainer.new()
	side_panel.add_theme_stylebox_override("panel", LiteGlyphs.box(Color(0.02, 0.03, 0.05, 0.75), Color(LiteGlyphs.LINE, 0.6), 4, 16))
	side_panel.anchor_left = 0.64; side_panel.anchor_right = 1; side_panel.anchor_top = 1; side_panel.anchor_bottom = 1
	side_panel.offset_right = -46; side_panel.offset_bottom = -48
	side_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	side_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.add_child(side_panel)
	_page_side = VBoxContainer.new()
	_page_side.add_theme_constant_override("separation", 7)
	side_panel.add_child(_page_side)
	root.add_child(o)
	_page = o

func _page_clear(pic: String, salt: int = -1) -> void:
	# Over everything (the front's strip is added to the same root later).
	_page.move_to_front()
	for box: VBoxContainer in [_page_box, _page_side]:
		for n: Node in box.get_children():
			box.remove_child(n)
			n.queue_free()
	_page_pic.texture = LiteStory.image(pic, salt, LiteBiome.climate(main.map) if main.map != null else -1)
	(_page_side.get_parent() as Control).visible = true

func _page_title(head: String, title: String, col: Color) -> void:
	var h:= _text(head, 13, LiteGlyphs.OBJECTIVE, true)
	h.add_theme_font_override("font", LiteGlyphs.black)
	_page_box.add_child(h)
	var t:= _text(title.to_upper() if LiteTheme.command else title, 46, col, true)
	t.add_theme_font_override("font", LiteGlyphs.black)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	t.add_theme_constant_override("shadow_offset_y", 3)
	_page_box.add_child(t)

func _page_button(text: String, primary: bool, f: Callable) -> Button:
	var b: Button = _wide(_page_box, text, primary, f)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.custom_minimum_size = Vector2(300, b.custom_minimum_size.y)
	return b

var page_open: bool:
	get: return _page != null and _page.visible

func close_page() -> void:
	if _page != null:
		_page.visible = false

## An operation's result, full screen: its picture, the outcome in big
## letters and three small buttons in a row under it. Nothing else.
func show_result(m: LiteMission, _c: LiteCampaign, title: String, good: bool, _lines: PackedStringArray, last: bool) -> void:
	_page_clear(LiteStory.result_key(m), LiteStory.salt(m))
	(_page_side.get_parent() as Control).visible = false
	var t:= _text(title.to_upper() if LiteTheme.command else title, 56, LiteGlyphs.GOOD if good else LiteGlyphs.ENEMY, true)
	t.add_theme_font_override("font", LiteGlyphs.black)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	t.add_theme_constant_override("shadow_offset_y", 3)
	_page_box.add_child(t)
	var row:= HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_page_box.add_child(row)
	var buttons: Array[Button] = []
	if not last:
		buttons.append(_wide(row, "Back to the front", true, func() -> void:
			close_page()
			main.next_mission()))
	buttons.append(_wide(row, "Statistics", false, func() -> void: show_stats()))
	buttons.append(_wide(row, "Main menu", false, func() -> void:
		close_page()
		main.to_title()))
	for b: Button in buttons:
		b.custom_minimum_size = Vector2(190, 36)
		b.add_theme_font_size_override("font_size", 13)
	_page.visible = true

## An event between operations, full screen; some ask for a decision.
func show_event(c: LiteCampaign, e: int, done: Callable) -> void:
	_page_clear(LiteStory.event_key(e))
	var good: bool = LiteCampaign.event_good(e)
	_page_title("BEFORE OPERATION %d  ·  %s" % [c.ops + 1, "GOOD NEWS" if good else "SITUATION REPORT"], LiteCampaign.event_title(e), LiteGlyphs.GOOD if good else LiteGlyphs.YELLOW)
	_page_box.add_child(_text(LiteCampaign.event_text(e), 18, LiteGlyphs.TEXT))
	if e == LiteCampaign.EV_ACCIDENT:
		# A decision: pay to have the plant ready, or start with it damaged.
		var price: int = LiteCampaign.ACCIDENT_FIX
		var fix: Button = _page_button("Repair it now  ($%d)" % price, true, func() -> void:
			if c.money >= price:
				c.money -= price
				c.events_next.erase(LiteCampaign.EV_ACCIDENT)
				c.save()
			close_page()
			done.call())
		fix.disabled = c.money < price
		_page_button("Leave it for now", false, func() -> void:
			close_page()
			done.call())
	elif e == LiteCampaign.EV_STORAGE:
		_page_button("Add it to the next strike", true, func() -> void:
			close_page()
			done.call())
	else:
		_page_button("Understood", true, func() -> void:
			close_page()
			done.call())
	(_page_side.get_parent() as Control).visible = false
	_page.visible = true

## The operation's screen: its picture, its name in the middle and, while
## its map is still being made (`loading`), a bar filling under it; once it
## is ready (briefing_ready), "click to begin" in the bar's place. Nothing
## else: the task is on the map's strip once it starts.
func show_briefing(m: LiteMission, _c: LiteCampaign, loading: bool = false) -> void:
	for n: Node in _brief_box.get_children():
		_brief_box.remove_child(n)
		n.queue_free()
	var box: VBoxContainer = _brief_box
	box.anchor_left = 0; box.anchor_right = 1
	box.offset_left = 0; box.offset_right = 0; box.offset_bottom = -90
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 22)
	_brief_pic.texture = LiteStory.image(LiteStory.op_key(m), LiteStory.salt(m), LiteBiome.climate(main.map) if main.map != null else -1)
	var t:= _text(m.title, 46, LiteGlyphs.TEXT, true)
	t.add_theme_font_override("font", LiteGlyphs.black)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	t.add_theme_constant_override("shadow_offset_y", 3)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(t)
	_brief_bar = _LoadBar.new()
	_brief_bar.custom_minimum_size = Vector2(460, 26)
	_brief_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_brief_bar)
	_brief_click = _text("CLICK TO BEGIN", 20, LiteGlyphs.OBJECTIVE, true)
	_brief_click.add_theme_font_override("font", LiteGlyphs.black)
	_brief_click.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_brief_click.add_theme_constant_override("shadow_offset_y", 2)
	_brief_click.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_brief_click.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(_brief_click)
	var tw: Tween = _brief_click.create_tween().set_loops()
	tw.tween_property(_brief_click, "modulate:a", 0.35, 0.7)
	tw.tween_property(_brief_click, "modulate:a", 1.0, 0.7)
	_brief_loading = loading
	_brief_bar.visible = loading
	_brief_click.visible = not loading
	for n: Node in _brief_side.get_children():
		_brief_side.remove_child(n)
		n.queue_free()
	_brief_side.get_parent().visible = false
	_briefing.visible = true

## The operation's map is ready: the bar gives way to "click to begin".
func briefing_ready() -> void:
	_brief_loading = false
	if _brief_bar != null:
		_brief_bar.visible = false
	if _brief_click != null:
		_brief_click.visible = true

var _brief_loading: bool = false
var _brief_bar: Control = null
var _brief_click: Label = null

## A loading bar: it fills fast at first, then slower and slower, never
## quite to the end (the map is ready when it is ready).
class _LoadBar extends Control:
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var r:= Rect2(Vector2(0, 8), Vector2(size.x, 10))
		draw_rect(r, Color(0, 0, 0, 0.55))
		var k: float = 0.95 * (1.0 - exp(-_t / 2.4))
		draw_rect(Rect2(r.position, Vector2(r.size.x * k, r.size.y)), LiteGlyphs.OBJECTIVE)
		# A light running along the filled part.
		var x: float = fmod(_t * 160.0, maxf(1.0, r.size.x * k))
		draw_rect(Rect2(r.position + Vector2(x, 0), Vector2(18, r.size.y)), Color(1, 1, 1, 0.25))
		draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)

## The picture of the Campaign or New war window (assets/ui/home_campaign.jpg,
## home_war.jpg; .png and .webp too), or null.
static func _art(which: String) -> Texture2D:
	for ext: String in ["jpg", "png", "webp"]:
		var path: String = "res://assets/ui/home_%s.%s" % [which, ext]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null

## Someone of the cast speaking: their portrait if there is one, their name
## and what they do, and the line.
static func speaker(q: Array, big: bool = false) -> Control:
	var who: Array = LiteStory.CAST.get(q[0], ["", ""])
	var row:= HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var tex: Texture2D = LiteStory.image("portrait_" + String(q[0]))
	if tex != null:
		var pic:= TextureRect.new()
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.custom_minimum_size = Vector2(84, 84) if big else Vector2(64, 64)
		pic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(pic)
	else:
		var bar:= ColorRect.new()
		bar.color = LiteTheme.ui(LiteGlyphs.YELLOW)
		bar.custom_minimum_size = Vector2(3, 0)
		row.add_child(bar)
	var col:= VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(_text("%s  ·  %s" % [String(who[0]).to_upper(), who[1]], 13 if big else 11, LiteGlyphs.YELLOW, true))
	col.add_child(_text("“%s”" % q[1], 20 if big else 13, LiteGlyphs.TEXT))
	return row

## A story picture at the top of a dialog, if there is one: as wide as it,
## cropped to a band.
static func _picture(box: VBoxContainer, tex: Texture2D) -> void:
	if tex == null:
		return
	var r:= TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.custom_minimum_size = Vector2(0, 165)
	r.clip_contents = true
	box.add_child(r)

## The story's slides, over everything (see LiteSlides).
var slides: LiteSlides = null
## A campaign's end page (see LiteCampaignEnd).
var campaign_end: LiteCampaignEnd = null

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
	if _debrief_quote != null:
		_debrief_quote.queue_free()
		_debrief_quote = null
	if main.campaign != null and m != null:
		var rng:= RandomNumberGenerator.new()
		rng.seed = m.number * 977 + m.province
		_debrief_quote = speaker(LiteStory.debrief_quote(m, main.war_map if main.war_map != null else main.map, rng))
		_debrief_text.get_parent().add_child(_debrief_quote)
		_debrief_text.get_parent().move_child(_debrief_quote, _debrief_text.get_index() + 1)
	_debrief_next.visible = not last
	_debrief.visible = true

var _debrief_quote: Control = null

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
		_front.visible = screen == null and main.front_open and not _cmd_front()
		if _cmd_front():
			main.cmd_ui.front.visible = screen == null and main.front_open

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
		if not _brief_loading:
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
		# Over whatever page asked for it (an operation's result, the war's end).
		stats_view.move_to_front()

## The arsenal page (home menu).
var arsenal: LiteArsenalView = null

func back() -> void:
	if arsenal != null and arsenal.visible:
		arsenal.close()
	elif achievements != null and achievements.visible:
		achievements.close()
	elif stats_view.visible:
		stats_view.visible = false
	elif _new_game.visible or _settings.visible or _campaign.visible:
		_show_screen(_menu)
	elif _menu.visible and (main.started or main.front_open) and main.sim.winner < 0:
		close_menu()

var _end_pic: TextureRect = null

func show_end(won: bool, stats: String, title: String = "") -> void:
	_end_title.text = title if title != "" else ("Victory" if won else "Defeat")
	if LiteTheme.command:
		_end_title.text = _end_title.text.to_upper()
	_end_pic.texture = LiteStory.image("victory" if won else "defeat")
	_end_pic.visible = _end_pic.texture != null
	_end_title.add_theme_color_override("font_color", LiteGlyphs.GOOD if won else LiteGlyphs.ENEMY)
	_end_text.text = stats
	# A campaign's end comes after its last operation: no war's statistics to show.
	_end_stats.visible = main.started
	_show_screen(null)
	_end.visible = true

func clear_feed() -> void:
	for c: Node in _feed.get_children():
		c.queue_free()
	feed_cleared.emit()

func post(text: String, tone: Color) -> void:
	posted.emit(text, tone)
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
	for i in BUILD_KINDS.size():
		_build[i].selected = main.build_tool == BUILD_KINDS[i]
		var price: int = main.sim.cost(0, BUILD_KINDS[i])
		_build[i].affordable = me.money >= price
		_build[i].price = "$%d" % price
	for i in 3:
		_strike[i].selected = main.strike_tool == ARMS[i]
		_strike[i].affordable = me.money >= main.sim.arm_cost(0, ARMS[i]) and main.sim.has_arm(0, ARMS[i]) and main.sim.in_stock(0, ARMS[i]) > 0
		_strike[i].price = ("$%d" % main.sim.arm_cost(0, ARMS[i])) if LiteSim.classic_rules else ("%d in stock" % main.sim.in_stock(0, ARMS[i]))
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
		_theme[i].selected = LiteTheme.command == (i == 1)
	# Map theme hook: the command interface stands in for the panel and HUD.
	var command: bool = LiteTheme.hud_on(main)
	_panel.visible = main.started and not home_open and not command
	var m: LiteMission = main.mission
	_withdraw.visible = m != null and main.started and m.result < 0 and not m.timed
	if not _withdraw.visible:
		_withdraw.text = "Withdraw"
	hud.visible = not home_open and not command
	for i in 4:
		_speed[i].selected = main.paused if i == 0 else (not main.paused and main.speed == SPEEDS[i])
	var on: bool = main.sim.sams_on_drones[0]
	_sam_toggle.text = "SAMs fire at drones: ON" if on else "SAMs fire at drones: OFF (guns only)"
	_sam_toggle.selected = on
