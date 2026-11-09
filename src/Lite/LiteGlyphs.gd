class_name LiteGlyphs
extends RefCounted

const PAGE: Color = Color("#16181d")
const PANEL: Color = Color("#1c1f25")
const PANEL_HI: Color = Color("#262a33")
const LINE: Color = Color("#2e323b")
const TEXT: Color = Color("#e8eaee")
const MUTED: Color = Color("#8b919d")
const FAINT: Color = Color("#5b616c")
const OURS: Color = Color("#4ea1ff")
const ENEMY: Color = Color("#ff5a48")
const YELLOW: Color = Color("#e5ad16")
const GOOD: Color = Color("#46c47e")

# Both countries are grey, as on a real alert map: ours lighter, the enemy's
# darker. Colour means danger only: yellow while drones are about, red while
# missiles (cruise or ballistic) are.
const OUR_LAND: Color = Color("#3a3d46")
const ENEMY_LAND: Color = Color("#24262c")
const AIR_ALERT: Color = Color("#d4a017")
const MISSILE_ALERT: Color = Color("#e0574a")
const BALLISTIC_ALERT: Color = MISSILE_ALERT
# Alerts over the enemy's land (our strikes) are only a dark red, close to
# its grey: a little stronger while missiles are about.
const ENEMY_ALERT: Color = Color("#3a282c")
const ENEMY_MISSILE_ALERT: Color = Color("#4a2328")
const HIT_GLOW: Color = Color("#ff8a3d")

static var font: Font = ThemeDB.fallback_font
static var bold: Font = ThemeDB.fallback_font
static var black: Font = ThemeDB.fallback_font
static var _loaded: bool = false

static func side_color(side: int) -> Color:
	return OURS if side == 0 else ENEMY

static func load_fonts() -> void:
	if _loaded:
		return
	_loaded = true
	const PATH: String = "res://assets/fonts/Inter.ttf"
	# Through the resource loader: an exported game holds only the imported font, not
	# the .ttf file itself, so reading the file directly finds nothing there.
	if not ResourceLoader.exists(PATH):
		return
	var f: FontFile = load(PATH) as FontFile
	if f == null:
		return
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.generate_mipmaps = false
	var tnum: Dictionary = { TextServerManager.get_primary_interface().name_to_tag("tnum"): 1 }
	var regular:= FontVariation.new()
	regular.base_font = f
	regular.opentype_features = tnum
	var heavy:= FontVariation.new()
	heavy.base_font = f
	heavy.opentype_features = tnum
	heavy.variation_embolden = 0.6
	font = regular
	bold = heavy
	# The heaviest cut of Inter (weight 900), for the logo and the home screen's menu.
	var heaviest:= FontVariation.new()
	heaviest.base_font = f
	heaviest.variation_opentype = { TextServerManager.get_primary_interface().name_to_tag("wght"): 900 }
	black = heaviest

	font.set_cache_capacity(512, 64)
	bold.set_cache_capacity(512, 64)
	ThemeDB.fallback_font = font

static func name(k: int) -> String:
	match k:
		LiteKind.CAPITAL: return "Capital"
		LiteKind.FACTORY: return "Factory"
		LiteKind.GUN: return "AA gun"
		_: return "SAM"

static func name_arm(a: int) -> String:
	match a:
		LiteArm.DRONE: return "Drone"
		LiteArm.CRUISE: return "Cruise"
		_: return "Ballistic"

static func plural(a: int, n: int) -> String:
	match a:
		LiteArm.DRONE: return "drone" if n == 1 else "drones"
		LiteArm.CRUISE: return "cruise missile" if n == 1 else "cruise missiles"
		_: return "ballistic missile" if n == 1 else "ballistic missiles"

static func of(k: int) -> int:
	match k:
		LiteKind.CAPITAL: return LiteGlyph.CAPITAL
		LiteKind.FACTORY: return LiteGlyph.FACTORY
		LiteKind.GUN: return LiteGlyph.GUN
		_: return LiteGlyph.SAM

static func of_arm(a: int) -> int:
	match a:
		LiteArm.DRONE: return LiteGlyph.DRONE
		LiteArm.CRUISE: return LiteGlyph.CRUISE
		_: return LiteGlyph.BALLISTIC

const FACTORY_PTS: PackedVector2Array = [
	Vector2(-5, 4), Vector2(5, 4), Vector2(5, -1), Vector2(1.7, -3.5), Vector2(1.7, -1), Vector2(-1.6, -3.5), Vector2(-1.6, -1), Vector2(-5, -3.5),
]
const SAM_PTS: PackedVector2Array = [
	Vector2(0, -5.5), Vector2(1.6, -2.5), Vector2(1.6, 2.5), Vector2(3.2, 4.8), Vector2(-3.2, 4.8), Vector2(-1.6, 2.5), Vector2(-1.6, -2.5),
]
## The attack drone of the logo (LiteLogo): a narrow nose, a delta wing swept
## back to the tips, the trailing edge stepping in to the tail. Nose along +x.
static var DRONE_PTS: PackedVector2Array = _mirror([Vector2(6.6, 0.0), Vector2(5.1, 0.5), Vector2(2.6, 0.8),
	Vector2(-3.7, 6.2), Vector2(-4.9, 6.2), Vector2(-3.2, 1.4), Vector2(-4.0, 0.7), Vector2(-4.8, 0.0)])
## A Tomahawk-like cruise missile seen from above: a long round body with a
## blunt ogive nose, short straight wings a little behind the middle and a
## cross of small fins at the tail.
static var CRUISE_PTS: PackedVector2Array = _mirror([Vector2(8.2, 0.0), Vector2(7.6, 0.6), Vector2(6.6, 0.95),
	Vector2(0.4, 0.95), Vector2(-0.5, 3.9), Vector2(-1.5, 3.9), Vector2(-1.4, 0.95),
	Vector2(-6.0, 0.95), Vector2(-7.6, 2.8), Vector2(-8.4, 2.8), Vector2(-7.9, 0.95), Vector2(-8.4, 0.0)])

## A shape symmetric about the x axis from its upper half (`half`, nose
## first, tail last, both on the axis).
static func _mirror(half: Array[Vector2]) -> PackedVector2Array:
	var p:= PackedVector2Array()
	for v: Vector2 in half:
		p.append(Vector2(v.x, -v.y))
	for i: int in range(half.size() - 2, 0, -1):
		p.append(half[i])
	return p
static var STAR_PTS: PackedVector2Array = _star()

static func _star() -> PackedVector2Array:
	var p:= PackedVector2Array()
	p.resize(10)
	for i: int in 10:
		var r: float = 5.6 if i % 2 == 0 else 2.3
		var a: float = -PI / 2 + i * PI / 5
		p[i] = Vector2(cos(a), sin(a)) * r
	return p

static func draw_ci(ci: CanvasItem, g: int, c: Vector2, s: float, col: Color, angle: float = 0, outline: Variant = null) -> void:
	match g:
		LiteGlyph.CAPITAL: poly(ci, STAR_PTS, c, s, angle, col, outline)
		LiteGlyph.FACTORY: poly(ci, FACTORY_PTS, c, s, angle, col, outline)
		LiteGlyph.SAM: poly(ci, SAM_PTS, c, s, angle, col, outline)
		LiteGlyph.DRONE: poly(ci, DRONE_PTS, c, s, angle, col, outline)
		LiteGlyph.CRUISE: poly(ci, CRUISE_PTS, c, s, angle, col, outline)
		LiteGlyph.GUN:
			var hub: Vector2 = c + Vector2(0, 1.6 * s)
			ci.draw_line(hub, c + Vector2(-2.6, -4.2) * s, col, 1.3 * s, true)
			ci.draw_line(hub, c + Vector2(2.6, -4.2) * s, col, 1.3 * s, true)
			ci.draw_circle(hub, 2.6 * s, col, true, -1, true)
		LiteGlyph.BALLISTIC: poly(ci, MISSILE_PTS, c, s * 1.05, angle, col, outline)

static var TRIS: Dictionary = {}

## A ballistic missile, nose along +x: a long pointed nose cone, a straight
## body, and fins swept back at the tail (two seen from above).
static var MISSILE_PTS: PackedVector2Array = _mirror([Vector2(8.2, 0.0), Vector2(6.8, 0.75), Vector2(4.6, 1.3),
	Vector2(-4.6, 1.3), Vector2(-6.8, 3.4), Vector2(-7.9, 3.4), Vector2(-7.0, 1.3), Vector2(-7.6, 0.0)])

static func missile(b: LiteBatch, c: Vector2, s: float, col: Color, angle: float, outline: Variant = null, rim: bool = true) -> void:
	b.shape(MISSILE_PTS, _cut(MISSILE_PTS), c, s, angle, col, outline, rim)

static func _cut(pts: PackedVector2Array) -> PackedInt32Array:
	if not TRIS.has(pts):
		TRIS[pts] = Geometry2D.triangulate_polygon(pts)
	return TRIS[pts]

static func draw(b: LiteBatch, g: int, c: Vector2, s: float, col: Color, angle: float = 0, outline: Variant = null, rim: bool = true) -> void:
	match g:
		LiteGlyph.CAPITAL: b.shape(STAR_PTS, _cut(STAR_PTS), c, s, angle, col, outline)
		LiteGlyph.FACTORY: b.shape(FACTORY_PTS, _cut(FACTORY_PTS), c, s, angle, col, outline)
		LiteGlyph.SAM: b.shape(SAM_PTS, _cut(SAM_PTS), c, s, angle, col, outline)
		LiteGlyph.DRONE: b.shape(DRONE_PTS, _cut(DRONE_PTS), c, s, angle, col, outline, rim)
		LiteGlyph.CRUISE: b.shape(CRUISE_PTS, _cut(CRUISE_PTS), c, s, angle, col, outline, rim)
		LiteGlyph.GUN:
			var hub: Vector2 = c + Vector2(0, 1.6 * s)
			b.line(hub, c + Vector2(-2.6, -4.2) * s, col, 1.3 * s)
			b.line(hub, c + Vector2(2.6, -4.2) * s, col, 1.3 * s)
			b.disc(hub, 2.6 * s, col)
		LiteGlyph.BALLISTIC: missile(b, c, s, col, angle, outline, rim)

## A glyph as a mesh, for drawing many of it at once (a MultiMesh): its fill
## white (each copy's colour tints it), edged when `edge` is given with a band
## `band` units wide and a soft fringe beyond, both in screen units at `scale`.
static func mesh(pts: PackedVector2Array, scale: float, edge: Variant = null, band: float = 1.1) -> ArrayMesh:
	var v:= PackedVector2Array()
	var c:= PackedColorArray()
	var idx:= PackedInt32Array()
	var n: int = pts.size()
	if edge != null:
		var e: Color = edge
		var mit: PackedVector2Array = LiteBatch._miter(pts)
		for r: int in 3:
			var off: float = 0.0 if r == 0 else (band if r == 1 else band + LiteBatch.FEATHER) / scale
			for i: int in n:
				v.append(pts[i] + mit[i] * off)
				c.append(Color(e, 0.0) if r == 2 else e)
		for i: int in n:
			var j: int = (i + 1) % n
			for r: int in 2:
				var a: int = r * n
				var b: int = a + n
				idx.append_array([a + i, a + j, b + j, a + i, b + j, b + i])
	var first: int = v.size()
	for i: int in n:
		v.append(pts[i])
		c.append(Color.WHITE)
	for t: int in _cut(pts):
		idx.append(first + t)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_INDEX] = idx
	var m:= ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return m

static func poly(ci: CanvasItem, src: PackedVector2Array, c: Vector2, s: float, angle: float, fill: Color, outline: Variant = null) -> void:
	var pts:= PackedVector2Array()
	pts.resize(src.size())
	var cs: float = cos(angle)
	var sn: float = sin(angle)
	for i: int in src.size():
		var v: Vector2 = src[i] * s
		pts[i] = c + Vector2(v.x * cs - v.y * sn, v.x * sn + v.y * cs)
	if outline != null:
		var loop: PackedVector2Array = pts.duplicate()
		loop.append(pts[0])
		ci.draw_polyline(loop, outline, 2.2, true)
	ci.draw_colored_polygon(pts, fill)

static func box(bg: Color, border: Color, radius: int, pad: float = 0, border_width: int = 1) -> StyleBoxFlat:
	var b:= StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.border_width_left = border_width
	b.border_width_right = border_width
	b.border_width_top = border_width
	b.border_width_bottom = border_width
	b.corner_radius_top_left = radius
	b.corner_radius_top_right = radius
	b.corner_radius_bottom_left = radius
	b.corner_radius_bottom_right = radius
	b.content_margin_left = pad
	b.content_margin_right = pad
	b.content_margin_top = pad
	b.content_margin_bottom = pad
	b.anti_aliasing = true
	return b
