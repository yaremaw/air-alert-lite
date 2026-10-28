class_name LiteStatus
extends Control
## The top of the side panel: budget with income, both capitals' health,
## and what is known about the war so far. The budget rolls to its value.

var main: LiteMain = null
var _money: float = -1
var _redraw: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(0, 150)


func _process(delta: float) -> void:
	var tp: float = LitePerf.now
	_process_body(delta)
	LitePerf.ui_proc_ms += LitePerf.now - tp


func _process_body(delta: float) -> void:
	var me: LiteSide = main.sim.sides[0]
	if _money < 0:
		_money = me.money
	_money += (me.money - _money) * (1 - exp(-delta * 10.0))
	# Numbers do not need every frame.
	_redraw -= delta
	if _redraw > 0:
		return
	_redraw = 1 / 15.0
	queue_redraw()


func _draw() -> void:
	var t0: float = LitePerf.now
	_draw_body()
	LitePerf.ui_ms += LitePerf.now - t0


func _draw_body() -> void:
	var sim: LiteSim = main.sim
	var me: LiteSide = sim.sides[0]
	var font: Font = LiteGlyphs.font
	var bold: Font = LiteGlyphs.bold
	var w: float = size.x
	draw_string(font, Vector2(0, 12), "BUDGET", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LiteGlyphs.MUTED)
	draw_string(bold, Vector2(0, 42), "$%d" % floori(_money), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, LiteGlyphs.TEXT)
	var inc: String = "+%.1f/s" % me.income
	draw_string(bold, Vector2(0, 40), inc, HORIZONTAL_ALIGNMENT_RIGHT, w, 12, LiteGlyphs.GOOD)
	var alert_factories: int = 0
	for b: LiteBuilding in sim.buildings:
		if b.alive and b.side == 0 and b.kind == LiteKind.FACTORY and b.ready and sim.alert[b.region]:
			alert_factories += 1
	if alert_factories > 0:
		draw_string(font, Vector2(0, 24), "%d factor%s sheltering" % [alert_factories, "y" if alert_factories == 1 else "ies"], HORIZONTAL_ALIGNMENT_RIGHT, w, 10, LiteGlyphs.YELLOW)

	_bar(62, main.map.capital_name[0], sim.sides[0], LiteGlyphs.OURS, w)
	_bar(94, main.map.capital_name[1], sim.sides[1], LiteGlyphs.ENEMY, w)

	var f: int = 0
	var ad: int = 0
	var ef: int = 0
	var ead: int = 0
	for b: LiteBuilding in sim.buildings:
		if not b.alive:
			continue
		if b.side == 0:
			if b.kind == LiteKind.FACTORY:
				f += 1
			elif b.is_ad:
				ad += 1
		elif b.seen[0]:
			if b.kind == LiteKind.FACTORY:
				ef += 1
			elif b.is_ad:
				ead += 1
	draw_string(font, Vector2(0, 136), "Ours  %d factories · %d AD" % [f, ad], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LiteGlyphs.MUTED)
	draw_string(font, Vector2(0, 136), "Seen  %d · %d" % [ef, ead], HORIZONTAL_ALIGNMENT_RIGHT, w, 11, LiteGlyphs.MUTED)
	draw_string(font, Vector2(0, 150), "Shot down %d · hits on enemy %d" % [me.downed, me.hits], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LiteGlyphs.FAINT)


## A capital's health, and how fast its factories are repairing it.
func _bar(y: float, name_: String, side: LiteSide, col: Color, w: float) -> void:
	var cap: LiteBuilding = side.capital
	var hp: float = maxf(0, cap.hp)
	draw_string(LiteGlyphs.bold, Vector2(0, y + 10), name_, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteGlyphs.TEXT)
	var repair: String = ("repairing +%s/min   " % _one_decimal(side.repair * 60)) if side.repair > 0 else ""
	draw_string(LiteGlyphs.font, Vector2(0, y + 10), "%s%d/%d" % [repair, roundi(hp), roundi(cap.max_hp)], HORIZONTAL_ALIGNMENT_RIGHT, w, 11, LiteGlyphs.MUTED)
	var r := Rect2(0, y + 16, w, 5)
	draw_rect(r, LiteGlyphs.PANEL_HI)
	draw_rect(Rect2(r.position, Vector2(w * hp / cap.max_hp, 5)), col.lerp(LiteGlyphs.HIT_GLOW, cap.flash))


## C# format "0.#": at most one decimal, no trailing ".0".
static func _one_decimal(x: float) -> String:
	var s: String = "%.1f" % x
	if s.ends_with(".0"):
		s = s.substr(0, s.length() - 2)
	return s
