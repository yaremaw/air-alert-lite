"""Two picture guides for the itch.io description, 1600 px wide like the other section
images: controls.png (the keys as keycaps) and arsenal.png (each weapon and defence with
its price and what it is good at, from the game's own numbers in src/Lite/LiteRules.gd).

The page shows them at about half size, so nothing here is smaller than 30 px (about
15 px on the page) and the main words are 40 px and up.

    python tools/itch_guides.py itch
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "assets", "fonts", "Inter.ttf")
PAGE = (0x16, 0x18, 0x1D)
PANEL = (0x20, 0x24, 0x2B)
FRAME = (0x33, 0x38, 0x42)
KEY = (0x2E, 0x33, 0x3D)
KEY_EDGE = (0x10, 0x12, 0x16)
TEXT = (0xEE, 0xF0, 0xF3)
MUTED = (0xA4, 0xAA, 0xB6)
DIM = (0x3A, 0x40, 0x4B)
BLUE = (0x4E, 0xA1, 0xFF)
YELLOW = (0xE5, 0xAD, 0x16)
S = 2       # drawn twice the size, then halved, for smooth edges


def font(size, weight):
    f = ImageFont.truetype(FONT, size * S)
    f.set_variation_by_name(weight)
    return f


def finish(img):
    w, h = img.size
    out = img.convert("RGB").resize((w // S, h // S), Image.LANCZOS)
    ImageDraw.Draw(out).rectangle([0, 0, out.width - 1, out.height - 1], outline=FRAME, width=2)
    return out


def text(d, x, y, s, size, weight, fill, anchor="lm"):
    d.text((x * S, y * S), s, font=font(size, weight), fill=fill, anchor=anchor)


# --- controls -------------------------------------------------------------------------------

def keycap(d, x, y, label, w=120, h=120):
    """A key with a darker lip below, so it reads as a key. (x, y) is its top-left."""
    X, Y, W, H = x * S, y * S, w * S, h * S
    d.rounded_rectangle([X, Y + 10 * S, X + W, Y + H + 10 * S], radius=20 * S, fill=KEY_EDGE)
    d.rounded_rectangle([X, Y, X + W, Y + H], radius=20 * S, fill=KEY, outline=(0x44, 0x4A, 0x57), width=2 * S)
    d.text((X + W / 2, Y + H / 2), label, font=font(56 if len(label) == 1 else 38, "Bold"), fill=TEXT, anchor="mm")


def mouse(d, x, y):
    X, Y = x * S, y * S
    w, h = 84 * S, 124 * S
    d.rounded_rectangle([X, Y, X + w, Y + h], radius=42 * S, outline=TEXT, width=5 * S)
    d.line([(X + w / 2, Y + 5 * S), (X + w / 2, Y + 50 * S)], fill=TEXT, width=5 * S)
    d.line([(X + 5 * S, Y + 50 * S), (X + w - 5 * S, Y + 50 * S)], fill=TEXT, width=5 * S)
    d.rounded_rectangle([X + w / 2 - 6 * S, Y + 16 * S, X + w / 2 + 6 * S, Y + 36 * S], radius=6 * S, fill=TEXT)


def controls():
    W, H = 1600, 640
    img = Image.new("RGB", (W * S, H * S), PAGE)
    d = ImageDraw.Draw(img)
    for y, keys, title, line, colour in ((60, ["1", "2", "3"], "BUILD", "Factory · AA gun · SAM", YELLOW),
                                         (240, ["Q", "W", "E"], "STRIKE", "Drone · Cruise · Ballistic", BLUE)):
        x = 90
        for k in keys:
            keycap(d, x, y, k)
            x += 140
        text(d, x + 30, y + 36, title, 34, "Black", colour)
        text(d, x + 30, y + 88, line, 46, "SemiBold", TEXT)
    y = 445
    mouse(d, 108, y - 2)
    text(d, 222, y + 60, "Build, aim", 44, "SemiBold", TEXT)
    keycap(d, 560, y, "SPACE", w=240)
    text(d, 830, y + 60, "Pause", 44, "SemiBold", TEXT)
    keycap(d, 1130, y, "T")
    text(d, 1280, y + 60, "Statistics", 44, "SemiBold", TEXT)
    return finish(img)


# --- arsenal --------------------------------------------------------------------------------

def _poly(d, pts, x, y, k, fill):
    d.polygon([((x + px * k) * S, (y + py * k) * S) for px, py in pts], fill=fill)


def glyph(d, kind, x, y, k, colour):
    """Small white silhouettes, (x, y) the centre, k about the half-width."""
    if kind == "drone":
        pts = [(1.0, 0.0), (0.88, 0.06), (0.56, 0.10), (-0.43, 1.0), (-0.62, 1.0), (-0.48, 0.16), (-0.64, 0.0)]
        _poly(d, pts + [(px, -py) for px, py in reversed(pts[1:-1])], x, y, k, colour)
    elif kind == "cruise":
        _poly(d, [(1.0, 0), (0.8, -0.1), (-0.9, -0.1), (-0.9, 0.1), (0.8, 0.1)], x, y, k, colour)
        _poly(d, [(0.15, -0.1), (-0.1, -0.55), (-0.25, -0.55), (-0.15, -0.1)], x, y, k, colour)
        _poly(d, [(0.15, 0.1), (-0.1, 0.55), (-0.25, 0.55), (-0.15, 0.1)], x, y, k, colour)
        _poly(d, [(-0.7, -0.1), (-0.95, -0.35), (-1.0, -0.35), (-0.95, -0.1)], x, y, k, colour)
        _poly(d, [(-0.7, 0.1), (-0.95, 0.35), (-1.0, 0.35), (-0.95, 0.1)], x, y, k, colour)
    elif kind == "ballistic":
        a = math.radians(-50)
        body = [(1.0, 0), (0.7, -0.15), (-0.8, -0.15), (-0.8, 0.15), (0.7, 0.15)]
        fins = [(-0.5, -0.15), (-0.85, -0.4), (-1.0, -0.4), (-0.8, -0.15), (-0.8, 0.15), (-1.0, 0.4), (-0.85, 0.4), (-0.5, 0.15)]
        for pts in (body, fins):
            _poly(d, [(px * math.cos(a) - py * math.sin(a), px * math.sin(a) + py * math.cos(a)) for px, py in pts], x, y, k, colour)
    elif kind == "gun":
        _poly(d, [(-0.8, 0.8), (0.8, 0.8), (0.55, 0.3), (-0.55, 0.3)], x, y, k, colour)
        _poly(d, [(-0.35, 0.3), (0.35, 0.3), (0.3, -0.05), (-0.3, -0.05)], x, y, k, colour)
        for off in (-0.12, 0.12):
            _poly(d, [(off - 0.06, -0.05), (off + 0.06, -0.05), (off + 0.62, -0.85), (off + 0.5, -0.85)], x, y, k, colour)
    elif kind == "sam":
        _poly(d, [(-1.0, 0.75), (1.0, 0.75), (1.0, 0.45), (-1.0, 0.45)], x, y, k, colour)
        for cx in (-0.6, 0.6):
            d.ellipse([(x + (cx - 0.17) * k) * S, (y + 0.68 * k) * S, (x + (cx + 0.17) * k) * S, (y + 1.02 * k) * S], fill=colour)
        for i in range(2):
            o = i * 0.24
            _poly(d, [(-0.7 + o, 0.45), (-0.48 + o, 0.45), (0.45 + o, -0.75), (0.23 + o, -0.75)], x, y, k, colour)


def bar(d, x, y, w, frac, colour, label, value):
    """A labelled bar, (x, y) the top-left of its label."""
    text(d, x, y, label, 32, "SemiBold", MUTED, "lt")
    text(d, x + w, y, value, 32, "Bold", TEXT, "rt")
    by = y + 46
    d.rounded_rectangle([x * S, by * S, (x + w) * S, (by + 16) * S], radius=8 * S, fill=DIM)
    if frac > 0:
        d.rounded_rectangle([x * S, by * S, (x + max(16, w * frac)) * S, (by + 16) * S], radius=8 * S, fill=colour)


def chip(d, x, y, w, label, value, frac):
    """A box with the target on top and the chance below, filled up to the chance."""
    h = 104
    d.rounded_rectangle([x * S, y * S, (x + w) * S, (y + h) * S], radius=16 * S, fill=DIM)
    if frac > 0:
        fill = tuple(round(DIM[i] + (YELLOW[i] - DIM[i]) * 0.55) for i in range(3))
        d.rounded_rectangle([x * S, y * S, (x + max(32, w * frac)) * S, (y + h) * S], radius=16 * S, fill=fill)
    text(d, x + w / 2, y + 32, label, 30, "SemiBold", TEXT, "mm")
    text(d, x + w / 2, y + 72, value, 38, "Black", TEXT, "mm")


def card_head(d, x, y, w, h, kind, name, price, line, colour):
    d.rounded_rectangle([x * S, y * S, (x + w) * S, (y + h) * S], radius=26 * S, fill=PANEL, outline=FRAME, width=2 * S)
    d.rounded_rectangle([(x + 16) * S, (y + 30) * S, (x + 23) * S, (y + h - 30) * S], radius=4 * S, fill=colour)
    glyph(d, kind, x + 78, y + 74, 36, TEXT)
    text(d, x + 128, y + 74, name, 48, "Black", TEXT)
    pf = font(34, "Black")
    pw = pf.getlength(price) / S + 32
    d.rounded_rectangle([(x + w - 30 - pw) * S, (y + 52) * S, (x + w - 30) * S, (y + 96) * S], radius=22 * S, fill=YELLOW)
    d.text(((x + w - 30 - pw / 2) * S, (y + 74) * S), price, font=pf, fill=PAGE, anchor="mm")
    text(d, x + 46, y + 156, line, 34, "SemiBold", TEXT)


def arsenal():
    W, H = 1600, 1170
    img = Image.new("RGB", (W * S, H * S), PAGE)
    d = ImageDraw.Draw(img)
    text(d, 48, 46, "STRIKE", 36, "Black", BLUE)
    # Speeds 26 / 72 / 220 and damage 1 / 2 / 3, from LiteRules.
    cw, gap, top = 488, 32, 84
    for i, (kind, name, price, line, speed, sv, dmg) in enumerate([
            ("drone", "Drone", "$12", "Finds hidden sites", 26 / 220, "slow", 1),
            ("cruise", "Cruise", "$55", "Flies your route", 72 / 220, "fast", 2),
            ("ballistic", "Ballistic", "$130", "Too fast for guns", 1.0, "very fast", 3)]):
        x = 48 + i * (cw + gap)
        card_head(d, x, top, cw, 420, kind, name, price, line, BLUE)
        bar(d, x + 46, top + 220, cw - 92, speed, BLUE, "Speed", sv)
        bar(d, x + 46, top + 316, cw - 92, dmg / 3, BLUE, "Damage", str(dmg))
    y0 = top + 420 + 64
    text(d, 48, y0, "DEFEND", 36, "Black", YELLOW)
    # Hit chance a shot: SAM 90 / 80 / 45 %, AA gun 25 / 8 / 0 %; range 125 / 58.
    dw = (W - 96 - gap) // 2
    top2 = y0 + 38
    for i, (kind, name, price, line, rng, rv, hits) in enumerate([
            ("gun", "AA gun", "$70", "Cheap. Best against drones", 58 / 125, "short",
             [("drone", 0.25, "25%"), ("cruise", 0.08, "8%"), ("ballistic", 0.0, "0%")]),
            ("sam", "SAM", "$240", "6 missiles, then reloads", 1.0, "long",
             [("drone", 0.9, "90%"), ("cruise", 0.8, "80%"), ("ballistic", 0.45, "45%")])]):
        x = 48 + i * (dw + gap)
        card_head(d, x, top2, dw, 510, kind, name, price, line, YELLOW)
        bar(d, x + 46, top2 + 220, dw - 92, rng, YELLOW, "Range", rv)
        text(d, x + 46, top2 + 322, "Hit chance per shot", 32, "SemiBold", MUTED, "lt")
        colw = (dw - 92 - 2 * 20) / 3
        for j, (who, frac, val) in enumerate(hits):
            cx = x + 46 + j * (colw + 20)
            chip(d, cx, top2 + 370, colw, who, val, frac)
    return finish(img)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "itch")
    for name, fn in (("controls", controls), ("arsenal", arsenal)):
        path = os.path.join(out, name + ".png")
        fn().save(path, optimize=True)
        print("wrote", path)


if __name__ == "__main__":
    main()
