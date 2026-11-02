class_name LiteStats
extends RefCounted
## The war as our side saw it: enemy launches by hour and weapon, where their
## routes ran, which of our regions they crossed, our air alerts, and a report
## for every large attack. One second of play is one minute on the clock, so
## an hour is 60 seconds of sim time.

## Attacks of at least this many drones and missiles get a report.
const REPORT_MIN: int = 14
## Route density grid: one cell per CELL map units.
const CELL: float = 10.0
const GW: int = 98
const GH: int = 72

## Enemy weapons launched at us in each hour: [drones, cruise, ballistic].
var hourly: Array[PackedInt32Array] = []
## Enemy weapons by type: launched, shot down by us, struck our ground.
var launched: PackedInt32Array = PackedInt32Array([0, 0, 0])
var downed: PackedInt32Array = PackedInt32Array([0, 0, 0])
var landed: PackedInt32Array = PackedInt32Array([0, 0, 0])
## Our own weapons by type: launched, shot down by the enemy, hits.
var our_launched: PackedInt32Array = PackedInt32Array([0, 0, 0])
var our_downed: PackedInt32Array = PackedInt32Array([0, 0, 0])
var our_hits: int = 0
var our_landed: PackedInt32Array = PackedInt32Array([0, 0, 0])

## How often an enemy drone or missile passed through each cell.
var heat: PackedFloat32Array = PackedFloat32Array()
var heat_max: float = 0.0
## Distinct enemy weapons that crossed each of our regions.
var crossed: PackedInt32Array = PackedInt32Array()

## Air alerts over our regions: how many began, how long the finished ones
## lasted (minutes), the longest, and how many regions were under alert in
## each minute of the war.
var alerts: int = 0
var alert_minutes: PackedFloat32Array = PackedFloat32Array()
var longest: float = 0.0
var longest_region: int = -1
var timeline: PackedByteArray = PackedByteArray()
var peak: int = 0

var reports: Array[LiteReport] = []
var _attack: LiteReport = null
var _minute: float = 0.0

func setup(map: LiteMap) -> void:
	heat.resize(GW * GH)
	crossed.resize(map.regions.size())

func _hour(time: float) -> PackedInt32Array:
	var h: int = int(time / 60.0)
	while hourly.size() <= h:
		hourly.append(PackedInt32Array([0, 0, 0]))
	return hourly[h]

func on_launch(w: LiteWeapon, time: float) -> void:
	if w.side == 0:
		our_launched[w.arm] += 1
		return
	launched[w.arm] += 1
	var h: PackedInt32Array = _hour(time)
	h[w.arm] += 1
	hourly[int(time / 60.0)] = h
	if _attack == null:
		_attack = LiteReport.new()
		_attack.start = time
	_attack.launched[w.arm] += 1
	_attack.alive += 1
	_attack.last = time
	w.report = _attack

func on_down(w: LiteWeapon, time: float) -> void:
	if w.side == 0:
		our_downed[w.arm] += 1
		return
	downed[w.arm] += 1
	if w.report != null:
		w.report.downed[w.arm] += 1
		w.report.alive -= 1
		w.report.last = time

## A weapon came down on its target: `lost` names what it destroyed.
func on_impact(w: LiteWeapon, struck: bool, lost: PackedStringArray, capital_damage: float, time: float) -> void:
	if w.side == 0:
		our_landed[w.arm] += 1
		if struck: our_hits += 1
		return
	landed[w.arm] += 1
	if w.report != null:
		if struck: w.report.hits += 1
		w.report.lost.append_array(lost)
		w.report.capital_damage += capital_damage
		w.report.alive -= 1
		w.report.last = time

func on_alert(region: int, side: int) -> void:
	if side == 0:
		alerts += 1

func on_all_clear(region: int, side: int, minutes: float) -> void:
	if side != 0:
		return
	alert_minutes.append(minutes)
	if minutes > longest:
		longest = minutes
		longest_region = region

## Called four times a second of sim time. Returns a finished large attack,
## if one just ended.
func tick(sim: LiteSim, dt: float) -> LiteReport:
	for w: LiteWeapon in sim.weapons:
		if not w.alive or w.side != 1 or not w.seen[0]:
			continue
		var cx: int = int(w.pos.x / CELL)
		var cy: int = int(w.pos.y / CELL)
		if cx >= 0 and cy >= 0 and cx < GW and cy < GH:
			var v: float = heat[cy * GW + cx] + 1.0
			heat[cy * GW + cx] = v
			heat_max = maxf(heat_max, v)
		var r: int = sim.map.region_at(w.pos)
		if r == LiteMap.NONE or sim.map.regions[r].side != 0:
			continue
		if sim.map.regions[r].city:
			r = sim.map.regions[r].parent
		if not w.crossed.has(r):
			w.crossed[r] = true
			crossed[r] += 1
	_minute += dt
	while _minute >= 1.0:
		_minute -= 1.0
		var n: int = mini(sim.alerted[0], 255)
		timeline.append(n)
		peak = maxi(peak, n)
	# An attack is over once nothing of it is in the air, nothing more is
	# queued to launch, and a few quiet minutes have passed.
	if _attack != null and _attack.alive <= 0 and sim.time - _attack.last > 5.0 and not sim.enemy_queued(0):
		var done: LiteReport = _attack
		_attack = null
		done.end = done.last
		if done.total >= REPORT_MIN:
			reports.append(done)
			return done
	return null

## The median of the finished alerts, in minutes.
func median_alert() -> float:
	if alert_minutes.is_empty():
		return 0.0
	var a: PackedFloat32Array = alert_minutes.duplicate()
	a.sort()
	var n: int = a.size()
	return a[n / 2] if n % 2 == 1 else (a[n / 2 - 1] + a[n / 2]) / 2.0
