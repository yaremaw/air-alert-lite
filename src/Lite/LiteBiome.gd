class_name LiteBiome
extends RefCounted
## Phase 4: the land's biomes as the simulation knows them, the same that
## the command look paints (lite_terrain_bake.gdshader's biomes(), from the
## same noise fields, made here once per map and shared with LiteTerrain).
## Used for where a country's working sites stand (an oil field in the
## desert, a substation in the cold north, a pumping station in the
## wetlands, grain silos on the steppe and the plains), for the snow on
## sites in the north, and for the weather a map gets (LiteEnv.climate).

enum { PLAINS, STEPPE, DESERT, WINTER, WETLANDS, FOREST }

## A whole map's climate (phase 4c): temperate (fields, forests, wetlands,
## a little steppe), arid (desert and dry steppe everywhere), frozen (snow
## and frozen lakes everywhere). The warmth and wetness fields are pulled
## towards it, here and in the terrain bake alike.
enum { TEMPERATE, ARID, FROZEN }
const CLIMATE_NAMES: Array[String] = ["Temperate", "Desert", "Winter"]

static func climate(map: LiteMap) -> int:
	if map.climate < 0:
		# Half the maps temperate, a quarter desert, a quarter winter.
		map.climate = [TEMPERATE, TEMPERATE, ARID, FROZEN][posmod(map.seed * 7919 + 17, 4)]
	return map.climate

## The pull towards a climate: [warmth aimed at, how strongly, wetness scale].
static func climate_shift(c: int) -> Array:
	match c:
		ARID: return [0.88, 0.88, 0.5]
		FROZEN: return [0.1, 0.88, 1.0]
	return [0.46, 0.75, 1.0]
const NAMES: Array[String] = ["Plains", "Steppe", "Desert", "Winter", "Wetlands", "Forest"]

## The fields of the last map asked for: [elev, moist, temp], half the
## terrain's resolution.
static var _seed: int = -1
static var _fields: Array[Image] = []

static func fields(map: LiteMap) -> Array[Image]:
	if _seed == map.seed and _fields.size() == 3:
		return _fields
	var sz: Vector2i = LiteTerrain.size()
	var hs:= Vector2i(ceili(sz.x / 2.0), ceili(sz.y / 2.0))
	_fields = [
		LiteTerrain._noise(map.seed * 3 + 1, 0.012, 4, FastNoiseLite.FRACTAL_FBM, hs),
		LiteTerrain._noise(map.seed * 5 + 2, 0.009, 3, FastNoiseLite.FRACTAL_FBM, hs),
		LiteTerrain._noise(map.seed * 7 + 3, 0.006, 2, FastNoiseLite.FRACTAL_FBM, hs),
	]
	_seed = map.seed
	return _fields

static func _at(img: Image, q: Vector2) -> float:
	var x: int = clampi(int((q.x + 0.5) * 0.5), 0, img.get_width() - 1)
	var y: int = clampi(int((q.y + 0.5) * 0.5), 0, img.get_height() - 1)
	return img.get_pixel(x, y).r

static func _ss(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x) if a < b else 1.0 - smoothstep(b, a, x)

## The biome at map point `p`.
static func at(map: LiteMap, p: Vector2) -> int:
	var f: Array[Image] = fields(map)
	var q: Vector2 = (p - LiteTerrain.origin()) / LiteTerrain.ART
	var cs: Array = climate_shift(climate(map))
	var e: float = _at(f[0], q)
	var m: float = _at(f[1], q) * float(cs[2])
	var lat: float = p.y / float(LiteMap.H)
	var t: float = lerpf(lerpf(_at(f[2], q), clampf(lat, -0.2, 1.2), 0.65), float(cs[0]), float(cs[1]))
	var winter: float = _ss(0.34, 0.26, t)
	var desert: float = _ss(0.62, 0.7, t) * _ss(0.44, 0.36, m) * (1.0 - winter)
	var steppe: float = _ss(0.5, 0.58, t) * _ss(0.54, 0.46, m) * (1.0 - desert) * (1.0 - winter)
	var wet: float = _ss(0.6, 0.68, m) * _ss(0.52, 0.42, e) * (1.0 - desert)
	var forest: float = _ss(0.55, 0.63, m) * (1.0 - desert) * (1.0 - steppe) * (1.0 - wet * 0.7)
	if winter > 0.5:
		return WINTER
	if desert > 0.5:
		return DESERT
	if wet > 0.5:
		return WETLANDS
	if steppe > 0.5:
		return STEPPE
	if forest > 0.5:
		return FOREST
	return PLAINS

## How much of a country's land (or the whole map's, side -1) is each
## biome, as shares, sampled on a grid.
static func shares(map: LiteMap, side: int = -1) -> PackedFloat32Array:
	var n:= PackedFloat32Array([0, 0, 0, 0, 0, 0])
	var total: float = 0.0
	for y: int in range(10, LiteMap.H, 24):
		for x: int in range(10, LiteMap.W, 24):
			var p:= Vector2(x, y)
			var s: int = map.side_at(p)
			if s < 0 or (side >= 0 and s != side):
				continue
			n[at(map, p)] += 1.0
			total += 1.0
	if total > 0.0:
		for i: int in n.size():
			n[i] /= total
	return n

## The map's main biome (forest counts as plains for the weather).
static func dominant(map: LiteMap) -> int:
	var s: PackedFloat32Array = shares(map)
	s[PLAINS] += s[FOREST]
	s[FOREST] = 0.0
	var best: int = PLAINS
	for i: int in s.size():
		if s[i] > s[best] + 0.0001:
			best = i
	# The plains are the rest: another biome over a third of the land wins.
	if best == PLAINS:
		for i: int in [WINTER, DESERT, WETLANDS, STEPPE]:
			if s[i] > 0.33:
				return i
	return best

## The working sites a biome has (LiteKind), the first the most typical.
static func works(b: int) -> Array[int]:
	match b:
		DESERT: return [LiteKind.OILRIG, LiteKind.REFINERY, LiteKind.OILRIG]
		WINTER: return [LiteKind.SUBSTATION]
		WETLANDS: return [LiteKind.PUMP]
		STEPPE: return [LiteKind.SILO]
		PLAINS: return [LiteKind.SILO, LiteKind.SUBSTATION]
	return []

## What a working site brings its country a second, in money.
static func income(k: int) -> float:
	match k:
		LiteKind.OILRIG: return 1.0
		LiteKind.REFINERY: return 2.0
		LiteKind.SILO: return 1.0
		LiteKind.PUMP: return 0.6
		LiteKind.SUBSTATION: return 0.5
	return 0.0
