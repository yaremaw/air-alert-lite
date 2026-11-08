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
## map: winding, jagged or ruled straight like a surveyed line, sometimes with
## a deep wedge driven into one side or the other, sometimes with a river
## along part of it. Each country is cut into provinces: the land nearest each
## of a scatter of seeds, measured through a noise warp, so their borders wind
## the way real ones do. Islands, enclaves and stray bits of a province are
## cleaned away, so every country and every province is one piece.
var _ns: int = 0
var _blob_c: PackedVector2Array = PackedVector2Array()
var _blob_r: PackedVector2Array = PackedVector2Array()
var _blob_a: PackedFloat32Array = PackedFloat32Array()
var _cut_c: PackedVector2Array = PackedVector2Array()
var _cut_r: PackedVector2Array = PackedVector2Array()
var _coast: FastNoiseLite = null
var _coast_a: float = 0.45
var _wobble: FastNoiseLite = null
var _front_n: FastNoiseLite = null
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
	var f: FileAccess = FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return FileAccess.get_open_error()
	f.store_var({"seed": seed, "ids": ids, "capital": capital, "capital_name": capital_name,
		"land_rect": land_rect, "regions": regs})
	f.close()
	return OK

static func load_baked(index: int) -> LiteMap:
	var f: FileAccess = FileAccess.open_compressed(BAKED_DIR + "map_%03d.bin" % index, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return null
	var d: Dictionary = f.get_var()
	f.close()
	var m:= LiteMap.new(int(d["seed"]))
	m.ids = d["ids"]
	m.capital = d["capital"]
	m.capital_name = d["capital_name"]
	m.land_rect = d["land_rect"]
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

func region_at(p: Vector2) -> int:
	var x: int = int(p.x)
	var y: int = int(p.y)
	if x < 0 or y < 0 or x >= W or y >= H:
		return NONE
	return cell[y * W + x]

func side_at(p: Vector2) -> int:
	var id: int = region_at(p)
	return -1 if id == NONE else regions[id].side

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
	_fine_ids(reg, all, n0, n1, city)
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
	var n: int = 0
	var turn: float = 0.0
	match rng.randi_range(0, 4):
		0:
			# A chain of land strung out west to east, leaning a little.
			n = rng.randi_range(4, 5)
			var x0: float = _r(rng, 160, 220)
			var x1: float = W - _r(rng, 160, 220)
			var yc: float = H * 0.5 + _r(rng, -30, 30)
			var tilt: float = _r(rng, -0.22, 0.22)
			for k: int in n:
				var x: float = lerpf(x0, x1, float(k) / (n - 1)) + _r(rng, -35, 35)
				_oval(Vector2(x, yc + (x - W * 0.5) * tilt + _r(rng, -60, 60)), Vector2(_r(rng, 120, 180), _r(rng, 160, 260)), _r(rng, -0.6, 0.6))
			turn = _r(rng, -0.35, 0.35)
		1:
			# A crescent, bowed up or down.
			n = 5
			var bow: float = 1.0 if rng.randf() < 0.5 else -1.0
			var c:= Vector2(W * 0.5, H * 0.5 + bow * _r(rng, 380, 480))
			var rad: float = c.distance_to(Vector2(W * 0.5, H * 0.5)) + _r(rng, -20, 20)
			for k: int in n:
				var a: float = (-PI * 0.5 * bow) + lerpf(-0.8, 0.8, float(k) / (n - 1)) * bow + _r(rng, -0.06, 0.06)
				var at: Vector2 = c + Vector2.from_angle(a) * rad
				_oval(at.clamp(Vector2(150, 140), Vector2(W - 150, H - 140)), Vector2(_r(rng, 115, 160), _r(rng, 120, 175)), a + PI * 0.5)
			turn = _r(rng, -0.25, 0.25)
		2:
			# Two masses joined by a neck of land, the frontier near it.
			n = 3
			_oval(Vector2(_r(rng, 230, 290), H * 0.5 + _r(rng, -60, 60)), Vector2(_r(rng, 170, 210), _r(rng, 210, 270)), _r(rng, -0.5, 0.5))
			_oval(Vector2(W - _r(rng, 230, 290), H * 0.5 + _r(rng, -60, 60)), Vector2(_r(rng, 170, 210), _r(rng, 210, 270)), _r(rng, -0.5, 0.5))
			_oval((_blob_c[0] + _blob_c[1]) * 0.5 + Vector2(0, _r(rng, -50, 50)), Vector2(_r(rng, 120, 160), _r(rng, 55, 85)), _r(rng, -0.3, 0.3))
			turn = _r(rng, -0.15, 0.15)
		3:
			# One compact continent.
			n = 3
			for k: int in n:
				var a: float = TAU * k / n + rng.randf()
				_oval(MID + Vector2.from_angle(a) * _r(rng, 70, 150) * Vector2(1.5, 1.0), Vector2(_r(rng, 200, 260), _r(rng, 180, 240)), rng.randf() * PI)
			turn = _r(rng, -0.6, 0.6)
		_:
			# A chain from one corner towards the other.
			n = rng.randi_range(4, 5)
			var tilt: float = _r(rng, 0.42, 0.62) * (1.0 if rng.randf() < 0.5 else -1.0)
			for k: int in n:
				var x: float = lerpf(190, W - 190, float(k) / (n - 1)) + _r(rng, -25, 25)
				var y: float = clampf(H * 0.5 + (x - W * 0.5) * tilt, 170, H - 170) + _r(rng, -40, 40)
				_oval(Vector2(x, y), Vector2(_r(rng, 120, 170), _r(rng, 150, 220)), atan(tilt) + _r(rng, -0.4, 0.4))
			turn = atan(tilt) * 0.8
	_axis = Vector2.from_angle(turn)
	# Now and then a long peninsula reaching out to sea.
	for k: int in rng.randi_range(0, 2):
		var b: int = rng.randi_range(0, n - 1)
		var d:= Vector2.from_angle(rng.randf() * TAU)
		var reach: float = maxf(_blob_r[b].x, _blob_r[b].y) * 0.8
		var length: float = _r(rng, 55, 95)
		_blob_c.append(_blob_c[b] + d * (reach + length * 0.45))
		_blob_r.append(Vector2(length, _r(rng, 30, 46)))
		_blob_a.append(d.angle())
	# Bays bitten out of the coast.
	var bays: int = rng.randi_range(2, 4)
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

func _oval(c: Vector2, r: Vector2, a: float) -> void:
	_blob_c.append(c)
	_blob_r.append(r)
	_blob_a.append(a)

## How far inside the ovals a point is: 1 at a centre, 0 on the rim.
func _ovals(p: Vector2) -> float:
	var v: float = -1.0
	for k: int in _blob_c.size():
		var d: Vector2 = (p - _blob_c[k]).rotated(-_blob_a[k]) / _blob_r[k]
		v = maxf(v, 1.0 - d.length())
	return v

## How far inland a point is: above LAND is land.
func _land(x: float, y: float) -> float:
	var p:= Vector2(x, y)
	var v: float = _ovals(p) + _coast_a * _coast.get_noise_2d(x, y)
	for k: int in _cut_c.size():
		var l: float = ((p - _cut_c[k]) / _cut_r[k]).length_squared()
		if l < 1.0:
			v -= 1.3 * (1.0 - sqrt(l))
	# Never right up to the edge of the map.
	var m: float = minf(minf(x, y), minf(W - x, H - y))
	if m < 46.0:
		v -= (46.0 - m) / 46.0 * 1.2
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
## `_fx`: the way it leans, its wedge, and its winding, jagged or ruled shape.
func _bend(v: float) -> float:
	var d: float = (v - _sal_v) / _sal_w
	var g: float = _slope * v + _sal_a * exp(-d * d)
	match _style:
		WINDING:
			g += 80.0 * _front_n.get_noise_1d(v) + 12.0 * _front_n.get_noise_1d(v * 4.0 + 1000.0)
		JAGGED:
			g += 50.0 * _front_n.get_noise_1d(v) + 26.0 * _front_n.get_noise_1d(v * 5.0 + 1000.0) + 9.0 * _front_n.get_noise_1d(v * 16.0 + 3000.0)
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
	_style = WINDING if roll < 0.45 else (JAGGED if roll < 0.75 else SURVEYED)
	_slope = _r(rng, -0.3, 0.3)
	_sal_v = _r(rng, -220, 220)
	_sal_a = 0.0 if rng.randf() < 0.35 else _r(rng, 60, 170) * (1.0 if rng.randf() < 0.5 else -1.0)
	_sal_w = _r(rng, 45, 120)
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
				var e: int = -1
				if _land(px, py) > LAND and not _river(px, py):
					var sv: int = 0 if _across(px, py) < _fx else 1
					e = _nearest(seeds, px, py, 0 if sv == 0 else n0, n0 if sv == 0 else n0 + n1)
				if e != v and _around(reg, cx, cy, e):
					v = e
			if v < 0:
				ids[o + fx] = NONE
			else:
				var s: int = 0 if v < n0 else 1
				ids[o + fx] = city[s] if Vector2(px, py).distance_squared_to(capital[s]) < cr2 else v

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

static func _chamfer_passes(e: PackedFloat32Array) -> PackedFloat32Array:
	const D: float = 1.4142
	for y: int in range(1, H - 1):
		var i: int = y * W + 1
		var end: int = y * W + W - 1
		var left: float = e[i - 1]
		var up_left: float = e[i - W - 1]
		var up: float = e[i - W]
		while i < end:
			var up_right: float = e[i - W + 1]
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
	for y: int in range(H - 2, 0, -1):
		var i: int = y * W + W - 2
		var end: int = y * W
		var right: float = e[i + 1]
		var down_right: float = e[i + W + 1]
		var down: float = e[i + W]
		while i > end:
			var down_left: float = e[i + W - 1]
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
