class_name LiteHud
extends Control
## Everything drawn over the map that is not the map: the alert card at the
## top (like the notice on map.ukrainealarm.com), the logo and clock badge
## bottom-left, the hint for the tool in hand, a short message after a
## refused order, and the tooltip for whatever is under the mouse.

var main: LiteMain = null
var _msg: String = ""
var _msg_age: float = 99.0
var _pulse: float = 0.0
var _state: float = -1
var _redraw: float = 0.0
var _mouse: Vector2 = Vector2.ZERO
## A LiteBuilding, a region id (int) or null.
var _hover: Variant = null
var _tool: int = -1
var _card: StyleBoxFlat = LiteGlyphs.box(Color(LiteGlyphs.PANEL, 0.96), LiteGlyphs.LINE, 10)
var _tip: StyleBoxFlat = LiteGlyphs.box(Color(LiteGlyphs.PANEL, 0.97), LiteGlyphs.LINE, 7)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func message(text: String) -> void:
	_msg = text
	_msg_age = 0


## True when `v` holds a tool (LiteMain's nullable LiteKind?/LiteArm?: null or -1 means none).
static func _has_tool(v: Variant) -> bool:
	return v != null and int(v) >= 0


func _process(delta: float) -> void:
	var tp: float = LitePerf.now
	_process_body(delta)
	LitePerf.ui_proc_ms += LitePerf.now - tp


func _process_body(delta: float) -> void:
	_msg_age += delta
	_pulse = maxf(0, _pulse - delta * 1.6)
	# Redrawn while the message fades, the card pulses or the tooltip
	# follows the mouse; otherwise four times a second for the clock.
	var hover: Variant = main.hover_building if main.hover_building != null else main.hover_region
	var tool: int = int(main.build_tool) if _has_tool(main.build_tool) else (10 + int(main.strike_tool) if _has_tool(main.strike_tool) else -1)
	var same_hover: bool = typeof(hover) == typeof(_hover) and hover == _hover
	var moving: bool = _msg_age < 2.4 or _pulse > 0 or (main.mouse != _mouse and hover != null) or not same_hover or tool != _tool
	_redraw -= delta
	if not moving and _redraw > 0:
		return
	_redraw = 0.25
	_mouse = main.mouse
	_hover = hover
	_tool = tool
	queue_redraw()


func _draw() -> void:
	var t0: float = LitePerf.now
	_draw_body()
	LitePerf.ui_ms += LitePerf.now - t0


func _draw_body() -> void:
	if not main.started:
		return
	_draw_alert_card()
	_draw_badge()
	_draw_hint()
	_draw_tooltip()


func _draw_alert_card() -> void:
	var sim: LiteSim = main.sim
	var regions: int = sim.alerted[0]
	var threats: int = 0
	var ballistic: bool = false
	for wp: LiteWeapon in sim.weapons:
		if wp.alive and wp.side == 1 and wp.seen[0]:
			threats += 1
			if wp.arm == LiteArm.BALLISTIC:
				ballistic = true
	var state: float = 0.0 if regions == 0 else (2.0 if ballistic else 1.0)
	if state != _state:
		if _state >= 0 and state > 0:
			_pulse = 1
		_state = state
	var tone: Color = LiteGlyphs.BALLISTIC_ALERT if state == 2 else (LiteGlyphs.YELLOW if state == 1 else LiteGlyphs.MUTED)
	var title: String
	if state == 2:
		title = "Ballistic threat!"
	elif state == 1:
		title = "Air alert · %d region%s" % [regions, "" if regions == 1 else "s"]
	else:
		title = "No air alert"
	var sub: String
	if state > 0:
		sub = "Since %s · %d in the air" % [main.clock_text(sim.side_alert_since[0], false), threats]
	elif sim.side_quiet_since[0] > 0:
		sub = "All clear since %s" % main.clock_text(sim.side_quiet_since[0], false)
	else:
		sub = "The sky is quiet"
	# Between alerts, intelligence's warning stays on the card until the strike comes.
	var ai: LiteAi = main.sim.ai[1]
	if state == 0 and ai != null and ai.massing:
		title = "Large strike expected"
		sub = "Intelligence: the enemy is massing drones and missiles"
		tone = LiteGlyphs.BALLISTIC_ALERT
		state = 1
	var font: Font = LiteGlyphs.bold
	var w: float = maxf(font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, LiteGlyphs.font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) + 74
	var cx: float = LiteMap.W / 2.0
	var grow: float = _pulse * _pulse * 6.0
	var rect := Rect2(cx - w / 2 - grow, 14 - grow * 0.5, w + grow * 2, 54 + grow)
	_card.border_color = LiteGlyphs.LINE.lerp(tone, 0.55 if state > 0 else 0.0)
	draw_style_box(_card, rect)
	# A clock face, as on the real notice.
	var c := Vector2(rect.position.x + 30, rect.position.y + rect.size.y / 2)
	draw_arc(c, 10, 0, TAU, 32, tone, 1.8, true)
	draw_line(c, c + Vector2(0, -6), tone, 1.8, true)
	draw_line(c, c + Vector2(4.5, 2.5), tone, 1.8, true)
	draw_string(font, Vector2(rect.position.x + 52, rect.position.y + 24), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, tone if state > 0 else LiteGlyphs.TEXT)
	draw_string(LiteGlyphs.font, Vector2(rect.position.x + 52, rect.position.y + 42), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteGlyphs.MUTED)


func _draw_badge() -> void:
	var at := Vector2(22, size.y - 58)
	var logo := Rect2(at, Vector2(36, 36))
	var box: StyleBoxFlat = LiteGlyphs.box(LiteGlyphs.OURS, LiteGlyphs.OURS, 8)
	draw_style_box(box, logo)
	var c: Vector2 = logo.get_center()
	draw_arc(c, 10, 0, TAU, 32, Color.WHITE, 1.6, true)
	draw_arc(c, 5, 0, TAU, 24, Color(1, 1, 1, 0.7), 1.2, true)
	draw_line(c, c + Vector2(8, -6), Color.WHITE, 1.6, true)
	draw_circle(c, 1.6, Color.WHITE, true, -1.0, true)
	draw_string(LiteGlyphs.font, Vector2(at.x + 46, at.y + 14), "strike alert · lite", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteGlyphs.MUTED)
	draw_string(LiteGlyphs.bold, Vector2(at.x + 46, at.y + 32), main.clock_text(main.sim.time, true), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, LiteGlyphs.TEXT)
	if main.paused and main.sim.winner < 0:
		draw_string(LiteGlyphs.bold, Vector2(at.x + 46, at.y - 8), "PAUSED · Space to resume", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LiteGlyphs.YELLOW)


func _draw_hint() -> void:
	var hint: String = ""
	if _has_tool(main.build_tool) and int(main.build_tool) == LiteKind.FACTORY:
		hint = "Click a region with a free place (green) to build a factory there ($%d) · Right-click cancels" % main.sim.cost(0, LiteKind.FACTORY)
	elif _has_tool(main.build_tool):
		var k: int = int(main.build_tool)
		hint = "Click your territory to build: %s ($%d) · Shift keeps the tool · Right-click cancels" % [LiteGlyphs.name(k), main.sim.cost(0, k)]
	elif _has_tool(main.strike_tool):
		var a: int = int(main.strike_tool)
		hint = "Click enemy territory to launch %s straight, or drag a route from your land to the target · Right-click cancels" % LiteGlyphs.plural(a, 2)
	var y: float = size.y - 34
	if _msg_age < 2.2:
		var a: float = clampf((2.2 - _msg_age) / 0.4, 0, 1)
		_pill(_msg, y - 34, Color(LiteGlyphs.ENEMY, a), a)
	if hint != "":
		_pill(hint, y, LiteGlyphs.MUTED, 1)


func _pill(text: String, y: float, col: Color, alpha: float) -> void:
	var font: Font = LiteGlyphs.font
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 28
	var r := Rect2(LiteMap.W / 2.0 - w / 2 + 40, y - 13, w, 26)
	_tip.bg_color = Color(LiteGlyphs.PANEL, 0.94 * alpha)
	_tip.border_color = Color(LiteGlyphs.LINE, alpha)
	draw_style_box(_tip, r)
	draw_string(font, Vector2(r.position.x + 14, y + 4.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


func _draw_tooltip() -> void:
	if (_has_tool(main.build_tool) and int(main.build_tool) != LiteKind.FACTORY) or _has_tool(main.strike_tool):
		return
	var sim: LiteSim = main.sim
	var head: String = ""
	var body: String = ""
	var b: LiteBuilding = main.hover_building
	if b != null:
		head = ("" if b.side == 0 else "Enemy ") + LiteGlyphs.name(b.kind)
		match b.kind:
			LiteKind.CAPITAL:
				body = "Health %d/%d · own AA guns · repaired by its factories" % [roundi(maxf(0, b.hp)), roundi(b.max_hp)]
			LiteKind.FACTORY:
				body = "Health %d/%d · +$%d/s, repairs the capital%s" % [roundi(b.hp), roundi(b.max_hp), roundi(LiteRules.FACTORY_INCOME), " (sheltering)" if sim.alert[b.region] else ""]
			LiteKind.SAM:
				body = ("Missiles %d/%d · health %d/%d" % [b.ammo, LiteRules.SAM_RACK, roundi(b.hp), roundi(b.max_hp)]) if b.side == 0 else ("Health %d/%d" % [roundi(b.hp), roundi(b.max_hp)])
			_:
				body = "Health %d/%d" % [roundi(b.hp), roundi(b.max_hp)]
		if not b.ready:
			body = "Building… %ds" % roundi(b.build)
	elif main.hover_region >= 0:
		var r: LiteRegion = main.map.regions[main.hover_region]
		head = r.name + ("" if r.city else (" region" if r.side == 0 else ""))
		if r.side == 0 and not r.city:
			var ruins: int = sim.ruins_in(r.id)
			head += " · factories %d/%d%s" % [sim.factories_in(r.id), sim.slots[r.id], (", %d in ruins" % ruins) if ruins > 0 else ""]
		if sim.alert[r.id]:
			body = "%s · %s" % ["Ballistic threat" if sim.ballistic[r.id] else "Air alert", duration(sim.time - sim.alert_since[r.id])]
		else:
			body = "No alert" if r.side == 0 else "Enemy territory"
	if head == "":
		return
	var font: Font = LiteGlyphs.font
	var w: float = maxf(LiteGlyphs.bold.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, font.get_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x) + 20
	var p: Vector2 = main.mouse + Vector2(16, 14)
	if p.x + w > LiteMap.W:
		p.x -= w + 28
	var rect := Rect2(p, Vector2(w, 42))
	_tip.bg_color = Color(LiteGlyphs.PANEL, 0.97)
	_tip.border_color = LiteGlyphs.LINE
	draw_style_box(_tip, rect)
	draw_string(LiteGlyphs.bold, p + Vector2(10, 17), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteGlyphs.TEXT)
	draw_string(font, p + Vector2(10, 33), body, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LiteGlyphs.MUTED)


static func duration(seconds: float) -> String:
	# One second of play is one minute on the clock.
	var m: int = int(seconds)
	return ("%d h %02d min" % [m / 60, m % 60]) if m >= 60 else ("%d min" % m)
