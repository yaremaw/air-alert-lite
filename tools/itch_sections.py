"""The two images inside the itch.io description, one for each section:
how-it-plays.png (build, defend, strike, win) and features.png (alert map,
statistics). Built from the screenshots in itch/screenshots and the victory
screen in itch/extra.

    python tools/itch_sections.py itch
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "assets", "fonts", "Inter.ttf")
ITCH = os.path.join(ROOT, "itch")
PAGE = (0x16, 0x18, 0x1D)
PANEL = (0x1C, 0x1F, 0x25)
TEXT = (0xE8, 0xEA, 0xEE)
MUTED = (0x8B, 0x91, 0x9D)
YELLOW = (0xE5, 0xAD, 0x16)

# (image, crop box x0, y0, x1, y1, number, title)
STEPS = [
    ("screenshots/2-ballistic-hit.png", (1490, 30, 1900, 420), "1", "BUILD"),
    ("screenshots/4-air-defence.png", (380, 300, 1180, 750), "2", "DEFEND"),
    ("screenshots/3-strike.png", (250, 330, 1130, 825), "3", "STRIKE"),
    ("extra/victory.png", (520, 240, 1400, 735), "4", "WIN"),
]
# (image, crop box, title, line)
CARDS = [
    ("screenshots/1-front.png", (150, 200, 1350, 990), "LIVE ALERT MAP", "Every region lights up"),
    ("screenshots/5-stats.png", (1058, 322, 1842, 1012), "WAR STATISTICS", "Every raid mapped and counted"),
]
W, M, GAP = 1600, 40, 40
PW = (W - 2 * M - GAP) // 2
PH = round(PW * 0.5625)


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def fill(src, box, w, h):
    """The box of `src` scaled to cover w x h, cut to that size round its centre."""
    im = Image.open(os.path.join(ITCH, src)).convert("RGB").crop(box)
    k = max(w / im.width, h / im.height)
    im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    x, y = (im.width - w) // 2, (im.height - h) // 2
    return im.crop((x, y, x + w, y + h))


def fit(src, box, w, h):
    """The box of `src` scaled to fit inside w x h, centred on the panel colour."""
    im = Image.open(os.path.join(ITCH, src)).convert("RGB").crop(box)
    k = min(w / im.width, h / im.height)
    im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    out = Image.new("RGB", (w, h), PANEL)
    out.paste(im, ((w - im.width) // 2, (h - im.height) // 2))
    return out


def frame(d, x, y, w, h):
    d.rectangle([x - 3, y - 3, x + w + 2, y + h + 2], outline=YELLOW, width=3)


def how_it_plays():
    bar = 100
    img = Image.new("RGB", (W, M + 2 * (PH + bar) + GAP + M - 20), PAGE)
    d = ImageDraw.Draw(img)
    num, title = font(44, "Black"), font(56, "Black")
    for i, (src, box, n, t) in enumerate(STEPS):
        x = M + (i % 2) * (PW + GAP)
        y = M + (i // 2) * (PH + bar + GAP)
        pic = fit(src, box, PW, PH) if t == "BUILD" else fill(src, box, PW, PH)
        img.paste(pic, (x, y))
        frame(d, x, y, PW, PH)
        cy = y + PH + 22
        d.ellipse([x, cy, x + 62, cy + 62], fill=YELLOW)
        d.text((x + 31, cy + 31), n, font=num, fill=PAGE, anchor="mm")
        d.text((x + 84, cy + 31), t, font=title, fill=TEXT, anchor="lm")
    return img


def features():
    img = Image.new("RGB", (W, M + PH + 150 + M - 20), PAGE)
    d = ImageDraw.Draw(img)
    title, line = font(56, "Black"), font(34, "Medium")
    for i, (src, box, t, s) in enumerate(CARDS):
        x = M + i * (PW + GAP)
        pic = fit(src, box, PW, PH) if t == "WAR STATISTICS" else fill(src, box, PW, PH)
        img.paste(pic, (x, M))
        frame(d, x, M, PW, PH)
        d.text((x, M + PH + 24), t, font=title, fill=TEXT)
        d.text((x, M + PH + 94), s, font=line, fill=MUTED)
    return img


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else ITCH
    os.makedirs(out, exist_ok=True)
    how_it_plays().save(os.path.join(out, "how-it-plays.png"))
    features().save(os.path.join(out, "features.png"))
    print("wrote how-it-plays.png and features.png to", out)
