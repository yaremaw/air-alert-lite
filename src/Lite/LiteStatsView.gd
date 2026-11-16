class_name LiteStatsView
extends Control
## The statistics screen: the war so far as our side saw it, on one page
## (launches at us by hour and weapon, where the routes ran, weapon mix and
## how much was shot down, air alerts, the regions crossed most), and the
## reports of the large attacks. T or the Stats chip opens it; the war waits
## while it is open.

const ARM_COLORS: Array[Color] = [Color("#f2a541"), Color("#e0574a"), Color("#a77bff")]
const ARM_NAMES: Array[String] = ["Drones", "Cruise missiles", "Ballistic missiles"]
const HEAT_LOW: Color = Color("#4a6cf7")
const HEAT_MID: Color = Color("#f2a541")
const HEAT_HIGH: Color = Color("#ff4a3d")

var main: LiteMain = null
var tab: int = 0
var _tabs: Array[Control] = []
var _close: Control = null
## Our land's box, in map units: the flight map shows our country only.
var _ours: Rect2 = Rect2()
var _map_tex: ImageTexture = null
var _heat_tex: ImageTexture = null
## Where the routes went, in map units: the picture takes it in as well as
## the land, so a route out over the sea is not cut off at the coast's box.
var _heat_box: Rect2 = Rect2()
var _panel: StyleBoxFlat = LiteGlyphs.box(LiteGlyphs.PAGE, LiteGlyphs.LINE, 16)
var _card: StyleBoxFlat = LiteGlyphs.box(LiteGlyphs.PANEL, LiteGlyphs.LINE, 12)
var _tile: StyleBoxFlat = LiteGlyphs.box(LiteGlyphs.PANEL_HI, LiteGlyphs.PANEL_HI, 8)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var names: Array[String] = ["Overview", "Attack reports"]
	for i: int in 2:
		var k: int = i
		var c: Control = _button(names[i])
		c.set("clicked", func() -> void:
			show_tab(k)
			main.audio.click())
		add_child(c)
		_tabs.append(c)
	_close = _button("Close · Esc")
	_close.set("clicked", func() -> void:
		main.audio.click()
		visible = false)
	add_child(_close)
	resized.connect(_layout)

## A button in the look of the rest of the game.
func _button(text: String) -> Control:
	if LiteTheme.command:
		var b:= LiteCmdButton.new()
		b.text = text.to_upper()
		b.font_size = 10
		b.bar_left = false
		return b
	var c:= LiteChip.new()
	c.text = text
	return c

## A panel or card: the command look's notched panels, or the old boxes.
func _box(r: Rect2, card: bool) -> void:
	if LiteTheme.command:
		LiteCmdStyle.panel(self, r, LiteTheme.PANEL if card else LiteTheme.BG2, LiteTheme.BORDER)
	else:
		draw_style_box(_card if card else _panel, r)

func open(p_tab: int = 0) -> void:
	_build_map()
	_build_heat()
	visible = true
	show_tab(p_tab)
	_layout()

func show_tab(k: int) -> void:
	tab = k
	for i: int in _tabs.size():
		_tabs[i].set("selected", i == k)
	var n: int = main.sim.stats.reports.size() if main != null and main.sim != null else 0
	var t1: String = "Attack reports · %d" % n
	_tabs[1].set("text", t1.to_upper() if LiteTheme.command else t1)
	queue_redraw()

func _panel_rect() -> Rect2:
	return Rect2(Vector2(24, 20), size - Vector2(48, 40))

func _layout() -> void:
	var p: Rect2 = _panel_rect()
	var y: float = p.position.y + 26
	var x: float = p.end.x - 26 - 118
	_close.position = Vector2(x, y)
	_close.size = Vector2(118, 30)
	for i: int in range(_tabs.size() - 1, -1, -1):
		var w: float = 170.0 if i == 1 else 110.0
		x -= w + 8
		_tabs[i].position = Vector2(x, y)
		_tabs[i].size = Vector2(w, 30)

# ---------------------------------------------------------------- pictures

## Our map, small: one pixel for 4 map units, land in its country's grey and
## the borders darker.
func _build_map() -> void:
	var map: LiteMap = main.map
	const K: int = 4
	var w: int = LiteMap.W / K
	var h: int = LiteMap.H / K
	var img: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var ids:= PackedInt32Array()
	ids.resize(w * h)
	for y: int in h:
		for x: int in w:
			ids[y * w + x] = map.cell[(y * K + K / 2) * LiteMap.W + x * K + K / 2]
	_ours = Rect2()
	for y: int in h:
		for x: int in w:
			var id: int = ids[y * w + x]
			if id == LiteMap.NONE or map.regions[id].side != 0:
				continue
			var cb:= Rect2(x * K, y * K, K, K)
			_ours = cb if _ours.size == Vector2.ZERO else _ours.merge(cb)
			var side: int = map.regions[id].side
			var col: Color = LiteGlyphs.OUR_LAND if side == 0 else LiteGlyphs.ENEMY_LAND.lightened(0.04)
			var edge: bool = false
			var front: bool = false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= w or ny >= h:
					continue
				var n: int = ids[ny * w + nx]
				if n != id and n != LiteMap.NONE:
					edge = true
					front = front or map.regions[n].side != side
			if front:
				col = LiteTheme.RED.darkened(0.3) if LiteTheme.command else Color(0.08, 0.08, 0.09)
			elif edge:
				col = col.darkened(0.3)
			img.set_pixel(x, y, col)
	_map_tex = ImageTexture.create_from_image(img)

## Where the enemy's drones and missiles flew: the density grid, smoothed,
## from transparent through blue and orange to red.
func _build_heat() -> void:
	var st: LiteStats = main.sim.stats
	var w: int = LiteStats.GW
	var h: int = LiteStats.GH
	var v: PackedFloat32Array = st.heat.duplicate()
	for pass_: int in 2:
		var o: PackedFloat32Array = v.duplicate()
		for y: int in h:
			for x: int in w:
				var sum: float = 0.0
				var n: int = 0
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						var xx: int = x + dx
						var yy: int = y + dy
						if xx >= 0 and yy >= 0 and xx < w and yy < h:
							sum += v[yy * w + xx]
							n += 1
				o[y * w + x] = sum / n
		v = o
	var top: float = 0.0
	for f: float in v:
		top = maxf(top, f)
	var img: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	_heat_box = Rect2()
	for y: int in h:
		for x: int in w:
			var t: float = sqrt(v[y * w + x] / top) if top > 0 else 0.0
			if t < 0.04:
				continue
			# Over our land only.
			var mc: Vector2 = Vector2((x + 0.5) * LiteStats.CELL, (y + 0.5) * LiteStats.CELL)
			if main.map.side_at(mc) != 0:
				continue
			var cell_box:= Rect2(x * LiteStats.CELL, y * LiteStats.CELL, LiteStats.CELL, LiteStats.CELL)
			_heat_box = cell_box if _heat_box.size == Vector2.ZERO else _heat_box.merge(cell_box)
			img.set_pixel(x, y, Color(heat_color(t), clampf(t * 1.8, 0, 0.92)))
	_heat_tex = ImageTexture.create_from_image(img)

static func heat_color(t: float) -> Color:
	return HEAT_LOW.lerp(HEAT_MID, clampf(t * 1.6, 0, 1)) if t < 0.62 else HEAT_MID.lerp(HEAT_HIGH, clampf((t - 0.62) / 0.38, 0, 1))

# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if main == null or main.sim == null:
		return
	var cmd: bool = LiteTheme.command
	draw_rect(Rect2(Vector2.ZERO, size), Color(LiteTheme.BG, 0.9) if cmd else Color(LiteGlyphs.PAGE, 0.86))
	var p: Rect2 = _panel_rect()
	_box(p, false)
	var st: LiteStats = main.sim.stats
	var x: float = p.position.x + 28
	var t: float = main.sim.time
	var sub: String = "From %s to %s · %s of war" % [main.clock_text(0, true), main.clock_text(t, true), LiteHud.duration(t)]
	if cmd:
		draw_string(LiteGlyphs.black, Vector2(x, p.position.y + 46), "WAR STATISTICS", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, LiteTheme.TEXT)
		draw_string(LiteGlyphs.bold, Vector2(x, p.position.y + 66), sub.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LiteTheme.MUTED)
		LiteCmdStyle.hatch(self, Rect2(x, p.position.y + 74, 260, 4), Color(LiteTheme.MUTED, 0.5))
		draw_rect(Rect2(x + 264, p.position.y + 74, 8, 4), LiteTheme.RED)
	else:
		draw_string(LiteGlyphs.bold, Vector2(x, p.position.y + 46), "War statistics", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, LiteGlyphs.TEXT)
		draw_string(LiteGlyphs.font, Vector2(x, p.position.y + 68), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteGlyphs.MUTED)
	var body:= Rect2(x, p.position.y + 88, p.size.x - 56, p.size.y - 88 - 24)
	if tab == 0:
		_overview(body, st)
	else:
		_reports(body, st)

func _card_at(r: Rect2, title: String, sub: String) -> Rect2:
	_box(r, true)
	if LiteTheme.command:
		draw_string(LiteGlyphs.black, r.position + Vector2(18, 28), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, LiteTheme.BLUE)
		draw_string(LiteGlyphs.font, r.position + Vector2(18, 46), sub, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 36, 11, LiteTheme.MUTED)
	else:
		draw_string(LiteGlyphs.bold, r.position + Vector2(18, 28), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, LiteGlyphs.TEXT)
		draw_string(LiteGlyphs.font, r.position + Vector2(18, 46), sub, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 36, 11, LiteGlyphs.MUTED)
	return Rect2(r.position + Vector2(18, 60), r.size - Vector2(36, 74))

func _overview(body: Rect2, st: LiteStats) -> void:
	var gap: float = 14
	var tiles_h: float = 92
	_tiles(Rect2(body.position, Vector2(body.size.x, tiles_h)), st)
	var y: float = body.position.y + tiles_h + gap
	var h: float = body.end.y - y
	var a_w: float = floorf((body.size.x - gap) * 0.55)
	_hours(Rect2(body.position.x, y, a_w, h), st)
	_density(Rect2(body.position.x + a_w + gap, y, body.size.x - a_w - gap, h), st)

## Four figures: what came at us, how much was shot down, the alerts, and the
## longest of them.
func _tiles(r: Rect2, st: LiteStats) -> void:
	var total: int = st.launched[0] + st.launched[1] + st.launched[2]
	var down: int = st.downed[0] + st.downed[1] + st.downed[2]
	var parts: PackedStringArray = PackedStringArray()
	for a: int in 3:
		if st.launched[a] > 0:
			parts.append("%d %s" % [st.launched[a], LiteGlyphs.plural(a, st.launched[a])])
	var tiles: Array = [
		["Launched at us", str(total), " · ".join(parts) if parts.size() > 0 else "nothing yet", LiteGlyphs.TEXT],
		["Shot down", ("%d%%" % roundi(100.0 * down / total)) if total > 0 else "—", "%d of %d" % [down, total], LiteGlyphs.GOOD],
		["Air alerts", str(st.alerts), ("median %s" % LiteHud.duration(st.median_alert())) if st.alert_minutes.size() > 0 else "over our regions", LiteGlyphs.YELLOW],
		["Longest alert", LiteHud.duration(st.longest) if st.longest > 0 else "—", main.region_name(st.longest_region) if st.longest_region >= 0 else "", LiteGlyphs.TEXT],
	]
	var gap: float = 14
	var w: float = (r.size.x - gap * 3) / 4
	for i: int in 4:
		var t:= Rect2(r.position + Vector2(i * (w + gap), 0), Vector2(w, r.size.y))
		_box(t, true)
		if LiteTheme.command:
			draw_rect(Rect2(t.position + Vector2(1, 1), Vector2(2, t.size.y - 2)), tiles[i][3])
			draw_string(LiteGlyphs.bold, t.position + Vector2(18, 26), String(tiles[i][0]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LiteTheme.MUTED)
			draw_string(LiteGlyphs.black, t.position + Vector2(18, 60), tiles[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, tiles[i][3])
		else:
			draw_string(LiteGlyphs.font, t.position + Vector2(18, 26), tiles[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteGlyphs.MUTED)
			draw_string(LiteGlyphs.bold, t.position + Vector2(18, 60), tiles[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, tiles[i][3])
		draw_string(LiteGlyphs.font, t.position + Vector2(18, 80), tiles[i][2], HORIZONTAL_ALIGNMENT_LEFT, w - 36, 11, LiteGlyphs.MUTED)

static func _nice(v: int) -> int:
	for n: int in [5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 5000]:
		if v <= n:
			return n
	return v

## Launches at us, day by day, stacked by weapon.
func _hours(card: Rect2, st: LiteStats) -> void:
	var c: Rect2 = _card_at(card, "Launches by day", "Enemy drones and missiles launched at us on each day of the war")
	var total: int = st.launched[0] + st.launched[1] + st.launched[2]
	# Legend along the bottom.
	var lx: float = c.position.x
	for a: int in 3:
		draw_circle(Vector2(lx + 4, c.end.y - 4), 4, ARM_COLORS[a], true, -1, true)
		var s: String = "%s · %d" % [ARM_NAMES[a], st.launched[a]]
		draw_string(LiteGlyphs.font, Vector2(lx + 13, c.end.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LiteGlyphs.MUTED)
		lx += LiteGlyphs.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 30
	var chart:= Rect2(c.position + Vector2(28, 8), c.size - Vector2(28, 52))
	var hours: int = maxi(1, int(main.sim.time / LiteRules.DAY) + 1)
	var first: int = maxi(0, hours - 24)
	var top: int = 1
	for i: int in range(first, mini(hours, st.hourly.size())):
		var hv: PackedInt32Array = st.hourly[i]
		top = maxi(top, hv[0] + hv[1] + hv[2])
	var nice: int = _nice(top)
	for k: int in 3:
		var gy: float = chart.end.y - chart.size.y * k / 2.0
		draw_line(Vector2(chart.position.x, gy), Vector2(chart.end.x, gy), LiteGlyphs.LINE, 1.0)
		draw_string(LiteGlyphs.font, Vector2(chart.position.x - 28, gy + 4), str(nice * k / 2), HORIZONTAL_ALIGNMENT_RIGHT, 22, 10, LiteGlyphs.FAINT)
	var n: int = hours - first
	var slot: float = chart.size.x / maxf(n, 12)
	var bw: float = minf(26.0, slot * 0.62)
	for i: int in n:
		var hour: int = first + i
		var bx: float = chart.position.x + slot * i + (slot - bw) / 2
		var y: float = chart.end.y
		if hour < st.hourly.size():
			var hv: PackedInt32Array = st.hourly[hour]
			for a: int in 3:
				if hv[a] <= 0:
					continue
				var bh: float = chart.size.y * hv[a] / nice
				draw_rect(Rect2(bx, y - bh, bw, bh), ARM_COLORS[a])
				y -= bh
		if n <= 14 or i % 2 == 0:
			draw_string(LiteGlyphs.font, Vector2(bx - 6, chart.end.y + 16), str(main.day_of_month((hour + 0.5) * LiteRules.DAY)), HORIZONTAL_ALIGNMENT_CENTER, bw + 12, 10, LiteGlyphs.FAINT)
	if total == 0:
		draw_string(LiteGlyphs.font, chart.get_center() + Vector2(-150, 0), "Nothing launched at us yet.", HORIZONTAL_ALIGNMENT_CENTER, 300, 12, LiteGlyphs.MUTED)

## Where the enemy's routes ran, over our map, and the regions they
## crossed most.
func _density(card: Rect2, st: LiteStats) -> void:
	var c: Rect2 = _card_at(card, "Where they flew", "The brighter, the more enemy drones and missiles passed")
	var list_w: float = 150.0
	# The land and wherever the routes went, with a little sea round them.
	var land: Rect2 = _ours if _ours.size != Vector2.ZERO else main.map.land_rect
	land = land.grow(10).intersection(Rect2(0, 0, LiteMap.W, LiteMap.H))
	var area:= Rect2(c.position, c.size - Vector2(list_w + 12, 22))
	var k: float = minf(area.size.x / land.size.x, area.size.y / land.size.y)
	var dst:= Rect2(area.get_center() - land.size * k / 2, land.size * k)
	if _map_tex != null:
		draw_texture_rect_region(_map_tex, dst, Rect2(land.position / 4.0, land.size / 4.0))
	if _heat_tex != null:
		draw_texture_rect_region(_heat_tex, dst, Rect2(land.position / LiteStats.CELL, land.size / LiteStats.CELL))
	var ly: float = c.end.y - 6
	var lx: float = area.get_center().x - 80
	draw_string(LiteGlyphs.font, Vector2(lx - 44, ly + 4), "rarer", HORIZONTAL_ALIGNMENT_RIGHT, 40, 10, LiteGlyphs.MUTED)
	for i: int in 32:
		draw_rect(Rect2(lx + i * 5, ly - 3, 5, 6), heat_color(i / 31.0))
	draw_string(LiteGlyphs.font, Vector2(lx + 166, ly + 4), "more often", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LiteGlyphs.MUTED)
	# The regions crossed most.
	var x: float = c.end.x - list_w
	draw_string(LiteGlyphs.bold, Vector2(x, c.position.y + 12), "Crossed most", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteGlyphs.TEXT)
	var order: Array[int] = []
	for i: int in st.crossed.size():
		if st.crossed[i] > 0:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return st.crossed[a] > st.crossed[b])
	if order.is_empty():
		draw_string(LiteGlyphs.font, Vector2(x, c.position.y + 34), "nothing yet", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LiteGlyphs.MUTED)
		return
	var top: float = st.crossed[order[0]]
	for n: int in mini(3, order.size()):
		var i: int = order[n]
		var y: float = c.position.y + 38 + n * 44
		draw_string(LiteGlyphs.bold, Vector2(x, y), main.map.regions[i].name, HORIZONTAL_ALIGNMENT_LEFT, list_w, 12, LiteGlyphs.TEXT)
		draw_string(LiteGlyphs.font, Vector2(x, y + 16), ("1 drone or missile" if st.crossed[i] == 1 else "%d drones and missiles" % st.crossed[i]), HORIZONTAL_ALIGNMENT_LEFT, list_w, 10, LiteGlyphs.MUTED)
		draw_rect(Rect2(x, y + 22, list_w, 3), LiteGlyphs.LINE)
		draw_rect(Rect2(x, y + 22, list_w * st.crossed[i] / top, 3), HEAT_MID)

## The large attacks, newest first.
func _reports(body: Rect2, st: LiteStats) -> void:
	if st.reports.is_empty():
		draw_string(LiteGlyphs.bold, body.position + Vector2(0, 40), "No large attacks yet.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, LiteGlyphs.TEXT)
		draw_string(LiteGlyphs.font, body.position + Vector2(0, 62), "A report is written after every enemy attack of %d or more drones and missiles." % LiteStats.REPORT_MIN, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteGlyphs.MUTED)
		return
	var cols: int = 3
	var gap: float = 14
	var w: float = (body.size.x - gap * (cols - 1)) / cols
	var h: float = LiteReportCard.SIZE.y
	var rows: int = maxi(1, int((body.size.y + gap) / (h + gap)))
	var shown: int = mini(st.reports.size(), rows * cols)
	for k: int in shown:
		var r: LiteReport = st.reports[st.reports.size() - 1 - k]
		var at: Vector2 = body.position + Vector2((k % cols) * (w + gap), (k / cols) * (h + gap))
		LiteReportCard.draw_card(self, Rect2(at, Vector2(w, h)), r, main)
	if st.reports.size() > shown:
		draw_string(LiteGlyphs.font, Vector2(body.position.x, body.end.y), "and %d earlier" % (st.reports.size() - shown), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LiteGlyphs.MUTED)
