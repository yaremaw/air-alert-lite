class_name LitePerf
extends RefCounted

static var sim_ms: float = 0.0
static var draw_ms: float = 0.0
static var ui_ms: float = 0.0
static var ui_proc_ms: float = 0.0
## Time by section (ms, summed since reset), for the profiling probes.
static var sec: Dictionary = {}

static func add(key: String, t0: float) -> void:
	sec[key] = float(sec.get(key, 0.0)) + (Time.get_ticks_usec() / 1000.0 - t0)

static var now: float:
	get: return Time.get_ticks_usec() / 1000.0

static func reset() -> void:
	sim_ms = 0
	draw_ms = 0
	ui_ms = 0
	ui_proc_ms = 0
	sec.clear()

static func monitors() -> String:
	return ("draw calls %d, " % roundi(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))) + ("objects %d, " % roundi(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))) + ("primitives %d" % roundi(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
