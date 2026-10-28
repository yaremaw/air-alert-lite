class_name LiteGlyphs
extends RefCounted
## Colours, fonts, names and the small flat icons of the lite game. Icons are
## polygons, so the same glyph serves the map and the buttons at any size.

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

# Region fills, after map.ukrainealarm.com.
const OUR_LAND: Color = Color("#3a3d46")
const ENEMY_LAND: Color = Color("#6a2622")
const AIR_ALERT: Color = Color("#d4a017")
const BALLISTIC_ALERT: Color = Color("#e0574a")
const ENEMY_ALERT: Color = Color("#b13d33")
const HIT_GLOW: Color = Color("#ff8a3d")

static var font: Font = ThemeDB.fallback_font
static var bold: Font = ThemeDB.fallback_font
static var _loaded: bool = false


static func side_color(side: int) -> Color:
	return OURS if side == 0 else ENEMY


## Inter (assets/fonts, SIL OFL) with tabular figures, so counters do not
## jitter; a bolder cut of it for titles and map labels.
static func load_fonts() -> void:
	if _loaded:
		return
	_loaded = true
	const PATH: String = "res://assets/fonts/Inter.ttf"
	if not FileAccess.file_exists(PATH):
		return
	var f := FontFile.new()
	if f.load_dynamic_font(PATH) != OK:
		return
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.generate_mipmaps = false
	var tnum: Dictionary = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
	var regular := FontVariation.new()
	regular.base_font = f
	regular.opentype_features = tnum
	var heavy := FontVariation.new()
	heavy.base_font = f
	heavy.opentype_features = tnum
	heavy.variation_embolden = 0.6
	font = regular
	bold = heavy
	# The panel and the HUD draw well over the default 64 strings a frame;
	# with a small cache every one of them is shaped again each frame.
	font.set_cache_capacity(512, 64)
	bold.set_cache_capacity(512, 64)
	ThemeDB.fallback_font = font


## Was the Name(LiteKind) overload.
static func name(k: int) -> String:
	match k:
		LiteKind.CAPITAL: return "Capital"
		LiteKind.FACTORY: return "Factory"
		LiteKind.GUN: return "AA gun"
		_: return "SAM"


## Was the Name(LiteArm) overload.
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


## Was the Of(LiteKind) overload.
static func of(k: int) -> int:
	match k:
		LiteKind.CAPITAL: return LiteGlyph.CAPITAL
		LiteKind.FACTORY: return LiteGlyph.FACTORY
		LiteKind.GUN: return LiteGlyph.GUN
		_: return LiteGlyph.SAM


## Was the Of(LiteArm) overload.
static func of_arm(a: int) -> int:
	match a:
		LiteArm.DRONE: return LiteGlyph.DRONE
		LiteArm.CRUISE: return LiteGlyph.CRUISE
		_: return LiteGlyph.BALLISTIC


# Shapes on a grid of about ten units, pointing right (weapons) or up.
const FACTORY_PTS: PackedVector2Array = [
	Vector2(-5, 4), Vector2(5, 4), Vector2(5, -1), Vector2(1.7, -3.5), Vector2(1.7, -1), Vector2(-1.6, -3.5), Vector2(-1.6, -1), Vector2(-5, -3.5),
]
const SAM_PTS: PackedVector2Array = [
	Vector2(0, -5.5), Vector2(1.6, -2.5), Vector2(1.6, 2.5), Vector2(3.2, 4.8), Vector2(-3.2, 4.8), Vector2(-1.6, 2.5), Vector2(-1.6, -2.5),
]
const DRONE_PTS: PackedVector2Array = [Vector2(6, 0), Vector2(-4, -5.5), Vector2(-2, 0), Vector2(-4, 5.5)]
const CRUISE_PTS: PackedVector2Array = [
	Vector2(7, 0), Vector2(4, -1.3), Vector2(0, -1.3), Vector2(-2, -4.5), Vector2(-3.5, -4.5), Vector2(-2.5, -1.3), Vector2(-6, -1.3),
	Vector2(-7, -3), Vector2(-7.5, -3), Vector2(-7.5, 3), Vector2(-7, 3), Vector2(-6, 1.3), Vector2(-2.5, 1.3), Vector2(-3.5, 4.5),
	Vector2(-2, 4.5), Vector2(0, 1.3), Vector2(4, 1.3),
]
static var STAR_PTS: PackedVector2Array = _star()


static func _star() -> PackedVector2Array:
	var p := PackedVector2Array()
	p.resize(10)
	for i: int in 10:
		var r: float = 5.6 if i % 2 == 0 else 2.3
		var a: float = -PI / 2 + i * PI / 5
		p[i] = Vector2(cos(a), sin(a)) * r
	return p


## Was the Draw(CanvasItem, ...) overload. Draws a glyph centred on `c`, `s`
## pixels per grid unit, turned by `angle`. `outline`: a Color, or null.
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
		LiteGlyph.BALLISTIC:
			if outline != null:
				ci.draw_circle(c, 3.6 * s, outline, true, -1, true)
			ci.draw_circle(c, 2.8 * s, col, true, -1, true)


## Triangles of each shape, cut once (keyed by the shape's points).
static var TRIS: Dictionary = {}


static func _cut(pts: PackedVector2Array) -> PackedInt32Array:
	if not TRIS.has(pts):
		TRIS[pts] = Geometry2D.triangulate_polygon(pts)
	return TRIS[pts]


## Was the Draw(LiteBatch, ...) overload. The same glyphs into a batch of
## triangles, for the map; each shape is cut into triangles once.
static func draw(b: LiteBatch, g: int, c: Vector2, s: float, col: Color, angle: float = 0, outline: Variant = null) -> void:
	match g:
		LiteGlyph.CAPITAL: b.shape(STAR_PTS, _cut(STAR_PTS), c, s, angle, col, outline)
		LiteGlyph.FACTORY: b.shape(FACTORY_PTS, _cut(FACTORY_PTS), c, s, angle, col, outline)
		LiteGlyph.SAM: b.shape(SAM_PTS, _cut(SAM_PTS), c, s, angle, col, outline)
		LiteGlyph.DRONE: b.shape(DRONE_PTS, _cut(DRONE_PTS), c, s, angle, col, outline)
		LiteGlyph.CRUISE: b.shape(CRUISE_PTS, _cut(CRUISE_PTS), c, s, angle, col, outline)
		LiteGlyph.GUN:
			var hub: Vector2 = c + Vector2(0, 1.6 * s)
			b.line(hub, c + Vector2(-2.6, -4.2) * s, col, 1.3 * s)
			b.line(hub, c + Vector2(2.6, -4.2) * s, col, 1.3 * s)
			b.disc(hub, 2.6 * s, col)
		LiteGlyph.BALLISTIC:
			if outline != null:
				b.disc(c, 3.6 * s, outline)
			b.disc(c, 2.8 * s, col)


static func poly(ci: CanvasItem, src: PackedVector2Array, c: Vector2, s: float, angle: float, fill: Color, outline: Variant = null) -> void:
	var pts := PackedVector2Array()
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
	var b := StyleBoxFlat.new()
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
