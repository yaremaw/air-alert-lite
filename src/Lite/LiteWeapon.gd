class_name LiteWeapon
extends RefCounted

var id: int = 0
var side: int = 0
var leg: int = 0
var engaged: int = 0
var arm: int = 0
var raid: LiteRaid = null
var pos: Vector2 = Vector2.ZERO
var start: Vector2 = Vector2.ZERO
var target: Vector2 = Vector2.ZERO
var dir: Vector2 = Vector2.ZERO
var speed: float = 0.0
var length: float = 0.0
var flown: float = 0.0
var alive: bool = true
## A jet attack drone (see LiteRules.JET_SPEED), not a propeller one.
var jet: bool = false
## The bomb (see LiteSim.nuke).
var nuke: bool = false

var aim: LiteBuilding = null
## The attack it belongs to (enemy weapons, for the attack report) and our
## regions it has crossed (for the statistics).
var report: LiteReport = null
var crossed: Dictionary = {}

## Whether each side has it on its map now: its own always; the other side
## while a sensor of its sees it (see LiteSense) and for a while after, as a
## track that grows less sure (`lost`).
var seen: Array[bool] = [false, false]
## Per side: when it was last seen, where and heading which way, for a lost
## track's reckoned place; and how long it has been lost (0 while seen).
var seen_at: PackedFloat32Array = PackedFloat32Array([-99.0, -99.0])
var seen_pos: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
var seen_dir: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
var lost: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
## Whether it has been seen at all (a first sighting is news).
var ever_seen: Array[bool] = [false, false]
var path: PackedVector2Array = PackedVector2Array()

## Sent on to a new target after its own was destroyed (see LiteSim.retarget):
## it keeps its place, heading and speed and turns towards the new target at
## `turn_rate`, rather than following a route.
var homing: bool = false
## Turned back home by a storm (see LiteSim._storm_check): it lands there.
var recalled: bool = false
## Whether it has flown into an enemy jammer's reach yet (it is tried once).
var jam_done: bool = false

## Where a side believes it is: where it is, while seen; its last sighting
## carried on along its heading, while lost.
func believed(v: int) -> Vector2:
	if v == side or lost[v] <= 0.0:
		return pos
	return seen_pos[v] + seen_dir[v] * speed * lost[v]

## How far off that belief may be (map units): growing while it is lost.
func doubt(v: int) -> float:
	return 0.0 if v == side else lost[v] * speed * 0.35

## How fast it can turn while homing, in radians a second: a drone turns
## tightly, a cruise missile makes wider corrections. (A ballistic missile
## never retargets.)
func turn_rate() -> float:
	return 1.8 if arm == LiteArm.DRONE else 1.1

## Drones and cruise missiles of one salvo fly side by side, not nose to
## tail on one line: each keeps to its own lane, `lane` widths to the side of
## the route (see LANE), closing in near the launcher and the target. `off` is
## how far it is drawn off its track now, eased so it never jumps at a turn.
const LANE: float = 6.0
var lane: float = 0.0
var off: Vector2 = Vector2.ZERO

## A ballistic missile's arc is drawn square to its flight on screen, towards
## the top (`arc`, a unit vector), so it looks the same on both sides of its
## highest point, `top` map units up.
var arc: Vector2 = Vector2.UP
var top: float = 0.0
var progress: float:
	get: return flown / length if length > 0 else 1.0

## How high it flies now, in map units, for drawing it above its shadow; the
## sim itself only follows the ground track (`pos`). Drones and cruise
## missiles keep low. A ballistic missile flies a parabola: up off its
## launcher, over the top halfway, and down as steeply as it went up.
func altitude() -> float:
	return altitude_at(progress)

func altitude_at(p: float) -> float:
	match arm:
		LiteArm.DRONE: return 5.0
		LiteArm.CRUISE: return 4.0
	var q: float = clampf(p, 0.0, 1.0)
	return top * 4.0 * q * (1.0 - q)

## How far its drawing is moved off its ground track, as a vector.
func lift_vec() -> Vector2:
	return arc * altitude() if arm == LiteArm.BALLISTIC else Vector2.ZERO

## Where it is drawn: a ballistic missile up on its arc, the others in their lane.
func view_pos() -> Vector2:
	return pos + lift_vec() if arm == LiteArm.BALLISTIC else pos + off

## Sets up a ballistic missile's arc: square to the line from launcher to
## target, on its upper side, tall (its top about three quarters as high as
## the flight is long) but kept inside `bounds`, the part of the map on screen.
func setup_arc(bounds: Rect2) -> void:
	var chord: Vector2 = target - start
	var n:= Vector2(chord.y, -chord.x)
	n = n.normalized() if n.length() > 0.001 else Vector2.UP
	if n.y > 0.0 or (absf(n.y) < 0.001 and n.x > 0.0):
		n = -n
	arc = n
	var mid: Vector2 = (start + target) * 0.5
	var t: float = clampf(length * 0.75, 90.0, 300.0)
	if n.x < -0.001: t = minf(t, (mid.x - bounds.position.x) / -n.x)
	if n.x > 0.001: t = minf(t, (bounds.end.x - mid.x) / n.x)
	if n.y < -0.001: t = minf(t, (mid.y - bounds.position.y) / -n.y)
	if n.y > 0.001: t = minf(t, (bounds.end.y - mid.y) / n.y)
	top = maxf(50.0, t)

## Puts it in its lane from the moment it is launched, so its trail starts
## straight instead of swinging out to the side.
func enter_lane() -> void:
	off = Vector2(-dir.y, dir.x) * (lane * LANE)

## Keeps it in its lane through the turns, closing in as it nears its target.
## `ease` is how far it moves towards its lane this step (0 to 1).
func steer_lane(ease: float) -> void:
	if lane == 0.0:
		# Out of its lane (sent on alone to a new target): it eases back onto
		# its track, never jumping.
		off = off.lerp(Vector2.ZERO, ease)
		return
	var e: float = minf(1.0, pos.distance_to(target) / 45.0)
	var want: Vector2 = Vector2(-dir.y, dir.x) * (lane * LANE * e)
	off = off.lerp(want, ease)
