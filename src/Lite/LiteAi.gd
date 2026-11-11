class_name LiteAi
extends RefCounted

const _FLOAT_MAX: float = 3.4028235e+38

class Known:
	var b: LiteBuilding
	var score: float
	var cov: float

	func _init(p_b: LiteBuilding, p_score: float, p_cov: float) -> void:
		b = p_b
		score = p_score
		cov = p_cov

var side: int = 0

var war_share: float = 0.5

var smart: bool = true

var tempo: float = 1.0

var waves: bool = false

var adaptive: bool = false

var massing: bool = false
## The provinces it is told to go for (a campaign offensive's, on an
## operation's map its districts), and how much more the sites there are
## worth to it than elsewhere.
var focus_set: PackedInt32Array = PackedInt32Array()
## How many more air defence sites it may build (-1: as many as it likes).
var ad_limit: int = -1
var focus_weight: float = 1.0
var _focus_at: float = 0.0
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

## No raids or waves before game time `t` (a campaign offensive gathering).
func hold_until(t: float) -> void:
	_next_raid = maxf(_next_raid, t)
	_plan_at = maxf(_plan_at, t)
	_focus_at = maxf(_focus_at, t)

func _r(a: float, b: float) -> float:
	return a + _rng.randf() * (b - a)

func _next(n: int) -> int:
	return _rng.randi_range(0, n - 1) if n > 0 else 0

static func _or(x: LiteRaid, fallback: LiteRaid) -> LiteRaid:
	return x if x != null else fallback

func tick(s: LiteSim, dt: float) -> void:
	var me: LiteSide = s.sides[side]
	var share: float = war_share * (0.5 if _exposed and not classic and smart else 1.0)
	me.war_fund = minf(me.war_fund + me.income * share * dt, me.money)
	_think -= dt
	if _think > 0: return
	_think = _r(0.7, 1.3)
	s.sams_on_drones[side] = me.money > 60
	if classic or not smart:
		defend(s, me)
		grow(s, me)
		if turtle and free_money(me) > 260:
			var mine: Array[LiteBuilding] = []
			for b: LiteBuilding in s.buildings:
				if b.alive and b.side == side and (b.kind == LiteKind.FACTORY or b.kind == LiteKind.CAPITAL):
					mine.append(b)
			if mine.size() > 0:
				var at: LiteBuilding = mine[_next(mine.size())]
				put(s, LiteKind.SAM if _rng.randf() < 0.35 else LiteKind.GUN, at.pos, 14, 60)
		attack(s, me)
		return
	grow(s, me)
	_defend_smart(s, me)
	_attack_smart(s, me)

func free_money(me: LiteSide) -> float:
	return me.money - me.war_fund

func afford(s: LiteSim, me: LiteSide, kind: int, urgent: bool) -> bool:
	var cost: int = s.cost(side, kind)
	if free_money(me) >= cost: return true
	if not urgent or me.money < cost: return false
	me.war_fund = maxf(0, me.money - cost)
	return true

func put(s: LiteSim, kind: int, near: Vector2, r_min: float, r_max: float) -> bool:
	var ad: bool = kind == LiteKind.GUN or kind == LiteKind.SAM
	if ad and ad_limit == 0:
		return false
	var p: Variant = s.find_spot(side, near, r_min, r_max)
	var ok: bool = p != null and s.build(side, kind, p) != null
	if ok and ad and ad_limit > 0:
		ad_limit -= 1
	return ok

func defend(s: LiteSim, me: LiteSide) -> void:

	var k: int = 0
	for h: LiteSide.Hit in me.hit_log:
		if not (s.time - h.t > 25):
			me.hit_log[k] = h
			k += 1
	me.hit_log.resize(k)

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
	var cap: int = 2 + int(s.time / (32.0 if adaptive and not classic else 45.0))
	if factories >= cap or free_money(me) < s.cost(side, LiteKind.FACTORY) + 20 or s.time - _last_factory < 9: return

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
	_press_focus(s, me)
	if waves:
		if not massing and s.time >= _plan_at: plan_wave(s, me)
		elif massing and (minf(me.war_fund, me.money) >= _wave_cost or s.time - _mass_since > 240):
			wave(s, me)
			massing = false
			_plan_at = s.time + _r(120, 200) * tempo
			_next_raid = maxf(_next_raid, s.time + 25)
			return
	if s.time < _next_raid: return

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

	# Nothing found yet: mostly scouting, but now and then the capital, which
	# is always in plain sight.
	if (known == 0 and _rng.randf() < 0.55) or _rng.randf() < 0.1: scout(s, mini(4, int(budget / LiteRules.cost(LiteArm.DRONE))))
	else:
		var raid: LiteRaid = null
		var delay: float = 0
		var k: int = 0
		while k < 4 and _targets.size() > 0 and budget >= LiteRules.cost(LiteArm.DRONE):
			var t: LiteBuilding = pick(s, me)
			_targets.erase(t)
			var cov: float = s.known_coverage(side, t.pos)

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

			var dist: float = t.pos.distance_to(me.capital.pos)
			var t_drone: float = dist / LiteRules.speed(LiteArm.DRONE) * 1.15
			if dr > 0: raid = _or(s.strike(side, LiteArm.DRONE, t.pos, dr, raid, delay, route), raid)
			if cru > 0: raid = _or(s.strike(side, LiteArm.CRUISE, t.pos, cru, raid, delay + maxf(0, t_drone - dist / LiteRules.speed(LiteArm.CRUISE) * 1.3), route), raid)
			if bal > 0: raid = _or(s.strike(side, LiteArm.BALLISTIC, t.pos, bal, raid, delay + maxf(0, t_drone - 2.0)), raid)
			budget = minf(me.war_fund - (before - me.money), me.money) * (0.2 if massing else (0.6 if waves else 1.0))
			delay += 1.5
			k += 1
	me.war_fund = maxf(0, me.war_fund - (before - me.money))

	_next_raid = s.time + _r(20, 36) * tempo * (0.6 if me.war_fund > 600 else 1.0)

func travel(s: LiteSim, me: LiteSide, target: Vector2, arm: int) -> float:
	var from: Vector2 = me.capital.pos
	if arm != LiteArm.CRUISE:
		var bd: float = _FLOAT_MAX
		for r: LiteRegion in s.map.regions:
			if r.side == side and not r.city and r.label.distance_to(target) < bd:
				bd = r.label.distance_to(target)
				from = r.label
	return from.distance_to(target) / LiteRules.mean_speed(arm) * (1.2 if arm == LiteArm.DRONE else 1.1)

func worth(s: LiteSim, b: LiteBuilding, cov: float) -> float:
	var w: float
	match b.kind:
		LiteKind.FACTORY: w = 3.0
		LiteKind.SAM: w = 2.5 + (0.3 * b.kills if adaptive else 0.0)
		LiteKind.GUN: w = 1.0
		_: w = 1.0 + 4.0 * (1 - b.hp / b.max_hp) + (2.0 if cov < 2 else 0.0)
	return w / (1 + 0.4 * cov)

func drones_for(s: LiteSim, me: LiteSide, t: LiteBuilding, cov: float) -> int:
	var loss: float = clampf(0.15 + 0.14 * cov + 0.3 * me.last_raid_loss, 0.15, 0.85)
	var hp: float = minf(t.hp, 40) if t.kind == LiteKind.CAPITAL else t.hp
	return mini(40, ceili(hp / (1 - loss) * 1.3) + 2)

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

	for sam: LiteBuilding in busiest:
		raid = _or(s.strike(side, LiteArm.CRUISE, sam.pos, 3, raid, maxf(0, arrive - 8 - travel(s, me, sam.pos, LiteArm.CRUISE)), route_to(s, me, sam.pos)), raid)

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

	var left: float = budget - (before - me.money)
	var heavy: LiteBuilding = main[0]
	for t: LiteBuilding in main:
		if t.kind == LiteKind.CAPITAL:
			heavy = t
			break
	var bal: int = mini(4, int(left * 0.8 / LiteRules.cost(LiteArm.BALLISTIC)))
	if bal > 0 and s.time > 150: s.strike(side, LiteArm.BALLISTIC, heavy.pos, bal, raid, maxf(0, arrive + 6 - travel(s, me, heavy.pos, LiteArm.BALLISTIC)))
	me.war_fund = maxf(0, me.war_fund - (before - me.money))

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

func pick(s: LiteSim, me: LiteSide) -> LiteBuilding:
	var total: float = 0
	var factories: bool = false
	for b: LiteBuilding in _targets:
		if b.kind == LiteKind.FACTORY:
			factories = true
			break
	var weights:= PackedFloat32Array()
	weights.resize(_targets.size())
	for i: int in _targets.size():
		var b: LiteBuilding = _targets[i]
		match b.kind:
			LiteKind.FACTORY: weights[i] = 3.0
			LiteKind.SAM: weights[i] = 2.0 + 3.0 * me.last_raid_loss + (0.4 * b.kills if adaptive else 0.0)
			LiteKind.GUN: weights[i] = 1.0 + me.last_raid_loss
			_: weights[i] = (0.5 + s.time / 300.0) if factories else (3.0 + s.time / 200.0)
		weights[i] *= _focus(s, b)
		total += weights[i]
	var roll: float = _r(0, total)
	for i: int in _targets.size():
		roll -= weights[i]
		if roll <= 0: return _targets[i]
	return _targets[-1]

# ================================================================ the planner
# Normal and Hard: the enemy plans like a commander. It keeps a map of the
# kills our known air defence would score on a drone or a cruise missile in
# each cell of a coarse grid, finds the cheapest way in from its own land to
# every cell (so routes go round the defence where there is a gap), prices
# every target it knows as the cheapest mix of weapons that destroys it after
# the losses on that way in, and spends its war fund on the targets worth
# most for their price: fewer, larger raids, timed to arrive together.

const CELL: float = 20.0
const GW: int = 49
const GH: int = 36
## How many cells of detour one expected kill is worth avoiding.
const RISK_WEIGHT: float = 7.0
const DX: Array[int] = [1, -1, 0, 0, 1, 1, -1, -1]
const DY: Array[int] = [0, 0, 1, -1, 1, -1, 1, -1]
const STEP: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.4142, 1.4142, 1.4142, 1.4142]

## Old behaviour: straight-ish raids at random targets (Easy, and the
## opponent in balance runs).
var classic: bool = false
## Test opponent: the classic AI that also spends spare money on air
## defence round its factories, the way a careful player does.
var turtle: bool = false

var _own: PackedByteArray = PackedByteArray()
var _sea: PackedByteArray = PackedByteArray()
var _cap: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
var _fields: Array = [null, null]
var _grid_key: int = -1
var _fields_at: float = -99.0
var _plan_cost: float = 0.0
var _waiting_since: float = -1.0
var _probe_at: float = 0.0
## Some factory of ours has little air defence over it.
var _exposed: bool = false

class Option:
	var target: LiteBuilding
	var arm: int
	var count: int
	var cost: float
	var value: float
	var route: Array[Vector2]
	var travel: float
	## A second group of another arm in the same raid (-1 for none): the
	## missiles that go in with the drones.
	var mix_arm: int = -1
	var mix_count: int = 0
	var mix_route: Array[Vector2] = []
	var mix_travel: float = 0.0

func _cell(p: Vector2) -> int:
	return clampi(int(p.y / CELL), 0, GH - 1) * GW + clampi(int(p.x / CELL), 0, GW - 1)

static func _center(c: int) -> Vector2:
	return Vector2((c % GW + 0.5) * CELL, (c / GW + 0.5) * CELL)

func _prepare(s: LiteSim) -> void:
	if _own.size() == GW * GH:
		return
	_own.resize(GW * GH)
	_sea.resize(GW * GH)
	for c: int in GW * GH:
		var sd: int = s.map.side_at(_center(c))
		_own[c] = 1 if sd == side else 0
		_sea[c] = 1 if sd < 0 else 0
	for a: int in 2:
		_cap[a].resize(GW * GH)

## Expected kills per cell crossed by one drone (0) or cruise missile (1),
## from the air defence of the other side we have seen. Rebuilt when that
## set changes.
func _threats(s: LiteSim) -> bool:
	var key: int = 17
	for b: LiteBuilding in s.buildings:
		if b.alive and b.side != side and (b.is_ad or b.is_gun) and b.seen[side] and b.ready:
			key = (key * 31 + b.id) % 1000000007
	if key == _grid_key:
		return false
	_grid_key = key
	for a: int in 2:
		_cap[a].fill(0.0)
	for b: LiteBuilding in s.buildings:
		if not b.alive or b.side == side or not (b.is_ad or b.is_gun) or not b.seen[side] or not b.ready:
			continue
		var r: float = LiteRules.range(b.kind)
		var kd: float
		var kc: float
		match b.kind:
			LiteKind.SAM:
				kd = 0.85
				kc = 0.32
			LiteKind.CAPITAL:
				kd = 0.85
				kc = 0.1
			_:
				kd = 0.43
				kc = 0.05
		var x0: int = maxi(0, int((b.pos.x - r) / CELL))
		var x1: int = mini(GW - 1, int((b.pos.x + r) / CELL))
		var y0: int = maxi(0, int((b.pos.y - r) / CELL))
		var y1: int = mini(GH - 1, int((b.pos.y + r) / CELL))
		for y: int in range(y0, y1 + 1):
			for x: int in range(x0, x1 + 1):
				if Vector2((x + 0.5) * CELL, (y + 0.5) * CELL).distance_to(b.pos) <= r:
					_cap[0][y * GW + x] += kd
					_cap[1][y * GW + x] += kc
	return true

## Cheapest ways in from our own land to every cell for one weapon:
## [cost, kills on the way, previous cell].
func _field(cap: PackedFloat32Array) -> Array:
	var n: int = GW * GH
	var dist:= PackedFloat32Array()
	dist.resize(n)
	dist.fill(INF)
	var risk:= PackedFloat32Array()
	risk.resize(n)
	var prev:= PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var done:= PackedByteArray()
	done.resize(n)
	var hk:= PackedFloat32Array()
	var hv:= PackedInt32Array()
	for c: int in n:
		if _own[c] == 1:
			dist[c] = 0.0
			hk.append(0.0)
			hv.append(c)
	while hk.size() > 0:
		var d: float = hk[0]
		var u: int = hv[0]
		var last: int = hk.size() - 1
		hk[0] = hk[last]
		hv[0] = hv[last]
		hk.resize(last)
		hv.resize(last)
		var i: int = 0
		while true:
			var l: int = 2 * i + 1
			if l >= last:
				break
			var m: int = l
			if l + 1 < last and hk[l + 1] < hk[l]:
				m = l + 1
			if hk[m] >= hk[i]:
				break
			var tk: float = hk[i]
			hk[i] = hk[m]
			hk[m] = tk
			var tv: int = hv[i]
			hv[i] = hv[m]
			hv[m] = tv
			i = m
		if done[u] == 1:
			continue
		done[u] = 1
		var ux: int = u % GW
		var uy: int = u / GW
		for k: int in 8:
			var nx: int = ux + DX[k]
			var ny: int = uy + DY[k]
			if nx < 0 or ny < 0 or nx >= GW or ny >= GH:
				continue
			var v: int = ny * GW + nx
			if done[v] == 1 or _own[v] == 1:
				continue
			var nd: float = d + STEP[k] * (1.0 + RISK_WEIGHT * cap[v]) * (1.15 if _sea[v] == 1 else 1.0)
			if nd < dist[v]:
				dist[v] = nd
				risk[v] = risk[u] + cap[v] * STEP[k]
				prev[v] = u
				hk.append(nd)
				hv.append(v)
				var j: int = hk.size() - 1
				while j > 0:
					var p: int = (j - 1) / 2
					if hk[p] <= hk[j]:
						break
					var tk: float = hk[p]
					hk[p] = hk[j]
					hk[j] = tk
					var tv: int = hv[p]
					hv[p] = hv[j]
					hv[j] = tv
					j = p
	return [dist, risk, prev]

func _refresh(s: LiteSim) -> void:
	_prepare(s)
	if _threats(s) or _fields[0] == null or s.time - _fields_at > 20.0:
		_fields_at = s.time
		for a: int in 2:
			_fields[a] = _field(_cap[a])

## Kills scored along a straight segment, sampled every half cell.
func _segment_risk(cap: PackedFloat32Array, a: Vector2, b: Vector2) -> float:
	var len: float = a.distance_to(b)
	var n: int = maxi(1, int(len / (CELL * 0.5)))
	var sum: float = 0.0
	for i: int in n:
		sum += cap[_cell(a.lerp(b, (i + 0.5) / n))]
	return sum * len / n / CELL

## The way in to a point for a weapon: waypoints from the edge of our land,
## straightened wherever a straight line is no more dangerous, and the
## kills expected on it.
func _route(arm: int, to: Vector2) -> Array:
	var field: Array = _fields[arm]
	var prev: PackedInt32Array = field[2]
	var risk: PackedFloat32Array = field[1]
	var cells: Array[int] = []
	var c: int = _cell(to)
	while c >= 0 and cells.size() < 400:
		cells.append(c)
		c = prev[c]
	cells.reverse()
	var pts: Array[Vector2] = []
	var acc:= PackedFloat32Array()
	var sum: float = 0.0
	for i: int in cells.size():
		var p: Vector2 = _center(cells[i])
		if p.distance_to(to) < 26:
			break
		if i > 0:
			sum += _cap[arm][cells[i]] * pts[pts.size() - 1].distance_to(p) / CELL
		pts.append(p)
		acc.append(sum)
	var out: Array[Vector2] = []
	var i: int = 0
	while i < pts.size():
		out.append(pts[i])
		var j: int = pts.size() - 1
		while j > i + 1 and _segment_risk(_cap[arm], pts[i], pts[j]) > acc[j] - acc[i] + 0.15:
			j -= 1
		if j <= i:
			j = i + 1
		i = j
	return [out, risk[_cell(to)]]

static func _path_length(from: Vector2, route: Array[Vector2], to: Vector2) -> float:
	var len: float = 0.0
	var a: Vector2 = from
	for p: Vector2 in route:
		len += a.distance_to(p)
		a = p
	return len + a.distance_to(to)

## Share of this weapon shot down so far in the war, softened early on.
func _loss(s: LiteSim, arm: int) -> float:
	var st: LiteStats = s.stats
	var down: int = st.downed[arm] if side == 1 else st.our_downed[arm]
	var land: int = st.landed[arm] if side == 1 else st.our_landed[arm]
	return minf(0.85, (down + 0.5) / (down + land + 2.0))

## With nothing it knows of left standing in its focus province, it shells
## the province itself now and then: an offensive goes on whether or not
## there is a site to aim at. True if it sent a raid.
func _press_focus(s: LiteSim, me: LiteSide) -> bool:
	if focus_set.is_empty() or s.time < _focus_at:
		return false
	for b: LiteBuilding in s.buildings:
		if b.alive and b.side != side and b.seen[side] and focus_set.has(s.map.province(b.region)):
			return false
	var spots: Array[Vector2] = s.map.regions[focus_set[_next(focus_set.size())]].spots
	if spots.is_empty():
		return false
	_focus_at = s.time + _r(16, 26) * tempo
	var n: int = mini(12, int(minf(me.war_fund, me.money) * 0.5 / LiteRules.cost(LiteArm.DRONE)))
	if n < 3:
		return false
	var at: Vector2 = spots[_next(spots.size())]
	var route: Array[Vector2] = []
	if smart and not classic:
		route = _route(LiteArm.DRONE, at)[0]
	var before: float = me.money
	s.strike(side, LiteArm.DRONE, at, n, null, 0.0, route)
	me.war_fund = maxf(0, me.war_fund - (before - me.money))
	return true

func _focus(s: LiteSim, b: LiteBuilding) -> float:
	return focus_weight if focus_set.has(s.map.province(b.region)) else 1.0

## What destroying a site is worth to us, in money.
func _value(s: LiteSim, b: LiteBuilding) -> float:
	return _site_value(s, b) * _focus(s, b)

func _site_value(s: LiteSim, b: LiteBuilding) -> float:
	var near: int = 0
	if b.is_ad or b.is_gun:
		for o: LiteBuilding in s.buildings:
			if o.alive and o.side == b.side and o != b and o.seen[side] and (o.kind == LiteKind.FACTORY or o.kind == LiteKind.CAPITAL) and o.pos.distance_to(b.pos) <= LiteRules.range(b.kind):
				near += 1
	match b.kind:
		LiteKind.FACTORY:
			return 520.0
		LiteKind.SAM:
			return 240.0 + 110.0 * near + (25.0 * b.kills if adaptive else 0.0)
		LiteKind.GUN:
			return 70.0 + 55.0 * near + (10.0 * b.kills if adaptive else 0.0)
		LiteKind.DEPOT:
			return 420.0
		LiteKind.RADAR:
			return 300.0 + 80.0 * near
		LiteKind.LAUNCHER:
			return 360.0
		LiteKind.CAPITAL:
			var factories: int = 0
			for o: LiteBuilding in s.buildings:
				if o.alive and o.side == b.side and o.kind == LiteKind.FACTORY:
					factories += 1
			# Taking it wins the war: worth most when it is low and no
			# factories are left to repair it.
			return 6000.0 * (1.6 - b.hp / b.max_hp) * (1.6 if factories <= 1 else 1.0)
	return 0.0

## The cheapest way to destroy a site: drones, cruise or ballistic missiles,
## enough for the hits it takes after the losses expected on the way in.
func _option(s: LiteSim, me: LiteSide, b: LiteBuilding) -> Option:
	# The capital is worn down a chunk at a time; a bigger one when it has no
	# air defence round it that we know of.
	var chunk: float = 45.0
	if b.kind == LiteKind.CAPITAL:
		chunk = 80.0
		for o: LiteBuilding in s.buildings:
			if o.alive and o.side != side and o.seen[side] and (o.is_ad or o.is_gun) and o.kind != LiteKind.CAPITAL and o.pos.distance_to(b.pos) <= LiteRules.range(o.kind):
				chunk = 45.0
				break
	var hp: float = minf(b.hp, chunk) if b.kind == LiteKind.CAPITAL else b.hp
	var drone: Option = null
	var missile: Option = null
	var by_arm: Array[Option] = [null, null, null]
	for arm: int in 3:
		var hits: int = ceili(hp / LiteRules.damage(arm))
		var route: Array[Vector2] = []
		var kills: float
		var from: Vector2
		if arm == LiteArm.BALLISTIC:
			var sams: int = 0
			for o: LiteBuilding in s.buildings:
				if o.alive and o.side != side and o.kind == LiteKind.SAM and o.seen[side] and o.ready and o.pos.distance_to(b.pos) <= LiteRules.range(LiteKind.SAM):
					sams += 1
			kills = minf(2.6 * sams, hits * 2.4) if sams > 0 else 0.0
			from = me.capital.pos
		else:
			var r: Array = _route(arm, b.pos)
			route = r[0]
			kills = r[1]
			from = route[0] if route.size() > 0 else me.capital.pos
		# A large group swamps the defence; small ones are shot down piecemeal.
		# Expected losses: what the defence it has seen would score on the way
		# in, plus what this weapon has been losing beyond that.
		var loss: float = _loss(s, arm)
		var count: int = hits + ceili(kills * 1.15 + hits * loss / (1.0 - loss)) + (1 if arm == LiteArm.DRONE else 0)
		var most: int = 60 if arm == LiteArm.DRONE else 30
		if b.kind == LiteKind.CAPITAL:
			most *= 2
		if count > most:
			continue
		var o:= Option.new()
		o.target = b
		o.arm = arm
		o.count = count
		o.cost = count * LiteRules.cost(arm)
		o.route = route
		o.travel = _path_length(from, route, b.pos) / LiteRules.mean_speed(arm) * 1.1
		by_arm[arm] = o
		if arm == LiteArm.DRONE:
			drone = o
	# The capital and air defence sites are what ballistic missiles are for:
	# they are preferred there unless they cost far more than cruise missiles.
	var cru: Option = by_arm[LiteArm.CRUISE]
	var bal: Option = by_arm[LiteArm.BALLISTIC]
	missile = cru
	if bal != null and (missile == null or bal.cost * (0.6 if b.kind == LiteKind.CAPITAL or b.is_ad else 1.0) < missile.cost):
		missile = bal
	# And now and then, once the war is under way, ballistic missiles anyway:
	# the other side never knows what is coming.
	if bal != null and s.time > 180.0 and _rng.randf() < 0.35:
		missile = bal
	# Missiles strike fast and with little warning: the enemy takes them
	# whenever they cost not much more than the drones would.
	var best: Option = drone
	if missile != null and (best == null or missile.cost <= best.cost * (1.5 if adaptive else 1.25)):
		best = missile
	elif missile != null and drone != null:
		# Otherwise the drones go in with missiles behind them, a share of
		# the damage that grows as the war goes on and is largest against
		# the capital, paying at most about twice what drones alone would.
		var share: float = 0.3 + minf(0.25, s.time / 1600.0) + (0.1 if adaptive else 0.0) + (0.15 if b.kind == LiteKind.CAPITAL else 0.0)
		var ratio: float = missile.cost / drone.cost
		if ratio > 1.0:
			share = minf(share, 1.1 / (ratio - 1.0))
		var mc: int = roundi(missile.count * share)
		if mc >= 1:
			var o:= Option.new()
			o.target = b
			o.arm = LiteArm.DRONE
			o.count = maxi(1, ceili(drone.count * (1.0 - share)))
			o.route = drone.route
			o.travel = drone.travel
			o.mix_arm = missile.arm
			o.mix_count = mc
			o.mix_route = missile.route
			o.mix_travel = missile.travel
			o.cost = o.count * LiteRules.cost(LiteArm.DRONE) + mc * LiteRules.cost(missile.arm)
			best = o
	if best != null:
		best.value = _value(s, b) * (hp / b.max_hp if b.kind == LiteKind.CAPITAL else 1.0)
	return best

func _attack_smart(s: LiteSim, me: LiteSide) -> void:
	if s.time < _next_raid:
		return
	_next_raid = s.time + 2.0
	_refresh(s)
	_press_focus(s, me)
	var known: Array[LiteBuilding] = []
	for b: LiteBuilding in s.buildings:
		if b.alive and b.side != side and b.seen[side] and b.ready or (b.alive and b.side != side and b.seen[side] and b.kind == LiteKind.FACTORY):
			known.append(b)
	var factories_known: int = 0
	for b: LiteBuilding in known:
		if b.kind == LiteKind.FACTORY:
			factories_known += 1
	# Find more of the other side's sites when it knows few.
	# (A few scouts at a time: sent every tick they would eat the whole fund.)
	if s.time > _probe_at and me.money > 40:
		_probe_at = s.time + (_r(28, 42) if factories_known < 2 else _r(70, 110)) * tempo
		var scouts: int = 3 if factories_known < 2 else 2
		_scout_smart(s, me, scouts)
	var options: Array[Option] = []
	for b: LiteBuilding in known:
		var o: Option = _option(s, me, b)
		if o != null and o.value / o.cost >= 0.55 * clampf(700.0 / maxf(1.0, me.war_fund), 0.2, 1.0):
			options.append(o)
	if options.is_empty():
		return
	options.sort_custom(func(a: Option, b: Option) -> bool: return a.value / a.cost > b.value / b.cost)
	# A raid: the best few targets, several of them if the fund allows, so
	# the defence is hit from more than one direction at once.
	var most: int = 5 if adaptive else 3
	var plan: Array[Option] = [options[0]]
	var cost: float = options[0].cost
	for k: int in range(1, options.size()):
		if plan.size() >= most:
			break
		var o: Option = options[k]
		if cost + o.cost <= maxf(me.war_fund, options[0].cost) * 1.0:
			plan.append(o)
			cost += o.cost
	var fund: float = minf(me.war_fund, me.money)
	if fund < cost:
		# Save for it, and warn of a large strike while doing so.
		if _waiting_since < 0:
			_waiting_since = s.time
		if not massing and cost >= 650 and waves:
			massing = true
			_plan_cost = cost
			s.events.append(LiteEvent.new(LiteEv.WARNING, side, 0, Vector2.ZERO, 0, 0, cost))
		var patience: float = 200.0 if massing else 90.0
		if s.time - _waiting_since < patience:
			return
		# Waited too long: strike with what the fund buys.
		while plan.size() > 1 and cost > fund:
			cost -= plan[plan.size() - 1].cost
			plan.remove_at(plan.size() - 1)
		if cost > fund:
			var o: Option = plan[0]
			o.count = int(fund / LiteRules.cost(o.arm))
			if o.count < 3:
				return
	_launch(s, me, plan)
	massing = false
	_waiting_since = -1.0
	_next_raid = s.time + _r(18, 30) * tempo

## All groups of a raid are timed to arrive within a few seconds.
func _launch(s: LiteSim, me: LiteSide, plan: Array[Option]) -> void:
	var before: float = me.money
	var arrive: float = 0.0
	for o: Option in plan:
		arrive = maxf(arrive, o.travel + o.count * (0.55 if o.arm == LiteArm.DRONE else 0.35) * 0.5)
		if o.mix_arm >= 0:
			arrive = maxf(arrive, o.mix_travel + o.mix_count * 0.35 * 0.5)
	var raid: LiteRaid = null
	for o: Option in plan:
		var aim: Vector2 = o.target.pos
		raid = _or(_send(s, o.arm, aim, o.count, raid, maxf(0.0, arrive - o.travel), o.route), raid)
		if o.mix_arm >= 0:
			# The missiles land just after the drones have drawn the defence's fire.
			raid = _or(_send(s, o.mix_arm, aim, o.mix_count, raid, maxf(0.0, arrive + 3.0 - o.mix_travel), o.mix_route), raid)
	me.war_fund = maxf(0, me.war_fund - (before - me.money))

func _send(s: LiteSim, arm: int, aim: Vector2, count: int, raid: LiteRaid, delay: float, route: Array[Vector2]) -> LiteRaid:
	if arm == LiteArm.BALLISTIC:
		return s.strike(side, arm, aim, count, raid, delay)
	return s.strike(side, arm, aim, count, raid, delay, route)

func _scout_smart(s: LiteSim, me: LiteSide, n: int) -> void:
	var regions: Array[LiteRegion] = []
	for r: LiteRegion in s.map.regions:
		if r.side != side and not r.city and r.spots.size() > 0 and not _scouted.has(r.id):
			regions.append(r)
	if regions.is_empty():
		_scouted.clear()
		return
	for i: int in n:
		if regions.is_empty():
			break
		var r: LiteRegion = regions[_next(regions.size())]
		regions.erase(r)
		_scouted[r.id] = true
		var way: Array = _route(LiteArm.DRONE, r.label)
		s.strike(side, LiteArm.DRONE, r.label, 1, null, i * 0.8, way[0])

func _factory_reserve(s: LiteSim, me: LiteSide) -> float:
	var factories: int = 0
	for b: LiteBuilding in s.buildings:
		if b.alive and b.side == side and b.kind == LiteKind.FACTORY:
			factories += 1
	var room: bool = false
	for r: LiteRegion in s.map.regions:
		if r.side == side and not r.city and s.free_slots(r.id) > 0:
			room = true
			break
	return float(s.cost(side, LiteKind.FACTORY)) if room and factories < 2 + int(s.time / (32.0 if adaptive else 45.0)) else 0.0

## Air defence round what matters: rings round the capital, then cover over
## every factory, more of both as the war goes on; and where hits came down.
func _defend_smart(s: LiteSim, me: LiteSide) -> void:
	var k: int = 0
	for h: LiteSide.Hit in me.hit_log:
		if not (s.time - h.t > 30):
			me.hit_log[k] = h
			k += 1
	me.hit_log.resize(k)
	var cap_sam: int = 0
	var cap_gun: int = 0
	for b: LiteBuilding in s.buildings:
		if not b.alive or b.side != side or b.pos.distance_to(me.capital.pos) > 80:
			continue
		if b.kind == LiteKind.SAM: cap_sam += 1
		elif b.kind == LiteKind.GUN: cap_gun += 1
	var stage: float = s.time / (150.0 if adaptive else 220.0)
	if cap_sam == 0:
		if afford(s, me, LiteKind.SAM, true): put(s, LiteKind.SAM, me.capital.pos, 18, 55)
		return
	# A factory with little cover gets some at once, a SAM if there is money.
	_exposed = false
	for b: LiteBuilding in s.buildings:
		if b.alive and b.side == side and b.kind == LiteKind.FACTORY and b.ready and s.coverage(side, b.pos) < 2:
			_exposed = true
			var kind: int = LiteKind.SAM if free_money(me) >= LiteRules.cost_kind(LiteKind.SAM) else LiteKind.GUN
			if afford(s, me, kind, true): put(s, kind, b.pos, 10, 30)
			return
	# Beyond that, the next factory comes first, unless we are being hit.
	var under_fire: bool = me.hit_log.size() > 0
	for b: LiteBuilding in s.buildings:
		if b.alive and b.side == side and b.kind == LiteKind.FACTORY and b.hp < b.max_hp:
			under_fire = true
			break
	if not under_fire and free_money(me) < _factory_reserve(s, me) + LiteRules.cost_kind(LiteKind.GUN):
		return
	if cap_sam < mini(5, 1 + int(stage)):
		if afford(s, me, LiteKind.SAM, true): put(s, LiteKind.SAM, me.capital.pos, 18, 55)
		return
	if cap_gun < mini(5, 1 + int(stage)):
		if afford(s, me, LiteKind.GUN, true): put(s, LiteKind.GUN, me.capital.pos, 18, 55)
		return
	# Every factory under cover, rising with the war: a SAM first (it also
	# stops ballistic missiles), then guns against the drones.
	var want: float = minf(6.0, 2.0 + stage)
	var weakest: LiteBuilding = null
	var low: float = INF
	for b: LiteBuilding in s.buildings:
		if not b.alive or b.side != side or b.kind != LiteKind.FACTORY:
			continue
		var c: float = s.coverage(side, b.pos)
		if c < low:
			low = c
			weakest = b
	if weakest != null and low < want:
		var sam: bool = low < 2 or (low < 4 and _rng.randf() < 0.4)
		var kind: int = LiteKind.SAM if sam else LiteKind.GUN
		if afford(s, me, kind, low < 1):
			put(s, kind, weakest.pos, 10, 34)
		return
	for i: int in me.hit_log.size():
		var h: LiteSide.Hit = me.hit_log[i]
		if s.coverage(side, h.p) >= want:
			continue
		if not afford(s, me, LiteKind.GUN, false):
			return
		if put(s, LiteKind.GUN, h.p, 8, 30):
			me.hit_log.remove_at(i)
		return
