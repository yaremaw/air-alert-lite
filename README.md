# Air Alert

A small strategy game about an air war, drawn like a live air-alert map: dark
regions turn yellow under air alert, red under ballistic threat. Build
factories and air defence, find the enemy's hidden sites, send drones and
missiles along routes you draw, and destroy the enemy capital before it
destroys yours. Every map is generated; all names are fictional.

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
| `1` `2` `3` | Build: factory (pick a region), AA gun, SAM |
| `Q` `W` `E` | Strike: drone, cruise missile, ballistic missile |
| Click enemy land | Launch straight at it |
| Drag from your land to the target | Draw the route |
| `Shift` + click | Keep the build tool |
| Right-click / `Esc` | Cancel; `Esc` again opens the menu |
| `Space` | Pause |

## How it works

- Factories earn money and repair your capital. Each region has room for only
  a few; the front has more room than the rear.
- Guns are cheap and good against drones; SAMs reach far and hit everything,
  but every interceptor costs money.
- Enemy sites, and its drones and missiles, are hidden until you find them:
  over your land, near your air defence radars, by drones, or by intelligence.
- The enemy builds, defends and adapts. On Normal and Hard it masses for large
  strikes when it sees a chance; your intelligence warns you.

The full rules are in [src/Lite/DESIGN.md](src/Lite/DESIGN.md).

## Build from source

The game is plain GDScript. Open `project.godot` in [Godot 4.6+](https://godotengine.org/download)
and press F5. To export, install the export templates and use the *Windows
Desktop*, *macOS* or *Web* preset. The web build has to be exported with the
standard (non-.NET) Godot editor; it is single-threaded, so it needs no special
server headers.

## Play in the browser

https://air-alert-beta.vercel.app

## Credits

Font: [Inter](https://rsms.me/inter/) by Rasmus Andersson, SIL Open Font
License (`assets/fonts/OFL.txt`).

Air-raid sirens (`alert.wav`, `all_clear.wav`, `ballistic_warning.wav`): cut
from [Air Raid Alert - Ukraine during russian invasion 2022](https://commons.wikimedia.org/wiki/File:Air_Raid_Alert_-_Ukraine_during_russian_invasion_2022.ogg)
by Lystopad, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/);
the edited clips are under the same license. The other sounds are synthesized
by `tools/make_sounds.py`.
