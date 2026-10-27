using System;
using System.Collections.Generic;
using Godot;

/// The lite game's sounds, from the shared assets/audio folder. A small pool
/// of players; the same sound is not repeated closer than its gap, so a
/// swarm shot down at once is a crackle, not a wall of noise.
public partial class LiteAudio : Node
{
	private const string Dir = "res://assets/audio/";
	private readonly List<AudioStreamPlayer> _pool = new();
	private readonly Dictionary<string, AudioStream?> _cache = new();
	private readonly Dictionary<string, double> _last = new();
	private readonly Random _rng = new();
	private int _next;

	public override void _Ready()
	{
		for (int i = 0; i < 12; i++)
		{
			var p = new AudioStreamPlayer { Bus = "Master" };
			AddChild(p);
			_pool.Add(p);
		}
	}

	public void Play(string file, float db = 0f, double gap = 0.06, float pitchJitter = 0.05f)
	{
		double now = Time.GetTicksMsec() / 1000.0;
		if (_last.TryGetValue(file, out var t) && now - t < gap) return;
		_last[file] = now;
		if (!_cache.TryGetValue(file, out var stream))
		{
			stream = ResourceLoader.Exists(Dir + file) ? GD.Load<AudioStream>(Dir + file) : null;
			_cache[file] = stream;
		}
		if (stream == null || _pool.Count == 0) return;
		var p = _pool[_next];
		_next = (_next + 1) % _pool.Count;
		p.Stream = stream;
		p.VolumeDb = db;
		p.PitchScale = 1f + ((float)_rng.NextDouble() * 2 - 1) * pitchJitter;
		p.Play();
	}

	public void Click() => Play("click.wav", -8f, 0.03, 0.03f);
}
