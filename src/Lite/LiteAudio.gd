class_name LiteAudio
extends Node

const DIR: String = "res://assets/audio/"
var _pool: Array[AudioStreamPlayer] = []

var _cache: Dictionary = {}

var _last: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next: int = 0

var _siren: AudioStreamPlayer
## Engine sounds that loop while their source is about: player and level.
var _loops: Dictionary = {}
var _loop_level: Dictionary = {}

func _init() -> void:
	_rng.randomize()

func _ready() -> void:
	for i in 12:
		var p:= AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_siren = AudioStreamPlayer.new()
	_siren.bus = "Master"
	add_child(_siren)

func _stream(file: String) -> AudioStream:
	if not _cache.has(file):
		_cache[file] = load(DIR + file) as AudioStream if ResourceLoader.exists(DIR + file) else null
	return _cache[file]

func siren(file: String, db: float = 0.0) -> void:
	var stream: AudioStream = _stream(file)
	if stream == null or (_siren.playing and _siren.stream == stream):
		return
	_siren.stream = stream
	_siren.volume_db = db
	_siren.play()

func play(file: String, db: float = 0.0, gap: float = 0.06, pitch_jitter: float = 0.05) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if _last.has(file) and now - float(_last[file]) < gap:
		return
	_last[file] = now
	var stream: AudioStream = _stream(file)
	if stream == null or _pool.size() == 0:
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = 1.0 + (_rng.randf() * 2 - 1) * pitch_jitter
	p.play()

## A looping sound whose loudness follows `level` (0 silent, 1 full), fading
## at `fade` of full per second; at full it plays at `max_db`. `key` lets one
## file loop on several players; `from_start` starts it at its beginning
## rather than somewhere inside.
func loop(file: String, level: float, max_db: float, delta: float, fade: float = 1.2,
		key: String = "", from_start: bool = false) -> void:
	if key == "":
		key = file
	var p: AudioStreamPlayer = _loops.get(key) as AudioStreamPlayer
	if p == null:
		var src: AudioStreamWAV = _stream(file) as AudioStreamWAV
		if src == null:
			return
		var s: AudioStreamWAV = src.duplicate() as AudioStreamWAV
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
		p = AudioStreamPlayer.new()
		p.stream = s
		p.bus = "Master"
		p.volume_db = -60.0
		add_child(p)
		_loops[key] = p
	var cur: float = move_toward(float(_loop_level.get(key, 0.0)), level, delta * fade)
	_loop_level[key] = cur
	if cur <= 0.01:
		if p.playing:
			p.stop()
		return
	if not p.playing:
		p.play(0.0 if from_start else _rng.randf() * p.stream.get_length())
	p.volume_db = max_db + linear_to_db(cur)

func click() -> void:
	play("click.wav", -8.0, 0.03, 0.03)
