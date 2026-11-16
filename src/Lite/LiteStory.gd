class_name LiteStory
extends RefCounted
## The campaign's story, told in words: how the war began, what each
## operation is about and why it matters, what taking (or losing) a region
## changes, and the news the country hears about it. Everything told here is
## also true in the game: a region's kind decides its targets and what taking
## it brings (see LiteMission, LiteCampaign).
##
## Pictures may go with it: drop them into assets/ui/story/ (see image()),
## and the intro and briefings show them; without them the words stand alone.

## The picture for a moment of the story, if there is one: a .jpg, .png or
## .webp in res://assets/ui/story/ (see its README.md for every key and a
## prompt for each). A key can have numbered variants, `<key>_1`, `<key>_2`
## ...: with a `salt` (an operation's own number) one of them is picked, the
## same one every time for that salt, so an operation of a kind that comes up
## again shows another picture. Without any of its own, a key falls back on
## the older, shared picture (LEGACY).
##
## A variant may be for one terrain only: `<key>_desert_1`, `<key>_winter_1`
## show only on a desert or winter map (`climate`, LiteBiome), the plain
## numbered ones on any other; a terrain with none of its own takes the
## plain ones, and the other way round.
static func image(key: String, salt: int = -1, climate: int = -1) -> Texture2D:
	if salt >= 0:
		var plain: Array[Texture2D] = _variants(key + "_")
		var own: Array[Texture2D] = []
		if climate == LiteBiome.ARID:
			own = _variants(key + "_desert_")
		elif climate == LiteBiome.FROZEN:
			own = _variants(key + "_winter_")
		var found: Array[Texture2D] = own if not own.is_empty() else plain
		if found.is_empty():
			found = _variants(key + "_desert_") + _variants(key + "_winter_")
		if not found.is_empty():
			return found[posmod(salt, found.size())]
	var tex: Texture2D = _load(key)
	if tex == null and LEGACY.has(key):
		return image(LEGACY[key], salt, climate)
	return tex

## `<prefix>1`, `<prefix>2` ... as far as they go.
static func _variants(prefix: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for k: int in range(1, 10):
		var t: Texture2D = _load(prefix + str(k))
		if t == null:
			break
		out.append(t)
	return out

static func _load(key: String) -> Texture2D:
	for ext: String in ["jpg", "png", "webp"]:
		var path: String = "res://assets/ui/story/%s.%s" % [key, ext]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null

## The older pictures the newer keys fall back on until they have their own.
const LEGACY: Dictionary = {
	"op_column": "offensive", "op_train": "logistics", "op_hunt": "military",
	"op_port": "logistics", "op_grid": "energy", "op_depot": "ew",
	"op_assault": "hold", "op_evac": "industry", "op_protect": "industry",
	"op_survive": "offensive", "op_capital": "capital",
	"win_attack": "taken", "win_defence": "hold",
	"loss_attack": "fallen", "loss_defence": "fallen",
}

## Which of a key's variants an operation shows (the same at its loading
## screen and its result, different for the next one of its kind).
static func salt(m: LiteMission) -> int:
	return m.number * 7 + m.province

## The key of an operation's picture: one per kind of operation.
static func op_key(m: LiteMission) -> String:
	match m.plot:
		LiteMission.PLOT_COLUMN: return "op_column"
		LiteMission.PLOT_TRAIN: return "op_train"
		LiteMission.PLOT_HUNT: return "op_hunt"
		LiteMission.PLOT_PORT: return "op_port"
		LiteMission.PLOT_GRID: return "op_grid"
		LiteMission.PLOT_DEPOT: return "op_depot"
		LiteMission.PLOT_ASSAULT: return "op_assault"
		LiteMission.PLOT_EVAC: return "op_evac"
	match m.kind:
		LiteMission.CAPITAL: return "op_capital"
		LiteMission.SURVIVE: return "op_survive"
		LiteMission.PROTECT: return "op_protect"
		LiteMission.HOLD: return "op_assault"
	match m.character:
		LiteMission.ENERGY: return "op_grid"
		LiteMission.EW: return "op_depot"
		LiteMission.LOGISTICS: return "op_train"
		LiteMission.INDUSTRY: return "op_column"
	return "op_hunt"

static func _cap(map: LiteMap, side: int) -> String:
	return map.capital_name[side].trim_prefix("HQ ")

## The picture for an operation's result (the full-screen results page):
## an attack won (the region taken) or failed, a defence held or the region
## lost.
static func result_key(m: LiteMission) -> String:
	var attack: bool = m.kind == LiteMission.STRIKE or m.kind == LiteMission.CAPITAL
	if m.result == 0:
		return "win_attack" if attack else "win_defence"
	return "loss_attack" if attack else "loss_defence"

## The picture for an event between operations.
static func event_key(e: int) -> String:
	match e:
		LiteCampaign.EV_RAID, LiteCampaign.EV_REINFORCE: return "offensive"
		LiteCampaign.EV_ACCIDENT, LiteCampaign.EV_BATCH: return "industry"
		LiteCampaign.EV_RADAR_OUT: return "ew"
		LiteCampaign.EV_GRID: return "energy"
		LiteCampaign.EV_STORAGE: return "logistics"
		LiteCampaign.EV_UNREST: return "fallen"
		LiteCampaign.EV_COMMAND: return "capital"
	return "military"

## The campaign's opening, as slides: [picture key, line] each.
static func intro(map: LiteMap) -> Array:
	var ours: String = _cap(map, 0)
	var theirs: String = _cap(map, 1)
	return [
		["intro_1", "04:12. The sirens of %s have not stopped since the night the war came." % ours],
		["intro_2", "%s sent its drones first. By morning its army held the east." % theirs],
		["intro_3", "Now it is your war. Take the east back, region by region. Then end it in %s." % theirs],
	]

## A region taken, as a slide.
static func taken_slide(region: String, character: int) -> Array:
	var gain: String
	match character:
		LiteMission.INDUSTRY: gain = "Its plants stop building their drones and start working for us."
		LiteMission.LOGISTICS: gain = "Their front loses its supplies; our convoys use its roads now."
		LiteMission.ENERGY: gain = "Their grid is cut: their SAMs will start every battle in the dark."
		LiteMission.EW: gain = "Their jamming gear is ours now, and it will guard our command."
		_: gain = "Their air base falls silent. Fewer launches at our cities."
	return ["taken", "%s is free.
%s" % [region, gain]]

## An enemy offensive starting, as a slide.
static func offensive_slide(region: String) -> Array:
	return ["offensive", "Their columns are moving on %s.
Hold it, or lose it." % region]

## A region lost while we fought elsewhere, as a slide.
static func fallen_slide(region: String) -> Array:
	return ["fallen", "%s has fallen.
We were fighting elsewhere when their offensive rolled in." % region]

## The war's end, as a slide.
static func end_slide(won: int, map: LiteMap) -> Array:
	match won:
		0: return ["victory", "%s gives up. The enemy asks for a ceasefire.
The sirens go quiet." % _cap(map, 1)]
		1: return ["defeat", "The country has no more to give. The war is lost.
The columns head west, away from the front."]
	return ["ceasefire", "The guns fall silent along the front.
Nobody won. Everybody lost something."]

## Why an operation matters, in two or three sentences, for its briefing.
static func briefing(m: LiteMission, map: LiteMap, ops: int) -> String:
	var r: String = m.region_name
	var theirs: String = _cap(map, 1)
	var ours: String = _cap(map, 0)
	var lead: String = ""
	match m.kind:
		LiteMission.HOLD:
			lead = ("They are coming for %s. Intelligence counts launchers by the dozen aimed at it, and they will throw " +
				"everything they have. Keep its sky clear until their offensive burns out.") % r
		LiteMission.CAPITAL:
			lead = ("This is it: %s. Their command, ringed with every SAM they have left. Every region we took has " +
				"thinned that ring; now break it, and the war is over.") % theirs
		_ when m.plot == LiteMission.PLOT_COLUMN:
			lead = ("Their offensive has begun. Armoured columns are forming up in %s, and the roads all lead one way: to our " +
				"border, and to %s behind it. They move slowly, nose to tail, with guns watching the roads. Burn every " +
				"battalion before it reaches our line: if one gets across, the front gives way.") % [r, ours]
		_ when m.plot == LiteMission.PLOT_TRAIN:
			lead = ("An ammunition train is loading at the depot in %s: forty wagons of shells for the guns that shell our " +
				"towns. Its line runs straight to a station at the front. Wreck the engine on the way and the wagons go " +
				"nowhere; burn the wagons and they go up for miles.") % r
		_ when m.plot == LiteMission.PLOT_HUNT:
			lead = ("Mobile launchers hide in the woods of %s. They fire on our positions, then drive off before we can answer. " +
				"Each salvo gives one away for half a minute, and our drones overhead find them too. Hunt them down before " +
				"our troops have taken more than they can.") % r
		_:
			match m.character:
				LiteMission.INDUSTRY:
					lead = ("The plants of %s work day and night: three factories side by side, building the drones that hit " +
						"%s. The enemy knows what they are worth, and the sky over them is thick with SAMs and guns. " +
						"One drone won't get through; a swarm might. Wear their air defence out, then send the missiles in.") % [r, ours]
				LiteMission.ENERGY:
					lead = ("Two power stations in %s feed the radars and SAMs along their front. Knock one out and their " +
						"sky goes dark for a day: then strike the other.") % r
				LiteMission.EW:
					lead = ("Their jammer at %s blinds our drones: half of them never come back. Its depot sits under that " +
						"cover. Missiles are not fooled: break the jammer with them, then send the drones.") % r
				LiteMission.LOGISTICS:
					lead = ("Every shell and every litre of fuel for their front goes through %s: two depots, far apart, each " +
						"with guns by it. Burn both and their troops at the front go hungry.") % r
				_:
					lead = ("The drones that hit %s last week took off from %s. The launch site and the radar that guides them " +
						"are hidden somewhere in its districts: find them with drones first, then destroy them.") % [ours, r]
	# Where the war is now.
	var stage: String = ""
	if ops == 0:
		stage = "Both sides fight with drones alone for now."
	elif ops == 1:
		stage = "Cruise missiles have reached the front, theirs and ours."
	elif ops == 3:
		stage = "Now both sides have ballistic missiles: fast, high, and only SAMs can stop them."
	elif ops >= 6:
		stage = "The war has dragged on: both sides are tired, and neither will give an inch."
	return lead if stage == "" else lead + "\n\n" + stage

## What a region taken by us changes, for the debrief.
static func taken(m: LiteMission, c: LiteCampaign, map: LiteMap) -> String:
	var r: String = m.region_name
	var line: String
	match m.character:
		LiteMission.INDUSTRY:
			line = ("The plants of %s are ours. The drones they built won't be built now, and their workshops " +
				"work for us: our income is 10%% higher from now on.") % r
		LiteMission.ENERGY:
			line = ("The power stations of %s are dark. Their SAMs will start every later operation without power " +
				"for half a day.") % r
		LiteMission.EW:
			line = ("Their jamming gear at %s is ours. From now on a jammer of ours guards our command: their " +
				"drones that come near it are often lost.") % r
		LiteMission.LOGISTICS:
			line = ("With %s gone, their front has lost its supplies: units along it are short of shells and fuel. " +
				"Our convoys use its roads now: +$200 at the start of every operation.") % r
		_:
			line = ("The air base at %s is silent. Fewer launches against our cities, and the enemy has 10%% less " +
				"to spend from now on.") % r
	if c.capital_locked():
		var left: int = LiteCampaign.CAPITAL_AFTER - c.taken[0]
		line += "\n\n%s is out of reach until %d more region%s fall%s." % [_cap(map, 1), left, "" if left == 1 else "s", "s" if left == 1 else ""]
	elif c.taken[0] == LiteCampaign.CAPITAL_AFTER:
		line += "\n\nThe road to %s is open: its region can be attacked." % _cap(map, 1)
	return line

## What a region lost to the enemy changes, for the debrief.
static func lost(m: LiteMission, map: LiteMap) -> String:
	return ("%s has fallen. The front bends towards %s: their launchers move up, and our factories there are " +
		"in enemy hands.") % [m.region_name, _cap(map, 0)]

## An attack that failed, or a defence that held, for the debrief.
static func held(m: LiteMission) -> String:
	if m.defensive:
		return "Their offensive against %s broke. Their launchers are spent for now; the front holds." % m.region_name
	return "We pulled back from %s. They will dig in deeper, but the front holds, and we can try again." % m.region_name

## An enemy offensive massing, for the debrief.
static func counter(region: String) -> String:
	return "Their offensive is massing against %s. Hold it next, or it falls while we fight elsewhere." % region

## A region lost to an offensive nobody met, for the debrief.
static func fell(region: String) -> String:
	return "While we fought, their offensive took %s." % region

## The line under a capture's announcement.
static func capture_line(character: int, to: int) -> String:
	if to == 1:
		return "The enemy pushes the front back"
	match character:
		LiteMission.INDUSTRY: return "Its plants now work for us"
		LiteMission.LOGISTICS: return "Their front loses its supplies"
		LiteMission.ENERGY: return "Their grid goes dark"
		LiteMission.EW: return "Their jammers are ours"
	return "Their air base falls silent"

## Campaign news for the ticker: about what has happened in this campaign.
static func news(c: LiteCampaign, map: LiteMap, rng: RandomNumberGenerator) -> String:
	var won: Array[String] = []
	var lost_: Array[String] = []
	for h: String in c.history:
		var title: String = h.get_slice(": ", 0).get_slice(". ", 1)
		var region: String = title.get_slice(" ", title.get_slice_count(" ") - 1)
		if h.contains("move into"):
			won.append(region)
		elif h.contains("Too many strikes got through"):
			lost_.append(region)
		elif h.contains("fell to an enemy offensive"):
			lost_.append(h.get_slice(". ", 1).get_slice(" fell", 0))
	var theirs: String = _cap(map, 1)
	var ours: String = _cap(map, 0)
	var out: Array[String] = []
	for r: String in won:
		out.append("Residents of %s hang out our flags as the first trucks arrive" % r)
		out.append("Engineers start rebuilding the bridges in %s" % r)
		out.append("%s state TV has not mentioned %s for a week" % [theirs, r])
		out.append("Children in %s go back to school, in the basement for now" % r)
	for r: String in lost_:
		out.append("Families from %s arrive in %s; volunteers hand out tea and blankets" % [r, ours])
		out.append("Our army vows to return to %s" % r)
	if c.taken[0] > 0:
		out.append("%d regions freed so far: the mood in %s lifts" % [c.taken[0], ours])
	if out.is_empty():
		return ""
	return out[rng.randi_range(0, out.size() - 1)]

# --- The cast ----------------------------------------------------------------------

## Who speaks: key to [name, what they do]. Their portraits, if made, are
## assets/ui/story/portrait_<key>.jpg.
const CAST: Dictionary = {
	"varga": ["General Orest Varga", "Commander of the front"],
	"moroz": ["Captain Lina Moroz", "Drone reconnaissance"],
	"bilyk": ["Sergeant Taras Bilyk", "Air defence crew chief"],
	"rudin": ["Colonel-General Rudin", "Enemy commander, intercepted"],
}

## Who says each tutorial tip (by its title), to the player in person.
const TUTOR: Dictionary = {
	"Your country": "varga", "The goal": "varga", "Factories": "varga", "Air defence": "bilyk",
	"Strike back": "moroz", "Air alerts": "bilyk", "Capitals": "varga", "SAMs and drones": "bilyk",
	"Air defence ranges": "bilyk", "The news": "moroz", "Time": "varga", "The front": "varga",
	"The enemy capital": "varga",
}

## What the cast says over the radio when an operation's event comes up:
## [cast key, line].
static func event_line(e: int) -> Array:
	match e:
		LiteMission.STORM: return ["moroz", "Storm front coming in. Every drone stays on the ground, theirs too."]
		LiteMission.INTEL: return ["moroz", "Recon found one of their districts. It's marked on your map."]
		LiteMission.REINFORCE: return ["varga", "They're rushing a new SAM battery to the targets. Hit fast."]
		LiteMission.SABOTAGE: return ["moroz", "Partisans just blew up one of their air defence sites. Use the gap."]
		LiteMission.OUTAGE: return ["moroz", "Their SAMs went silent for half a day. Strike now!"]
		LiteMission.CONVOY: return ["moroz", "A convoy on the move. Catch it before it gets away."]
		LiteMission.RAID: return ["bilyk", "They're massing for a big raid. Everyone to the launchers."]
		LiteMission.DEFECTOR: return ["moroz", "A defector brought us their air defence map. It's all on yours now."]
		LiteMission.VOLUNTEERS: return ["bilyk", "Volunteers brought two AA guns. We set them by the factories."]
	return ["varga", "Supplies came through. Spend them well."]

## The situation on the front between operations, as one of the cast
## reports it: [cast key, line].
static func front_report(c: LiteCampaign, war: LiteMap) -> Array:
	var theirs: String = _cap(war, 1)
	if c.counter >= 0:
		return ["bilyk", "Their offensive is massing against %s. Hold it next, or it falls after our next operation." % c.group_name(war, c.counter)]
	if c.ops == 0:
		return ["varga", "Pick our first target on the map, commander. Industry pays, supply hubs feed us, air bases hurt them."]
	if c.points > 0:
		return ["varga", "We have %d command point%s to spend. The war council is waiting, top right." % [c.points, "" if c.points == 1 else "s"]]
	if c.capital_locked():
		var left: int = LiteCampaign.CAPITAL_AFTER - c.taken[0]
		return ["varga", "Take %d more region%s and %s is within reach." % [left, "" if left == 1 else "s", theirs]]
	return ["varga", "%s is open: %d SAM batteries round it. Every region we take near it thins that ring." % [theirs, c.capital_defence(war)]]

## Who briefs an operation, and what they say: [cast key, line].
static func briefing_quote(m: LiteMission, map: LiteMap, ops: int) -> Array:
	# The first operation's welcome, unless the region needs its own advice
	# (hidden sites, a jammer, a grid to black out).
	if ops == 0 and m.kind == LiteMission.STRIKE and (m.character == LiteMission.INDUSTRY or m.character == LiteMission.LOGISTICS):
		return ["varga", "Welcome to the front, commander. We start small: %s. Show them we can hit back." % m.region_name]
	match m.kind:
		LiteMission.HOLD:
			return ["bilyk", "We dug in last night. Give us SAMs by the towns and we'll give them a wall."]
		LiteMission.CAPITAL:
			return ["varga", "Everything we have goes in tonight. Break the ring round %s and finish this." % _cap(map, 1)]
	match m.plot:
		LiteMission.PLOT_COLUMN:
			return ["bilyk", "My lads are dug in at the border. Stop those tanks on the road, or we meet them in the trenches."]
		LiteMission.PLOT_TRAIN:
			return ["varga", "That train carries a month of shells for their guns. Wreck the engine. The wagons are a bonus."]
		LiteMission.PLOT_HUNT:
			return ["moroz", "They shoot and run. Keep a few drones over the woods, and something fast ready for when they fire."]
	match m.character:
		LiteMission.INDUSTRY:
			return ["varga", "Those plants built every drone that hit us this month. Wear their SAMs out first, then break them."]
		LiteMission.LOGISTICS:
			return ["varga", "Two depots, far apart. Hit one and they will guard the other twice as hard. Be quick."]
		LiteMission.ENERGY:
			return ["varga", "Lights out in one station and their sky goes blind for a day. Use that day."]
		LiteMission.EW:
			return ["moroz", "That jammer ate half my drones yesterday. Don't fly drones into its circle. Missiles first."]
	return ["moroz", "We lost their launch site somewhere in those forests. Send drones over every district: we find it, you hit it."]

## What is said after an operation: [cast key, line].
static func debrief_quote(m: LiteMission, map: LiteMap, rng: RandomNumberGenerator) -> Array:
	if m.defensive:
		return ["bilyk", "Not one got through to the town. Well, almost none." if m.result == 0 else "We held as long as we could, commander. We'll be back for it."]
	if m.kind == LiteMission.CAPITAL and m.result == 0:
		return ["varga", "It's over. Go home, commander. Sleep."]
	if m.result != 0:
		return ["varga", "We'll be back. Rest the crews, count the launchers, try again."]
	var lines: Array[String] = ["Good work. The front moves because of you.", "One more off their map. Keep going.",
		"They felt that one in %s." % _cap(map, 1), "The men in the trenches saw the smoke. They cheered."]
	return ["varga", lines[rng.randi_range(0, lines.size() - 1)]]

## A line of radio chatter during an operation: ours, or theirs intercepted.
static func radio(m: LiteMission, map: LiteMap, rng: RandomNumberGenerator) -> String:
	var r: String = m.region_name
	var ours: String = _cap(map, 0)
	var lines: Array[String] = [
		"Rudin to all units: the sky over %s stays closed. Whatever it costs." % r,
		"Intercepted: their crews in %s are begging for more interceptors" % r,
		"Intercepted: \"Who switched off the radar?\" \"Nobody. It's gone.\"",
		"Rudin: launch everything at %s tonight" % ours,
		"Bilyk: crews ready. Sky's quiet. For now.",
		"Moroz: recon drones out over %s" % r,
		"Varga: keep the pressure on, commander. They are cracking.",
		"Moroz: fresh tracks on the roads round %s, they are moving something" % r,
	]
	return lines[rng.randi_range(0, lines.size() - 1)]
