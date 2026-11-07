"""Three images for the itch.io page, 1600 px wide like the other section images:
discord-banner.png (join the Discord), socials-banner.png (YouTube, Instagram,
TikTok, Telegram) and whats-next.png (the teaser for the next game).

    python tools/itch_socials.py itch

The platform icons are simple drawings of each platform's mark, made here.
"""
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "assets", "fonts", "Inter.ttf")
ART = os.path.join(ROOT, "itch", "cover-pixel.png")
PAGE = (0x10, 0x12, 0x18)
PANEL = (0x1A, 0x1D, 0x24)
TEXT = (0xEE, 0xF0, 0xF3)
MUTED = (0x9A, 0xA0, 0xAC)
RED = (0xE8, 0x4B, 0x3C)
BLURPLE = (0x58, 0x65, 0xF2)
SS = 4      # icons are drawn this many times bigger, then scaled down (smooth edges)


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


# --- icons (each returns an RGBA image `size` px square) -----------------------------------

def _canvas(size):
    n = size * SS
    return Image.new("RGBA", (n, n), (0, 0, 0, 0)), n


def _done(img, size):
    return img.resize((size, size), Image.LANCZOS)


def _rounded_mask(n, r):
    m = Image.new("L", (n, n), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, n - 1, n - 1], radius=r, fill=255)
    return m


def icon_youtube(size):
    img, n = _canvas(size)
    d = ImageDraw.Draw(img)
    h = n * 0.70
    y0 = (n - h) / 2
    d.rounded_rectangle([0, y0, n - 1, y0 + h], radius=n * 0.22, fill=(0xFF, 0x00, 0x00))
    c = n / 2
    d.polygon([(c - n * 0.12, c - n * 0.15), (c - n * 0.12, c + n * 0.15), (c + n * 0.15, c)], fill=(255, 255, 255))
    return _done(img, size)


def icon_instagram(size):
    img, n = _canvas(size)
    # The warm-to-purple gradient, from the bottom left to the top right.
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32) / n
    t = np.clip((xs + (1 - ys)) / 2, 0, 1)
    stops = [(0.0, (0xFE, 0xDA, 0x75)), (0.3, (0xFA, 0x7E, 0x1E)), (0.55, (0xD6, 0x29, 0x76)),
             (0.8, (0x96, 0x2F, 0xBF)), (1.0, (0x4F, 0x5B, 0xD5))]
    col = np.stack([np.interp(t, [s[0] for s in stops], [s[1][c] for s in stops]) for c in range(3)], -1)
    g = Image.fromarray(col.astype(np.uint8), "RGB").convert("RGBA")
    g.putalpha(_rounded_mask(n, n * 0.24))
    d = ImageDraw.Draw(g)
    w = n * 0.075
    m = n * 0.2
    d.rounded_rectangle([m, m, n - m, n - m], radius=n * 0.17, outline=(255, 255, 255), width=round(w))
    c = n / 2
    r = n * 0.145
    d.ellipse([c - r, c - r, c + r, c + r], outline=(255, 255, 255), width=round(w))
    r2 = n * 0.045
    d.ellipse([n * 0.69 - r2, n * 0.31 - r2, n * 0.69 + r2, n * 0.31 + r2], fill=(255, 255, 255))
    return _done(g, size)


# The Discord and TikTok marks as vector outlines (24 x 24 units, as in the Simple Icons set),
# filled here, because their curves are too fiddly to draw from circles and boxes.
DISCORD_D = ("M20.317 4.3698a19.7913 19.7913 0 00-4.8851-1.5152.0741.0741 0 00-.0785.0371c-.211.3753-.4447.8648"
             "-.6083 1.2495-1.8447-.2762-3.68-.2762-5.4868 0-.1636-.3933-.4058-.8742-.6177-1.2495a.077.077 0 00"
             "-.0785-.037 19.7363 19.7363 0 00-4.8852 1.515.0699.0699 0 00-.0321.0277C.5334 9.0458-.319 13.5799"
             ".0992 18.0578a.0824.0824 0 00.0312.0561c2.0528 1.5076 4.0413 2.4228 5.9929 3.0294a.0777.0777 0 00"
             ".0842-.0276c.4616-.6304.8731-1.2952 1.226-1.9942a.076.076 0 00-.0416-.1057c-.6528-.2476-1.2743-.5495"
             "-1.8722-.8923a.077.077 0 01-.0076-.1277c.1258-.0943.2517-.1923.3718-.2914a.0743.0743 0 01.0776-.0105"
             "c3.9278 1.7933 8.18 1.7933 12.0614 0a.0739.0739 0 01.0785.0095c.1202.099.246.1981.3728.2924a.077.077"
             " 0 01-.0066.1276 12.2986 12.2986 0 01-1.873.8914.0766.0766 0 00-.0407.1067c.3604.698.7719 1.3628"
             " 1.225 1.9932a.076.076 0 00.0842.0286c1.961-.6067 3.9495-1.5219 6.0023-3.0294a.077.077 0 00.0313"
             "-.0552c.5004-5.177-.8382-9.6739-3.5485-13.6604a.061.061 0 00-.0312-.0286zM8.02 15.3312c-1.1825 0"
             "-2.1569-1.0857-2.1569-2.419 0-1.3332.9555-2.4189 2.157-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419"
             " 0 1.3332-.9555 2.4189-2.1569 2.4189zm7.9748 0c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9554"
             "-2.4189 2.1569-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.946 2.4189-2.1568 2.4189Z")
TIKTOK_D = ("M12.525.02c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03"
            "c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79"
            "-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71"
            "-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96"
            "-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82"
            " 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01"
            "-8.05.02-12.07z")

_NUM = re.compile(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")
_ARGS = {"M": 2, "L": 2, "T": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "A": 7, "Z": 0}


def _svg_tokens(d):
    """(command, numbers) pairs; arc flags may be written as bare digits with no gaps."""
    pos = [0]

    def skip():
        while pos[0] < len(d) and d[pos[0]] in " ,\t\r\n":
            pos[0] += 1

    def number():
        skip()
        m = _NUM.match(d, pos[0])
        pos[0] = m.end()
        return float(m.group())

    def flag():
        skip()
        c = d[pos[0]]
        pos[0] += 1
        return float(c)

    out, cmd = [], None
    while True:
        skip()
        if pos[0] >= len(d):
            return out
        if d[pos[0]].isalpha():
            cmd = d[pos[0]]
            pos[0] += 1
        elif cmd in ("M", "m"):
            cmd = "L" if cmd == "M" else "l"     # numbers after a move are lines
        up = cmd.upper()
        if up == "Z":
            out.append((cmd, []))
        elif up == "A":
            out.append((cmd, [number(), number(), number(), flag(), flag(), number(), number()]))
        else:
            out.append((cmd, [number() for _ in range(_ARGS[up])]))


def _arc(x1, y1, rx, ry, phi, large, sweep, x2, y2):
    """Points along an SVG arc (endpoint form), after the SVG spec's conversion to centre form."""
    if rx == 0 or ry == 0:
        return [(x2, y2)]
    phi = math.radians(phi)
    c, s = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    xp, yp = c * dx + s * dy, -s * dx + c * dy
    rx, ry = abs(rx), abs(ry)
    lam = xp * xp / (rx * rx) + yp * yp / (ry * ry)
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = rx * rx * ry * ry - rx * rx * yp * yp - ry * ry * xp * xp
    den = rx * rx * yp * yp + ry * ry * xp * xp
    k = math.sqrt(max(0.0, num / den)) if den else 0.0
    if large == sweep:
        k = -k
    cxp, cyp = k * rx * yp / ry, -k * ry * xp / rx
    cx, cy = c * cxp - s * cyp + (x1 + x2) / 2, s * cxp + c * cyp + (y1 + y2) / 2
    a1 = math.atan2((yp - cyp) / ry, (xp - cxp) / rx)
    a2 = math.atan2((-yp - cyp) / ry, (-xp - cxp) / rx)
    da = a2 - a1
    if sweep and da < 0:
        da += 2 * math.pi
    elif not sweep and da > 0:
        da -= 2 * math.pi
    n = max(4, int(abs(da) / (math.pi / 24)))
    return [(c * rx * math.cos(a1 + da * j / n) - s * ry * math.sin(a1 + da * j / n) + cx,
             s * rx * math.cos(a1 + da * j / n) + c * ry * math.sin(a1 + da * j / n) + cy) for j in range(1, n + 1)]


def svg_outlines(d):
    """The path's closed outlines as lists of points, in the path's own units."""
    shapes, cur = [], []
    x = y = sx = sy = 0.0
    last_ctrl, last_cmd = (0.0, 0.0), ""
    for cmd, a in _svg_tokens(d):
        rel = cmd.islower()
        up = cmd.upper()
        ox, oy = (x, y) if rel else (0.0, 0.0)
        if up == "M":
            if len(cur) > 1:
                shapes.append(cur)
            x, y = ox + a[0], oy + a[1]
            sx, sy = x, y
            cur = [(x, y)]
        elif up == "L":
            x, y = ox + a[0], oy + a[1]
            cur.append((x, y))
        elif up == "H":
            x = (x if rel else 0.0) + a[0]
            cur.append((x, y))
        elif up == "V":
            y = (y if rel else 0.0) + a[0]
            cur.append((x, y))
        elif up in ("C", "S"):
            if up == "C":
                c1 = (ox + a[0], oy + a[1])
                c2, e = (ox + a[2], oy + a[3]), (ox + a[4], oy + a[5])
            else:
                c1 = (2 * x - last_ctrl[0], 2 * y - last_ctrl[1]) if last_cmd in ("C", "S") else (x, y)
                c2, e = (ox + a[0], oy + a[1]), (ox + a[2], oy + a[3])
            for j in range(1, 17):
                t = j / 16
                u = 1 - t
                cur.append((u ** 3 * x + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t ** 3 * e[0],
                            u ** 3 * y + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t ** 3 * e[1]))
            last_ctrl = c2
            x, y = e
        elif up == "A":
            ex, ey = ox + a[5], oy + a[6]
            cur += _arc(x, y, a[0], a[1], a[2], int(a[3]), int(a[4]), ex, ey)
            x, y = ex, ey
        elif up == "Z":
            if len(cur) > 1:
                shapes.append(cur)
            x, y = sx, sy
            cur = [(x, y)]
        last_cmd = up
    if len(cur) > 1:
        shapes.append(cur)
    return shapes


def svg_mask(d, n, box):
    """A 24-unit path filled even-odd into an n x n mask, scaled into box = (x0, y0, side)."""
    x0, y0, side = box
    k = side / 24.0
    acc = np.zeros((n, n), bool)
    for shape in svg_outlines(d):
        m = Image.new("1", (n, n), 0)
        ImageDraw.Draw(m).polygon([(x0 + px * k, y0 + py * k) for px, py in shape], fill=1)
        acc ^= np.asarray(m, bool)
    return Image.fromarray((acc * 255).astype(np.uint8), "L")


def _glyph(mask, colour, n):
    lay = Image.new("RGBA", (n, n), colour + (255,))
    lay.putalpha(mask)
    return lay


def icon_tiktok(size):
    img, n = _canvas(size)
    base = Image.new("RGBA", (n, n), (0x0F, 0x0F, 0x12, 255))
    side = n * 0.56
    m = svg_mask(TIKTOK_D, n, ((n - side) / 2 + n * 0.01, (n - side) / 2, side))
    o = round(n * 0.022)
    base.alpha_composite(_glyph(m, (0x25, 0xF4, 0xEE), n), (-o, -o))
    base.alpha_composite(_glyph(m, (0xFE, 0x2C, 0x55), n), (o, o))
    base.alpha_composite(_glyph(m, (255, 255, 255), n))
    base.putalpha(_rounded_mask(n, n * 0.24))
    return _done(base, size)


def icon_telegram(size):
    img, n = _canvas(size)
    d = ImageDraw.Draw(img)
    d.ellipse([0, 0, n - 1, n - 1], fill=(0x2A, 0xAB, 0xEE))
    p = lambda x, y: (x * n, y * n)
    d.polygon([p(0.22, 0.49), p(0.75, 0.28), p(0.66, 0.72), p(0.51, 0.61), p(0.43, 0.70), p(0.42, 0.58)],
              fill=(255, 255, 255))
    d.polygon([p(0.42, 0.58), p(0.66, 0.37), p(0.44, 0.60)], fill=(0xC8, 0xDA, 0xEA))
    d.polygon([p(0.42, 0.58), p(0.43, 0.70), p(0.47, 0.635)], fill=(0xD2, 0xE4, 0xF2))
    return _done(img, size)


def icon_discord(size):
    img, n = _canvas(size)
    base = Image.new("RGBA", (n, n), BLURPLE + (255,))
    base.putalpha(_rounded_mask(n, n * 0.24))
    side = n * 0.62
    m = svg_mask(DISCORD_D, n, ((n - side) / 2, (n - side) / 2 + n * 0.005, side))
    base.alpha_composite(_glyph(m, (255, 255, 255), n))
    return _done(base, size)


# --- pieces ---------------------------------------------------------------------------------

def art_strip(w, h, y_mid, dark=0.0, blur=0):
    """The cover art scaled to width w, cropped to h around y_mid (in the art's own pixels)."""
    src = Image.open(ART).convert("RGB")
    s = w / src.width
    sh = h / s
    y0 = min(max(y_mid - sh / 2, 0), src.height - sh)
    img = src.resize((w, h), Image.LANCZOS, box=(0, y0, src.width, y0 + sh))
    if blur:
        img = img.filter(ImageFilter.GaussianBlur(blur))
    if dark:
        img = Image.blend(img, Image.new("RGB", (w, h), PAGE), dark)
    return img


def h_fade(w, h, x0, x1, a0, a1):
    """A PAGE-coloured overlay whose opacity goes from a0 at x0 to a1 at x1."""
    xs = np.clip((np.arange(w, dtype=np.float32) - x0) / max(1, x1 - x0), 0, 1)
    xs = xs * xs * (3 - 2 * xs)
    a = (a0 + (a1 - a0) * xs) * 255
    lay = Image.new("RGBA", (w, h), PAGE + (0,))
    lay.putalpha(Image.fromarray(np.repeat(a[None, :], h, 0).astype(np.uint8)))
    return lay


def pill(d, x, y, text, f, fill, fg=(255, 255, 255), anchor="lm"):
    l, t, r, b = f.getbbox(text)
    hgt = round(f.size * 2.0)
    w = r - l + hgt
    x0 = x if anchor == "lm" else x - w / 2
    d.rounded_rectangle([x0, y - hgt / 2, x0 + w, y + hgt / 2], radius=hgt / 2, fill=fill)
    d.text((x0 + w / 2, y), text, font=f, fill=fg, anchor="mm")
    return w


def border(img, colour=(0x33, 0x38, 0x42, 255)):
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, img.width - 1, img.height - 1], outline=colour, width=2)


# --- the images -----------------------------------------------------------------------------

def discord_banner():
    W, H = 1600, 400
    img = art_strip(W, H, 520).convert("RGBA")
    img.alpha_composite(h_fade(W, H, 560, 1250, 0.96, 0.15))
    d = ImageDraw.Draw(img)
    ic = icon_discord(170)
    img.alpha_composite(ic, (90, (H - 170) // 2))
    x = 310
    d.text((x, 128), "JOIN THE DISCORD", font=font(76, "Black"), fill=TEXT, anchor="lm")
    d.text((x, 200), "Tactics, bug reports and new builds first", font=font(34, "SemiBold"), fill=MUTED, anchor="lm")
    pill(d, x, 284, "discord.gg/Zf6rerfAu", font(32, "Bold"), BLURPLE)
    border(img)
    return img.convert("RGB")


def socials_banner():
    W, H = 1600, 400
    img = art_strip(W, H, 430, dark=0.72, blur=10).convert("RGBA")
    d = ImageDraw.Draw(img)
    d.text((W / 2, 78), "FOLLOW THE DEVELOPMENT", font=font(52, "Black"), fill=TEXT, anchor="mm")
    items = [("YouTube", icon_youtube), ("Instagram", icon_instagram), ("TikTok", icon_tiktok), ("Telegram", icon_telegram)]
    tw, th, gap = 330, 210, 40
    x0 = (W - (4 * tw + 3 * gap)) / 2
    y0 = 140
    f = font(36, "Bold")
    for i, (name, fn) in enumerate(items):
        x = x0 + i * (tw + gap)
        tile = Image.new("RGBA", (tw, th), PANEL + (215,))
        td = ImageDraw.Draw(tile)
        mask = Image.new("L", (tw, th), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, tw - 1, th - 1], radius=26, fill=215)
        tile.putalpha(mask)
        ImageDraw.Draw(tile).rounded_rectangle([0, 0, tw - 1, th - 1], radius=26, outline=(255, 255, 255, 30), width=2)
        img.alpha_composite(tile, (round(x), y0))
        ic = fn(104)
        img.alpha_composite(ic, (round(x + (tw - 104) / 2), y0 + 26))
        d.text((x + tw / 2, y0 + 172), name, font=f, fill=TEXT, anchor="mm")
    border(img)
    return img.convert("RGB")


def _noise(w, h, seed, scales):
    """Smooth random terrain: a few layers of upscaled random grids."""
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for s in scales:
        g = rng.random((max(2, h // s + 2), max(2, w // s + 2))).astype(np.float32)
        layer = np.asarray(Image.fromarray(g, "F").resize((w + 2 * s, h + 2 * s), Image.BICUBIC))[s:s + h, s:s + w]
        out += layer * amp
        tot += amp
        amp *= 0.5
    return out / tot


# A delta-wing attack drone seen from below, nose along +y, half-span 1 (x, y).
DRONE = [(0.0, 1.0), (0.06, 0.93), (0.085, 0.80), (0.10, 0.56), (1.0, -0.43), (1.0, -0.62), (0.16, -0.48),
         (0.085, -0.60), (0.0, -0.64)]


def whats_next():
    """One drone seen through a thermal camera (white-hot), with a few tracking marks, and
    the teaser text on the left: simple, serious, and still drones and missiles."""
    W, H = 1600, 900
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    # The sky, warmer (lighter) towards the horizon, with faint cloud.
    v = 0.17 + 0.13 * (ys / H) ** 1.6 + (_noise(W, H, 3, [420, 210, 105]) - 0.5) * 0.08
    # The drone.
    cx, cy, span, head = 1200.0, 410.0, 165.0, math.radians(-28)
    ch, sh = math.cos(head), math.sin(head)

    def to_screen(x, y):
        px, py = x * span, -y * span * 0.9
        return (cx + px * ch - py * sh, cy + px * sh + py * ch)

    outline = DRONE + [(-x, y) for x, y in reversed(DRONE[1:-1])]
    big = Image.new("L", (W * 2, H * 2), 0)
    dd = ImageDraw.Draw(big)
    dd.polygon([tuple(c * 2 for c in to_screen(x, y)) for x, y in outline], fill=255)
    for s in (1, -1):        # the fins at the wing tips, a little warmer
        dd.polygon([tuple(c * 2 for c in to_screen(s * x, y)) for x, y in [(0.97, -0.62), (1.03, -0.62), (1.03, -0.30), (0.97, -0.30)]],
                   fill=255)
    body = np.asarray(big.resize((W, H), Image.LANCZOS).filter(ImageFilter.GaussianBlur(1.4)), np.float32) / 255
    # The engine at the tail, white hot, and its exhaust trailing behind; the airframe is
    # warmest near the engine and cooler towards the nose and the wing tips.
    ex, ey = to_screen(0.0, -0.66)
    r2 = (xs - ex) ** 2 + (ys - ey) ** 2
    warm = 0.50 + 0.20 * np.exp(-r2 / (2 * (span * 0.55) ** 2))
    warm += (_noise(W, H, 21, [24, 12]) - 0.5) * 0.05
    v = v * (1 - body) + warm * body
    v += 0.55 * np.exp(-r2 / (2 * 9.0 ** 2))
    back = np.array(to_screen(0.0, -1.66)) - np.array([ex, ey])
    back /= np.linalg.norm(back)
    along = (xs - ex) * back[0] + (ys - ey) * back[1]
    across = (xs - ex) * -back[1] + (ys - ey) * back[0]
    plume = np.exp(-np.clip(along, 0, None) / 150) * np.exp(-across ** 2 / (2 * (6 + 0.12 * np.clip(along, 0, None)) ** 2))
    v += 0.16 * plume * (along > 0)
    # Bloom round the hottest parts, sensor grain, faint scan lines, a vignette.
    hot = Image.fromarray((np.clip(v - 0.75, 0, 0.5) * 510).astype(np.uint8), "L")
    v += 0.5 * np.asarray(hot.filter(ImageFilter.GaussianBlur(16)), np.float32) / 510
    v += np.random.default_rng(9).normal(0, 0.02, (H, W)).astype(np.float32)
    v += 0.008 * np.sin(ys * math.pi)
    v *= 1 - 0.32 * np.clip(((xs - W / 2) / (W * 0.6)) ** 2 + ((ys - H / 2) / (H * 0.6)) ** 2, 0, 1)
    rgb = np.clip(v, 0, 1)[..., None] * np.array([0.95, 0.975, 1.0], np.float32)
    img = Image.fromarray((rgb * 255).astype(np.uint8), "RGB").convert("RGBA")
    # Dark on the left for the text.
    img.alpha_composite(h_fade(W, H, 260, 1000, 0.93, 0.0))
    d = ImageDraw.Draw(img)
    # Tracking marks: a crosshair on the drone and corner brackets round it.
    hud = (255, 255, 255, 190)
    mx, my = to_screen(0.0, 0.1)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        d.line([(mx + dx * 16, my + dy * 16), (mx + dx * 44, my + dy * 44)], fill=hud, width=2)
    pts = [to_screen(x, y) for x, y in outline]
    x0, x1 = min(p[0] for p in pts) - 34, max(p[0] for p in pts) + 34
    y0, y1 = min(p[1] for p in pts) - 34, max(p[1] for p in pts) + 34
    k = 38
    for bx, by, sx, sy in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
        d.line([(bx, by + sy * k), (bx, by), (bx + sx * k, by)], fill=hud, width=3)
    small = font(24, "SemiBold")
    d.text((W - 56, 52), "WHT   NFOV   x12", font=small, fill=(255, 255, 255, 150), anchor="rm")
    d.text((W - 56, H - 52), "TRK   AZ 047.3   EL 11.8", font=small, fill=(255, 255, 255, 150), anchor="rm")
    d.text((x0, y0 - 22), "TRACK 01", font=small, fill=(255, 255, 255, 170), anchor="lm")
    # The words.
    x = 96
    pill(d, x, 300, "IN DEVELOPMENT", font(26, "Black"), RED)
    d.text((x, 405), "WHAT'S NEXT?", font=font(104, "Black"), fill=TEXT, anchor="lm")
    d.text((x, 502), "A new game about drones and missiles", font=font(44, "SemiBold"), fill=TEXT, anchor="lm")
    d.text((x, 564), "More realistic. More serious.", font=font(42, "Medium"), fill=MUTED, anchor="lm")
    border(img)
    return img.convert("RGB")


# One button per platform, so each can carry its own link on the itch page.
# (file name, icon, the line on the button, the platform's colour for the edge)
BUTTONS = [
    ("youtube", icon_youtube, "Subscribe on YouTube", (0xFF, 0x00, 0x00)),
    ("instagram", icon_instagram, "Follow on Instagram", (0xD6, 0x29, 0x76)),
    ("tiktok", icon_tiktok, "Follow on TikTok", (0x25, 0xF4, 0xEE)),
    ("telegram", icon_telegram, "Join on Telegram", (0x2A, 0xAB, 0xEE)),
    ("discord", icon_discord, "Join the Discord", BLURPLE),
]
BW, BH = 480, 104          # the size it shows at on the page


def button(icon_fn, label, accent):
    """Drawn twice the size, then halved, for smooth edges."""
    w, h = BW * 2, BH * 2
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=40, fill=255)
    body = Image.new("RGBA", (w, h), PANEL + (255,))
    # A soft glow of the platform's colour from the left.
    xs = np.linspace(0, 1, w, dtype=np.float32)
    glow = np.clip(1 - xs / 0.55, 0, 1) ** 2 * 0.22
    tint = Image.new("RGBA", (w, h), accent + (0,))
    tint.putalpha(Image.fromarray(np.repeat((glow * 255)[None, :], h, 0).astype(np.uint8)))
    body.alpha_composite(tint)
    body.putalpha(mask)
    img.alpha_composite(body)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([1, 1, w - 2, h - 2], radius=40, outline=(255, 255, 255, 34), width=3)
    ic = icon_fn(120)
    img.alpha_composite(ic, (44, (h - 120) // 2))
    d.text((200, h / 2), label, font=font(50, "Bold"), fill=TEXT, anchor="lm")
    # An arrow on the right: it's a link.
    ax, ay = w - 70, h / 2
    d.line([(ax - 30, ay), (ax + 6, ay)], fill=MUTED, width=8)
    d.line([(ax - 12, ay - 20), (ax + 8, ay), (ax - 12, ay + 20)], fill=MUTED, width=8, joint="curve")
    return img.resize((BW, BH), Image.LANCZOS)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "itch")
    for name, fn in (("discord-banner", discord_banner), ("socials-banner", socials_banner), ("whats-next", whats_next)):
        path = os.path.join(out, name + ".png")
        fn().save(path, optimize=True)
        print("wrote", path)
    bdir = os.path.join(out, "buttons")
    os.makedirs(bdir, exist_ok=True)
    made = []
    for name, icon_fn, label, accent in BUTTONS:
        b = button(icon_fn, label, accent)
        b.save(os.path.join(bdir, "button-%s.png" % name), optimize=True)
        made.append(b)
    # How they look stacked on the page, for checking.
    sheet = Image.new("RGBA", (BW + 60, len(made) * (BH + 14) + 46), PAGE + (255,))
    for i, b in enumerate(made):
        sheet.alpha_composite(b, (30, 30 + i * (BH + 14)))
    sheet.convert("RGB").save(os.path.join(bdir, "all-buttons-preview.png"))
    print("wrote", bdir)
    # A sheet of the icons, for checking them.
    if "--icons" in sys.argv:
        sheet = Image.new("RGBA", (5 * 220, 220), PAGE + (255,))
        for i, fn in enumerate((icon_youtube, icon_instagram, icon_tiktok, icon_telegram, icon_discord)):
            sheet.alpha_composite(fn(180), (20 + i * 220, 20))
        sheet.save(os.path.join(out, "icons-check.png"))


if __name__ == "__main__":
    main()
