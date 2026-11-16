class_name LiteRaid
extends RefCounted

var id: int = 0
var side: int = 0
var total: int = 0
var launched: int = 0
var done: int = 0
var down: int = 0
var hits: int = 0

var reported: bool = false
## A scouting flight (drones sent to find sites), drawn as recon drones.
var scout: bool = false
var target: Vector2 = Vector2.ZERO
var by_arm: Array[int] = [0, 0, 0]
var destroyed: Array[String] = []
