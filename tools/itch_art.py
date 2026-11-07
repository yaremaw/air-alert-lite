"""Cover (630x500) and banner (960x240) for the itch.io page: a piece of a
screenshot with the logo (made by tools/itch_logo.py) over it.

    python tools/itch_art.py itch/screenshots/3-strike.png itch --only cover --focus 0.36,0.55
    python tools/itch_art.py itch/screenshots/4-air-defence.png itch --only banner --focus 0.42,0.47

--focus is the point of the screenshot, as fractions of its width and height,
the picture is centred on; --zoom scales the screenshot (1 = its own pixels).
"""
import argparse
import os

from PIL import Image, ImageDraw

PAGE = (0x16, 0x18, 0x1D)


def crop(shot, w, h, focus, zoom):
    """The w x h piece of the shot round `focus`, `zoom` times the shot's own scale."""
    sw, sh = shot.size
    cw, ch = w / zoom, h / zoom
    cx = min(max(focus[0] * sw, cw / 2), sw - cw / 2)
    cy = min(max(focus[1] * sh, ch / 2), sh - ch / 2)
    box = (round(cx - cw / 2), round(cy - ch / 2), round(cx + cw / 2), round(cy + ch / 2))
    return shot.crop(box).resize((w, h), Image.LANCZOS)


def fade(img, horizontal, solid, end, alpha):
    """Covers the picture with the page colour up to `solid` (a fraction of the
    width, or of the height from the bottom), then fades it out by `end`."""
    w, h = img.size
    over = Image.new("RGBA", (w, h), PAGE + (0,))
    d = ImageDraw.Draw(over)
    n = w if horizontal else h
    a, b = int(n * solid), int(n * end)
    for i in range(0, b):
        t = 1.0 if i < a else 1 - (i - a) / max(1, b - a)
        a8 = int(alpha * t ** 0.8)
        if horizontal:
            d.line([(i, 0), (i, h)], fill=PAGE + (a8,))
        else:
            d.line([(0, h - 1 - i), (w, h - 1 - i)], fill=PAGE + (a8,))
    return Image.alpha_composite(img.convert("RGBA"), over)


def scaled(logo, width):
    return logo.resize((width, round(logo.height * width / logo.width)), Image.LANCZOS)


def cover(shot, logo, focus, zoom):
    w, h = 630, 500
    img = fade(crop(shot, w, h, focus, zoom), False, 0.18, 0.5, 240)
    lg = scaled(logo, 560)
    img.alpha_composite(lg, ((w - lg.width) // 2, h - lg.height - 30))
    return img.convert("RGB")


def banner(shot, logo, focus, zoom):
    w, h = 960, 240
    img = fade(crop(shot, w, h, focus, zoom), True, 0.36, 0.7, 238)
    lg = scaled(logo, 420)
    img.alpha_composite(lg, (34, (h - lg.height) // 2))
    return img.convert("RGB")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("shot")
    p.add_argument("out_dir")
    p.add_argument("--only", choices=["cover", "banner"], required=True)
    p.add_argument("--focus", default="0.4,0.5")
    p.add_argument("--zoom", type=float, default=1.0)
    p.add_argument("--logo", help="defaults to logo.png in out_dir")
    a = p.parse_args()
    shot = Image.open(a.shot).convert("RGB")
    logo = Image.open(a.logo or os.path.join(a.out_dir, "logo.png")).convert("RGBA")
    focus = tuple(float(v) for v in a.focus.split(","))
    make = cover if a.only == "cover" else banner
    path = os.path.join(a.out_dir, a.only + ".png")
    make(shot, logo, focus, a.zoom).save(path)
    print("wrote", path)


if __name__ == "__main__":
    main()
