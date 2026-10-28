using System;
using System.Collections.Generic;
using Godot;

/// Draws the lite map: the region fills (a sprite of region ids coloured by
/// a palette that eases towards each region's state), then names, air
/// defence cover, sites, weapons with their tracks and routes, interceptors,
/// blasts, and the ghost of whatever tool the player holds.
///
/// The names are a child drawn once (LiteLabels). Everything that moves goes
/// into one LiteBatch of triangles a frame, sent as a single command; only
/// the capitals' names and the tool ghost are ordinary draw calls.
///
/// Routes: what has flown leaves a track (drones a dotted one, missiles a
/// fading line). Our own weapons show the rest of their route as a dashed
/// line to the target. Of the enemy's we only see the heading, a short
/// dashed line as far as the alert reaches ahead; a ballistic missile's
/// fall is known, so its whole arc is dashed to the target.
public partial class LiteView : Node2D
{
	public LiteMain Main = null!;
	private Image _pal = null!;
	private ImageTexture _palTex = null!;
	private Color[] _shown = Array.Empty<Color>();
	private float _clock;
	private readonly List<Vector2> _pts = new();
	private readonly LiteBatch _b = new();

	private LiteSim Sim => Main.Sim;
	private LiteMap Map => Main.Map;

	public void Build()
	{
		var img = Image.CreateFromData(LiteMap.RW, LiteMap.RH, false, Image.Format.R8, Map.Ids);
		_pal = Image.CreateEmpty(256, 2, false, Image.Format.Rgba8);
		_shown = new Color[Map.Regions.Count];
		for (int i = 0; i < _shown.Length; i++)
		{
			_shown[i] = Target(i);
			_pal.SetPixel(i, 0, _shown[i]);
			_pal.SetPixel(i, 1, new Color(Map.Regions[i].Side, 0, 0, 1));
		}
		_palTex = ImageTexture.CreateFromImage(_pal);
		var mat = new ShaderMaterial { Shader = GD.Load<Shader>("res://src/Lite/lite_map.gdshader") };
		var ids = ImageTexture.CreateFromImage(img);
		mat.SetShaderParameter("ids", ids);
		mat.SetShaderParameter("palette", _palTex);
		AddChild(new Sprite2D
		{
			Texture = ids, Centered = false, Scale = Vector2.One / LiteMap.S,
			Material = mat, TextureFilter = TextureFilterEnum.Nearest, ShowBehindParent = true,
		});
		AddChild(new LiteLabels { Map = Map, ShowBehindParent = true });
	}

	private Color Target(int i)
	{
		var r = Map.Regions[i];
		Color c = r.Side == 0 ? LiteGlyphs.OurLand : LiteGlyphs.EnemyLand;
		if (Sim.Alert[i])
			c = r.Side == 0
				? (Sim.Ballistic[i] ? LiteGlyphs.BallisticAlert : LiteGlyphs.AirAlert)
				: (Sim.Ballistic[i] ? LiteGlyphs.BallisticAlert : LiteGlyphs.EnemyAlert);
		if (i == Main.HoverRegion) c = c.Lightened(0.07f);
		float f = Sim.RegionFlash[i];
		if (f > 0) c = c.Lerp(LiteGlyphs.HitGlow, f * 0.4f);
		return c;
	}

	public override void _Process(double delta)
	{
		float dt = (float)delta;
		_clock += dt;
		float k = 1 - MathF.Exp(-dt * 7f);
		for (int i = 0; i < _shown.Length; i++)
		{
			_shown[i] = _shown[i].Lerp(Target(i), k);
			_pal.SetPixel(i, 0, _shown[i]);
		}
		_palTex.Update(_pal);
		QueueRedraw();
	}

	private bool Shown(LiteBuilding b) => b.Side == 0 || b.Seen[0] || Sim.Winner >= 0;

	/// Enemy weapons appear once our side has seen them.
	private bool Shown(LiteWeapon w) => w.Alive && (w.Seen[0] || Sim.Winner >= 0);

	public override void _Draw()
	{
		double t0 = LitePerf.Now;
		DrawAll();
		LitePerf.DrawMs += LitePerf.Now - t0;
	}

	private void DrawAll()
	{
		var sim = Sim;
		var b = _b;
		b.Begin(this);
		// Air defence radar sectors: ours, and the enemy's that has shown itself.
		if (LiteSettings.Ranges)
			foreach (var s in sim.Buildings)
			{
				if (!s.Alive || !s.IsAd || !s.Ready || !Shown(s)) continue;
				Sector(s.Pos, s.Facing, LiteGlyphs.SideColor(s.Side), 1f, s.FireFlash);
				// Turning: where it will face, dashed.
				if (MathF.Abs(Mathf.AngleDifference(s.Facing, s.TargetFacing)) > 0.02f)
				{
					_pts.Clear();
					_pts.Add(s.Pos);
					_pts.Add(s.Pos + Vector2.FromAngle(s.TargetFacing) * LiteRules.AdRange);
					b.Dashed(_pts, new Color(LiteGlyphs.SideColor(s.Side), 0.5f), 1.2f, 5, 4);
				}
			}
		foreach (var f in sim.Fx)
			if (f.Kind == LiteFxKind.Scorch)
				b.Disc(f.A, f.Size * 0.5f, new Color(0.04f, 0.04f, 0.05f, 0.32f * (1 - f.Age / f.Life)));
		// Ballistic targets: a ring closing in as the missile comes down.
		foreach (var w in sim.Weapons)
		{
			if (!w.Alive || w.Arm != LiteArm.Ballistic) continue;
			var col = w.Side == 1 ? new Color(1f, 0.85f, 0.8f) : LiteGlyphs.Ours;
			float k = w.Progress;
			b.Ring(w.Target, 7 + 20 * (1 - k), new Color(col, 0.3f + 0.6f * k), 1.5f);
			b.Disc(w.Target, 2f, new Color(col, 0.8f));
		}
		foreach (var w in sim.Weapons) if (Shown(w)) DrawRoute(w);
		foreach (var s in sim.Buildings) if (Shown(s)) DrawBuilding(s);
		foreach (var w in sim.Weapons) if (Shown(w)) DrawWeapon(w);
		foreach (var i in sim.Interceptors) if (i.Alive) DrawInterceptor(i);
		foreach (var f in sim.Fx) DrawFx(f);
		b.Flush();
		for (int side = 0; side < 2; side++)
			LiteLabels.Draw(this, Sim.Sides[side].Center + new Vector2(0, 4), Map.CapitalName[side], 12, LiteGlyphs.Text);
		DrawTool();
	}

	private void DrawBuilding(LiteBuilding s)
	{
		var b = _b;
		var col = LiteGlyphs.SideColor(s.Side);
		bool cap = s.IsKey;
		float rad = cap ? 9.5f : 8f;
		var p = s.Pos;
		if (!s.Alive)
		{
			float a = Math.Clamp(1 - (Sim.Time - s.DeadAt) / 30f, 0, 1);
			b.Disc(p, rad * 0.8f, new Color(0.07f, 0.07f, 0.08f, 0.75f * a));
			var x = new Color(0.55f, 0.57f, 0.6f, 0.8f * a);
			b.Line(p + new Vector2(-3.5f, -3.5f), p + new Vector2(3.5f, 3.5f), x, 1.5f);
			b.Line(p + new Vector2(3.5f, -3.5f), p + new Vector2(-3.5f, 3.5f), x, 1.5f);
			return;
		}
		b.Disc(p + new Vector2(0, 1.5f), rad + 1.5f, new Color(0, 0, 0, 0.3f));
		b.Disc(p, rad, LiteGlyphs.Page.Lerp(LiteGlyphs.HitGlow, s.Flash * 0.7f));
		if (s.Ready) b.Ring(p, rad, col, 1.6f);
		else
		{
			b.Ring(p, rad, new Color(col, 0.25f), 1.6f);
			float k = 1 - s.Build / s.BuildTotal;
			if (k > 0.01f) b.Ring(p, rad, col, 1.6f, -MathF.PI / 2, -MathF.PI / 2 + MathF.Tau * k);
		}
		LiteGlyphs.Draw(b, LiteGlyphs.Of(s.Kind), p, cap ? 1.25f : 0.95f, new Color(1, 1, 1, s.Ready ? 1f : 0.45f));
		// Air defence: a tick on the rim towards where its radar faces.
		if (s.IsAd && s.Ready)
		{
			var dir = Vector2.FromAngle(s.Facing);
			b.Line(p + dir * (rad + 1), p + dir * (rad + 6), col, 2f);
		}
		if (cap || s.Hp < s.MaxHp)
		{
			float w = cap ? 28 : 16, y = p.Y + rad + 4;
			var bar = new Rect2(p.X - w / 2, y, w, 3);
			b.Rect(bar, new Color(0, 0, 0, 0.55f));
			b.Rect(new Rect2(bar.Position, new Vector2(w * Math.Max(0, s.Hp) / s.MaxHp, 3)), col);
		}
	}

	/// An air defence radar sector: a faint cone with its rim and sides.
	private void Sector(Vector2 at, float facing, Color col, float strength, float flash)
	{
		float half = Mathf.DegToRad(LiteRules.AdArc) / 2, r = LiteRules.AdRange;
		_b.Fan(at, r, new Color(col, 0.05f * strength), facing - half, facing + half);
		var edge = new Color(col, (0.22f + 0.3f * flash) * strength);
		_b.Ring(at, r, edge, 1f, facing - half, facing + half);
		_b.Line(at, at + Vector2.FromAngle(facing - half) * r, new Color(edge, edge.A * 0.6f), 1f);
		_b.Line(at, at + Vector2.FromAngle(facing + half) * r, new Color(edge, edge.A * 0.6f), 1f);
	}

	private static readonly Color EnemyWeapon = new("#ff4f3f"), OurWeapon = new("#5cb0ff");
	private static Color WeaponColor(int side) => side == 1 ? EnemyWeapon : OurWeapon;

	/// The track behind a weapon and, if routes are shown, the way ahead.
	private void DrawRoute(LiteWeapon w)
	{
		var b = _b;
		var col = WeaponColor(w.Side);
		int n = w.Trail.Count;
		if (w.Arm == LiteArm.Drone)
			for (int i = 0; i < n; i++)
				b.Dot(w.Trail[i], 1.1f, new Color(col, 0.65f * (i + 1) / (n + 1)));
		else
		{
			float width = w.Arm == LiteArm.Ballistic ? 2f : 1.5f;
			for (int i = 0; i < n; i++)
			{
				var to = i + 1 < n ? w.Trail[i + 1] : w.Pos;
				b.Line(w.Trail[i], to, new Color(col, 0.55f * (i + 1) / (n + 1)), new Color(col, 0.55f * (i + 2) / (n + 1)), width);
			}
		}
		if (!LiteSettings.Routes) return;
		if (w.Side == 0)
		{
			_pts.Clear();
			_pts.Add(w.Pos);
			for (int i = w.Leg; i < w.Path.Count; i++) _pts.Add(w.Path[i]);
			b.Dashed(_pts, new Color(col, 0.32f), 1.1f, 6, 6);
			var t = w.Target;
			b.Line(t + new Vector2(-3, -3), t + new Vector2(3, 3), new Color(col, 0.6f), 1.2f);
			b.Line(t + new Vector2(3, -3), t + new Vector2(-3, 3), new Color(col, 0.6f), 1.2f);
		}
		else if (w.Arm == LiteArm.Ballistic)
		{
			_pts.Clear();
			_pts.Add(w.Pos);
			_pts.Add(w.Target);
			b.Dashed(_pts, new Color(col, 0.4f), 1.2f, 6, 4);
		}
		else
		{
			float ahead = w.Speed * LiteRules.Heading(w.Arm);
			var end = w.Pos + w.Dir * ahead;
			_pts.Clear();
			_pts.Add(w.Pos + w.Dir * 8);
			_pts.Add(end);
			b.Dashed(_pts, new Color(col, 0.38f), 1.1f, 4, 4);
			var back = -w.Dir * 5;
			b.Line(end, end + back.Rotated(0.6f), new Color(col, 0.5f), 1.2f);
			b.Line(end, end + back.Rotated(-0.6f), new Color(col, 0.5f), 1.2f);
		}
	}

	private static readonly Color Dark = new(0.05f, 0.05f, 0.06f, 0.85f);

	private void DrawWeapon(LiteWeapon w)
	{
		var col = WeaponColor(w.Side);
		float ang = w.Dir.Angle();
		switch (w.Arm)
		{
			case LiteArm.Drone: LiteGlyphs.Draw(_b, LiteGlyph.Drone, w.Pos, 0.85f, col, ang, Dark); break;
			case LiteArm.Cruise: LiteGlyphs.Draw(_b, LiteGlyph.Cruise, w.Pos, 0.85f, col, ang, Dark); break;
			default:
				_b.Disc(w.Pos, 6f, new Color(col, 0.22f));
				LiteGlyphs.Draw(_b, LiteGlyph.Ballistic, w.Pos, 0.9f, col.Lightened(0.25f), 0, Dark);
				break;
		}
	}

	private void DrawInterceptor(LiteInterceptor i)
	{
		int n = i.Trail.Count;
		for (int k = 0; k < n; k++)
		{
			var to = k + 1 < n ? i.Trail[k + 1] : i.Pos;
			_b.Line(i.Trail[k], to, new Color(1, 1, 1, 0.5f * (k + 1) / (n + 1)), new Color(1, 1, 1, 0.5f * (k + 2) / (n + 1)), 1.2f);
		}
		_b.Disc(i.Pos, 1.8f, Colors.White);
	}

	private void DrawFx(LiteFx f)
	{
		var b = _b;
		float t = f.Age / f.Life, inv = 1 - t;
		switch (f.Kind)
		{
			case LiteFxKind.Blast:
				float grow = 1 - inv * inv;
				b.Disc(f.A, f.Size * (0.35f + 0.65f * grow), new Color(1f, 0.72f, 0.32f, 0.85f * inv * inv));
				b.Disc(f.A, Math.Max(0.2f, f.Size * 0.3f * inv), new Color(1f, 0.95f, 0.8f, inv));
				b.Ring(f.A, f.Size * (0.5f + 1.1f * grow), new Color(1f, 0.6f, 0.3f, 0.7f * inv), 1.5f);
				break;
			case LiteFxKind.Pop:
				b.Disc(f.A, 1.5f + f.Size * t, new Color(1f, 0.95f, 0.7f, 0.9f * inv));
				b.Ring(f.A, 2 + f.Size * 1.6f * t, new Color(1, 1, 1, 0.6f * inv), 1.2f);
				break;
			case LiteFxKind.Puff:
				b.Disc(f.A, 2 + f.Size * t, new Color(0.75f, 0.77f, 0.8f, 0.45f * inv));
				break;
			case LiteFxKind.Tracer:
				b.Line(f.A, f.B, new Color(1f, 0.88f, 0.5f, 0.8f * inv), 1f);
				break;
			case LiteFxKind.Launch:
				b.Ring(f.A, 2 + 9 * t, new Color(LiteGlyphs.SideColor(f.Side), 0.6f * inv), 1.3f);
				break;
		}
	}

	private void DrawTool()
	{
		var p = Main.Mouse;
		if (Main.Aiming is LiteBuilding aim && Main.Mouse.DistanceTo(aim.Pos) > 10)
		{
			// Turning one of ours: its sector as it would face, towards the mouse.
			_b.Begin(this);
			Sector(aim.Pos, (Main.Mouse - aim.Pos).Angle(), LiteGlyphs.Yellow, 2.5f, 0);
			_b.Flush();
			return;
		}
		if (Main.BuildTool == LiteKind.Factory)
		{
			// Factories go into regions: under each of ours, its room as pips,
			// filled for factories, crossed for ruins, empty for free places.
			foreach (var r in Map.Regions)
			{
				if (r.Side != 0 || r.City) continue;
				int f = Sim.FactoriesIn(r.Id), ru = Sim.RuinsIn(r.Id), n = Sim.Slots[r.Id];
				var at = r.Label + new Vector2(-(n - 1) * 5f, 13);
				if (n == 0) { DrawString(LiteGlyphs.Font, r.Label + new Vector2(-30, 18), "no room", HorizontalAlignment.Center, 60, 9, LiteGlyphs.Faint); continue; }
				for (int i = 0; i < n; i++)
				{
					var c = at + new Vector2(i * 10f, 0);
					var box = new Rect2(c - new Vector2(3.5f, 3.5f), new Vector2(7, 7));
					if (i < f) DrawRect(box, LiteGlyphs.Ours);
					else if (i < f + ru)
					{
						DrawRect(box, LiteGlyphs.Muted, false, 1.2f);
						DrawLine(box.Position, box.End, LiteGlyphs.Muted, 1.2f, true);
					}
					else DrawRect(box, LiteGlyphs.Good, false, 1.4f);
				}
			}
			return;
		}
		if (Main.BuildTool is LiteKind k)
		{
			// Under each of our regions, how many air defence sites it holds of the most it can.
			foreach (var r in Map.Regions)
			{
				if (r.Side != 0) continue;
				int n = Sim.AdIn(r.Id);
				var at = r.City ? Map.Capital[0] + new Vector2(0, 40) : r.Label + new Vector2(0, 17);
				DrawString(LiteGlyphs.Bold, at + new Vector2(-30, 0), $"AD {n}/{LiteRules.AdPerRegion}", HorizontalAlignment.Center, 60, 9,
					n >= LiteRules.AdPerRegion ? LiteGlyphs.Enemy : LiteGlyphs.Good);
			}
			bool ok = Sim.CanPlace(0, p) && Sim.AdRoom(p) && Sim.Sides[0].Money >= Sim.Cost(0, k);
			var col = ok ? LiteGlyphs.Ours : LiteGlyphs.Enemy;
			if (k == LiteKind.Ad)
			{
				// Its sector as it would first face, towards the enemy capital.
				_b.Begin(this);
				Sector(p, (Sim.Sides[1].Center - p).Angle(), col, 2.2f, 0);
				_b.Flush();
			}
			DrawCircle(p, 8, new Color(LiteGlyphs.Page, 0.85f), true, -1, true);
			DrawArc(p, 8, 0, MathF.Tau, 36, col, 1.6f, true);
			LiteGlyphs.Draw(this, LiteGlyphs.Of(k), p, 0.95f, new Color(1, 1, 1, 0.85f));
		}
		else if (Main.StrikeTool is LiteArm a)
		{
			var at = Main.StrikeTarget;
			bool ok = Map.SideAt(at) == 1;
			if (Main.Drawing is { } route)
			{
				// The route being drawn, dashed, to the target under the mouse.
				var pts = new List<Vector2>(route) { at };
				var line = new Color(LiteGlyphs.Yellow, 0.85f);
				for (int i = 0; i + 1 < pts.Count; i++) DrawDashedLine(pts[i], pts[i + 1], line, 1.6f, 6f, true, true);
				DrawCircle(pts[0], 3f, line, true, -1, true);
			}
			var col = ok ? LiteGlyphs.Yellow : LiteGlyphs.Muted;
			float r = LiteRules.Blast(a) + LiteRules.Scatter(a);
			DrawArc(at, r, 0, MathF.Tau, 48, col, 1.4f, true);
			for (int i = 0; i < 4; i++)
			{
				var d = new Vector2(1, 0).Rotated(i * MathF.PI / 2);
				DrawLine(at + d * (r - 4), at + d * (r + 5), col, 1.4f, true);
			}
			if (Main.StrikeSnap != null) DrawArc(at, 12, 0, MathF.Tau, 32, Colors.White, 1.2f, true);
			if (ok)
			{
				string s = $"{LiteGlyphs.Plural(a, 2)} · {Math.Min(Main.Salvo, Sim.Sides[0].Production.Stock[(int)a])} of {Sim.Sides[0].Production.Stock[(int)a]} in stock";
				var font = LiteGlyphs.Bold;
				DrawStringOutline(font, at + new Vector2(r + 8, 4), s, HorizontalAlignment.Left, -1, 11, 4, new Color(0, 0, 0, 0.6f));
				DrawString(font, at + new Vector2(r + 8, 4), s, HorizontalAlignment.Left, -1, 11, LiteGlyphs.Text);
			}
		}
	}
}
