"""The game's own icon and boot splash, from the logo in tools/itch_logo2.py.

    python tools/app_icon.py

writes, into assets/ui:
- icon.png: the emblem on a dark rounded square, 512 px (the project icon: the
  browser tab, the macOS app and the window);
- icon.ico: the same at 16 to 256 px, for the Windows .exe;
- splash.png: the emblem and the name, shown while the game loads.
"""
import os

from PIL import Image, ImageDraw

import itch_logo2 as logo2

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui")
PAGE = (0x16, 0x18, 0x1D, 255)
K = logo2.K


def icon():
    n = 512 * K
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, n - 1, n - 1], radius=n * 0.2, fill=PAGE)
    # A slightly heavier emblem than the itch one, so it still reads at 16 px.
    logo2.emblem(d, n / 2, n / 2, n * 0.34)
    return img.resize((512, 512), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    big = icon()
    big.save(os.path.join(OUT, "icon.png"))
    big.save(os.path.join(OUT, "icon.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    splash = logo2.logo()
    w = 720
    splash.resize((w, round(splash.height * w / splash.width)), Image.LANCZOS).save(os.path.join(OUT, "splash.png"))
    print("wrote icon.png, icon.ico and splash.png to", OUT)


if __name__ == "__main__":
    main()
