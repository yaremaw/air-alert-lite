class_name LiteTheme
extends RefCounted
## The map theme: Legacy (the game's own look, the default) or Modern Military
## Command, an alternative look for the battle map and its interface, kept
## entirely in src/Lite/command/ so it can be compared with the original and
## dropped without touching it.
##
## The command look is the default; Legacy is chosen in Settings (Map theme),
## with F8 during a war, with `?mapTheme=modern-command`
## (or `?mapTheme=legacy`) in the web build's address, or `--map-theme=modern-command`
## on the desktop command line. The address and the command line choose for
## that session only; Settings and F8 remember the choice in a file of their
## own (user://lite_map_theme.cfg), never in the game's settings.
##
## The command look covers every map: a war, a campaign operation and the
## campaign's front. Its bars and panel are up over a war and an operation;
## the front has its own strip and cards (LiteCmdFront), its map the whole
## screen.

const LEGACY: String = "legacy"
const COMMAND: String = "modern-command"
const PATH: String = "user://lite_map_theme.cfg"

## Whether the Modern Military Command theme is chosen (the default).
static var command: bool = true
## Whether this session's theme came from the address or command line.
static var _forced: bool = false

# The command theme's palette.
const BG: Color = Color("#0B1119")
const BG2: Color = Color("#111B27")
const PANEL: Color = Color("#142131")
const PANEL_HI: Color = Color("#1A2A3D")
const BORDER: Color = Color("#26394B")
const BLUE: Color = Color("#45B9F2")
const RED: Color = Color("#F05B50")
const AMBER: Color = Color("#E8A33D")
const TEXT: Color = Color("#E5EDF5")
const MUTED: Color = Color("#8FA2B5")
const NEUTRAL: Color = Color("#65788B")
const GREEN: Color = Color("#52C78A")
const OBJECTIVE: Color = Color("#D9E3EC")
## Friendly and hostile territory, and the world round them.
const OUR_LAND: Color = Color("#1F2D3E")
const ENEMY_LAND: Color = Color("#32252B")
const NEUTRAL_LAND: Color = Color("#171E27")
const SEA: Color = Color("#0A1018")

## The interface's frame round the map, in screen units (see LiteCmdUi): the
## top bar, the toolbar (LEFT wide, on the right) and the news line.
const TOP: float = 40.0
const LEFT: float = 76.0
const BOTTOM: float = 76.0
## The report bar along the bottom of the campaign's front (see LiteCmdFront).
## The front's bottom margin (once the room for the cast's report strip).
const FRONT_BOTTOM: float = 12.0
## An operation's strip under the top bar (see LiteCmdUi.OpStrip).
const OP_STRIP: float = 30.0

## How much of the top of the screen the bars take now: the top bar, and in
## an operation its strip under it.
static func top(main: LiteMain) -> float:
	return TOP + (OP_STRIP if main.mission != null else 0.0)
## The news line folded away: the map takes its room.
static var news_hidden: bool = false

## How much of the bottom of the screen the news line takes now.
static func bottom() -> float:
	return 0.0 if news_hidden else BOTTOM

## Reads the remembered choice, then the address or command line over it.
static func setup() -> void:
	command = true
	var c:= ConfigFile.new()
	if c.load(PATH) == OK:
		command = str(c.get_value("map", "theme", LEGACY)) == COMMAND
		news_hidden = bool(c.get_value("map", "news_hidden", false))
	var arg: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--map-theme="):
			arg = a.substr(12)
	if OS.has_feature("web"):
		var q: String = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('mapTheme') || ''"))
		if q != "" and q != "null":
			arg = q
	if arg != "":
		_forced = true
		command = arg == COMMAND or arg == "command" or arg == "modern"

static func save() -> void:
	if LiteSettings.dry:
		return
	var c:= ConfigFile.new()
	c.set_value("map", "theme", COMMAND if command else LEGACY)
	c.set_value("map", "news_hidden", news_hidden)
	c.save(PATH)

## Whether the battle map now on screen is drawn in the command look: the
## theme is chosen and this is not the campaign's front.
static func battle_view(main: LiteMain) -> bool:
	return command

## Whether this is the campaign's front between operations.
static func on_front(main: LiteMain) -> bool:
	return main.campaign != null and main.mission == null

## Whether the command interface is up: over a war or an operation, out of
## the menus.
static func hud_on(main: LiteMain) -> bool:
	return main._view is LiteCmdView and main.ui != null and not main.ui.home_open and not on_front(main)

## The map's place on screen in the command look: inside the frame of bars and
## panels, the land scaled to fill it. Returns false (the legacy fit applies)
## when the map is not drawn in the command look.
static func fit(main: LiteMain) -> bool:
	if not main._view is LiteCmdView:
		return false
	main.get_viewport().canvas_transform = front_transform(main) if on_front(main) else fit_transform(main)
	return true

## The front's map: the whole screen under its strip (LiteCmdFront).
static func front_transform(main: LiteMain) -> Transform2D:
	var vs: Vector2 = main.get_viewport().get_visible_rect().size
	var frame:= Rect2(24, TOP + 16, vs.x - 48, vs.y - TOP - FRONT_BOTTOM - 28)
	var land: Rect2 = main.map.land_rect.grow(10)
	var k: float = minf(minf(frame.size.x / land.size.x, frame.size.y / land.size.y), 1.8)
	var off: Vector2 = frame.get_center() - land.get_center() * k
	return Transform2D(0, Vector2(k, k), 0, off)

static func fit_transform(main: LiteMain) -> Transform2D:
	var vs: Vector2 = main.get_viewport().get_visible_rect().size
	var t: float = top(main)
	var frame:= Rect2(10, t + 10, vs.x - LEFT - 20, vs.y - t - bottom() - 20)
	var land: Rect2 = main.map.land_rect.grow(10)
	var most: float = 1.6
	if main.mission != null and not main.map.focus.is_empty():
		# An operation: the province fought over and our command, the land
		# round them at the edges.
		land = op_rect(main)
		most = 2.4
	var k: float = minf(minf(frame.size.x / land.size.x, frame.size.y / land.size.y), most)
	var off: Vector2 = frame.get_center() - land.get_center() * k
	return Transform2D(0, Vector2(k, k), 0, off)

## What an operation's view takes in: the districts fought over, all of our
## land on this map (the enemy strikes it anywhere), both commands and the
## targets, with a margin. Only the enemy's land beyond may be cut off.
static func op_rect(main: LiteMain) -> Rect2:
	var map: LiteMap = main.map
	var r:= Rect2(map.capital[0], Vector2.ZERO)
	for reg: LiteRegion in map.regions:
		if reg.side != 0 and not map.focus.has(reg.id):
			continue
		r = r.expand(reg.center)
		for p: Vector2 in reg.spots:
			r = r.expand(p)
	r = r.expand(map.capital[1])
	if main.mission != null:
		for b: LiteBuilding in main.mission.targets:
			r = r.expand(b.pos)
	return r.grow(34).intersection(map.land_rect.grow(40))

## The colour the screen is cleared to under the map, for the view now up.
static func clear_color(main: LiteMain) -> Color:
	return BG if main._view is LiteCmdView else LiteGlyphs.PAGE

## The menus and dialogs in the command look: the legacy palette's colours as
## the command palette's (unchanged in the legacy look). Used where the
## menus make their panels, buttons and labels (LiteGlyphs.box, LiteChip,
## LiteUi), so they are drawn in the command look from the start. (Switching
## look during a game restyles the map and its bars at once, the menus the
## next time the game starts.)
static func ui(c: Color) -> Color:
	if not command:
		return c
	for pair: Array in _MAP:
		var from: Color = pair[0]
		if absf(c.r - from.r) < 0.004 and absf(c.g - from.g) < 0.004 and absf(c.b - from.b) < 0.004:
			return Color(pair[1], c.a)
	return c

## Corners: square-ish in the command look.
static func corner(r: int) -> int:
	return mini(r, 2) if command else r

static var _MAP: Array = [
	[LiteGlyphs.PAGE, BG],
	[LiteGlyphs.PANEL, PANEL],
	[LiteGlyphs.PANEL_HI, PANEL_HI],
	[LiteGlyphs.LINE, BORDER],
	[LiteGlyphs.TEXT, TEXT],
	[LiteGlyphs.MUTED, MUTED],
	[LiteGlyphs.FAINT, NEUTRAL],
	[LiteGlyphs.OURS, BLUE],
	[LiteGlyphs.ENEMY, RED],
	[LiteGlyphs.GOOD, GREEN],
	[LiteGlyphs.YELLOW, AMBER],
	[LiteGlyphs.OBJECTIVE, BLUE],
	[LiteGlyphs.OBJECTIVE.darkened(0.3), BORDER],
	[LiteGlyphs.YELLOW.darkened(0.2), AMBER.darkened(0.25)],
]

## Puts the chosen theme on screen: the map view rebuilt in its look (the war
## and its state are untouched), the interface over it shown or hidden.
static func apply(main: LiteMain) -> void:
	if main.map != null and main.sim != null:
		main.rebuild_view()
	ensure_ui(main)

## The command interface, made the first time the theme is chosen.
static func ensure_ui(main: LiteMain) -> void:
	if command and main.cmd_ui == null and main.ui != null:
		main.cmd_ui = LiteCmdUi.new()
		main.cmd_ui.main = main
		main.ui.get_child(0).add_child(main.cmd_ui)
		# Over the map and the legacy HUD, under the menus and overlays.
		main.ui.get_child(0).move_child(main.cmd_ui, 1)
		main.cmd_ui.build()

## Switches theme (Settings, F8) and remembers it.
static func set_command(main: LiteMain, on: bool) -> void:
	if on == command:
		return
	command = on
	save()
	apply(main)
