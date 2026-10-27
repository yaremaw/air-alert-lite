using Godot;

/// The lite game's few settings, kept in user://lite_settings.cfg.
public static class LiteSettings
{
	private const string Path = "user://lite_settings.cfg";
	private static readonly float[] VolumeDb = { -80f, -16f, -8f, 0f };

	/// 0 off, 1 low, 2 medium, 3 high.
	public static int Volume = 2;
	public static int Difficulty = 1;
	public static bool Fullscreen, Routes = true, Ranges = true;

	public static void Load()
	{
		var c = new ConfigFile();
		if (c.Load(Path) != Error.Ok) return;
		Volume = Mathf.Clamp(c.GetValue("lite", "volume", Volume).AsInt32(), 0, 3);
		Difficulty = Mathf.Clamp(c.GetValue("lite", "difficulty", Difficulty).AsInt32(), 0, 2);
		Fullscreen = c.GetValue("lite", "fullscreen", Fullscreen).AsBool();
		Routes = c.GetValue("lite", "routes", Routes).AsBool();
		Ranges = c.GetValue("lite", "ranges", Ranges).AsBool();
	}

	public static void Save()
	{
		var c = new ConfigFile();
		c.SetValue("lite", "volume", Volume);
		c.SetValue("lite", "difficulty", Difficulty);
		c.SetValue("lite", "fullscreen", Fullscreen);
		c.SetValue("lite", "routes", Routes);
		c.SetValue("lite", "ranges", Ranges);
		c.Save(Path);
	}

	public static void ApplySound()
	{
		AudioServer.SetBusMute(0, Volume == 0);
		AudioServer.SetBusVolumeDb(0, VolumeDb[Volume]);
	}

	public static void ApplyWindow() =>
		DisplayServer.WindowSetMode(Fullscreen ? DisplayServer.WindowMode.Fullscreen : DisplayServer.WindowMode.Windowed);
}
