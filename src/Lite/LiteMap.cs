using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Godot;

/// One region of the lite map, like an oblast on an air-alert map.
public sealed class LiteRegion
{
	public int Id, Side, Area;
	public string Name = "";
	/// The small city region round a capital ("м. Київ" on the real map).
	public bool City;
	/// For a city region, the region round it.
	public int Parent = -1;
	public Vector2 Label, Center;
	/// Points well inside the region: launch points and building spots.
	public readonly List<Vector2> Spots = new();
	public readonly HashSet<int> Neighbors = new();
}

/// The map of the lite game: two countries side by side, ours in the west and
/// the enemy's, as big or bigger, in the east up to the edge of the map. Each
/// is a jagged polygon bent by noise and cut into regions of about the same
/// size. Everything comes from the seed.
/// Region ids are rasterised at twice the map's resolution (the shader draws
/// the fills and borders from them); a one-unit grid keeps each unit's region
/// and its distance to the nearest region border, which places labels and
/// spots.
public sealed class LiteMap
{
	public const int W = 980, H = 720, S = 2, RW = W * S, RH = H * S;
	public const byte None = 255;
	private const float CityR = 15f;

	public readonly int Seed;
	public readonly byte[] Ids = new byte[RW * RH];
	public readonly byte[] Cell = new byte[W * H];
	public readonly float[] Edge = new float[W * H];
	public readonly List<LiteRegion> Regions = new();
	public readonly Vector2[] Capital = new Vector2[2];
	public readonly string[] CapitalName = new string[2];

	private float _fx, _bend, _salY, _salA, _salW;
	private Vector2 _c0, _c1;
	private int _ns;
	/// The warp and the region bend on the corners of the map units; points
	/// between them are interpolated.
	private Vector2[] _warp = null!, _bendGrid = null!;
	/// Each country's outline, and bays cut out of the coast.
	private readonly List<Vector2> _poly0 = new(), _poly1 = new();
	private readonly List<(Vector2 C, Vector2 R)> _bays = new();

	private static readonly string[] OurNames =
	{
		"Verbivska", "Lisova", "Zorianska", "Dubivska", "Kalynivska", "Ozerna", "Stepova", "Bilohirska",
		"Sosnivska", "Yasenivska", "Hrabivska", "Kamianska", "Bereznianska", "Topolivska", "Vyshnevska",
		"Lukivska", "Sribnianska", "Klenivska", "Vodianska", "Polianska", "Morivska", "Hlynska",
	};
	private static readonly string[] EnemyNames =
	{
		"Morvansk", "Kolmar", "Dvorsk", "Urbelsk", "Velgrad", "Tarmesk", "Zhorovsk", "Brekhov",
		"Sartovsk", "Gromel", "Krasnar", "Ulmedsk", "Borgansk", "Strelov", "Yarmut", "Ozhgorsk",
		"Kurgal", "Vyatsk", "Lebrovo", "Tamsk", "Sorvinsk", "Rudnev", "Belgost", "Orlemsk",
	};
	private static readonly string[] OurCapitals = { "Zoriv", "Svitanok", "Yasnohrad", "Verbohrad" };
	private static readonly string[] EnemyCapitals = { "Morgrad", "Kolvansk", "Tarmund" };

	public static LiteMap Generate(int seed)
	{
		var m = new LiteMap(seed);
		m.Build();
		return m;
	}

	private LiteMap(int seed) { Seed = seed; }

	public byte RegionAt(Vector2 p)
	{
		int x = (int)p.X, y = (int)p.Y;
		if (x < 0 || y < 0 || x >= W || y >= H) return None;
		return Cell[y * W + x];
	}

	public int SideAt(Vector2 p)
	{
		byte id = RegionAt(p);
		return id == None ? -1 : Regions[id].Side;
	}

	private void Build()
	{
		var rng = new Random(Seed);
		float R(float a, float b) => a + (float)rng.NextDouble() * (b - a);
		_ns = rng.Next(1, 1 << 20);
		// The frontier runs north to south somewhere left of the middle, so the
		// enemy is about as big as we are or bigger.
		_fx = R(470, 570);
		_bend = R(-70, 90);
		_salY = R(180, 560); _salA = R(-75, 75); _salW = R(50, 110);
		float cy = 362 + R(-14, 14);
		_c0 = new Vector2(_fx * 0.5f + R(0, 30), cy + R(-8, 16));
		Polygon(_poly0, rng, _c0, _c0.X - R(18, 40), _fx - _c0.X + R(140, 190), R(215, 262), R(212, 268), 15 + rng.Next(6));
		_c1 = new Vector2(_fx + (W - _fx) * 0.42f, cy + R(-22, 8));
		Polygon(_poly1, rng, _c1, _c1.X - _fx + R(150, 210), W - 16 - _c1.X, _c1.Y - R(22, 70), H - _c1.Y - R(22, 80), 14 + rng.Next(6));
		// A sea on our south coast now and then, and a bay or two elsewhere.
		if (rng.NextDouble() < 0.6)
			_bays.Add((new Vector2(_c0.X + R(-60, 140), H + R(30, 70)), new Vector2(R(150, 230), R(110, 150))));
		for (int i = 0, n = rng.Next(3); i < n; i++)
		{
			var own = i % 2 == 0 ? _poly0 : _poly1;
			var c = own[rng.Next(own.Count)];
			// Only on the outer coast: not by the frontier, not inside the other country.
			if (MathF.Abs(c.X - _fx) < 140 || Inside(i % 2 == 0 ? _poly1 : _poly0, c)) continue;
			_bays.Add((c, new Vector2(R(35, 70), R(30, 60))));
		}

		_warp = new Vector2[(W + 1) * (H + 1)];
		_bendGrid = new Vector2[(W + 1) * (H + 1)];
		Parallel.For(0, H + 1, y =>
		{
			for (int x = 0; x <= W; x++)
			{
				_warp[y * (W + 1) + x] = WarpAt(x, y);
				_bendGrid[y * (W + 1) + x] = new Vector2(Fbm(x * 0.011f, y * 0.011f, _ns + 5), Fbm(x * 0.011f, y * 0.011f, _ns + 6)) * 22f;
			}
		});

		// 1. Land and country per map unit; islands are dropped.
		var side = new sbyte[W * H];
		Parallel.For(0, H, y =>
		{
			for (int x = 0; x < W; x++) side[y * W + x] = (sbyte)SideOf(Warp(x + 0.5f, y + 0.5f));
		});
		KeepMainland(side);

		// 2. Region seeds: each capital first, then spread out over its country,
		// one region per about the same area on both sides.
		// The two capitals stand equally far from the other country, so neither
		// side starts with its capital closer to the enemy.
		var toEnemy = new[] { Chamfer(side, v => v == 1), Chamfer(side, v => v == 0) };
		var toSea = Chamfer(side, v => v < 0);
		var room = new float[2];
		for (int i = 0; i < W * H; i++)
			if (side[i] >= 0 && toSea[i] >= 32) room[side[i]] = Math.Max(room[side[i]], toEnemy[side[i]][i]);
		float reach = Math.Min(Math.Min(room[0], room[1]), 280f) * 0.85f;
		Capital[0] = Place(side, 0, toEnemy[0], toSea, reach, _c0 + new Vector2(R(-10, 70), -R(55, 110)));
		Capital[1] = Place(side, 1, toEnemy[1], toSea, reach, new Vector2(_c1.X + R(50, 120), _c1.Y + R(-110, 30)));
		var area = new int[2];
		foreach (var v in side) if (v >= 0) area[v]++;
		float per = area[0] / 15f;
		var seeds = new List<Vector2>[] { new() { Capital[0] }, new() { Capital[1] } };
		for (int s = 0; s < 2; s++)
		{
			int want = s == 0 ? 15 : Math.Clamp((int)MathF.Round(area[1] / per), 8, 22);
			float dmin = MathF.Sqrt(per) * 0.82f;
			for (int tries = 0; tries < 30000 && seeds[s].Count < want; tries++)
			{
				if (tries % 4000 == 3999) dmin *= 0.9f;
				int x = rng.Next(W), y = rng.Next(H);
				if (side[y * W + x] != s) continue;
				var p = new Vector2(x, y);
				bool ok = true;
				foreach (var list in seeds) foreach (var q in list) if (q.DistanceTo(p) < dmin) { ok = false; break; }
				if (ok) seeds[s].Add(p);
			}
		}
		int n0 = seeds[0].Count, n1 = seeds[1].Count;
		int[] city = { n0 + n1, n0 + n1 + 1 };
		var warped = new List<Vector2>();
		foreach (var list in seeds) foreach (var p in list) warped.Add(RegionPos(p.X, p.Y, Warp(p.X, p.Y)));
		var capW = new[] { warped[0], warped[n0] };

		// 3. The id raster: nearest seed of the pixel's own country, in warped space.
		Parallel.For(0, RH, ry =>
		{
			for (int rx = 0; rx < RW; rx++)
			{
				float x = (rx + 0.5f) / S, y = (ry + 0.5f) / S;
				var w = Warp(x, y);
				int s = SideOf(w);
				if (s < 0 || !Near(side, Math.Min(W - 1, (int)x), Math.Min(H - 1, (int)y), s)) { Ids[ry * RW + rx] = None; continue; }
				var q = RegionPos(x, y, w);
				if (q.DistanceSquaredTo(capW[s]) < CityR * CityR) { Ids[ry * RW + rx] = (byte)city[s]; continue; }
				int from = s == 0 ? 0 : n0, to = s == 0 ? n0 : n0 + n1, bi = from;
				float bd = float.MaxValue;
				for (int i = from; i < to; i++)
				{
					float d = q.DistanceSquaredTo(warped[i]);
					if (d < bd) { bd = d; bi = i; }
				}
				Ids[ry * RW + rx] = (byte)bi;
			}
		});
		for (int y = 0; y < H; y++)
			for (int x = 0; x < W; x++)
				Cell[y * W + x] = Ids[(y * S + 1) * RW + x * S + 1];
		ComputeEdge();

		// 4. Regions: names, label points, spots, neighbours.
		var ours = Shuffled(OurNames, rng);
		var theirs = Shuffled(EnemyNames, rng);
		CapitalName[0] = OurCapitals[rng.Next(OurCapitals.Length)];
		CapitalName[1] = EnemyCapitals[rng.Next(EnemyCapitals.Length)];
		int total = n0 + n1 + 2;
		for (int i = 0; i < total; i++)
		{
			var r = new LiteRegion { Id = i, Side = i < n0 || i == city[0] ? 0 : 1, City = i >= n0 + n1 };
			if (r.City) { r.Name = CapitalName[r.Side]; r.Parent = r.Side == 0 ? 0 : n0; }
			else if (i == 0) r.Name = CapitalName[0] + "ska";
			else r.Name = r.Side == 0 ? ours[(i - 1) % ours.Length] : theirs[(i - n0) % theirs.Length];
			Regions.Add(r);
		}
		var sum = new Vector2[total];
		var best = new float[total];
		var spots = new List<Vector2>[total];
		for (int i = 0; i < total; i++) { best[i] = float.MinValue; spots[i] = new List<Vector2>(); }
		for (int y = 0; y < H; y++)
			for (int x = 0; x < W; x++)
			{
				int id = Cell[y * W + x];
				if (id == None) continue;
				var r = Regions[id];
				r.Area++;
				sum[id] += new Vector2(x + 0.5f, y + 0.5f);
				if (Edge[y * W + x] >= 6 && (x + y * 7) % 5 == 0) spots[id].Add(new Vector2(x + 0.5f, y + 0.5f));
				if (x + 1 < W) { int n = Cell[y * W + x + 1]; if (n != None && n != id) { r.Neighbors.Add(n); Regions[n].Neighbors.Add(id); } }
				if (y + 1 < H) { int n = Cell[(y + 1) * W + x]; if (n != None && n != id) { r.Neighbors.Add(n); Regions[n].Neighbors.Add(id); } }
			}
		foreach (var r in Regions) r.Center = r.Area > 0 ? sum[r.Id] / r.Area : Capital[r.Side];
		for (int y = 0; y < H; y++)
			for (int x = 0; x < W; x++)
			{
				int id = Cell[y * W + x];
				if (id == None) continue;
				var p = new Vector2(x + 0.5f, y + 0.5f);
				float score = Math.Min(Edge[y * W + x], 40) - 0.06f * p.DistanceTo(Regions[id].Center);
				// Keep clear of the capital's own name.
				score -= Math.Max(0, 75 - p.DistanceTo(Capital[Regions[id].Side])) * 1.5f;
				if (score > best[id]) { best[id] = score; Regions[id].Label = p; }
			}
		foreach (var r in Regions)
		{
			var list = spots[r.Id];
			for (int i = list.Count - 1; i > 0; i--) { int j = rng.Next(i + 1); (list[i], list[j]) = (list[j], list[i]); }
			for (int i = 0; i < Math.Min(80, list.Count); i++) r.Spots.Add(list[i]);
			if (r.City) r.Label = Capital[r.Side] + new Vector2(0, 19);
		}
	}

	private static string[] Shuffled(string[] src, Random rng)
	{
		var a = (string[])src.Clone();
		for (int i = a.Length - 1; i > 0; i--) { int j = rng.Next(i + 1); (a[i], a[j]) = (a[j], a[i]); }
		return a;
	}

	/// The coastline and the frontier are drawn in coordinates bent by noise,
	/// so they wander like real borders.
	private Vector2 Warp(float x, float y) => Lerp(_warp, x, y);

	private static Vector2 Lerp(Vector2[] grid, float x, float y)
	{
		x = Math.Clamp(x, 0, W - 0.001f);
		y = Math.Clamp(y, 0, H - 0.001f);
		int xi = (int)x, yi = (int)y, i = yi * (W + 1) + xi;
		float fx = x - xi, fy = y - yi;
		var top = grid[i].Lerp(grid[i + 1], fx);
		var bottom = grid[i + W + 1].Lerp(grid[i + W + 2], fx);
		return top.Lerp(bottom, fy);
	}

	private Vector2 WarpAt(float x, float y)
	{
		float n1 = Fbm(x * 0.0045f, y * 0.0045f, _ns + 1), n2 = Fbm(x * 0.0045f, y * 0.0045f, _ns + 2);
		float m1 = Fbm(x * 0.01f, y * 0.01f, _ns + 8), m2 = Fbm(x * 0.01f, y * 0.01f, _ns + 9);
		float d1 = Fbm(x * 0.024f, y * 0.024f, _ns + 3), d2 = Fbm(x * 0.024f, y * 0.024f, _ns + 4);
		float f1 = Fbm(x * 0.06f, y * 0.06f, _ns + 10), f2 = Fbm(x * 0.06f, y * 0.06f, _ns + 11);
		return new Vector2(x + 40 * n1 + 24 * m1 + 13 * d1 + 4.5f * f1, y + 40 * n2 + 24 * m2 + 13 * d2 + 4.5f * f2);
	}

	/// Region borders get one more bend of their own, like borders along rivers.
	private Vector2 RegionPos(float x, float y, Vector2 w) => w + Lerp(_bendGrid, x, y);

	/// -1 sea, 0 ours, 1 the enemy's. West of the frontier a point is ours if
	/// it is inside our outline; the enemy's outline reaching round our coast
	/// past the frontier is the enemy's, and the other way round.
	private int SideOf(Vector2 w)
	{
		foreach (var (c, r) in _bays)
		{
			float qx = (w.X - c.X) / r.X, qy = (w.Y - c.Y) / r.Y;
			if (qx * qx + qy * qy < 1f) return -1;
		}
		bool in0 = Inside(_poly0, w), in1 = Inside(_poly1, w);
		if (!in0 && !in1) return -1;
		if (in0 != in1) return in0 ? 0 : 1;
		return w.X < Frontier(w.Y) ? 0 : 1;
	}

	private float Frontier(float y)
	{
		float d = (y - _salY) / _salW;
		return _fx - _bend * (Smooth((y - 160f) / 420f) - 0.5f) + 46f * Fbm(5.3f, y * 0.009f, _ns + 7)
			- _salA * MathF.Exp(-d * d);
	}

	/// A rough polygon round `c`: vertices at uneven angles on a squarish
	/// outline with its own radius to each side, each pushed in or out.
	private static void Polygon(List<Vector2> poly, Random rng, Vector2 c, float west, float east, float north, float south, int n)
	{
		float R(float a, float b) => a + (float)rng.NextDouble() * (b - a);
		for (int i = 0; i < n; i++)
		{
			float a = (i + R(-0.35f, 0.35f)) / n * MathF.Tau, cs = MathF.Cos(a), sn = MathF.Sin(a);
			float rx = cs > 0 ? east : west, ry = sn > 0 ? south : north;
			float k = 1f / MathF.Pow(MathF.Pow(MathF.Abs(cs) / rx, 3) + MathF.Pow(MathF.Abs(sn) / ry, 3), 1f / 3f);
			k *= rng.NextDouble() < 0.18 ? R(0.66f, 0.8f) : R(0.86f, 1.06f);
			var p = c + new Vector2(cs, sn) * k;
			poly.Add(new Vector2(Math.Clamp(p.X, 14, W - 14), Math.Clamp(p.Y, 14, H - 14)));
		}
	}

	private static bool Inside(List<Vector2> poly, Vector2 p)
	{
		bool inside = false;
		for (int i = 0, j = poly.Count - 1; i < poly.Count; j = i++)
		{
			var a = poly[i]; var b = poly[j];
			if ((a.Y > p.Y) != (b.Y > p.Y) && p.X < (b.X - a.X) * (p.Y - a.Y) / (b.Y - a.Y) + a.X) inside = !inside;
		}
		return inside;
	}

	private static bool Near(sbyte[] side, int x, int y, int s)
	{
		if (side[y * W + x] == s) return true;
		if (x > 0 && side[y * W + x - 1] == s) return true;
		if (x + 1 < W && side[y * W + x + 1] == s) return true;
		if (y > 0 && side[(y - 1) * W + x] == s) return true;
		return y + 1 < H && side[(y + 1) * W + x] == s;
	}

	private static void KeepMainland(sbyte[] side)
	{
		var comp = new int[W * H];
		var stack = new Stack<int>();
		int bestComp = 0, bestSize = 0, next = 0;
		for (int i = 0; i < W * H; i++)
		{
			if (side[i] < 0 || comp[i] != 0) continue;
			int c = ++next, size = 0;
			comp[i] = c;
			stack.Push(i);
			while (stack.Count > 0)
			{
				int j = stack.Pop();
				size++;
				int x = j % W, y = j / W;
				void Try(int k) { if (side[k] >= 0 && comp[k] == 0) { comp[k] = c; stack.Push(k); } }
				if (x > 0) Try(j - 1);
				if (x + 1 < W) Try(j + 1);
				if (y > 0) Try(j - W);
				if (y + 1 < H) Try(j + W);
			}
			if (size > bestSize) { bestSize = size; bestComp = c; }
		}
		for (int i = 0; i < W * H; i++) if (comp[i] != bestComp) side[i] = -1;
	}

	/// The point of country `s`, at least 32 units from the sea, whose distance
	/// to the other country is nearest `reach`; of those, the one nearest `want`.
	private static Vector2 Place(sbyte[] side, int s, float[] toEnemy, float[] toSea, float reach, Vector2 want)
	{
		Vector2 best = want;
		float bd = float.MaxValue;
		for (int y = 0; y < H; y += 2)
			for (int x = 0; x < W; x += 2)
			{
				int i = y * W + x;
				if (side[i] != s || toSea[i] < 32) continue;
				float d = MathF.Abs(toEnemy[i] - reach) * 4 + want.DistanceTo(new Vector2(x, y)) * 0.1f;
				if (d < bd) { bd = d; best = new Vector2(x + 0.5f, y + 0.5f); }
			}
		return best;
	}

	/// Chamfer distance from every unit to the nearest unit whose country passes `from`.
	private static float[] Chamfer(sbyte[] side, Func<sbyte, bool> from)
	{
		const float D = 1.4142f;
		var e = new float[W * H];
		for (int i = 0; i < W * H; i++) e[i] = from(side[i]) ? 0f : 1e9f;
		for (int y = 1; y < H - 1; y++)
			for (int x = 1; x < W - 1; x++)
			{
				int i = y * W + x;
				float v = e[i];
				v = Math.Min(v, e[i - 1] + 1); v = Math.Min(v, e[i - W] + 1);
				v = Math.Min(v, e[i - W - 1] + D); v = Math.Min(v, e[i - W + 1] + D);
				e[i] = v;
			}
		for (int y = H - 2; y >= 1; y--)
			for (int x = W - 2; x >= 1; x--)
			{
				int i = y * W + x;
				float v = e[i];
				v = Math.Min(v, e[i + 1] + 1); v = Math.Min(v, e[i + W] + 1);
				v = Math.Min(v, e[i + W + 1] + D); v = Math.Min(v, e[i + W - 1] + D);
				e[i] = v;
			}
		return e;
	}

	/// Chamfer distance from every unit to the nearest region border or coast.
	private void ComputeEdge()
	{
		const float D = 1.4142f;
		for (int y = 0; y < H; y++)
			for (int x = 0; x < W; x++)
			{
				int i = y * W + x, c = Cell[i];
				bool border = c == None || x == 0 || y == 0 || x == W - 1 || y == H - 1
					|| Cell[i - 1] != c || Cell[i + 1] != c || Cell[i - W] != c || Cell[i + W] != c;
				Edge[i] = border ? 0f : 1e9f;
			}
		for (int y = 1; y < H - 1; y++)
			for (int x = 1; x < W - 1; x++)
			{
				int i = y * W + x;
				float e = Edge[i];
				e = Math.Min(e, Edge[i - 1] + 1); e = Math.Min(e, Edge[i - W] + 1);
				e = Math.Min(e, Edge[i - W - 1] + D); e = Math.Min(e, Edge[i - W + 1] + D);
				Edge[i] = e;
			}
		for (int y = H - 2; y >= 1; y--)
			for (int x = W - 2; x >= 1; x--)
			{
				int i = y * W + x;
				float e = Edge[i];
				e = Math.Min(e, Edge[i + 1] + 1); e = Math.Min(e, Edge[i + W] + 1);
				e = Math.Min(e, Edge[i + W + 1] + D); e = Math.Min(e, Edge[i + W - 1] + D);
				Edge[i] = e;
			}
	}

	private static float Smooth(float t)
	{
		t = Math.Clamp(t, 0f, 1f);
		return t * t * (3 - 2 * t);
	}

	private static float Fbm(float x, float y, int s)
	{
		float sum = 0, amp = 0.5f, norm = 0, f = 1;
		for (int o = 0; o < 3; o++)
		{
			sum += amp * Value(x * f, y * f, s + o * 101);
			norm += amp;
			amp *= 0.5f;
			f *= 2.03f;
		}
		return sum / norm;
	}

	private static float Value(float x, float y, int s)
	{
		int xi = (int)MathF.Floor(x), yi = (int)MathF.Floor(y);
		float fx = x - xi, fy = y - yi;
		fx = fx * fx * (3 - 2 * fx);
		fy = fy * fy * (3 - 2 * fy);
		float a = Hash(xi, yi, s), b = Hash(xi + 1, yi, s), c = Hash(xi, yi + 1, s), d = Hash(xi + 1, yi + 1, s);
		return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy;
	}

	private static float Hash(int x, int y, int s)
	{
		unchecked
		{
			uint h = (uint)x * 0x8da6b343u ^ (uint)y * 0xd8163841u ^ (uint)s * 0xcb1ab31fu;
			h ^= h >> 15; h *= 0x2c1b3c6du;
			h ^= h >> 12; h *= 0x297a2d39u;
			h ^= h >> 15;
			return h / 2147483648f - 1f;
		}
	}
}
