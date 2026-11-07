"""The Strike Alert logo: a drone caught in an air-defence reticle, and the name.

    python tools/itch_logo2.py itch

writes logo-v2.png (the emblem and the name, transparent) and logo-v2-icon.png
(the emblem alone, square). Drawn at four times the size and scaled down.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "assets", "fonts", "Inter.ttf")
WHITE = (0xF2, 0xF3, 0xF5)
RED = (0xE8, 0x4B, 0x3C)
K = 4  # supersampling


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def capsule(a, b, r0, r1, n=24):
    """A tapered bar from a (radius r0) to b (radius r1) with round ends, as a polygon."""
    ang = math.atan2(b[1] - a[1], b[0] - a[0])
    pts = []
    for t in range(n + 1):
        q = ang + math.pi / 2 + math.pi * t / n
        pts.append((b[0] + math.cos(q - math.pi) * r1, b[1] + math.sin(q - math.pi) * r1))
    for t in range(n + 1):
        q = ang + math.pi / 2 + math.pi * t / n
        pts.append((a[0] + math.cos(q) * r0, a[1] + math.sin(q) * r0))
    return pts


# A delta-wing attack drone from below, nose along +x, 2 long and about 1.5 across: the
# body runs well ahead of the wing to a blunt nose, fins stand at the wingtips, a pusher
# propeller at the back.
SHAHED = [
    [(1.0, 0), (0.95, -0.075), (0.78, -0.105), (0.3, -0.105), (-0.56, -0.74), (-0.74, -0.74),
     (-0.68, -0.11), (-0.86, -0.08), (-0.86, 0.08), (-0.68, 0.11), (-0.74, 0.74), (-0.56, 0.74),
     (0.3, 0.105), (0.78, 0.105), (0.95, 0.075)],
    [(-0.47, -0.69), (-0.47, -0.8), (-0.8, -0.8), (-0.8, -0.69)],  # wingtip fins
    [(-0.47, 0.69), (-0.47, 0.8), (-0.8, 0.8), (-0.8, 0.69)],
    [(-0.85, -0.21), (-0.85, 0.21), (-0.92, 0.21), (-0.92, -0.21)],  # the propeller
]


def drone(size, angle):
    """The drone as polygons, nose along `angle` (degrees, screen), `size` its length in pixels."""
    L = size / 2
    c, s = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    return [[(x * L * c - y * L * s, x * L * s + y * L * c) for x, y in p] for p in SHAHED]


def emblem(d, cx, cy, r):
    """The reticle: a red ring with ticks and a gap at each quarter, the drone inside."""
    w = r * 0.12
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=RED, width=int(w))
    for k in range(4):
        a = math.radians(90 * k)
        x0, y0 = cx + math.cos(a) * (r + w * 0.9), cy + math.sin(a) * (r + w * 0.9)
        x1, y1 = cx + math.cos(a) * r * 0.74, cy + math.sin(a) * r * 0.74
        d.line([(x0, y0), (x1, y1)], fill=RED, width=int(w * 0.8))
    for part in drone(r * 1.5, -45):
        d.polygon([(cx + x, cy + y) for x, y in part], fill=WHITE)


def logo():
    h = 360 * K
    r = h * 0.38
    name, alert = "STRIKE ", "ALERT"
    f = font(int(h * 0.54), "Black")
    tw = f.getlength(name) + f.getlength(alert)
    gap = h * 0.16
    w = int(h + gap + tw + h * 0.04)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    emblem(d, h / 2, h / 2, r)
    x = h + gap
    d.text((x, h * 0.53), name, font=f, fill=WHITE, anchor="lm")
    d.text((x + f.getlength(name), h * 0.53), alert, font=f, fill=RED, anchor="lm")
    return img.resize((w // K, h // K), Image.LANCZOS)


def icon():
    n = 512 * K
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    emblem(ImageDraw.Draw(img), n / 2, n / 2, n * 0.4)
    return img.resize((512, 512), Image.LANCZOS)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "itch")
    logo().save(os.path.join(out, "logo-v2.png"))
    icon().save(os.path.join(out, "logo-v2-icon.png"))
    print("wrote logo-v2.png and logo-v2-icon.png to", out)
