class_name LiteRegion
extends RefCounted

var id: int = 0
var side: int = 0
var area: int = 0
var name: String = ""

var city: bool = false

var parent: int = -1
var label: Vector2 = Vector2.ZERO
var center: Vector2 = Vector2.ZERO

var spots: Array[Vector2] = []

var neighbors: Dictionary[int, bool] = {}
