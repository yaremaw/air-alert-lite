using System;
using Godot;

/// A small rounded toggle: salvo size, speed, difficulty, switches.
public partial class LiteChip : Control
{
	public string Text = "";
	public bool Selected;
	public Color Accent = LiteGlyphs.Ours;
	public int FontSize = 12;
	public Action? Clicked;
	private float _hover, _sel;
	private bool _in;
	/// What was drawn last; the chip is redrawn only when this changes.
	private (int, int, string) _drawn;
	private readonly StyleBoxFlat _box = LiteGlyphs.Box(LiteGlyphs.Panel, LiteGlyphs.Line, 7);

	public override void _Ready()
	{
		if (CustomMinimumSize.Y == 0) CustomMinimumSize = new Vector2(CustomMinimumSize.X, 28);
		MouseFilter = MouseFilterEnum.Stop;
		MouseDefaultCursorShape = CursorShape.PointingHand;
		MouseEntered += () => _in = true;
		MouseExited += () => _in = false;
	}

	public override void _Process(double delta)
	{
		double tp = LitePerf.Now;
		ProcessBody(delta);
		LitePerf.UiProcMs += LitePerf.Now - tp;
	}

	private void ProcessBody(double delta)
	{
		float k = 1 - MathF.Exp(-(float)delta * 14f);
		_hover += ((_in ? 1 : 0) - _hover) * k;
		_sel += ((Selected ? 1 : 0) - _sel) * k;
		var now = ((int)(_hover * 64), (int)(_sel * 64), Text);
		if (now != _drawn) { _drawn = now; QueueRedraw(); }
	}

	public override void _GuiInput(InputEvent e)
	{
		if (e is InputEventMouseButton mb && mb.Pressed && mb.ButtonIndex == MouseButton.Left)
		{
			Clicked?.Invoke();
			AcceptEvent();
		}
	}

	public override void _Draw()
	{
		double t0 = LitePerf.Now;
		DrawBody();
		LitePerf.UiMs += LitePerf.Now - t0;
	}

	private void DrawBody()
	{
		_box.BgColor = LiteGlyphs.Panel.Lerp(LiteGlyphs.PanelHi, _hover).Lerp(Accent.Darkened(0.6f), _sel);
		_box.BorderColor = LiteGlyphs.Line.Lerp(Accent, _sel);
		DrawStyleBox(_box, new Rect2(Vector2.Zero, Size));
		var col = LiteGlyphs.Muted.Lerp(Colors.White, Math.Max(_sel, _hover * 0.6f));
		DrawString(LiteGlyphs.Bold, new Vector2(0, Size.Y / 2 + FontSize * 0.36f), Text, HorizontalAlignment.Center, Size.X, FontSize, col);
	}
}
