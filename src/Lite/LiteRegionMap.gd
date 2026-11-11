class_name LiteRegionMap
extends RefCounted
## A campaign operation's map: one province of the war's map drawn large, cut
## into its districts (each its own air-alert region, named after its main
## town, the province's city the largest), with a band of the provinces round
## it, and the sea and foreign land beyond as on the war's map. Built when an
## operation starts: a few seconds' work, not the war map's minute.
##
## Its province ids are the war map's districts, so to the war on it each
## district is a province: alerts, factories and targets go district by
## district.

## How far, in the operation map's units, its borders are pushed either way
## by their zigzag: detail the war map is too coarse to have at this scale.
const ZIGZAG: float = 4.0
## Print how long each stage of building takes.
static var timing: bool = false

## The map for an operation over `province` of `war` (its owners as the
## campaign has left them). Null if the province has no land, or no land of
## the other side lies round it.
static func build(war: LiteMap, provinces: Array[int], province: int, seed: int, host: Node) -> LiteMap:
	# The campaign region fought over: its provinces (`province` the main one,
	# whose name it bears and whose city is its city).
	var in_set:= PackedByteArray()
	in_set.resize(war.regions.size())
	for p: int in provinces:
		in_set[p] = 1
	const W: int = LiteMap.W
	const H: int = LiteMap.H
	var lo:= Vector2(W, H)
	var hi:= Vector2.ZERO
	for y: int in H:
		for x: int in W:
			var c: int = war.cell[y * W + x]
			if c != LiteMap.NONE and in_set[war.province(c)] == 1:
				lo = lo.min(Vector2(x, y))
				hi = hi.max(Vector2(x + 1, y + 1))
	if hi == Vector2.ZERO:
		return null
	var size: Vector2 = (hi - lo).max(Vector2(24, 24))
	var margin: float = maxf(size.x, size.y) * 0.3 + 24.0
	var win:= Rect2(lo - Vector2(margin, margin), size + Vector2(margin, margin) * 2.0)
	# Its box filling the frame, wider or taller as it is.
	var k: float = minf((W - 40.0) / win.size.x, (H - 40.0) / win.size.y)
	var mid:= Vector2(W, H) * 0.5
	var at: Vector2 = win.get_center()
	var zig:= FastNoiseLite.new()
	zig.seed = seed
	zig.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	zig.fractal_type = FastNoiseLite.FRACTAL_FBM
	zig.fractal_octaves = 3
	zig.frequency = 0.03
	var has_sub: bool = war.sub.size() == W * H
	var t0: int = Time.get_ticks_msec()
	# The zigzag, worked out every ZG units and read between: a noise lookup
	# per map unit would take seconds.
	const ZG: int = 4
	var gw: int = W / ZG + 2
	var gh: int = H / ZG + 2
	var zx:= PackedFloat32Array()
	var zy:= PackedFloat32Array()
	zx.resize(gw * gh)
	zy.resize(gw * gh)
	for gy: int in gh:
		for gx: int in gw:
			zx[gy * gw + gx] = zig.get_noise_2d(gx * ZG, gy * ZG) * (ZIGZAG / k)
			zy[gy * gw + gx] = zig.get_noise_2d(gx * ZG + 917.0, gy * ZG - 331.0) * (ZIGZAG / k)
	# Each map unit's district on the war map (or its province, on a map
	# baked before districts), through the zigzag; and how many of each
	# district's units lie in each province.
	const KEYS: int = 400
	const PROVS: int = 64
	var key:= PackedInt32Array()
	key.resize(W * H)
	var votes:= PackedInt32Array()
	votes.resize(KEYS * PROVS)
	var used:= PackedByteArray()
	used.resize(KEYS)
	# Each war-map unit's district (or province, on a map baked before
	# districts; 300 + the province where a unit has none), -1 for the sea.
	var unit:= PackedInt32Array()
	unit.resize(W * H)
	# The same, as a texture for the graphics card (district + 1, two bytes).
	var unit_bytes:= PackedByteArray()
	unit_bytes.resize(W * H * 2)
	for j: int in W * H:
		var c: int = war.cell[j]
		var u: int
		if c == LiteMap.NONE:
			u = -1
		elif not has_sub:
			u = war.province(c)
		else:
			var dd: int = war.sub[j]
			u = dd if dd != LiteMap.NONE else 300 + war.province(c)
		unit[j] = u
		unit_bytes[j * 2] = (u + 1) & 255
		unit_bytes[j * 2 + 1] = (u + 1) >> 8
	var inv: float = 1.0 / k
	var origin: Vector2 = at - mid * inv
	for y: int in H:
		var gy: int = y / ZG
		var ty: float = float(y % ZG) / ZG
		for x: int in W:
			var gx: int = x / ZG
			var tx: float = float(x % ZG) / ZG
			var g: int = gy * gw + gx
			var ox: float = lerpf(lerpf(zx[g], zx[g + 1], tx), lerpf(zx[g + gw], zx[g + gw + 1], tx), ty)
			var oy: float = lerpf(lerpf(zy[g], zy[g + 1], tx), lerpf(zy[g + gw], zy[g + gw + 1], tx), ty)
			var i: int = y * W + x
			var fx: float = origin.x + (x + 0.5) * inv + ox - 0.5
			var fy: float = origin.y + (y + 0.5) * inv + oy - 0.5
			var qx: int = int(floor(fx))
			var qy: int = int(floor(fy))
			if qx < 0 or qy < 0 or qx >= W - 1 or qy >= H - 1:
				key[i] = -1
				continue
			# The four war-map units round the point, blended: what most of
			# their weight is (a district, or the sea), so borders and coasts
			# come out as curves, not as each unit's square edges.
			var j: int = qy * W + qx
			var v00: int = unit[j]
			var v10: int = unit[j + 1]
			var v01: int = unit[j + W]
			var v11: int = unit[j + W + 1]
			var d: int = v00
			var src: int = j
			if v10 != v00 or v01 != v00 or v11 != v00:
				var tx2: float = fx - qx
				var ty2: float = fy - qy
				var w00: float = (1 - tx2) * (1 - ty2)
				var w10: float = tx2 * (1 - ty2)
				var w01: float = (1 - tx2) * ty2
				var w11: float = tx2 * ty2
				var s00: float = w00 + (w10 if v10 == v00 else 0.0) + (w01 if v01 == v00 else 0.0) + (w11 if v11 == v00 else 0.0)
				var s10: float = w10 + (w00 if v00 == v10 else 0.0) + (w01 if v01 == v10 else 0.0) + (w11 if v11 == v10 else 0.0)
				var s01: float = w01 + (w00 if v00 == v01 else 0.0) + (w10 if v10 == v01 else 0.0) + (w11 if v11 == v01 else 0.0)
				var s11: float = w11 + (w00 if v00 == v11 else 0.0) + (w10 if v10 == v11 else 0.0) + (w01 if v01 == v11 else 0.0)
				var best: float = s00
				if s10 > best:
					best = s10
					d = v10
					src = j + 1
				if s01 > best:
					best = s01
					d = v01
					src = j + W
				if s11 > best:
					d = v11
					src = j + W + 1
			if d < 0:
				key[i] = -1
				continue
			var c: int = war.cell[src]
			var p: int = war.province(c)
			key[i] = d
			votes[d * PROVS + p] += 1
			used[d] = 1
	if timing:
		print("[region]   sample %d ms" % (Time.get_ticks_msec() - t0))
	# Only the province and the ring of districts round it: cut out along
	# district borders, not along the edge of a box (which would show as
	# straight lines). The land beyond shows faintly, as the world does.
	var adj:= PackedByteArray()
	adj.resize(KEYS * KEYS)
	for y: int in H:
		for x: int in W:
			var i: int = y * W + x
			var a: int = key[i]
			if a < 0:
				continue
			if x + 1 < W and key[i + 1] >= 0 and key[i + 1] != a:
				adj[a * KEYS + key[i + 1]] = 1
				adj[key[i + 1] * KEYS + a] = 1
			if y + 1 < H and key[i + W] >= 0 and key[i + W] != a:
				adj[a * KEYS + key[i + W]] = 1
				adj[key[i + W] * KEYS + a] = 1
	var keep:= PackedByteArray()
	keep.resize(KEYS)
	var dside:= PackedByteArray()
	dside.resize(KEYS)
	for d: int in KEYS:
		if used[d] == 1:
			var best: int = 0
			for p: int in PROVS:
				if votes[d * PROVS + p] > votes[d * PROVS + best]:
					best = p
			if in_set[best] == 1:
				keep[d] = 2
			dside[d] = war.regions[best].side
	for d: int in KEYS:
		if keep[d] != 0 or used[d] == 0:
			continue
		for o: int in KEYS:
			if keep[o] == 2 and adj[d * KEYS + o] == 1:
				keep[d] = 1
				break
	# And a second ring of our own districts, so we have room behind our
	# front for factories and air defence.
	for d: int in KEYS:
		if keep[d] != 0 or used[d] == 0 or dside[d] != 0:
			continue
		for o: int in KEYS:
			if keep[o] == 1 and dside[o] == 0 and adj[d * KEYS + o] == 1:
				keep[d] = 3
				break
	var beyond:= PackedByteArray()
	beyond.resize(W * H)
	for i: int in W * H:
		if key[i] >= 0 and keep[key[i]] == 0:
			beyond[i] = 1
			key[i] = -1
	for d: int in KEYS:
		if keep[d] == 0:
			used[d] = 0
	# The districts become this map's regions, each on the side of the
	# province holding most of it.
	var m:= LiteMap.new(seed)
	var region_of:= PackedInt32Array()
	region_of.resize(KEYS)
	region_of.fill(-1)
	var owner: PackedInt32Array = PackedInt32Array()
	for d: int in KEYS:
		if used[d] == 0:
			continue
		var best: int = 0
		for p: int in PROVS:
			if votes[d * PROVS + p] > votes[d * PROVS + best]:
				best = p
		var r:= LiteRegion.new()
		r.id = m.regions.size()
		r.side = war.regions[best].side
		region_of[d] = r.id
		owner.append(best)
		m.regions.append(r)
	if m.regions.size() > 250:
		return null
	var cell:= PackedByteArray()
	cell.resize(W * H)
	for i: int in W * H:
		cell[i] = LiteMap.NONE if key[i] < 0 else region_of[key[i]]
	m.cell = cell
	# The drawn texture, S texels a unit, worked out on the graphics card
	# (see lite_region_ids.gdshader): smooth borders, where a unit at a time
	# drew them in steps. The units' regions are then read from it, so what
	# the war sees and what is drawn agree.
	t0 = Time.get_ticks_msec()
	var lut:= PackedByteArray()
	lut.resize(512)
	lut.fill(LiteMap.NONE)
	for d: int in KEYS:
		if region_of[d] >= 0:
			lut[d + 1] = region_of[d]
	var zbytes:= PackedByteArray()
	zbytes.resize(gw * gh * 2)
	var zr: float = maxf(0.001, ZIGZAG / k)
	for g: int in gw * gh:
		zbytes[g * 2] = clampi(roundi((0.5 + zx[g] / (2.0 * zr)) * 255.0), 0, 255)
		zbytes[g * 2 + 1] = clampi(roundi((0.5 + zy[g] / (2.0 * zr)) * 255.0), 0, 255)
	var ids: PackedByteArray = await _gpu_ids(host, unit_bytes, lut, zbytes, gw, gh, zr, origin, inv, float(ZG))
	if ids.size() == LiteMap.RW * LiteMap.RH:
		m.ids = ids
		var small: Image = Image.create_from_data(LiteMap.RW, LiteMap.RH, false, Image.FORMAT_R8, ids)
		small.resize(W, H, Image.INTERPOLATE_NEAREST)
		m.cell = small.get_data()
	else:
		var img: Image = Image.create_from_data(W, H, false, Image.FORMAT_R8, m.cell)
		img.resize(LiteMap.RW, LiteMap.RH, Image.INTERPOLATE_NEAREST)
		m.ids = img.get_data()
	if timing:
		print("[region]   drawn on the graphics card %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	m._compute_edge()
	_describe(m)
	if timing:
		print("[region]   edges and regions %d ms" % (Time.get_ticks_msec() - t0))
	# Names, as on the war map: every district is called by its province
	# (for tips and the feed), but each province's name is drawn once, on its
	# largest district; one town is marked, the region's city.
	var side_here: int = war.regions[province].side
	var largest: Dictionary = {}
	for r: LiteRegion in m.regions:
		var p: int = owner[r.id]
		r.name = war.regions[p].name
		if not largest.has(p) or r.area > m.regions[largest[p]].area:
			largest[p] = r.id
	var city: int = largest.get(province, -1)
	if city < 0:
		return null
	m.label_only = {}
	for p: int in largest:
		var id: int = largest[p]
		if in_set[p] == 1 or m.regions[id].area > 700:
			m.label_only[id] = war.regions[p].name
	m.towns.append(m.regions[city].label)
	m.town_size.append(2)
	# Each side's command: in the province, at its city; for the other side,
	# in its largest district in view.
	# The other side's command: in its district furthest from the province,
	# well behind its front.
	var other: int = -1
	var far: float = -1.0
	for r: LiteRegion in m.regions:
		if r.side == side_here or r.spots.size() < 4 or r.area < 900:
			continue
		var d: float = INF
		for f: LiteRegion in m.regions:
			if in_set[owner[f.id]] == 1:
				d = minf(d, r.label.distance_to(f.label))
		if d > far:
			far = d
			other = r.id
	if other < 0:
		return null
	m.capital[side_here] = _command_spot(m.regions[city])
	m.capital[1 - side_here] = _command_spot(m.regions[other])
	for r: LiteRegion in m.regions:
		if in_set[owner[r.id]] == 1:
			m.focus.append(r.id)
	# A province holding the other side's command is named by it ("HQ ...");
	# its own name would only sit beside it.
	var cmd: int = m.region_at(m.capital[1 - side_here])
	if cmd != LiteMap.NONE and owner[cmd] != province:
		m.label_only.erase(largest.get(owner[cmd], -1))
	m.capital_name[side_here] = "HQ %s" % m.regions[city].name
	m.capital_name[1 - side_here] = "HQ %s" % (m.regions[other].name if m.regions[other].name != "" else "Front")
	# The sea and foreign land round it, as on the war's map.
	if war.world != null:
		t0 = Time.get_ticks_msec()
		m.world = _world_of(war, at, k, mid, m, beyond)
		if timing:
			print("[region]   world %d ms" % (Time.get_ticks_msec() - t0))
	return m

## A command post: in its district, clear of the name and town in the middle
## of it (about 30 units off) but not out at its edge.
static func _command_spot(r: LiteRegion) -> Vector2:
	var best: Vector2 = r.label + Vector2(0, -24)
	var off: float = INF
	for p: Vector2 in r.spots:
		var miss: float = absf(p.distance_to(r.label) - 34.0)
		# Its own name, drawn 26 units under it, must not land on the
		# district's name either.
		var name_at: Vector2 = p + Vector2(0, 26)
		if absf(name_at.y - r.label.y) < 16.0 and absf(name_at.x - r.label.x) < 70.0:
			miss += 100.0
		if miss < off:
			off = miss
			best = p
	return best

## Renders an operation map's region ids on the graphics card, in a viewport
## of its own drawn once, and reads them back.
static func _gpu_ids(host: Node, unit_bytes: PackedByteArray, lut: PackedByteArray, zbytes: PackedByteArray,
		gw: int, gh: int, zr: float, origin: Vector2, inv: float, zg: float) -> PackedByteArray:
	var mat:= ShaderMaterial.new()
	mat.shader = load("res://src/Lite/lite_region_ids.gdshader") as Shader
	mat.set_shader_parameter("units", ImageTexture.create_from_image(Image.create_from_data(LiteMap.W, LiteMap.H, false, Image.FORMAT_RG8, unit_bytes)))
	mat.set_shader_parameter("lut", ImageTexture.create_from_image(Image.create_from_data(512, 1, false, Image.FORMAT_R8, lut)))
	mat.set_shader_parameter("zig", ImageTexture.create_from_image(Image.create_from_data(gw, gh, false, Image.FORMAT_RG8, zbytes)))
	mat.set_shader_parameter("origin", origin)
	mat.set_shader_parameter("inv", inv)
	mat.set_shader_parameter("zr", zr)
	mat.set_shader_parameter("zg", zg)
	mat.set_shader_parameter("grid", Vector2(gw, gh))
	mat.set_shader_parameter("cells", Vector2(LiteMap.W, LiteMap.H))
	var vp:= SubViewport.new()
	vp.size = Vector2i(LiteMap.RW, LiteMap.RH)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect:= ColorRect.new()
	rect.size = Vector2(LiteMap.RW, LiteMap.RH)
	rect.material = mat
	vp.add_child(rect)
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.get_width() != LiteMap.RW:
		return PackedByteArray()
	img.convert(Image.FORMAT_R8)
	return img.get_data()

## Specks of a region cut off from the rest of it by the zigzag go to the
## region round them.
static func _drop_crumbs(m: LiteMap) -> void:
	var v:= PackedInt32Array()
	v.resize(LiteMap.W * LiteMap.H)
	for i: int in v.size():
		v[i] = -1 if m.cell[i] == LiteMap.NONE else m.cell[i]
	var res: Array = LiteMap._label(v)
	var comp: PackedInt32Array = res[0]
	var sizes: PackedInt32Array = res[1]
	var vals: PackedInt32Array = res[2]
	var biggest: Dictionary = {}
	for c: int in sizes.size():
		if not biggest.has(vals[c]) or sizes[c] > sizes[biggest[vals[c]]]:
			biggest[vals[c]] = c
	var to: Dictionary = {}
	for i: int in v.size():
		var c: int = comp[i]
		if c < 0 or biggest[vals[c]] == c or to.has(c):
			continue
		var x: int = i % LiteMap.W
		for j: int in [i - 1 if x > 0 else -1, i + 1 if x + 1 < LiteMap.W else -1, i - LiteMap.W, i + LiteMap.W]:
			if j >= 0 and j < v.size() and v[j] >= 0 and v[j] != vals[c]:
				to[c] = v[j]
				break
	for i: int in v.size():
		if comp[i] >= 0 and to.has(comp[i]):
			m.cell[i] = to[comp[i]]

## The texture of region ids, S texels a map unit: away from borders a copy of
## the map unit's; along them, the region (or sea) the 4 x 4 units round it
## vote for, nearer ones counting more, so borders come out as curves.
static func _upsample(cell: PackedByteArray) -> PackedByteArray:
	const W: int = LiteMap.W
	const H: int = LiteMap.H
	const S: int = LiteMap.S
	var ids:= PackedByteArray()
	ids.resize(LiteMap.RW * LiteMap.RH)
	var kern: Array[PackedFloat32Array] = []
	for sy: int in S:
		for sx: int in S:
			var kk:= PackedFloat32Array()
			kk.resize(16)
			var t:= Vector2((sx + 0.5) / S, (sy + 0.5) / S)
			for j: int in 4:
				for i: int in 4:
					var d: Vector2 = Vector2(i - 0.5, j - 0.5) - t
					kk[j * 4 + i] = exp(-d.length_squared() / (2.0 * 0.85 * 0.85))
			kern.append(kk)
	var lab:= PackedInt32Array()
	lab.resize(16)
	var wt:= PackedFloat32Array()
	wt.resize(16)
	for cy: int in H:
		for cx: int in W:
			var v: int = cell[cy * W + cx]
			var mixed: bool = false
			for dy: int in range(-1, 2):
				var yy: int = cy + dy
				if yy < 0 or yy >= H:
					continue
				for dx: int in range(-1, 2):
					var xx: int = cx + dx
					if xx >= 0 and xx < W and cell[yy * W + xx] != v:
						mixed = true
			for sy: int in S:
				for sx: int in S:
					var o: int = (cy * S + sy) * LiteMap.RW + cx * S + sx
					if not mixed:
						ids[o] = v
						continue
					var kk: PackedFloat32Array = kern[sy * S + sx]
					var n: int = 0
					for j: int in 4:
						var yy: int = cy - 1 + j
						if yy < 0 or yy >= H:
							continue
						for i: int in 4:
							var xx: int = cx - 1 + i
							if xx < 0 or xx >= W:
								continue
							var l: int = cell[yy * W + xx]
							var q: int = 0
							while q < n and lab[q] != l:
								q += 1
							if q == n:
								lab[n] = l
								wt[n] = 0.0
								n += 1
							wt[q] += kk[j * 4 + i]
					var best: int = 0
					for q: int in range(1, n):
						if wt[q] > wt[best]:
							best = q
					ids[o] = lab[best] if n > 0 else v
	return ids

## Each region's area, centre, neighbours, a scatter of free ground (its
## spots) and where its name goes; the box round the land.
static func _describe(m: LiteMap) -> void:
	const W: int = LiteMap.W
	const H: int = LiteMap.H
	var n: int = m.regions.size()
	var sum:= PackedVector2Array()
	sum.resize(n)
	var areas:= PackedInt32Array()
	areas.resize(n)
	var best:= PackedFloat32Array()
	best.resize(n)
	best.fill(-1.0)
	var labels:= PackedVector2Array()
	labels.resize(n)
	var spots: Array[Array] = []
	for i: int in n:
		spots.append([] as Array[Vector2])
	var lo:= Vector2(W, H)
	var hi:= Vector2.ZERO
	for y: int in H:
		for x: int in W:
			var i: int = y * W + x
			var id: int = m.cell[i]
			if id == LiteMap.NONE:
				continue
			lo = lo.min(Vector2(x, y))
			hi = hi.max(Vector2(x + 1, y + 1))
			areas[id] += 1
			sum[id] += Vector2(x + 0.5, y + 0.5)
			var e: float = m.edge[i]
			if e >= 8 and (x + y * 7) % 7 == 0:
				spots[id].append(Vector2(x + 0.5, y + 0.5))
			if e > best[id]:
				best[id] = e
				labels[id] = Vector2(x + 0.5, y + 0.5)
			if x + 1 < W:
				var o: int = m.cell[i + 1]
				if o != LiteMap.NONE and o != id:
					m.regions[id].neighbors[o] = true
					m.regions[o].neighbors[id] = true
			if y + 1 < H:
				var o: int = m.cell[i + W]
				if o != LiteMap.NONE and o != id:
					m.regions[id].neighbors[o] = true
					m.regions[o].neighbors[id] = true
	for r: LiteRegion in m.regions:
		r.area = areas[r.id]
		r.center = sum[r.id] / r.area if r.area > 0 else Vector2.ZERO
		r.label = labels[r.id]
		var list: Array = spots[r.id]
		list.shuffle()
		for kk: int in mini(80, list.size()):
			r.spots.append(list[kk])
	m.land_rect = Rect2(lo, hi - lo)

## The world round it (sea, foreign land) from the war map's, at this scale.
## The war's own land beyond the operation's districts (BEYOND) shows as land
## too, faintly, so the cut-out does not float in the sea.
const BEYOND: int = 254

static func _world_of(war: LiteMap, at: Vector2, k: float, mid: Vector2, m: LiteMap, beyond: PackedByteArray) -> LiteWorld:
	var w:= LiteWorld.new()
	w.ids.resize(LiteWorld.WW * LiteWorld.WH)
	for y: int in LiteWorld.WH:
		for x: int in LiteWorld.WW:
			var p: Vector2 = LiteWorld.cell_pos(x, y)
			var q: Vector2 = at + (p - mid) / k
			# The four war-world cells round it, blended (as the land is), or
			# its coasts come out in steps five cells wide.
			var wq: Vector2 = (q + LiteWorld.PAD) / LiteWorld.K - Vector2(0.5, 0.5)
			var wx: int = clampi(int(floor(wq.x)), 0, LiteWorld.WW - 2)
			var wy: int = clampi(int(floor(wq.y)), 0, LiteWorld.WH - 2)
			var tx: float = clampf(wq.x - wx, 0.0, 1.0)
			var ty: float = clampf(wq.y - wy, 0.0, 1.0)
			var j: int = wy * LiteWorld.WW + wx
			var a00: int = war.world.ids[j]
			var a10: int = war.world.ids[j + 1]
			var a01: int = war.world.ids[j + LiteWorld.WW]
			var a11: int = war.world.ids[j + LiteWorld.WW + 1]
			var v: int = a00
			if a10 != a00 or a01 != a00 or a11 != a00:
				var w00: float = (1 - tx) * (1 - ty)
				var w10: float = tx * (1 - ty)
				var w01: float = (1 - tx) * ty
				var w11: float = tx * ty
				var s00: float = w00 + (w10 if a10 == a00 else 0.0) + (w01 if a01 == a00 else 0.0) + (w11 if a11 == a00 else 0.0)
				var s10: float = w10 + (w00 if a00 == a10 else 0.0) + (w01 if a01 == a10 else 0.0) + (w11 if a11 == a10 else 0.0)
				var s01: float = w01 + (w00 if a00 == a01 else 0.0) + (w10 if a10 == a01 else 0.0) + (w11 if a11 == a01 else 0.0)
				var s11: float = w11 + (w00 if a00 == a11 else 0.0) + (w10 if a10 == a11 else 0.0) + (w01 if a01 == a11 else 0.0)
				var top: float = s00
				if s10 > top:
					top = s10
					v = a10
				if s01 > top:
					top = s01
					v = a01
				if s11 > top:
					v = a11
			if v == LiteWorld.OURS:
				# Inside this map: its own land, or the war's beyond it.
				var cx: int = int(p.x)
				var cy: int = int(p.y)
				var inside: bool = cx >= 0 and cy >= 0 and cx < LiteMap.W and cy < LiteMap.H
				if inside and m.cell[cy * LiteMap.W + cx] != LiteMap.NONE:
					v = LiteWorld.OURS
				elif not inside or beyond[cy * LiteMap.W + cx] == 1:
					# The war's province there, faded, its borders drawn:
					# ours from OURS_BEYOND on, the enemy's from THEIRS_BEYOND.
					v = BEYOND
					var qx: int = clampi(int(q.x), 0, LiteMap.W - 1)
					var qy: int = clampi(int(q.y), 0, LiteMap.H - 1)
					var wc: int = war.cell[qy * LiteMap.W + qx]
					if wc != LiteMap.NONE:
						var pr: int = war.province(wc)
						v = (LiteWorld.OURS_BEYOND if war.regions[pr].side == 0 else LiteWorld.THEIRS_BEYOND) + pr
				else:
					v = LiteWorld.SEA
			w.ids[y * LiteWorld.WW + x] = v
	# The names of the provinces beyond, where they show and are not under
	# the operation's own land.
	var named: Dictionary = {}
	for o: LiteRegion in m.regions:
		named[o.name] = true
	for r: LiteRegion in war.regions:
		if r.city or named.has(r.name):
			continue
		var p: Vector2 = mid + (r.label - at) * k
		if p.x < 40 or p.y < 30 or p.x > LiteMap.W - 40 or p.y > LiteMap.H - 20:
			continue
		var cx: int = int(p.x)
		var cy: int = int(p.y)
		if m.cell[cy * LiteMap.W + cx] != LiteMap.NONE:
			continue
		w.label_text.append(r.name)
		w.label_at.append(p)
		w.label_kind.append(2)
	return w
