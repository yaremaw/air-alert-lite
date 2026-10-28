using System;
using Godot;

public enum LiteGlyph { Capital, Factory, Gun, Sam, Drone, Cruise, Ballistic, Bunker, Energy, Gov }

/// Colours, fonts, names and the small flat icons of the lite game. Icons are
/// polygons, so the same glyph serves the map and the buttons at any size.
public static class LiteGlyphs
{
	public static readonly Color Page = new("#16181d");
	public static readonly Color Panel = new("#1c1f25");
	public static readonly Color PanelHi = new("#262a33");
	public static readonly Color Line = new("#2e323b");
	public static readonly Color Text = new("#e8eaee");
	public static readonly Color Muted = new("#8b919d");
	public static readonly Color Faint = new("#5b616c");
	public static readonly Color Ours = new("#4ea1ff");
	public static readonly Color Enemy = new("#ff5a48");
	public static readonly Color Yellow = new("#e5ad16");
	public static readonly Color Good = new("#46c47e");

	// Region fills, after map.ukrainealarm.com.
	public static readonly Color OurLand = new("#3a3d46");
	public static readonly Color EnemyLand = new("#6a2622");
	public static readonly Color AirAlert = new("#d4a017");
	public static readonly Color BallisticAlert = new("#e0574a");
	public static readonly Color EnemyAlert = new("#b13d33");
	public static readonly Color HitGlow = new("#ff8a3d");

	public static Font Font = ThemeDB.FallbackFont, Bold = ThemeDB.FallbackFont;
	private static bool _loaded;

	public static Color SideColor(int side) => side == 0 ? Ours : Enemy;

	/// Inter (assets/fonts, SIL OFL) with tabular figures, so counters do not
	/// jitter; a bolder cut of it for titles and map labels.
	public static void LoadFonts()
	{
		if (_loaded) return;
		_loaded = true;
		const string path = "res://assets/fonts/Inter.ttf";
		if (!FileAccess.FileExists(path)) return;
		var f = new FontFile();
		if (f.LoadDynamicFont(path) != Error.Ok) return;
		f.Antialiasing = TextServer.FontAntialiasing.Gray;
		f.Hinting = TextServer.Hinting.Light;
		f.GenerateMipmaps = false;
		var tnum = new Godot.Collections.Dictionary { { TextServerManager.GetPrimaryInterface().NameToTag("tnum"), 1 } };
		Font = new FontVariation { BaseFont = f, OpentypeFeatures = tnum };
		Bold = new FontVariation { BaseFont = f, OpentypeFeatures = tnum, VariationEmbolden = 0.6f };
		// The panel and the HUD draw well over the default 64 strings a frame;
		// with a small cache every one of them is shaped again each frame.
		Font.SetCacheCapacity(512, 64);
		Bold.SetCacheCapacity(512, 64);
		ThemeDB.FallbackFont = Font;
	}

	public static string Name(LiteKind k) => k switch
	{
		LiteKind.Factory => "Factory", LiteKind.Ad => "Air defence", LiteKind.Hq => "Headquarters",
		LiteKind.Bunker => "Command bunker", LiteKind.Energy => "Energy centre", _ => "Government building",
	};

	/// Short names of the key targets, for the status panel.
	public static string Short(LiteKind k) => k switch
	{
		LiteKind.Hq => "HQ", LiteKind.Bunker => "Bunker", LiteKind.Energy => "Energy", LiteKind.Gov => "Gov", _ => Name(k),
	};

	public static string Name(LiteArm a) => a switch
	{
		LiteArm.Drone => "Drone", LiteArm.Cruise => "Cruise", _ => "Ballistic",
	};

	public static string Plural(LiteArm a, int n) => a switch
	{
		LiteArm.Drone => n == 1 ? "drone" : "drones",
		LiteArm.Cruise => n == 1 ? "cruise missile" : "cruise missiles",
		_ => n == 1 ? "ballistic missile" : "ballistic missiles",
	};

	public static LiteGlyph Of(LiteKind k) => k switch
	{
		LiteKind.Factory => LiteGlyph.Factory, LiteKind.Ad => LiteGlyph.Sam, LiteKind.Hq => LiteGlyph.Capital,
		LiteKind.Bunker => LiteGlyph.Bunker, LiteKind.Energy => LiteGlyph.Energy, _ => LiteGlyph.Gov,
	};

	public static LiteGlyph Of(LiteArm a) => a switch
	{
		LiteArm.Drone => LiteGlyph.Drone, LiteArm.Cruise => LiteGlyph.Cruise, _ => LiteGlyph.Ballistic,
	};

	// Shapes on a grid of about ten units, pointing right (weapons) or up.
	private static readonly Vector2[] FactoryPts =
	{
		new(-5, 4), new(5, 4), new(5, -1), new(1.7f, -3.5f), new(1.7f, -1), new(-1.6f, -3.5f), new(-1.6f, -1), new(-5, -3.5f),
	};
	private static readonly Vector2[] SamPts =
	{
		new(0, -5.5f), new(1.6f, -2.5f), new(1.6f, 2.5f), new(3.2f, 4.8f), new(-3.2f, 4.8f), new(-1.6f, 2.5f), new(-1.6f, -2.5f),
	};
	private static readonly Vector2[] DronePts = { new(6, 0), new(-4, -5.5f), new(-2, 0), new(-4, 5.5f) };
	private static readonly Vector2[] CruisePts =
	{
		new(7, 0), new(4, -1.3f), new(0, -1.3f), new(-2, -4.5f), new(-3.5f, -4.5f), new(-2.5f, -1.3f), new(-6, -1.3f),
		new(-7, -3), new(-7.5f, -3), new(-7.5f, 3), new(-7, 3), new(-6, 1.3f), new(-2.5f, 1.3f), new(-3.5f, 4.5f),
		new(-2, 4.5f), new(0, 1.3f), new(4, 1.3f),
	};
	private static readonly Vector2[] StarPts = Star();
	private static readonly Vector2[] BunkerPts =
	{
		new(-5.5f, 3.5f), new(5.5f, 3.5f), new(5.5f, 1.5f), new(4f, -1.5f), new(2f, -3.5f), new(0, -4f), new(-2f, -3.5f), new(-4f, -1.5f), new(-5.5f, 1.5f),
	};
	private static readonly Vector2[] EnergyPts = { new(1.5f, -5.5f), new(-3.5f, 0.8f), new(-0.3f, 0.8f), new(-1.5f, 5.5f), new(3.5f, -0.8f), new(0.3f, -0.8f) };
	private static readonly Vector2[] GovPts =
	{
		new(-5.5f, -1.5f), new(0, -5f), new(5.5f, -1.5f), new(4.5f, -1.5f), new(4.5f, 3f), new(5.5f, 3f), new(5.5f, 4.5f),
		new(-5.5f, 4.5f), new(-5.5f, 3f), new(-4.5f, 3f), new(-4.5f, -1.5f),
	};

	private static Vector2[] Star()
	{
		var p = new Vector2[10];
		for (int i = 0; i < 10; i++)
		{
			float r = i % 2 == 0 ? 5.6f : 2.3f, a = -MathF.PI / 2 + i * MathF.PI / 5;
			p[i] = new Vector2(MathF.Cos(a), MathF.Sin(a)) * r;
		}
		return p;
	}

	/// Draws a glyph centred on `c`, `s` pixels per grid unit, turned by `angle`.
	public static void Draw(CanvasItem ci, LiteGlyph g, Vector2 c, float s, Color col, float angle = 0, Color? outline = null)
	{
		switch (g)
		{
			case LiteGlyph.Capital: Poly(ci, StarPts, c, s, angle, col, outline); break;
			case LiteGlyph.Bunker: Poly(ci, BunkerPts, c, s, angle, col, outline); break;
			case LiteGlyph.Energy: Poly(ci, EnergyPts, c, s, angle, col, outline); break;
			case LiteGlyph.Gov: Poly(ci, GovPts, c, s, angle, col, outline); break;
			case LiteGlyph.Factory: Poly(ci, FactoryPts, c, s, angle, col, outline); break;
			case LiteGlyph.Sam: Poly(ci, SamPts, c, s, angle, col, outline); break;
			case LiteGlyph.Drone: Poly(ci, DronePts, c, s, angle, col, outline); break;
			case LiteGlyph.Cruise: Poly(ci, CruisePts, c, s, angle, col, outline); break;
			case LiteGlyph.Gun:
				var hub = c + new Vector2(0, 1.6f * s);
				ci.DrawLine(hub, c + new Vector2(-2.6f, -4.2f) * s, col, 1.3f * s, true);
				ci.DrawLine(hub, c + new Vector2(2.6f, -4.2f) * s, col, 1.3f * s, true);
				ci.DrawCircle(hub, 2.6f * s, col, true, -1, true);
				break;
			case LiteGlyph.Ballistic:
				if (outline != null) ci.DrawCircle(c, 3.6f * s, outline.Value, true, -1, true);
				ci.DrawCircle(c, 2.8f * s, col, true, -1, true);
				break;
		}
	}

	private static readonly System.Collections.Generic.Dictionary<Vector2[], int[]> Tris = new();

	private static int[] Cut(Vector2[] pts)
	{
		if (!Tris.TryGetValue(pts, out var t)) Tris[pts] = t = Geometry2D.TriangulatePolygon(pts);
		return t;
	}

	/// The same glyphs into a batch of triangles, for the map; each shape is cut into triangles once.
	public static void Draw(LiteBatch b, LiteGlyph g, Vector2 c, float s, Color col, float angle = 0, Color? outline = null)
	{
		switch (g)
		{
			case LiteGlyph.Capital: b.Shape(StarPts, Cut(StarPts), c, s, angle, col, outline); break;
			case LiteGlyph.Bunker: b.Shape(BunkerPts, Cut(BunkerPts), c, s, angle, col, outline); break;
			case LiteGlyph.Energy: b.Shape(EnergyPts, Cut(EnergyPts), c, s, angle, col, outline); break;
			case LiteGlyph.Gov: b.Shape(GovPts, Cut(GovPts), c, s, angle, col, outline); break;
			case LiteGlyph.Factory: b.Shape(FactoryPts, Cut(FactoryPts), c, s, angle, col, outline); break;
			case LiteGlyph.Sam: b.Shape(SamPts, Cut(SamPts), c, s, angle, col, outline); break;
			case LiteGlyph.Drone: b.Shape(DronePts, Cut(DronePts), c, s, angle, col, outline); break;
			case LiteGlyph.Cruise: b.Shape(CruisePts, Cut(CruisePts), c, s, angle, col, outline); break;
			case LiteGlyph.Gun:
				var hub = c + new Vector2(0, 1.6f * s);
				b.Line(hub, c + new Vector2(-2.6f, -4.2f) * s, col, 1.3f * s);
				b.Line(hub, c + new Vector2(2.6f, -4.2f) * s, col, 1.3f * s);
				b.Disc(hub, 2.6f * s, col);
				break;
			case LiteGlyph.Ballistic:
				if (outline != null) b.Disc(c, 3.6f * s, outline.Value);
				b.Disc(c, 2.8f * s, col);
				break;
		}
	}

	public static void Poly(CanvasItem ci, Vector2[] src, Vector2 c, float s, float angle, Color fill, Color? outline = null)
	{
		var pts = new Vector2[src.Length];
		float cos = MathF.Cos(angle), sin = MathF.Sin(angle);
		for (int i = 0; i < src.Length; i++)
		{
			var v = src[i] * s;
			pts[i] = c + new Vector2(v.X * cos - v.Y * sin, v.X * sin + v.Y * cos);
		}
		if (outline != null)
		{
			var loop = new Vector2[pts.Length + 1];
			pts.CopyTo(loop, 0);
			loop[^1] = pts[0];
			ci.DrawPolyline(loop, outline.Value, 2.2f, true);
		}
		ci.DrawColoredPolygon(pts, fill);
	}

	public static StyleBoxFlat Box(Color bg, Color border, int radius, float pad = 0, int borderWidth = 1) => new()
	{
		BgColor = bg, BorderColor = border,
		BorderWidthLeft = borderWidth, BorderWidthRight = borderWidth, BorderWidthTop = borderWidth, BorderWidthBottom = borderWidth,
		CornerRadiusTopLeft = radius, CornerRadiusTopRight = radius, CornerRadiusBottomLeft = radius, CornerRadiusBottomRight = radius,
		ContentMarginLeft = pad, ContentMarginRight = pad, ContentMarginTop = pad, ContentMarginBottom = pad,
		AntiAliasing = true,
	};
}
