class_name LiteCmdFront
extends Control
## The campaign's front in the command look (see LiteTheme): the war's map
## over the whole screen, no side panel. A strip along the top says which
## operation is next, the date, the enemy capital's state and the weapons
## this operation; the regions that can be attacked (or the one that must be
## held) carry badges on the map (LiteCmdView). Click one and a card opens
## beside it: what is there, the reward, and the button to launch the
## operation. It drives the same campaign as the legacy front panel does
## (LiteMain.pick_front, launch_operation).

var main: LiteMain = null
var _strip: Strip = null
var _card: PanelContainer = null
var _box: VBoxContainer = null
var _menu: LiteCmdButton = null
## Where the card points (the picked region's name, on screen).
var _at: Vector2 = Vector2.ZERO

func build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_strip = Strip.new()
	_strip.front = self
	_strip.anchor_left = 0; _strip.anchor_right = 1
	_strip.offset_bottom = LiteTheme.TOP
	add_child(_strip)
	_menu = LiteCmdButton.new()
	_menu.text = "MAIN MENU"
	_menu.font_size = 11
	_menu.bar_left = false
	_menu.anchor_left = 1; _menu.anchor_right = 1
	_menu.offset_left = -128; _menu.offset_right = -8
	_menu.offset_top = 6; _menu.offset_bottom = LiteTheme.TOP - 6
	_menu.clicked = func() -> void:
		main.audio.click()
		main.ui.close_front()
		main.to_title()
	_strip.add_child(_menu)
	_council_btn = LiteCmdButton.new()
	_council_btn.font_size = 11
	_council_btn.bar_left = false
	_council_btn.accent = Color("#F2C14E")
	_council_btn.anchor_left = 1; _council_btn.anchor_right = 1
	_council_btn.offset_left = -296; _council_btn.offset_right = -136
	_council_btn.offset_top = 6; _council_btn.offset_bottom = LiteTheme.TOP - 6
	_council_btn.tooltip_text = "Spend command points on upgrades for every later operation"
	_council_btn.clicked = func() -> void:
		main.audio.click()
		_show_council(not _council.visible)
	_strip.add_child(_council_btn)
	# The report bar along the bottom: one of the cast on the situation.
	_report = PanelContainer.new()
	var rbox: StyleBoxFlat = LiteGlyphs.box(LiteTheme.BG2, LiteTheme.BORDER, 0, 0)
	rbox.border_width_left = 0; rbox.border_width_right = 0; rbox.border_width_bottom = 0
	rbox.content_margin_left = 8; rbox.content_margin_right = 16; rbox.content_margin_top = 6; rbox.content_margin_bottom = 6
	_report.add_theme_stylebox_override("panel", rbox)
	_report.anchor_left = 0; _report.anchor_right = 1; _report.anchor_top = 1; _report.anchor_bottom = 1
	_report.offset_top = -LiteTheme.FRONT_BOTTOM
	_report.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_report)
	# The cast's report is not shown on the front any more (see LiteMain.RADIO).
	_report.visible = false
	var row:= HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_report.add_child(row)
	_report_pic = TextureRect.new()
	_report_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_report_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_report_pic.custom_minimum_size = Vector2(LiteTheme.FRONT_BOTTOM - 12, LiteTheme.FRONT_BOTTOM - 12)
	row.add_child(_report_pic)
	var col:= VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	_report_name = _label("", 13, LiteTheme.AMBER, LiteGlyphs.bold)
	col.add_child(_report_name)
	_report_line = _label("", 21, LiteTheme.TEXT, LiteGlyphs.font)
	_report_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_report_line.custom_minimum_size = Vector2(700, 0)
	col.add_child(_report_line)
	_council = PanelContainer.new()
	_council.mouse_filter = Control.MOUSE_FILTER_STOP
	var cbox: StyleBoxFlat = LiteGlyphs.box(Color(LiteTheme.PANEL, 0.98), Color("#F2C14E").darkened(0.35), 0, 18)
	cbox.border_width_top = 3
	_council.add_theme_stylebox_override("panel", cbox)
	_council.visible = false
	add_child(_council)
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	var box: StyleBoxFlat = LiteGlyphs.box(Color(LiteTheme.PANEL, 0.97), LiteTheme.BLUE.darkened(0.3), 0, 16)
	box.border_width_left = 3
	_card.add_theme_stylebox_override("panel", box)
	_card.custom_minimum_size = Vector2(340, 0)
	_card.visible = false
	add_child(_card)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_card.add_child(_box)

var _council_btn: LiteCmdButton = null
var _report: PanelContainer = null
var _report_pic: TextureRect = null
var _report_name: Label = null
var _report_line: Label = null
var _council: PanelContainer = null

## The war council: the command points to spend, and each upgrade with its
## level and a button to buy the next.
func _show_council(on: bool) -> void:
	_council.visible = on
	if not on:
		return
	_card.visible = false
	for n: Node in _council.get_children():
		_council.remove_child(n)
		n.queue_free()
	var c: LiteCampaign = main.campaign
	var v:= VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(560, 0)
	_council.add_child(v)
	var head:= HBoxContainer.new()
	v.add_child(head)
	var t: Label = _label("WAR COUNCIL", 24, LiteTheme.TEXT, LiteGlyphs.black)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(_label("★ %d" % c.points, 24, Color("#F2C14E"), LiteGlyphs.black))
	var sub: Label = _label("Command points: one for each operation won, one more for its optional goal. Upgrades last the whole campaign.", 13, LiteTheme.MUTED, LiteGlyphs.font)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(560, 0)
	v.add_child(sub)
	for u: Array in LiteCampaign.UPGRADES:
		var key: String = u[0]
		var lv: int = c.level(key)
		var most: int = u[3]
		var row:= HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		v.add_child(row)
		var col:= VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		col.add_child(_label(String(u[1]).to_upper(), 13, LiteTheme.TEXT, LiteGlyphs.bold))
		col.add_child(_label(u[2], 12, LiteTheme.MUTED, LiteGlyphs.font))
		var pips: String = ""
		for k: int in most:
			pips += "■ " if k < lv else "□ "
		row.add_child(_label(pips.strip_edges(), 16, Color("#F2C14E") if lv > 0 else LiteTheme.NEUTRAL, LiteGlyphs.bold))
		var b:= LiteCmdButton.new()
		b.font_size = 11
		b.bar_left = false
		b.custom_minimum_size = Vector2(110, 34)
		b.text = "MAXED" if lv >= most else "UPGRADE ★1"
		b.enabled = lv < most and c.points > 0
		b.clicked = func() -> void:
			if c.buy(key):
				c.save()
				main.audio.play("click_off.wav", -8.0)
				_show_council(true)
				_strip.queue_redraw()
		row.add_child(b)
	var close:= LiteCmdButton.new()
	close.text = "BACK TO THE FRONT"
	close.font_size = 12
	close.bar_left = false
	close.custom_minimum_size = Vector2(0, 40)
	close.clicked = func() -> void:
		main.audio.click()
		_show_council(false)
	v.add_child(close)
	_council.size = Vector2.ZERO
	_center_council.call_deferred()

func _center_council() -> void:
	_council.reset_size()
	_council.position = ((get_viewport_rect().size - _council.size) * 0.5).floor()

## The front as it stands: the strip, and the card for the region picked
## (once the player has picked one, or when one must be held).
func show_front(c: LiteCampaign) -> void:
	visible = true
	_strip.queue_redraw()
	_council_btn.text = "WAR COUNCIL ★%d" % c.points
	_council_btn.selected = c.points > 0
	# The situation, as one of the cast reports it.
	var q: Array = LiteStory.front_report(c, main.war_map)
	var who: Array = LiteStory.CAST.get(q[0], ["", ""])
	_report_pic.texture = LiteStory.image("portrait_" + String(q[0]))
	_report_name.text = "%s  ·  %s" % [String(who[0]).to_upper(), who[1]]
	_report_name.add_theme_color_override("font_color", LiteCmdUi.Comms.ACCENT.get(q[0], LiteTheme.AMBER))
	_report_line.text = "“%s”" % q[1]
	for n: Node in _box.get_children():
		_box.remove_child(n)
		n.queue_free()
	var show_card: bool = main.front_pick >= 0 and (main.front_chosen or c.counter >= 0)
	_card.visible = show_card
	if not show_card:
		return
	var war: LiteMap = main.war_map
	c.clear_preview()
	var m: LiteMission = c.preview(war, main.front_pick)
	var head: Label = _label("OPERATION %d" % (c.ops + 1), 11, LiteTheme.BLUE, LiteGlyphs.black)
	_box.add_child(head)
	_box.add_child(_label(m.title, 24, LiteTheme.TEXT, LiteGlyphs.black))
	var holding: bool = m.defensive
	var kind: String = "Defend" if holding else ("Capital" if m.kind == LiteMission.CAPITAL else LiteMission.character_name(m.character))
	if m.plot != LiteMission.PLOT_NONE and m.label != "":
		kind = "%s · %s" % [kind, m.label]
	_box.add_child(_label(kind.to_upper(), 11, LiteTheme.RED if not holding else LiteTheme.AMBER, LiteGlyphs.bold))
	var sum: Label = _label(m.summary(), 14, LiteTheme.TEXT, LiteGlyphs.font)
	sum.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sum.custom_minimum_size = Vector2(308, 0)
	_box.add_child(sum)
	if m.kind == LiteMission.STRIKE:
		# The targets' icons for an attack on sites; a plan on the map for one
		# against forces on the move (see LiteCmdView._draw_plan).
		if m.plot == LiteMission.PLOT_NONE:
			_box.add_child(LiteIconList.of_kinds(LiteMission.target_kinds(m.character)))
		_box.add_child(_label("Reward: " + LiteMission.character_gain(m.character), 13, LiteTheme.GREEN, LiteGlyphs.font))
	_box.add_child(_label("Weapons: " + LiteCampaign.arms_text(LiteCampaign.arms_at(c.ops)), 12, LiteTheme.MUTED, LiteGlyphs.font))
	var row:= HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_box.add_child(row)
	var go:= Button.new()
	go.text = "Launch operation"
	go.focus_mode = Control.FOCUS_NONE
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.custom_minimum_size = Vector2(0, 42)
	go.pressed.connect(func() -> void:
		main.audio.click()
		main.launch_operation())
	row.add_child(go)
	if not holding:
		var close:= LiteCmdButton.new()
		close.text = "×"
		close.font_size = 18
		close.bar_left = false
		close.custom_minimum_size = Vector2(42, 42)
		close.tooltip_text = "Close"
		close.clicked = func() -> void:
			main.front_chosen = false
			main.audio.click()
			show_front(c)
		row.add_child(close)
	var r: LiteRegion = war.regions[int(main.front_labels.get(main.front_pick, main.front_pick))]
	_at = main.to_screen(r.label)
	_place.call_deferred()

## The card in a corner of the screen away from the region picked.
func _place() -> void:
	_card.reset_size()
	var sz: Vector2 = _card.get_combined_minimum_size()
	var vs: Vector2 = get_viewport_rect().size
	# In the corner of the screen farthest from the region, clear of its
	# plan drawn round it on the map (see LiteCmdView._draw_plan).
	var top: float = LiteTheme.TOP + 12
	var bottom: float = vs.y - LiteTheme.FRONT_BOTTOM - sz.y - 12
	var p:= Vector2(12.0 if _at.x > vs.x * 0.5 else vs.x - sz.x - 12.0, bottom if _at.y < vs.y * 0.5 else top)
	p.y = clampf(p.y, top, maxf(top, bottom))
	_card.position = p
	_card.size = sz

func hide_front() -> void:
	visible = false

## For the first-time tips: the first region that can be attacked, on screen.
func council_rect() -> Rect2:
	return _council_btn.get_global_rect()

func option_rect() -> Rect2:
	if main.front_options.is_empty():
		return _strip.get_global_rect()
	var id: int = main.front_options[0]
	var r: LiteRegion = main.war_map.regions[int(main.front_labels.get(id, id))]
	return Rect2(main.to_screen(r.label) - Vector2(40, 46), Vector2(80, 64))

static func _label(text: String, size: int, col: Color, font: Font) -> Label:
	var l:= Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## The strip along the top of the front.
class Strip extends Control:
	var front: LiteCmdFront = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		var main: LiteMain = front.main
		var c: LiteCampaign = main.campaign
		if c == null or main.war_map == null:
			return
		var war: LiteMap = main.war_map
		draw_rect(Rect2(Vector2.ZERO, size), LiteTheme.BG2)
		draw_rect(Rect2(0, size.y - 1, size.x, 1), LiteTheme.BORDER)
		var cy: float = size.y / 2.0
		LiteLogo.draw_mark(self, Vector2(22, cy), 10.0)
		draw_string(LiteGlyphs.black, Vector2(40, cy + 4.5), "STRIKE ALERT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteTheme.TEXT)
		var x: float = 158.0
		draw_rect(Rect2(146, 9, 1, size.y - 18), LiteTheme.BORDER)
		var head: String = "OPERATION %d" % (c.ops + 1)
		draw_string(LiteGlyphs.bold, Vector2(x, cy + 5), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, LiteTheme.TEXT)
		x += LiteGlyphs.bold.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 14.0
		var date: String = main.clock_text(0.0, true).to_upper()
		draw_string(LiteGlyphs.font, Vector2(x, cy + 5), date, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, LiteTheme.MUTED)
		x += LiteGlyphs.font.get_string_size(date, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 24.0
		# What to do now, in the middle.
		var hint: String
		var short: String
		var col: Color = LiteTheme.TEXT
		if c.counter >= 0:
			hint = "Enemy offensive on %s: hold it, or it falls after your next operation" % c.group_name(war, c.counter)
			short = "Offensive on %s" % c.group_name(war, c.counter)
			col = LiteTheme.AMBER
		else:
			hint = "Click a marked region to plan the next operation"
			short = "Pick a region"
		# The enemy capital and the weapons, before the menu button.
		var cap: String
		if c.capital_locked():
			cap = "%s opens after %d regions (%d/%d)" % [war.capital_name[1].to_upper(), LiteCampaign.CAPITAL_AFTER, c.taken[0], LiteCampaign.CAPITAL_AFTER]
		else:
			cap = "%s · %d SAM batteries" % [war.capital_name[1].to_upper(), c.capital_defence(war)]
		var weapons: String = "WEAPONS: " + LiteCampaign.arms_text(LiteCampaign.arms_at(c.ops)).to_upper()
		var right: float = size.x - 304.0
		var ww: float = LiteGlyphs.bold.get_string_size(weapons, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(LiteGlyphs.bold, Vector2(right - ww, cy + 4), weapons, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LiteTheme.MUTED)
		var cw: float = LiteGlyphs.bold.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(LiteGlyphs.bold, Vector2(right - ww - 24 - cw, cy + 4), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LiteTheme.AMBER if c.capital_locked() else LiteTheme.RED)
		# The hint in what room is left between: shorter when it would not fit.
		var room: float = right - ww - 24 - cw - 24 - x
		if LiteGlyphs.bold.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x > room:
			hint = short
		draw_string(LiteGlyphs.bold, Vector2(x, cy + 5), hint, HORIZONTAL_ALIGNMENT_LEFT, maxf(40.0, room), 14, col)
