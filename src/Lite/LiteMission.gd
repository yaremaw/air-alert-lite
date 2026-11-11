class_name LiteMission
extends RefCounted
## One operation of a campaign, fought on the map of one province (see
## LiteRegionMap): its goal, its deadline in game days, an optional goal, and
## the events that come up during it. It follows the war's events to see how
## the goal goes; LiteMain ends the operation when `result` is set.

## Destroy the targets set out in the province (and the province is taken);
## hold one of ours against an offensive (fewer than `need` enemy hits in it
## by the deadline); or destroy the enemy's command in its capital province.
enum { STRIKE, HOLD, CAPITAL }
## Optional goals.
enum { NONE, NO_FACTORY_LOST, SHOOT_DOWN }
## What a province is, which decides an attack's targets (and what taking it
## brings): its industry, its army, or the depots that supply the front.
enum { INDUSTRY, MILITARY, LOGISTICS }
## Events that come up during an operation.
enum { STORM, INTEL, REINFORCE, SUPPLY, SABOTAGE, OUTAGE, CONVOY, RAID }

var kind: int = STRIKE
var character: int = MILITARY
var number: int = 0
var title: String = ""
## The region fought over on the war map: its main province (which names
## it), all its provinces, and its name.
var province: int = -1
var provinces: Array[int] = []
var region_name: String = ""
var days: float = 5.0
var need: int = 0
var optional: int = NONE
var optional_need: int = 0
## Money the optional goal brings at the start of the next operation.
var reward: int = 0
var briefing: String = ""
## What else shapes this operation, one line each.
var notes: PackedStringArray = PackedStringArray()

## The sites to destroy (STRIKE, CAPITAL).
var targets: Array[LiteBuilding] = []
## Events still to come: [game time, which].
var events: Array = []

## What has happened so far.
var hits: int = 0
var downed: int = 0
var factories_lost: int = 0
## -1 while under way, then 0 done or 1 failed.
var result: int = -1
var optional_done: bool = false
var outcome: String = ""
## Until when drones stay on the ground (a storm), in game time.
var storm_until: float = -1.0
## Until when the enemy's SAMs are silent (an outage).
var outage_until: float = -1.0
## A convoy at a depot (a bonus target), until when it stays, and what it is worth.
var convoy: LiteBuilding = null
var convoy_until: float = -1.0
const CONVOY_REWARD: int = 300

var length: float:
	get: return days * LiteRules.DAY

func time_left(sim: LiteSim) -> float:
	return maxf(0.0, length - sim.time)

## The province's districts on the operation's map.
func in_province(map: LiteMap, region: int) -> bool:
	return map.focus.has(region)

func on_event(e: LiteEvent, map: LiteMap) -> void:
	if result >= 0:
		return
	match e.type:
		LiteEv.DESTROYED:
			if e.side == 0 and e.kind == LiteKind.FACTORY:
				factories_lost += 1
		LiteEv.SHOT_DOWN:
			if e.side == 0:
				downed += 1
		LiteEv.HIT:
			if e.side == 1 and kind == HOLD and in_province(map, e.region):
				hits += 1

func destroyed() -> int:
	var n: int = 0
	for t: LiteBuilding in targets:
		if not t.alive:
			n += 1
	return n

func update(sim: LiteSim) -> void:
	if result >= 0:
		return
	if optional == SHOOT_DOWN and downed >= optional_need:
		optional_done = true
	var late: bool = sim.time >= length
	# A command falling decides it: theirs taken, ours lost.
	if sim.winner == 0 and kind != HOLD:
		_end(0, "Their command destroyed, our troops move into %s." % region_name if kind == STRIKE
			else "The enemy's command in %s is gone, and with it its hold on the war." % region_name)
		return
	if sim.winner == 1:
		_end(1, "Our command fell: our troops fall back from %s." % region_name)
		return
	match kind:
		STRIKE, CAPITAL:
			# No deadline: an attack ends when its targets are gone (or it is
			# called off, see withdraw).
			if destroyed() >= targets.size():
				if kind == CAPITAL:
					_end(0, "The enemy's command in %s is gone, and with it its hold on the war." % region_name)
				else:
					_end(0, "Its defences broken, our troops move into %s." % region_name)
		HOLD:
			if hits >= need:
				_end(1, "Too many strikes got through: our troops fall back from %s." % region_name)
			elif late:
				_end(0, "The offensive broke against %s: it stays ours." % region_name)

## The attack called off: it counts as failed.
func withdraw() -> void:
	if result < 0:
		_end(1, "We withdrew from %s." % region_name)

## Whether it has a deadline: only holding a province does (until the
## offensive runs out); an attack runs until its targets are gone.
var timed: bool:
	get: return kind == HOLD

func _end(r: int, why: String) -> void:
	result = r
	outcome = why
	if optional == NO_FACTORY_LOST:
		optional_done = factories_lost == 0

func goal_text(sim: LiteSim) -> String:
	match kind:
		STRIKE:
			return "Destroy the targets in %s" % region_name
		HOLD:
			return "Hold %s: under %d enemy hits there" % [region_name, need]
		_:
			return "Destroy the enemy command in %s" % region_name

func goal_progress(sim: LiteSim) -> String:
	if kind == HOLD:
		return "%d/%d" % [hits, need]
	return "%d/%d" % [destroyed(), targets.size()]

## One line per target, for the card and the briefing: what, and whether it
## is gone.
func target_lines() -> Array:
	var out: Array = []
	for t: LiteBuilding in targets:
		out.append([LiteGlyphs.name(t.kind), not t.alive])
	return out

## The optional goal; `short` for the card.
func optional_text(short: bool = false) -> String:
	var what: String
	match optional:
		NO_FACTORY_LOST: what = "Lose no factory"
		SHOOT_DOWN: what = ("Shoot down %d" if short else "Shoot down %d enemy weapons") % optional_need
		_: return ""
	if reward <= 0:
		return what
	return what + ((" · +$%d" if short else " · +$%d next operation") % reward)

func optional_progress() -> String:
	match optional:
		NO_FACTORY_LOST: return "%d lost" % factories_lost
		SHOOT_DOWN: return "%d/%d" % [mini(downed, optional_need), optional_need]
	return ""

func optional_open() -> bool:
	return optional != NO_FACTORY_LOST or factories_lost == 0

## The goal in one line.
func summary() -> String:
	match kind:
		HOLD: return "Keep enemy hits under %d for %s." % [need, LiteHud.duration(length)]
		CAPITAL: return "Destroy the enemy command."
	return "Destroy the targets."

## The sites an attack on a province of this kind must destroy.
static func target_kinds(c: int) -> Array[int]:
	match c:
		INDUSTRY: return [LiteKind.DEPOT, LiteKind.FACTORY, LiteKind.FACTORY]
		LOGISTICS: return [LiteKind.DEPOT, LiteKind.DEPOT]
	return [LiteKind.RADAR, LiteKind.LAUNCHER]

## What taking a province of this kind brings, in a few words.
static func character_gain(c: int) -> String:
	match c:
		INDUSTRY: return "+10% income"
		LOGISTICS: return "+$200 each operation"
	return "Enemy: −10% money"

static func character_short(c: int) -> String:
	match c:
		INDUSTRY: return "Industry"
		LOGISTICS: return "Supply"
	return "Military"

static func character_name(c: int) -> String:
	match c:
		INDUSTRY: return "Industrial province"
		LOGISTICS: return "Supply hub"
		_: return "Military district"

## What taking a province of this kind brings, in a line.
static func character_reward(c: int) -> String:
	match c:
		INDUSTRY: return "Its industry works for us: +10% income in later operations."
		LOGISTICS: return "Its depots supply us: +$200 at the start of later operations."
		_: return "The enemy loses an air base: it has 10% less to spend in later operations."

## Events: what each is called and does, in a line for the feed.
static func event_text(e: int) -> String:
	match e:
		STORM: return "Storm: drones on both sides grounded for half a day."
		INTEL: return "Intelligence: enemy sites in one district located."
		REINFORCE: return "Enemy reinforcements: a new SAM by one of the targets."
		SABOTAGE: return "Sabotage: partisans blew up an enemy air defence site."
		OUTAGE: return "Outage: enemy SAMs silent for half a day. Strike now."
		CONVOY: return "Convoy spotted: destroy it within half a day for +$%d." % CONVOY_REWARD
		RAID: return "Warning: the enemy is massing a big raid."
		_: return "Supplies: +$250."
