class_name LiteMotion
extends RefCounted
## Where moving things are drawn and which way they point, eased out of
## sudden changes: a visual layer kept apart from where they really are. The
## sim's state is only read here, never written, so the war plays the same.
##
## Each frame: begin(), then track() each moving thing with where it really is
## now, which way it really points and how far it could move in the frame,
## then end() (which forgets the things not tracked this frame). Drawing asks
## pos() and angle().
##
## Position: drawn = real + offset. Steady motion is drawn exactly where it is,
## with no lag; only a step longer than the thing could have made in the frame
## (a jump) goes into the offset, which then fades out over POS_TIME, so the
## thing glides across instead of jumping.
## Heading: eased towards the real one at TURN_RATE, so a corner taken in one
## step turns over a few frames instead of snapping.
##
## Both are timed in real seconds, the same at any frame rate; a frame of 0
## seconds (the war paused) moves nothing.

## Seconds for a jump's offset to fade to about a third.
const POS_TIME: float = 0.12
## How fast a heading catches up, per second (about 95% in 0.15 s).
const TURN_RATE: float = 20.0

class State:
	var real: Vector2 = Vector2.ZERO
	var offset: Vector2 = Vector2.ZERO
	var angle: float = 0.0
	var stamp: int = 0

var _s: Dictionary = {}
var _stamp: int = 0
var _dt: float = 0.0

## A frame of `dt` real seconds (0 while nothing moves).
func begin(dt: float) -> void:
	_dt = maxf(0.0, dt)
	_stamp += 1

## One moving thing (any object, used as its key): where it really is, which
## way it really points (radians) and how far it could move this frame.
## With `face_motion` it is drawn pointing the way it is actually seen to
## move (its drawn velocity), not the way it says it points: a thing drawn
## off its track (in a lane, on a curve) never seems to slide sideways.
func track(key: Object, real_pos: Vector2, real_angle: float, max_step: float, face_motion: bool = false) -> void:
	var s: State = _s.get(key)
	if s == null:
		s = State.new()
		s.real = real_pos
		s.angle = real_angle
		s.stamp = _stamp
		_s[key] = s
		return
	s.stamp = _stamp
	if _dt <= 0.0:
		return
	var drawn_before: Vector2 = s.real + s.offset
	var step: Vector2 = real_pos - s.real
	if step.length() > max_step:
		# A jump: drawn on from where it was, the part of the step it could
		# not have made taken into the offset.
		s.offset -= step - step.limit_length(max_step)
	s.offset *= exp(-_dt / POS_TIME)
	if s.offset.length_squared() < 0.0001:
		s.offset = Vector2.ZERO
	s.real = real_pos
	var want: float = real_angle
	if face_motion:
		var moved: Vector2 = s.real + s.offset - drawn_before
		# Too small a step to tell a direction from: it keeps its heading.
		want = moved.angle() if moved.length_squared() > 0.0004 else s.angle
	s.angle += angle_difference(s.angle, want) * (1.0 - exp(-_dt * TURN_RATE))

## Forgets the things not tracked this frame (gone from the war).
func end() -> void:
	for k: Variant in _s.keys():
		if (_s[k] as State).stamp != _stamp:
			_s.erase(k)

## Where a thing is drawn (`real` if it isn't tracked).
func pos(key: Object, real: Vector2) -> Vector2:
	var s: State = _s.get(key)
	return s.real + s.offset if s != null else real

## Which way a thing is drawn pointing (`real` if it isn't tracked).
func angle(key: Object, real: float) -> float:
	var s: State = _s.get(key)
	return s.angle if s != null else real

## The same as a unit vector.
func dir(key: Object, real: Vector2) -> Vector2:
	var s: State = _s.get(key)
	return Vector2.from_angle(s.angle) if s != null else real

## How many things it is following (for tests).
func count() -> int:
	return _s.size()
