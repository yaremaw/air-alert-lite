class_name LiteCampaign
extends RefCounted
## A campaign: one war, fought province by province. Between operations the
## war's map shows the front; you choose which enemy province on it to attack
## next, and each attack is fought on that province's own map (see
## LiteRegionMap), district by district, against its targets. Take it and the
## front moves forward, and what it was (industry, an air base, depots) works
## for you after; fail and it stays theirs. Now and then the enemy strikes
## back at a province of ours, and that has to be held. Taking the enemy's
## capital province wins the war; losing ours loses it.
##
## Saved between operations: quitting during one and continuing replays it.

## Where the campaign is saved (a test run uses a file of its own).
static var path: String = "user://lite_campaign.json"
## Saves of other versions are not loaded (3: operations on province maps).
const SAVE_VERSION: int = 3
## Game days between two operations.
const GAP_DAYS: float = 2.0
## Money we start an operation with at least, and the most carried over.
const START_MONEY: float = 500.0
const MONEY_CARRIED: float = 600.0
## The war has this many operations to be won in; after them, a ceasefire.
const MAX_OPS: int = 10
## The enemy capital's defences: SAM batteries (and as many guns) for each
## province round it that the enemy still holds, on top of these.
const CAPITAL_BASE: int = 1

## How often the enemy strikes back after we take a province (a test run can
## make it always).
static var counter_chance: float = 0.5

var map_seed: int = 0
var difficulty: int = 1
## Provinces that changed hands, by id: the side holding them now.
var owners: Dictionary = {}
## Game time before the next operation, in seconds of play: the clock runs on.
var clock: float = 0.0
var money: float = START_MONEY
var ops: int = 0
var taken: Array[int] = [0, 0]
## Money owed to us for the last operation's optional goal.
var bonus: int = 0
## What the provinces taken bring: our income up, money at each start, the
## enemy's income down.
var income_bonus: float = 0.0
var supply: int = 0
var enemy_cut: float = 0.0
## A province of ours the enemy is attacking: the next operation must hold it.
var counter: int = -1
## -1 while the war goes on, 0 won, 1 lost, 2 a ceasefire (out of time).
var won: int = -1
var results: Array[int] = []
var history: PackedStringArray = PackedStringArray()
## The campaign's regions: provinces grouped a few together, so the front
## offers a handful of real choices rather than every province. Each
## province's group is named by its main province (the id the campaign uses
## for the group); cities follow their province. Worked out from the map as
## baked (see make_groups), so the same all campaign long.
var group_of: PackedInt32Array = PackedInt32Array()
## About how many provinces make a region.
const GROUP_SIZE: float = 3.5

static func fresh(seed_: int, difficulty_: int) -> LiteCampaign:
	var c:= LiteCampaign.new()
	c.map_seed = seed_
	c.difficulty = difficulty_
	return c

static func has_save() -> bool:
	return load_saved() != null

static func load_saved() -> LiteCampaign:
	if not FileAccess.file_exists(path):
		return null
	var got: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not got is Dictionary:
		return null
	var d: Dictionary = got
	if int(d.get("version", 0)) != SAVE_VERSION:
		return null
	var c:= LiteCampaign.new()
	c.map_seed = int(d["map_seed"])
	c.difficulty = int(d["difficulty"])
	for k: String in (d["owners"] as Dictionary):
		c.owners[int(k)] = int(d["owners"][k])
	c.clock = float(d["clock"])
	c.money = float(d["money"])
	c.ops = int(d["ops"])
	c.taken = [int(d["taken"][0]), int(d["taken"][1])]
	c.bonus = int(d["bonus"])
	c.income_bonus = float(d["income_bonus"])
	c.supply = int(d["supply"])
	c.enemy_cut = float(d["enemy_cut"])
	c.counter = int(d["counter"])
	c.won = int(d["won"])
	for r: Variant in d["results"]:
		c.results.append(int(r))
	c.history = PackedStringArray(d["history"])
	if c.won >= 0:
		return null
	return c

func save() -> void:
	var owners_: Dictionary = {}
	for k: int in owners:
		owners_[str(k)] = owners[k]
	var d: Dictionary = {"version": SAVE_VERSION, "map_seed": map_seed, "difficulty": difficulty,
		"owners": owners_, "clock": clock, "money": money, "ops": ops, "taken": taken, "bonus": bonus,
		"income_bonus": income_bonus, "supply": supply, "enemy_cut": enemy_cut, "counter": counter,
		"won": won, "results": results, "history": history}
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
		f.close()

static func forget() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

## Groups the provinces of a freshly loaded map (sides as baked): for each
## side, its capital's province and others as far from each other as can be
## seed the groups, which then grow a province at a time across borders, each
## province joining the group that reaches it first, so every group is one
## piece.
func make_groups(map: LiteMap) -> void:
	group_of = PackedInt32Array()
	group_of.resize(map.regions.size())
	group_of.fill(-1)
	for side: int in 2:
		var provs: Array[int] = []
		for r: LiteRegion in map.regions:
			if not r.city and r.side == side:
				provs.append(r.id)
		if provs.is_empty():
			continue
		var count: int = clampi(roundi(provs.size() / GROUP_SIZE), 2, 7)
		var seeds: Array[int] = [map.capital_province(side)]
		while seeds.size() < count:
			var best: int = -1
			var bd: float = -1.0
			for p: int in provs:
				if seeds.has(p):
					continue
				var d: float = INF
				for s: int in seeds:
					d = minf(d, map.regions[p].label.distance_to(map.regions[s].label))
				if d > bd:
					bd = d
					best = p
			if best < 0:
				break
			seeds.append(best)
		var queue: Array[int] = []
		for s: int in seeds:
			group_of[s] = s
			queue.append(s)
		var head: int = 0
		while head < queue.size():
			var p: int = queue[head]
			head += 1
			for n: int in map.provinces_next_to(p):
				if group_of[n] < 0 and map.regions[n].side == side and not map.regions[n].city:
					group_of[n] = group_of[p]
					queue.append(n)
		# Any province no group reached (cut off by the sea) joins the nearest.
		for p: int in provs:
			if group_of[p] >= 0:
				continue
			var near: int = seeds[0]
			for s: int in seeds:
				if map.regions[p].label.distance_to(map.regions[s].label) < map.regions[p].label.distance_to(map.regions[near].label):
					near = s
			group_of[p] = near
	for r: LiteRegion in map.regions:
		if r.city and r.parent >= 0:
			group_of[r.id] = group_of[r.parent]

## Each group's name shown once, on the province nearest the middle of it
## (only these names drawn, on this map); returns, for each group, the
## province its name is on.
func label_groups(map: LiteMap) -> Dictionary:
	var at: Dictionary = {}
	var mains: Dictionary = {}
	for r: LiteRegion in map.regions:
		var g: int = group_at(r.id)
		if not r.city and g >= 0:
			mains[g] = true
	for g: int in mains:
		var ps: Array[int] = group(g)
		var mid:= Vector2.ZERO
		for p: int in ps:
			mid += map.regions[p].label
		mid /= maxf(1.0, ps.size())
		var best: int = g
		for p: int in ps:
			if map.regions[p].label.distance_to(mid) < map.regions[best].label.distance_to(mid):
				best = p
		at[g] = best
	map.label_only = {}
	for g: int in mains:
		# A capital's group is named by its capital, already marked.
		if g == group_at(map.capital_province(0)) or g == group_at(map.capital_province(1)):
			continue
		map.label_only[at[g]] = map.regions[g].name
	return at

## A group's name: its capital's for a capital's group, else its main
## province's.
func group_name(map: LiteMap, g: int) -> String:
	for s: int in 2:
		if g == group_at(map.capital_province(s)):
			return map.capital_name[s]
	return map.regions[g].name

## The provinces of the group `g` (a group's main province).
func group(g: int) -> Array[int]:
	var out: Array[int] = []
	for p: int in group_of.size():
		if group_of[p] == g and p != -1:
			out.append(p)
	return out

## The group a region belongs to (-1 for none).
func group_at(region: int) -> int:
	return group_of[region] if region >= 0 and region < group_of.size() else -1

## The war's map as the campaign has left it.
func apply_map(map: LiteMap) -> void:
	for id: int in owners:
		map.give(id, owners[id])

## The provinces of `side` on the front (its capital's left out).
static func _border(map: LiteMap, side: int) -> Array[int]:
	var out: Array[int] = []
	var cap: int = map.capital_province(side)
	for r: LiteRegion in map.regions:
		if r.city or r.side != side or r.id == cap or r.spots.is_empty():
			continue
		if map.on_front(r.id):
			out.append(r.id)
	return out

## The groups bordering group `g`.
func groups_next_to(map: LiteMap, g: int) -> Array[int]:
	var out: Array[int] = []
	for p: int in group(g):
		for n: int in map.provinces_next_to(p):
			var o: int = group_at(n)
			if o >= 0 and o != g and not out.has(o):
				out.append(o)
	return out

## What can be done next: hold the group under attack, if one is; else
## attack any enemy group on the front, the capital's too once it is.
func options(map: LiteMap) -> Array[int]:
	if counter >= 0:
		return [counter]
	var out: Array[int] = []
	var seen: Dictionary = {}
	for r: LiteRegion in map.regions:
		var g: int = group_at(r.id)
		if r.city or g < 0 or seen.has(g) or map.regions[g].side != 1:
			continue
		seen[g] = true
		for o: int in groups_next_to(map, g):
			if map.regions[o].side == 0:
				out.append(g)
				break
	# The capital's group last.
	var cap: int = group_at(map.capital_province(1))
	if out.has(cap):
		out.erase(cap)
		out.append(cap)
	return out

## The enemy capital's defences now: one SAM battery and one gun for each
## region round the capital's that the enemy still holds, and CAPITAL_BASE
## more. Taking those regions wears it down.
func capital_defence(map: LiteMap) -> int:
	var n: int = CAPITAL_BASE
	for g: int in groups_next_to(map, group_at(map.capital_province(1))):
		if map.regions[g].side == 1:
			n += 1
	return n

## What a province is: the same for it all campaign long.
func character(province: int) -> int:
	var h: int = hash(str(map_seed) + ":" + str(province))
	return posmod(h, 3)

## The operation over `province`: its kind, deadline, goals and briefing.
func make_op(map: LiteMap, province: int) -> LiteMission:
	var m:= LiteMission.new()
	m.number = ops + 1
	m.province = province
	m.provinces = group(province)
	m.region_name = group_name(map, province)
	m.character = character(province)
	var r: String = m.region_name
	if map.regions[province].side == 0:
		m.kind = LiteMission.HOLD
		m.title = "Hold %s" % r
		m.days = 4.0
		m.need = 30
		m.optional = LiteMission.SHOOT_DOWN
		m.optional_need = 40
		m.reward = 200
		m.briefing = ("The enemy is attacking %s. Hold it until the offensive runs out: every drone or " +
			"missile that lands in it wears our troops down, and at %d hits they pull back. Keep its sky clear.") % [r, m.need]
	elif province == group_at(map.capital_province(1)):
		m.kind = LiteMission.CAPITAL
		m.title = "Strike at the heart"
		m.days = 7.0
		m.optional = LiteMission.SHOOT_DOWN
		m.optional_need = 60
		m.need = capital_defence(map)
		m.briefing = ("%s is within reach. Destroy the enemy's command there and the war is over: it is " +
			"the best defended ground the enemy has.") % map.capital_name[1]
	else:
		m.kind = LiteMission.STRIKE
		m.title = "Take %s" % r
		m.days = 6.0
		match m.character:
			LiteMission.INDUSTRY:
				m.briefing = "%s is an industrial province: its depot and factories keep the enemy's war going. Destroy them and our troops can move in." % r
			LiteMission.LOGISTICS:
				m.briefing = "%s is a supply hub for the front: two ammunition depots feed it. Destroy both and the front there collapses." % r
			_:
				m.briefing = "%s is a military district: a radar guides its air defence and drones take off from a launch site there. Destroy both." % r
		m.optional = LiteMission.NO_FACTORY_LOST
		m.reward = 150
		m.notes.append("Taking it: " + LiteMission.character_reward(m.character))
	if bonus > 0:
		m.notes.append("Reward from the last operation: $%d." % bonus)
	if supply > 0:
		m.notes.append("Depots taken earlier: +$%d." % supply)
	if income_bonus > 0.0:
		m.notes.append("Industry taken earlier: +%d%% income." % roundi(income_bonus * 100))
	if enemy_cut > 0.0:
		m.notes.append("Air bases taken earlier: the enemy has %d%% less to spend." % roundi(enemy_cut * 100))
	return m

## Sets up an operation's war on its map: our money and what earlier gains
## bring, the targets in the province with guns by them, the enemy's orders,
## and the events to come.
func setup(m: LiteMission, sim: LiteSim, ai: LiteAi) -> void:
	var map: LiteMap = sim.map
	sim.sides[0].money = maxf(START_MONEY, minf(money, MONEY_CARRIED)) + bonus + supply
	sim.income_scale[0] *= 1.0 + income_bonus
	sim.income_scale[1] *= maxf(0.5, 1.0 - enemy_cut)
	var rng:= RandomNumberGenerator.new()
	rng.seed = map_seed * 31 + ops * 7 + m.province
	var districts: Array[int] = []
	for id: int in map.focus:
		if map.regions[id].spots.size() > 0:
			districts.append(id)
	districts.shuffle()
	match m.kind:
		LiteMission.STRIKE:
			# Defending one province, the enemy has less to spend and spends
			# less of it on attacks.
			sim.income_scale[1] *= 0.85
			ai.war_share -= 0.1
			# It cannot ring the targets with batteries without end.
			ai.ad_limit = 4
			var kinds: Array[int] = LiteMission.target_kinds(m.character)
			for k: int in kinds.size():
				var at: int = districts[k % districts.size()] if not districts.is_empty() else map.focus[0]
				var t: LiteBuilding = _put(sim, 1, kinds[k], at, rng)
				if t == null:
					continue
				t.seen[0] = true
				m.targets.append(t)
				var gun: Variant = sim.find_spot(1, t.pos, 14, 26)
				if gun != null:
					sim.add(1, LiteKind.GUN, gun, true)
			if m.character == LiteMission.MILITARY and not m.targets.is_empty():
				var sam: Variant = sim.find_spot(1, m.targets[0].pos, 16, 32)
				if sam != null:
					sim.add(1, LiteKind.SAM, sam, true)
		LiteMission.CAPITAL:
			var cap: LiteBuilding = sim.sides[1].capital
			m.targets.append(cap)
			for k: int in m.need:
				var p: Variant = sim.find_spot(1, cap.pos, 20, 55)
				if p != null:
					sim.add(1, LiteKind.SAM, p, true)
				var g: Variant = sim.find_spot(1, cap.pos, 16, 45)
				if g != null:
					sim.add(1, LiteKind.GUN, g, true)
			ai.ad_limit = 4
		LiteMission.HOLD:
			# Engineers dig in where the offensive is coming.
			for id: int in districts.slice(0, 2):
				var f: LiteBuilding = _put(sim, 0, LiteKind.FACTORY, id, rng)
				if f != null:
					var sam: Variant = sim.find_spot(0, f.pos, 14, 30)
					if sam != null:
						sim.add(0, LiteKind.SAM, sam, true)
			for b: LiteBuilding in sim.buildings:
				if b.side == 0 and map.focus.has(map.province(b.region)):
					b.seen[1] = true
			sim.income_scale[1] *= 1.2
			ai.war_share += 0.1
			ai.focus_set = map.focus
			ai.focus_weight = 3.0
			ai.hold_until(40.0)
	# Events, at random times between a sixth and four fifths of the way:
	# three in an attack, two in a defence.
	var pool: Array[int] = [LiteMission.STORM, LiteMission.SUPPLY]
	var count: int = 2
	if m.kind == LiteMission.HOLD:
		pool.append(LiteMission.RAID)
	else:
		pool.append_array([LiteMission.INTEL, LiteMission.REINFORCE, LiteMission.SABOTAGE, LiteMission.OUTAGE, LiteMission.CONVOY])
		count = 3
	for k: int in count:
		var e: int = pool[rng.randi_range(0, pool.size() - 1)]
		pool.erase(e)
		m.events.append([m.length * rng.randf_range(0.16, 0.8), e])
	m.events.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])

## A site in a district, on its free ground; free and ready at once.
static func _put(sim: LiteSim, side: int, kind: int, id: int, rng: RandomNumberGenerator) -> LiteBuilding:
	var spots: Array[Vector2] = sim.map.regions[id].spots
	for i: int in 60:
		if spots.is_empty():
			break
		var p: Vector2 = spots[rng.randi_range(0, spots.size() - 1)]
		if sim.can_place(side, p):
			return sim.add(side, kind, p, true)
	return null

## An event comes up: what it does to the war.
static func happen(m: LiteMission, e: int, sim: LiteSim) -> void:
	match e:
		LiteMission.STORM:
			m.storm_until = sim.time + LiteRules.DAY * 0.5
			sim.grounded_until = m.storm_until
		LiteMission.SUPPLY:
			sim.sides[0].money += 250
		LiteMission.INTEL:
			var hidden: Array[int] = []
			for b: LiteBuilding in sim.buildings:
				if b.alive and b.side == 1 and not b.seen[0] and not hidden.has(b.region):
					hidden.append(b.region)
			if not hidden.is_empty():
				var r: int = hidden[randi() % hidden.size()]
				for b: LiteBuilding in sim.buildings:
					if b.alive and b.side == 1 and b.region == r:
						sim.spot(b, 0)
		LiteMission.REINFORCE:
			for t: LiteBuilding in m.targets:
				if t.alive:
					var p: Variant = sim.find_spot(1, t.pos, 16, 34)
					if p != null:
						sim.add(1, LiteKind.SAM, p, false)
					break
		LiteMission.SABOTAGE:
			# The enemy air defence site nearest a target still standing.
			var aim: Vector2 = sim.sides[1].capital.pos
			for t: LiteBuilding in m.targets:
				if t.alive:
					aim = t.pos
					break
			var best: LiteBuilding = null
			for b: LiteBuilding in sim.buildings:
				if b.alive and b.side == 1 and b.is_ad and (best == null or b.pos.distance_to(aim) < best.pos.distance_to(aim)):
					best = b
			if best != null:
				sim.spot(best, 0)
				sim.destroy(best, 0, LiteRaid.new())
		LiteMission.OUTAGE:
			m.outage_until = sim.time + LiteRules.DAY * 0.5
			sim.sam_off_until[1] = m.outage_until
		LiteMission.CONVOY:
			var spots: Array[int] = []
			for id: int in sim.map.focus:
				if sim.map.regions[id].spots.size() > 0:
					spots.append(id)
			if not spots.is_empty():
				var rng:= RandomNumberGenerator.new()
				rng.seed = int(sim.time * 1000.0)
				var c: LiteBuilding = _put(sim, 1, LiteKind.DEPOT, spots[rng.randi_range(0, spots.size() - 1)], rng)
				if c != null:
					c.seen[0] = true
					m.convoy = c
					m.convoy_until = sim.time + LiteRules.DAY * 0.5
		LiteMission.RAID:
			sim.sides[1].money += 450
			sim.sides[1].war_fund += 450

## After an operation: the province changes hands or not, what it brings,
## the money carried on, the clock, whether the enemy strikes back, and
## whether the war is over.
func after(m: LiteMission, war: LiteMap, sim: LiteSim) -> void:
	results.append(m.result)
	history.append("%d. %s: %s" % [m.number, m.title, m.outcome])
	bonus = m.reward if m.optional_done else 0
	money = minf(sim.sides[0].money, MONEY_CARRIED)
	clock += m.length + GAP_DAYS * LiteRules.DAY
	ops += 1
	counter = -1
	match m.kind:
		LiteMission.STRIKE:
			if m.result == 0:
				for p: int in m.provinces:
					owners[p] = 0
					war.give(p, 0)
				taken[0] += 1
				match m.character:
					LiteMission.INDUSTRY: income_bonus += 0.1
					LiteMission.LOGISTICS: supply += 200
					_: enemy_cut += 0.1
				var rng:= RandomNumberGenerator.new()
				rng.seed = map_seed + ops * 13
				if rng.randf() < counter_chance:
					counter = m.province
		LiteMission.CAPITAL:
			if m.result == 0:
				won = 0
		LiteMission.HOLD:
			if m.result == 1:
				for p: int in m.provinces:
					owners[p] = 1
					war.give(p, 1)
				taken[1] += 1
				if m.provinces.has(war.capital_province(0)):
					won = 1
	if won < 0 and _border(war, 0).is_empty() and not war.on_front(war.capital_province(0)):
		won = 1
	if won < 0 and ops >= MAX_OPS:
		won = 2

var finished: bool:
	get: return won >= 0
