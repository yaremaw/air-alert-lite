class_name LiteMap
extends RefCounted

const W: int = 980
const H: int = 720
const S: int = 2
const RW: int = W * S
const RH: int = H * S
const NONE: int = 255
const CITY_R: float = 15.0

var seed: int = 0

var ids: PackedByteArray = PackedByteArray()

var cell: PackedByteArray = PackedByteArray()

var edge: PackedFloat32Array = PackedFloat32Array()
var regions: Array[LiteRegion] = []
## Each province is cut into districts, as an oblast is into raions: the
## district of each map unit (NONE for sea), drawn as fainter lines.
var sub: PackedByteArray = PackedByteArray()
## The world round the two countries (neighbours, sea, islands): only drawn.
var world: LiteWorld = null
## Towns marked on an operation's map (see LiteRegionMap): where, and how
## big (2 for the province's city, 1 for a district's town).
var towns: PackedVector2Array = PackedVector2Array()
var town_size: PackedInt32Array = PackedInt32Array()
## When set (the campaign's front), the only names drawn: region id to text.
var label_only: Dictionary = {}
## On an operation's map, the regions (districts) of the province it is over.
var focus: PackedInt32Array = PackedInt32Array()
var capital: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
var capital_name: PackedStringArray = PackedStringArray(["", ""])
## The box round all land, in map units: the view is scaled to fill the
## screen with it.
var land_rect: Rect2 = Rect2(0, 0, W, H)

## How a map is made. One landmass between seas, in one of a few layouts: a
## long chain of land, a crescent, two masses joined by a neck, one compact
## continent, or a chain running corner to corner. Its coast is made ragged
## by noise, more on some maps than others, with bays bitten out of it and now
## and then a peninsula. Ours is the near end of it and theirs the far, split
## by a frontier that runs from coast to coast, turned a different way on each
## map: winding, rugged or ruled straight like a surveyed line, sometimes with
## a deep wedge driven into one side or the other, sometimes with a river
## along part of it. Each country is cut into provinces: the land nearest each
## of a scatter of seeds, measured through a noise warp, so their borders wind
## the way real ones do. Islands, enclaves and stray bits of a province are
## cleaned away, so every country and every province is one piece.
var _ns: int = 0
var _blob_c: PackedVector2Array = PackedVector2Array()
var _blob_r: PackedVector2Array = PackedVector2Array()
var _blob_a: PackedFloat32Array = PackedFloat32Array()
var _blob_e: PackedFloat32Array = PackedFloat32Array()
var _cut_c: PackedVector2Array = PackedVector2Array()
var _cut_r: PackedVector2Array = PackedVector2Array()
var _coast: FastNoiseLite = null
var _coast_a: float = 0.45
var _wobble: FastNoiseLite = null
var _front_n: FastNoiseLite = null
## The fine zigzag of administrative borders and coasts (see _crinkled).
var _crinkle_n: FastNoiseLite = null
## The frontier is laid out across `_axis` (ours is on the side it points
## away from): at each point `v` along it, it lies `_fx + _bend(v)` along the
## axis from the middle of the map.
const MID: Vector2 = Vector2(W * 0.5, H * 0.5)
enum { WINDING, JAGGED, SURVEYED }
var _axis: Vector2 = Vector2.RIGHT
var _style: int = WINDING
var _knots: PackedVector2Array = PackedVector2Array()
var _fx: float = 0.0
var _slope: float = 0.0
var _sal_v: float = 0.0
var _sal_a: float = 0.0
var _sal_w: float = 1.0
## A river along the frontier: how wide (0 for none), and the stretch of it
## (in `v`) it runs along, from one coast.
var _river_w: float = 0.0
var _river_lo: float = 0.0
var _river_hi: float = 0.0
## How much province borders wind, and how many provinces ours has.
var _warp_a: float = 24.0
var _provinces: int = 15
## The layouts are drawn in a space of their own, then fitted to the map
## frame: a point `p` on the map is `_dc + (p - MID) / _dk` in it. So a map
## fills the screen's height as well as its width, whatever its layout.
var _dc: Vector2 = MID
var _dk: Vector2 = Vector2.ONE
## Land is where `_land` is above this.
const LAND: float = 0.1

const OUR_NAMES: Array[String] = [
	"Verbivska", "Lisova", "Zorianska", "Dubivska", "Kalynivska", "Ozerna", "Stepova", "Bilohirska",
	"Sosnivska", "Yasenivska", "Hrabivska", "Kamianska", "Bereznianska", "Topolivska", "Vyshnevska",
	"Lukivska", "Sribnianska", "Klenivska", "Vodianska", "Polianska", "Morivska", "Hlynska",
]
const ENEMY_NAMES: Array[String] = [
	"Morvansk", "Kolmar", "Dvorsk", "Urbelsk", "Velgrad", "Tarmesk", "Zhorovsk", "Brekhov",
	"Sartovsk", "Gromel", "Krasnar", "Ulmedsk", "Borgansk", "Strelov", "Yarmut", "Ozhgorsk",
	"Kurgal", "Vyatsk", "Lebrovo", "Tamsk", "Sorvinsk", "Rudnev", "Belgost", "Orlemsk",
]
const OUR_CAPITALS: Array[String] = ["Zoriv", "Svitanok", "Yasnohrad", "Verbohrad"]
const ENEMY_CAPITALS: Array[String] = ["Morgrad", "Kolvansk", "Tarmund"]

static func generate(p_seed: int) -> LiteMap:
	var m:= LiteMap.new(p_seed)
	m._build()
	return m

# Generating a map takes seconds of per-pixel work, too slow for a browser, so
# the game ships a pool of maps baked ahead (`--lite-bake=N`) and a war loads
# one of them; generation remains for baking and as a fallback.
const BAKED_DIR: String = "res://maps/"
## Off for map previews and baking, so they show freshly generated maps.
static var use_baked: bool = true
static var _baked_count: int = -1

static func baked_count() -> int:
	if _baked_count < 0:
		_baked_count = 0
		while FileAccess.file_exists(BAKED_DIR + "map_%03d.bin" % _baked_count):
			_baked_count += 1
	return _baked_count

## The map for a seed: a baked one when there are any, else generated.
static func for_seed(p_seed: int) -> LiteMap:
	var n: int = baked_count() if use_baked else 0
	if n > 0:
		var m: LiteMap = load_baked(posmod(p_seed, n))
		if m != null:
			return m
	return generate(p_seed)

func save_baked(path: String) -> Error:
	var regs: Array = []
	for r: LiteRegion in regions:
		var nb:= PackedInt32Array()
		for k: int in r.neighbors:
			nb.append(k)
		regs.append({"side": r.side, "area": r.area, "name": r.name, "city": r.city, "parent": r.parent,
			"label": r.label, "center": r.center, "spots": PackedVector2Array(r.spots), "neighbors": nb})
	# The whole map compressed as one piece (Godot's own compressed files
	# work in 4 KB blocks, which come out more than twice the size).
	var raw: PackedByteArray = var_to_bytes({"seed": seed, "ids": ids, "capital": capital, "capital_name": capital_name,
		"land_rect": land_rect, "regions": regs, "sub": sub,
		"world": world.to_dict() if world != null else {}})
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(MAGIC)
	f.store_32(raw.size())
	f.store_buffer(raw.compress(FileAccess.COMPRESSION_ZSTD))
	f.close()
	return OK

const MAGIC: PackedByteArray = [0x53, 0x41, 0x4d, 0x31]

## A baked map's contents, from either file format.
static func _read_baked(path: String) -> Variant:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	if f.get_buffer(4) == MAGIC:
		var size: int = f.get_32()
		var raw: PackedByteArray = f.get_buffer(f.get_length() - 8).decompress(size, FileAccess.COMPRESSION_ZSTD)
		f.close()
		return bytes_to_var(raw)
	f.close()
	f = FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return null
	var d: Variant = f.get_var()
	f.close()
	return d

static func load_baked(index: int) -> LiteMap:
	var got: Variant = _read_baked(BAKED_DIR + "map_%03d.bin" % index)
	if not got is Dictionary:
		return null
	var d: Dictionary = got
	var m:= LiteMap.new(int(d["seed"]))
	m.ids = d["ids"]
	m.capital = d["capital"]
	m.capital_name = d["capital_name"]
	m.land_rect = d["land_rect"]
	m.sub = d.get("sub", PackedByteArray())
	if d.has("world") and not (d["world"] as Dictionary).is_empty():
		m.world = LiteWorld.from_dict(d["world"])
	var i: int = 0
	for rd: Dictionary in d["regions"]:
		var r:= LiteRegion.new()
		r.id = i
		r.side = rd["side"]
		r.area = rd["area"]
		r.name = rd["name"]
		r.city = rd["city"]
		r.parent = rd["parent"]
		r.label = rd["label"]
		r.center = rd["center"]
		for p: Vector2 in rd["spots"]:
			r.spots.append(p)
		for k: int in rd["neighbors"]:
			r.neighbors[k] = true
		m.regions.append(r)
		i += 1
	# One region per map unit, sampled from the finer id texture as _build does.
	var cl:= PackedByteArray()
	cl.resize(W * H)
	for y: int in H:
		var ro: int = (y * S + 1) * RW + 1
		var co: int = y * W
		for x: int in W:
			cl[co + x] = m.ids[ro + x * S]
	m.cell = cl
	return m

func _init(p_seed: int = 0) -> void:
	seed = p_seed

## How thin each province is, for finding badly shaped ones: its area over
## that of the widest disc that fits inside it (about 2 for a well rounded
## province, far more for a sliver), and that disc's radius. Cities are left out.
func shapes() -> Array:
	if edge.is_empty():
		_compute_edge()
	var inner:= PackedFloat32Array()
	inner.resize(regions.size())
	for i: int in W * H:
		var c: int = cell[i]
		if c != NONE and edge[i] > inner[c]:
			inner[c] = edge[i]
	var out: Array = []
	for r: LiteRegion in regions:
		if r.city:
			continue
		var rad: float = maxf(1.0, inner[r.id])
		out.append([r.id, r.area / (PI * rad * rad), rad])
	return out

func region_at(p: Vector2) -> int:
	var x: int = int(p.x)
	var y: int = int(p.y)
	if x < 0 or y < 0 or x >= W or y >= H:
		return NONE
	return cell[y * W + x]

func side_at(p: Vector2) -> int:
	var id: int = region_at(p)
	return -1 if id == NONE else regions[id].side

## The province a region belongs to: a capital city is part of the province
## round it. -1 for the sea.
func province(id: int) -> int:
	if id < 0 or id >= regions.size():
		return -1
	var r: LiteRegion = regions[id]
	return r.parent if r.city else r.id

## The province holding a side's capital.
func capital_province(side: int) -> int:
	return province(region_at(capital[side]))

## The provinces bordering province `id`.
func provinces_next_to(id: int) -> Array[int]:
	var out: Array[int] = []
	for r: LiteRegion in regions:
		if province(r.id) != id:
			continue
		for n: int in r.neighbors:
			var p: int = province(n)
			if p != id and p >= 0 and not out.has(p):
				out.append(p)
	return out

## Whether province `id` borders the other side's land.
func on_front(id: int) -> bool:
	for n: int in provinces_next_to(id):
		if regions[n].side != regions[id].side:
			return true
	return false

## Hands a province, and any city in it, to `side`.
func give(id: int, side: int) -> void:
	for r: LiteRegion in regions:
		if r.id == id or (r.city and r.parent == id):
			r.side = side

static func _r(rng: RandomNumberGenerator, a: float, b: float) -> float:
	return a + rng.randf() * (b - a)

func _build() -> void:
	var rng:= RandomNumberGenerator.new()
	rng.seed = seed
	_ns = rng.randi_range(1, (1 << 20) - 1)
	_shape(rng)

	var land:= PackedByteArray()
	land.resize(W * H)
	for y: int in H:
		var i: int = y * W
		for x: int in W:
			land[i] = 1 if _land(x + 0.5, y + 0.5) > LAND else 0
			i += 1
	_fill_lakes(land)
	var across:= PackedFloat32Array()
	across.resize(W * H)
	_place_frontier(rng, land, across)
	var side:= PackedInt32Array()
	side.resize(W * H)
	for i: int in W * H:
		side[i] = -1 if land[i] == 0 else (0 if across[i] < _fx else 1)
	# The river: water along its stretch of the frontier.
	if _river_w > 0.0:
		for y: int in H:
			for x: int in W:
				var i: int = y * W + x
				if side[i] >= 0 and _river(x + 0.5, y + 0.5):
					side[i] = -1
	side = _keep_mainland(side)
	_one_piece(side)
	_no_slivers(side)
	_one_piece(side)
	_smooth_frontier(side)
	_one_piece(side)

	var to_enemy: Array[PackedFloat32Array] = [
		_chamfer(side, func(v: int) -> bool: return v == 1),
		_chamfer(side, func(v: int) -> bool: return v == 0),
	]
	var to_sea: PackedFloat32Array = _chamfer(side, func(v: int) -> bool: return v < 0)
	var room: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
	var te0: PackedFloat32Array = to_enemy[0]
	var te1: PackedFloat32Array = to_enemy[1]
	var box_lo: Array[Vector2] = [Vector2(W, H), Vector2(W, H)]
	var box_hi: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
	for y: int in H:
		for x: int in W:
			var i: int = y * W + x
			var sv: int = side[i]
			if sv < 0:
				continue
			box_lo[sv] = box_lo[sv].min(Vector2(x, y))
			box_hi[sv] = box_hi[sv].max(Vector2(x, y))
			if to_sea[i] >= 32:
				room[sv] = maxf(room[sv], te0[i] if sv == 0 else te1[i])
	# Both capitals sit as far from the frontier as each other, somewhere
	# different on every map.
	var reach: float = minf(minf(room[0], room[1]), 280.0) * 0.85
	var want0:= Vector2(lerpf(box_lo[0].x, box_hi[0].x, _r(rng, 0.2, 0.55)), lerpf(box_lo[0].y, box_hi[0].y, _r(rng, 0.25, 0.75)))
	var want1:= Vector2(lerpf(box_lo[1].x, box_hi[1].x, _r(rng, 0.45, 0.8)), lerpf(box_lo[1].y, box_hi[1].y, _r(rng, 0.25, 0.75)))
	capital[0] = _place(side, 0, te0, to_sea, reach, want0)
	capital[1] = _place(side, 1, te1, to_sea, reach, want1)
	var area: PackedInt32Array = PackedInt32Array([0, 0])
	for v: int in side:
		if v >= 0:
			area[v] += 1
	var per: float = area[0] / float(_provinces)
	var seeds0: Array[Vector2] = [capital[0]]
	var seeds1: Array[Vector2] = [capital[1]]
	var seeds: Array[Array] = [seeds0, seeds1]
	for s: int in 2:
		var want: int = _provinces if s == 0 else clampi(roundi(area[1] / per), 8, 22)
		var dmin: float = sqrt(per) * 0.82
		var mine: Array[Vector2] = seeds0 if s == 0 else seeds1
		var tries: int = 0
		while tries < 30000 and mine.size() < want:
			if tries % 4000 == 3999:
				dmin *= 0.9
			var x: int = rng.randi_range(0, W - 1)
			var y: int = rng.randi_range(0, H - 1)
			tries += 1
			if side[y * W + x] != s:
				continue
			var p:= Vector2(x, y)
			var ok: bool = true
			# Provinces differ in size, as real ones do: big ones in some
			# parts of the country, small ones in others.
			var near: float = dmin * clampf(1.0 + 0.9 * _fbm(x * 0.0055, y * 0.0055, _ns + 41), 0.68, 1.4)
			for list: Array in seeds:
				for q: Vector2 in list:
					if q.distance_to(p) < near:
						ok = false
						break
			if ok:
				mine.append(p)
	var n0: int = seeds0.size()
	var n1: int = seeds1.size()
	var city: PackedInt32Array = PackedInt32Array([n0 + n1, n0 + n1 + 1])
	var all:= PackedVector2Array()
	for list: Array in seeds:
		for p: Vector2 in list:
			all.append(p)

	# Provinces, one map unit at a time, then cleaned up.
	var reg:= PackedInt32Array()
	reg.resize(W * H)
	for y: int in H:
		var i: int = y * W
		for x: int in W:
			var sv: int = side[i]
			reg[i] = -1 if sv < 0 else _nearest(all, x + 0.5, y + 0.5, 0 if sv == 0 else n0, n0 if sv == 0 else n0 + n1)
			i += 1
	_merge_strays(reg)
	_merge_strays(reg)
	# No province drawn out into a thin strip or tail (one squeezed along the
	# frontier, say): parts narrower than about 2 * THIN go to the provinces
	# round them, and a province left with nothing goes altogether.
	_thin_out(reg, side, n0 + n1, PackedInt32Array([0, n0]))
	_merge_strays(reg)
	var kept: Array = _renumber(reg, all, n0)
	all = kept[0]
	n0 = kept[1]
	n1 = all.size() - n0
	city = PackedInt32Array([n0 + n1, n0 + n1 + 1])
	_n0 = n0
	reg = _crinkled(reg)
	_merge_strays(reg)
	_fine_ids(reg, all, n0, n1, city)
	sub = _districts(reg, n0 + n1, rng)
	var cell_l:= PackedByteArray()
	cell_l.resize(W * H)
	for y: int in H:
		var ro: int = (y * S + 1) * RW + 1
		var co: int = y * W
		for x: int in W:
			cell_l[co + x] = ids[ro + x * S]
	cell = cell_l
	_compute_edge()
	var lo:= Vector2(W, H)
	var hi:= Vector2.ZERO
	for y: int in range(0, H, 2):
		for x: int in range(0, W, 2):
			if cell_l[y * W + x] != NONE:
				lo = lo.min(Vector2(x, y))
				hi = hi.max(Vector2(x + 2, y + 2))
	land_rect = Rect2(lo, hi - lo)
	world = LiteWorld.generate(self, seed)

	var ours: Array[String] = _shuffled(OUR_NAMES, rng)
	var theirs: Array[String] = _shuffled(ENEMY_NAMES, rng)
	capital_name[0] = OUR_CAPITALS[rng.randi_range(0, OUR_CAPITALS.size() - 1)]
	capital_name[1] = ENEMY_CAPITALS[rng.randi_range(0, ENEMY_CAPITALS.size() - 1)]
	var total: int = n0 + n1 + 2
	for i: int in total:
		var r:= LiteRegion.new()
		r.id = i
		r.side = 0 if i < n0 or i == city[0] else 1
		r.city = i >= n0 + n1
		if r.city:
			r.name = capital_name[r.side]
			r.parent = 0 if r.side == 0 else n0
		elif i == 0:
			r.name = capital_name[0] + "ska"
		else:
			r.name = ours[(i - 1) % ours.size()] if r.side == 0 else theirs[(i - n0) % theirs.size()]
		regions.append(r)
	var sum:= PackedVector2Array()
	sum.resize(total)
	var best:= PackedFloat32Array()
	best.resize(total)
	var spots: Array[Array] = []
	var areas:= PackedInt32Array()
	areas.resize(total)
	for i: int in total:
		best[i] = -3.4028235e+38
		spots.append([] as Array[Vector2])
	var cl: PackedByteArray = cell
	var ed: PackedFloat32Array = edge
	for y: int in H:
		for x: int in W:
			var i: int = y * W + x
			var id: int = cl[i]
			if id == NONE:
				continue
			areas[id] += 1
			sum[id] += Vector2(x + 0.5, y + 0.5)
			if ed[i] >= 6 and (x + y * 7) % 5 == 0:
				spots[id].append(Vector2(x + 0.5, y + 0.5))
			if x + 1 < W:
				var n: int = cl[i + 1]
				if n != NONE and n != id:
					regions[id].neighbors[n] = true
					regions[n].neighbors[id] = true
			if y + 1 < H:
				var n: int = cl[i + W]
				if n != NONE and n != id:
					regions[id].neighbors[n] = true
					regions[n].neighbors[id] = true
	for r: LiteRegion in regions:
		r.area = areas[r.id]
		r.center = sum[r.id] / r.area if r.area > 0 else capital[r.side]

	var centers:= PackedVector2Array()
	var caps:= PackedVector2Array()
	for r: LiteRegion in regions:
		centers.append(r.center)
		caps.append(capital[r.side])
	var labels:= PackedVector2Array()
	labels.resize(total)
	for y: int in H:
		for x: int in W:
			var i: int = y * W + x
			var id: int = cl[i]
			if id == NONE:
				continue
			var p:= Vector2(x + 0.5, y + 0.5)
			var score: float = minf(ed[i], 40) - 0.06 * p.distance_to(centers[id])

			score -= maxf(0, 75 - p.distance_to(caps[id])) * 1.5
			if score > best[id]:
				best[id] = score
				labels[id] = p
	for r: LiteRegion in regions:
		r.label = labels[r.id]
	for r: LiteRegion in regions:
		var list: Array[Vector2] = spots[r.id]
		var i: int = list.size() - 1
		while i > 0:
			var j: int = rng.randi_range(0, i)
			var t: Vector2 = list[i]
			list[i] = list[j]
			list[j] = t
			i -= 1
		for k: int in mini(80, list.size()):
			r.spots.append(list[k])
		if r.city:
			r.label = capital[r.side] + Vector2(0, 19)

static func _shuffled(src: Array[String], rng: RandomNumberGenerator) -> Array[String]:
	var a: Array[String] = src.duplicate()
	var i: int = a.size() - 1
	while i > 0:
		var j: int = rng.randi_range(0, i)
		var t: String = a[i]
		a[i] = a[j]
		a[j] = t
		i -= 1
	return a

## The landmass, the bays cut into it, and the noise for its coast,
## the frontier and province borders.
func _shape(rng: RandomNumberGenerator) -> void:
	_coast = FastNoiseLite.new()
	_coast.seed = _ns
	_coast.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_coast.fractal_type = FastNoiseLite.FRACTAL_FBM
	_coast.fractal_octaves = 5
	_coast.frequency = _r(rng, 0.004, 0.0075)
	_coast_a = _r(rng, 0.3, 0.55)
	_wobble = FastNoiseLite.new()
	_wobble.seed = _ns + 7
	_wobble.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_wobble.fractal_type = FastNoiseLite.FRACTAL_FBM
	_wobble.fractal_octaves = 3
	_wobble.frequency = _r(rng, 0.008, 0.014)
	_warp_a = _r(rng, 10.0, 34.0)
	_provinces = rng.randi_range(12, 18)
	_front_n = FastNoiseLite.new()
	_front_n.seed = _ns + 13
	_front_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_front_n.fractal_type = FastNoiseLite.FRACTAL_FBM
	_front_n.fractal_octaves = 4
	_front_n.frequency = 0.0055
	_crinkle_n = FastNoiseLite.new()
	_crinkle_n.seed = _ns + 29
	_crinkle_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_crinkle_n.fractal_type = FastNoiseLite.FRACTAL_FBM
	_crinkle_n.fractal_octaves = 3
	_crinkle_n.frequency = 0.045
	# The land fills the map, as a country fills an alert map: one broad
	# mass, squarer than an oval, its outline broken by lobes pushing out on
	# some sides (one may run out into a long arm), with the coast's noise,
	# bays and now and then a peninsula on top. No two alike, none a blob.
	var n: int = 1
	var cx: float = W * 0.5 + _r(rng, -20, 20)
	var cy: float = H * 0.5 + _r(rng, -15, 15)
	var hw: float = _r(rng, 320, 390)
	var hh: float = _r(rng, 225, 275)
	_oval(Vector2(cx, cy), Vector2(hw, hh), _r(rng, -0.12, 0.12), _r(rng, 2.8, 4.2))
	for k: int in rng.randi_range(3, 5):
		var a: float = rng.randf() * TAU
		var at:= Vector2(cx + cos(a) * hw * _r(rng, 0.7, 0.9), cy + sin(a) * hh * _r(rng, 0.7, 0.9))
		var long: bool = rng.randf() < 0.25
		_oval(at, Vector2(_r(rng, 150, 210) if long else _r(rng, 85, 150), _r(rng, 60, 90) if long else _r(rng, 70, 120)), a + _r(rng, -0.5, 0.5))
		n += 1
	var turn: float = _r(rng, -0.3, 0.3)
	_fit(rng)
	_axis = (Vector2.from_angle(turn) * _dk).normalized()
	# Now and then a peninsula reaching out to sea.
	for k: int in (1 if rng.randf() < 0.4 else 0):
		var b: int = rng.randi_range(1, n - 1)
		var d:= Vector2.from_angle(rng.randf() * TAU)
		var reach: float = maxf(_blob_r[b].x, _blob_r[b].y) * 0.8
		var length: float = _r(rng, 55, 95)
		_oval(_blob_c[b] + d * (reach + length * 0.45), Vector2(length, _r(rng, 32, 48)), d.angle())
	# Bays bitten out of the coast.
	var bays: int = rng.randi_range(1, 3)
	for k: int in 40:
		if _cut_c.size() >= bays:
			break
		var b: int = rng.randi_range(0, n - 1)
		var d:= Vector2.from_angle(rng.randf() * TAU)
		var c: Vector2 = _blob_c[b] + d * maxf(_blob_r[b].x, _blob_r[b].y) * _r(rng, 0.85, 1.05)
		# Only on the coast: one deep inland would leave a lake.
		if _ovals(c) < 0.12:
			_cut_c.append(c)
			_cut_r.append(Vector2(_r(rng, 35, 80), _r(rng, 25, 55)))

## Fits the layout to the frame: stretched towards the frame's own shape
## (about 1.4 times as wide as tall) but keeping some of its own, from a
## little taller to a lot wider than that, and filling most of the frame.
func _fit(rng: RandomNumberGenerator) -> void:
	var lo:= Vector2(3.4e38, 3.4e38)
	var hi:= -lo
	var t: float = LAND - _coast_a * 0.45
	for y: int in range(-400, H + 400, 8):
		for x: int in range(-400, W + 400, 8):
			if _ovals(Vector2(x, y)) > t:
				lo = lo.min(Vector2(x, y))
				hi = hi.max(Vector2(x, y))
	var size: Vector2 = (hi - lo).max(Vector2(50, 50))
	var room:= Vector2(W - 70, H - 70)
	var aspect: float = clampf(lerpf(size.x / size.y, room.x / room.y, _r(rng, 0.55, 0.8)), 1.1, 1.75)
	var want: Vector2 = Vector2(room.x, room.x / aspect) if aspect > room.x / room.y else Vector2(room.y * aspect, room.y)
	want *= _r(rng, 0.96, 1.0)
	var k: Vector2 = want / size
	# Not stretched so far one way that the shapes look pulled out of true.
	var mean: float = sqrt(k.x * k.y)
	var r: float = clampf(k.y / k.x, 0.6, 1.7)
	k = Vector2(mean / sqrt(r), mean * sqrt(r))
	k *= minf(room.x / (size.x * k.x), room.y / (size.y * k.y))
	_dk = k
	_dc = (lo + hi) * 0.5

## An oval of land, or with `e` over 2 a squarer one (a superellipse).
func _oval(c: Vector2, r: Vector2, a: float, e: float = 2.0) -> void:
	_blob_c.append(c)
	_blob_r.append(r)
	_blob_a.append(a)
	_blob_e.append(e)

## How far inside the ovals a point is: 1 at a centre, 0 on the rim.
func _ovals(p: Vector2) -> float:
	var v: float = -1.0
	for k: int in _blob_c.size():
		var d: Vector2 = (p - _blob_c[k]).rotated(-_blob_a[k]) / _blob_r[k]
		var e: float = _blob_e[k]
		var l: float = d.length() if e == 2.0 else pow(pow(absf(d.x), e) + pow(absf(d.y), e), 1.0 / e)
		v = maxf(v, 1.0 - l)
	return v

## How far inland a point is: above LAND is land.
func _land(x: float, y: float) -> float:
	var p: Vector2 = _dc + (Vector2(x, y) - MID) / _dk
	var v: float = _ovals(p) + _coast_a * _coast.get_noise_2d(x, y) + COAST_CRINKLE * _crinkle_n.get_noise_2d(x, y)
	for k: int in _cut_c.size():
		var l: float = ((p - _cut_c[k]) / _cut_r[k]).length_squared()
		if l < 1.0:
			v -= 1.3 * (1.0 - sqrt(l))
	# Never right up to the edge of the map.
	var m: float = minf(minf(x, y), minf(W - x, H - y))
	# Fading out well before it: the land never runs up to the map's edge,
	# where it would end in a straight line (seen on an operation's map).
	if m < 40.0:
		v -= pow((40.0 - m) / 40.0, 1.5) * 3.0
	return v

## Water that does not reach the open sea is filled in: no lakes, which on
## this map would read as holes.
static func _fill_lakes(land: PackedByteArray) -> void:
	var sea:= PackedInt32Array()
	sea.resize(W * H)
	for i: int in W * H:
		sea[i] = 0 if land[i] == 0 else -1
	var res: Array = _label(sea)
	var comp: PackedInt32Array = res[0]
	var open:= {}
	for x: int in W:
		open[comp[x]] = true
		open[comp[(H - 1) * W + x]] = true
	for y: int in H:
		open[comp[y * W]] = true
		open[comp[y * W + W - 1]] = true
	for i: int in W * H:
		if comp[i] >= 0 and not open.has(comp[i]):
			land[i] = 1

## How far the frontier is pushed along the axis at `v` across it, besides
## `_fx`: the way it leans, its wedge, and its winding, rugged or ruled shape.
func _bend(v: float) -> float:
	var d: float = (v - _sal_v) / _sal_w
	var g: float = _slope * v + _sal_a * exp(-d * d)
	match _style:
		WINDING:
			g += 80.0 * _front_n.get_noise_1d(v) + 12.0 * _front_n.get_noise_1d(v * 4.0 + 1000.0)
		JAGGED:
			g += 50.0 * _front_n.get_noise_1d(v) + 16.0 * _front_n.get_noise_1d(v * 3.0 + 1000.0)
		_:
			# Straight runs between corners, the way borders are drawn with a ruler.
			var k: int = 0
			while k < _knots.size() - 2 and v > _knots[k + 1].x:
				k += 1
			var a: Vector2 = _knots[k]
			var b: Vector2 = _knots[k + 1]
			g += lerpf(a.y, b.y, clampf((v - a.x) / (b.x - a.x), 0.0, 1.0)) + 2.5 * _front_n.get_noise_1d(v * 6.0)
	return g

## Where a point is, relative to the frontier: below `_fx` it is ours.
func _across(x: float, y: float) -> float:
	var d:= Vector2(x, y) - MID
	return d.dot(_axis) - _bend(d.dot(Vector2(-_axis.y, _axis.x)))

## Whether a point is in the frontier river.
func _river(x: float, y: float) -> bool:
	if _river_w <= 0.0:
		return false
	var d:= Vector2(x, y) - MID
	var v: float = d.dot(Vector2(-_axis.y, _axis.x))
	return v >= _river_lo and v <= _river_hi and absf(d.dot(_axis) - _bend(v) - _fx) < _river_w * 0.5

## Lays the frontier: its style, how it leans and its wedge, then slid along
## the axis until our share of the land is what it should be (a little under
## half). Fills `across` with each map unit's place relative to it.
func _place_frontier(rng: RandomNumberGenerator, land: PackedByteArray, across: PackedFloat32Array) -> void:
	var roll: float = rng.randf()
	# (The ruled, straight-lined style is left out: it read as artificial.)
	_style = WINDING if roll < 0.6 else JAGGED
	_slope = _r(rng, -0.3, 0.3)
	_sal_v = _r(rng, -220, 220)
	_sal_a = 0.0 if rng.randf() < 0.6 else _r(rng, 45, 115) * (1.0 if rng.randf() < 0.5 else -1.0)
	_sal_w = _r(rng, 85, 150)
	if _style == SURVEYED:
		var v: float = -700.0
		_knots.append(Vector2(v, 0.0))
		while v < 700.0:
			v += _r(rng, 90, 260)
			_knots.append(Vector2(v, _r(rng, -70, 70)))
	var ws:= PackedFloat32Array()
	var lo_v: float = 3.4e38
	var hi_v: float = -3.4e38
	var perp:= Vector2(-_axis.y, _axis.x)
	for y: int in H:
		for x: int in W:
			var i: int = y * W + x
			if land[i] == 0:
				across[i] = 3.4e38
				continue
			var w: float = _across(x + 0.5, y + 0.5)
			across[i] = w
			ws.append(w)
			var v: float = (Vector2(x + 0.5, y + 0.5) - MID).dot(perp)
			lo_v = minf(lo_v, v)
			hi_v = maxf(hi_v, v)
	ws.sort()
	_fx = ws[clampi(int(ws.size() * _r(rng, 0.42, 0.5)), 0, ws.size() - 1)]
	# Now and then a river runs along part of it, in from one coast.
	if rng.randf() < 0.35:
		_river_w = _r(rng, 4.5, 7.0)
		var f: float = _r(rng, 0.35, 0.7)
		if rng.randf() < 0.5:
			_river_lo = lo_v - 50.0
			_river_hi = lerpf(lo_v, hi_v, f)
		else:
			_river_lo = lerpf(lo_v, hi_v, 1.0 - f)
			_river_hi = hi_v + 50.0
	# No river after all: it ran along the frontier as first laid, which the
	# tidying then moves, so it wandered across the frontier as a notched
	# dark gap. (Its dice are still thrown, so every map keeps its layout.)
	_river_w = 0.0

## Each country in one piece: any stray bit of one (cut off by the other's
## bulge) goes to the other.
func _one_piece(side: PackedInt32Array) -> void:
	for pass_: int in 2:
		var res: Array = _label(side)
		var comp: PackedInt32Array = res[0]
		var sizes: PackedInt32Array = res[1]
		var vals: PackedInt32Array = res[2]
		var best:= PackedInt32Array([-1, -1])
		for c: int in sizes.size():
			var s: int = vals[c]
			if best[s] < 0 or sizes[c] > sizes[best[s]]:
				best[s] = c
		var moved: bool = false
		for i: int in W * H:
			var c: int = comp[i]
			if c >= 0 and c != best[vals[c]]:
				side[i] = 1 - vals[c]
				moved = true
		if not moved:
			return

## No thin strips of one country squeezed between the other and the sea:
## any part of a country narrower than SLIVER across that touches the other
## goes to the other. One country after the other, so the two never swap
## corners where the frontier meets the coast.
const SLIVER: float = 8.0
func _no_slivers(side: PackedInt32Array) -> void:
	for s: int in 2:
		var inside: PackedFloat32Array = _chamfer(side, func(v: int) -> bool: return v != s)
		var core:= PackedFloat32Array()
		core.resize(W * H)
		for i: int in W * H:
			core[i] = 0.0 if side[i] == s and inside[i] >= SLIVER else 1000000000.0
		var near_core: PackedFloat32Array = _chamfer_passes(core)
		var other: PackedFloat32Array = _chamfer(side, func(v: int) -> bool: return v == 1 - s)
		for i: int in W * H:
			if side[i] == s and near_core[i] > SLIVER + 1.0 and other[i] < SLIVER * 1.5:
				side[i] = 1 - s

## Rounds off the notches tidying leaves in the frontier: each land unit
## goes with the country holding most of the land within 2 units of it
## (ties stay), twice over. Counted from running sums, not unit by unit.
func _smooth_frontier(side: PackedInt32Array) -> void:
	const R: int = 2
	var sw: int = W + 1
	for pass_: int in 2:
		var c0:= PackedInt32Array()
		var c1:= PackedInt32Array()
		c0.resize(sw * (H + 1))
		c1.resize(sw * (H + 1))
		for y: int in H:
			var r0: int = 0
			var r1: int = 0
			for x: int in W:
				var v: int = side[y * W + x]
				if v == 0:
					r0 += 1
				elif v == 1:
					r1 += 1
				c0[(y + 1) * sw + x + 1] = c0[y * sw + x + 1] + r0
				c1[(y + 1) * sw + x + 1] = c1[y * sw + x + 1] + r1
		var out: PackedInt32Array = side.duplicate()
		for y: int in H:
			var y0: int = maxi(0, y - R)
			var y1: int = mini(H, y + R + 1)
			for x: int in W:
				var i: int = y * W + x
				if side[i] < 0:
					continue
				var x0: int = maxi(0, x - R)
				var x1: int = mini(W, x + R + 1)
				var n0: int = c0[y1 * sw + x1] - c0[y0 * sw + x1] - c0[y1 * sw + x0] + c0[y0 * sw + x0]
				var n1: int = c1[y1 * sw + x1] - c1[y0 * sw + x1] - c1[y1 * sw + x0] + c1[y0 * sw + x0]
				if n0 > n1:
					out[i] = 0
				elif n1 > n0:
					out[i] = 1
		for i: int in W * H:
			side[i] = out[i]

## Labels the pieces of `v`: cells side by side with the same value (not
## below 0). Returns each cell's piece (or -1), and each piece's size and value.
static func _label(v: PackedInt32Array) -> Array:
	var comp:= PackedInt32Array()
	comp.resize(W * H)
	comp.fill(-1)
	var sizes:= PackedInt32Array()
	var vals:= PackedInt32Array()
	var stack:= PackedInt32Array()
	stack.resize(W * H)
	var n_all: int = W * H
	for i: int in n_all:
		var val: int = v[i]
		if val < 0 or comp[i] >= 0:
			continue
		var c: int = sizes.size()
		var n: int = 0
		var top: int = 1
		comp[i] = c
		stack[0] = i
		while top > 0:
			top -= 1
			var j: int = stack[top]
			n += 1
			var x: int = j % W
			if x > 0 and comp[j - 1] < 0 and v[j - 1] == val:
				comp[j - 1] = c
				stack[top] = j - 1
				top += 1
			if x + 1 < W and comp[j + 1] < 0 and v[j + 1] == val:
				comp[j + 1] = c
				stack[top] = j + 1
				top += 1
			if j >= W and comp[j - W] < 0 and v[j - W] == val:
				comp[j - W] = c
				stack[top] = j - W
				top += 1
			if j + W < n_all and comp[j + W] < 0 and v[j + W] == val:
				comp[j + W] = c
				stack[top] = j + W
				top += 1
		sizes.append(n)
		vals.append(val)
	return [comp, sizes, vals]

## The province a point belongs to: the nearest of seeds `a` to `b` - 1,
## measured from where the noise warp moves it, so borders wind.
func _nearest(seeds: PackedVector2Array, x: float, y: float, a: int, b: int) -> int:
	var q:= Vector2(x + _warp_a * _wobble.get_noise_2d(x, y), y + _warp_a * _wobble.get_noise_2d(x + 517.0, y - 311.0))
	var best: int = a
	var bd: float = 3.4028235e+38
	for k: int in range(a, b):
		var d: float = q.distance_squared_to(seeds[k])
		if d < bd:
			bd = d
			best = k
	return best

## Each province in one piece: a stray bit of one goes to the province of
## the same country it touches most.
static func _merge_strays(reg: PackedInt32Array) -> void:
	var res: Array = _label(reg)
	var comp: PackedInt32Array = res[0]
	var sizes: PackedInt32Array = res[1]
	var vals: PackedInt32Array = res[2]
	var best: Dictionary = {}
	for c: int in sizes.size():
		var r: int = vals[c]
		if not best.has(r) or sizes[c] > sizes[best[r]]:
			best[r] = c
	var votes: Dictionary = {}
	for i: int in W * H:
		var c: int = comp[i]
		if c < 0 or best[vals[c]] == c:
			continue
		var x: int = i % W
		for j: int in [i - 1 if x > 0 else -1, i + 1 if x + 1 < W else -1, i - W, i + W]:
			if j < 0 or j >= W * H:
				continue
			var o: int = reg[j]
			if o < 0 or o == vals[c] or comp[j] == c:
				continue
			if not votes.has(c):
				votes[c] = {}
			votes[c][o] = int(votes[c].get(o, 0)) + 1
	var to:= {}
	for c: int in votes:
		var top: int = -1
		var tn: int = 0
		for o: int in votes[c]:
			if votes[c][o] > tn:
				tn = votes[c][o]
				top = o
		to[c] = top
	for i: int in W * H:
		var c: int = comp[i]
		if c >= 0 and to.has(c):
			reg[i] = to[c]

## The id texture, at S texels per map unit: copied from the map units where
## all round is one province, worked out texel by texel along borders and
## coasts so they are smooth; the capital cities are rings round each capital.
func _fine_ids(reg: PackedInt32Array, seeds: PackedVector2Array, n0: int, n1: int, city: PackedInt32Array) -> void:
	var mixed:= PackedByteArray()
	mixed.resize(W * H)
	for y: int in H:
		for x: int in W:
			var i: int = y * W + x
			var v: int = reg[i]
			var m: int = 0
			for dy: int in range(-1, 2):
				var yy: int = y + dy
				if yy < 0 or yy >= H:
					continue
				for dx: int in range(-1, 2):
					var xx: int = x + dx
					if xx >= 0 and xx < W and reg[yy * W + xx] != v:
						m = 1
			mixed[i] = m
	ids.resize(RW * RH)
	var cr2: float = CITY_R * CITY_R
	# Where a texel lies inside its map unit (S * S places), the weights of
	# the 4 x 4 map units round it: a gaussian on the distance to each centre.
	var kern: Array[PackedFloat32Array] = []
	for sy: int in S:
		for sx: int in S:
			var k:= PackedFloat32Array()
			k.resize(16)
			var t:= Vector2((sx + 0.5) / S, (sy + 0.5) / S)
			for j: int in 4:
				for i: int in 4:
					var d: Vector2 = Vector2(i - 0.5, j - 0.5) - t
					k[j * 4 + i] = exp(-d.length_squared() / (2.0 * VOTE_SIGMA * VOTE_SIGMA))
			kern.append(k)
	var lab:= PackedInt32Array()
	lab.resize(16)
	var wt:= PackedFloat32Array()
	wt.resize(16)
	for fy: int in RH:
		var cy: int = fy / S
		var py: float = (fy + 0.5) / S
		var o: int = fy * RW
		for fx: int in RW:
			var cx: int = fx / S
			var ci: int = cy * W + cx
			var v: int = reg[ci]
			var px: float = (fx + 0.5) / S
			if mixed[ci] == 1:
				if _land(px, py) <= LAND or _river(px, py):
					if _around(reg, cx, cy, -1):
						v = -1
				else:
					# Land: the province the map units round it vote for,
					# nearer ones counting more. Borders and the frontier come
					# out as smooth curves through the provinces as they finally
					# are, whatever was moved between them on the way.
					var k: PackedFloat32Array = kern[(fy % S) * S + (fx % S)]
					var n: int = 0
					for j: int in 4:
						var yy: int = cy - 1 + j
						if yy < 0 or yy >= H:
							continue
						for i: int in 4:
							var xx: int = cx - 1 + i
							if xx < 0 or xx >= W:
								continue
							var l: int = reg[yy * W + xx]
							if l < 0:
								continue
							var q: int = 0
							while q < n and lab[q] != l:
								q += 1
							if q == n:
								lab[n] = l
								wt[n] = 0.0
								n += 1
							wt[q] += k[j * 4 + i]
					if n > 0:
						var best: int = 0
						for q: int in range(1, n):
							if wt[q] > wt[best]:
								best = q
						v = lab[best]
			if v < 0:
				ids[o + fx] = NONE
			else:
				var s: int = 0 if v < n0 else 1
				ids[o + fx] = city[s] if Vector2(px, py).distance_squared_to(capital[s]) < cr2 else v

## How much the coast zigzags (see _land), and how far, in map units, a
## border is pushed either way by its zigzag (see _crinkled).
const COAST_CRINKLE: float = 0.04
const CRINKLE: float = 3.6

## Administrative borders are not smooth curves: each map unit takes the
## province of a point a few units away, the offset wandering with noise at
## several scales, so borders, the frontier and districts zigzag the way real
## ones do. Done after the tidying, which would smooth such detail away.
func _crinkled(reg: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = reg.duplicate()
	for y: int in H:
		for x: int in W:
			var i: int = y * W + x
			if reg[i] < 0:
				continue
			var qx: int = clampi(int(x + 0.5 + CRINKLE * _crinkle_n.get_noise_2d(x * 1.7, y * 1.7)), 0, W - 1)
			var qy: int = clampi(int(y + 0.5 + CRINKLE * _crinkle_n.get_noise_2d(x * 1.7 + 913.0, y * 1.7 - 377.0)), 0, H - 1)
			var v: int = reg[qy * W + qx]
			if v >= 0:
				out[i] = v
	return out

## About how much land, in map units, a district has.
const DISTRICT: float = 2600.0

## Each province cut into districts, 1 to 6 of them by its size: the land
## nearest each of a few seeds spread out over it (each as far from the others
## as can be), measured through a gentler warp than the provinces get, and the
## same zigzag. Returns the district of each map unit (NONE for sea).
func _districts(reg: PackedInt32Array, count: int, rng: RandomNumberGenerator) -> PackedByteArray:
	var cells: Array[PackedInt32Array] = []
	for p: int in count:
		cells.append(PackedInt32Array())
	for i: int in W * H:
		if reg[i] >= 0 and reg[i] < count:
			cells[reg[i]].append(i)
	var seeds:= PackedVector2Array()
	var owner:= PackedInt32Array()
	var first:= PackedInt32Array()
	first.resize(count + 1)
	for p: int in count:
		first[p] = seeds.size()
		var list: PackedInt32Array = cells[p]
		if list.is_empty():
			continue
		var k: int = clampi(roundi(list.size() / DISTRICT), 1, 6)
		k = mini(k, maxi(1, (250 - seeds.size()) - (count - p - 1)))
		var sample:= PackedVector2Array()
		for t: int in mini(400, list.size()):
			var c: int = list[rng.randi_range(0, list.size() - 1)]
			sample.append(Vector2(c % W + 0.5, c / W + 0.5))
		var chosen: Array[Vector2] = [sample[0]]
		while chosen.size() < k:
			var best: Vector2 = sample[0]
			var bd: float = -1.0
			for q: Vector2 in sample:
				var dq: float = INF
				for c: Vector2 in chosen:
					dq = minf(dq, q.distance_squared_to(c))
				if dq > bd:
					bd = dq
					best = q
			chosen.append(best)
		for c: Vector2 in chosen:
			seeds.append(c)
			owner.append(p)
	first[count] = seeds.size()
	var d:= PackedInt32Array()
	d.resize(W * H)
	d.fill(-1)
	var warp: float = _warp_a * 0.6
	for p: int in count:
		var a: int = first[p]
		var b: int = first[p + 1]
		for i: int in cells[p]:
			if b - a <= 1:
				d[i] = a
				continue
			var x: float = i % W + 0.5
			var y: float = i / W + 0.5
			var q:= Vector2(x + warp * _wobble.get_noise_2d(x * 1.6, y * 1.6) + CRINKLE * _crinkle_n.get_noise_2d(x * 1.7, y * 1.7),
				y + warp * _wobble.get_noise_2d(x * 1.6 + 517.0, y * 1.6 - 311.0) + CRINKLE * _crinkle_n.get_noise_2d(x * 1.7 + 913.0, y * 1.7 - 377.0))
			var best: int = a
			var bd: float = INF
			for k: int in range(a, b):
				var dd: float = q.distance_squared_to(seeds[k])
				if dd < bd:
					bd = dd
					best = k
			d[i] = best
	# Stray bits of a district go to a district of the same province they touch.
	var res: Array = _label(d)
	var comp: PackedInt32Array = res[0]
	var sizes: PackedInt32Array = res[1]
	var vals: PackedInt32Array = res[2]
	var biggest: Dictionary = {}
	for c: int in sizes.size():
		if not biggest.has(vals[c]) or sizes[c] > sizes[biggest[vals[c]]]:
			biggest[vals[c]] = c
	var to: Dictionary = {}
	for i: int in W * H:
		var c: int = comp[i]
		if c < 0 or biggest[vals[c]] == c or to.has(c):
			continue
		var x: int = i % W
		for j: int in [i - 1 if x > 0 else -1, i + 1 if x + 1 < W else -1, i - W, i + W]:
			if j >= 0 and j < W * H and d[j] >= 0 and d[j] != vals[c] and owner[d[j]] == owner[vals[c]]:
				to[c] = d[j]
				break
	var out:= PackedByteArray()
	out.resize(W * H)
	out.fill(NONE)
	for i: int in W * H:
		var c: int = comp[i]
		if c >= 0:
			out[i] = to[c] if to.has(c) else d[i]
	return out

## How many provinces are ours while the map is being built (they come first).
var _n0: int = 0

## Parts of a province narrower than about twice this, in map units, go to
## its neighbours.
const THIN: float = 13.0
## How far, in map units, the vote for a texel's province reaches.
const VOTE_SIGMA: float = 0.85

## Cuts thin strips and tails off provinces: a morphological opening, one
## province at a time inside its own box. The cells cut off go, spreading
## from their edges, to the neighbouring provinces of the same country; any
## that none reaches stay as they were. A province with no part wider than
## the limit goes whole, unless it is one of `keep` (the capitals').
func _thin_out(reg: PackedInt32Array, side: PackedInt32Array, count: int, keep: PackedInt32Array) -> void:
	var lo:= PackedInt32Array()
	var hi:= PackedInt32Array()
	lo.resize(count * 2)
	hi.resize(count * 2)
	for p: int in count:
		lo[p * 2] = W
		lo[p * 2 + 1] = H
		hi[p * 2] = -1
		hi[p * 2 + 1] = -1
	for y: int in H:
		for x: int in W:
			var v: int = reg[y * W + x]
			if v < 0:
				continue
			lo[v * 2] = mini(lo[v * 2], x)
			lo[v * 2 + 1] = mini(lo[v * 2 + 1], y)
			hi[v * 2] = maxi(hi[v * 2], x)
			hi[v * 2 + 1] = maxi(hi[v * 2 + 1], y)
	var cut:= PackedByteArray()
	cut.resize(W * H)
	const FAR: float = 1000000000.0
	for p: int in count:
		if hi[p * 2] < 0:
			continue
		# The box, a cell larger all round so its edge counts as outside.
		var x0: int = lo[p * 2] - 1
		var y0: int = lo[p * 2 + 1] - 1
		var w: int = hi[p * 2] - x0 + 2
		var h: int = hi[p * 2 + 1] - y0 + 2
		var e:= PackedFloat32Array()
		e.resize(w * h)
		for ly: int in h:
			var y: int = y0 + ly
			for lx: int in w:
				var x: int = x0 + lx
				var mine: bool = x >= 0 and y >= 0 and x < W and y < H and reg[y * W + x] == p
				e[ly * w + lx] = FAR if mine else 0.0
		var inside: PackedFloat32Array = _chamfer_passes(e, w, h)
		var widest: float = 0.0
		for v: float in inside:
			widest = maxf(widest, v)
		var whole: bool = widest < THIN and not keep.has(p)
		if widest < THIN and not whole:
			continue
		var core:= PackedFloat32Array()
		core.resize(w * h)
		for k: int in w * h:
			core[k] = 0.0 if inside[k] >= THIN and inside[k] < FAR else FAR
		var near: PackedFloat32Array = core if whole else _chamfer_passes(core, w, h)
		for ly: int in h:
			var y: int = y0 + ly
			for lx: int in w:
				var x: int = x0 + lx
				if x < 0 or y < 0 or x >= W or y >= H or reg[y * W + x] != p:
					continue
				if whole or near[ly * w + lx] > THIN + 0.5:
					cut[y * W + x] = 1
	# Hand the cut cells to the other provinces of the same country they
	# border, a ring at a time inwards. Cells no other province reaches (a
	# stretch only its own province and the frontier or sea touch) stay put.
	var wave:= PackedInt32Array()
	for i: int in W * H:
		if cut[i] == 1:
			wave.append(i)
	var goes:= PackedInt32Array()
	while wave.size() > 0:
		goes.resize(wave.size())
		var moved: int = 0
		for k: int in wave.size():
			var i: int = wave[k]
			goes[k] = -1
			var x: int = i % W
			for j: int in [i - 1 if x > 0 else -1, i + 1 if x + 1 < W else -1, i - W, i + W]:
				if j >= 0 and j < W * H and cut[j] == 0 and reg[j] >= 0 and reg[j] != reg[i] and side[j] == side[i]:
					goes[k] = reg[j]
					break
		var next:= PackedInt32Array()
		for k: int in wave.size():
			var i: int = wave[k]
			if goes[k] >= 0:
				reg[i] = goes[k]
				cut[i] = 0
				moved += 1
			else:
				next.append(i)
		if moved == 0:
			break
		wave = next

## Province ids made consecutive again after some went: ours first, then
## theirs. Returns the seeds of those left and how many of them are ours.
static func _renumber(reg: PackedInt32Array, seeds: PackedVector2Array, n0: int) -> Array:
	var used:= PackedByteArray()
	used.resize(seeds.size())
	for v: int in reg:
		if v >= 0:
			used[v] = 1
	var to:= PackedInt32Array()
	to.resize(seeds.size())
	var out:= PackedVector2Array()
	var ours: int = 0
	for k: int in seeds.size():
		to[k] = out.size()
		if used[k] == 1:
			out.append(seeds[k])
			if k < n0:
				ours += 1
	for i: int in reg.size():
		if reg[i] >= 0:
			reg[i] = to[reg[i]]
	return [out, ours]

## Whether province `e` (or sea, -1) is in or next to map unit `x`, `y`.
static func _around(reg: PackedInt32Array, x: int, y: int, e: int) -> bool:
	for dy: int in range(-1, 2):
		var yy: int = y + dy
		if yy < 0 or yy >= H:
			continue
		for dx: int in range(-1, 2):
			var xx: int = x + dx
			if xx >= 0 and xx < W and reg[yy * W + xx] == e:
				return true
	return false

static func _keep_mainland(side: PackedInt32Array) -> PackedInt32Array:
	var comp:= PackedInt32Array()
	comp.resize(W * H)
	var stack:= PackedInt32Array()
	stack.resize(W * H)
	var top: int = 0
	var best_comp: int = 0
	var best_size: int = 0
	var next: int = 0
	for i: int in W * H:
		if side[i] < 0 or comp[i] != 0:
			continue
		next += 1
		var c: int = next
		var size: int = 0
		comp[i] = c
		stack[top] = i
		top += 1
		while top > 0:
			top -= 1
			var j: int = stack[top]
			size += 1
			var x: int = j % W
			var y: int = j / W

			if x > 0 and side[j - 1] >= 0 and comp[j - 1] == 0:
				comp[j - 1] = c
				stack[top] = j - 1
				top += 1
			if x + 1 < W and side[j + 1] >= 0 and comp[j + 1] == 0:
				comp[j + 1] = c
				stack[top] = j + 1
				top += 1
			if y > 0 and side[j - W] >= 0 and comp[j - W] == 0:
				comp[j - W] = c
				stack[top] = j - W
				top += 1
			if y + 1 < H and side[j + W] >= 0 and comp[j + W] == 0:
				comp[j + W] = c
				stack[top] = j + W
				top += 1
		if size > best_size:
			best_size = size
			best_comp = c
	for i: int in W * H:
		if comp[i] != best_comp:
			side[i] = -1
	return side

static func _place(side: PackedInt32Array, s: int, to_enemy: PackedFloat32Array, to_sea: PackedFloat32Array, reach: float, want: Vector2) -> Vector2:
	var best: Vector2 = want
	var bd: float = 3.4028235e+38
	for y: int in range(0, H, 2):
		for x: int in range(0, W, 2):
			var i: int = y * W + x
			if side[i] != s or to_sea[i] < 32:
				continue
			var d: float = absf(to_enemy[i] - reach) * 4 + want.distance_to(Vector2(x, y)) * 0.1
			if d < bd:
				bd = d
				best = Vector2(x + 0.5, y + 0.5)
	return best

static func _chamfer(side: PackedInt32Array, from: Callable) -> PackedFloat32Array:

	var pass_: Array[bool] = [from.call(-1), from.call(0), from.call(1)]
	var e:= PackedFloat32Array()
	e.resize(W * H)
	for i: int in W * H:
		e[i] = 0.0 if pass_[side[i] + 1] else 1000000000.0
	return _chamfer_passes(e)

## Distances out from the cells at 0, over a grid `w` by `h` (the map's by default).
static func _chamfer_passes(e: PackedFloat32Array, w: int = W, h: int = H) -> PackedFloat32Array:
	const D: float = 1.4142
	for y: int in range(1, h - 1):
		var i: int = y * w + 1
		var end: int = y * w + w - 1
		var left: float = e[i - 1]
		var up_left: float = e[i - w - 1]
		var up: float = e[i - w]
		while i < end:
			var up_right: float = e[i - w + 1]
			var v: float = e[i]
			var t: float = left + 1
			if t < v: v = t
			t = up + 1
			if t < v: v = t
			t = up_left + D
			if t < v: v = t
			t = up_right + D
			if t < v: v = t
			e[i] = v
			left = v
			up_left = up
			up = up_right
			i += 1
	for y: int in range(h - 2, 0, -1):
		var i: int = y * w + w - 2
		var end: int = y * w
		var right: float = e[i + 1]
		var down_right: float = e[i + w + 1]
		var down: float = e[i + w]
		while i > end:
			var down_left: float = e[i + w - 1]
			var v: float = e[i]
			var t: float = right + 1
			if t < v: v = t
			t = down + 1
			if t < v: v = t
			t = down_right + D
			if t < v: v = t
			t = down_left + D
			if t < v: v = t
			e[i] = v
			right = v
			down_right = down
			down = down_left
			i -= 1
	return e

func _compute_edge() -> void:
	var cl: PackedByteArray = cell
	var e:= PackedFloat32Array()
	e.resize(W * H)
	for y: int in H:
		for x: int in W:
			var i: int = y * W + x
			var c: int = cl[i]
			var border: bool = c == NONE or x == 0 or y == 0 or x == W - 1 or y == H - 1 or cl[i - 1] != c or cl[i + 1] != c or cl[i - W] != c or cl[i + W] != c
			e[i] = 0.0 if border else 1000000000.0
	edge = _chamfer_passes(e)

static func _fbm(x: float, y: float, s: int) -> float:
	var sum: float = 0.0
	var amp: float = 0.5
	var norm: float = 0.0
	var f: float = 1.0
	for o: int in 3:
		sum += amp * _value(x * f, y * f, s + o * 101)
		norm += amp
		amp *= 0.5
		f *= 2.03
	return sum / norm

static func _value(x: float, y: float, s: int) -> float:
	var xi: int = floori(x)
	var yi: int = floori(y)
	var fx: float = x - xi
	var fy: float = y - yi
	fx = fx * fx * (3 - 2 * fx)
	fy = fy * fy * (3 - 2 * fy)
	var a: float = _hash(xi, yi, s)
	var b: float = _hash(xi + 1, yi, s)
	var c: float = _hash(xi, yi + 1, s)
	var d: float = _hash(xi + 1, yi + 1, s)
	return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy

const _M32: int = 4294967295

static func _mul32(a: int, c: int) -> int:
	return ((((a * (c >> 16)) & 65535) << 16) + a * (c & 65535)) & _M32

static func _hash(x: int, y: int, s: int) -> float:
	var h: int = _mul32(x & _M32, 2376512323) ^ _mul32(y & _M32, 3625334849) ^ _mul32(s & _M32, 3407524639)
	h ^= h >> 15
	h = _mul32(h, 739982445)
	h ^= h >> 12
	h = _mul32(h, 695872825)
	h ^= h >> 15
	return h / 2147483648.0 - 1.0
