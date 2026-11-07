"""The Strike Alert logo: a radar roundel with a drone diving in and an
interceptor rising to meet it, beside the wordmark.

    python tools/itch_logo.py itch

writes logo.png (the mark and wordmark, cropped to fit) and logo-icon.png (the
mark alone, 512x512), both on a transparent background.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "assets", "fonts", "Inter.ttf")
PAGE = (0x16, 0x18, 0x1D)
TEXT = (0xE8, 0xEA, 0xEE)
RED = (0xE0, 0x57, 0x4A)
ENEMY = (0xFF, 0x5A, 0x48)
BLUE = (0x4E, 0xA1, 0xFF)
YELLOW = (0xE5, 0xAD, 0x16)
# The game's drone glyph (LiteGlyphs.DRONE_PTS), nose along +x.
DRONE = [(6, 0), (-4, -5.5), (-2, 0), (-4, 5.5)]
SS = 4  # drawn this many times larger, then scaled down for smooth edges


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def mark(size):
    M = size * SS
    img = Image.new("RGBA", (M, M), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    c = M / 2

    def at(fx, fy):
        return (fx * M, fy * M)

    # The roundel: dark disc, red rim, radar rings and cross.
    r = 0.47 * M
    d.ellipse([c - r, c - r, c + r, c + r], fill=PAGE + (255,), outline=RED + (255,), width=round(0.04 * M))
    for k in (0.33, 0.21, 0.09):
        rr = k * M
        d.ellipse([c - rr, c - rr, c + rr, c + rr], outline=BLUE + (95,), width=round(0.012 * M))
    t = round(0.008 * M)
    d.line([at(0.13, 0.5), at(0.87, 0.5)], fill=BLUE + (60,), width=t)
    d.line([at(0.5, 0.13), at(0.5, 0.87)], fill=BLUE + (60,), width=t)

    # The drone's dotted trail, from the rim towards the centre.
    head = (0.645, 0.355)
    tail = (0.84, 0.16)
    for i in range(6):
        u = i / 6
        x = tail[0] + (head[0] - tail[0]) * u * 0.78
        y = tail[1] + (head[1] - tail[1]) * u * 0.78
        rd = (0.010 + 0.006 * u) * M
        d.ellipse([x * M - rd, y * M - rd, x * M + rd, y * M + rd], fill=ENEMY + (int(110 + 120 * u),))

    # The interceptor rising from the lower left, with its glow ahead of it.
    p0, p1 = at(0.27, 0.77), at(0.52, 0.48)
    d.line([p0, p1], fill=BLUE + (255,), width=round(0.026 * M))
    g = 0.05 * M
    d.ellipse([p1[0] - g, p1[1] - g, p1[0] + g, p1[1] + g], fill=YELLOW + (255,))
    g2 = 0.022 * M
    d.ellipse([p1[0] - g2, p1[1] - g2, p1[0] + g2, p1[1] + g2], fill=(255, 245, 210, 255))

    # The drone, diving at the centre.
    ang = math.atan2(0.5 - head[1], 0.5 - head[0])
    s = 0.027 * M
    pts = []
    for px, py in DRONE:
        x = px * math.cos(ang) - py * math.sin(ang)
        y = px * math.sin(ang) + py * math.cos(ang)
        pts.append((head[0] * M + x * s, head[1] * M + y * s))
    d.polygon(pts, fill=ENEMY + (255,), outline=PAGE + (255,), width=round(0.008 * M))
    return img.resize((size, size), Image.LANCZOS)


def spaced(d, xy, text, f, fill, spacing):
    x, y = xy
    for ch in text:
        d.text((x, y), ch, font=f, fill=fill)
        x += f.getlength(ch) + spacing
    return x


def spaced_width(text, f, spacing):
    return sum(f.getlength(ch) for ch in text) + spacing * (len(text) - 1)


def logo():
    W, H = 1900, 440
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    m = mark(380)
    img.alpha_composite(m, (20, (H - 380) // 2))
    d = ImageDraw.Draw(img)
    big = font(170, "Black")
    x0 = 450
    top = 70
    d.text((x0, top), "STRIKE", font=big, fill=TEXT)
    d.text((x0 + big.getlength("STRIKE "), top), "ALERT", font=big, fill=RED)
    word_w = big.getlength("STRIKE ALERT")
    tag = font(40, "Bold")
    text = "HOLD THE SKY · STRIKE BACK"
    sp = (word_w - spaced_width(text, tag, 0)) / (len(text) - 1)
    spaced(d, (x0 + 6, top + 205), text, tag, YELLOW, min(sp, 16))
    return img.crop(img.getbbox())


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "itch")
    os.makedirs(out, exist_ok=True)
    logo().save(os.path.join(out, "logo.png"))
    mark(512).save(os.path.join(out, "logo-icon.png"))
    print("wrote logo.png and logo-icon.png to", out)
