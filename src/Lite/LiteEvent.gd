class_name LiteEvent
extends RefCounted

var type: int = 0
var side: int = 0
var region: int = 0
var pos: Vector2 = Vector2.ZERO
var arm: int = 0
var kind: int = 0
var value: float = 0.0
var raid: LiteRaid = null

func _init(p_type: int = 0, p_side: int = 0, p_region: int = 0, p_pos: Vector2 = Vector2.ZERO, p_arm: int = 0, p_kind: int = 0, p_value: float = 0.0, p_raid: LiteRaid = null) -> void:
	type = p_type
	side = p_side
	region = p_region
	pos = p_pos
	arm = p_arm
	kind = p_kind
	value = p_value
	raid = p_raid
