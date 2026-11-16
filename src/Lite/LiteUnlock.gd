class_name LiteUnlock
extends Control
## New equipment arriving in a campaign (phase 4c), shown before the
## operation's briefing, one piece at a time: the screen goes dark, light
## rays turn behind, the piece drops in big with a flash, sparks and a
## thump, its name types out, a line says what it does. A click goes on.
##
## What arrives when: gun trucks and attack drones at the start; SAMs and
## cruise missiles for the second operation; the armoured AA gun (the
## trucks go) for the third; ballistic missiles for the fourth.

const STEP_IN: float = 0.55

var main: LiteMain = null
var _items: Array = []
var _i: int = 0
var _t: float = 0.0
var _done: Callable = Callable()
var _sparks: Array = []
var _sites: Texture2D = null
var _weapons: Texture2D = null
var _boomed: bool = false

## [name, what it does, "site" or "weapon", cell]
static func items_at(op: int) -> Array:
	match op:
		0: return [
			["GUN TRUCKS", "Pickups with heavy machine guns. Cheap, quick, they patrol their region and chase the drones over it.", "site", LiteKind.MOBILE],
			["ATTACK DRONES", "Slow, cheap, many. Your factories build them; launching is free.", "weapon", 0],
		]
		1: return [
			["SAM SYSTEMS", "Long-range interceptors against drones, cruise and ballistic missiles. Keep them by what matters.", "site", LiteKind.SAM],
			["CRUISE MISSILES", "Fast and low. Strike deep: radars, refineries, launchers.", "weapon", 2],
		]
		2: return [
			["ARMOURED AA GUN", "Tracked, a rotary cannon, a radar of its own. It patrols its region and replaces the gun trucks.", "site", LiteKind.GUN],
			["JET DRONES", "A jet engine in place of the propeller: a fifth faster, much harder to shoot down. Built slower; they replace the old drones.", "weapon", 4],
		]
		3: return [
			["BALLISTIC MISSILES", "High and fast: only SAMs can stop them. Save them for what matters most.", "weapon", 3],
		]
	return []

static func play(main_: LiteMain, items: Array, done: Callable) -> void:
	var layer:= CanvasLayer.new()
	layer.layer = 55
	main_.add_child(layer)
	var u:= LiteUnlock.new()
	u.main = main_
	u._items = items
	u._done = func() -> void:
		layer.queue_free()
		done.call()
	layer.add_child(u)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sites = load("res://assets/ui/sites.png") as Texture2D
	_weapons = load("res://assets/ui/weapons.png") as Texture2D
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _gui_input(e: InputEvent) -> void:
	if _wants(e):
		accept_event()
		_go()

func _unhandled_key_input(e: InputEvent) -> void:
	if _wants(e):
		get_viewport().set_input_as_handled()
		_go()

func _wants(e: InputEvent) -> bool:
	var mb:= e as InputEventMouseButton
	var key:= e as InputEventKey
	return (mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT) or (key != null and key.pressed and not key.echo and (key.keycode == KEY_ENTER or key.keycode == KEY_SPACE or key.keycode == KEY_ESCAPE))

## On to the next piece (or the briefing); too early, to the end of this one's arrival.
func _go() -> void:
	if _i >= _items.size():
		return
	if _t < STEP_IN + 0.5:
		_t = STEP_IN + 2.0
		return
	main.audio.click()
	_i += 1
	_t = 0.0
	_boomed = false
	_sparks.clear()
	if _i >= _items.size():
		_done.call()

func _process(delta: float) -> void:
	if _i >= _items.size():
		return
	_t += delta
	if not _boomed and _t >= STEP_IN:
		_boomed = true
		main.audio.play("explosion_b.wav", -12.0, 0.1, 0.0)
		main.audio.play("sam_launch.wav", -16.0, 0.1, 0.0)
		var c: Vector2 = _centre()
		for k: int in 70:
			var a: float = randf() * TAU
			var v: float = randf_range(120.0, 620.0)
			_sparks.append([c, Vector2.from_angle(a) * v, randf_range(0.5, 1.4), randf_range(1.5, 4.0)])
	for s: Array in _sparks:
		s[0] = (s[0] as Vector2) + (s[1] as Vector2) * delta
		s[1] = (s[1] as Vector2) * pow(0.12, delta) + Vector2(0, 260.0) * delta
		s[2] = float(s[2]) - delta
	queue_redraw()

func _centre() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.44)

## An ease with a bounce past the end (the piece landing).
static func _back(x: float) -> float:
	var c: float = 2.2
	x = clampf(x, 0.0, 1.0)
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3) + c * pow(x - 1.0, 2)

func _draw() -> void:
	if _i >= _items.size():
		return
	var it: Array = _items[_i]
	var t: float = _t
	var vs: Vector2 = size
	var c: Vector2 = _centre()
	var fade: float = clampf(t / 0.3, 0.0, 1.0)
	# The dark, a vignette.
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.025, 0.04, 0.96 * fade))
	# Light rays turning behind, stronger once it has landed.
	var rays: float = clampf((t - 0.2) / 0.6, 0.0, 1.0) * (0.55 + 0.45 * clampf((t - STEP_IN) / 0.4, 0.0, 1.0))
	var spin: float = t * 0.25
	var reach: float = vs.length()
	for k: int in 18:
		var a: float = spin + k * TAU / 18.0
		var w: float = 0.07
		var col: Color = Color(1.0, 0.78, 0.35, 0.10 * rays)
		draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a - w) * reach, c + Vector2.from_angle(a + w) * reach]), col)
	# A glow under it.
	var glow: Texture2D = LiteCmdCity.soft()
	var gr: float = 260.0 + 30.0 * sin(t * 2.0)
	draw_texture_rect(glow, Rect2(c - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(1.0, 0.7, 0.3, 0.35 * rays))
	# The heading.
	var hk: float = clampf((t - 0.15) / 0.35, 0.0, 1.0)
	var head: String = "NEW EQUIPMENT"
	var hf: Font = LiteGlyphs.black
	var hw: float = hf.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var hy: float = vs.y * 0.12 - (1.0 - hk) * 30.0
	draw_string(hf, Vector2(c.x - hw / 2.0, hy), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(LiteTheme.AMBER, hk))
	var band:= Rect2(c.x - 220, hy + 12, 440, 6)
	draw_rect(band, Color(LiteTheme.BORDER, 0.5 * hk))
	LiteCmdStyle.hatch(self, band, Color(LiteTheme.AMBER, 0.5 * hk), 6.0)
	if _items.size() > 1:
		var n: String = "%d / %d" % [_i + 1, _items.size()]
		draw_string(LiteGlyphs.bold, Vector2(c.x - LiteGlyphs.bold.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x / 2.0, hy + 40), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(LiteTheme.MUTED, hk))
	# The piece: dropping in from big, landing with a bounce, then bobbing.
	var land: float = clampf((t - 0.15) / (STEP_IN - 0.15), 0.0, 1.0)
	var k: float = lerpf(3.2, 1.0, _back(land)) if land < 1.0 else 1.0
	var bob: float = sin(maxf(0.0, t - STEP_IN) * 2.2) * 6.0
	var shake: Vector2 = Vector2.ZERO
	var since: float = t - STEP_IN
	if since > 0.0 and since < 0.35:
		shake = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 10.0 * (1.0 - since / 0.35)
	var weapon: bool = it[2] == "weapon"
	var px: float = 15.0 if not weapon else 8.5
	var tex: Texture2D = _weapons if weapon else _sites
	var cell: int = int(it[3])
	var src:= Rect2(cell * 32, 0, 32, 32) if weapon else Rect2(cell * 16, 0, 16, 16)
	var sz: Vector2 = src.size * px * k
	var at: Vector2 = c + shake + Vector2(0, bob)
	var alpha: float = clampf(land * 3.0, 0.0, 1.0)
	if weapon:
		draw_set_transform(at, -0.3, Vector2.ONE)
		draw_texture_rect_region(tex, Rect2(-sz / 2.0 + Vector2(10, 14), sz), src, Color(0, 0, 0, 0.45 * alpha))
		draw_texture_rect_region(tex, Rect2(-sz / 2.0, sz), src, Color(0.75, 0.85, 1.0, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect_region(tex, Rect2(at - sz / 2.0 + Vector2(10, 14), sz), src, Color(0, 0, 0, 0.45 * alpha))
		draw_texture_rect_region(tex, Rect2(at - sz / 2.0, sz), src, Color(1, 1, 1, alpha))
	# The flash as it lands.
	if since > 0.0 and since < 0.5:
		var fl: float = 1.0 - since / 0.5
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.95, 0.85, 0.55 * fl * fl))
		var ring: float = 80.0 + since * 900.0
		draw_arc(c, ring, 0, TAU, 64, Color(1.0, 0.85, 0.5, 0.8 * fl), 4.0)
	# Sparks.
	for s: Array in _sparks:
		var life: float = float(s[2])
		if life <= 0.0:
			continue
		var p: Vector2 = s[0]
		var v: Vector2 = s[1]
		var col: Color = Color(1.0, 0.75 + 0.2 * randf(), 0.35, clampf(life, 0.0, 1.0))
		draw_line(p, p - v * 0.03, col, float(s[3]))
	# Its name typing out, then what it does.
	var name: String = it[0]
	var shown: int = clampi(int((t - STEP_IN - 0.1) / 0.045), 0, name.length())
	var nf: Font = LiteGlyphs.black
	var nw: float = nf.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 58).x
	var ny: float = vs.y * 0.78
	if shown > 0:
		draw_string(nf, Vector2(c.x - nw / 2.0 + 3, ny + 4), name.substr(0, shown), HORIZONTAL_ALIGNMENT_LEFT, -1, 58, Color(0, 0, 0, 0.6))
		draw_string(nf, Vector2(c.x - nw / 2.0, ny), name.substr(0, shown), HORIZONTAL_ALIGNMENT_LEFT, -1, 58, LiteTheme.TEXT)
	var dk: float = clampf((t - STEP_IN - 0.2 - name.length() * 0.045) / 0.4, 0.0, 1.0)
	if dk > 0.0:
		var df: Font = LiteGlyphs.font
		var line: String = it[1]
		var lw: float = minf(900.0, vs.x - 80.0)
		draw_multiline_string(df, Vector2(c.x - lw / 2.0, ny + 44), line, HORIZONTAL_ALIGNMENT_CENTER, lw, 20, 3, Color(LiteTheme.MUTED, dk))
		var pulse: float = 0.55 + 0.45 * sin(t * 4.0)
		var go: String = "CLICK TO CONTINUE" if _i < _items.size() - 1 else "CLICK TO GO TO THE BRIEFING"
		var gw: float = LiteGlyphs.black.get_string_size(go, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(LiteGlyphs.black, Vector2(c.x - gw / 2.0, vs.y - 36), go, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(LiteTheme.AMBER, dk * pulse))
