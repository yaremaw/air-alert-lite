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
## Saves of other versions are not loaded (3: operations on province maps;
## 4: smaller, compact regions; 5: small provinces merged on loading).
const SAVE_VERSION: int = 7
## Game days between two operations.
const GAP_DAYS: float = 2.0
## Money we start an operation with at least, and the most carried over.
const START_MONEY: float = 500.0
const MONEY_CARRIED: float = 600.0
## The enemy capital's defences: SAM batteries (and as many guns) for each
## province round it that the enemy still holds, on top of these.
const CAPITAL_BASE: int = 1

## The enemy capital can be attacked only once this many regions are taken:
## its region is never the first, nor the second, operation.
const CAPITAL_AFTER: int = 2

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
## Regions the enemy took unopposed after the last operation (its offensive
## met nobody), to show on the front; not saved.
var fallen: Array[int] = []
## Whether the offensive (counter) was launched after the last operation, so
## the front shows it coming; not saved.
var new_offensive: bool = false
## Power grids and EW hubs taken (see LiteMission.ENERGY, EW).
var blackouts: int = 0
var jammers: int = 0
## The whole campaign's figures, for its end (see LiteCampaignEnd).
var downed: int = 0
var sites: int = 0
## The kinds of region taken (LiteMission.INDUSTRY ...), one per region.
var kinds_taken: Array[int] = []
## Whether its opening slides have been shown (see LiteMain.show_front).
var intro_seen: bool = false
## Command points to spend in the war council, and what they bought: upgrade
## key to its level (see UPGRADES).
var points: int = 1
var upgrades: Dictionary = {}

# --- Phase 4 -------------------------------------------------------------------

## Both countries' morale (LiteMorale), carried from one operation to the
## next; at none the war is lost (won, the enemy's).
var morale: float = LiteMorale.START
var enemy_morale: float = LiteMorale.START
## Our stockpiles (LiteStock: drones, cruise, ballistic, interceptors),
## carried on.
var stock: Array = LiteStock.START.duplicate()
## Enemy radar networks broken (suppression operations won): later operations
## find them without their long-range radar.
var radar_cut: int = 0
## The enemy command's defences worn down by events.
var capital_weak: int = 0
## Damage our capital carries into the next operation (a raid nobody met).
var capital_scar: float = 0.0
## A threat to meet next (besides an offensive, `counter`): a coordinated
## raid on our capital (LiteMission.SURVIVE) or on our industry (PROTECT),
## and the group it aims at; -1 none.
var threat: int = -1
var threat_group: int = -1
## Events between operations (EV_*): what came up after the last one, to
## show and to apply to the next.
enum { EV_RAID, EV_ACCIDENT, EV_RADAR_OUT, EV_STORM, EV_REINFORCE, EV_GRID, EV_STORAGE, EV_UNREST, EV_COMMAND, EV_BATCH }
var events_next: Array[int] = []
## What the last operation changed, a line each, for the debrief; not saved.
var consequences: PackedStringArray = PackedStringArray()

static func event_title(e: int) -> String:
	match e:
		EV_RAID: return "Surprise raid"
		EV_ACCIDENT: return "Industrial accident"
		EV_RADAR_OUT: return "Radar network disrupted"
		EV_STORM: return "Storm approaching"
		EV_REINFORCE: return "Enemy reinforcements"
		EV_GRID: return "Power grid damaged"
		EV_STORAGE: return "Missile storage found"
		EV_UNREST: return "Unrest in the rear"
		EV_COMMAND: return "Enemy command exposed"
		_: return "Production batch ready"

static func event_text(e: int) -> String:
	match e:
		EV_RAID: return "The enemy struck the moment our last operation ended: the next one opens under a raid already in the air."
		EV_ACCIDENT: return "A fire at one of our plants. It starts the next operation heavily damaged and mends slowly."
		EV_RADAR_OUT: return "Sabotage on our radar network: the long-range radar is out for the next operation. Mobile radars will have to do."
		EV_STORM: return "A storm front is moving in: the next operation opens with drones grounded on both sides."
		EV_REINFORCE: return "Fresh SAM batteries have reached the enemy's front: expect two more where we strike next."
		EV_GRID: return "A substation went down: our radars near the capital run short of power for the first half day."
		EV_STORAGE: return "Intelligence found a missile storage site in the next target region: destroy it for a bonus."
		EV_UNREST: return "Funerals, blackouts, queues: the country is tired. National morale falls."
		EV_COMMAND: return "A defector gave away the layout of their command: its defences are weaker from now on."
		_: return "Our plants finished a big order: extra drones and missiles in the stockpile for the next operation."

## What having the plant hit by an accident repaired at once costs.
const ACCIDENT_FIX: int = 150
## The operation (ops) whose events have been shown on their page.
var events_shown: int = -1

static func event_good(e: int) -> bool:
	return e == EV_STORAGE or e == EV_COMMAND or e == EV_BATCH

## The war council's upgrades: [key, name, what each level does, most levels].
const UPGRADES: Array = [
	["bonds", "War bonds", "+$150 at the start of every operation", 3],
	["workshops", "Drone workshops", "Factories build drones 25% faster", 2],
	["racks", "Bigger SAM racks", "+2 interceptors in every SAM site", 2],
	["crews", "Trained SAM crews", "SAMs reload 25% faster", 2],
	["shelters", "Hardened factories", "Factories take 2 more hits", 2],
	["recon", "Recon network", "Enemy air defence in the target region located from the start", 1],
]

func level(key: String) -> int:
	return int(upgrades.get(key, 0))

## Spends a point on `key`, if there is one to spend and a level to buy.
func buy(key: String) -> bool:
	for u: Array in UPGRADES:
		if u[0] == key and points > 0 and level(key) < int(u[3]):
			upgrades[key] = level(key) + 1
			points -= 1
			return true
	return false
## -1 while the war goes on, 0 won (their capital fell), 1 lost (ours fell).
## (2, a ceasefire, is kept for the end page but no longer happens.)
var won: int = -1
var results: Array[int] = []
var history: PackedStringArray = PackedStringArray()
## The campaign's regions: provinces grouped a few together, so the front
## offers a handful of real choices rather than every province. Each
## province's group is named by its main province (the id the campaign uses
## for the group); cities follow their province. Worked out from the map as
## baked (see make_groups), so the same all campaign long.
var group_of: PackedInt32Array = PackedInt32Array()
## About how many provinces make a region: few enough for an operation's map
## to show its region large, not the whole country.
const GROUP_SIZE: float = 1.8
## The provinces that changed hands in the last operation, and to which side:
## the front shows them changing (see LiteMain.show_front); not saved.
var last_change: Array[int] = []
var last_change_to: int = -1

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
	c.blackouts = int(d.get("blackouts", 0))
	c.jammers = int(d.get("jammers", 0))
	c.downed = int(d.get("downed", 0))
	c.intro_seen = bool(d.get("intro_seen", false))
	c.points = int(d.get("points", 1))
	var ups: Variant = d.get("upgrades", {})
	if ups is Dictionary:
		for k: String in ups:
			c.upgrades[k] = int(ups[k])
	c.sites = int(d.get("sites", 0))
	for k: Variant in d.get("kinds_taken", []):
		c.kinds_taken.append(int(k))
	c.won = int(d["won"])
	for r: Variant in d["results"]:
		c.results.append(int(r))
	c.history = PackedStringArray(d["history"])
	c.morale = float(d.get("morale", LiteMorale.START))
	c.enemy_morale = float(d.get("enemy_morale", LiteMorale.START))
	var st: Variant = d.get("stock", [])
	if st is Array and (st as Array).size() == 4:
		c.stock = [float(st[0]), float(st[1]), float(st[2]), float(st[3])]
	c.radar_cut = int(d.get("radar_cut", 0))
	c.capital_weak = int(d.get("capital_weak", 0))
	c.capital_scar = float(d.get("capital_scar", 0.0))
	c.threat = int(d.get("threat", -1))
	c.threat_group = int(d.get("threat_group", -1))
	for e: Variant in d.get("events_next", []):
		c.events_next.append(int(e))
	if c.won >= 0:
		return null
	return c

func save() -> void:
	var owners_: Dictionary = {}
	for k: int in owners:
		owners_[str(k)] = owners[k]
	var d: Dictionary = {"version": SAVE_VERSION, "map_seed": map_seed, "difficulty": difficulty,
		"owners": owners_, "clock": clock, "money": money, "ops": ops, "taken": taken, "bonus": bonus,
		"income_bonus": income_bonus, "supply": supply, "enemy_cut": enemy_cut, "counter": counter, "blackouts": blackouts, "jammers": jammers, "downed": downed, "sites": sites, "intro_seen": intro_seen, "points": points, "upgrades": upgrades, "kinds_taken": kinds_taken,
		"won": won, "results": results, "history": history,
		"morale": morale, "enemy_morale": enemy_morale, "stock": stock, "radar_cut": radar_cut, "capital_weak": capital_weak,
		"capital_scar": capital_scar, "threat": threat, "threat_group": threat_group, "events_next": events_next}
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
		f.close()

static func forget() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

## Groups the provinces of a freshly loaded map (sides as baked) into
## compact regions of a few provinces each: for each side, its capital's
## province and others as far from each other as can be seed the groups,
## which then grow outwards a province at a time, always the province nearest
## (by its centre) to the seed of a group next to it, a large group a little
## less eager; so each group is one piece and roughly round, not a long strip.
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
		var count: int = clampi(roundi(provs.size() / GROUP_SIZE), 4, 9)
		count = mini(count, provs.size())
		var seeds: Array[int] = [map.capital_province(side)]
		while seeds.size() < count:
			var best: int = -1
			var bd: float = -1.0
			for p: int in provs:
				if seeds.has(p):
					continue
				var d: float = INF
				for sd: int in seeds:
					d = minf(d, _wide(map.regions[p].label, map.regions[sd].label))
				if d > bd:
					bd = d
					best = p
			if best < 0:
				break
			seeds.append(best)
		var size: Dictionary = {}
		for sd: int in seeds:
			group_of[sd] = sd
			size[sd] = 1
		while true:
			var pick: int = -1
			var to: int = -1
			var pd: float = INF
			for p: int in provs:
				if group_of[p] < 0:
					continue
				var g: int = group_of[p]
				for n: int in map.provinces_next_to(p):
					if group_of[n] >= 0 or map.regions[n].side != side or map.regions[n].city:
						continue
					var d: float = _wide(map.regions[n].label, map.regions[g].label) * (1.0 + 0.6 * int(size[g]))
					if d < pd:
						pd = d
						pick = n
						to = g
			if pick < 0:
				break
			group_of[pick] = to
			size[to] = int(size[to]) + 1
		# Any province no group reached (cut off by the sea) joins the nearest.
		for p: int in provs:
			if group_of[p] >= 0:
				continue
			var near: int = seeds[0]
			for sd: int in seeds:
				if _wide(map.regions[p].label, map.regions[sd].label) < _wide(map.regions[p].label, map.regions[near].label):
					near = sd
			group_of[p] = near
	for r: LiteRegion in map.regions:
		if r.city and r.parent >= 0:
			group_of[r.id] = group_of[r.parent]

## How far apart two places are for grouping provinces: north-south counts
## WIDE times east-west, so groups come out wide and low, like the screen an
## operation is fought on.
const WIDE: float = 1.8

static func _wide(a: Vector2, b: Vector2) -> float:
	var d: Vector2 = b - a
	return Vector2(d.x, d.y * WIDE).length()

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

## Whether the enemy capital's region is still out of reach: not until
## CAPITAL_AFTER regions are taken.
func capital_locked() -> bool:
	return taken[0] < CAPITAL_AFTER

## What can be done next: hold the group under attack, if one is; else
## attack any enemy group on the front; the capital's too once enough regions
## are taken (see CAPITAL_AFTER), or when it is all that is left to attack.
func options(map: LiteMap) -> Array[int]:
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
	# The capital's group last, and not before its time.
	var cap: int = group_at(map.capital_province(1))
	if out.has(cap):
		out.erase(cap)
		if not capital_locked() or out.is_empty():
			out.append(cap)
	# An enemy offensive under way: holding the region it aims at is one of
	# the choices (the first). Attack elsewhere, and it falls.
	if counter >= 0 and map.regions[counter].side == 0:
		out.insert(0, counter)
	# A raid coming (on the capital, or our industry): meeting it is a choice
	# too. Ignore it, and it lands unopposed.
	if threat >= 0 and threat_group >= 0 and map.regions[threat_group].side == 0 and not out.has(threat_group):
		out.insert(0, threat_group)
	return out

## Which weapons both sides have in operation `op` (counted from 0): drones
## only at first, cruise missiles from the second, ballistic from the fourth.
static func arms_at(op: int) -> Array:
	return [true, op >= 1, op >= 3]

## Our AA gun in operation `op` (phase 4c): gun trucks at first, the
## armoured AA guns from the third operation on (the trucks go then).
static func gun_kind_at(op: int) -> int:
	return LiteKind.MOBILE if op < 2 else LiteKind.GUN

## The operation each front option would be (make_op), worked out once while
## the front is up (see preview), for its card, its badge and its plan.
var _preview: Dictionary = {}
var _preview_ops: int = -1

func preview(map: LiteMap, province: int) -> LiteMission:
	if _preview_ops != ops:
		_preview.clear()
		_preview_ops = ops
	if not _preview.has(province):
		_preview[province] = make_op(map, province)
	return _preview[province]

func clear_preview() -> void:
	_preview.clear()

## Operations lost so far (for the Iron Will achievement).
var losses: int = 0

## The last operation whose new equipment was shown (LiteUnlock), -1 none.
var revealed: int = -1

## What we have to fight with by now: the gun of the day, no SAMs in the
## first operation; the sites already standing (the war's own start, see
## LiteSim.setup) made to match.
func _equip(sim: LiteSim) -> void:
	var gk: int = gun_kind_at(ops)
	sim.gun_kind[0] = gk
	sim.no_build[0] = [LiteKind.SAM] if ops < 1 else []
	# Jet drones in place of the propeller ones: ours from the third
	# operation, the enemy's from the fifth.
	sim.jet_drones[0] = ops >= 2
	if ops >= 2 and not LiteSettings.jets and not LiteSettings.dry:
		LiteSettings.jets = true
		LiteSettings.save()
	sim.jet_drones[1] = ops >= 4
	for b: LiteBuilding in sim.buildings:
		if b.side != 0 or not b.alive:
			continue
		if ((b.kind == LiteKind.GUN or b.kind == LiteKind.MOBILE) and b.kind != gk) or (b.kind == LiteKind.SAM and ops < 1):
			b.kind = gk
			b.max_hp = LiteRules.max_hp(gk)
			b.hp = b.max_hp
			b.ammo = LiteRules.MOBILE_MAG if gk == LiteKind.MOBILE else LiteRules.GUN_MAG
			b.home = -1

## How strong the enemy is in operation `op`: weak at first, at full strength
## from the fourth.
static func enemy_strength(op: int) -> float:
	return [0.7, 0.8, 0.9][op] if op < 3 else 1.0

static func arms_text(arms: Array) -> String:
	var names: PackedStringArray = PackedStringArray()
	for a: int in 3:
		if arms[a]:
			names.append(["drones", "cruise missiles", "ballistic missiles"][a])
	return ", ".join(names)

## The enemy capital's defences now: one SAM battery and one gun for each
## region round the capital's that the enemy still holds, and CAPITAL_BASE
## more. Taking those regions wears it down.
func capital_defence(map: LiteMap) -> int:
	var n: int = CAPITAL_BASE - capital_weak
	for g: int in groups_next_to(map, group_at(map.capital_province(1))):
		if map.regions[g].side == 1:
			n += 1
	return maxi(1, n)

## What a province is: the same for it all campaign long.
## For tests (`--lite-kinds=`): every region of this kind, when 0 or more.
static var force_character: int = -1

## Whether a region's coast has a port worth an operation: about a third of
## the coastal ones, the same all campaign long.
func has_port(province: int) -> bool:
	return posmod(hash(str(map_seed) + ":port:" + str(province)), 3) == 0

func character(province: int) -> int:
	if force_character >= 0:
		return force_character
	var h: int = hash(str(map_seed) + ":" + str(province))
	return posmod(h, LiteMission.CHARACTERS)

## The operation over `province`: its kind, deadline, goals and briefing.
func make_op(map: LiteMap, province: int) -> LiteMission:
	var m:= LiteMission.new()
	m.number = ops + 1
	m.province = province
	m.provinces = group(province)
	m.region_name = group_name(map, province)
	m.character = character(province)
	var r: String = m.region_name
	var rng:= RandomNumberGenerator.new()
	rng.seed = map_seed * 7 + ops * 31 + province
	if map.regions[province].side == 0 and province == threat_group and threat == LiteMission.SURVIVE:
		m.kind = LiteMission.SURVIVE
		m.title = "Weather the storm over %s" % map.capital_name[0].trim_prefix("HQ ")
		m.label = "Defend the capital"
		m.days = 4.0
		m.cap_limit = 20.0
		m.morale_floor = 0.0
		m.set_bonus([[LiteMission.CAPITAL_SAFE, 8, 200], [LiteMission.SHOOT_DOWN, 50, 150]])
		m.intel.append("Waves aimed at the capital")
		m.notes.append("If the capital is hit %d times, the operation fails." % roundi(m.cap_limit))
	elif map.regions[province].side == 0 and province == threat_group and threat == LiteMission.PROTECT:
		m.kind = LiteMission.PROTECT
		if rng.randf() < 0.5:
			m.plot = LiteMission.PLOT_EVAC
			m.may_lose = 2
		m.title = ("Evacuate %s" % r) if m.plot == LiteMission.PLOT_EVAC else ("Keep the lines running in %s" % r)
		m.label = "Defend our industry"
		m.days = 4.0
		m.need = 2
		m.set_bonus([[LiteMission.NO_FACTORY_LOST, 0, 200], [LiteMission.SHOOT_DOWN, 40, 100]])
		m.intel.append("Our plants are the target")
		m.notes.append("Lose %d factories there and the operation fails. Damaged plants mend themselves between raids." % m.need)
	elif map.regions[province].side == 0:
		m.kind = LiteMission.HOLD
		m.plot = LiteMission.PLOT_ASSAULT
		m.title = "Hold %s" % r
		m.days = 4.0
		m.need = 30
		m.set_bonus([[LiteMission.SHOOT_DOWN, 40, 200], [LiteMission.NO_FACTORY_LOST, 0, 100]])
		m.label = "Hold the line"
		m.notes.append("Enemy armour with its own AA drives on the town. If one column reaches it, the region falls.")
	elif province == group_at(map.capital_province(1)):
		m.kind = LiteMission.CAPITAL
		m.title = "Strike at the heart"
		m.label = "Decapitation strike"
		m.days = 7.0
		m.set_bonus([[LiteMission.SHOOT_DOWN, 60, 0], [LiteMission.CAPITAL_SAFE, 10, 0]])
		m.need = capital_defence(map)
		m.cap_target = 24 + 2 * m.need
		m.briefing = ("%s is within reach. Strike its command again and again until the government gives up: it is " +
			"the best defended ground the enemy has.") % map.capital_name[1]
	else:
		m.kind = LiteMission.STRIKE
		m.days = 6.0
		# A region on the sea (not one whose plot is its industry or its rail
		# line): its port and the tankers loading there.
		var coast: Array = []
		if m.character != LiteMission.INDUSTRY and m.character != LiteMission.LOGISTICS and has_port(province):
			var members: Array[int] = m.provinces
			coast = coast_of(map, func(q: Vector2) -> bool: return members.has(map.province(map.region_at(q))))
		if not coast.is_empty():
			m.plot = LiteMission.PLOT_PORT
			m.objective = coast[1]
			m.title = "Close the port of %s" % r
			m.label = "Port strike"
			m.notes.append("Destroy the oil terminal and the cargo docks. The port is ringed with SAMs and guns.")
			m.notes.append("Cargo ships sail one by one: each one sunk earns a command point. Each one that gets away pays for another SAM battery at the port.")
		match -1 if not coast.is_empty() else m.character:
			LiteMission.INDUSTRY:
				# Their armour on the move (phase 4b; the plants were once the target).
				m.plot = LiteMission.PLOT_COLUMN
				m.title = "Stop the armour at %s" % r
				m.label = "Interdiction"
				m.days = 5.0
				m.notes.append("Armoured columns are making for our border. Destroy every one on the road: if one gets across, the operation fails.")
				m.notes.append("Strikes home in on a moving column once close. Their air defence watches the roads.")
			LiteMission.LOGISTICS:
				m.plot = LiteMission.PLOT_TRAIN
				m.title = "Stop the train at %s" % r
				m.label = "Rail strike"
				m.days = 5.0
				m.notes.append("An ammunition train runs for their front. Wreck the engine before it gets there; each wagon burnt pays $60.")
			-1:
				pass
			LiteMission.ENERGY:
				m.plot = LiteMission.PLOT_GRID
				m.title = "Black out %s" % r
				m.label = "Grid strike"
				m.repair_limit = 3
				m.notes.append("Two power stations. Knock one out and a repair crew drives out from the town to mend it: have both down at once.")
				m.notes.append("If their crews mend %d stations, the operation fails. A crew burnt on the road buys time." % m.repair_limit)
			LiteMission.EW:
				m.plot = LiteMission.PLOT_DEPOT
				m.title = "Silence the jammers at %s" % r
				m.label = "Depot strike"
				m.escape_limit = 3
				m.notes.append("A jammer covers the depot that supplies their front: drones flying into its circle are often lost, missiles are not fooled.")
				m.notes.append("A supply convoy leaves the depot for the front every few hours. If %d get through, the operation fails." % m.escape_limit)
			_:
				m.plot = LiteMission.PLOT_HUNT
				m.title = "Hunt the launchers of %s" % r
				m.label = "Launcher hunt"
				m.salvo_limit = 6 if ops == 0 else 5
				m.notes.append("Three mobile launchers fire from cover and move on. A salvo gives one away for half a minute; our drones overhead find them too.")
				m.notes.append("If %d salvos land, our troops pull back and the operation fails." % m.salvo_limit)
		if m.plot == LiteMission.PLOT_PORT:
			m.notes.append("Taking it: their oil export stops (the enemy has 10% less to spend).")
		if m.label == "":
			m.label = "Strike"
		# Some strikes are against the clock: not a deadline that fails the
		# operation (players hated those), but a big reward for being quick,
		# and enemy reinforcements once the time is up (see setup).
		var quick: int = 0
		if m.plot == LiteMission.PLOT_NONE and m.character != LiteMission.MILITARY and ops >= 1 and rng.randf() < 0.4:
			quick = 3 if m.character == LiteMission.INDUSTRY else 4
			m.label = "Timed strike"
			m.notes.append("Against the clock: finish within %d days for +$300. After that, fresh SAM batteries reach the targets." % quick)
		var pool: Array = [[LiteMission.NO_FACTORY_LOST, 0, 150], [LiteMission.CAPITAL_SAFE, 5, 150], [LiteMission.RADARS_DOWN, 1, 150]]
		if quick == 0:
			pool.append([LiteMission.FAST, 3, 200])
		var first: Array = [LiteMission.FAST, quick, 300] if quick > 0 else pool[rng.randi_range(0, pool.size() - 1)]
		pool.erase(first)
		var second: Array = pool[rng.randi_range(0, pool.size() - 1)]
		m.set_bonus([first, second])
		m.notes.append("Taking it: " + LiteMission.character_reward(m.character))
	# Conditions, now and then once the war is under way.
	if ops >= 1 and rng.randf() < 0.55:
		var c: int = rng.randi_range(0, LiteMission.C_HIDDEN)
		if not (c == LiteMission.C_HIDDEN and (m.defensive or m.kind == LiteMission.CAPITAL or m.plot != LiteMission.PLOT_NONE)):
			m.conditions.append(c)
	if events_next.has(EV_STORM) and not m.conditions.has(LiteMission.C_STORM):
		m.conditions.append(LiteMission.C_STORM)
	if events_next.has(EV_RADAR_OUT) and not m.conditions.has(LiteMission.C_BLIND):
		m.conditions.append(LiteMission.C_BLIND)
	for c: int in m.conditions:
		m.notes.append("%s: %s" % [LiteMission.CONDITION_NAMES[c], LiteMission.CONDITION_TEXT[c]])
	# What intelligence says to expect.
	if not m.defensive:
		match m.plot:
			LiteMission.PLOT_COLUMN: m.intel.append("Columns tracked by our drones")
			LiteMission.PLOT_TRAIN: m.intel.append("Rail line known")
			LiteMission.PLOT_HUNT: m.intel.append("Launchers hide between salvos")
			LiteMission.PLOT_PORT: m.intel.append("Cargo ships at the quay")
			LiteMission.PLOT_GRID: m.intel.append("Repair crews in the town")
			LiteMission.PLOT_DEPOT: m.intel.append("Convoys on the roads")
			_: m.intel.append("Targets hidden" if m.conditions.has(LiteMission.C_HIDDEN) or m.character == LiteMission.MILITARY and m.label != "Air-defence suppression" else "Targets located")
		m.intel.append("Radar network broken" if radar_cut > 0 else ("No radar network yet" if ops < 2 else "Radar network: hit it first"))
	m.intel.append("Threats: %s" % arms_text(arms_at(ops)))
	m.intel.append("Weather: %s" % ("storm" if m.conditions.has(LiteMission.C_STORM) else "changeable"))
	m.notes.append("Weapons on both sides: %s." % arms_text(arms_at(ops)))
	if ops == 1 or ops == 3:
		m.notes.append("New: %s." % ("cruise missiles" if ops == 1 else "ballistic missiles"))
	if bonus > 0:
		m.notes.append("Reward from the last operation: $%d." % bonus)
	m.briefing = LiteStory.briefing(m, map, ops)
	if supply > 0:
		m.notes.append("Depots taken earlier: +$%d." % supply)
	if blackouts > 0:
		m.notes.append("Their grid is cut: enemy SAMs silent for the first half day.")
	if jammers > 0:
		m.notes.append("Our own jammer guards our command.")
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
	_equip(sim)
	# An operation is its task, ours and the enemy's: no national morale in it
	# (that is the single war's, see LiteMorale).
	for sd: LiteSide in sim.sides:
		sd.morale_on = false
	# Early in the war both sides are short of weapons, the enemy of strength.
	var arms: Array = arms_at(ops)
	sim.arms = [arms.duplicate(), arms.duplicate()]
	sim.income_scale[1] *= enemy_strength(ops)
	sim.sides[0].money = maxf(START_MONEY, minf(money, MONEY_CARRIED)) + bonus + supply + 150 * level("bonds")
	# The war council's upgrades.
	sim.arm_off[0][LiteArm.DRONE] = 2 * level("workshops")
	sim.drone_rate[0] = 0.25 * level("workshops")
	sim.rack[0] = LiteRules.SAM_RACK + 2 * level("racks")
	sim.reload_mul[0] = 1.0 - 0.25 * level("crews")
	sim.factory_hp[0] = 2.0 * level("shelters")
	for b: LiteBuilding in sim.buildings:
		if b.side == 0 and b.kind == LiteKind.SAM:
			b.ammo = sim.rack[0]
		elif b.side == 0 and b.kind == LiteKind.FACTORY:
			b.max_hp += sim.factory_hp[0]
			b.hp = b.max_hp
	sim.income_scale[0] *= 1.0 + income_bonus
	sim.income_scale[1] *= maxf(0.5, 1.0 - enemy_cut)
	# Phase 4: morale and stockpiles carry on from the last operation.
	sim.sides[0].morale = morale
	sim.sides[1].morale = enemy_morale
	for l: int in 4:
		sim.sides[0].stock[l] = float(stock[l])
	# The enemy's stockpiles thinner for every factory region lost.
	for l: int in 4:
		sim.sides[1].stock[l] *= maxf(0.4, 1.0 - enemy_cut * 2.0)
	if capital_scar > 0.0:
		sim.sides[0].capital.hp = maxf(sim.sides[0].capital.max_hp * 0.4, sim.sides[0].capital.hp - capital_scar)
	_conditions(m, sim, ai)
	_apply_events(m, sim, ai)
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
			ai.ad_limit = 5
			match -1 if m.plot == LiteMission.PLOT_PORT else m.character:
				-1: _port(m, sim, rng)
				LiteMission.INDUSTRY: _column(m, sim, ai, rng)
				LiteMission.LOGISTICS: _train(m, sim, rng)
				LiteMission.ENERGY:
					_grid(m, sim, districts, rng)
					m.objective = _their_town(sim)
				LiteMission.EW:
					_ew(m, sim, districts, rng)
					m.next_convoy = LiteRules.DAY * 0.5
				_:
					if m.label == "Air-defence suppression":
						_radars(m, sim, ai, districts, rng)
					elif m.plot == LiteMission.PLOT_HUNT:
						_hunt(m, sim, districts, rng)
					else:
						_air_base(m, sim, districts, rng)
			# Now and then a power station feeds their air defence here: not a
			# target, but knocking it out silences their SAMs for a day.
			if m.character != LiteMission.ENERGY and rng.randf() < 0.5:
				_power_aside(m, sim, rng)
		LiteMission.CAPITAL:
			var cap: LiteBuilding = sim.sides[1].capital
			m.targets.append(cap)
			for k: int in m.need:
				var p: Variant = sim.find_spot(1, cap.pos, 44, 66)
				if p != null:
					sim.add(1, LiteKind.SAM, p, true)
				var g: Variant = sim.find_spot(1, cap.pos, 44, 60)
				if g != null:
					sim.add(1, LiteKind.GUN, g, true)
			ai.ad_limit = 4
		LiteMission.SURVIVE:
			# Their whole strike force at our capital, in waves.
			sim.income_scale[1] *= 1.3
			ai.war_share += 0.15
			ai.waves = true
			var cap_set:= PackedInt32Array()
			for id: int in map.focus:
				cap_set.append(id)
			cap_set.append(map.region_at(sim.sides[0].capital.pos))
			ai.focus_set = cap_set
			ai.focus_weight = 4.0
			ai.hold_until(25.0)
			sim.sides[1].money += 600
			# Their stockpiles filled for it: this is their big push.
			sim.sides[1].stock[LiteStock.DRONES] += 40.0
			sim.sides[1].stock[LiteStock.CRUISE] += 8.0
			sim.sides[1].stock[LiteStock.BALLISTIC] += 3.0
			for b: LiteBuilding in sim.buildings:
				if b.side == 0:
					b.seen[1] = true
		LiteMission.PROTECT:
			# Our plants, and the enemy after them.
			for id: int in districts.slice(0, 3):
				var f: LiteBuilding = _put(sim, 0, LiteKind.FACTORY, id, rng)
				if f != null:
					f.seen[1] = true
			for b: LiteBuilding in sim.buildings:
				if b.side == 0 and b.kind == LiteKind.FACTORY:
					b.seen[1] = true
			sim.income_scale[1] *= 1.15
			ai.war_share += 0.1
			ai.focus_set = map.focus
			ai.focus_weight = 3.5
			ai.hold_until(35.0)
		LiteMission.HOLD:
			# Engineers dig in where the offensive is coming.
			for id: int in districts.slice(0, 2):
				var f: LiteBuilding = _put(sim, 0, LiteKind.FACTORY, id, rng)
				if f != null:
					var sam: Variant = sim.find_spot(0, f.pos, 19, 32)
					if sam != null:
						sim.add(0, LiteKind.SAM if sim.may_build(0, LiteKind.SAM) else sim.gun_kind[0], sam, true)
			for b: LiteBuilding in sim.buildings:
				if b.side == 0 and map.focus.has(map.province(b.region)):
					b.seen[1] = true
			sim.income_scale[1] *= 1.2
			ai.war_share += 0.1
			ai.focus_set = map.focus
			ai.focus_weight = 3.0
			ai.hold_until(40.0)
	match m.plot:
		LiteMission.PLOT_ASSAULT: _assault(m, sim, ai, rng)
		LiteMission.PLOT_EVAC: _evac(m, sim, rng)
	# The recon network: the enemy's air defence in the region, located.
	if level("recon") > 0:
		for b: LiteBuilding in sim.buildings:
			if b.alive and b.side == 1 and (b.is_ad or b.is_gun) and map.focus.has(b.region):
				sim.spot(b, 0)
	# What earlier operations won: their grid cut, our jammer.
	if blackouts > 0:
		sim.sam_off_until[1] = maxf(sim.sam_off_until[1], LiteRules.DAY * 0.5)
	if jammers > 0:
		var jp: Variant = sim.find_spot(0, sim.sides[0].capital.pos, 44, 60)
		if jp != null:
			sim.add(0, LiteKind.JAMMER, jp, true)
	# Events, at random times between a sixth and four fifths of the way:
	# three in an attack, two in a defence.
	var pool: Array[int] = [LiteMission.STORM, LiteMission.SUPPLY]
	var count: int = 2
	if m.kind == LiteMission.HOLD:
		pool.append(LiteMission.RAID)
	else:
		pool.append_array([LiteMission.INTEL, LiteMission.REINFORCE, LiteMission.SABOTAGE, LiteMission.OUTAGE, LiteMission.CONVOY,
			LiteMission.DEFECTOR, LiteMission.VOLUNTEERS])
		count = 3
	for k: int in count:
		var e: int = pool[rng.randi_range(0, pool.size() - 1)]
		pool.erase(e)
		m.events.append([m.length * rng.randf_range(0.16, 0.8), e])
	# A timed strike: reinforcements when the time is up.
	if m.label == "Timed strike" and not m.bonus.is_empty() and int(m.bonus[0][0]) == LiteMission.FAST:
		var t: float = float(m.bonus[0][1]) * LiteRules.DAY
		m.events.append([t, LiteMission.REINFORCE])
		m.events.append([t + 2.0, LiteMission.REINFORCE])
	m.events.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])

## An operation's conditions (LiteMission.C_*): what they do to its war.
func _conditions(m: LiteMission, sim: LiteSim, ai: LiteAi) -> void:
	for c: int in m.conditions:
		match c:
			LiteMission.C_NIGHT:
				# The clock is set by LiteMain.launch_operation: ten at night.
				pass
			LiteMission.C_STORM:
				sim.env.force(LiteEnv.STORM if sim.env.climate != LiteBiome.WINTER else LiteEnv.SNOWSTORM, 0.0, LiteRules.DAY * 0.6)
				sim.env.blend = 1.0
			LiteMission.C_LIMITED:
				sim.sides[0].money *= 0.5
				for l: int in 3:
					sim.sides[0].stock[l] = minf(sim.sides[0].stock[l], LiteStock.START[l])
				sim.income_scale[0] *= 0.8
			LiteMission.C_BLIND:
				for b: LiteBuilding in sim.buildings:
					if b.side == 0 and b.kind == LiteKind.RADAR:
						b.alive = false
						b.dead_at = 0.0
			LiteMission.C_HIDDEN:
				for t: LiteBuilding in m.targets:
					t.seen[0] = false

## The events that came up since the last operation, as they land on this one.
func _apply_events(m: LiteMission, sim: LiteSim, ai: LiteAi) -> void:
	for e: int in events_next:
		match e:
			EV_RAID:
				sim.sides[1].money += 350
				sim.sides[1].war_fund += 350
				ai.hold_until(5.0)
			EV_ACCIDENT:
				for b: LiteBuilding in sim.buildings:
					if b.side == 0 and b.kind == LiteKind.FACTORY:
						b.hp = b.max_hp * 0.35
						break
			EV_REINFORCE:
				var at: Vector2 = sim.sides[1].capital.pos
				for t: LiteBuilding in m.targets:
					at = t.pos
					break
				for k: int in 2:
					var q: Variant = sim.find_spot(1, at, 22, 60)
					if q != null:
						sim.add(1, LiteKind.SAM, q, true)
			EV_GRID:
				sim.grid_off_until[0] = LiteRules.DAY * 0.5
				sim.grid_off_at[0] = sim.sides[0].capital.pos
			EV_STORAGE:
				if not m.defensive and not map_focus_empty(sim):
					var spots: Array[int] = []
					for id: int in sim.map.focus:
						if sim.map.regions[id].spots.size() > 0 and sim.map.regions[id].side == 1:
							spots.append(id)
					if not spots.is_empty():
						var rng:= RandomNumberGenerator.new()
						rng.seed = map_seed + ops
						var d: LiteBuilding = _put(sim, 1, LiteKind.DEPOT, spots[rng.randi_range(0, spots.size() - 1)], rng)
						if d != null:
							d.seen[0] = true
							m.convoy = d
							m.convoy_until = 1e9
			EV_BATCH:
				sim.sides[0].stock[LiteStock.DRONES] += 10.0
				if sim.has_arm(0, LiteArm.CRUISE):
					sim.sides[0].stock[LiteStock.CRUISE] += 3.0
				if sim.has_arm(0, LiteArm.BALLISTIC):
					sim.sides[0].stock[LiteStock.BALLISTIC] += 1.0
	# Their radar network, broken earlier (or not yet up, in the first two
	# operations: a learning curve): no long-range radar this time.
	if radar_cut > 0 or ops < 2:
		for b: LiteBuilding in sim.buildings:
			if b.side == 1 and b.kind == LiteKind.RADAR:
				b.alive = false
				b.dead_at = 0.0

static func map_focus_empty(sim: LiteSim) -> bool:
	return sim.map.focus.is_empty()

## The plants: three factories side by side in the province's biggest
## district, two SAM batteries and two guns round them.
static func _industry(m: LiteMission, sim: LiteSim, ai: LiteAi, districts: Array[int], rng: RandomNumberGenerator) -> void:
	var map: LiteMap = sim.map
	var best: int = map.focus[0]
	for id: int in districts:
		if map.regions[id].spots.size() > map.regions[best].spots.size():
			best = id
	var first: LiteBuilding = _put(sim, 1, LiteKind.FACTORY, best, rng)
	if first == null:
		return
	first.seen[0] = true
	m.targets.append(first)
	var mid: Vector2 = first.pos
	for k: int in 2:
		var p: Variant = sim.find_spot(1, first.pos, 19, 30)
		if p == null:
			continue
		var t: LiteBuilding = sim.add(1, LiteKind.FACTORY, p, true)
		t.seen[0] = true
		m.targets.append(t)
		mid += t.pos
	mid /= m.targets.size()
	# Phase 4: one SAM battery (radar-linked, it hits far harder than before),
	# guns close in, a mobile unit.
	for k: int in 2:
		var s: Variant = sim.find_spot(1, mid, 18, 38) if k == 0 or LiteSim.classic_rules else null
		if s != null:
			sim.add(1, LiteKind.SAM, s, true)
		var g: Variant = sim.find_spot(1, mid, 19, 34)
		if g != null:
			sim.add(1, LiteKind.GUN, g, true)
	ai.ad_limit = 6

## The supply hub: two depots as far apart as its districts allow, a gun by
## each.
static func _supply(m: LiteMission, sim: LiteSim, districts: Array[int], rng: RandomNumberGenerator) -> void:
	var map: LiteMap = sim.map
	var a: int = districts[0] if not districts.is_empty() else map.focus[0]
	var b: int = a
	var far: float = -1.0
	for i: int in districts:
		for j: int in districts:
			var d: float = map.regions[i].center.distance_to(map.regions[j].center)
			if d > far:
				far = d
				a = i
				b = j
	for id: int in [a, b]:
		var t: LiteBuilding = _put(sim, 1, LiteKind.DEPOT, id, rng)
		if t == null:
			continue
		t.seen[0] = true
		m.targets.append(t)
		var gun: Variant = sim.find_spot(1, t.pos, 19, 30)
		if gun != null:
			sim.add(1, LiteKind.GUN, gun, true)

## The air base: a radar and a launch site in different districts, both
## hidden until our drones find them; a SAM and a gun by the radar.
static func _air_base(m: LiteMission, sim: LiteSim, districts: Array[int], rng: RandomNumberGenerator) -> void:
	var map: LiteMap = sim.map
	var kinds: Array[int] = [LiteKind.RADAR, LiteKind.LAUNCHER]
	for k: int in 2:
		var at: int = districts[k % districts.size()] if not districts.is_empty() else map.focus[0]
		var t: LiteBuilding = _put(sim, 1, kinds[k], at, rng)
		if t == null:
			continue
		t.seen[0] = false
		m.targets.append(t)
		var gun: Variant = sim.find_spot(1, t.pos, 19, 30)
		if gun != null:
			sim.add(1, LiteKind.GUN, gun, true)
	if not m.targets.is_empty():
		var sam: Variant = sim.find_spot(1, m.targets[0].pos, 19, 34)
		if sam != null:
			sim.add(1, LiteKind.SAM, sam, true)

## Their radar network: a long-range radar and a mobile one in different
## districts, each with SAMs it links and a gun; more batteries round them.
static func _radars(m: LiteMission, sim: LiteSim, ai: LiteAi, districts: Array[int], rng: RandomNumberGenerator) -> void:
	var map: LiteMap = sim.map
	var kinds: Array[int] = [LiteKind.RADAR, LiteKind.RADAR]
	for k: int in 2:
		var at: int = districts[k % maxi(1, districts.size())] if not districts.is_empty() else map.focus[0]
		var t: LiteBuilding = _put(sim, 1, kinds[k], at, rng)
		if t == null:
			continue
		t.seen[0] = true
		m.targets.append(t)
		for j: int in 2:
			var q: Variant = sim.find_spot(1, t.pos, 20, 60)
			if q != null:
				sim.add(1, LiteKind.SAM if j == 0 else LiteKind.GUN, q, true)
	ai.ad_limit = 5

## The power grid: two stations in districts far apart, a SAM and a gun by
## each.
static func _grid(m: LiteMission, sim: LiteSim, districts: Array[int], rng: RandomNumberGenerator) -> void:
	var map: LiteMap = sim.map
	var a: int = districts[0] if not districts.is_empty() else map.focus[0]
	var b: int = a
	var far: float = -1.0
	for i: int in districts:
		for j: int in districts:
			var d: float = map.regions[i].center.distance_to(map.regions[j].center)
			if d > far:
				far = d
				a = i
				b = j
	for id: int in [a, b]:
		var t: LiteBuilding = _put(sim, 1, LiteKind.POWER, id, rng)
		if t == null:
			continue
		t.seen[0] = true
		m.targets.append(t)
		var s: Variant = sim.find_spot(1, t.pos, 19, 34)
		if s != null:
			sim.add(1, LiteKind.SAM, s, true)
		var g: Variant = sim.find_spot(1, t.pos, 19, 30)
		if g != null:
			sim.add(1, LiteKind.GUN, g, true)

## The EW hub: a jammer, and an ammunition depot under its cover; guns by
## both.
static func _ew(m: LiteMission, sim: LiteSim, districts: Array[int], rng: RandomNumberGenerator) -> void:
	var map: LiteMap = sim.map
	var at: int = districts[0] if not districts.is_empty() else map.focus[0]
	var j: LiteBuilding = _put(sim, 1, LiteKind.JAMMER, at, rng)
	if j == null:
		return
	j.seen[0] = true
	m.targets.append(j)
	var dp: Variant = sim.find_spot(1, j.pos, 20, LiteRules.JAMMER_RANGE * 0.7)
	if dp != null:
		var d: LiteBuilding = sim.add(1, LiteKind.DEPOT, dp, true)
		d.seen[0] = true
		m.targets.append(d)
	for t: LiteBuilding in m.targets.duplicate():
		var g: Variant = sim.find_spot(1, t.pos, 19, 30)
		if g != null:
			sim.add(1, LiteKind.GUN, g, true)

## A power station feeding the enemy's air defence, away from the targets.
static func _power_aside(m: LiteMission, sim: LiteSim, rng: RandomNumberGenerator) -> void:
	var map: LiteMap = sim.map
	var spots: Array[int] = []
	for r: LiteRegion in map.regions:
		if r.side == 1 and not map.focus.has(r.id) and r.spots.size() > 0:
			spots.append(r.id)
	if spots.is_empty():
		return
	var p: LiteBuilding = _put(sim, 1, LiteKind.POWER, spots[rng.randi_range(0, spots.size() - 1)], rng)
	if p != null:
		p.seen[0] = true
		m.notes.append("A power station feeds their air defence nearby: knock it out and their SAMs go silent for a day.")

## Our regions (each by its group) next to an enemy one.
func _our_front_groups(map: LiteMap) -> Array[int]:
	var out: Array[int] = []
	for r: LiteRegion in map.regions:
		var g: int = group_at(r.id)
		if r.city or g < 0 or out.has(g) or map.regions[g].side != 0:
			continue
		for o: int in groups_next_to(map, g):
			if map.regions[o].side == 1:
				out.append(g)
				break
	return out

## A site in a district, on its free ground; free and ready at once.
# --- Forces on the move (phase 4b, see LiteUnit) ------------------------------

## The province's places furthest from our land, at least `apart` from each other.
static func _far_spots(sim: LiteSim, n: int, apart: float) -> Array[Vector2]:
	var map: LiteMap = sim.map
	var all: Array[Vector2] = []
	for id: int in map.focus:
		for p: Vector2 in map.regions[id].spots:
			if map.side_at(p) == 1:
				all.append(p)
	all.sort_custom(func(a: Vector2, b: Vector2) -> bool: return sim.front_distance(1, a) > sim.front_distance(1, b))
	var out: Array[Vector2] = []
	for p: Vector2 in all:
		if out.size() >= n:
			break
		var ok: bool = true
		for q: Vector2 in out:
			if q.distance_to(p) < apart:
				ok = false
				break
		if ok:
			out.append(p)
	if out.is_empty() and not map.focus.is_empty():
		out.append(map.regions[map.focus[0]].label)
	return out

## Where a march from `from` towards our command first reaches our land
## (or, if the sea is in the way, towards the nearest of our regions).
static func _border_towards(sim: LiteSim, from: Vector2) -> Vector2:
	var map: LiteMap = sim.map
	var aims: Array[Vector2] = [map.capital[0]]
	var best: float = INF
	var near: Vector2 = map.capital[0]
	for r: LiteRegion in map.regions:
		if r.side == 0 and not r.city and r.label.distance_to(from) < best:
			best = r.label.distance_to(from)
			near = r.label
	aims.append(near)
	for aim: Vector2 in aims:
		var dir: Vector2 = (aim - from).normalized()
		var p: Vector2 = from
		var wet: bool = false
		for i: int in 400:
			p += dir * 2.0
			var s: int = map.side_at(p)
			if s == 0:
				return p
			if s < 0:
				wet = true
				break
		if not wet:
			break
	return near

## A unit of `t` starting on `route` (behind its start by `back`, so a
## column forms up nose to tail) at `pace`, after `wait`.
static func _unit(sim: LiteSim, t: int, route: PackedVector2Array, pace: float, wait: float, back: float) -> LiteBuilding:
	var r:= route.duplicate()
	if back > 0.0 and r.size() >= 2:
		r.insert(0, r[0] - (r[1] - r[0]).normalized() * back)
	var b: LiteBuilding = sim.add(1, LiteKind.UNIT, r[0], true)
	b.unit = t
	b.max_hp = LiteUnit.hp(t)
	b.hp = b.max_hp
	b.route = r
	b.route_len = LiteUnit.length(r)
	b.pace = pace
	b.wait = wait
	b.seen[0] = true
	return b

## Armoured columns forming up deep in the province and grinding towards our
## border, a few battalions nose to tail each, a third column a wave behind;
## guns and a SAM watching the roads.
static func _column(m: LiteMission, sim: LiteSim, ai: LiteAi, rng: RandomNumberGenerator) -> void:
	var map: LiteMap = sim.map
	var starts: Array[Vector2] = _far_spots(sim, 3, 45.0)
	var crews: Array = [[LiteUnit.ARMOUR, LiteUnit.MECH], [LiteUnit.MECH, LiteUnit.ARTILLERY], [LiteUnit.ARMOUR, LiteUnit.ARMOUR]]
	for c: int in starts.size():
		var from: Vector2 = starts[c]
		var cross: Vector2 = _border_towards(sim, from)
		var dir: Vector2 = (cross - from).normalized()
		var route: PackedVector2Array = LiteUnit.road(map, from, cross + dir * 5.0, rng, 9.0)
		var length: float = LiteUnit.length(route)
		# Slow: the first columns reach the border in about two and a half days.
		var days: float = rng.randf_range(1.9, 2.4) + (1.1 if c == 2 else 0.0)
		var wave: float = LiteRules.DAY * (1.0 if c == 2 else 0.15 * c)
		var pace: float = length / (LiteRules.DAY * days - wave)
		var crew: Array = crews[c % crews.size()]
		for k: int in crew.size():
			var u: LiteBuilding = _unit(sim, crew[k], route, pace, wave, k * 8.0)
			u.halts = PackedFloat32Array([u.route_len * rng.randf_range(0.25, 0.4), u.route_len * rng.randf_range(0.55, 0.7)])
			m.targets.append(u)
			if k == 0:
				_escort_for(sim, u, 1.0 if c % 2 == 0 else -1.0)
		# Their air defence by the road.
		for f: float in [0.4, 0.7]:
			var at: Vector2 = LiteUnit.along(route, length * f)[0]
			var g: Variant = sim.find_spot(1, at, 8, 22)
			if g != null:
				sim.add(1, LiteKind.SAM if f > 0.5 and ops_now(sim) >= 1 and c == 0 else LiteKind.GUN, g, true)
	ai.ad_limit = 4
	m.lines.append(["moroz", "Drone feed: armour forming up in %s. They're heading for our line." % m.region_name])

## An enemy armoured AA gun riding with `u` (see LiteSim._escort), on its
## `side` (1 or -1).
static func _escort_for(sim: LiteSim, u: LiteBuilding, side: float) -> LiteBuilding:
	var g: LiteBuilding = sim.add(u.side, LiteKind.GUN, u.pos, true)
	g.leader = u
	g.gap = side
	g.heading = u.heading
	g.seen[1 - u.side] = true
	return g

## The town an assault on our region aims at: its city, or its biggest district.
static func _town(map: LiteMap) -> Vector2:
	var best: LiteRegion = null
	for id: int in map.focus:
		var r: LiteRegion = map.regions[id]
		if r.side != 0:
			continue
		if best == null or (r.city and not best.city) or (r.city == best.city and r.area > best.area):
			best = r
	return best.label if best != null else map.capital[0]

## An assault on our region: enemy armour forming up over the front, driving
## on its town in two or three columns, each with its own AA escort.
static func _assault(m: LiteMission, sim: LiteSim, ai: LiteAi, rng: RandomNumberGenerator) -> void:
	var map: LiteMap = sim.map
	var town: Vector2 = _town(map)
	m.objective = town
	# Where they form up: enemy land nearest the town, spread along the front.
	var starts: Array[Vector2] = []
	for i: int in 80:
		if starts.size() >= 3:
			break
		var p: Variant = sim.find_spot(1, town, 60.0 + i * 2.0, 150.0 + i * 5.0)
		if p == null:
			continue
		var ok: bool = true
		for q: Vector2 in starts:
			if q.distance_to(p) < 45.0:
				ok = false
		if ok:
			starts.append(p)
	var crews: Array = [[LiteUnit.ARMOUR, LiteUnit.MECH], [LiteUnit.ARMOUR, LiteUnit.ARTILLERY], [LiteUnit.MECH, LiteUnit.ARMOUR]]
	for c: int in starts.size():
		var route: PackedVector2Array = LiteUnit.road(map, starts[c], town + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4)), rng, 8.0)
		var length: float = LiteUnit.length(route)
		var wave: float = LiteRules.DAY * (0.2 + 0.6 * c)
		var pace: float = length / (LiteRules.DAY * rng.randf_range(1.7, 2.2))
		var crew: Array = crews[c % crews.size()]
		for k: int in crew.size():
			var u: LiteBuilding = _unit(sim, crew[k], route, pace, wave, k * 8.0)
			u.halts = PackedFloat32Array([u.route_len * rng.randf_range(0.3, 0.45)])
			m.targets.append(u)
			if k == 0:
				_escort_for(sim, u, 1.0 if c % 2 == 0 else -1.0)
	m.lines.append(["bilyk", "Their armour is massing across the front from %s. If it reaches the town, we lose the region." % m.region_name])

## An evacuation: our trucks leaving the region's town for the rear, in a
## line, while the enemy raids them (see LiteMission._plot).
static func _evac(m: LiteMission, sim: LiteSim, rng: RandomNumberGenerator) -> void:
	var map: LiteMap = sim.map
	var town: Vector2 = _town(map)
	# The way out: towards our capital, as far as our land goes.
	var dir: Vector2 = (map.capital[0] - town).normalized()
	var to: Vector2 = town
	for i: int in 200:
		var q: Vector2 = to + dir * 3.0
		if map.side_at(q) != 0:
			break
		to = q
		if to.distance_to(town) > 220.0:
			break
	var route: PackedVector2Array = LiteUnit.road(map, town, to, rng, 6.0)
	var pace: float = LiteUnit.length(route) / (LiteRules.DAY * 2.6)
	for k: int in 5:
		var u: LiteBuilding = sim.add(0, LiteKind.UNIT, town, true)
		u.unit = LiteUnit.CONVOY
		u.max_hp = 3.0
		u.hp = 3.0
		var r:= route.duplicate()
		r.insert(0, r[0] - (r[1] - r[0]).normalized() * (k * 7.0 + 0.1))
		u.route = r
		u.route_len = LiteUnit.length(r)
		u.pace = pace
		u.wait = LiteRules.DAY * 0.3
		u.seen[1] = true
		m.targets.append(u)
		# A gun truck of ours rides with the lead truck.
		if k == 0:
			_escort_for(sim, u, 1.0).kind = sim.gun_kind[0]
	m.raid_at = LiteRules.DAY * 0.6
	m.lines.append(["varga", "The convoy leaves %s at first light. Their drones will hunt it all the way: keep the road covered." % m.region_name])

## How far into the campaign the operation on `sim` is (its arms tell).
static func ops_now(sim: LiteSim) -> int:
	return 1 if sim.has_arm(1, LiteArm.CRUISE) else 0

## An ammunition train: its engine and wagons at the depot deep in the
## province, its rail line to a station just short of our border; guns at
## the depot, along the line and at the station.
static func _train(m: LiteMission, sim: LiteSim, rng: RandomNumberGenerator) -> void:
	var map: LiteMap = sim.map
	var from: Vector2 = _far_spots(sim, 1, 0.0)[0]
	var cross: Vector2 = _border_towards(sim, from)
	var dir: Vector2 = (cross - from).normalized()
	var station: Vector2 = cross - dir * 14.0
	for i: int in 20:
		if map.side_at(station) == 1:
			break
		station -= dir * 3.0
	var rail: PackedVector2Array = LiteUnit.road(map, from, station, rng, 5.0)
	var length: float = LiteUnit.length(rail)
	var pace: float = length / (LiteRules.DAY * rng.randf_range(1.8, 2.1))
	# A run-up behind the depot, so the wagons stand behind the engine.
	var loco: LiteBuilding = _unit(sim, LiteUnit.LOCO, rail, pace, LiteRules.DAY * 0.1, 26.0)
	loco.max_hp = 9.0
	loco.hp = 9.0
	loco.dist = 26.0
	loco.halts = PackedFloat32Array([26.0 + length * rng.randf_range(0.3, 0.4), 26.0 + length * rng.randf_range(0.6, 0.7)])
	m.targets.append(loco)
	for k: int in 4:
		var w: LiteBuilding = _unit(sim, LiteUnit.WAGON, rail, pace, 0.0, 26.0)
		w.leader = loco
		w.gap = 5.5 * (k + 1)
		w.dist = 26.0 - w.gap
		m.extras.append(w)
	# An armoured AA wagon riding with it, and another gun on the next.
	_escort_for(sim, loco, 1.0)
	_escort_for(sim, loco, -1.0)
	for f: float in [0.0, 0.5, 1.0]:
		var at: Vector2 = LiteUnit.along(rail, length * f)[0]
		var g: Variant = sim.find_spot(1, at, 8, 20)
		if g != null:
			sim.add(1, LiteKind.SAM if f == 0.0 or (f == 0.5 and ops_now(sim) >= 1) else LiteKind.GUN, g, true)
		var g2: Variant = sim.find_spot(1, at, 10, 24)
		if g2 != null and f > 0.0:
			sim.add(1, LiteKind.GUN, g2, true)
	m.lines.append(["moroz", "Their ammunition train is loading at the depot in %s. The line runs straight for the front." % m.region_name])

## Where a stretch of land (`inside` says which) meets the open sea: [a
## point on the shore, a point in the water off it], or [] if it does not.
## Wide water only, not a river: the water must run on a good way.
static func coast_of(map: LiteMap, inside: Callable) -> Array:
	var starts: Array[Vector2] = []
	for r: LiteRegion in map.regions:
		if r.label == Vector2.ZERO or not inside.call(r.label):
			continue
		starts.append(r.label)
		for i: int in mini(10, r.spots.size()):
			starts.append(r.spots[i * r.spots.size() / mini(10, r.spots.size())])
	# Every place the land meets wide water, nearest first; the first from
	# which a ship can sail out to open sea (not a bay closed off by land).
	var found: Array = []
	for p: Vector2 in starts:
		for k: int in 16:
			var dir: Vector2 = Vector2.from_angle(k * TAU / 16.0)
			var s: float = 3.0
			while s < 70.0:
				var q: Vector2 = p + dir * s
				if map.is_sea(q):
					var wide: bool = true
					var e: float = 4.0
					while e < 34.0:
						if not map.is_sea(q + dir * e):
							wide = false
							break
						e += 4.0
					if wide:
						found.append([s, q - dir * 3.0, q + dir * 3.0])
					break
				if not inside.call(q):
					break
				s += 3.0
	found.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	for k: int in mini(found.size(), 12):
		sea_lane(map, found[k][2], Vector2.RIGHT)
		if lane_found:
			return [found[k][1], found[k][2]]
	return []

## Whether the last sea_lane found a way out through the water.
static var lane_found: bool = false

## A way out to sea from `from` (in the water): through water to the map's
## edge, on a grid of 6-unit cells; a straight line out if none is found.
static func sea_lane(map: LiteMap, from: Vector2, out_dir: Vector2) -> PackedVector2Array:
	const C: int = 6
	var gw: int = LiteMap.W / C
	var gh: int = LiteMap.H / C
	var wet:= func(x: int, y: int) -> bool: return map.is_sea(Vector2(x * C + C * 0.5, y * C + C * 0.5))
	var sx: int = clampi(int(from.x / C), 0, gw - 1)
	var sy: int = clampi(int(from.y / C), 0, gh - 1)
	var prev:= PackedInt32Array()
	prev.resize(gw * gh)
	prev.fill(-2)
	var queue:= PackedInt32Array([sy * gw + sx])
	prev[sy * gw + sx] = -1
	var head: int = 0
	var goal: int = -1
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var x: int = i % gw
		var y: int = i / gw
		if x == 0 or y == 0 or x == gw - 1 or y == gh - 1:
			goal = i
			break
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			var j: int = ny * gw + nx
			if prev[j] == -2 and wet.call(nx, ny):
				prev[j] = i
				queue.append(j)
	var out:= PackedVector2Array()
	lane_found = goal >= 0
	if goal < 0:
		out.append(from)
		out.append(from + out_dir * 400.0)
		return out
	var cells:= PackedInt32Array()
	var c: int = goal
	while c >= 0:
		cells.append(c)
		c = prev[c]
	cells.reverse()
	out.append(from)
	for k: int in range(3, cells.size(), 3):
		out.append(Vector2((cells[k] % gw) * C + C * 0.5, (cells[k] / gw) * C + C * 0.5))
	var last: int = cells[cells.size() - 1]
	var end:= Vector2((last % gw) * C + C * 0.5, (last / gw) * C + C * 0.5)
	out.append(end + (end - Vector2(LiteMap.W, LiteMap.H) * 0.5).normalized() * 12.0)
	# Rounded off a little.
	for pass_: int in 2:
		for k: int in range(1, out.size() - 1):
			out[k] = out[k] * 0.5 + (out[k - 1] + out[k + 1]) * 0.25
	return out

## The enemy's biggest town in the province (its city if it has one).
static func _their_town(sim: LiteSim) -> Vector2:
	var map: LiteMap = sim.map
	var best: LiteRegion = null
	for id: int in map.focus:
		var r: LiteRegion = map.regions[id]
		if r.side != 1:
			continue
		if best == null or (r.city and not best.city) or (r.city == best.city and r.area > best.area):
			best = r
	return best.label if best != null else sim.sides[1].capital.pos

## The port: an oil terminal on the shore, SAMs and guns round it, four
## tankers at the quay leaving one after another for the open sea.
static func _port(m: LiteMission, sim: LiteSim, rng: RandomNumberGenerator) -> void:
	var map: LiteMap = sim.map
	var coast: Array = coast_of(map, func(q: Vector2) -> bool: return map.focus.has(map.region_at(q)))
	if coast.is_empty():
		var p: Vector2 = _far_spots(sim, 1, 0.0)[0]
		coast = [p, p + Vector2(20, 0)]
	var shore: Vector2 = coast[0]
	var water: Vector2 = coast[1]
	var out: Vector2 = (water - shore).normalized()
	var spot: Variant = sim.find_spot(1, shore - out * 6.0, 0.0, 8.0)
	if spot == null:
		spot = sim.find_spot(1, shore, 4.0, 18.0)
	var terminal: LiteBuilding = sim.add(1, LiteKind.REFINERY, spot if spot != null else shore - out * 6.0, true)
	terminal.max_hp = 8.0
	terminal.hp = 8.0
	terminal.seen[0] = true
	m.targets.append(terminal)
	m.objective = water
	# The cargo docks along the shore beside it.
	var along_shore: Vector2 = out.orthogonal()
	var dq: Variant = sim.find_spot(1, terminal.pos + along_shore * 16.0, 0.0, 10.0)
	if dq == null:
		dq = sim.find_spot(1, terminal.pos, 12.0, 26.0)
	if dq != null:
		var docks: LiteBuilding = sim.add(1, LiteKind.DEPOT, dq, true)
		docks.max_hp = 6.0
		docks.hp = 6.0
		docks.seen[0] = true
		m.targets.append(docks)
	# Its air defence round the port: SAMs and guns, and later in the war a
	# radar linking them (early on, with drones only, a ring that tight
	# could not be broken).
	var early: bool = ops_now(sim) == 0
	var sams: int = 1 if early else 2
	for k: int in sams + (2 if early else 3):
		var q: Variant = sim.find_spot(1, terminal.pos, 14.0, 40.0)
		if q != null:
			sim.add(1, LiteKind.SAM if k < sams else LiteKind.GUN, q, true)
	if not early:
		var rq: Variant = sim.find_spot(1, terminal.pos, 22.0, 46.0)
		if rq != null:
			sim.add(1, LiteKind.RADAR, rq, true)
	# The tankers moored along the quay, each with its lane out to sea.
	var along: Vector2 = out.orthogonal()
	for k: int in 4:
		# Side by side off the quay, pushed out until clear of the land.
		var moor: Vector2 = water + out * 6.0 + along * (k - 1.5) * 10.0
		for i: int in 12:
			if map.is_sea(moor) and map.is_sea(moor + out * 3.0):
				break
			moor += out * 3.0
		var lane: PackedVector2Array = sea_lane(map, moor, out)
		var pace: float = LiteUnit.length(lane) / (LiteRules.DAY * 0.6)
		var t: LiteBuilding = _unit(sim, LiteUnit.TANKER, lane, pace, LiteRules.DAY * (0.5 + 0.6 * k), 0.0)
		t.heading = out.angle()
		m.extras.append(t)
	m.lines.append(["moroz", "Cargo ships are loading at %s. Every one that sails pays for their next raid." % m.region_name])

## Mobile launchers hidden in the province's districts, each firing in turn
## and moving on; a gun by each hide.
static func _hunt(m: LiteMission, sim: LiteSim, districts: Array[int], rng: RandomNumberGenerator) -> void:
	var map: LiteMap = sim.map
	for k: int in 3:
		var at: int = districts[k % districts.size()] if not districts.is_empty() else map.focus[0]
		var spots: Array[Vector2] = map.regions[at].spots
		var p: Vector2 = spots[rng.randi_range(0, spots.size() - 1)] if not spots.is_empty() else map.regions[at].label
		var b: LiteBuilding = sim.add(1, LiteKind.UNIT, p, true)
		b.unit = LiteUnit.LAUNCHER
		b.max_hp = LiteUnit.hp(b.unit)
		b.hp = b.max_hp
		b.arrived = true
		b.seen[0] = false
		b.seen_pos = p
		b.fire_at = LiteRules.DAY * (0.35 + 0.4 * k) + rng.randf_range(0.0, 10.0)
		m.targets.append(b)
		var g: Variant = sim.find_spot(1, p, 14, 28)
		if g != null:
			sim.add(1, LiteKind.GUN, g, true)
	m.lines.append(["moroz", "Their launchers hide in the woods round %s. When one fires, we see it. Briefly." % m.region_name])

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
					var p: Variant = sim.find_spot(1, t.pos, 19, 36)
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
		LiteMission.DEFECTOR:
			for b: LiteBuilding in sim.buildings:
				if b.alive and b.side == 1 and (b.is_ad or b.is_gun):
					sim.spot(b, 0)
		LiteMission.VOLUNTEERS:
			var ours: Array[LiteBuilding] = []
			for b: LiteBuilding in sim.buildings:
				if b.alive and b.side == 0 and b.kind == LiteKind.FACTORY:
					ours.append(b)
			for k: int in mini(2, ours.size()):
				var g: Variant = sim.find_spot(0, ours[k].pos, 19, 28)
				if g != null:
					sim.add(0, sim.gun_kind[0], g, true)

## After an operation: the province changes hands or not, what it brings,
## the money carried on, the clock, whether the enemy strikes back, and
## whether the war is over.
func after(m: LiteMission, war: LiteMap, sim: LiteSim) -> void:
	results.append(m.result)
	history.append("%d. %s: %s" % [m.number, m.title, m.outcome])
	bonus = m.bonus_money()
	consequences = PackedStringArray()
	# Phase 4: morale and stockpiles carry on; the result moves morale.
	morale = sim.sides[0].morale + (LiteMorale.DELTA[LiteMorale.OP_WON] if m.result == 0 else LiteMorale.DELTA[LiteMorale.OP_LOST])
	enemy_morale = sim.sides[1].morale + (LiteMorale.DELTA[LiteMorale.OP_LOST] * 0.5 if m.result == 0 else LiteMorale.DELTA[LiteMorale.OP_WON] * 0.5)
	# The days between operations calm both countries a little.
	morale = clampf(morale + 5.0, 0.0, 100.0) if sim.sides[0].morale > 0.0 else 0.0
	enemy_morale = clampf(enemy_morale + 5.0, 0.0, 100.0) if sim.sides[1].morale > 0.0 else 0.0
	for l: int in 4:
		stock[l] = sim.sides[0].stock[l]
	capital_scar = 0.0
	var met: Array = []
	for i: int in m.bonus.size():
		if i < m.bonus_done.size() and m.bonus_done[i]:
			met.append(LiteMission.bonus_name(m.bonus[i]).to_lower())
	if not met.is_empty():
		morale = minf(100.0, morale + 2.0 * met.size())
	match m.kind:
		LiteMission.SURVIVE:
			if m.result == 0:
				consequences.append("Capital held: morale up")
				morale = minf(100.0, morale + 4.0)
			else:
				consequences.append("Capital burning: damage carries on")
				capital_scar = 25.0
		LiteMission.PROTECT:
			if m.result == 0:
				consequences.append("Plants kept working")
			else:
				consequences.append("Industry broken: income −10%")
				income_bonus -= 0.1
		LiteMission.STRIKE:
			if m.result == 0:
				consequences.append("Taken: %s" % LiteMission.character_gain(m.character))
			if m.result == 0 and m.label == "Air-defence suppression":
				radar_cut += 1
				consequences.append("Their radar network is broken")
	if m.kind == threat and m.province == threat_group:
		threat = -1
		threat_group = -1
	elif threat >= 0:
		# A raid nobody met: it lands unopposed.
		if threat == LiteMission.SURVIVE:
			consequences.append("Unmet raid hit the capital")
			morale = maxf(0.0, morale - 12.0)
			capital_scar = 30.0
		else:
			consequences.append("Unmet raid hit industry: income −10%")
			income_bonus -= 0.1
			morale = maxf(0.0, morale - 6.0)
		threat = -1
		threat_group = -1
	if morale <= 0.0:
		won = 1
		consequences.append("Our country gives up")
	elif enemy_morale <= 0.0:
		won = 0
		consequences.append("The enemy gives up")
	money = minf(sim.sides[0].money, MONEY_CARRIED)
	clock += m.length + GAP_DAYS * LiteRules.DAY
	ops += 1
	new_offensive = false
	downed += sim.sides[0].downed
	sites += sim.sides[0].destroyed
	# Command points: one for an operation won, one more for its optional goal.
	points += (1 if m.result == 0 else 0) + (1 if m.optional_done else 0) + m.ships_sunk()
	var pending: int = counter
	counter = -1
	last_change = []
	last_change_to = -1
	match m.kind:
		LiteMission.STRIKE:
			if m.result == 0:
				for p: int in m.provinces:
					owners[p] = 0
					war.give(p, 0)
				last_change = m.provinces.duplicate()
				last_change_to = 0
				taken[0] += 1
				kinds_taken.append(m.character)
				if m.plot == LiteMission.PLOT_PORT:
					enemy_cut += 0.1
				match m.character:
					LiteMission.INDUSTRY: income_bonus += 0.1
					LiteMission.LOGISTICS: supply += 200
					LiteMission.ENERGY: blackouts += 1
					LiteMission.EW: jammers += 1
					_: enemy_cut += 0.1
		LiteMission.CAPITAL:
			if m.result == 0:
				won = 0
		LiteMission.HOLD:
			if m.result == 1:
				for p: int in m.provinces:
					owners[p] = 1
					war.give(p, 1)
				last_change = m.provinces.duplicate()
				last_change_to = 1
				taken[1] += 1
				if m.provinces.has(war.capital_province(0)):
					won = 1
	# An enemy offensive nobody met: the region it aimed at falls.
	fallen = []
	if pending >= 0 and not (m.kind == LiteMission.HOLD and m.province == pending) and war.regions[pending].side == 0:
		for p: int in group(pending):
			owners[p] = 1
			war.give(p, 1)
			fallen.append(p)
		taken[1] += 1
		history.append("%d. %s fell to an enemy offensive while we fought elsewhere" % [m.number, group_name(war, pending)])
		if fallen.has(war.capital_province(0)):
			won = 1
	# A new offensive, now and then: at one of our regions on the front, not
	# the one just taken (its troops are dug in) and never at our capital's.
	if won < 0 and counter < 0 and ops >= 1:
		var rng:= RandomNumberGenerator.new()
		rng.seed = map_seed + ops * 13
		var chance: float = counter_chance if counter_chance >= 1.0 else minf(0.65, 0.35 + 0.05 * ops)
		if rng.randf() < chance:
			var aims: Array[int] = []
			var ours_cap: int = group_at(war.capital_province(0))
			for g: int in _our_front_groups(war):
				if g != ours_cap and not (m.kind == LiteMission.STRIKE and g == m.province):
					aims.append(g)
			if not aims.is_empty():
				counter = aims[rng.randi_range(0, aims.size() - 1)]
				new_offensive = true
	if won < 0 and _border(war, 0).is_empty() and not war.on_front(war.capital_province(0)):
		won = 1
	# A raid in the making (besides an offensive), now and then.
	if won < 0 and ops >= 2 and threat < 0:
		var trng:= RandomNumberGenerator.new()
		trng.seed = map_seed * 3 + ops * 101
		if trng.randf() < 0.4:
			# Only on the front (an operation's map shows the enemy's side
			# too): the capital's region if it is there, else another.
			var front: Array[int] = _our_front_groups(war)
			front.erase(counter)
			var cap_g: int = group_at(war.capital_province(0))
			if front.has(cap_g) and trng.randf() < 0.6:
				threat = LiteMission.SURVIVE
				threat_group = cap_g
			elif not front.is_empty():
				front.erase(cap_g)
				if not front.is_empty():
					threat = LiteMission.PROTECT
					threat_group = front[trng.randi_range(0, front.size() - 1)]
	# What comes up before the next operation.
	events_next = []
	if won < 0 and ops >= 1:
		var erng:= RandomNumberGenerator.new()
		erng.seed = map_seed * 5 + ops * 53
		if erng.randf() < 0.75:
			var e: int = erng.randi_range(0, EV_BATCH)
			events_next.append(e)
			if e == EV_UNREST:
				morale = maxf(1.0, morale - 8.0)
			elif e == EV_COMMAND:
				capital_weak += 1

var finished: bool:
	get: return won >= 0
