class_name LiteWorld
extends RefCounted
## The world round the two warring countries, so the map does not float in
## an empty page: neighbouring countries with their names, the sea, and a
## few islands. Only drawn: the war never sees any of it (to the game it is
## all sea, NONE), so weapons may cross it on their way.
##
## A grid of its own, coarser than the map's and reaching well past its
## edges, as the view may show beyond them: one byte per cell, 0 for sea,
## OURS under the two countries, and 1 to N for the neighbours.

const PAD: Vector2 = Vector2(320, 260)
## Map units per cell.
const K: int = 2
const WW: int = int((LiteMap.W + 2 * PAD.x) / K)
const WH: int = int((LiteMap.H + 2 * PAD.y) / K)
const SEA: int = 0
const OURS: int = 255
## On an operation's map, the war's own provinces beyond its districts: ours
## from 100 on, the enemy's from 170 on (each plus its province id).
const OURS_BEYOND: int = 100
const THEIRS_BEYOND: int = 170

const NAMES: Array[String] = ["Valmora", "Ostrelia", "Karvenia", "Lindmar", "Belsaria", "Drovania",
	"Halvoria", "Nordessa", "Varenta", "Kelmoria", "Austerra", "Pellonia", "Tavria Minor", "Esmeria"]
const SEAS: Array[String] = ["Grey Sea", "Amber Sea", "Cold Sea", "Sea of Vela", "Gulf of Orm", "Bay of Lisk"]

var ids: PackedByteArray = PackedByteArray()
## Names to draw: where, what, and whether a country (0) or a sea (1).
var label_text: PackedStringArray = PackedStringArray()
var label_at: PackedVector2Array = PackedVector2Array()
var label_kind: PackedInt32Array = PackedInt32Array()

static func cell_pos(x: int, y: int) -> Vector2:
	return Vector2(x * K + K * 0.5, y * K + K * 0.5) - PAD

func to_dict() -> Dictionary:
	return {"ids": ids, "text": label_text, "at": label_at, "kind": label_kind}

static func from_dict(d: Dictionary) -> LiteWorld:
	var w:= LiteWorld.new()
	w.ids = d["ids"]
	w.label_text = d["text"]
	w.label_at = d["at"]
	w.label_kind = d["kind"]
	return w

## The part of the map the view shows (see LiteMain.fit_view), for placing names.
static func shown(map: LiteMap) -> Rect2:
	var land: Rect2 = map.land_rect.grow(14)
	var frame:= Vector2(LiteMap.W - 12, LiteMap.H - 36)
	var k: float = minf(minf(frame.x / land.size.x, frame.y / land.size.y), 1.6)
	var size: Vector2 = frame / k
	return Rect2(land.get_center() - size * 0.5, size)

static func generate(map: LiteMap, seed: int) -> LiteWorld:
	var w:= LiteWorld.new()
	var rng:= RandomNumberGenerator.new()
	rng.seed = seed * 31 + 7
	var noise:= FastNoiseLite.new()
	noise.seed = seed + 101
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.frequency = 0.0055
	var fine:= FastNoiseLite.new()
	fine.seed = seed + 103
	fine.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fine.fractal_type = FastNoiseLite.FRACTAL_FBM
	fine.fractal_octaves = 3
	fine.frequency = 0.045
	var n: int = WW * WH
	var ours:= PackedByteArray()
	ours.resize(n)
	for y: int in WH:
		for x: int in WW:
			var p: Vector2 = cell_pos(x, y)
			if p.x >= 0 and p.y >= 0 and p.x < LiteMap.W and p.y < LiteMap.H and map.cell[int(p.y) * LiteMap.W + int(p.x)] != LiteMap.NONE:
				ours[y * WW + x] = 1
	var near_ours: PackedFloat32Array = _distance(ours, 1)
	# Which sides of the map neighbours lie on (the rest is sea): at least
	# one of each.
	var land_side: Array[bool] = []
	for k: int in 4:
		land_side.append(rng.randf() < 0.55)
	if not land_side.has(true):
		land_side[rng.randi_range(0, 3)] = true
	if not land_side.has(false):
		land_side[rng.randi_range(0, 3)] = false
	var mid:= Vector2(LiteMap.W, LiteMap.H) * 0.5
	var half:= Vector2(LiteMap.W, LiteMap.H) * 0.5
	var land:= PackedByteArray()
	land.resize(n)
	for y: int in WH:
		for x: int in WW:
			var i: int = y * WW + x
			if ours[i] == 1:
				continue
			var p: Vector2 = cell_pos(x, y)
			var u: Vector2 = (p - mid) / half
			var f: float = -0.55 + 0.6 * noise.get_noise_2d(p.x, p.y) + 0.06 * fine.get_noise_2d(p.x, p.y)
			if land_side[0]: f += 1.2 * smoothstep(0.3, 1.15, -u.y)
			if land_side[1]: f += 1.2 * smoothstep(0.3, 1.15, u.x)
			if land_side[2]: f += 1.2 * smoothstep(0.3, 1.15, u.y)
			if land_side[3]: f += 1.2 * smoothstep(0.3, 1.15, -u.x)
			if f > 0.0:
				land[i] = 1
	# No thin strips of a neighbour's land (along our coast, say): what is
	# left after shaving SLIVER units off it and growing it back.
	_open(land, SLIVER / K)
	# A narrow strait between a neighbour and our coast closes into a land
	# border instead.
	var to_n: PackedFloat32Array = _distance(land, 1)
	for i: int in n:
		if land[i] == 0 and ours[i] == 0 and (to_n[i] + near_ours[i]) * K < 14.0:
			land[i] = 1
	# Islands, out at sea.
	var to_land: PackedFloat32Array = _distance(_or(land, ours), 1)
	var islands: int = rng.randi_range(2, 5)
	for t: int in 400:
		if islands <= 0:
			break
		var x: int = rng.randi_range(20, WW - 21)
		var y: int = rng.randi_range(20, WH - 21)
		if to_land[y * WW + x] * K < 40.0:
			continue
		islands -= 1
		var r: float = rng.randf_range(6.0, 15.0) / K
		var a: float = rng.randf() * TAU
		var stretch: float = rng.randf_range(1.0, 2.2)
		for dy: int in range(-int(r * 3), int(r * 3) + 1):
			for dx: int in range(-int(r * 3), int(r * 3) + 1):
				var q:= Vector2(dx, dy).rotated(a)
				var e: float = Vector2(q.x / stretch, q.y).length() / r + 0.4 * fine.get_noise_2d((x + dx) * K, (y + dy) * K)
				var xx: int = x + dx
				var yy: int = y + dy
				if e < 1.0 and xx >= 0 and yy >= 0 and xx < WW and yy < WH:
					land[yy * WW + xx] = 1
	# Tiny bits of land and small enclosed patches of water go.
	_drop_small(land, 1, 160)
	_drop_small(land, 0, 400, ours)
	# The neighbours: the land nearest each of a few seeds spread over it.
	var cells: PackedInt32Array = PackedInt32Array()
	for i: int in n:
		if land[i] == 1:
			cells.append(i)
	w.ids.resize(n)
	for i: int in n:
		w.ids[i] = OURS if ours[i] == 1 else SEA
	if cells.is_empty():
		return w
	# The neighbours, one landmass at a time, so none owns a piece far from
	# the rest of it: each large mass is shared between a few seeds spread over
	# it, by the nearest (through a warp, so the borders wind); a small one (an
	# island) goes to the country nearest it.
	var lab: Array = _label(land)
	var comp: PackedInt32Array = lab[0]
	var sizes: PackedInt32Array = lab[1]
	var seeds: Array[Vector2] = []
	var seed_mass: PackedInt32Array = PackedInt32Array()
	var members: Array[PackedInt32Array] = []
	for c: int in sizes.size():
		members.append(PackedInt32Array())
	for i: int in cells:
		members[comp[i]].append(i)
	for c: int in sizes.size():
		if sizes[c] * K * K < 6000:
			continue
		var count: int = clampi(roundi(sizes[c] * K * K / 70000.0), 1, 4)
		var sample: Array[Vector2] = []
		for t: int in 400:
			var m: int = members[c][rng.randi_range(0, members[c].size() - 1)]
			sample.append(Vector2(m % WW, m / WW))
		var mine: Array[Vector2] = [sample[0]]
		while mine.size() < count:
			var best: Vector2 = sample[0]
			var bd: float = -1.0
			for q: Vector2 in sample:
				var dq: float = INF
				for s: Vector2 in mine:
					dq = minf(dq, q.distance_squared_to(s))
				if dq > bd:
					bd = dq
					best = q
			mine.append(best)
		for q: Vector2 in mine:
			seeds.append(q)
			seed_mass.append(c)
		if seeds.size() >= 8:
			break
	if seeds.is_empty():
		var m0: int = cells[0]
		seeds.append(Vector2(m0 % WW, m0 / WW))
		seed_mass.append(comp[m0])
	for c: int in sizes.size():
		var own: Array[int] = []
		for k: int in seeds.size():
			if seed_mass[k] == c:
				own.append(k)
		if own.is_empty():
			# An island: the country of the nearest seed.
			var m: int = members[c][0]
			var at:= Vector2(m % WW, m / WW)
			var best: int = 0
			for k: int in seeds.size():
				if at.distance_squared_to(seeds[k]) < at.distance_squared_to(seeds[best]):
					best = k
			for i: int in members[c]:
				w.ids[i] = best + 1
			continue
		for i: int in members[c]:
			var x: int = i % WW
			var y: int = i / WW
			var p: Vector2 = cell_pos(x, y)
			var q:= Vector2(x, y) + Vector2(14.0 * noise.get_noise_2d(p.x * 1.7, p.y * 1.7) + 1.8 * fine.get_noise_2d(p.x, p.y),
				14.0 * noise.get_noise_2d(p.x * 1.7 + 517.0, p.y * 1.7 - 311.0) + 1.8 * fine.get_noise_2d(p.x + 913.0, p.y - 377.0))
			var best: int = own[0]
			var bd: float = INF
			for k: int in own:
				var dd: float = q.distance_squared_to(seeds[k])
				if dd < bd:
					bd = dd
					best = k
			w.ids[i] = best + 1
	w._merge_strays()
	w._name_things(map, seeds.size(), rng, to_land)
	return w

## Names for the neighbours that show, each where it is widest within view,
## and for the open sea, where it is furthest from land.
func _name_things(map: LiteMap, count: int, rng: RandomNumberGenerator, to_land: PackedFloat32Array) -> void:
	# Kept clear of the edges, more so at the sides, where the spaced-out
	# names run long.
	var view: Rect2 = shown(map).grow_individual(-90, -30, -90, -30)
	var names: Array[String] = NAMES.duplicate()
	for i: int in range(names.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t: String = names[i]
		names[i] = names[j]
		names[j] = t
	# How far inside its own country each cell is.
	var e:= PackedFloat32Array()
	e.resize(WW * WH)
	for y: int in WH:
		for x: int in WW:
			var i: int = y * WW + x
			var v: int = ids[i]
			var edge: bool = x == 0 or y == 0 or x == WW - 1 or y == WH - 1 or ids[i - 1] != v or ids[i + 1] != v or ids[i - WW] != v or ids[i + WW] != v
			e[i] = 0.0 if edge else 1000000000.0
	e = LiteMap._chamfer_passes(e, WW, WH)
	var best_at: Array[Vector2] = []
	var best_d: PackedFloat32Array = PackedFloat32Array()
	best_d.resize(count + 1)
	best_d.fill(-1.0)
	for k: int in count + 1:
		best_at.append(Vector2.ZERO)
	var sea_at:= Vector2.ZERO
	var sea_d: float = -1.0
	for y: int in WH:
		for x: int in WW:
			var p: Vector2 = cell_pos(x, y)
			if not view.has_point(p):
				continue
			var i: int = y * WW + x
			var v: int = ids[i]
			if v == SEA:
				if to_land[i] > sea_d:
					sea_d = to_land[i]
					sea_at = p
			elif v != OURS and e[i] > best_d[v]:
				best_d[v] = e[i]
				best_at[v] = p
	for k: int in range(1, count + 1):
		# Only where enough of it shows to hold a name.
		if best_d[k] * K >= 14.0:
			label_text.append(names[(k - 1) % names.size()])
			label_at.append(best_at[k])
			label_kind.append(0)
	if sea_d * K >= 30.0:
		label_text.append(SEAS[rng.randi_range(0, SEAS.size() - 1)])
		label_at.append(sea_at)
		label_kind.append(1)

## Neighbour land thinner than about twice this, in map units, is shaved off.
const SLIVER: float = 7.0

## Each neighbour in one piece where it can be: a stray bit of one that
## touches another goes to the one it touches most. (An island alone keeps
## its country.)
func _merge_strays() -> void:
	var lab: Array = _label_ids(ids)
	var comp: PackedInt32Array = lab[0]
	var sizes: PackedInt32Array = lab[1]
	var vals: PackedInt32Array = lab[2]
	var biggest: Dictionary = {}
	for c: int in sizes.size():
		if not biggest.has(vals[c]) or sizes[c] > sizes[biggest[vals[c]]]:
			biggest[vals[c]] = c
	var votes: Dictionary = {}
	for i: int in WW * WH:
		var c: int = comp[i]
		if c < 0 or biggest[vals[c]] == c:
			continue
		var x: int = i % WW
		for j: int in [i - 1 if x > 0 else -1, i + 1 if x + 1 < WW else -1, i - WW, i + WW]:
			if j < 0 or j >= WW * WH:
				continue
			var o: int = ids[j]
			if o == SEA or o == OURS or o == vals[c]:
				continue
			if not votes.has(c):
				votes[c] = {}
			votes[c][o] = int(votes[c].get(o, 0)) + 1
	for i: int in WW * WH:
		var c: int = comp[i]
		if c < 0 or not votes.has(c):
			continue
		var top: int = -1
		var tn: int = 0
		for o: int in votes[c]:
			if votes[c][o] > tn:
				tn = votes[c][o]
				top = o
		ids[i] = top

## Pieces of land (value 1) side by side, and pieces of each neighbour.
static func _label(a: PackedByteArray) -> Array:
	var v:= PackedInt32Array()
	v.resize(a.size())
	for i: int in a.size():
		v[i] = 1 if a[i] == 1 else -1
	return _label_values(v)

static func _label_ids(a: PackedByteArray) -> Array:
	var v:= PackedInt32Array()
	v.resize(a.size())
	for i: int in a.size():
		v[i] = -1 if a[i] == SEA or a[i] == OURS else a[i]
	return _label_values(v)

## Labels the pieces of `v` (cells side by side with one value, not below 0):
## each cell's piece (or -1), and each piece's size and value.
static func _label_values(v: PackedInt32Array) -> Array:
	var comp:= PackedInt32Array()
	comp.resize(WW * WH)
	comp.fill(-1)
	var sizes:= PackedInt32Array()
	var vals:= PackedInt32Array()
	var stack:= PackedInt32Array()
	stack.resize(WW * WH)
	for i: int in WW * WH:
		var val: int = v[i]
		if val < 0 or comp[i] >= 0:
			continue
		var c: int = sizes.size()
		var count: int = 0
		var top: int = 1
		comp[i] = c
		stack[0] = i
		while top > 0:
			top -= 1
			var j: int = stack[top]
			count += 1
			var x: int = j % WW
			for o: int in [j - 1 if x > 0 else -1, j + 1 if x + 1 < WW else -1, j - WW, j + WW]:
				if o >= 0 and o < WW * WH and comp[o] < 0 and v[o] == val:
					comp[o] = c
					stack[top] = o
					top += 1
		sizes.append(count)
		vals.append(val)
	return [comp, sizes, vals]

## Thin parts of land (value 1) go: a morphological opening of radius `r` cells.
static func _open(a: PackedByteArray, r: float) -> void:
	var inside: PackedFloat32Array = _distance(a, 0)
	var core:= PackedFloat32Array()
	core.resize(WW * WH)
	for i: int in WW * WH:
		core[i] = 0.0 if a[i] == 1 and inside[i] >= r else 1000000000.0
	var near: PackedFloat32Array = LiteMap._chamfer_passes(core, WW, WH)
	for i: int in WW * WH:
		if a[i] == 1 and near[i] > r + 0.5:
			a[i] = 0

## Distance in cells to the nearest cell with value `v`.
static func _distance(a: PackedByteArray, v: int) -> PackedFloat32Array:
	var e:= PackedFloat32Array()
	e.resize(WW * WH)
	for i: int in WW * WH:
		e[i] = 0.0 if a[i] == v else 1000000000.0
	return LiteMap._chamfer_passes(e, WW, WH)

static func _or(a: PackedByteArray, b: PackedByteArray) -> PackedByteArray:
	var o:= PackedByteArray()
	o.resize(a.size())
	for i: int in a.size():
		o[i] = 1 if a[i] == 1 or b[i] == 1 else 0
	return o

## Pieces of value `v` smaller than `most` cells become the other value; for
## water (v 0), only pieces enclosed away from the grid's edge and from `keep`.
static func _drop_small(a: PackedByteArray, v: int, most: int, keep: PackedByteArray = PackedByteArray()) -> void:
	var comp:= PackedInt32Array()
	comp.resize(WW * WH)
	comp.fill(-1)
	var stack:= PackedInt32Array()
	for s: int in WW * WH:
		if a[s] != v or comp[s] >= 0 or (not keep.is_empty() and keep[s] == 1):
			continue
		var members:= PackedInt32Array([s])
		comp[s] = s
		stack.clear()
		stack.append(s)
		var edge: bool = false
		while not stack.is_empty():
			var i: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var x: int = i % WW
			var y: int = i / WW
			if x == 0 or y == 0 or x == WW - 1 or y == WH - 1:
				edge = true
			for j: int in [i - 1 if x > 0 else -1, i + 1 if x + 1 < WW else -1, i - WW if y > 0 else -1, i + WW if y + 1 < WH else -1]:
				if j >= 0 and comp[j] < 0 and a[j] == v and (keep.is_empty() or keep[j] == 0):
					comp[j] = s
					stack.append(j)
					members.append(j)
		if members.size() < most and (v == 1 or not edge):
			for i: int in members:
				a[i] = 1 - v
