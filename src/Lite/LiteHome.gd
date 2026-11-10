class_name LiteHome
extends Control

## The home screen, and the pause menu during a war: the cover art behind (see
## LiteHomeScene), the logo and the menu on the left over a darkened strip, and the
## community links bottom right.

const VERSION: String = "Update 1 · v1.1"
const LINKS: Array = [
	["Discord", "https://discord.gg/Zf6rerfAu"],
	["YouTube", "https://youtube.com/@strike-alert-game"],
	["Telegram", "https://t.me/strikealertgame"],
]

var main: LiteMain = null
var on_continue: Callable = Callable()
var on_new_war: Callable = Callable()
var on_campaign: Callable = Callable()
var on_settings: Callable = Callable()
var on_quit: Callable = Callable()

var scene: LiteHomeScene = null
var _continue: LiteMenuItem = null
var _new_war: LiteMenuItem = null
var _campaign: LiteMenuItem = null
var _sub: Label = null

func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	scene = LiteHomeScene.new()
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scene)
	var shade:= Control.new()
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.draw.connect(func() -> void: _draw_shade(shade))
	shade.resized.connect(shade.queue_redraw)
	add_child(shade)

	var logo:= LiteLogo.new()
	logo.position = Vector2(56, 64)
	add_child(logo)

	_sub = Label.new()
	_sub.position = Vector2(84, 214)
	_sub.add_theme_font_size_override("font_size", 15)
	_sub.add_theme_color_override("font_color", LiteGlyphs.MUTED)
	add_child(_sub)

	var menu:= VBoxContainer.new()
	menu.position = Vector2(56, 262)
	menu.add_theme_constant_override("separation", 4)
	add_child(menu)
	_continue = _item(menu, "CONTINUE", func() -> void: on_continue.call())
	_new_war = _item(menu, "NEW WAR", func() -> void: on_new_war.call())
	_campaign = _item(menu, "CAMPAIGN", func() -> void: on_campaign.call())
	_item(menu, "SETTINGS", func() -> void: on_settings.call())
	if not OS.has_feature("web"):
		_item(menu, "QUIT", func() -> void: on_quit.call())

	var foot:= VBoxContainer.new()
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.offset_left = 84
	foot.offset_right = 700
	foot.offset_top = -28
	foot.offset_bottom = -28
	foot.add_theme_constant_override("separation", 2)
	add_child(foot)
	foot.add_child(_label(VERSION.to_upper(), 12, LiteGlyphs.MUTED, LiteGlyphs.bold))
	foot.add_child(_label("Esc opens this menu during the war  ·  F11 fullscreen", 12, LiteGlyphs.FAINT, LiteGlyphs.font))

	# The community links in the left column, above the version line, off the picture.
	var follow_box:= VBoxContainer.new()
	follow_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	follow_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	follow_box.offset_left = 84
	follow_box.offset_right = 600
	follow_box.offset_top = -92
	follow_box.offset_bottom = -92
	follow_box.add_theme_constant_override("separation", 8)
	add_child(follow_box)
	follow_box.add_child(_label("FOLLOW THE DEVELOPMENT", 11, LiteGlyphs.MUTED, LiteGlyphs.bold))
	var links:= HBoxContainer.new()
	links.add_theme_constant_override("separation", 8)
	follow_box.add_child(links)
	for l: Array in LINKS:
		var url: String = l[1]
		var c:= LiteChip.new()
		c.text = l[0]
		c.font_size = 13
		c.custom_minimum_size = Vector2(96, 34)
		c.clicked = func() -> void:
			main.audio.click()
			OS.shell_open(url)
		links.add_child(c)

func _item(parent: Control, text: String, pressed: Callable) -> LiteMenuItem:
	var it:= LiteMenuItem.new()
	it.text = text
	it.clicked = func() -> void:
		main.audio.click()
		pressed.call()
	parent.add_child(it)
	return it

static func _label(s: String, size_: int, col: Color, f: Font) -> Label:
	var l:= Label.new()
	l.text = s
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size_)
	l.add_theme_color_override("font_color", col)
	return l

## live: a war is on (and paused), so Continue leads; otherwise New war does.
func set_live(live: bool, sub: String) -> void:
	_continue.visible = live
	_continue.primary = live
	_new_war.primary = not live
	_new_war.note = "" if live else "Enter"
	_continue.note = "Esc" if live else ""
	var saved: LiteCampaign = LiteCampaign.load_saved()
	_campaign.note = ("Mission %d of %d" % [saved.mission + 1, LiteCampaign.MISSIONS.size()]) if saved != null else "New"
	_continue.queue_redraw()
	_new_war.queue_redraw()
	_campaign.queue_redraw()
	_sub.text = sub

func activate_primary() -> void:
	if _continue.visible:
		on_continue.call()
	else:
		on_new_war.call()
	main.audio.click()

## The dark strip on the left, under the logo, the menu and the links.
func _draw_shade(ci: Control) -> void:
	var w: float = ci.size.x
	var h: float = ci.size.y
	var page: Color = LiteGlyphs.PAGE
	var stops: Array = [[0.0, 0.92], [0.28, 0.80], [0.42, 0.35], [0.56, 0.0]]
	for i: int in stops.size() - 1:
		var x0: float = w * stops[i][0]
		var x1: float = w * stops[i + 1][0]
		var c0:= Color(page, stops[i][1])
		var c1:= Color(page, stops[i + 1][1])
		ci.draw_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, h), Vector2(x0, h)]),
			PackedColorArray([c0, c1, c1, c0]))
