class_name LiteMorale
extends RefCounted
## Phase 4: a country's morale, 0 to 100: its people's confidence, their
## resilience, their trust in the government, their will to go on. Separate
## from the capital's own state (its hit points, LiteBuilding.hp): a capital
## hit shakes morale, but a country can be worn down without its capital
## falling. Strikes that land, and losses, lower it; enemy weapons shot
## down, strikes of its own that tell, repairs, and quiet days raise it.
## Low morale makes the country work less (efficiency); at 0 it gives up
## (the war is lost, see LiteSim.step).

## Its states, from the top, with where each begins.
const STATES: Array[String] = ["Stable", "Concerned", "Frustrated", "Exhausted", "Near collapse"]
const FROM: Array[float] = [70.0, 50.0, 35.0, 18.0, 0.0]
const START: float = 72.0

## What changes it, and by how much.
enum { CAPITAL_HIT, FACTORY_LOST, SITE_LOST, WORKS_LOST, HIT, DOWNED_DRONE, DOWNED_CRUISE, DOWNED_BALLISTIC,
	STRUCK, STRUCK_FACTORY, STRUCK_CAPITAL, REPAIRED, OP_WON, OP_LOST, EVENT_GOOD, EVENT_BAD }
const DELTA: Array[float] = [-1.8, -3.5, -1.0, -2.5, -0.35, 0.1, 0.3, 0.8,
	0.6, 2.0, 0.5, 0.8, 8.0, -6.0, 4.0, -4.0]
## Quiet days: while no alert is up over the country, it recovers this much
## a second, up to RECOVER_TO.
const RECOVER: float = 0.04
const RECOVER_TO: float = 80.0

static func state(m: float) -> int:
	for i: int in FROM.size():
		if m >= FROM[i]:
			return i
	return FROM.size() - 1

static func state_name(m: float) -> String:
	return STATES[state(m)]

## How well the country works (income, production), from its morale: full
## from 70 up, down to 60% at none.
static func efficiency(m: float) -> float:
	return 0.6 + 0.4 * clampf(m / 70.0, 0.0, 1.0)

static func change(sim: LiteSim, side: int, what: int, times: float = 1.0) -> void:
	var me: LiteSide = sim.sides[side]
	if not me.morale_on:
		return
	me.morale = clampf(me.morale + DELTA[what] * times, 0.0, 100.0)
	me.morale_trend += DELTA[what] * times

## Recovery in quiet, once a step.
static func step(sim: LiteSim, dt: float) -> void:
	for me: LiteSide in sim.sides:
		me.morale_trend *= exp(-dt / 20.0)
		if me.morale_on and sim.alerted[me.index] == 0 and me.morale < RECOVER_TO:
			me.morale = minf(RECOVER_TO, me.morale + RECOVER * dt)
		# The economy: a country earning little loses heart slowly.
		if me.morale_on and me.income < 5.0:
			me.morale = maxf(0.0, me.morale - 0.03 * dt)
