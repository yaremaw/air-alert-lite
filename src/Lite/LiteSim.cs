using System;
using System.Collections.Generic;
using Godot;

public enum LiteKind { Factory, Ad, Hq, Bunker, Energy, Gov }
public enum LiteArm { Drone, Cruise, Ballistic }
public enum LiteEv { RaidAlert, AllClear, Launch, Detected, ShotDown, Hit, KeyHit, Destroyed, Built, Spotted, RaidOver, GameOver, Industry, Warning }
public enum LiteFxKind { Blast, Scorch, Pop, Puff, Tracer, Launch }

public sealed class LiteBuilding
{
	public int Id, Side, Region;
	public LiteKind Kind;
	public Vector2 Pos;
	public float Hp, MaxHp, Build, BuildTotal, DeadAt, Flash, FireFlash;
	/// Air defence: where its radar sector faces now and where it is turning
	/// to (radians), what each channel is tracking, and its time to the next shot.
	public float Facing, TargetFacing;
	public readonly LiteWeapon?[] Tracks = new LiteWeapon?[LiteRules.AdChannels];
	public readonly float[] ChannelCool = new float[LiteRules.AdChannels];
	/// Weapons it has shot down; a sharp enemy goes for the busiest air defence.
	public int Kills;
	public bool Alive = true;
	public readonly bool[] Seen = new bool[2];
	public bool Ready => Build <= 0f;
	public bool IsAd => Kind == LiteKind.Ad;
	/// One of the four key targets round a capital.
	public bool IsKey => Kind >= LiteKind.Hq;
	public float Armor => LiteRules.Armor(Kind);
}

public sealed class LiteWeapon
{
	public int Id, Side, Leg;
	public LiteArm Arm;
	public LiteRaid Raid = null!;
	public Vector2 Pos, Start, Target, Dir;
	public float Speed, Length, Flown, TrailAcc;
	public bool Alive = true;
	/// The site it was sent at, if any: when that is gone, a drone or cruise
	/// missile turns to another known site close by.
	public LiteBuilding? Aim;
	/// Which side knows it is in the air. The other side sees it only over
	/// its own land or near its air defence radars; ballistic launches at once.
	public readonly bool[] Seen = new bool[2];
	public readonly List<Vector2> Path = new();
	public readonly List<Vector2> Trail = new();
	public float Progress => Length > 0 ? Flown / Length : 1f;
}

public sealed class LiteInterceptor
{
	public int Side;
	public LiteWeapon Target = null!;
	public LiteBuilding? From;
	public Vector2 Pos, Goal;
	public float Age;
	public bool Alive = true;
	public readonly List<Vector2> Trail = new();
}

public sealed class LiteFx
{
	public LiteFxKind Kind;
	public Vector2 A, B;
	public float Age, Life, Size;
	public int Side;
}

/// One salvo or raid: what was sent, what was shot down, what got through.
public sealed class LiteRaid
{
	public int Id, Side, Total, Launched, Done, Down, Hits;
	/// The other side has been told about it.
	public bool Reported;
	public Vector2 Target;
	public readonly int[] ByArm = new int[3];
	public readonly List<string> Destroyed = new();
}

public struct LiteEvent
{
	public LiteEv Type;
	public int Side, Region;
	public Vector2 Pos;
	public LiteArm Arm;
	public LiteKind Kind;
	public float Value;
	public LiteRaid? Raid;
}

public sealed class LiteSide
{
	public readonly int Index;
	public float Money = LiteRules.StartMoney, Income, LastRaidLoss;
	/// Weapons are built here, from production points; strikes take from its stock.
	public readonly LiteProduction Production = new();
	/// Damaged buildings are repaired for money while this is on; `RepairSpend` is $ a second.
	public bool Repairing = true;
	public float RepairSpend;
	/// The capital's middle, and the four key targets round it.
	public Vector2 Center;
	public readonly List<LiteBuilding> Keys = new();
	public int KeysLost;
	public int Launched, Hits, Downed, Lost, Destroyed;
	/// Where the other side's weapons came down on our land lately (the AI defends there).
	public readonly List<(Vector2 P, float T)> HitLog = new();
	public LiteSide(int index) { Index = index; }
}

/// The whole lite game: two sides with the same rules. Factories earn money
/// and production points; the points build weapons into a stockpile, the
/// money pays for factories, air defence and repairs. Air defence shoots down
/// what flies into range; drones and missiles fly to where they were sent and
/// damage what is there. Regions go under air alert where a weapon is and
/// where it is heading, and factories under alert work at half their pace.
/// Each capital has four armored key targets; destroying KeysToWin of the
/// other side's wins the war.
public sealed class LiteSim
{
	public readonly LiteMap Map;
	public readonly LiteSide[] Sides = { new(0), new(1) };
	public readonly List<LiteBuilding> Buildings = new();
	public readonly List<LiteWeapon> Weapons = new();
	public readonly List<LiteInterceptor> Interceptors = new();
	public readonly List<LiteFx> Fx = new();
	public readonly List<LiteEvent> Events = new();
	public readonly LiteAi?[] Ai = new LiteAi?[2];
	/// Difficulty: scales a side's money and production.
	public readonly float[] IncomeScale = { 1f, 1f };
	public float Time;
	public int Winner = -1;

	public readonly bool[] Alert, Ballistic;
	public readonly float[] AlertSince, RegionFlash;
	public readonly int[] Alerted = new int[2];
	public readonly float[] SideAlertSince = new float[2], SideQuietSince = new float[2];
	private readonly float[] _quiet, _balQuiet;
	private readonly bool[] _threat, _bal;

	private readonly Random _rng;
	private readonly LiteAirDefence _ad;
	private readonly List<Pending> _queue = new();
	private readonly List<LiteRegion> _tmp = new();
	private readonly List<LiteArm> _done = new();
	private int _ids, _raids;
	private float _alertTick;

	/// Room for factories in each region; ruins of destroyed ones take room
	/// until they are cleared. Regions near the front have more room than the
	/// deep rear, and the room moves about during the war.
	public readonly int[] Slots;
	private readonly List<(int Region, float Until)> _ruins = new();
	private float _shift = LiteRules.IndustryShift, _intel = LiteRules.IntelEvery;

	private readonly record struct Pending(float At, int Side, LiteArm Arm, Vector2 Target, LiteRaid Raid, List<Vector2>? Route);

	public LiteSim(LiteMap map, int seed)
	{
		Map = map;
		_rng = new Random(seed * 7919 + 13);
		int n = map.Regions.Count;
		Alert = new bool[n]; Ballistic = new bool[n]; AlertSince = new float[n]; RegionFlash = new float[n];
		_quiet = new float[n]; _balQuiet = new float[n]; _threat = new bool[n]; _bal = new bool[n];
		Slots = new int[n];
		_ad = new LiteAirDefence(this, _rng);
		for (int s = 0; s < 2; s++) Sides[s].Center = Map.Capital[s];
		for (int s = 0; s < 2; s++) InitSlots(s);
		EvenSlots();
		for (int s = 0; s < 2; s++) Setup(s);
		foreach (var b in Buildings)
			if (b.Kind == LiteKind.Factory) Slots[b.Region] = Math.Max(Slots[b.Region], FactoriesIn(b.Region));
	}

	private void Setup(int side)
	{
		var me = Sides[side];
		// The key targets on a ring round the capital, the other side knows where.
		var kinds = new[] { LiteKind.Hq, LiteKind.Bunker, LiteKind.Energy, LiteKind.Gov };
		float turn = (float)_rng.NextDouble() * MathF.Tau;
		for (int i = 0; i < 4; i++)
		{
			var want = me.Center + new Vector2(LiteRules.KeyRing, 0).Rotated(turn + i * MathF.Tau / 4);
			var p = CanPlace(side, want) ? want : FindSpot(side, want, 2, 16) ?? FindSpot(side, me.Center, 14, 40);
			if (p == null) continue;
			var key = Add(side, kinds[i], p.Value, true);
			key.Seen[1 - side] = true;
			me.Keys.Add(key);
		}
		for (int i = 0; i < 2; i++)
		{
			var ad = FindSpot(side, me.Center, 30, 55, true);
			if (ad != null) Add(side, LiteKind.Ad, ad.Value, true);
		}
		// Two factories to start with.
		for (int i = 0; i < 2; i++)
		{
			var factory = FindSpot(side, Map.Capital[side], 55 + 40 * i, 110 + 50 * i);
			if (factory != null) Add(side, LiteKind.Factory, factory.Value, true);
		}
	}

	// ---------------------------------------------------------------- orders

	public bool CanPlace(int side, Vector2 p)
	{
		if (Map.SideAt(p) != side) return false;
		for (int a = 0; a < 4; a++)
			if (Map.SideAt(p + new Vector2(5, 0).Rotated(a * MathF.PI / 2)) != side) return false;
		foreach (var b in Buildings) if (b.Alive && b.Pos.DistanceTo(p) < 13) return false;
		return true;
	}

	/// The price of a building for a side: every factory costs FactoryGrowth
	/// times the one before, every air defence system AdStep more.
	public int Cost(int side, LiteKind kind)
	{
		int n = 0;
		foreach (var b in Buildings)
			if (b.Alive && b.Side == side && b.Kind == kind) n++;
		return kind switch
		{
			LiteKind.Factory => (int)(LiteRules.FactoryCost * MathF.Pow(LiteRules.FactoryGrowth, n)),
			LiteKind.Ad => LiteRules.AdCost + LiteRules.AdStep * n,
			_ => 0,
		};
	}

	/// Air defence sites standing (or being built) in a region.
	public int AdIn(int region)
	{
		int n = 0;
		foreach (var b in Buildings) if (b.Alive && b.IsAd && b.Region == region) n++;
		return n;
	}

	/// Room for one more air defence site at `p`.
	public bool AdRoom(Vector2 p)
	{
		byte r = Map.RegionAt(p);
		return r != LiteMap.None && AdIn(r) < LiteRules.AdPerRegion;
	}

	/// Front regions get 2 or 3 places for factories, the middle 1 or 2, the
	/// deep rear 0 or 1; the capital's region one more. Depth is how far the
	/// region's middle lies from the nearest region of the other side.
	private void InitSlots(int side)
	{
		var depth = new Dictionary<int, float>();
		foreach (var r in Map.Regions)
		{
			if (r.Side != side || r.City) continue;
			float d = float.MaxValue;
			foreach (var o in Map.Regions) if (o.Side != side && !o.City) d = Math.Min(d, r.Label.DistanceTo(o.Label));
			depth[r.Id] = d;
		}
		float lo = float.MaxValue, hi = 0;
		foreach (var d in depth.Values) { lo = Math.Min(lo, d); hi = Math.Max(hi, d); }
		foreach (var (id, d) in depth)
		{
			float t = (d - lo) / Math.Max(1, hi - lo);
			Slots[id] = t < 0.33f ? 2 + _rng.Next(2) : t < 0.66f ? 1 + _rng.Next(2) : _rng.Next(2);
			if (Map.Regions[id].Neighbors.Contains(Map.RegionAt(Map.Capital[side]))) Slots[id] = Math.Max(Slots[id], 1);
		}
		int capRegion = Map.Regions[Map.RegionAt(Map.Capital[side])].Parent;
		if (capRegion >= 0) Slots[capRegion]++;
	}

	/// The bigger country has more regions; both get the same room in all,
	/// taken off random regions of the one with more.
	private void EvenSlots()
	{
		var total = new int[2];
		foreach (var r in Map.Regions) total[r.Side] += Slots[r.Id];
		int more = total[0] > total[1] ? 0 : 1;
		var list = new List<int>();
		while (total[more] > total[1 - more])
		{
			list.Clear();
			foreach (var r in Map.Regions) if (r.Side == more && Slots[r.Id] > 0) list.Add(r.Id);
			Slots[list[_rng.Next(list.Count)]]--;
			total[more]--;
		}
	}

	public int FactoriesIn(int region)
	{
		int n = 0;
		foreach (var b in Buildings) if (b.Alive && b.Kind == LiteKind.Factory && b.Region == region) n++;
		return n;
	}

	public int RuinsIn(int region)
	{
		int n = 0;
		foreach (var r in _ruins) if (r.Region == region) n++;
		return n;
	}

	public int FreeSlots(int region) => Slots[region] - FactoriesIn(region) - RuinsIn(region);

	/// A factory goes into a region, at a free spot of its choosing.
	public LiteBuilding? BuildFactory(int side, int region)
	{
		if (region < 0 || region >= Map.Regions.Count || Map.Regions[region].Side != side || FreeSlots(region) <= 0) return null;
		int cost = Cost(side, LiteKind.Factory);
		if (Sides[side].Money < cost) return null;
		var spots = Map.Regions[region].Spots;
		for (int k = 0; k < 40 && spots.Count > 0; k++)
		{
			var p = spots[_rng.Next(spots.Count)];
			if (!CanPlace(side, p)) continue;
			Sides[side].Money -= cost;
			return Add(side, LiteKind.Factory, p, false);
		}
		return null;
	}

	/// Agents and satellites: each side learns where one hidden factory of the
	/// other's is, or a hidden air defence site if no factory is hidden.
	private void Intel()
	{
		var hidden = new List<LiteBuilding>();
		for (int viewer = 0; viewer < 2; viewer++)
		{
			foreach (var kind in new[] { LiteKind.Factory, LiteKind.Ad })
			{
				hidden.Clear();
				foreach (var b in Buildings)
					if (b.Alive && b.Side != viewer && b.Kind == kind && !b.Seen[viewer]) hidden.Add(b);
				if (hidden.Count == 0) continue;
				Spot(hidden[_rng.Next(hidden.Count)], viewer);
				break;
			}
		}
	}

	/// Every few minutes on each side one region gains room for a factory
	/// and, half the time, another with room to spare loses one.
	private void ShiftIndustry()
	{
		for (int side = 0; side < 2; side++)
		{
			var grow = new List<int>();
			var shrink = new List<int>();
			foreach (var r in Map.Regions)
			{
				if (r.Side != side || r.City) continue;
				if (Slots[r.Id] < 4) grow.Add(r.Id);
				if (FreeSlots(r.Id) > 0) shrink.Add(r.Id);
			}
			if (grow.Count > 0)
			{
				int g = grow[_rng.Next(grow.Count)];
				Slots[g]++;
				shrink.Remove(g);
				Events.Add(new LiteEvent { Type = LiteEv.Industry, Side = side, Region = g, Value = 1 });
			}
			if (shrink.Count > 0 && _rng.NextDouble() < 0.5)
			{
				int k = shrink[_rng.Next(shrink.Count)];
				Slots[k]--;
				Events.Add(new LiteEvent { Type = LiteEv.Industry, Side = side, Region = k, Value = -1 });
			}
		}
	}

	public LiteBuilding? Build(int side, LiteKind kind, Vector2 p)
	{
		if (kind == LiteKind.Factory) return BuildFactory(side, Map.RegionAt(p));
		if (!AdRoom(p)) return null;
		int cost = Cost(side, kind);
		if (Sides[side].Money < cost || !CanPlace(side, p)) return null;
		Sides[side].Money -= cost;
		return Add(side, kind, p, false);
	}

	private LiteBuilding Add(int side, LiteKind kind, Vector2 p, bool instant)
	{
		var b = new LiteBuilding
		{
			Id = ++_ids, Side = side, Kind = kind, Pos = p, Region = Map.RegionAt(p),
			MaxHp = LiteRules.MaxHp(kind), BuildTotal = LiteRules.BuildTime(kind),
		};
		// Air defence first faces the other side's capital.
		if (kind == LiteKind.Ad) b.Facing = b.TargetFacing = (Sides[1 - side].Center - p).Angle();
		b.Hp = b.MaxHp;
		b.Build = instant ? 0 : b.BuildTotal;
		b.Seen[side] = true;
		Buildings.Add(b);
		return b;
	}

	/// Sends `count` weapons of one kind from the stockpile at `target`,
	/// launched a moment apart, along `route` if given (drones and cruise
	/// missiles; ballistic ones fly straight).
	public LiteRaid? Strike(int side, LiteArm arm, Vector2 target, int count, LiteRaid? raid = null, float delay = 0f, List<Vector2>? route = null)
	{
		if (!Sides[side].Production.Take(arm, count)) return null;
		raid ??= new LiteRaid { Id = ++_raids, Side = side, Target = target };
		raid.Total += count;
		raid.ByArm[(int)arm] += count;
		float gap = arm == LiteArm.Drone ? 0.55f : 0.35f;
		for (int i = 0; i < count; i++)
			_queue.Add(new Pending(Time + delay + i * gap * (0.7f + 0.6f * (float)_rng.NextDouble()), side, arm, target, raid, route));
		return raid;
	}

	/// A free place near `near`; for air defence (`ad`), in a region with room for it.
	public Vector2? FindSpot(int side, Vector2 near, float rMin, float rMax, bool ad = false)
	{
		for (int i = 0; i < 80; i++)
		{
			float a = (float)_rng.NextDouble() * MathF.Tau, r = rMin + (float)_rng.NextDouble() * (rMax - rMin);
			var p = near + new Vector2(r, 0).Rotated(a);
			if (CanPlace(side, p) && (!ad || AdRoom(p))) return p;
		}
		return null;
	}

	public Vector2 RandomSpot(int side, Random rng)
	{
		_tmp.Clear();
		foreach (var r in Map.Regions) if (r.Side == side && !r.City && r.Spots.Count > 0) _tmp.Add(r);
		var pick = _tmp[rng.Next(_tmp.Count)];
		return pick.Spots[rng.Next(pick.Spots.Count)];
	}

	/// Air defence of the other side that `viewer` knows about whose sector
	/// covers a point (2 for each system).
	public float KnownCoverage(int viewer, Vector2 p)
	{
		float c = 0;
		foreach (var b in Buildings)
			if (b.Alive && b.Side != viewer && b.IsAd && b.Seen[viewer] && LiteAirDefence.InSector(b, p)) c += 2;
		return c;
	}

	/// How well a point is covered by the sectors of one side's own air
	/// defence (2 for each system).
	public float Coverage(int side, Vector2 p)
	{
		float c = 0;
		foreach (var b in Buildings)
			if (b.Alive && b.Side == side && b.IsAd && LiteAirDefence.InSector(b, p)) c += 2;
		return c;
	}

	// ---------------------------------------------------------------- step

	public void Step(float dt)
	{
		if (Winner >= 0) { StepFx(dt); return; }
		Time += dt;
		Economy(dt);
		for (int i = _queue.Count - 1; i >= 0; i--)
			if (_queue[i].At <= Time) { var p = _queue[i]; _queue.RemoveAt(i); Launch(p); }
		MoveWeapons(dt);
		Detect();
		_ad.Step(dt);
		Reveal();
		_alertTick -= dt;
		if (_alertTick <= 0) { _alertTick += 0.25f; Alerts(0.25f); }
		_ruins.RemoveAll(r => r.Until <= Time);
		if ((_shift -= dt) <= 0) { _shift = LiteRules.IndustryShift; ShiftIndustry(); }
		if ((_intel -= dt) <= 0) { _intel = LiteRules.IntelEvery; Intel(); }
		Ai[0]?.Tick(this, dt);
		Ai[1]?.Tick(this, dt);
		StepFx(dt);
		Buildings.RemoveAll(b => !b.Alive && Time - b.DeadAt > 30);
		Weapons.RemoveAll(w => !w.Alive);
		Interceptors.RemoveAll(i => !i.Alive);
	}

	public void StepFx(float dt)
	{
		foreach (var f in Fx) f.Age += dt;
		Fx.RemoveAll(f => f.Age >= f.Life);
		for (int i = 0; i < RegionFlash.Length; i++) RegionFlash[i] = Math.Max(0, RegionFlash[i] - dt * 0.7f);
		foreach (var b in Buildings) { b.Flash = Math.Max(0, b.Flash - dt * 2f); b.FireFlash = Math.Max(0, b.FireFlash - dt * 4f); }
	}

	private void Economy(float dt)
	{
		foreach (var side in Sides)
		{
			float work = 0;
			foreach (var b in Buildings)
			{
				if (b.Side != side.Index || !b.Alive) continue;
				if (!b.Ready)
				{
					b.Build -= dt;
					if (b.Ready) Events.Add(new LiteEvent { Type = LiteEv.Built, Side = b.Side, Kind = b.Kind, Pos = b.Pos, Region = b.Region });
					continue;
				}
				if (b.Kind == LiteKind.Factory)
					work += (0.4f + 0.6f * b.Hp / b.MaxHp) * (Alert[b.Region] ? LiteRules.AlertWork : 1f);
			}
			float scale = IncomeScale[side.Index];
			side.Income = (LiteRules.BaseIncome + LiteRules.FactoryIncome * work) * scale;
			side.Money += side.Income * dt;
			// Production: one queue, every factory working on it.
			var prod = side.Production;
			prod.Rate = (LiteRules.BasePP + LiteRules.FactoryPP * work) * scale;
			_done.Clear();
			prod.Work(prod.Rate * dt, _done);
			// Repairs, paid for as they go.
			float spent = 0;
			if (side.Repairing)
				foreach (var b in Buildings)
				{
					if (b.Side != side.Index || !b.Alive || !b.Ready || b.Hp >= b.MaxHp) continue;
					float hp = Math.Min(b.MaxHp * LiteRules.RepairRate * dt, b.MaxHp - b.Hp);
					float price = hp / b.MaxHp * 100 * LiteRules.RepairPrice;
					if (side.Money < price) break;
					side.Money -= price;
					spent += price;
					b.Hp += hp;
				}
			side.RepairSpend += (spent / Math.Max(dt, 1e-4f) - side.RepairSpend) * Math.Min(1, dt * 2);
		}
	}

	// ---------------------------------------------------------------- weapons

	private void Launch(Pending p)
	{
		var arm = p.Arm;
		var target = p.Target + new Vector2(LiteRules.Scatter(arm) * MathF.Sqrt((float)_rng.NextDouble()), 0).Rotated((float)_rng.NextDouble() * MathF.Tau);
		var route = arm == LiteArm.Ballistic ? null : p.Route;
		var start = route is { Count: > 0 } ? OriginNear(p.Side, route[0]) : Origin(p.Side, arm, target);
		var w = new LiteWeapon
		{
			Id = ++_ids, Side = p.Side, Arm = arm, Raid = p.Raid, Start = start, Pos = start, Target = target,
			Speed = LiteRules.Speed(arm) * (0.94f + 0.12f * (float)_rng.NextDouble()),
		};
		w.Seen[p.Side] = true;
		if (arm == LiteArm.Ballistic) w.Seen[1 - p.Side] = true;
		float near = 12;
		foreach (var b in Buildings)
			if (b.Alive && b.Side != p.Side && b.Pos.DistanceTo(p.Target) < near) { near = b.Pos.DistanceTo(p.Target); w.Aim = b; }
		BuildPath(w, route);
		w.Dir = (w.Path[0] - start).Normalized();
		Weapons.Add(w);
		p.Raid.Launched++;
		Sides[p.Side].Launched++;
		Fx.Add(new LiteFx { Kind = LiteFxKind.Launch, A = start, Life = 0.7f, Side = p.Side });
		Events.Add(new LiteEvent { Type = LiteEv.Launch, Side = p.Side, Arm = arm, Pos = start, Region = Map.RegionAt(target), Raid = p.Raid });
	}

	/// For a drawn route: a launch site of ours nearest its first point.
	private Vector2 OriginNear(int side, Vector2 at)
	{
		Vector2 best = Sides[side].Center;
		float bd = float.MaxValue;
		foreach (var r in Map.Regions)
		{
			if (r.Side != side || r.City) continue;
			for (int i = 0; i < r.Spots.Count; i += 3)
			{
				float d = r.Spots[i].DistanceSquaredTo(at);
				if (d < bd) { bd = d; best = r.Spots[i]; }
			}
		}
		return best;
	}

	/// Drones go up from near the target, ballistic missiles from the nearest
	/// region, cruise missiles from deep inside the country (as from bombers).
	private Vector2 Origin(int side, LiteArm arm, Vector2 target)
	{
		_tmp.Clear();
		foreach (var r in Map.Regions) if (r.Side == side && !r.City && r.Spots.Count > 0) _tmp.Add(r);
		_tmp.Sort((a, b) => a.Label.DistanceSquaredTo(target).CompareTo(b.Label.DistanceSquaredTo(target)));
		int n = _tmp.Count;
		var pick = arm switch
		{
			LiteArm.Drone => _tmp[_rng.Next(Math.Min(3, n))],
			LiteArm.Ballistic => _tmp[_rng.Next(Math.Min(2, n))],
			_ => _tmp[n / 2 + _rng.Next(n - n / 2)],
		};
		return pick.Spots[_rng.Next(pick.Spots.Count)];
	}

	/// Along a drawn route if there is one, each weapon a few units off it so
	/// a salvo does not fly in single file. Otherwise drones bend once, gently,
	/// and cruise missiles now and then; ballistic missiles fly straight. The
	/// route is a smooth curve through the turning points.
	private void BuildPath(LiteWeapon w, List<Vector2>? route)
	{
		float R(float a, float b) => a + (float)_rng.NextDouble() * (b - a);
		var a = w.Start;
		var d = w.Target - a;
		float len = d.Length();
		var n = new Vector2(-d.Y, d.X) / Math.Max(1f, len);
		var ctrl = new List<Vector2> { a };
		int turns = 0;
		if (route != null)
		{
			var off = new Vector2(R(-6, 6), R(-6, 6));
			foreach (var q in route) ctrl.Add(q + off);
			turns = route.Count;
		}
		else if (w.Arm != LiteArm.Ballistic && len > 60)
		{
			bool drone = w.Arm == LiteArm.Drone;
			if (drone || _rng.NextDouble() < 0.5)
			{
				float amp = drone ? Math.Min(60f, len * 0.15f) : Math.Min(40f, len * 0.1f);
				var line = a + d * R(0.35f, 0.65f);
				var p = line + n * amp * R(-1f, 1f);
				if (Map.SideAt(p) < 0) p = line;
				ctrl.Add(p);
				turns = 1;
			}
		}
		ctrl.Add(w.Target);
		if (turns == 0) w.Path.Add(w.Target);
		else
			for (int i = 0; i < ctrl.Count - 1; i++)
			{
				var p0 = ctrl[Math.Max(0, i - 1)]; var p1 = ctrl[i]; var p2 = ctrl[i + 1]; var p3 = ctrl[Math.Min(ctrl.Count - 1, i + 2)];
				int steps = Math.Max(2, (int)(p1.DistanceTo(p2) / 12));
				for (int k = 1; k <= steps; k++)
				{
					float t = k / (float)steps, t2 = t * t, t3 = t2 * t;
					w.Path.Add(0.5f * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3));
				}
			}
		var prev = a;
		foreach (var p in w.Path) { w.Length += prev.DistanceTo(p); prev = p; }
	}

	private void MoveWeapons(float dt)
	{
		foreach (var w in Weapons)
		{
			if (!w.Alive) continue;
			float move = w.Speed * dt;
			w.Flown += move;
			while (move > 0 && w.Leg < w.Path.Count)
			{
				var to = w.Path[w.Leg] - w.Pos;
				float d = to.Length();
				if (d > 0.001f) w.Dir = to / d;
				if (d <= move) { w.Pos = w.Path[w.Leg]; w.Leg++; move -= d; }
				else { w.Pos += to / d * move; move = 0; }
			}
			// The track it leaves behind, drawn on the map.
			float step = w.Arm == LiteArm.Drone ? 6f : w.Arm == LiteArm.Cruise ? 6f : 10f;
			int keep = w.Arm == LiteArm.Drone ? 26 : w.Arm == LiteArm.Cruise ? 36 : 30;
			w.TrailAcc += w.Speed * dt;
			if (w.TrailAcc >= step)
			{
				w.TrailAcc = 0;
				w.Trail.Add(w.Pos);
				if (w.Trail.Count > keep) w.Trail.RemoveAt(0);
			}
			if (w.Leg >= w.Path.Count) Impact(w);
			else if (w.Aim != null && !w.Aim.Alive && w.Arm != LiteArm.Ballistic) Retarget(w);
		}
	}

	/// Its site is gone: head for the nearest other site of the enemy's that
	/// its side knows of close by, or carry on to the empty spot.
	private void Retarget(LiteWeapon w)
	{
		LiteBuilding? next = null;
		float bd = 90;
		foreach (var b in Buildings)
		{
			if (!b.Alive || b.Side == w.Side || !b.Seen[w.Side]) continue;
			float d = b.Pos.DistanceTo(w.Target);
			if (d < bd) { bd = d; next = b; }
		}
		w.Aim = next;
		if (next == null) return;
		w.Target = next.Pos;
		w.Path.Clear();
		w.Path.Add(next.Pos);
		w.Leg = 0;
		w.Length = w.Flown + w.Pos.DistanceTo(next.Pos);
	}

	/// Each side sees the other's drones and cruise missiles over its own land
	/// and within its air defence radars (half as far again as they shoot).
	/// Once seen, a weapon stays tracked.
	private void Detect()
	{
		foreach (var w in Weapons)
		{
			int v = 1 - w.Side;
			if (!w.Alive || w.Seen[v]) continue;
			bool seen = Map.SideAt(w.Pos) == v;
			if (!seen)
				foreach (var b in Buildings)
					if (b.Alive && b.Side == v && b.IsAd && b.Ready && b.Pos.DistanceTo(w.Pos) < LiteRules.AdRange * LiteRules.RadarReach) { seen = true; break; }
			if (!seen) continue;
			w.Seen[v] = true;
			Events.Add(new LiteEvent { Type = LiteEv.Detected, Side = w.Side, Arm = w.Arm, Pos = w.Pos, Region = Map.RegionAt(w.Pos), Raid = w.Raid });
		}
	}

	private void Impact(LiteWeapon w)
	{
		w.Alive = false;
		var arm = w.Arm;
		bool any = false;
		foreach (var b in Buildings)
		{
			if (!b.Alive || b.Side == w.Side) continue;
			if (b.Pos.DistanceTo(w.Pos) > LiteRules.Blast(arm) + (b.IsKey ? 4 : 0)) continue;
			any = true;
			// Armor takes its share of every hit.
			b.Hp -= LiteDamage.Dealt(arm, b.Kind);
			b.Flash = 1;
			if (b.IsKey && b.Hp > 0)
				Events.Add(new LiteEvent { Type = LiteEv.KeyHit, Side = b.Side, Kind = b.Kind, Pos = b.Pos, Value = b.Hp, Arm = arm });
			if (b.Hp <= 0) Destroy(b, w.Side, w.Raid);
		}
		if (any) { w.Raid.Hits++; Sides[w.Side].Hits++; }
		float size = arm == LiteArm.Drone ? 11 : arm == LiteArm.Cruise ? 15 : 21;
		Fx.Add(new LiteFx { Kind = LiteFxKind.Blast, A = w.Pos, Life = 0.9f, Size = size, Side = w.Side });
		Fx.Add(new LiteFx { Kind = LiteFxKind.Scorch, A = w.Pos, Life = 40f, Size = size, Side = w.Side });
		byte region = Map.RegionAt(w.Pos);
		if (region != LiteMap.None)
		{
			RegionFlash[region] = 1;
			if (Map.Regions[region].Side != w.Side) Sides[1 - w.Side].HitLog.Add((w.Pos, Time));
		}
		Events.Add(new LiteEvent { Type = LiteEv.Hit, Side = w.Side, Arm = arm, Pos = w.Pos, Region = region, Value = any ? 1 : 0, Raid = w.Raid });
		Finish(w.Raid);
	}

	private void Destroy(LiteBuilding b, int by, LiteRaid raid)
	{
		b.Alive = false;
		b.DeadAt = Time;
		if (b.Kind == LiteKind.Factory) _ruins.Add((b.Region, Time + LiteRules.RuinTime));
		Sides[b.Side].Lost++;
		Sides[by].Destroyed++;
		string where = b.Region < Map.Regions.Count ? Map.Regions[b.Region].Name : "";
		raid.Destroyed.Add($"{LiteGlyphs.Name(b.Kind)} in {where}");
		if (b.IsKey) Sides[b.Side].KeysLost++;
		Events.Add(new LiteEvent { Type = LiteEv.Destroyed, Side = b.Side, Kind = b.Kind, Pos = b.Pos, Region = b.Region, Value = Sides[b.Side].KeysLost });
		if (b.IsKey && Sides[b.Side].KeysLost >= LiteRules.KeysToWin && Winner < 0)
		{
			Winner = by;
			Events.Add(new LiteEvent { Type = LiteEv.GameOver, Side = by });
		}
	}

	internal void Kill(LiteWeapon w, int by, LiteBuilding? shooter)
	{
		w.Alive = false;
		if (shooter != null) shooter.Kills++;
		w.Raid.Down++;
		Sides[by].Downed++;
		Fx.Add(new LiteFx { Kind = LiteFxKind.Pop, A = w.Pos, Life = 0.5f, Size = w.Arm == LiteArm.Drone ? 6 : 8, Side = by });
		Events.Add(new LiteEvent { Type = LiteEv.ShotDown, Side = by, Arm = w.Arm, Pos = w.Pos, Region = Map.RegionAt(w.Pos), Raid = w.Raid });
		Finish(w.Raid);
	}

	private void Finish(LiteRaid raid)
	{
		raid.Done++;
		if (raid.Done < raid.Total) return;
		Sides[raid.Side].LastRaidLoss = raid.Total > 0 ? raid.Down / (float)raid.Total : 0;
		Events.Add(new LiteEvent { Type = LiteEv.RaidOver, Side = raid.Side, Pos = raid.Target, Raid = raid });
	}

	// Air defence engagement is in LiteAirDefence.

	// ---------------------------------------------------------------- intelligence and alerts

	private void Reveal()
	{
		foreach (var w in Weapons)
		{
			if (!w.Alive) continue;
			float r = LiteRules.SpotRadius(w.Arm);
			if (r <= 0) continue;
			foreach (var b in Buildings)
				if (b.Alive && b.Side != w.Side && !b.Seen[w.Side] && b.Pos.DistanceTo(w.Pos) < r) Spot(b, w.Side);
		}
	}

	internal void Spot(LiteBuilding b, int viewer)
	{
		if (b.Seen[viewer]) return;
		b.Seen[viewer] = true;
		Events.Add(new LiteEvent { Type = LiteEv.Spotted, Side = viewer, Kind = b.Kind, Pos = b.Pos, Region = b.Region });
	}

	/// A region is under alert while a drone or cruise missile is over it or
	/// close by, or would reach it in a few seconds on its present heading;
	/// where it will turn next nobody knows. A ballistic launch alerts the
	/// target region and its neighbours at once. The all-clear comes a few
	/// seconds after the last threat.
	private void Alerts(float dt)
	{
		Array.Clear(_threat);
		Array.Clear(_bal);
		foreach (var w in Weapons)
		{
			int victim = 1 - w.Side;
			// Nobody sounds the alert for what nobody has seen.
			if (!w.Alive || !w.Seen[victim]) continue;
			Mark(w.Pos, victim, false);
			if (w.Arm == LiteArm.Ballistic)
			{
				byte t = Map.RegionAt(w.Target);
				if (t != LiteMap.None && Map.Regions[t].Side == victim)
				{
					Mark(w.Target, victim, true);
					foreach (int n in Map.Regions[t].Neighbors) if (Map.Regions[n].Side == victim) { _threat[n] = true; _bal[n] = true; }
				}
				continue;
			}
			float r = LiteRules.AlertRadius(w.Arm);
			for (int a = 0; a < 8; a++) Mark(w.Pos + new Vector2(r, 0).Rotated(a * MathF.PI / 4), victim, false);
			float ahead = w.Speed * LiteRules.Heading(w.Arm);
			for (float d = 15; d <= ahead; d += 15) Mark(w.Pos + w.Dir * d, victim, false);
		}
		foreach (var r in Map.Regions)
			if (r.City) { _threat[r.Id] |= _threat[r.Parent]; _bal[r.Id] |= _bal[r.Parent]; }
		for (int i = 0; i < Alert.Length; i++)
		{
			int side = Map.Regions[i].Side;
			if (_bal[i]) { Ballistic[i] = true; _balQuiet[i] = 0; }
			else if (Ballistic[i] && (_balQuiet[i] += dt) >= 2f) Ballistic[i] = false;
			if (_threat[i])
			{
				_quiet[i] = 0;
				if (!Alert[i])
				{
					Alert[i] = true;
					AlertSince[i] = Time;
					if (Alerted[side]++ == 0)
					{
						SideAlertSince[side] = Time;
						Events.Add(new LiteEvent { Type = LiteEv.RaidAlert, Side = side, Region = i });
					}
				}
			}
			else if (Alert[i] && (_quiet[i] += dt) >= LiteRules.AllClearAfter)
			{
				Alert[i] = false;
				Ballistic[i] = false;
				if (--Alerted[side] == 0)
				{
					SideQuietSince[side] = Time;
					Events.Add(new LiteEvent { Type = LiteEv.AllClear, Side = side, Value = Time - SideAlertSince[side] });
				}
			}
		}
	}

	private void Mark(Vector2 p, int victim, bool ballistic)
	{
		byte id = Map.RegionAt(p);
		if (id == LiteMap.None || Map.Regions[id].Side != victim) return;
		_threat[id] = true;
		if (ballistic) _bal[id] = true;
	}
}
