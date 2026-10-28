class_name LiteSim
extends RefCounted
## The whole lite game: two sides with the same rules. Factories earn money
## and repair the capital; guns and SAMs shoot down what flies into range;
## drones and missiles fly to where they were sent and damage what is there.
## Regions go under air alert where a weapon is and where it is heading, and
## factories under alert work at a third of their pace. Destroying a capital
## ends the game.

## C# float.MaxValue.
const _FLOAT_MAX: float = 3.4028235e38


## Was `private readonly record struct Pending`.
class Pending:
	var at: float
	var side: int
	var arm: int
	var target: Vector2
	var raid: LiteRaid
	## Empty = no route (was null).
	var route: Array[Vector2]

	func _init(p_at: float, p_side: int, p_arm: int, p_target: Vector2, p_raid: LiteRaid, p_route: Array[Vector2]) -> void:
		at = p_at
		side = p_side
		arm = p_arm
		target = p_target
		raid = p_raid
		route = p_route


## Was the tuple `(int Region, float Until)`.
class Ruin:
	var region: int
	var until: float

	func _init(p_region: int, p_until: float) -> void:
		region = p_region
		until = p_until


var map: LiteMap
var sides: Array[LiteSide] = [LiteSide.new(0), LiteSide.new(1)]
var buildings: Array[LiteBuilding] = []
var weapons: Array[LiteWeapon] = []
var interceptors: Array[LiteInterceptor] = []
var fx: Array[LiteFx] = []
var events: Array[LiteEvent] = []
var ai: Array[LiteAi] = [null, null]
var sams_on_drones: Array[bool] = [true, true]
var income_scale: Array[float] = [1.0, 1.0]
var time: float = 0.0
var winner: int = -1

var alert: Array[bool] = []
var ballistic: Array[bool] = []
var alert_since: PackedFloat32Array = PackedFloat32Array()
var region_flash: PackedFloat32Array = PackedFloat32Array()
var alerted: Array[int] = [0, 0]
var side_alert_since: Array[float] = [0.0, 0.0]
var side_quiet_since: Array[float] = [0.0, 0.0]
var _quiet: PackedFloat32Array = PackedFloat32Array()
var _bal_quiet: PackedFloat32Array = PackedFloat32Array()
var _threat: Array[bool] = []
var _bal: Array[bool] = []

var _rng: RandomNumberGenerator
var _queue: Array[Pending] = []
var _tmp: Array[LiteRegion] = []
var _ids: int = 0
var _raids: int = 0
var _alert_tick: float = 0.0

## Room for factories in each region; ruins of destroyed ones take room
## until they are cleared. Regions near the front have more room than the
## deep rear, and the room moves about during the war.
var slots: PackedInt32Array = PackedInt32Array()
var _ruins: Array[Ruin] = []
var _shift: float = LiteRules.INDUSTRY_SHIFT
var _intel: float = LiteRules.INTEL_EVERY


func _init(p_map: LiteMap, seed: int) -> void:
	map = p_map
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed * 7919 + 13
	var n: int = map.regions.size()
	alert.resize(n); alert.fill(false)
	ballistic.resize(n); ballistic.fill(false)
	alert_since.resize(n)
	region_flash.resize(n)
	_quiet.resize(n); _bal_quiet.resize(n)
	_threat.resize(n); _threat.fill(false)
	_bal.resize(n); _bal.fill(false)
	slots.resize(n)
	for s: int in 2: init_slots(s)
	even_slots()
	for s: int in 2: setup(s)
	for b: LiteBuilding in buildings:
		if b.kind == LiteKind.FACTORY: slots[b.region] = maxi(slots[b.region], factories_in(b.region))


## C# `Random.Next(n)`.
func _next(n: int) -> int:
	return _rng.randi_range(0, n - 1) if n > 0 else 0


func setup(side: int) -> void:
	var cap: LiteBuilding = add(side, LiteKind.CAPITAL, map.capital[side], true)
	sides[side].capital = cap
	cap.seen[1 - side] = true
	var sam: Variant = find_spot(side, map.capital[side], 14, 26)
	if sam != null: add(side, LiteKind.SAM, sam, true)
	# Two factories to start with, one guarded by a gun.
	for i: int in 2:
		var factory: Variant = find_spot(side, map.capital[side], 55 + 40 * i, 110 + 50 * i)
		if factory == null: continue
		add(side, LiteKind.FACTORY, factory, true)
		var gun: Variant = find_spot(side, factory, 14, 28) if i == 0 else null
		if gun != null: add(side, LiteKind.GUN, gun, true)


# ---------------------------------------------------------------- orders

func can_place(side: int, p: Vector2) -> bool:
	if map.side_at(p) != side: return false
	for a: int in 4:
		if map.side_at(p + Vector2(5, 0).rotated(a * PI / 2)) != side: return false
	for b: LiteBuilding in buildings:
		if b.alive and b.pos.distance_to(p) < 13: return false
	return true


## The price of a building for a side: factories get dearer the more it has.
func cost(side: int, kind: int) -> int:
	var c: int = LiteRules.cost_kind(kind)
	if kind == LiteKind.FACTORY:
		for b: LiteBuilding in buildings:
			if b.alive and b.side == side and b.kind == LiteKind.FACTORY: c += LiteRules.FACTORY_STEP
	return c


## Front regions get 2 or 3 places for factories, the middle 1 or 2, the
## deep rear 0 or 1; the capital's region one more. Depth is how far the
## region's middle lies from the nearest region of the other side.
func init_slots(side: int) -> void:
	var depth: Dictionary = {}
	for r: LiteRegion in map.regions:
		if r.side != side or r.city: continue
		var d: float = _FLOAT_MAX
		for o: LiteRegion in map.regions:
			if o.side != side and not o.city: d = minf(d, r.label.distance_to(o.label))
		depth[r.id] = d
	var lo: float = _FLOAT_MAX
	var hi: float = 0
	for d: float in depth.values():
		lo = minf(lo, d)
		hi = maxf(hi, d)
	for id: int in depth:
		var d: float = depth[id]
		var t: float = (d - lo) / maxf(1, hi - lo)
		slots[id] = (2 + _next(2)) if t < 0.33 else ((1 + _next(2)) if t < 0.66 else _next(2))
		if map.regions[id].neighbors.has(map.region_at(map.capital[side])): slots[id] = maxi(slots[id], 1)
	var cap_region: int = map.regions[map.region_at(map.capital[side])].parent
	if cap_region >= 0: slots[cap_region] += 1


## The bigger country has more regions; both get the same room in all,
## taken off random regions of the one with more.
func even_slots() -> void:
	var total: Array[int] = [0, 0]
	for r: LiteRegion in map.regions: total[r.side] += slots[r.id]
	var more: int = 0 if total[0] > total[1] else 1
	var list: Array[int] = []
	while total[more] > total[1 - more]:
		list.clear()
		for r: LiteRegion in map.regions:
			if r.side == more and slots[r.id] > 0: list.append(r.id)
		slots[list[_next(list.size())]] -= 1
		total[more] -= 1


func factories_in(region: int) -> int:
	var n: int = 0
	for b: LiteBuilding in buildings:
		if b.alive and b.kind == LiteKind.FACTORY and b.region == region: n += 1
	return n


func ruins_in(region: int) -> int:
	var n: int = 0
	for r: Ruin in _ruins:
		if r.region == region: n += 1
	return n


func free_slots(region: int) -> int:
	return slots[region] - factories_in(region) - ruins_in(region)


## A factory goes into a region, at a free spot of its choosing.
func build_factory(side: int, region: int) -> LiteBuilding:
	if region < 0 or region >= map.regions.size() or map.regions[region].side != side or free_slots(region) <= 0: return null
	var c: int = cost(side, LiteKind.FACTORY)
	if sides[side].money < c: return null
	var spots := map.regions[region].spots
	var k: int = 0
	while k < 40 and spots.size() > 0:
		var p: Vector2 = spots[_next(spots.size())]
		k += 1
		if not can_place(side, p): continue
		sides[side].money -= c
		return add(side, LiteKind.FACTORY, p, false)
	return null


## Agents and satellites: each side learns where one hidden factory of the
## other's is, or a hidden air defence site if no factory is hidden.
func intel() -> void:
	var hidden: Array[LiteBuilding] = []
	for viewer: int in 2:
		for kind: int in [LiteKind.FACTORY, LiteKind.SAM, LiteKind.GUN]:
			hidden.clear()
			for b: LiteBuilding in buildings:
				if b.alive and b.side != viewer and b.kind == kind and not b.seen[viewer]: hidden.append(b)
			if hidden.size() == 0: continue
			spot(hidden[_next(hidden.size())], viewer)
			break


## Every few minutes on each side one region gains room for a factory
## and, half the time, another with room to spare loses one.
func shift_industry() -> void:
	for side: int in 2:
		var grow: Array[int] = []
		var shrink: Array[int] = []
		for r: LiteRegion in map.regions:
			if r.side != side or r.city: continue
			if slots[r.id] < 4: grow.append(r.id)
			if free_slots(r.id) > 0: shrink.append(r.id)
		if grow.size() > 0:
			var g: int = grow[_next(grow.size())]
			slots[g] += 1
			shrink.erase(g)
			events.append(LiteEvent.new(LiteEv.INDUSTRY, side, g, Vector2.ZERO, 0, 0, 1))
		if shrink.size() > 0 and _rng.randf() < 0.5:
			var k: int = shrink[_next(shrink.size())]
			slots[k] -= 1
			events.append(LiteEvent.new(LiteEv.INDUSTRY, side, k, Vector2.ZERO, 0, 0, -1))


func build(side: int, kind: int, p: Vector2) -> LiteBuilding:
	if kind == LiteKind.FACTORY: return build_factory(side, map.region_at(p))
	var c: int = cost(side, kind)
	if sides[side].money < c or not can_place(side, p): return null
	sides[side].money -= c
	return add(side, kind, p, false)


func add(side: int, kind: int, p: Vector2, instant: bool) -> LiteBuilding:
	var b := LiteBuilding.new()
	_ids += 1
	b.id = _ids
	b.side = side
	b.kind = kind
	b.pos = p
	b.region = map.region_at(p)
	b.max_hp = LiteRules.max_hp(kind)
	b.build_total = LiteRules.build_time(kind)
	b.ammo = LiteRules.SAM_RACK if kind == LiteKind.SAM else 0
	b.hp = b.max_hp
	b.build = 0.0 if instant else b.build_total
	b.seen[side] = true
	buildings.append(b)
	return b


## Sends `count` weapons of one kind at `target`, launched a moment apart,
## along `route` if given (drones and cruise missiles; ballistic ones fly straight).
## An empty `route` means none (was null in C#).
func strike(side: int, arm: int, target: Vector2, count: int, raid: LiteRaid = null, delay: float = 0.0, route: Array[Vector2] = []) -> LiteRaid:
	var c: int = LiteRules.cost(arm) * count
	if count <= 0 or sides[side].money < c: return null
	sides[side].money -= c
	if raid == null:
		raid = LiteRaid.new()
		_raids += 1
		raid.id = _raids
		raid.side = side
		raid.target = target
	raid.total += count
	raid.by_arm[arm] += count
	var gap: float = 0.55 if arm == LiteArm.DRONE else 0.35
	for i: int in count:
		_queue.append(Pending.new(time + delay + i * gap * (0.7 + 0.6 * _rng.randf()), side, arm, target, raid, route))
	return raid


## Returns a Vector2, or null when no spot was found (was `Vector2?`).
func find_spot(side: int, near: Vector2, r_min: float, r_max: float) -> Variant:
	for i: int in 80:
		var a: float = _rng.randf() * TAU
		var r: float = r_min + _rng.randf() * (r_max - r_min)
		var p: Vector2 = near + Vector2(r, 0).rotated(a)
		if can_place(side, p): return p
	return null


func random_spot(side: int, rng: RandomNumberGenerator) -> Vector2:
	_tmp.clear()
	for r: LiteRegion in map.regions:
		if r.side == side and not r.city and r.spots.size() > 0: _tmp.append(r)
	var pick: LiteRegion = _tmp[rng.randi_range(0, _tmp.size() - 1)]
	return pick.spots[rng.randi_range(0, pick.spots.size() - 1)]


## How well a point is covered by one side's ready air defence (gun 1, SAM 2).
## Air defence of the other side that `viewer` knows about, round a point (gun 1, SAM 2).
func known_coverage(viewer: int, p: Vector2) -> float:
	var c: float = 0
	for b: LiteBuilding in buildings:
		if b.alive and b.side != viewer and (b.is_ad or b.is_gun) and b.seen[viewer] and b.pos.distance_to(p) <= LiteRules.range(b.kind):
			c += 2 if b.kind == LiteKind.SAM else 1
	return c


func coverage(side: int, p: Vector2) -> float:
	var c: float = 0
	for b: LiteBuilding in buildings:
		if b.alive and b.side == side and b.is_ad and b.pos.distance_to(p) <= LiteRules.range(b.kind):
			c += 2 if b.kind == LiteKind.SAM else 1
	return c


# ---------------------------------------------------------------- step

func step(dt: float) -> void:
	if winner >= 0:
		step_fx(dt)
		return
	time += dt
	economy(dt)
	for i: int in range(_queue.size() - 1, -1, -1):
		if _queue[i].at <= time:
			var p: Pending = _queue[i]
			_queue.remove_at(i)
			launch(p)
	move_weapons(dt)
	detect()
	air_defence(dt)
	move_interceptors(dt)
	reveal()
	_alert_tick -= dt
	if _alert_tick <= 0:
		_alert_tick += 0.25
		alerts(0.25)
	# _ruins.RemoveAll(r => r.Until <= Time)
	var k: int = 0
	for r: Ruin in _ruins:
		if not (r.until <= time):
			_ruins[k] = r
			k += 1
	_ruins.resize(k)
	_shift -= dt
	if _shift <= 0:
		_shift = LiteRules.INDUSTRY_SHIFT
		shift_industry()
	_intel -= dt
	if _intel <= 0:
		_intel = LiteRules.INTEL_EVERY
		intel()
	if ai[0] != null: ai[0].tick(self, dt)
	if ai[1] != null: ai[1].tick(self, dt)
	step_fx(dt)
	# Buildings.RemoveAll(b => !b.Alive && Time - b.DeadAt > 30)
	k = 0
	for b: LiteBuilding in buildings:
		if not (not b.alive and time - b.dead_at > 30):
			buildings[k] = b
			k += 1
	buildings.resize(k)
	# Weapons.RemoveAll(w => !w.Alive)
	k = 0
	for w: LiteWeapon in weapons:
		if w.alive:
			weapons[k] = w
			k += 1
	weapons.resize(k)
	# Interceptors.RemoveAll(i => !i.Alive)
	k = 0
	for it: LiteInterceptor in interceptors:
		if it.alive:
			interceptors[k] = it
			k += 1
	interceptors.resize(k)


func step_fx(dt: float) -> void:
	for f: LiteFx in fx: f.age += dt
	# Fx.RemoveAll(f => f.Age >= f.Life)
	var k: int = 0
	for f: LiteFx in fx:
		if not (f.age >= f.life):
			fx[k] = f
			k += 1
	fx.resize(k)
	for i: int in region_flash.size(): region_flash[i] = maxf(0, region_flash[i] - dt * 0.7)
	for b: LiteBuilding in buildings:
		b.flash = maxf(0, b.flash - dt * 2.0)
		b.fire_flash = maxf(0, b.fire_flash - dt * 4.0)


func economy(dt: float) -> void:
	for side: LiteSide in sides:
		var income: float = LiteRules.CAPITAL_INCOME if side.capital.alive else 0.0
		var work: float = 0
		for b: LiteBuilding in buildings:
			if b.side != side.index or not b.alive: continue
			if not b.ready:
				b.build -= dt
				if b.ready: events.append(LiteEvent.new(LiteEv.BUILT, b.side, b.region, b.pos, 0, b.kind))
				continue
			if b.kind == LiteKind.FACTORY:
				work += (0.4 + 0.6 * b.hp / b.max_hp) * (LiteRules.ALERT_WORK if alert[b.region] else 1.0)
		side.income = (income + LiteRules.FACTORY_INCOME * work) * income_scale[side.index]
		side.money += side.income * dt
		var cap: LiteBuilding = side.capital
		side.repair = minf(LiteRules.MAX_REPAIR, LiteRules.CAPITAL_REPAIR * work) if cap.alive and cap.hp < cap.max_hp else 0.0
		if side.repair > 0: cap.hp = minf(cap.max_hp, cap.hp + side.repair * dt)


# ---------------------------------------------------------------- weapons

func launch(p: Pending) -> void:
	var arm: int = p.arm
	var target: Vector2 = p.target + Vector2(LiteRules.scatter(arm) * sqrt(_rng.randf()), 0).rotated(_rng.randf() * TAU)
	var route: Array[Vector2] = p.route
	if arm == LiteArm.BALLISTIC: route = []
	var start: Vector2 = origin_near(p.side, route[0]) if route.size() > 0 else origin(p.side, arm, target)
	var w := LiteWeapon.new()
	_ids += 1
	w.id = _ids
	w.side = p.side
	w.arm = arm
	w.raid = p.raid
	w.start = start
	w.pos = start
	w.target = target
	w.speed = LiteRules.speed(arm) * (0.94 + 0.12 * _rng.randf())
	w.seen[p.side] = true
	if arm == LiteArm.BALLISTIC: w.seen[1 - p.side] = true
	var near: float = 12
	for b: LiteBuilding in buildings:
		if b.alive and b.side != p.side and b.pos.distance_to(p.target) < near:
			near = b.pos.distance_to(p.target)
			w.aim = b
	build_path(w, route)
	w.dir = (w.path[0] - start).normalized()
	weapons.append(w)
	p.raid.launched += 1
	sides[p.side].launched += 1
	fx.append(LiteFx.new(LiteFxKind.LAUNCH, start, Vector2.ZERO, 0, 0.7, 0, p.side))
	events.append(LiteEvent.new(LiteEv.LAUNCH, p.side, map.region_at(target), start, arm, 0, 0, p.raid))


## For a drawn route: a launch site of ours nearest its first point.
func origin_near(side: int, at: Vector2) -> Vector2:
	var best: Vector2 = sides[side].capital.pos
	var bd: float = _FLOAT_MAX
	for r: LiteRegion in map.regions:
		if r.side != side or r.city: continue
		for i: int in range(0, r.spots.size(), 3):
			var d: float = r.spots[i].distance_squared_to(at)
			if d < bd:
				bd = d
				best = r.spots[i]
	return best


## Drones go up from near the target, ballistic missiles from the nearest
## region, cruise missiles from deep inside the country (as from bombers).
func origin(side: int, arm: int, target: Vector2) -> Vector2:
	_tmp.clear()
	for r: LiteRegion in map.regions:
		if r.side == side and not r.city and r.spots.size() > 0: _tmp.append(r)
	_tmp.sort_custom(func(a: LiteRegion, b: LiteRegion) -> bool: return a.label.distance_squared_to(target) < b.label.distance_squared_to(target))
	var n: int = _tmp.size()
	var pick: LiteRegion
	match arm:
		LiteArm.DRONE: pick = _tmp[_next(mini(3, n))]
		LiteArm.BALLISTIC: pick = _tmp[_next(mini(2, n))]
		_: pick = _tmp[n / 2 + _next(n - n / 2)]
	return pick.spots[_next(pick.spots.size())]


## C# local function `R(a, b)` of BuildPath.
func _r(a: float, b: float) -> float:
	return a + _rng.randf() * (b - a)


## Along a drawn route if there is one, each weapon a few units off it so
## a salvo does not fly in single file. Otherwise drones bend once, gently,
## and cruise missiles now and then; ballistic missiles fly straight. The
## route is a smooth curve through the turning points.
func build_path(w: LiteWeapon, route: Array[Vector2]) -> void:
	var a: Vector2 = w.start
	var d: Vector2 = w.target - a
	var len: float = d.length()
	var n: Vector2 = Vector2(-d.y, d.x) / maxf(1.0, len)
	var ctrl: PackedVector2Array = PackedVector2Array([a])
	var turns: int = 0
	if route.size() > 0:
		var off := Vector2(_r(-6, 6), _r(-6, 6))
		for q: Vector2 in route: ctrl.append(q + off)
		turns = route.size()
	elif w.arm != LiteArm.BALLISTIC and len > 60:
		var drone: bool = w.arm == LiteArm.DRONE
		if drone or _rng.randf() < 0.5:
			var amp: float = minf(60.0, len * 0.15) if drone else minf(40.0, len * 0.1)
			var line: Vector2 = a + d * _r(0.35, 0.65)
			var p: Vector2 = line + n * amp * _r(-1.0, 1.0)
			if map.side_at(p) < 0: p = line
			ctrl.append(p)
			turns = 1
	ctrl.append(w.target)
	if turns == 0: w.path.append(w.target)
	else:
		for i: int in ctrl.size() - 1:
			var p0: Vector2 = ctrl[maxi(0, i - 1)]
			var p1: Vector2 = ctrl[i]
			var p2: Vector2 = ctrl[i + 1]
			var p3: Vector2 = ctrl[mini(ctrl.size() - 1, i + 2)]
			var steps: int = maxi(2, int(p1.distance_to(p2) / 12))
			for k: int in range(1, steps + 1):
				var t: float = k / float(steps)
				var t2: float = t * t
				var t3: float = t2 * t
				w.path.append(0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3))
	var prev: Vector2 = a
	for p: Vector2 in w.path:
		w.length += prev.distance_to(p)
		prev = p


func move_weapons(dt: float) -> void:
	for w: LiteWeapon in weapons:
		if not w.alive: continue
		var move: float = w.speed * dt
		w.flown += move
		while move > 0 and w.leg < w.path.size():
			var to: Vector2 = w.path[w.leg] - w.pos
			var d: float = to.length()
			if d > 0.001: w.dir = to / d
			if d <= move:
				w.pos = w.path[w.leg]
				w.leg += 1
				move -= d
			else:
				w.pos += to / d * move
				move = 0
		# The track it leaves behind, drawn on the map.
		var step: float = 6.0 if w.arm == LiteArm.DRONE else (6.0 if w.arm == LiteArm.CRUISE else 10.0)
		var keep: int = 26 if w.arm == LiteArm.DRONE else (36 if w.arm == LiteArm.CRUISE else 30)
		w.trail_acc += w.speed * dt
		if w.trail_acc >= step:
			w.trail_acc = 0
			w.trail.append(w.pos)
			if w.trail.size() > keep: w.trail.remove_at(0)
		if w.leg >= w.path.size(): impact(w)
		elif w.aim != null and not w.aim.alive and w.arm != LiteArm.BALLISTIC: retarget(w)


## Its site is gone: head for the nearest other site of the enemy's that
## its side knows of close by, or carry on to the empty spot.
func retarget(w: LiteWeapon) -> void:
	var next: LiteBuilding = null
	var bd: float = 90
	for b: LiteBuilding in buildings:
		if not b.alive or b.side == w.side or not b.seen[w.side]: continue
		var d: float = b.pos.distance_to(w.target)
		if d < bd:
			bd = d
			next = b
	w.aim = next
	if next == null: return
	w.target = next.pos
	w.path.clear()
	w.path.append(next.pos)
	w.leg = 0
	w.length = w.flown + w.pos.distance_to(next.pos)


## Each side sees the other's drones and cruise missiles over its own land
## and within its air defence radars (half as far again as they shoot).
## Once seen, a weapon stays tracked.
func detect() -> void:
	for w: LiteWeapon in weapons:
		var v: int = 1 - w.side
		if not w.alive or w.seen[v]: continue
		var seen: bool = map.side_at(w.pos) == v
		if not seen:
			for b: LiteBuilding in buildings:
				if b.alive and b.side == v and b.is_ad and b.ready and b.pos.distance_to(w.pos) < LiteRules.range(b.kind) * 1.5:
					seen = true
					break
		if not seen: continue
		w.seen[v] = true
		events.append(LiteEvent.new(LiteEv.DETECTED, w.side, map.region_at(w.pos), w.pos, w.arm, 0, 0, w.raid))


func impact(w: LiteWeapon) -> void:
	w.alive = false
	var arm: int = w.arm
	var any: bool = false
	for b: LiteBuilding in buildings:
		if not b.alive or b.side == w.side: continue
		var reach: float = LiteRules.blast(arm) + (6 if b.kind == LiteKind.CAPITAL else 0)
		if b.pos.distance_to(w.pos) > reach: continue
		any = true
		b.hp -= LiteRules.damage(arm)
		b.flash = 1
		if b.kind == LiteKind.CAPITAL and b.hp > 0:
			events.append(LiteEvent.new(LiteEv.CAPITAL_HIT, b.side, 0, b.pos, arm, 0, b.hp))
		if b.hp <= 0: destroy(b, w.side, w.raid)
	if any:
		w.raid.hits += 1
		sides[w.side].hits += 1
	var size: float = 11.0 if arm == LiteArm.DRONE else (15.0 if arm == LiteArm.CRUISE else 21.0)
	fx.append(LiteFx.new(LiteFxKind.BLAST, w.pos, Vector2.ZERO, 0, 0.9, size, w.side))
	fx.append(LiteFx.new(LiteFxKind.SCORCH, w.pos, Vector2.ZERO, 0, 40.0, size, w.side))
	var region: int = map.region_at(w.pos)
	if region != LiteMap.NONE:
		region_flash[region] = 1
		if map.regions[region].side != w.side: sides[1 - w.side].hit_log.append(LiteSide.Hit.new(w.pos, time))
	events.append(LiteEvent.new(LiteEv.HIT, w.side, region, w.pos, arm, 0, 1 if any else 0, w.raid))
	finish(w.raid)


func destroy(b: LiteBuilding, by: int, raid: LiteRaid) -> void:
	b.alive = false
	b.dead_at = time
	if b.kind == LiteKind.FACTORY: _ruins.append(Ruin.new(b.region, time + LiteRules.RUIN_TIME))
	sides[b.side].lost += 1
	sides[by].destroyed += 1
	var where: String = map.regions[b.region].name if b.region < map.regions.size() else ""
	raid.destroyed.append("%s in %s" % [LiteGlyphs.name(b.kind), where])
	events.append(LiteEvent.new(LiteEv.DESTROYED, b.side, b.region, b.pos, 0, b.kind))
	if b.kind == LiteKind.CAPITAL and winner < 0:
		winner = by
		events.append(LiteEvent.new(LiteEv.GAME_OVER, by))


func kill(w: LiteWeapon, by: int, shooter: LiteBuilding) -> void:
	w.alive = false
	if shooter != null: shooter.kills += 1
	w.raid.down += 1
	sides[by].downed += 1
	fx.append(LiteFx.new(LiteFxKind.POP, w.pos, Vector2.ZERO, 0, 0.5, 6 if w.arm == LiteArm.DRONE else 8, by))
	events.append(LiteEvent.new(LiteEv.SHOT_DOWN, by, map.region_at(w.pos), w.pos, w.arm, 0, 0, w.raid))
	finish(w.raid)


func finish(raid: LiteRaid) -> void:
	raid.done += 1
	if raid.done < raid.total: return
	sides[raid.side].last_raid_loss = raid.down / float(raid.total) if raid.total > 0 else 0.0
	events.append(LiteEvent.new(LiteEv.RAID_OVER, raid.side, 0, raid.target, 0, 0, 0, raid))


# ---------------------------------------------------------------- air defence

func air_defence(dt: float) -> void:
	for b: LiteBuilding in buildings:
		if not b.alive or not (b.is_ad or b.is_gun) or not b.ready: continue
		if b.kind == LiteKind.SAM and b.ammo < LiteRules.SAM_RACK:
			b.reload -= dt
			if b.reload <= 0:
				b.ammo += 1
				b.reload = LiteRules.SAM_RELOAD
		b.cool -= dt
		if b.cool > 0: continue
		var range: float = LiteRules.range(b.kind)
		var best: LiteWeapon = null
		var best_score: float = -_FLOAT_MAX
		for w: LiteWeapon in weapons:
			if not w.alive or w.side == b.side: continue
			var d: float = w.pos.distance_to(b.pos)
			if d > range: continue
			var score: float
			if b.is_gun:
				if w.arm == LiteArm.BALLISTIC: continue
				score = (100 if w.arm == LiteArm.DRONE else 0) - d
			else:
				if b.ammo <= 0: break
				if w.arm == LiteArm.DRONE and not sams_on_drones[b.side]: continue
				if w.engaged >= (2 if w.arm == LiteArm.BALLISTIC else 1): continue
				score = w.arm * 1000 - d
			if score > best_score:
				best_score = score
				best = w
		if best == null: continue
		if b.is_gun:
			b.cool = LiteRules.GUN_INTERVAL * (0.5 if b.kind == LiteKind.CAPITAL else 1.0)
			var aim: Vector2 = best.pos + Vector2(_rng.randf() * 6 - 3, _rng.randf() * 6 - 3)
			fx.append(LiteFx.new(LiteFxKind.TRACER, b.pos, aim, 0, 0.14, 0, b.side))
			b.fire_flash = 1
			if _rng.randf() < LiteRules.gun_pk(best.arm): kill(best, b.side, b)
		else:
			var side: LiteSide = sides[b.side]
			if side.money < LiteRules.INTERCEPTOR_COST:
				b.cool = 0.5
				continue
			side.money -= LiteRules.INTERCEPTOR_COST
			b.ammo -= 1
			b.cool = LiteRules.SAM_INTERVAL
			b.fire_flash = 1
			best.engaged += 1
			var it := LiteInterceptor.new()
			it.side = b.side
			it.target = best
			it.from = b
			it.pos = b.pos
			it.goal = best.pos
			interceptors.append(it)
			fx.append(LiteFx.new(LiteFxKind.LAUNCH, b.pos, Vector2.ZERO, 0, 0.5, 0, b.side))
		spot(b, 1 - b.side)


func move_interceptors(dt: float) -> void:
	for i: LiteInterceptor in interceptors:
		if not i.alive: continue
		i.age += dt
		if i.target.alive: i.goal = i.target.pos
		var to: Vector2 = i.goal - i.pos
		var step: float = LiteRules.INTERCEPTOR_SPEED * dt
		var d: float = to.length()
		i.trail.append(i.pos)
		if i.trail.size() > 8: i.trail.remove_at(0)
		if d > step + 3 and i.age < 4.0:
			i.pos += to / d * step
			continue
		i.pos = i.goal
		i.alive = false
		if i.target.alive and _rng.randf() < LiteRules.sam_pk(i.target.arm): kill(i.target, i.side, i.from)
		else:
			if i.target.alive: i.target.engaged -= 1
			fx.append(LiteFx.new(LiteFxKind.PUFF, i.pos, Vector2.ZERO, 0, 0.45, 4, i.side))


# ---------------------------------------------------------------- intelligence and alerts

func reveal() -> void:
	for w: LiteWeapon in weapons:
		if not w.alive: continue
		var r: float = LiteRules.spot_radius(w.arm)
		if r <= 0: continue
		for b: LiteBuilding in buildings:
			if b.alive and b.side != w.side and not b.seen[w.side] and b.pos.distance_to(w.pos) < r: spot(b, w.side)


func spot(b: LiteBuilding, viewer: int) -> void:
	if b.seen[viewer]: return
	b.seen[viewer] = true
	events.append(LiteEvent.new(LiteEv.SPOTTED, viewer, b.region, b.pos, 0, b.kind))


## A region is under alert while a drone or cruise missile is over it or
## close by, or would reach it in a few seconds on its present heading;
## where it will turn next nobody knows. A ballistic launch alerts the
## target region and its neighbours at once. The all-clear comes a few
## seconds after the last threat.
func alerts(dt: float) -> void:
	_threat.fill(false)
	_bal.fill(false)
	for w: LiteWeapon in weapons:
		var victim: int = 1 - w.side
		# Nobody sounds the alert for what nobody has seen.
		if not w.alive or not w.seen[victim]: continue
		mark(w.pos, victim, false)
		if w.arm == LiteArm.BALLISTIC:
			var t: int = map.region_at(w.target)
			if t != LiteMap.NONE and map.regions[t].side == victim:
				mark(w.target, victim, true)
				for n: int in map.regions[t].neighbors:
					if map.regions[n].side == victim:
						_threat[n] = true
						_bal[n] = true
			continue
		var r: float = LiteRules.alert_radius(w.arm)
		for a: int in 8: mark(w.pos + Vector2(r, 0).rotated(a * PI / 4), victim, false)
		var ahead: float = w.speed * LiteRules.heading(w.arm)
		var d: float = 15
		while d <= ahead:
			mark(w.pos + w.dir * d, victim, false)
			d += 15
	for r: LiteRegion in map.regions:
		if r.city:
			_threat[r.id] = _threat[r.id] or _threat[r.parent]
			_bal[r.id] = _bal[r.id] or _bal[r.parent]
	for i: int in alert.size():
		var side: int = map.regions[i].side
		if _bal[i]:
			ballistic[i] = true
			_bal_quiet[i] = 0
		elif ballistic[i]:
			_bal_quiet[i] += dt
			if _bal_quiet[i] >= 2.0: ballistic[i] = false
		if _threat[i]:
			_quiet[i] = 0
			if not alert[i]:
				alert[i] = true
				alert_since[i] = time
				var was: int = alerted[side]
				alerted[side] += 1
				if was == 0:
					side_alert_since[side] = time
					events.append(LiteEvent.new(LiteEv.RAID_ALERT, side, i))
		elif alert[i]:
			_quiet[i] += dt
			if _quiet[i] >= LiteRules.ALL_CLEAR_AFTER:
				alert[i] = false
				ballistic[i] = false
				alerted[side] -= 1
				if alerted[side] == 0:
					side_quiet_since[side] = time
					events.append(LiteEvent.new(LiteEv.ALL_CLEAR, side, 0, Vector2.ZERO, 0, 0, time - side_alert_since[side]))


func mark(p: Vector2, victim: int, ballistic: bool) -> void:
	var id: int = map.region_at(p)
	if id == LiteMap.NONE or map.regions[id].side != victim: return
	_threat[id] = true
	if ballistic: _bal[id] = true
