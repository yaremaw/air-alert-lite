using System;
using System.Collections.Generic;
using Godot;

/// A side's commander, used for the enemy (and for our side in the test
/// and screenshot runs). It knows only what its side has seen.
///
/// Money goes on buildings and repairs: air defence first (round the
/// capital, then where weapons came down, then where systems were lost,
/// then by factories), factories with what is left. Production keeps the
/// stockpile near a mix set by what it knows of the other side: drones for
/// its factories and air defence, cruise missiles for defended sites,
/// ballistic missiles for the armored key targets. Its air defence turns
/// towards where the other side's weapons have been coming from.
///
/// A raid goes at up to four known sites. For each it picks the weapons that
/// do the most damage per production point after the losses the defence
/// there is likely to cause (armor makes drones useless against bunkers and
/// ballistic missiles wasteful against a factory), sends about as many as
/// its health needs, and flies round the air defence it knows of; a big
/// group of drones splits up and comes from two or three directions at once,
/// more than the defence's channels can track. Scouts go to regions not yet
/// flown over.
///
/// With waves on (Normal and Hard) it also weighs up a massive strike: what
/// the sites it knows of are worth against what it would take to overwhelm
/// the defence round them. When one is worth it and the stockpile can reach
/// it within a few minutes it starts massing (the other side's intelligence
/// notices), keeps its small raids small, and launches once the weapons are
/// there: drones from all sides arriving together to drain the air defence,
/// missiles behind them. Adaptive (Hard) also sends cruise missiles ahead of
/// the wave at the air defence that has shot down the most, and drones as a
/// feint at the other end of the country.
public sealed class LiteAi
{
	public readonly int Side;
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
	private readonly List<LiteBuilding> _targets = new();
	private readonly HashSet<int> _scouted = new();
	private readonly int[] _avail = new int[3];
	/// Per air defence system of ours: where threats have been coming from
	/// lately (a sum of directions that fades), and where it stood, to put
	/// it back if it is destroyed.
	private readonly Dictionary<LiteBuilding, Vector2> _threats = new();
	private readonly List<Vector2> _rebuild = new();

	public LiteAi(int side, int seed, float firstRaid)
	{
		Side = side;
		_rng = new Random(seed);
		_nextRaid = firstRaid;
	}

	private float R(float a, float b) => a + (float)_rng.NextDouble() * (b - a);

	public void Tick(LiteSim s, float dt)
	{
		_think -= dt;
		if (_think > 0) return;
		_think = R(0.7f, 1.3f);
		var me = s.Sides[Side];
		me.Repairing = true;
		Watch(s, me, 1f);
		Produce(s, me);
		Defend(s, me);
		Grow(s, me);
		Attack(s, me);
	}

	// ---------------------------------------------------------------- production

	/// The stockpile it wants, set by what it knows of the other side:
	/// drones for factories and air defence, cruise missiles where that
	/// defence stands, ballistic missiles for the key targets still standing.
	private float Want(LiteSim s, LiteArm a)
	{
		int light = 0, ad = 0, keys = 0;
		foreach (var b in s.Buildings)
		{
			if (!b.Alive || b.Side == Side || !b.Seen[Side]) continue;
			if (b.IsKey) keys++;
			else { light++; if (b.IsAd) ad++; }
		}
		if (!Smart) return a == LiteArm.Drone ? 30 : a == LiteArm.Cruise ? 4 : 0;
		return a switch
		{
			LiteArm.Drone => Math.Min(70, 12 + 5 * light),
			LiteArm.Cruise => s.Time < 40 ? 0 : Math.Min(16, 2 + 1.5f * ad + s.Time / 240f),
			_ => s.Time < 60 ? 0 : Math.Min(10, 1.5f * keys),
		};
	}

	/// The share of a kind of weapon expected to get through, when `loss` of
	/// the drones would be shot down: missiles are harder to stop.
	private static float Survive(LiteArm a, float loss) => a switch
	{
		LiteArm.Drone => 1 - loss,
		LiteArm.Cruise => 1 - loss * 0.7f,
		_ => 1 - loss * 0.3f,
	};

	/// The weapons to send at `t`, out of `avail`: the kind doing the most
	/// damage per production point there first, then the next, until its
	/// `hp` is covered. Kinds that would barely scratch it are left out.
	private int[] Mix(LiteBuilding t, float hp, float loss, int[] avail, int cap = 30)
	{
		var n = new int[3];
		var order = new List<LiteArm> { LiteArm.Drone, LiteArm.Cruise, LiteArm.Ballistic };
		float Value(LiteArm a) => LiteDamage.Useful(a, t.Kind, hp) * Survive(a, loss) / LiteRules.PP(a);
		order.Sort((a, b) => Value(b).CompareTo(Value(a)));
		float left = hp;
		foreach (var a in order)
		{
			float per = LiteDamage.Dealt(a, t.Kind) * Survive(a, loss);
			if (LiteDamage.Dealt(a, t.Kind) < t.Armor * 0.5f || per <= 0) continue;
			int need = (int)Math.Ceiling(left / per) + (a == LiteArm.Drone ? 1 : 0);
			int take = Math.Min(Math.Min(need, avail[(int)a]), cap);
			n[(int)a] = take;
			left -= take * per;
			if (left <= 0) break;
		}
		return n;
	}

	/// What a site's destruction needs in production points.
	private float CostFor(LiteBuilding t, float loss)
	{
		var n = Mix(t, t.Hp, loss, new[] { 999, 999, 999 }, 999);
		float pp = 0;
		for (int i = 0; i < 3; i++) pp += n[i] * LiteRules.PP((LiteArm)i);
		return pp;
	}

	private float Loss(LiteSide me, float cov) =>
		Smart ? Math.Clamp(0.1f + 0.14f * cov + 0.4f * me.LastRaidLoss, 0.1f, 0.85f) : 0.5f;

	/// Keeps a short queue, always topped up with what the stock lacks most.
	private void Produce(LiteSim s, LiteSide me)
	{
		var prod = me.Production;
		while (prod.Queue.Count < 3)
		{
			var pick = LiteArm.Drone;
			float worst = float.MaxValue;
			for (int i = 0; i < 3; i++)
			{
				var a = (LiteArm)i;
				float want = Want(s, a);
				if (want <= 0) continue;
				float have = (prod.Stock[i] + prod.Count(a)) / want;
				if (have < worst) { worst = have; pick = a; }
			}
			prod.Add(pick);
		}
	}

	// ---------------------------------------------------------------- watching the sky

	/// Turns each air defence system towards where the other side's weapons
	/// have been coming from, and notes systems lost so they can be put back.
	private void Watch(LiteSim s, LiteSide me, float dt)
	{
		foreach (var b in new List<LiteBuilding>(_threats.Keys))
			if (!b.Alive)
			{
				_threats.Remove(b);
				_rebuild.Add(b.Pos);
			}
		float reach = LiteRules.AdRange * LiteRules.RadarReach;
		foreach (var b in s.Buildings)
		{
			if (!b.Alive || b.Side != Side || !b.IsAd || !b.Ready) continue;
			_threats.TryGetValue(b, out var heat);
			heat *= MathF.Pow(0.5f, dt / 40f);
			foreach (var w in s.Weapons)
				if (w.Alive && w.Side != Side && w.Seen[Side] && w.Pos.DistanceTo(b.Pos) < reach)
					heat += (w.Pos - b.Pos).Normalized() * (w.Arm == LiteArm.Drone ? 1f : 2f);
			foreach (var h in me.HitLog)
				if (h.P.DistanceTo(b.Pos) < reach) heat += (h.P - b.Pos).Normalized() * 0.5f;
			_threats[b] = heat;
			// Turn only when the threats clearly come from somewhere else.
			if (Smart && heat.Length() > 3 && MathF.Abs(Mathf.AngleDifference(b.TargetFacing, heat.Angle())) > 0.35f)
				b.TargetFacing = heat.Angle();
		}
	}

	// ---------------------------------------------------------------- building

	/// Money kept back for repairs.
	private const float Reserve = 40f;

	private bool Afford(LiteSim s, LiteSide me, LiteKind kind) => me.Money - Reserve >= s.Cost(Side, kind);

	/// Air defence near a point, in a region with room for it: 1 built,
	/// 0 a place is free but the money is not there yet, -1 no place.
	private int Put(LiteSim s, LiteSide me, Vector2 near, float rMin, float rMax)
	{
		var p = s.FindSpot(Side, near, rMin, rMax, true);
		if (p == null) return -1;
		if (!Afford(s, me, LiteKind.Ad)) return 0;
		return s.Build(Side, LiteKind.Ad, p.Value) != null ? 1 : 0;
	}

	private void Defend(LiteSim s, LiteSide me)
	{
		me.HitLog.RemoveAll(h => s.Time - h.T > 25);
		// 1. The capital: more air defence as the war goes on, as far as the
		// regions round it have room.
		int capAd = 0;
		foreach (var b in s.Buildings)
			if (b.Alive && b.Side == Side && b.IsAd && b.Pos.DistanceTo(me.Center) < 70) capAd++;
		if (capAd < Math.Min(4, 1 + (int)(s.Time / 200)) && Put(s, me, me.Center, 16, 60) >= 0) return;
		// 2. Where the other side's weapons came down near something of ours.
		for (int i = 0; i < me.HitLog.Count; i++)
		{
			var h = me.HitLog[i];
			bool valuable = false;
			foreach (var b in s.Buildings)
				if (b.Alive && b.Side == Side && b.Pos.DistanceTo(h.P) < 35) { valuable = true; break; }
			if (!valuable || s.Coverage(Side, h.P) >= 4) { me.HitLog.RemoveAt(i--); continue; }
			int r = Put(s, me, h.P, 8, 40);
			if (r != 0) me.HitLog.RemoveAt(i);
			if (r >= 0) return;
			i--;
		}
		// 3. Air defence lost: put it back where it stood.
		for (int i = 0; i < _rebuild.Count; i++)
		{
			int r = Put(s, me, _rebuild[i], 4, 40);
			if (r != 0) _rebuild.RemoveAt(i);
			if (r >= 0) return;
			i--;
		}
		// 4. Spare money: the least covered factory, then the key targets.
		if (s.Time < 50 || me.Money < 450) return;
		LiteBuilding? weak = null;
		float low = 2;
		foreach (var b in s.Buildings)
		{
			if (!b.Alive || b.Side != Side || b.Kind != LiteKind.Factory) continue;
			float c = s.Coverage(Side, b.Pos);
			if (c < low) { low = c; weak = b; }
		}
		if (weak != null && Put(s, me, weak.Pos, 12, 40) >= 0) return;
		if (me.Money > 900)
			foreach (var k in me.Keys)
				if (k.Alive && s.Coverage(Side, k.Pos) < 6 && Put(s, me, k.Pos, 16, 50) >= 0) return;
	}

	private void Grow(LiteSim s, LiteSide me)
	{
		if (!Afford(s, me, LiteKind.Factory) || s.Time - _lastFactory < (me.Money > 800 ? 3 : 9)) return;
		// A region with room: the further from the other side's capital the
		// safer, but a region with more room counts for something too.
		var enemyCap = s.Sides[1 - Side].Center;
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

	// ---------------------------------------------------------------- raids

	private void Attack(LiteSim s, LiteSide me)
	{
		var prod = me.Production;
		if (Waves)
		{
			if (!Massing && s.Time >= _planAt) PlanWave(s, me);
			else if (Massing && (prod.StockValue >= _waveCost || s.Time - _massSince > 240))
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
		float use = Massing ? 0.25f : Waves ? 0.6f : 1f;
		for (int i = 0; i < 3; i++) _avail[i] = (int)(prod.Stock[i] * use);
		if (_avail[0] + _avail[1] + _avail[2] == 0) { _nextRaid = s.Time + 4; return; }
		_targets.Clear();
		int known = 0;
		foreach (var b in s.Buildings)
			if (b.Alive && b.Side != Side && b.Seen[Side]) { _targets.Add(b); if (!b.IsKey) known++; }

		if (known == 0 || _rng.NextDouble() < 0.1) Scout(s, Math.Min(4, _avail[0]));
		else
		{
			LiteRaid? raid = null;
			float delay = 0;
			for (int k = 0; k < 4 && _targets.Count > 0 && _avail[0] + _avail[1] + _avail[2] > 0; k++)
			{
				var t = Pick(s, me);
				_targets.Remove(t);
				// The share likely to be shot down: what the defence there looks
				// like, and how the last raid fared.
				float loss = Loss(me, s.KnownCoverage(Side, t.Pos));
				var route = Smart ? Route(s, me, t.Pos) : null;
				// A small raid takes a bite of a key target, not all of it.
				var mix = Mix(t, t.IsKey ? Math.Min(t.Hp, 200) : t.Hp, loss, _avail);
				int dr = mix[0], cru = mix[1], bal = mix[2];
				if (dr + cru + bal == 0) continue;
				_avail[0] -= dr; _avail[1] -= cru; _avail[2] -= bal;
				// Drones go first; the missiles are timed to arrive with them.
				float tDrone = Travel(s, me, t.Pos, LiteArm.Drone);
				if (dr > 0) raid = Converge(s, me, t.Pos, dr, raid, delay, tDrone) ?? raid;
				if (cru > 0) raid = s.Strike(Side, LiteArm.Cruise, t.Pos, cru, raid, delay + Math.Max(0, tDrone - Travel(s, me, t.Pos, LiteArm.Cruise)), route) ?? raid;
				if (bal > 0) raid = s.Strike(Side, LiteArm.Ballistic, t.Pos, bal, raid, delay + Math.Max(0, tDrone - 2f)) ?? raid;
				delay += 1.5f;
			}
		}
		_nextRaid = s.Time + R(20, 36) * Tempo;
	}

	/// Seconds from launch to the target, roughly: drones and ballistic
	/// missiles go up near the front, cruise missiles from deep inside.
	private float Travel(LiteSim s, LiteSide me, Vector2 target, LiteArm arm)
	{
		var from = me.Center;
		if (arm != LiteArm.Cruise)
		{
			float bd = float.MaxValue;
			foreach (var r in s.Map.Regions)
				if (r.Side == Side && !r.City && r.Label.DistanceTo(target) < bd) { bd = r.Label.DistanceTo(target); from = r.Label; }
		}
		return from.DistanceTo(target) / LiteRules.Speed(arm) * (arm == LiteArm.Drone ? 1.2f : 1.1f);
	}

	/// What a site is worth to a massive strike: key targets most, the more
	/// so the more damaged they are and the closer the war is to won.
	private float Worth(LiteSim s, LiteBuilding b, float cov) => b.Kind switch
	{
		LiteKind.Factory => 3f,
		LiteKind.Ad => 2.5f + (Adaptive ? 0.3f * b.Kills : 0),
		_ => 3f + 4f * (1 - b.Hp / b.MaxHp) + 2f * s.Sides[b.Side].KeysLost,
	} / (1 + 0.3f * cov);

	/// Is a massive strike worth it, and can the stockpile reach it within
	/// about four minutes? Then start massing for it on the best few targets.
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
		var prod = me.Production;
		float reach = prod.StockValue + prod.Rate * 240;
		while (known.Count > 0)
		{
			float worth = 0, cost = 0;
			var ads = new HashSet<LiteBuilding>();
			foreach (var (b, score, cov) in known)
			{
				worth += score;
				cost += CostFor(b, Loss(me, cov));
				foreach (var o in s.Buildings)
					if (o.Alive && o.Side != Side && o.Seen[Side] && o.IsAd && o.Pos.DistanceTo(b.Pos) <= LiteRules.Range(LiteKind.Ad)) ads.Add(o);
			}
			// Enough extra drones to keep every channel of the air defence on the way busy.
			cost += ads.Count * LiteRules.AdChannels * 3 * LiteRules.PP(LiteArm.Drone);
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

	/// The massive wave: the planned targets, the drones timed to arrive
	/// together, the missiles ten seconds behind them; most of the stockpile.
	private void Wave(LiteSim s, LiteSide me)
	{
		var stock = me.Production.Stock;
		for (int i = 0; i < 3; i++) _avail[i] = stock[i];
		if (_avail[0] + _avail[1] + _avail[2] == 0) return;
		_targets.Clear();
		foreach (var b in s.Buildings) if (b.Alive && b.Side != Side && b.Seen[Side]) _targets.Add(b);
		var busiest = new List<LiteBuilding>();
		if (Adaptive)
		{
			foreach (var b in _targets) if (b.IsAd && b.Kills >= 2) busiest.Add(b);
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
		// Ahead of the wave, cruise missiles at the air defence that shot down most.
		foreach (var ad in busiest)
		{
			int n = Math.Min(3, _avail[1]);
			_avail[1] -= n;
			raid = s.Strike(Side, LiteArm.Cruise, ad.Pos, n, raid, Math.Max(0, arrive - 8 - Travel(s, me, ad.Pos, LiteArm.Cruise)), Route(s, me, ad.Pos)) ?? raid;
		}
		// A feint: drones at the far end of the country, there before the wave.
		if (Adaptive)
		{
			var c = main[0].Pos;
			LiteRegion? far = null;
			foreach (var r in s.Map.Regions)
				if (r.Side != Side && !r.City && r.Spots.Count > 0 && r.Label.DistanceTo(c) > 250 && (far == null || _rng.NextDouble() < 0.3)) far = r;
			int n = Math.Min(5 + _rng.Next(4), _avail[0] / 5);
			_avail[0] -= n;
			if (far != null && n > 0) raid = s.Strike(Side, LiteArm.Drone, far.Label, n, raid, 0, Route(s, me, far.Label)) ?? raid;
		}
		// Each target its fair share of what is left, mixed for its armor:
		// drones arrive together, cruise missiles ten seconds behind, ballistic last.
		for (int k = 0; k < main.Count; k++)
		{
			var t = main[k];
			int ways = main.Count - k;
			var share = new int[3];
			for (int i = 0; i < 3; i++) share[i] = (_avail[i] + ways - 1) / ways;
			var mix = Mix(t, t.Hp * 1.2f, Loss(me, s.KnownCoverage(Side, t.Pos)), share, 40);
			for (int i = 0; i < 3; i++) _avail[i] -= mix[i];
			var route = Route(s, me, t.Pos);
			if (mix[0] > 0) raid = Converge(s, me, t.Pos, mix[0], raid, 0, arrive) ?? raid;
			if (mix[1] > 0) raid = s.Strike(Side, LiteArm.Cruise, t.Pos, mix[1], raid, Math.Max(0, arrive + 10 - Travel(s, me, t.Pos, LiteArm.Cruise)), route) ?? raid;
			if (mix[2] > 0) raid = s.Strike(Side, LiteArm.Ballistic, t.Pos, mix[2], raid, Math.Max(0, arrive + 6 - Travel(s, me, t.Pos, LiteArm.Ballistic))) ?? raid;
		}
	}

	/// Sends `n` drones at a target so they all arrive about `arrive` seconds
	/// from now: a big group splits into two or three, each along its own way
	/// in, so the air defence there sees them from several sides at once.
	private LiteRaid? Converge(LiteSim s, LiteSide me, Vector2 target, int n, LiteRaid? raid, float delay, float arrive)
	{
		int groups = !Smart || n < 6 ? 1 : n < 14 ? 2 : 3;
		var ways = Routes(s, me, target, groups);
		for (int g = 0; g < ways.Count; g++)
		{
			int k = n / ways.Count + (g < n % ways.Count ? 1 : 0);
			if (k <= 0) continue;
			var route = ways[g];
			float travel = PathLength(s, me, target, route) / LiteRules.Speed(LiteArm.Drone) * 1.05f;
			raid = s.Strike(Side, LiteArm.Drone, target, k, raid, delay + Math.Max(0, arrive - travel), route) ?? raid;
		}
		return raid;
	}

	/// Launch point to target along a route (or straight), in map units.
	private float PathLength(LiteSim s, LiteSide me, Vector2 target, List<Vector2>? route)
	{
		var from = Front(s, target);
		if (route == null || route.Count == 0) return from.DistanceTo(target);
		return from.DistanceTo(route[0]) + route[0].DistanceTo(target);
	}

	/// Our region nearest the target, where drones go up.
	private Vector2 Front(LiteSim s, Vector2 target)
	{
		var from = s.Sides[Side].Center;
		float bd = float.MaxValue;
		foreach (var r in s.Map.Regions)
			if (r.Side == Side && !r.City && r.Label.DistanceTo(target) < bd) { bd = r.Label.DistanceTo(target); from = r.Label; }
		return from;
	}

	/// Up to `k` ways in from different directions, each the least exposed
	/// of its side: straight, from the left, from the right.
	private List<List<Vector2>?> Routes(LiteSim s, LiteSide me, Vector2 target, int k)
	{
		var ways = new List<List<Vector2>?>();
		if (k <= 1) { ways.Add(Smart ? Route(s, me, target) : null); return ways; }
		var from = Front(s, target);
		var d = target - from;
		float len = d.Length();
		var n = new Vector2(-d.Y, d.X) / Math.Max(1, len);
		List<Vector2>? Best(float[] offs)
		{
			float best = float.MaxValue;
			List<Vector2>? pick = null;
			foreach (float off in offs)
			{
				// The turn comes late, so the group closes in from that side.
				var mid = from + d * 0.65f + n * off;
				if (s.Map.SideAt(mid) < 0) continue;
				float score = Exposure(s, from, mid) + Exposure(s, mid, target) + R(0, 1.5f);
				if (score < best) { best = score; pick = new List<Vector2> { mid }; }
			}
			return pick;
		}
		ways.Add(Best(new[] { -90f, -140f, -190f }));
		ways.Add(Best(new[] { 90f, 140f, 190f }));
		if (k >= 3) ways.Add(null);
		// Sides with no way in over land fall back to the straight one.
		if (k < 3) ways.RemoveAll(w => w == null);
		if (ways.Count == 0) ways.Add(null);
		return ways;
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
		var from = me.Center;
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

	/// Factories first; air defence when the last raid was shot to pieces;
	/// key targets when no factory is known, and more as the war goes on.
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
				LiteKind.Ad => 2f + 3f * me.LastRaidLoss + (Adaptive ? 0.4f * b.Kills : 0),
				_ => (factories ? 0.6f + s.Time / 300f : 3f + s.Time / 200f) * (2 - b.Hp / b.MaxHp),
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
