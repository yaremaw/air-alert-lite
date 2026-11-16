class_name LiteStock
extends RefCounted
## Phase 4: a side's weapons are made, not bought on the spot. Its factories
## (and its capital's own works, a little) make them over time into its
## stockpiles, each line its own: drones, cruise missiles, ballistic
## missiles, and the interceptors its SAMs fire. A stockpile holds only so
## much (more with more factories on that line), so a big strike takes
## preparing for, and a side cannot sit on its money and then launch
## hundreds. Launching still costs its price in money (LiteSim.arm_cost),
## more while a side keeps launching hard (strain). Damaged factories make less, heavily
## damaged ones nothing; repairs cost money and take time.
##
## All of it simulation (LiteSim calls step); the views and the AI read it.

## The lines (a factory's `line`), and the stockpiles' order.
enum { DRONES, CRUISE, BALLISTIC, AMMO }
const LINES: int = 4
const LINE_NAMES: Array[String] = ["Drones", "Cruise missiles", "Ballistic missiles", "Interceptors"]
const LINE_SHORT: Array[String] = ["DRONES", "CRUISE", "BALLISTIC", "SAM AMMO"]

## What one factory at full strength makes a second, by line.
const MAKE: Array[float] = [0.25, 0.045, 0.014, 0.16]
## What the capital's works make a second without any factory.
const BASE: Array[float] = [0.15, 0.012, 0.004, 0.08]
## What a stockpile holds: so much, and so much more for each factory on it
## (enough for a real raid on a defended target, not for hundreds).
const HOLD: Array[float] = [30.0, 6.0, 3.0, 16.0]
const HOLD_EACH: Array[float] = [12.0, 3.0, 2.0, 10.0]
## Interceptors held besides at each SAM site (in its rack, see LiteSim.rack).
const HOLD_SAM: float = 4.0
## What a side starts a war with.
const START: Array[float] = [12.0, 2.0, 1.0, 18.0]
## The lines new factories are put on, in turn.
const DEFAULT_LINES: Array[int] = [DRONES, CRUISE, AMMO, DRONES, BALLISTIC, CRUISE]

## Strain: each launch adds to it (more for missiles), it eases off a little
## every second; launch costs go up with it.
const STRAIN: Array[float] = [1.0, 3.0, 6.0]
const STRAIN_EASE: float = 0.025
static func strain_mul(strain: float) -> float:
	return 1.0 + strain / 80.0

## A factory's output by its condition (LiteBuilding.condition): full,
## damaged, heavily damaged (none).
const CONDITION_K: Array[float] = [1.0, 0.6, 0.0, 0.0]
## While being repaired, a factory makes this share of what it would.
const REPAIRING_K: float = 0.3

## Repairs: what restoring a site costs (its build price, or a set price for
## sites never built, times the share of it that is lost, times this), and
## how long a full repair would take, in seconds.
const REPAIR_PRICE_K: float = 0.7
static func repair_time(k: int) -> float:
	match k:
		LiteKind.FACTORY: return 30.0
		LiteKind.SAM: return 14.0
		LiteKind.RADAR: return 14.0
		LiteKind.GUN: return 8.0
		LiteKind.MRADAR: return 8.0
		LiteKind.MOBILE: return 5.0
		_: return 16.0
static func base_price(k: int) -> int:
	var c: int = LiteRules.cost_kind(k)
	if c > 0:
		return c
	match k:
		LiteKind.REFINERY: return 200
		LiteKind.SUBSTATION: return 120
		_: return 100
## Rebuilding a destroyed factory where it stood: dearer and slower than a
## new one.
const REBUILD_PRICE_K: float = 1.3
const REBUILD_TIME_K: float = 2.0

## The money a site's repair costs now (0 if it is whole).
static func repair_cost(b: LiteBuilding) -> int:
	var lost: float = clampf(1.0 - b.hp / maxf(0.001, b.max_hp), 0.0, 1.0)
	if lost <= 0.0:
		return 0
	return maxi(5, ceili(base_price(b.kind) * lost * REPAIR_PRICE_K))

## Whether `b` can be repaired now.
static func can_repair(b: LiteBuilding) -> bool:
	return b.alive and b.ready and b.repairing <= 0.0 and b.hp < b.max_hp and b.kind != LiteKind.CAPITAL

## Starts repairing `b` if `side` has the money; true if it started.
static func repair(sim: LiteSim, b: LiteBuilding) -> bool:
	if not can_repair(b):
		return false
	var c: int = repair_cost(b)
	var me: LiteSide = sim.sides[b.side]
	if me.money < c:
		return false
	me.money -= c
	b.repairing = b.max_hp / repair_time(b.kind)
	return true

## Where a factory's line is: how many factories are on each line now.
static func lines(sim: LiteSim, side: int) -> PackedInt32Array:
	var n:= PackedInt32Array([0, 0, 0, 0])
	for b: LiteBuilding in sim.buildings:
		if b.alive and b.side == side and b.kind == LiteKind.FACTORY and b.ready:
			n[b.line] += 1
	return n

## The line a new factory of `side` goes on: the next in DEFAULT_LINES that
## its weapons allow.
static func next_line(sim: LiteSim, side: int) -> int:
	var count: int = 0
	for b: LiteBuilding in sim.buildings:
		if b.alive and b.side == side and b.kind == LiteKind.FACTORY:
			count += 1
	for k: int in DEFAULT_LINES.size():
		var l: int = DEFAULT_LINES[(count + k) % DEFAULT_LINES.size()]
		if l == AMMO or sim.has_arm(side, l):
			return l
	return DRONES

## The arm a line makes (or -1: interceptors).
static func arm_of(line: int) -> int:
	return line if line < AMMO else -1

## One step of every side's production, repairs and strain.
static func step(sim: LiteSim, dt: float) -> void:
	for side: LiteSide in sim.sides:
		var s: int = side.index
		var on_line:= PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
		var count:= PackedInt32Array([0, 0, 0, 0])
		var sams: int = 0
		for b: LiteBuilding in sim.buildings:
			if b.side != s or not b.alive or not b.ready:
				continue
			# Damaged sites mend by themselves (phase 4b), not while their region
			# is under air alert (the crews shelter); a capital mends by its
			# factories (LiteSim.economy).
			if b.hp < b.max_hp and b.kind != LiteKind.CAPITAL and b.kind != LiteKind.UNIT and not sim.alert[b.region]:
				b.repairing = b.max_hp * LiteRules.SELF_REPAIR
				b.hp = minf(b.max_hp, b.hp + b.repairing * dt)
				if b.hp >= b.max_hp:
					b.repairing = 0.0
					LiteMorale.change(sim, s, LiteMorale.REPAIRED, 0.3)
			elif b.hp >= b.max_hp:
				b.repairing = 0.0
			if b.kind == LiteKind.FACTORY:
				count[b.line] += 1
				var k: float = CONDITION_K[b.condition] * (REPAIRING_K if b.repairing > 0.0 else 1.0)
				k *= LiteRules.ALERT_WORK if sim.alert[b.region] else 1.0
				on_line[b.line] += k
			elif b.kind == LiteKind.SAM:
				sams += 1
		var eff: float = LiteMorale.efficiency(side.morale) * sim.income_scale[s]
		var cap_alive: bool = side.capital != null and side.capital.alive
		for l: int in LINES:
			var hold: float = HOLD[l] + HOLD_EACH[l] * count[l] + (HOLD_SAM * sams if l == AMMO else 0.0)
			side.hold[l] = hold
			var arm: int = arm_of(l)
			if arm >= 0 and not sim.has_arm(s, arm):
				side.making[l] = 0.0
				continue
			var rate: float = (MAKE[l] * on_line[l] + (BASE[l] if cap_alive else 0.0)) * eff
			if l == DRONES:
				rate *= 1.0 + sim.drone_rate[s]
				# Jets are built slower than propeller drones.
				if sim.jet_drones[s]:
					rate *= LiteRules.JET_MAKE
			side.making[l] = rate
			if side.stock[l] < hold:
				side.stock[l] = minf(hold, side.stock[l] + rate * dt)
		side.strain = maxf(0.0, side.strain - side.strain * STRAIN_EASE * dt - 0.02 * dt)

## Whether `side` has `n` of `arm` in its stockpile.
static func has(sim: LiteSim, side: int, arm: int, n: int) -> bool:
	return sim.sides[side].stock[arm] >= float(n) - 0.001

## How many of `arm` `side` could launch now (stock and money).
static func can_launch(sim: LiteSim, side: int, arm: int) -> int:
	var me: LiteSide = sim.sides[side]
	var each: float = sim.launch_price(side, arm)
	var by_money: int = int(me.money / maxf(0.01, each))
	return mini(int(me.stock[arm] + 0.001), by_money)
