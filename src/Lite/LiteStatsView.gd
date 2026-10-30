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
var _tabs: Array[LiteChip] = []
var _close: LiteChip = null
var _map_tex: ImageTexture = null
var _heat_tex: ImageTexture = null
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
		var c:= LiteChip.new()
		c.text = names[i]
		c.clicked = func() -> void:
			show_tab(k)
			main.audio.click()
		add_child(c)
		_tabs.append(c)
	_close = LiteChip.new()
	_close.text = "Close · Esc"
	_close.clicked = func() -> void:
		main.audio.click()
		visible = false
	add_child(_close)
	resized.connect(_layout)

func open(p_tab: int = 0) -> void:
	_build_map()
	_build_heat()
	visible = true
	show_tab(p_tab)
	_layout()

func show_tab(k: int) -> void:
	tab = k
	for i: int in _tabs.size():
		_tabs[i].selected = i == k
	var n: int = main.sim.stats.reports.size() if main != null and main.sim != null else 0
	_tabs[1].text = "Attack reports · %d" % n
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
		var w: float = 150.0 if i == 1 else 110.0
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
	for y: int in h:
		for x: int in w:
			var id: int = ids[y * w + x]
			if id == LiteMap.NONE:
				continue
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
				col = Color(0.08, 0.08, 0.09)
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
	for y: int in h:
		for x: int in w:
			var t: float = sqrt(v[y * w + x] / top) if top > 0 else 0.0
			if t < 0.04:
				continue
			img.set_pixel(x, y, Color(heat_color(t), clampf(t * 1.8, 0, 0.92)))
	_heat_tex = ImageTexture.create_from_image(img)

static func heat_color(t: float) -> Color:
	return HEAT_LOW.lerp(HEAT_MID, clampf(t * 1.6, 0, 1)) if t < 0.62 else HEAT_MID.lerp(HEAT_HIGH, clampf((t - 0.62) / 0.38, 0, 1))

# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if main == null or main.sim == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(LiteGlyphs.PAGE, 0.86))
	var p: Rect2 = _panel_rect()
	draw_style_box(_panel, p)
	var st: LiteStats = main.sim.stats
	var x: float = p.position.x + 28
	draw_string(LiteGlyphs.bold, Vector2(x, p.position.y + 46), "War statistics", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, LiteGlyphs.TEXT)
	var t: float = main.sim.time
	draw_string(LiteGlyphs.font, Vector2(x, p.position.y + 68), "From %s to %s · %s of war" % [main.clock_text(0, true), main.clock_text(t, true), LiteHud.duration(t)], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteGlyphs.MUTED)
	var body:= Rect2(x, p.position.y + 88, p.size.x - 56, p.size.y - 88 - 24)
	if tab == 0:
		_overview(body, st)
	else:
		_reports(body, st)

func _card_at(r: Rect2, title: String, sub: String) -> Rect2:
	draw_style_box(_card, r)
	draw_string(LiteGlyphs.bold, r.position + Vector2(18, 28), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, LiteGlyphs.TEXT)
	draw_string(LiteGlyphs.font, r.position + Vector2(18, 46), sub, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 36, 11, LiteGlyphs.MUTED)
	return Rect2(r.position + Vector2(18, 60), r.size - Vector2(36, 74))

func _overview(body: Rect2, st: LiteStats) -> void:
	var gap: float = 14
	var top_h: float = floorf(body.size.y * 0.54)
	var a_w: float = floorf((body.size.x - gap) * 0.56)
	_hours(Rect2(body.position, Vector2(a_w, top_h)), st)
	_density(Rect2(body.position + Vector2(a_w + gap, 0), Vector2(body.size.x - a_w - gap, top_h)), st)
	var y: float = body.position.y + top_h + gap
	var h: float = body.end.y - y
	var w: float = floorf((body.size.x - 2 * gap) / 3)
	_types(Rect2(body.position.x, y, w, h), st)
	_alerts(Rect2(body.position.x + w + gap, y, w, h), st)
	_regions(Rect2(body.position.x + 2 * (w + gap), y, body.end.x - body.position.x - 2 * (w + gap), h), st)

static func _nice(v: int) -> int:
	for n: int in [5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 5000]:
		if v <= n:
			return n
	return v

## Launches at us, hour by hour, stacked by weapon.
func _hours(card: Rect2, st: LiteStats) -> void:
	var c: Rect2 = _card_at(card, "Launches by hour", "Enemy drones and missiles launched at us in each hour of the war")
	var total: int = st.launched[0] + st.launched[1] + st.launched[2]
	draw_string(LiteGlyphs.bold, card.position + Vector2(0, 38), str(total), HORIZONTAL_ALIGNMENT_RIGHT, card.size.x - 18, 28, LiteGlyphs.TEXT)
	draw_string(LiteGlyphs.font, card.position + Vector2(0, 54), "in total", HORIZONTAL_ALIGNMENT_RIGHT, card.size.x - 18, 10, LiteGlyphs.MUTED)
	# Legend along the bottom.
	var lx: float = c.position.x
	for a: int in 3:
		draw_circle(Vector2(lx + 4, c.end.y - 4), 4, ARM_COLORS[a], true, -1, true)
		var s: String = "%s · %d" % [ARM_NAMES[a], st.launched[a]]
		draw_string(LiteGlyphs.font, Vector2(lx + 13, c.end.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LiteGlyphs.MUTED)
		lx += LiteGlyphs.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 30
	var chart:= Rect2(c.position + Vector2(28, 8), c.size - Vector2(28, 52))
	var hours: int = maxi(1, int(main.sim.time / 60.0) + 1)
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
			draw_string(LiteGlyphs.font, Vector2(bx - 6, chart.end.y + 16), "%02d" % ((21 + hour) % 24), HORIZONTAL_ALIGNMENT_CENTER, bw + 12, 10, LiteGlyphs.FAINT)
	if total == 0:
		draw_string(LiteGlyphs.font, chart.get_center() + Vector2(-150, 0), "Nothing launched at us yet.", HORIZONTAL_ALIGNMENT_CENTER, 300, 12, LiteGlyphs.MUTED)

## Where the enemy's routes ran, over our map.
func _density(card: Rect2, st: LiteStats) -> void:
	var c: Rect2 = _card_at(card, "Route density", "The brighter, the more enemy drones and missiles flew there")
	var land: Rect2 = main.map.land_rect
	var area:= Rect2(c.position, c.size - Vector2(0, 22))
	var k: float = minf(area.size.x / land.size.x, area.size.y / land.size.y)
	var dst:= Rect2(area.get_center() - land.size * k / 2, land.size * k)
	if _map_tex != null:
		draw_texture_rect_region(_map_tex, dst, Rect2(land.position / 4.0, land.size / 4.0))
	if _heat_tex != null:
		draw_texture_rect_region(_heat_tex, dst, Rect2(land.position / LiteStats.CELL, land.size / LiteStats.CELL))
	# Legend.
	var ly: float = c.end.y - 6
	var lx: float = c.get_center().x - 120
	draw_string(LiteGlyphs.font, Vector2(lx - 44, ly + 4), "rarer", HORIZONTAL_ALIGNMENT_RIGHT, 40, 10, LiteGlyphs.MUTED)
	for i: int in 48:
		draw_rect(Rect2(lx + i * 5, ly - 3, 5, 6), heat_color(i / 47.0))
	draw_string(LiteGlyphs.font, Vector2(lx + 246, ly + 4), "more often", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LiteGlyphs.MUTED)

## The mix of weapons sent at us, and how much of each was shot down.
func _types(card: Rect2, st: LiteStats) -> void:
	var c: Rect2 = _card_at(card, "By type", "Share of each weapon, and how much of it was shot down")
	var total: int = st.launched[0] + st.launched[1] + st.launched[2]
	var r: float = minf(54.0, c.size.y * 0.36)
	var at:= Vector2(c.position.x + r + 6, c.position.y + r + 8)
	if total == 0:
		draw_arc(at, r, 0, TAU, 64, LiteGlyphs.LINE, 18, true)
	else:
		var a0: float = -PI / 2
		for a: int in 3:
			if st.launched[a] <= 0:
				continue
			var span: float = TAU * st.launched[a] / total
			draw_arc(at, r, a0 + 0.02, a0 + span - 0.02, maxi(4, int(64 * span / TAU)), ARM_COLORS[a], 18, true)
			a0 += span
	draw_string(LiteGlyphs.bold, at + Vector2(-40, 6), str(total), HORIZONTAL_ALIGNMENT_CENTER, 80, 20, LiteGlyphs.TEXT)
	draw_string(LiteGlyphs.font, at + Vector2(-40, 20), "launched", HORIZONTAL_ALIGNMENT_CENTER, 80, 10, LiteGlyphs.MUTED)
	var lx: float = at.x + r + 22
	var ly: float = c.position.y + 10
	for a: int in 3:
		draw_circle(Vector2(lx + 4, ly + 6), 4, ARM_COLORS[a], true, -1, true)
		var pct: int = roundi(100.0 * st.launched[a] / maxi(1, total))
		draw_string(LiteGlyphs.bold, Vector2(lx + 14, ly + 10), "%s  %d · %d%%" % [ARM_NAMES[a], st.launched[a], pct], HORIZONTAL_ALIGNMENT_LEFT, c.end.x - lx - 14, 11, LiteGlyphs.TEXT)
		var down: String = ("shot down %d%%" % roundi(100.0 * st.downed[a] / st.launched[a])) if st.launched[a] > 0 else "none yet"
		draw_string(LiteGlyphs.font, Vector2(lx + 14, ly + 25), down, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LiteGlyphs.MUTED)
		ly += 38
	var ours: int = st.our_launched[0] + st.our_launched[1] + st.our_launched[2]
	var line: String = "Our strikes: %d launched · %d shot down · %d hits" % [ours, st.our_downed[0] + st.our_downed[1] + st.our_downed[2], st.our_hits]
	draw_string(LiteGlyphs.font, Vector2(c.position.x, c.end.y), line, HORIZONTAL_ALIGNMENT_LEFT, c.size.x, 11, LiteGlyphs.OURS)

## Air alerts over our regions: four figures and the count under alert,
## minute by minute.
func _alerts(card: Rect2, st: LiteStats) -> void:
	var c: Rect2 = _card_at(card, "Air alerts", "Over our regions since the war began")
	var tw: float = (c.size.x - 8) / 2
	var th: float = 48.0
	var longest: String = LiteHud.duration(st.longest) if st.longest > 0 else "—"
	var where: String = main.region_name(st.longest_region) if st.longest_region >= 0 else ""
	var tiles: Array = [
		["Alerts", str(st.alerts), ""],
		["Median length", LiteHud.duration(st.median_alert()) if st.alert_minutes.size() > 0 else "—", ""],
		["Longest", longest, where],
		["Most at once", "%d region%s" % [st.peak, "" if st.peak == 1 else "s"], ""],
	]
	for i: int in 4:
		var tr:= Rect2(c.position + Vector2((i % 2) * (tw + 8), (i / 2) * (th + 8)), Vector2(tw, th))
		draw_style_box(_tile, tr)
		draw_string(LiteGlyphs.font, tr.position + Vector2(10, 16), tiles[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LiteGlyphs.MUTED)
		draw_string(LiteGlyphs.bold, tr.position + Vector2(10, 38), tiles[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, LiteGlyphs.TEXT)
		if tiles[i][2] != "":
			var vw: float = LiteGlyphs.bold.get_string_size(tiles[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			draw_string(LiteGlyphs.font, tr.position + Vector2(16 + vw, 38), tiles[i][2], HORIZONTAL_ALIGNMENT_LEFT, tr.size.x - vw - 24, 10, LiteGlyphs.MUTED)
	var chart:= Rect2(c.position.x, c.position.y + 2 * th + 22, c.size.x, c.end.y - (c.position.y + 2 * th + 22))
	var n: int = st.timeline.size()
	if n < 2 or chart.size.y < 16:
		return
	var top: float = maxf(4, st.peak)
	var pts:= PackedVector2Array()
	pts.append(Vector2(chart.position.x, chart.end.y))
	for i: int in n:
		var px: float = chart.position.x + chart.size.x * i / (n - 1)
		pts.append(Vector2(px, chart.end.y - chart.size.y * st.timeline[i] / top))
	pts.append(Vector2(chart.end.x, chart.end.y))
	draw_colored_polygon(pts, Color(LiteGlyphs.MISSILE_ALERT, 0.18))
	draw_polyline(pts.slice(1, pts.size() - 1), LiteGlyphs.MISSILE_ALERT, 1.5, true)
	draw_line(Vector2(chart.position.x, chart.end.y), Vector2(chart.end.x, chart.end.y), LiteGlyphs.LINE, 1.0)
	draw_string(LiteGlyphs.font, chart.position + Vector2(0, -4), "regions under alert", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LiteGlyphs.FAINT)

## Our regions crossed by the most enemy drones and missiles.
func _regions(card: Rect2, st: LiteStats) -> void:
	var c: Rect2 = _card_at(card, "Most crossed regions", "How many enemy drones and missiles flew over each")
	var order: Array[int] = []
	for i: int in st.crossed.size():
		if st.crossed[i] > 0:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return st.crossed[a] > st.crossed[b])
	if order.is_empty():
		draw_string(LiteGlyphs.font, c.position + Vector2(0, 20), "Nothing has crossed our land yet.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteGlyphs.MUTED)
		return
	var rows: int = mini(order.size(), clampi(int(c.size.y / 27), 1, 7))
	var rh: float = c.size.y / rows
	var top: float = st.crossed[order[0]]
	for k: int in rows:
		var i: int = order[k]
		var y: float = c.position.y + k * rh
		draw_string(LiteGlyphs.font, Vector2(c.position.x, y + 12), "%d" % (k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LiteGlyphs.FAINT)
		draw_string(LiteGlyphs.bold, Vector2(c.position.x + 16, y + 12), main.map.regions[i].name, HORIZONTAL_ALIGNMENT_LEFT, c.size.x - 70, 12, LiteGlyphs.TEXT)
		draw_string(LiteGlyphs.font, Vector2(c.position.x, y + 12), str(st.crossed[i]), HORIZONTAL_ALIGNMENT_RIGHT, c.size.x, 11, LiteGlyphs.MUTED)
		var bar:= Rect2(c.position.x + 16, y + 17, c.size.x - 16, 4)
		draw_rect(bar, LiteGlyphs.LINE)
		var f: float = bar.size.x * st.crossed[i] / top
		var a: Vector2 = bar.position
		draw_polygon(PackedVector2Array([a, a + Vector2(f, 0), a + Vector2(f, 4), a + Vector2(0, 4)]),
			PackedColorArray([LiteGlyphs.OURS, HEAT_MID.lerp(LiteGlyphs.OURS, 1 - f / bar.size.x), HEAT_MID.lerp(LiteGlyphs.OURS, 1 - f / bar.size.x), LiteGlyphs.OURS]))

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
