class_name LiteAi
extends RefCounted
## A side's commander, used for the enemy (and for our side in the test
## and screenshot runs). It knows only what its side has seen. Part of its
## income is saved for raids; the rest builds factories and puts air
## defence where the other side's weapons have been landing.
##
## A raid goes at up to four known sites, each sent about as many weapons
## as its health needs after the losses the defence there is likely to
## cause, and flies round the air defence it knows of. Scouts go to regions
## not yet flown over.
##
## With waves on (Normal and Hard) it also weighs up a massive strike: what
## the sites it knows of are worth against what it would take to overwhelm
## the defence round them. When one is worth it and affordable within a few
## minutes it starts massing (the other side's intelligence notices), keeps
## its small raids small, and launches once the money is there: drones from
## all sides arriving together to drain the air defence, missiles behind
## them. Adaptive (Hard) also sends cruise missiles ahead of the wave at the
## air defence that has shot down the most, and drones as a feint at the
## other end of the country.
##
## Defence comes first: SAMs and guns round the capital, more as the war
## goes on, a gun by every factory, and air defence where weapons came down.
## When the capital is short of it, money is taken from the war fund.

## C# float.MaxValue.
const _FLOAT_MAX: float = 3.4028235e38


## Was the tuple `(LiteBuilding B, float Score, float Cov)` in PlanWave.
class Known:
	var b: LiteBuilding
	var score: float
	var cov: float

	func _init(p_b: LiteBuilding, p_score: float, p_cov: float) -> void:
		b = p_b
		score = p_score
		cov = p_cov


var side: int = 0
## Share of income kept for raids.
var war_share: float = 0.5
## Plans its raids: weapons sized to the target, routes round known air
## defence. Off on Easy, where raids go straight and in rough numbers.
var smart: bool = true
## Time between raids, as a share of the usual.
var tempo: float = 1.0
## Saves up for massive waves (Normal, Hard).
var waves: bool = false
## Goes for the air defence that hurts it most, and feints (Hard).
var adaptive: bool = false
## Saving up for a massive strike on `_plan`.
var massing: bool = false
var _wave_cost: float = 0.0
var _mass_since: float = 0.0
var _plan_at: float = 90.0
var _plan: Array[LiteBuilding] = []
var _rng: RandomNumberGenerator
var _think: float = 0.0
var _next_raid: float = 0.0
var _last_factory: float = -99.0
var _raids: int = 0
var _targets: Array[LiteBuilding] = []
var _scouted: Dictionary = {}


func _init(p_side: int, seed: int, first_raid: float) -> void:
	side = p_side
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed
	_next_raid = first_raid


## C# `R(a, b)`.
func _r(a: float, b: float) -> float:
	return a + _rng.randf() * (b - a)


## C# `Random.Next(n)`.
func _next(n: int) -> int:
	return _rng.randi_range(0, n - 1) if n > 0 else 0


## C# `x ?? fallback` for raids.
static func _or(x: LiteRaid, fallback: LiteRaid) -> LiteRaid:
	return x if x != null else fallback


func tick(s: LiteSim, dt: float) -> void:
	var me: LiteSide = s.sides[side]
	me.war_fund = minf(me.war_fund + me.income * war_share * dt, me.money)
	_think -= dt
	if _think > 0: return
	_think = _r(0.7, 1.3)
	s.sams_on_drones[side] = me.money > 60
	defend(s, me)
	grow(s, me)
	attack(s, me)


## Was `Free(me)`; `free` is taken by Object.
func free_money(me: LiteSide) -> float:
	return me.money - me.war_fund


## Pays for a building out of spare money, or, when `urgent`, out of the
## war fund as well.
func afford(s: LiteSim, me: LiteSide, kind: int, urgent: bool) -> bool:
	var cost: int = s.cost(side, kind)
	if free_money(me) >= cost: return true
	if not urgent or me.money < cost: return false
	me.war_fund = maxf(0, me.money - cost)
	return true


func put(s: LiteSim, kind: int, near: Vector2, r_min: float, r_max: float) -> bool:
	var p: Variant = s.find_spot(side, near, r_min, r_max)
	return p != null and s.build(side, kind, p) != null


func defend(s: LiteSim, me: LiteSide) -> void:
	# me.HitLog.RemoveAll(h => s.Time - h.T > 25)
	var k: int = 0
	for h: LiteSide.Hit in me.hit_log:
		if not (s.time - h.t > 25):
			me.hit_log[k] = h
			k += 1
	me.hit_log.resize(k)
	# 1. The capital: SAMs and guns, more as the war goes on.
	var cap_sam: int = 0
	var cap_gun: int = 0
	for b: LiteBuilding in s.buildings:
		if not b.alive or b.side != side or b.pos.distance_to(me.capital.pos) > 70: continue
		if b.kind == LiteKind.SAM: cap_sam += 1
		elif b.kind == LiteKind.GUN: cap_gun += 1
	var want_sam: int = mini(4, 1 + int(s.time / 240))
	var want_gun: int = mini(4, 1 + int(s.time / 300))
	if cap_sam < want_sam:
		if afford(s, me, LiteKind.SAM, true): put(s, LiteKind.SAM, me.capital.pos, 16, 45)
		return
	if cap_gun < want_gun:
		if afford(s, me, LiteKind.GUN, true): put(s, LiteKind.GUN, me.capital.pos, 18, 50)
		return
	# 2. Where the other side's weapons came down near something of ours.
	for i: int in me.hit_log.size():
		var h: LiteSide.Hit = me.hit_log[i]
		var valuable: bool = false
		for b: LiteBuilding in s.buildings:
			if b.alive and b.side == side and b.pos.distance_to(h.p) < 35:
				valuable = true
				break
		var cov: float = s.coverage(side, h.p)
		if not valuable or cov >= 3: continue
		var kind: int = LiteKind.SAM if cov < 1 and free_money(me) >= s.cost(side, LiteKind.SAM) + 20 and _rng.randf() < 0.5 else LiteKind.GUN
		if not afford(s, me, kind, false): return
		if put(s, kind, h.p, 8, 30): me.hit_log.remove_at(i)
		return
	# 3. A gun by every factory; then spare money for the least covered.
	var weak: LiteBuilding = null
	var low: float = 2
	for b: LiteBuilding in s.buildings:
		if not b.alive or b.side != side or b.kind != LiteKind.FACTORY: continue
		var c: float = s.coverage(side, b.pos)
		if c < 1 and afford(s, me, LiteKind.GUN, false):
			put(s, LiteKind.GUN, b.pos, 12, 30)
			return
		if c < low:
			low = c
			weak = b
	if weak == null or free_money(me) < 250 or s.time < 50: return
	put(s, LiteKind.SAM if low < 2 else LiteKind.GUN, weak.pos, 12, 30)


func grow(s: LiteSim, me: LiteSide) -> void:
	var factories: int = 0
	for b: LiteBuilding in s.buildings:
		if b.alive and b.side == side and b.kind == LiteKind.FACTORY: factories += 1
	var cap: int = 2 + int(s.time / 45)
	if factories >= cap or free_money(me) < s.cost(side, LiteKind.FACTORY) + 20 or s.time - _last_factory < 9: return
	# A region with room: the further from the other side's capital the
	# safer, but a region with more room counts for something too.
	var enemy_cap: Vector2 = s.sides[1 - side].capital.pos
	var best: int = -1
	var best_score: float = -_FLOAT_MAX
	for r: LiteRegion in s.map.regions:
		if r.side != side or r.city or s.free_slots(r.id) <= 0: continue
		var score: float = r.label.distance_to(enemy_cap) + 40 * s.free_slots(r.id) + _r(0, 160)
		if score > best_score:
			best_score = score
			best = r.id
	if best >= 0 and s.build_factory(side, best) != null: _last_factory = s.time


func attack(s: LiteSim, me: LiteSide) -> void:
	if waves:
		if not massing and s.time >= _plan_at: plan_wave(s, me)
		elif massing and (minf(me.war_fund, me.money) >= _wave_cost or s.time - _mass_since > 240):
			wave(s, me)
			massing = false
			_plan_at = s.time + _r(120, 200) * tempo
			_next_raid = maxf(_next_raid, s.time + 25)
			return
	if s.time < _next_raid: return
	# While massing, small raids stay small.
	var budget: float = minf(me.war_fund, me.money) * (0.2 if massing else (0.6 if waves else 1.0))
	if budget < 50:
		_next_raid = s.time + 4
		return
	var before: float = me.money
	_raids += 1
	_targets.clear()
	var known: int = 0
	for b: LiteBuilding in s.buildings:
		if b.alive and b.side != side and b.seen[side]:
			_targets.append(b)
			if b.kind != LiteKind.CAPITAL: known += 1

	if known == 0 or _rng.randf() < 0.1: scout(s, mini(4, int(budget / LiteRules.cost(LiteArm.DRONE))))
	else:
		var raid: LiteRaid = null
		var delay: float = 0
		var k: int = 0
		while k < 4 and _targets.size() > 0 and budget >= LiteRules.cost(LiteArm.DRONE):
			var t: LiteBuilding = pick(s, me)
			_targets.erase(t)
			var cov: float = s.known_coverage(side, t.pos)
			# The share likely to be shot down: what the defence there looks
			# like, and how the last raid fared.
			var loss: float = clampf(0.1 + 0.14 * cov + 0.4 * me.last_raid_loss, 0.1, 0.85)
			var hp: float = minf(t.hp, 30) if t.kind == LiteKind.CAPITAL else t.hp
			var route: Array[Vector2] = []
			if smart: route = route_to(s, me, t.pos)
			if not smart: loss = 0.5
			var bal: int = 0
			var cru: int = 0
			if (t.kind == LiteKind.CAPITAL or t.kind == LiteKind.SAM) and s.time > 150 and budget >= 400 and _rng.randf() < 0.5:
				bal = mini(3, int(budget * 0.3 / LiteRules.cost(LiteArm.BALLISTIC)))
			if cov >= 2 and s.time > 60 and budget >= 200:
				cru = mini(8, ceili(hp * 0.5 / LiteRules.damage(LiteArm.CRUISE) / (1 - loss * 0.7)))
			var left: float = hp - bal * LiteRules.damage(LiteArm.BALLISTIC) * 0.5 - cru * LiteRules.damage(LiteArm.CRUISE) * (1 - loss * 0.7)
			var dr: int = maxi(1 if left > 0 else 0, ceili(left / (1 - loss)) + (1 if left > 0 else 0))
			cru = mini(cru, int((budget - bal * LiteRules.cost(LiteArm.BALLISTIC)) / LiteRules.cost(LiteArm.CRUISE)))
			dr = mini(dr, int((budget - bal * LiteRules.cost(LiteArm.BALLISTIC) - cru * LiteRules.cost(LiteArm.CRUISE)) / LiteRules.cost(LiteArm.DRONE)))
			dr = mini(dr, 30)
			# Drones go first; the missiles are timed to arrive with them.
			var dist: float = t.pos.distance_to(me.capital.pos)
			var t_drone: float = dist / LiteRules.speed(LiteArm.DRONE) * 1.15
			if dr > 0: raid = _or(s.strike(side, LiteArm.DRONE, t.pos, dr, raid, delay, route), raid)
			if cru > 0: raid = _or(s.strike(side, LiteArm.CRUISE, t.pos, cru, raid, delay + maxf(0, t_drone - dist / LiteRules.speed(LiteArm.CRUISE) * 1.3), route), raid)
			if bal > 0: raid = _or(s.strike(side, LiteArm.BALLISTIC, t.pos, bal, raid, delay + maxf(0, t_drone - 2.0)), raid)
			budget = minf(me.war_fund - (before - me.money), me.money) * (0.2 if massing else (0.6 if waves else 1.0))
			delay += 1.5
			k += 1
	me.war_fund = maxf(0, me.war_fund - (before - me.money))
	# A rich side raids more often.
	_next_raid = s.time + _r(20, 36) * tempo * (0.6 if me.war_fund > 600 else 1.0)


## Seconds from launch to the target, roughly: drones and ballistic
## missiles go up near the front, cruise missiles from deep inside.
func travel(s: LiteSim, me: LiteSide, target: Vector2, arm: int) -> float:
	var from: Vector2 = me.capital.pos
	if arm != LiteArm.CRUISE:
		var bd: float = _FLOAT_MAX
		for r: LiteRegion in s.map.regions:
			if r.side == side and not r.city and r.label.distance_to(target) < bd:
				bd = r.label.distance_to(target)
				from = r.label
	return from.distance_to(target) / LiteRules.speed(arm) * (1.2 if arm == LiteArm.DRONE else 1.1)


## What a site is worth to a massive strike.
func worth(s: LiteSim, b: LiteBuilding, cov: float) -> float:
	var w: float
	match b.kind:
		LiteKind.FACTORY: w = 3.0
		LiteKind.SAM: w = 2.5 + (0.3 * b.kills if adaptive else 0.0)
		LiteKind.GUN: w = 1.0
		_: w = 1.0 + 4.0 * (1 - b.hp / b.max_hp) + (2.0 if cov < 2 else 0.0)
	return w / (1 + 0.4 * cov)


## Drones (and dollars) to break through to `t`: what its health needs
## after the expected losses.
func drones_for(s: LiteSim, me: LiteSide, t: LiteBuilding, cov: float) -> int:
	var loss: float = clampf(0.15 + 0.14 * cov + 0.3 * me.last_raid_loss, 0.15, 0.85)
	var hp: float = minf(t.hp, 40) if t.kind == LiteKind.CAPITAL else t.hp
	return mini(40, ceili(hp / (1 - loss) * 1.3) + 2)


## Is a massive strike worth it, and affordable within about four
## minutes? Then start saving for it on the best few targets.
func plan_wave(s: LiteSim, me: LiteSide) -> void:
	_plan_at = s.time + 10
	var known: Array[Known] = []
	for b: LiteBuilding in s.buildings:
		if b.alive and b.side != side and b.seen[side]:
			var cov: float = s.known_coverage(side, b.pos)
			known.append(Known.new(b, worth(s, b, cov) * _r(0.85, 1.15), cov))
	known.sort_custom(func(a: Known, b: Known) -> bool: return a.score > b.score)
	if known.size() > 4: known.resize(4)
	var reach: float = me.war_fund + me.income * war_share * 240
	while known.size() > 0:
		var worth_sum: float = 0
		var cost: float = 0
		var sams: Dictionary = {}
		for kn: Known in known:
			worth_sum += kn.score
			cost += drones_for(s, me, kn.b, kn.cov) * LiteRules.cost(LiteArm.DRONE)
			if kn.cov >= 2: cost += 2 * LiteRules.cost(LiteArm.CRUISE)
			for o: LiteBuilding in s.buildings:
				if o.alive and o.side != side and o.seen[side] and o.kind == LiteKind.SAM and o.pos.distance_to(kn.b.pos) <= LiteRules.range(LiteKind.SAM): sams[o] = true
		# Enough extra drones to empty the SAMs on the way.
		cost += sams.size() * LiteRules.SAM_RACK * LiteRules.cost(LiteArm.DRONE)
		if worth_sum < 4.5: return
		if cost <= reach:
			_plan.clear()
			for kn: Known in known: _plan.append(kn.b)
			_wave_cost = cost
			massing = true
			_mass_since = s.time
			s.events.append(LiteEvent.new(LiteEv.WARNING, side, 0, Vector2.ZERO, 0, 0, cost))
			return
		known.remove_at(known.size() - 1)


## The massive wave: up to five targets, the drones timed to arrive
## together, the missiles ten seconds behind them.
func wave(s: LiteSim, me: LiteSide) -> void:
	var budget: float = minf(me.war_fund, me.money)
	var before: float = me.money
	if budget < 100: return
	_targets.clear()
	for b: LiteBuilding in s.buildings:
		if b.alive and b.side != side and b.seen[side]: _targets.append(b)
	var busiest: Array[LiteBuilding] = []
	if adaptive:
		for b: LiteBuilding in _targets:
			if b.kind == LiteKind.SAM and b.kills >= 2: busiest.append(b)
		busiest.sort_custom(func(a: LiteBuilding, b: LiteBuilding) -> bool: return a.kills > b.kills)
		if busiest.size() > 2: busiest.resize(2)
	# The planned targets that are still there, topped up from the rest.
	var main: Array[LiteBuilding] = []
	for b: LiteBuilding in _plan:
		if b.alive: main.append(b)
	for b: LiteBuilding in main: _targets.erase(b)
	while main.size() < 3 and _targets.size() > 0:
		var t: LiteBuilding = pick(s, me)
		_targets.erase(t)
		main.append(t)
	if main.size() == 0: return
	var arrive: float = 0
	for t: LiteBuilding in main: arrive = maxf(arrive, travel(s, me, t.pos, LiteArm.DRONE))
	arrive += 4
	var raid: LiteRaid = null
	# float Spend() => before - me.Money;
	# Ahead of the wave, cruise missiles at the air defence that shot down most.
	for sam: LiteBuilding in busiest:
		raid = _or(s.strike(side, LiteArm.CRUISE, sam.pos, 3, raid, maxf(0, arrive - 8 - travel(s, me, sam.pos, LiteArm.CRUISE)), route_to(s, me, sam.pos)), raid)
	# A feint: drones at the far end of the country, there before the wave.
	if adaptive:
		var c: Vector2 = main[0].pos
		var far: LiteRegion = null
		for r: LiteRegion in s.map.regions:
			if r.side != side and not r.city and r.spots.size() > 0 and r.label.distance_to(c) > 250 and (far == null or _rng.randf() < 0.3): far = r
		if far != null:
			var n: int = 5 + _next(4)
			raid = _or(s.strike(side, LiteArm.DRONE, far.label, n, raid, 0, route_to(s, me, far.label)), raid)
	var share: float = (budget - (before - me.money)) * 0.75 / main.size()
	for t: LiteBuilding in main:
		var cov: float = s.known_coverage(side, t.pos)
		var loss: float = clampf(0.15 + 0.14 * cov + 0.3 * me.last_raid_loss, 0.15, 0.85)
		var hp: float = minf(t.hp, 40) if t.kind == LiteKind.CAPITAL else t.hp
		var dr: int = mini(ceili(hp / (1 - loss) * 1.3) + 2, int(share / LiteRules.cost(LiteArm.DRONE)))
		dr = mini(dr, 40)
		var route: Array[Vector2] = route_to(s, me, t.pos)
		if dr > 0: raid = _or(s.strike(side, LiteArm.DRONE, t.pos, dr, raid, maxf(0, arrive - travel(s, me, t.pos, LiteArm.DRONE)), route), raid)
		if cov >= 2 or t.kind == LiteKind.CAPITAL:
			var cru: int = mini(6, ceili(hp * 0.5 / LiteRules.damage(LiteArm.CRUISE) / (1 - loss * 0.6)))
			cru = mini(cru, int((budget - (before - me.money)) * 0.5 / LiteRules.cost(LiteArm.CRUISE)))
			if cru > 0: raid = _or(s.strike(side, LiteArm.CRUISE, t.pos, cru, raid, maxf(0, arrive + 10 - travel(s, me, t.pos, LiteArm.CRUISE)), route), raid)
	# What is left: ballistic missiles at the capital or the main target, last.
	var left: float = budget - (before - me.money)
	var heavy: LiteBuilding = main[0]
	for t: LiteBuilding in main:
		if t.kind == LiteKind.CAPITAL:
			heavy = t
			break
	var bal: int = mini(4, int(left * 0.8 / LiteRules.cost(LiteArm.BALLISTIC)))
	if bal > 0 and s.time > 150: s.strike(side, LiteArm.BALLISTIC, heavy.pos, bal, raid, maxf(0, arrive + 6 - travel(s, me, heavy.pos, LiteArm.BALLISTIC)))
	me.war_fund = maxf(0, me.war_fund - (before - me.money))


## A few drones, each to a region of the other side not yet flown over.
func scout(s: LiteSim, n: int) -> void:
	var regions: Array[LiteRegion] = []
	for r: LiteRegion in s.map.regions:
		if r.side != side and not r.city and r.spots.size() > 0 and not _scouted.has(r.id): regions.append(r)
	if regions.size() == 0:
		_scouted.clear()
		return
	var i: int = 0
	while i < n and regions.size() > 0:
		var r: LiteRegion = regions[_next(regions.size())]
		regions.erase(r)
		_scouted[r.id] = true
		s.strike(side, LiteArm.DRONE, r.label, 1, null, i * 0.8, route_to(s, s.sides[side], r.label))
		i += 1


## The way in that passes least of the air defence this side knows of:
## straight, or bent through one point to either side. Sometimes the
## second best, so the way in is not always the same.
## Was `Route`; returns an empty array for "straight" (was null).
func route_to(s: LiteSim, me: LiteSide, target: Vector2) -> Array[Vector2]:
	var from: Vector2 = me.capital.pos
	var bd: float = _FLOAT_MAX
	for r: LiteRegion in s.map.regions:
		if r.side == side and not r.city and r.label.distance_to(target) < bd:
			bd = r.label.distance_to(target)
			from = r.label
	var d: Vector2 = target - from
	var len: float = d.length()
	if len < 1: return []
	var n: Vector2 = Vector2(-d.y, d.x) / len
	var best: float = _FLOAT_MAX
	var second: float = _FLOAT_MAX
	var best_route: Array[Vector2] = []
	var second_route: Array[Vector2] = []
	for off: float in [0.0, -90.0, 90.0, -170.0, 170.0, -250.0, 250.0]:
		var mid: Vector2 = from + d * 0.5 + n * off
		if off != 0 and s.map.side_at(mid) < 0: continue
		var score: float = exposure(s, from, mid) + exposure(s, mid, target) + (from.distance_to(mid) + mid.distance_to(target)) * 0.004
		var route: Array[Vector2] = []
		if off != 0: route.append(mid)
		if score < best:
			second = best
			second_route = best_route
			best = score
			best_route = route
		elif score < second:
			second = score
			second_route = route
	return second_route if second < best * 1.2 + 0.5 and _rng.randf() < 0.3 else best_route


func exposure(s: LiteSim, a: Vector2, b: Vector2) -> float:
	var sum: float = 0
	var len: float = a.distance_to(b)
	var t: float = 0
	while t < len:
		sum += s.known_coverage(side, a.lerp(b, t / len))
		t += 15
	return sum


## Factories first, since they repair the capital; air defence when the
## last raid was shot to pieces; the capital when no factory is known,
## and more and more as the war goes on.
func pick(s: LiteSim, me: LiteSide) -> LiteBuilding:
	var total: float = 0
	var factories: bool = false
	for b: LiteBuilding in _targets:
		if b.kind == LiteKind.FACTORY:
			factories = true
			break
	var weights := PackedFloat32Array()
	weights.resize(_targets.size())
	for i: int in _targets.size():
		var b: LiteBuilding = _targets[i]
		match b.kind:
			LiteKind.FACTORY: weights[i] = 3.0
			LiteKind.SAM: weights[i] = 2.0 + 3.0 * me.last_raid_loss + (0.4 * b.kills if adaptive else 0.0)
			LiteKind.GUN: weights[i] = 1.0 + me.last_raid_loss
			_: weights[i] = (0.5 + s.time / 300.0) if factories else (3.0 + s.time / 200.0)
		total += weights[i]
	var roll: float = _r(0, total)
	for i: int in _targets.size():
		roll -= weights[i]
		if roll <= 0: return _targets[i]
	return _targets[-1]
