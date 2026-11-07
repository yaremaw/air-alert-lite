"""The promo image at the top of the itch.io description (1600x880), built from
the screenshots in itch/screenshots.

    python tools/itch_hero.py itch
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "assets", "fonts", "Inter.ttf")
SHOTS = os.path.join(ROOT, "itch", "screenshots")
PAGE = (0x16, 0x18, 0x1D)
TEXT = (0xE8, 0xEA, 0xEE)
MUTED = (0x8B, 0x91, 0x9D)
FAINT = (0x5B, 0x61, 0x6C)
YELLOW = (0xE5, 0xAD, 0x16)
GOOD = (0x46, 0xC4, 0x7E)

LOGO = os.path.join(ROOT, "itch", "logo.png")
HEADLINE = "A real-time air war"
SUB = "on an air-raid alert map."
BULLETS = [
    "Shoot down drones, cruise and ballistic missiles",
    "Build factories, AA guns and SAMs",
    "Find the enemy's hidden sites, then strike them",
    "Live alert map, attack reports, war statistics",
    "Real air-raid sirens recorded in Ukraine",
]
FOOTER = "Free  ·  browser, Windows and macOS     |     tenchery.itch.io/strike-alert"
# (screenshot, caption, crop box x0, y0, width) - the height follows the tile shape.
TILES = [
    ("1-front.png", "Missile threat", 250, 230, 850),
    ("2-ballistic-hit.png", "Ballistic hit", 350, 230, 800),
    ("3-strike.png", "Strike back", 150, 230, 950),
    ("5-stats.png", "War statistics", 1060, 325, 780),
]


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def fit(text, weight, size, width):
    """The largest font up to `size` that keeps `text` within `width`."""
    f = font(size, weight)
    while f.getlength(text) > width and size > 10:
        size -= 2
        f = font(size, weight)
    return f


def tile(name, x0, y0, w, tw, th):
    shot = Image.open(os.path.join(SHOTS, name)).convert("RGB")
    h = round(w * th / tw)
    return shot.crop((x0, y0, x0 + w, y0 + h)).resize((tw, th), Image.LANCZOS)


def hero():
    W, H = 1600, 880
    img = Image.new("RGB", (W, H), PAGE)
    d = ImageDraw.Draw(img)

    # Left: what the game is.
    x = 70
    logo = Image.open(LOGO).convert("RGBA")
    logo = logo.resize((680, round(logo.height * 680 / logo.width)), Image.LANCZOS)
    img.paste(logo, (x - 6, 70), logo)
    d.text((x, 256), "OUT NOW ON ITCH.IO", font=font(24, "Bold"), fill=YELLOW)
    d.text((x, 290), HEADLINE, font=fit(HEADLINE, "Bold", 44, 700), fill=TEXT)
    d.text((x, 342), SUB, font=fit(SUB, "Bold", 44, 700), fill=TEXT)
    bf = fit(max(BULLETS, key=len), "Medium", 27, 660)
    y = 432
    for b in BULLETS:
        d.rectangle([x, y + 10, x + 13, y + 23], fill=YELLOW)
        d.text((x + 32, y), b, font=bf, fill=TEXT)
        y += 56
    d.text((x, 800), FOOTER, font=font(21, "Regular"), fill=FAINT)

    # Right: four framed screenshots with captions.
    gx, gw, gap = 830, 720, 22
    tw = (gw - gap) // 2
    th = round(tw * 0.73)
    gy = (H - (2 * th + gap)) // 2 + 20
    cap = font(23, "Bold")
    for i, (name, caption, x0, y0, w) in enumerate(TILES):
        tx = gx + (i % 2) * (tw + gap)
        ty = gy + (i // 2) * (th + gap)
        img.paste(tile(name, x0, y0, w, tw, th), (tx, ty))
        d.rectangle([tx - 3, ty - 3, tx + tw + 2, ty + th + 2], outline=YELLOW, width=3)
        cw = cap.getlength(caption)
        px, py = tx + (tw - cw) / 2 - 18, ty + th - 58
        d.rounded_rectangle([px, py, px + cw + 36, py + 40], radius=20, fill=(0x10, 0x11, 0x14))
        d.text((px + 18, py + 7), caption, font=cap, fill=TEXT)

    # The price tag above the grid.
    badge = font(26, "Black")
    bw = badge.getlength("FREE") + 56
    bx, by = gx + gw - bw, gy - 62
    d.rounded_rectangle([bx, by, bx + bw, by + 44], radius=8, fill=GOOD)
    d.text((bx + 28, by + 8), "FREE", font=badge, fill=PAGE)
    return img


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "itch")
    os.makedirs(out, exist_ok=True)
    path = os.path.join(out, "hero.png")
    hero().save(path)
    print("wrote", path)
