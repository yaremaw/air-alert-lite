class_name LiteAudio
extends Node
## The lite game's sounds, from the shared assets/audio folder. A small pool
## of players; the same sound is not repeated closer than its gap, so a
## swarm shot down at once is a crackle, not a wall of noise.

const DIR: String = "res://assets/audio/"
var _pool: Array[AudioStreamPlayer] = []
## file -> AudioStream (or null when the file does not exist)
var _cache: Dictionary = {}
## file -> seconds when it last played
var _last: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next: int = 0
## Sirens get a voice of their own: a long wail is never stacked on itself.
var _siren: AudioStreamPlayer


func _init() -> void:
	_rng.randomize()


func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
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


## Sounds a siren unless that one is already wailing; another one cuts in.
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


func click() -> void:
	play("click.wav", -8.0, 0.03, 0.03)
