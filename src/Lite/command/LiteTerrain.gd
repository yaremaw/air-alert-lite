class_name LiteTerrain
extends RefCounted
## The illustrated terrain under the command look's map: grassland and fields,
## forests, mountain ranges, rivers and lakes, roads with bridges, towns and
## cities, over the two countries and the world round them. Worked out once
## per map: its features (rivers, roads, towns) drawn here into an image, the
## rest painted by lite_terrain_bake.gdshader into a texture on the graphics
## card, one texel an art pixel (ART map units, as the site sprites). The map
## and world shaders lay the countries' colours over it.

## Map units an art pixel (16-pixel site sprites are drawn 20 units wide).
const ART: float = 1.25

## The terrain texture's size, in art pixels, and where its top left lies.
static func size() -> Vector2i:
	var ext: Vector2 = Vector2(LiteMap.W, LiteMap.H) + LiteWorld.PAD * 2.0
	return Vector2i(ceili(ext.x / ART), ceili(ext.y / ART))

static func origin() -> Vector2:
	return -LiteWorld.PAD

## Starts painting `map`'s terrain; the texture it gives is filled in on the
## next frame. `host` keeps the viewport that paints it.
## The settlements' lights at night, made with the terrain (see LiteSettle):
## one pixel a light, alpha under 1 for those that flicker.
static var lights: Image = null

static func make(map: LiteMap, host: Node, ids: Texture2D) -> Texture2D:
	var sz: Vector2i = size()
	var rng:= RandomNumberGenerator.new()
	rng.seed = map.seed * 977 + 41
	# The smooth fields at half the resolution (sampled smoothly anyway):
	# a quarter of the work.
	var hs:= Vector2i(ceili(sz.x / 2.0), ceili(sz.y / 2.0))
	# Height, wetness and warmth over broad areas: the biomes (see the bake
	# shader), the same fields the simulation knows them by (LiteBiome).
	var f: Array[Image] = LiteBiome.fields(map)
	var elev: Image = f[0]
	var moist: Image = f[1]
	var temp: Image = f[2]
	var farm: Image = _noise(map.seed * 11 + 4, 0.03, 2, FastNoiseLite.FRACTAL_FBM, hs)
	var feat: Image = Image.create_empty(sz.x, sz.y, false, Image.FORMAT_RGBA8)
	var t:= Terrain.new()
	t.map = map
	t.feat = feat
	t.elev = elev
	t.moist = moist
	t.sz = sz
	t.rng = rng
	t.lights = Image.create_empty(sz.x, sz.y, false, Image.FORMAT_RGBA8)
	t.rivers()
	t.lakes()
	t.towns()
	t.roads()
	lights = t.lights
	var vp:= SubViewport.new()
	vp.size = sz
	vp.disable_3d = true
	# Its alpha is kept: how much of the countries' colours each texel takes.
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect:= ColorRect.new()
	rect.size = Vector2(sz)
	var mat:= ShaderMaterial.new()
	mat.shader = load("res://src/Lite/command/lite_terrain_bake.gdshader") as Shader
	mat.set_shader_parameter("ids", ids)
	if map.world != null:
		mat.set_shader_parameter("world", ImageTexture.create_from_image(Image.create_from_data(LiteWorld.WW, LiteWorld.WH, false, Image.FORMAT_R8, map.world.ids)))
		mat.set_shader_parameter("has_world", true)
	mat.set_shader_parameter("world_pad", LiteWorld.PAD)
	mat.set_shader_parameter("world_k", float(LiteWorld.K))
	mat.set_shader_parameter("map_size", Vector2(LiteMap.W, LiteMap.H))
	mat.set_shader_parameter("origin", origin())
	mat.set_shader_parameter("art", ART)
	mat.set_shader_parameter("elev", ImageTexture.create_from_image(elev))
	mat.set_shader_parameter("moist", ImageTexture.create_from_image(moist))
	mat.set_shader_parameter("temp", ImageTexture.create_from_image(temp))
	var cs: Array = LiteBiome.climate_shift(LiteBiome.climate(map))
	mat.set_shader_parameter("climate_t", float(cs[0]))
	mat.set_shader_parameter("climate_w", float(cs[1]))
	mat.set_shader_parameter("dry", float(cs[2]))
	mat.set_shader_parameter("arid", LiteBiome.climate(map) == LiteBiome.ARID)
	mat.set_shader_parameter("farm", ImageTexture.create_from_image(farm))
	mat.set_shader_parameter("feat", ImageTexture.create_from_image(feat))
	mat.set_shader_parameter("atlas", load("res://assets/ui/terrain.png") as Texture2D)
	rect.material = mat
	vp.add_child(rect)
	host.add_child(vp)
	return vp.get_texture()

static func _noise(seed_: int, freq: float, octaves: int, fractal: int, sz: Vector2i) -> Image:
	var n:= FastNoiseLite.new()
	n.seed = seed_
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	n.frequency = freq
	var img: Image = n.get_image(sz.x, sz.y, false, false, true)
	img.convert(Image.FORMAT_L8)
	return img


## The features drawn into an image: r water, g road, b town (how dense),
## a bridge.
class Terrain extends RefCounted:
	var map: LiteMap
	var feat: Image
	var elev: Image
	var moist: Image
	var sz: Vector2i
	var rng: RandomNumberGenerator
	var lights: Image

	## Map units of art pixel `q`'s middle.
	func mp(q: Vector2) -> Vector2:
		return LiteTerrain.origin() + (q + Vector2(0.5, 0.5)) * LiteTerrain.ART

	func art(p: Vector2) -> Vector2:
		return (p - LiteTerrain.origin()) / LiteTerrain.ART

	func inside(q: Vector2) -> bool:
		return q.x >= 1 and q.y >= 1 and q.x < sz.x - 1 and q.y < sz.y - 1

	## Whether `q` is the two countries' land (not the world round them).
	func ours(q: Vector2) -> bool:
		var p: Vector2 = mp(q)
		if p.x < 0 or p.y < 0 or p.x >= LiteMap.W or p.y >= LiteMap.H:
			return false
		return map.cell[int(p.y) * LiteMap.W + int(p.x)] != LiteMap.NONE

	## Elevation at art pixel `q` (the field is at half resolution).
	func e(q: Vector2) -> float:
		var c: Vector2i = Vector2i(clampi(int(q.x * 0.5), 0, elev.get_width() - 1), clampi(int(q.y * 0.5), 0, elev.get_height() - 1))
		return elev.get_pixelv(c).r

	func water(q: Vector2) -> bool:
		return inside(q) and feat.get_pixelv(Vector2i(q)).r > 0.5

	## A disc of water.
	func wet(c: Vector2, r: float) -> void:
		var rr: int = ceili(r)
		for dy: int in range(-rr, rr + 1):
			for dx: int in range(-rr, rr + 1):
				if dx * dx + dy * dy > r * r + 0.3:
					continue
				var q: Vector2i = Vector2i(c) + Vector2i(dx, dy)
				if q.x < 0 or q.y < 0 or q.x >= sz.x or q.y >= sz.y:
					continue
				var px: Color = feat.get_pixelv(q)
				px.r = 1.0
				feat.set_pixelv(q, px)

	## Rivers: each from a mouth on the coast up into the higher ground,
	## winding, wide at the sea and narrow at its source; a tributary or two
	## branching off upstream.
	func rivers() -> void:
		var mouths: Array[Vector2] = []
		for tries: int in 4000:
			if mouths.size() >= 6 + rng.randi_range(0, 3):
				break
			var q:= Vector2(rng.randi_range(4, sz.x - 5), rng.randi_range(4, sz.y - 5))
			if not ours(q):
				continue
			var coast: bool = false
			for d: Vector2 in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
				if not ours(q + d) and not _neighbour(q + d):
					coast = true
			if not coast:
				continue
			var far: bool = true
			for o: Vector2 in mouths:
				if o.distance_to(q) < 80.0:
					far = false
			if far:
				mouths.append(q)
		for m: Vector2 in mouths:
			var path: PackedVector2Array = _climb(m, rng.randi_range(220, 420), 0.0)
			for i: int in path.size():
				var k: float = float(i) / maxf(1.0, path.size() - 1)
				wet(path[i], lerpf(2.4, 0.9, k))
			for b: int in rng.randi_range(1, 3):
				if path.size() < 40:
					break
				var at: int = int(path.size() * rng.randf_range(0.3, 0.6))
				var side: float = (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.9, 1.3)
				var trib: PackedVector2Array = _climb(path[at], rng.randi_range(80, 180), side)
				for i: int in trib.size():
					wet(trib[i], lerpf(1.3, 0.86, float(i) / maxf(1.0, trib.size() - 1)))

	func _neighbour(q: Vector2) -> bool:
		if map.world == null:
			return false
		var p: Vector2 = mp(q) + LiteWorld.PAD
		var wx: int = int(p.x / LiteWorld.K)
		var wy: int = int(p.y / LiteWorld.K)
		if wx < 0 or wy < 0 or wx >= LiteWorld.WW or wy >= LiteWorld.WH:
			return false
		var w: int = map.world.ids[wy * LiteWorld.WW + wx]
		return w != 0 and w != 255

	## A river's course from `from` uphill, meandering; `turn` bends a
	## tributary off to one side at first.
	func _climb(from: Vector2, steps: int, turn: float) -> PackedVector2Array:
		var out:= PackedVector2Array([from])
		var p: Vector2 = from
		# Inland: away from the nearest sea at first.
		var dir:= Vector2.ZERO
		for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			if ours(p + d * 6.0):
				dir += d
		dir = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
		if turn != 0.0:
			dir = dir.rotated(turn)
		var phase: float = rng.randf() * TAU
		for i: int in steps:
			var g:= Vector2(e(p + Vector2(2, 0)) - e(p - Vector2(2, 0)), e(p + Vector2(0, 2)) - e(p - Vector2(0, 2)))
			var up: Vector2 = g.normalized() if g.length() > 0.0001 else dir
			dir = (dir * 0.82 + up * 0.18).normalized()
			var wiggle: Vector2 = dir.orthogonal() * sin(i * 0.06 + phase) * 0.6
			var n: Vector2 = p + (dir + wiggle).normalized() * 0.9
			if not ours(n) or not inside(n):
				break
			# A tributary ends where it meets other water.
			if turn != 0.0 and i > 6 and water(n + dir * 2.0):
				break
			p = n
			out.append(p)
		return out

	## A few lakes in the wet low ground, each a blob of overlapping discs.
	func lakes() -> void:
		var best: Array = []
		for tries: int in 600:
			var q:= Vector2(rng.randi_range(8, sz.x - 9), rng.randi_range(8, sz.y - 9))
			if not ours(q) or water(q):
				continue
			var score: float = moist.get_pixelv(Vector2i(q * 0.5)).r - e(q)
			best.append([score, q])
		best.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var made: Array[Vector2] = []
		for c: Array in best:
			if made.size() >= 3:
				break
			var q: Vector2 = c[1]
			var ok: bool = true
			for o: Vector2 in made:
				if o.distance_to(q) < 90.0:
					ok = false
			if not ok:
				continue
			made.append(q)
			for k: int in 4:
				var o:= Vector2(rng.randf_range(-4, 4), rng.randf_range(-3, 3))
				if ours(q + o):
					wet(q + o, rng.randf_range(2.5, 4.5))

	## Settlements (see LiteSettle): one at each region's name, a city, a
	## town or a village by how big the region is, and a village or two more
	## in the bigger ones; the capitals' suburbs (their cities are drawn live,
	## see LiteCmdCity).
	func towns() -> void:
		var st:= LiteSettle.new(feat, lights, rng, func(q: Vector2) -> bool: return inside(q) and ours(q) and not water(q))
		for side: int in 2:
			var cp: Vector2 = map.capital[side]
			if cp != Vector2.ZERO:
				st.keep_clear.append([art(cp), 44.0])
		var areas: Array[int] = []
		for r: LiteRegion in map.regions:
			if r.label != Vector2.ZERO and not r.city:
				areas.append(r.area)
		areas.sort()
		var big: int = areas[int(areas.size() * 0.8)] if not areas.is_empty() else 0
		var mid: int = areas[int(areas.size() * 0.45)] if not areas.is_empty() else 0
		for r: LiteRegion in map.regions:
			if r.label == Vector2.ZERO or r.city:
				continue
			var away: Vector2 = (r.label - map.capital[1 - r.side]).normalized() if map.capital[1 - r.side] != Vector2.ZERO else Vector2.LEFT
			var rr: float = rng.randf_range(3.5, 5.0)
			if r.area >= big:
				rr = clampf(sqrt(float(r.area)) / 4.6, 9.0, 14.0)
			elif r.area >= mid:
				rr = clampf(sqrt(float(r.area)) / 6.5, 5.0, 8.0)
			var c: Vector2 = art(_fit(r, rr * LiteTerrain.ART))
			if r.area >= big:
				st.city(c, rr, away)
			elif r.area >= mid:
				st.town(c, rr, away)
			else:
				st.village(c, rr)
			# A village or two more in the bigger regions, away from the name.
			if r.area >= mid and not r.spots.is_empty():
				for k: int in (2 if r.area >= big else 1):
					var p: Vector2 = r.spots[rng.randi_range(0, r.spots.size() - 1)]
					if p.distance_to(r.label) > 40.0:
						st.village(art(p), rng.randf_range(3.5, 5.5))
		# The capitals: the biggest cities of all, their landmarks (see
		# LiteCmdCity) on a clear square in the middle.
		for side: int in 2:
			var cp: Vector2 = map.capital[side]
			if cp != Vector2.ZERO:
				var core: float = LiteCmdCity.RADIUS / LiteTerrain.ART
				var rr: float = 31.0
				var away: Vector2 = (cp - map.capital[1 - side]).normalized()
				st.keep_clear.clear()
				st.keep_clear.append([art(cp), core])
				st.city(art(cp), rr, away)
				st.keep_clear.clear()
				st.keep_clear.append([art(cp), rr + 1.0])
				st.suburbs(art(cp), rr + 1.0, rr + 9.0)
		st.settle_ground()
		# Lights over the countryside (farmsteads, crossings): the land between
		# the towns is not dark at night. Only lights: by day nothing shows.
		var land: int = 0
		for r: LiteRegion in map.regions:
			land += r.area
		for k: int in land / 320:
			var r: LiteRegion = map.regions[rng.randi_range(0, map.regions.size() - 1)]
			if r.spots.is_empty() or r.city:
				continue
			var p: Vector2 = r.spots[rng.randi_range(0, r.spots.size() - 1)] + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
			var q: Vector2i = Vector2i(art(p).round())
			st.lamp(q, 0.45 + rng.randf() * 0.4)
			if rng.randf() < 0.4:
				st.lamp(q + Vector2i(rng.randi_range(-2, 2), rng.randi_range(1, 2)), 0.35 + rng.randf() * 0.3)

	## Where a settlement of `reach` map units fits in region `r`: just under
	## its name if it fits there whole, else the nearest of the region's
	## spots (or above the name) where it does, clear of the name itself.
	func _fit(r: LiteRegion, reach: float) -> Vector2:
		# The same place the simulation keeps clear (LiteMap.built_up).
		return map.settle_spot(r, reach)

	func _settle(c: Vector2, rr: float, core: float) -> void:
		var r: int = ceili(rr)
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				var d: float = Vector2(dx, dy).length()
				if d > rr:
					continue
				var q: Vector2 = c + Vector2(dx, dy)
				if not inside(q) or not ours(q) or water(q):
					continue
				var px: Color = feat.get_pixelv(Vector2i(q))
				px.b = maxf(px.b, core * (1.0 - d / rr * 0.75))
				feat.set_pixelv(Vector2i(q), px)

	## Roads joining the towns (the shortest network over them all), each a
	## little crooked; a bridge where one crosses water.
	func roads() -> void:
		var nodes: Array[Vector2] = []
		for r: LiteRegion in map.regions:
			if r.label != Vector2.ZERO and r.area > 200:
				nodes.append(art(r.label + Vector2(0, 9)))
		for side: int in 2:
			if map.capital[side] != Vector2.ZERO:
				nodes.append(art(map.capital[side] + Vector2(0, 14)))
		if nodes.size() < 2:
			return
		# Prim's: from the first node out.
		var inn: Array[bool] = []
		inn.resize(nodes.size())
		inn.fill(false)
		inn[0] = true
		for k: int in nodes.size() - 1:
			var bi: int = -1
			var bj: int = -1
			var bd: float = INF
			for i: int in nodes.size():
				if not inn[i]:
					continue
				for j: int in nodes.size():
					if inn[j]:
						continue
					var d: float = nodes[i].distance_squared_to(nodes[j])
					if d < bd:
						bd = d
						bi = i
						bj = j
			if bj < 0:
				break
			inn[bj] = true
			_road(nodes[bi], nodes[bj])

	func _road(a: Vector2, b: Vector2) -> void:
		var mid: Vector2 = (a + b) * 0.5 + (b - a).orthogonal().normalized() * (b - a).length() * rng.randf_range(-0.12, 0.12)
		for seg: Array in [[a, mid], [mid, b]]:
			var p0: Vector2 = seg[0]
			var p1: Vector2 = seg[1]
			var n: int = int(p0.distance_to(p1) * 2.0) + 1
			for i: int in n + 1:
				var q: Vector2i = Vector2i((p0.lerp(p1, float(i) / n)).round())
				if not inside(Vector2(q)) or not ours(Vector2(q)):
					continue
				var px: Color = feat.get_pixelv(q)
				px.g = 1.0
				if px.r > 0.5:
					px.a = 1.0
				feat.set_pixelv(q, px)
				# Now and then a lamp along it (a petrol station, a crossing).
				if i % 9 == 0 and rng.randf() < 0.3 and px.r < 0.5:
					lights.set_pixelv(q + Vector2i(1, 0), Color(0.75, 0.62, 0.4, 0.6 if rng.randf() < 0.15 else 1.0))
