class_name LiteCampaign
extends RefCounted
## A campaign: one war fought as a run of missions on one map, each over one
## province. Take a province and the frontier moves forward; fail and the
## enemy pushes back and takes one of ours. Sites, damage and money carry from
## one mission to the next, a few days apart, with some repairs in between.
## The side that lost a province rallies in the next mission, so a bad mission
## does not snowball into a lost campaign.
##
## Saved between missions: quitting mid-mission and continuing replays that
## mission from its start.

## Where the campaign is saved (a test run uses a file of its own).
static var path: String = "user://lite_campaign.json"
const MISSIONS: Array[int] = [LiteMission.STRIKE, LiteMission.HOLD, LiteMission.CAPITAL]
## Game days between two missions.
const GAP_DAYS: float = 3.0
## The most money either side brings into the next mission.
const MONEY_CARRIED: float = 600.0

var map_seed: int = 0
var difficulty: int = 1
## Which mission is next (0-based).
var mission: int = 0
## Provinces that changed hands, by id: the side holding them now.
var owners: Dictionary = {}
## Every site standing at the end of the last mission (see keep); empty
## before the first, which starts like a new war.
var sites: Array = []
var money: Array[float] = [LiteRules.START_MONEY, LiteRules.START_MONEY]
## Game time before this mission, in seconds of play: the clock runs on.
var clock: float = 0.0
## Provinces each side has taken.
var taken: Array[int] = [0, 0]
## The side that lost a province last mission and rallies in this one (-1:
## nobody), and which province it was.
var rally_side: int = -1
var rally_name: String = ""
## Money owed to us for last mission's optional goal.
var bonus: int = 0
## The province last fought over.
var front: int = -1
## Each mission's result (0 done, 1 failed) and one line on how it went.
var results: Array[int] = []
var history: PackedStringArray = PackedStringArray()

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
	if int(d.get("version", 0)) != 1:
		return null
	var c:= LiteCampaign.new()
	c.map_seed = int(d["map_seed"])
	c.difficulty = int(d["difficulty"])
	c.mission = int(d["mission"])
	for k: String in (d["owners"] as Dictionary):
		c.owners[int(k)] = int(d["owners"][k])
	c.sites = d["sites"]
	c.money = [float(d["money"][0]), float(d["money"][1])]
	c.clock = float(d["clock"])
	c.taken = [int(d["taken"][0]), int(d["taken"][1])]
	c.rally_side = int(d["rally_side"])
	c.rally_name = str(d["rally_name"])
	c.bonus = int(d["bonus"])
	c.front = int(d["front"])
	for r: Variant in d["results"]:
		c.results.append(int(r))
	c.history = PackedStringArray(d["history"])
	if c.mission >= MISSIONS.size():
		return null
	return c

func save() -> void:
	var owners_: Dictionary = {}
	for k: int in owners:
		owners_[str(k)] = owners[k]
	var d: Dictionary = {"version": 1, "map_seed": map_seed, "difficulty": difficulty, "mission": mission,
		"owners": owners_, "sites": sites, "money": money, "clock": clock, "taken": taken,
		"rally_side": rally_side, "rally_name": rally_name, "bonus": bonus, "front": front,
		"results": results, "history": history}
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
		f.close()

static func forget() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

## The map as the campaign has left it.
func apply_map(map: LiteMap) -> void:
	for id: int in owners:
		map.give(id, owners[id])

## The provinces of `side` that border the other side, its capital's left out.
static func _border(map: LiteMap, side: int) -> Array[int]:
	var out: Array[int] = []
	var cap: int = map.capital_province(side)
	for r: LiteRegion in map.regions:
		if r.city or r.side != side or r.id == cap or r.spots.is_empty():
			continue
		if map.on_front(r.id):
			out.append(r.id)
	return out

static func _nearest(map: LiteMap, list: Array[int], to: Vector2) -> int:
	var best: int = -1
	var bd: float = INF
	for id: int in list:
		var d: float = map.regions[id].label.distance_to(to)
		if d < bd:
			bd = d
			best = id
	return best

## The next mission on this map. A strike goes for the enemy province nearest
## our capital; a defence holds the province just fought over if it is ours
## and on the front, else our front province nearest it.
func make_mission(map: LiteMap) -> LiteMission:
	var m:= LiteMission.new()
	m.number = mission + 1
	m.kind = MISSIONS[mission]
	var cap_name: String = map.capital_name[1]
	match m.kind:
		LiteMission.STRIKE:
			m.region = _nearest(map, _border(map, 1), map.capital[0])
			if m.region < 0:
				m.kind = LiteMission.CAPITAL
	if m.kind == LiteMission.HOLD:
		var ours: Array[int] = _border(map, 0)
		if ours.has(front):
			m.region = front
		else:
			m.region = _nearest(map, ours, map.regions[front].label if front >= 0 else map.capital[1])
		if m.region < 0:
			m.kind = LiteMission.CAPITAL
	if m.kind == LiteMission.CAPITAL:
		m.region = map.capital_province(1)
	m.region_name = map.regions[m.region].name
	var r: String = m.region_name
	match m.kind:
		LiteMission.STRIKE:
			m.title = "First push"
			m.days = 6.0
			m.need = 2
			m.optional = LiteMission.NO_FACTORY_LOST
			m.reward = 150
			m.briefing = ("Enemy guns in %s shell our border towns. Take the province: destroy two of its sites " +
				"and our troops move in. Reconnaissance has found a factory and an air defence position there.") % r
		LiteMission.HOLD:
			m.title = "Counter-attack"
			m.days = 4.0
			m.need = 30
			m.optional = LiteMission.SHOOT_DOWN
			m.optional_need = 40
			m.reward = 200
			m.briefing = ("The enemy is massing to take %s. Hold it until the offensive runs out: every drone or " +
				"missile that lands there wears our troops down, and at %d hits they pull back. Engineers have " +
				"dug in a factory, an AA gun and a SAM there. Keep its sky clear.") % [r, m.need]
			m.notes.append("Enemy offensive: it has more to spend and goes for %s first." % r)
		_:
			m.title = "Strike at the heart"
			m.days = 7.0
			m.need = 30
			m.optional = LiteMission.SHOOT_DOWN
			m.optional_need = 60
			m.briefing = ("%s keeps the enemy in the war. Land %d damage on the capital, whatever its factories " +
				"repair, or destroy it outright and end the war.") % [cap_name, m.need]
			m.notes.append("Allied delivery: $300 for this mission.")
			m.notes.append("The enemy has dug in: a new SAM battery guards %s." % cap_name)
	if bonus > 0:
		m.notes.append("Reward from the last mission: $%d." % bonus)
	if rally_side == 0:
		m.notes.append("The country rallies after losing %s: +$250, factories work 15%% harder." % rally_name)
	elif rally_side == 1:
		m.notes.append("The enemy rallies after losing %s: it has more to spend this time." % rally_name)
	return m

## Sets up a mission's war: the money carried over, what its events and a
## side's rally bring, the sites its goal needs, and the enemy's orders.
func setup(m: LiteMission, sim: LiteSim, ai: LiteAi) -> void:
	# Money carries over, up to a limit: the rest went to the ground war in
	# between. (Without it the enemy banks a fortune and spends it all in the
	# first minute of the next mission.)
	if not sites.is_empty():
		sim.sides[0].money = minf(money[0], MONEY_CARRIED)
		sim.sides[1].money = minf(money[1], MONEY_CARRIED)
	sim.sides[0].money += bonus
	if rally_side == 0:
		sim.sides[0].money += 250
		sim.income_scale[0] *= 1.15
	elif rally_side == 1:
		sim.sides[1].money += 200
		sim.income_scale[1] *= 1.15
	var rng:= RandomNumberGenerator.new()
	rng.seed = map_seed * 31 + mission
	match m.kind:
		LiteMission.STRIKE:
			# Something to destroy there, and our side knows where it is.
			if sim.sites_in(1, m.region, LiteKind.FACTORY).is_empty():
				_put(sim, 1, LiteKind.FACTORY, m.region, rng)
			if sim.sites_in(1, m.region).size() < 2:
				_put(sim, 1, LiteKind.GUN, m.region, rng)
			for b: LiteBuilding in sim.sites_in(1, m.region):
				b.seen[0] = true
		LiteMission.HOLD:
			# Engineers dig in: a factory to hold, with a gun and a SAM by it.
			if sim.sites_in(0, m.region, LiteKind.FACTORY).is_empty():
				_put(sim, 0, LiteKind.FACTORY, m.region, rng)
			if sim.sites_in(0, m.region, LiteKind.GUN).is_empty():
				_put(sim, 0, LiteKind.GUN, m.region, rng)
			if sim.sites_in(0, m.region, LiteKind.SAM).is_empty():
				_put(sim, 0, LiteKind.SAM, m.region, rng)
			for b: LiteBuilding in sim.sites_in(0, m.region):
				b.seen[1] = true
			sim.income_scale[1] *= 1.2
			ai.war_share += 0.1
			ai.focus = m.region
			ai.focus_weight = 3.0
			# The offensive takes a while to gather: time to get ready.
			ai.hold_until(40.0)
		LiteMission.CAPITAL:
			sim.sides[0].money += 300
			var p: Variant = sim.find_spot(1, sim.sides[1].capital.pos, 20, 50)
			if p != null:
				sim.add(1, LiteKind.SAM, p, true)

## A site in a province, placed among its free ground; free and ready at once.
static func _put(sim: LiteSim, side: int, kind: int, id: int, rng: RandomNumberGenerator) -> LiteBuilding:
	var spots: Array[Vector2] = sim.map.regions[id].spots
	var first: LiteBuilding = null
	for b: LiteBuilding in sim.sites_in(side, id):
		first = b
		break
	for i: int in 60:
		if spots.is_empty():
			break
		var p: Vector2 = spots[rng.randi_range(0, spots.size() - 1)]
		# A gun goes next to what it guards.
		if kind == LiteKind.GUN and first != null and i < 40:
			p = first.pos + Vector2(rng.randf_range(14, 26), 0).rotated(rng.randf() * TAU)
		if sim.can_place(side, p) and sim.map.province(sim.map.region_at(p)) == id:
			return sim.add(side, kind, p, true)
	return null

## What a mission's end does to the map: the province changes hands, or not.
## Returns the province that changed hands (-1 for none) and its new owner.
func outcome(m: LiteMission, map: LiteMap) -> Array[int]:
	var lost: int = -1
	var to: int = -1
	match m.kind:
		LiteMission.STRIKE:
			if m.result == 0:
				lost = m.region
				to = 0
			else:
				# The enemy pushes back: our front province nearest the fight.
				lost = _nearest(map, _border(map, 0), map.regions[m.region].label)
				to = 1
		LiteMission.HOLD:
			if m.result == 1:
				lost = m.region
				to = 1
	return [lost, to]

## After a mission: the province changes hands, the sites standing are kept
## for the next one (a little repaired), and the clock moves on.
func after(m: LiteMission, sim: LiteSim, changed: Array[int]) -> void:
	var map: LiteMap = sim.map
	front = m.region
	rally_side = -1
	if changed[0] >= 0:
		owners[changed[0]] = changed[1]
		taken[changed[1]] += 1
		rally_side = 1 - changed[1]
		rally_name = map.regions[changed[0]].name
	results.append(m.result)
	history.append("%d. %s: %s" % [m.number, m.title, m.outcome])
	bonus = m.reward if m.optional_done else 0
	keep(sim, mission + 1)
	money = [sim.sides[0].money, sim.sides[1].money]
	clock += m.length + GAP_DAYS * LiteRules.DAY
	mission += 1

## How many factories and air defence sites the enemy brings into each
## mission at most: what it had beyond that was pulled back out of reach.
## This, more than the rally, keeps one bad mission from deciding the rest:
## an economy left to snowball across missions made them unwinnable.
const ENEMY_FACTORIES: Array[int] = [3, 4, 5]
const ENEMY_AD: Array[int] = [4, 8, 11]
## The fewest factories we start a mission with: plants evacuated to the rear.
const OUR_FACTORIES: int = 2

## Every site standing, with half its damage repaired in the days between,
## for mission `next`.
func keep(sim: LiteSim, next: int) -> void:
	sites = []
	var k: int = mini(next, ENEMY_FACTORIES.size() - 1)
	var cap: Vector2 = sim.sides[1].capital.pos
	# The enemy's sites furthest forward go first.
	var theirs: Array[LiteBuilding] = []
	for b: LiteBuilding in sim.buildings:
		if b.alive and b.side == 1 and b.kind != LiteKind.CAPITAL:
			theirs.append(b)
	theirs.sort_custom(func(a: LiteBuilding, b: LiteBuilding) -> bool: return a.pos.distance_to(cap) < b.pos.distance_to(cap))
	var dropped: Dictionary = {}
	var factories: int = 0
	var ad: int = 0
	for b: LiteBuilding in theirs:
		if b.kind == LiteKind.FACTORY:
			factories += 1
			if factories > ENEMY_FACTORIES[k]:
				dropped[b] = true
		else:
			ad += 1
			if ad > ENEMY_AD[k]:
				dropped[b] = true
	var ours: int = 0
	for b: LiteBuilding in sim.buildings:
		if b.alive and b.side == 0 and b.kind == LiteKind.FACTORY:
			ours += 1
	if ours < OUR_FACTORIES:
		var rng:= RandomNumberGenerator.new()
		rng.seed = map_seed + next * 101
		var rear: Array[int] = []
		for r: LiteRegion in sim.map.regions:
			if r.side == 0 and not r.city and not sim.map.on_front(r.id) and r.spots.size() > 0:
				rear.append(r.id)
		var tries: int = 0
		while ours < OUR_FACTORIES and rear.size() > 0 and tries < 20:
			tries += 1
			if _put(sim, 0, LiteKind.FACTORY, rear[rng.randi_range(0, rear.size() - 1)], rng) != null:
				ours += 1
	for b: LiteBuilding in sim.buildings:
		if not b.alive or dropped.has(b):
			continue
		var hp: float = b.hp + (b.max_hp - b.hp) * 0.5
		if b.kind == LiteKind.CAPITAL:
			hp = minf(b.max_hp, b.hp + 25.0)
		sites.append({"side": b.side, "kind": b.kind, "x": b.pos.x, "y": b.pos.y, "hp": hp,
			"build": b.build, "seen": b.seen[1 - b.side]})

var finished: bool:
	get: return mission >= MISSIONS.size()
