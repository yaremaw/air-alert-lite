class_name LiteSettings
extends RefCounted

const PATH: String = "user://lite_settings.cfg"
const VOLUME_DB: Array[float] = [-80.0, -16.0, -8.0, 0.0]

static var volume: int = 2
static var difficulty: int = 1
static var fullscreen: bool = false
static var routes: bool = false
static var ranges: bool = false
## Whether the first-time tips have been shown, for a war and for the front.
static var tips_war: bool = false
static var tips_front: bool = false
## Jet drones won in the campaign: a single war has them too since.
static var jets: bool = false
## Which version of the tips was seen (see load).
const TIPS_VERSION: int = 2

static func load() -> void:
	var c:= ConfigFile.new()
	if c.load(PATH) != OK and c.load(_old_path()) != OK:
		return
	volume = clampi(int(c.get_value("lite", "volume", volume)), 0, 3)
	difficulty = clampi(int(c.get_value("lite", "difficulty", difficulty)), 0, 2)
	# Every launch starts windowed; fullscreen is chosen in Settings or with F11.
	fullscreen = false
	routes = bool(c.get_value("lite", "routes_shown", routes))
	ranges = bool(c.get_value("lite", "coverage_layer", ranges))
	tips_war = bool(c.get_value("lite", "tips_war", tips_war))
	tips_front = bool(c.get_value("lite", "tips_front", tips_front))
	jets = bool(c.get_value("lite", "jets", jets))
	# The tips were rewritten: shown again once to everyone who saw the old ones.
	if int(c.get_value("lite", "tips_version", 1)) < TIPS_VERSION:
		tips_war = false
		tips_front = false

## Until version 1.1 the project was called "Air Alert", and Godot keeps a
## desktop game's files in a folder named after the project: read the old one's
## settings once, so players keep them. (The web version's folder never moved.)
static func _old_path() -> String:
	return OS.get_user_data_dir().get_base_dir().path_join("Air Alert").path_join(PATH.get_file())

## A test run changes nothing on disk.
static var dry: bool = false

static func save() -> void:
	if dry:
		return
	var c:= ConfigFile.new()
	c.set_value("lite", "volume", volume)
	c.set_value("lite", "difficulty", difficulty)
	c.set_value("lite", "fullscreen", fullscreen)
	c.set_value("lite", "routes_shown", routes)
	c.set_value("lite", "coverage_layer", ranges)
	c.set_value("lite", "tips_war", tips_war)
	c.set_value("lite", "tips_front", tips_front)
	c.set_value("lite", "jets", jets)
	c.set_value("lite", "tips_version", TIPS_VERSION)
	c.save(PATH)

static func apply_sound() -> void:
	AudioServer.set_bus_mute(0, volume == 0)
	AudioServer.set_bus_volume_db(0, VOLUME_DB[volume])

static func apply_window() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
