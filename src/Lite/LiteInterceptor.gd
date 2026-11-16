class_name LiteInterceptor
extends RefCounted

var side: int = 0
var target: LiteWeapon = null
var from: LiteBuilding = null
var pos: Vector2 = Vector2.ZERO
var goal: Vector2 = Vector2.ZERO
var age: float = 0.0
var alive: bool = true
## Its chance to hit, set when fired (phase 4: the site's radar link, the
## weather); -1 under the old rules.
var pk: float = -1.0
