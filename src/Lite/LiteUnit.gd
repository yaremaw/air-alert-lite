class_name LiteUnit
extends RefCounted
## Enemy forces on the move in an operation (phase 4b): sites of kind
## LiteKind.UNIT that drive along a route (LiteBuilding.route), shown as NATO
## symbols. An armoured column grinding towards our border, an ammunition
## train on its rail line, a mobile launcher that fires and moves on. See
## LiteSim._move_units for how they move, LiteMission for what they are to
## an operation, LiteCampaign for where they start.

enum { ARMOUR, MECH, ARTILLERY, LOCO, WAGON, LAUNCHER, CONVOY, TANKER, CREW, SUPPLY }

static func name(t: int) -> String:
	match t:
		ARMOUR: return "Armoured battalion"
		MECH: return "Mechanised battalion"
		ARTILLERY: return "Artillery battalion"
		LOCO: return "Ammunition train"
		WAGON: return "Ammunition wagons"
		CONVOY: return "Evacuation convoy"
		TANKER: return "Cargo ship"
		CREW: return "Repair crew"
		SUPPLY: return "Supply convoy"
		_: return "Mobile launcher"

static func hp(t: int) -> float:
	match t:
		ARMOUR: return 3.0
		LOCO: return 4.0
		WAGON: return 2.0
		LAUNCHER: return 2.0
		TANKER: return 5.0
		_: return 2.0

## A NATO symbol for a hostile unit: a red diamond with its arm inside (an
## oval for armour, an oval crossed for mechanised infantry, a dot for
## artillery, a rocket for a launcher, a wagon for a train), facing `dir`.
## `k` is its size (map units), `alpha` how sure we are of it.
static func symbol(ci: CanvasItem, at: Vector2, t: int, k: float, alpha: float = 1.0, hit: float = 0.0, friend: bool = false) -> void:
	var fill: Color = (Color(0.36, 0.6, 0.92, alpha) if friend else Color(0.86, 0.3, 0.26, alpha)).lerp(Color(1, 0.85, 0.6, alpha), hit)
	var ink: Color = Color(0.08, 0.06, 0.06, alpha)
	# NATO frames: a friendly unit a rectangle, a hostile one a diamond.
	var d:= PackedVector2Array([at + Vector2(-k, -k * 0.7), at + Vector2(k, -k * 0.7), at + Vector2(k, k * 0.7), at + Vector2(-k, k * 0.7)]) if friend else PackedVector2Array([at + Vector2(0, -k), at + Vector2(k, 0), at + Vector2(0, k), at + Vector2(-k, 0)])
	var shadow:= PackedVector2Array()
	for p: Vector2 in d:
		shadow.append(p + Vector2(0.6, 0.8))
	ci.draw_colored_polygon(shadow, Color(0, 0, 0, 0.35 * alpha))
	ci.draw_colored_polygon(d, fill)
	d.append(d[0])
	ci.draw_polyline(d, ink, maxf(0.35, k * 0.12))
	var w: float = maxf(0.3, k * 0.1)
	match t:
		ARMOUR:
			_oval(ci, at, k * 0.45, k * 0.22, ink, w)
		MECH:
			_oval(ci, at, k * 0.45, k * 0.22, ink, w)
			ci.draw_line(at + Vector2(-k * 0.45, -k * 0.3), at + Vector2(k * 0.45, k * 0.3), ink, w)
			ci.draw_line(at + Vector2(-k * 0.45, k * 0.3), at + Vector2(k * 0.45, -k * 0.3), ink, w)
		ARTILLERY:
			ci.draw_circle(at, k * 0.18, ink)
		TANKER:
			# A ship's hull, side on, its bridge at the stern.
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-k * 0.5, -k * 0.02), at + Vector2(k * 0.55, -k * 0.02), at + Vector2(k * 0.38, k * 0.26), at + Vector2(-k * 0.42, k * 0.26)]), ink)
			ci.draw_rect(Rect2(at + Vector2(-k * 0.42, -k * 0.26), Vector2(k * 0.2, k * 0.24)), ink)
		CREW:
			# Engineers: a spanner.
			ci.draw_line(at + Vector2(-k * 0.35, k * 0.35), at + Vector2(k * 0.2, -k * 0.2), ink, w * 1.5)
			ci.draw_arc(at + Vector2(k * 0.27, -k * 0.27), k * 0.16, 0, TAU, 10, ink, w * 1.2)
		LAUNCHER:
			ci.draw_line(at + Vector2(-k * 0.35, k * 0.3), at + Vector2(k * 0.3, -k * 0.35), ink, w * 1.4)
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(k * 0.42, -k * 0.47), at + Vector2(k * 0.12, -k * 0.38), at + Vector2(k * 0.33, -k * 0.17)]), ink)
			ci.draw_line(at + Vector2(-k * 0.45, k * 0.42), at + Vector2(k * 0.05, k * 0.42), ink, w)
		_:
			ci.draw_rect(Rect2(at - Vector2(k * 0.4, k * 0.18), Vector2(k * 0.8, k * 0.36)), ink, false, w)
			ci.draw_circle(at + Vector2(-k * 0.22, k * 0.3), k * 0.08, ink)
			ci.draw_circle(at + Vector2(k * 0.22, k * 0.3), k * 0.08, ink)

static func _oval(ci: CanvasItem, at: Vector2, rx: float, ry: float, col: Color, w: float) -> void:
	var pts:= PackedVector2Array()
	for i: int in 17:
		var a: float = i * TAU / 16.0
		pts.append(at + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_polyline(pts, col, w)

## A point `dist` along a route, and the way it runs there.
static func along(route: PackedVector2Array, dist: float) -> Array:
	if route.size() < 2:
		return [route[0] if route.size() == 1 else Vector2.ZERO, Vector2.RIGHT]
	var left: float = maxf(0.0, dist)
	for i: int in range(1, route.size()):
		var a: Vector2 = route[i - 1]
		var b: Vector2 = route[i]
		var l: float = a.distance_to(b)
		if left <= l or i == route.size() - 1:
			var u: float = clampf(left / maxf(0.001, l), 0.0, 1.0)
			return [a.lerp(b, u), (b - a).normalized()]
		left -= l
	return [route[route.size() - 1], Vector2.RIGHT]

static func length(route: PackedVector2Array) -> float:
	var n: float = 0.0
	for i: int in range(1, route.size()):
		n += route[i - 1].distance_to(route[i])
	return n

## A road from `from` to `to`, winding a little, kept on land.
static func road(map: LiteMap, from: Vector2, to: Vector2, rng: RandomNumberGenerator, wiggle: float) -> PackedVector2Array:
	var pts:= PackedVector2Array([from])
	var n: int = maxi(2, int(from.distance_to(to) / 12.0))
	var across: Vector2 = (to - from).normalized().orthogonal()
	var ph: float = rng.randf() * TAU
	var ph2: float = rng.randf() * TAU
	for i: int in range(1, n):
		var u: float = float(i) / n
		var p: Vector2 = from.lerp(to, u) + across * (sin(u * PI * 2.3 + ph) * 0.7 + sin(u * PI * 5.1 + ph2) * 0.3) * wiggle * sin(u * PI)
		if map.region_at(p) == LiteMap.NONE:
			p = from.lerp(to, u)
		pts.append(p)
	pts.append(to)
	return pts
