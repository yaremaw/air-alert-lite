using System;
using System.Collections.Generic;
using Godot;

/// A side's commander, used for the enemy (and for our side in the test
/// and screenshot runs). It knows only what its side has seen. Part of its
/// income is saved for raids; the rest builds factories and puts air
/// defence where the other side's weapons have been landing.
///
/// A raid goes at up to four known sites, each sent about as many weapons
/// as its health needs after the losses the defence there is likely to
/// cause, and flies round the air defence it knows of. Scouts go to regions
/// not yet flown over.
///
/// With waves on (Normal and Hard) it also weighs up a massive strike: what
/// the sites it knows of are worth against what it would take to overwhelm
/// the defence round them. When one is worth it and affordable within a few
/// minutes it starts massing (the other side's intelligence notices), keeps
/// its small raids small, and launches once the money is there: drones from
/// all sides arriving together to drain the air defence, missiles behind
/// them. Adaptive (Hard) also sends cruise missiles ahead of the wave at the
/// air defence that has shot down the most, and drones as a feint at the
/// other end of the country.
///
/// Defence comes first: SAMs and guns round the capital, more as the war
/// goes on, a gun by every factory, and air defence where weapons came down.
/// When the capital is short of it, money is taken from the war fund.
public sealed class LiteAi
{
	public readonly int Side;
	/// Share of income kept for raids.
	public float WarShare = 0.5f;
	/// Plans its raids: weapons sized to the target, routes round known air
	/// defence. Off on Easy, where raids go straight and in rough numbers.
	public bool Smart = true;
	/// Time between raids, as a share of the usual.
	public float Tempo = 1f;
	/// Saves up for massive waves (Normal, Hard).
	public bool Waves;
	/// Goes for the air defence that hurts it most, and feints (Hard).
	public bool Adaptive;
	/// Saving up for a massive strike on `_plan`.
	public bool Massing;
	private float _waveCost, _massSince, _planAt = 90f;
	private readonly List<LiteBuilding> _plan = new();
	private readonly Random _rng;
	private float _think, _nextRaid, _lastFactory = -99f;
	private int _raids;
	private readonly List<LiteBuilding> _targets = new();
	private readonly HashSet<int> _scouted = new();

	public LiteAi(int side, int seed, float firstRaid)
	{
		Side = side;
		_rng = new Random(seed);
		_nextRaid = firstRaid;
	}

	private float R(float a, float b) => a + (float)_rng.NextDouble() * (b - a);

	public void Tick(LiteSim s, float dt)
	{
		var me = s.Sides[Side];
		me.WarFund = Math.Min(me.WarFund + me.Income * WarShare * dt, me.Money);
		_think -= dt;
		if (_think > 0) return;
		_think = R(0.7f, 1.3f);
		s.SamsOnDrones[Side] = me.Money > 60;
		Defend(s, me);
		Grow(s, me);
		Attack(s, me);
	}

	private float Free(LiteSide me) => me.Money - me.WarFund;

	/// Pays for a building out of spare money, or, when `urgent`, out of the
	/// war fund as well.
	private bool Afford(LiteSim s, LiteSide me, LiteKind kind, bool urgent)
	{
		int cost = s.Cost(Side, kind);
		if (Free(me) >= cost) return true;
		if (!urgent || me.Money < cost) return false;
		me.WarFund = Math.Max(0, me.Money - cost);
		return true;
	}

	private bool Put(LiteSim s, LiteKind kind, Vector2 near, float rMin, float rMax)
	{
		var p = s.FindSpot(Side, near, rMin, rMax);
		return p != null && s.Build(Side, kind, p.Value) != null;
	}

	private void Defend(LiteSim s, LiteSide me)
	{
		me.HitLog.RemoveAll(h => s.Time - h.T > 25);
		// 1. The capital: SAMs and guns, more as the war goes on.
		int capSam = 0, capGun = 0;
		foreach (var b in s.Buildings)
		{
			if (!b.Alive || b.Side != Side || b.Pos.DistanceTo(me.Capital.Pos) > 70) continue;
			if (b.Kind == LiteKind.Sam) capSam++;
			else if (b.Kind == LiteKind.Gun) capGun++;
		}
		int wantSam = Math.Min(4, 1 + (int)(s.Time / 240)), wantGun = Math.Min(4, 1 + (int)(s.Time / 300));
		if (capSam < wantSam)
		{
			if (Afford(s, me, LiteKind.Sam, true)) Put(s, LiteKind.Sam, me.Capital.Pos, 16, 45);
			return;
		}
		if (capGun < wantGun)
		{
			if (Afford(s, me, LiteKind.Gun, true)) Put(s, LiteKind.Gun, me.Capital.Pos, 18, 50);
			return;
		}
		// 2. Where the other side's weapons came down near something of ours.
		for (int i = 0; i < me.HitLog.Count; i++)
		{
			var h = me.HitLog[i];
			bool valuable = false;
			foreach (var b in s.Buildings)
				if (b.Alive && b.Side == Side && b.Pos.DistanceTo(h.P) < 35) { valuable = true; break; }
			float cov = s.Coverage(Side, h.P);
			if (!valuable || cov >= 3) continue;
			var kind = cov < 1 && Free(me) >= s.Cost(Side, LiteKind.Sam) + 20 && _rng.NextDouble() < 0.5 ? LiteKind.Sam : LiteKind.Gun;
			if (!Afford(s, me, kind, false)) return;
			if (Put(s, kind, h.P, 8, 30)) me.HitLog.RemoveAt(i);
			return;
		}
		// 3. A gun by every factory; then spare money for the least covered.
		LiteBuilding? weak = null;
		float low = 2;
		foreach (var b in s.Buildings)
		{
			if (!b.Alive || b.Side != Side || b.Kind != LiteKind.Factory) continue;
			float c = s.Coverage(Side, b.Pos);
			if (c < 1 && Afford(s, me, LiteKind.Gun, false)) { Put(s, LiteKind.Gun, b.Pos, 12, 30); return; }
			if (c < low) { low = c; weak = b; }
		}
		if (weak == null || Free(me) < 250 || s.Time < 50) return;
		Put(s, low < 2 ? LiteKind.Sam : LiteKind.Gun, weak.Pos, 12, 30);
	}

	private void Grow(LiteSim s, LiteSide me)
	{
		int factories = 0;
		foreach (var b in s.Buildings) if (b.Alive && b.Side == Side && b.Kind == LiteKind.Factory) factories++;
		int cap = 2 + (int)(s.Time / 45);
		if (factories >= cap || Free(me) < s.Cost(Side, LiteKind.Factory) + 20 || s.Time - _lastFactory < 9) return;
		// A region with room: the further from the other side's capital the
		// safer, but a region with more room counts for something too.
		var enemyCap = s.Sides[1 - Side].Capital.Pos;
		int best = -1;
		float bestScore = float.MinValue;
		foreach (var r in s.Map.Regions)
		{
			if (r.Side != Side || r.City || s.FreeSlots(r.Id) <= 0) continue;
			float score = r.Label.DistanceTo(enemyCap) + 40 * s.FreeSlots(r.Id) + R(0, 160);
			if (score > bestScore) { bestScore = score; best = r.Id; }
		}
		if (best >= 0 && s.BuildFactory(Side, best) != null) _lastFactory = s.Time;
	}

	private void Attack(LiteSim s, LiteSide me)
	{
		if (Waves)
		{
			if (!Massing && s.Time >= _planAt) PlanWave(s, me);
			else if (Massing && (Math.Min(me.WarFund, me.Money) >= _waveCost || s.Time - _massSince > 240))
			{
				Wave(s, me);
				Massing = false;
				_planAt = s.Time + R(120, 200) * Tempo;
				_nextRaid = Math.Max(_nextRaid, s.Time + 25);
				return;
			}
		}
		if (s.Time < _nextRaid) return;
		// While massing, small raids stay small.
		float budget = Math.Min(me.WarFund, me.Money) * (Massing ? 0.2f : Waves ? 0.6f : 1f);
		if (budget < 50) { _nextRaid = s.Time + 4; return; }
		float before = me.Money;
		_raids++;
		_targets.Clear();
		int known = 0;
		foreach (var b in s.Buildings)
			if (b.Alive && b.Side != Side && b.Seen[Side]) { _targets.Add(b); if (b.Kind != LiteKind.Capital) known++; }

		if (known == 0 || _rng.NextDouble() < 0.1) Scout(s, Math.Min(4, (int)(budget / LiteRules.Cost(LiteArm.Drone))));
		else
		{
			LiteRaid? raid = null;
			float delay = 0;
			for (int k = 0; k < 4 && _targets.Count > 0 && budget >= LiteRules.Cost(LiteArm.Drone); k++)
			{
				var t = Pick(s, me);
				_targets.Remove(t);
				float cov = s.KnownCoverage(Side, t.Pos);
				// The share likely to be shot down: what the defence there looks
				// like, and how the last raid fared.
				float loss = Math.Clamp(0.1f + 0.14f * cov + 0.4f * me.LastRaidLoss, 0.1f, 0.85f);
				float hp = t.Kind == LiteKind.Capital ? Math.Min(t.Hp, 30) : t.Hp;
				var route = Smart ? Route(s, me, t.Pos) : null;
				if (!Smart) loss = 0.5f;
				int bal = 0, cru = 0;
				if (t.Kind is LiteKind.Capital or LiteKind.Sam && s.Time > 150 && budget >= 400 && _rng.NextDouble() < 0.5)
					bal = Math.Min(3, (int)(budget * 0.3f / LiteRules.Cost(LiteArm.Ballistic)));
				if (cov >= 2 && s.Time > 60 && budget >= 200)
					cru = Math.Min(8, (int)Math.Ceiling(hp * 0.5f / LiteRules.Damage(LiteArm.Cruise) / (1 - loss * 0.7f)));
				float left = hp - bal * LiteRules.Damage(LiteArm.Ballistic) * 0.5f - cru * LiteRules.Damage(LiteArm.Cruise) * (1 - loss * 0.7f);
				int dr = Math.Max(left > 0 ? 1 : 0, (int)Math.Ceiling(left / (1 - loss)) + (left > 0 ? 1 : 0));
				cru = Math.Min(cru, (int)((budget - bal * LiteRules.Cost(LiteArm.Ballistic)) / LiteRules.Cost(LiteArm.Cruise)));
				dr = Math.Min(dr, (int)((budget - bal * LiteRules.Cost(LiteArm.Ballistic) - cru * LiteRules.Cost(LiteArm.Cruise)) / LiteRules.Cost(LiteArm.Drone)));
				dr = Math.Min(dr, 30);
				// Drones go first; the missiles are timed to arrive with them.
				float dist = t.Pos.DistanceTo(me.Capital.Pos);
				float tDrone = dist / LiteRules.Speed(LiteArm.Drone) * 1.15f;
				if (dr > 0) raid = s.Strike(Side, LiteArm.Drone, t.Pos, dr, raid, delay, route) ?? raid;
				if (cru > 0) raid = s.Strike(Side, LiteArm.Cruise, t.Pos, cru, raid, delay + Math.Max(0, tDrone - dist / LiteRules.Speed(LiteArm.Cruise) * 1.3f), route) ?? raid;
				if (bal > 0) raid = s.Strike(Side, LiteArm.Ballistic, t.Pos, bal, raid, delay + Math.Max(0, tDrone - 2f)) ?? raid;
				budget = Math.Min(me.WarFund - (before - me.Money), me.Money) * (Massing ? 0.2f : Waves ? 0.6f : 1f);
				delay += 1.5f;
			}
		}
		me.WarFund = Math.Max(0, me.WarFund - (before - me.Money));
		// A rich side raids more often.
		_nextRaid = s.Time + R(20, 36) * Tempo * (me.WarFund > 600 ? 0.6f : 1f);
	}

	/// Seconds from launch to the target, roughly: drones and ballistic
	/// missiles go up near the front, cruise missiles from deep inside.
	private float Travel(LiteSim s, LiteSide me, Vector2 target, LiteArm arm)
	{
		var from = me.Capital.Pos;
		if (arm != LiteArm.Cruise)
		{
			float bd = float.MaxValue;
			foreach (var r in s.Map.Regions)
				if (r.Side == Side && !r.City && r.Label.DistanceTo(target) < bd) { bd = r.Label.DistanceTo(target); from = r.Label; }
		}
		return from.DistanceTo(target) / LiteRules.Speed(arm) * (arm == LiteArm.Drone ? 1.2f : 1.1f);
	}

	/// What a site is worth to a massive strike.
	private float Worth(LiteSim s, LiteBuilding b, float cov) => b.Kind switch
	{
		LiteKind.Factory => 3f,
		LiteKind.Sam => 2.5f + (Adaptive ? 0.3f * b.Kills : 0),
		LiteKind.Gun => 1f,
		_ => 1f + 4f * (1 - b.Hp / b.MaxHp) + (cov < 2 ? 2f : 0),
	} / (1 + 0.4f * cov);

	/// Drones (and dollars) to break through to `t`: what its health needs
	/// after the expected losses.
	private int DronesFor(LiteSim s, LiteSide me, LiteBuilding t, float cov)
	{
		float loss = Math.Clamp(0.15f + 0.14f * cov + 0.3f * me.LastRaidLoss, 0.15f, 0.85f);
		float hp = t.Kind == LiteKind.Capital ? Math.Min(t.Hp, 40) : t.Hp;
		return Math.Min(40, (int)Math.Ceiling(hp / (1 - loss) * 1.3f) + 2);
	}

	/// Is a massive strike worth it, and affordable within about four
	/// minutes? Then start saving for it on the best few targets.
	private void PlanWave(LiteSim s, LiteSide me)
	{
		_planAt = s.Time + 10;
		var known = new List<(LiteBuilding B, float Score, float Cov)>();
		foreach (var b in s.Buildings)
			if (b.Alive && b.Side != Side && b.Seen[Side])
			{
				float cov = s.KnownCoverage(Side, b.Pos);
				known.Add((b, Worth(s, b, cov) * R(0.85f, 1.15f), cov));
			}
		known.Sort((a, b) => b.Score.CompareTo(a.Score));
		if (known.Count > 4) known.RemoveRange(4, known.Count - 4);
		float reach = me.WarFund + me.Income * WarShare * 240;
		while (known.Count > 0)
		{
			float worth = 0, cost = 0;
			var sams = new HashSet<LiteBuilding>();
			foreach (var (b, score, cov) in known)
			{
				worth += score;
				cost += DronesFor(s, me, b, cov) * LiteRules.Cost(LiteArm.Drone);
				if (cov >= 2) cost += 2 * LiteRules.Cost(LiteArm.Cruise);
				foreach (var o in s.Buildings)
					if (o.Alive && o.Side != Side && o.Seen[Side] && o.Kind == LiteKind.Sam && o.Pos.DistanceTo(b.Pos) <= LiteRules.Range(LiteKind.Sam)) sams.Add(o);
			}
			// Enough extra drones to empty the SAMs on the way.
			cost += sams.Count * LiteRules.SamRack * LiteRules.Cost(LiteArm.Drone);
			if (worth < 4.5f) return;
			if (cost <= reach)
			{
				_plan.Clear();
				foreach (var k in known) _plan.Add(k.B);
				_waveCost = cost;
				Massing = true;
				_massSince = s.Time;
				s.Events.Add(new LiteEvent { Type = LiteEv.Warning, Side = Side, Value = cost });
				return;
			}
			known.RemoveAt(known.Count - 1);
		}
	}

	/// The massive wave: up to five targets, the drones timed to arrive
	/// together, the missiles ten seconds behind them.
	private void Wave(LiteSim s, LiteSide me)
	{
		float budget = Math.Min(me.WarFund, me.Money), before = me.Money;
		if (budget < 100) return;
		_targets.Clear();
		foreach (var b in s.Buildings) if (b.Alive && b.Side != Side && b.Seen[Side]) _targets.Add(b);
		var busiest = new List<LiteBuilding>();
		if (Adaptive)
		{
			foreach (var b in _targets) if (b.Kind == LiteKind.Sam && b.Kills >= 2) busiest.Add(b);
			busiest.Sort((a, b) => b.Kills.CompareTo(a.Kills));
			if (busiest.Count > 2) busiest.RemoveRange(2, busiest.Count - 2);
		}
		// The planned targets that are still there, topped up from the rest.
		var main = _plan.FindAll(b => b.Alive);
		foreach (var b in main) _targets.Remove(b);
		while (main.Count < 3 && _targets.Count > 0) { var t = Pick(s, me); _targets.Remove(t); main.Add(t); }
		if (main.Count == 0) return;
		float arrive = 0;
		foreach (var t in main) arrive = Math.Max(arrive, Travel(s, me, t.Pos, LiteArm.Drone));
		arrive += 4;
		LiteRaid? raid = null;
		float Spend() => before - me.Money;
		// Ahead of the wave, cruise missiles at the air defence that shot down most.
		foreach (var sam in busiest)
			raid = s.Strike(Side, LiteArm.Cruise, sam.Pos, 3, raid, Math.Max(0, arrive - 8 - Travel(s, me, sam.Pos, LiteArm.Cruise)), Route(s, me, sam.Pos)) ?? raid;
		// A feint: drones at the far end of the country, there before the wave.
		if (Adaptive)
		{
			var c = main[0].Pos;
			LiteRegion? far = null;
			foreach (var r in s.Map.Regions)
				if (r.Side != Side && !r.City && r.Spots.Count > 0 && r.Label.DistanceTo(c) > 250 && (far == null || _rng.NextDouble() < 0.3)) far = r;
			if (far != null) raid = s.Strike(Side, LiteArm.Drone, far.Label, 5 + _rng.Next(4), raid, 0, Route(s, me, far.Label)) ?? raid;
		}
		float share = (budget - Spend()) * 0.75f / main.Count;
		foreach (var t in main)
		{
			float cov = s.KnownCoverage(Side, t.Pos);
			float loss = Math.Clamp(0.15f + 0.14f * cov + 0.3f * me.LastRaidLoss, 0.15f, 0.85f);
			float hp = t.Kind == LiteKind.Capital ? Math.Min(t.Hp, 40) : t.Hp;
			int dr = Math.Min((int)Math.Ceiling(hp / (1 - loss) * 1.3f) + 2, (int)(share / LiteRules.Cost(LiteArm.Drone)));
			dr = Math.Min(dr, 40);
			var route = Route(s, me, t.Pos);
			if (dr > 0) raid = s.Strike(Side, LiteArm.Drone, t.Pos, dr, raid, Math.Max(0, arrive - Travel(s, me, t.Pos, LiteArm.Drone)), route) ?? raid;
			if (cov >= 2 || t.Kind == LiteKind.Capital)
			{
				int cru = Math.Min(6, (int)Math.Ceiling(hp * 0.5f / LiteRules.Damage(LiteArm.Cruise) / (1 - loss * 0.6f)));
				cru = Math.Min(cru, (int)((budget - Spend()) * 0.5f / LiteRules.Cost(LiteArm.Cruise)));
				if (cru > 0) raid = s.Strike(Side, LiteArm.Cruise, t.Pos, cru, raid, Math.Max(0, arrive + 10 - Travel(s, me, t.Pos, LiteArm.Cruise)), route) ?? raid;
			}
		}
		// What is left: ballistic missiles at the capital or the main target, last.
		float left = budget - Spend();
		var heavy = main.Find(t => t.Kind == LiteKind.Capital) ?? main[0];
		int bal = Math.Min(4, (int)(left * 0.8f / LiteRules.Cost(LiteArm.Ballistic)));
		if (bal > 0 && s.Time > 150) s.Strike(Side, LiteArm.Ballistic, heavy.Pos, bal, raid, Math.Max(0, arrive + 6 - Travel(s, me, heavy.Pos, LiteArm.Ballistic)));
		me.WarFund = Math.Max(0, me.WarFund - Spend());
	}

	/// A few drones, each to a region of the other side not yet flown over.
	private void Scout(LiteSim s, int n)
	{
		var regions = new List<LiteRegion>();
		foreach (var r in s.Map.Regions)
			if (r.Side != Side && !r.City && r.Spots.Count > 0 && !_scouted.Contains(r.Id)) regions.Add(r);
		if (regions.Count == 0) { _scouted.Clear(); return; }
		for (int i = 0; i < n && regions.Count > 0; i++)
		{
			var r = regions[_rng.Next(regions.Count)];
			regions.Remove(r);
			_scouted.Add(r.Id);
			s.Strike(Side, LiteArm.Drone, r.Label, 1, null, i * 0.8f, Route(s, s.Sides[Side], r.Label));
		}
	}

	/// The way in that passes least of the air defence this side knows of:
	/// straight, or bent through one point to either side. Sometimes the
	/// second best, so the way in is not always the same.
	private List<Vector2>? Route(LiteSim s, LiteSide me, Vector2 target)
	{
		var from = me.Capital.Pos;
		float bd = float.MaxValue;
		foreach (var r in s.Map.Regions)
			if (r.Side == Side && !r.City && r.Label.DistanceTo(target) < bd) { bd = r.Label.DistanceTo(target); from = r.Label; }
		var d = target - from;
		float len = d.Length();
		if (len < 1) return null;
		var n = new Vector2(-d.Y, d.X) / len;
		float best = float.MaxValue, second = float.MaxValue;
		List<Vector2>? bestRoute = null, secondRoute = null;
		foreach (float off in new[] { 0f, -90f, 90f, -170f, 170f, -250f, 250f })
		{
			var mid = from + d * 0.5f + n * off;
			if (off != 0 && s.Map.SideAt(mid) < 0) continue;
			float score = Exposure(s, from, mid) + Exposure(s, mid, target) + (from.DistanceTo(mid) + mid.DistanceTo(target)) * 0.004f;
			var route = off == 0 ? null : new List<Vector2> { mid };
			if (score < best) { second = best; secondRoute = bestRoute; best = score; bestRoute = route; }
			else if (score < second) { second = score; secondRoute = route; }
		}
		return second < best * 1.2f + 0.5f && _rng.NextDouble() < 0.3 ? secondRoute : bestRoute;
	}

	private float Exposure(LiteSim s, Vector2 a, Vector2 b)
	{
		float sum = 0, len = a.DistanceTo(b);
		for (float t = 0; t < len; t += 15) sum += s.KnownCoverage(Side, a.Lerp(b, t / len));
		return sum;
	}

	/// Factories first, since they repair the capital; air defence when the
	/// last raid was shot to pieces; the capital when no factory is known,
	/// and more and more as the war goes on.
	private LiteBuilding Pick(LiteSim s, LiteSide me)
	{
		float total = 0;
		bool factories = _targets.Exists(b => b.Kind == LiteKind.Factory);
		var weights = new float[_targets.Count];
		for (int i = 0; i < _targets.Count; i++)
		{
			var b = _targets[i];
			weights[i] = b.Kind switch
			{
				LiteKind.Factory => 3f,
				LiteKind.Sam => 2f + 3f * me.LastRaidLoss + (Adaptive ? 0.4f * b.Kills : 0),
				LiteKind.Gun => 1f + me.LastRaidLoss,
				_ => factories ? 0.5f + s.Time / 300f : 3f + s.Time / 200f,
			};
			total += weights[i];
		}
		float roll = R(0, total);
		for (int i = 0; i < _targets.Count; i++)
		{
			roll -= weights[i];
			if (roll <= 0) return _targets[i];
		}
		return _targets[^1];
	}
}
