using System;
using System.Collections.Generic;
using Godot;

/// Collects the map's moving pictures (lines, discs, rings, glyphs) as plain
/// triangles and hands them to the renderer in one command. Hundreds of
/// weapons with their tracks would otherwise be thousands of separate
/// antialiased draw calls a frame. Edges are softened by a thin feather of
/// vertices fading to nothing, in place of the renderer's antialiasing.
public sealed class LiteBatch
{
	private const float Feather = 0.9f;
	private const int MaxVerts = 60000;
	private Vector2[] _p = new Vector2[8192];
	private Color[] _c = new Color[8192];
	private int[] _i = new int[24576];
	private int _np, _ni;
	private readonly Vector2[] _unit = new Vector2[66];
	private Rid _item;

	public void Begin(CanvasItem ci)
	{
		_item = ci.GetCanvasItem();
		_np = _ni = 0;
	}

	/// Sends what has been collected; later Draw* calls of the item go above it.
	public void Flush()
	{
		if (_ni > 0)
			RenderingServer.CanvasItemAddTriangleArray(_item, _i[.._ni], _p[.._np], _c[.._np]);
		_np = _ni = 0;
	}

	private int Vert(Vector2 p, Color c) { _p[_np] = p; _c[_np] = c; return _np++; }

	private void Tri(int a, int b, int c) { _i[_ni++] = a; _i[_ni++] = b; _i[_ni++] = c; }

	private void Quad(int a, int b, int c, int d) { Tri(a, b, c); Tri(a, c, d); }

	/// Makes sure `verts` more vertices (and their triangles) fit, sending the batch first if it is full.
	private void Room(int verts)
	{
		if (_np + verts > MaxVerts) Flush();
		if (_np + verts > _p.Length)
		{
			int n = Math.Max(_p.Length * 2, _np + verts);
			Array.Resize(ref _p, n);
			Array.Resize(ref _c, n);
		}
		// A soft disc, the hungriest shape, takes under five indices a vertex.
		if (_ni + verts * 5 > _i.Length) Array.Resize(ref _i, Math.Max(_i.Length * 2, _ni + verts * 5));
	}

	public void Line(Vector2 a, Vector2 b, Color col, float width) => Line(a, b, col, col, width);

	public void Line(Vector2 a, Vector2 b, Color ca, Color cb, float width)
	{
		var d = b - a;
		float len = d.Length();
		if (len < 1e-4f) return;
		Room(8);
		var n = new Vector2(-d.Y, d.X) / len;
		if (width <= 1.6f)
		{
			// Thin: full colour along the middle fading to nothing at both edges.
			float e = width * 0.5f + Feather * 0.5f;
			int t = Vert(a + n * e, new Color(ca, 0));
			Vert(a, ca); Vert(a - n * e, new Color(ca, 0));
			Vert(b + n * e, new Color(cb, 0)); Vert(b, cb); Vert(b - n * e, new Color(cb, 0));
			Quad(t, t + 1, t + 4, t + 3);
			Quad(t + 1, t + 2, t + 5, t + 4);
			return;
		}
		float h = width * 0.5f - Feather * 0.5f, o = h + Feather;
		int k = Vert(a + n * o, new Color(ca, 0));
		Vert(a + n * h, ca); Vert(a - n * h, ca); Vert(a - n * o, new Color(ca, 0));
		Vert(b + n * o, new Color(cb, 0)); Vert(b + n * h, cb); Vert(b - n * h, cb); Vert(b - n * o, new Color(cb, 0));
		Quad(k, k + 1, k + 5, k + 4);
		Quad(k + 1, k + 2, k + 6, k + 5);
		Quad(k + 2, k + 3, k + 7, k + 6);
	}

	/// A dashed line along the points: `dash` drawn, `gap` left out.
	public void Dashed(List<Vector2> pts, Color col, float width, float dash, float gap)
	{
		float phase = 0, period = dash + gap;
		for (int i = 0; i + 1 < pts.Count; i++)
		{
			var a = pts[i];
			var d = pts[i + 1] - a;
			float len = d.Length();
			if (len < 0.01f) continue;
			var u = d / len;
			float at = 0;
			while (at < len - 1e-3f)
			{
				bool on = phase < dash;
				float step = Math.Max(0.01f, Math.Min((on ? dash : period) - phase, len - at));
				if (on) Line(a + u * at, a + u * (at + step), col, width);
				at += step;
				phase = (phase + step) % period;
			}
		}
	}

	private int Segments(float r) => Math.Clamp((int)(r * 0.9f) + 6, 6, 64);

	private void Unit(int n, float from, float span)
	{
		for (int s = 0; s <= n; s++)
		{
			float a = from + span * s / n;
			_unit[s] = new Vector2(MathF.Cos(a), MathF.Sin(a));
		}
	}

	public void Disc(Vector2 c, float r, Color col, bool soft = true)
	{
		int n = Segments(r);
		Room(n * 2 + 3);
		Unit(n, 0, MathF.Tau);
		float inner = soft ? Math.Max(0.1f, r - Feather * 0.5f) : r;
		int center = Vert(c, col);
		int first = _np;
		for (int s = 0; s < n; s++)
		{
			Vert(c + _unit[s] * inner, col);
			if (soft) Vert(c + _unit[s] * (inner + Feather), new Color(col, 0));
		}
		int step = soft ? 2 : 1;
		for (int s = 0; s < n; s++)
		{
			int a = first + s * step, b = first + (s + 1) % n * step;
			Tri(center, a, b);
			if (soft) Quad(a, a + 1, b + 1, b);
		}
	}

	public void Ring(Vector2 c, float r, Color col, float width, float from = 0, float to = MathF.Tau)
	{
		float span = to - from;
		int n = Math.Clamp((int)(Segments(r) * Math.Abs(span) / MathF.Tau) + 1, 3, 64);
		Room((n + 1) * 4);
		Unit(n, from, span);
		float h = Math.Max(0.05f, width * 0.5f - Feather * 0.5f), o = h + Feather;
		if (width < Feather) col.A *= width / Feather;
		var clear = new Color(col, 0);
		int first = _np;
		for (int s = 0; s <= n; s++)
		{
			var u = _unit[s];
			Vert(c + u * (r + o), clear); Vert(c + u * (r + h), col); Vert(c + u * (r - h), col); Vert(c + u * (r - o), clear);
		}
		for (int s = 0; s < n; s++)
		{
			int k = first + s * 4;
			Quad(k, k + 1, k + 5, k + 4);
			Quad(k + 1, k + 2, k + 6, k + 5);
			Quad(k + 2, k + 3, k + 7, k + 6);
		}
	}

	/// A speck too small to need roundness: a square of the same area as a disc of radius `r`.
	public void Dot(Vector2 c, float r, Color col)
	{
		float h = r * 0.89f;
		Rect(new Rect2(c.X - h, c.Y - h, h * 2, h * 2), col);
	}

	public void Rect(Rect2 r, Color col)
	{
		Room(4);
		int k = Vert(r.Position, col);
		Vert(new Vector2(r.End.X, r.Position.Y), col); Vert(r.End, col); Vert(new Vector2(r.Position.X, r.End.Y), col);
		Quad(k, k + 1, k + 2, k + 3);
	}

	/// A polygon already cut into triangles (`tris` index `pts`), placed at
	/// `c`, scaled by `s` and turned by `angle`; a soft rim of its own colour,
	/// or an outline in another.
	public void Shape(Vector2[] pts, int[] tris, Vector2 c, float s, float angle, Color fill, Color? outline = null)
	{
		Room(pts.Length * 9 + 8);
		float cos = MathF.Cos(angle), sin = MathF.Sin(angle);
		Vector2 At(int i) { var v = pts[i] * s; return c + new Vector2(v.X * cos - v.Y * sin, v.X * sin + v.Y * cos); }
		var rim = outline ?? new Color(fill, fill.A * 0.6f);
		float rimWidth = outline != null ? 2.2f : 0.9f;
		for (int i = 0; i < pts.Length; i++) Line(At(i), At((i + 1) % pts.Length), rim, rimWidth);
		int first = _np;
		for (int i = 0; i < pts.Length; i++) Vert(At(i), fill);
		foreach (int t in tris) _i[_ni++] = first + t;
	}
}
