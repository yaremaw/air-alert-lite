class_name LiteSim
extends RefCounted

const _FLOAT_MAX: float = 3.4028235e+38

class Pending:
	var at: float
	var side: int
	var arm: int
	var target: Vector2
	var raid: LiteRaid

	var route: Array[Vector2]

	func _init(p_at: float, p_side: int, p_arm: int, p_target: Vector2, p_raid: LiteRaid, p_route: Array[Vector2]) -> void:
		at = p_at
		side = p_side
		arm = p_arm
		target = p_target
		raid = p_raid
		route = p_route

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
## How much more often each side's SAMs hit: more while it has a radar.
var sam_bonus: Array[float] = [1.0, 1.0]
## Until when no drones can be launched (a storm), in game time.
var grounded_until: float = -1.0
## The time of day and the weather, and what they do to the war (LiteEnv).
var env: LiteEnv = null
var _was_grounded: bool = false
## Time gathered for the slow parts of a step (production, morale).
var _slow: float = 0.0
## Until when each side's SAMs cannot fire (an outage), in game time.
var sam_off_until: Array[float] = [-1.0, -1.0]
## Until when each side's radars near a lost substation run short of power,
## and where it was (see LiteSense.sees).
var grid_off_until: Array[float] = [-1.0, -1.0]
var grid_off_at: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
## Phase 4 off (tests and balance runs that want the old war): every enemy
## weapon seen, no stockpiles, no morale. Static so a run can set it first.
static var classic_rules: bool = false
var income_scale: Array[float] = [1.0, 1.0]
## Which weapons each side has (drones, cruise, ballistic): all of them in a
## war; in a campaign's first operations only some (see LiteCampaign.setup).
var arms: Array = [[true, true, true], [true, true, true]]

func has_arm(side: int, arm: int) -> bool:
	return bool(arms[side][arm])
var time: float = 0.0
var winner: int = -1
## Hits on the capitals' cities, [side, where, damage], for the view to
## take (see LiteCmdView._update_cities); kept short.
var capital_hits: Array = []

var alert: Array[bool] = []
var ballistic: Array[bool] = []
## Regions under missile threat (cruise or ballistic): shown red.
var missile: Array[bool] = []
var alert_since: PackedFloat32Array = PackedFloat32Array()
var region_flash: PackedFloat32Array = PackedFloat32Array()
var alerted: Array[int] = [0, 0]
var side_alert_since: Array[float] = [0.0, 0.0]
var side_quiet_since: Array[float] = [0.0, 0.0]
var _quiet: PackedFloat32Array = PackedFloat32Array()
var _bal_quiet: PackedFloat32Array = PackedFloat32Array()
var _threat: Array[bool] = []
## Alerts district by district (the war map's districts, see LiteMap.sub),
## for the map to show where drones and missiles really are: a district under
## threat is shown under alert, the rest of its province not. Display only:
## sirens, sheltering factories and the statistics go by the province
## (`alert`). 0 no alert, 1 drones, 2 missiles; empty on a map without
## districts.
var sub_alert: PackedByteArray = PackedByteArray()
var _sub_threat: PackedByteArray = PackedByteArray()
var _sub_quiet: PackedFloat32Array = PackedFloat32Array()
var _bal: Array[bool] = []
var _mis: Array[bool] = []

var stats: LiteStats = LiteStats.new()

var _rng: RandomNumberGenerator
var _queue: Array[Pending] = []
var _tmp: Array[LiteRegion] = []
var _ids: int = 0
var _raids: int = 0
var _alert_tick: float = 0.0
## Spotting (weapons seen by the other side, buildings seen from the air)
## is checked ten times a second rather than every step: it scans every
## weapon against every building, and a tenth of a second is never noticed.
var _spot_tick: float = 0.0

var slots: PackedInt32Array = PackedInt32Array()
var _ruins: Array[Ruin] = []
var _shift: float = LiteRules.INDUSTRY_SHIFT
var _intel: float = LiteRules.INTEL_EVERY

func _init(p_map: LiteMap, seed: int) -> void:
	map = p_map
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed * 7919 + 13
	env = LiteEnv.new(seed)
	env.climate = LiteBiome.dominant(map)
	var n: int = map.regions.size()
	alert.resize(n); alert.fill(false)
	ballistic.resize(n); ballistic.fill(false)
	missile.resize(n); missile.fill(false)
	_mis.resize(n); _mis.fill(false)
	alert_since.resize(n)
	region_flash.resize(n)
	_quiet.resize(n); _bal_quiet.resize(n)
	_threat.resize(n); _threat.fill(false)
	_bal.resize(n); _bal.fill(false)
	if map.sub.size() == LiteMap.W * LiteMap.H:
		sub_alert.resize(256)
		_sub_threat.resize(256)
		_sub_quiet.resize(256)
	slots.resize(n)
	stats.setup(map)
	if classic_rules:
		for sd: LiteSide in sides:
			sd.morale_on = false
	for s: int in 2: init_slots(s)
	even_slots()
	for s: int in 2: setup(s)
	for b: LiteBuilding in buildings:
		if b.kind == LiteKind.FACTORY: slots[b.region] = maxi(slots[b.region], factories_in(b.region))

func _next(n: int) -> int:
	return _rng.randi_range(0, n - 1) if n > 0 else 0

func setup(side: int) -> void:
	var cap: LiteBuilding = add(side, LiteKind.CAPITAL, map.capital[side], true)
	sides[side].capital = cap
	cap.seen[1 - side] = true
	var sam: Variant = find_spot(side, map.capital[side], 44, 56)
	if sam != null: add(side, LiteKind.SAM, sam, true)
	# A long-range radar by the capital: the start of its air defence network.
	if not classic_rules:
		var radar: Variant = find_spot(side, map.capital[side], 46, 64)
		if radar != null: add(side, LiteKind.RADAR, radar, true)

	# On an operation's map the land is narrow: the factories go to the
	# districts deepest behind the front instead of round the command.
	var deep: Array[LiteRegion] = []
	if not map.focus.is_empty():
		deep = _deepest(side)
	for i: int in 2:
		var factory: Variant = find_spot(side, map.capital[side], 55 + 40 * i, 110 + 50 * i)
		if i < deep.size():
			for t: int in 30:
				var q: Vector2 = deep[i].spots[_next(deep[i].spots.size())]
				if can_place(side, q):
					factory = q
					break
		if factory == null: continue
		add(side, LiteKind.FACTORY, factory, true)
		var gun: Variant = find_spot(side, factory, 19, 30) if i == 0 else null
		if gun != null: add(side, LiteKind.GUN, gun, true)
	if not classic_rules:
		# A refinery to start the economy with, deep in the country.
		var rp: Variant = null
		if not deep.is_empty():
			for t: int in 30:
				var q: Vector2 = deep[0].spots[_next(deep[0].spots.size())]
				if can_place(side, q):
					rp = q
					break
		if rp == null:
			rp = find_spot(side, map.capital[side], 48, 100)
		if rp != null:
			add(side, LiteKind.REFINERY, rp, true)

## A country's working sites where its land suits them (see LiteBiome): an
## oil field and a refinery in the desert, a substation in the cold north,
## a pumping station in the wetlands, grain silos on the steppe and plains.
## Not on an operation's map (it shows one province).
func _works(side: int) -> void:
	if not map.focus.is_empty():
		return
	var by_biome: Dictionary = {}
	for r: LiteRegion in map.regions:
		if r.side != side or r.city or r.spots.is_empty():
			continue
		for i: int in range(0, r.spots.size(), 5):
			var q: Vector2 = r.spots[i]
			var bi: int = LiteBiome.at(map, q)
			if not by_biome.has(bi):
				by_biome[bi] = []
			by_biome[bi].append(q)
	var placed: int = 0
	var order: Array[int] = [LiteBiome.DESERT, LiteBiome.WINTER, LiteBiome.WETLANDS, LiteBiome.STEPPE, LiteBiome.PLAINS]
	for bi: int in order:
		if not by_biome.has(bi) or placed >= 4:
			continue
		var spots: Array = by_biome[bi]
		# Only where the biome is a real part of the country, not a corner.
		if spots.size() < 6:
			continue
		var kinds: Array[int] = LiteBiome.works(bi)
		var first: Variant = null
		for k: int in kinds:
			if placed >= 4:
				break
			for t: int in 24:
				var q: Vector2 = spots[_next(spots.size())]
				if first != null and q.distance_to(first) > 70.0:
					continue
				if can_place(side, q):
					var b: LiteBuilding = add(side, k, q, true)
					if first == null:
						first = q
					placed += 1
					break

## The regions of `side` furthest from the other side's land, deepest first.
func _deepest(side: int) -> Array[LiteRegion]:
	var mine: Array[LiteRegion] = []
	var theirs: Array[Vector2] = []
	for r: LiteRegion in map.regions:
		if r.side == side and not r.city and r.spots.size() > 0:
			mine.append(r)
		elif r.side != side:
			theirs.append(r.label)
	var depth: Dictionary = {}
	for r: LiteRegion in mine:
		var d: float = INF
		for q: Vector2 in theirs:
			d = minf(d, r.label.distance_to(q))
		depth[r] = d
	mine.sort_custom(func(a: LiteRegion, b: LiteRegion) -> bool: return depth[a] > depth[b])
	return mine

## Sites of `side` in province `id`, alive or not yet built.
func sites_in(side: int, id: int, kind: int = -1) -> Array[LiteBuilding]:
	var out: Array[LiteBuilding] = []
	for b: LiteBuilding in buildings:
		if b.alive and b.side == side and map.province(b.region) == id and (kind < 0 or b.kind == kind):
			out.append(b)
	return out

## Hands province `id` to `to`: the old owner's sites there are lost, and any
## alert over it is called off first, so the alert counts of both sides stay true.
func hand_over(id: int, to: int) -> void:
	for r: LiteRegion in map.regions:
		if map.province(r.id) != id or not alert[r.id]:
			continue
		alert[r.id] = false
		ballistic[r.id] = false
		missile[r.id] = false
		alerted[r.side] = maxi(0, alerted[r.side] - 1)
	clear_province(id, 1 - to)
	map.give(id, to)
	_front = [PackedFloat32Array(), PackedFloat32Array()]

## When a province changes hands, the sites the old owner had there are lost:
## blown up where they stand, without the news a strike would make.
func clear_province(id: int, side: int) -> int:
	var n: int = 0
	for b: LiteBuilding in sites_in(side, id):
		b.alive = false
		b.dead_at = time
		fx.append(LiteFx.new(LiteFxKind.BLAST, b.pos, Vector2.ZERO, 0, 0.9, 15.0, 1 - side))
		fx.append(LiteFx.new(LiteFxKind.SCORCH, b.pos, Vector2.ZERO, 0, 40.0, 15.0, 1 - side))
		n += 1
	return n

func can_place(side: int, p: Vector2) -> bool:
	if map.side_at(p) != side: return false
	# Not on a town or a city (a site's half width clear of it).
	if map.in_town(p, 4.0): return false
	for a: int in 4:
		if map.side_at(p + Vector2(5, 0).rotated(a * PI / 2)) != side: return false
	# Far enough apart that their frames on the map don't cover each other
	# (a capital's frame is bigger).
	for b: LiteBuilding in buildings:
		if b.alive and b.pos.distance_to(p) < (LiteRules.SITE_GAP_CAPITAL if b.kind == LiteKind.CAPITAL else LiteRules.SITE_GAP): return false
	return true

func cost(side: int, kind: int) -> int:
	var c: int = LiteRules.cost_kind(kind)
	if kind == LiteKind.FACTORY or kind == LiteKind.REFINERY:
		# Each one dearer than the last.
		for b: LiteBuilding in buildings:
			if b.alive and b.side == side and b.kind == kind: c += LiteRules.FACTORY_STEP if kind == LiteKind.FACTORY else 30
	return c

## What building `kind` at `p` costs: dearer on wet ground (phase 4: the
## wetlands, LiteBiome).
func cost_at(side: int, kind: int, p: Vector2) -> int:
	var c: int = cost(side, kind)
	if not classic_rules and LiteBiome.at(map, p) == LiteBiome.WETLANDS:
		c = ceili(c * 1.2)
	return c

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

func build_factory(side: int, region: int) -> LiteBuilding:
	if region < 0 or region >= map.regions.size() or map.regions[region].side != side or free_slots(region) <= 0: return null
	var c: int = cost(side, LiteKind.FACTORY)
	if sides[side].money < c: return null
	var p: Variant = factory_spot(side, region)
	if p == null: return null
	sides[side].money -= c
	return add(side, LiteKind.FACTORY, p, false)

## Rebuilding a ruined factory where it stood: dearer and slower than a new
## one (LiteStock.REBUILD_*), and the ruin is cleared.
func rebuild_cost(side: int) -> int:
	return ceili(cost(side, LiteKind.FACTORY) * LiteStock.REBUILD_PRICE_K)

func rebuild_factory(side: int, region: int) -> LiteBuilding:
	if region < 0 or region >= map.regions.size() or map.regions[region].side != side or ruins_in(region) <= 0:
		return null
	var c: int = rebuild_cost(side)
	if sides[side].money < c:
		return null
	var p: Variant = factory_spot(side, region)
	if p == null:
		return null
	for i: int in _ruins.size():
		if _ruins[i].region == region:
			_ruins.remove_at(i)
			break
	sides[side].money -= c
	var b: LiteBuilding = add(side, LiteKind.FACTORY, p, false)
	b.build_total *= LiteStock.REBUILD_TIME_K
	b.build = b.build_total
	return b

## Whether a factory of `side` would fit anywhere in `region` now.
func has_factory_room(side: int, region: int) -> bool:
	for q: Vector2 in map.regions[region].spots:
		if can_place(side, q): return true
	return false

## Where a factory of `side` would go in `region`: of all the free ground
## there, the spot furthest from the enemy's land (the region's safe side),
## with a little spread so they don't all line one edge. Null if none is free.
func factory_spot(side: int, region: int) -> Variant:
	var best: Variant = null
	var bd: float = -_FLOAT_MAX
	for q: Vector2 in map.regions[region].spots:
		if not can_place(side, q): continue
		var d: float = front_distance(side, q) + _rng.randf() * 8.0
		if d > bd:
			bd = d
			best = q
	return best

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
	if not LiteKind.BUILT.has(kind): return null
	var c: int = cost_at(side, kind, p)
	if sides[side].money < c or not can_place(side, p): return null
	sides[side].money -= c
	return add(side, kind, p, false)

## What a campaign's upgrades change, per side (see LiteCampaign.UPGRADES):
## money off each weapon, interceptors a SAM site holds, how fast SAMs
## reload (a factor on the time), and hits a factory takes on top.
var arm_off: Array = [[0, 0, 0], [0, 0, 0]]
## Phase 4c: each side's one kind of AA gun (the toolbar's gun slot): the
## gun truck early in a campaign, the armoured AA gun once it arrives; and
## the kinds a side cannot build yet (a campaign's SAMs before its second
## operation).
var gun_kind: Array[int] = [LiteKind.GUN, LiteKind.GUN]
## Whether each side's attack drones are jets now (phase 4d).
var jet_drones: Array[bool] = [false, false]
## Whether a side may use the bomb (a campaign's last operation, once every
## other region is taken), and the next ballistic missile launched carries it.
var nuke_ready: Array[bool] = [false, false]
var _nuke_next: bool = false
## How far the bomb destroys everything, and damages beyond.
const NUKE_R: float = 120.0

## The bomb: one ballistic missile from the capital at `target`.
func nuke(side: int, target: Vector2) -> void:
	nuke_ready[side] = false
	_nuke_next = true
	fire_from(side, LiteArm.BALLISTIC, sides[side].capital.pos, target, 1)
var no_build: Array = [[], []]

## Whether `side` may build `kind` now.
func may_build(side: int, kind: int) -> bool:
	return not (no_build[side] as Array).has(kind)
## How much faster each side's drone lines work (the war council's drone
## workshops; launching is free under phase 4, so they no longer cut a price).
var drone_rate: Array[float] = [0.0, 0.0]
var rack: Array[int] = [LiteRules.SAM_RACK, LiteRules.SAM_RACK]
var reload_mul: Array[float] = [1.0, 1.0]
var factory_hp: Array[float] = [0.0, 0.0]

## What launching one weapon costs `side` in money: its price, and (phase 4)
## more while it keeps launching hard (strain, see LiteStock). It must be in
## the stockpile too (in_stock).
func arm_cost(side: int, arm: int) -> int:
	return 0 if not classic_rules else maxi(1, ceili(launch_price(side, arm)))

func launch_price(side: int, arm: int) -> float:
	if not classic_rules:
		# Weapons come from the factories' stockpiles: launching is free.
		return 0.0
	return float(maxi(1, LiteRules.cost(arm) - int(arm_off[side][arm])))

## How many of `arm` `side` has ready to launch (its stockpile).
func in_stock(side: int, arm: int) -> int:
	if classic_rules:
		return 9999
	return int(sides[side].stock[arm] + 0.001)

func add(side: int, kind: int, p: Vector2, instant: bool) -> LiteBuilding:
	var b:= LiteBuilding.new()
	_ids += 1
	b.id = _ids
	b.side = side
	b.kind = kind
	b.pos = p
	b.region = map.region_at(p)
	b.max_hp = LiteRules.max_hp(kind) + (factory_hp[side] if kind == LiteKind.FACTORY else 0.0)
	b.build_total = LiteRules.build_time(kind)
	b.ammo = rack[side] if kind == LiteKind.SAM else (LiteRules.GUN_MAG if kind == LiteKind.GUN or kind == LiteKind.CAPITAL else (LiteRules.MOBILE_MAG if kind == LiteKind.MOBILE else 0))
	b.hp = b.max_hp
	b.biome = LiteBiome.at(map, p) if not classic_rules else LiteBiome.PLAINS
	b.winter = b.biome == LiteBiome.WINTER
	if kind == LiteKind.FACTORY:
		b.line = LiteStock.next_line(self, side)
	b.build = 0.0 if instant else b.build_total
	b.seen[side] = true
	buildings.append(b)
	return b

func strike(side: int, arm: int, target: Vector2, count: int, raid: LiteRaid = null, delay: float = 0.0, route: Array[Vector2] = []) -> LiteRaid:
	if not classic_rules:
		# Only what is in the stockpile goes.
		count = mini(count, in_stock(side, arm))
	var c: int = arm_cost(side, arm) * count
	if count <= 0 or sides[side].money < c or not has_arm(side, arm): return null
	if arm == LiteArm.DRONE and (time < grounded_until or env.drones_grounded()): return null
	sides[side].money -= c
	if not classic_rules:
		sides[side].stock[arm] -= count
		sides[side].strain += LiteStock.STRAIN[arm] * count
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

## Ground the driving guns keep off: the capitals' cities, the towns at the
## regions' names, every standing site; [centre, radius squared], worked out
## every two seconds.
var _keep_off: Array = []
var _keep_off_at: float = -99.0

func _refresh_keep_off() -> void:
	_keep_off_at = time
	_keep_off.clear()
	for s: int in 2:
		if map.capital[s] != Vector2.ZERO:
			_keep_off.append([map.capital[s], 42.0 * 42.0])
	for t: Array in map.built_up():
		_keep_off.append([t[0], float(t[1]) * float(t[1])])
	for b: LiteBuilding in buildings:
		if b.alive and not (b.kind == LiteKind.GUN or b.kind == LiteKind.MOBILE or b.kind == LiteKind.UNIT or b.kind == LiteKind.CAPITAL):
			_keep_off.append([b.pos, 13.0 * 13.0])

## Whether a driving gun may not go to `p` (see _keep_off).
func blocked(p: Vector2) -> bool:
	for k: Array in _keep_off:
		if p.distance_squared_to(k[0]) < float(k[1]):
			return true
	return false

## An AA gun escorting a unit on the move: beside it, a little behind, at
## its pace; once the unit is gone it stays where it is and guards that.
func _escort(b: LiteBuilding, dt: float) -> void:
	var l: LiteBuilding = b.leader
	if not l.alive:
		b.leader = null
		b.home = map.region_at(b.pos)
		b.goal = b.pos
		return
	var want: Vector2 = l.pos + Vector2(-7.0, 5.0 * b.gap).rotated(l.heading)
	var to: Vector2 = want - b.pos
	var d: float = to.length()
	if d > 0.3:
		var step: float = minf(d, maxf(l.pace * 1.3, 3.0) * dt)
		b.pos += to / d * step
		b.heading = lerp_angle(b.heading, to.angle(), minf(1.0, dt * 3.0))
		b.pace = step / maxf(dt, 0.0001)
	else:
		b.pace = 0.0
	var reg: int = map.region_at(b.pos)
	if reg != LiteMap.NONE:
		b.region = reg

## Weapons fired from a given place (a mobile launcher), at no cost from
## the stockpile: the operation set it out with its own rounds.
func fire_from(side: int, arm: int, from: Vector2, target: Vector2, count: int) -> void:
	var raid:= LiteRaid.new()
	_raids += 1
	raid.id = _raids
	raid.side = side
	raid.target = target
	raid.total += count
	raid.by_arm[arm] += count
	var route: Array[Vector2] = [from]
	for i: int in count:
		_queue.append(Pending.new(time + i * 0.5, side, arm, target, raid, route))

## Enemy forces on the move (LiteUnit): along their routes at their pace,
## halting now and then; a train's wagons behind their engine; a mobile
## launcher firing from cover and moving on. A column or a train is tracked
## (seen) all the way; a launcher only while a salvo gives it away or our
## drones are over it.
func _move_units(dt: float) -> void:
	for b: LiteBuilding in buildings:
		if not b.alive or b.kind != LiteKind.UNIT:
			continue
		if b.wait > 0.0:
			b.wait -= dt
		elif b.leader != null:
			if b.leader.alive:
				b.dist = maxf(0.0, b.leader.dist - b.gap)
		elif not b.arrived and b.route.size() >= 2:
			b.dist += b.pace * dt
			if not b.halts.is_empty() and b.dist >= b.halts[0]:
				b.halts.remove_at(0)
				b.wait = _rng.randf_range(4.0, 9.0) * (2.2 if b.unit == LiteUnit.LOCO else 1.0)
			if b.dist >= b.route_len:
				b.dist = b.route_len
				b.arrived = true
		if b.route.size() >= 2:
			var at: Array = LiteUnit.along(b.route, b.dist)
			var np: Vector2 = at[0]
			if np.distance_squared_to(b.pos) > 0.0001:
				b.heading = (at[1] as Vector2).angle()
			b.pos = np
			var reg: int = map.region_at(np)
			if reg != LiteMap.NONE:
				b.region = reg
		var v: int = 1 - b.side
		if b.unit == LiteUnit.LAUNCHER:
			_launcher(b)
		else:
			b.seen[v] = true

func _launcher(b: LiteBuilding) -> void:
	var v: int = 1 - b.side
	var over: bool = false
	for w: LiteWeapon in weapons:
		if w.alive and w.side == v and w.arm == LiteArm.DRONE and w.pos.distance_to(b.pos) < 24.0:
			over = true
			break
	if time < b.reveal_until or over:
		b.seen[v] = true
		b.seen_pos = b.pos
	else:
		b.seen[v] = false
	if not b.arrived and b.route.size() >= 2:
		return
	if b.scoot_at > 0.0 and time >= b.scoot_at:
		# Moving on to a new hide.
		b.scoot_at = -1.0
		var hide: Variant = find_spot(b.side, b.pos, 26, 55)
		if hide != null:
			b.route = LiteUnit.road(map, b.pos, hide, _rng, 4.0)
			b.route_len = LiteUnit.length(b.route)
			b.dist = 0.0
			b.arrived = false
			b.pace = 6.5
		b.fire_at = time + b.route_len / maxf(1.0, b.pace) + _rng.randf_range(38.0, 60.0)
		return
	if b.scoot_at < 0.0 and time >= b.fire_at:
		# A salvo at our nearest site (or our command).
		var target: Vector2 = sides[v].capital.pos
		var bd: float = _FLOAT_MAX
		for o: LiteBuilding in buildings:
			if o.alive and o.side == v and o.kind != LiteKind.UNIT:
				var d: float = o.pos.distance_squared_to(b.pos)
				if d < bd:
					bd = d
					target = o.pos
		var arm: int = LiteArm.CRUISE if has_arm(b.side, LiteArm.CRUISE) else LiteArm.DRONE
		fire_from(b.side, arm, b.pos, target, 2 if arm == LiteArm.CRUISE else 3)
		b.salvos += 1
		b.reveal_until = time + 40.0
		b.seen_pos = b.pos
		b.scoot_at = time + 34.0

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
	if _tmp.is_empty():
		return sides[side].capital.pos
	var pick: LiteRegion = _tmp[rng.randi_range(0, _tmp.size() - 1)]
	return pick.spots[rng.randi_range(0, pick.spots.size() - 1)]

func known_coverage(viewer: int, p: Vector2) -> float:
	var c: float = 0
	for b: LiteBuilding in buildings:
		if b.alive and b.side != viewer and (b.is_ad or b.is_gun) and b.seen[viewer] and b.pos.distance_to(p) <= ad_range(b):
			c += _weight(b)
	return c

func coverage(side: int, p: Vector2) -> float:
	var c: float = 0
	for b: LiteBuilding in buildings:
		if b.alive and b.side == side and b.is_ad and b.pos.distance_to(p) <= ad_range(b):
			c += _weight(b)
	return c

## What a site counts for in a place's cover: a SAM two, a gun one and a
## half (they hit hard now), a mobile unit one.
static func _weight(b: LiteBuilding) -> float:
	match b.kind:
		LiteKind.SAM: return 2.0
		LiteKind.GUN: return 1.5
		_: return 1.0

## How far an air defence site reaches now: a SAM without a radar's picture
## less far (LiteRules.SAM_ALONE_RANGE); guns less far in fog.
func ad_range(b: LiteBuilding) -> float:
	var r: float = LiteRules.range(b.kind)
	if classic_rules:
		return r
	if b.kind == LiteKind.SAM and not b.linked:
		r *= LiteRules.SAM_ALONE_RANGE
	if b.kind == LiteKind.GUN or b.kind == LiteKind.CAPITAL:
		r *= env.gun_range()
	return r

## How often an air defence site hits weapon `w` with a shot now: by what it
## is, its radar link, the night and the weather.
func ad_pk(b: LiteBuilding, w: LiteWeapon) -> float:
	return _ad_pk(b, w) * (LiteRules.JET_PK if w.jet else 1.0)

func _ad_pk(b: LiteBuilding, w: LiteWeapon) -> float:
	match b.kind:
		LiteKind.SAM:
			var k: float = LiteRules.sam_pk(w.arm) * sam_bonus[b.side]
			if not classic_rules:
				k *= LiteRules.SAM_LINK_PK * env.sam_linked_factor() if b.linked else LiteRules.SAM_ALONE_PK * env.sam_alone_factor()
			return minf(0.97, k)
		LiteKind.MOBILE:
			return minf(0.95, LiteRules.mobile_pk(w.arm) * (LiteRules.MOBILE_LINK_PK if b.linked else 1.0) * env.thermal_factor())
		_:
			var k: float = LiteRules.gun_pk(w.arm) * env.gun_factor()
			if not classic_rules:
				k *= LiteRules.GUN_LINK_PK if b.linked else LiteRules.GUN_ALONE_PK
				# A stream from the rotary cannon: shorter and more often.
				k *= LiteRules.MINIGUN_INTERVAL / LiteRules.GUN_INTERVAL
			return minf(0.95, k)

func step(dt: float) -> void:
	if winner >= 0:
		step_fx(dt)
		return
	time += dt
	var tq: float = LitePerf.now
	env.step(time, dt)
	_storm_check()
	economy(dt)
	if not classic_rules:
		_slow += dt
		if _slow >= 0.25:
			LiteStock.step(self, _slow)
			LiteMorale.step(self, _slow)
			_slow = 0.0
		for s: int in 2:
			if sides[s].morale <= 0.0 and winner < 0 and sides[s].morale_on:
				# Its people will not go on: the war is lost.
				winner = 1 - s
				events.append(LiteEvent.new(LiteEv.MORALE, s, 0, Vector2.ZERO, 0, 0, 0.0))
				events.append(LiteEvent.new(LiteEv.GAME_OVER, 1 - s))
				return
	LitePerf.add("sim env+economy", tq)
	tq = LitePerf.now
	var grounded: bool = env.drones_grounded()
	for i: int in range(_queue.size() - 1, -1, -1):
		if _queue[i].at <= time:
			var p: Pending = _queue[i]
			# In a storm, drones wait on the ground for it to pass.
			if grounded and p.arm == LiteArm.DRONE:
				p.at = time + 1.0
				continue
			_queue.remove_at(i)
			launch(p)
	LitePerf.add("sim launch", tq)
	tq = LitePerf.now
	move_weapons(dt)
	LitePerf.add("sim move weapons", tq)
	tq = LitePerf.now
	if not classic_rules:
		_move_mobiles(dt)
	_move_units(dt)
	LitePerf.add("sim mobiles", tq)
	tq = LitePerf.now
	_spot_tick -= dt
	var spotting: bool = _spot_tick <= 0
	if spotting:
		_spot_tick += 0.1
		if classic_rules:
			detect()
		else:
			LiteSense.link(self)
			LiteSense.detect(self)
	LitePerf.add("sim sense", tq)
	tq = LitePerf.now
	air_defence(dt)
	LitePerf.add("sim air defence", tq)
	tq = LitePerf.now
	move_interceptors(dt)
	if spotting:
		reveal()
	LitePerf.add("sim interceptors+reveal", tq)
	tq = LitePerf.now
	_alert_tick -= dt
	if _alert_tick <= 0:
		_alert_tick += 0.25
		alerts(0.25)
		var report: LiteReport = stats.tick(self, 0.25)
		if report != null:
			events.append(LiteEvent.new(LiteEv.REPORT, 1, 0, Vector2.ZERO, 0, 0, stats.reports.size() - 1))
	LitePerf.add("sim alerts+stats", tq)
	tq = LitePerf.now

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
	LitePerf.add("sim rest", tq)
	tq = LitePerf.now
	if ai[0] != null: ai[0].tick(self, dt)
	if ai[1] != null: ai[1].tick(self, dt)
	LitePerf.add("sim ai", tq)
	tq = LitePerf.now
	step_fx(dt)
	LitePerf.add("sim fx", tq)

	k = 0
	for b: LiteBuilding in buildings:
		if not (not b.alive and time - b.dead_at > 30):
			buildings[k] = b
			k += 1
	buildings.resize(k)

	k = 0
	for w: LiteWeapon in weapons:
		if w.alive:
			weapons[k] = w
			k += 1
	weapons.resize(k)

	k = 0
	for it: LiteInterceptor in interceptors:
		if it.alive:
			interceptors[k] = it
			k += 1
	interceptors.resize(k)

func step_fx(dt: float) -> void:
	for f: LiteFx in fx: f.age += dt

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
	var radar: Array[bool] = [false, false]
	for side: LiteSide in sides:
		var income: float = LiteRules.CAPITAL_INCOME if side.capital.alive else 0.0
		var work: float = 0
		var works: float = 0
		for b: LiteBuilding in buildings:
			if b.side != side.index or not b.alive: continue
			if not b.ready:
				b.build -= dt
				if b.ready:
					events.append(LiteEvent.new(LiteEv.BUILT, b.side, b.region, b.pos, 0, b.kind))
					LiteSense.relink()
				continue
			if b.kind == LiteKind.FACTORY:
				if classic_rules:
					work += (0.4 + 0.6 * b.hp / b.max_hp) * (LiteRules.ALERT_WORK if alert[b.region] else 1.0)
				else:
					work += LiteStock.CONDITION_K[b.condition] * (LiteStock.REPAIRING_K if b.repairing > 0.0 else 1.0) * (LiteRules.ALERT_WORK if alert[b.region] else 1.0)
			elif b.kind == LiteKind.RADAR:
				radar[side.index] = true
			elif b.kind == LiteKind.REFINERY and not classic_rules:
				works += LiteRules.REFINERY_INCOME * LiteStock.CONDITION_K[b.condition] * (LiteRules.ALERT_WORK if alert[b.region] else 1.0)
			elif LiteKind.is_works(b.kind):
				works += LiteBiome.income(b.kind) * LiteStock.CONDITION_K[b.condition]
		var eff: float = 1.0 if classic_rules else LiteMorale.efficiency(side.morale)
		var per: float = LiteRules.FACTORY_INCOME if classic_rules else LiteRules.FACTORY_INCOME_P4
		side.income = (income + per * work + works) * income_scale[side.index] * eff
		side.money += side.income * dt
		var cap: LiteBuilding = side.capital
		side.repair = minf(LiteRules.MAX_REPAIR, LiteRules.CAPITAL_REPAIR * work) if cap.alive and cap.hp < cap.max_hp else 0.0
		if side.repair > 0: cap.hp = minf(cap.max_hp, cap.hp + side.repair * dt)
	# The old rule (a radar anywhere: every SAM better) under the old rules
	# only; now a radar helps the air defence it links (LiteSense).
	for s: int in 2:
		sam_bonus[s] = (LiteRules.RADAR_PK if radar[s] else 1.0) if classic_rules else 1.0

func launch(p: Pending) -> void:
	var arm: int = p.arm
	var spread: float = LiteRules.scatter(arm) * (env.scatter() if arm == LiteArm.DRONE else 1.0)
	var target: Vector2 = p.target + Vector2(spread * sqrt(_rng.randf()), 0).rotated(_rng.randf() * TAU)
	var route: Array[Vector2] = p.route
	if arm == LiteArm.BALLISTIC: route = []
	var start: Vector2 = origin_near(p.side, route[0]) if route.size() > 0 else origin(p.side, arm, target)
	var w:= LiteWeapon.new()
	_ids += 1
	w.id = _ids
	w.side = p.side
	w.arm = arm
	w.raid = p.raid
	w.start = start
	w.pos = start
	w.target = target
	w.speed = LiteRules.speed(arm) * (0.94 + 0.12 * _rng.randf())
	if arm == LiteArm.DRONE: w.speed *= env.drone_pace()
	if arm == LiteArm.DRONE and jet_drones[p.side] and not (p.raid != null and p.raid.scout):
		w.jet = true
		w.speed *= LiteRules.JET_SPEED
	w.seen[p.side] = true
	if arm == LiteArm.BALLISTIC:
		w.seen[1 - p.side] = true
		w.ever_seen[1 - p.side] = true
		w.seen_at[1 - p.side] = time
	if classic_rules:
		# The old rules: everything over a side's land is seen (see detect).
		pass
	var near: float = 12
	for b: LiteBuilding in buildings:
		if not b.alive or b.side == p.side:
			continue
		var dd: float = b.pos.distance_to(p.target)
		# A unit on the move may have gone on since the strike was ordered:
		# the weapon still takes it as its target (and homes on it, see
		# move_weapons).
		if b.kind == LiteKind.UNIT:
			dd -= 20.0
		if dd < near:
			near = dd
			w.aim = b
	build_path(w, route)
	w.dir = (w.path[0] - start).normalized()
	if arm == LiteArm.BALLISTIC:
		w.setup_arc(map.land_rect.grow(6))
		if _nuke_next:
			_nuke_next = false
			w.nuke = true
			w.seen[1 - p.side] = true
	else:
		# Side by side with the others of its salvo: the middle lane first,
		# then one each side, further out.
		var k: int = p.raid.launched % 6
		w.lane = (0.0 if k == 0 else float((k + 1) / 2) * (1.0 if k % 2 == 1 else -1.0)) + _rng.randf_range(-0.3, 0.3)
		w.enter_lane()
	weapons.append(w)
	p.raid.launched += 1
	sides[p.side].launched += 1
	stats.on_launch(w, time)
	# `size` carries the arm, so the view can give a ballistic launch its own effect.
	fx.append(LiteFx.new(LiteFxKind.LAUNCH, start + w.off, Vector2.ZERO, 0, 0.7, arm, p.side))
	events.append(LiteEvent.new(LiteEv.LAUNCH, p.side, map.region_at(target), start, arm, 0, 0, p.raid))

# --- The no-launch band along the front --------------------------------------

## For each side, every FG-unit cell's distance to the other side's land;
## worked out when first needed, again when land changes hands.
var _front: Array = [PackedFloat32Array(), PackedFloat32Array()]
const FG: int = 4

## How far `p` is from the land of the side other than `side`, in map units.
func front_distance(side: int, p: Vector2) -> float:
	if (_front[side] as PackedFloat32Array).is_empty():
		_front[side] = _front_field(side)
	var f: PackedFloat32Array = _front[side]
	var gw: int = LiteMap.W / FG + 1
	var gh: int = LiteMap.H / FG + 1
	var x: int = clampi(int(p.x / FG), 0, gw - 1)
	var y: int = clampi(int(p.y / FG), 0, gh - 1)
	return f[y * gw + x]

## Whether `side` may launch from `p`: not in the band along the front.
func may_launch(side: int, p: Vector2) -> bool:
	return front_distance(side, p) >= LiteRules.LAUNCH_STANDOFF

## The distance field behind front_distance: a two-pass chamfer from every
## cell of the other side's land.
func _front_field(side: int) -> PackedFloat32Array:
	var gw: int = LiteMap.W / FG + 1
	var gh: int = LiteMap.H / FG + 1
	var f:= PackedFloat32Array()
	f.resize(gw * gh)
	const BIG: float = 1e9
	for y: int in gh:
		for x: int in gw:
			var mx: int = mini(x * FG + FG / 2, LiteMap.W - 1)
			var my: int = mini(y * FG + FG / 2, LiteMap.H - 1)
			var c: int = map.cell[my * LiteMap.W + mx]
			f[y * gw + x] = 0.0 if c != LiteMap.NONE and map.regions[c].side != side else BIG
	var a: float = float(FG)
	var d: float = a * 1.4142
	for y: int in gh:
		for x: int in gw:
			var i: int = y * gw + x
			var v: float = f[i]
			if x > 0: v = minf(v, f[i - 1] + a)
			if y > 0:
				v = minf(v, f[i - gw] + a)
				if x > 0: v = minf(v, f[i - gw - 1] + d)
				if x < gw - 1: v = minf(v, f[i - gw + 1] + d)
			f[i] = v
	for y: int in range(gh - 1, -1, -1):
		for x: int in range(gw - 1, -1, -1):
			var i: int = y * gw + x
			var v: float = f[i]
			if x < gw - 1: v = minf(v, f[i + 1] + a)
			if y < gh - 1:
				v = minf(v, f[i + gw] + a)
				if x < gw - 1: v = minf(v, f[i + gw + 1] + d)
				if x > 0: v = minf(v, f[i + gw - 1] + d)
			f[i] = v
	return f

func origin_near(side: int, at: Vector2) -> Vector2:
	var best: Vector2 = sides[side].capital.pos
	var bd: float = _FLOAT_MAX
	for r: LiteRegion in map.regions:
		if r.side != side or r.city: continue
		for i: int in range(0, r.spots.size(), 3):
			if not may_launch(side, r.spots[i]): continue
			var d: float = r.spots[i].distance_squared_to(at)
			if d < bd:
				bd = d
				best = r.spots[i]
	return best

func origin(side: int, arm: int, target: Vector2) -> Vector2:
	# Drones take off from the side's launch sites while it has any.
	if arm == LiteArm.DRONE:
		var sites: Array[LiteBuilding] = []
		for b: LiteBuilding in buildings:
			if b.alive and b.side == side and b.kind == LiteKind.LAUNCHER and b.ready:
				sites.append(b)
		if not sites.is_empty():
			return sites[_next(sites.size())].pos + Vector2(_r(-5, 5), _r(-5, 5))
	_tmp.clear()
	for r: LiteRegion in map.regions:
		if r.side == side and not r.city and r.spots.size() > 0: _tmp.append(r)
	_tmp.sort_custom(func(a: LiteRegion, b: LiteRegion) -> bool: return a.label.distance_squared_to(target) < b.label.distance_squared_to(target))
	var n: int = _tmp.size()
	# A side with no province left to launch from (a campaign can take them)
	# launches from its capital.
	if n == 0:
		return sides[side].capital.pos
	# Only provinces with ground clear of the band along the front.
	var clear: Array[LiteRegion] = []
	for r: LiteRegion in _tmp:
		for i: int in range(0, r.spots.size(), 4):
			if may_launch(side, r.spots[i]):
				clear.append(r)
				break
	if clear.is_empty():
		return sides[side].capital.pos
	n = clear.size()
	var pick: LiteRegion
	match arm:
		LiteArm.DRONE: pick = clear[_next(mini(3, n))]
		LiteArm.BALLISTIC: pick = clear[_next(mini(2, n))]
		_: pick = clear[n / 2 + _next(n - n / 2)]
	for k: int in 12:
		var p: Vector2 = pick.spots[_next(pick.spots.size())]
		if may_launch(side, p):
			return p
	for p: Vector2 in pick.spots:
		if may_launch(side, p):
			return p
	return sides[side].capital.pos

func _r(a: float, b: float) -> float:
	return a + _rng.randf() * (b - a)

func build_path(w: LiteWeapon, route: Array[Vector2]) -> void:
	var a: Vector2 = w.start
	var d: Vector2 = w.target - a
	var len: float = d.length()
	var n: Vector2 = Vector2(-d.y, d.x) / maxf(1.0, len)
	var ctrl: PackedVector2Array = PackedVector2Array([a])
	var turns: int = 0
	if route.size() > 0:
		var off:= Vector2(_r(-6, 6), _r(-6, 6))
		# Skips turning points next to the launcher or behind it, which would
		# bend the start of its flight into a hook.
		var first: int = 0
		var ahead: Vector2 = w.target - a
		while first < route.size():
			var to: Vector2 = route[first] + off - a
			if to.length() > 40.0 and to.dot(ahead) > 0.0 and to.angle_to(ahead) < 1.2 and to.angle_to(ahead) > -1.2:
				break
			first += 1
		for i: int in range(first, route.size()): ctrl.append(route[i] + off)
		turns = route.size() - first
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
	var ease: float = 1.0 - exp(-dt * 2.5)
	var jams: Array[LiteBuilding] = []
	for b: LiteBuilding in buildings:
		if b.alive and b.ready and b.kind == LiteKind.JAMMER:
			jams.append(b)
	for w: LiteWeapon in weapons:
		if not w.alive: continue
		if w.arm == LiteArm.DRONE and not w.jam_done and not jams.is_empty():
			for j: LiteBuilding in jams:
				if j.side != w.side and w.pos.distance_to(j.pos) < LiteRules.JAMMER_RANGE:
					w.jam_done = true
					if _rng.randf() < LiteRules.JAM_CHANCE:
						kill(w, j.side, j)
					break
			if not w.alive: continue
		var move: float = w.speed * dt * (LiteRules.ballistic_pace(w.progress) if w.arm == LiteArm.BALLISTIC else 1.0)
		w.flown += move
		w.steer_lane(ease)
		# On a unit on the move, while it is seen: homing on it once close.
		var mover: LiteBuilding = w.aim
		if mover != null and mover.alive and mover.kind == LiteKind.UNIT and w.arm != LiteArm.BALLISTIC and mover.seen[w.side]:
			if w.homing or w.pos.distance_to(mover.pos) < 70.0:
				if not w.homing:
					w.path.clear()
					w.path.append(mover.pos)
					w.leg = 0
					w.homing = true
					w.lane = 0.0
				w.target = mover.pos
				w.path[0] = mover.pos
		if w.homing:
			_home(w, move, dt)
		while move > 0 and w.leg < w.path.size() and not w.homing:
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

		if w.leg >= w.path.size():
			if w.recalled: land(w)
			else: impact(w)
		elif w.aim != null and not w.aim.alive and w.arm != LiteArm.BALLISTIC: retarget(w)

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
	# No other target near: it flies on along its route to where its own was.
	if next == null: return
	# A new target only changes where it steers: it keeps its place, heading
	# and speed, and turns towards it (see _home). Out of its salvo's lane too,
	# which would otherwise open out again with the target further away.
	w.target = next.pos
	w.path.clear()
	w.path.append(next.pos)
	w.leg = 0
	w.length = w.flown + w.pos.distance_to(next.pos)
	w.homing = true
	w.lane = 0.0

## A weapon homing on a new target, one step: it turns towards it by at most
## its turn rate, then flies `move` along its heading. Close to the target,
## inside its turning circle, it turns harder, so it closes in rather than
## circling it.
func _home(w: LiteWeapon, move: float, dt: float) -> void:
	var to: Vector2 = w.target - w.pos
	var d: float = to.length()
	if d <= move:
		w.pos = w.target
		w.leg = w.path.size()
		return
	var rate: float = w.turn_rate()
	var circle: float = 2.2 * w.speed / rate
	if d < circle * 0.5:
		# Close in: straight at it. Turning at any limited rate, it could go
		# round and round its target instead of reaching it.
		w.dir = to / d
	else:
		if d < circle:
			rate *= minf(4.0, circle / maxf(1.0, d))
		var turn: float = clampf(w.dir.angle_to(to / d), -rate * dt, rate * dt)
		w.dir = w.dir.rotated(turn)
	w.pos += w.dir * move
	w.length = w.flown + w.pos.distance_to(w.target)

## Each side's working air defence (its radars), gathered once per look round.
var _radars: Array[Array] = [[], []]

func detect() -> void:
	_radars[0].clear()
	_radars[1].clear()
	for b: LiteBuilding in buildings:
		if b.alive and b.is_ad and b.ready:
			_radars[b.side].append(b)
	for w: LiteWeapon in weapons:
		var v: int = 1 - w.side
		if not w.alive or w.seen[v]: continue
		var seen: bool = map.side_at(w.pos) == v
		if not seen:
			for b: LiteBuilding in _radars[v]:
				if b.pos.distance_to(w.pos) < LiteRules.range(b.kind) * 1.5:
					seen = true
					break
		if not seen: continue
		w.seen[v] = true
		events.append(LiteEvent.new(LiteEv.DETECTED, w.side, map.region_at(w.pos), w.pos, w.arm, 0, 0, w.raid))

func impact(w: LiteWeapon) -> void:
	if w.nuke:
		_nuke_impact(w)
		return
	w.alive = false
	var arm: int = w.arm
	var any: bool = false
	var lost_before: int = w.raid.destroyed.size()
	var capital_damage: float = 0.0
	for b: LiteBuilding in buildings:
		if not b.alive or b.side == w.side: continue
		var reach: float = LiteRules.blast(arm) * (0.6 if b.kind == LiteKind.UNIT else 1.0) + (6 if b.kind == LiteKind.CAPITAL else 0)
		if b.pos.distance_to(w.pos) > reach: continue
		any = true
		if b.kind == LiteKind.CAPITAL:
			capital_damage += LiteRules.damage(arm)
			# Where its city is hit (see LiteCmdCity): the view takes these.
			capital_hits.append([b.side, w.pos, LiteRules.damage(arm)])
			if capital_hits.size() > 64:
				capital_hits.pop_front()
			LiteMorale.change(self, b.side, LiteMorale.CAPITAL_HIT, LiteRules.damage(arm))
			LiteMorale.change(self, w.side, LiteMorale.STRUCK_CAPITAL)
		b.hp -= LiteRules.damage(arm)
		b.flash = 1
		if b.kind == LiteKind.CAPITAL and not classic_rules:
			# A capital never falls now: its country's morale decides the war.
			b.hp = maxf(1.0, b.hp)
		if b.kind == LiteKind.CAPITAL and b.hp > 0:
			events.append(LiteEvent.new(LiteEv.CAPITAL_HIT, b.side, 0, b.pos, arm, 0, b.hp))
		if b.hp <= 0: destroy(b, w.side, w.raid)
	if any:
		w.raid.hits += 1
		sides[w.side].hits += 1
	stats.on_impact(w, any, PackedStringArray(w.raid.destroyed.slice(lost_before)), capital_damage, time)
	var size: float = 11.0 if arm == LiteArm.DRONE else (15.0 if arm == LiteArm.CRUISE else 21.0)
	fx.append(LiteFx.new(LiteFxKind.BLAST, w.pos, Vector2.ZERO, 0, 0.9, size, w.side))
	fx.append(LiteFx.new(LiteFxKind.SCORCH, w.pos, Vector2.ZERO, 0, 40.0, size, w.side))
	var region: int = map.region_at(w.pos)
	if region != LiteMap.NONE:
		region_flash[region] = 1
		if map.regions[region].side != w.side:
			sides[1 - w.side].hit_log.append(LiteSide.Hit.new(w.pos, time))
			LiteMorale.change(self, 1 - w.side, LiteMorale.HIT, LiteRules.damage(arm))
	events.append(LiteEvent.new(LiteEv.HIT, w.side, region, w.pos, arm, 0, 1 if any else 0, w.raid))
	finish(w.raid)

## The bomb going off: everything of theirs within NUKE_R gone (their
## capital all but), damage twice as far, what flies there knocked out of
## the sky; the country's will broken; a light and a cloud (LiteFxKind.NUKE).
func _nuke_impact(w: LiteWeapon) -> void:
	w.alive = false
	var foe: int = 1 - w.side
	for b: LiteBuilding in buildings:
		if not b.alive or b.side != foe:
			continue
		var d: float = b.pos.distance_to(w.pos)
		if b.kind == LiteKind.CAPITAL:
			if d < NUKE_R * 1.5:
				b.hp = maxf(1.0, b.hp - b.max_hp * 0.9)
				b.flash = 1
				capital_hits.append([b.side, b.pos, 60.0])
			continue
		if d < NUKE_R:
			destroy(b, w.side, w.raid)
		elif d < NUKE_R * 2.0:
			b.hp -= b.max_hp * 0.6
			b.flash = 1
			if b.hp <= 0:
				destroy(b, w.side, w.raid)
	for x: LiteWeapon in weapons:
		if x.alive and x != w and x.pos.distance_to(w.pos) < NUKE_R:
			x.alive = false
	if sides[foe].morale_on:
		sides[foe].morale = maxf(0.0, sides[foe].morale - 70.0)
	fx.append(LiteFx.new(LiteFxKind.BLAST, w.pos, Vector2.ZERO, 0, 1.0, 24.0, w.side))
	fx.append(LiteFx.new(LiteFxKind.SCORCH, w.pos, Vector2.ZERO, 0, 600.0, 170.0, w.side))
	fx.append(LiteFx.new(LiteFxKind.NUKE, w.pos, Vector2.ZERO, 0, 6.0, NUKE_R, w.side))
	events.append(LiteEvent.new(LiteEv.NUKE, w.side, map.region_at(w.pos), w.pos, LiteArm.BALLISTIC, 0, 0, w.raid))
	finish(w.raid)

func destroy(b: LiteBuilding, by: int, raid: LiteRaid) -> void:
	b.alive = false
	if b.kind == LiteKind.UNIT and (b.unit == LiteUnit.WAGON or b.unit == LiteUnit.LOCO):
		# Ammunition cooking off.
		fx.append(LiteFx.new(LiteFxKind.BLAST, b.pos, Vector2.ZERO, 0, 1.4, 24.0, by))
		fx.append(LiteFx.new(LiteFxKind.SCORCH, b.pos, Vector2.ZERO, 0, 90.0, 26.0, by))
	LiteSense.relink()
	b.dead_at = time
	if b.kind == LiteKind.FACTORY: _ruins.append(Ruin.new(b.region, time + LiteRules.RUIN_TIME))
	sides[b.side].lost += 1
	sides[by].destroyed += 1
	if b.kind == LiteKind.FACTORY:
		LiteMorale.change(self, b.side, LiteMorale.FACTORY_LOST)
		LiteMorale.change(self, by, LiteMorale.STRUCK_FACTORY)
	elif LiteKind.is_works(b.kind):
		LiteMorale.change(self, b.side, LiteMorale.WORKS_LOST)
		LiteMorale.change(self, by, LiteMorale.STRUCK)
	elif b.kind != LiteKind.CAPITAL:
		LiteMorale.change(self, b.side, LiteMorale.SITE_LOST)
		LiteMorale.change(self, by, LiteMorale.STRUCK)
	if LiteKind.is_radar(b.kind) and not classic_rules:
		# Its air defence loses its picture: news for its side.
		var n: int = LiteSense.would_lose(self, b)
		events.append(LiteEvent.new(LiteEv.LINK_LOST, b.side, b.region, b.pos, 0, b.kind, n))
	if b.kind == LiteKind.REFINERY:
		# Oil burns: a big fire for a long time (the view keeps it, see
		# LiteView._particles), the ground blackened.
		fx.append(LiteFx.new(LiteFxKind.BLAST, b.pos, Vector2.ZERO, 0, 1.2, 24.0, by))
		fx.append(LiteFx.new(LiteFxKind.SCORCH, b.pos, Vector2.ZERO, 0, 120.0, 32.0, by))
	if b.kind == LiteKind.SUBSTATION:
		# The radars round it run short of power for half a day.
		grid_off_until[b.side] = time + LiteRules.DAY * 0.5
		grid_off_at[b.side] = b.pos
	var where: String = map.regions[b.region].name if b.region < map.regions.size() else ""
	raid.destroyed.append("%s in %s" % [LiteGlyphs.name(b.kind), where])
	events.append(LiteEvent.new(LiteEv.DESTROYED, b.side, b.region, b.pos, 0, b.kind))
	if b.kind == LiteKind.DEPOT:
		_secondary(b, by, raid)
	if b.kind == LiteKind.POWER:
		# The lights go out: its side's SAMs are silent for a day.
		sam_off_until[b.side] = maxf(sam_off_until[b.side], time + LiteRules.DAY)
	if b.kind == LiteKind.CAPITAL and winner < 0:
		winner = by
		events.append(LiteEvent.new(LiteEv.GAME_OVER, by))

## Mobile anti-drone units (phase 4b): each keeps to its own region. It
## patrols, driving from one spot of the region to another; when its side
## sees a drone or a cruise missile over its region (or close to it), it
## drives after it, leading it a little, and fires as it comes in range. It
## turns like a vehicle and slows to fire; it never leaves its region.
func _move_mobiles(dt: float) -> void:
	if time - _keep_off_at > 2.0:
		_refresh_keep_off()
	for b: LiteBuilding in buildings:
		# Gun trucks and (phase 4c) armoured AA guns patrol their regions.
		if not b.alive or not b.ready or not (b.kind == LiteKind.MOBILE or b.kind == LiteKind.GUN):
			continue
		# An escort keeps by the column (or train) it guards (phase 4d).
		if b.leader != null:
			_escort(b, dt)
			continue
		if b.home < 0:
			b.home = b.region
			b.goal = b.pos
			b.heading = _rng.randf() * TAU
		var home: LiteRegion = map.regions[b.home] if b.home < map.regions.size() else null
		if home == null or home.side != b.side:
			continue
		# The player is driving it (see LiteGunner).
		if b.manual:
			continue
		# A target over its region?
		if b.chase != null and (not b.chase.alive or not LiteSense.sighted(b.chase, b.side) or b.chase.pos.distance_to(b.pos) > LiteRules.MOBILE_HUNT * 1.3):
			b.chase = null
		# It looks round a few times a second (every step was costly with a
		# full sky and every AA gun on patrol), its crew not all at once.
		if b.chase == null and time >= b.hunt_at:
			b.hunt_at = time + 0.35 + _rng.randf() * 0.2
			var best: float = LiteRules.MOBILE_HUNT
			for w: LiteWeapon in weapons:
				if not w.alive or w.side == b.side or w.arm == LiteArm.BALLISTIC or not LiteSense.sighted(w, b.side):
					continue
				var d: float = w.pos.distance_to(b.pos)
				if d < best and map.region_at(w.pos) == b.home:
					best = d
					b.chase = w
		# Tracked armour is slower than a pickup.
		var tracks: float = 0.72 if b.kind == LiteKind.GUN else 1.0
		var want_speed: float = LiteRules.MOBILE_PATROL * tracks
		if b.chase != null:
			# Head for where it will be, a little ahead of it.
			var lead: Vector2 = b.chase.pos + b.chase.dir * minf(30.0, b.chase.speed * 0.8)
			b.goal = lead if map.region_at(lead) == b.home else b.chase.pos
			want_speed = LiteRules.MOBILE_CHASE * tracks * (0.45 if b.cool > 0.2 else 1.0)
		elif b.pos.distance_to(b.goal) < 3.0 or map.region_at(b.goal) != b.home or blocked(b.goal):
			# On to another spot of the region, clear of its towns and sites.
			if not home.spots.is_empty():
				for k: int in 6:
					b.goal = home.spots[_next(home.spots.size())]
					if not blocked(b.goal):
						break
			b.pace = 0.0
		# Turn towards the goal, at a vehicle's rate; speed up, slow down.
		var to: Vector2 = b.goal - b.pos
		if to.length() > 0.5:
			var turn: float = clampf(wrapf(to.angle() - b.heading, -PI, PI), -LiteRules.MOBILE_TURN * dt, LiteRules.MOBILE_TURN * dt)
			b.heading += turn
			# Slower through a tight turn.
			var sharp: float = absf(wrapf(to.angle() - b.heading, -PI, PI))
			var target_pace: float = want_speed * clampf(1.0 - sharp / PI, 0.25, 1.0)
			b.pace = move_toward(b.pace, target_pace, 6.0 * dt)
		else:
			b.pace = move_toward(b.pace, 0.0, 8.0 * dt)
		var next: Vector2 = b.pos + Vector2.from_angle(b.heading) * b.pace * dt
		# Never out of its region, never into a town or onto a site (once
		# clear of one): stop at the edge and pick another way.
		if map.region_at(next) == b.home and map.side_at(next) == b.side and (not blocked(next) or blocked(b.pos)):
			b.pos = next
		else:
			b.pace = 0.0
			b.heading += PI * 0.5
			if b.chase == null and not home.spots.is_empty():
				b.goal = home.spots[_next(home.spots.size())]

## An ammo depot going up: blasts round it, and damage to every site in reach.
func _secondary(b: LiteBuilding, by: int, raid: LiteRaid) -> void:
	for k: int in 5:
		var at: Vector2 = b.pos + Vector2(_rng.randf_range(4.0, 16.0), 0).rotated(_rng.randf() * TAU)
		fx.append(LiteFx.new(LiteFxKind.BLAST, at, Vector2.ZERO, 0, 0.9 + k * 0.15, 14.0 + k * 2.0, by))
	fx.append(LiteFx.new(LiteFxKind.SCORCH, b.pos, Vector2.ZERO, 0, 60.0, 26.0, by))
	for o: LiteBuilding in buildings:
		if o == b or not o.alive or o.kind == LiteKind.CAPITAL or o.pos.distance_to(b.pos) > LiteRules.DEPOT_BLAST:
			continue
		o.hp -= LiteRules.DEPOT_DAMAGE
		o.flash = 1
		if o.hp <= 0:
			destroy(o, by, raid)

## A storm coming in: no drone takes off while it lasts (see launch), but
## those already in the air fly on to their targets (they no longer turn
## back home: the user found it odd).
func _storm_check() -> void:
	_was_grounded = env.drones_grounded()

## A recalled drone home: it lands, and goes back into its side's stock.
func land(w: LiteWeapon) -> void:
	w.alive = false
	if classic_rules:
		sides[w.side].money += LiteRules.cost(LiteArm.DRONE)
	else:
		sides[w.side].stock[LiteArm.DRONE] += 1.0
	finish(w.raid)

func kill(w: LiteWeapon, by: int, shooter: LiteBuilding) -> void:
	w.alive = false
	if shooter != null: shooter.kills += 1
	w.raid.down += 1
	sides[by].downed += 1
	LiteMorale.change(self, by, [LiteMorale.DOWNED_DRONE, LiteMorale.DOWNED_CRUISE, LiteMorale.DOWNED_BALLISTIC][w.arm])
	stats.on_down(w, time)
	# `b.y` is how high it was, for drawing the burst in the air.
	fx.append(LiteFx.new(LiteFxKind.POP, w.pos, w.lift_vec() + w.off, 0, 0.5, 6 if w.arm == LiteArm.DRONE else 8, by))
	events.append(LiteEvent.new(LiteEv.SHOT_DOWN, by, map.region_at(w.pos), w.pos, w.arm, 0, 0, w.raid))
	finish(w.raid)

func finish(raid: LiteRaid) -> void:
	raid.done += 1
	if raid.done < raid.total: return
	sides[raid.side].last_raid_loss = raid.down / float(raid.total) if raid.total > 0 else 0.0
	events.append(LiteEvent.new(LiteEv.RAID_OVER, raid.side, 0, raid.target, 0, 0, 0, raid))

func air_defence(dt: float) -> void:
	for b: LiteBuilding in buildings:
		if not b.alive or not (b.is_ad or b.is_gun) or not b.ready: continue
		if b.kind == LiteKind.SAM and b.ammo < rack[b.side]:
			b.reload -= dt
			if b.reload <= 0:
				# Reloaded from the side's stock of interceptors (none: it waits).
				if classic_rules or sides[b.side].stock[LiteStock.AMMO] >= 1.0:
					if not classic_rules:
						sides[b.side].stock[LiteStock.AMMO] -= 1.0
					b.ammo += 1
				b.reload = LiteRules.SAM_RELOAD * reload_mul[b.side]
		elif not classic_rules and b.is_gun:
			# Guns' and mobile units' magazines fill again by themselves.
			var mag: int = LiteRules.MOBILE_MAG if b.kind == LiteKind.MOBILE else LiteRules.GUN_MAG
			if b.ammo < mag:
				b.reload -= dt
				if b.reload <= 0:
					b.ammo += 1
					b.reload = LiteRules.MOBILE_REFILL if b.kind == LiteKind.MOBILE else LiteRules.GUN_REFILL
		b.cool -= dt
		if b.cool > 0: continue
		if b.kind == LiteKind.SAM and time < sam_off_until[b.side]:
			b.cool = 0.5
			continue
		if not classic_rules and b.is_gun and b.ammo <= 0:
			b.cool = 0.3
			continue
		var range: float = ad_range(b) if not classic_rules else LiteRules.range(b.kind)
		# Guns aim by eye: they see less far in fog (SAMs, by radar, do not).
		if b.is_gun and classic_rules: range *= env.gun_range()
		var best: LiteWeapon = null
		var best_score: float = -_FLOAT_MAX
		for w: LiteWeapon in weapons:
			if not w.alive or w.side == b.side: continue
			# Only what its side sees now (a held track is not enough to aim at).
			if not classic_rules and not LiteSense.sighted(w, b.side): continue
			var d: float = w.pos.distance_to(b.pos)
			if d > range: continue
			var score: float
			if b.is_gun:
				if w.arm == LiteArm.BALLISTIC: continue
				score = (100 if w.arm == LiteArm.DRONE else 0) - d
			else:
				if b.ammo <= 0: break
				if w.arm == LiteArm.DRONE and not sams_on_drones[b.side]: continue
				if not LiteRules.sam_can_engage(w): continue
				if w.engaged >= (2 if w.arm == LiteArm.BALLISTIC else 1): continue
				score = w.arm * 1000 - d
			if score > best_score:
				best_score = score
				best = w
		# Nothing in range: look again in a tenth of a second, not every step.
		if best == null:
			b.cool = 0.1
			continue
		if b.is_gun:
			var every: float = LiteRules.GUN_INTERVAL if classic_rules else LiteRules.MINIGUN_INTERVAL
			b.cool = (LiteRules.MOBILE_INTERVAL if b.kind == LiteKind.MOBILE else every) * (0.5 if b.kind == LiteKind.CAPITAL else 1.0)
			# A player at the gun aims it himself (see LiteGunner).
			if b.manual:
				b.cool = 0.1
				continue
			var aim: Vector2 = best.pos + Vector2(_rng.randf() * 6 - 3, _rng.randf() * 6 - 3)
			b.aim_to = (aim - b.pos).angle()
			b.aim_time = time
			# The tracer: a pickup's machine gun (size 1), the armoured gun's
			# rotary cannon (2), the old gun's burst (0).
			var kind_fx: int = 1 if b.kind == LiteKind.MOBILE else (0 if classic_rules else 2)
			# From the turret's muzzle (a vehicle's), not its middle.
			var from: Vector2 = b.pos + (aim - b.pos).normalized() * (6.0 if kind_fx > 0 else 0.0)
			fx.append(LiteFx.new(LiteFxKind.TRACER, from, aim, 0, 0.14 if kind_fx == 0 else 0.3, kind_fx, b.side))
			b.fire_flash = 1
			if classic_rules:
				if _rng.randf() < LiteRules.gun_pk(best.arm) * env.gun_factor(): kill(best, b.side, b)
			else:
				b.ammo -= 1
				if _rng.randf() < ad_pk(b, best): kill(best, b.side, b)
		else:
			var side: LiteSide = sides[b.side]
			if classic_rules:
				if side.money < LiteRules.INTERCEPTOR_COST:
					b.cool = 0.5
					continue
				side.money -= LiteRules.INTERCEPTOR_COST
			b.ammo -= 1
			b.cool = LiteRules.SAM_BALLISTIC_RELOAD * reload_mul[b.side] if best.arm == LiteArm.BALLISTIC else LiteRules.SAM_INTERVAL
			b.fire_flash = 1
			best.engaged += 1
			var it:= LiteInterceptor.new()
			it.side = b.side
			it.target = best
			it.from = b
			it.pos = b.pos
			it.goal = best.pos
			interceptors.append(it)
			fx.append(LiteFx.new(LiteFxKind.LAUNCH, b.pos, Vector2.ZERO, 0, 0.5, 0, b.side))
			if not classic_rules:
				it.pk = ad_pk(b, best)
		spot(b, 1 - b.side)

func move_interceptors(dt: float) -> void:
	for i: LiteInterceptor in interceptors:
		if not i.alive: continue
		i.age += dt
		if i.target.alive: i.goal = i.target.pos
		var to: Vector2 = i.goal - i.pos
		var step: float = LiteRules.INTERCEPTOR_SPEED * LiteRules.sam_pace(i.age) * dt
		var d: float = to.length()
		if d > step + 3 and i.age < 4.0:
			i.pos += to / d * step
			continue
		i.pos = i.goal
		i.alive = false
		var pk: float = i.pk if i.pk >= 0.0 else minf(0.97, LiteRules.sam_pk(i.target.arm) * sam_bonus[i.side])
		if i.target.alive and _rng.randf() < pk: kill(i.target, i.side, i.from)
		else:
			if i.target.alive: i.target.engaged -= 1
			fx.append(LiteFx.new(LiteFxKind.PUFF, i.pos, i.target.lift_vec() + i.target.off, 0, 0.45, 4, i.side))

## Sites each side has not found yet, gathered once per look round.
var _hidden: Array[Array] = [[], []]

func reveal() -> void:
	_hidden[0].clear()
	_hidden[1].clear()
	for b: LiteBuilding in buildings:
		if b.alive and not b.seen[1 - b.side]:
			_hidden[1 - b.side].append(b)
	if _hidden[0].is_empty() and _hidden[1].is_empty():
		return
	for w: LiteWeapon in weapons:
		if not w.alive: continue
		var r: float = LiteRules.spot_radius(w.arm) * (1.0 if classic_rules else env.recon())
		if r <= 0: continue
		for b: LiteBuilding in _hidden[w.side]:
			if not b.seen[w.side] and b.pos.distance_to(w.pos) < r: spot(b, w.side)

func spot(b: LiteBuilding, viewer: int) -> void:
	if b.seen[viewer]: return
	b.seen[viewer] = true
	events.append(LiteEvent.new(LiteEv.SPOTTED, viewer, b.region, b.pos, 0, b.kind))

## Where round a weapon to look for regions it threatens (times its alert radius).
const _AROUND: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(0.7, 0.7), Vector2(-0.7, -0.7)]

func alerts(dt: float) -> void:
	_threat.fill(false)
	_sub_threat.fill(0)
	_bal.fill(false)
	_mis.fill(false)
	for w: LiteWeapon in weapons:
		var victim: int = 1 - w.side

		if not w.alive or not w.seen[victim]: continue
		# Where the side believes it is (a lost track, reckoned on).
		var wp: Vector2 = w.pos if classic_rules else w.believed(victim)
		mark(wp, victim, false)
		if w.arm == LiteArm.BALLISTIC:
			# High on its arc, nobody can tell where it will come down: the
			# alert goes out over most of the country, every region within
			# BALLISTIC_WARN of it. Only in its final dive does it narrow to
			# where it is falling and round there.
			if w.progress < LiteRules.BALLISTIC_TERMINAL:
				for r: LiteRegion in map.regions:
					if r.side == victim and r.label.distance_to(w.pos) < LiteRules.BALLISTIC_WARN:
						_threat[r.id] = true
						_bal[r.id] = true
						_mis[r.id] = true
				continue
			var t: int = map.region_at(w.target)
			if t != LiteMap.NONE and map.regions[t].side == victim:
				mark(w.target, victim, true)
				for n: int in map.regions[t].neighbors:
					if map.regions[n].side == victim:
						_threat[n] = true
						_bal[n] = true
						_mis[n] = true
			continue
		var r: float = LiteRules.alert_radius(w.arm)
		var mis: bool = w.arm == LiteArm.CRUISE
		mark(wp, victim, false, mis)
		for o: Vector2 in _AROUND: mark(wp + o * r, victim, false, mis)
		var ahead: float = w.speed * LiteRules.heading(w.arm)
		var d: float = 20
		while d <= ahead:
			mark(wp + w.dir * d, victim, false, mis)
			d += 25
	for r: LiteRegion in map.regions:
		if r.city:
			_threat[r.id] = _threat[r.id] or _threat[r.parent]
			_bal[r.id] = _bal[r.id] or _bal[r.parent]
			_mis[r.id] = _mis[r.id] or _mis[r.parent]
	for i: int in alert.size():
		var side: int = map.regions[i].side
		if _bal[i]:
			ballistic[i] = true
			_bal_quiet[i] = 0
		elif ballistic[i]:
			_bal_quiet[i] += dt
			if _bal_quiet[i] >= 2.0: ballistic[i] = false
		# Red follows missiles in the air: it fades back to yellow (or the
		# all-clear) as soon as no missile threatens the region.
		missile[i] = _mis[i] or ballistic[i]
		if _threat[i]:
			_quiet[i] = 0
			if not alert[i]:
				alert[i] = true
				alert_since[i] = time
				stats.on_alert(i, side)
				var was: int = alerted[side]
				alerted[side] += 1
				if was == 0:
					side_alert_since[side] = time
					events.append(LiteEvent.new(LiteEv.RAID_ALERT, side, i))
		elif alert[i]:
			_quiet[i] += dt
			if _quiet[i] >= LiteRules.ALL_CLEAR_AFTER:
				stats.on_all_clear(i, side, time - alert_since[i])
				alert[i] = false
				ballistic[i] = false
				missile[i] = false
				alerted[side] -= 1
				if alerted[side] == 0:
					side_quiet_since[side] = time
					events.append(LiteEvent.new(LiteEv.ALL_CLEAR, side, 0, Vector2.ZERO, 0, 0, time - side_alert_since[side]))
	# The districts: under alert while threatened (red while missiles are), the
	# all-clear after the same quiet as a province's.
	for d: int in _sub_threat.size():
		if _sub_threat[d] > 0:
			sub_alert[d] = _sub_threat[d]
			_sub_quiet[d] = 0.0
		elif sub_alert[d] > 0:
			_sub_quiet[d] += dt
			if _sub_quiet[d] >= LiteRules.ALL_CLEAR_AFTER:
				sub_alert[d] = 0

## Whether launches at `victim` are still waiting in the queue.
func enemy_queued(victim: int) -> bool:
	for p: Pending in _queue:
		if p.side != victim: return true
	return false

func mark(p: Vector2, victim: int, ballistic: bool, mis: bool = false) -> void:
	var id: int = map.region_at(p)
	if id == LiteMap.NONE or map.regions[id].side != victim: return
	if not _sub_threat.is_empty():
		var x: int = int(p.x)
		var y: int = int(p.y)
		if x >= 0 and y >= 0 and x < LiteMap.W and y < LiteMap.H:
			var d: int = map.sub[y * LiteMap.W + x]
			if d != LiteMap.NONE:
				_sub_threat[d] = maxi(_sub_threat[d], 2 if ballistic or mis else 1)
	_threat[id] = true
	if ballistic: _bal[id] = true
	if ballistic or mis: _mis[id] = true
