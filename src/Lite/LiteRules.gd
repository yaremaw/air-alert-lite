class_name LiteRules
extends RefCounted

const START_MONEY: float = 320.0
## The war's clock: game minutes per second of play, so a war of a quarter
## of an hour or so runs for weeks. DAY is one game day, in seconds of play.
const GAME_MINUTES: float = 30.0
const DAY: float = 1440.0 / GAME_MINUTES
const CAPITAL_INCOME: float = 3.0
const FACTORY_INCOME: float = 4.0
## Phase 4: a factory makes weapons besides (LiteStock), so it brings in less
## money of its own.
const FACTORY_INCOME_P4: float = 0.0
## A refinery's money a second (phase 4b: the money comes from refineries,
## the weapons from factories).
const REFINERY_INCOME: float = 2.5
## How fast a damaged site mends by itself, as a share of its health a
## second (not while its region is under air alert).
const SELF_REPAIR: float = 1.0 / 40.0
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
## Phase 4: the armoured AA gun's rotary cannon fires in short streams, more
## often and each less likely to hit (the same kills a second as a burst
## every GUN_INTERVAL; see LiteSim.ad_pk).
const MINIGUN_INTERVAL: float = 0.25
## Phase 4d: jet attack drones (Geran-3 style), once a side has them in
## place of its propeller ones: a fifth faster, harder to bring down (every
## shot at one this likely to hit, of a propeller drone's), built at this
## share of the rate.
const JET_SPEED: float = 1.2
const JET_PK: float = 0.6
const JET_MAKE: float = 0.6
## A SAM's top speed; it leaves the rail slower and accelerates (see sam_pace).
const INTERCEPTOR_SPEED: float = 160.0
const ALL_CLEAR_AFTER: float = 3.0
## A destroyed ammo depot's secondary explosions: how far they reach, and the
## damage they do to every site there.
const DEPOT_BLAST: float = 34.0
const DEPOT_DAMAGE: float = 2.0
## While a side has a radar standing, its SAMs hit this much more often.
const RADAR_PK: float = 1.2

## What a site costs to build. Phase 4 (2026-11-15): AA guns dearer (they
## hit far more often now, close in), radars and mobile units new.
static func cost_kind(k: int) -> int:
	match k:
		LiteKind.FACTORY: return 130
		LiteKind.GUN: return 110
		LiteKind.SAM: return 240
		LiteKind.MOBILE: return 60
		LiteKind.RADAR: return 200
		LiteKind.MRADAR: return 90
		LiteKind.REFINERY: return 150
		_: return 0

static func build_time(k: int) -> float:
	match k:
		LiteKind.FACTORY: return 8.0
		LiteKind.GUN: return 4.0
		LiteKind.SAM: return 7.0
		LiteKind.MOBILE: return 2.5
		LiteKind.RADAR: return 9.0
		LiteKind.MRADAR: return 4.0
		LiteKind.REFINERY: return 7.0
		_: return 0.0

static func max_hp(k: int) -> float:
	match k:
		LiteKind.CAPITAL: return 120.0
		LiteKind.FACTORY: return 5.0
		LiteKind.GUN: return 2.0
		LiteKind.DEPOT: return 6.0
		LiteKind.RADAR: return 3.0
		LiteKind.LAUNCHER: return 4.0
		LiteKind.POWER: return 6.0
		LiteKind.JAMMER: return 3.0
		LiteKind.MOBILE: return 2.0
		LiteKind.MRADAR: return 2.0
		LiteKind.REFINERY: return 5.0
		LiteKind.SUBSTATION: return 4.0
		_: return 3.0

## How far a site's weapons reach (with a radar's picture; without one, see
## LiteSense). Phase 4: all of them closer in than before (SAM 125, guns 58),
## so a country needs a network of them, not a few.
static func range(k: int) -> float:
	match k:
		LiteKind.GUN: return 38.0
		LiteKind.SAM: return 92.0
		LiteKind.CAPITAL: return 40.0
		LiteKind.MOBILE: return 24.0
		_: return 0.0

# --- Detection (see LiteSense) ------------------------------------------------

## How far each kind of site sees what flies, in map units, at best: radars
## far; a SAM by its own fire-control radar; guns and mobile units by eye,
## thermal sights and sound; every other site by its people (posts that
## report what flies over). Times sense_k for what is flying.
static func sense_range(k: int) -> float:
	match k:
		LiteKind.RADAR: return 260.0
		LiteKind.MRADAR: return 150.0
		LiteKind.SAM: return 100.0
		LiteKind.GUN: return 50.0
		LiteKind.MOBILE: return 36.0
		LiteKind.CAPITAL: return 46.0
		_: return 26.0

## Whether a kind of site sees by radar (else by eye: night and weather
## shorten it, see LiteEnv.optical).
static func by_radar(k: int) -> bool:
	return k == LiteKind.RADAR or k == LiteKind.MRADAR or k == LiteKind.SAM

## How well a sensor picks up a weapon, as a share of its range: a radar sees
## a drone (small, slow, low) less far and a cruise missile hugging the
## ground less far still, a ballistic missile high up very far; by eye, a
## drone's engine is heard, a cruise missile is fast and low.
static func sense_k(radar: bool, a: int) -> float:
	match a:
		LiteArm.DRONE: return 0.85 if radar else 1.0
		LiteArm.CRUISE: return 0.65 if radar else 0.8
		_: return 1.6 if radar else 0.0

## How long a lost track is kept on the map, in seconds, its place reckoned
## from its last heading, less sure all the while.
const TRACK_HOLD: float = 8.0
## How far a radar's picture reaches air defence: the share of its range
## within which air defence sites are linked to it.
const LINK_K: float = 0.7
## A substation lost: radars within this reach of it see this much as far,
## for half a day.
const GRID_REACH: float = 200.0
const GRID_CUT_K: float = 0.6
## Air defence without a radar's picture: how far it reaches (its own range
## times this) and how often it hits (times this), SAMs and guns.
const SAM_ALONE_RANGE: float = 0.65
const SAM_ALONE_PK: float = 0.65
const GUN_ALONE_PK: float = 0.85
## And with one: how much more often it hits.
const SAM_LINK_PK: float = 1.05
const GUN_LINK_PK: float = 1.2
const MOBILE_LINK_PK: float = 1.1

# --- Air defence ammunition ---------------------------------------------------

## An AA gun's magazine (bursts) and how long one burst takes to come back;
## each burst costs a little money (shells).
const GUN_MAG: int = 32
const GUN_REFILL: float = 0.8
const GUN_BURST_COST: float = 0.4
## A mobile unit's, the same.
const MOBILE_MAG: int = 8
const MOBILE_REFILL: float = 3.0
const MOBILE_BURST_COST: float = 0.3
const MOBILE_INTERVAL: float = 0.6
## A mobile unit on the move: its speed patrolling and chasing (map units a
## second), how fast it turns (radians a second), and how far off it goes
## after a drone it sees over its region.
const MOBILE_PATROL: float = 6.0
const MOBILE_CHASE: float = 11.0
const MOBILE_TURN: float = 2.2
const MOBILE_HUNT: float = 90.0

static func cost(a: int) -> int:
	match a:
		LiteArm.DRONE: return 12
		LiteArm.CRUISE: return 55
		_: return 130

## How fast each weapon flies, map units a second (2026-11-15: a quarter
## slower than the 26, 72 and 110 before, so a raid can be watched and met).
static func speed(a: int) -> float:
	match a:
		LiteArm.DRONE: return 19.5
		LiteArm.CRUISE: return 54.0
		_: return 82.5

## Nothing is launched closer than this to the other side's land, in map
## units: a band along the front where launchers would be in reach of the
## enemy's guns at once. (A side's own launch sites are where they are.)
const LAUNCH_STANDOFF: float = 38.0
## How close two sites may stand (a capital's bigger frame needs more room):
## enough that their frames on the map do not cover each other.
const SITE_GAP: float = 18.0
const SITE_GAP_CAPITAL: float = 23.0
## An EW jammer's reach, and the chance a drone flying into it is lost.
const JAMMER_RANGE: float = 64.0
const JAM_CHANCE: float = 0.5

## A ballistic missile's final dive, the last part of its flight (from this
## share of it on): until then nobody can tell where it will come down (see
## BALLISTIC_WARN). SAMs may engage it anywhere in range; AA guns never do.
const BALLISTIC_TERMINAL: float = 0.7
## A SAM site that has fired at a ballistic missile reloads this long, in
## seconds, before it fires again: a hard target that ties a battery up.
const SAM_BALLISTIC_RELOAD: float = 7.0
## Until then, every region of the country within this distance of it is
## under a missile alert: most of the country.
const BALLISTIC_WARN: float = 420.0

## Whether a SAM may engage this weapon now: always (a site that fires at a
## ballistic missile then reloads, SAM_BALLISTIC_RELOAD).
static func sam_can_engage(_w: LiteWeapon) -> bool:
	return true

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
		LiteArm.DRONE: return 0.85
		LiteArm.CRUISE: return 0.78
		_: return 0.45

## An AA gun's chance to hit with a burst (phase 4: far better than it was
## at 0.25 and 0.08, but only close in; see range).
static func gun_pk(a: int) -> float:
	match a:
		LiteArm.DRONE: return 0.4
		LiteArm.CRUISE: return 0.18
		_: return 0.0

## A mobile anti-drone unit's: good at drones, a long shot at a cruise
## missile, nothing against a ballistic one.
static func mobile_pk(a: int) -> float:
	match a:
		LiteArm.DRONE: return 0.55
		LiteArm.CRUISE: return 0.1
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
