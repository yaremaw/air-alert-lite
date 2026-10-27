using System;
using Godot;

/// A card in the side panel: icon, name and price. Hover and selection ease
/// in rather than snap; a card you cannot afford dims and shows its price red.
public partial class LiteToolButton : Control
{
	public LiteGlyph Glyph;
	public string Title = "", Price = "", Key = "";
	public bool Selected, Affordable = true;
	public Color Accent = LiteGlyphs.Ours;
	public Action? Clicked;
	private float _hover, _sel, _press;
	private bool _in;
	/// What was drawn last; the card is redrawn only when this changes.
	private (int, int, int, bool, string) _drawn;
	private readonly StyleBoxFlat _box = LiteGlyphs.Box(LiteGlyphs.Panel, LiteGlyphs.Line, 9);

	public override void _Ready()
	{
		CustomMinimumSize = new Vector2(0, 72);
		SizeFlagsHorizontal = SizeFlags.ExpandFill;
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
		_press = Math.Max(0, _press - (float)delta * 5f);
		var now = ((int)(_hover * 64), (int)(_sel * 64), (int)(_press * 64), Affordable, Price);
		if (now != _drawn) { _drawn = now; QueueRedraw(); }
	}

	public override void _GuiInput(InputEvent e)
	{
		if (e is InputEventMouseButton mb && mb.Pressed && mb.ButtonIndex == MouseButton.Left)
		{
			_press = 1;
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
		float dim = Affordable ? 1f : 0.45f;
		_box.BgColor = LiteGlyphs.Panel.Lerp(LiteGlyphs.PanelHi, _hover).Lerp(Accent.Darkened(0.68f), _sel * 0.9f);
		_box.BorderColor = LiteGlyphs.Line.Lerp(Accent, Math.Max(_sel, _press * 0.6f));
		float inset = _press * 1.5f;
		DrawStyleBox(_box, new Rect2(new Vector2(inset, inset), Size - new Vector2(inset, inset) * 2));
		float lift = -2f * _hover;
		var icon = new Color(1, 1, 1, dim).Lerp(Accent.Lightened(0.35f), _sel * 0.6f);
		float angle = Glyph is LiteGlyph.Drone or LiteGlyph.Cruise ? -MathF.PI / 4 : 0;
		LiteGlyphs.Draw(this, Glyph, new Vector2(Size.X / 2, 24 + lift), 1.55f, icon, angle);
		DrawString(LiteGlyphs.Bold, new Vector2(0, 50), Title, HorizontalAlignment.Center, Size.X, 12, new Color(LiteGlyphs.Text, dim));
		DrawString(LiteGlyphs.Font, new Vector2(0, 64), Price, HorizontalAlignment.Center, Size.X, 11, Affordable ? LiteGlyphs.Muted : LiteGlyphs.Enemy);
		if (Key != "") DrawString(LiteGlyphs.Font, new Vector2(8, 15), Key, HorizontalAlignment.Left, -1, 10, LiteGlyphs.Faint);
	}
}
