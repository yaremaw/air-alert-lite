class_name LiteRegion
extends RefCounted
## One region of the lite map, like an oblast on an air-alert map.

var id: int = 0
var side: int = 0
var area: int = 0
var name: String = ""
## The small city region round a capital ("м. Київ" on the real map).
var city: bool = false
## For a city region, the region round it.
var parent: int = -1
var label: Vector2 = Vector2.ZERO
var center: Vector2 = Vector2.ZERO
## Points well inside the region: launch points and building spots.
var spots: Array[Vector2] = []
## Was HashSet<int>: region id -> true, in the order they were found.
var neighbors: Dictionary[int, bool] = {}
