using System;
using Godot;

/// The interface of the lite game: the side panel (status, BUILD,
/// PRODUCTION with its queue, STRIKE from the stockpile, the feed, speed and
/// the menu button), the HUD over the map, and the screens over it: the
/// menu, a new game, settings and the end of a war.
public partial class LiteUi : CanvasLayer
{
	public LiteMain Main = null!;
	public LiteHud Hud = null!;
	private readonly LiteToolButton[] _build = new LiteToolButton[2], _strike = new LiteToolButton[3];
	private readonly LiteChip[] _salvo = new LiteChip[4], _speed = new LiteChip[4], _diff = new LiteChip[3], _make = new LiteChip[3];
	private LiteChip _repairs = null!, _repeat = null!;
	private Label _ppHint = null!;
	private readonly LiteChip[] _volume = new LiteChip[4], _window = new LiteChip[2], _routes = new LiteChip[2], _ranges = new LiteChip[2];
	private VBoxContainer _feed = null!;
	private Control _panel = null!, _menu = null!, _newGame = null!, _settings = null!, _end = null!;
	private Button _continue = null!, _newGameButton = null!;
	private Label _menuSub = null!, _endTitle = null!, _endText = null!;

	/// True while one of the screens over the map is open; the war stands still.
	public bool MenuOpen => _menu.Visible || _newGame.Visible || _settings.Visible;

	public static readonly LiteKind[] BuildKinds = { LiteKind.Factory, LiteKind.Ad };
	public static readonly LiteArm[] Arms = { LiteArm.Drone, LiteArm.Cruise, LiteArm.Ballistic };
	/// Salvo sizes; the last means everything in stock.
	public static readonly int[] Salvos = { 1, 3, 6, 999 };
	private static readonly float[] Speeds = { 0, 1, 2, 3 };

	private static readonly string[] BuildTips =
	{
		$"Factory: +${LiteRules.FactoryIncome:0}/s and +{LiteRules.FactoryPP:0.#} PP/s for weapons. Built into a region with room for it; the front has more room than the rear. Each one costs {LiteRules.FactoryGrowth:0.#}× the last. While its region is under air alert it runs at half its pace.",
		$"Air defence system: shoots down drones and missiles in range. Its shots cost nothing. Each costs ${LiteRules.AdStep} more than the last; a region holds {LiteRules.AdPerRegion}.",
	};
	private static readonly string[] StrikeTips =
	{
		"Attack drone: slow and cheap, wanders on its way. Reveals enemy sites it flies over.",
		"Cruise missile: fast and accurate, launched from deep inside our country.",
		"Ballistic missile: very fast, hard to intercept, a little scattered.",
	};
	private static readonly string[] MakeKeys = { "A", "S", "D" };

	public void Build()
	{
		var root = new Control { MouseFilter = Control.MouseFilterEnum.Ignore, Theme = MakeTheme() };
		root.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
		AddChild(root);
		Hud = new LiteHud { Main = Main };
		root.AddChild(Hud);

		var panel = new PanelContainer { MouseFilter = Control.MouseFilterEnum.Stop };
		panel.AnchorLeft = 1; panel.AnchorRight = 1; panel.AnchorTop = 0; panel.AnchorBottom = 1;
		panel.OffsetLeft = -292; panel.OffsetRight = -10; panel.OffsetTop = 10; panel.OffsetBottom = -10;
		panel.AddThemeStyleboxOverride("panel", LiteGlyphs.Box(new Color(LiteGlyphs.Panel, 0.97f), LiteGlyphs.Line, 14, 14));
		root.AddChild(panel);
		_panel = panel;
		var vb = new VBoxContainer();
		vb.AddThemeConstantOverride("separation", 8);
		panel.AddChild(vb);

		vb.AddChild(new LiteStatus { Main = Main, CustomMinimumSize = new Vector2(0, 150) });

		vb.AddChild(Section("BUILD", "money", out _));
		var row = Row(vb);
		for (int i = 0; i < 2; i++)
		{
			var k = BuildKinds[i];
			var b = new LiteToolButton { Glyph = LiteGlyphs.Of(k), Title = LiteGlyphs.Name(k), Key = $"{i + 1}", TooltipText = BuildTips[i], Height = 58 };
			b.Clicked = () => Main.SelectBuild(k);
			_build[i] = b;
			row.AddChild(b);
		}

		vb.AddChild(Section("PRODUCTION", "", out _ppHint));
		row = Row(vb);
		for (int i = 0; i < 3; i++)
		{
			var a = Arms[i];
			var c = new LiteChip { Text = $"+ {LiteGlyphs.Name(a)} {LiteRules.PP(a):0}", FontSize = 11, SizeFlagsHorizontal = Control.SizeFlags.ExpandFill,
				TooltipText = $"Queue a {LiteGlyphs.Plural(a, 1)}: {LiteRules.PP(a):0} production points ({MakeKeys[i]}; Shift adds 5)" };
			c.Clicked = () => Main.Enqueue(a, Input.IsKeyPressed(Key.Shift) ? 5 : 1);
			_make[i] = c;
			row.AddChild(c);
		}
		vb.AddChild(new LiteQueue { Main = Main });
		row = Row(vb);
		_repeat = new LiteChip { FontSize = 11, SizeFlagsHorizontal = Control.SizeFlags.ExpandFill, TooltipText = "Every finished weapon goes to the back of the queue again, so production never stops." };
		_repeat.Clicked = () => { var p = Main.Sim.Sides[0].Production; p.Repeat = !p.Repeat; Main.Audio.Click(); };
		row.AddChild(_repeat);
		var clear = new LiteChip { Text = "Clear", FontSize = 11, CustomMinimumSize = new Vector2(52, 28), TooltipText = "Empty the queue" };
		clear.Clicked = () => { Main.Sim.Sides[0].Production.Clear(); Main.Audio.Click(); };
		row.AddChild(clear);
		_repairs = new LiteChip { FontSize = 11, SizeFlagsHorizontal = Control.SizeFlags.ExpandFill,
			TooltipText = $"Damaged buildings are repaired for money: {LiteRules.RepairRate * 100:0.#}% of their health a second, ${LiteRules.RepairPrice:0.##} for each 1%." };
		_repairs.Clicked = () => { var me = Main.Sim.Sides[0]; me.Repairing = !me.Repairing; Main.Audio.Click(); };
		row.AddChild(_repairs);

		vb.AddChild(Section("STRIKE", "from the stockpile", out _));
		row = Row(vb);
		string[] keys = { "Q", "W", "E" };
		for (int i = 0; i < 3; i++)
		{
			var a = Arms[i];
			var b = new LiteToolButton { Glyph = LiteGlyphs.Of(a), Title = LiteGlyphs.Name(a), Key = keys[i], Accent = LiteGlyphs.Yellow, TooltipText = StrikeTips[i], Height = 58 };
			b.Clicked = () => Main.SelectStrike(a);
			_strike[i] = b;
			row.AddChild(b);
		}
		row = Row(vb);
		var salvoLabel = new Label { Text = "Salvo", VerticalAlignment = VerticalAlignment.Center, CustomMinimumSize = new Vector2(40, 0) };
		salvoLabel.AddThemeColorOverride("font_color", LiteGlyphs.Muted);
		salvoLabel.AddThemeFontSizeOverride("font_size", 12);
		row.AddChild(salvoLabel);
		for (int i = 0; i < Salvos.Length; i++)
		{
			int n = Salvos[i];
			bool all = i == Salvos.Length - 1;
			var c = new LiteChip { Text = all ? "All" : $"{n}×", Accent = LiteGlyphs.Yellow, SizeFlagsHorizontal = Control.SizeFlags.ExpandFill,
				TooltipText = all ? "Launch everything of that kind in stock" : $"Launch {n} at each click" };
			c.Clicked = () => { Main.Salvo = n; Main.Audio.Click(); };
			_salvo[i] = c;
			row.AddChild(c);
		}

		vb.AddChild(Section("FEED", "", out _));
		// The feed takes what room is left and never pushes the row below off the panel.
		var scroll = new ScrollContainer
		{
			SizeFlagsVertical = Control.SizeFlags.ExpandFill,
			HorizontalScrollMode = ScrollContainer.ScrollMode.Disabled,
			VerticalScrollMode = ScrollContainer.ScrollMode.ShowNever,
			CustomMinimumSize = new Vector2(0, 40),
		};
		vb.AddChild(scroll);
		_feed = new VBoxContainer { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill };
		_feed.AddThemeConstantOverride("separation", 5);
		scroll.AddChild(_feed);

		row = Row(vb);
		var menu = new LiteChip { Text = "Menu", TooltipText = "Menu and settings (Esc)", CustomMinimumSize = new Vector2(58, 28) };
		menu.Clicked = () => { ShowMenu(); Main.Audio.Click(); };
		row.AddChild(menu);
		string[] speedText = { "II", "1×", "2×", "3×" };
		for (int i = 0; i < 4; i++)
		{
			float s = Speeds[i];
			var c = new LiteChip { Text = speedText[i], SizeFlagsHorizontal = Control.SizeFlags.ExpandFill, TooltipText = s == 0 ? "Pause (Space)" : $"Speed {s}×" };
			c.Clicked = () => { Main.SetSpeed(s); Main.Audio.Click(); };
			_speed[i] = c;
			row.AddChild(c);
		}

		_menu = BuildMenu(root);
		_newGame = BuildNewGame(root);
		_settings = BuildSettings(root);
		_end = BuildEnd(root);
	}

	private static HBoxContainer Row(Control parent)
	{
		var row = new HBoxContainer();
		row.AddThemeConstantOverride("separation", 6);
		parent.AddChild(row);
		return row;
	}

	private static Control Section(string title, string hint, out Label hintLabel)
	{
		var row = new HBoxContainer { CustomMinimumSize = new Vector2(0, 16) };
		var t = new Label { Text = title, SizeFlagsHorizontal = Control.SizeFlags.ExpandFill };
		t.AddThemeFontOverride("font", LiteGlyphs.Bold);
		t.AddThemeFontSizeOverride("font_size", 10);
		t.AddThemeColorOverride("font_color", LiteGlyphs.Muted);
		row.AddChild(t);
		var h = new Label { Text = hint };
		h.AddThemeFontSizeOverride("font_size", 10);
		h.AddThemeColorOverride("font_color", LiteGlyphs.Faint);
		row.AddChild(h);
		hintLabel = h;
		return row;
	}

	private static Theme MakeTheme()
	{
		var t = new Theme { DefaultFont = LiteGlyphs.Font, DefaultFontSize = 13 };
		t.SetStylebox("panel", "TooltipPanel", LiteGlyphs.Box(new Color(LiteGlyphs.Panel, 0.98f), LiteGlyphs.Line, 7, 8));
		t.SetColor("font_color", "TooltipLabel", LiteGlyphs.Text);
		t.SetFontSize("font_size", "TooltipLabel", 12);
		t.SetColor("font_color", "Label", LiteGlyphs.Text);
		t.SetStylebox("normal", "Button", LiteGlyphs.Box(LiteGlyphs.Ours, LiteGlyphs.Ours, 9, 10));
		t.SetStylebox("hover", "Button", LiteGlyphs.Box(LiteGlyphs.Ours.Lightened(0.12f), LiteGlyphs.Ours.Lightened(0.12f), 9, 10));
		t.SetStylebox("pressed", "Button", LiteGlyphs.Box(LiteGlyphs.Ours.Darkened(0.15f), LiteGlyphs.Ours, 9, 10));
		t.SetStylebox("focus", "Button", new StyleBoxEmpty());
		t.SetColor("font_color", "Button", Colors.White);
		t.SetColor("font_hover_color", "Button", Colors.White);
		t.SetColor("font_pressed_color", "Button", Colors.White);
		t.SetFont("font", "Button", LiteGlyphs.Bold);
		t.SetFontSize("font_size", "Button", 15);
		return t;
	}

	// ---------------------------------------------------------------- screens

	private Control Overlay(Control root, out VBoxContainer box, float width)
	{
		var o = new Control { MouseFilter = Control.MouseFilterEnum.Stop, Visible = false };
		o.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
		var dim = new ColorRect { Color = new Color(LiteGlyphs.Page, 0.8f), MouseFilter = Control.MouseFilterEnum.Ignore };
		dim.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
		o.AddChild(dim);
		var center = new CenterContainer { MouseFilter = Control.MouseFilterEnum.Ignore };
		center.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
		o.AddChild(center);
		var panel = new PanelContainer { CustomMinimumSize = new Vector2(width, 0) };
		panel.AddThemeStyleboxOverride("panel", LiteGlyphs.Box(LiteGlyphs.Panel, LiteGlyphs.Line, 16, 26));
		center.AddChild(panel);
		box = new VBoxContainer();
		box.AddThemeConstantOverride("separation", 12);
		panel.AddChild(box);
		root.AddChild(o);
		return o;
	}

	private static Label Text(string s, int size, Color col, bool bold = false)
	{
		var l = new Label { Text = s, AutowrapMode = TextServer.AutowrapMode.WordSmart };
		l.AddThemeFontSizeOverride("font_size", size);
		l.AddThemeColorOverride("font_color", col);
		if (bold) l.AddThemeFontOverride("font", LiteGlyphs.Bold);
		return l;
	}

	/// A wide button: blue for the main action, quiet grey for the rest.
	private Button Wide(Control parent, string text, bool primary, Action pressed)
	{
		var b = new Button { Text = text, CustomMinimumSize = new Vector2(0, primary ? 44 : 40), FocusMode = Control.FocusModeEnum.None, MouseDefaultCursorShape = Control.CursorShape.PointingHand };
		Quiet(b, !primary);
		b.Pressed += () => { Main.Audio.Click(); pressed(); };
		parent.AddChild(b);
		return b;
	}

	private static void Quiet(Button b, bool quiet)
	{
		foreach (var st in new[] { "normal", "hover", "pressed" }) b.RemoveThemeStyleboxOverride(st);
		foreach (var st in new[] { "font_color", "font_hover_color" }) b.RemoveThemeColorOverride(st);
		if (!quiet) return;
		b.AddThemeStyleboxOverride("normal", LiteGlyphs.Box(LiteGlyphs.PanelHi, LiteGlyphs.Line, 9, 10));
		b.AddThemeStyleboxOverride("hover", LiteGlyphs.Box(LiteGlyphs.PanelHi.Lightened(0.06f), LiteGlyphs.Muted, 9, 10));
		b.AddThemeStyleboxOverride("pressed", LiteGlyphs.Box(LiteGlyphs.Panel, LiteGlyphs.Muted, 9, 10));
		b.AddThemeColorOverride("font_color", LiteGlyphs.Text);
		b.AddThemeColorOverride("font_hover_color", Colors.White);
	}

	private static void Title(VBoxContainer box, string title)
	{
		box.AddChild(Text("STRIKE ALERT · LITE", 11, LiteGlyphs.Muted, true));
		box.AddChild(Text(title, 34, LiteGlyphs.Text, true));
	}

	private Control BuildMenu(Control root)
	{
		var o = Overlay(root, out var box, 360);
		Title(box, "Air Alert");
		_menuSub = Text("", 13, LiteGlyphs.Muted);
		box.AddChild(_menuSub);
		_continue = Wide(box, "Continue", true, CloseMenu);
		_newGameButton = Wide(box, "New war", true, () => Show(_newGame));
		Wide(box, "Settings", false, () => Show(_settings));
		Wide(box, "Quit", false, () => Main.GetTree().Quit());
		box.AddChild(Text("Esc opens this menu during the war", 11, LiteGlyphs.Faint));
		return o;
	}

	private Control BuildNewGame(Control root)
	{
		var o = Overlay(root, out var box, 500);
		Title(box, "New war");
		box.AddChild(Text(
			"Hold the sky over your country and strike back.\n\n" +
			"•  Factories earn money and production points. Money builds factories and air defence and pays for repairs; production points build drones and missiles into a stockpile.\n" +
			"•  Air defence shoots down drones and missiles flying into range.\n" +
			"•  The enemy's sites are hidden: send drones to find them, missiles to destroy them.\n" +
			"•  Its capital heals while its factories work: hit them, and the air defence guarding them, first.\n" +
			"•  Destroy the enemy capital before it destroys yours.",
			13, LiteGlyphs.Muted));
		var row = Row(box);
		for (int i = 0; i < 3; i++)
		{
			int d = i;
			var c = new LiteChip { Text = new[] { "Easy", "Normal", "Hard" }[i], SizeFlagsHorizontal = Control.SizeFlags.ExpandFill, CustomMinimumSize = new Vector2(0, 32) };
			c.Clicked = () => { LiteSettings.Difficulty = d; LiteSettings.Save(); Main.Audio.Click(); };
			_diff[i] = c;
			row.AddChild(c);
		}
		Wide(box, "Start", true, () => { Show(null); Main.NewGame(); });
		Wide(box, "Back", false, () => Show(_menu));
		box.AddChild(Text("1 2 3 build  ·  Q W E strike  ·  Space pause  ·  Esc cancel or menu", 11, LiteGlyphs.Faint));
		return o;
	}

	private Control BuildSettings(Control root)
	{
		var o = Overlay(root, out var box, 460);
		Title(box, "Settings");
		Choice(box, "Sound", new[] { "Off", "Low", "Medium", "High" }, _volume, i => { LiteSettings.Volume = i; LiteSettings.ApplySound(); });
		Choice(box, "Window", new[] { "Windowed", "Fullscreen" }, _window, i => { LiteSettings.Fullscreen = i == 1; LiteSettings.ApplyWindow(); });
		Choice(box, "Weapon routes", new[] { "Shown", "Hidden" }, _routes, i => LiteSettings.Routes = i == 0);
		Choice(box, "Air defence ranges", new[] { "Shown", "Hidden" }, _ranges, i => LiteSettings.Ranges = i == 0);
		Wide(box, "Back", false, () => Show(_menu));
		return o;
	}

	private void Choice(VBoxContainer box, string label, string[] options, LiteChip[] chips, Action<int> pick)
	{
		var row = Row(box);
		var l = new Label { Text = label, VerticalAlignment = VerticalAlignment.Center, CustomMinimumSize = new Vector2(140, 0) };
		l.AddThemeColorOverride("font_color", LiteGlyphs.Muted);
		row.AddChild(l);
		for (int i = 0; i < options.Length; i++)
		{
			int k = i;
			var c = new LiteChip { Text = options[i], SizeFlagsHorizontal = Control.SizeFlags.ExpandFill, CustomMinimumSize = new Vector2(0, 30) };
			c.Clicked = () => { pick(k); LiteSettings.Save(); Main.Audio.Click(); };
			chips[i] = c;
			row.AddChild(c);
		}
	}

	private Control BuildEnd(Control root)
	{
		var o = Overlay(root, out var box, 420);
		_endTitle = Text("", 34, LiteGlyphs.Text, true);
		_endText = Text("", 13, LiteGlyphs.Muted);
		box.AddChild(_endTitle);
		box.AddChild(_endText);
		Wide(box, "New war", true, () => { _end.Visible = false; Show(_newGame); });
		Wide(box, "Main menu", false, () => { _end.Visible = false; ShowMenu(); });
		return o;
	}

	/// Shows one screen (or none) over the map.
	private void Show(Control? screen)
	{
		_menu.Visible = screen == _menu;
		_newGame.Visible = screen == _newGame;
		_settings.Visible = screen == _settings;
	}

	public void ShowMenu()
	{
		bool live = Main.Started && Main.Sim.Winner < 0;
		_continue.Visible = live;
		Quiet(_newGameButton, live);
		_menuSub.Text = live ? $"The war is paused · {Main.ClockText(Main.Sim.Time, true)}" : "An air war on a live air-alert map.";
		_end.Visible = false;
		Show(_menu);
	}

	public void ShowSettings() => Show(_settings);

	public void CloseMenu() => Show(null);

	/// Esc on a screen: back to the menu, or out of the menu into a war under way.
	public void Back()
	{
		if (_newGame.Visible || _settings.Visible) Show(_menu);
		else if (_menu.Visible && Main.Started && Main.Sim.Winner < 0) CloseMenu();
	}

	public void ShowEnd(bool won, string stats)
	{
		_endTitle.Text = won ? "Victory" : "Defeat";
		_endTitle.AddThemeColorOverride("font_color", won ? LiteGlyphs.Good : LiteGlyphs.Enemy);
		_endText.Text = stats;
		Show(null);
		_end.Visible = true;
	}

	// ---------------------------------------------------------------- feed

	public void ClearFeed()
	{
		foreach (var c in _feed.GetChildren()) c.QueueFree();
	}

	public void Post(string text, Color tone)
	{
		var card = new PanelContainer { MouseFilter = Control.MouseFilterEnum.Ignore };
		var box = LiteGlyphs.Box(new Color(LiteGlyphs.PanelHi, 0.7f), tone, 7);
		box.BorderWidthTop = box.BorderWidthRight = box.BorderWidthBottom = 0;
		box.BorderWidthLeft = 3;
		box.ContentMarginLeft = 10; box.ContentMarginRight = 8; box.ContentMarginTop = 6; box.ContentMarginBottom = 7;
		card.AddThemeStyleboxOverride("panel", box);
		var vb = new VBoxContainer();
		vb.AddThemeConstantOverride("separation", 1);
		vb.AddChild(Text(Main.ClockText(Main.Sim.Time, false), 10, LiteGlyphs.Faint));
		vb.AddChild(Text(text, 12, LiteGlyphs.Text));
		card.AddChild(vb);
		card.Modulate = new Color(1, 1, 1, 0);
		_feed.AddChild(card);
		_feed.MoveChild(card, 0);
		card.CreateTween().TweenProperty(card, "modulate:a", 1f, 0.35f);
		while (_feed.GetChildCount() > 8) { var old = _feed.GetChild(_feed.GetChildCount() - 1); _feed.RemoveChild(old); old.QueueFree(); }
	}

	// ---------------------------------------------------------------- refresh

	public override void _Process(double delta)
	{
		if (Main.Sim == null) return;
		var me = Main.Sim.Sides[0];
		var prod = me.Production;
		for (int i = 0; i < 2; i++)
		{
			_build[i].Selected = Main.BuildTool == BuildKinds[i];
			int price = Main.Sim.Cost(0, BuildKinds[i]);
			_build[i].Affordable = me.Money >= price;
			_build[i].Price = $"${price}";
		}
		for (int i = 0; i < 3; i++)
		{
			int stock = prod.Stock[i];
			_strike[i].Selected = Main.StrikeTool == Arms[i];
			_strike[i].Affordable = stock > 0;
			_strike[i].Price = stock > 0 ? $"{stock} ready" : "none ready";
			_diff[i].Selected = LiteSettings.Difficulty == i;
		}
		for (int i = 0; i < Salvos.Length; i++) _salvo[i].Selected = Main.Salvo == Salvos[i];
		_ppHint.Text = $"{prod.Rate:0.#} PP/s";
		_repeat.Text = prod.Repeat ? "Repeat: ON" : "Repeat: OFF";
		_repeat.Selected = prod.Repeat;
		_repairs.Text = me.Repairing ? "Repairs: ON" : "Repairs: OFF";
		_repairs.Selected = me.Repairing;
		for (int i = 0; i < 4; i++) _volume[i].Selected = LiteSettings.Volume == i;
		for (int i = 0; i < 2; i++)
		{
			_window[i].Selected = LiteSettings.Fullscreen == (i == 1);
			_routes[i].Selected = LiteSettings.Routes == (i == 0);
			_ranges[i].Selected = LiteSettings.Ranges == (i == 0);
		}
		_panel.Visible = Main.Started;
		for (int i = 0; i < 4; i++) _speed[i].Selected = i == 0 ? Main.Paused : !Main.Paused && Main.Speed == Speeds[i];
	}
}
