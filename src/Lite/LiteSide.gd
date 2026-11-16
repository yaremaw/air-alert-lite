class_name LiteSide
extends RefCounted

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

var hit_log: Array[Hit] = []

## Phase 4. Its stockpiles by line (LiteStock: drones, cruise, ballistic,
## interceptors), what each holds at most, and what is being made a second.
var stock: PackedFloat32Array = PackedFloat32Array(LiteStock.START)
var hold: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var making: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## How hard it has been launching lately (see LiteStock.strain_mul).
var strain: float = 0.0
## Its people's morale, 0 to 100 (LiteMorale), and how it has been moving
## lately (for the top bar's arrow); off in tests that want the old war.
var morale: float = LiteMorale.START
var morale_trend: float = 0.0
var morale_on: bool = true

func _init(p_index: int) -> void:
	index = p_index
