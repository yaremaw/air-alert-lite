class_name LiteArsenalView
extends Control
## The arsenal, opened from the home screen: every unit of the war in cells
## by kind (air defence, economy, strike weapons, enemy forces), each its
## sprite and name. A click opens one: the sprite large over a radar screen
## that sweeps and blinks, its name and a line or two about it. Back (or
## Esc) returns to the menu.

var main: LiteMain = null

## [title, sheet ("site", "weapon" or "unit"), cell, what it is, a short line].
const GROUPS: Array = [
	["AIR DEFENCE", [
		["Gun truck", "site", LiteKind.MOBILE, "Mobile AA", "A pickup with a heavy machine gun in its bed. Cheap and quick: it patrols its region and chases drones. Double-click it to take the gun yourself."],
		["Armoured AA gun", "site", LiteKind.GUN, "Self-propelled AA", "Tracks, twin cannons and its own radar. It replaces the trucks and shreds drones; a cruise missile is in reach too. Double-click it to take the gun yourself."],
		["SAM launcher", "site", LiteKind.SAM, "Long-range interceptors", "Stops drones, cruise and ballistic missiles far out. Its rack empties fast: the factories reload it."],
		["Radar", "site", LiteKind.RADAR, "Early warning", "Sees far. Air defence near it fights by its picture: longer reach, surer hits."],
	]],
	["ECONOMY", [
		["Factory", "site", LiteKind.FACTORY, "Arms industry", "Builds the drones and missiles, and the interceptors. It shelters, and slows down, under an air alert."],
		["Refinery", "site", LiteKind.REFINERY, "Money", "Pays for the war. In the desert it is an oil field. Hit, it burns for a long time."],
		["Power station", "site", LiteKind.POWER, "Grid", "Knock one out and that side's SAMs go silent for a day."],
		["Jammer", "site", LiteKind.JAMMER, "Electronic warfare", "Drones flying into its circle are often lost. Missiles are not fooled."],
	]],
	["STRIKE WEAPONS", [
		["Attack drone", "weapon", 0, "Loitering munition", "Slow and cheap, launched by the dozen. Air defence spends itself on them."],
		["Jet drone", "weapon", 4, "Jet-powered drone", "A fifth faster and harder to bring down; the factories make fewer of them."],
		["Cruise missile", "weapon", 2, "Low and fast", "Hugs the ground on its way in. Guns struggle with it; SAMs do not."],
		["Ballistic missile", "weapon", 3, "From above", "Falls from the edge of space in minutes. Only a SAM can stop it."],
	]],
	["ENEMY FORCES", [
		["Armoured battalion", "unit", LiteUnit.ARMOUR, "Columns on the move", "Grinds towards the border, its own AA riding with it. Burn it on the road."],
		["Ammunition train", "unit", LiteUnit.LOCO, "Rail supply", "A month of shells for their guns. Wreck the engine and the wagons go nowhere."],
		["Mobile launcher", "unit", LiteUnit.LAUNCHER, "Shoot and scoot", "Fires from cover, then drives off. A salvo gives it away for half a minute."],
		["Cargo ship", "unit", LiteUnit.TANKER, "Export", "Sails from their port with oil. Each one sunk is a command point."],
		["Repair crew", "unit", LiteUnit.CREW, "Engineers", "Drives out to mend what we break. Catch it on the road."],
		["Supply convoy", "unit", LiteUnit.SUPPLY, "Logistics", "Trucks from the depot to their front, every few hours."],
	]],
]

var _cells: Array[Rect2] = []
var _items: Array = []
var _back: Rect2 = Rect2()
var _hover: int = -1
var _hover_back: bool = false
var _open: int = -1
## How long the opened one has been open, and the page's clock.
var _age: float = 0.0
var _clock: float = 0.0
static var SITES: Texture2D = null
static var WEAPONS: Texture2D = null

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	# Pixel art scaled up stays crisp.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)

func open() -> void:
	if SITES == null:
		SITES = load("res://assets/ui/sites.png") as Texture2D
		WEAPONS = load("res://assets/ui/weapons.png") as Texture2D
	visible = true
	_open = -1
	move_to_front()
	set_process(true)
	queue_redraw()

func close() -> void:
	if _open >= 0:
		_open = -1
		queue_redraw()
		return
	visible = false
	set_process(false)

func _process(delta: float) -> void:
	_clock += delta
	_age += delta
	queue_redraw()

func _gui_input(e: InputEvent) -> void:
	var mm:= e as InputEventMouseMotion
	if mm != null:
		var h: bool = _open < 0 and _back.has_point(mm.position)
		var c: int = -1
		if _open < 0:
			for i: int in _cells.size():
				if _cells[i].has_point(mm.position):
					c = i
		if h != _hover_back or c != _hover:
			_hover_back = h
			_hover = c
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h or c >= 0 else Control.CURSOR_ARROW
	var mb:= e as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if main != null:
		main.audio.click()
	if _open >= 0:
		_open = -1
	elif _back.has_point(mb.position):
		close()
	else:
		for i: int in _cells.size():
			if _cells[i].has_point(mb.position):
				_open = i
				_age = 0.0
				_hover = -1

func _draw() -> void:
	var vs: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, vs), LiteTheme.BG)
	# A faint grid drifting slowly down.
	var off: float = fmod(_clock * 6.0, 48.0)
	for x: int in range(0, int(vs.x), 48):
		draw_rect(Rect2(x, 0, 1, vs.y), Color(LiteTheme.BORDER, 0.22))
	for y: float in range(-48, int(vs.y), 48):
		draw_rect(Rect2(0, y + off, vs.x, 1), Color(LiteTheme.BORDER, 0.22))
	var left: float = 56.0
	draw_string(LiteGlyphs.black, Vector2(left, 70), "ARSENAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, LiteTheme.TEXT)
	draw_string(LiteGlyphs.bold, Vector2(left, 96), "EVERYTHING ON THE MAP, OURS AND THEIRS · CLICK ONE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, LiteTheme.AMBER)
	_cells.clear()
	_items.clear()
	var cols: int = 8
	var gap: float = 10.0
	var cw: float = (vs.x - left * 2 - gap * (cols - 1)) / cols
	var ch: float = 92.0
	var y: float = 122.0
	for g: Array in GROUPS:
		draw_string(LiteGlyphs.bold, Vector2(left, y + 12), g[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LiteTheme.MUTED)
		draw_rect(Rect2(left + LiteGlyphs.bold.get_string_size(g[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12, y + 7, vs.x - left * 2 - 140, 1), Color(LiteTheme.BORDER, 0.8))
		y += 22.0
		var items: Array = g[1]
		for i: int in items.size():
			var r:= Rect2(left + (i % cols) * (cw + gap), y + (i / cols) * (ch + gap), cw, ch)
			var k: int = _cells.size()
			_cells.append(r)
			_items.append(items[i])
			_cell(r, items[i], k == _hover)
		y += ceilf(items.size() / float(cols)) * (ch + gap) + 8.0
	_back = Rect2(left, vs.y - 62, 200, 40)
	draw_rect(_back, LiteTheme.PANEL)
	draw_rect(_back, LiteTheme.BLUE if _hover_back else LiteTheme.BORDER, false, 1.5)
	draw_string(LiteGlyphs.black, _back.position + Vector2(20, 27), "BACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, LiteTheme.TEXT)
	if _open >= 0 and _open < _items.size():
		_detail(_items[_open])

func _cell(r: Rect2, it: Array, hover: bool) -> void:
	draw_rect(r, Color(LiteTheme.PANEL, 0.9))
	var pic:= Rect2(r.position + Vector2(4, 4), Vector2(r.size.x - 8, r.size.y - 28))
	draw_rect(pic, Color(LiteTheme.BG, 0.9))
	var bob: float = sin(_clock * 2.0 + r.position.x * 0.05) * 1.5 if hover else 0.0
	_sprite(it, pic.get_center() + Vector2(0, bob), minf(pic.size.y, pic.size.x) * 0.9)
	draw_string(LiteGlyphs.black, Vector2(r.position.x + 4, r.end.y - 9), String(it[0]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 8, 10, LiteTheme.TEXT if hover else Color(LiteTheme.TEXT, 0.8))
	draw_rect(r, LiteTheme.BLUE if hover else LiteTheme.BORDER, false, 1.5 if hover else 1.0)

## A unit's picture, `s` across, centred on `c`.
func _sprite(it: Array, c: Vector2, s: float) -> void:
	match String(it[1]):
		"site":
			var src:= Rect2(int(it[2]) * 16, 0, 16, 16)
			var r:= Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
			draw_texture_rect_region(SITES, Rect2(r.position + Vector2(s / 16.0, s / 16.0), r.size), src, Color(0, 0, 0, 0.45))
			draw_texture_rect_region(SITES, r, src)
		"weapon":
			var src:= Rect2(int(it[2]) * 32, 0, 32, 32)
			var r:= Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
			draw_texture_rect_region(WEAPONS, Rect2(r.position + Vector2(s / 20.0, s / 14.0), r.size), src, Color(0, 0, 0, 0.45))
			draw_texture_rect_region(WEAPONS, r, src, Color(0.62, 0.8, 1.0))
		_:
			LiteUnit.symbol(self, c, int(it[2]), s * 0.36)

## An opened unit: a radar screen sweeping behind it, rings pulsing out,
## blips flaring and fading, a scan line running down; its name, what it
## is, a line or two about it.
func _detail(it: Array) -> void:
	var vs: Vector2 = size
	var a: float = clampf(_age / 0.25, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.72 * a))
	var w: float = minf(920.0, vs.x - 80.0)
	var h: float = 400.0
	var r:= Rect2((vs - Vector2(w, h)) / 2.0 + Vector2(0, 14.0 * (1.0 - a)), Vector2(w, h))
	draw_rect(r, Color(LiteTheme.PANEL, a))
	var scr:= Rect2(r.position + Vector2(20, 20), Vector2(h - 40, h - 40))
	draw_rect(scr, Color(0.02, 0.06, 0.06, a))
	var c: Vector2 = scr.get_center()
	var rad: float = scr.size.x * 0.46
	var green:= Color(0.35, 1.0, 0.6)
	# The scope: rings, cross hairs.
	for k: int in 4:
		draw_arc(c, rad * (k + 1) / 4.0, 0, TAU, 64, Color(green, 0.16 * a), 1.0, true)
	draw_line(c - Vector2(rad, 0), c + Vector2(rad, 0), Color(green, 0.12 * a), 1.0)
	draw_line(c - Vector2(0, rad), c + Vector2(0, rad), Color(green, 0.12 * a), 1.0)
	# The sweep: a bright arm and a fading wedge behind it.
	var ang: float = _clock * 1.6
	for k: int in 28:
		var a0: float = ang - k * 0.035
		var tri:= PackedVector2Array([c, c + Vector2.from_angle(a0) * rad, c + Vector2.from_angle(a0 - 0.036) * rad])
		draw_colored_polygon(tri, Color(green, 0.22 * (1.0 - k / 28.0) * a))
	draw_line(c, c + Vector2.from_angle(ang) * rad, Color(green, 0.85 * a), 1.5, true)
	# Blips: lit as the arm passes, fading after.
	for k: int in 7:
		var ba: float = k * 2.39 + 0.7
		var br: float = rad * (0.3 + 0.62 * fposmod(k * 0.37, 1.0))
		var since: float = fposmod(ang - ba, TAU)
		var glow: float = clampf(1.0 - since / 2.6, 0.0, 1.0)
		if glow > 0.0:
			var p: Vector2 = c + Vector2.from_angle(ba) * br
			draw_circle(p, 2.0 + 2.0 * glow, Color(green, 0.8 * glow * a))
			draw_circle(p, 6.0 * glow, Color(green, 0.15 * glow * a))
	# A ring pulsing out from the middle.
	var pr: float = fmod(_clock * 0.6, 1.0)
	draw_arc(c, rad * pr, 0, TAU, 64, Color(green, 0.4 * (1.0 - pr) * a), 2.0, true)
	# The unit itself, bobbing, a soft glow under it.
	draw_circle(c, rad * 0.36, Color(green, 0.06 * a))
	var bob: float = sin(_clock * 1.8) * 4.0
	_sprite(it, c + Vector2(0, bob), rad * 0.95 * (0.85 + 0.15 * a))
	# A scan line running down the screen.
	var sy: float = scr.position.y + fmod(_clock * 90.0, scr.size.y)
	draw_rect(Rect2(scr.position.x, sy, scr.size.x, 2), Color(green, 0.18 * a))
	draw_rect(scr, Color(green, 0.35 * a), false, 1.0)
	# Its words, typed out quickly.
	var x: float = scr.end.x + 28
	var tw: float = r.end.x - x - 24
	var y: float = r.position.y + 62
	draw_string(LiteGlyphs.bold, Vector2(x, y - 26), String(it[3]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, tw, 13, Color(LiteTheme.AMBER, a))
	draw_string(LiteGlyphs.black, Vector2(x, y + 6), String(it[0]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, tw, 32, Color(LiteTheme.TEXT, a))
	draw_rect(Rect2(x, y + 22, 60.0 * clampf(_age / 0.5, 0.0, 1.0), 3), Color(LiteTheme.AMBER, a))
	var text: String = String(it[4])
	var shown: int = mini(text.length(), int(_age * 140.0))
	draw_multiline_string(LiteGlyphs.font, Vector2(x, y + 64), text.substr(0, shown), HORIZONTAL_ALIGNMENT_LEFT, tw, 19, 6, Color(LiteTheme.TEXT, 0.92 * a))
	draw_rect(r, Color(LiteTheme.BLUE, 0.7 * a), false, 1.5)
	draw_string(LiteGlyphs.bold, Vector2(r.position.x, r.end.y + 26), "CLICK TO CLOSE", HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(LiteTheme.MUTED, 0.8 * a))
