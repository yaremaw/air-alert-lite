class_name LiteMission
extends RefCounted
## One operation of a campaign, fought on the map of one province (see
## LiteRegionMap): its goal, its deadline in game days, an optional goal, and
## the events that come up during it. It follows the war's events to see how
## the goal goes; LiteMain ends the operation when `result` is set.

## Destroy the targets set out in the province (and the province is taken);
## hold one of ours against an offensive (fewer than `need` enemy hits in it
## by the deadline); or destroy the enemy's command in its capital province.
## Phase 4: SURVIVE, a coordinated raid on our capital to live through (its
## damage under `cap_limit`, morale over `morale_floor`, until the deadline);
## PROTECT, our industry under attack (fewer than `need` factories lost by
## the deadline). A STRIKE may be timed (`deadline`): its targets gone in
## time, or it fails.
enum { STRIKE, HOLD, CAPITAL, SURVIVE, PROTECT }
## Optional goals (phase 4: up to two at once, see `bonus`).
enum { NONE, NO_FACTORY_LOST, SHOOT_DOWN, CAPITAL_SAFE, FAST, RADARS_DOWN, KEEP_MORALE }
## What else shapes an operation (phase 4): it starts at night; in a storm;
## short of money and weapons; with our long-range radar out; the targets'
## places unknown.
enum { C_NIGHT, C_STORM, C_LIMITED, C_BLIND, C_HIDDEN }
const CONDITION_NAMES: Array[String] = ["Night operation", "Storm front", "Short of everything", "Radar outage", "Poor intelligence"]
const CONDITION_TEXT: Array[String] = [
	"It starts at night: AA guns aimed by eye are weaker, radar decides.",
	"A storm front sits over the region: no drones for the first day, missiles only.",
	"Supplies are short: half the usual money, few weapons in stock.",
	"Our long-range radar is down for repairs: the air defence starts blind. Build a mobile radar.",
	"Intelligence is poor: the targets' places are unknown until our drones find them.",
]
## What a province is, which decides an attack's targets (and what taking it
## brings): its industry, its army, or the depots that supply the front.
enum { INDUSTRY, MILITARY, LOGISTICS, ENERGY, EW }
## How many kinds of region there are.
const CHARACTERS: int = 5
## Events that come up during an operation.
enum { STORM, INTEL, REINFORCE, SUPPLY, SABOTAGE, OUTAGE, CONVOY, RAID, DEFECTOR, VOLUNTEERS }

## Phase 4b: an attack with a plot of its own, against forces on the move
## (see LiteUnit): armoured columns making for our border (each must burn
## before it crosses), an ammunition train running for their front (its
## engine wrecked before it gets there), mobile launchers firing from cover
## (all destroyed before `salvo_limit` salvos land).
enum { PLOT_NONE, PLOT_COLUMN, PLOT_TRAIN, PLOT_HUNT, PLOT_ASSAULT, PLOT_EVAC, PLOT_PORT, PLOT_GRID, PLOT_DEPOT }
## The port (PLOT_PORT): tankers loading at its oil terminal (targets[0])
## sail for the open sea one by one (`extras`); `escape_limit` of them away
## and it fails. The grid (PLOT_GRID): two power stations, repair crews
## driving out from the town (`objective`) to mend a station knocked out;
## `repair_limit` repairs and it fails. The depot (PLOT_DEPOT): a jammer and
## the depot under its cover, supply convoys leaving it for the front every
## so often; `escape_limit` of them through and it fails.
var escape_limit: int = 0
var repair_limit: int = 0
var repairs: int = 0
## Repair crews on their way: station -> crew.
var _crews: Dictionary = {}
## Supply convoys on the road, and when the next leaves.
var movers: Array[LiteBuilding] = []
var next_convoy: float = 0.0
var _convoy_k: int = 0
## Where an assault aims (PLOT_ASSAULT: our region's city), how many of a
## convoy may be lost (PLOT_EVAC), how many got out, when the next raid on it is.
var objective: Vector2 = Vector2.ZERO
var may_lose: int = 0
var saved: int = 0
var raid_at: float = 0.0

var kind: int = STRIKE
var plot: int = PLOT_NONE
## A train's wagons: not needed for the goal, each burnt pays.
var extras: Array[LiteBuilding] = []
var crossed: int = 0
var salvo_limit: int = 0
## Radio lines due as the plot unfolds: [who, line]; LiteMain says them.
var lines: Array = []
var _beats: Dictionary = {}
var _salvos_told: int = 0
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
## Phase 4: all its optional goals, [kind, need, reward] each (the first is
## `optional` too), and which were met.
var bonus: Array = []
var bonus_done: Array[bool] = []
## Its conditions (C_*), its deadline for a timed strike (days, 0: none),
## what our capital may lose (SURVIVE), the morale under which it fails.
var conditions: Array[int] = []
var deadline: float = 0.0
var cap_limit: float = 0.0
var morale_floor: float = 0.0
## The capital operation: hits on the enemy's command to make it give up,
## and how many have landed.
var cap_target: int = 0
var cap_hits: int = 0
## What it is called in the briefing: the kind of operation.
var label: String = ""
## Intelligence and expected threats, a line each, for the briefing.
var intel: PackedStringArray = PackedStringArray()
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
var radars_down: int = 0
var cap_damage: float = 0.0
var _cap_start: float = -1.0
var _morale_low: float = 100.0
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
			if e.side == 1 and LiteKind.is_radar(e.kind):
				radars_down += 1
		LiteEv.SHOT_DOWN:
			if e.side == 0:
				downed += 1
		LiteEv.CAPITAL_HIT when e.side == 1:
			cap_hits += 1
		LiteEv.NUKE when e.side == 0 and kind == CAPITAL:
			cap_hits = maxi(cap_hits, cap_target)
		LiteEv.CAPITAL_HIT:
			# Phase 4: how many times our capital was hit (it has no health).
			if e.side == 0 and not LiteSim.classic_rules:
				cap_damage += 1.0
		LiteEv.HIT:
			if e.side == 1 and kind == HOLD and in_province(map, e.region):
				hits += 1

func destroyed() -> int:
	var n: int = 0
	for t: LiteBuilding in targets:
		if not t.alive:
			n += 1
	return n

## Whether it is fought on our own ground, holding on.
var defensive: bool:
	get: return kind == HOLD or kind == SURVIVE or kind == PROTECT

func update(sim: LiteSim) -> void:
	if result >= 0:
		return
	var cap: LiteBuilding = sim.sides[0].capital
	if _cap_start < 0.0 and cap != null:
		_cap_start = cap.hp
	if cap != null and LiteSim.classic_rules:
		cap_damage = maxf(cap_damage, _cap_start - cap.hp)
	_morale_low = minf(_morale_low, sim.sides[0].morale)
	if optional == SHOOT_DOWN and downed >= optional_need:
		optional_done = true
	var late: bool = sim.time >= length
	# A command falling decides it: theirs taken, ours lost.
	if sim.winner == 0 and kind != HOLD:
		_end(0, "Their will broke: the enemy asks for terms, and our troops move into %s." % region_name if kind == STRIKE
			else "The enemy's will is broken. %s asks for terms." % region_name)
		return
	if sim.winner == 1:
		_end(1, "The country's will broke: the government asks for terms.")
		return
	match kind:
		STRIKE, CAPITAL:
			if plot != PLOT_NONE:
				_plot(sim)
				return
			# An attack ends when its targets are gone (or it is called off,
			# see withdraw); a timed one fails when its time is up.
			if kind == CAPITAL and cap_target > 0 and not LiteSim.classic_rules:
				if cap_hits >= cap_target:
					_end(0, "Strike after strike on its command: %s asks for terms. The war is over." % region_name)
				return
			if destroyed() >= targets.size():
				if kind == CAPITAL:
					_end(0, "The enemy's command in %s is gone, and with it its hold on the war." % region_name)
				else:
					_end(0, "Its defences broken, our troops move into %s." % region_name)
			elif deadline > 0.0 and late:
				_end(1, "Time ran out: the enemy reinforced %s before we could break it." % region_name)
		SURVIVE:
			if cap_damage > cap_limit:
				_end(1, "The raid broke through: %s is burning, and the country with it." % region_name)
			elif late:
				_end(0, "The raid is spent. %s stands, and the country with it." % region_name)
		PROTECT, HOLD when plot != PLOT_NONE:
			_plot(sim)
		PROTECT:
			if factories_lost >= need:
				_end(1, "Our industry in %s is broken: the plants are gone." % region_name)
			elif late:
				_end(0, "The plants of %s kept working through it all." % region_name)
		HOLD:
			if hits >= need:
				_end(1, "Too many strikes got through: our troops fall back from %s." % region_name)
			elif late:
				_end(0, "The offensive broke against %s: it stays ours." % region_name)

## A line of the plot, said once.
func _beat(key: String, who: String, line: String) -> void:
	if _beats.has(key):
		return
	_beats[key] = true
	lines.append([who, line])

## The salvos the launchers got off.
func salvos() -> int:
	var n: int = 0
	for t: LiteBuilding in targets:
		n += t.salvos
	return n

## How far along its route the furthest unit is, 0 to 1.
func lead() -> float:
	var u: float = 0.0
	for t: LiteBuilding in targets:
		if t.alive and t.route_len > 0.0:
			u = maxf(u, t.dist / t.route_len)
	return u

func _plot(sim: LiteSim) -> void:
	var map: LiteMap = sim.map
	match plot:
		PLOT_COLUMN:
			for t: LiteBuilding in targets:
				if not t.alive:
					continue
				if t.wait <= 0.0 and t.dist > 1.0:
					_beat("moving", "bilyk", "They're rolling. Armour on the roads, slow and heavy. Stop them before the border!")
				if map.side_at(t.pos) == 0:
					t.crossed = true
					t.alive = false
					t.dead_at = sim.time
					crossed += 1
			var u: float = lead()
			if u > 0.5:
				_beat("half", "moroz", "Lead column is halfway to the border. Still time.")
			if u > 0.8:
				_beat("near", "bilyk", "They're almost on us! Everything you have on the lead column, now!")
			for t: LiteBuilding in targets:
				if t.alive and t.wait > 0.0 and t.dist > 1.0:
					_beat("halt", "moroz", "A column has stopped to refuel. Sitting ducks.")
			if crossed > 0:
				_end(1, "A battalion broke through at the border: our line before %s gives way." % region_name)
			elif destroyed() >= targets.size():
				_end(0, "Every column burned on the road. Their offensive is broken, and our troops push into %s." % region_name)
		PLOT_TRAIN:
			var loco: LiteBuilding = targets[0] if not targets.is_empty() else null
			if loco == null:
				return
			var burnt: int = 0
			for w: LiteBuilding in extras:
				if not w.alive:
					burnt += 1
			if not loco.alive:
				_end(0, "The engine lies wrecked on the line%s. The guns at %s wait for shells that will not come." % [(" and %d wagons burnt out" % burnt) if burnt > 0 else "", region_name])
				return
			if burnt > 0:
				_beat("wagon", "varga", "Wagon hit, it's cooking off! Now the engine, or it drags the rest on!")
			if loco.dist > 26.0:
				_beat("moving", "moroz", "The train is moving. The line is marked on your map.")
			var u: float = loco.dist / maxf(1.0, loco.route_len)
			if loco.wait > 0.0 and u > 0.15:
				_beat("siding", "moroz", "It stopped at a siding. Hit it now!")
			if u > 0.5:
				_beat("half", "moroz", "Halfway to the front station.")
			if u > 0.8:
				_beat("near", "varga", "The front station is in sight. Last chance!")
			if loco.arrived:
				_end(1, "The train reached the front and unloaded: their guns at %s have shells for a month." % region_name)
		PLOT_ASSAULT:
			var lost_city: bool = false
			for t: LiteBuilding in targets:
				if t.alive and t.wait <= 0.0 and t.dist > 1.0:
					_beat("moving", "bilyk", "Their armour is moving on %s. Everything we have on the roads!" % region_name)
				if t.alive and (t.arrived or t.pos.distance_to(objective) < 7.0):
					lost_city = true
			var u: float = lead()
			if u > 0.5:
				_beat("half", "moroz", "Lead column halfway to %s." % region_name)
			if u > 0.8:
				_beat("near", "bilyk", "They're at the edge of town! Stop them NOW!")
			if lost_city:
				_end(1, "Their armour rolled into %s. The town is lost." % region_name)
			elif destroyed() >= targets.size():
				_end(0, "Their assault burned out on the roads. %s holds." % region_name)
			elif sim.time >= length:
				_end(0, "Their offensive stalled short of %s." % region_name)
		PLOT_PORT:
			_port_plot(sim)
		PLOT_GRID:
			_grid_plot(sim)
		PLOT_DEPOT:
			_depot_plot(sim)
		PLOT_EVAC:
			var lost: int = 0
			var out: int = 0
			for t: LiteBuilding in targets:
				if not t.alive:
					lost += 1
				elif t.arrived:
					out += 1
			saved = out
			if lost > 0:
				_beat("hit", "bilyk", "A truck's hit! Keep their drones off the road!")
			if lost > may_lose:
				_end(1, "Too many trucks burned on the road out of %s." % region_name)
			elif lost + out >= targets.size():
				_end(0, "The convoy is out of %s: %d of %d trucks made it." % [region_name, out, targets.size()])
			# The enemy hunts it: a raid on the lead truck every half minute or so.
			elif sim.time >= raid_at:
				raid_at = sim.time + randf_range(30.0, 42.0)
				for t: LiteBuilding in targets:
					if t.alive and not t.arrived and t.wait <= 0.0:
						var at: Vector2 = t.pos + Vector2.from_angle(t.heading) * t.pace * 6.0
						var arm: int = LiteArm.CRUISE if sim.has_arm(1, LiteArm.CRUISE) and randf() < 0.3 else LiteArm.DRONE
						sim.fire_from(1, arm, sim.origin_near(1, at), at, 2 if arm == LiteArm.DRONE else 1)
						_beat("raid", "moroz", "Drones inbound on the convoy. Guns, cover the road!")
						break
		PLOT_HUNT:
			var n: int = salvos()
			if n > _salvos_told:
				_salvos_told = n
				if n < salvo_limit:
					lines.append(["moroz", ["Launch detected! It's marked: you have half a minute before it moves.", "Another salvo. I have the launcher, hit it before it drives off!", "They fired again. Marked on your map."][n % 3]])
			if destroyed() >= targets.size():
				_end(0, "The last launcher burns in its hide. The sky over our positions at %s is quiet." % region_name)
			elif n >= salvo_limit:
				_end(1, "Salvo after salvo landed on our positions: the troops facing %s pull back." % region_name)
			elif n >= salvo_limit - 2:
				_beat("warn", "bilyk", "Their rockets keep landing on us. We can't take many more!")

## The port: its terminal and docks destroyed wins. Ships sunk on their
## way out are command points; each one that gets away pays for another SAM
## battery at the port.
func _port_plot(sim: LiteSim) -> void:
	for t: LiteBuilding in extras:
		if t.alive and t.arrived and not t.crossed:
			# Out at sea, off the map: its cargo is sold.
			t.crossed = true
			t.alive = false
			t.dead_at = sim.time
			crossed += 1
			if not targets.is_empty():
				var q: Variant = sim.find_spot(1, targets[0].pos, 14.0, 44.0)
				if q != null:
					sim.add(1, LiteKind.SAM, q, false)
	if destroyed() >= targets.size():
		_end(0, "The port of %s burns: its terminal and docks are gone, and the export with them." % region_name)

## Cargo ships sunk (PLOT_PORT): a command point each.
func ships_sunk() -> int:
	var n: int = 0
	if plot == PLOT_PORT:
		for t: LiteBuilding in extras:
			if not t.alive and not t.crossed:
				n += 1
	return n

## The grid: both stations dark at once wins; the crews mend what we break.
func _grid_plot(sim: LiteSim) -> void:
	if destroyed() >= targets.size():
		_end(0, "Both power stations of %s are down: their air defence sits in the dark." % region_name)
		return
	for st: LiteBuilding in targets:
		var crew: LiteBuilding = _crews.get(st, null)
		if st.alive:
			continue
		if crew == null:
			# The crew sets out from the town a little after the station goes dark.
			if sim.time - st.dead_at < LiteRules.DAY * 0.08:
				continue
			var rng:= RandomNumberGenerator.new()
			rng.seed = int(sim.time * 10.0) + repairs * 7
			var route: PackedVector2Array = LiteUnit.road(sim.map, objective, st.pos, rng, 5.0)
			crew = LiteCampaign._unit(sim, LiteUnit.CREW, route, LiteUnit.length(route) / (LiteRules.DAY * 0.4), 0.0, 0.0)
			_crews[st] = crew
			movers.append(crew)
		elif not crew.alive:
			# Their crew burnt on the road: the next one sets out later.
			_crews.erase(st)
			st.dead_at = sim.time
		elif crew.arrived:
			# Mended: the station back up, the crew done.
			st.alive = true
			st.hp = st.max_hp * 0.6
			st.flash = 1.0
			crew.alive = false
			crew.dead_at = sim.time
			_crews.erase(st)
			repairs += 1
	if repairs >= repair_limit:
		_end(1, "Their engineers kept the lights on in %s: every station we hit was back by morning." % region_name)

## The depot: supply convoys leave it for the front while it stands.
func _depot_plot(sim: LiteSim) -> void:
	var depot: LiteBuilding = targets[targets.size() - 1] if not targets.is_empty() else null
	for t: LiteBuilding in movers:
		if t.alive and not t.crossed and sim.map.side_at(t.pos) == 0:
			t.crossed = true
			t.alive = false
			t.dead_at = sim.time
			crossed += 1
	if destroyed() >= targets.size():
		_end(0, "The jammer is silent and the depot at %s burns: their front goes hungry." % region_name)
		return
	if crossed >= escape_limit:
		_end(1, "Convoy after convoy reached their front: the troops facing us are supplied for weeks.")
		return
	if depot != null and depot.alive and sim.time >= next_convoy:
		next_convoy = sim.time + LiteRules.DAY * 0.6
		var cross: Vector2 = LiteCampaign._border_towards(sim, depot.pos)
		var dir: Vector2 = (cross - depot.pos).normalized()
		var rng:= RandomNumberGenerator.new()
		rng.seed = _convoy_k * 131 + 7
		var route: PackedVector2Array = LiteUnit.road(sim.map, depot.pos, cross + dir * 5.0, rng, 7.0)
		var pace: float = LiteUnit.length(route) / (LiteRules.DAY * 0.8)
		# One convoy, one symbol: its trucks together, an AA gun riding with
		# every other one.
		var u: LiteBuilding = LiteCampaign._unit(sim, LiteUnit.SUPPLY, route, pace, 0.0, 0.0)
		u.max_hp = 3.0
		u.hp = 3.0
		movers.append(u)
		if _convoy_k % 2 == 1:
			LiteCampaign._escort_for(sim, u, 1.0)
		_convoy_k += 1

## The attack called off: it counts as failed.
func withdraw() -> void:
	if result < 0:
		_end(1, "We withdrew from %s." % region_name)

## Whether it has a deadline: holding on does (until the offensive runs
## out), and a timed strike; an attack otherwise runs until its targets are
## gone.
var timed: bool:
	get: return defensive or deadline > 0.0

func _end(r: int, why: String) -> void:
	result = r
	outcome = why
	bonus_done.clear()
	for g: Array in bonus:
		bonus_done.append(_bonus_met(g, r))
	optional_done = not bonus_done.is_empty() and bonus_done[0]

## Whether an optional goal was met, at the end.
func _bonus_met(g: Array, r: int) -> bool:
	match int(g[0]):
		NO_FACTORY_LOST: return factories_lost == 0
		SHOOT_DOWN: return downed >= int(g[1])
		CAPITAL_SAFE: return cap_damage <= float(g[1])
		FAST: return r == 0 and _ended_in <= float(g[1]) * LiteRules.DAY
		RADARS_DOWN: return radars_down >= int(g[1])
		KEEP_MORALE: return _morale_low >= float(g[1])
	return false

var _ended_in: float = 0.0
## Called by the operation's loop each step: how long it has run.
func tick_time(t: float) -> void:
	if result < 0:
		_ended_in = t

## The money its met optional goals bring.
func bonus_money() -> int:
	var n: int = 0
	for i: int in bonus_done.size():
		if bonus_done[i]:
			n += int(bonus[i][2])
	return n

func goal_text(sim: LiteSim) -> String:
	match plot:
		PLOT_ASSAULT: return "Stop the armour before it reaches %s" % region_name
		PLOT_EVAC: return "Get the convoy out: lose no more than %d trucks" % may_lose
		PLOT_COLUMN: return "Stop the armour before it crosses our border"
		PLOT_TRAIN: return "Wreck the ammunition train before it reaches the front"
		PLOT_HUNT: return "Hunt down the launchers before %d salvos land" % salvo_limit
		PLOT_PORT: return "Destroy the port of %s" % region_name
		PLOT_GRID: return "Black out both power stations at once"
		PLOT_DEPOT: return "Destroy the jammer and the depot before %d convoys get through" % escape_limit
	match kind:
		STRIKE:
			return ("Destroy the targets in %s within %s" % [region_name, LiteHud.duration(length)]) if deadline > 0.0 else "Destroy the targets in %s" % region_name
		HOLD:
			return "Hold %s: under %d enemy hits there" % [region_name, need]
		SURVIVE:
			return "Survive the raid: under %d hits on the capital" % roundi(cap_limit)
		PROTECT:
			return "Protect the plants of %s: lose fewer than %d" % [region_name, need]
		_:
			return "Hit the enemy's command in %s %d times" % [region_name, cap_target] if not LiteSim.classic_rules else "Destroy the enemy command in %s" % region_name

func goal_progress(sim: LiteSim) -> String:
	match plot:
		PLOT_ASSAULT: return "%d/%d" % [destroyed(), targets.size()]
		PLOT_EVAC: return "%d out · %d lost" % [saved, destroyed()]
		PLOT_COLUMN: return "%d/%d" % [destroyed(), targets.size()]
		PLOT_TRAIN:
			var loco: LiteBuilding = targets[0] if not targets.is_empty() else null
			return "%d%% of the way" % roundi(100.0 * loco.dist / maxf(1.0, loco.route_len)) if loco != null else ""
		PLOT_HUNT: return "%d/%d · salvos %d/%d" % [destroyed(), targets.size(), salvos(), salvo_limit]
		PLOT_PORT: return "%d/%d · ships sunk %d" % [destroyed(), targets.size(), ships_sunk()]
		PLOT_GRID: return "%d/%d down · repaired %d/%d" % [destroyed(), targets.size(), repairs, repair_limit]
		PLOT_DEPOT: return "%d/%d · convoys through %d/%d" % [destroyed(), targets.size(), crossed, escape_limit]
	if kind == CAPITAL and not LiteSim.classic_rules:
		return "%d/%d hits" % [cap_hits, cap_target]
	match kind:
		HOLD: return "%d/%d" % [hits, need]
		SURVIVE: return "%d/%d" % [roundi(cap_damage), roundi(cap_limit)]
		PROTECT: return "%d/%d" % [factories_lost, need]
	return "%d/%d" % [destroyed(), targets.size()]

## One line per target, for the card and the briefing: what, and whether it
## is gone.
func target_lines() -> Array:
	var out: Array = []
	for t: LiteBuilding in targets:
		var what: String = LiteUnit.name(t.unit) if t.kind == LiteKind.UNIT else LiteGlyphs.name(t.kind)
		if plot == PLOT_PORT and t.kind == LiteKind.REFINERY:
			what = "Oil terminal"
		elif plot == PLOT_PORT and t.kind == LiteKind.DEPOT:
			what = "Cargo docks"
		out.append([what, not t.alive])
	return out

## The optional goals; `short` for the card.
func optional_text(short: bool = false) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for g: Array in bonus:
		var what: String = bonus_name(g, short)
		if int(g[2]) > 0:
			what += (" · +$%d" if short else " · +$%d next operation") % int(g[2])
		parts.append(what)
	return (" | " if short else "; ").join(parts)

## One optional goal in words.
static func bonus_name(g: Array, short: bool = false) -> String:
	match int(g[0]):
		NO_FACTORY_LOST: return "Lose no factory"
		SHOOT_DOWN: return ("Shoot down %d" if short else "Shoot down %d enemy weapons") % int(g[1])
		CAPITAL_SAFE: return ("≤ %d hits on the capital" if short else "Keep hits on our capital to %d") % int(g[1])
		FAST: return ("Done in %d days" if short else "Finish within %d days") % int(g[1])
		RADARS_DOWN:
			var n: int = int(g[1])
			return ("Destroy %d radar%s" if short else "Destroy %d enemy radar%s") % [n, "" if n == 1 else "s"]
		KEEP_MORALE: return ("Morale ≥ %d" if short else "Keep national morale at %d or more") % int(g[1])
	return ""

func optional_progress() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for g: Array in bonus:
		match int(g[0]):
			NO_FACTORY_LOST: parts.append("%d lost" % factories_lost)
			SHOOT_DOWN: parts.append("%d/%d" % [mini(downed, int(g[1])), int(g[1])])
			CAPITAL_SAFE: parts.append("%d hits" % roundi(cap_damage))
			FAST: parts.append("day %d" % (int(_ended_in / LiteRules.DAY) + 1))
			RADARS_DOWN: parts.append("%d/%d" % [mini(radars_down, int(g[1])), int(g[1])])
			KEEP_MORALE: parts.append("low %d" % roundi(_morale_low))
	return " | ".join(parts)

## Sets the optional goals (the first is `optional` too).
func set_bonus(list: Array) -> void:
	bonus = list
	if not list.is_empty():
		optional = int(list[0][0])
		optional_need = int(list[0][1])
		reward = int(list[0][2])

func optional_open() -> bool:
	for g: Array in bonus:
		if int(g[0]) == NO_FACTORY_LOST and factories_lost > 0:
			return false
	return true

## The goal in one line.
func summary() -> String:
	match plot:
		PLOT_ASSAULT: return "Enemy armour, with its own air defence, drives on %s. Destroy it before it gets there." % region_name
		PLOT_EVAC: return "Our convoy runs out of %s under enemy raids. Lose no more than %d trucks." % [region_name, may_lose]
		PLOT_COLUMN: return "Destroy every armoured column before it crosses our border."
		PLOT_TRAIN: return "Wreck the ammunition train's engine before it reaches the front."
		PLOT_HUNT: return "Destroy the mobile launchers before %d salvos land." % salvo_limit
		PLOT_PORT: return "Destroy the oil terminal and docks of %s. Each cargo ship sunk earns a command point." % region_name
		PLOT_GRID: return "Two power stations; their crews mend what we break. Have both down at once."
		PLOT_DEPOT: return "A jammer covers the depot that supplies their front. Destroy both before %d convoys get through." % escape_limit
	match kind:
		HOLD: return "Keep enemy hits under %d for %s." % [need, LiteHud.duration(length)]
		CAPITAL: return "Hit the enemy's command %d times." % cap_target
		SURVIVE: return "Survive %s of raids on the capital." % LiteHud.duration(length)
		PROTECT: return "Keep the plants working for %s." % LiteHud.duration(length)
	if deadline > 0.0:
		return "Destroy the targets within %s." % LiteHud.duration(length)
	return "Destroy the targets."

## The sites an attack on a province of this kind must destroy.
static func target_kinds(c: int) -> Array[int]:
	match c:
		INDUSTRY: return [LiteKind.FACTORY, LiteKind.FACTORY, LiteKind.FACTORY]
		LOGISTICS: return [LiteKind.DEPOT, LiteKind.DEPOT]
		ENERGY: return [LiteKind.POWER, LiteKind.POWER]
		EW: return [LiteKind.JAMMER, LiteKind.DEPOT]
	return [LiteKind.RADAR, LiteKind.LAUNCHER]

## What taking a province of this kind brings, in a few words.
static func character_gain(c: int) -> String:
	match c:
		INDUSTRY: return "+10% income"
		LOGISTICS: return "+$200 each operation"
		ENERGY: return "Enemy SAMs start each operation dark"
		EW: return "A jammer guards our command"
	return "Enemy: −10% money"

static func character_short(c: int) -> String:
	match c:
		INDUSTRY: return "Industry"
		LOGISTICS: return "Supply"
		ENERGY: return "Power"
		EW: return "EW"
	return "Military"

static func character_name(c: int) -> String:
	match c:
		INDUSTRY: return "Industrial province"
		LOGISTICS: return "Supply hub"
		ENERGY: return "Power grid"
		EW: return "Electronic warfare hub"
		_: return "Military district"

## What taking a province of this kind brings, in a line.
static func character_reward(c: int) -> String:
	match c:
		INDUSTRY: return "Its industry works for us: +10% income in later operations."
		LOGISTICS: return "Its depots supply us: +$200 at the start of later operations."
		ENERGY: return "Their grid is cut: enemy SAMs start every later operation silent for half a day."
		EW: return "We take their jamming gear: a jammer of ours guards our command in later operations."
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
		DEFECTOR: return "A defector brings their air defence map: all its sites located."
		VOLUNTEERS: return "Volunteers set up AA guns by our factories."
		_: return "Supplies: +$250."
