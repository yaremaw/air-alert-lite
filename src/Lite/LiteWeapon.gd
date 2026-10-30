class_name LiteWeapon
extends RefCounted

var id: int = 0
var side: int = 0
var leg: int = 0
var engaged: int = 0
var arm: int = 0
var raid: LiteRaid = null
var pos: Vector2 = Vector2.ZERO
var start: Vector2 = Vector2.ZERO
var target: Vector2 = Vector2.ZERO
var dir: Vector2 = Vector2.ZERO
var speed: float = 0.0
var length: float = 0.0
var flown: float = 0.0
var trail_acc: float = 0.0
var alive: bool = true

var aim: LiteBuilding = null
## The attack it belongs to (enemy weapons, for the attack report) and our
## regions it has crossed (for the statistics).
var report: LiteReport = null
var crossed: Dictionary = {}

var seen: Array[bool] = [false, false]
var path: PackedVector2Array = PackedVector2Array()
var trail: PackedVector2Array = PackedVector2Array()
var progress: float:
	get: return flown / length if length > 0 else 1.0
