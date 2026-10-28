class_name LiteRules
extends RefCounted
## Every number of the lite game in one place.

const START_MONEY: float = 320.0
const CAPITAL_INCOME: float = 3.0
const FACTORY_INCOME: float = 4.0
const ALERT_WORK: float = 0.5
## Capital health each working factory puts back per second, and the most all of them can.
const CAPITAL_REPAIR: float = 0.04
const MAX_REPAIR: float = 0.3
## Every factory a side already has makes the next one this much dearer.
const FACTORY_STEP: int = 20
## A destroyed factory leaves ruins that take its place in the region this long.
const RUIN_TIME: float = 180.0
## How often industry shifts between regions on each side.
const INDUSTRY_SHIFT: float = 120.0
## How often each side's intelligence locates one hidden site of the other's.
const INTEL_EVERY: float = 75.0
const INTERCEPTOR_COST: int = 10
const SAM_RACK: int = 6
const SAM_RELOAD: float = 3.5
const SAM_INTERVAL: float = 0.7
const GUN_INTERVAL: float = 0.45
const INTERCEPTOR_SPEED: float = 330.0
const ALL_CLEAR_AFTER: float = 3.0


## Price of a building kind (C# overload `Cost(LiteKind)`).
static func cost_kind(k: int) -> int:
	match k:
		LiteKind.FACTORY: return 130
		LiteKind.GUN: return 70
		LiteKind.SAM: return 240
		_: return 0


static func build_time(k: int) -> float:
	match k:
		LiteKind.FACTORY: return 8.0
		LiteKind.GUN: return 4.0
		LiteKind.SAM: return 7.0
		_: return 0.0


static func max_hp(k: int) -> float:
	match k:
		LiteKind.CAPITAL: return 120.0
		LiteKind.FACTORY: return 5.0
		LiteKind.GUN: return 2.0
		_: return 3.0


## A capital has AA guns of its own, a little shorter-ranged than a gun site.
static func range(k: int) -> float:
	match k:
		LiteKind.GUN: return 58.0
		LiteKind.SAM: return 125.0
		LiteKind.CAPITAL: return 50.0
		_: return 0.0


## Price of a weapon (C# overload `Cost(LiteArm)`).
static func cost(a: int) -> int:
	match a:
		LiteArm.DRONE: return 12
		LiteArm.CRUISE: return 55
		_: return 130


static func speed(a: int) -> float:
	match a:
		LiteArm.DRONE: return 26.0
		LiteArm.CRUISE: return 72.0
		_: return 220.0


static func damage(a: int) -> float:
	match a:
		LiteArm.DRONE: return 1.0
		LiteArm.CRUISE: return 2.0
		_: return 3.0


static func blast(a: int) -> float:
	match a:
		LiteArm.DRONE: return 12.0
		LiteArm.CRUISE: return 16.0
		_: return 21.0


static func scatter(a: int) -> float:
	match a:
		LiteArm.DRONE: return 5.0
		LiteArm.CRUISE: return 3.0
		_: return 8.0


static func sam_pk(a: int) -> float:
	match a:
		LiteArm.DRONE: return 0.9
		LiteArm.CRUISE: return 0.8
		_: return 0.45


static func gun_pk(a: int) -> float:
	match a:
		LiteArm.DRONE: return 0.25
		LiteArm.CRUISE: return 0.08
		_: return 0.0


## How far round itself a weapon in flight reveals the other side's sites.
static func spot_radius(a: int) -> float:
	match a:
		LiteArm.DRONE: return 46.0
		LiteArm.CRUISE: return 26.0
		_: return 0.0


## Regions within this distance of a drone or cruise missile go under alert...
static func alert_radius(a: int) -> float:
	match a:
		LiteArm.DRONE: return 30.0
		LiteArm.CRUISE: return 34.0
		_: return 0.0


## ...and so do those it would reach in this many seconds if it kept its
## heading. Nobody on the ground knows its route.
static func heading(a: int) -> float:
	match a:
		LiteArm.DRONE: return 4.0
		LiteArm.CRUISE: return 3.0
		_: return 0.0
