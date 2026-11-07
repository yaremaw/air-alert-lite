"""The banner for the itch.io page: the game's map from our capital to theirs in the
middle of a raid, drawn in the game's own colours and glyphs. Drones come in on curving
paths, cruise missiles weave, ballistic missiles arc in from the east, our SAMs meet two
of them, an AA gun gets a drone, a factory of ours burns, and our own strike lands on
one of theirs. The logo and the tagline on the left.

    python tools/itch_banner.py itch/extra/geo itch

GEO holds ids.png and map.json exported from the game (see tools/itch_orbit.py).
Writes banner-v2.png (960x240) and banner-v2@2x.png (1920x480).
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from itch_dawn import blur, smooth  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(ROOT, "itch", "logo-v2.png")
FONT = os.path.join(ROOT, "assets", "fonts", "Inter.ttf")

W, H, K = 960, 240, 4            # the banner, and how much bigger it is drawn
S = 0.86                          # pixels per map unit
U0, V0 = 302.5 - 528 / S, 300.0 - 120 / S   # the map point at the banner's top left


def hexc(s):
    return tuple(int(s[i:i + 2], 16) for i in (1, 3, 5))


PAGE, PANEL = hexc("#16181d"), hexc("#1c1f25")
OUR_LAND, ENEMY_LAND = hexc("#3a3d46"), hexc("#24262c")
AIR, MISSILE = hexc("#d4a017"), hexc("#e0574a")
ENEMY_ALERT, ENEMY_MISSILE = hexc("#3a282c"), hexc("#4a2328")
OURS, ENEMY, YELLOW, TEXT = hexc("#4ea1ff"), hexc("#ff5a48"), hexc("#e5ad16"), hexc("#e8eaee")

AIR_REGIONS = {"Lukivska", "Sosnivska", "Hlynska", "Stepova", "Lisova", "Bilohirska"}
MISSILE_REGIONS = {"Verbohradska", "Verbohrad", "Zorianska", "Dubivska"}
STRUCK = {"Kurgal": ENEMY_MISSILE, "Kolmar": ENEMY_ALERT, "Tamsk": ENEMY_ALERT}

# The game's glyphs (src/Lite/LiteGlyphs.gd), in its units.
FACTORY = [(-5, 4), (5, 4), (5, -1), (1.7, -3.5), (1.7, -1), (-1.6, -3.5), (-1.6, -1), (-5, -3.5)]
SAM = [(0, -5.5), (1.6, -2.5), (1.6, 2.5), (3.2, 4.8), (-3.2, 4.8), (-1.6, 2.5), (-1.6, -2.5)]
DRONE = [(6, 0), (-4, -5.5), (-2, 0), (-4, 5.5)]
CRUISE = [(7, 0), (4, -1.3), (0, -1.3), (-2, -4.5), (-3.5, -4.5), (-2.5, -1.3), (-6, -1.3), (-7, -3), (-7.5, -3),
          (-7.5, 3), (-7, 3), (-6, 1.3), (-2.5, 1.3), (-3.5, 4.5), (-2, 4.5), (0, 1.3), (4, 1.3)]
STAR = [(math.cos(-math.pi / 2 + i * math.pi / 5) * (5.6 if i % 2 == 0 else 2.3),
         math.sin(-math.pi / 2 + i * math.pi / 5) * (5.6 if i % 2 == 0 else 2.3)) for i in range(10)]


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def px(u, v):
    """A map point to banner pixels (in the big drawing)."""
    return (u - U0) * S * K, (v - V0) * S * K


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def quad(a, c, b, t):
    t = np.asarray(t)[..., None]
    a, c, b = np.array(a), np.array(c), np.array(b)
    return (1 - t) ** 2 * a + 2 * t * (1 - t) * c + t ** 2 * b


def cubic(a, c1, c2, b, t):
    t = np.asarray(t)[..., None]
    a, c1, c2, b = np.array(a), np.array(c1), np.array(c2), np.array(b)
    return (1 - t) ** 3 * a + 3 * t * (1 - t) ** 2 * c1 + 3 * t ** 2 * (1 - t) * c2 + t ** 3 * b


# --- the map ----------------------------------------------------------------------------

def base_map(geo):
    ids = np.asarray(Image.open(os.path.join(geo, "ids.png")))
    data = json.load(open(os.path.join(geo, "map.json"), encoding="utf-8"))
    w, h = W * K, H * K
    us = U0 + (np.arange(w) + 0.5) / (S * K)
    vs = V0 + (np.arange(h) + 0.5) / (S * K)
    jj = np.clip((us * data["S"]).astype(np.int64), 0, ids.shape[1] - 1)
    ii = np.clip((vs * data["S"]).astype(np.int64), 0, ids.shape[0] - 1)
    g = ids[ii[:, None], jj[None, :]].astype(np.int64)
    out = ((us < 0) | (us >= data["W"]))[None, :] | ((vs < 0) | (vs >= data["H"]))[:, None]
    g[out] = 255
    lut = np.zeros((256, 3), np.float32)
    lut[:] = PAGE
    city = np.zeros(256, bool)
    for r in data["regions"]:
        n = r["name"]
        if r["side"] == 0:
            c = MISSILE if n in MISSILE_REGIONS else AIR if n in AIR_REGIONS else OUR_LAND
        else:
            c = STRUCK.get(n, ENEMY_LAND)
        lut[r["id"]] = c
        city[r["id"]] = r["city"]
    img = lut[g] / 255
    # Borders: faint between regions, darker on the outline of the land.
    edge = np.zeros((h, w), np.float32)
    coast = np.zeros((h, w), np.float32)
    for dy, dx in ((0, 1), (1, 0)):
        a, b = g[: h - dy, : w - dx], g[dy:, dx:]
        diff = (a != b)
        land = (a != 255) & (b != 255)
        inner = diff & land & ~city[np.where(a == 255, 0, a)] & ~city[np.where(b == 255, 0, b)]
        edge[: h - dy, : w - dx] = np.maximum(edge[: h - dy, : w - dx], inner)
        coast[: h - dy, : w - dx] = np.maximum(coast[: h - dy, : w - dx], diff & ~land)
    e = np.clip(blur(edge, 0.6 * K / 2) * 2.2, 0, 1)[..., None]
    c = np.clip(blur(coast, 0.8 * K / 2) * 2.2, 0, 1)[..., None]
    img = img * (1 - 0.32 * e) + np.array(PAGE, np.float32) / 255 * 0.32 * e
    img = img * (1 - 0.5 * c)
    return img, data


def labels(d, data):
    show = {"Zorianska", "Dubivska", "Lukivska", "Stepova", "Kolmar",
            "Zhorovsk", "Kurgal", "Strelov", "Bilohirska", "Tamsk", "Brekhov"}
    f = font(int(10.5 * K), "SemiBold")
    fc = font(int(12.5 * K), "Bold")
    for r in data["regions"]:
        n = r["name"]
        if n == "Verbohrad":
            x, y = px(279, 325)
            d.text((x + 1.2 * K, y + 1.2 * K), n, font=fc, fill=(0, 0, 0, 120), anchor="mm")
            d.text((x, y), n, font=fc, fill=TEXT + (255,), anchor="mm")
        elif n in show:
            x, y = px(*r["label"])
            d.text((x + K, y + K), n, font=f, fill=(0, 0, 0, 90), anchor="mm")
            d.text((x, y), n, font=f, fill=TEXT + (215,), anchor="mm")


def shape(pts, x, y, s, ang=0.0):
    c, sn = math.cos(ang), math.sin(ang)
    return [(x + (a * c - b * sn) * s, y + (a * sn + b * c) * s) for a, b in pts]


def badge(d, kind, side, u, v):
    """A site as the game draws it: a dark disc, a ring in the side's colour, a white glyph."""
    x, y = px(u, v)
    ring = OURS if side == 0 else ENEMY
    r = (10.5 if kind == 0 else 8.2) * K
    d.ellipse([x - r - 1.5 * K, y - r - 1.5 * K, x + r + 1.5 * K, y + r + 1.5 * K], fill=(0, 0, 0, 70))
    d.ellipse([x - r, y - r, x + r, y + r], fill=(26, 34, 50, 255), outline=ring + (255,), width=int(1.8 * K))
    s = r / 8.6
    white = (245, 247, 250, 255)
    if kind == 0:
        d.polygon(shape(STAR, x, y, s * 1.15), fill=white)
    elif kind == 1:
        d.polygon(shape(FACTORY, x, y, s), fill=white)
    elif kind == 3:
        d.polygon(shape(SAM, x, y, s), fill=white)
    else:
        hub = (x, y + 1.6 * s)
        for sx in (-2.6, 2.6):
            d.line([hub, (x + sx * s, y - 4.2 * s)], fill=white, width=max(1, int(1.3 * s)))
        d.ellipse([hub[0] - 2.6 * s, hub[1] - 2.6 * s, hub[0] + 2.6 * s, hub[1] + 2.6 * s], fill=white)


# --- light ------------------------------------------------------------------------------

class Light:
    """Additive light, kept as one grey mask per colour, glowing when added up."""

    def __init__(self):
        self.masks = {}

    def draw(self, colour):
        if colour not in self.masks:
            self.masks[colour] = Image.new("L", (W * K, H * K))
        return ImageDraw.Draw(self.masks[colour])

    def add(self, img, glow=1.0):
        E = np.zeros_like(img)
        for colour, m in self.masks.items():
            E += (np.asarray(m, np.float32) / 255)[..., None] * np.asarray(colour, np.float32)
        out = img + E
        for sigma, k in ((1.5 * K, 0.7), (5 * K, 0.45), (14 * K, 0.25)):
            out += blur(E, sigma) * k * glow
        self.masks = {}
        return out


def trail(draw, pts, width, dotted=False, power=1.6, start=0.0):
    """A fading line along pts (in the big drawing), brightest at the end."""
    n = len(pts)
    for i in range(n - 1):
        t = i / (n - 1)
        if t < start:
            continue
        a = ((t - start) / (1 - start)) ** power
        if dotted and i % 3 != 0:
            continue
        if dotted:
            x, y = pts[i]
            r = width * (0.6 + 0.4 * a)
            draw.ellipse([x - r, y - r, x + r, y + r], fill=int(255 * (0.15 + 0.85 * a)))
        else:
            draw.line([tuple(pts[i]), tuple(pts[i + 1])], fill=int(255 * (0.08 + 0.92 * a)),
                      width=max(1, int(round(width * (0.5 + 0.5 * a)))))


def dot(draw, x, y, r, v=255):
    draw.ellipse([x - r, y - r, x + r, y + r], fill=v)


def burst(light, x, y, size, rng, sparks=7):
    """An interception: a white flash in an orange fireball, a thin ring going out, a few
    burning pieces thrown off."""
    dot(light.draw((1.0, 0.45, 0.12)), x, y, size * 0.75, 190)
    dot(light.draw((0.3, 0.1, 0.03)), x, y, size * 1.6, 120)
    dot(light.draw((1.7, 1.55, 1.4)), x, y, size * 0.3)
    dr = light.draw((0.9, 0.75, 0.6))
    r = size * 1.3
    dr.ellipse([x - r, y - r, x + r, y + r], outline=90, width=max(1, int(0.7 * K)))
    ds = light.draw((1.3, 0.75, 0.35))
    for _ in range(sparks):
        a = rng.uniform(0, math.tau)
        d0 = size * rng.uniform(0.9, 1.6)
        sx, sy = x + math.cos(a) * d0, y + math.sin(a) * d0 + size * 0.3
        dot(ds, sx, sy, 0.8 * K, int(rng.uniform(150, 255)))


def smoke(img, x, y, wind, length, size, strength=0.42):
    """A thin plume blowing downwind, greyish, thinning out."""
    h, w = img.shape[:2]
    sm = np.zeros((h, w), np.float32)
    for k in range(22):
        t = k / 21
        cx = x + wind[0] * t * length + math.sin(t * 5) * size * 0.25
        cy = y + wind[1] * t * length
        r = size * (0.35 + 1.1 * t)
        x0, x1 = int(max(0, cx - 3 * r)), int(min(w, cx + 3 * r))
        y0, y1 = int(max(0, cy - 3 * r)), int(min(h, cy + 3 * r))
        if x1 <= x0 or y1 <= y0:
            continue
        gx = np.exp(-((np.arange(x0, x1) - cx) ** 2) / (2 * r * r))
        gy = np.exp(-((np.arange(y0, y1) - cy) ** 2) / (2 * r * r))
        sm[y0:y1, x0:x1] += np.outer(gy, gx) * (1 - t) ** 1.3 * 0.5
    sm = (np.clip(sm, 0, 1) * strength)[..., None]
    return img * (1 - sm) + np.array([0.12, 0.11, 0.11], np.float32) * sm


# --- the raid -----------------------------------------------------------------------------

def raid(img, data, rng):
    w, h = W * K, H * K
    sites = data["sites"]
    S_ = {(round(s["pos"][0]), round(s["pos"][1])): s for s in sites}

    def site(u, v):
        return tuple(S_[(u, v)]["pos"])

    cap = site(302, 296)
    sam_a, sam_b, sam_c, sam_d = site(322, 300), site(339, 318), site(366, 349), site(375, 249)
    gun = site(311, 229)
    fac_n, fac_ne, fac_e, fac_s = site(325, 235), site(354, 256), site(352, 308), site(333, 351)
    their_fac, their_fac2 = site(731, 300), site(770, 341)
    their_cap = tuple(data["capitals"][1])

    # Under the action: faint SAM ranges round the capital, as the game draws them.
    over = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    for s in (sam_a, sam_d):
        x, y = px(*s)
        r = 62 * S * K
        d.ellipse([x - r, y - r, x + r, y + r], fill=OURS + (10,), outline=OURS + (55,), width=int(0.8 * K))
    labels(d, data)
    for s in sites:
        badge(d, s["kind"], s["side"], *s["pos"])
    a = np.asarray(over, np.float32) / 255
    img = img * (1 - a[..., 3:]) + a[..., :3] * a[..., 3:]

    # Our factory south of the capital, hit: a thin plume blowing south-west.
    fx, fy = px(*fac_s)
    img = smoke(img, fx, fy, (-0.8, 0.6), 46 * K, 6 * K)

    light = Light()
    red = (1.0, 0.36, 0.28)
    orange = (1.2, 0.62, 0.25)
    blue = (0.4, 0.75, 1.4)
    craft = []   # (glyph, x, y, angle, colour, scale): drawn crisp over the light

    def head(pts):
        (x0, y0), (x1, y1) = pts[-2], pts[-1]
        return x1, y1, math.atan2(y1 - y0, x1 - x0)

    # Drones: over the front in loose streams, each on its own gentle curve.
    drones = [((640, 176), (560, 150), fac_ne, 0.55), ((655, 232), (560, 250), fac_n, 0.5),
              ((662, 430), (565, 440), fac_e, 0.5), ((635, 372), (540, 350), cap, 0.58),
              ((680, 300), (600, 275), sam_c, 0.42)]
    for a_, c_, b_, t in drones:
        P = [px(*p) for p in quad(a_, c_, b_, np.linspace(0, t, 120))]
        trail(light.draw(red), P, 1.25 * K, dotted=True, power=1.3)
        x, y, ang = head(P)
        craft.append((DRONE, x, y, ang, ENEMY, 1.25))
    # One the AA gun north of the capital has just got: a burst of tracer and a small blast.
    route = ((600, 150), (470, 150), fac_n)
    P = [px(*p) for p in quad(*route, np.linspace(0, 0.8, 100))]
    trail(light.draw(red), P, 1.25 * K, dotted=True, power=1.3)
    kx, ky = P[-1]
    gx, gy = px(*gun)
    dt = light.draw((1.4, 0.95, 0.4))
    for k in range(8):
        t0 = 0.14 + k * 0.105
        p0, p1 = lerp((gx, gy), (kx, ky), t0), lerp((gx, gy), (kx, ky), min(0.97, t0 + 0.05))
        dt.line([p0, p1], fill=235, width=int(1.1 * K))
    burst(light, kx, ky, 6 * K, rng, sparks=5)

    # Cruise missiles: long, gently weaving routes, low and fast.
    P = [px(*p) for p in cubic((700, 262), (610, 300), (520, 190), cap, np.linspace(0, 0.8, 200))]
    trail(light.draw(orange), P, 1.4 * K, power=2.2)
    x, y, ang = head(P)
    craft.append((CRUISE, x, y, ang, ENEMY, 1.3))
    P = [px(*p) for p in cubic((700, 470), (600, 470), (520, 330), fac_e, np.linspace(0, 0.62, 200))]
    trail(light.draw(orange), P, 1.4 * K, power=2.2)
    x, y, _ = head(P)
    # ...this one met by the SAM south-east of the capital.
    sx, sy = px(*sam_c)
    I = quad((sx, sy), (sx + 30 * K, sy - 6 * K), (x, y), np.linspace(0, 1, 60))
    trail(light.draw(blue), I, 1.5 * K, power=1.1)
    burst(light, x, y, 8 * K, rng)

    # Ballistic missiles from deep in their land, on high arcs (drawn lifted toward the top).
    def arc(a_, b_, lift, t):
        ts = np.linspace(0, t, 160)
        return [(gx_ - 0.0, gy_ - lift * S * K * 4 * tt * (1 - tt))
                for (gx_, gy_), tt in zip([px(*lerp(a_, b_, tt)) for tt in ts], ts)]

    A = arc(their_cap, cap, 120, 0.7)
    trail(light.draw(orange), A, 1.8 * K, power=2.8)
    hx, hy = A[-1]
    for s, bend in ((sam_a, -60), (sam_b, -40)):
        sx, sy = px(*s)
        I = quad((sx, sy), (sx + 10 * K, sy + bend * K), (hx, hy), np.linspace(0, 1, 60))
        trail(light.draw(blue), I, 1.5 * K, power=1.1)
    burst(light, hx, hy, 12 * K, rng, sparks=9)

    A = arc((980, 330), fac_e, 70, 0.45)
    trail(light.draw(orange), A, 1.8 * K, power=2.8)
    hx, hy = A[-1]
    dot(light.draw((1.7, 1.6, 1.5)), hx, hy, 2.4 * K)
    dot(light.draw((1.0, 0.5, 0.15)), hx, hy, 5 * K, 150)

    # Our strike back: a cruise missile has just hit their factory; a drone is on its way
    # to another.
    P = [px(*p) for p in cubic(fac_e, (470, 290), (600, 250), their_fac, np.linspace(0, 1, 220))]
    trail(light.draw(blue), P, 1.2 * K, power=2.6, start=0.45)
    fx2, fy2 = px(*their_fac)
    burst(light, fx2, fy2, 13 * K, rng, sparks=9)
    P = [px(*p) for p in quad(fac_s, (560, 420), their_fac2, np.linspace(0, 0.78, 140))]
    trail(light.draw(blue), P, 1.2 * K, dotted=True, power=1.3, start=0.35)
    x, y, ang = head(P)
    craft.append((DRONE, x, y, ang, OURS, 1.2))

    # The fire under our factory's smoke.
    fl = light.draw((1.3, 0.55, 0.15))
    for _ in range(12):
        dot(fl, fx + rng.uniform(-6, 6) * K, fy + rng.uniform(-5, 4) * K, rng.uniform(1.4, 3.2) * K,
            int(rng.uniform(140, 255)))
    dot(light.draw((1.6, 1.2, 0.7)), fx, fy - K, 2.6 * K)
    img = light.add(img)

    # The craft, crisp on top.
    over = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    for glyph, x, y, ang, col, s in craft:
        d.polygon(shape(glyph, x, y, s * K, ang), fill=col + (255,), outline=(10, 12, 16, 255), width=int(0.9 * K))
    a = np.asarray(over, np.float32) / 255
    return img * (1 - a[..., 3:]) + a[..., :3] * a[..., 3:]


# --- the left side ------------------------------------------------------------------------

def finish(img):
    w, h = img.shape[1], img.shape[0]
    xs = np.arange(w, dtype=np.float32) / w
    # The page colour over the left, fading out across the middle.
    a = np.where(xs < 0.34, 1.0, np.clip(1 - (xs - 0.34) / 0.34, 0, 1)) ** 0.9 * 0.94
    img = img * (1 - a)[None, :, None] + np.array(PAGE, np.float32) / 255 * a[None, :, None]
    yy = np.arange(h, dtype=np.float32)[:, None] / h
    v = 1 - 0.35 * ((yy - 0.5) / 0.6) ** 2 - 0.25 * ((xs[None, :] - 0.75) / 0.6) ** 2
    img = img * np.clip(v, 0.6, 1)[..., None]
    # A red glow behind the emblem.
    ex, ey = 70 * K, h / 2 - 9 * K
    r2 = ((np.arange(w)[None, :] - ex) ** 2 + (np.arange(h)[:, None] - ey) ** 2) / (60 * K) ** 2
    img = img + np.array([0.22, 0.05, 0.03], np.float32) * np.exp(-r2)[..., None]
    out = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).convert("RGBA")
    lg = Image.open(LOGO).convert("RGBA")
    lw = 400 * K
    lg = lg.resize((lw, round(lg.height * lw / lg.width)), Image.LANCZOS)
    top = (h - lg.height - 22 * K) // 2
    out.alpha_composite(lg, (26 * K, top))
    d = ImageDraw.Draw(out)
    f = font(int(11.5 * K), "Bold")
    text = "HOLD THE SKY  ·  STRIKE BACK"
    x = 26 * K + lg.height * (1 + 0.16) + 2 * K     # under the name, past the emblem
    y = top + lg.height + 3 * K
    for ch in text:
        d.text((x, y), ch, font=f, fill=YELLOW + (255,))
        x += f.getlength(ch) + 3.2 * K
    return out.convert("RGB")


def main():
    geo, out = sys.argv[1], sys.argv[2]
    img, data = base_map(geo)
    img = raid(img, data, np.random.default_rng(3))
    big = finish(img)
    big.resize((W * 2, H * 2), Image.LANCZOS).save(os.path.join(out, "banner-v2@2x.png"))
    big.resize((W, H), Image.LANCZOS).save(os.path.join(out, "banner-v2.png"))
    print("wrote", out)


if __name__ == "__main__":
    main()
