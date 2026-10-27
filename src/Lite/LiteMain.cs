using System;
using System.Globalization;
using System.Linq;
using Godot;

/// Root of the lite game (scenes/LiteMain.tscn): makes the map and the war,
/// runs the clock, turns the player's clicks into orders and the war's
/// events into feed cards and sounds.
///
/// Command line (after `--`):
///   --lite-seed=N        a fixed map
///   --lite-sim=SECONDS   headless balance run, both sides played by the AI
///   --lite-seeds=N       how many maps the balance run plays
///   --lite-shot=DIR      screenshots of a short AI-played game, then quit
///   --lite-maps=N        with --lite-shot, first a picture of N maps
public partial class LiteMain : Node2D
{
	public LiteMap Map = null!;
	public LiteSim Sim = null!;
	public LiteUi Ui = null!;
	public LiteAudio Audio = null!;
	public LiteKind? BuildTool;
	public LiteArm? StrikeTool;
	public int Salvo = 1, Seed;
	public float Speed = 1;
	public bool Paused = true, Started;
	public Vector2 Mouse, StrikeTarget;
	public LiteBuilding? StrikeSnap, HoverBuilding;
	public int HoverRegion = -1;
	/// The route being drawn with a strike tool: the mouse held down and dragged.
	public System.Collections.Generic.List<Vector2>? Drawing;

	private LiteView? _view;
	private float _endTimer = -1, _lastCapitalPost = -99;
	private bool _autoplay;
	private Vector2? _fakeMouse;

	// Difficulty: Easy, Normal, Hard. Its bigger country is harder to defend,
	// so from Normal up the enemy gets a little more income to make up for it.
	private static readonly float[] EnemyIncome = { 0.8f, 1.1f, 1.3f };
	private static readonly float[] EnemyWarShare = { 0.4f, 0.5f, 0.55f };
	private static readonly float[] EnemyTempo = { 1.3f, 1f, 0.85f };

	public override void _Ready()
	{
		LiteGlyphs.LoadFonts();
		RenderingServer.SetDefaultClearColor(LiteGlyphs.Page);
		int seed = (int)(Time.GetUnixTimeFromSystem() % 1000003);
		string? shots = null;
		int simSeconds = 0, simSeeds = 1, maps = 0;
		foreach (var a in OS.GetCmdlineUserArgs())
		{
			if (a.StartsWith("--lite-seed=") && int.TryParse(a.Substring(12), out var s)) seed = s;
			if (a.StartsWith("--lite-sim=") && int.TryParse(a.Substring(11), out var t)) simSeconds = t;
			if (a.StartsWith("--lite-seeds=") && int.TryParse(a.Substring(13), out var n)) simSeeds = n;
			if (a.StartsWith("--lite-shot=")) shots = a.Substring(12).Trim('"');
			if (a.StartsWith("--lite-maps=") && int.TryParse(a.Substring(12), out var m)) maps = m;
		}
		if (simSeconds > 0) { RunBalance(seed, simSeconds, simSeeds); return; }

		LiteSettings.Load();
		LiteSettings.ApplySound();
		if (LiteSettings.Fullscreen && shots == null) LiteSettings.ApplyWindow();
		Audio = new LiteAudio();
		AddChild(Audio);
		NewWorld(seed);
		Ui = new LiteUi { Main = this };
		AddChild(Ui);
		Ui.Build();
		Ui.ShowMenu();
		if (shots != null) RunShots(shots, maps);
	}

	private void NewWorld(int seed)
	{
		Seed = seed;
		ulong t0 = Time.GetTicksMsec();
		Map = LiteMap.Generate(seed);
		Sim = new LiteSim(Map, seed);
		GD.Print($"[lite] map {seed}: {Map.Regions.Count} regions in {Time.GetTicksMsec() - t0} ms");
		_view?.QueueFree();
		_view = new LiteView { Main = this };
		AddChild(_view);
		MoveChild(_view, 0);
		_view.Build();
	}

	/// A new war: on the map shown behind the menu if it is still unplayed,
	/// otherwise on a new one.
	public void NewGame()
	{
		if (Started) NewWorld((int)((Seed * 7919L + 104729) % 1000003));
		int d = LiteSettings.Difficulty;
		Started = true;
		Paused = false;
		BuildTool = null;
		StrikeTool = null;
		_endTimer = -1;
		Sim.IncomeScale[1] = EnemyIncome[d];
		Sim.Ai[1] = new LiteAi(1, Seed + 1, 22f) { WarShare = EnemyWarShare[d], Tempo = EnemyTempo[d], Smart = d > 0, Waves = d > 0, Adaptive = d > 1 };
		if (_autoplay) Sim.Ai[0] = new LiteAi(0, Seed + 2, 30f);
		Ui.CloseMenu();
		Ui.ClearFeed();
		Ui.Post($"War. The enemy capital is {Map.CapitalName[1]}; its factories repair it. Its other sites are hidden: drones will find them.", LiteGlyphs.Muted);
		Audio.Click();
	}

	public void SetSpeed(float s)
	{
		if (!Started || Sim.Winner >= 0) return;
		if (s <= 0) { Paused = true; return; }
		Paused = false;
		Speed = s;
	}

	public void SelectBuild(LiteKind k)
	{
		BuildTool = BuildTool == k ? null : k;
		StrikeTool = null;
		Audio.Click();
	}

	public void SelectStrike(LiteArm a)
	{
		StrikeTool = StrikeTool == a ? null : a;
		BuildTool = null;
		Audio.Click();
	}

	/// One second of play is one minute on the clock; the war starts at 21:00.
	public string ClockText(float t, bool date)
	{
		var at = new DateTime(2026, 10, 26, 21, 0, 0).AddMinutes(t);
		return at.ToString(date ? "d MMMM HH:mm" : "HH:mm", CultureInfo.InvariantCulture);
	}

	// ---------------------------------------------------------------- frame

	public override void _Process(double delta)
	{
		Mouse = _fakeMouse ?? GetGlobalMousePosition();
		UpdateHover();
		if (Drawing != null)
		{
			if (StrikeTool == null || Ui.MenuOpen) Drawing = null;
			else if (Input.IsMouseButtonPressed(MouseButton.Left))
			{
				if (Drawing[^1].DistanceTo(Mouse) >= 16) Drawing.Add(Mouse);
			}
			else FinishRoute();
		}
		if (Started && !Paused && !Ui.MenuOpen)
		{
			double t0 = LitePerf.Now;
			float dt = (float)delta * Speed;
			while (dt > 1e-4f)
			{
				float h = Math.Min(dt, 1 / 30f);
				Sim.Step(h);
				dt -= h;
			}
			LitePerf.SimMs += LitePerf.Now - t0;
		}
		HandleEvents();
		if (_endTimer > 0 && (_endTimer -= (float)delta) <= 0) ShowEnd();
	}

	private void UpdateHover()
	{
		HoverBuilding = null;
		HoverRegion = -1;
		StrikeSnap = null;
		StrikeTarget = Mouse;
		if (!Started || Ui.MenuOpen || (_fakeMouse == null && GetViewport().GuiGetHoveredControl() != null)) return;
		float best = 11;
		foreach (var b in Sim.Buildings)
		{
			if (!b.Alive || !(b.Side == 0 || b.Seen[0])) continue;
			float d = b.Pos.DistanceTo(Mouse);
			if (d < best) { best = d; HoverBuilding = b; }
		}
		byte id = Map.RegionAt(Mouse);
		HoverRegion = id == LiteMap.None ? -1 : id;
		if (StrikeTool != null && HoverBuilding is LiteBuilding t && t.Side == 1)
		{
			StrikeSnap = t;
			StrikeTarget = t.Pos;
		}
	}

	public override void _UnhandledInput(InputEvent e)
	{
		// Esc steps back: out of a screen, then drops the tool in hand, then opens the menu.
		if (e is InputEventKey esc && esc.Pressed && !esc.Echo && esc.Keycode == Key.Escape)
		{
			if (Ui.MenuOpen) Ui.Back();
			else if (BuildTool != null || StrikeTool != null) { BuildTool = null; StrikeTool = null; }
			else if (Started && Sim.Winner < 0) Ui.ShowMenu();
			GetViewport().SetInputAsHandled();
			return;
		}
		if (!Started || Sim.Winner >= 0 || Ui.MenuOpen) return;
		if (e is InputEventKey k && k.Pressed && !k.Echo)
		{
			switch (k.Keycode)
			{
				case Key.Space: if (Paused) SetSpeed(Speed); else Paused = true; break;
				case Key.Key1: SelectBuild(LiteKind.Factory); break;
				case Key.Key2: SelectBuild(LiteKind.Gun); break;
				case Key.Key3: SelectBuild(LiteKind.Sam); break;
				case Key.Q: SelectStrike(LiteArm.Drone); break;
				case Key.W: SelectStrike(LiteArm.Cruise); break;
				case Key.E: SelectStrike(LiteArm.Ballistic); break;
				default: return;
			}
			GetViewport().SetInputAsHandled();
		}
		else if (e is InputEventMouseButton mb && mb.Pressed)
		{
			if (mb.ButtonIndex == MouseButton.Right) { BuildTool = null; StrikeTool = null; Drawing = null; }
			else if (mb.ButtonIndex == MouseButton.Left)
			{
				if (BuildTool != null) TryBuild(mb.ShiftPressed);
				// Press starts a route; letting go launches (see _Process).
				else if (StrikeTool != null) Drawing = new() { GetGlobalMousePosition() };
				else return;
			}
			else return;
			GetViewport().SetInputAsHandled();
		}
	}

	private void TryBuild(bool keep)
	{
		var k = BuildTool!.Value;
		if (Sim.Sides[0].Money < Sim.Cost(0, k)) { Refuse($"Not enough money: {LiteGlyphs.Name(k)} costs ${Sim.Cost(0, k)}"); return; }
		if (k == LiteKind.Factory)
		{
			int r = HoverRegion >= 0 && Map.Regions[HoverRegion].City ? Map.Regions[HoverRegion].Parent : HoverRegion;
			if (r < 0 || Map.Regions[r].Side != 0) { Refuse("Pick one of your regions"); return; }
			if (Sim.FreeSlots(r) <= 0) { Refuse($"No room for a factory in {Map.Regions[r].Name}"); return; }
			if (Sim.BuildFactory(0, r) == null) { Refuse($"No free ground in {Map.Regions[r].Name}"); return; }
			Audio.Play("click.wav", -3f);
			if (!keep) BuildTool = null;
			return;
		}
		if (!Sim.CanPlace(0, Mouse)) { Refuse("Build on your own territory, a little away from other sites"); return; }
		Sim.Build(0, k, Mouse);
		Audio.Play("click.wav", -3f);
		if (!keep) BuildTool = null;
	}

	/// A click launches straight at the target; a drag is the route there,
	/// starting from our launch site nearest where the drag began.
	private void FinishRoute()
	{
		var pts = Drawing!;
		Drawing = null;
		float length = 0;
		for (int i = 1; i < pts.Count; i++) length += pts[i - 1].DistanceTo(pts[i]);
		if (length < 20) { TryStrike(null); return; }
		pts.RemoveAll(q => q.DistanceTo(StrikeTarget) < 14);
		TryStrike(pts.Count > 0 ? pts : null);
	}

	private void TryStrike(System.Collections.Generic.List<Vector2>? route)
	{
		var a = StrikeTool!.Value;
		if (Map.SideAt(StrikeTarget) != 1) { Refuse("Pick a target on enemy territory"); return; }
		int n = Salvo;
		if (Sim.Sides[0].Money < LiteRules.Cost(a))  { Refuse($"Not enough money: a {LiteGlyphs.Name(a).ToLowerInvariant()} costs ${LiteRules.Cost(a)}"); return; }
		while (n > 1 && Sim.Sides[0].Money < LiteRules.Cost(a) * n) n--;
		Sim.Strike(0, a, StrikeTarget, n, null, 0f, route);
		Audio.Play("click.wav", -3f);
	}

	private void Refuse(string why)
	{
		Ui.Hud.Message(why);
		Audio.Play("click_off.wav", -4f);
	}

	// ---------------------------------------------------------------- events

	private string RegionName(int id) => id >= 0 && id < Map.Regions.Count ? Map.Regions[id].Name : "the sea";

	private static string Composition(LiteRaid r)
	{
		var parts = new System.Collections.Generic.List<string>();
		for (int i = 0; i < 3; i++)
			if (r.ByArm[i] > 0) parts.Add($"{r.ByArm[i]} {LiteGlyphs.Plural((LiteArm)i, r.ByArm[i])}");
		return string.Join(", ", parts);
	}

	private void HandleEvents()
	{
		if (Sim == null) return;
		foreach (var e in Sim.Events)
		{
			switch (e.Type)
			{
				case LiteEv.RaidAlert:
					if (e.Side != 0) break;
					Ui.Post($"Air alert in {RegionName(e.Region)}. Take cover.", LiteGlyphs.Yellow);
					Audio.Play("alert.wav", -7f, 2);
					break;
				case LiteEv.AllClear:
					if (e.Side == 0) Ui.Post($"All clear. The alert lasted {LiteHud.Duration(e.Value)}.", LiteGlyphs.Good);
					break;
				case LiteEv.Launch:
					if (e.Side == 0) { Audio.Play("launch.wav", -15f, 0.15); break; }
					if (e.Arm == LiteArm.Ballistic)
					{
						Ui.Post($"Ballistic launch! Heading for {RegionName(e.Region)}.", LiteGlyphs.BallisticAlert);
						Audio.Play("ballistic_warning.wav", -5f, 2);
					}
					break;
				case LiteEv.Detected:
					if (e.Side != 1 || e.Raid == null || e.Raid.Reported) break;
					e.Raid.Reported = true;
					Ui.Post($"Enemy {LiteGlyphs.Plural(e.Arm, 2)} spotted over {RegionName(e.Region)}.", LiteGlyphs.Yellow);
					break;
				case LiteEv.ShotDown:
					Audio.Play("intercept.wav", e.Side == 0 ? -11f : -18f, 0.08);
					break;
				case LiteEv.Hit:
					bool onUs = e.Side == 1;
					Audio.Play(e.Arm == LiteArm.Drone ? "explosion_small_a.wav" : "explosion_a.wav", onUs ? -7f : -15f, 0.06);
					break;
				case LiteEv.CapitalHit:
					if (Sim.Time - _lastCapitalPost < 4) break;
					_lastCapitalPost = Sim.Time;
					if (e.Side == 0) Ui.Post($"{Map.CapitalName[0]} is hit! {e.Value:0}/{LiteRules.MaxHp(LiteKind.Capital):0} left.", LiteGlyphs.Enemy);
					else Ui.Post($"Hit on {Map.CapitalName[1]}: {e.Value:0}/{LiteRules.MaxHp(LiteKind.Capital):0} left.", LiteGlyphs.Ours);
					break;
				case LiteEv.Destroyed:
					if (e.Kind == LiteKind.Capital) break;
					if (e.Side == 0) Ui.Post($"Our {LiteGlyphs.Name(e.Kind)} destroyed in {RegionName(e.Region)}.", LiteGlyphs.Enemy);
					else Ui.Post($"Enemy {LiteGlyphs.Name(e.Kind)} destroyed in {RegionName(e.Region)}.", LiteGlyphs.Good);
					Audio.Play("wreck.wav", -9f, 0.2);
					break;
				case LiteEv.Built:
					if (e.Side == 0) Audio.Play("click_off.wav", -12f);
					break;
				case LiteEv.Industry:
					if (e.Side != 0) break;
					Ui.Post(e.Value > 0
						? $"Industry moves to {RegionName(e.Region)}: room for one more factory there."
						: $"{RegionName(e.Region)} loses room for a factory: workers called up.", LiteGlyphs.Muted);
					break;
				case LiteEv.Warning:
					if (e.Side != 1) break;
					Ui.Post("Intelligence: the enemy is massing drones and missiles for a large strike. Ready the air defence.", LiteGlyphs.BallisticAlert);
					Audio.Play("alert.wav", -5f, 2);
					break;
				case LiteEv.Spotted:
					if (e.Side == 1 && e.Kind == LiteKind.Factory)
						Ui.Post($"The enemy has located our factory in {RegionName(e.Region)}.", LiteGlyphs.Enemy);
					if (e.Side == 0) Ui.Post($"Spotted: enemy {LiteGlyphs.Name(e.Kind)} in {RegionName(e.Region)}.", LiteGlyphs.Ours);
					break;
				case LiteEv.RaidOver:
					var r = e.Raid!;
					string hits = $"{r.Hits} hit{(r.Hits == 1 ? "" : "s")}";
					if (r.Side == 1)
						Ui.Post($"Raid over: {Composition(r)}. {r.Down} shot down, {hits}.",
							r.Hits == 0 ? LiteGlyphs.Good : r.Destroyed.Count > 0 ? LiteGlyphs.Enemy : LiteGlyphs.Yellow);
					else if (r.Total > 1 || r.Hits > 0) Ui.Post($"Our strike: {Composition(r)}. {hits}, {r.Down} shot down.", LiteGlyphs.Ours);
					break;
				case LiteEv.GameOver:
					_endTimer = 2f;
					BuildTool = null;
					StrikeTool = null;
					Audio.Play("explosion_b.wav", -2f);
					break;
			}
		}
		Sim.Events.Clear();
	}

	private void ShowEnd()
	{
		var me = Sim.Sides[0];
		bool won = Sim.Winner == 0;
		string stats = $"{Map.CapitalName[won ? 1 : 0]} has fallen after {LiteHud.Duration(Sim.Time)} of war.\n\n" +
			$"Enemy weapons shot down: {me.Downed}\n" +
			$"Our hits on enemy sites: {me.Hits}\n" +
			$"Enemy sites destroyed: {me.Destroyed}\n" +
			$"Our sites lost: {me.Lost}";
		Ui.ShowEnd(won, stats);
	}

	// ---------------------------------------------------------------- test modes

	/// Both sides played by the AI, no window, a line a minute per map.
	private void RunBalance(int seed, int seconds, int seeds)
	{
		for (int k = 0; k < seeds; k++)
		{
			int sd = seed + k * 101;
			ulong t0 = Time.GetTicksMsec();
			var map = LiteMap.Generate(sd);
			var sim = new LiteSim(map, sd);
			sim.Ai[0] = new LiteAi(0, sd + 2, 30f) { Waves = true };
			sim.Ai[1] = new LiteAi(1, sd + 1, 22f) { Waves = true, Adaptive = true };
			GD.Print($"[lite] seed {sd}: {map.Regions.Count} regions ({map.Regions.Count(r => r.Side == 0)} ours), map {Time.GetTicksMsec() - t0} ms");
			int alertTicks = 0, ticks = 0, waves = 0;
			for (int step = 1; step <= seconds * 30 && sim.Winner < 0; step++)
			{
				sim.Step(1 / 30f);
				foreach (var e in sim.Events) if (e.Type == LiteEv.Warning) { waves++; GD.Print($"  t={sim.Time:0} {(e.Side == 0 ? "west" : "east")} massing for ${e.Value:0}"); }
				sim.Events.Clear();
				if (step % 30 == 0) { ticks++; if (sim.Alerted[0] > 0) alertTicks++; }
				if (step % (60 * 30) == 0) GD.Print("  " + Line(sim));
			}
			GD.Print($"  end t={sim.Time:0}s winner={(sim.Winner < 0 ? "none" : sim.Winner == 0 ? "west" : "east")} alert {100 * alertTicks / Math.Max(1, ticks)}% of the time, {waves} massive strikes planned");
		}
		GetTree().Quit();
	}

	private static string Line(LiteSim s)
	{
		string Side(int i)
		{
			var sd = s.Sides[i];
			int f = s.Buildings.Count(b => b.Alive && b.Side == i && b.Kind == LiteKind.Factory);
			int g = s.Buildings.Count(b => b.Alive && b.Side == i && b.Kind == LiteKind.Gun);
			int m = s.Buildings.Count(b => b.Alive && b.Side == i && b.Kind == LiteKind.Sam);
			return $"${sd.Money:0} +{sd.Income:0.0} f{f} g{g} s{m} cap{sd.Capital.Hp:0} launched{sd.Launched} hits{sd.Hits} downed{sd.Downed}";
		}
		return $"t={s.Time:0} W[{Side(0)}] E[{Side(1)}] air{s.Weapons.Count}";
	}

	/// The menu and settings screens, then a game played by the AI on both
	/// sides at 12x: its first seconds, the first big raid, and a few minutes
	/// in. With `maps` > 0, first one picture per map of that many seeds.
	private async void RunShots(string dir, int maps)
	{
		DirAccess.MakeDirRecursiveAbsolute(dir);
		async System.Threading.Tasks.Task Wait(double s) => await ToSignal(GetTree().CreateTimer(s, true, false, true), SceneTreeTimer.SignalName.Timeout);
		async System.Threading.Tasks.Task Until(Func<bool> cond) { while (!cond()) await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame); }
		async System.Threading.Tasks.Task Shot(string name)
		{
			await ToSignal(RenderingServer.Singleton, RenderingServer.SignalName.FramePostDraw);
			var img = GetViewport().GetTexture().GetImage();
			string path = System.IO.Path.Combine(dir, name);
			img.SavePng(path);
			GD.Print($"[shot] {path} t={Sim.Time:0}");
		}
		if (maps > 0)
		{
			int first = Seed;
			Ui.CloseMenu();
			for (int k = 0; k < maps; k++)
			{
				NewWorld(first + k * 101);
				await Wait(0.3);
				await Shot($"map_{Seed}.png");
			}
			NewWorld(first);
			Ui.ShowMenu();
		}
		await Wait(1.0);
		await Shot("0_menu.png");
		Ui.ShowSettings();
		await Wait(0.4);
		await Shot("0_settings.png");
		_autoplay = true;
		NewGame();
		Speed = 3;
		Engine.TimeScale = 4;
		await Until(() => Sim.Time > 4);
		await Shot("1_start.png");
		await Until(() => Sim.Winner >= 0 || Sim.Time > 260 || (Sim.Alerted[0] >= 3 && Sim.Weapons.Count(w => w.Alive && w.Side == 1) >= 8));
		Paused = true;
		Engine.TimeScale = 1;
		await Wait(0.6);
		await Shot("2_raid.png");
		Paused = false;
		Engine.TimeScale = 4;
		await Until(() => Sim.Winner >= 0 || Sim.Time > 320);
		Engine.TimeScale = 1;
		BuildTool = LiteKind.Sam;
		_fakeMouse = Map.Capital[0] + new Vector2(-60, 40);
		await Wait(0.6);
		await Shot("3_later.png");
		BuildTool = null;
		Ui.ShowMenu();
		await Wait(0.4);
		await Shot("4_pause_menu.png");
		Ui.CloseMenu();
		_fakeMouse = null;
		await Stress(Shot);
		GetTree().Quit();
	}

	/// A crowded sky at 1x with no vsync: both sides send big salvos, then
	/// the frame time, the sim and the map drawing are measured.
	private async System.Threading.Tasks.Task Stress(Func<string, System.Threading.Tasks.Task> shot)
	{
		if (Sim.Winner >= 0) { GD.Print("[perf] the war ended before the stress stage"); return; }
		DisplayServer.WindowSetVsyncMode(DisplayServer.VSyncMode.Disabled);
		Engine.MaxFps = 0;
		Engine.TimeScale = 1;
		Speed = 1;
		Paused = false;
		await Measure("quiet sky", 1);
		var rng = new Random(5);
		for (int side = 0; side < 2; side++)
		{
			Sim.Sides[side].Money += 100000;
			for (int i = 0; i < 6; i++)
			{
				Sim.Strike(side, LiteArm.Drone, Sim.RandomSpot(1 - side, rng), 14);
				Sim.Strike(side, LiteArm.Cruise, Sim.RandomSpot(1 - side, rng), 4);
			}
			Sim.Strike(side, LiteArm.Ballistic, Sim.Sides[1 - side].Capital.Pos, 4, null, 6f);
		}
		for (int i = 0; i < 40; i++) await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
		await Measure("crowded sky", 3);
		await shot("5_stress.png");
	}

	private async System.Threading.Tasks.Task Measure(string what, int rounds)
	{
		for (int round = 0; round < rounds; round++)
		{
			LitePerf.Reset();
			double t0 = LitePerf.Now, process = 0;
			int frames = 0;
			while (LitePerf.Now - t0 < 2000)
			{
				await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
				frames++;
				process += Performance.GetMonitor(Performance.Monitor.TimeProcess) * 1000;
			}
			double ms = (LitePerf.Now - t0) / frames;
			GD.Print($"[perf] {what}: {Sim.Weapons.Count} in the air, {Sim.Interceptors.Count} interceptors, {Sim.Fx.Count} effects: " +
				$"{1000 / ms:0} fps, frame {ms:0.0} ms, process {process / frames:0.0} ms (sim {LitePerf.SimMs / frames:0.00}, map draw {LitePerf.DrawMs / frames:0.00}, ui draw {LitePerf.UiMs / frames:0.00}, ui process {LitePerf.UiProcMs / frames:0.00}); {LitePerf.Monitors()}");
		}
	}
}
