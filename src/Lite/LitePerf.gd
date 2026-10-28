class_name LitePerf
extends RefCounted
## Frame timings for the lite game: how long the sim and the map drawing
## take on the CPU. Read by the stress stage of the screenshot run.

static var sim_ms: float = 0.0
static var draw_ms: float = 0.0
static var ui_ms: float = 0.0
static var ui_proc_ms: float = 0.0

## Milliseconds since the engine started (was a Stopwatch in C#).
static var now: float:
	get: return Time.get_ticks_usec() / 1000.0


static func reset() -> void:
	sim_ms = 0
	draw_ms = 0
	ui_ms = 0
	ui_proc_ms = 0


static func monitors() -> String:
	return ("draw calls %d, " % roundi(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))) + \
		("objects %d, " % roundi(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))) + \
		("primitives %d" % roundi(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
