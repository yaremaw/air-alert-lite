class_name LiteInterceptor
extends RefCounted

var side: int = 0
var target: LiteWeapon = null
var from: LiteBuilding = null
var pos: Vector2 = Vector2.ZERO
var goal: Vector2 = Vector2.ZERO
var age: float = 0.0
var alive: bool = true
var trail: PackedVector2Array = PackedVector2Array()
