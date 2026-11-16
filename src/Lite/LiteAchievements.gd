class_name LiteAchievements
extends RefCounted
## The player's achievements: what counts towards them (counters, kept
## across games in user://achievements.cfg), which are won and when. The
## game notes what happens (`note`, `best`); an achievement is won when its
## counter reaches its goal, and `on_unlock` is told (the toast, see
## LiteAchievementsView.Toast). Shown on the home screen (LiteAchievementsView)
## as cells, each with its own picture (assets/ui/achievements/<id>.png when
## there is one, a medal until then), opened for its story and a quote.

const PATH: String = "user://achievements.cfg"
## Where each achievement's picture goes (512x512 PNG, named by its id).
const ART_DIR: String = "res://assets/ui/achievements/"

## Each: id, title, what it takes (a few words), counter, goal, icon (0 shield,
## 1 crosshair, 2 star, 3 flame, 4 flag, 5 factory, 6 atom), hidden until won
## (its hint shown instead), a quote and who said it; its tier (0 bronze,
## 1 silver, 2 gold, 3 legendary, 4 the bomb: see tools/medal_art.py). In
## order of how hard they are.
const LIST: Array = [
	{"id": "first_down", "tier": 0, "title": "First Intercept", "what": "Bring down your first drone or missile.", "counter": "downed", "goal": 1, "icon": 0,
		"quote": "The first casualty when war comes is truth.", "by": "Hiram Johnson"},
	{"id": "salvo", "tier": 0, "title": "Saturation", "what": "Launch a salvo of ten.", "counter": "salvo10", "goal": 1, "icon": 3,
		"quote": "Artillery lends dignity to what would otherwise be a vulgar brawl.", "by": "Frederick the Great (attributed)"},
	{"id": "hand_25", "tier": 1, "title": "Ace Gunner", "what": "Bring down 25 drones and missiles at a gun yourself.", "counter": "hand_kill", "goal": 25, "icon": 1,
		"quote": "Aim small, miss small.", "by": "American rifleman's saying"},
	{"id": "hand_streak", "tier": 1, "title": "Bullet Hose", "what": "Bring down 6 without leaving the gun.", "counter": "hand_streak", "goal": 1, "icon": 1,
		"quote": "Fortune favours the bold.", "by": "Virgil"},
	{"id": "hand_cruise", "tier": 1, "title": "Skeet Shooter", "what": "Bring down a cruise missile by hand.", "counter": "hand_cruise", "goal": 1, "icon": 1,
		"quote": "It is not the size of the dog in the fight, it is the size of the fight in the dog.", "by": "Mark Twain (attributed)"},
	{"id": "black_gold", "tier": 1, "title": "Black Gold", "what": "Set five enemy refineries ablaze in one war.", "counter": "black_gold", "goal": 1, "icon": 3,
		"quote": "Oil is the blood of victory.", "by": "attributed to Georges Clemenceau"},
	{"id": "blind", "tier": 1, "title": "Blind Them All", "what": "Destroy three enemy radars in one war.", "counter": "blind", "goal": 1, "icon": 3,
		"quote": "All warfare is based on deception.", "by": "Sun Tzu"},
	{"id": "stopped_cold", "tier": 1, "title": "Stopped Cold", "what": "Burn every column before it reaches our border.", "counter": "columns", "goal": 1, "icon": 4,
		"quote": "They shall not pass.", "by": "Robert Nivelle, Verdun"},
	{"id": "derailed", "tier": 1, "title": "Derailed", "what": "Wreck the ammunition train with every wagon burnt.", "counter": "derailed", "goal": 1, "icon": 4,
		"quote": "Amateurs talk strategy; professionals talk logistics.", "by": "attributed to Omar Bradley"},
	{"id": "left_behind", "tier": 1, "title": "Nobody Left Behind", "what": "Evacuate a town without losing a single truck.", "counter": "left_behind", "goal": 1, "icon": 4,
		"quote": "I will never leave a fallen comrade.", "by": "The Soldier's Creed"},
	{"id": "downs_500", "tier": 2, "title": "Unbroken Sky", "what": "Bring down 500 drones and missiles.", "counter": "downed", "goal": 500, "icon": 0,
		"quote": "Never in the field of human conflict was so much owed by so many to so few.", "by": "Winston Churchill"},
	{"id": "swarm", "tier": 2, "title": "Swarm Doctrine", "what": "Win a war launching nothing but drones.", "counter": "swarm", "goal": 1, "icon": 3,
		"quote": "Quantity has a quality all its own.", "by": "attributed to Joseph Stalin"},
	{"id": "no_sam", "tier": 2, "title": "No Shield Needed", "what": "Win a war without building a single SAM.", "counter": "no_sam", "goal": 1, "icon": 0,
		"quote": "The best defence is a good offence.", "by": "proverb"},
	{"id": "untouched", "tier": 2, "title": "Untouched", "what": "Win a war without a single hit on your capital.", "counter": "untouched", "goal": 1, "icon": 0,
		"quote": "Invincibility lies in the defence.", "by": "Sun Tzu"},
	{"id": "lightning", "tier": 2, "title": "Lightning War", "what": "Win a war within ten days.", "counter": "lightning", "goal": 1, "icon": 2,
		"quote": "Speed is the essence of war.", "by": "Sun Tzu"},
	{"id": "veteran", "tier": 2, "title": "Veteran", "what": "Win fifteen campaign operations.", "counter": "ops_won", "goal": 15, "icon": 4,
		"quote": "Old soldiers never die; they just fade away.", "by": "Douglas MacArthur"},
	{"id": "ballistic_exec", "tier": 3, "title": "Ballistic Executioner", "what": "Win a war where only ballistic missiles ever hit their capital (10 at least).", "counter": "ballistic_exec", "goal": 1, "icon": 3,
		"quote": "Speak softly and carry a big stick; you will go far.", "by": "Theodore Roosevelt"},
	{"id": "war_hard", "tier": 3, "title": "Against the Odds", "what": "Win a war on Hard.", "counter": "wars_hard", "goal": 1, "icon": 2,
		"quote": "It always seems impossible until it's done.", "by": "Nelson Mandela"},
	{"id": "flawless", "tier": 3, "title": "Iron Will", "what": "Win a campaign without losing an operation.", "counter": "flawless", "goal": 1, "icon": 2,
		"quote": "Victory belongs to the most persevering.", "by": "Napoleon Bonaparte"},
	{"id": "campaign", "tier": 3, "title": "Liberation", "what": "Win a campaign.", "counter": "campaigns_won", "goal": 1, "icon": 2,
		"quote": "Freedom is never more than one generation away from extinction.", "by": "Ronald Reagan"},
	{"id": "oppenheimer", "tier": 4, "title": "Destroyer of Worlds", "what": "Use the bomb.", "counter": "nuke", "goal": 1, "icon": 6, "hidden": true,
		"hint": "Take every region but their capital, and become Oppenheimer.",
		"quote": "Now I am become Death, the destroyer of worlds.", "by": "J. Robert Oppenheimer, quoting the Bhagavad Gita"},
]

static var _loaded: bool = false
static var counts: Dictionary = {}
## Won ones: id -> when (unix time).
static var won: Dictionary = {}
## Told of each one won, with its LIST entry.
static var on_unlock: Callable = Callable()

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var f:= ConfigFile.new()
	if f.load(PATH) != OK:
		return
	for k: String in f.get_section_keys("counts") if f.has_section("counts") else PackedStringArray():
		counts[k] = int(f.get_value("counts", k, 0))
	for k: String in f.get_section_keys("won") if f.has_section("won") else PackedStringArray():
		won[k] = int(f.get_value("won", k, 0))

static func _save() -> void:
	# Test runs leave the player's record alone.
	if LiteSettings.dry:
		return
	var f:= ConfigFile.new()
	for k: String in counts:
		f.set_value("counts", k, counts[k])
	for k: String in won:
		f.set_value("won", k, won[k])
	f.save(PATH)

## Something that counts happened `n` times.
static func note(counter: String, n: int = 1) -> void:
	_load()
	counts[counter] = int(counts.get(counter, 0)) + n
	_check(counter)

## A counter that keeps its best (how many at once).
static func best(counter: String, value: int) -> void:
	_load()
	if value <= int(counts.get(counter, 0)):
		return
	counts[counter] = value
	_check(counter)

static func _check(counter: String) -> void:
	var changed: bool = false
	for a: Dictionary in LIST:
		if a["counter"] != counter or won.has(a["id"]):
			continue
		if int(counts.get(counter, 0)) >= int(a["goal"]):
			won[a["id"]] = int(Time.get_unix_time_from_system())
			changed = true
			if on_unlock.is_valid():
				on_unlock.call(a)
	# Counters are saved now and then (and with every achievement won).
	_dirty += 1
	if changed or _dirty >= 20:
		_dirty = 0
		_save()

static var _dirty: int = 0

## Saves whatever was counted since the last save (at a war's end).
static func flush() -> void:
	if _loaded:
		_dirty = 0
		_save()

static func is_won(id: String) -> bool:
	_load()
	return won.has(id)

## How far along: [have, goal].
static func progress(a: Dictionary) -> Array:
	_load()
	return [mini(int(counts.get(a["counter"], 0)), int(a["goal"])), int(a["goal"])]

static func won_count() -> int:
	_load()
	var n: int = 0
	for a: Dictionary in LIST:
		if won.has(a["id"]):
			n += 1
	return n

## Its picture, when there is one (else null: a medal is drawn).
## (Loaded once and kept: one loaded while the page draws comes out blank
## on that frame, so the page loads them all when it opens.)
static var _art: Dictionary = {}

static func art(a: Dictionary) -> Texture2D:
	var id: String = String(a["id"])
	if not _art.has(id):
		var path: String = ART_DIR + id + ".png"
		_art[id] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _art[id]
