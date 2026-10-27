using Godot;

/// The region names. They never change, so they are drawn once and kept,
/// under everything the map draws each frame.
public partial class LiteLabels : Node2D
{
	public LiteMap Map = null!;

	public override void _Draw()
	{
		foreach (var r in Map.Regions)
			if (!r.City) Draw(this, r.Label, r.Name, 11, new Color(1, 1, 1, 0.92f));
	}

	public static void Draw(CanvasItem ci, Vector2 at, string text, int size, Color col)
	{
		var font = LiteGlyphs.Bold;
		var pos = new Vector2(at.X - 100, at.Y + size * 0.36f);
		ci.DrawStringOutline(font, pos, text, HorizontalAlignment.Center, 200, size, 4, new Color(0, 0, 0, 0.28f));
		ci.DrawString(font, pos, text, HorizontalAlignment.Center, 200, size, col);
	}
}
