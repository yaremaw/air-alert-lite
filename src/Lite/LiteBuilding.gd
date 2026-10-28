class_name LiteBuilding
extends RefCounted

var id: int = 0
var side: int = 0
var region: int = 0
var ammo: int = 0
var kind: int = 0  # LiteKind
var pos: Vector2 = Vector2.ZERO
var hp: float = 0.0
var max_hp: float = 0.0
var build: float = 0.0
var build_total: float = 0.0
var cool: float = 0.0
var reload: float = 0.0
var dead_at: float = 0.0
var flash: float = 0.0
var fire_flash: float = 0.0
## Weapons it has shot down; a sharp enemy goes for the busiest air defence.
var kills: int = 0
var alive: bool = true
var seen: Array[bool] = [false, false]
var ready: bool:
	get: return build <= 0.0
var is_ad: bool:
	get: return kind == LiteKind.GUN or kind == LiteKind.SAM
## Shoots like an AA gun: gun sites and the capital's own guns.
var is_gun: bool:
	get: return kind == LiteKind.GUN or kind == LiteKind.CAPITAL
