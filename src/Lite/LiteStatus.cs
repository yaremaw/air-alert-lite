using System;
using Godot;

/// The top of the side panel: budget with income, both capitals' health,
/// and what is known about the war so far. The budget rolls to its value.
public partial class LiteStatus : Control
{
	public LiteMain Main = null!;
	private float _money = -1, _redraw;

	public override void _Ready() => CustomMinimumSize = new Vector2(0, 150);

	public override void _Process(double delta)
	{
		double tp = LitePerf.Now;
		ProcessBody(delta);
		LitePerf.UiProcMs += LitePerf.Now - tp;
	}

	private void ProcessBody(double delta)
	{
		var me = Main.Sim.Sides[0];
		if (_money < 0) _money = me.Money;
		_money += (me.Money - _money) * (1 - MathF.Exp(-(float)delta * 10f));
		// Numbers do not need every frame.
		if ((_redraw -= (float)delta) > 0) return;
		_redraw = 1 / 15f;
		QueueRedraw();
	}

	public override void _Draw()
	{
		double t0 = LitePerf.Now;
		DrawBody();
		LitePerf.UiMs += LitePerf.Now - t0;
	}

	private void DrawBody()
	{
		var sim = Main.Sim;
		var me = sim.Sides[0];
		var font = LiteGlyphs.Font;
		var bold = LiteGlyphs.Bold;
		float w = Size.X;
		DrawString(font, new Vector2(0, 12), "BUDGET", HorizontalAlignment.Left, -1, 10, LiteGlyphs.Muted);
		DrawString(bold, new Vector2(0, 42), $"${Math.Floor(_money):0}", HorizontalAlignment.Left, -1, 28, LiteGlyphs.Text);
		var inc = $"+{me.Income:0.0}/s";
		DrawString(bold, new Vector2(0, 40), inc, HorizontalAlignment.Right, w, 12, LiteGlyphs.Good);
		int alertFactories = 0;
		foreach (var b in sim.Buildings)
			if (b.Alive && b.Side == 0 && b.Kind == LiteKind.Factory && b.Ready && sim.Alert[b.Region]) alertFactories++;
		if (alertFactories > 0)
			DrawString(font, new Vector2(0, 24), $"{alertFactories} factor{(alertFactories == 1 ? "y" : "ies")} sheltering", HorizontalAlignment.Right, w, 10, LiteGlyphs.Yellow);

		Bar(62, Main.Map.CapitalName[0], sim.Sides[0], LiteGlyphs.Ours, w);
		Bar(94, Main.Map.CapitalName[1], sim.Sides[1], LiteGlyphs.Enemy, w);

		int f = 0, ad = 0, ef = 0, ead = 0;
		foreach (var b in sim.Buildings)
		{
			if (!b.Alive) continue;
			if (b.Side == 0) { if (b.Kind == LiteKind.Factory) f++; else if (b.IsAd) ad++; }
			else if (b.Seen[0]) { if (b.Kind == LiteKind.Factory) ef++; else if (b.IsAd) ead++; }
		}
		DrawString(font, new Vector2(0, 136), $"Ours  {f} factories · {ad} AD", HorizontalAlignment.Left, -1, 11, LiteGlyphs.Muted);
		DrawString(font, new Vector2(0, 136), $"Seen  {ef} · {ead}", HorizontalAlignment.Right, w, 11, LiteGlyphs.Muted);
		DrawString(font, new Vector2(0, 150), $"Shot down {me.Downed} · hits on enemy {me.Hits}", HorizontalAlignment.Left, -1, 11, LiteGlyphs.Faint);
	}

	/// A capital's health, and how fast its factories are repairing it.
	private void Bar(float y, string name, LiteSide side, Color col, float w)
	{
		var cap = side.Capital;
		float hp = Math.Max(0, cap.Hp);
		DrawString(LiteGlyphs.Bold, new Vector2(0, y + 10), name, HorizontalAlignment.Left, -1, 12, LiteGlyphs.Text);
		string repair = side.Repair > 0 ? $"repairing +{side.Repair * 60:0.#}/min   " : "";
		DrawString(LiteGlyphs.Font, new Vector2(0, y + 10), $"{repair}{hp:0}/{cap.MaxHp:0}", HorizontalAlignment.Right, w, 11, LiteGlyphs.Muted);
		var r = new Rect2(0, y + 16, w, 5);
		DrawRect(r, LiteGlyphs.PanelHi);
		DrawRect(new Rect2(r.Position, new Vector2(w * hp / cap.MaxHp, 5)), col.Lerp(LiteGlyphs.HitGlow, cap.Flash));
	}
}
