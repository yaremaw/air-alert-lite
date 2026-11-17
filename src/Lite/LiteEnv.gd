class_name LiteEnv
extends RefCounted
## The war's surroundings, part of the simulation (see LiteSim.env): the time
## of day from the war's clock, and the weather, which changes now and then
## on its own (it is the game's weather, not the real world's), the kinds of
## it and how often each comes by the map's climate (its main biome, see
## LiteBiome.dominant): sandstorms in the desert, snowstorms in the north,
## fog in the wetlands, wind on the steppe.
##
## What they do to the war:
## - Night: AA guns (aimed by eye) hit a fifth less often; everything that
##   sees by eye (guns, mobile units, posts) sees less far, mobile units'
##   thermal sights a little less. Radars see as ever.
## - Fog: guns hit 30% less often still and reach a fifth less far; eyes see
##   little. Radars see as ever.
## - Storm: no drone takes off; drones already in the air fly on
##   (they are not lost); missiles fly as ever. Radars see a little less far.
## - Sandstorm: eyes see very little and drones find much less (dust); guns
##   hit less often. Drones fly. Radar matters most.
## - Snowstorm: as a storm for drones (grounded), and eyes see little.
## - Wind: drones fly slower and land less true.
## - Cloud: eyes see a little less far.
## SAMs with a radar's picture are hardly touched by any of it; SAMs alone
## feel half of what guns do (see LiteSense, sam_alone_factor).
## The map draws all of it (see LiteCmdView), the top bar says it (LiteCmdUi).

enum { CLEAR, CLOUDY, FOG, STORM, SANDSTORM, SNOWSTORM, WINDY }
const NAMES: Array[String] = ["Clear", "Cloudy", "Fog", "Storm", "Sandstorm", "Snowstorm", "Wind"]

## The war's clock: seconds of the war before this simulation's own (an
## operation of a campaign goes on from the campaign's clock).
var clock_offset: float = 0.0
## The hour of the day, 0 to 24.
var hour: float = 21.0
## How dark it is, 0 (day) to 1 (night), easing through dawn and dusk.
var night: float = 1.0
## How much of a dawn or a dusk glow there is, 0 to 1.
var glow: float = 0.0
## The weather now and the one it is turning into, `blend` of the way there.
var weather: int = CLEAR
var prev: int = CLEAR
var blend: float = 1.0
## The map's climate (LiteBiome: PLAINS, STEPPE, DESERT, WINTER, WETLANDS).
var climate: int = LiteBiome.PLAINS
## A weather set from outside (a campaign operation's), and until when.
var forced: int = -1
var forced_until: float = -1.0
var _left: float = 60.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## How long a change of weather takes, in seconds of the war.
const TURN: float = 8.0
## How much each condition takes off AA guns' chance to hit, and fog off how
## far they see. Tuned 2026-11-15 on 13 baked maps, AI against AI, fixed
## steps: with no effects the west won 9 of 13; with 0.35/0.4/0.2/0.3 only 6
## (the enemy leans on guns, but more of its drones got through); with these
## 8, enemy hits up a fifth. Static so a balance run can try others.
static var NIGHT_GUN: float = 0.2
static var FOG_GUN: float = 0.3
static var STORM_GUN: float = 0.1
static var FOG_RANGE: float = 0.2
static var SAND_GUN: float = 0.25
static var SNOW_GUN: float = 0.2
## Off: no night and no weather effects at all (for balance runs).
static var effects: bool = true

## How often each weather comes, by climate: [kind, weight] pairs.
static func odds(c: int) -> Array:
	match c:
		LiteBiome.DESERT: return [[CLEAR, 55], [CLOUDY, 10], [WINDY, 10], [SANDSTORM, 22], [STORM, 3]]
		LiteBiome.WINTER: return [[CLEAR, 38], [CLOUDY, 27], [FOG, 10], [SNOWSTORM, 20], [WINDY, 5]]
		LiteBiome.WETLANDS: return [[CLEAR, 30], [CLOUDY, 25], [FOG, 30], [STORM, 15]]
		LiteBiome.STEPPE: return [[CLEAR, 45], [CLOUDY, 20], [WINDY, 20], [STORM, 10], [FOG, 5]]
	return [[CLEAR, 42], [CLOUDY, 28], [FOG, 14], [STORM, 12], [WINDY, 4]]

static func severe(w: int) -> bool:
	return w == STORM or w == SANDSTORM or w == SNOWSTORM

func _init(seed_: int) -> void:
	_rng.seed = seed_ * 2654435 + 97
	_left = _rng.randf_range(35.0, 70.0)

## How much of each weather there is now (the old one fading, the new one
## coming in), 0 to 1.
func amount(kind: int) -> float:
	var a: float = 0.0
	if weather == kind:
		a += blend
	if prev == kind:
		a += 1.0 - blend
	return a

## Turns the weather to `kind` now (a campaign's), held for `hold` seconds.
func force(kind: int, time: float, hold: float) -> void:
	if kind != weather:
		prev = weather
		weather = kind
		blend = 0.0
	forced = kind
	forced_until = time + hold
	_left = hold

func step(time: float, dt: float) -> void:
	var minutes: float = 21.0 * 60.0 + (time + clock_offset) * LiteRules.GAME_MINUTES
	hour = fmod(minutes / 60.0, 24.0)
	# Day 7 to 17, night 20 to 5, easing between.
	if hour >= 7.0 and hour < 17.0:
		night = 0.0
	elif hour >= 17.0 and hour < 20.0:
		night = smoothstep(17.0, 20.0, hour)
	elif hour >= 5.0 and hour < 7.0:
		night = 1.0 - smoothstep(5.0, 7.0, hour)
	else:
		night = 1.0
	glow = maxf(1.0 - absf(hour - 6.0) / 1.5, 1.0 - absf(hour - 18.5) / 1.5)
	glow = clampf(glow, 0.0, 1.0)
	blend = minf(1.0, blend + dt / TURN)
	_left -= dt
	if forced >= 0 and time < forced_until:
		return
	forced = -1
	if _left <= 0.0:
		var next: int = _pick()
		if next != weather:
			prev = weather
			weather = next
			blend = 0.0
		# A storm passes quicker than fair weather stays.
		_left = _rng.randf_range(18.0, 30.0) if severe(weather) else _rng.randf_range(35.0, 75.0)

func _pick() -> int:
	var table: Array = odds(climate)
	var total: float = 0.0
	for e: Array in table:
		total += float(e[1])
	var r: float = _rng.randf() * total
	for e: Array in table:
		r -= float(e[1])
		if r <= 0.0:
			return int(e[0])
	return CLEAR

## AA guns' chance to hit, as a share of their usual: by night and in fog
## worse; SAMs with a radar's picture are not touched by any of it.
func gun_factor() -> float:
	if not effects:
		return 1.0
	return (1.0 - NIGHT_GUN * night) * (1.0 - FOG_GUN * amount(FOG)) * (1.0 - STORM_GUN * amount(STORM)) \
		* (1.0 - SAND_GUN * amount(SANDSTORM)) * (1.0 - SNOW_GUN * amount(SNOWSTORM))

## A SAM without a radar's picture: half of what guns lose.
func sam_alone_factor() -> float:
	return 1.0 - (1.0 - gun_factor()) * 0.5

## A SAM with one: only storms, a little.
func sam_linked_factor() -> float:
	if not effects:
		return 1.0
	return 1.0 - 0.05 * (amount(STORM) + amount(SNOWSTORM))

## A mobile unit's thermal sights: night costs it far less than a gun.
func thermal_factor() -> float:
	if not effects:
		return 1.0
	return (1.0 - 0.06 * night) * (1.0 - 0.2 * amount(FOG)) * (1.0 - SAND_GUN * amount(SANDSTORM)) * (1.0 - 0.15 * amount(SNOWSTORM))

## How far AA guns see, as a share of their usual range: less in fog.
func gun_range() -> float:
	if not effects:
		return 1.0
	return 1.0 - FOG_RANGE * amount(FOG) - 0.15 * amount(SANDSTORM) - 0.1 * amount(SNOWSTORM)

## How far what sees by eye sees, as a share of its usual (`thermal`:
## thermal sights, which night hardly touches).
func optical(thermal: bool = false) -> float:
	if not effects:
		return 1.0
	var k: float = 1.0 - (0.12 if thermal else 0.4) * night
	k *= 1.0 - 0.1 * amount(CLOUDY)
	k *= 1.0 - 0.45 * amount(FOG)
	k *= 1.0 - 0.3 * amount(STORM)
	k *= 1.0 - 0.55 * amount(SANDSTORM)
	k *= 1.0 - 0.5 * amount(SNOWSTORM)
	return k

## How far radars see, as a share of their usual.
func radar() -> float:
	if not effects:
		return 1.0
	return 1.0 - 0.15 * amount(STORM) - 0.08 * amount(SANDSTORM) - 0.1 * amount(SNOWSTORM)

## How far a drone finds what it flies over, as a share (dust).
func recon() -> float:
	if not effects:
		return 1.0
	return (1.0 - 0.5 * amount(SANDSTORM)) * (1.0 - 0.25 * amount(FOG)) * (1.0 - 0.25 * night)

## How fast drones fly in the wind, as a share, and how much wider they land.
func drone_pace() -> float:
	return 1.0 - 0.15 * amount(WINDY) if effects else 1.0
func scatter() -> float:
	return 1.0 + 0.6 * amount(WINDY) if effects else 1.0

## Whether drones are grounded by the weather.
func drones_grounded() -> bool:
	return effects and (weather == STORM or weather == SNOWSTORM) and blend > 0.3

## The weather now, in a word.
func weather_name() -> String:
	return NAMES[weather]

## For the top bar: what the weather and the hour do to the war, short.
func effects_text() -> String:
	var parts: Array[String] = []
	var g: float = gun_factor()
	if g < 0.97:
		parts.append("AA guns %d%%" % roundi(g * 100.0))
	var o: float = optical()
	if o < 0.9:
		parts.append("Visual detection %d%%" % roundi(o * 100.0))
	if drones_grounded():
		parts.append("Drones grounded")
	elif amount(WINDY) > 0.5:
		parts.append("Drones slowed")
	if amount(SANDSTORM) > 0.5:
		parts.append("Recon blinded")
	if parts.is_empty():
		return "No effect"
	return " · ".join(parts)
