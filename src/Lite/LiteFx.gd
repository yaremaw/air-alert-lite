class_name LiteFx
extends RefCounted

var kind: int = 0  # LiteFxKind
var a: Vector2 = Vector2.ZERO
var b: Vector2 = Vector2.ZERO
var age: float = 0.0
var life: float = 0.0
var size: float = 0.0
var side: int = 0


## Takes the fields in declaration order, all optional (C# object initializer).
func _init(p_kind: int = 0, p_a: Vector2 = Vector2.ZERO, p_b: Vector2 = Vector2.ZERO, p_age: float = 0.0, p_life: float = 0.0, p_size: float = 0.0, p_side: int = 0) -> void:
	kind = p_kind
	a = p_a
	b = p_b
	age = p_age
	life = p_life
	size = p_size
	side = p_side
