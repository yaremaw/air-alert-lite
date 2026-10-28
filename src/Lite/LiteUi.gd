class_name LiteUi
extends CanvasLayer
## The interface of the lite game: the side panel (status, BUILD, STRIKE,
## the feed, speed and the menu button), the HUD over the map, and the
## screens over it: the menu, a new game, settings and the end of a war.

var main: LiteMain = null
var hud: LiteHud = null
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
var _continue: Button = null
var _new_game_button: Button = null
var _menu_sub: Label = null
var _end_title: Label = null
var _end_text: Label = null

## True while one of the screens over the map is open; the war stands still.
var menu_open: bool:
	get: return _menu.visible or _new_game.visible or _settings.visible

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
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	hud = LiteHud.new()
	hud.main = main
	root.add_child(hud)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.anchor_left = 1; panel.anchor_right = 1; panel.anchor_top = 0; panel.anchor_bottom = 1
	panel.offset_left = -292; panel.offset_right = -10; panel.offset_top = 10; panel.offset_bottom = -10
	panel.add_theme_stylebox_override("panel", LiteGlyphs.box(Color(LiteGlyphs.PANEL, 0.97), LiteGlyphs.LINE, 14, 14))
	root.add_child(panel)
	_panel = panel
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var status := LiteStatus.new()
	status.main = main
	status.custom_minimum_size = Vector2(0, 156)
	vb.add_child(status)

	vb.add_child(_section("BUILD", "on your territory"))
	var row: HBoxContainer = _row(vb)
	for i in 3:
		var k: int = BUILD_KINDS[i]
		var b := LiteToolButton.new()
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
		var b := LiteToolButton.new()
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
	var salvo_label := Label.new()
	salvo_label.text = "Salvo"
	salvo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	salvo_label.custom_minimum_size = Vector2(46, 0)
	salvo_label.add_theme_color_override("font_color", LiteGlyphs.MUTED)
	salvo_label.add_theme_font_size_override("font_size", 12)
	row.add_child(salvo_label)
	for i in 3:
		var n: int = SALVOS[i]
		var c := LiteChip.new()
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
	# The feed takes what room is left and never pushes the row below off the panel.
	var scroll := ScrollContainer.new()
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
	var menu := LiteChip.new()
	menu.text = "Menu"
	menu.tooltip_text = "Menu and settings (Esc)"
	menu.custom_minimum_size = Vector2(58, 28)
	menu.clicked = func() -> void:
		show_menu()
		main.audio.click()
	row.add_child(menu)
	var speed_text: Array[String] = ["II", "1×", "2×", "3×"]
	for i in 4:
		var s: float = SPEEDS[i]
		var c := LiteChip.new()
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
	_end = _build_end(root)


static func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	return row


static func _section(title: String, hint: String) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 16)
	var t := Label.new()
	t.text = title
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_override("font", LiteGlyphs.bold)
	t.add_theme_font_size_override("font_size", 10)
	t.add_theme_color_override("font_color", LiteGlyphs.MUTED)
	row.add_child(t)
	var h := Label.new()
	h.text = hint
	h.add_theme_font_size_override("font_size", 10)
	h.add_theme_color_override("font_color", LiteGlyphs.FAINT)
	row.add_child(h)
	return row


static func _make_theme() -> Theme:
	var t := Theme.new()
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


# ---------------------------------------------------------------- screens

## Was `Overlay(root, out VBoxContainer box, width)`: returns [overlay: Control, box: VBoxContainer].
func _overlay(root: Control, width: float) -> Array:
	var o := Control.new()
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	o.visible = false
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(LiteGlyphs.PAGE, 0.8)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.add_child(dim)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.add_theme_stylebox_override("panel", LiteGlyphs.box(LiteGlyphs.PANEL, LiteGlyphs.LINE, 16, 26))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	root.add_child(o)
	return [o, box]


static func _text(s: String, size: int, col: Color, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = s
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", LiteGlyphs.bold)
	return l


## A wide button: blue for the main action, quiet grey for the rest.
func _wide(parent: Control, text: String, primary: bool, pressed: Callable) -> Button:
	var b := Button.new()
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
	box.add_child(_text("STRIKE ALERT · LITE", 11, LiteGlyphs.MUTED, true))
	box.add_child(_text(title, 34, LiteGlyphs.TEXT, true))


func _build_menu(root: Control) -> Control:
	var ob: Array = _overlay(root, 360)
	var o: Control = ob[0]
	var box: VBoxContainer = ob[1]
	_title(box, "Air Alert")
	_menu_sub = _text("", 13, LiteGlyphs.MUTED)
	box.add_child(_menu_sub)
	_continue = _wide(box, "Continue", true, close_menu)
	_new_game_button = _wide(box, "New war", true, func() -> void: _show_screen(_new_game))
	_wide(box, "Settings", false, func() -> void: _show_screen(_settings))
	# A browser tab cannot quit itself.
	if not OS.has_feature("web"):
		_wide(box, "Quit", false, func() -> void: main.get_tree().quit())
	box.add_child(_text("Esc opens this menu during the war", 11, LiteGlyphs.FAINT))
	return o


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
		var c := LiteChip.new()
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
	box.add_child(_text("1 2 3 build  ·  Q W E strike  ·  Space pause  ·  Esc cancel or menu", 11, LiteGlyphs.FAINT))
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
	_wide(box, "Back", false, func() -> void: _show_screen(_menu))
	return o


func _choice(box: VBoxContainer, label: String, options: Array[String], chips: Array[LiteChip], pick: Callable) -> void:
	var row: HBoxContainer = _row(box)
	var l := Label.new()
	l.text = label
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(140, 0)
	l.add_theme_color_override("font_color", LiteGlyphs.MUTED)
	row.add_child(l)
	for i in options.size():
		var k: int = i
		var c := LiteChip.new()
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
	_wide(box, "Main menu", false, func() -> void:
		_end.visible = false
		show_menu())
	return o


## Shows one screen (or none) over the map.
## (Was `Show` in C#; renamed because CanvasLayer already has `show()`.)
func _show_screen(screen: Control) -> void:
	_menu.visible = screen == _menu
	_new_game.visible = screen == _new_game
	_settings.visible = screen == _settings


func show_menu() -> void:
	var live: bool = main.started and main.sim.winner < 0
	_continue.visible = live
	_quiet(_new_game_button, live)
	_menu_sub.text = ("The war is paused · %s" % main.clock_text(main.sim.time, true)) if live else "An air war on a live air-alert map."
	_end.visible = false
	_show_screen(_menu)


func show_settings() -> void:
	_show_screen(_settings)


func close_menu() -> void:
	_show_screen(null)


## Esc on a screen: back to the menu, or out of the menu into a war under way.
func back() -> void:
	if _new_game.visible or _settings.visible:
		_show_screen(_menu)
	elif _menu.visible and main.started and main.sim.winner < 0:
		close_menu()


func show_end(won: bool, stats: String) -> void:
	_end_title.text = "Victory" if won else "Defeat"
	_end_title.add_theme_color_override("font_color", LiteGlyphs.GOOD if won else LiteGlyphs.ENEMY)
	_end_text.text = stats
	_show_screen(null)
	_end.visible = true


# ---------------------------------------------------------------- feed

func clear_feed() -> void:
	for c: Node in _feed.get_children():
		c.queue_free()


func post(text: String, tone: Color) -> void:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box: StyleBoxFlat = LiteGlyphs.box(Color(LiteGlyphs.PANEL_HI, 0.7), tone, 7)
	box.border_width_top = 0
	box.border_width_right = 0
	box.border_width_bottom = 0
	box.border_width_left = 3
	box.content_margin_left = 10; box.content_margin_right = 8; box.content_margin_top = 6; box.content_margin_bottom = 7
	card.add_theme_stylebox_override("panel", box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.add_child(_text(main.clock_text(main.sim.time, false), 10, LiteGlyphs.FAINT))
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


# ---------------------------------------------------------------- refresh

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
	for i in 4:
		_volume[i].selected = LiteSettings.volume == i
	for i in 2:
		_window[i].selected = LiteSettings.fullscreen == (i == 1)
		_routes[i].selected = LiteSettings.routes == (i == 0)
		_ranges[i].selected = LiteSettings.ranges == (i == 0)
	_panel.visible = main.started
	for i in 4:
		_speed[i].selected = main.paused if i == 0 else (not main.paused and main.speed == SPEEDS[i])
	var on: bool = main.sim.sams_on_drones[0]
	_sam_toggle.text = "SAMs fire at drones: ON" if on else "SAMs fire at drones: OFF (guns only)"
	_sam_toggle.selected = on
