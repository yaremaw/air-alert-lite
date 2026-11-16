class_name LiteCmdCity
extends Node2D
## A capital in the command look: its landmarks standing in the middle of
## its city (the city itself is the terrain's, see LiteTerrain), from
## assets/ui/capitals.png (tools/capital_sprites.py): ours a white domed
## government house and a TV tower, the enemy's a red fortress wall with
## towers, gold onion domes and a spired high-rise. They show how hard the
## capital has been hit lately (standing, damaged, in ruins), fires burn
## where hits came down, their windows light at night (dark in a blackout).
##
## Purely a picture: the capital's hits and what they do to the country's
## morale are the simulation's (LiteSim, LiteMorale).

## The square kept clear in the middle of the capital's city (the city is
## the terrain's, see LiteTerrain), where the landmarks stand, in map units.
const RADIUS: float = 11.0
## The landmarks' sprite on the map, in map units (64 pixels).
const SIZE: float = 38.0
const CELL: int = 64

static var SHEET: Texture2D = null

var site: LiteBuilding = null
var side_col: Color = Color.WHITE
## How dark it is, 0 by day to 1 at night (see LiteCmdView.night).
var night: float = 0.0
## Whether its power is on (1) or out (0): a blackout (see LiteCmdView.blackout).
var power: float = 1.0
var _clock: float = 0.0
## Fires where it was hit: [where, until (clock)]; flashes: [where, when].
var _fires: Array = []
var _flashes: Array = []
## The night glow and the fires, added on.
var _glow: Node2D = null

func build(_map: LiteMap, site_: LiteBuilding, _away: Vector2, _others: Array = []) -> void:
	site = site_
	if SHEET == null:
		SHEET = load("res://assets/ui/capitals.png") as Texture2D
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var sharp:= ShaderMaterial.new()
	sharp.shader = load("res://src/Lite/command/lite_sharp.gdshader") as Shader
	material = sharp
	_glow = Node2D.new()
	var mat:= CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	_glow.draw.connect(_draw_glow)
	add_child(_glow)

## How much of the city lies in ruins, 0 to 1, from what its capital has lost.
func lost() -> float:
	if site == null or site.max_hp <= 0:
		return 0.0
	return clampf(1.0 - maxf(0.0, site.hp) / site.max_hp, 0.0, 1.0)

## A hit on the capital came down at `p`: a flash, and a fire there for a while.
func hit(p: Vector2) -> void:
	_flashes.append([p, _clock])
	if _flashes.size() > 6:
		_flashes.pop_front()
	_fires.append([p + Vector2(randf_range(-2, 2), randf_range(-2, 2)), _clock + randf_range(20.0, 40.0)])
	if _fires.size() > 14:
		_fires.pop_front()

## A fire burning now and then, for smoke (see LiteCmdView).
func a_ruin(rng_f: float) -> Variant:
	var live: Array = []
	for f: Array in _fires:
		if float(f[1]) > _clock:
			live.append(f[0])
	if live.is_empty():
		return null
	return live[int(rng_f * live.size()) % live.size()]

func step(dt: float) -> void:
	_clock += dt
	queue_redraw()
	_glow.queue_redraw()

## Where the landmarks are drawn: standing on the city's middle square.
func _rect() -> Rect2:
	return Rect2(site.pos - Vector2(SIZE * 0.5, SIZE * 0.78), Vector2(SIZE, SIZE))

func _stage() -> int:
	var k: float = lost()
	return 0 if k < 0.12 else (1 if k < 0.45 else 2)

func _draw() -> void:
	if SHEET == null or site == null:
		return
	var col: int = 0 if site.side == 0 else 1
	var r: Rect2 = _rect()
	var src:= Rect2(col * CELL, _stage() * CELL, CELL, CELL)
	# Its shadow, then the city, darker at night.
	draw_texture_rect_region(SHEET, Rect2(r.position + Vector2(1.2, 1.5), r.size), src, Color(0, 0, 0, 0.35))
	var shade: float = 1.0 - 0.45 * night
	draw_texture_rect_region(SHEET, r, src, Color(shade, shade, shade * 1.05, 1.0))

## Its windows at night (dark in a blackout), its glow, the fires and
## flashes where it was hit.
func _draw_glow() -> void:
	if SHEET == null or site == null:
		return
	var col: int = 0 if site.side == 0 else 1
	var r: Rect2 = _rect()
	if night > 0.05 and power > 0.05:
		var lit:= Rect2(col * CELL, (_stage() + 3) * CELL, CELL, CELL)
		_glow.draw_texture_rect_region(SHEET, r, lit, Color(night * power, night * power, night * power, 1.0))
		# Floodlights on the landmarks.
		_glow.draw_texture_rect(soft(), Rect2(site.pos - Vector2(SIZE, SIZE) * 0.45, Vector2(SIZE, SIZE) * 0.9), false,
			Color(0.3, 0.24, 0.12, 0.45 * night * power * (1.0 - 0.5 * lost())))
	for f: Array in _fires:
		var left: float = float(f[1]) - _clock
		if left <= 0.0:
			continue
		var c: Vector2 = f[0]
		var fl: float = 0.5 + 0.5 * sin(_clock * 9.0 + c.x)
		var k: float = clampf(left / 10.0, 0.0, 1.0)
		_glow.draw_rect(Rect2(c - Vector2(0.8, 0.8), Vector2(1.6, 1.6)), Color(1.0, 0.45 + 0.3 * fl, 0.12, (0.7 + 0.3 * fl) * k))
		_glow.draw_texture_rect(soft(), Rect2(c - Vector2(6, 6), Vector2(12, 12)), false, Color(0.55, 0.24, 0.06, (0.3 + 0.4 * night) * k))
	for fl2: Array in _flashes:
		var age: float = _clock - float(fl2[1])
		if age < 1.2:
			var k2: float = 1.0 - age / 1.2
			var rr: float = 14.0 + 12.0 * age
			_glow.draw_texture_rect(soft(), Rect2(fl2[0] - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(0.9, 0.6, 0.3, 0.6 * k2 * k2))

## A soft round light, drawn as one quad wherever a glow is wanted.
static var _soft: Texture2D = null

static func soft() -> Texture2D:
	if _soft == null:
		var g:= Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t:= GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 64
		t.height = 64
		_soft = t
	return _soft
