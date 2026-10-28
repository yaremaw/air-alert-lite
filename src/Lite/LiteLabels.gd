class_name LiteLabels
extends Node2D
## The region names. They never change, so they are drawn once and kept,
## under everything the map draws each frame.

var map: LiteMap = null


func _draw() -> void:
	for r: LiteRegion in map.regions:
		if not r.city:
			draw_label(self, r.label, r.name, 11, Color(1, 1, 1, 0.92))


## Was `Draw` in C#: renamed because `draw` is a CanvasItem signal.
static func draw_label(ci: CanvasItem, at: Vector2, text: String, size: int, col: Color) -> void:
	var font: Font = LiteGlyphs.bold
	var pos := Vector2(at.x - 100, at.y + size * 0.36)
	ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 200, size, 4, Color(0, 0, 0, 0.28))
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 200, size, col)
