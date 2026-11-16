class_name LiteCmdView
extends LiteView
## The map in the Modern Military Command look (see LiteTheme): the war, a
## campaign operation and the campaign's front. It is the legacy LiteView in
## all it does: the same war, and the same trails, smoke, flames, blasts and
## fires, worked out and drawn the same way. What differs:
##
## - the land: a dark blue-grey base, friendly territory blue-grey, hostile
##   dark red, elevation as contour lines, thin sharp borders, a two-tone
##   frontier, a reference grid (lite_cmd_map.gdshader, lite_cmd_world.gdshader);
##   alerts as a tint and hatch over the territory, not in place of it;
## - names and province centres (LiteCmdLabels);
## - sites as NATO-style frames: friendly a blue rectangle, hostile a red
##   diamond, the site's own glyph inside, health and readiness beside it;
## - air defence: thin rings, weapon range solid (SAM) or dashed (guns), the
##   SAMs' wider detection range dotted, the enemy's known threat zones in red;
## - weapons coloured by side (hostile drones orange); ballistic missiles'
##   impact points marked; selection and objective brackets.

const FRIEND: Color = LiteTheme.BLUE
const HOSTILE: Color = LiteTheme.RED
const HOSTILE_DRONE: Color = Color("#F0904B")
const FRIEND_FILL: Color = Color("#0E1A28")
const HOSTILE_FILL: Color = Color("#22131A")
## A friendly site's frame (a rectangle) and a hostile one's (a diamond).
const RECT_PTS: PackedVector2Array = [Vector2(-8.5, -6.4), Vector2(8.5, -6.4), Vector2(8.5, 6.4), Vector2(-8.5, 6.4)]
const DIAMOND_PTS: PackedVector2Array = [Vector2(0, -9.2), Vector2(9.2, 0), Vector2(0, 9.2), Vector2(-9.2, 0)]

## Each region's state as shown (palette row 3), eased like its fill.
var _state: PackedColorArray = PackedColorArray()
## The districts' alerts as shown (see LiteSim.sub_alert), eased; and each
## district's province.
var _sub_pal: Image = null
var _sub_tex: ImageTexture = null
var _sub_shown: PackedFloat32Array = PackedFloat32Array()
var _sub_region: PackedInt32Array = PackedInt32Array()
var _labels: LiteCmdLabels = null
## What the information panel has pinned (LiteCmdUi sets them): a site, or a
## region (-1 for none).
var pinned: LiteBuilding = null
var pinned_region: int = -1

## Map units per screen pixel now (the map is scaled to fit its frame).
var px: float:
	get: return 1.0 / maxf(0.01, get_viewport().canvas_transform.x.x)

func build() -> void:
	var map_: LiteMap = map
	var img: Image = Image.create_from_data(LiteMap.RW, LiteMap.RH, false, Image.FORMAT_R8, map_.ids)
	_pal = Image.create_empty(256, 4, false, Image.FORMAT_RGBA8)
	_shown.resize(map_.regions.size())
	_state.resize(map_.regions.size())
	for i: int in _shown.size():
		_shown[i] = target(i)
		_state[i] = _state_of(i)
		_pal.set_pixel(i, 0, _shown[i])
		_pal.set_pixel(i, 1, Color(map_.regions[i].side, 0, 0, 1))
		_pal.set_pixel(i, 2, Color(i / 255.0, 0, 0, 1))
		_pal.set_pixel(i, 3, _state[i])
	_pal_tex = ImageTexture.create_from_image(_pal)
	# The land's elevation: one smooth field over the whole world round the
	# map, drawn as contour lines (no fine noise: an operational map's terrain).
	var extent: Vector2 = Vector2(LiteMap.W, LiteMap.H) + LiteWorld.PAD * 2.0
	var relief: ImageTexture = _noise(map_.seed * 7 + 11, 0.012, 3, extent / 2.0)
	# The illustrated terrain (see LiteTerrain), painted once for this map.
	var ids_tex: ImageTexture = ImageTexture.create_from_image(img)
	var terrain: Texture2D = LiteTerrain.make(map_, self, ids_tex)
	if map_.world != null:
		var wimg: Image = Image.create_from_data(LiteWorld.WW, LiteWorld.WH, false, Image.FORMAT_R8, map_.world.ids)
		var wmat:= ShaderMaterial.new()
		_world_mat = wmat
		wmat.shader = load("res://src/Lite/command/lite_cmd_world.gdshader") as Shader
		var wtex: ImageTexture = ImageTexture.create_from_image(wimg)
		wmat.set_shader_parameter("ids", wtex)
		wmat.set_shader_parameter("sea_col", LiteTheme.SEA)
		wmat.set_shader_parameter("land_col", LiteTheme.NEUTRAL_LAND)
		wmat.set_shader_parameter("line_col", Color("#2A3644"))
		wmat.set_shader_parameter("coast_col", Color("#2C3D4F"))
		wmat.set_shader_parameter("ours_col", LiteTheme.OUR_LAND.lerp(LiteTheme.NEUTRAL_LAND, 0.35))
		wmat.set_shader_parameter("theirs_col", LiteTheme.ENEMY_LAND.lerp(LiteTheme.NEUTRAL_LAND, 0.35))
		wmat.set_shader_parameter("soft", 2 if map_.towns.size() > 0 else 0)
		wmat.set_shader_parameter("relief", relief)
		wmat.set_shader_parameter("relief_origin", -LiteWorld.PAD)
		wmat.set_shader_parameter("relief_size", extent)
		wmat.set_shader_parameter("origin", -LiteWorld.PAD)
		wmat.set_shader_parameter("cell", float(LiteWorld.K))
		wmat.set_shader_parameter("grid_step", LiteCmdLabels.GRID)
		wmat.set_shader_parameter("grid_col", Color(0.45, 0.58, 0.7, 0.07))
		wmat.set_shader_parameter("terrain", terrain)
		wmat.set_shader_parameter("has_terrain", true)
		wmat.set_shader_parameter("terrain_origin", LiteTerrain.origin())
		wmat.set_shader_parameter("terrain_art", LiteTerrain.ART)
		var ws: Sprite2D = Sprite2D.new()
		ws.texture = wtex
		ws.centered = false
		ws.position = -LiteWorld.PAD
		ws.scale = Vector2(LiteWorld.K, LiteWorld.K)
		ws.material = wmat
		ws.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ws.show_behind_parent = true
		add_child(ws)
	var mat: ShaderMaterial = ShaderMaterial.new()
	_map_mat = mat
	_contest_dirty = true
	mat.shader = load("res://src/Lite/command/lite_cmd_map.gdshader") as Shader
	var ids: ImageTexture = ids_tex
	mat.set_shader_parameter("ids", ids)
	mat.set_shader_parameter("terrain", terrain)
	mat.set_shader_parameter("has_terrain", true)
	# A desert or a winter map shows more of its land under the countries' colours.
	var plain: bool = LiteBiome.climate(main.map) == LiteBiome.TEMPERATE
	mat.set_shader_parameter("wash", 0.21 if plain else 0.11)
	mat.set_shader_parameter("keep_sat", 0.75 if plain else 1.0)
	mat.set_shader_parameter("keep_contrast", 0.8 if plain else 0.95)
	mat.set_shader_parameter("terrain_origin", LiteTerrain.origin())
	mat.set_shader_parameter("terrain_art", LiteTerrain.ART)
	mat.set_shader_parameter("palette", _pal_tex)
	var subs: Image
	if map_.sub.size() == LiteMap.W * LiteMap.H:
		subs = Image.create_from_data(LiteMap.W, LiteMap.H, false, Image.FORMAT_R8, map_.sub)
	else:
		subs = Image.create_empty(LiteMap.W, LiteMap.H, false, Image.FORMAT_R8)
	mat.set_shader_parameter("subs", ImageTexture.create_from_image(subs))
	if not sim.sub_alert.is_empty():
		_sub_region.resize(256)
		_sub_region.fill(-1)
		for j: int in LiteMap.W * LiteMap.H:
			var d: int = map_.sub[j]
			if d != LiteMap.NONE and _sub_region[d] < 0 and map_.cell[j] != LiteMap.NONE:
				_sub_region[d] = map_.province(map_.cell[j])
		_sub_shown.resize(256)
		_sub_pal = Image.create_empty(256, 1, false, Image.FORMAT_RGBA8)
		_sub_tex = ImageTexture.create_from_image(_sub_pal)
		mat.set_shader_parameter("sub_alerts", _sub_tex)
		mat.set_shader_parameter("has_sub_alerts", true)
	if map_.world != null:
		mat.set_shader_parameter("world", ImageTexture.create_from_image(Image.create_from_data(LiteWorld.WW, LiteWorld.WH, false, Image.FORMAT_R8, map_.world.ids)))
		mat.set_shader_parameter("has_world", true)
		mat.set_shader_parameter("world_pad", LiteWorld.PAD)
		mat.set_shader_parameter("world_k", float(LiteWorld.K))
		mat.set_shader_parameter("per_unit", float(LiteMap.S))
	mat.set_shader_parameter("relief", relief)
	mat.set_shader_parameter("relief_origin", -LiteWorld.PAD)
	mat.set_shader_parameter("relief_size", extent)
	mat.set_shader_parameter("map_size", Vector2(LiteMap.W, LiteMap.H))
	mat.set_shader_parameter("grid_step", LiteCmdLabels.GRID)
	mat.set_shader_parameter("edge_col", Color("#3A4A5C"))
	mat.set_shader_parameter("coast_col", Color("#4A6178"))
	mat.set_shader_parameter("border_col", LiteTheme.MUTED)
	mat.set_shader_parameter("ours_line", Color("#4FA6DA"))
	mat.set_shader_parameter("theirs_line", Color("#D25A4F"))
	mat.set_shader_parameter("amber_col", LiteTheme.AMBER)
	mat.set_shader_parameter("red_col", LiteTheme.RED)
	mat.set_shader_parameter("select_col", LiteTheme.TEXT)
	mat.set_shader_parameter("grid_col", Color(0.62, 0.74, 0.86, 0.09))
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = ids
	sprite.centered = false
	sprite.scale = Vector2.ONE / LiteMap.S
	sprite.material = mat
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.show_behind_parent = true
	add_child(sprite)
	# The settlements' lights at night (LiteSettle), over the land, under
	# the names and the sites.
	if LiteTerrain.lights != null:
		var li: Image = LiteTerrain.lights
		var glow: Image = li.duplicate()
		glow.generate_mipmaps()
		_lights = Sprite2D.new()
		_lights.texture = ImageTexture.create_from_image(li)
		_lights.centered = false
		_lights.position = LiteTerrain.origin()
		_lights.scale = Vector2.ONE * LiteTerrain.ART
		_lights.show_behind_parent = true
		var lm:= ShaderMaterial.new()
		lm.shader = load("res://src/Lite/command/lite_lights.gdshader") as Shader
		lm.set_shader_parameter("px_tex", _lights.texture)
		lm.set_shader_parameter("glow_tex", ImageTexture.create_from_image(glow))
		lm.set_shader_parameter("origin", LiteTerrain.origin())
		lm.set_shader_parameter("art", LiteTerrain.ART)
		lm.set_shader_parameter("ids", ids_tex)
		_bo_img = Image.create_empty(256, 1, false, Image.FORMAT_RGF)
		_bo_tex = ImageTexture.create_from_image(_bo_img)
		lm.set_shader_parameter("blackout", _bo_tex)
		_lights.material = lm
		add_child(_lights)
	_labels = LiteCmdLabels.new()
	_labels.map = map_
	_labels.show_behind_parent = true
	add_child(_labels)
	_ranges = Node2D.new()
	_ranges.show_behind_parent = true
	_ranges.draw.connect(func() -> void:
		var t_perf: float = LitePerf.now
		_draw_ranges()
		LitePerf.add("draw ranges", t_perf))
	add_child(_ranges)
	# The sites as pixel sprites: over the map, its fills and frames, under
	# what flies.
	# The capitals as cities (see LiteCmdCity); moved over the sites below.
	_city_layer = Node2D.new()
	add_child(_city_layer)
	_cities.clear()
	_sites = Node2D.new()
	# Crisp pixels at any size (the sprites are drawn smaller than their own
	# pixels): sharp bilinear, see lite_sharp.gdshader.
	_sites.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var sharp:= ShaderMaterial.new()
	sharp.shader = load("res://src/Lite/command/lite_sharp.gdshader") as Shader
	_sites.material = sharp
	# Craters, under the sites.
	_scar_layer = Node2D.new()
	_scar_layer.draw.connect(func() -> void:
		var t_perf: float = LitePerf.now
		_draw_scars()
		LitePerf.add("draw scars", t_perf))
	add_child(_scar_layer)
	move_child(_scar_layer, _city_layer.get_index())
	_scars.clear()
	_sites.draw.connect(func() -> void:
		var t_perf: float = LitePerf.now
		_draw_sites()
		LitePerf.add("draw sites", t_perf))
	add_child(_sites)
	# Enemy forces on the move, as NATO symbols, their roads and rail lines.
	_units = Node2D.new()
	_units.draw.connect(func() -> void:
		var t_perf: float = LitePerf.now
		_draw_units()
		LitePerf.add("draw units", t_perf))
	add_child(_units)
	# The capitals over the sites and the units round them: a city always in
	# front (its craters stay under everything).
	move_child(_city_layer, get_child_count() - 1)
	# Impacts' and fires' light, over the land and the sites.
	_light_layer = Node2D.new()
	var lmat:= CanvasItemMaterial.new()
	lmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_light_layer.material = lmat
	_light_layer.draw.connect(func() -> void:
		var t_perf: float = LitePerf.now
		_draw_impact_light()
		LitePerf.add("draw impact_light", t_perf))
	add_child(_light_layer)
	# The weather over the land and the sites, under what flies (LiteEnv).
	_weather = ColorRect.new()
	_weather.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weather.position = -LiteWorld.PAD
	_weather.size = Vector2(LiteMap.W, LiteMap.H) + LiteWorld.PAD * 2.0
	var wm:= ShaderMaterial.new()
	wm.shader = load("res://src/Lite/command/lite_weather.gdshader") as Shader
	wm.set_shader_parameter("origin", -LiteWorld.PAD)
	wm.set_shader_parameter("extent", _weather.size)
	_weather.material = wm
	add_child(_weather)
	# Drones and cruise missiles, many at a time from one mesh each (see
	# LiteView._fill_flock), and their shadows (meshes 2 and 3).
	# Smoke, fire and trails in pixels, like the sprites; the particles on the
	# GPU (see LiteParticles.use_gpu), drawn under the effects layer (_top).
	LiteParticles.pixel = true
	var pmm:= MultiMesh.new()
	pmm.transform_format = MultiMesh.TRANSFORM_2D
	pmm.use_custom_data = true
	var pq:= QuadMesh.new()
	pq.size = Vector2(1, 1)
	pmm.mesh = pq
	pmm.instance_count = LiteParticles.MAX
	pmm.custom_aabb = AABB(Vector3(-5000, -5000, -1), Vector3(10000, 10000, 2))
	_parts_node = MultiMeshInstance2D.new()
	_parts_node.multimesh = pmm
	var pmat:= ShaderMaterial.new()
	pmat.shader = load("res://src/Lite/command/lite_parts.gdshader") as Shader
	_parts_node.material = pmat
	_parts.use_gpu(pmm)
	# Drones (0), cruise missiles (1) and recon drones (4) as pixel sprites
	# (assets/ui/weapons.png), tinted by side; their shadows (2, 3) as shapes.
	if WEAPONS == null:
		WEAPONS = load("res://assets/ui/weapons.png") as Texture2D
	_flock_n = PackedInt32Array([0, 0, 0, 0, 0, 0])
	for k: int in 6:
		var mm:= MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.custom_aabb = AABB(Vector3(-500, -500, -1), Vector3(LiteMap.W + 1000, LiteMap.H + 1000, 2))
		var node:= MultiMeshInstance2D.new()
		if k == 2 or k == 3:
			mm.mesh = LiteGlyphs.mesh(LiteGlyphs.DRONE_PTS if k == 2 else LiteGlyphs.CRUISE_PTS, WEAPON_SCALE, null)
			node.show_behind_parent = true
		else:
			var cell: int = [0, 2, -1, -1, 1, 4][k]
			# Pixel sprites drawn at about the size they are seen (one sprite
			# pixel a screen pixel at 1080p), each in a 32-pixel cell; smoothed
			# (with mipmaps) as they turn. The cell's size on the map, which
			# puts each across (its longest side, outline included): Shahed
			# 8.4 map units, cruise 11.9, recon 7.6 (2026-11-15, phase 4: 70%,
			# 90% and 70% of the 12, 13.2 and 10.8 before).
			# Drones (attack, recon, jet) at 70% of that since (user, 2026-11-15).
			var size: float = [11.76, 17.28, 0.0, 0.0, 11.3, 12.32][k]
			mm.mesh = _sprite_quad(cell, size / WEAPON_SCALE)
			node.texture = WEAPONS
			node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			# Behind it, the same sprite a little larger in a dark, see-through
			# tone: a thin backing that lifts it off busy terrain.
			var back:= MultiMesh.new()
			back.transform_format = MultiMesh.TRANSFORM_2D
			back.use_colors = true
			back.custom_aabb = mm.custom_aabb
			back.mesh = _sprite_quad(cell, size * 1.22 / WEAPON_SCALE)
			var bnode:= MultiMeshInstance2D.new()
			bnode.multimesh = back
			bnode.texture = WEAPONS
			bnode.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			bnode.modulate = Color(0.0, 0.0, 0.0, 0.55)
			add_child(bnode)
			_backing[k] = back
		node.multimesh = mm
		add_child(node)
		_flock.append(mm)
		_flock_buf.append(PackedFloat32Array())
	_top = Node2D.new()
	_top.draw.connect(func() -> void:
		var t_perf: float = LitePerf.now
		_draw_top()
		LitePerf.add("draw top", t_perf))
	if _parts_node != null:
		add_child(_parts_node)
	add_child(_top)
	# What falls from the sky, over everything on the map.
	_rain = LiteCmdRain.new()
	var wmap: LiteMap = main.map
	_rain.water_at = func(p: Vector2) -> bool: return _water(wmap, p)
	add_child(_rain)

## The lights of region `id` go out (out, on for a moment, out again, then
## back), `len` stretching how long they stay out: a strike there, or a
## power station lost (longer).
func blackout(id: int, len: float = 1.0) -> void:
	if _bo_img == null or id < 0 or id >= 256:
		return
	var c: Color = _bo_img.get_pixel(id, 0)
	# Not again while one is still under way.
	if c.g > 0.0 and _clock - c.r < 3.0 * c.g + 2.0:
		return
	_bo_img.set_pixel(id, 0, Color(_clock, len, 0, 1))
	_bo_dirty = true

## Whether region `id`'s lights are on now (1) or out (0), by its blackout
## (the same pattern as lite_lights.gdshader's).
func power_at(id: int) -> float:
	if _bo_img == null or id < 0 or id >= 256:
		return 1.0
	var c: Color = _bo_img.get_pixel(id, 0)
	if c.g <= 0.0:
		return 1.0
	var t: float = _clock - c.r
	var len: float = c.g
	if t < 0.0:
		return 1.0
	if t < 1.1 * len:
		return 0.0
	if t < 1.1 * len + 0.35:
		return 1.0
	if t < 2.4 * len + 0.35:
		return 0.0
	var u: float = t - (2.4 * len + 0.35)
	if u < 1.2:
		return (1.0 if fmod(u * 6.0, 1.0) >= 0.45 else 0.0) * u / 1.2
	return 1.0

## A new blast: a crater where it came down (on land).
func on_blast(f: LiteFx) -> void:
	var rid: int = main.map.region_at(f.a)
	if rid != LiteMap.NONE:
		blackout(rid, 2.5 if f.size >= 24.0 else 1.0)
	if _water(main.map, f.a):
		return
	_scars.append([f.a, f.size, randf() * 1000.0])
	if _scars.size() > MAX_SCARS:
		_scars.pop_front()
	_scar_layer.queue_redraw()

## The craters: a scorched patch, a dark pit, thrown earth round it, in the
## map's pixels; where several overlap, the ground is churned.
func _draw_scars() -> void:
	var a: float = LiteTerrain.ART
	for s: Array in _scars:
		var c: Vector2 = ((s[0] as Vector2) / a).floor() * a
		var r: int = clampi(int(float(s[1]) / 7.0), 1, 3)
		var sd: float = s[2]
		for y: int in range(-r - 1, r + 2):
			for x: int in range(-r - 1, r + 2):
				var d: float = Vector2(x, y).length()
				if d > r + 0.8:
					continue
				var h: float = absf(fmod(sin(sd + x * 12.9 + y * 78.2) * 43758.5, 1.0))
				var col: Color
				if d <= r * 0.45:
					col = Color(0.07, 0.06, 0.05, 0.85)
				elif d <= r:
					col = Color(0.16, 0.13, 0.10, 0.55) if h > 0.3 else Color(0.36, 0.30, 0.24, 0.5)
				else:
					if h < 0.55:
						continue
					col = Color(0.30, 0.26, 0.21, 0.35)
				_scar_layer.draw_rect(Rect2(c + Vector2(x, y) * a, Vector2(a, a)), col)

## The light of fresh blasts on the ground round them, and of fires: warm,
## brief, much stronger at night (by day it hardly shows).
func _draw_impact_light() -> void:
	var sim_: LiteSim = main.sim
	if sim_ == null:
		return
	var k: float = 0.25 + 0.75 * night
	for f: LiteFx in sim_.fx:
		if f.kind != LiteFxKind.BLAST or f.age > 1.2:
			continue
		var t: float = 1.0 - f.age / 1.2
		var r: float = f.size * 2.4
		_light_layer.draw_texture_rect(LiteCmdCity.soft(), Rect2(f.a - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(0.55, 0.32, 0.12, 0.8 * t * t * k))
	var now: float = sim_.time
	for f: Vector4 in _fires:
		var left: float = f.z - now
		if left <= 0.0:
			continue
		var fl: float = 0.8 + 0.2 * sin(_clock * 9.0 + f.x) * sin(_clock * 13.0 + f.y)
		var a: float = clampf(left / 8.0, 0.0, 1.0) * fl * night
		var fr: float = f.w * 1.6
		_light_layer.draw_texture_rect(LiteCmdCity.soft(), Rect2(Vector2(f.x, f.y) - Vector2(fr, fr), Vector2(fr, fr) * 2.0), false, Color(0.6, 0.28, 0.08, 0.6 * a))

## Whether map point `p` is open water (the sea round the countries).
static func _water(map_: LiteMap, p: Vector2) -> bool:
	if map_.region_at(p) != LiteMap.NONE:
		return false
	if map_.world == null:
		return true
	var x: int = int((p.x + LiteWorld.PAD.x) / LiteWorld.K)
	var y: int = int((p.y + LiteWorld.PAD.y) / LiteWorld.K)
	if x < 0 or y < 0 or x >= LiteWorld.WW or y >= LiteWorld.WH:
		return true
	return map_.world.ids[y * LiteWorld.WW + x] == LiteWorld.SEA

## Smooth noise, 0 to 1, as a texture `size` texels big (a texel is two map
## units): worked out once per map, natively (FastNoiseLite).
static func _noise(seed_: int, freq: float, octaves: int, size: Vector2) -> ImageTexture:
	var n:= FastNoiseLite.new()
	n.seed = seed_
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	var im: Image = n.get_image(int(size.x), int(size.y), false, false, true)
	return ImageTexture.create_from_image(im)

## The map was scaled anew (the panel folded or unfolded): names are drawn
## at a size in screen pixels.
func refit() -> void:
	if _labels != null:
		_labels.queue_redraw()
	_ranges_at = -1

## A region's fill: friendly blue-grey or hostile dark red, a shade apart
## from its neighbours; an operation's province lit a little, the region
## under the pointer a little lighter. Alerts are not in the fill (row 3).
func target(i: int) -> Color:
	var r: LiteRegion = main.map.regions[i]
	var c: Color = LiteTheme.OUR_LAND if r.side == 0 else LiteTheme.ENEMY_LAND
	var shade: float = float(posmod(i * 2654435761, 1000)) / 1000.0
	c = Color(c.r * (0.93 + 0.14 * shade), c.g * (0.93 + 0.14 * shade), c.b * (0.93 + 0.14 * shade))
	if r.city:
		c = c.lightened(0.06)
	var m: LiteMission = main.mission
	if m != null and m.result < 0 and main.map.focus.has(i):
		c = c.lerp(LiteTheme.OBJECTIVE, 0.07 + 0.03 * sin(_clock * 2.2))
	elif m == null and main.front_open:
		# The front: the regions that can be attacked a little lighter, the
		# one picked more, gently pulsing.
		var p: int = main.campaign.group_at(i) if main.campaign != null else main.map.province(i)
		if p == main.front_pick:
			c = c.lerp(LiteTheme.OBJECTIVE, 0.16 + 0.05 * sin(_clock * 2.6))
		elif main.front_options.has(p):
			c = c.lerp(LiteTheme.OBJECTIVE, 0.06)
	if i == main.hover_region:
		c = c.lightened(0.07)
	return c.lerp(LiteTheme.TEXT, 0.16 * _changed_pulse(i))

## A province that has just changed hands: its outline pulses for a few
## seconds (1 at the change, fading to 0), while its fill turns to its new side.
var _sides: PackedInt32Array = PackedInt32Array()
## The countries' material, and the contested band along the front (see
## _update_contested), worked out again whenever a province changes hands.
var _map_mat: ShaderMaterial = null
## The capitals' cities by their sites, and the layer they are drawn in.
var _cities: Dictionary = {}
var _city_layer: Node2D = null
var _lights: Sprite2D = null
## Each region's blackout (see blackout): when, and how long.
var _bo_img: Image = null
var _bo_tex: ImageTexture = null
var _bo_dirty: bool = false
var _hits_buf: PackedVector4Array = PackedVector4Array()
## How dark it is, 0 by day to 1 at night (see the day and night cycle).
var night: float = 0.0
var _world_mat: ShaderMaterial = null
var _weather: ColorRect = null
var _rain: LiteCmdRain = null
## Impacts' light on the ground round them (stronger at night), and fires'.
var _light_layer: Node2D = null
## Craters left by impacts: [where, size, seed], kept (the most recent
## MAX_SCARS), so repeated strikes scar an area; redrawn when one is added.
var _scars: Array = []
var _scar_layer: Node2D = null
const MAX_SCARS: int = 500
var _flash: float = 0.0
var _next_flash: float = 3.0

## The light of the hour and the weather on the land (LiteEnv): day light,
## a warm glow at dawn and dusk, a dark blue-grey night (never so dark the
## map can't be read), greyer under cloud, darker in a storm; and the
## weather's own layer, lightning in a storm.
func _update_env(dt: float) -> void:
	var sim_: LiteSim = main.sim
	if sim_ == null or sim_.env == null:
		return
	var env: LiteEnv = sim_.env
	night = env.night
	var a:= Vector3(1, 1, 1)
	a = a.lerp(Vector3(1.05, 0.9, 0.76), env.glow * 0.6)
	a = a.lerp(Vector3(0.46, 0.52, 0.66), night)
	var cl: float = env.amount(LiteEnv.CLOUDY)
	var fg: float = env.amount(LiteEnv.FOG)
	var st: float = env.amount(LiteEnv.STORM)
	var sd: float = env.amount(LiteEnv.SANDSTORM)
	var sn: float = env.amount(LiteEnv.SNOWSTORM)
	var wd: float = env.amount(LiteEnv.WINDY)
	a *= 1.0 - 0.08 * cl - 0.06 * fg - 0.22 * st - 0.12 * sd - 0.1 * sn
	a = a.lerp(Vector3(1.0, 0.86, 0.68) * a.length() / 1.732, sd * 0.35)
	a = a.lerp(Vector3(0.6, 0.64, 0.78) * a.length() / 1.732, st * 0.3)
	# Lightning now and then in a storm.
	_flash = maxf(0.0, _flash - dt * 4.0)
	if st > 0.6:
		_next_flash -= dt
		if _next_flash <= 0.0:
			_flash = 1.0
			_next_flash = randf_range(2.5, 7.0)
	var amb:= Vector3(a.x, a.y, a.z) + Vector3.ONE * _flash * 0.35
	if _map_mat != null:
		_map_mat.set_shader_parameter("ambient", amb)
	if _world_mat != null:
		_world_mat.set_shader_parameter("ambient", amb)
	if _lights != null:
		# By day the lights add nothing: not drawn at all (a full-map pass).
		_lights.visible = night > 0.01
	if _lights != null and _lights.visible:
		var lm: ShaderMaterial = _lights.material
		lm.set_shader_parameter("night", night)
		# The latest impacts, for the lights round them to flash and stutter.
		_hits_buf.resize(8)
		_hits_buf.fill(Vector4.ZERO)
		var n: int = 0
		for i: int in range(sim_.fx.size() - 1, -1, -1):
			var f: LiteFx = sim_.fx[i]
			if f.kind == LiteFxKind.BLAST and f.age < 3.0 and n < 8:
				_hits_buf[n] = Vector4(f.a.x, f.a.y, f.age, clampf(f.size / 15.0, 0.5, 1.6))
				n += 1
		lm.set_shader_parameter("hits", _hits_buf)
		lm.set_shader_parameter("now", _clock)
		if _bo_dirty:
			_bo_dirty = false
			_bo_tex.update(_bo_img)
	if _weather != null:
		# Clear skies: the weather overlay (a full-map pass) is off.
		_weather.visible = cl + st + fg + sd + sn + _flash > 0.005
	if _weather != null and _weather.visible:
		var wm: ShaderMaterial = _weather.material
		wm.set_shader_parameter("cloud", cl + st * 0.8)
		wm.set_shader_parameter("fog", fg)
		wm.set_shader_parameter("rain", st)
		wm.set_shader_parameter("flash", _flash)
		wm.set_shader_parameter("night", night)
		wm.set_shader_parameter("sand", sd)
		wm.set_shader_parameter("snow", sn)
	if _light_layer != null:
		_light_layer.queue_redraw()
	if _rain != null:
		_rain.rain = st
		_rain.snow = sn + 0.25 * cl * float(env.climate == LiteBiome.WINTER)
		_rain.sand = sd + 0.35 * wd * float(env.climate == LiteBiome.DESERT or env.climate == LiteBiome.STEPPE)
		_rain.wind = 9.0 + 30.0 * wd + 20.0 * sd
		# The map's area on screen, in map units.
		var vr: Rect2 = get_viewport_rect()
		var inv: Transform2D = get_global_transform_with_canvas().affine_inverse()
		_rain.view = Rect2(inv * vr.position, (inv * vr.end) - (inv * vr.position))
		_rain.step(dt)

## Each capital site gets its city (once); each city follows its capital's
## health, and smoke rises from its ruins.
func _update_cities(dt: float) -> void:
	var sim_: LiteSim = main.sim
	if sim_ == null or _city_layer == null:
		return
	for b: LiteBuilding in sim_.buildings:
		if b.kind != LiteKind.CAPITAL or _cities.has(b):
			continue
		var city:= LiteCmdCity.new()
		var enemy: Vector2 = main.map.capital[1 - b.side]
		var away: Vector2 = (b.pos - enemy).normalized() if enemy != Vector2.ZERO else Vector2.LEFT
		city.side_col = side_col(b.side)
		city.build(main.map, b, away, sim_.buildings)
		_city_layer.add_child(city)
		_cities[b] = city
	# Where the capitals were hit: each city takes the damage there.
	for h: Array in sim_.capital_hits:
		for b: LiteBuilding in _cities:
			if b.side == int(h[0]):
				(_cities[b] as LiteCmdCity).hit(h[1])
	sim_.capital_hits.clear()
	for b: LiteBuilding in _cities:
		var city: LiteCmdCity = _cities[b]
		city.visible = shown(b) or b.side == 0
		city.night = night
		city.power = power_at(main.map.region_at(b.pos))
		city.step(dt)
		if randf() < dt / 0.45:
			var p: Variant = city.a_ruin(randf())
			if p != null:
				_parts.chimney(p, true)
var _contest_dirty: bool = true
const CONTEST_CELL: int = 4

## How contested each spot is: 1 on the front line, falling to 0 at
## LiteRules.LAUNCH_STANDOFF from it (the band nothing may be launched from),
## on both sides; a cell every CONTEST_CELL map units. The map shader scorches
## and craters the ground by it.
func _update_contested() -> void:
	_contest_dirty = false
	if _map_mat == null:
		return
	var map_: LiteMap = main.map
	var gw: int = LiteMap.W / CONTEST_CELL + 1
	var gh: int = LiteMap.H / CONTEST_CELL + 1
	var side:= PackedInt32Array()
	side.resize(gw * gh)
	for y: int in gh:
		for x: int in gw:
			var mx: int = mini(x * CONTEST_CELL + CONTEST_CELL / 2, LiteMap.W - 1)
			var my: int = mini(y * CONTEST_CELL + CONTEST_CELL / 2, LiteMap.H - 1)
			var c: int = map_.cell[my * LiteMap.W + mx]
			side[y * gw + x] = -1 if c == LiteMap.NONE else map_.regions[c].side
	# Distance to the nearest cell of the other side: a two-pass chamfer from
	# the cells along the line.
	const BIG: float = 1e9
	var f:= PackedFloat32Array()
	f.resize(gw * gh)
	for y: int in gh:
		for x: int in gw:
			var i: int = y * gw + x
			var s: int = side[i]
			var edge: bool = false
			if s >= 0:
				for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var xx: int = x + o.x
					var yy: int = y + o.y
					if xx >= 0 and yy >= 0 and xx < gw and yy < gh:
						var t: int = side[yy * gw + xx]
						if t >= 0 and t != s:
							edge = true
			f[i] = 0.0 if edge else BIG
	var a: float = float(CONTEST_CELL)
	var d: float = a * 1.4142
	for y: int in gh:
		for x: int in gw:
			var i: int = y * gw + x
			var v: float = f[i]
			if x > 0: v = minf(v, f[i - 1] + a)
			if y > 0:
				v = minf(v, f[i - gw] + a)
				if x > 0: v = minf(v, f[i - gw - 1] + d)
				if x < gw - 1: v = minf(v, f[i - gw + 1] + d)
			f[i] = v
	for y: int in range(gh - 1, -1, -1):
		for x: int in range(gw - 1, -1, -1):
			var i: int = y * gw + x
			var v: float = f[i]
			if x < gw - 1: v = minf(v, f[i + 1] + a)
			if y < gh - 1:
				v = minf(v, f[i + gw] + a)
				if x < gw - 1: v = minf(v, f[i + gw + 1] + d)
				if x > 0: v = minf(v, f[i + gw - 1] + d)
			f[i] = v
	var data:= PackedByteArray()
	data.resize(gw * gh)
	var band: float = LiteRules.LAUNCH_STANDOFF
	for i: int in gw * gh:
		data[i] = 0 if side[i] < 0 else int(clampf(1.0 - f[i] / band, 0.0, 1.0) * 255.0)
	var img: Image = Image.create_from_data(gw, gh, false, Image.FORMAT_L8, data)
	_map_mat.set_shader_parameter("contested", ImageTexture.create_from_image(img))
	_map_mat.set_shader_parameter("contested_extent", Vector2(gw * CONTEST_CELL, gh * CONTEST_CELL))
	_map_mat.set_shader_parameter("has_contested", true)
var _changed_at: PackedFloat32Array = PackedFloat32Array()
const CHANGE_TIME: float = 3.0

func _changed_pulse(i: int) -> float:
	if i >= _changed_at.size():
		return 0.0
	var age: float = _clock - _changed_at[i]
	if age < 0.0 or age > CHANGE_TIME:
		return 0.0
	return (1.0 - age / CHANGE_TIME) * (0.65 + 0.35 * cos(age * 9.0))

func _note_side_changes() -> void:
	var regions: Array[LiteRegion] = main.map.regions
	if _sides.size() != regions.size():
		_sides.resize(regions.size())
		_changed_at.resize(regions.size())
		for i: int in regions.size():
			_sides[i] = regions[i].side
			_changed_at[i] = -99.0
		_contest_dirty = true
		return
	for i: int in regions.size():
		if regions[i].side != _sides[i]:
			_sides[i] = regions[i].side
			_changed_at[i] = _clock
			_contest_dirty = true

## Palette row 3: how strongly a region is under alert (the enemy's own
## alerts, from our strikes, at half strength), whether for missiles, a hit's
## flash, and whether it is selected, under the pointer or just taken.
func _state_of(i: int) -> Color:
	var sim_: LiteSim = main.sim
	var a: float = 0.0
	if sim_.alert[i]:
		a = 1.0 if main.map.regions[i].side == 0 else 0.2
	var sel: float = _changed_pulse(i)
	if i == pinned_region:
		sel = 1.0
	elif i == main.hover_region:
		sel = maxf(sel, 0.55)
	return Color(a, 1.0 if sim_.missile[i] else 0.0, clampf(sim_.region_flash[i], 0.0, 1.0), sel)

func _process(delta: float) -> void:
	var t_perf: float = LitePerf.now
	_process_timed(delta)
	LitePerf.add("view process", t_perf)
	if _parts_node != null:
		(_parts_node.material as ShaderMaterial).set_shader_parameter("now", _parts.clock)

func _process_timed(delta: float) -> void:
	var dt: float = delta
	_clock += dt
	var k: float = 1 - exp(-dt * 7.0)
	var ks: float = 1 - exp(-dt * 12.0)
	_note_side_changes()
	_update_env(dt)
	_update_cities(dt)
	if _contest_dirty:
		_update_contested()
	# (While a new map is being put up, the old palette may be the longer.)
	for i: int in mini(_shown.size(), mini(main.map.regions.size(), main.sim.alert.size())):
		_shown[i] = _shown[i].lerp(target(i), k)
		_pal.set_pixel(i, 0, _shown[i])
		var want: Color = _state_of(i)
		var s: Color = _state[i]
		# The alert eases in and out; its kind and the selection switch at once.
		_state[i] = Color(lerpf(s.r, want.r, k), want.g, want.b, lerpf(s.a, want.a, ks))
		_pal.set_pixel(i, 3, _state[i])
	_pal_tex.update(_pal)
	_update_sub_alerts(k)
	_track_motion(dt)
	_particles(dt)
	_turn_turrets(dt)
	_update_traces()
	queue_redraw()
	_top.queue_redraw()

## Each district's alert, eased in and out: amber for drones, red for
## missiles (a whole province red while a ballistic missile is coming down on
## it); the enemy's own districts, under our strikes, only faintly.
func _update_sub_alerts(k: float) -> void:
	if _sub_pal == null:
		return
	var sim_: LiteSim = main.sim
	for d: int in 256:
		var r: int = _sub_region[d]
		if r < 0:
			continue
		var level: int = sim_.sub_alert[d]
		if r < sim_.ballistic.size() and sim_.ballistic[r]:
			level = 2
		var want: float = 0.0
		if level > 0:
			want = 1.0 if main.map.regions[r].side == 0 else 0.2
		_sub_shown[d] = lerpf(_sub_shown[d], want, k)
		_sub_pal.set_pixel(d, 0, Color(_sub_shown[d], 1.0 if level == 2 else 0.0, 0.0, 1.0))
	_sub_tex.update(_sub_pal)

static func side_col(side: int) -> Color:
	return FRIEND if side == 0 else HOSTILE

static func cmd_weapon_color(w: LiteWeapon) -> Color:
	if w.side == 0:
		return FRIEND
	return HOSTILE_DRONE if w.arm == LiteArm.DRONE else HOSTILE

# --- Air defence coverage ----------------------------------------------------

## Thin rings with a faint fill, so overlapping coverage builds up: our SAMs'
## weapon range solid and their detection range (half as wide again) dotted;
## our guns' range dashed; the enemy's known sites as red threat zones, long
## dashes for SAMs and short for guns. Redrawn only when the sites change.
func _draw_ranges() -> void:
	var b: LiteBatch = _ranges_b
	b.begin(_ranges)
	if LiteSettings.ranges:
		for s: LiteBuilding in sim.buildings:
			if not s.alive or not (s.is_ad or s.is_gun) or not s.ready or not shown(s):
				continue
			var friend: bool = s.side == 0
			var col: Color = side_col(s.side)
			var r: float = sim.ad_range(s)
			if s.kind == LiteKind.SAM:
				b.disc(s.pos, r, Color(col, 0.04 if friend else 0.05), false)
				if friend:
					b.ring(s.pos, r, Color(col, 0.42), 1.0)
					_dashed_ring(b, s.pos, LiteSense.sees(sim, s, LiteArm.DRONE), Color(col, 0.16), 0.8, 1.6, 4.4)
				else:
					_dashed_ring(b, s.pos, r, Color(col, 0.5), 1.0, 9.0, 5.0)
			else:
				b.disc(s.pos, r, Color(col, 0.03), false)
				_dashed_ring(b, s.pos, r, Color(col, 0.36 if friend else 0.42), 0.9, 4.0, 4.0)
		# Radars: how far their picture reaches our air defence.
		for s: LiteBuilding in sim.buildings:
			if s.alive and s.ready and LiteKind.is_radar(s.kind) and shown(s):
				_dashed_ring(b, s.pos, LiteSense.link_range(sim, s), Color(side_col(s.side), 0.3), 0.8, 7.0, 5.0)
	b.flush()

var _ring_pts: PackedVector2Array = PackedVector2Array()

## One site's coverage, while it is selected or under the pointer: what its
## weapons reach (solid), what it sees (dotted), and for a radar how far its
## picture reaches air defence (dashed), with a thin line to each site it
## links. Ours fully; the enemy's as far as we know it.
func _coverage(b: LiteBatch, s: LiteBuilding) -> void:
	var sim_: LiteSim = sim
	var col: Color = side_col(s.side)
	var reach: float = sim_.ad_range(s) if LiteKind.shoots(s.kind) else 0.0
	if reach > 0.0:
		b.disc(s.pos, reach, Color(col, 0.05), false)
		b.ring(s.pos, reach, Color(col, 0.55), 1.0)
	if s.side == 0 or LiteKind.is_radar(s.kind):
		var see: float = LiteSense.sees(sim_, s, LiteArm.DRONE)
		_dashed_ring(b, s.pos, see, Color(col, 0.35), 0.8, 1.5, 4.0)
	if LiteKind.is_radar(s.kind):
		_dashed_ring(b, s.pos, LiteSense.link_range(sim_, s), Color(col, 0.4), 0.9, 7.0, 5.0)
		for o: LiteBuilding in sim_.buildings:
			if o.alive and o.link == s and shown(o):
				b.line(s.pos, o.pos, Color(col, 0.35), 0.8)
	elif LiteKind.shoots(s.kind) and s.link != null and s.link.alive and shown(s.link):
		b.line(s.pos, s.link.pos, Color(col, 0.35), 0.8)

func _dashed_ring(b: LiteBatch, c: Vector2, r: float, col: Color, width: float, dash: float, gap: float) -> void:
	var n: int = clampi(int(r * 0.5), 24, 120)
	_ring_pts.resize(n + 1)
	for i: int in n + 1:
		_ring_pts[i] = c + Vector2.from_angle(TAU * i / n) * r
	b.dashed(_ring_pts, col, width, dash, gap)

# --- The main layer ----------------------------------------------------------

## Whether a trail may be on screen: its ends or its middle in `vis`.
func _trace_seen(t: Trace, vis: Rect2) -> bool:
	var n: int = t.pts.size()
	if n == 0:
		return false
	return vis.has_point(t.pts[0]) or vis.has_point(t.pts[n - 1]) or vis.has_point(t.pts[n / 2]) or (t.live and vis.has_point(t.head))

func draw_all() -> void:
	var sim_: LiteSim = sim
	var b: LiteBatch = _b
	# Place names only on the campaign's front map: a war's or an
	# operation's map goes without them.
	if _labels != null and _labels.visible != main.front_open:
		_labels.visible = main.front_open
	b.begin(self)
	if LiteSettings.ranges:
		var key: int = _ranges_key()
		if key != _ranges_at:
			_ranges_at = key
			_ranges.queue_redraw()
		for s: LiteBuilding in sim_.buildings:
			if not s.alive or not s.ready or not shown(s):
				continue
			if s.fire_flash > 0.02 and (s.is_ad or s.is_gun):
				b.ring(s.pos, LiteRules.range(s.kind), Color(side_col(s.side), 0.35 * s.fire_flash), 1.0)
	elif _ranges_at != 0:
		_ranges_at = 0
		_ranges.queue_redraw()
	for f: LiteFx in sim_.fx:
		if f.kind == LiteFxKind.SCORCH:
			# Scorched ground, glowing at first: as in the legacy look.
			var fade: float = 1 - f.age / f.life
			b.disc(f.a, f.size * 0.75, Color(0.04, 0.04, 0.05, 0.22 * fade))
			b.disc(f.a, f.size * 0.4, Color(0.02, 0.02, 0.02, 0.45 * fade))
			if f.age < 10.0:
				var glow: float = (1 - f.age / 10.0) * (0.75 + 0.25 * sin(_clock * 11.0 + f.a.x))
				b.disc(f.a, f.size * 0.3, Color(1.0, 0.4, 0.1, 0.4 * glow))
	_parts.draw_smoke(b)
	# Enemy weapons we have lost track of: a ring round where we reckon each
	# is, wider the longer it is lost.
	for w: LiteWeapon in sim_.weapons:
		if w.alive and w.side != 0 and w.arm != LiteArm.BALLISTIC and w.seen[0] and w.lost[0] > 0.0 and sim_.winner < 0:
			_dashed_ring(b, vis_pos(w), 4.0 + w.doubt(0), Color(HOSTILE, 0.5 * sure(w)), 0.8, 2.0, 3.0)
	var now: float = sim_.time
	var tq: float = LitePerf.now
	# What is on screen (zoomed in at a gun, most of the map is not): only
	# that is drawn.
	var vr: Rect2 = get_viewport_rect()
	var inv: Transform2D = get_global_transform_with_canvas().affine_inverse()
	var vis:= Rect2(inv * vr.position, Vector2.ZERO).expand(inv * vr.end).grow(30.0)
	for t: Trace in _old_traces:
		if _trace_seen(t, vis):
			draw_trace(t, now)
	for t: Trace in _traces.values():
		if _trace_seen(t, vis):
			draw_trace(t, now)
	LitePerf.add("map traces", tq)
	tq = LitePerf.now
	# Our ballistic missiles: the point of impact, closing in as they come
	# down. (Where an enemy's will come down is not known.)
	for w: LiteWeapon in sim_.weapons:
		if not w.alive or w.arm != LiteArm.BALLISTIC or w.side != 0:
			continue
		var col: Color = cmd_weapon_color(w)
		var k: float = w.progress
		var r: float = 6.0 + 16.0 * (1.0 - k)
		b.ring(w.target, r, Color(col, 0.35 + 0.55 * k), 1.2)
		for q: int in 4:
			var d: Vector2 = Vector2.from_angle(q * PI / 2.0)
			b.line(w.target + d * (r - 3.0), w.target + d * (r + 3.5), Color(col, 0.7), 1.1)
		b.disc(w.target, 1.6, Color(col, 0.9))
	tq = LitePerf.now
	_fill_flock()
	LitePerf.add("map flock", tq)
	tq = LitePerf.now
	for w: LiteWeapon in sim_.weapons:
		if w.arm == LiteArm.BALLISTIC and shown_weapon(w):
			draw_shadow(w)
	_route_raids.clear()
	for w: LiteWeapon in sim_.weapons:
		if shown_weapon(w) and not _route_raids.has(w.raid):
			_route_raids[w.raid] = true
			draw_route(w)
	LitePerf.add("map routes", tq)
	tq = LitePerf.now
	for s: LiteBuilding in sim_.buildings:
		if shown(s) and vis.has_point(s.pos):
			draw_building(s)
	_sites.queue_redraw()
	if _units != null:
		_units.queue_redraw()
	LitePerf.add("map buildings", tq)
	tq = LitePerf.now
	for w: LiteWeapon in sim_.weapons:
		if shown_weapon(w) and vis.has_point(w.pos):
			draw_weapon(w)
	LitePerf.add("map weapons", tq)
	tq = LitePerf.now
	b.flush()
	LitePerf.add("map flush", tq)


## Drones and cruise missiles in their side's colour; no shadows.
func _fill_flock() -> void:
	_flock_n.fill(0)
	for w: LiteWeapon in sim.weapons:
		if w.arm == LiteArm.BALLISTIC or not shown_weapon(w):
			continue
		var at: Vector2 = vis_pos(w)
		var ang: float = vis_angle(w)
		# With their shadows on the ground below them, as in the legacy look.
		if w.arm == LiteArm.DRONE:
			# Scouts as recon drones (straight wings), the rest as attack drones.
			var mesh: int = 4 if w.raid != null and w.raid.scout else (5 if w.jet else 0)
			_put(mesh, at, ang + (0.0 if w.jet else sin(_clock * 5.0 + w.id * 1.7) * 0.08), Color(cmd_weapon_color(w), sure(w)))
			_put(2, at - LIFT * 5.0, ang, SHADOW, ARM_K[0])
		else:
			_put(1, at, ang, Color(cmd_weapon_color(w), sure(w)))
			_put(3, at - LIFT * 4.0, ang, SHADOW, ARM_K[1])
	for k: int in _flock.size():
		var mm: MultiMesh = _flock[k]
		if mm.instance_count > 0 and _flock_n[k] > 0:
			RenderingServer.multimesh_set_buffer(mm.get_rid(), _flock_buf[k])
		mm.visible_instance_count = _flock_n[k]
		var back: MultiMesh = _backing.get(k)
		if back != null:
			if back.instance_count != mm.instance_count:
				back.instance_count = mm.instance_count
			if mm.instance_count > 0 and _flock_n[k] > 0:
				RenderingServer.multimesh_set_buffer(back.get_rid(), _flock_buf[k])
			back.visible_instance_count = _flock_n[k]

## Our strikes' routes: a dashed blue line with chevrons pointing the way, the
## target crossed. (The enemy's routes stay hidden, as in the legacy look.)
func draw_route(w: LiteWeapon) -> void:
	if not LiteSettings.routes or w.side != 0:
		return
	var b: LiteBatch = _b
	_pts.clear()
	_pts.append(vis_pos(w))
	var path: PackedVector2Array = w.path
	for i: int in range(w.leg, path.size()):
		_pts.append(path[i])
	b.dashed(_pts, Color(FRIEND, 0.4), 1.0, 6, 5)
	_chevrons(b, _pts, Color(FRIEND, 0.55), 46.0)
	var t: Vector2 = w.target
	b.ring(t, 4.5, Color(FRIEND, 0.65), 1.0)
	b.line(t + Vector2(-7, 0), t + Vector2(7, 0), Color(FRIEND, 0.65), 1.0)
	b.line(t + Vector2(0, -7), t + Vector2(0, 7), Color(FRIEND, 0.65), 1.0)

## Small arrowheads every `spacing` map units along a path.
func _chevrons(b: LiteBatch, pts: Array[Vector2], col: Color, spacing: float) -> void:
	var run: float = spacing * 0.5
	for i: int in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var d: Vector2 = pts[i] - a
		var length: float = d.length()
		if length < 0.01:
			continue
		var u: Vector2 = d / length
		while run < length:
			var at: Vector2 = a + u * run
			var n: Vector2 = Vector2(-u.y, u.x)
			b.line(at - u * 3.5 + n * 3.0, at, col, 1.1)
			b.line(at - u * 3.5 - n * 3.0, at, col, 1.1)
			run += spacing
		run -= length

## The flying weapons' sprites (assets/ui/weapons.png: attack drone, recon
## drone, cruise missile, ballistic missile, 32 pixels each, nose to the
## right; see tools/weapon_sprites.py).
static var WEAPONS: Texture2D = null
const WEAPON_PX: int = 32
## The ballistic missile's cell on the map (times its draw scale, which has
## ARM_K in it): it puts the missile 12 map units long, 80% of the 15 before.
const BALLISTIC_SIZE: float = 17.45 / 0.8
## This frame's ballistic missiles, drawn as sprites with the sites: [where,
## heading, scale, colour].
var _ballistics: Array = []

## A square of `size` (before WEAPON_SCALE) showing weapon sprite `cell`.
static func _sprite_quad(cell: int, size: float) -> ArrayMesh:
	var h: float = size * 0.5
	# The sheet's cells across (it grows as weapons are added: 5 with the jet).
	var cells: float = float(WEAPONS.get_width()) / WEAPON_PX if WEAPONS != null else 5.0
	var u0: float = cell / cells
	var u1: float = (cell + 1) / cells
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1)])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m:= ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

func ballistic_body(w: LiteWeapon, at: Vector2, s: float, dir: Vector2) -> bool:
	_ballistics.append([at, dir.angle(), s, cmd_weapon_color(w)])
	return true

## The sites' sprites (assets/ui/sites.png, 16 pixels each in the order of
## LiteKind; see tools/site_sprites.py) and how big they are drawn.
static var SITES: Texture2D = null
## 16-pixel sprites, 12.8 map units across (phase 4, 2026-11-15: a fifth
## under the 16 before), drawn crisp at any size (lite_sharp.gdshader).
const SITE_SIZE: float = 18.5
const CAPITAL_SIZE: float = 16.8
## The weapons' dark backings (see build), by flock mesh.
var _backing: Dictionary = {}
var _sites: Node2D = null
var _units: Node2D = null
## The particles' MultiMesh (see LiteParticles.use_gpu).
var _parts_node: MultiMeshInstance2D = null

## Enemy forces on the move (LiteUnit): a train's rail line, a column's road
## ahead of it to the border (a cross where it would come over), the units
## as NATO symbols; a hidden launcher where it was last seen, a dashed ring
## and a question mark.
func _draw_units() -> void:
	var sim_: LiteSim = main.sim
	if sim_ == null:
		return
	var m: LiteMission = main.mission
	var t: float = Time.get_ticks_msec() / 1000.0
	if m != null and m.plot == LiteMission.PLOT_PORT and not m.targets.is_empty():
		# The quay: a pier from the terminal out into the water, its moorings.
		var from: Vector2 = m.targets[0].pos
		var to: Vector2 = m.objective + (m.objective - from).normalized() * 4.0
		_units.draw_line(from, to, Color(0.05, 0.06, 0.08, 0.9), 3.2)
		_units.draw_line(from, to, Color(0.55, 0.52, 0.46, 0.95), 2.0)
		var n: Vector2 = (to - from).normalized().orthogonal()
		_units.draw_line(to - n * 9.0, to + n * 9.0, Color(0.05, 0.06, 0.08, 0.9), 3.2)
		_units.draw_line(to - n * 9.0, to + n * 9.0, Color(0.55, 0.52, 0.46, 0.95), 2.0)
	for s: LiteBuilding in sim_.buildings:
		if s.kind != LiteKind.UNIT or s.route.size() < 2 or s.leader != null:
			continue
		if s.unit == LiteUnit.LOCO:
			# The rail line, the whole way: two rails and their sleepers.
			var rail: PackedVector2Array = s.route.slice(1)
			for i: int in range(1, rail.size()):
				var a: Vector2 = rail[i - 1]
				var b: Vector2 = rail[i]
				var n: Vector2 = (b - a).normalized().orthogonal()
				var steps: int = maxi(1, int(a.distance_to(b) / 2.2))
				for k: int in steps:
					var p: Vector2 = a.lerp(b, (k + 0.5) / steps)
					_units.draw_line(p - n * 1.7, p + n * 1.7, Color(0.3, 0.24, 0.18, 0.9), 0.6)
				_units.draw_line(a - n * 1.0, b - n * 1.0, Color(0.72, 0.72, 0.75, 0.95), 0.45)
				_units.draw_line(a + n * 1.0, b + n * 1.0, Color(0.72, 0.72, 0.75, 0.95), 0.45)
			# The front station at its end.
			var st: Vector2 = rail[rail.size() - 1]
			_units.draw_rect(Rect2(st - Vector2(3, 2), Vector2(6, 4)), Color(0.86, 0.3, 0.26, 0.9), false, 0.6)
		elif s.alive and s.unit != LiteUnit.LAUNCHER and not s.arrived:
			# The road ahead of a column, dashed, to where it would cross.
			var ahead: float = s.dist
			var end: float = s.route_len
			var step: float = 4.0
			var off: float = fmod(t * 3.0, step)
			var d: float = ahead + off
			while d < end - 1.0:
				var p0: Vector2 = LiteUnit.along(s.route, d)[0]
				var p1: Vector2 = LiteUnit.along(s.route, minf(end, d + step * 0.5))[0]
				_units.draw_line(p0, p1, Color(0.4, 0.65, 0.95, 0.55) if s.side == 0 else Color(0.95, 0.35, 0.3, 0.55), 0.7)
				d += step
			var x: Vector2 = s.route[s.route.size() - 1]
			var r: float = 3.2
			_units.draw_line(x + Vector2(-r, -r), x + Vector2(r, r), Color(0.95, 0.35, 0.3, 0.9), 0.9)
			_units.draw_line(x + Vector2(r, -r), x + Vector2(-r, r), Color(0.95, 0.35, 0.3, 0.9), 0.9)
	for s: LiteBuilding in sim_.buildings:
		if s.kind != LiteKind.UNIT or not s.alive:
			continue
		if s.unit == LiteUnit.LAUNCHER and not shown(s):
			# Where it was last seen: it has moved on since.
			var q: Vector2 = s.seen_pos
			for k: int in 12:
				var a0: float = k * TAU / 12.0 + t * 0.4
				_units.draw_arc(q, 12.0, a0, a0 + TAU / 24.0, 3, Color(0.95, 0.4, 0.32, 0.85), 0.9)
			LiteUnit.symbol(_units, q, LiteUnit.LAUNCHER, 7.2, 0.35)
			_units.draw_string(LiteGlyphs.black, q + Vector2(5.5, -5.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.55, 0.42, 0.95))
			continue
		if not shown(s):
			continue
		var hit: float = s.flash
		if s.unit == LiteUnit.LOCO or s.unit == LiteUnit.WAGON:
			# The train itself: dark boxes along the line, the engine longer.
			var dir: Vector2 = Vector2.from_angle(s.heading)
			var len: float = 8.9 if s.unit == LiteUnit.LOCO else 7.4
			var wid: float = 4.3
			var n: Vector2 = dir.orthogonal()
			var c: Vector2 = s.pos
			var box:= PackedVector2Array([c - dir * len * 0.5 - n * wid * 0.5, c + dir * len * 0.5 - n * wid * 0.5, c + dir * len * 0.5 + n * wid * 0.5, c - dir * len * 0.5 + n * wid * 0.5])
			_units.draw_colored_polygon(box, Color(0.3, 0.26, 0.22).lerp(Color(1, 0.8, 0.5), hit))
			box.append(box[0])
			_units.draw_polyline(box, Color(0.06, 0.05, 0.05), 0.35)
			if s.unit == LiteUnit.LOCO:
				LiteUnit.symbol(_units, c + Vector2(0, -12.0), LiteUnit.LOCO, 7.9, 1.0, hit)
			continue
		var k: float = 9.4
		LiteUnit.symbol(_units, s.pos, s.unit, k, 1.0, hit, s.side == 0)
		# Its health in small blocks under it.
		var cells: int = roundi(s.max_hp)
		for i: int in cells:
			var on: bool = i < roundi(maxf(0.0, s.hp))
			_units.draw_rect(Rect2(s.pos + Vector2(-cells * 1.2 + i * 2.4 + 0.2, k + 1.2), Vector2(2.0, 1.0)), Color(0.95, 0.4, 0.32) if on else Color(0.2, 0.2, 0.22))
		if s.unit == LiteUnit.LAUNCHER and main.sim.time < s.reveal_until:
			# Just fired: a pulsing ring while it gives itself away.
			var pr: float = 6.0 + 2.0 * sin(t * 8.0)
			_units.draw_arc(s.pos, pr, 0, TAU, 24, Color(1.0, 0.75, 0.3, 0.8), 0.6)

func _draw_sites() -> void:
	if SITES == null:
		SITES = load("res://assets/ui/sites.png") as Texture2D
	var sim_: LiteSim = main.sim
	if sim_ == null or SITES == null:
		return
	for s: LiteBuilding in sim_.buildings:
		if not s.alive or not shown(s):
			continue
		# A capital is its city (see LiteCmdCity), not a sprite; a unit on
		# the move a NATO symbol (see _draw_units).
		if s.kind == LiteKind.CAPITAL and _cities.has(s):
			continue
		if s.kind == LiteKind.UNIT:
			continue
		var sz: float = CAPITAL_SIZE if s.kind == LiteKind.CAPITAL else SITE_SIZE
		var tint: Color = Color.WHITE.lerp(LiteGlyphs.HIT_GLOW, s.flash * 0.7)
		if not s.ready:
			tint = Color(tint, 0.5)
		# Below half its health, the damaged sprite (the sheet's second row);
		# in the snow, the winter rows under them.
		var row: int = (16 if s.hp < s.max_hp * 0.5 else 0) + (32 if s.winter else 0)
		var r:= Rect2(s.pos - Vector2(sz, sz * 1.08) * 0.5, Vector2(sz, sz))
		# A refinery in the desert is an oil field.
		var cell: int = LiteKind.OILRIG if s.kind == LiteKind.REFINERY and s.biome == LiteBiome.DESERT else s.kind
		var src:= Rect2(cell * 16, row, 16, 16)
		# A thin dark outline round its silhouette and a short shadow down
		# and right: it stands off the terrain without a glow.
		var dark:= Color(0.02, 0.03, 0.05, 0.6 * tint.a)
		var drives: bool = s.kind == LiteKind.MOBILE or (s.kind == LiteKind.GUN and not LiteSim.classic_rules)
		if drives:
			_draw_vehicle(s, tint)
			continue
		if s.kind == LiteKind.SAM:
			sz = SAM_SIZE
			r = Rect2(s.pos - Vector2(sz, sz * 1.08) * 0.5, Vector2(sz, sz))
		_sites.draw_texture_rect_region(SITES, Rect2(r.position + Vector2(0.8, 1.0), r.size), src, Color(0, 0, 0, 0.35 * tint.a))
		for o: Vector2 in [Vector2(-0.65, 0), Vector2(0.65, 0), Vector2(0, -0.65), Vector2(0, 0.65)]:
			_sites.draw_texture_rect_region(SITES, Rect2(r.position + o, r.size), src, dark)
		_sites.draw_texture_rect_region(SITES, r, src, tint)
		# Its radar antenna turning on top (a bar that sweeps side to side),
		# still and dark when the radar is out.
		if s.kind == LiteKind.SAM or LiteKind.is_radar(s.kind):
			# A SAM's on its cab (the sprite's right end), clear of the
			# missiles; a long-range radar's wide array on top of its mast
			# (the sprite has it drawn still: this is it turning); a mobile
			# radar's panel on the truck.
			var k: float = sz / 16.0
			# A SAM's radar panel on top of its mast at the front (the sprite's right).
			var top: Vector2 = Vector2(r.position.x + 13.0 * k, r.position.y + 1.0 * k)
			var span: float = 3.6 * k
			if s.kind == LiteKind.RADAR:
				top = Vector2(r.get_center().x, r.position.y + 2.5 * k)
				span = 12.0 * k
			elif s.kind == LiteKind.MRADAR:
				top = Vector2(r.position.x + 9.0 * k, r.position.y + 3.5 * k)
				span = 6.0 * k
			if radar_on(s):
				var c: float = cos(_clock * (0.8 if s.kind == LiteKind.RADAR else 1.6) + s.id * 1.3)
				var w: float = maxf(0.6, absf(c) * span)
				var face: Color = Color(0.86, 0.9, 0.94, tint.a) if c > 0.0 else Color(0.5, 0.55, 0.6, tint.a)
				_sites.draw_rect(Rect2(top + Vector2(-w * 0.5, 0), Vector2(w, 1.0 * k)), face)
			elif s.kind == LiteKind.SAM:
				_sites.draw_rect(Rect2(top + Vector2(-1.5, 0), Vector2(3.0, 1.0)), Color(0.25, 0.25, 0.26, tint.a))
	# Ballistic missiles over the sites, under the drones.
	if WEAPONS != null:
		for b: Array in _ballistics:
			var sz2: float = BALLISTIC_SIZE * float(b[2])
			_sites.draw_set_transform(b[0], b[1], Vector2.ONE)
			var bs: float = sz2 * 1.2
			_sites.draw_texture_rect_region(WEAPONS, Rect2(Vector2(-bs, -bs) * 0.5, Vector2(bs, bs)), Rect2(3 * WEAPON_PX, 0, WEAPON_PX, WEAPON_PX), Color(0, 0, 0, 0.5))
			_sites.draw_texture_rect_region(WEAPONS, Rect2(Vector2(-sz2, -sz2) * 0.5, Vector2(sz2, sz2)), Rect2(3 * WEAPON_PX, 0, WEAPON_PX, WEAPON_PX), b[3])
		_sites.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_ballistics.clear()

## The driving AA guns side on (assets/ui/sites.png's GUN_SIDE and
## MOBILE_SIDE, see tools/site_sprites.py): the hull facing the way its gun
## points (mirrored when that is left), the barrels drawn from the mount
## turned to where it aims (to the pointer, at the player's gun).
const ARMOUR_SIZE: float = 15.0
const TRUCK_SIZE: float = 15.8
## The SAM, a fifth bigger than the armoured gun.
const SAM_SIZE: float = 18.0
## The sheet's cells for the hulls side on.
const GUN_SIDE: int = 16
const MOBILE_SIDE: int = 17

## The mount's place in its cell (facing right), in the cell's pixels.
static func _mount(truck: bool) -> Vector2:
	return Vector2(5.5, 5.5) if truck else Vector2(9.5, 8.5)

## The mount on the map: the hull faces the way the gun points.
static func _mount_at(s: LiteBuilding) -> Vector2:
	var truck: bool = s.kind == LiteKind.MOBILE
	var k: float = (TRUCK_SIZE if truck else ARMOUR_SIZE) / 16.0
	var o: Vector2 = (_mount(truck) - Vector2(8.0, 8.64)) * k
	if cos(s.turret) < 0.0:
		o.x = -o.x
	return s.pos + o

## The barrels' length on the map.
static func _barrel(s: LiteBuilding) -> float:
	var truck: bool = s.kind == LiteKind.MOBILE
	return (9.0 if truck else 7.5) * (TRUCK_SIZE if truck else ARMOUR_SIZE) / 16.0

func _draw_vehicle(s: LiteBuilding, tint: Color) -> void:
	var truck: bool = s.kind == LiteKind.MOBILE
	var sz: float = TRUCK_SIZE if truck else ARMOUR_SIZE
	var row: int = (16 if s.hp < s.max_hp * 0.5 else 0) + (32 if s.winter else 0)
	var src:= Rect2((MOBILE_SIDE if truck else GUN_SIDE) * 16, row, 16, 16)
	var r:= Rect2(s.pos - Vector2(sz, sz * 1.08) * 0.5, Vector2(sz, sz))
	var left: bool = cos(s.turret) < 0.0
	if left:
		_sites.draw_set_transform(Vector2(s.pos.x * 2.0, 0.0), 0.0, Vector2(-1, 1))
	var dark:= Color(0.02, 0.03, 0.05, 0.6 * tint.a)
	_sites.draw_texture_rect_region(SITES, Rect2(r.position + Vector2(0.8, 1.0), r.size), src, Color(0, 0, 0, 0.35 * tint.a))
	for o: Vector2 in [Vector2(-0.6, 0), Vector2(0.6, 0), Vector2(0, -0.6), Vector2(0, 0.6)]:
		_sites.draw_texture_rect_region(SITES, Rect2(r.position + o, r.size), src, dark)
	_sites.draw_texture_rect_region(SITES, r, src, tint)
	if left:
		_sites.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The barrels: a gun truck's one heavy machine gun, the armoured gun's
	# two cannons, from the mount to where it aims.
	var m: Vector2 = _mount_at(s)
	var d: Vector2 = Vector2.from_angle(s.turret)
	# Side on, an AA gun firing by itself always points up into the sky; at
	# the player's hands it points straight at the pointer.
	if not s.manual and d.y > -0.25:
		d = Vector2(1.0 if d.x >= 0.0 else -1.0, -0.25).normalized()
	var n: Vector2 = d.orthogonal()
	var length: float = _barrel(s)
	var offs: Array = [0.0] if truck else [-0.75, 0.75]
	var steel:= Color(0.66, 0.7, 0.74, tint.a)
	for o: float in offs:
		_sites.draw_line(m + n * o - d * 0.6, m + n * o + d * (length + 0.4), Color(0.02, 0.03, 0.05, 0.85 * tint.a), 1.3)
	for o: float in offs:
		_sites.draw_line(m + n * o, m + n * o + d * length, steel, 0.55)
	if s.pace > 1.0 and randf() < 0.25:
		_parts.dust(s.pos + Vector2(-signf(cos(s.heading)) * 5.0, 3.0))

## Where a driving gun's barrels end (for its fire, see LiteGunner).
static func muzzle(s: LiteBuilding) -> Vector2:
	return _mount_at(s) + Vector2.from_angle(s.turret) * _barrel(s)

## The turrets turn to where they last aimed, back to the way they drive
## after a while, at a turret's rate.
func _turn_turrets(dt: float) -> void:
	var sim_: LiteSim = main.sim
	for s: LiteBuilding in sim_.buildings:
		if not s.alive or not (s.kind == LiteKind.MOBILE or s.kind == LiteKind.GUN):
			continue
		# At rest the barrels stand raised forward, the way it drives (side
		# on, "forward" is left or right; never down the screen).
		var rest: float = -PI / 6.0 if cos(s.heading) >= 0.0 else -PI + PI / 6.0
		var want: float = s.aim_to if sim_.time - s.aim_time < 1.6 or s.manual else rest
		var d: float = wrapf(want - s.turret, -PI, PI)
		var rate: float = (9.0 if s.manual else 4.5) * dt
		s.turret += clampf(d, -rate, rate)

## Whether a site's radar is at work: built, not badly damaged, and (a SAM)
## not knocked out with the rest of its side's SAMs (see LiteSense).
func radar_on(s: LiteBuilding) -> bool:
	return LiteSense.radar_works(main.sim, s)

## A site as a pixel sprite (see _draw_sites) on a plate in its side's
## colour; under it its health (green, amber, red) when damaged, over a
## friendly SAM its missiles.
func draw_building(s: LiteBuilding) -> void:
	var b: LiteBatch = _b
	var friend: bool = s.side == 0
	var col: Color = side_col(s.side)
	var cap: bool = s.kind == LiteKind.CAPITAL
	var sc: float = 1.3 if cap else 1.0
	var p: Vector2 = s.pos
	var pts: PackedVector2Array = RECT_PTS if friend else DIAMOND_PTS
	var half_h: float = (6.4 if friend else 9.2) * sc
	if not s.alive:
		var since: float = main.sim.time - s.dead_at
		var a: float = clampf(1 - since / 30.0, 0, 1)
		if since < 20.0:
			var burn: float = 1 - since / 20.0
			for k: int in 3:
				var fl: float = 0.5 + 0.5 * sin(_clock * (9.0 + k * 4.0) + p.x * 0.7 + k * 2.1)
				var off: Vector2 = Vector2(cos(k * 2.1 + p.y), sin(k * 2.1 + p.x)) * 3.0
				b.disc(p + off, (3.0 + 2.0 * fl) * burn + 1.0, Color(1.0, 0.45 + 0.3 * fl, 0.12, 0.45 * burn * fl))
		_outline(b, pts, p, sc, Color(LiteTheme.NEUTRAL, 0.7 * a), 1.0)
		var x: Color = Color(LiteTheme.MUTED, 0.85 * a)
		b.line(p + Vector2(-4, -4), p + Vector2(4, 4), x, 1.3)
		b.line(p + Vector2(4, -4), p + Vector2(-4, 4), x, 1.3)
		return
	# A soft dark halo lifts it off the terrain and the alert hatching; a
	# plate in its side's colour under the sprite says whose it is.
	var sz: float = CAPITAL_SIZE if cap else SITE_SIZE
	var pw: float = sz * 0.42
	var py: float = p.y + sz * 0.36
	if cap and _cities.has(s):
		# The city is the capital; its health bar under its middle.
		py = p.y + LiteCmdCity.RADIUS * 0.55
	else:
		b.disc(p, sz * 0.55, Color(LiteTheme.BG, 0.18))
		var pc: Color = Color(col, 0.95 if s.ready else 0.45)
		b.rect(Rect2(p.x - pw, py - 1.6, pw * 2.0, 3.2), pc)
		b.disc(Vector2(p.x - pw, py), 1.6, pc)
		b.disc(Vector2(p.x + pw, py), 1.6, pc)
	var below: float = py + 3.4
	half_h = sz * 0.5
	if not s.ready:
		# Under construction: how far along, as a bar.
		var w: float = 16.0
		var k: float = clampf(1 - s.build / s.build_total, 0.0, 1.0)
		b.rect(Rect2(p.x - w / 2, below, w, 2.2), Color(0, 0, 0, 0.6))
		b.rect(Rect2(p.x - w / 2, below, w * k, 2.2), Color(col, 0.9))
		return
	# A SAM's or a radar's search radar at work: a short, faint sweep turning
	# slowly round it, the beam's arc and a tail fading behind it. Still and
	# dark when it is out of action (damaged, or the side's SAMs knocked out).
	if (s.kind == LiteKind.SAM or LiteKind.is_radar(s.kind)) and radar_on(s):
		var big: bool = s.kind == LiteKind.RADAR
		var ang: float = _clock * (0.8 if big else 1.1) + s.id * 1.3
		var rr: float = 20.0 if big else (16.0 if s.kind == LiteKind.MRADAR else 12.0)
		var r0: float = 8.0
		var beam: Color = col.lightened(0.45)
		var fade: float = 1.0 - night * 0.2
		for j: int in 6:
			var a0: float = ang - j * 0.09
			var a: float = (0.22 - j * 0.035) * fade
			b.line(p + Vector2.from_angle(a0) * r0, p + Vector2.from_angle(a0) * rr, Color(beam, a), 0.8)
		b.ring(p, rr, Color(beam, 0.16 * fade), 0.7, ang - 0.5, ang)
		if LiteKind.is_radar(s.kind):
			# Its blip: a contact painted where the sweep has just passed.
			b.ring(p, rr, Color(beam, 0.06), 0.6)
	elif LiteKind.is_radar(s.kind) and s.ready:
		# Out of action: a dim, broken ring.
		_dashed_ring(b, p, 12.0, Color(LiteTheme.NEUTRAL, 0.45), 0.8, 2.0, 3.0)
	# At night, small lights: a red beacon blinking on military sites, a warm
	# glow from a factory's windows.
	if night > 0.2 and not cap:
		var la: float = (night - 0.2) / 0.8
		if s.kind == LiteKind.FACTORY:
			b.rect(Rect2(p.x - 3.0, p.y - 1.0, 6.0, 1.6), Color(1.0, 0.78, 0.4, 0.55 * la))
		elif fmod(_clock + s.id * 0.37, 1.6) < 0.25:
			b.rect(Rect2(p.x - 0.7, p.y - half_h - 1.6, 1.4, 1.4), Color(1.0, 0.25, 0.2, 0.95 * la))
	if s.kind == LiteKind.SAM and friend:
		var rk: int = main.sim.rack[s.side]
		for i: int in rk:
			var x0: float = p.x + (i - (rk - 1) / 2.0) * 3.2
			b.rect(Rect2(x0 - 1.1, p.y - half_h - 4.6, 2.2, 2.6), LiteTheme.TEXT if i < s.ammo else Color(LiteTheme.TEXT, 0.18))
	if (cap and LiteSim.classic_rules) or (not cap and s.hp < s.max_hp):
		var w: float = 26.0 if cap else 16.0
		var f: float = clampf(maxf(0.0, s.hp) / s.max_hp, 0.0, 1.0)
		var hc: Color = LiteTheme.GREEN if f > 0.66 else (LiteTheme.AMBER if f > 0.33 else LiteTheme.RED)
		b.rect(Rect2(p.x - w / 2 - 0.5, below - 0.5, w + 1, 3.2), Color(0, 0, 0, 0.6))
		b.rect(Rect2(p.x - w / 2, below, w * f, 2.2), hc)

func _outline(b: LiteBatch, pts: PackedVector2Array, c: Vector2, s: float, col: Color, width: float) -> void:
	var n: int = pts.size()
	for i: int in n:
		b.line(c + pts[i] * s, c + pts[(i + 1) % n] * s, col, width)

# --- The layer over the weapons ------------------------------------------------

func _draw_top() -> void:
	var sim_: LiteSim = sim
	var now: float = sim_.time
	var main_b: LiteBatch = _b
	_b = _top_b
	var b: LiteBatch = _b
	b.begin(_top)
	for i: LiteInterceptor in sim_.interceptors:
		if i.alive:
			draw_interceptor(i)
	var tq: float = LitePerf.now
	for f: LiteFx in sim_.fx:
		draw_fx(f)
	LitePerf.add("top fx", tq)
	tq = LitePerf.now
	for f: Vector4 in _fires:
		var left: float = f.z - now
		if left > 0.0:
			var fl: float = 0.8 + 0.2 * sin(_clock * 9.0 + f.x) * sin(_clock * 13.0 + f.y)
			b.puff(Vector2(f.x, f.y), f.w * 1.6, Color(1.0, 0.45, 0.12, 0.28 * clampf(left / 12.0, 0.2, 1.0) * fl))
	LitePerf.add("top fires", tq)
	tq = LitePerf.now
	_parts.draw_fire(b, _clock)
	LitePerf.add("top parts", tq)
	tq = LitePerf.now
	# An operation's targets: white corner brackets round each one still
	# standing; a convoy's in amber.
	var m: LiteMission = main.mission
	if m != null and m.result < 0:
		for t: LiteBuilding in m.targets:
			if t.alive and shown(t):
				var r: float = (17.0 if t.kind == LiteKind.CAPITAL else 13.0) + 0.8 * sin(_clock * 3.0)
				_brackets(b, t.pos, r, Color(LiteTheme.OBJECTIVE, 0.9), 1.2)
		if m.convoy != null and m.convoy.alive:
			_brackets(b, m.convoy.pos, 14.0 + 1.5 * sin(_clock * 6.0), Color(LiteTheme.AMBER, 0.95), 1.4)
	# The site under the pointer, and the one pinned (described in the tooltip).
	var hb: LiteBuilding = main.hover_building
	if hb != null and hb != pinned:
		_brackets(b, hb.pos, 12.5, Color(LiteTheme.TEXT, 0.75), 1.0)
	# Jammers' reach: drones flying into it are often lost.
	for jb: LiteBuilding in sim_.buildings:
		if jb.alive and jb.kind == LiteKind.JAMMER and shown(jb):
			var jc: Color = side_col(jb.side)
			b.ring(jb.pos, LiteRules.JAMMER_RANGE, Color(jc, 0.30 + 0.12 * sin(_clock * 4.0)), 1.3)
			b.ring(jb.pos, LiteRules.JAMMER_RANGE * (0.35 + 0.65 * fmod(_clock * 0.5, 1.0)), Color(jc, 0.18 * (1.0 - fmod(_clock * 0.5, 1.0))), 1.0)
	if pinned != null and pinned.alive and shown(pinned):
		_brackets(b, pinned.pos, 14.0, FRIEND, 1.5)
		b.ring(pinned.pos, 18.0 + 2.0 * sin(_clock * 3.0), Color(FRIEND, 0.25), 1.0)
		_coverage(b, pinned)
	elif hb != null and hb.alive and shown(hb):
		_coverage(b, hb)
	LitePerf.add("top marks", tq)
	tq = LitePerf.now
	b.flush()
	LitePerf.add("top flush", tq)
	_b = main_b
	var tx: float = px
	# No name tag under the capitals (it covered the sites round them): their
	# health is in the top bar.
	_draw_front(tx)
	if m != null and m.result < 0:
		var sz2: int = maxi(5, roundi(8.0 * tx))
		for t: LiteBuilding in m.targets:
			if t.alive and shown(t) and t.kind != LiteKind.UNIT:
				var r2: float = (17.0 if t.kind == LiteKind.CAPITAL else 13.0)
				_top.draw_string(LiteGlyphs.bold, t.pos + Vector2(-r2, -r2 - 2.0), "OBJ", HORIZONTAL_ALIGNMENT_LEFT, -1, sz2, Color(LiteTheme.OBJECTIVE, 0.85))
	_draw_nuke()
	draw_tool()

## The bomb's light: the whole screen white for a moment, fading; a white-hot
## dome where it went off, swelling and cooling; a ring racing out.
func _draw_nuke() -> void:
	var age: float = _clock - _nuke_at
	if age < 0.0 or age > 6.0:
		return
	for f: LiteFx in main.sim.fx:
		if f.kind != LiteFxKind.NUKE:
			continue
		var k: float = clampf(age / 6.0, 0.0, 1.0)
		var r: float = f.size * (0.25 + 0.45 * sqrt(k))
		_top.draw_circle(f.a, r * 1.6, Color(1.0, 0.55, 0.2, 0.25 * (1.0 - k)))
		_top.draw_circle(f.a, r, Color(1.0, 0.85 - 0.4 * k, 0.6 - 0.45 * k, 0.75 * (1.0 - k)))
		_top.draw_arc(f.a, f.size * (0.3 + 3.0 * minf(1.0, age / 1.6)), 0, TAU, 96, Color(1, 0.95, 0.85, 0.7 * maxf(0.0, 1.0 - age / 1.6)), 3.0, true)
	if age < 1.6:
		var fl: float = 1.0 - age / 1.6
		var vr: Rect2 = get_viewport_rect()
		var inv: Transform2D = get_global_transform_with_canvas().affine_inverse()
		_top.draw_rect(Rect2(inv * vr.position, Vector2.ZERO).expand(inv * vr.end), Color(1, 0.98, 0.92, 0.95 * fl * fl))

## The effects as in the legacy look; an interception also leaves a cross in
## the shooter's colour where the threat was killed ("track terminated"),
## opening out and fading as the burst does.
func draw_fx(f: LiteFx) -> void:
	super.draw_fx(f)
	if f.kind == LiteFxKind.POP:
		var t: float = clampf(f.age / f.life, 0.0, 1.0)
		var at: Vector2 = f.a + f.b
		var r: float = 3.5 + 4.0 * t
		var col: Color = Color(side_col(f.side), 0.95 * (1.0 - t))
		_b.line(at + Vector2(-r, -r), at + Vector2(r, r), col, 1.3)
		_b.line(at + Vector2(r, -r), at + Vector2(-r, r), col, 1.3)

## On the front: a badge over each region that can be attacked (or must be
## held), showing what is there; the one picked ringed brighter; the enemy
## capital's with its defences.
func _draw_front(tx: float) -> void:
	if not main.front_open or main.campaign == null:
		return
	# What crosses the front (see LiteView._front_life).
	for f: Array in flyers:
		var at: Vector2 = flyer_pos(f)
		# Facing along its curved way (where it is going next), not the
		# straight line, with the slight sway of a drone in the wind.
		var ahead: Array = f.duplicate()
		ahead[2] = float(f[2]) + 0.05
		var dir: Vector2 = flyer_pos(ahead) - at
		var drone: bool = int(f[5]) == LiteArm.DRONE
		var ang: float = dir.angle() + (sin(_clock * 5.0 + float(f[3]) * 7.0) * 0.08 if drone else 0.0)
		var col: Color = side_col(int(f[4]))
		if int(f[4]) == 1 and drone:
			col = HOSTILE_DRONE
		# The same sprites as in an operation (both sides' drones Shaheds),
		# a little bigger on the strategic map, their shadow on the ground.
		var cell: int = 0 if drone else 2
		var sz: float = (16.8 * 0.7 if drone else 17.28) * 1.3
		var src:= Rect2(cell * WEAPON_PX, 0, WEAPON_PX, WEAPON_PX)
		_top.draw_set_transform(at - LIFT * 6.0, ang, Vector2.ONE * 0.9)
		_top.draw_texture_rect_region(WEAPONS, Rect2(Vector2(-sz, -sz) * 0.5, Vector2(sz, sz)), src, Color(0, 0, 0, 0.3))
		_top.draw_set_transform(at, ang, Vector2.ONE)
		_top.draw_texture_rect_region(WEAPONS, Rect2(Vector2(-sz, -sz) * 0.61, Vector2(sz, sz) * 1.22), src, Color(0, 0, 0, 0.55))
		_top.draw_texture_rect_region(WEAPONS, Rect2(Vector2(-sz, -sz) * 0.5, Vector2(sz, sz)), src, col)
		if drone:
			# The pusher propeller spinning behind it.
			var spin: float = absf(sin(_clock * 37.0 + float(f[3]) * 13.0))
			_top.draw_line(Vector2(-sz * 0.42, -2.1 * spin), Vector2(-sz * 0.42, 2.1 * spin), Color(0.9, 0.92, 0.96, 0.6), 0.6)
		else:
			# A jet's exhaust.
			_top.draw_line(Vector2(-sz * 0.45, 0), Vector2(-sz * 0.75, 0), Color(1.0, 0.75, 0.4, 0.7), 1.4)
		_top.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_front_state(tx)
	for id: int in main.front_options:
		var r: LiteRegion = main.map.regions[int(main.front_labels.get(id, id))]
		var at: Vector2 = r.label + Vector2(0, -19)
		var cap: bool = id == main.campaign.group_at(main.map.capital_province(1))
		var pm: LiteMission = main.campaign.preview(main.map, id)
		var glyph: int
		if main.map.regions[id].side == 0:
			glyph = LiteGlyph.SAM
		elif cap:
			glyph = LiteGlyph.CAPITAL
		else:
			glyph = LiteGlyphs.of(LiteMission.target_kinds(main.campaign.character(id))[0])
		var picked: bool = id == main.front_pick
		var col: Color = FRIEND if main.map.regions[id].side == 0 else HOSTILE
		_top.draw_circle(at, 10.0, Color(LiteTheme.BG, 0.92), true, -1, true)
		_top.draw_arc(at, 10.0, 0, TAU, 32, col if picked else Color(col, 0.6), 1.8 if picked else 1.2, true)
		if picked:
			_top.draw_arc(at, 13.5 + sin(_clock * 3.0), 0, TAU, 32, Color(LiteTheme.OBJECTIVE, 0.5), 1.0, true)
			_draw_plan(pm, id)
		# Forces on the move: their NATO symbol on the badge.
		var ut: int = PLAN_UNIT.get(pm.plot, -1)
		if ut >= 0:
			LiteUnit.symbol(_top, at, ut, 5.2, 1.0, 0.0, pm.plot == LiteMission.PLOT_EVAC)
		else:
			LiteGlyphs.draw_ci(_top, glyph, at, 0.8, LiteTheme.TEXT)
		if cap:
			_top.draw_string(LiteGlyphs.bold, at + Vector2(14, 4), "×%d" % main.campaign.capital_defence(main.map), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(6, roundi(11.0 * tx)), LiteTheme.TEXT)

## The unit on an option's badge, by its plot.
const PLAN_UNIT: Dictionary = {
	LiteMission.PLOT_COLUMN: LiteUnit.ARMOUR, LiteMission.PLOT_TRAIN: LiteUnit.LOCO,
	LiteMission.PLOT_HUNT: LiteUnit.LAUNCHER, LiteMission.PLOT_ASSAULT: LiteUnit.ARMOUR,
	LiteMission.PLOT_EVAC: LiteUnit.CONVOY, LiteMission.PLOT_PORT: LiteUnit.TANKER,
	LiteMission.PLOT_GRID: LiteUnit.CREW, LiteMission.PLOT_DEPOT: LiteUnit.SUPPLY,
}

## The plan of the operation picked on the front, drawn on the map: our
## forces' thrust in blue, the enemy's moves in red, as the operation's plot
## has them (armour coming up from the rear, a train on its line, launchers
## hidden in the woods, an assault on our town, our convoy's road out, a raid
## on our capital, the converging attack on theirs).
func _draw_plan(m: LiteMission, g: int) -> void:
	var c: LiteCampaign = main.campaign
	var map_: LiteMap = main.map
	var target: Vector2 = map_.regions[int(main.front_labels.get(g, g))].label
	var members: Array[int] = c.group(g)
	# Neighbouring regions outside the group: ours and theirs.
	var ours: Array[Vector2] = []
	var theirs: Array[Vector2] = []
	for id: int in members:
		for n: int in map_.regions[id].neighbors:
			if members.has(n) or map_.regions[n].label == Vector2.ZERO:
				continue
			if map_.regions[n].side == 0:
				ours.append(map_.regions[n].label)
			else:
				theirs.append(map_.regions[n].label)
	# The nearest of ours, the farthest of theirs from our capital first.
	ours.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(target) < b.distance_to(target))
	theirs.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(map_.capital[0]) > b.distance_to(map_.capital[0]))
	var t: float = _clock
	match m.plot:
		LiteMission.PLOT_COLUMN:
			for k: int in mini(2, theirs.size()):
				_plan_arrow(theirs[k], target, HOSTILE, 0.25 * (1 if k == 0 else -1))
				LiteUnit.symbol(_top, theirs[k], LiteUnit.ARMOUR, 5.5)
			if not ours.is_empty():
				_plan_arrow(ours[0], target.lerp(ours[0], 0.25), FRIEND, 0.15)
		LiteMission.PLOT_TRAIN:
			var from: Vector2 = theirs[0] if not theirs.is_empty() else map_.capital[1]
			# The rail line, sleepers and all, the train on it.
			var d: Vector2 = target - from
			var n: Vector2 = d.normalized().orthogonal()
			_top.draw_line(from + n * 1.4, target + n * 1.4, Color(HOSTILE, 0.75), 1.0, true)
			_top.draw_line(from - n * 1.4, target - n * 1.4, Color(HOSTILE, 0.75), 1.0, true)
			var steps: int = int(d.length() / 5.0)
			for i: int in steps:
				var p: Vector2 = from + d * (float(i) / steps)
				_top.draw_line(p - n * 2.6, p + n * 2.6, Color(HOSTILE, 0.5), 0.8, true)
			var u: float = fmod(t * 0.08, 1.0)
			LiteUnit.symbol(_top, from.lerp(target, u), LiteUnit.LOCO, 5.5)
			if not ours.is_empty():
				_plan_arrow(ours[0], target.lerp(ours[0], 0.3), FRIEND, 0.15)
		LiteMission.PLOT_HUNT:
			for k: int in 3:
				var p: Vector2 = target + Vector2.from_angle(k * 2.1 + 0.4) * 22.0
				LiteUnit.symbol(_top, p, LiteUnit.LAUNCHER, 4.6, 0.6 + 0.4 * absf(sin(t * 2.0 + k)))
				_top.draw_string(LiteGlyphs.black, p + Vector2(5, -5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(HOSTILE, 0.9))
			if not ours.is_empty():
				_plan_arrow(target, ours[0], HOSTILE, 0.3, true)
				_plan_arrow(ours[0], target.lerp(ours[0], 0.3), FRIEND, 0.15)
		LiteMission.PLOT_ASSAULT:
			for k: int in mini(3, theirs.size()):
				_plan_arrow(theirs[k], target, HOSTILE, 0.2 * (k - 1))
				LiteUnit.symbol(_top, theirs[k], LiteUnit.ARMOUR, 5.5)
			_top.draw_arc(target, 16.0 + sin(t * 3.0), 0, TAU, 40, Color(FRIEND, 0.8), 2.0, true)
		LiteMission.PLOT_PORT:
			# The tankers' way out to sea, one on it.
			var sea: Vector2 = m.objective if m.objective != Vector2.ZERO else target + Vector2(40, 0)
			var out: Vector2 = target.lerp(sea, 1.0) + (sea - target).normalized() * 40.0
			_plan_arrow(target, out, HOSTILE, 0.15, true)
			LiteUnit.symbol(_top, target.lerp(out, 0.25 + fmod(t * 0.07, 0.7)), LiteUnit.TANKER, 5.0)
			if not ours.is_empty():
				_plan_arrow(ours[0], target.lerp(ours[0], 0.25), FRIEND, 0.15)
		LiteMission.PLOT_GRID:
			# Two stations, a crew driving out to one of them.
			var a: Vector2 = target + Vector2(-16, -6)
			var b: Vector2 = target + Vector2(16, 6)
			for p: Vector2 in [a, b]:
				LiteGlyphs.draw_ci(_top, LiteGlyph.POWER, p, 0.6, Color(HOSTILE, 0.9))
			_plan_arrow(target + Vector2(0, 14), a + Vector2(0, 6), HOSTILE, 0.3, true)
			LiteUnit.symbol(_top, (target + Vector2(0, 14)).lerp(a + Vector2(0, 6), fmod(t * 0.1, 1.0)), LiteUnit.CREW, 4.4)
			if not ours.is_empty():
				_plan_arrow(ours[0], target.lerp(ours[0], 0.25), FRIEND, 0.15)
		LiteMission.PLOT_DEPOT:
			# Convoys from the depot to their front, the jammer's circle over it.
			_top.draw_arc(target, 18.0 + sin(t * 2.0), 0, TAU, 40, Color(HOSTILE, 0.6), 1.2, true)
			if not ours.is_empty():
				var front: Vector2 = target.lerp(ours[0], 0.8)
				_plan_arrow(target, front, HOSTILE, 0.2, true)
				LiteUnit.symbol(_top, target.lerp(front, fmod(t * 0.08, 1.0)), LiteUnit.SUPPLY, 4.6)
				_plan_arrow(ours[0], target.lerp(ours[0], 0.3), FRIEND, -0.2)
		LiteMission.PLOT_EVAC:
			var to: Vector2 = map_.capital[0]
			_plan_arrow(target, target.lerp(to, 0.8), FRIEND, 0.1)
			LiteUnit.symbol(_top, target.lerp(to, fmod(t * 0.06, 0.8)), LiteUnit.CONVOY, 5.0, 1.0, 0.0, true)
			if not theirs.is_empty():
				_plan_arrow(theirs[0], target.lerp(to, 0.4), HOSTILE, -0.3, true)
		_:
			match m.kind:
				LiteMission.CAPITAL:
					for k: int in mini(3, ours.size()):
						_plan_arrow(ours[k], target, FRIEND, 0.2 * (k - 1))
				LiteMission.SURVIVE:
					for k: int in 3:
						_plan_arrow(map_.capital[1], target, HOSTILE, -0.4 + 0.4 * k, true)
				LiteMission.PROTECT, LiteMission.HOLD:
					for k: int in mini(2, theirs.size()):
						_plan_arrow(theirs[k], target, HOSTILE, 0.25, true)
				_:
					if not ours.is_empty():
						_plan_arrow(ours[0], target, FRIEND, 0.2)
					var pulse: float = 0.5 + 0.5 * sin(t * 4.0)
					for k: int in 3:
						var p: Vector2 = target + Vector2.from_angle(k * 2.1) * 14.0
						_top.draw_arc(p, 3.0 + pulse, 0, TAU, 16, Color(HOSTILE, 0.9), 1.2, true)
						_top.draw_line(p - Vector2(2, 2), p + Vector2(2, 2), Color(HOSTILE, 0.9), 1.0, true)
						_top.draw_line(p + Vector2(2, -2), p - Vector2(2, -2), Color(HOSTILE, 0.9), 1.0, true)

## A thick plan arrow from `a` to `b`, bent by `bend` (of its length), its
## dashes running along it; dotted for strikes through the air.
func _plan_arrow(a: Vector2, b: Vector2, col: Color, bend: float, air: bool = false) -> void:
	var d: Vector2 = b - a
	var len: float = d.length()
	if len < 8.0:
		return
	var mid: Vector2 = (a + b) * 0.5 + d.orthogonal().normalized() * len * bend
	var pts:= PackedVector2Array()
	for i: int in 25:
		var u: float = i / 24.0
		pts.append(a.lerp(mid, u).lerp(mid.lerp(b, u), u))
	# Stop short of the end, for the head.
	var w: float = 1.4 if air else 3.2
	var run: float = fmod(_clock * 14.0, 8.0)
	var acc: float = 0.0
	for i: int in range(1, pts.size() - 2):
		var p0: Vector2 = pts[i - 1]
		var p1: Vector2 = pts[i]
		var seg: float = p0.distance_to(p1)
		var on: bool = fmod(acc + run, 8.0) < (4.0 if air else 6.0)
		acc += seg
		if on or not air:
			_top.draw_line(p0, p1, Color(col, 0.85 if on else 0.55), w, true)
	var tip: Vector2 = pts[pts.size() - 1]
	var dir: Vector2 = (tip - pts[pts.size() - 3]).normalized()
	var hs: float = 7.0 if not air else 5.0
	_top.draw_colored_polygon(PackedVector2Array([tip, tip - dir * hs + dir.orthogonal() * hs * 0.6, tip - dir * hs - dir.orthogonal() * hs * 0.6]), col)

## The campaign's state on its front (phase 4): a raid massing (a pulsing
## red ring and a word at the region it aims at), an enemy offensive, the
## events that came up (a marker where each lands), our radar's cover round
## our capital.
func _draw_front_state(tx: float) -> void:
	var c: LiteCampaign = main.campaign
	var map_: LiteMap = main.map
	var fs: int = maxi(6, roundi(9.0 * tx))
	var pulse: float = 0.5 + 0.5 * sin(_clock * 3.0)
	var marks: Array = []
	if c.threat >= 0 and c.threat_group >= 0:
		marks.append([c.threat_group, "RAID MASSING" if c.threat == LiteMission.SURVIVE else "STRIKE ON INDUSTRY", LiteTheme.RED])
	if c.counter >= 0:
		marks.append([c.counter, "OFFENSIVE", LiteTheme.AMBER])
	for e: int in c.events_next:
		var at_g: int = -1
		match e:
			LiteCampaign.EV_STORAGE, LiteCampaign.EV_REINFORCE:
				at_g = main.front_pick
			LiteCampaign.EV_COMMAND:
				at_g = c.group_at(map_.capital_province(1))
			LiteCampaign.EV_RAID, LiteCampaign.EV_UNREST, LiteCampaign.EV_GRID, LiteCampaign.EV_RADAR_OUT:
				at_g = c.group_at(map_.capital_province(0))
		if at_g >= 0:
			marks.append([at_g, LiteCampaign.event_title(e).to_upper(), LiteTheme.GREEN if LiteCampaign.event_good(e) else LiteTheme.AMBER])
	var stack: Dictionary = {}
	for m: Array in marks:
		var g: int = m[0]
		var r: LiteRegion = map_.regions[int(main.front_labels.get(g, g))]
		var n: int = stack.get(g, 0)
		stack[g] = n + 1
		var at: Vector2 = r.label + Vector2(0, 14 + n * 11)
		var col: Color = m[2]
		_top.draw_arc(r.label, 22.0 + 4.0 * pulse, 0, TAU, 40, Color(col, 0.35 + 0.3 * pulse), 1.2, true)
		var w: float = LiteGlyphs.bold.get_string_size(m[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_top.draw_rect(Rect2(at + Vector2(-w * 0.5 - 4, -fs + 1), Vector2(w + 8, fs + 3)), Color(LiteTheme.BG, 0.85))
		_top.draw_string(LiteGlyphs.bold, at + Vector2(-w * 0.5, 0), m[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	# Our capital's radar cover, faint.
	var cp: Vector2 = map_.capital[0]
	if cp != Vector2.ZERO:
		_dashed_ring_ci(_top, cp, LiteRules.sense_range(LiteKind.RADAR) * 0.5, Color(FRIEND, 0.25 + 0.1 * pulse))

func _dashed_ring_ci(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var n: int = 48
	for i: int in range(0, n, 2):
		ci.draw_arc(c, r, TAU * i / n, TAU * (i + 1) / n, 4, col, 1.0, true)

## Corner brackets round a point: a selection or designation mark.
func _brackets(b: LiteBatch, c: Vector2, r: float, col: Color, width: float) -> void:
	var l: float = r * 0.42
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner: Vector2 = c + Vector2(sx * r, sy * r)
			b.line(corner, corner - Vector2(sx * l, 0), col, width)
			b.line(corner, corner - Vector2(0, sy * l), col, width)

## The tool in hand: a site's frame and range where it would go, or the
## strike reticle and its route, in the command look.
## Regions with ground free for a factory now (see draw_tool), and when it
## was worked out.
var _room: Dictionary = {}
var _room_at: float = -99.0

func draw_tool() -> void:
	if not main.started:
		return
	var p: Vector2 = main.mouse
	if main.nuke_tool:
		# The bomb's reach where it would go off, pulsing red.
		var pulse: float = 0.5 + 0.5 * sin(_clock * 6.0)
		_top.draw_circle(p, LiteSim.NUKE_R, Color(1.0, 0.2, 0.15, 0.08 + 0.06 * pulse))
		_top.draw_arc(p, LiteSim.NUKE_R, 0, TAU, 96, Color(1.0, 0.25, 0.2, 0.8), 2.0, true)
		_top.draw_arc(p, LiteSim.NUKE_R * 2.0, 0, TAU, 96, Color(1.0, 0.45, 0.2, 0.35), 1.0, true)
		_top.draw_line(p + Vector2(-8, 0), p + Vector2(8, 0), Color(1, 0.3, 0.25), 1.2, true)
		_top.draw_line(p + Vector2(0, -8), p + Vector2(0, 8), Color(1, 0.3, 0.25), 1.2, true)
		return
	var sim_: LiteSim = main.sim
	var map_: LiteMap = main.map
	var tx: float = px
	if main.build_tool != null and main.build_tool == LiteKind.FACTORY:
		# Which regions have ground free for one now (worked out twice a second).
		if sim_.time - _room_at > 0.5 or sim_.time < _room_at:
			_room_at = sim_.time
			_room.clear()
			for r: LiteRegion in map_.regions:
				if r.side == 0 and not r.city and sim_.free_slots(r.id) > 0:
					_room[r.id] = sim_.has_factory_room(0, r.id)
		for r: LiteRegion in map_.regions:
			if r.side != 0 or r.city:
				continue
			var f: int = sim_.factories_in(r.id)
			var ru: int = sim_.ruins_in(r.id)
			var n: int = sim_.slots[r.id]
			var at: Vector2 = slot_row(r, n)
			if n == 0:
				_top.draw_string(LiteGlyphs.font, r.label + Vector2(-30, 18), "NO ROOM", HORIZONTAL_ALIGNMENT_CENTER, 60, maxi(6, roundi(8.0 * tx)), LiteTheme.NEUTRAL)
				continue
			var room: bool = _room.get(r.id, true)
			if not room and sim_.free_slots(r.id) > 0:
				_top.draw_string(LiteGlyphs.font, at + Vector2(-30, 14), "NO SPACE", HORIZONTAL_ALIGNMENT_CENTER, 60 + n * 10.0, maxi(6, roundi(8.0 * tx)), LiteTheme.NEUTRAL)
			for i: int in n:
				var c: Vector2 = at + Vector2(i * 10.0, 0)
				var box: Rect2 = Rect2(c - Vector2(3.5, 3.5), Vector2(7, 7))
				if i < f:
					_top.draw_rect(box, FRIEND)
				elif i < f + ru:
					_top.draw_rect(box, LiteTheme.NEUTRAL, false, 1.0)
					_top.draw_line(box.position, box.end, LiteTheme.NEUTRAL, 1.0, true)
				else:
					_top.draw_rect(box, LiteTheme.GREEN if room else Color(LiteTheme.NEUTRAL, 0.7), false, 1.2)
		return
	if main.build_tool != null and main.build_tool == LiteMain.REPAIR_TOOL:
		# The repair tool: our damaged sites ringed amber, the one under the
		# pointer with its price.
		for s: LiteBuilding in sim_.buildings:
			if s.side == 0 and LiteStock.can_repair(s):
				_top.draw_arc(s.pos, 9.0, 0, TAU, 24, Color(LiteTheme.AMBER, 0.75), 1.2, true)
		var hb: LiteBuilding = main.hover_building
		if hb != null and hb.side == 0 and LiteStock.can_repair(hb):
			var t: String = "REPAIR $%d" % LiteStock.repair_cost(hb)
			_top.draw_string(LiteGlyphs.bold, hb.pos + Vector2(-20, -12), t, HORIZONTAL_ALIGNMENT_CENTER, 40, maxi(6, roundi(9.0 * tx)), LiteTheme.AMBER)
		_top.draw_arc(p, 5.0, 0, TAU, 16, LiteTheme.AMBER, 1.2, true)
		_top.draw_line(p + Vector2(-3, 3), p + Vector2(3, -3), LiteTheme.AMBER, 1.2, true)
	elif main.build_tool != null:
		var k: int = main.build_tool
		var price: int = sim_.cost_at(0, k, p)
		var ok: bool = sim_.can_place(0, p) and sim_.sides[0].money >= price
		if price > sim_.cost(0, k):
			_top.draw_string(LiteGlyphs.bold, p + Vector2(-34, 22), "WET GROUND $%d" % price, HORIZONTAL_ALIGNMENT_CENTER, 68, maxi(6, roundi(8.0 * tx)), LiteTheme.AMBER)
		var col: Color = FRIEND if ok else LiteTheme.RED
		var r: float = LiteRules.range(k)
		if LiteKind.is_radar(k):
			r = LiteRules.sense_range(k) * LiteRules.LINK_K
		if r > 0.0:
			_top.draw_circle(p, r, Color(col, 0.06))
			_top.draw_arc(p, r, 0, TAU, 72, Color(col, 0.6), 1.0, true)
		var pts:= PackedVector2Array()
		for v: Vector2 in RECT_PTS:
			pts.append(p + v)
		_top.draw_colored_polygon(pts, Color(FRIEND_FILL, 0.85))
		pts.append(pts[0])
		_top.draw_polyline(pts, col, 1.3, true)
		LiteGlyphs.draw_ci(_top, LiteGlyphs.of(k), p, 0.68, Color(1, 1, 1, 0.85))
	elif main.strike_tool != null:
		_draw_no_launch()
		var a: int = main.strike_tool
		var at: Vector2 = main.strike_target
		var ok: bool = map_.side_at(at) == 1
		if main.drawing != null:
			var route: Array[Vector2] = main.drawing
			var pts: Array[Vector2] = route.duplicate()
			pts.append(at)
			var line: Color = Color(FRIEND, 0.9)
			var i: int = 0
			while i + 1 < pts.size():
				_top.draw_dashed_line(pts[i], pts[i + 1], line, 1.3, 6.0, true, true)
				i += 1
			_top.draw_circle(pts[0], 2.5, line, true, -1, true)
		var col: Color = LiteTheme.TEXT if ok else LiteTheme.NEUTRAL
		var r: float = LiteRules.blast(a) + LiteRules.scatter(a)
		_top.draw_arc(at, r, 0, TAU, 48, col, 1.1, true)
		for i: int in 4:
			var d: Vector2 = Vector2(1, 0).rotated(i * PI / 2)
			_top.draw_line(at + d * (r - 4), at + d * (r + 6), col, 1.1, true)
		_top.draw_circle(at, 1.2, col, true, -1, true)
		if main.strike_snap != null:
			_top.draw_arc(at, 12, 0, TAU, 32, HOSTILE, 1.2, true)
		if ok:
			var s: String = ("%d× %s · $%d" % [main.salvo, LiteGlyphs.plural(a, main.salvo).to_upper(), main.sim.arm_cost(0, a) * main.salvo]) if LiteSim.classic_rules 				else "%d× %s · %d IN STOCK" % [mini(main.salvo, main.sim.in_stock(0, a)), LiteGlyphs.plural(a, main.salvo).to_upper(), main.sim.in_stock(0, a)]
			var sz: int = maxi(6, roundi(10.0 * tx))
			var font: Font = LiteGlyphs.bold
			# On a plate of its own, over whatever names lie under the reticle.
			var tw: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
			var plate:= Rect2(at + Vector2(r + 6, -sz * 0.8), Vector2(tw + 8 * tx, sz * 1.5))
			_top.draw_rect(plate, Color(LiteTheme.PANEL, 0.94))
			_top.draw_rect(Rect2(plate.position, Vector2(2 * tx, plate.size.y)), LiteTheme.RED)
			_top.draw_string(font, at + Vector2(r + 6 + 5 * tx, sz * 0.38), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, LiteTheme.TEXT)
