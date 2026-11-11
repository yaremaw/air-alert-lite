class_name LiteOpCard
extends Control
## A campaign operation in the war panel, under the budget: its title, each
## target with its icon (ticked off once destroyed) or the hits a held
## province has taken, the time left, the optional goal, and a storm while it
## lasts. In the panel rather than over the map, where it hid sites.

var main: LiteMain = null
var _redraw: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	var m: LiteMission = main.mission
	visible = m != null and main.started
	if not visible:
		return
	var rows: int = 2 + (m.targets.size() if m.kind != LiteMission.HOLD else 1)
	if m.optional != LiteMission.NONE:
		rows += 1
	if m.storm_until > main.sim.time:
		rows += 1
	if m.outage_until > main.sim.time:
		rows += 1
	if m.convoy != null:
		rows += 1
	var h: float = 14.0 + rows * 19.0
	if absf(custom_minimum_size.y - h) > 0.5:
		custom_minimum_size = Vector2(0, h)
	_redraw -= delta
	if _redraw <= 0:
		_redraw = 0.25
		queue_redraw()

func _draw() -> void:
	var m: LiteMission = main.mission
	if m == null:
		return
	var sim: LiteSim = main.sim
	var w: float = size.x
	draw_style_box(LiteGlyphs.box(Color(LiteGlyphs.OBJECTIVE, 0.08), Color(LiteGlyphs.OBJECTIVE, 0.45), 8), Rect2(Vector2.ZERO, size))
	var y: float = 18.0
	var head: String = "OPERATION %d · %s" % [m.number, m.title.to_upper()]
	draw_string(LiteGlyphs.black, Vector2(10, y), head, HORIZONTAL_ALIGNMENT_LEFT, w - 90, 10, LiteGlyphs.OBJECTIVE)
	var left: String
	var tone: Color = LiteGlyphs.MUTED
	if m.result < 0:
		# An attack has no deadline: the day of it; a defence, the time left.
		left = LiteHud.duration(m.time_left(sim)) if m.timed else "Day %d" % (int(sim.time / LiteRules.DAY) + 1)
	else:
		left = "Complete" if m.result == 0 else "Failed"
		tone = LiteGlyphs.GOOD if m.result == 0 else LiteGlyphs.ENEMY
	_right(LiteGlyphs.bold, y, left, 10, tone)
	y += 20.0
	if m.kind == LiteMission.HOLD:
		# Hits taken, as a bar filling towards the limit.
		draw_string(LiteGlyphs.font, Vector2(10, y), "Enemy hits", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteGlyphs.TEXT)
		_right(LiteGlyphs.bold, y, "%d/%d" % [m.hits, m.need], 12, LiteGlyphs.TEXT)
		var bar:= Rect2(10, y + 5, w - 20, 3)
		draw_rect(bar, Color(0, 0, 0, 0.4))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * minf(1.0, float(m.hits) / maxi(1, m.need)), 3)), LiteGlyphs.ENEMY)
		y += 19.0
	else:
		for t: LiteBuilding in m.targets:
			var gone: bool = not t.alive
			var col: Color = LiteGlyphs.GOOD if gone else LiteGlyphs.TEXT
			LiteGlyphs.draw_ci(self, LiteGlyphs.of(t.kind), Vector2(18, y - 4), 0.85, Color(col, 0.5 if gone else 1.0))
			draw_string(LiteGlyphs.font, Vector2(32, y), LiteGlyphs.name(t.kind), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(col, 0.6 if gone else 1.0))
			if gone:
				_right(LiteGlyphs.bold, y, "✓", 12, LiteGlyphs.GOOD)
			y += 19.0
	if m.optional != LiteMission.NONE:
		var oc: Color = LiteGlyphs.GOOD if m.optional_done else (LiteGlyphs.MUTED if m.optional_open() else LiteGlyphs.FAINT)
		draw_string(LiteGlyphs.font, Vector2(10, y), "Optional: " + m.optional_text(true), HORIZONTAL_ALIGNMENT_LEFT, w - 70, 11, oc)
		_right(LiteGlyphs.font, y, m.optional_progress(), 11, oc)
		y += 19.0
	if m.storm_until > sim.time:
		_timed(y, "Storm: drones grounded", m.storm_until - sim.time)
		y += 19.0
	if m.outage_until > sim.time:
		_timed(y, "Enemy SAMs silent", m.outage_until - sim.time)
		y += 19.0
	if m.convoy != null:
		_timed(y, "Convoy: +$%d" % LiteMission.CONVOY_REWARD, m.convoy_until - sim.time)

## Text ending `10` short of the right edge (draw_string only aligns right
## within a given width).
func _right(font: Font, y: float, text: String, fsize: int, col: Color) -> void:
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_string(font, Vector2(size.x - 10 - tw, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)

func _timed(y: float, what: String, left: float) -> void:
	draw_string(LiteGlyphs.bold, Vector2(10, y), what, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LiteGlyphs.YELLOW)
	_right(LiteGlyphs.font, y, LiteHud.duration(maxf(0.0, left)), 11, LiteGlyphs.YELLOW)
