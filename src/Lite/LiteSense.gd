class_name LiteSense
extends RefCounted
## Phase 4: what each side sees of the other's weapons in the air, and its
## air defence network.
##
## Detection: an enemy drone or missile is on a side's map only while one of
## its sensors sees it: a radar (far; a mobile one less far), a SAM's own
## radar, an AA gun's or a mobile unit's eyes and thermal sights, or the
## people at any of its sites (close round them). Night and weather shorten
## what is seen by eye; radars see through them. Once lost, a track is kept
## for a while (LiteRules.TRACK_HOLD), its place reckoned from its last
## heading and less sure all the time (LiteWeapon.believed, doubt). A
## ballistic launch is seen at once (early warning) and kept.
##
## The network: an air defence site within a working radar's reach (its
## range times LiteRules.LINK_K) is linked to it: it is cued by the radar's
## picture, and fights better (see LiteSim.air_defence). A radar heavily
## damaged, or out of power (a substation down near it), links nothing.
##
## Gameplay only; LiteCmdView draws it.

## Each side's sensors this look round: where, and how far each sees drones,
## cruise missiles (squared).
static var _at: Array = [PackedVector2Array(), PackedVector2Array()]
## The weather's factors for this pass (worked out once, see _env).
static var _opt: float = 1.0
static var _opt_t: float = 1.0
static var _rad: float = 1.0
static var _env_at: float = -1.0
static var _link_at: float = -1.0

static func _env(sim: LiteSim) -> void:
	if sim.time == _env_at:
		return
	_env_at = sim.time
	_opt = sim.env.optical(false)
	_opt_t = sim.env.optical(true)
	_rad = sim.env.radar()
static var _r2: Array = [[PackedFloat32Array(), PackedFloat32Array()], [PackedFloat32Array(), PackedFloat32Array()]]

## Whether a radar (RADAR, MRADAR, or a SAM's own) works now.
static func radar_works(sim: LiteSim, b: LiteBuilding) -> bool:
	if not b.alive or not b.ready or b.condition >= 2:
		return false
	if b.kind == LiteKind.SAM and sim.time < sim.sam_off_until[b.side]:
		return false
	return true

## How far `b` sees a weapon of arm `a` now.
static func sees(sim: LiteSim, b: LiteBuilding, a: int) -> float:
	_env(sim)
	var radar: bool = LiteRules.by_radar(b.kind)
	if radar and not radar_works(sim, b):
		# A dead radar's crew still look up.
		return LiteRules.sense_range(LiteKind.FACTORY) * _opt * LiteRules.sense_k(false, a)
	var r: float = LiteRules.sense_range(b.kind) * LiteRules.sense_k(radar, a)
	if radar:
		r *= _rad
		if LiteKind.is_radar(b.kind):
			if b.condition == 1:
				r *= 0.8
			if sim.time < sim.grid_off_until[b.side] and b.pos.distance_to(sim.grid_off_at[b.side]) < LiteRules.GRID_REACH:
				r *= LiteRules.GRID_CUT_K
	else:
		r *= _opt_t if b.kind == LiteKind.MOBILE else _opt
		# The land: forest hides what flies low; the open steppe and plains
		# let eyes see further.
		match b.biome:
			LiteBiome.FOREST: r *= 0.85
			LiteBiome.STEPPE, LiteBiome.PLAINS, LiteBiome.DESERT: r *= 1.08
	return r

## How far a working radar links air defence.
static func link_range(sim: LiteSim, r: LiteBuilding) -> float:
	return sees(sim, r, LiteArm.DRONE) / LiteRules.sense_k(true, LiteArm.DRONE) * LiteRules.LINK_K

## Works out each side's network: which air defence is linked to which
## radar (twice a second: it changes only as sites come and go).
static func link(sim: LiteSim) -> void:
	if sim.time - _link_at < 0.5 and sim.time >= _link_at:
		return
	_link_at = sim.time
	var radars: Array = [[], []]
	# (Packed arrays are values: kept in a plain Array of floats instead.)
	var reach: Array = [[], []]
	for b: LiteBuilding in sim.buildings:
		if b.alive and LiteKind.is_radar(b.kind) and radar_works(sim, b):
			radars[b.side].append(b)
			var lr: float = link_range(sim, b)
			reach[b.side].append(lr * lr)
	for b: LiteBuilding in sim.buildings:
		if not b.alive or not LiteKind.shoots(b.kind):
			continue
		var best: LiteBuilding = null
		var bd: float = INF
		var rs: Array = radars[b.side]
		var r2: Array = reach[b.side]
		for i: int in rs.size():
			var r: LiteBuilding = rs[i]
			var d: float = r.pos.distance_squared_to(b.pos)
			if d <= float(r2[i]) and d < bd:
				bd = d
				best = r
		b.link = best
		b.linked = best != null

## Links worked out again at the next pass (a site built or lost).
static func relink() -> void:
	_link_at = -1.0

## The air defence that would lose its link if radar `r` went: linked to it,
## and no other working radar in reach.
static func would_lose(sim: LiteSim, r: LiteBuilding) -> int:
	var n: int = 0
	for b: LiteBuilding in sim.buildings:
		if not b.alive or b.link != r:
			continue
		var other: bool = false
		for o: LiteBuilding in sim.buildings:
			if o != r and o.alive and o.side == b.side and LiteKind.is_radar(o.kind) and radar_works(sim, o) and o.pos.distance_to(b.pos) <= link_range(sim, o):
				other = true
				break
		if not other:
			n += 1
	return n

## One look round (ten a second): who sees what.
static func detect(sim: LiteSim) -> void:
	for v: int in 2:
		var at: PackedVector2Array = _at[v]
		var rd: PackedFloat32Array = _r2[v][0]
		var rc: PackedFloat32Array = _r2[v][1]
		at.clear()
		rd.clear()
		rc.clear()
		for b: LiteBuilding in sim.buildings:
			if b.side != v or not b.alive or not b.ready:
				continue
			var d: float = sees(sim, b, LiteArm.DRONE)
			var c: float = sees(sim, b, LiteArm.CRUISE)
			at.append(b.pos)
			rd.append(d * d)
			rc.append(c * c)
		_at[v] = at
		_r2[v][0] = rd
		_r2[v][1] = rc
	var now: float = sim.time
	for w: LiteWeapon in sim.weapons:
		if not w.alive:
			continue
		var v: int = 1 - w.side
		var seen: bool = false
		if w.arm == LiteArm.BALLISTIC:
			# Early warning: a ballistic launch is seen at once, and kept.
			seen = true
		else:
			var at: PackedVector2Array = _at[v]
			var r2: PackedFloat32Array = _r2[v][0 if w.arm == LiteArm.DRONE else 1]
			for i: int in at.size():
				if at[i].distance_squared_to(w.pos) <= r2[i]:
					seen = true
					break
		if seen:
			w.seen[v] = true
			w.seen_at[v] = now
			w.seen_pos[v] = w.pos
			w.seen_dir[v] = w.dir
			w.lost[v] = 0.0
			if not w.ever_seen[v]:
				w.ever_seen[v] = true
				sim.events.append(LiteEvent.new(LiteEv.DETECTED, w.side, sim.map.region_at(w.pos), w.pos, w.arm, 0, 0, w.raid))
		elif w.seen[v]:
			w.lost[v] = now - w.seen_at[v]
			if w.lost[v] > LiteRules.TRACK_HOLD:
				w.seen[v] = false

## Whether side `v` sees weapon `w` right now (not a held track).
static func sighted(w: LiteWeapon, v: int) -> bool:
	return w.side == v or (w.seen[v] and w.lost[v] <= 0.0)
