class_name LiteMap
extends RefCounted
## The map of the lite game: two countries side by side, ours in the west and
## the enemy's, as big or bigger, in the east up to the edge of the map. Each
## is a jagged polygon bent by noise and cut into regions of about the same
## size. Everything comes from the seed.
## Region ids are rasterised at twice the map's resolution (the shader draws
## the fills and borders from them); a one-unit grid keeps each unit's region
## and its distance to the nearest region border, which places labels and
## spots.
##
## GDScript port note: the grid loops are written for speed (no threads on the
## web): the noise is evaluated per lattice row instead of per point, the
## polygon test only looks at the edges crossing the point's row, and the
## nearest region seed is looked up among the few seeds that can be nearest in
## a coarse cell. Each of these gives the same answer as the plain loop.

const W: int = 980
const H: int = 720
const S: int = 2
const RW: int = W * S
const RH: int = H * S
const NONE: int = 255
const CITY_R: float = 15.0

var seed: int = 0
## RW * RH region ids (NONE for sea).
var ids: PackedByteArray = PackedByteArray()
## W * H region ids, one per map unit.
var cell: PackedByteArray = PackedByteArray()
## W * H distances to the nearest region border or coast.
var edge: PackedFloat32Array = PackedFloat32Array()
var regions: Array[LiteRegion] = []
var capital: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
var capital_name: PackedStringArray = PackedStringArray(["", ""])

var _fx: float = 0.0
var _bend: float = 0.0
var _sal_y: float = 0.0
var _sal_a: float = 0.0
var _sal_w: float = 0.0
var _c0: Vector2 = Vector2.ZERO
var _c1: Vector2 = Vector2.ZERO
var _ns: int = 0
## The warp and the region bend on the corners of the map units; points
## between them are interpolated. (W + 1) * (H + 1) each.
var _warp: PackedVector2Array = PackedVector2Array()
var _bend_grid: PackedVector2Array = PackedVector2Array()
## Each country's outline, and bays cut out of the coast (centre, radii).
var _poly0: PackedVector2Array = PackedVector2Array()
var _poly1: PackedVector2Array = PackedVector2Array()
var _bays_c: PackedVector2Array = PackedVector2Array()
var _bays_r: PackedVector2Array = PackedVector2Array()

# Port-only speed-ups (see the class note).
## Polygon edges (ax, ay, bx, by) listed per map row they cross; _row_start
## holds, for polygon 0 then polygon 1, H + 1 offsets (in edges) into _row_edges.
var _row_edges: PackedFloat32Array = PackedFloat32Array()
var _row_start: PackedInt32Array = PackedInt32Array()
## The frontier noise sampled along its fixed x: per octave, values on lattice rows.
const _FR_LO: int = -64
const _FR_N: int = 192
var _fr_rows: PackedFloat64Array = PackedFloat64Array()
## Bounds of the frontier's x over each map row.
var _fr_lo: PackedFloat32Array = PackedFloat32Array()
var _fr_hi: PackedFloat32Array = PackedFloat32Array()
## Coarse cells of _MC units, 2 bits a polygon: wholly outside, wholly inside, or near an edge.
const _MC: float = 4.0
const _MW: int = 245
const _MH: int = 180
var _mask: PackedByteArray = PackedByteArray()
## Cells of _GC units over warped region space (from _G0, _GW by _GH, once
## for each side), each with the seeds that can be nearest in it, filled in
## when first needed: _g_count -1 until then.
const _G0: float = -64.0
const _GC: float = 8.0
const _GW: int = 140
const _GH: int = 108
var _g_start: PackedInt32Array = PackedInt32Array()
var _g_count: PackedInt32Array = PackedInt32Array()
var _g_list: PackedInt32Array = PackedInt32Array()
var _g_seeds: PackedVector2Array = PackedVector2Array()
var _g_n0: int = 0
var _g_n1: int = 0

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
	var m := LiteMap.new(p_seed)
	m._build()
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
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_ns = rng.randi_range(1, (1 << 20) - 1)
	# The frontier runs north to south somewhere left of the middle, so the
	# enemy is about as big as we are or bigger.
	_fx = _r(rng, 470, 570)
	_bend = _r(rng, -70, 90)
	_sal_y = _r(rng, 180, 560)
	_sal_a = _r(rng, -75, 75)
	_sal_w = _r(rng, 50, 110)
	var cy: float = 362 + _r(rng, -14, 14)
	var c0x: float = _fx * 0.5 + _r(rng, 0, 30)
	_c0 = Vector2(c0x, cy + _r(rng, -8, 16))
	var west0: float = _c0.x - _r(rng, 18, 40)
	var east0: float = _fx - _c0.x + _r(rng, 140, 190)
	var north0: float = _r(rng, 215, 262)
	var south0: float = _r(rng, 212, 268)
	var n0v: int = 15 + rng.randi_range(0, 5)
	_poly0 = _polygon(rng, _c0, west0, east0, north0, south0, n0v)
	_c1 = Vector2(_fx + (W - _fx) * 0.42, cy + _r(rng, -22, 8))
	var west1: float = _c1.x - _fx + _r(rng, 150, 210)
	var east1: float = W - 16 - _c1.x
	var north1: float = _c1.y - _r(rng, 22, 70)
	var south1: float = H - _c1.y - _r(rng, 22, 80)
	var n1v: int = 14 + rng.randi_range(0, 5)
	_poly1 = _polygon(rng, _c1, west1, east1, north1, south1, n1v)
	# A sea on our south coast now and then, and a bay or two elsewhere.
	if rng.randf() < 0.6:
		var sea_c := Vector2(_c0.x + _r(rng, -60, 140), H + _r(rng, 30, 70))
		var sea_r := Vector2(_r(rng, 150, 230), _r(rng, 110, 150))
		_bays_c.append(sea_c)
		_bays_r.append(sea_r)
	var nb: int = rng.randi_range(0, 2)
	for i: int in nb:
		var own: PackedVector2Array = _poly0 if i % 2 == 0 else _poly1
		var c: Vector2 = own[rng.randi_range(0, own.size() - 1)]
		# Only on the outer coast: not by the frontier, not inside the other country.
		if absf(c.x - _fx) < 140 or _inside(_poly1 if i % 2 == 0 else _poly0, c):
			continue
		_bays_c.append(c)
		_bays_r.append(Vector2(_r(rng, 35, 70), _r(rng, 30, 60)))
	_prepare_side_of()

	_build_grids()

	# 1. Land and country per map unit; islands are dropped.
	var side := PackedInt32Array()
	side.resize(W * H)
	var warp: PackedVector2Array = _warp
	var mask: PackedByteArray = _mask
	for y: int in H:
		var gi: int = y * (W + 1)
		var ui: int = y * W
		for x: int in W:
			# Warp(x + 0.5, y + 0.5): halfway between the four corners.
			var w: Vector2 = warp[gi].lerp(warp[gi + 1], 0.5).lerp(warp[gi + W + 1].lerp(warp[gi + W + 2], 0.5), 0.5)
			# Deep inside one country or out at sea, the coarse cell answers.
			var mx: int = floori(w.x / _MC)
			var my: int = floori(w.y / _MC)
			var st: int = mask[my * _MW + mx] if mx >= 0 and mx < _MW and my >= 0 and my < _MH else 26
			if st == 1:
				side[ui] = 0
			elif st == 4:
				side[ui] = 1
			elif st == 0:
				side[ui] = -1
			else:
				side[ui] = _side_of(w.x, w.y)
			gi += 1
			ui += 1
	side = _keep_mainland(side)

	# 2. Region seeds: each capital first, then spread out over its country,
	# one region per about the same area on both sides.
	# The two capitals stand equally far from the other country, so neither
	# side starts with its capital closer to the enemy.
	var to_enemy: Array[PackedFloat32Array] = [
		_chamfer(side, func(v: int) -> bool: return v == 1),
		_chamfer(side, func(v: int) -> bool: return v == 0),
	]
	var to_sea: PackedFloat32Array = _chamfer(side, func(v: int) -> bool: return v < 0)
	var room: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
	var te0: PackedFloat32Array = to_enemy[0]
	var te1: PackedFloat32Array = to_enemy[1]
	for i: int in W * H:
		var sv: int = side[i]
		if sv >= 0 and to_sea[i] >= 32:
			room[sv] = maxf(room[sv], te0[i] if sv == 0 else te1[i])
	var reach: float = minf(minf(room[0], room[1]), 280.0) * 0.85
	var want0 := _c0 + Vector2(_r(rng, -10, 70), -_r(rng, 55, 110))
	capital[0] = _place(side, 0, te0, to_sea, reach, want0)
	var want1x: float = _c1.x + _r(rng, 50, 120)
	var want1 := Vector2(want1x, _c1.y + _r(rng, -110, 30))
	capital[1] = _place(side, 1, te1, to_sea, reach, want1)
	var area: PackedInt32Array = PackedInt32Array([0, 0])
	for v: int in side:
		if v >= 0:
			area[v] += 1
	var per: float = area[0] / 15.0
	var seeds0: Array[Vector2] = [capital[0]]
	var seeds1: Array[Vector2] = [capital[1]]
	var seeds: Array[Array] = [seeds0, seeds1]
	for s: int in 2:
		var want: int = 15 if s == 0 else clampi(roundi(area[1] / per), 8, 22)
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
			var p := Vector2(x, y)
			var ok: bool = true
			for list: Array in seeds:
				for q: Vector2 in list:
					if q.distance_to(p) < dmin:
						ok = false
						break
			if ok:
				mine.append(p)
	var n0: int = seeds0.size()
	var n1: int = seeds1.size()
	var city: PackedInt32Array = PackedInt32Array([n0 + n1, n0 + n1 + 1])
	var warped := PackedVector2Array()
	for list: Array in seeds:
		for p: Vector2 in list:
			warped.append(_region_pos(p.x, p.y, _warp_point(p.x, p.y)))
	var cap_w0: Vector2 = warped[0]
	var cap_w1: Vector2 = warped[n0]

	# 3. The id raster: nearest seed of the pixel's own country, in warped space.
	_raster(side, warped, n0, n1, city, cap_w0, cap_w1)
	var cell_l := PackedByteArray()
	cell_l.resize(W * H)
	for y: int in H:
		var ro: int = (y * S + 1) * RW + 1
		var co: int = y * W
		for x: int in W:
			cell_l[co + x] = ids[ro + x * S]
	cell = cell_l
	_compute_edge()

	# 4. Regions: names, label points, spots, neighbours.
	var ours: Array[String] = _shuffled(OUR_NAMES, rng)
	var theirs: Array[String] = _shuffled(ENEMY_NAMES, rng)
	capital_name[0] = OUR_CAPITALS[rng.randi_range(0, OUR_CAPITALS.size() - 1)]
	capital_name[1] = ENEMY_CAPITALS[rng.randi_range(0, ENEMY_CAPITALS.size() - 1)]
	var total: int = n0 + n1 + 2
	for i: int in total:
		var r := LiteRegion.new()
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
	var sum := PackedVector2Array()
	sum.resize(total)
	var best := PackedFloat32Array()
	best.resize(total)
	var spots: Array[Array] = []
	var areas := PackedInt32Array()
	areas.resize(total)
	for i: int in total:
		best[i] = -3.4028235e38
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
	# Hoisted out of the loop below: each region's centre and its capital.
	var centers := PackedVector2Array()
	var caps := PackedVector2Array()
	for r: LiteRegion in regions:
		centers.append(r.center)
		caps.append(capital[r.side])
	var labels := PackedVector2Array()
	labels.resize(total)
	for y: int in H:
		for x: int in W:
			var i: int = y * W + x
			var id: int = cl[i]
			if id == NONE:
				continue
			var p := Vector2(x + 0.5, y + 0.5)
			var score: float = minf(ed[i], 40) - 0.06 * p.distance_to(centers[id])
			# Keep clear of the capital's own name.
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


## The warp and the region bend on every unit corner. Was a Parallel.For over
## WarpAt(x, y) and Vector2(Fbm(x * 0.011, y * 0.011, _ns + 5), Fbm(.., _ns + 6)) * 22:
##   WarpAt(x, y) = (x + 40 * n1 + 24 * m1 + 13 * d1 + 4.5 * f1, y + 40 * n2 + ...)
## with n1, n2 = Fbm(x * 0.0045, y * 0.0045, _ns + 1 / _ns + 2), m at 0.01
## (_ns + 8, + 9), d at 0.024 (+ 3, + 4) and f at 0.06 (+ 10, + 11).
## Value noise is bilinear in the smoothed fractions, so each octave of each
## pair is first interpolated along x on every lattice row it needs (`av`,
## times its weight in the sum, with the step to the next row in `dv`); a
## corner then only blends between the two rows round it.
func _build_grids() -> void:
	const GW: int = W + 1
	const GH: int = H + 1
	# Scale, the two seeds and the weight of each pair; bend last.
	var pairs: Array[Array] = [
		[0.0045, _ns + 1, _ns + 2, 40.0],
		[0.01, _ns + 8, _ns + 9, 24.0],
		[0.024, _ns + 3, _ns + 4, 13.0],
		[0.06, _ns + 10, _ns + 11, 4.5],
		[0.011, _ns + 5, _ns + 6, 22.0],
	]
	var av := PackedVector2Array()
	var dv := PackedVector2Array()
	# Per term (pair and octave) and corner row: where its row starts in av, and the blend.
	var rof := PackedInt32Array()
	rof.resize(15 * GH)
	var rt := PackedFloat64Array()
	rt.resize(15 * GH)
	var xi := PackedInt32Array()
	xi.resize(GW)
	var sx := PackedFloat64Array()
	sx.resize(GW)
	var yi := PackedInt32Array()
	yi.resize(GH)
	for p: int in 5:
		var k: float = pairs[p][0]
		var s1: int = pairs[p][1]
		var s2: int = pairs[p][2]
		var weight: float = pairs[p][3]
		# As Fbm: three octaves, each half as strong and 2.03 times as fine.
		var amp: float = 0.5
		var norm: float = 0.5 + 0.25 + 0.125
		var f: float = 1.0
		for o: int in 3:
			var term: int = p * 3 + o
			var so1: int = s1 + o * 101
			var so2: int = s2 + o * 101
			var wgt: float = weight * amp / norm
			for x: int in GW:
				var u: float = (x * k) * f
				var i: int = floori(u)
				var t: float = u - i
				xi[x] = i
				sx[x] = t * t * (3 - 2 * t)
			for y: int in GH:
				var u: float = (y * k) * f
				var i: int = floori(u)
				var t: float = u - i
				yi[y] = i
				rt[term * GH + y] = t * t * (3 - 2 * t)
			var x0: int = xi[0]
			var y0: int = yi[0]
			var nx: int = xi[GW - 1] - x0 + 2
			var ny: int = yi[GH - 1] - y0 + 2
			var base: int = av.size()
			for y: int in GH:
				rof[term * GH + y] = base + (yi[y] - y0) * GW
			var h1 := PackedFloat64Array()
			h1.resize(nx * ny)
			var h2 := PackedFloat64Array()
			h2.resize(nx * ny)
			for j: int in ny:
				for i: int in nx:
					h1[j * nx + i] = _hash(x0 + i, y0 + j, so1)
					h2[j * nx + i] = _hash(x0 + i, y0 + j, so2)
			av.resize(base + ny * GW)
			dv.resize(base + ny * GW)
			for j: int in ny:
				for x: int in GW:
					var b: int = j * nx + xi[x] - x0
					var t: float = sx[x]
					var a1: float = h1[b] + (h1[b + 1] - h1[b]) * t
					var a2: float = h2[b] + (h2[b + 1] - h2[b]) * t
					av[base + j * GW + x] = Vector2(a1, a2) * wgt
			for i: int in (ny - 1) * GW:
				dv[base + i] = av[base + i + GW] - av[base + i]
			amp *= 0.5
			f *= 2.03
	var warp := PackedVector2Array()
	warp.resize(GW * GH)
	var bend := PackedVector2Array()
	bend.resize(GW * GH)
	for y: int in GH:
		var o0: int = rof[0 * GH + y]
		var t0: float = rt[0 * GH + y]
		var o1: int = rof[1 * GH + y]
		var t1: float = rt[1 * GH + y]
		var o2: int = rof[2 * GH + y]
		var t2: float = rt[2 * GH + y]
		var o3: int = rof[3 * GH + y]
		var t3: float = rt[3 * GH + y]
		var o4: int = rof[4 * GH + y]
		var t4: float = rt[4 * GH + y]
		var o5: int = rof[5 * GH + y]
		var t5: float = rt[5 * GH + y]
		var o6: int = rof[6 * GH + y]
		var t6: float = rt[6 * GH + y]
		var o7: int = rof[7 * GH + y]
		var t7: float = rt[7 * GH + y]
		var o8: int = rof[8 * GH + y]
		var t8: float = rt[8 * GH + y]
		var o9: int = rof[9 * GH + y]
		var t9: float = rt[9 * GH + y]
		var o10: int = rof[10 * GH + y]
		var t10: float = rt[10 * GH + y]
		var o11: int = rof[11 * GH + y]
		var t11: float = rt[11 * GH + y]
		var o12: int = rof[12 * GH + y]
		var t12: float = rt[12 * GH + y]
		var o13: int = rof[13 * GH + y]
		var t13: float = rt[13 * GH + y]
		var o14: int = rof[14 * GH + y]
		var t14: float = rt[14 * GH + y]
		var gi: int = y * GW
		for x: int in GW:
			warp[gi + x] = (Vector2(x, y)
				+ av[o0 + x] + dv[o0 + x] * t0
				+ av[o1 + x] + dv[o1 + x] * t1
				+ av[o2 + x] + dv[o2 + x] * t2
				+ av[o3 + x] + dv[o3 + x] * t3
				+ av[o4 + x] + dv[o4 + x] * t4
				+ av[o5 + x] + dv[o5 + x] * t5
				+ av[o6 + x] + dv[o6 + x] * t6
				+ av[o7 + x] + dv[o7 + x] * t7
				+ av[o8 + x] + dv[o8 + x] * t8
				+ av[o9 + x] + dv[o9 + x] * t9
				+ av[o10 + x] + dv[o10 + x] * t10
				+ av[o11 + x] + dv[o11 + x] * t11)
			bend[gi + x] = (av[o12 + x] + dv[o12 + x] * t12
				+ av[o13 + x] + dv[o13 + x] * t13
				+ av[o14 + x] + dv[o14 + x] * t14)
	_warp = warp
	_bend_grid = bend


## The coastline and the frontier are drawn in coordinates bent by noise,
## so they wander like real borders.
func _warp_point(x: float, y: float) -> Vector2:
	return _lerp(_warp, x, y)


static func _lerp(grid: PackedVector2Array, x: float, y: float) -> Vector2:
	x = clampf(x, 0, W - 0.001)
	y = clampf(y, 0, H - 0.001)
	var xi: int = int(x)
	var yi: int = int(y)
	var i: int = yi * (W + 1) + xi
	var fx: float = x - xi
	var fy: float = y - yi
	var top: Vector2 = grid[i].lerp(grid[i + 1], fx)
	var bottom: Vector2 = grid[i + W + 1].lerp(grid[i + W + 2], fx)
	return top.lerp(bottom, fy)


## Region borders get one more bend of their own, like borders along rivers.
func _region_pos(x: float, y: float, w: Vector2) -> Vector2:
	return w + _lerp(_bend_grid, x, y)


## Lists each polygon's edges by the map rows they cross, marks the coarse
## cells no edge comes near as wholly inside or outside each polygon, and
## samples the frontier noise along its column, for _side_of.
func _prepare_side_of() -> void:
	_row_edges = PackedFloat32Array()
	_row_start = PackedInt32Array()
	_row_start.resize(2 * (H + 1))
	var ne: int = 0
	for pi: int in 2:
		var poly: PackedVector2Array = _poly0 if pi == 0 else _poly1
		var n: int = poly.size()
		for row: int in H:
			_row_start[pi * (H + 1) + row] = ne
			var j: int = n - 1
			for i: int in n:
				var a: Vector2 = poly[i]
				var b: Vector2 = poly[j]
				# An edge counts for p when min(a.y, b.y) <= p.y < max(a.y, b.y).
				if minf(a.y, b.y) < row + 1 and maxf(a.y, b.y) > row:
					_row_edges.append(a.x)
					_row_edges.append(a.y)
					_row_edges.append(b.x)
					_row_edges.append(b.y)
					ne += 1
				j = i
		_row_start[pi * (H + 1) + H] = ne
	# Coarse cells: 2 bits a polygon (0 outside, 1 inside, 2 an edge comes
	# near), and 16 when a bay comes near.
	_mask = PackedByteArray()
	_mask.resize(_MW * _MH)
	for pi: int in 2:
		var poly: PackedVector2Array = _poly0 if pi == 0 else _poly1
		var near := PackedByteArray()
		near.resize(_MW * _MH)
		var j: int = poly.size() - 1
		for i: int in poly.size():
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[j]
			# Every point of the edge is within half a unit of a sample, and a
			# sample marks the cells round its own, _MC units each way.
			var steps: int = ceili(a.distance_to(b)) + 1
			for t: int in steps + 1:
				var p: Vector2 = a.lerp(b, float(t) / steps)
				var cx: int = floori(p.x / _MC)
				var cy: int = floori(p.y / _MC)
				for yy: int in range(maxi(cy - 1, 0), mini(cy + 2, _MH)):
					for xx: int in range(maxi(cx - 1, 0), mini(cx + 2, _MW)):
						near[yy * _MW + xx] = 1
			j = i
		for cy: int in _MH:
			for cx: int in _MW:
				var k: int = cy * _MW + cx
				var st: int = 2
				if near[k] == 0:
					st = 1 if _inside_rows(pi, (cx + 0.5) * _MC, (cy + 0.5) * _MC) else 0
				_mask[k] |= st << (pi * 2)
	for cy: int in _MH:
		for cx: int in _MW:
			var lo := Vector2(cx * _MC, cy * _MC)
			var hi := lo + Vector2(_MC, _MC)
			for b: int in _bays_c.size():
				var c: Vector2 = _bays_c[b]
				var r: Vector2 = _bays_r[b]
				# The cell's point nearest the bay's centre, measured in the bay's radii.
				var qx: float = (clampf(c.x, lo.x, hi.x) - c.x) / r.x
				var qy: float = (clampf(c.y, lo.y, hi.y) - c.y) / r.y
				if qx * qx + qy * qy < 1.01:
					_mask[cy * _MW + cx] |= 16
	_fr_rows = PackedFloat64Array()
	_fr_rows.resize(3 * _FR_N)
	var f: float = 1.0
	for o: int in 3:
		var u: float = 5.3 * f
		var xi: int = floori(u)
		var t: float = u - xi
		t = t * t * (3 - 2 * t)
		var s: int = _ns + 7 + o * 101
		for j: int in _FR_N:
			var a: float = _hash(xi, _FR_LO + j, s)
			_fr_rows[o * _FR_N + j] = a + (_hash(xi + 1, _FR_LO + j, s) - a) * t
		f *= 2.03
	# Bounds of the frontier over each map row: it moves less than 4 units a
	# unit of y (bend 0.33, noise 2.2, salient 1.3), so 4 more is safe.
	_fr_lo = PackedFloat32Array()
	_fr_lo.resize(H)
	_fr_hi = PackedFloat32Array()
	_fr_hi.resize(H)
	var prev: float = _frontier(0.0)
	for row: int in H:
		var next: float = _frontier(row + 1.0)
		_fr_lo[row] = minf(prev, next) - 4.0
		_fr_hi[row] = maxf(prev, next) + 4.0
		prev = next


## Inside(poly, p) for polygon `pi`, over the edges crossing p's row only.
func _inside_rows(pi: int, wx: float, wy: float) -> bool:
	var inside: bool = false
	var row: int = floori(wy)
	if row < 0 or row >= H:
		return false
	var e: PackedFloat32Array = _row_edges
	var k: int = _row_start[pi * (H + 1) + row]
	var k1: int = _row_start[pi * (H + 1) + row + 1]
	while k < k1:
		var o: int = k * 4
		var ay: float = e[o + 1]
		var by: float = e[o + 3]
		if (ay > wy) != (by > wy) and wx < (e[o + 2] - e[o]) * (wy - ay) / (by - ay) + e[o]:
			inside = not inside
		k += 1
	return inside


## -1 sea, 0 ours, 1 the enemy's. West of the frontier a point is ours if
## it is inside our outline; the enemy's outline reaching round our coast
## past the frontier is the enemy's, and the other way round.
func _side_of(wx: float, wy: float) -> int:
	# Bays first, unless the coarse cell says none comes near.
	var mx: int = floori(wx / _MC)
	var my: int = floori(wy / _MC)
	var st: int = 26
	if mx >= 0 and mx < _MW and my >= 0 and my < _MH:
		st = _mask[my * _MW + mx]
	if (st & 16) != 0:
		for b: int in _bays_c.size():
			var c: Vector2 = _bays_c[b]
			var r: Vector2 = _bays_r[b]
			var qx: float = (wx - c.x) / r.x
			var qy: float = (wy - c.y) / r.y
			if qx * qx + qy * qy < 1.0:
				return -1
	# Inside(_poly0, w) and Inside(_poly1, w): from the coarse cell unless an
	# edge comes near it.
	var in0: bool = (st & 3) == 1
	if (st & 3) == 2:
		in0 = _inside_rows(0, wx, wy)
	var in1: bool = ((st >> 2) & 3) == 1
	if ((st >> 2) & 3) == 2:
		in1 = _inside_rows(1, wx, wy)
	if not in0 and not in1:
		return -1
	if in0 != in1:
		return 0 if in0 else 1
	# Both outlines: the frontier decides; far from it, its row bounds do.
	var row: int = floori(wy)
	if row >= 0 and row < H:
		if wx < _fr_lo[row]:
			return 0
		if wx >= _fr_hi[row]:
			return 1
	return 0 if wx < _frontier(wy) else 1


func _frontier(y: float) -> float:
	var d: float = (y - _sal_y) / _sal_w
	return _fx - _bend * (_smooth((y - 160.0) / 420.0) - 0.5) + 46.0 * _frontier_fbm(y) \
		- _sal_a * exp(-d * d)


## Fbm(5.3, y * 0.009, _ns + 7), from the rows sampled in _prepare_side_of.
func _frontier_fbm(y: float) -> float:
	var sum: float = 0.0
	var amp: float = 0.5
	var norm: float = 0.0
	var f: float = 1.0
	for o: int in 3:
		var u: float = (y * 0.009) * f
		var yi: int = floori(u)
		var j: int = yi - _FR_LO
		var v: float
		if j >= 0 and j + 1 < _FR_N:
			var t: float = u - yi
			t = t * t * (3 - 2 * t)
			var a: float = _fr_rows[o * _FR_N + j]
			v = a + (_fr_rows[o * _FR_N + j + 1] - a) * t
		else:
			v = _value(5.3 * f, u, _ns + 7 + o * 101)
		sum += amp * v
		norm += amp
		amp *= 0.5
		f *= 2.03
	return sum / norm


## Step 3 of _build: fills `ids`. A unit's four pixels share its warp and bend
## corners and its neighbourhood in `side`. Their warped points lie in the box
## of the warped corners, so when that box settles the side, the city disc or
## the nearest seed for all of them, it is not worked out four times.
func _raster(side: PackedInt32Array, warped: PackedVector2Array, n0: int, n1: int,
		city: PackedInt32Array, cap_w0: Vector2, cap_w1: Vector2) -> void:
	const GW: int = W + 1
	const CITY_R2: float = CITY_R * CITY_R
	const GCELLS: int = _GW * _GH
	# Slack round the corner boxes for float rounding in the blends.
	const PAD := Vector2(0.01, 0.01)
	var ids_l := PackedByteArray()
	ids_l.resize(RW * RH)
	var warp: PackedVector2Array = _warp
	var bend: PackedVector2Array = _bend_grid
	_g_seeds = warped
	_g_n0 = n0
	_g_n1 = n1
	_g_start = PackedInt32Array()
	_g_start.resize(2 * GCELLS)
	_g_count = PackedInt32Array()
	_g_count.resize(2 * GCELLS)
	_g_count.fill(-1)
	_g_list = PackedInt32Array()
	var city0: int = city[0]
	var city1: int = city[1]
	var wt: Vector2
	var wb: Vector2
	var bt: Vector2
	var bb: Vector2
	for uy: int in H:
		for ux: int in W:
			var ui: int = uy * W + ux
			var sc: int = side[ui]
			var sl: int = side[ui - 1] if ux > 0 else -2
			var sr: int = side[ui + 1] if ux + 1 < W else -2
			var su: int = side[ui - W] if uy > 0 else -2
			var sd: int = side[ui + W] if uy + 1 < H else -2
			var p0: int = uy * S * RW + ux * S
			if sc < 0 and sl < 0 and sr < 0 and su < 0 and sd < 0:
				# Nothing near: no country can claim any of the four pixels.
				ids_l[p0] = NONE
				ids_l[p0 + 1] = NONE
				ids_l[p0 + RW] = NONE
				ids_l[p0 + RW + 1] = NONE
				continue
			var gi: int = uy * GW + ux
			var w00: Vector2 = warp[gi]
			var w10: Vector2 = warp[gi + 1]
			var w01: Vector2 = warp[gi + GW]
			var w11: Vector2 = warp[gi + GW + 1]
			var b00: Vector2 = bend[gi]
			var b10: Vector2 = bend[gi + 1]
			var b01: Vector2 = bend[gi + GW]
			var b11: Vector2 = bend[gi + GW + 1]
			# The side of all four pixels at once, when the box settles it (-3 if not).
			var us: int = _box_side(w00.min(w10).min(w01.min(w11)) - PAD, w00.max(w10).max(w01.max(w11)) + PAD)
			if us == -1 or (us >= 0 and sc != us and sl != us and sr != us and su != us and sd != us):
				ids_l[p0] = NONE
				ids_l[p0 + 1] = NONE
				ids_l[p0 + RW] = NONE
				ids_l[p0 + RW + 1] = NONE
				continue
			# 1 when no pixel can be in the city disc, 2 when all are, 0 not known.
			var in_city: int = 0
			if us >= 0:
				var q00: Vector2 = w00 + b00
				var q10: Vector2 = w10 + b10
				var q01: Vector2 = w01 + b01
				var q11: Vector2 = w11 + b11
				var qlo: Vector2 = q00.min(q10).min(q01.min(q11)) - PAD
				var qhi: Vector2 = q00.max(q10).max(q01.max(q11)) + PAD
				var cap: Vector2 = cap_w0 if us == 0 else cap_w1
				if cap.clamp(qlo, qhi).distance_squared_to(cap) >= CITY_R2:
					in_city = 1
					var gx0: int = floori((qlo.x - _G0) / _GC)
					var gy0: int = floori((qlo.y - _G0) / _GC)
					var gx1: int = floori((qhi.x - _G0) / _GC)
					var gy1: int = floori((qhi.y - _G0) / _GC)
					if gx0 >= 0 and gy0 >= 0 and gx1 < _GW and gy1 < _GH:
						var gc: int = us * GCELLS + gy0 * _GW + gx0
						var only: int = _cell_only(gc)
						if only >= 0 and gx1 != gx0 and _cell_only(gc + 1) != only:
							only = -1
						if only >= 0 and gy1 != gy0 and _cell_only(gc + _GW) != only:
							only = -1
						if only >= 0 and gx1 != gx0 and gy1 != gy0 and _cell_only(gc + _GW + 1) != only:
							only = -1
						if only >= 0:
							# One seed is nearest everywhere in the box.
							ids_l[p0] = only
							ids_l[p0 + 1] = only
							ids_l[p0 + RW] = only
							ids_l[p0 + RW + 1] = only
							continue
				else:
					var far := Vector2(maxf(absf(qlo.x - cap.x), absf(qhi.x - cap.x)), maxf(absf(qlo.y - cap.y), absf(qhi.y - cap.y)))
					if far.length_squared() < CITY_R2:
						var cid: int = city0 if us == 0 else city1
						ids_l[p0] = cid
						ids_l[p0 + 1] = cid
						ids_l[p0 + RW] = cid
						ids_l[p0 + RW + 1] = cid
						continue
			for k: int in 4:
				var dx: int = k >> 1
				var dy: int = k & 1
				var fy: float = 0.25 + 0.5 * dy
				if dy == 0:
					# The top and bottom rows of the bilinear blend, once per column.
					var fx: float = 0.25 + 0.5 * dx
					wt = w00.lerp(w10, fx)
					wb = w01.lerp(w11, fx)
					bt = b00.lerp(b10, fx)
					bb = b01.lerp(b11, fx)
				var pi: int = p0 + dy * RW + dx
				var w: Vector2 = wt.lerp(wb, fy)
				var s: int = us
				if s == -3:
					s = _side_of(w.x, w.y)
					# Near(side, x, y, s)
					if s < 0 or (sc != s and sl != s and sr != s and su != s and sd != s):
						ids_l[pi] = NONE
						continue
				var q: Vector2 = w + bt.lerp(bb, fy)
				if in_city != 1 and q.distance_squared_to(cap_w0 if s == 0 else cap_w1) < CITY_R2:
					ids_l[pi] = city0 if s == 0 else city1
					continue
				var from: int = 0 if s == 0 else n0
				var bi: int = from
				var bd: float = 3.4028235e38
				var gx: int = floori((q.x - _G0) / _GC)
				var gy: int = floori((q.y - _G0) / _GC)
				if gx >= 0 and gx < _GW and gy >= 0 and gy < _GH:
					var gc: int = s * GCELLS + gy * _GW + gx
					if _g_count[gc] < 0:
						_fill_cell(gc)
					var t: int = _g_start[gc]
					var t1: int = t + _g_count[gc]
					while t < t1:
						var i: int = _g_list[t]
						var d: float = q.distance_squared_to(warped[i])
						if d < bd:
							bd = d
							bi = i
						t += 1
				else:
					var to: int = n0 if s == 0 else n0 + n1
					for i: int in range(from, to):
						var d: float = q.distance_squared_to(warped[i])
						if d < bd:
							bd = d
							bi = i
				ids_l[pi] = bi
	ids = ids_l


## _side_of for every warped point in the box lo..hi, or -3 when the box does
## not settle it (a bay, an outline or the frontier may run through it).
func _box_side(lo: Vector2, hi: Vector2) -> int:
	var mx0: int = floori(lo.x / _MC)
	var my0: int = floori(lo.y / _MC)
	var mx1: int = floori(hi.x / _MC)
	var my1: int = floori(hi.y / _MC)
	if mx0 < 0 or my0 < 0 or mx1 >= _MW or my1 >= _MH or mx1 - mx0 > 1 or my1 - my0 > 1:
		return -3
	var st: int = _mask[my0 * _MW + mx0]
	# Bits 1 and 3: an edge comes near the cell.
	if (st & 10) != 0:
		return -3
	if _mask[my0 * _MW + mx1] != st or _mask[my1 * _MW + mx0] != st or _mask[my1 * _MW + mx1] != st:
		return -3
	if (st & 16) != 0:
		for b: int in _bays_c.size():
			var c: Vector2 = _bays_c[b]
			var r: Vector2 = _bays_r[b]
			# The box's point nearest the bay's centre, measured in the bay's radii.
			var qx: float = (clampf(c.x, lo.x, hi.x) - c.x) / r.x
			var qy: float = (clampf(c.y, lo.y, hi.y) - c.y) / r.y
			if qx * qx + qy * qy < 1.0:
				return -3
	var in0: bool = (st & 3) == 1
	var in1: bool = ((st >> 2) & 3) == 1
	if in0 != in1:
		return 0 if in0 else 1
	if not in0:
		return -1
	var r0: int = floori(lo.y)
	var r1: int = floori(hi.y)
	if r0 < 0 or r1 >= H:
		return -3
	var flo: float = _fr_lo[r0]
	var fhi: float = _fr_hi[r0]
	for row: int in range(r0 + 1, r1 + 1):
		flo = minf(flo, _fr_lo[row])
		fhi = maxf(fhi, _fr_hi[row])
	if hi.x < flo:
		return 0
	if lo.x >= fhi:
		return 1
	return -3


## The one seed that can be nearest in cell `gc`, or -1 if more can.
func _cell_only(gc: int) -> int:
	if _g_count[gc] < 0:
		_fill_cell(gc)
	return _g_list[_g_start[gc]] if _g_count[gc] == 1 else -1


## Lists, in index order, the seeds of the cell's side that can be the nearest
## to some point of the cell. A seed is left out when it is farther than some
## seed's farthest point of the cell, or when the seed nearest the cell's
## centre is nearer at all four corners (the difference of the two squared
## distances is linear, so it is then nearer all over the cell).
func _fill_cell(gc: int) -> void:
	const GCELLS: int = _GW * _GH
	var s: int = gc / GCELLS
	var gy: int = (gc % GCELLS) / _GW
	var gx: int = gc % _GW
	var from: int = 0 if s == 0 else _g_n0
	var to: int = _g_n0 if s == 0 else _g_n0 + _g_n1
	var x0: float = _G0 + gx * _GC
	var y0: float = _G0 + gy * _GC
	var x1: float = x0 + _GC
	var y1: float = y0 + _GC
	var mid := Vector2(x0 + _GC * 0.5, y0 + _GC * 0.5)
	var far_min: float = INF
	var ref: int = from
	var ref_d: float = INF
	for i: int in range(from, to):
		var p: Vector2 = _g_seeds[i]
		var fx: float = maxf(absf(p.x - x0), absf(p.x - x1))
		var fy: float = maxf(absf(p.y - y0), absf(p.y - y1))
		far_min = minf(far_min, fx * fx + fy * fy)
		var dm: float = p.distance_squared_to(mid)
		if dm < ref_d:
			ref_d = dm
			ref = i
	# A little slack for rounding.
	var limit: float = far_min * 1.0001 + 0.01
	var r: Vector2 = _g_seeds[ref]
	var c00 := Vector2(x0, y0)
	var c10 := Vector2(x1, y0)
	var c01 := Vector2(x0, y1)
	var c11 := Vector2(x1, y1)
	_g_start[gc] = _g_list.size()
	var n: int = 0
	for i: int in range(from, to):
		var p: Vector2 = _g_seeds[i]
		var dx: float = maxf(0.0, maxf(x0 - p.x, p.x - x1))
		var dy: float = maxf(0.0, maxf(y0 - p.y, p.y - y1))
		if dx * dx + dy * dy > limit:
			continue
		if i != ref and p.distance_squared_to(c00) - r.distance_squared_to(c00) > 0.05 \
				and p.distance_squared_to(c10) - r.distance_squared_to(c10) > 0.05 \
				and p.distance_squared_to(c01) - r.distance_squared_to(c01) > 0.05 \
				and p.distance_squared_to(c11) - r.distance_squared_to(c11) > 0.05:
			continue
		_g_list.append(i)
		n += 1
	_g_count[gc] = n


## A rough polygon round `c`: vertices at uneven angles on a squarish
## outline with its own radius to each side, each pushed in or out.
## (Returns the polygon instead of filling a list.)
static func _polygon(rng: RandomNumberGenerator, c: Vector2, west: float, east: float, north: float, south: float, n: int) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for i: int in n:
		var a: float = (i + _r(rng, -0.35, 0.35)) / n * TAU
		var cs: float = cos(a)
		var sn: float = sin(a)
		var rx: float = east if cs > 0 else west
		var ry: float = south if sn > 0 else north
		var k: float = 1.0 / pow(pow(absf(cs) / rx, 3) + pow(absf(sn) / ry, 3), 1.0 / 3.0)
		if rng.randf() < 0.18:
			k *= _r(rng, 0.66, 0.8)
		else:
			k *= _r(rng, 0.86, 1.06)
		var p: Vector2 = c + Vector2(cs, sn) * k
		poly.append(Vector2(clampf(p.x, 14, W - 14), clampf(p.y, 14, H - 14)))
	return poly


static func _inside(poly: PackedVector2Array, p: Vector2) -> bool:
	var inside: bool = false
	var j: int = poly.size() - 1
	for i: int in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[j]
		if (a.y > p.y) != (b.y > p.y) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
		j = i
	return inside


## (Returns `side` instead of changing it in place.)
static func _keep_mainland(side: PackedInt32Array) -> PackedInt32Array:
	var comp := PackedInt32Array()
	comp.resize(W * H)
	var stack := PackedInt32Array()
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
			# Try(k) for each neighbour.
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


## The point of country `s`, at least 32 units from the sea, whose distance
## to the other country is nearest `reach`; of those, the one nearest `want`.
static func _place(side: PackedInt32Array, s: int, to_enemy: PackedFloat32Array, to_sea: PackedFloat32Array, reach: float, want: Vector2) -> Vector2:
	var best: Vector2 = want
	var bd: float = 3.4028235e38
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


## Chamfer distance from every unit to the nearest unit whose country passes `from`.
static func _chamfer(side: PackedInt32Array, from: Callable) -> PackedFloat32Array:
	# `from` asked once per country value (-1, 0, 1) instead of once per unit.
	var pass_: Array[bool] = [from.call(-1), from.call(0), from.call(1)]
	var e := PackedFloat32Array()
	e.resize(W * H)
	for i: int in W * H:
		e[i] = 0.0 if pass_[side[i] + 1] else 1e9
	return _chamfer_passes(e)


## The two sweeps shared by _chamfer and _compute_edge. The neighbours are
## carried along the row in locals instead of read again each step.
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


## Chamfer distance from every unit to the nearest region border or coast.
func _compute_edge() -> void:
	var cl: PackedByteArray = cell
	var e := PackedFloat32Array()
	e.resize(W * H)
	for y: int in H:
		for x: int in W:
			var i: int = y * W + x
			var c: int = cl[i]
			var border: bool = c == NONE or x == 0 or y == 0 or x == W - 1 or y == H - 1 \
				or cl[i - 1] != c or cl[i + 1] != c or cl[i - W] != c or cl[i + W] != c
			e[i] = 0.0 if border else 1e9
	edge = _chamfer_passes(e)


static func _smooth(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3 - 2 * t)


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


const _M32: int = 0xFFFFFFFF


## (a * c) mod 2^32 for 0 <= a, c < 2^32, without overflowing 64 bits.
static func _mul32(a: int, c: int) -> int:
	return ((((a * (c >> 16)) & 0xFFFF) << 16) + a * (c & 0xFFFF)) & _M32


## Unsigned 32-bit hash, as the C# `unchecked` uint arithmetic.
static func _hash(x: int, y: int, s: int) -> float:
	var h: int = _mul32(x & _M32, 0x8da6b343) ^ _mul32(y & _M32, 0xd8163841) ^ _mul32(s & _M32, 0xcb1ab31f)
	h ^= h >> 15
	h = _mul32(h, 0x2c1b3c6d)
	h ^= h >> 12
	h = _mul32(h, 0x297a2d39)
	h ^= h >> 15
	return h / 2147483648.0 - 1.0
