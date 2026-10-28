using System;
using Godot;

/// The production queue in the side panel: the weapon being built with its
/// progress, then the next ones as small icons. Clicking an icon takes that
/// weapon off the queue. Redrawn a few times a second.
public partial class LiteQueue : Control
{
	public LiteMain Main = null!;
	private float _redraw;
	private const float Slot = 18f, First = 74f;

	public override void _Ready()
	{
		CustomMinimumSize = new Vector2(0, 24);
		MouseFilter = MouseFilterEnum.Stop;
		TooltipText = "The production queue. Every factory works on the weapon at its head; click a waiting weapon to take it off.";
	}

	public override void _Process(double delta)
	{
		if ((_redraw -= (float)delta) > 0) return;
		_redraw = 0.1f;
		QueueRedraw();
	}

	public override void _GuiInput(InputEvent e)
	{
		if (e is not InputEventMouseButton { Pressed: true, ButtonIndex: MouseButton.Left } mb) return;
		var q = Main.Sim.Sides[0].Production.Queue;
		int i = mb.Position.X < First ? 0 : 1 + (int)((mb.Position.X - First) / Slot);
		if (i < q.Count)
		{
			if (i == 0) Main.Sim.Sides[0].Production.Progress = 0;
			q.RemoveAt(i);
			Main.Audio.Click();
		}
		AcceptEvent();
	}

	public override void _Draw()
	{
		var prod = Main.Sim.Sides[0].Production;
		var box = new Rect2(Vector2.Zero, Size);
		DrawRect(box, LiteGlyphs.PanelHi);
		if (prod.Idle)
		{
			DrawString(LiteGlyphs.Bold, new Vector2(0, 16), "Queue empty: production is lost", HorizontalAlignment.Center, Size.X, 11, LiteGlyphs.Yellow);
			return;
		}
		// The head of the queue: icon and a progress bar.
		var head = prod.Queue[0];
		DrawRect(new Rect2(0, 0, First - 4, Size.Y), LiteGlyphs.Ours.Darkened(0.6f));
		DrawRect(new Rect2(0, 0, (First - 4) * prod.Share, Size.Y), LiteGlyphs.Ours.Darkened(0.25f));
		LiteGlyphs.Draw(this, LiteGlyphs.Of(head), new Vector2(12, Size.Y / 2), 0.9f, Colors.White, -MathF.PI / 4);
		float left = (LiteRules.PP(head) - prod.Progress) / Math.Max(0.01f, prod.Rate);
		DrawString(LiteGlyphs.Bold, new Vector2(24, 16), $"{left:0}s", HorizontalAlignment.Left, -1, 11, LiteGlyphs.Text);
		// The rest, as icons.
		for (int i = 1; i < prod.Queue.Count; i++)
		{
			float x = First + (i - 1) * Slot + Slot / 2;
			if (x > Size.X - 8) { DrawString(LiteGlyphs.Font, new Vector2(x - 6, 16), "…", HorizontalAlignment.Left, -1, 11, LiteGlyphs.Muted); break; }
			LiteGlyphs.Draw(this, LiteGlyphs.Of(prod.Queue[i]), new Vector2(x, Size.Y / 2), 0.75f, LiteGlyphs.Muted, -MathF.PI / 4);
		}
	}
}
