class_name LiteCmdLabels
extends Node2D
## Names and place marks on the map in the Modern Military Command look (see
## LiteCmdView); the legacy look's names are LiteLabels, untouched. No roads:
## the game has none of its own, and drawn ones only cluttered the map. (No
## rivers either: the map has none.)
##
## By rank: the capitals (drawn by LiteCmdView, with their frames and tags);
## each province's centre, a small ringed dot over its name; towns on an
## operation's map, a small square and a compact name; the provinces' names
## in spaced capitals; the neighbouring countries and the sea, fainter still.
## Sizes are kept in screen pixels whatever the map's scale; a town's name
## moves to the other side of its square, or is left out, when it would cover
## a province's name.

## The reference grid's spacing, in map units (the shaders draw its lines).
const GRID: float = 60.0

var map: LiteMap = null
func _draw() -> void:
	var px: float = 1.0 / maxf(0.01, get_viewport().canvas_transform.x.x)
	var taken: Array[Rect2] = []
	# The world round the countries.
	var w: LiteWorld = map.world
	if w != null:
		for k: int in w.label_text.size():
			var kind: int = w.label_kind[k]
			if kind == 2:
				spaced(self, w.label_at[k], w.label_text[k].to_upper(), roundi(9.0 * px), Color(LiteTheme.MUTED, 0.45), 1.2 * px)
				continue
			var sea: bool = kind == 1
			spaced(self, w.label_at[k], w.label_text[k].to_upper(), roundi((10.0 if sea else 10.0) * px),
				Color("#3E5A75") if sea else Color("#4D5D6E"), (2.6 if not sea else 1.6) * px)
	# The provinces.
	var names: Dictionary = {}
	if not map.label_only.is_empty():
		names = map.label_only
	else:
		for r: LiteRegion in map.regions:
			if not r.city and r.name != "":
				names[r.id] = r.name
	var psize: int = maxi(5, roundi(9.5 * px))
	# A province's centre: a ringed dot over its name (on the war map, where
	# each name is a province's; not the front's region names, nor an
	# operation's, whose towns are marked below).
	# (No longer: the user found the dots over the names noise.)
	var centres: bool = false
	for id: int in names:
		var at: Vector2 = map.regions[id].label
		if centres:
			var c: Vector2 = at - Vector2(0, psize * 1.05)
			draw_circle(c, 3.2 * px, Color(LiteTheme.BG, 0.8))
			draw_arc(c, 2.6 * px, 0, TAU, 16, Color(LiteTheme.TEXT, 0.8), 1.0 * px, true)
			draw_circle(c, 1.1 * px, Color(LiteTheme.TEXT, 0.9))
		var rect: Rect2 = spaced(self, at, str(names[id]).to_upper(), psize, Color(LiteTheme.TEXT, 0.9), 1.3 * px)
		taken.append(rect)
	# Towns on an operation's map.
	var tsize: int = maxi(5, roundi(9.0 * px))
	for k: int in map.towns.size():
		var big: bool = map.town_size[k] >= 2
		var at: Vector2 = map.towns[k] + Vector2(0, -12)
		var h: float = (3.2 if big else 2.2) * px
		draw_rect(Rect2(at - Vector2(h, h), Vector2(h, h) * 2.0), LiteTheme.BG)
		draw_rect(Rect2(at - Vector2(h, h), Vector2(h, h) * 2.0), LiteTheme.TEXT, false, 1.0 * px)
		if big:
			draw_rect(Rect2(at - Vector2(h, h) * 0.4, Vector2(h, h) * 0.8), LiteTheme.TEXT)
		var name_: String = _town_name(k)
		if name_ == "":
			continue
		var font: Font = LiteGlyphs.font
		var tw: float = font.get_string_size(name_, HORIZONTAL_ALIGNMENT_LEFT, -1, tsize).x
		var placed: bool = false
		for side: float in [1.0, -1.0]:
			var x: float = at.x + side * (h + 3.0 * px) - (tw if side < 0 else 0.0)
			var rect:= Rect2(x, at.y - tsize * 0.6, tw, tsize * 1.2)
			var clear: bool = true
			for t: Rect2 in taken:
				if t.intersects(rect):
					clear = false
					break
			if clear:
				_text(self, Vector2(x, at.y + tsize * 0.36), name_, tsize, Color(LiteTheme.TEXT, 0.9))
				taken.append(rect)
				placed = true
				break

## The name of an operation map's town: the district it stands in.
func _town_name(k: int) -> String:
	var id: int = map.region_at(map.towns[k])
	if id == LiteMap.NONE or id >= map.regions.size():
		return ""
	var r: LiteRegion = map.regions[id]
	# Its province's name is there already when it is the province's label.
	if map.label_only.has(id) and str(map.label_only[id]) == r.name:
		return ""
	return r.name

## A name in spaced capitals, centred on `at`, with a dark halo; returns the
## space it takes.
static func spaced(ci: CanvasItem, at: Vector2, text: String, size: int, col: Color, track: float) -> Rect2:
	var font: Font = _tracked(roundi(track))
	var total: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos:= Vector2(at.x - total / 2.0, at.y + size * 0.36)
	ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(3, roundi(size * 0.4)), Color(LiteTheme.BG, 0.85))
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return Rect2(at.x - total / 2.0, at.y - size * 0.6, total, size * 1.2)

## The bold face with `track` units between letters (one string drawn at
## once, rather than a letter at a time).
static var _tracks: Dictionary = {}

static func _tracked(track: int) -> Font:
	var f: FontVariation = _tracks.get(track)
	if f == null:
		f = FontVariation.new()
		f.base_font = LiteGlyphs.bold
		f.spacing_glyph = track
		_tracks[track] = f
	return f

static func _text(ci: CanvasItem, at: Vector2, text: String, size: int, col: Color) -> void:
	var font: Font = LiteGlyphs.font
	ci.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(3, roundi(size * 0.4)), Color(LiteTheme.BG, 0.85))
	ci.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

## A capital's name: bold capitals centred at `at`, on a dark plate edged
## at the bottom in its side's colour.
static func tag(ci: CanvasItem, at: Vector2, text: String, size: int, col: Color, side_col: Color) -> void:
	var font: Font = LiteGlyphs.bold
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pad: float = size * 0.45
	var r:= Rect2(at.x - w / 2.0 - pad, at.y - size * 0.95, w + pad * 2.0, size * 1.45)
	ci.draw_rect(r, Color(LiteTheme.BG, 0.82))
	ci.draw_rect(Rect2(r.position.x, r.end.y - size * 0.12, r.size.x, size * 0.12), side_col)
	ci.draw_string(font, Vector2(at.x - w / 2.0, at.y + size * 0.05), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
