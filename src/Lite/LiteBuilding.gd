class_name LiteBuilding
extends RefCounted

var id: int = 0
var side: int = 0
var region: int = 0
var ammo: int = 0
var kind: int = 0
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

var kills: int = 0
var alive: bool = true
var seen: Array[bool] = [false, false]

## Phase 4 (see LiteSense, LiteStock):
## Whether a friendly radar's picture reaches it (air defence; see LiteSense.link).
var linked: bool = false
## The radar it is linked to, if any.
var link: LiteBuilding = null
## A factory's production line (LiteStock.DRONES, CRUISE, BALLISTIC, AMMO).
var line: int = 0
## Being repaired: hit points restored a second, until whole (see LiteStock.repair).
var repairing: float = 0.0
## Standing in the snow (drawn snowed over; see LiteBiome).
var winter: bool = false
## Which biome it stands in (LiteBiome), for its look and what it is.
var biome: int = 0
## A mobile unit (phase 4b, see LiteSim._move_mobiles): the region it keeps
## to, where it is driving, which way it faces, how fast it goes now, and
## the drone it is chasing.
var home: int = -1
var goal: Vector2 = Vector2.ZERO
var heading: float = 0.0
var pace: float = 0.0
## A unit on the move (kind LiteKind.UNIT, see LiteUnit): its type, its
## route, its length and how far along it is, a wait before it sets off (or a
## halt), where it halts, the engine a train's wagon follows and how far
## behind, whether it got to its route's end, whether it crossed our border.
var unit: int = -1
var route: PackedVector2Array = PackedVector2Array()
var route_len: float = 0.0
var dist: float = 0.0
var wait: float = 0.0
var halts: PackedFloat32Array = PackedFloat32Array()
var leader: LiteBuilding = null
var gap: float = 0.0
var arrived: bool = false
var crossed: bool = false
## A mobile launcher: until when a salvo gives it away, where it was last
## seen, when it fires next and when it moves on, the salvos it got off.
var reveal_until: float = -1.0
var seen_pos: Vector2 = Vector2.ZERO
var fire_at: float = 0.0
var scoot_at: float = -1.0
var salvos: int = 0
## Whether the player is at its gun (see LiteGunner): it does not fire by itself.
var manual: bool = false
## A patrolling gun: when it next looks round for something to chase.
var hunt_at: float = 0.0
## A gun's turret (phase 4c): where it was last laid (an angle) and when;
## the turret drawn turns to it (`turret`, the view's), back to the way the
## vehicle drives when it has not fired for a while.
var aim_to: float = 0.0
var aim_time: float = -99.0
var turret: float = 0.0
var chase: LiteWeapon = null

var ready: bool:
	get: return build <= 0.0
var is_ad: bool:
	get: return kind == LiteKind.GUN or kind == LiteKind.SAM or kind == LiteKind.MOBILE

var is_gun: bool:
	get: return kind == LiteKind.GUN or kind == LiteKind.CAPITAL or kind == LiteKind.MOBILE

## Its state, by what is left of it: 0 operational, 1 damaged, 2 heavily
## damaged (a factory makes nothing), 3 destroyed.
var condition: int:
	get:
		if not alive: return 3
		var k: float = hp / maxf(0.001, max_hp)
		return 0 if k >= 0.75 else (1 if k >= 0.4 else 2)
