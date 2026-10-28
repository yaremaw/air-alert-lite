# Air Alert

A small strategy game about an air war, drawn like a live air-alert map: dark
regions turn yellow under air alert, red under ballistic threat. Build
factories and air defence, find the enemy's hidden sites, send drones and
missiles along routes you draw, and destroy the key targets round the enemy
capital before it destroys yours. Every map is generated; all names are fictional.

## Play (Windows)

1. Download `AirAlert-windows.zip` from the [Releases](../../releases) page.
2. Unzip it anywhere and run `AirAlert/AirAlert.exe`.

Windows may warn that the app is from an unknown publisher (it is not signed):
choose *More info → Run anyway*.

## Play (macOS)

1. Download `AirAlert-macos.zip` from the [Releases](../../releases) page and
   unzip it (Apple Silicon and Intel Macs, macOS 11 or newer).
2. The app is not notarized by Apple, so the first time macOS will refuse to
   open it. Either right-click (Control-click) `Air Alert.app` → *Open* →
   *Open*, or, if there is no *Open* button, go to *System Settings → Privacy &
   Security* and click *Open Anyway* next to "Air Alert".
3. If macOS says the app "is damaged", run this once in Terminal (adjust the
   path to where you unzipped it):

   ```
   xattr -dr com.apple.quarantine ~/Downloads/"Air Alert.app"
   ```

## Controls

| Key | Action |
|---|---|
| `1` `2` | Build: factory (pick a region), air defence. The tool stays in hand: click again for more |
| `A` `S` `D` | Queue a drone, cruise missile, ballistic missile (`Shift`: five) |
| `Q` `W` `E` | Strike from stock: drone, cruise missile, ballistic missile |
| Click enemy land | Launch straight at it (salvo 1×, 3×, 6× or all) |
| Drag from your land to the target | Draw the route |
| Drag from your air defence | Turn its radar |
| Right-click / `Esc` | Put the tool down; `Esc` again opens the menu |
| `Space` | Pause |

## How it works

- Win by destroying 3 of the 4 key targets round the enemy capital:
  headquarters, command bunker, energy centre, government building.
- Factories earn money and production points. Money pays for factories, air
  defence and repairs; production points build weapons in one shared queue
  into a stockpile you launch from.
- Armor matters: a hit deals warhead power minus armor. Drones barely scratch a
  bunker; a ballistic missile wrecks it.
- Air defence sees and fires only inside a 120° radar sector, tracks two
  weapons at once, and misses often. Come round its cones, from the side it
  is not facing, or with more than it can track.
- Enemy sites, and its drones and missiles, are hidden until you find them:
  over your land, near your air defence radars, by drones, or by intelligence.
- The enemy builds, defends, turns its radars towards your attacks, rebuilds
  what it loses and attacks from several directions. On Normal and Hard it
  masses for large strikes when it sees a chance; your intelligence warns you.

The full rules are in [src/Lite/DESIGN.md](src/Lite/DESIGN.md).

## Build from source

Needs [Godot 4.6.2 .NET](https://godotengine.org/download) and the .NET 8 SDK.
Open `project.godot` in Godot and press F5. To export, install the export
templates and use the *Windows Desktop* preset.

## Credits

Font: [Inter](https://rsms.me/inter/) by Rasmus Andersson, SIL Open Font
License (`assets/fonts/OFL.txt`).
