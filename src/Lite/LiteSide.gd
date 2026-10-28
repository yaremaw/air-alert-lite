class_name LiteSide
extends RefCounted

## One entry of `hit_log` (was the tuple `(Vector2 P, float T)`).
class Hit:
	var p: Vector2
	var t: float

	func _init(p_p: Vector2, p_t: float) -> void:
		p = p_p
		t = p_t


var index: int = 0
var money: float = LiteRules.START_MONEY
var income: float = 0.0
var repair: float = 0.0
var war_fund: float = 0.0
var last_raid_loss: float = 0.0
var capital: LiteBuilding = null
var launched: int = 0
var hits: int = 0
var downed: int = 0
var lost: int = 0
var destroyed: int = 0
## Where the other side's weapons came down on our land lately (the AI defends there).
var hit_log: Array[Hit] = []


func _init(p_index: int) -> void:
	index = p_index
