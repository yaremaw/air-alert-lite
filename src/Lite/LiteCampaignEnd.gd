class_name LiteCampaignEnd
extends Control
## The end of a campaign, over the whole screen: its picture behind (a parade
## for a victory, see LiteStory.image), the outcome in big letters, the rank
## the war earned, its figures, the medals (kept from campaign to campaign, the
## new ones marked), every operation as a dot, and the way on.

var main: LiteMain = null
var _c: LiteCampaign = null
var _won: int = -1
var _pic: TextureRect = null
var _box: VBoxContainer = null
var _medals: HBoxContainer = null
var _medals2: HBoxContainer = null
const PATH: String = "user://lite_medals.cfg"

## [key, name, what earns it, glyph]
const MEDALS: Array = [
	["victory", "Victory Day", "Win a campaign", LiteGlyph.CAPITAL],
	["flawless", "Flawless", "Win every operation", LiteGlyph.CAPITAL],
	["no_step_back", "Not One Step Back", "Lose no region", LiteGlyph.GUN],
	["blitz", "Blitz", "Win in 6 operations", LiteGlyph.BALLISTIC],
	["liberator", "Liberator", "Free 5 regions", LiteGlyph.FACTORY],
	["clear_skies", "Clear Skies", "Shoot down 150", LiteGlyph.SAM],
	["lights_out", "Lights Out", "Take a power grid", LiteGlyph.POWER],
	["signal_lost", "Signal Lost", "Take an EW hub", LiteGlyph.JAMMER],
	["ghost_hunter", "Ghost Hunter", "Take an air base", LiteGlyph.LAUNCHER],
	["brink", "Back from the Brink", "Win after losing 2 regions", LiteGlyph.DEPOT],
]

func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var back:= ColorRect.new()
	back.color = Color("#070b11")
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	_pic = TextureRect.new()
	_pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pic)
	# Dark on the left, where the words are, clearing towards the right.
	var shade:= TextureRect.new()
	var g:= Gradient.new()
	g.set_color(0, Color(0.03, 0.04, 0.07, 0.94))
	g.set_color(1, Color(0.03, 0.04, 0.07, 0.25))
	g.add_point(0.55, Color(0.03, 0.04, 0.07, 0.80))
	var gt:= GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	gt.width = 64
	gt.height = 4
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var margin:= MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 56 if side == "left" or side == "right" else 26)
	add_child(margin)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	margin.add_child(_box)

## Shows the end of campaign `c` (won: 0 victory, 1 defeat, 2 ceasefire).
func show_end(c: LiteCampaign, won: int, war: LiteMap) -> void:
	_c = c
	_won = won
	for n: Node in _box.get_children():
		_box.remove_child(n)
		n.queue_free()
	var key: String = ["victory", "defeat", "ceasefire"][won]
	_pic.texture = LiteStory.image(key)
	var tone: Color = [LiteTheme.GREEN, LiteTheme.RED, LiteTheme.AMBER][won]
	var won_ops: int = 0
	for r: int in c.results:
		if r == 0:
			won_ops += 1
	var days: int = int(c.clock / LiteRules.DAY)
	_box.add_child(_label("CAMPAIGN OVER  ·  %d DAYS  ·  %d OPERATIONS" % [days, c.ops], 13, LiteTheme.MUTED, LiteGlyphs.bold))
	var title: Label = _label(["VICTORY", "DEFEAT", "CEASEFIRE"][won], 64, tone, LiteGlyphs.black)
	_box.add_child(title)
	var line: Array = LiteStory.end_slide(won, war)
	_box.add_child(_label(String(line[1]).replace("\n", " "), 18, LiteTheme.TEXT, LiteGlyphs.font))
	# The rank the war earned.
	var rank: String = _rank(c, won, won_ops)
	var rr:= HBoxContainer.new()
	rr.add_theme_constant_override("separation", 12)
	var star:= _Medal.new()
	star.glyph = LiteGlyph.CAPITAL
	star.earned = true
	star.small = true
	rr.add_child(star)
	var rv:= VBoxContainer.new()
	rv.add_theme_constant_override("separation", 0)
	rv.add_child(_label("RANK AWARDED", 11, LiteTheme.MUTED, LiteGlyphs.bold))
	rv.add_child(_label(rank, 22, Color("#F2C14E"), LiteGlyphs.black))
	rv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rr.add_child(rv)
	_box.add_child(rr)
	# The war in figures.
	var tiles:= HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 10)
	_box.add_child(tiles)
	for t: Array in [["%d" % days, "days of war"], ["%d / %d" % [won_ops, c.ops], "operations won"],
			["%d" % c.taken[0], "regions freed"], ["%d" % c.downed, "enemy weapons shot down"], ["%d" % c.sites, "enemy sites destroyed"]]:
		tiles.add_child(_tile(t[0], t[1]))
	# The medals: those earned bright (the first time ever, marked NEW), the
	# rest faint, to aim for next time.
	var earned: Array[String] = _earned(c, won, won_ops)
	var before: Dictionary = _load()
	var newly: Array[String] = []
	for k: String in earned:
		if not before.has(k):
			newly.append(k)
			before[k] = true
	_save(before)
	_box.add_child(_label("MEDALS  ·  %d OF %d" % [before.size(), MEDALS.size()], 13, LiteTheme.MUTED, LiteGlyphs.bold))
	_medals = HBoxContainer.new()
	_medals.add_theme_constant_override("separation", 6)
	_box.add_child(_medals)
	_medals2 = HBoxContainer.new()
	_medals2.add_theme_constant_override("separation", 6)
	_box.add_child(_medals2)
	var order: Array = MEDALS.duplicate()
	order.sort_custom(func(a: Array, b: Array) -> bool: return earned.has(a[0]) and not earned.has(b[0]))
	var shown: Array[_Medal] = []
	for i: int in order.size():
		var md: Array = order[i]
		var m:= _Medal.new()
		m.glyph = md[3]
		m.title = md[1]
		m.what = md[2]
		m.earned = earned.has(md[0])
		m.ever = before.has(md[0])
		m.fresh = newly.has(md[0])
		m.tooltip_text = "%s: %s" % [md[1], md[2]]
		(_medals if i < 5 else _medals2).add_child(m)
		shown.append(m)
	# Every operation as a dot: won green, lost red.
	var dots:= HBoxContainer.new()
	dots.add_theme_constant_override("separation", 6)
	dots.add_child(_label("THE WAR", 11, LiteTheme.MUTED, LiteGlyphs.bold))
	for i: int in c.results.size():
		var d:= ColorRect.new()
		d.custom_minimum_size = Vector2(16, 16)
		d.color = LiteTheme.GREEN if c.results[i] == 0 else LiteTheme.RED
		d.tooltip_text = c.history[i] if i < c.history.size() else ""
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dots.add_child(d)
	_box.add_child(dots)
	var spacer:= Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box.add_child(spacer)
	var buttons:= HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	_box.add_child(buttons)
	buttons.add_child(_button("New campaign", true, func() -> void:
		visible = false
		main.ui._show_screen(null)
		main.start_campaign(true)))
	buttons.add_child(_button("Main menu", false, func() -> void:
		visible = false
		main.to_title()))
	visible = true
	get_parent().move_child(self, -1)
	# Coming in: the title, then the medals one at a time.
	title.modulate.a = 0.0
	create_tween().tween_property(title, "modulate:a", 1.0, 0.6)
	for k: int in shown.size():
		var m: _Medal = shown[k]
		m.pop = 0.0
		var tw: Tween = create_tween()
		tw.tween_interval(0.5 + k * 0.12)
		tw.tween_property(m, "pop", 1.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if m.earned:
			tw.tween_callback(func() -> void: main.audio.click())

## The rank the war earned: from Major to Marshal of the Air Defence.
static func _rank(c: LiteCampaign, won: int, won_ops: int) -> String:
	var score: float = 0.0
	if c.ops > 0:
		score += 50.0 * won_ops / c.ops
	score += 6.0 * c.taken[0] - 8.0 * c.taken[1]
	score += 25.0 if won == 0 else (5.0 if won == 2 else -15.0)
	score += minf(15.0, c.downed / 20.0)
	var ranks: Array[String] = ["Major", "Colonel", "Brigadier General", "General of the Air Defence", "Marshal of the Air Defence"]
	var at: int = clampi(int(score / 25.0), 0, ranks.size() - 1)
	return ranks[at]

static func _earned(c: LiteCampaign, won: int, won_ops: int) -> Array[String]:
	var out: Array[String] = []
	if won == 0:
		out.append("victory")
		if c.ops <= 6:
			out.append("blitz")
		if c.taken[1] >= 2:
			out.append("brink")
	if c.ops > 0 and won_ops == c.ops:
		out.append("flawless")
	if c.taken[1] == 0 and won != 1:
		out.append("no_step_back")
	if c.taken[0] >= 5:
		out.append("liberator")
	if c.downed >= 150:
		out.append("clear_skies")
	if c.kinds_taken.has(LiteMission.ENERGY):
		out.append("lights_out")
	if c.kinds_taken.has(LiteMission.EW):
		out.append("signal_lost")
	if c.kinds_taken.has(LiteMission.MILITARY):
		out.append("ghost_hunter")
	return out

static func _load() -> Dictionary:
	var f:= ConfigFile.new()
	var out: Dictionary = {}
	if f.load(PATH) == OK:
		for k: String in f.get_section_keys("medals") if f.has_section("medals") else PackedStringArray():
			out[k] = true
	return out

static func _save(d: Dictionary) -> void:
	if LiteSettings.dry:
		return
	var f:= ConfigFile.new()
	for k: String in d:
		f.set_value("medals", k, true)
	f.save(PATH)

func _tile(value: String, what: String) -> Control:
	var p:= PanelContainer.new()
	var box: StyleBoxFlat = LiteGlyphs.box(Color(LiteTheme.PANEL, 0.85), LiteTheme.BORDER, 0, 12)
	p.add_theme_stylebox_override("panel", box)
	p.custom_minimum_size = Vector2(150, 0)
	var v:= VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	v.add_child(_label(value, 30, LiteTheme.TEXT, LiteGlyphs.black))
	v.add_child(_label(what, 12, LiteTheme.MUTED, LiteGlyphs.font))
	return p

func _button(text: String, primary: bool, pressed: Callable) -> Control:
	var b:= LiteCmdButton.new()
	b.text = text.to_upper()
	b.font_size = 14
	b.bar_left = false
	b.selected = primary
	b.custom_minimum_size = Vector2(220, 46)
	b.clicked = func() -> void:
		main.audio.click()
		pressed.call()
	return b

static func _label(s: String, size_: int, col: Color, f: Font) -> Label:
	var l:= Label.new()
	l.text = s
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size_)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


## A medal: a striped ribbon, a gold disc with its symbol, the name and what
## earns it under it. Faint when not earned; NEW on one just won.
class _Medal extends Control:
	var glyph: int = LiteGlyph.CAPITAL
	var title: String = ""
	var what: String = ""
	var earned: bool = false
	var ever: bool = false
	var fresh: bool = false
	var small: bool = false
	var pop: float = 1.0:
		set(v):
			pop = v
			queue_redraw()

	func _ready() -> void:
		custom_minimum_size = Vector2(52, 60) if small else Vector2(150, 100)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		var a: float = (1.0 if earned else (0.55 if ever else 0.28)) * clampf(pop, 0.0, 1.0)
		var s: float = lerpf(0.6, 1.0, clampf(pop, 0.0, 1.2))
		var cx: float = size.x / 2.0
		var r: float = (17.0 if small else 22.0) * s
		var cy: float = (36.0 if small else 42.0)
		# The ribbon: blue and yellow stripes.
		var rw: float = r * 1.2
		var top: float = cy - r - (16.0 if small else 22.0) * s
		var stripes: Array[Color] = [Color("#2F6FD6"), Color("#F2C14E"), Color("#2F6FD6"), Color("#F2C14E"), Color("#2F6FD6")]
		for i: int in 5:
			draw_rect(Rect2(cx - rw / 2.0 + i * rw / 5.0, top, rw / 5.0 + 0.5, cy - top - r * 0.6), Color(stripes[i], a))
		var gold: Color = Color("#E9B949") if earned else Color("#9AA7B4")
		draw_circle(Vector2(cx, cy), r, Color(gold.darkened(0.35), a), true, -1, true)
		draw_circle(Vector2(cx, cy), r * 0.84, Color(gold, a), true, -1, true)
		LiteGlyphs.draw_ci(self, glyph, Vector2(cx, cy), r / 7.5, Color(Color("#3A2A06"), a), -PI / 4 if glyph == LiteGlyph.BALLISTIC else 0.0)
		if small:
			return
		var f: Font = LiteGlyphs.bold
		draw_string(f, Vector2(0, cy + r + 18), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color(LiteTheme.TEXT, maxf(a, 0.45)))
		draw_string(LiteGlyphs.font, Vector2(4, cy + r + 32), what, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 11, Color(LiteTheme.MUTED, maxf(a, 0.4)))
		if fresh:
			var tw: float = f.get_string_size("NEW", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 10.0
			draw_rect(Rect2(cx + r * 0.5, cy - r - 4, tw, 15), Color("#F05B50"))
			draw_string(f, Vector2(cx + r * 0.5 + 5, cy - r + 7), "NEW", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
