class_name LiteLabels
extends Node2D

var map: LiteMap = null

func _draw() -> void:
	# The neighbours and the sea, faint, their names spaced out.
	var w: LiteWorld = map.world
	if w != null:
		for k: int in w.label_text.size():
			var kind: int = w.label_kind[k]
			if kind == 2:
				# A province beyond an operation's map: its name, faint.
				draw_label(self, w.label_at[k], w.label_text[k], 11, Color(1, 1, 1, 0.4))
				continue
			var sea: bool = kind == 1
			var text: String = " ".join(w.label_text[k].to_upper().split("")) if not sea else w.label_text[k]
			draw_label(self, w.label_at[k], text, 12 if not sea else 13, LiteGlyphs.SEA_NAME if sea else LiteGlyphs.NEUTRAL_NAME)
	# Towns on an operation's map: a dot over each district's name, larger
	# for the province's city.
	for k: int in map.towns.size():
		var big: bool = map.town_size[k] >= 2
		var at: Vector2 = map.towns[k] + Vector2(0, -10)
		draw_circle(at, 4.0 if big else 2.6, Color(0, 0, 0, 0.45))
		draw_circle(at, 3.0 if big else 1.8, Color(1, 1, 1, 0.9))
	if not map.label_only.is_empty():
		for id: int in map.label_only:
			draw_label(self, map.regions[id].label, map.label_only[id], 12, Color(1, 1, 1, 0.92))
		return
	for r: LiteRegion in map.regions:
		if not r.city and r.name != "":
			draw_label(self, r.label, r.name, 11, Color(1, 1, 1, 0.92))

static func draw_label(ci: CanvasItem, at: Vector2, text: String, size: int, col: Color) -> void:
	var font: Font = LiteGlyphs.bold
	var pos:= Vector2(at.x - 100, at.y + size * 0.36)
	ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 200, size, 4, Color(0, 0, 0, 0.28))
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 200, size, col)
