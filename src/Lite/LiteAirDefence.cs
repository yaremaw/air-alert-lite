using System;
using Godot;

/// Air defence engagement. A system sees and fires only inside its radar
/// sector: a cone of AdArc degrees facing where its owner turned it, out to
/// its range. It tracks at most AdChannels weapons at a time and fires one
/// interceptor per channel every AdShotInterval seconds, each with a chance
/// to hit that depends on the weapon. So a weapon crossing the middle of the
/// cone is shot at many times and one clipping its edge a few; many weapons
/// at once from several directions are more than its channels can track.
public sealed class LiteAirDefence
{
	private readonly LiteSim _s;
	private readonly Random _rng;

	public LiteAirDefence(LiteSim sim, Random rng)
	{
		_s = sim;
		_rng = rng;
	}

	/// Whether `p` lies inside the system's radar sector (as it faces now).
	public static bool InSector(LiteBuilding b, Vector2 p) => InSector(b.Pos, b.Facing, p);

	public static bool InSector(Vector2 at, float facing, Vector2 p)
	{
		var d = p - at;
		if (d.LengthSquared() > LiteRules.AdRange * LiteRules.AdRange) return false;
		if (d.LengthSquared() < 1) return true;
		return MathF.Abs(Mathf.AngleDifference(facing, d.Angle())) <= Mathf.DegToRad(LiteRules.AdArc) / 2;
	}

	public void Step(float dt)
	{
		float turn = Mathf.DegToRad(LiteRules.AdTurnRate) * dt;
		foreach (var b in _s.Buildings)
		{
			if (!b.Alive || !b.IsAd || !b.Ready) continue;
			b.Facing = Mathf.RotateToward(b.Facing, b.TargetFacing, turn);
			for (int c = 0; c < LiteRules.AdChannels; c++)
			{
				var t = b.Tracks[c];
				if (t != null && (!t.Alive || !InSector(b, t.Pos))) b.Tracks[c] = t = null;
				t ??= b.Tracks[c] = Acquire(b);
				b.ChannelCool[c] -= dt;
				if (t == null || b.ChannelCool[c] > 0) continue;
				b.ChannelCool[c] = LiteRules.AdShotInterval;
				b.FireFlash = 1;
				_s.Interceptors.Add(new LiteInterceptor { Side = b.Side, Target = t, From = b, Pos = b.Pos, Goal = t.Pos });
				_s.Fx.Add(new LiteFx { Kind = LiteFxKind.Launch, A = b.Pos, Life = 0.5f, Side = b.Side });
				_s.Spot(b, 1 - b.Side);
			}
		}
		MoveInterceptors(dt);
	}

	/// The nearest enemy weapon in the sector that this system is not already tracking.
	private LiteWeapon? Acquire(LiteBuilding b)
	{
		LiteWeapon? best = null;
		float bd = float.MaxValue;
		foreach (var w in _s.Weapons)
		{
			if (!w.Alive || w.Side == b.Side || Array.IndexOf(b.Tracks, w) >= 0 || !InSector(b, w.Pos)) continue;
			float d = w.Pos.DistanceSquaredTo(b.Pos);
			if (d < bd) { bd = d; best = w; }
		}
		return best;
	}

	private void MoveInterceptors(float dt)
	{
		foreach (var i in _s.Interceptors)
		{
			if (!i.Alive) continue;
			i.Age += dt;
			if (i.Target.Alive) i.Goal = i.Target.Pos;
			var to = i.Goal - i.Pos;
			float step = LiteRules.InterceptorSpeed * dt, d = to.Length();
			i.Trail.Add(i.Pos);
			if (i.Trail.Count > 8) i.Trail.RemoveAt(0);
			if (d > step + 3 && i.Age < 4f) { i.Pos += to / d * step; continue; }
			i.Pos = i.Goal;
			i.Alive = false;
			if (i.Target.Alive && _rng.NextDouble() < LiteRules.AdHit(i.Target.Arm)) _s.Kill(i.Target, i.Side, i.From);
			else _s.Fx.Add(new LiteFx { Kind = LiteFxKind.Puff, A = i.Pos, Life = 0.45f, Size = 4, Side = i.Side });
		}
	}
}
