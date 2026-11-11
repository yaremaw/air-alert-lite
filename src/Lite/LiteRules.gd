class_name LiteRules
extends RefCounted

const START_MONEY: float = 320.0
## The war's clock: game minutes per second of play, so a war of a quarter
## of an hour or so runs for weeks. DAY is one game day, in seconds of play.
const GAME_MINUTES: float = 30.0
const DAY: float = 1440.0 / GAME_MINUTES
const CAPITAL_INCOME: float = 3.0
const FACTORY_INCOME: float = 4.0
const ALERT_WORK: float = 0.5

const CAPITAL_REPAIR: float = 0.04
const MAX_REPAIR: float = 0.3

const FACTORY_STEP: int = 20

const RUIN_TIME: float = 180.0

const INDUSTRY_SHIFT: float = 120.0

const INTEL_EVERY: float = 75.0
const INTERCEPTOR_COST: int = 10
const SAM_RACK: int = 6
const SAM_RELOAD: float = 3.5
const SAM_INTERVAL: float = 0.7
const GUN_INTERVAL: float = 0.45
## A SAM's top speed; it leaves the rail slower and accelerates (see sam_pace).
const INTERCEPTOR_SPEED: float = 160.0
const ALL_CLEAR_AFTER: float = 3.0
## A destroyed ammo depot's secondary explosions: how far they reach, and the
## damage they do to every site there.
const DEPOT_BLAST: float = 34.0
const DEPOT_DAMAGE: float = 2.0
## While a side has a radar standing, its SAMs hit this much more often.
const RADAR_PK: float = 1.2

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
		LiteKind.DEPOT: return 6.0
		LiteKind.RADAR: return 3.0
		LiteKind.LAUNCHER: return 4.0
		_: return 3.0

static func range(k: int) -> float:
	match k:
		LiteKind.GUN: return 58.0
		LiteKind.SAM: return 125.0
		LiteKind.CAPITAL: return 50.0
		_: return 0.0

static func cost(a: int) -> int:
	match a:
		LiteArm.DRONE: return 12
		LiteArm.CRUISE: return 55
		_: return 130

static func speed(a: int) -> float:
	match a:
		LiteArm.DRONE: return 26.0
		LiteArm.CRUISE: return 72.0
		_: return 165.0

## A ballistic missile is slow off its launcher and gathers speed all the way
## down: its speed, as a share of `speed`, at progress `p` (half at launch,
## 1.8 times at impact).
static func ballistic_pace(p: float) -> float:
	return 0.5 + 1.3 * p * p

## Over a whole flight that averages out to `speed` divided by this.
const BALLISTIC_SLOWER: float = 1.26

## How fast a weapon covers its whole route on average, for planning.
static func mean_speed(a: int) -> float:
	return speed(a) / BALLISTIC_SLOWER if a == LiteArm.BALLISTIC else speed(a)

## A SAM's speed `age` seconds after launch, as a share of INTERCEPTOR_SPEED.
static func sam_pace(age: float) -> float:
	return minf(1.3, 0.4 + 2.0 * age)

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

static func spot_radius(a: int) -> float:
	match a:
		LiteArm.DRONE: return 46.0
		LiteArm.CRUISE: return 26.0
		_: return 0.0

static func alert_radius(a: int) -> float:
	match a:
		LiteArm.DRONE: return 30.0
		LiteArm.CRUISE: return 34.0
		_: return 0.0

static func heading(a: int) -> float:
	match a:
		LiteArm.DRONE: return 4.0
		LiteArm.CRUISE: return 3.0
		_: return 0.0
