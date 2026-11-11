class_name LiteIconList
extends Control
## A short list of sites, each its icon and its name: an operation's targets
## in the briefing and on the front, instead of a paragraph about them.

var items: Array = []

func _init(p_items: Array = []) -> void:
	items = p_items
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 22 * items.size())

## The sites `kinds` (LiteKind values), each once with a count where repeated.
static func of_kinds(kinds: Array[int]) -> LiteIconList:
	var count: Dictionary = {}
	var order: Array[int] = []
	for k: int in kinds:
		if not count.has(k):
			order.append(k)
		count[k] = int(count.get(k, 0)) + 1
	var out: Array = []
	for k: int in order:
		out.append([k, ("%d %ss" % [count[k], LiteGlyphs.name(k).to_lower()]) if count[k] > 1 else LiteGlyphs.name(k)])
	return LiteIconList.new(out)

func _draw() -> void:
	var y: float = 11.0
	for it: Array in items:
		draw_circle(Vector2(10, y), 9.0, LiteGlyphs.PAGE)
		draw_arc(Vector2(10, y), 9.0, 0, TAU, 24, LiteGlyphs.ENEMY, 1.3, true)
		LiteGlyphs.draw_ci(self, LiteGlyphs.of(it[0]), Vector2(10, y), 0.8, Color.WHITE)
		draw_string(LiteGlyphs.font, Vector2(26, y + 5), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, LiteGlyphs.TEXT)
		y += 22.0
