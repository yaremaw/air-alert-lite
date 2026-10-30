class_name LiteReport
extends RefCounted
## One enemy attack on us, from its first launch until its last drone or
## missile is down or has struck. Large ones become an attack report.

var start: float = 0.0
var end: float = 0.0
## By weapon (drone, cruise, ballistic): launched at us, and shot down.
var launched: PackedInt32Array = PackedInt32Array([0, 0, 0])
var downed: PackedInt32Array = PackedInt32Array([0, 0, 0])
## Weapons that struck something, and the sites they destroyed.
var hits: int = 0
var lost: PackedStringArray = PackedStringArray()
var capital_damage: float = 0.0
## Still in the air, and when anything last happened.
var alive: int = 0
var last: float = 0.0

var total: int:
	get: return launched[0] + launched[1] + launched[2]

var total_downed: int:
	get: return downed[0] + downed[1] + downed[2]
