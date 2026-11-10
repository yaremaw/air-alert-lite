class_name LiteMission
extends RefCounted
## One mission of a campaign: a fight over one province, with a goal, a
## deadline in game days, now and then an optional goal with a reward, and
## the events that shape it. It follows the war's events to see how the goal
## goes; LiteMain ends the mission when `result` is set.

## Take an enemy province (destroy `need` of its sites), hold one of ours
## (until the deadline, with fewer than `need` enemy hits landing there), or
## land `need` damage on the enemy capital (its repairs do not undo it).
enum { STRIKE, HOLD, CAPITAL }
## Optional goals.
enum { NONE, NO_FACTORY_LOST, SHOOT_DOWN }

var kind: int = STRIKE
var number: int = 0
var title: String = ""
## The province fought over.
var region: int = -1
var region_name: String = ""
var days: float = 6.0
var need: int = 0
var optional: int = NONE
var optional_need: int = 0
## Money the optional goal brings at the start of the next mission.
var reward: int = 0
var briefing: String = ""
## What else shapes this mission (events, a side rallying), one line each.
var notes: PackedStringArray = PackedStringArray()

## What has happened so far.
var destroyed: int = 0
## Enemy hits landed in the province (HOLD).
var hits: int = 0
## Damage landed on the enemy capital (CAPITAL).
var damage: float = 0.0
var downed: int = 0
var factories_lost: int = 0
## -1 while under way, then 0 done or 1 failed.
var result: int = -1
var optional_done: bool = false
## How it ended, in a sentence.
var outcome: String = ""

var length: float:
	get: return days * LiteRules.DAY

func time_left(sim: LiteSim) -> float:
	return maxf(0.0, length - sim.time)

func on_event(e: LiteEvent, map: LiteMap) -> void:
	if result >= 0:
		return
	match e.type:
		LiteEv.DESTROYED:
			if e.side == 1 and kind == STRIKE and map.province(e.region) == region:
				destroyed += 1
			if e.side == 0 and e.kind == LiteKind.FACTORY:
				factories_lost += 1
		LiteEv.SHOT_DOWN:
			if e.side == 0:
				downed += 1
		LiteEv.HIT:
			if e.side == 1 and kind == HOLD and map.province(e.region) == region:
				hits += 1
		LiteEv.CAPITAL_HIT:
			if e.side == 1:
				damage += LiteRules.damage(e.arm)

func update(sim: LiteSim) -> void:
	if result >= 0:
		return
	if optional == SHOOT_DOWN and downed >= optional_need:
		optional_done = true
	var late: bool = sim.time >= length
	match kind:
		STRIKE:
			if destroyed >= need:
				_end(0, "Its defences broken, our troops move into %s." % region_name)
			elif late:
				_end(1, "Time ran out with %s still in enemy hands." % region_name)
		HOLD:
			if hits >= need:
				_end(1, "Too many strikes got through: our troops fall back from %s." % region_name)
			elif late:
				_end(0, "The offensive broke against %s: it stays ours." % region_name)
		CAPITAL:
			if damage >= need:
				_end(0, "%s is in ruins and the enemy's war effort is faltering." % sim.map.capital_name[1])
			elif late:
				_end(1, "%s held out: too few strikes got through its defences." % sim.map.capital_name[1])

func _end(r: int, why: String) -> void:
	result = r
	outcome = why
	if optional == NO_FACTORY_LOST:
		optional_done = factories_lost == 0

## The mission card's lines: what is asked, how far it has got, and whether it
## is met (true), lost (false) or still open (null).
func goal_text(sim: LiteSim) -> String:
	match kind:
		STRIKE:
			return "Destroy %d enemy sites in %s" % [need, region_name]
		HOLD:
			return "Hold %s: under %d enemy hits there" % [region_name, need]
		_:
			return "Land %d damage on %s" % [need, sim.map.capital_name[1]]

func goal_progress(sim: LiteSim) -> String:
	match kind:
		STRIKE:
			return "%d/%d" % [mini(destroyed, need), need]
		HOLD:
			return "%d/%d" % [hits, need]
		_:
			return "%d/%d" % [mini(roundi(damage), need), need]

## The optional goal; `short` for the mission card.
func optional_text(short: bool = false) -> String:
	var what: String
	match optional:
		NO_FACTORY_LOST: what = "Lose no factory"
		SHOOT_DOWN: what = ("Shoot down %d" if short else "Shoot down %d enemy weapons") % optional_need
		_: return ""
	if reward <= 0:
		return what
	return what + ((" · +$%d" if short else " · +$%d next mission") % reward)

func optional_progress() -> String:
	match optional:
		NO_FACTORY_LOST: return "%d lost" % factories_lost
		SHOOT_DOWN: return "%d/%d" % [mini(downed, optional_need), optional_need]
	return ""

## Whether the optional goal can still be met.
func optional_open() -> bool:
	return optional != NO_FACTORY_LOST or factories_lost == 0
