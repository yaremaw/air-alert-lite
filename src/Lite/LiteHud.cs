using System;
using Godot;

/// Everything drawn over the map that is not the map: the alert card at the
/// top (like the notice on map.ukrainealarm.com), the logo and clock badge
/// bottom-left, the hint for the tool in hand, a short message after a
/// refused order, and the tooltip for whatever is under the mouse.
public partial class LiteHud : Control
{
	public LiteMain Main = null!;
	private string _msg = "";
	private float _msgAge = 99f, _pulse, _state = -1, _redraw;
	private Vector2 _mouse;
	private object? _hover;
	private int _tool = -1;
	private readonly StyleBoxFlat _card = LiteGlyphs.Box(new Color(LiteGlyphs.Panel, 0.96f), LiteGlyphs.Line, 10);
	private readonly StyleBoxFlat _tip = LiteGlyphs.Box(new Color(LiteGlyphs.Panel, 0.97f), LiteGlyphs.Line, 7);

	public override void _Ready()
	{
		MouseFilter = MouseFilterEnum.Ignore;
		SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);
	}

	public void Message(string text)
	{
		_msg = text;
		_msgAge = 0;
	}

	public override void _Process(double delta)
	{
		double tp = LitePerf.Now;
		ProcessBody(delta);
		LitePerf.UiProcMs += LitePerf.Now - tp;
	}

	private void ProcessBody(double delta)
	{
		_msgAge += (float)delta;
		_pulse = Math.Max(0, _pulse - (float)delta * 1.6f);
		// Redrawn while the message fades, the card pulses or the tooltip
		// follows the mouse; otherwise four times a second for the clock.
		object? hover = Main.HoverBuilding != null ? Main.HoverBuilding : Main.HoverRegion;
		int tool = Main.BuildTool is LiteKind k ? (int)k : Main.StrikeTool is LiteArm a ? 10 + (int)a : -1;
		bool moving = _msgAge < 2.4f || _pulse > 0 || (Main.Mouse != _mouse && hover != null) || !Equals(hover, _hover) || tool != _tool;
		_redraw -= (float)delta;
		if (!moving && _redraw > 0) return;
		_redraw = 0.25f;
		_mouse = Main.Mouse;
		_hover = hover;
		_tool = tool;
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
		if (!Main.Started) return;
		DrawAlertCard();
		DrawBadge();
		DrawHint();
		DrawTooltip();
	}

	private void DrawAlertCard()
	{
		var sim = Main.Sim;
		int regions = sim.Alerted[0], threats = 0;
		bool ballistic = false;
		foreach (var wp in sim.Weapons)
			if (wp.Alive && wp.Side == 1 && wp.Seen[0]) { threats++; if (wp.Arm == LiteArm.Ballistic) ballistic = true; }
		float state = regions == 0 ? 0 : ballistic ? 2 : 1;
		if (state != _state) { if (_state >= 0 && state > 0) _pulse = 1; _state = state; }
		Color tone = state == 2 ? LiteGlyphs.BallisticAlert : state == 1 ? LiteGlyphs.Yellow : LiteGlyphs.Muted;
		string title = state == 2 ? "Ballistic threat!" : state == 1 ? $"Air alert · {regions} region{(regions == 1 ? "" : "s")}" : "No air alert";
		string sub = state > 0
			? $"Since {Main.ClockText(sim.SideAlertSince[0], false)} · {threats} in the air"
			: sim.SideQuietSince[0] > 0 ? $"All clear since {Main.ClockText(sim.SideQuietSince[0], false)}" : "The sky is quiet";
		// Between alerts, intelligence's warning stays on the card until the strike comes.
		if (state == 0 && Main.Sim.Ai[1] is { Massing: true })
		{
			title = "Large strike expected";
			sub = "Intelligence: the enemy is massing drones and missiles";
			tone = LiteGlyphs.BallisticAlert;
			state = 1;
		}
		var font = LiteGlyphs.Bold;
		float w = Math.Max(font.GetStringSize(title, HorizontalAlignment.Left, -1, 15).X, LiteGlyphs.Font.GetStringSize(sub, HorizontalAlignment.Left, -1, 12).X) + 74;
		float cx = LiteMap.W / 2f;
		float grow = _pulse * _pulse * 6f;
		var rect = new Rect2(cx - w / 2 - grow, 14 - grow * 0.5f, w + grow * 2, 54 + grow);
		_card.BorderColor = LiteGlyphs.Line.Lerp(tone, state > 0 ? 0.55f : 0f);
		DrawStyleBox(_card, rect);
		// A clock face, as on the real notice.
		var c = new Vector2(rect.Position.X + 30, rect.Position.Y + rect.Size.Y / 2);
		DrawArc(c, 10, 0, MathF.Tau, 32, tone, 1.8f, true);
		DrawLine(c, c + new Vector2(0, -6), tone, 1.8f, true);
		DrawLine(c, c + new Vector2(4.5f, 2.5f), tone, 1.8f, true);
		DrawString(font, new Vector2(rect.Position.X + 52, rect.Position.Y + 24), title, HorizontalAlignment.Left, -1, 15, state > 0 ? tone : LiteGlyphs.Text);
		DrawString(LiteGlyphs.Font, new Vector2(rect.Position.X + 52, rect.Position.Y + 42), sub, HorizontalAlignment.Left, -1, 12, LiteGlyphs.Muted);
	}

	private void DrawBadge()
	{
		var at = new Vector2(22, Size.Y - 58);
		var logo = new Rect2(at, new Vector2(36, 36));
		var box = LiteGlyphs.Box(LiteGlyphs.Ours, LiteGlyphs.Ours, 8);
		DrawStyleBox(box, logo);
		var c = logo.GetCenter();
		DrawArc(c, 10, 0, MathF.Tau, 32, Colors.White, 1.6f, true);
		DrawArc(c, 5, 0, MathF.Tau, 24, new Color(1, 1, 1, 0.7f), 1.2f, true);
		DrawLine(c, c + new Vector2(8, -6), Colors.White, 1.6f, true);
		DrawCircle(c, 1.6f, Colors.White, true, -1, true);
		DrawString(LiteGlyphs.Font, new Vector2(at.X + 46, at.Y + 14), "strike alert · lite", HorizontalAlignment.Left, -1, 12, LiteGlyphs.Muted);
		DrawString(LiteGlyphs.Bold, new Vector2(at.X + 46, at.Y + 32), Main.ClockText(Main.Sim.Time, true), HorizontalAlignment.Left, -1, 13, LiteGlyphs.Text);
		if (Main.Paused && Main.Sim.Winner < 0)
			DrawString(LiteGlyphs.Bold, new Vector2(at.X + 46, at.Y - 8), "PAUSED · Space to resume", HorizontalAlignment.Left, -1, 11, LiteGlyphs.Yellow);
	}

	private void DrawHint()
	{
		string hint = "";
		if (Main.BuildTool == LiteKind.Factory) hint = $"Click a region with a free place (green) to build a factory there (${Main.Sim.Cost(0, LiteKind.Factory)}) · Right-click cancels";
		else if (Main.BuildTool is LiteKind k) hint = $"Click your territory to build: {LiteGlyphs.Name(k)} (${Main.Sim.Cost(0, k)}) · Shift keeps the tool · Right-click cancels";
		else if (Main.StrikeTool is LiteArm a) hint = $"Click enemy territory to launch {LiteGlyphs.Plural(a, 2)} straight, or drag a route from your land to the target · Right-click cancels";
		float y = Size.Y - 34;
		if (_msgAge < 2.2f)
		{
			float a = Math.Clamp((2.2f - _msgAge) / 0.4f, 0, 1);
			Pill(_msg, y - 34, new Color(LiteGlyphs.Enemy, a), a);
		}
		if (hint != "") Pill(hint, y, LiteGlyphs.Muted, 1);
	}

	private void Pill(string text, float y, Color col, float alpha)
	{
		var font = LiteGlyphs.Font;
		float w = font.GetStringSize(text, HorizontalAlignment.Left, -1, 12).X + 28;
		var r = new Rect2(LiteMap.W / 2f - w / 2 + 40, y - 13, w, 26);
		_tip.BgColor = new Color(LiteGlyphs.Panel, 0.94f * alpha);
		_tip.BorderColor = new Color(LiteGlyphs.Line, alpha);
		DrawStyleBox(_tip, r);
		DrawString(font, new Vector2(r.Position.X + 14, y + 4.5f), text, HorizontalAlignment.Left, -1, 12, col);
	}

	private void DrawTooltip()
	{
		if ((Main.BuildTool != null && Main.BuildTool != LiteKind.Factory) || Main.StrikeTool != null) return;
		var sim = Main.Sim;
		string head = "", body = "";
		if (Main.HoverBuilding is LiteBuilding b)
		{
			head = (b.Side == 0 ? "" : "Enemy ") + LiteGlyphs.Name(b.Kind);
			body = b.Kind switch
			{
				LiteKind.Capital => $"Health {Math.Max(0, b.Hp):0}/{b.MaxHp:0} · own AA guns · repaired by its factories",
				LiteKind.Factory => $"Health {b.Hp:0}/{b.MaxHp:0} · +${LiteRules.FactoryIncome:0}/s, repairs the capital{(sim.Alert[b.Region] ? " (sheltering)" : "")}",
				LiteKind.Sam => b.Side == 0 ? $"Missiles {b.Ammo}/{LiteRules.SamRack} · health {b.Hp:0}/{b.MaxHp:0}" : $"Health {b.Hp:0}/{b.MaxHp:0}",
				_ => $"Health {b.Hp:0}/{b.MaxHp:0}",
			};
			if (!b.Ready) body = $"Building… {b.Build:0}s";
		}
		else if (Main.HoverRegion >= 0)
		{
			var r = Main.Map.Regions[Main.HoverRegion];
			head = r.Name + (r.City ? "" : r.Side == 0 ? " region" : "");
			if (r.Side == 0 && !r.City)
				head += $" · factories {sim.FactoriesIn(r.Id)}/{sim.Slots[r.Id]}{(sim.RuinsIn(r.Id) > 0 ? $", {sim.RuinsIn(r.Id)} in ruins" : "")}";
			body = sim.Alert[r.Id]
				? $"{(sim.Ballistic[r.Id] ? "Ballistic threat" : "Air alert")} · {Duration(sim.Time - sim.AlertSince[r.Id])}"
				: r.Side == 0 ? "No alert" : "Enemy territory";
		}
		if (head == "") return;
		var font = LiteGlyphs.Font;
		float w = Math.Max(LiteGlyphs.Bold.GetStringSize(head, HorizontalAlignment.Left, -1, 12).X, font.GetStringSize(body, HorizontalAlignment.Left, -1, 11).X) + 20;
		var p = Main.Mouse + new Vector2(16, 14);
		if (p.X + w > LiteMap.W) p.X -= w + 28;
		var rect = new Rect2(p, new Vector2(w, 42));
		_tip.BgColor = new Color(LiteGlyphs.Panel, 0.97f);
		_tip.BorderColor = LiteGlyphs.Line;
		DrawStyleBox(_tip, rect);
		DrawString(LiteGlyphs.Bold, p + new Vector2(10, 17), head, HorizontalAlignment.Left, -1, 12, LiteGlyphs.Text);
		DrawString(font, p + new Vector2(10, 33), body, HorizontalAlignment.Left, -1, 11, LiteGlyphs.Muted);
	}

	public static string Duration(float seconds)
	{
		// One second of play is one minute on the clock.
		int m = (int)seconds;
		return m >= 60 ? $"{m / 60} h {m % 60:00} min" : $"{m} min";
	}
}
