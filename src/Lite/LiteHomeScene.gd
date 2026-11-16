class_name LiteHomeScene
extends Control

## The home screen's background: the cover art (a foggy dawn over a Soviet
## city, its TV tower burning at its foot, an air defence launcher on the
## hill in front; assets/ui/home_bg.jpg), filling the screen with a very
## slow push-in so the picture is never quite still. Over it, live: the fire
## at the tower's foot (the picture's own flames rippling and flickering,
## home_fire.gdshader; its glow; a flare-up now and then with a burst of
## sparks; embers and smoke rising along the painted plume), banks of fog
## drifting low through the valley (home_fog.gdshader), the tower's red
## aviation lights pulsing in the mist, the launcher's marker lights, drones
## low over the rooftops and now and then a cruise missile, passing behind
## the launcher.

const ART: Vector2 = Vector2(1920, 1072)
## Places in the picture's pixels.
const FOCUS: Vector2 = Vector2(965, 520)      # what the push-in closes on
const FIRE: Vector2 = Vector2(966, 690)       # the fire's heart
const FIRE_BASE: Rect2 = Rect2(930, 645, 78, 72) # where its flames and embers rise from
const SMOKE: Vector2 = Vector2(995, 615)      # where the smoke leaves it
## The painted smoke column, from the fire up (traced off the picture): its
## middle and how wide it is at each point. The live smoke keeps to it.
const PLUME: Array[Vector3] = [
	Vector3(995, 615, 70), Vector3(1007, 585, 80), Vector3(1024, 568, 88), Vector3(1040, 540, 95),
	Vector3(1055, 510, 85), Vector3(1058, 470, 80), Vector3(1062, 430, 100), Vector3(1095, 400, 145),
	Vector3(1118, 370, 175), Vector3(1128, 332, 170), Vector3(1148, 300, 145), Vector3(1168, 272, 125),
	Vector3(1200, 245, 170), Vector3(1238, 215, 230), Vector3(1228, 175, 140), Vector3(1220, 140, 70)]
const PLUME_TIME: float = 16.0
## The tower's red lights (top, the pair half way, the pair on its deck).
const TOWER_LIGHTS: Array[Vector2] = [Vector2(960, 197), Vector2(955, 262), Vector2(965, 262), Vector2(942, 334), Vector2(978, 334)]
## The launcher's amber marker lights.
const MARKERS: Array[Vector2] = [Vector2(1572, 706), Vector2(1533, 719), Vector2(1570, 755), Vector2(1752, 750)]
## The launcher cut out of the picture (assets/ui/home_fg.png, its place in
## the picture): drawn again over the drones, so they fly behind it.
const FG_POS: Vector2 = Vector2(1265, 416)
## The picture's own flames, cut out (assets/ui/home_fire.png), and where.
const FIRE_LAYER: Vector2 = Vector2(890, 590)
const EMBERS: int = 40
const DRONES: int = 1

var _tex: Texture2D = null
var _fg: Texture2D = null
var _t: float = 0.0
var _rng:= RandomNumberGenerator.new()
## Embers and sparks, riding up the smoke column: how far up it each is (x,
## 0 at the fire to 1 at the top) and to which side (y); how fast it climbs
## (x) and how far up it goes out (y); its age, and a seed for its flicker.
var _pos:= PackedVector2Array()
var _vel:= PackedVector2Array()
var _age:= PackedFloat32Array()
var _life:= PackedFloat32Array()
## Smoke puffs rising along the plume: [pos, age, size, seed].
var _smoke: Array = []
var _smoke_at: float = 0.0
## A flare-up: when it started, and the next one.
var _flare_at: float = -99.0
var _next_flare: float = 3.0
## Drones: where, which way, how fast, when they come back.
var _dpos:= PackedVector2Array()
var _ddir:= PackedFloat32Array()
var _dspeed:= PackedFloat32Array()
var _dwait:= PackedFloat32Array()
## The picture on the screen: where its (0, 0) is, its scale.
var _origin: Vector2 = Vector2.ZERO
var _k: float = 1.0
var _fog: ColorRect = null
var _fire: TextureRect = null
## A cruise missile flying by now and then: where, which way, when the next.
var _cm_pos: Vector2 = Vector2(-999, 0)
var _cm_dir: float = 1.0
var _cm_next: float = 9.0
## Its exhaust: puffs left behind [pos, age], spreading and fading; its
## height wavering a little as it follows the ground.
var _cm_trail: Array = []
var _cm_y: float = 0.0
var _cm_puff: float = 0.0
var _light: Control = null
var _air: Control = null
var _air_light: Control = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex = load("res://assets/ui/home_bg.jpg") as Texture2D
	_fg = load("res://assets/ui/home_fg.png") as Texture2D
	_rng.randomize()
	for i: int in EMBERS:
		_pos.append(Vector2.ZERO)
		_vel.append(Vector2.ZERO)
		_age.append(0.0)
		_life.append(1.0)
		_spawn(i, false)
		_pos[i] = Vector2(_rng.randf() * _vel[i].y, _pos[i].y)
	for i: int in DRONES:
		_dpos.append(Vector2.ZERO)
		_ddir.append(1.0)
		_dspeed.append(30.0)
		_dwait.append(0.0)
		_drone(i)
		_dwait[i] = _rng.randf_range(0.0, 6.0)
	# The smoke already rising when the screen opens.
	for i: int in 61:
		var m: Array = [SMOKE, i * 0.26, 10.0, _rng.randf()]
		_smoke_step(m, 0.0)
		_smoke.append(m)
	# The fog over the picture, then the light (added, as light is) over that.
	_fog = ColorRect.new()
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fm:= ShaderMaterial.new()
	fm.shader = load("res://src/Lite/home_fog.gdshader") as Shader
	_fog.material = fm
	add_child(_fog)
	_fire = TextureRect.new()
	_fire.texture = load("res://assets/ui/home_fire.png") as Texture2D
	_fire.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fire.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fire.stretch_mode = TextureRect.STRETCH_SCALE
	var firem:= ShaderMaterial.new()
	firem.shader = load("res://src/Lite/home_fire.gdshader") as Shader
	_fire.material = firem
	add_child(_fire)
	_light = Control.new()
	_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_light.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var add:= CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_light.material = add
	_light.draw.connect(_draw_light)
	add_child(_light)
	_air = Control.new()
	_air.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_air.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_air.draw.connect(_draw_air)
	add_child(_air)
	_air_light = Control.new()
	_air_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_air_light.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var add2:= CanvasItemMaterial.new()
	add2.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_air_light.material = add2
	_air_light.draw.connect(_draw_air_light)
	add_child(_air_light)

## An ember (or, in a flare-up, a spark shooting up fast) off the fire,
## climbing the smoke column with the smoke.
func _spawn(i: int, spark: bool) -> void:
	_pos[i] = Vector2(0.0, _rng.randf_range(-0.32, 0.32))
	_vel[i] = Vector2(_rng.randf_range(0.28, 0.45) if spark else _rng.randf_range(0.07, 0.14), _rng.randf_range(0.18, 0.6))
	_age[i] = 0.0
	_life[i] = _rng.randf()

## Where an ember is in the picture: up the column, to its side, with a
## little flutter.
func _ember_at(i: int) -> Vector2:
	var at: Vector3 = _plume(_pos[i].x)
	var flutter: float = sin(_t * 3.0 + _life[i] * 20.0) * 0.05
	return Vector2(at.x + (_pos[i].y + flutter) * at.z * (0.6 + 0.4 * _pos[i].x), at.y)

func _drone(i: int) -> void:
	var right: bool = _rng.randf() < 0.5
	_ddir[i] = 1.0 if right else -1.0
	# Low, just over the rooftops, passing behind the launcher.
	_dpos[i] = Vector2(-40.0 if right else ART.x + 40.0, _rng.randf_range(565.0, 600.0))
	_dspeed[i] = _rng.randf_range(65.0, 95.0)
	_dwait[i] = _rng.randf_range(10.0, 22.0)

## A smoke puff rising along the painted column: it moves up the column's
## middle over PLUME_TIME seconds, held to one side of it (its seed), swaying
## a little, swelling as the column widens.
func _smoke_step(m: Array, dt: float) -> void:
	m[1] = float(m[1]) + dt
	var u: float = clampf(float(m[1]) / PLUME_TIME, 0.0, 1.0)
	var at: Vector3 = _plume(pow(u, 0.85))
	var side: float = (float(m[3]) - 0.5) * 0.55 + 0.08 * sin(float(m[1]) * 0.9 + float(m[3]) * 9.0)
	m[0] = Vector2(at.x + side * at.z, at.y)
	m[2] = at.z * (0.32 + 0.1 * float(m[3]))

## A point up the plume, 0 at the fire to 1 at its top: [x, y, width].
func _plume(u: float) -> Vector3:
	var f: float = u * (PLUME.size() - 1)
	var i: int = mini(int(f), PLUME.size() - 2)
	return PLUME[i].lerp(PLUME[i + 1], f - i)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	var flare: float = _flare()
	for i: int in EMBERS:
		_age[i] += delta
		_pos[i] = _pos[i] + Vector2(_vel[i].x * delta, 0.0)
		if _pos[i].x >= _vel[i].y:
			_spawn(i, flare > 0.3 and _rng.randf() < 0.6)
	if _t >= _next_flare:
		_flare_at = _t
		_next_flare = _t + _rng.randf_range(4.0, 9.0)
	_smoke_at += delta
	if _smoke_at > 0.26:
		_smoke_at = 0.0
		var m: Array = [SMOKE, 0.0, 10.0, _rng.randf()]
		_smoke_step(m, 0.0)
		_smoke.append(m)
	for m: Array in _smoke:
		_smoke_step(m, delta)
	_smoke = _smoke.filter(func(m: Array) -> bool: return float(m[1]) < PLUME_TIME)
	for i: int in DRONES:
		if _dwait[i] > 0.0:
			_dwait[i] -= delta
			continue
		_dpos[i] += Vector2(_ddir[i] * _dspeed[i], sin(_t * 0.7 + i) * 2.0) * delta
		if _dpos[i].x < -60.0 or _dpos[i].x > ART.x + 60.0:
			_drone(i)
	# A cruise missile now and then, fast and low over the city.
	if _cm_pos.x < -100.0 or _cm_pos.x > ART.x + 100.0:
		if _t >= _cm_next:
			_cm_dir = 1.0 if _rng.randf() < 0.5 else -1.0
			_cm_y = _rng.randf_range(540.0, 580.0)
			_cm_pos = Vector2(-80.0 if _cm_dir > 0.0 else ART.x + 80.0, _cm_y)
			_cm_next = _t + _rng.randf_range(14.0, 28.0)
	else:
		# Fast and level, its height wavering a little as it hugs the ground.
		_cm_pos.x += _cm_dir * 330.0 * delta
		_cm_pos.y = _cm_y + sin(_t * 1.7) * 3.0 + sin(_t * 4.3) * 0.8
		# A puff of exhaust from its tail every few pixels flown.
		_cm_puff += delta
		while _cm_puff > 0.012:
			_cm_puff -= 0.012
			_cm_trail.append([_cm_pos + Vector2(-_cm_dir * 13.0, 0.5), 0.0])
	for e: Array in _cm_trail:
		e[1] = float(e[1]) + delta
		# The exhaust drifts and rises a touch as it cools.
		e[0] = (e[0] as Vector2) + Vector2(2.0, -2.5) * delta
	_cm_trail = _cm_trail.filter(func(e: Array) -> bool: return float(e[1]) < 2.6)
	_fire.position = _at(FIRE_LAYER)
	_fire.size = _fire.texture.get_size() * _k
	var firem: ShaderMaterial = _fire.material
	firem.set_shader_parameter("t", _t)
	firem.set_shader_parameter("gain", 0.42 * _flicker())
	queue_redraw()
	_light.queue_redraw()
	_air.queue_redraw()
	_air_light.queue_redraw()
	var fm: ShaderMaterial = _fog.material
	fm.set_shader_parameter("t", _t)
	fm.set_shader_parameter("rect_size", size)
	fm.set_shader_parameter("origin", _origin)
	fm.set_shader_parameter("scale", _k)

## How hard the fire flares now: 0, up to 1 just after a flare-up.
func _flare() -> float:
	var since: float = _t - _flare_at
	if since < 0.0 or since > 2.2:
		return 0.0
	return (1.0 - since / 2.2) * minf(1.0, since / 0.15)

## The fire's flicker: a few waves of different speeds, and the flare-up.
func _flicker() -> float:
	return 0.78 + 0.12 * sin(_t * 7.3) + 0.07 * sin(_t * 13.1 + 1.3) + 0.05 * sin(_t * 23.0 + 0.4) + 0.6 * _flare()

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	draw_rect(Rect2(Vector2.ZERO, size), LiteGlyphs.PAGE)
	if _tex == null:
		return
	# The picture covers the screen; its dark left side sits under the menu.
	var s: float = maxf(w / ART.x, h / ART.y)
	var x0: float = (w - ART.x * s) * 0.5
	var y0: float = (h - ART.y * s) * 0.5
	# The push-in: 2.5% over a minute and back, round the tower.
	var z: float = 1.0 + 0.025 * (0.5 - 0.5 * cos(_t * TAU / 60.0))
	var c:= Vector2(x0, y0) + FOCUS * s
	_origin = c + (Vector2(x0, y0) - c) * z
	_k = s * z
	draw_texture_rect(_tex, Rect2(_origin, ART * _k), false)
	# Smoke rising along the plume: dark, soft, swelling and thinning out.
	for m: Array in _smoke:
		var age: float = m[1]
		var a: float = minf(1.0, age / 1.5) * clampf((PLUME_TIME - age) / 4.0, 0.0, 1.0)
		var warm: float = clampf(1.0 - age / 2.5, 0.0, 1.0)
		var col: Color = Color(0.2, 0.19, 0.19).lerp(Color(0.55, 0.3, 0.16), warm * 0.6)
		_glow(self, _at(m[0]), float(m[2]) * _k, Color(col, 0.3 * a))

## The light, added over the picture and the fog: the fire, its sparks, the
## tower's lights, the launcher's.
func _draw_light() -> void:
	var ci: CanvasItem = _light
	var fl: float = _flicker()
	var fire: Vector2 = _at(FIRE)
	var k: float = _k
	# Its glow through the fog, on the tower's legs and the blocks round it.
	_glow(ci, fire, 300.0 * k, Color(0.55, 0.22, 0.06, 0.22 * fl))
	_glow(ci, _at(FIRE + Vector2(-8, -70)), 120.0 * k, Color(0.6, 0.28, 0.08, 0.16 * fl))
	_glow(ci, fire, 70.0 * k, Color(1.0, 0.6, 0.25, 0.3 * fl))
	# Embers and sparks: square, like the picture's pixels, cooling as they rise.
	var px: float = maxf(1.5, 1.4 * k)
	for i: int in EMBERS:
		var t: float = clampf(_pos[i].x / _vel[i].y, 0.0, 1.0)
		var tw: float = 0.6 + 0.4 * sin(_t * 11.0 + i * 2.1)
		var a: float = minf(1.0, t * 10.0) * (1.0 - t) * tw
		var col: Color = Color(1.0, 0.9, 0.55).lerp(Color(1.0, 0.35, 0.08), t)
		var p: Vector2 = _at(_ember_at(i)).floor()
		var r: float = px * (1.0 if i % 3 else 1.6)
		_glow(ci, p + Vector2(r, r) * 0.5, r * 2.6, Color(col, a * 0.3))
		ci.draw_rect(Rect2(p, Vector2(r, r)), Color(col, a))
	# The tower's red aviation lights: all together, slowly up, on, down,
	# off, a halo round each in the mist.
	var cyc: float = fmod(_t, 2.4)
	var on: float = clampf(cyc / 0.35, 0.0, 1.0) * clampf((1.6 - cyc) / 0.35, 0.0, 1.0)
	for i: int in TOWER_LIGHTS.size():
		var lp: Vector2 = _at(TOWER_LIGHTS[i])
		var big: float = 1.4 if i == 0 else 1.0
		_glow(ci, lp, 42.0 * k * big, Color(0.9, 0.08, 0.05, 0.22 * on))
		_glow(ci, lp, 12.0 * k * big, Color(1.0, 0.2, 0.12, 0.55 * on))
		_glow(ci, lp, 3.5 * k * big, Color(1.0, 0.75, 0.65, 0.9 * on))
## What flies, over the fire and its sparks but behind the launcher: drones
## low over the rooftops, the cruise missile and its exhaust; then the
## launcher again over them.
func _draw_air() -> void:
	# Drones far off, side on, half lost in the haze.
	for i: int in DRONES:
		if _dwait[i] > 0.0:
			continue
		var p: Vector2 = _at(_dpos[i])
		var d: float = _ddir[i]
		var u: float = 7.0 * _k
		var pt:= func(x: float, y: float) -> Vector2: return p + Vector2(d * x * u, y * u)
		var dark:= Color(0.16, 0.17, 0.2, 0.75)
		_air.draw_colored_polygon(PackedVector2Array([pt.call(1.5, 0.0), pt.call(1.1, -0.2), pt.call(-0.9, -0.22), pt.call(-1.1, 0.05), pt.call(-0.9, 0.2), pt.call(1.0, 0.18)]), dark)
		_air.draw_colored_polygon(PackedVector2Array([pt.call(0.4, 0.12), pt.call(-1.0, 0.1), pt.call(-1.0, 0.26), pt.call(0.1, 0.22)]), dark)
		_air.draw_colored_polygon(PackedVector2Array([pt.call(-0.62, 0.1), pt.call(-0.85, -0.72), pt.call(-1.02, -0.72), pt.call(-0.98, 0.12)]), dark)
	# The cruise missile's exhaust: a thin grey haze left behind it,
	# spreading and thinning out (a jet engine's, no rocket flame).
	# Drawn as one ribbon: each stretch as wide and as faint as its age.
	for j: int in range(1, _cm_trail.size()):
		var e0: Array = _cm_trail[j - 1]
		var e1: Array = _cm_trail[j]
		var age: float = e1[1]
		var a: float = 1.0 - age / 2.6
		a *= a
		var wide: float = (1.2 + age * 5.0) * _k
		var col:= Color(0.66, 0.67, 0.7, 0.2 * a / (1.0 + age * 1.5))
		_air.draw_line(_at(e0[0]), _at(e1[0]), col, wide)
		if j % 6 == 0:
			_glow(_air, _at(e1[0]), wide * 1.4, Color(col, col.a * 0.6))
	# Its body side on: a long slim fuselage with an ogive nose, the small
	# folded-out wings, the tail fins, the engine's intake under the belly;
	# the dawn light catching its back.
	if _cm_pos.x > -100.0 and _cm_pos.x < ART.x + 100.0:
		var p: Vector2 = _at(_cm_pos)
		var d: float = _cm_dir
		var u: float = 10.0 * _k
		var pt:= func(x: float, y: float) -> Vector2: return p + Vector2(d * x * u, y * u)
		var body:= Color(0.17, 0.18, 0.2, 0.97)
		_air.draw_colored_polygon(PackedVector2Array([pt.call(1.6, 0.02), pt.call(1.42, -0.07), pt.call(1.15, -0.12), pt.call(-1.18, -0.12), pt.call(-1.28, -0.07), pt.call(-1.28, 0.1), pt.call(-1.18, 0.13), pt.call(1.15, 0.13), pt.call(1.42, 0.09)]), body)
		_air.draw_colored_polygon(PackedVector2Array([pt.call(0.25, 0.04), pt.call(-0.15, 0.04), pt.call(-0.42, 0.2), pt.call(-0.2, 0.2)]), body)
		_air.draw_colored_polygon(PackedVector2Array([pt.call(-0.95, -0.1), pt.call(-1.2, -0.1), pt.call(-1.3, -0.42), pt.call(-1.16, -0.42)]), body)
		_air.draw_colored_polygon(PackedVector2Array([pt.call(-1.0, 0.1), pt.call(-1.2, 0.1), pt.call(-1.26, 0.3), pt.call(-1.14, 0.3)]), body)
		_air.draw_colored_polygon(PackedVector2Array([pt.call(-0.45, 0.12), pt.call(-0.85, 0.12), pt.call(-0.9, 0.22), pt.call(-0.55, 0.22)]), body)
		_air.draw_line(pt.call(1.38, -0.08), pt.call(-1.15, -0.1), Color(0.62, 0.62, 0.64, 0.45), maxf(1.0, 0.07 * u))
	# The launcher again, over them.
	if _fg != null:
		_air.draw_texture_rect(_fg, Rect2(_at(FG_POS), _fg.get_size() * _k), false)

## The lights of what flies, added: the missile's engine, the drones' blinking.
func _draw_air_light() -> void:
	var ci: CanvasItem = _air_light
	var k: float = _k
	# The cruise missile's engine: only a dull glow at its tail nozzle and a
	# faint shimmer of heat, flickering; hidden behind the launcher.
	var nozzle: Vector2 = _cm_pos + Vector2(-_cm_dir * 13.0, 0.3)
	if _cm_pos.x > -100.0 and _cm_pos.x < ART.x + 100.0 and not _behind(nozzle):
		var ex: Vector2 = _at(nozzle)
		var f: float = 0.8 + 0.2 * sin(_t * 41.0) + 0.1 * sin(_t * 67.0)
		_glow(ci, ex, 7.0 * k, Color(1.0, 0.45, 0.15, 0.28 * f))
		_glow(ci, ex - Vector2(_cm_dir * 3.0 * k, 0), 2.2 * k, Color(1.0, 0.8, 0.55, 0.75 * f))
	# The launcher's amber markers, steady, a soft halo.
	for i: int in MARKERS.size():
		var mp: Vector2 = _at(MARKERS[i])
		var b: float = 0.85 + 0.15 * sin(_t * 1.3 + i * 2.0)
		_glow(ci, mp, 14.0 * k, Color(1.0, 0.6, 0.15, 0.3 * b))
		_glow(ci, mp, 3.5 * k, Color(1.0, 0.85, 0.5, 0.7 * b))
	# The drones' red lights blinking.
	for i: int in DRONES:
		if _dwait[i] <= 0.0 and fmod(_t * 1.6 + i * 0.37, 1.0) < 0.2 and not _behind(_dpos[i]):
			var p: Vector2 = _at(_dpos[i]) + Vector2(-_ddir[i] * 6.4, -5.0) * k
			_glow(ci, p, 6.0 * k, Color(1.0, 0.15, 0.1, 0.8))

## Whether a point of the picture is behind the launcher (under its cut-out).
var _fg_img: Image = null
func _behind(p: Vector2) -> bool:
	if _fg == null:
		return false
	if _fg_img == null:
		_fg_img = _fg.get_image()
	var q: Vector2i = Vector2i(p - FG_POS)
	if q.x < 0 or q.y < 0 or q.x >= _fg_img.get_width() or q.y >= _fg_img.get_height():
		return false
	return _fg_img.get_pixelv(q).a > 0.5

## A point of the picture on the screen.
func _at(p: Vector2) -> Vector2:
	return _origin + p * _k

## A soft round light: `col` in the middle, fading to nothing at radius `r`.
static func _glow(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	const N: int = 20
	var clear:= Color(col, 0.0)
	var prev: Vector2 = c + Vector2(r, 0)
	for i: int in range(1, N + 1):
		var nxt: Vector2 = c + Vector2.from_angle(i * TAU / N) * r
		ci.draw_primitive(PackedVector2Array([c, prev, nxt]), PackedColorArray([col, clear, clear]), PackedVector2Array())
		prev = nxt

## Hidden (itself or a parent), it does no work frame by frame: with dozens
## of these in the menus and the HUD, their _process added up.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_READY:
		set_process(is_visible_in_tree())
