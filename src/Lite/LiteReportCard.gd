class_name LiteReportCard
extends Control
## After a large enemy attack: a card with when it came, how many drones and
## missiles, how many were shot down by type, and what was lost. It shows
## for a while at the top left of the map; a click dismisses it.

const BG: Color = Color("#1b2a3d")
const EDGE: Color = Color("#2e4361")
const SOFT: Color = Color("#9fb3cc")
const SIZE: Vector2 = Vector2(320, 262)
const SHOW_FOR: float = 14.0

var main: LiteMain = null
var report: LiteReport = null
var _age: float = 99.0
static var _box: StyleBoxFlat = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	position = Vector2(16, 16)
	size = SIZE
	visible = false

func show_report(r: LiteReport) -> void:
	report = r
	_age = 0.0
	visible = true
	queue_redraw()

func _process(delta: float) -> void:
	if not visible:
		return
	_age += delta
	modulate.a = clampf(_age / 0.3, 0, 1) * clampf((SHOW_FOR - _age) / 0.6, 0, 1)
	position.x = 16 - 24 * (1 - clampf(_age / 0.3, 0, 1))
	if _age >= SHOW_FOR:
		visible = false

func _gui_input(e: InputEvent) -> void:
	var mb:= e as InputEventMouseButton
	if mb != null and mb.pressed:
		visible = false
		accept_event()

func _draw() -> void:
	if report != null:
		draw_card(self, Rect2(Vector2.ZERO, size), report, main)

static func draw_card(ci: CanvasItem, rect: Rect2, r: LiteReport, main: LiteMain) -> void:
	if _box == null:
		_box = LiteGlyphs.box(BG, EDGE, 12)
	ci.draw_style_box(_box, rect)
	var x: float = rect.position.x + 18
	var y: float = rect.position.y
	var w: float = rect.size.x - 36
	var bold: Font = LiteGlyphs.bold
	var font: Font = LiteGlyphs.font
	# When.
	ci.draw_string(bold, Vector2(x, y + 32), main.clock_text(r.start, true), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, LiteGlyphs.TEXT)
	ci.draw_string(font, Vector2(x, y + 50), "attack until %s" % main.clock_text(r.end, false), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, SOFT)
	# How many.
	ci.draw_string(bold, Vector2(x, y + 40), str(r.total), HORIZONTAL_ALIGNMENT_RIGHT, w, 32, LiteGlyphs.TEXT)
	ci.draw_string(font, Vector2(x, y + 56), "drones and missiles", HORIZONTAL_ALIGNMENT_RIGHT, w, 10, SOFT)
	ci.draw_line(Vector2(x, y + 72), Vector2(x + w, y + 72), EDGE, 1.0)
	# Shot down.
	ci.draw_string(bold, Vector2(x, y + 96), "SHOT DOWN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, SOFT)
	var down: String = str(r.total_downed)
	ci.draw_string(bold, Vector2(x, y + 128), down, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, LiteGlyphs.TEXT)
	var dw: float = bold.get_string_size(down, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	ci.draw_string(font, Vector2(x + dw + 8, y + 128), "of %d  ·  %d%%" % [r.total, roundi(100.0 * r.total_downed / maxi(1, r.total))], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, SOFT)
	# By weapon: a glyph, how many were shot down, of how many.
	var arms: Array[int] = []
	for a: int in 3:
		if r.launched[a] > 0:
			arms.append(a)
	var col_w: float = w / maxf(1, arms.size())
	for i: int in arms.size():
		var a: int = arms[i]
		var c:= Vector2(x + i * col_w + 12, y + 162)
		LiteGlyphs.draw_ci(ci, LiteGlyphs.of_arm(a), c, 1.5, Color("#dfe6ef"), -PI / 2)
		ci.draw_string(bold, c + Vector2(18, 6), "× %d" % r.downed[a], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, LiteGlyphs.TEXT)
		ci.draw_string(font, c + Vector2(18, 22), "of %d" % r.launched[a], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, SOFT)
	ci.draw_line(Vector2(x, y + 196), Vector2(x + w, y + 196), EDGE, 1.0)
	# What got through.
	var through: int = r.total - r.total_downed
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%d got through, %d hit" % [through, r.hits])
	if r.capital_damage > 0:
		parts.append("%s −%d" % [main.map.capital_name[0], roundi(r.capital_damage)])
	if r.lost.size() > 0:
		var lost: PackedStringArray = r.lost.slice(0, 2)
		var more: String = (" +%d" % (r.lost.size() - 2)) if r.lost.size() > 2 else ""
		parts.append("lost: " + ", ".join(lost) + more)
	else:
		parts.append("nothing lost")
	ci.draw_multiline_string(font, Vector2(x, y + 216), " · ".join(parts), HORIZONTAL_ALIGNMENT_LEFT, w, 11, 2, LiteGlyphs.TEXT if r.lost.size() > 0 else SOFT)
	# Signature.
	var foot:= Vector2(x + 6, rect.end.y - 16)
	ci.draw_arc(foot, 5, 0, TAU, 20, SOFT, 1.2, true)
	ci.draw_line(foot, foot + Vector2(4, -3), SOFT, 1.2, true)
	ci.draw_string(font, foot + Vector2(12, 4), "Air Defence Command", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, SOFT)
